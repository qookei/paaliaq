from amaranth import *
from amaranth.build import *
from amaranth.vendor import LatticeECP5Platform
from amaranth_boards.resources import *

from top import TopLevel
from uart import UARTTransmitter
from probe import W65C816DebugProbe


class FpgaTopLevel(Elaboratable):
    def elaborate(self, platform):
        m = Module()

        cd_sync = ClockDomain("sync")
        m.domains += cd_sync

        cd_sdram = ClockDomain("sdram")
        m.domains += cd_sdram

        primary_clk = Signal()

        # TODO
        # platform.add_clock_constraint(cd_sync.clk, 100e6)

        m.submodules.pll = Instance(
            "EHXPLLL",

            a_FREQUENCY_PIN_CLKI="25",
            a_FREQUENCY_PIN_CLKOP="75",
            a_FREQUENCY_PIN_CLKOS="75",
            a_ICP_CURRENT="12",
            a_LPF_RESISTOR="8",
            p_CLKI_DIV=1,
            p_CLKOP_DIV=8,
            p_CLKOS_DIV=8,
            p_CLKOP_CPHASE=4,
            p_CLKOP_FPHASE=0,
            p_CLKOS_CPHASE=8,
            p_CLKOS_FPHASE=0,
            p_CLKFB_DIV=3,
            p_FEEDBK_PATH="CLKOP",
            p_CLKOP_ENABLE="ENABLED",
            p_CLKOS_ENABLE="ENABLED",

            i_CLKI=platform.request("clk25").i,

            o_CLKOP=ClockSignal("sync"),
            o_CLKOS=ClockSignal("sdram"),
            i_CLKFB=ClockSignal("sync"),
        )

        m.submodules.top = top = TopLevel()

        if False:
            m.submodules.probe = probe = W65C816DebugProbe(top.cpu_bridge)
            uart = platform.request("uart")
            m.d.comb += uart.tx.o.eq(probe.tx)
            m.d.comb += top.uart.rx.eq(1)
        else:
            uart = platform.request("uart")
            m.d.comb += [
                uart.tx.o.eq(top.uart.tx),
                top.uart.rx.eq(uart.rx.i),
            ]

        led = platform.request("led")
        m.d.comb += led.o.eq(top.timer.irq.i)

        return m


class PaaliaqPlatform(LatticeECP5Platform):
    device               = "LFE5U-25F"
    package              = "BG256"
    speed                = "7"
    default_clk          = "clk25"
    target_clk_frequency = 75000000

    resources = [
        Resource("clk25", 0, Pins("P6", dir="i"), Clock(25e6), Attrs(IO_TYPE="LVCMOS33")),

        *LEDResources(pins="T6", invert=True,
                      attrs=Attrs(IO_TYPE="LVCMOS33", DRIVE="4")),

        *ButtonResources(pins="R7", invert=True,
                         attrs=Attrs(IO_TYPE="LVCMOS33", PULLMODE="UP")),

        UARTResource(0, rx="R7", tx="T13"),
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
