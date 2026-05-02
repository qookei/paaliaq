from amaranth import *
from amaranth.lib import io

from paaliaq.hdmi import DMT_MODE_1024x768_60Hz

from paaliaq.artix7.pll import S7MMCM


class CRG(Elaboratable):
    def elaborate(self, platform):
        m = Module()

        m.submodules.clk = clk = io.Buffer("i", platform.request(platform.default_clk, dir="-"))

        clk_freq = platform.default_clk_frequency

        m.submodules.soc_pll = soc_pll = S7MMCM()
        soc_pll.add_input(clk=clk.i, freq=clk_freq)
        soc_pll.add_primary_output(freq=platform.soc_clk)
        soc_pll.add_secondary_output(freq=platform.soc_clk, phase=180, domain="sdram")

        mode = DMT_MODE_1024x768_60Hz

        m.submodules.video_pll = video_pll = S7MMCM()
        video_pll.add_input(clk=clk.i, freq=clk_freq)
        video_pll.add_primary_output(freq=mode.pixel_clock * 5, domain="tmds")
        video_pll.add_secondary_output(freq=mode.pixel_clock, domain="pixel")

        return m
