import pytest
import random

from paaliaq.test import *
from paaliaq.hdmi import *


class TMDSModel:
    def __init__(self):
        self.balance = 0

    def encode(self, d, c, de):
        if not de:
            self.balance = 0
            return TMDS_CONTROL_SYMBOLS[c], 0

        def n1(v): return v.bit_count()
        def n0(v): return 8 - v.bit_count()

        xnor = n1(d) > 4 or (n1(d) == 4 and (d & 1) == 0)

        q_m = [d & 1] + [0] * 7
        for i in range(1, 8):
            q_m[i] = q_m[i - 1] ^ ((d >> i) & 1) ^ xnor

        q_m8 = 0 if xnor else 1
        q_m07 = 0
        for i, b in enumerate(q_m):
            q_m07 |= b << i

        cnt = self.balance

        if cnt == 0 or n1(q_m07) == n0(q_m07):
            out9 = 1 ^ q_m8
            out8 = q_m8
            if q_m8:
                out07 = q_m07
                cnt = cnt + n1(q_m07) - n0(q_m07)
            else:
                out07 = q_m07 ^ 0xFF
                cnt = cnt + n0(q_m07) - n1(q_m07)
        elif (cnt > 0 and n1(q_m07) > n0(q_m07)) or (cnt < 0 and n0(q_m07) > n1(q_m07)):
            out9 = 1
            out8 = q_m8
            out07 = q_m07 ^ 0xFF
            cnt = cnt + 2 * q_m8 + n0(q_m07) - n1(q_m07)
        else:
            out9 = 0
            out8 = q_m8
            out07 = q_m07
            cnt = cnt - 2 * (1 - q_m8) + n1(q_m07) - n0(q_m07)

        out = (out9 << 9) | (out8 << 8) | out07
        self.balance = cnt

        return out, self.balance


class TestTMDSEncoder:
    def test_random_stream(self):
        dut = TMDSEncoder()
        sim = prepare_sim(dut, timeout=20480)

        @sim.add_testbench
        async def tb(ctx):
            ctx.set(dut.active, 1)

            balance = 0
            model = TMDSModel()
            for _ in range(1024):
                d_in = random.randrange(0, 256)
                ctx.set(dut.data_in, d_in)
                await ctx.tick()
                d_out = ctx.get(dut.data_out)
                b_out = ctx.get(dut.balance_out)

                # Make sure we don't produce a control symbol by accident.
                assert d_out not in TMDS_CONTROL_SYMBOLS

                # Compare our result against a reference model.
                d_ref, b_ref = model.encode(d_in, 0, True)
                assert d_out == d_ref, "Symbols produced by encoder and model don't match"
                assert b_out == b_ref, "Balances computed by encoder and model don't match"

                # Compute the balance from the actual symbols
                one_count = d_out.bit_count()
                zero_count = 10 - one_count
                balance += one_count - zero_count

            # Absolute worst balance can be either +8 or -8. This can occur if the current balance
            # is 0, and the next symbol is all 0s or all 1s after the XORs/XNORs. The balance cannot
            # become worse than that, as the symbol will get inverted and bring the balance closer
            # to 0, even if it was another extreme one.
            assert balance in range(-8, 8+1)

        run_sim(sim)
