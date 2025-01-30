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

        #m.d.comb += led.o.eq(addr_tmp.bit_select(0, 1))
        #m.d.comb += led.o.eq(top.cpu_bridge.cpu.w_data.bit_select(0, 1))
        #m.d.comb += led.o.eq(self.top.cpu.cpu_clk.bit_select(0, 1))
        #m.d.comb += led.o.eq(self.top.cpu.t1_ctr.bit_select(0, 1))
        #m.d.comb += led.o.eq(self.top.cpu.ctr.bit_select(0, 1))

        m.submodules.uart_tx = uart_tx = UARTTransmitter()
        uart = platform.request("uart")
        m.d.comb += uart.tx.o.eq(uart_tx.tx)

        ctr = Signal()

        clk_edge_sr = Signal(2)
        m.d.sync += clk_edge_sr.eq((clk_edge_sr << 1) | (~top.cpu_bridge.cpu.clk))

        out_latch = Signal(8)

        def tohex(i, o):
            with m.Switch(i):
                for i in range(16):
                    with m.Case(i):
                        m.d.sync += o.eq(ord(f'{i:x}'))

        def emit_char(this_state, next_state, v):

            with m.State('tx-low'):
                tohex(out_latch.bit_select(0, 4), uart_tx.w_data)
                m.d.sync += uart_tx.w_en.eq(1)
                m.next = 'tx-low-done'

            with m.State('tx-low-done'):
                m.d.sync += uart_tx.w_en.eq(0)
                m.next = 'tx-nl'


        with m.FSM():
            with m.State('idle'):
                with m.If((clk_edge_sr == 0b01) & ~top.cpu_bridge.cpu.rw):
                    m.d.sync += out_latch.eq(top.cpu_bridge.cpu.w_data)

                    tohex(top.cpu_bridge.cpu.w_data.bit_select(4, 4), uart_tx.w_data)
                    m.d.sync += uart_tx.w_en.eq(1)

                    m.next = 'tx-high-done'

            with m.State('tx-high-done'):
                m.d.sync += uart_tx.w_en.eq(0)
                m.next = 'tx-low'

            with m.State('tx-low'):
                tohex(out_latch.bit_select(0, 4), uart_tx.w_data)
                m.d.sync += uart_tx.w_en.eq(1)
                m.next = 'tx-low-done'

            with m.State('tx-low-done'):
                m.d.sync += uart_tx.w_en.eq(0)
                m.next = 'tx-nl'

            with m.State('tx-nl'):
                m.d.sync += uart_tx.w_data.eq(ord('\n'))
                m.d.sync += uart_tx.w_en.eq(1)
                m.next = 'tx-nl-done'

            with m.State('tx-nl-done'):
                m.d.sync += uart_tx.w_en.eq(0)
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
