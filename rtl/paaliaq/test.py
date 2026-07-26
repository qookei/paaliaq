# Test utilities

import inspect

from amaranth.sim import Simulator


class TimeoutError(RuntimeError):
    pass


async def stream_get(ctx, stream):
    ctx.set(stream.ready, 1)
    payload, = await ctx.tick().sample(stream.payload).until(stream.valid)
    ctx.set(stream.ready, 0)
    return payload


async def stream_put(ctx, stream, payload):
    ctx.set(stream.valid, 1)
    ctx.set(stream.payload, payload)
    await ctx.tick().until(stream.ready)
    ctx.set(stream.valid, 0)


def timeout_process(ticks):
    async def inner(ctx):
        await ctx.tick().repeat(ticks)
        raise TimeoutError("Simulation timed out")

    return inner


def prepare_sim(dut, timeout=100, period=1e-6):
    sim = Simulator(dut)
    sim.add_clock(1e-6)
    sim.add_process(timeout_process(timeout))

    return sim


def run_sim(sim, test_name=None):
    if not test_name:
        test_name = inspect.stack()[1].function

    try:
        sim.run()
    except:
        sim.reset()
        with sim.write_vcd(f"fail-{test_name}.vcd"):
            sim.run()
