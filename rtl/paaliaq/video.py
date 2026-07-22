from amaranth import *
from amaranth.lib import wiring, io, memory, data, enum, stream
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


class Opcode(enum.Enum, shape=4):
    # Put a character at the current cursor position and advance.
    # Also handles characters such as \t, \b, \n, \r etc.
    PUT_CHAR    = 0
    # Set the foreground color for the next characters.
    SET_FG      = 1
    # Set the background color for the next characters.
    SET_BG      = 2
    # Set the attribute flags for the next characters.
    SET_ATTR    = 3
    # Scroll the display in the specified direction by the specified amount of lines.
    # Also moves the cursor by that amount.
    SCROLL      = 4
    # Move the cursor to the specified absolute position.
    MOVE_CURSOR_ABS = 6
    # Move the cursor by the specified relative amounts.
    # May optionally reset the other coordinate.
    MOVE_CURSOR_REL = 7
    # Erase a part of the line before and/or after the cursor.
    ERASE_LINE = 8
    # Erase a part of the display before and/or after the cursor.
    ERASE_DISPLAY = 9
    # Clears the display and resets the cursor position, current color and attributes.
    RESET = 10


class Attributes(enum.Flag, shape=8):
    INVERT = 1


class Command(data.Struct):
    class Params(data.Union):
        char: unsigned(8)
        attr: Attributes
        color: unsigned(8)
        abs_pos: data.StructLayout({
            "x": unsigned(7),
            "y": unsigned(6),
        })
        rel_pos: data.StructLayout({
            "x_axis": unsigned(1),
            "delta": signed(8),
        })
        erase: data.StructLayout({
            "before": unsigned(1),
            "after": unsigned(1),
        })

    opcode: Opcode
    params: Params


class CharacterCell(data.Struct):
    char: unsigned(8)
    fg: unsigned(8)
    bg: unsigned(8)
    attr: Attributes


def saturate(v, maxv):
    return Mux(v < 0, 0, Mux(v > maxv, maxv, v))


class TextCommandProcessor(wiring.Component):
    commands: In(stream.Signature(Command))
    fb_read: In(memory.ReadPort.Signature(addr_width=13, shape=CharacterCell))
    fb_write: In(memory.WritePort.Signature(addr_width=13, shape=CharacterCell))
    cursor_x: Out(7)
    cursor_y: Out(6)

    def elaborate(self, platform):
        m = Module()

        cursor_x, cursor_y = Signal(7), Signal(6)
        cursor_addr = cursor_y * 128 + cursor_x

        m.d.comb += self.cursor_x.eq(cursor_x)
        m.d.comb += self.cursor_y.eq(cursor_y)

        cur_fg, cur_bg, cur_attr = Signal(8, init=15), Signal(8), Signal(Attributes)

        mem_addr = Signal(13)

        m.d.comb += self.fb_read.addr.eq(mem_addr)
        m.d.comb += self.fb_write.addr.eq(mem_addr)

        m.d.comb += self.fb_write.data.fg.eq(cur_fg)
        m.d.comb += self.fb_write.data.bg.eq(cur_bg)
        m.d.comb += self.fb_write.data.attr.eq(cur_attr)

        erase_cur, erase_goal = Signal(13), Signal(13)
        scroll_src, scroll_dst, scroll_fwd, scroll_ctr = Signal(signed(15)), Signal(signed(15)), Signal(), Signal(13)
        scroll_blank = Signal()

        cur_command = Signal(Command)
        with m.FSM():
            with m.State("idle"):
                with m.If(self.commands.valid):
                    m.d.comb += self.commands.ready.eq(1)
                    m.d.sync += cur_command.eq(self.commands.payload)
                    with m.Switch(self.commands.payload.opcode):
                        with m.Case(Opcode.PUT_CHAR):
                            m.next = "handle-PUT_CHAR"
                        with m.Case(Opcode.SET_FG):
                            m.next = "handle-SET_FG"
                        with m.Case(Opcode.SET_BG):
                            m.next = "handle-SET_BG"
                        with m.Case(Opcode.SET_ATTR):
                            m.next = "handle-SET_ATTR"
                        with m.Case(Opcode.SCROLL):
                            m.next = "handle-SCROLL"
                        with m.Case(Opcode.MOVE_CURSOR_ABS):
                            m.next = "handle-MOVE_CURSOR_ABS"
                        with m.Case(Opcode.MOVE_CURSOR_REL):
                            m.next = "handle-MOVE_CURSOR_REL"
                        with m.Case(Opcode.ERASE_LINE):
                            m.next = "handle-ERASE_LINE"
                        with m.Case(Opcode.ERASE_DISPLAY):
                            m.next = "handle-ERASE_DISPLAY"
                        with m.Case(Opcode.RESET):
                            m.next = "handle-RESET"

            with m.State("handle-PUT_CHAR"):
                with m.Switch(cur_command.params.char):
                    m.next = "idle"
                    with m.Case(ord("\r")):
                        m.d.sync += cursor_x.eq(0)
                    with m.Case(ord("\n")):
                        with m.If(cursor_y == 47):
                            m.d.sync += scroll_src.eq(128)
                            m.d.sync += scroll_dst.eq(0)
                            m.d.sync += scroll_ctr.eq(128 * 48)
                            m.d.sync += scroll_fwd.eq(1)
                            m.next = "do-scroll-read"
                        with m.Else():
                            m.d.sync += cursor_y.eq(cursor_y + 1)
                    with m.Case(ord("\t")):
                        m.d.sync += cursor_x.eq(saturate(cursor_x + 8 - (cursor_x & 7), 127))
                    with m.Case(ord("\b")):
                        with m.If(cursor_x == 0):
                            with m.If(cursor_y > 0):
                                m.d.sync += cursor_x.eq(127)
                                m.d.sync += cursor_y.eq(cursor_y - 1)
                            with m.Else():
                                pass
                        with m.Else():
                            m.d.sync += cursor_x.eq(cursor_x - 1)
                    with m.Default():
                        m.d.comb += self.fb_write.en.eq(1)
                        m.d.comb += mem_addr.eq(cursor_addr)
                        m.d.comb += self.fb_write.data.char.eq(cur_command.params.char)

                        # TODO: There is an unhandled edge case here:
                        # When the last cell of the line is empty, writing a character will keep the
                        # cursor on it, and only advance on the next character.
                        with m.If(cursor_x == 127):
                            with m.If(cursor_y == 47):
                                m.d.sync += cursor_x.eq(0)
                                m.d.sync += scroll_src.eq(128)
                                m.d.sync += scroll_dst.eq(0)
                                m.d.sync += scroll_ctr.eq(128 * 48)
                                m.d.sync += scroll_fwd.eq(1)
                                m.next = "do-scroll-read"
                            with m.Else():
                                m.d.sync += cursor_x.eq(0)
                                m.d.sync += cursor_y.eq(cursor_y + 1)
                        with m.Else():
                            m.d.sync += cursor_x.eq(cursor_x + 1)
            with m.State("handle-SET_FG"):
                m.d.sync += cur_fg.eq(cur_command.params.color)
                m.next = "idle"
            with m.State("handle-SET_BG"):
                m.d.sync += cur_bg.eq(cur_command.params.color)
                m.next = "idle"
            with m.State("handle-SET_ATTR"):
                m.d.sync += cur_attr.eq(cur_command.params.attr)
                m.next = "idle"
            with m.State("handle-SCROLL"):
                m.d.sync += cursor_y.eq(saturate(cursor_y + cur_command.params.rel_pos.delta, 47))
                with m.If(cur_command.params.rel_pos.delta > 0):
                    m.d.sync += scroll_src.eq(128 * cur_command.params.rel_pos.delta)
                    m.d.sync += scroll_dst.eq(0)
                    m.d.sync += scroll_ctr.eq(128 * 48)
                    m.d.sync += scroll_fwd.eq(1)
                    m.next = "do-scroll-read"
                with m.Elif(cur_command.params.rel_pos.delta < 0):
                    m.d.sync += scroll_src.eq(128 * 48 - 1)
                    m.d.sync += scroll_dst.eq(128 * 48 - 1 + (-cur_command.params.rel_pos.delta) * 128)
                    m.d.sync += scroll_ctr.eq(128 * 48)
                    m.d.sync += scroll_fwd.eq(0)
                    m.next = "do-scroll-read"
                with m.Else():
                    m.next = "idle"
            with m.State("handle-MOVE_CURSOR_ABS"):
                m.d.sync += cursor_x.eq(cur_command.params.abs_pos.x)
                m.d.sync += cursor_y.eq(cur_command.params.abs_pos.y)
                m.next = "idle"
            with m.State("handle-MOVE_CURSOR_REL"):
                with m.If(cur_command.params.rel_pos.x_axis):
                    m.d.sync += cursor_x.eq(saturate(cursor_x + cur_command.params.rel_pos.delta, 127))
                with m.Else():
                    m.d.sync += cursor_y.eq(saturate(cursor_y + cur_command.params.rel_pos.delta, 47))
                m.next = "idle"
            with m.State("handle-ERASE_LINE"):
                line_start = cursor_y * 128
                line_end = line_start + 127

                m.d.sync += erase_cur.eq(Mux(cur_command.params.erase.before, line_start, cursor_addr))
                m.d.sync += erase_goal.eq(Mux(cur_command.params.erase.after, line_end, cursor_addr))
                m.next = "do-erase"
            with m.State("handle-ERASE_DISPLAY"):
                disp_start = 0
                disp_end = 128 * 48 - 1

                m.d.sync += erase_cur.eq(Mux(cur_command.params.erase.before, line_start, cursor_addr))
                m.d.sync += erase_goal.eq(Mux(cur_command.params.erase.after, line_end, cursor_addr))
                m.next = "do-erase"
            with m.State("handle-RESET"):
                m.d.sync += cursor_x.eq(0)
                m.d.sync += cursor_y.eq(0)
                m.d.sync += cur_fg.eq(15)
                m.d.sync += cur_bg.eq(0)
                m.d.sync += cur_attr.eq(0)
                m.d.sync += erase_cur.eq(0)
                m.d.sync += erase_goal.eq(128 * 48 - 1)
                m.next = "do-erase"
            with m.State("do-erase"):
                with m.If(erase_cur == erase_goal):
                    m.next = "idle"
                m.d.sync += erase_cur.eq(erase_cur + 1)
                m.d.comb += self.fb_write.en.eq(1)
                m.d.comb += mem_addr.eq(erase_cur)
                m.d.comb += self.fb_write.data.char.eq(ord(" "))
            with m.State("do-scroll-read"):
                with m.If((scroll_src < 0) | (scroll_src >= 128 * 48)):
                    m.d.sync += scroll_blank.eq(1)
                with m.Else():
                    m.d.sync += scroll_blank.eq(0)
                    m.d.comb += self.fb_read.en.eq(1)
                    m.d.comb += mem_addr.eq(scroll_src)
                with m.If(scroll_fwd):
                    m.d.sync += scroll_src.eq(scroll_src + 1)
                with m.Else():
                    m.d.sync += scroll_src.eq(scroll_src - 1)
                m.next = "do-scroll-write"
                pass
            with m.State("do-scroll-write"):
                with m.If((scroll_dst >= 0) & (scroll_dst < 128 * 48)):
                    m.d.comb += self.fb_write.en.eq(1)
                    m.d.comb += mem_addr.eq(scroll_dst)
                    with m.If(scroll_blank):
                        m.d.comb += self.fb_write.data.char.eq(ord(" "))
                    with m.Else():
                        m.d.comb += self.fb_write.data.eq(self.fb_read.data)
                with m.If(scroll_fwd):
                    m.d.sync += scroll_dst.eq(scroll_dst + 1)
                with m.Else():
                    m.d.sync += scroll_dst.eq(scroll_dst - 1)
                m.d.sync += scroll_ctr.eq(scroll_ctr - 1)

                with m.If(scroll_ctr == 1):
                    m.next = "idle"
                with m.Else():
                    m.next = "do-scroll-read"

        return m



class TextAnsiEscProcessor(wiring.Component):
    chars: In(stream.Signature(unsigned(8)))
    commands: Out(stream.Signature(Command))

    def elaborate(self, platform):
        m = Module()

        # ANSI escape codes have the following format:
        # ESC (\[ \?? (NUMBER(;NUMBER)*)?)? LETTER
        #
        # Numbers appear to go into the thousands (e.g. CSI ? 2004 h), so we should saturate them.
        # For the commands we're interested in, we only need 3 numbers (CSI 48;5;<fg> m)
        #
        # ? can be treated as a flag and simply ignored (for now at least)
        #
        # Unrecognized sequences we'll just ignore and not show.
        # On parse error we abandon parsing and just dump out the crap to screen.

        csi_question_mark = Signal()

        max_args = 3
        num_args = Array([Signal(16) for _ in range(max_args + 1)])
        num_idx = Signal(range(max_args + 1))

        cur_num = num_args[num_idx]

        def arg_val(n, default):
            return Mux(n >= num_idx, default, num_args[n])

        with m.If(self.commands.valid):
            with m.If(self.commands.ready):
                m.d.sync += self.commands.valid.eq(0)
        with m.Elif(self.chars.valid):
            with m.FSM():
                with m.State("idle"):
                    m.d.comb += self.chars.ready.eq(1)
                    with m.If(self.chars.payload == 0x1B):
                        m.next = "esc"
                    with m.Else():
                        m.d.sync += self.commands.valid.eq(1)
                        m.d.sync += self.commands.payload.opcode.eq(Opcode.PUT_CHAR)
                        m.d.sync += self.commands.payload.params.char.eq(self.chars.payload)
                with m.State("esc"):
                    m.d.comb += self.chars.ready.eq(1)
                    m.next = "idle"
                    with m.Switch(self.chars.payload):
                        with m.Case(ord("[")):
                            m.d.sync += csi_question_mark.eq(0)
                            m.next = "csi-begin"
                        with m.Case(ord("c")):
                            m.d.sync += self.commands.valid.eq(1)
                            m.d.sync += self.commands.payload.opcode.eq(Opcode.RESET)
                        with m.Default():
                            pass

                with m.State("csi-begin"):
                    with m.If((self.chars.payload == ord("?")) & ~csi_question_mark):
                        m.d.comb += self.chars.ready.eq(1)
                        m.d.sync += csi_question_mark.eq(1)
                    with m.Elif((self.chars.payload >= ord("0")) & (self.chars.payload <= ord("9"))):
                        m.d.sync += num_idx.eq(0)
                        m.d.sync += num_args[0].eq(0)
                        m.next = "csi-numarg"
                    with m.Else():
                        m.next = "csi-act"

                with m.State("csi-numarg"):
                    with m.If((self.chars.payload >= ord("0")) & (self.chars.payload <= ord("9"))):
                        m.d.comb += self.chars.ready.eq(1)
                        m.d.sync += cur_num.eq(cur_num * 10 + self.chars.payload - ord("0"))
                    with m.Elif(self.chars.payload == ord(";")):
                        m.d.comb += self.chars.ready.eq(1)
                        m.d.sync += num_idx.eq(num_idx + 1)
                        m.d.sync += num_args[num_idx + 1].eq(0)
                    with m.Else():
                        m.d.sync += num_idx.eq(num_idx + 1)
                        m.next = "csi-act"

                with m.State("csi-act"):
                    m.d.comb += self.chars.ready.eq(1)

                    with m.Switch(self.chars.payload):
                        with m.Case(ord("A")):
                            m.d.sync += self.commands.valid.eq(1)
                            m.d.sync += self.commands.payload.opcode.eq(Opcode.MOVE_CURSOR_REL)
                            m.d.sync += self.commands.payload.params.rel_pos.x_axis.eq(0)
                            m.d.sync += self.commands.payload.params.rel_pos.delta.eq(-arg_val(0, 1))
                        with m.Case(ord("B")):
                            m.d.sync += self.commands.valid.eq(1)
                            m.d.sync += self.commands.payload.opcode.eq(Opcode.MOVE_CURSOR_REL)
                            m.d.sync += self.commands.payload.params.rel_pos.x_axis.eq(0)
                            m.d.sync += self.commands.payload.params.rel_pos.delta.eq(arg_val(0, 1))
                        with m.Case(ord("C")):
                            m.d.sync += self.commands.valid.eq(1)
                            m.d.sync += self.commands.payload.opcode.eq(Opcode.MOVE_CURSOR_REL)
                            m.d.sync += self.commands.payload.params.rel_pos.x_axis.eq(1)
                            m.d.sync += self.commands.payload.params.rel_pos.delta.eq(arg_val(0, 1))
                        with m.Case(ord("D")):
                            m.d.sync += self.commands.valid.eq(1)
                            m.d.sync += self.commands.payload.opcode.eq(Opcode.MOVE_CURSOR_REL)
                            m.d.sync += self.commands.payload.params.rel_pos.x_axis.eq(1)
                            m.d.sync += self.commands.payload.params.rel_pos.delta.eq(-arg_val(0, 1))
                        with m.Case(ord("E")):
                            # TODO: Next Line
                            pass
                        with m.Case(ord("F")):
                            # TODO: Previous Line
                            pass
                        with m.Case(ord("G")):
                            # TODO: Horizontal absolute
                            pass
                        with m.Case(ord("H"), ord("f")):
                            m.d.sync += self.commands.valid.eq(1)
                            m.d.sync += self.commands.payload.opcode.eq(Opcode.MOVE_CURSOR_ABS)
                            m.d.sync += self.commands.payload.params.abs_pos.x.eq(saturate(arg_val(1, 1) - 1, 127))
                            m.d.sync += self.commands.payload.params.abs_pos.y.eq(saturate(arg_val(0, 1) - 1, 47))
                        with m.Case(ord("J")):
                            m.d.sync += self.commands.valid.eq(1)
                            m.d.sync += self.commands.payload.opcode.eq(Opcode.ERASE_DISPLAY)
                            m.d.sync += self.commands.payload.params.erase.before.eq((arg_val(0, 0) == 1) | (arg_val(0, 0) == 2))
                            m.d.sync += self.commands.payload.params.erase.after.eq((arg_val(0, 0) == 0) | (arg_val(0, 0) == 2))
                        with m.Case(ord("K")):
                            m.d.sync += self.commands.valid.eq(1)
                            m.d.sync += self.commands.payload.opcode.eq(Opcode.ERASE_LINE)
                            m.d.sync += self.commands.payload.params.erase.before.eq((arg_val(0, 0) == 1) | (arg_val(0, 0) == 2))
                            m.d.sync += self.commands.payload.params.erase.after.eq((arg_val(0, 0) == 0) | (arg_val(0, 0) == 2))
                        with m.Case(ord("S")):
                            m.d.sync += self.commands.valid.eq(1)
                            m.d.sync += self.commands.payload.opcode.eq(Opcode.SCROLL)
                            m.d.sync += self.commands.payload.params.rel_pos.delta.eq(arg_val(0, 1))
                        with m.Case(ord("T")):
                            m.d.sync += self.commands.valid.eq(1)
                            m.d.sync += self.commands.payload.opcode.eq(Opcode.SCROLL)
                            m.d.sync += self.commands.payload.params.rel_pos.delta.eq(-arg_val(0, 1))
                        with m.Case(ord("m")):
                            # TODO: SGR
                            pass


                    m.next = "idle"

        return m


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
