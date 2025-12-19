from amaranth import *

import math
from dataclasses import dataclass


@dataclass
class PLLOutputParams:
    domain: str
    freq: int
    phase: int


class ECP5PLL(Elaboratable):
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
        if len(self._secondaries) == 3:
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
            "EHXPLLL",
            **self._compute_pll_params(),
        )

        return m

    # Compute PLL parameters for a PLL with the specified configuration.
    # Main logic derived from the ecppll tool from prjtrellis:
    # https://github.com/YosysHQ/prjtrellis/blob/master/libtrellis/tools/ecppll.cpp
    # (specifically calc_pll_params, generate_secondary_output)
    # Phase computation derived from description at https://blog.dave.tf/post/ecp5-pll/
    # Parameters match PLLs generated in Lattice Diamond 3.14.
    def _compute_pll_params(self):
        PFD_MIN = 3.125
        PFD_MAX = 400
        VCO_MIN = 400
        VCO_MAX = 800

        in_MHz = self._input_freq // 1e6

        all_out = [self._primary] + self._secondaries
        all_out_MHz = [x.freq // 1e6 for x in all_out]

        # Since the different outputs only differ by a divider on the
        # VCO, make sure the primary is the largest. Technically, we
        # could instead do feedback from any of the secondary outputs,
        # but that'd involve a bunch of extra logic, and I'm too lazy. :^)
        max_out_MHz = max(all_out_MHz)
        if all_out_MHz[0] != max_out_MHz:
            raise RuntimeError(
                f"Highest output frequency {max_out_MHz * 1e6} must be at the primary PLL output"
            )

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
                    if abs(fout - max_out_MHz) < error or (
                            abs(fout - max_out_MHz) == error
                            and abs(fvco - 600) < abs(best_fvco - 600)
                    ):
                        error = abs(fout - max_out_MHz)
                        best_in_div = in_div
                        best_fb_div = fb_div
                        best_out_div = out_div
                        best_fvco = fvco
                        best_fout = fout

        if best_fout != max_out_MHz:
            raise RuntimeError(
                f"Failed to find PLL configuration that reaches primary frequency {max_out_MHz * 1e6}"
                f" (closest found is {best_fout * 1e6})"
            )


        def _compute_phase_params(phase, div):
            assert phase > -360 and phase < 360, f"Phase {phase} out of bounds"

            coarse_step = 360 / div
            fine_step = 360 / (8 * div)

            # Truncation rounds towards -inf, which is what we want because
            # fine phase shift can only add to the total phase.
            coarse_turns = int(phase / coarse_step)
            fine_phase = phase - coarse_turns * coarse_step

            # CPHASE has a range [0, 2*(div - 1)], and is biased so that
            # (div - 1) is 0 deg
            cphase = coarse_turns + div - 1

            # FPHASE has a range [0, min(127, 8 * div - 1)], with no bias
            max_fphase = min(127, 8 * div - 1)
            fphase = int(fine_phase / fine_step)

            assert fphase <= max_fphase, (
                f"Computed FPHASE {fphase} is larger than maximum {max_fphase} for this divider"
            )

            computed_phase = (cphase - (div - 1)) * coarse_step + fphase * fine_step
            assert computed_phase == phase, (
                f"Failed to meet phase requested phase {phase}, closest is {computed_phase}"
                f" with CPHASE {cphase} and FPHASE {fphase}"
            )

            return (cphase, fphase)


        # TODO(qookie): ICP_CURRENT seems to be determined dynamically
        # I've seen values 5 and 6 for the two PLLs in this design.
        pll_params = {
            "a_ICP_CURRENT": "6",
            "a_LPF_RESISTOR": "16",
            "a_MFG_ENABLE_FILTEROPAMP": "1",
            "a_MFG_GMCREF_SEL": "2",
            "p_PLLRST_ENA": "DISABLED",
            "p_INTFB_WAKE": "DISABLED",
            "p_STDBY_ENABLE": "DISABLED",
            "p_DPHASE_SOURCE": "DISABLED",
            "p_PLL_LOCK_MODE": 0,
            "p_OUTDIVIDER_MUXA": "DIVA",
            "p_OUTDIVIDER_MUXB": "DIVB",
            "p_OUTDIVIDER_MUXC": "DIVC",
            "p_OUTDIVIDER_MUXD": "DIVD",
        }

        # Wire up input clock
        pll_params.update(
            i_CLKI=self._input_clk,
            a_FREQUENCY_PIN_CLKI=f"{self._input_freq / 1e6}",
            p_CLKI_DIV=best_in_div,
        )

        primary_cphase, primary_fphase = _compute_phase_params(self._primary.phase, best_out_div)

        # Wire up primary output and feedback signals
        pll_params.update(
            o_CLKOP=ClockSignal(self._primary.domain),
            a_FREQUENCY_PIN_CLKOP=f"{self._primary.freq / 1e6}",
            p_CLKOP_ENABLE="ENABLED",
            p_CLKOP_DIV=best_out_div,
            p_CLKOP_CPHASE=primary_cphase,
            p_CLKOP_FPHASE=primary_fphase,
            p_CLKOP_TRIM_DELAY=0,
            p_CLKOP_TRIM_POL="FALLING",
            p_FEEDBK_PATH="CLKOP",
            i_CLKFB=ClockSignal(self._primary.domain),
            p_CLKFB_DIV=best_fb_div,
        )

        # Sanity check and wire up all secondary outputs
        for name, secondary in zip(["CLKOS", "CLKOS2", "CLKOS3"], self._secondaries):
            ratio = int(self._primary.freq // secondary.freq)
            if ratio * secondary.freq != self._primary.freq:
                raise RuntimeError(
                    f"Primary output frequency {self._primary.freq} is not an integer multiple of "
                    f"secondary {name} output freequency {secondary.freq}"
                )
            if ratio * best_out_div > 128:
                raise RuntimeError(
                    f"Secondary {name} output frequency {secondary.freq} is too far away from "
                    f"primary output frequency {self._primary.freq}, divisor {ratio * best_out_div} > 128"
                )

            secondary_cphase, secondary_fphase = _compute_phase_params(secondary.phase, best_out_div * ratio)

            # Wire up secondary output
            pll_params.update({
                f"o_{name}": ClockSignal(secondary.domain),
                f"a_FREQUENCY_PIN_{name}": f"{secondary.freq / 1e6}",
                f"p_{name}_ENABLE": "ENABLED",
                f"p_{name}_DIV": best_out_div * ratio,
                f"p_{name}_CPHASE": secondary_cphase,
                f"p_{name}_FPHASE": secondary_fphase,
                f"p_{name}_TRIM_DELAY": 0,
                f"p_{name}_TRIM_POL": "FALLING",
            })

        return pll_params
