from amaranth import *
from amaranth_soc.memory import *
from amaranth_soc.wishbone import *

class ExternalRAM(Elaboratable):
    def __init__(self, addr_pins):
        self.ram_addr = Signal(addr_pins)

        self.ram_data_i = Signal(8)
        self.ram_data_o = Signal(8)
        self.ram_data_oe = Signal()

        self.ram_oe = Signal()
        self.ram_we = Signal()
        self.ram_cs = Signal()

        self.arb = Arbiter(addr_width=addr_pins, data_width=8)

    def new_bus(self):
        bus = Interface(addr_width = self.arb.bus.addr_width,
                        data_width = self.arb.bus.data_width,
                        memory_map=MemoryMap(addr_width=self.arb.bus.addr_width, data_width=8))
        self.arb.add(bus)
        return bus

    def elaborate(self, platform):
        m = Module()
        m.submodules += self.arb

        m.d.comb += [
            self.ram_addr.eq(self.arb.bus.adr),

            self.ram_data_o.eq(self.arb.bus.dat_w),
            self.ram_data_oe.eq(self.arb.bus.we),
        ]

        # Once CYC goes high, we need to set CS & OE/WE,
        # then wait a few cycles (to meet external RAM access times),
        # then assert ACK until CYC goes low.

        # 4 cycles is probably overkill? @ 100MHz it's 40ns...
        delay1 = Signal(1, reset = 0)
        delay2 = Signal(1, reset = 0)
        delay3 = Signal(1, reset = 0)

        m.d.sync += [
            delay1.eq(self.arb.bus.cyc),
            delay2.eq(delay1),
            delay3.eq(delay2),
            self.arb.bus.ack.eq(self.arb.bus.cyc & delay3),

            self.ram_cs.eq(~delay1),
            self.ram_oe.eq(~(self.arb.bus.cyc & ~self.arb.bus.we)),
            self.ram_we.eq(~(self.arb.bus.cyc &  self.arb.bus.we))
        ]

        # Once we're sure the input is stable, latch it
        with m.If(delay3 & ~self.arb.bus.we):
            m.d.sync += self.arb.bus.dat_r.eq(self.ram_data_i)

        return m
