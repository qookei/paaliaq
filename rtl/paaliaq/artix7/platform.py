from collections import deque, namedtuple

from amaranth import *
from amaranth.build import *
from amaranth.vendor import XilinxPlatform
from amaranth_boards.resources import *

from paaliaq.resource import *


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

        UARTResource(
            1,
            rx="H4", tx="F4",
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

        W65C816Resource(
            0,
            clk="W18", rst="V14",
            addr="T20 W21 U22 V23 AB24 AA24 V24 AB26 Y25 W25 V26 U25 U26 W26 Y26 AA25",
            data="U20 Y21 V22 W23 AC24 AB25 W24 AC26",
            rwb="W19", vda="V17", vpa="V19", vpb="U14",
            irq="V16", nmi="V18", abort="U15",
            attrs=Attrs(DRIVE="4", IOSTANDARD="LVCMOS33")
        )
    ]

    connectors = []

    def __init__(self, *, soc_clk):
        super().__init__()

        self._soc_clk = soc_clk
        self._sdram_clk = soc_clk
        self._uarts = deque()
        self._spis = deque()

    def toolchain_prepare(self, fragment, name, **kwargs):
        constraints = """
        create_generated_clock -name soc_clk [get_pins crg/soc_pll/pll/CLKOUT0]
        create_generated_clock -name sdram_clk [get_pins crg/soc_pll/pll/CLKOUT1]
        create_generated_clock -name tmds_clk [get_pins crg/video_pll/pll/CLKOUT0]
        create_generated_clock -name pixel_clk [get_pins crg/video_pll/pll/CLKOUT1]

        set_clock_groups -asynchronous -group soc_clk -group {pixel_clk tmds_clk}
        """

        return super().toolchain_prepare(fragment, name, add_constraints=constraints, **kwargs)

    @property
    def soc_clk(self):
        return self._soc_clk

    @property
    def sdram_clk(self):
        return self._sdram_clk

    def set_sdram_ios(self, ios):
        if hasattr(self, "_sdram_ios"):
            raise RuntimeError("SDRAM IOs already set")

        self._sdram_ios = ios

    def set_w65c816_ios(self, ios):
        if hasattr(self, "_w65c816_ios"):
            raise RuntimeError("W65C816 IOs already set")

        self._w65c816_ios = ios

    def set_boot_spi_clk(self, o, oe):
        if hasattr(self, "_boot_spi_clk_o") or hasattr(self, "_boot_spi_clk_oe"):
            raise RuntimeError("Boot SPI clock IOs already set")

        self._boot_spi_clk_o = o
        self._boot_spi_clk_oe = oe

    def add_uart(self, rx, tx):
        ty = namedtuple("UartPins", "rx, tx")
        self._uarts.append(ty(rx, tx))

    def add_spi(self, spi):
        self._spis.append(spi)

    def set_debug_uart(self, rx, tx):
        if hasattr(self, "_debug_uart"):
            raise RuntimeError("Debug UART IOs already set")

        ty = namedtuple("DebugUartPins", "rx, tx")
        self._debug_uart = ty(rx, tx)

    def get_sdram_ios(self):
        return self._sdram_ios

    def get_w65c816_ios(self):
        return self._w65c816_ios

    def get_boot_spi_clk_o(self):
        return self._boot_spi_clk_o

    def get_boot_spi_clk_oe(self):
        return self._boot_spi_clk_oe

    def get_uart(self):
        return self._uarts.popleft()

    def get_spi(self):
        return self._spis.popleft()

    def get_debug_uart(self):
        return self._debug_uart
