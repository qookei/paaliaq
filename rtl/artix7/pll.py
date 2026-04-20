from amaranth import *

import math
from dataclasses import dataclass


@dataclass
class PLLOutputParams:
    domain: str
    freq: int
    phase: int


class S7MMCM(Elaboratable):
    def __init__(self):
        super().__init__()

        self._input_clk = None
        self._input_freq = None

        self._primary = None
        self._secondaries = []

    def add_input(self, *, clk, freq):
        assert (self._input_clk is None) == (self._input_freq is None)
        if self._input_clk is not None:
            raise RuntimeError("PLL already has an input")
        freq_MHz = freq // 1e6
        if freq_MHz * 1e6 != freq:
            raise RuntimeError(f"Input clock frequency {freq} must be an integer multiple of MHz")

        self._input_clk = clk
        self._input_freq = freq

    def add_primary_output(self, *, domain="sync", freq, phase=0):
        if self._primary:
            raise RuntimeError("PLL already has a primary output")
        freq_MHz = freq // 1e6
        if freq_MHz * 1e6 != freq:
            raise RuntimeError(f"Output clock frequency {freq} must be an integer multiple of MHz")

        self._primary = PLLOutputParams(
            domain=domain,
            freq=freq,
            phase=phase,
        )

    def add_secondary_output(self, *, domain, freq, phase=0):
        if len(self._secondaries) == 5:
            raise RuntimeError("PLL is out of usable secondary outputs")
        freq_MHz = freq // 1e6
        if freq_MHz * 1e6 != freq:
            raise RuntimeError(f"Output clock frequency {freq} must be an integer multiple of MHz")

        self._secondaries += [PLLOutputParams(
            domain=domain,
            freq=freq,
            phase=phase,
        )]

    def elaborate(self, platform):
        m = Module()

        if self._input_clk is None or self._input_freq is None:
            raise RuntimeError("No input clock for PLL")
        if not self._primary:
            raise RuntimeError("No primary clock output for PLL")

        m.submodules.pll = Instance(
            "MMCME2_ADV",
            **self._compute_mmcm_params(),
        )

        return m

    def _compute_mmcm_params(self):
        PFD_MIN = 10
        PFD_MAX = 800
        VCO_MIN = 600
        VCO_MAX = 1200

        in_MHz = self._input_freq // 1e6

        all_out = [self._primary] + self._secondaries
        all_out_MHz = [x.freq // 1e6 for x in all_out]
        max_out_MHz = max(all_out_MHz)

        best_in_div = -1
        best_fb_mul = -1
        best_out_div = -1
        best_fvco = -1
        best_fout = -1

        error = math.inf
        for in_div in range(1, 106+1):
            fpfd = in_MHz / in_div
            if fpfd < PFD_MIN or fpfd > PFD_MAX:
                continue
            for fb_mul in range(2, 64+1):
                for out_div in range(1, 128+1):
                    fvco = fpfd * fb_mul
                    if fvco < VCO_MIN or fvco > VCO_MAX:
                        continue
                    fout = fvco / out_div
                    if abs(fout - max_out_MHz) < error or (
                            abs(fout - max_out_MHz) == error
                            and abs(fvco - 1000) < abs(best_fvco - 1000)
                    ):
                        error = abs(fout - max_out_MHz)
                        best_in_div = in_div
                        best_fb_mul = fb_mul
                        best_out_div = out_div
                        best_fvco = fvco
                        best_fout = fout

        if best_fout != max_out_MHz:
            raise RuntimeError(
                f"Failed to find PLL configuration that reaches primary frequency {max_out_MHz * 1e6}"
                f" (closest found is {best_fout * 1e6})"
            )

        pll_params = {}

        # Wire up input clock
        pll_params.update(
            i_CLKIN1=self._input_clk,
            p_CLKIN1_PERIOD=1e9 / self._input_freq,
            p_DIVCLK_DIVIDE=best_in_div,
        )

        # Wire up feedback clock
        clk_fb = Signal(name="pll_fb")
        pll_params.update(
            i_CLKFBIN=clk_fb,
            o_CLKFBOUT=clk_fb,
            p_CLKFBOUT_MULT_F=best_fb_mul,
        )

        # Wire up outputs
        for i, output in enumerate([self._primary] + self._secondaries):
            max_freq = max_out_MHz * 1e6
            ratio = int(max_freq // output.freq)
            if ratio * output.freq != max_freq:
                raise RuntimeError(
                    f"Maximum output frequency {max_freq} is not an integer multiple of "
                    f"output {i} freequency {output.freq}"
                )
            if ratio * best_out_div > 128:
                raise RuntimeError(
                    f"Output {i} frequency {output.freq} is too far away from "
                    f"maximum output frequency {max_freq}, divisor {ratio * best_out_div} > 128"
                )

            pll_params.update({
                f"o_CLKOUT{i}": ClockSignal(output.domain),
                f"p_CLKOUT{i}_DIVIDE{'_F' if i == 0 else ''}": best_out_div * ratio,
                f"p_CLKOUT{i}_PHASE": output.phase,
            })

        return pll_params
