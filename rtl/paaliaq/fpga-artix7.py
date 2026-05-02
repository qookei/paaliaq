import argparse, math

from amaranth import *
from amaranth.lib import wiring, io
from amaranth.build import *
from amaranth.vendor import XilinxPlatform
from amaranth_boards.resources import *

from paaliaq.soc import SoC

from paaliaq.hdmi import DMT_MODE_1024x768_60Hz

from paaliaq.artix7.pll import S7MMCM
from paaliaq.artix7.platform import PaaliaqPlatform

from paaliaq.cpu import P65C816SoftCore
from paaliaq.sdram import SDRAMConnector

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
        m.domains.sdram = cd_sdram = ClockDomain("sdram")
        m.domains.tmds = cd_tmds = ClockDomain("tmds")
        m.domains.pixel = cd_pixel = ClockDomain("pixel")

        m.submodules.soc_pll = soc_pll = S7MMCM()
        soc_pll.add_input(clk=clk.i, freq=clk_freq)
        soc_pll.add_primary_output(freq=self._target_clk)
        soc_pll.add_secondary_output(freq=self._target_clk, phase=180, domain="sdram")

        mode = DMT_MODE_1024x768_60Hz

        m.submodules.video_pll = video_pll = S7MMCM()
        video_pll.add_input(clk=clk.i, freq=clk_freq)
        video_pll.add_primary_output(freq=mode.pixel_clock * 5, domain="tmds")
        video_pll.add_secondary_output(freq=mode.pixel_clock, domain="pixel")

        m.submodules.sdram_conn = sdram_conn = SDRAMConnector()
        m.submodules.w65c816_conn = w65c816_conn = P65C816SoftCore()

        platform.set_sdram_ios(sdram_conn.sdram)
        platform.set_w65c816_ios(w65c816_conn.iface)

        m.submodules.soc = soc = SoC(target_clk=self._target_clk, boot_rom_path=self._boot_rom_path)

        uart = platform.request("uart", dir="-")
        m.submodules.uart_tx = uart_tx = io.Buffer("o", uart.tx)
        m.submodules.uart_rx = uart_rx = io.Buffer("i", uart.rx)

        m.d.comb += [
            uart_tx.o.eq(soc.tx),
            soc.rx.eq(uart_rx.i),
        ]

        return m


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--external-cpu', action='store_true')
    parser.add_argument('--allow-timing-fail', action='store_true')
    parser.add_argument('--target-clk', type=int, default=75)
    parser.add_argument("--boot-rom", type=str, default="../build/boot0.bin")
    parser.add_argument("--build-dir", type=str, default="build")

    args = parser.parse_args()
    platform = PaaliaqPlatform()
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
