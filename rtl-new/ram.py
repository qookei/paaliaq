from amaranth import *
from amaranth_soc.memory import *
from amaranth_soc.wishbone import *

import math

class RAM(Elaboratable):
    def __init__(self, initial_contents):
        self.data = Memory(width = 8, depth = len(initial_contents),
                           init = initial_contents)
        self.r = self.data.read_port()
        self.w = self.data.write_port()

        self.arb = Arbiter(addr_width=int(math.log2(len(initial_contents))),
                           data_width=8)

    def new_bus(self):
        bus = Interface(addr_width = self.arb.bus.addr_width,
                        data_width = self.arb.bus.data_width,
                        memory_map=MemoryMap(addr_width=self.arb.bus.addr_width, data_width=8))
        self.arb.add(bus)
        return bus

    def elaborate(self, platform):
        m = Module()
        m.submodules.r = self.r
        m.submodules.w = self.w
        m.submodules.arb = self.arb

        # Ack two cycles after activation, for memory port access and
        # synchronous read-out (to prevent combinatorial loops).
        rws = Signal(1, reset = 0)
        m.d.sync += rws.eq(self.arb.bus.cyc)
        m.d.sync += self.arb.bus.ack.eq(self.arb.bus.cyc & rws)
        m.d.comb += [
            # Set the RAM port addresses.
            self.r.addr.eq(self.arb.bus.adr),
            self.w.addr.eq(self.arb.bus.adr),
            self.w.en.eq(self.arb.bus.we & rws)
        ]

        # Read / Write logic: synchronous to avoid combinatorial loops.
        m.d.sync += self.arb.bus.dat_r.eq(self.r.data)
        m.d.comb += self.w.data.eq(self.arb.bus.dat_w)

        return m
