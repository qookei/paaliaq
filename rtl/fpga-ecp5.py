import argparse, math

from amaranth import *
from amaranth.lib import wiring, io
from amaranth.build import *
from amaranth.vendor import LatticeECP5Platform
from amaranth_boards.resources import *

from soc import SoC
from sdram import SDRAMConnector
from cpu import W65C816Connector, P65C816SoftCore

from pll import ECP5PLL


class TopLevel(Elaboratable):
    def __init__(self, *, target_clk=75e6, external_cpu=False, boot_rom_path):
        super().__init__()
        self._target_clk = target_clk
        self._external_cpu = external_cpu
        self._boot_rom_path = boot_rom_path

    def elaborate(self, platform):
        m = Module()

        m.domains.clk25 = cd_clk25 = ClockDomain(platform.default_clk)
        m.submodules.clk = clk = io.Buffer("i", platform.request(platform.default_clk, dir="-"))
        m.d.comb += ClockSignal(platform.default_clk).eq(clk.i)

        clk_freq = platform.default_clk_frequency

        m.domains.sync = cd_sync = ClockDomain("sync")
        m.domains.sdram = cd_sdram = ClockDomain("sdram")

        m.submodules.pll = pll = ECP5PLL()
        pll.add_input(clk=clk.i, freq=clk_freq)
        pll.add_primary_output(freq=self._target_clk)
        pll.add_secondary_output(domain="sdram", freq=self._target_clk, phase=180)

        m.submodules.soc = soc = SoC(target_clk=self._target_clk, boot_rom_path=self._boot_rom_path)

        uart = platform.request("uart", dir="-")
        m.submodules.uart_tx = uart_tx = io.Buffer("o", uart.tx)
        m.submodules.uart_rx = uart_rx = io.Buffer("i", uart.rx)

        m.d.comb += [
            uart_tx.o.eq(soc.tx),
            soc.rx.eq(uart_rx.i),
        ]

        # m.submodules.led = led = io.Buffer("o", platform.request("led", dir="-"))
        # m.d.sync += led.o.eq(~led.o)

        m.submodules.sdram = sdram = SDRAMConnector()
        wiring.connect(m, sdram.sdram, soc.sdram)

        m.submodules.cpu = cpu = W65C816Connector() if self._external_cpu else P65C816SoftCore()
        wiring.connect(m, cpu.iface, soc.cpu)

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


def HDMIResource(*args, clk_p, clk_n, data_p, data_n, conn=None, attrs=None):
    io = []

    io.append(Subsignal('clk_p', Pins(clk_p, dir='o', conn=conn, assert_width=1)))
    io.append(Subsignal('clk_n', Pins(clk_n, dir='o', conn=conn, assert_width=1)))
    io.append(Subsignal('data_p', Pins(data_p, dir='o', conn=conn, assert_width=3)))
    io.append(Subsignal('data_n', Pins(data_n, dir='o', conn=conn, assert_width=3)))

    if attrs is not None:
        io.append(attrs)
    return Resource.family(*args, default_name='hdmi', ios=io)

class PaaliaqPlatform(LatticeECP5Platform):
    device      = "LFE5U-25F"
    package     = "BG381"
    speed       = "8"
    default_clk = "clk25"


    def __init__(self, *, allow_timing_fail=False):
        super().__init__()
        self._allow_timing_fail = allow_timing_fail


    resources = [
        Resource("clk25", 0, Pins("P3", dir="i"), Clock(25e6), Attrs(IO_TYPE="LVCMOS33")),

        *LEDResources(pins="U16", invert=True,
                      attrs=Attrs(IO_TYPE="LVCMOS33", DRIVE="4")),

        SDRAMResource(0,
            clk="B9", we_n="A10", cas_n="A9", ras_n="B10",
            ba="B11 C8", a="B13 C14 A16 A17 B16 B15 A14 A13 A12 A11 B12",
            dq="B6  A5  A6  A7  C7  B8  B5  A8  D8  D7  E8  D6  C6  D5  E7  C5 "
               "C10 D9  E11 D11 C11 D12 E9  C12 E14 C15 E13 D15 E12 B17 D14 D13",
            attrs=Attrs(PULLMODE="NONE", DRIVE="4", SLEWRATE="FAST", IO_TYPE="LVCMOS33")
        ),

        UARTResource(0, rx="H18", tx="J17"),

        HDMIResource(
            0,
            clk_p="J19", clk_n="K19",
            data_p="G19 E20 C20",
            data_n="H20 F19 D19",
            attrs=Attrs(DRIVE="4", IO_TYPE="LVCMOS33D"),
        ),

        # XXX(qookie): This is not the final pin assignment. I haven't
        # designed the PCB with the CPU yet, I just want to see the
        # fMAX when using an external CPU.
        #W65C816Resource(
        #    0,
        #    clk="C4", rst="D4",
        #    addr="E4 D3 F5 E3 F1 F2 G2 G1 H2 H3 B1 C2 C1 D1 E2 E1",
        #    data="P5 R3 P2 R2 T2 N6 N14 R12",
        #    rwb="R14", vda="T14", vpa="P12", vpb="P14",
        #    irq="R15", nmi="T15", abort="P13",
        #    attrs=Attrs(PULLMODE="NONE", DRIVE="4", SLEWRATE="FAST", IO_TYPE="LVCMOS33")
        #)
    ]

    connectors = []

    def toolchain_prepare(self, fragment, name, **kwargs):
        overrides = dict(ecppack_opts="--compress")
        if self._allow_timing_fail:
            overrides['nextpnr_opts'] = '--timing-allow-fail'
        overrides.update(kwargs)
        return super().toolchain_prepare(fragment, name, **overrides)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--external-cpu', action='store_true')
    parser.add_argument('--allow-timing-fail', action='store_true')
    parser.add_argument('--target-clk', type=int, default=75)
    parser.add_argument("--boot-rom", type=str, default="../build/boot0.bin")

    args = parser.parse_args()
    platform = PaaliaqPlatform(allow_timing_fail=args.allow_timing_fail)
    with open("external/P65C816.v", "r") as f:
        platform.add_file("P65C816.v", f)
    platform.build(TopLevel(
        external_cpu=args.external_cpu,
        target_clk=args.target_clk * 1e6,
        boot_rom_path=args.boot_rom,
    ))
