import argparse, math

from amaranth import *
from amaranth.lib import wiring, io
from amaranth.build import *
from amaranth.vendor import XilinxPlatform
from amaranth_boards.resources import *

from soc import SoC
from sdram import SDRAMConnector
from cpu import W65C816Connector, P65C816SoftCore

from pll import S7MMCM


class TopLevel(Elaboratable):
    def __init__(self, *, target_clk=75e6, external_cpu=False, boot_rom_path):
        super().__init__()
        self._target_clk = target_clk
        self._external_cpu = external_cpu
        self._boot_rom_path = boot_rom_path

    def elaborate(self, platform):
        m = Module()

        m.domains.clk50 = cd_clk50 = ClockDomain(platform.default_clk)
        m.submodules.clk = clk = io.Buffer("i", platform.request(platform.default_clk, dir="-"))
        m.d.comb += ClockSignal(platform.default_clk).eq(clk.i)

        clk_freq = platform.default_clk_frequency

        m.domains.sync = cd_sync = ClockDomain("sync")

        m.submodules.pll = pll = S7MMCM()
        pll.add_input(clk=clk.i, freq=clk_freq)
        pll.add_primary_output(freq=self._target_clk)

        m.submodules.soc = soc = SoC(target_clk=self._target_clk, boot_rom_path=self._boot_rom_path)

        uart = platform.request("uart", dir="-")
        m.submodules.uart_tx = uart_tx = io.Buffer("o", uart.tx)
        m.submodules.uart_rx = uart_rx = io.Buffer("i", uart.rx)

        m.d.comb += [
            uart_tx.o.eq(soc.tx),
            soc.rx.eq(uart_rx.i),
        ]

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

    io.append(Subsignal('clk', DiffPairs(clk_p, clk_n, dir='o', conn=conn, assert_width=1)))
    io.append(Subsignal('data', DiffPairs(data_p, data_n, dir='o', conn=conn, assert_width=3)))

    if attrs is not None:
        io.append(attrs)
    return Resource.family(*args, default_name='hdmi', ios=io)


def SPIResource(*args, cs_n, clk, dq0, dq1, dq2, dq3, conn=None, attrs=None):
    io = []

    io.append(Subsignal('cs_n', PinsN(cs_n, dir='o', conn=conn, assert_width=1)))
    if clk is not None:
        io.append(Subsignal('clk', Pins(clk, dir='o', conn=conn, assert_width=1)))
    io.append(Subsignal('dq0', Pins(dq0, dir='io', conn=conn)))
    io.append(Subsignal('dq1', Pins(dq1, dir='io', conn=conn)))
    io.append(Subsignal('dq2', Pins(dq2, dir='io', conn=conn)))
    io.append(Subsignal('dq3', Pins(dq3, dir='io', conn=conn)))

    if attrs is not None:
        io.append(attrs)
    return Resource.family(*args, default_name='spi', ios=io)

class PaaliaqPlatform(XilinxPlatform):
    device      = "XC7A100T"
    package     = "FGG676"
    speed       = "1"
    default_clk = "clk50"


    def __init__(self, *, allow_timing_fail=False):
        super().__init__()
        self._allow_timing_fail = allow_timing_fail


    resources = [
        Resource("clk50", 0, Pins("M21", dir="i"), Clock(50e6), Attrs(IOSTANDARD="LVCMOS33")),

        SDRAMResource(
            0,
            clk="G22", cke="H22", cs_n="L25", we_n="J26", cas_n="K25", ras_n="K26", dqm="J25 K23",
            ba="M25 M26", a="R26 P25 P26 N26 M24 M22 L24 L23 L22 K21 R25 K22 J21",
            dq="D25 D26 E25 E26 F25 G25 G26 H26 J24 J23 H24 H23 G24 F24 F23 E23",
            attrs=Attrs(SLEW="FAST", IOSTANDARD="LVTTL", DRIVE="12")
        ),

        UARTResource(
            0,
            rx="F3", tx="E3",
            attrs=Attrs(IOSTANDARD="LVCMOS33"),
        ),

        HDMIResource(
            0,
            clk_p="D4", clk_n="C4",
            data_p="E1 F2 G2",
            data_n="D1 E2 G1",
            attrs=Attrs(IOSTANDARD="TMDS_33"),
        ),

        SPIResource(
            0,
            cs_n="P18",
            clk=None,
            dq0="R14", dq1="R15", dq2="P14", dq3="N14",
            attrs=Attrs(IOSTANDARD="LVCMOS33"),
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
        #    attrs=Attrs(PULLMODE="NONE", DRIVE="4", SLEWRATE="FAST", IOSTANDARD="LVCMOS33")
        #)
    ]

    connectors = []


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--external-cpu', action='store_true')
    parser.add_argument('--allow-timing-fail', action='store_true')
    parser.add_argument('--target-clk', type=int, default=75)
    parser.add_argument("--boot-rom", type=str, default="../build/boot0.bin")
    parser.add_argument("--build-dir", type=str, default="build")

    args = parser.parse_args()
    platform = PaaliaqPlatform(allow_timing_fail=args.allow_timing_fail)
    with open("external/P65C816.v", "r") as f:
        platform.add_file("P65C816.v", f)
    platform.build(
        TopLevel(
            external_cpu=args.external_cpu,
            target_clk=args.target_clk * 1e6,
            boot_rom_path=args.boot_rom,
        ),
        build_dir=args.build_dir,
    )
