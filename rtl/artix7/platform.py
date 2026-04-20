from amaranth import *
from amaranth.build import *
from amaranth.vendor import XilinxPlatform
from amaranth_boards.resources import *

from cpu import P65C816SoftCore
from resource import *
from sdram import SDRAMConnector

class PaaliaqPlatform(XilinxPlatform):
    device      = "XC7A100T"
    package     = "FGG676"
    speed       = "1"
    default_clk = "clk50"

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

    def toolchain_prepare(self, fragment, name, **kwargs):
        constraints = """
        create_generated_clock -name soc_clk [get_pins soc_pll/pll/CLKOUT0]
        create_generated_clock -name sdram_clk [get_pins soc_pll/pll/CLKOUT1]
        create_generated_clock -name tmds_clk [get_pins video_pll/pll/CLKOUT0]
        create_generated_clock -name pixel_clk [get_pins video_pll/pll/CLKOUT1]

        set_clock_groups -asynchronous -group soc_clk -group {pixel_clk tmds_clk}
        """

        return super().toolchain_prepare(fragment, name, add_constraints=constraints, **kwargs)


    def get_sdram_ios(self):
        return SDRAMConnector()


    def get_cpu_ios(self):
        return P65C816SoftCore()
