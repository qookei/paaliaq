from amaranth import *
from amaranth.lib import wiring, io, memory
from amaranth.lib.fifo import AsyncFIFOBuffered
from amaranth.lib.wiring import In, Out
from amaranth_soc import csr, wishbone
from amaranth_soc.memory import MemoryMap

from dataclasses import dataclass, field

from paaliaq.hdmi import VideoSequencer, HDMIEncoder, DMT_MODE_1024x768_60Hz
from paaliaq.pll import S7MMCM

from paaliaq.font import get_font_data


def gen_color_palette():
    out = [0] * 256

    # Colors [0, 16) are the classical 16 color palette
    for i in range(0, 16):
        if i > 8:
            level = 255
        elif i == 7:
            level = 229
        else:
            level = 205

        r = 127 if i == 8 else level if (i & 1) != 0 else 92 if i == 12 else 0
        g = 127 if i == 8 else level if (i & 2) != 0 else 92 if i == 12 else 0
        b = 127 if i == 8 else 238 if i == 4 else level if (i & 4) != 0 else 0

        out[i] = (r << 16) | (g << 8) | b

    # Colors [16, 232) are a 6x6x6 color cube
    for i in range(16, 232):
        xyz = i - 16
        x, yz = xyz // 36, xyz % 36
        y, z = yz // 6, yz % 6

        r = x * 40 + 55 if x != 0 else 0
        g = y * 40 + 55 if y != 0 else 0
        b = z * 40 + 55 if z != 0 else 0

        out[i] = (r << 16) | (g << 8) | b

    # Colors [232, 256) are grayscale ramp
    for i in range(232, 256):
        level = i - 232
        r = g = b = level * 10 + 8

        out[i] = (r << 16) | (g << 8) | b

    return out


class TextFramebuffer(wiring.Component):
    wb_bus: In(wishbone.Signature(addr_width=15, data_width=8))
    csr_bus: wiring.In(csr.Signature(addr_width=4, data_width=8))

    class CursorRegister(csr.Register, access="rw"):
        x: csr.Field(csr.action.RW, 16)
        y: csr.Field(csr.action.RW, 16)


    def __init__(self):
        super().__init__()

        regs = csr.Builder(addr_width=4, data_width=8)
        self._cursor = regs.add("Cursor", self.CursorRegister())
        mmap = regs.as_memory_map()
        self._bridge = csr.Bridge(mmap)
        self.csr_bus.memory_map = mmap

        self.wb_bus.memory_map = MemoryMap(addr_width=15, data_width=8)
        self.wb_bus.memory_map.add_resource(self, name=("text",), size=128*48*4)
        self.wb_bus.memory_map.freeze()

    def elaborate(self, platform):
        m = Module()

        m.submodules.bridge = self._bridge
        wiring.connect(m, wiring.flipped(self.csr_bus), self._bridge.bus)

        # ---
        # Signal generation logic

        mode = DMT_MODE_1024x768_60Hz

        m.submodules.enc = enc = HDMIEncoder()
        m.submodules.seq = seq = DomainRenamer("pixel")(VideoSequencer(mode, pipeline_depth=3))

        m.d.comb += [
            enc.h_sync.eq(seq.h_sync),
            enc.v_sync.eq(seq.v_sync),
            enc.active.eq(seq.active),
        ]

        # ---
        # Pixel generation logic

        m.submodules.font = font = memory.Memory(
            shape=unsigned(8),
            depth=256 * 16,
            init=get_font_data(),
        )

        m.submodules.text = text = memory.Memory(
            shape=unsigned(32),
            depth=128*48,
            init=[],
        )

        def delayed(sig, by):
            x = sig
            for i in range(by):
                y = Signal.like(sig)
                m.d.pixel += y.eq(x)
                x = y

            return x

        cursor_x = Signal(range(128))
        cursor_y = Signal(range(48))

        cursor_blink = Signal(range(64))
        with m.If(seq.v_start):
            m.d.pixel += cursor_blink.eq(cursor_blink + 1)

        font_rd = font.read_port(domain="pixel")
        text_rd = text.read_port(domain="pixel")

        m.d.comb += text_rd.addr.eq((seq.h_pos >> 3) + (seq.v_pos >> 4) * 128)

        char, fg, bg = Signal(8), Signal(8), Signal(8)
        m.d.comb += Cat(char, fg, bg).eq(text_rd.data)

        m.d.comb += font_rd.addr.eq(char * 16 + (seq.v_pos & 15))

        colors = Array(gen_color_palette())

        cell_x = delayed(seq.h_pos, 2)
        font_bit = font_rd.data[::-1].bit_select(cell_x & 7, 1)
        in_cursor_cell = ((cell_x >> 3) == cursor_x) & ((seq.v_pos >> 4) == cursor_y)
        in_cursor_line = in_cursor_cell & ((seq.v_pos & 0b1110) == 0b1110) & ((cursor_blink >> 4) & 1)
        bit = in_cursor_line | font_bit

        m.d.pixel += Cat(enc.blue, enc.green, enc.red).eq(
            colors[Mux(bit, delayed(fg, 1), delayed(bg, 1))]
        )

        # ---
        # Wishbone text buffer access

        text_bus_rd = text.read_port()
        text_wr = text.write_port(granularity=8)
        m.d.comb += [
            text_bus_rd.addr.eq(self.wb_bus.adr >> 2),
            text_wr.addr.eq(self.wb_bus.adr >> 2),
            text_wr.data.eq(self.wb_bus.dat_w.replicate(4)),
            self.wb_bus.dat_r.eq(text_bus_rd.data.word_select(self.wb_bus.adr & 3, 8)),
        ]

        with m.If(self.wb_bus.ack):
            m.d.sync += self.wb_bus.ack.eq(0)
        with m.Elif(self.wb_bus.cyc & self.wb_bus.stb):
            m.d.comb += text_wr.en.eq(Mux(self.wb_bus.we, 1 << (self.wb_bus.adr & 3), 0))
            m.d.comb += text_bus_rd.en.eq(~self.wb_bus.we)
            m.d.sync += self.wb_bus.ack.eq(1)

        # ---
        # Cursor register CDC

        m.submodules.cursor_cdc_fifo = cursor_cdc_fifo = AsyncFIFOBuffered(
            width=13,
            depth=4,
            w_domain="sync",
            r_domain="pixel")

        stb = self._cursor.f.x.port.w_stb | self._cursor.f.y.port.w_stb

        m.d.comb += [
            cursor_cdc_fifo.w_data.eq(
                Cat(
                    self._cursor.f.x.data.bit_select(0, 7),
                    self._cursor.f.y.data.bit_select(0, 6)
                )
            ),
            cursor_cdc_fifo.w_en.eq(stb),
        ]

        with m.If(cursor_cdc_fifo.r_rdy & ~cursor_cdc_fifo.r_en):
            m.d.pixel += [
                Cat(cursor_x, cursor_y).eq(cursor_cdc_fifo.r_data),
                cursor_cdc_fifo.r_en.eq(1),
            ]
        with m.Else():
            m.d.pixel += cursor_cdc_fifo.r_en.eq(0)

        return m
