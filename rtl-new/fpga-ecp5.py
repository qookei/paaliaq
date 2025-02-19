from amaranth import *
from amaranth.lib import wiring
from amaranth.build import *
from amaranth.vendor import LatticeECP5Platform
from amaranth_boards.resources import *

from top import TopLevel
from uart import UARTTransmitter
from probe import W65C816DebugProbe
from sdram import SDRAMConnector
from cpu import W65C816Connector, P65C816SoftCore


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
            m.d.comb += top.rx.eq(1)
        else:
            uart = platform.request("uart")
            m.d.comb += [
                uart.tx.o.eq(top.tx),
                top.rx.eq(uart.rx.i),
            ]

        led = platform.request("led")
        #m.d.comb += led.o.eq(top.timer.irq.i)

        m.submodules.sdram = sdram = SDRAMConnector()
        wiring.connect(m, sdram.sdram, top.sdram)

        m.submodules.cpu = cpu = P65C816SoftCore() if True else W65C816Connector()
        wiring.connect(m, cpu.iface, top.cpu)

        return m


def W65C816Resource(*args, clk, rst, addr, data, rwb, vda, vpa, vpb,
                    irq, nmi, abort, conn=None, attrs=None):
    io = []

    io.append(Subsignal('clk', Pins(clk, dir='o', conn=conn, assert_width=1)))
    io.append(Subsignal('rst', Pins(rst, dir='o', conn=conn, assert_width=1)))

    io.append(Subsignal('addr', Pins(addr, dir='i', conn=conn, assert_width=16)))
    io.append(Subsignal('data', Pins(data, dir='io', conn=conn, assert_width=8)))

    io.append(Subsignal('rwb', Pins(rwb, dir='i', conn=conn, assert_width=1)))
    io.append(Subsignal('vda', Pins(vda, dir='i', conn=conn, assert_width=1)))
    io.append(Subsignal('vpa', Pins(vpa, dir='i', conn=conn, assert_width=1)))
    io.append(Subsignal('vpb', Pins(vpb, dir='i', conn=conn, assert_width=1)))

    io.append(Subsignal('irq',   Pins(irq,   dir='o', conn=conn, assert_width=1)))
    io.append(Subsignal('nmi',   Pins(nmi,   dir='o', conn=conn, assert_width=1)))
    io.append(Subsignal('abort', Pins(abort, dir='o', conn=conn, assert_width=1)))

    if attrs is not None:
        io.append(attrs)
    return Resource.family(*args, default_name='w65c816', ios=io)


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

        SDRAMResource(0,
            clk="C8", we_n="B5", cas_n="A6", ras_n="B6",
            ba="B7 A8", a="A9 B9 B10 C10 D9 C9 E9 D8 E8 C7 B8",
            dq="B2  A2  C3  A3  B3  A4  B4  A5  E7  C6  D7  D6  E6  D5  C5  E5 "
               "A11 B11 B12 A13 B13 A14 B14 D14 D13 E11 C13 D11 C12 E10 C11 D10",
            attrs=Attrs(PULLMODE="NONE", DRIVE="4", SLEWRATE="FAST", IO_TYPE="LVCMOS33")
        ),

        UARTResource(0, rx="R7", tx="T13"),

        # XXX(qookie): This is not the final pin assignment. I haven't
        # designed the PCB with the CPU yet, I just want to see the
        # fMAX when using an external CPU.
        W65C816Resource(
            0,
            clk="C4", rst="D4",
            addr="E4 D3 F5 E3 F1 F2 G2 G1 H2 H3 B1 C2 C1 D1 E2 E1",
            data="P5 R3 P2 R2 T2 N6 N14 R12",
            rwb="R14", vda="T14", vpa="P12", vpb="P14",
            irq="R15", nmi="T15", abort="P13"
        )
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
