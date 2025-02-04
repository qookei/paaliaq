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

        m.submodules.top = top = TopLevel()

        if True:
            m.submodules.probe = probe = W65C816DebugProbe(top.cpu_bridge)
            uart = platform.request("uart")
            m.d.comb += uart.tx.o.eq(probe.tx)

        led = platform.request("led")
        m.d.comb += led.o.eq(1)

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
