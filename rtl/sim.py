from amaranth import *
from amaranth.lib import wiring
from amaranth.lib.wiring import In, Out

from top import TopLevel
from probe import W65C816DebugProbe
from sdram import SDRAMSignature


class SimTopLevel(wiring.Component):
    tx: Out(1)
    sdram: Out(SDRAMSignature())
    sdram_clk: Out(1)

    def elaborate(self, platform):
        m = Module()

        m.submodules.top = top = TopLevel(target_clk=115200 * 10)

        #m.submodules.probe = probe = W65C816DebugProbe(top.cpu_bridge)
        #m.d.comb += self.tx.eq(probe.tx)
        m.d.comb += self.tx.eq(top.tx)
        m.d.comb += top.rx.eq(1)

        m.d.comb += [
            self.sdram.ba.eq(top.sdram.ba),
            self.sdram.a.eq(top.sdram.a),
            self.sdram.dq_o.eq(top.sdram.dq_o),
            top.sdram.dq_i.eq(self.sdram.dq_i),
            self.sdram.we.eq(~top.sdram.we),
            self.sdram.ras.eq(~top.sdram.ras),
            self.sdram.cas.eq(~top.sdram.cas),
            self.sdram_clk.eq(~ClockSignal("sync")),
        ]


        return m


if __name__ == '__main__':
    from amaranth.back import verilog

    class SimPlatform:
        target_clk_frequency = 115200 * 10

    with open("sim_top.v", "w") as f:
        top = SimTopLevel()
        f.write(verilog.convert(top, platform=SimPlatform(), ports=[
            top.tx,
            top.sdram_clk,
            top.sdram.ba,
            top.sdram.a,
            top.sdram.dq_i,
            top.sdram.dq_o,
            top.sdram.we,
            top.sdram.ras,
            top.sdram.cas,
        ]))
