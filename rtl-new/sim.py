from amaranth import *
from amaranth.lib import wiring
from amaranth.lib.wiring import In, Out

from top import TopLevel
from probe import W65C816DebugProbe


class SimTopLevel(wiring.Component):
    tx: Out(1)

    def elaborate(self, platform):
        m = Module()

        m.submodules.top = top = TopLevel()

        m.submodules.probe = probe = W65C816DebugProbe(top.cpu_bridge)
        m.d.comb += self.tx.eq(probe.tx)

        return m


if __name__ == '__main__':
    from amaranth.back import verilog

    class SimPlatform:
        default_clk_frequency = 115200 * 15

    with open("sim_top.v", "w") as f:
        top = SimTopLevel()
        f.write(verilog.convert(top, platform=SimPlatform(), ports=[
            top.tx
        ]))
