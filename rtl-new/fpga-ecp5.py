from amaranth import *
from amaranth.build import *
from amaranth.vendor import LatticeECP5Platform
from amaranth_boards.resources import *

from top import TopLevel
from uart import UARTTransmitter


class FpgaTopLevel(Elaboratable):
    def elaborate(self, platform):
        m = Module()

        m.submodules.top = top = TopLevel()

        led = platform.request("led")
        m.d.comb += led.o.eq(1)

        m.submodules.uart_tx = uart_tx = UARTTransmitter(fifo_depth=32)
        uart = platform.request("uart")
        m.d.comb += uart.tx.o.eq(uart_tx.tx)

        clk_edge_sr = Signal(2)
        m.d.sync += clk_edge_sr.eq((clk_edge_sr << 1) | top.cpu_bridge.debug_trigger)

        out_latch = Signal(8)

        def to_hex(o, i):
            with m.Switch(i):
                for i in range(16):
                    with m.Case(i):
                        m.d.sync += o.eq(ord(f'{i:x}'))

        def emit_char(seq, v):
            with m.State(f'tx-{seq}'):
                m.d.sync += uart_tx.w_data.eq(v)
                m.d.sync += uart_tx.w_en.eq(1)
                m.next = f'tx-{seq}-done'

            with m.State(f'tx-{seq}-done'):
                m.d.sync += uart_tx.w_en.eq(0)
                m.next = f'tx-{seq + 1}'

        addr_char0 = Signal(8)
        addr_char1 = Signal(8)
        addr_char2 = Signal(8)
        addr_char3 = Signal(8)
        addr_char4 = Signal(8)
        addr_char5 = Signal(8)

        data_char0 = Signal(8)
        data_char1 = Signal(8)

        vda = Signal()
        vpa = Signal()
        rwb = Signal()

        with m.FSM():
            with m.State('idle'):
                with m.If(clk_edge_sr == 0b01):
                    to_hex(addr_char0, top.cpu_bridge.cpu.addr_lo.bit_select(0, 4))
                    to_hex(addr_char1, top.cpu_bridge.cpu.addr_lo.bit_select(4, 4))
                    to_hex(addr_char2, top.cpu_bridge.cpu.addr_lo.bit_select(8, 4))
                    to_hex(addr_char3, top.cpu_bridge.cpu.addr_lo.bit_select(12, 4))
                    to_hex(addr_char4, top.cpu_bridge.cpu.addr_hi.bit_select(0, 4))
                    to_hex(addr_char5, top.cpu_bridge.cpu.addr_hi.bit_select(4, 4))

                    with m.If(top.cpu_bridge.cpu.r_data_en):
                        to_hex(data_char0, top.cpu_bridge.cpu.r_data.bit_select(0, 4))
                        to_hex(data_char1, top.cpu_bridge.cpu.r_data.bit_select(4, 4))
                    with m.Else():
                        to_hex(data_char0, top.cpu_bridge.cpu.w_data.bit_select(0, 4))
                        to_hex(data_char1, top.cpu_bridge.cpu.w_data.bit_select(4, 4))

                    m.d.sync += [
                        vda.eq(top.cpu_bridge.cpu.vda),
                        vpa.eq(top.cpu_bridge.cpu.vpa),
                        rwb.eq(top.cpu_bridge.cpu.rw),
                    ]

                    m.next = 'tx-0'

            emit_char(0, addr_char5)
            emit_char(1, addr_char4)
            emit_char(2, addr_char3)
            emit_char(3, addr_char2)
            emit_char(4, addr_char1)
            emit_char(5, addr_char0)

            emit_char(6, C(ord(' '), 8))

            emit_char(7, data_char1)
            emit_char(8, data_char0)

            emit_char(9, C(ord(' '), 8))

            emit_char(10, Mux(vda, C(ord('D'), 8), C(ord('-'), 8)))
            emit_char(11, Mux(vpa, C(ord('P'), 8), C(ord('-'), 8)))
            emit_char(12, Mux(rwb, C(ord('R'), 8), C(ord('W'), 8)))
            emit_char(13, C(ord('\n'), 8))

            with m.State('tx-14'):
                m.next = 'idle'

        return m


class PaaliaqPlatform(LatticeECP5Platform):
    device                 = "LFE5U-25F"
    package                = "BG256"
    speed                  = "7"
    default_clk            = "clk25"
    default_clk_frequency  = 25000000

    resources = [
        Resource("clk25", 0, Pins("P6", dir="i"), Clock(25e6), Attrs(IO_TYPE="LVCMOS33")),

        *LEDResources(pins="T6", invert=True,
                      attrs=Attrs(IO_TYPE="LVCMOS33", DRIVE="4")),

        *ButtonResources(pins="R7", invert=True,
                         attrs=Attrs(IO_TYPE="LVCMOS33", PULLMODE="UP")),

        UARTResource(0, rx="T14", tx="T13"),
    ]

    connectors = []

    def toolchain_prepare(self, fragment, name, **kwargs):
        # FIXME: Drop `-noabc9` once that works. (Bug YosysHQ/yosys#4249)
        overrides = dict(synth_opts="-noabc9", ecppack_opts="--compress")
        overrides.update(kwargs)
        return super().toolchain_prepare(fragment, name, **overrides)


if __name__ == '__main__':
    platform = PaaliaqPlatform()
    platform.add_file('65c816.v', open('65c816.v'))
    platform.build(FpgaTopLevel())
