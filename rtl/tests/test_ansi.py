import pytest

from paaliaq.test import *
from paaliaq.video import *


class TestAnsiEscapeProcessor:
    def test_sgr_multiple(self):
        dut = TextAnsiEscProcessor()
        sim = prepare_sim(dut)

        @sim.add_testbench
        async def tb_push(ctx):
            seq = "\x1b[38;5;101;48;5;76;9m"
            for c in seq:
                await stream_put(ctx, dut.chars, ord(c))

        @sim.add_testbench
        async def tb_pull(ctx):
            cmd = await stream_get(ctx, dut.commands)
            assert cmd.opcode == Opcode.SET_FG
            assert cmd.params.color == 101

            cmd = await stream_get(ctx, dut.commands)
            assert cmd.opcode == Opcode.SET_BG
            assert cmd.params.color == 76

            cmd = await stream_get(ctx, dut.commands)
            assert cmd.opcode == Opcode.SET_ATTR
            assert cmd.params.attr == Attributes.STRIKE

        run_sim(sim)
