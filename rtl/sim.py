from amaranth import *
from amaranth.lib import wiring
from amaranth.lib.wiring import In, Out

from soc import SoC
from cpu import P65C816SoftCore
from probe import W65C816DebugProbe
from sdram import SDRAMSignature


class TopLevel(wiring.Component):
    tx: Out(1)
    sdram: Out(SDRAMSignature())
    sdram_clk: Out(1)

    def elaborate(self, platform):
        m = Module()

        m.submodules.soc = soc = SoC(target_clk=115200 * 10)

        m.submodules.cpu = cpu = P65C816SoftCore()
        wiring.connect(m, cpu.iface, soc.cpu)

        #m.submodules.probe = probe = W65C816DebugProbe(top.cpu_bridge)
        #m.d.comb += self.tx.eq(probe.tx)
        m.d.comb += self.tx.eq(soc.tx)
        m.d.comb += soc.rx.eq(1)

        m.d.comb += [
            self.sdram.ba.eq(soc.sdram.ba),
            self.sdram.a.eq(soc.sdram.a),
            self.sdram.dq_o.eq(soc.sdram.dq_o),
            soc.sdram.dq_i.eq(self.sdram.dq_i),
            self.sdram.we.eq(~soc.sdram.we),
            self.sdram.ras.eq(~soc.sdram.ras),
            self.sdram.cas.eq(~soc.sdram.cas),
            self.sdram_clk.eq(~ClockSignal("sync")),
        ]


        return m


if __name__ == '__main__':
    from amaranth.back import verilog

    class SimPlatform:
        target_clk_frequency = 115200 * 10

    with open("sim_top.v", "w") as f:
        top = TopLevel()
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
