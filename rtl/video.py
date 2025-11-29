from amaranth import *
from amaranth.lib import wiring, io, memory
from amaranth.lib.fifo import AsyncFIFOBuffered
from amaranth.lib.wiring import In, Out
from amaranth_soc import csr, wishbone
from amaranth_soc.memory import MemoryMap

from dataclasses import dataclass, field

from hdmi import VideoSequencer, HDMIEncoder, DMT_MODE_1024x768_60Hz
from pll import ECP5PLL

from font import get_font_data


class TextFramebuffer(wiring.Component):
    wb_bus: In(wishbone.Signature(addr_width=14, data_width=8))
    csr_bus: wiring.In(csr.Signature(addr_width=4, data_width=8))

    class CursorRegister(csr.Register, access="rw"):
        x: csr.Field(csr.action.RW, 16)
        y: csr.Field(csr.action.RW, 16)


    def __init__(self, in_clk, in_freq):
        super().__init__()
        self._in_clk = in_clk
        self._in_freq = in_freq

        regs = csr.Builder(addr_width=4, data_width=8)
        self._cursor = regs.add("Cursor", self.CursorRegister())
        mmap = regs.as_memory_map()
        self._bridge = csr.Bridge(mmap)
        self.csr_bus.memory_map = mmap

        self.wb_bus.memory_map = MemoryMap(addr_width=14, data_width=8)
        self.wb_bus.memory_map.add_resource(self, name=("text",), size=128*48*2)
        self.wb_bus.memory_map.freeze()

    def elaborate(self, platform):
        m = Module()

        m.submodules.bridge = self._bridge
        wiring.connect(m, wiring.flipped(self.csr_bus), self._bridge.bus)

        # ---
        # Signal generation logic

        mode = DMT_MODE_1024x768_60Hz

        m.domains.tmds = cd_tmds = ClockDomain("tmds")
        m.domains.pixel = cd_pixel = ClockDomain("pixel")

        m.submodules.pll = pll = ECP5PLL()
        pll.add_input(clk=self._in_clk, freq=self._in_freq)
        pll.add_primary_output(domain="tmds", freq=mode.pixel_clock * 5)
        pll.add_secondary_output(domain="pixel", freq=mode.pixel_clock)

        m.submodules.enc = enc = HDMIEncoder()
        m.submodules.seq = seq = DomainRenamer("pixel")(VideoSequencer(mode, pipeline_depth=2))

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
            shape=unsigned(16),
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

        char, fg, bg = Signal(8), Signal(4), Signal(4)
        m.d.comb += Cat(char, fg, bg).eq(text_rd.data)

        m.d.comb += font_rd.addr.eq(char * 16 + (seq.v_pos & 15))

        colors = Array([
            0x232627,
            0xed1515,
            0x11d116,
            0xf67400,
            0x1d99f3,
            0x9b59b6,
            0x1abc9c,
            0xfcfcfc,
            0x7f8c8d,
            0xc0392b,
            0x1cdc9a,
            0xfdbc4b,
            0x3daee9,
            0x8e44ad,
            0x16a085,
            0xffffff,
        ])

        cell_x = delayed(seq.h_pos, 2)
        font_bit = font_rd.data[::-1].bit_select(cell_x & 7, 1)
        in_cursor_cell = ((cell_x >> 3) == cursor_x) & ((seq.v_pos >> 4) == cursor_y)
        in_cursor_line = in_cursor_cell & ((seq.v_pos & 0b1110) == 0b1110) & ((cursor_blink >> 4) & 1)
        bit = in_cursor_line | font_bit

        m.d.comb += Cat(enc.blue, enc.green, enc.red).eq(
            colors[Mux(bit, delayed(fg, 1), delayed(bg, 1))]
        )

        # ---
        # Wishbone text buffer access

        text_bus_rd = text.read_port()
        text_wr = text.write_port(granularity=8)
        m.d.comb += [
            text_bus_rd.addr.eq(self.wb_bus.adr >> 1),
            text_wr.addr.eq(self.wb_bus.adr >> 1),
            text_wr.data.eq(self.wb_bus.dat_w.replicate(2)),
            self.wb_bus.dat_r.eq(text_bus_rd.data.word_select(self.wb_bus.adr & 1, 8)),
        ]

        with m.If(self.wb_bus.ack):
            m.d.sync += self.wb_bus.ack.eq(0)
        with m.Elif(self.wb_bus.cyc & self.wb_bus.stb):
            m.d.comb += text_wr.en.eq(Mux(self.wb_bus.we, 1 << (self.wb_bus.adr & 1), 0))
            m.d.comb += text_bus_rd.en.eq(~self.wb_bus.we)
            m.d.sync += self.wb_bus.ack.eq(1)

        # ---
        # Cursor register CDC

        m.submodules.cursor_cdc_fifo = cursor_cdc_fifo = AsyncFIFOBuffered(
            width=16,
            depth=8,
            w_domain="sync",
            r_domain="pixel")

        stb = self._cursor.f.x.port.w_stb | self._cursor.f.y.port.w_stb

        m.d.comb += [
            cursor_cdc_fifo.w_data.eq(Cat(self._cursor.f.x.data, self._cursor.f.y.data)),
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
