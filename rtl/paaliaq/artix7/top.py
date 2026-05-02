from amaranth import *
from amaranth.lib import io

from paaliaq.soc import SoC

from paaliaq.artix7.crg import CRG

from paaliaq.cpu import P65C816SoftCore
from paaliaq.sdram import SDRAMConnector


class PaaliaqTop(Elaboratable):
    def __init__(self, *, external_cpu=False, boot_rom_path):
        super().__init__()
        self._external_cpu = external_cpu
        self._boot_rom_path = boot_rom_path

    def elaborate(self, platform):
        m = Module()

        m.domains.sync = cd_sync = ClockDomain("sync")
        m.domains.sdram = cd_sdram = ClockDomain("sdram")
        m.domains.tmds = cd_tmds = ClockDomain("tmds")
        m.domains.pixel = cd_pixel = ClockDomain("pixel")

        m.submodules.crg = CRG()

        m.submodules.sdram_conn = sdram_conn = SDRAMConnector()
        m.submodules.w65c816_conn = w65c816_conn = P65C816SoftCore()

        spi_clk_o, spi_clk_oe = Signal(), Signal()

        m.submodules.startupe2 = Instance(
            "STARTUPE2",
            i_USRCCLKO=spi_clk_o,
            i_USRCCLKTS=~spi_clk_oe,
        )

        platform.set_sdram_ios(sdram_conn.sdram)
        platform.set_w65c816_ios(w65c816_conn.iface)
        platform.set_boot_spi_clk(spi_clk_o, spi_clk_oe)

        m.submodules.soc = soc = SoC(boot_rom_path=self._boot_rom_path)

        uart = platform.request("uart", dir="-")
        m.submodules.uart_tx = uart_tx = io.Buffer("o", uart.tx)
        m.submodules.uart_rx = uart_rx = io.Buffer("i", uart.rx)

        m.d.comb += [
            uart_tx.o.eq(soc.tx),
            soc.rx.eq(uart_rx.i),
        ]

        return m
