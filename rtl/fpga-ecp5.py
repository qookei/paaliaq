import argparse, math

from amaranth import *
from amaranth.lib import wiring
from amaranth.build import *
from amaranth.vendor import LatticeECP5Platform
from amaranth_boards.resources import *

from soc import SoC
from sdram import SDRAMConnector
from cpu import W65C816Connector, P65C816SoftCore


# Compute PLL parameters for a PLL with a primary and one secondary
# output configured to the same frequency, with the secondary output
# being 180 degrees out of phase with the primary.
# Logic derived from the ecppll tool from prjtrellis:
# https://github.com/YosysHQ/prjtrellis/blob/master/libtrellis/tools/ecppll.cpp
# (specifically calc_pll_params, generate_secondary_output)
PFD_MIN = 3.125
PFD_MAX = 400
VCO_MIN = 400
VCO_MAX = 800
def compute_pll_params(in_clk, out_clk):
    in_MHz = in_clk // 1e6
    out_MHz = out_clk // 1e6

    assert in_MHz * 1e6 == in_clk, 'Input clock must be a integer multiple of MHz'
    assert out_MHz * 1e6 == out_clk, 'Output clock must be a integer multiple of MHz'

    best_in_div = -1
    best_fb_div = -1
    best_out_div = -1
    best_fvco = -1
    best_fout = -1

    error = math.inf
    for in_div in range(1, 129):
        fpfd = in_MHz / in_div
        if fpfd < PFD_MIN or fpfd > PFD_MAX:
            continue
        for fb_div in range(1, 81):
            for out_div in range(1, 129):
                fvco = fpfd * fb_div * out_div
                if fvco < VCO_MIN or fvco > VCO_MAX:
                    continue
                fout = fvco / out_div
                if abs(fout - out_MHz) < error or (
                        abs(fout - out_MHz) == error
                        and abs(fvco - 600) < abs(best_fvco - 600)
                ):
                    error = abs(fout - out_MHz)
                    best_in_div = in_div
                    best_fb_div = fb_div
                    best_out_div = out_div
                    best_fvco = fvco
                    best_fout = fout

    assert best_fout == out_MHz, 'Failed to find PLL configuration that reaches target freq.'

    # Primary clock has a phase shift of 180 degrees.  Secondary clock
    # has a phase shift of 180 degrees relative to primary.
    ns_shift = 1 / (out_MHz * 1e6) * (180 / 360)
    primary_cphase = int(ns_shift * (best_fvco * 1e6))
    secondary_cphase = int(primary_cphase * 2)

    return {
        'a_FREQUENCY_PIN_CLKI': int(in_MHz),
        'a_FREQUENCY_PIN_CLKOP': int(out_MHz),
        'a_FREQUENCY_PIN_CLKOS': int(out_MHz),
        'a_ICP_CURRENT': 12,
        'a_LPF_RESISTOR': 8,
        'p_CLKI_DIV': best_in_div,
        'p_FEEDBK_PATH': 'CLKOP',
        'p_CLKFB_DIV': best_fb_div,
        'p_CLKOP_ENABLE': 'ENABLED',
        'p_CLKOP_DIV': best_out_div,
        'p_CLKOP_CPHASE': primary_cphase,
        'p_CLKOP_FPHASE': 0,
        'p_CLKOS_ENABLE': 'ENABLED',
        'p_CLKOS_DIV': best_out_div,
        'p_CLKOS_CPHASE': secondary_cphase,
        'p_CLKOS_FPHASE': 0,
    }


class TopLevel(Elaboratable):
    def __init__(self, *, target_clk=75e6, external_cpu=False):
        super().__init__()
        self._target_clk = target_clk
        self._external_cpu = external_cpu

    def elaborate(self, platform):
        m = Module()

        cd_sync = ClockDomain("sync")
        m.domains += cd_sync

        cd_sdram = ClockDomain("sdram")
        m.domains += cd_sdram

        primary_clk = Signal()

        # TODO: (Bug amaranth-lang/amaranth#1565).
        # platform.add_clock_constraint(cd_sync.clk, self._target_clk)

        m.submodules.pll = Instance(
            "EHXPLLL",
            **compute_pll_params(platform.default_clk_frequency, self._target_clk),

            i_CLKI=platform.request("clk25").i,

            o_CLKOP=ClockSignal("sync"),
            o_CLKOS=ClockSignal("sdram"),
            i_CLKFB=ClockSignal("sync"),
        )

        m.submodules.soc = soc = SoC(target_clk=self._target_clk)

        uart = platform.request("uart")
        m.d.comb += [
            uart.tx.o.eq(soc.tx),
            soc.rx.eq(uart.rx.i),
        ]

        led = platform.request("led")
        #m.d.comb += led.o.eq(top.timer.irq.i)

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


class PaaliaqPlatform(LatticeECP5Platform):
    device      = "LFE5U-25F"
    package     = "BG256"
    speed       = "7"
    default_clk = "clk25"


    def __init__(self, *, use_abc9=True, allow_timing_fail=False):
        super().__init__()
        self._use_abc9 = use_abc9
        self._allow_timing_fail = allow_timing_fail


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
            irq="R15", nmi="T15", abort="P13",
            attrs=Attrs(PULLMODE="NONE", DRIVE="4", SLEWRATE="FAST", IO_TYPE="LVCMOS33")
        )
    ]

    connectors = []

    def toolchain_prepare(self, fragment, name, **kwargs):
        overrides = dict(ecppack_opts="--compress")
        if not self._use_abc9:
            overrides['synth_opts'] = '-noabc9'
        if self._allow_timing_fail or True:
            overrides['nextpnr_opts'] = '--timing-allow-fail'
        overrides.update(kwargs)
        return super().toolchain_prepare(fragment, name, **overrides)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--external-cpu', action='store_true')
    parser.add_argument('--allow-timing-fail', action='store_true')
    parser.add_argument('--target-clk', type=int, default=75)

    args = parser.parse_args()
    # FIXME(qookie): Don't disable ABC9 once it's fixed and doesn't
    # croak on the P65C816 soft-core. (Bug YosysHQ/yosys#4249).
    platform = PaaliaqPlatform(
        use_abc9=args.external_cpu,
        allow_timing_fail=args.allow_timing_fail)
    platform.add_file('65c816.v', open('65c816.v'))
    platform.build(TopLevel(
        external_cpu=args.external_cpu,
        target_clk=args.target_clk * 1e6))
