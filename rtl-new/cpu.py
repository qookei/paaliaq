from amaranth import *
from amaranth.lib import wiring
from amaranth.lib.wiring import In, Out
from amaranth_soc import wishbone


class W65C816BusSignature(wiring.Signature):
    def __init__(self):
        super().__init__({
            # TODO(qookie): We probably should instead create a new
            # ClockDomain?
            'clk': In(1),
            'rst': In(1),
            # Address bus. (addr_hi is only valid during a part of the
            # clock cycle, and might be the same as w_data)
            'addr_lo': Out(16),
            'addr_hi': Out(8),
            # Data bus.
            'r_data': In(8),
            'r_data_en': In(1),
            'w_data': Out(8),
            # Bus control lines.
            'rw': Out(1),
            'vda': Out(1),
            'vpa': Out(1),
            'vpb': Out(1),
            'mlb': Out(1),
            # Other control lines.
            'irq': In(1),
            'nmi': In(1),
            'abort': In(1),
        })


class P65C816SoftCore(wiring.Component):
    iface: Out(W65C816BusSignature())

    def elaborate(self, platform):
        m = Module()

        m.submodules.cpu = Instance(
            'P65C816',
            ("i", "CLK", ~self.iface.clk),
            ("i", "RST_N", self.iface.rst),
            ("i", "CE", C(1)),
            ("i", "RDY_IN", C(1)),
            ("i", "NMI_N", self.iface.nmi),
            ("i", "IRQ_N", self.iface.irq),
            ("i", "ABORT_N", self.iface.abort),
            ("i", "D_IN", self.iface.r_data),
            ("o", "D_OUT", self.iface.w_data),
            ("o", "A_OUT", Cat(self.iface.addr_lo, self.iface.addr_hi)),
            ("o", "WE", self.iface.rw),
            ("o", "VPA", self.iface.vpa),
            ("o", "VDA", self.iface.vda),
            ("o", "VPB", self.iface.vpb),
            ("o", "MLB", self.iface.mlb),
        )

        return m


class W65C816WishboneBridge(wiring.Component):
    cpu: In(W65C816BusSignature())
    wb_bus: Out(wishbone.Signature(addr_width=24, data_width=8))

    def elaborate(self, platform):
        m = Module()

        m.d.comb += self.cpu.nmi.eq(1)
        m.d.comb += self.cpu.irq.eq(1)
        m.d.comb += self.cpu.abort.eq(1)

        #     1   2  3       4    5         1
        #     |   |  |       |    |         |
        # ____                ______________
        #     \______________/              \____
        # 1) We bring the CPU clock down, after which, if the CPU is reading, it will
        #    look the data bus for the read result.
        # 2) After a bit, we let go of the data bus if we're outputting anything.
        #    This is needed because in a moment the CPU will output the bank address
        #    on the data bus.
        # 3) The CPU outputs the bank address on the data bus. Additionally, the rest
        #    of the address, and RWB/VDA/VPA/VP are all valid at this point.
        # -) Between 3 and 4, we need to perform address translation with the MMU, to
        #    figure out the state for ABORT.
        #    Address translation may take more than we have time (at 8MHz), in which
        #    case we delay the entry to state 4, stretching the clock.
        # 4) We bring the CPU clock up, after which the CPU will probe ABORT.
        # -) After point 4, we can initiate a read transaction if the CPU is reading.
        #    We need to wait for a minimum amount of cycles, after which we stretch
        #    the clock until it completes before going back to point 1.
        # 5) If writing, the CPU outputs the write data on the data bus at this point.
        #    We can initiate the write transaction here.
        #    In theory, we could let the write transaction run until point 4 of the
        #    next clock cycle before we have to block (and even longer if the next
        #    cycle is a no-op [VDA=VPA=0]), but for simplicity, the read & write paths
        #    will converge on blocking before point 1 is reached.
        # Timings for the various points (at 8MHz @ 3.3V):
        #  1 -> 2) tDHW & tDHR: min 10 ns (upper bound up to 1 -> 3 time)
        #  1 -> 3) tADS & tBAS: max 40 ns
        # 4? -> 5) tMDS: max 40 ns

        half_freq = int(platform.default_clk_frequency // 64)
        timer = Signal(range(half_freq + 1))

        ctr = Signal(8)

        with m.If(timer == half_freq):
            m.d.sync += timer.eq(0)
            m.d.sync += ctr.eq(ctr + 1)
        with m.Else():
            m.d.sync += timer.eq(timer + 1)
        #m.d.sync += self.ctr.eq(self.ctr + 1)


        addr_latch = Signal(24)


        # TODO: Replace uses of ctr with discrete states

        CTR_T2_AT = 2
        CTR_T3_AT = 6

        CTR_T5_AT = 4
        CTR_T6_AT = 8
        # Since our data bus is only 8 bits wide, SEL_O is just always 1.
        m.d.comb += self.wb_bus.sel.eq(1)

        with m.FSM():
            with m.State('T1'):
                m.d.sync += [
                    self.cpu.clk.eq(0),
                    ctr.eq(0)
                ]
                m.next = 'T2'
            with m.State('T2'):
                with m.If(ctr < CTR_T2_AT):
                    m.next = 'T2'
                with m.Else():
                    m.d.sync += self.cpu.r_data_en.eq(0)
                    m.next = 'T3'
            with m.State('T3'):
                with m.If(ctr < CTR_T3_AT):
                    m.next = 'T3'
                with m.Else():
                    m.d.sync += addr_latch.eq(
                        (self.cpu.addr_hi << 16) | self.cpu.addr_lo
                    )
                    m.next = 'T4'
            with m.State('T4'):
                m.d.sync += [
                    self.cpu.clk.eq(1),
                    ctr.eq(0)
                ]
                m.next = 'T5'
            with m.State('T5'):
                with m.If(ctr < CTR_T5_AT):
                    m.next = 'T5'
                with m.Else():
                    # XXX: Is this right?
                    m.d.sync += [
                        self.wb_bus.adr.eq(addr_latch),
                        self.wb_bus.cyc.eq(self.cpu.vda | self.cpu.vpa),
                        self.wb_bus.stb.eq(self.cpu.vda | self.cpu.vpa),
                        self.wb_bus.we.eq(~self.cpu.rw),
                        self.wb_bus.dat_w.eq(self.cpu.w_data),
                    ]
                    m.next = 'T6'
            with m.State('T6'):
                # Not in diagram above, here we wait until either the transaction completes
                # (and set the data bus output for reads), or we wait for the minimum amount
                # of cycles to pass.
                m.d.sync += [
                    self.cpu.rst.eq(1)
                ]
                m.next = 'T1'
                with m.If(ctr < CTR_T6_AT):
                    m.next = 'T6'
                with m.Elif(~self.wb_bus.cyc | ~self.cpu.rst): # No-op cycle
                    m.next = 'T1'
                with m.Elif(self.wb_bus.ack): # Access complete
                    m.next = 'T1'

                    m.d.sync += [
                        self.wb_bus.cyc.eq(0),
                        self.wb_bus.stb.eq(0),
                    ]

                    with m.If(self.cpu.rw): # XXX: One cycle may not be enough setup time
                        m.d.sync += [
                            self.cpu.r_data.eq(self.wb_bus.dat_r),
                            self.cpu.r_data_en.eq(1)
                        ]
                with m.Else():
                    # Access still in progress
                    # FIXME: Add a timeout? If no one responds to our bus transaction,
                    # we get stuck here...

                    # Bug amaranth-lang/amaranth-soc#38 talks about
                    # making the Wishbone decoder assert ERR for
                    # unmapped addresses...
                    m.next = 'T1'

        return m
