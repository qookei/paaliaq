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
    debug_trigger: Out(1)

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

        # Times in nanoseconds
        tDHR = 10 # From falling edge, read hold time
        tADS = 40 # From falling edge to when full address is available
        tMDS = 40 # From rising edge to when data bus has write data

        tPWL = 63 # Min time for clock to be low
        tPWH = 63 # Min time for clock to be high

        assert tDHR + tADS <= tPWL, "Min clock low time too short"

        def ns_to_cycles(ns):
            return (ns * platform.default_clk_frequency) // 1000000000

        clks_hold_r_data = ns_to_cycles(tDHR)
        clks_latch_addr = ns_to_cycles(tADS - tDHR)
        clks_w_data_valid = ns_to_cycles(tMDS)
        clks_wait_high = ns_to_cycles(tPWH - tMDS)
        clks_rst_low = ns_to_cycles(tPWL)
        clks_rst_high = ns_to_cycles(tPWH)

        max_clks = max(clks_hold_r_data,
                       clks_latch_addr,
                       clks_w_data_valid,
                       clks_wait_high,
                       clks_rst_low,
                       clks_rst_high)

        ctr = Signal(range(max_clks + 1))

        if True:
            delay_clks = int(platform.default_clk_frequency // 16)
            delay_timer = Signal(range(delay_clks + 1))

            with m.If(delay_timer == delay_clks):
                m.d.sync += delay_timer.eq(0)
                m.d.sync += ctr.eq(ctr + 1)
            with m.Else():
                m.d.sync += delay_timer.eq(delay_timer + 1)
        else:
            m.d.sync += ctr.eq(ctr + 1)

        addr_latch = Signal(24)

        # Since our data bus is only 8 bits wide, SEL_O is just always 1.
        m.d.comb += self.wb_bus.sel.eq(1)

        with m.FSM():
            with m.State('rst-clk-low'):
                m.d.sync += [
                    self.cpu.rst.eq(0),
                    self.cpu.clk.eq(0),
                ]
                with m.If(ctr == clks_rst_low):
                    m.next = 'rst-clk-high'
                    m.d.sync += ctr.eq(0)
            with m.State('rst-clk-high'):
                m.d.sync += [
                    self.cpu.clk.eq(1),
                ]
                with m.If(ctr == clks_rst_high):
                    m.next = 'clk-falling-edge'
                    m.d.sync += self.cpu.rst.eq(1)
            with m.State('clk-falling-edge'):
                m.d.sync += [
                    self.cpu.clk.eq(0),
                    ctr.eq(0)
                ]
                m.next = 'clear-r_data_en'
            with m.State('clear-r_data_en'):
                with m.If(ctr == clks_hold_r_data):
                    m.d.sync += [
                        self.cpu.r_data_en.eq(0),
                        ctr.eq(0)
                    ]
                    m.next = 'latch-address'
            with m.State('latch-address'):
                with m.If(ctr == clks_latch_addr):
                    m.d.sync += addr_latch.eq(Cat(self.cpu.addr_lo, self.cpu.addr_hi))
                    m.next = 'clk-rising-edge'
            with m.State('clk-rising-edge'):
                m.d.sync += [
                    self.cpu.clk.eq(1),
                    ctr.eq(0)
                ]
                m.next = 'initiate-transaction'
            with m.State('initiate-transaction'):
                with m.If(ctr == clks_w_data_valid):
                    # XXX: Is this right?
                    m.d.sync += [
                        self.wb_bus.adr.eq(addr_latch),
                        self.wb_bus.cyc.eq(self.cpu.vda | self.cpu.vpa),
                        self.wb_bus.stb.eq(self.cpu.vda | self.cpu.vpa),
                        self.wb_bus.we.eq(~self.cpu.rw),
                        self.wb_bus.dat_w.eq(self.cpu.w_data),
                        ctr.eq(0)
                    ]
                    m.next = 'complete-transaction'
            with m.State('complete-transaction'):
                with m.If(~self.wb_bus.cyc): # No-op cycle
                    m.d.sync += ctr.eq(0)
                    m.next = 'wait-high'

                    m.d.sync += self.debug_trigger.eq(1)
                with m.Elif(self.wb_bus.ack): # Access complete
                    m.d.sync += ctr.eq(0)
                    m.next = 'wait-high'

                    m.d.sync += [
                        self.wb_bus.cyc.eq(0),
                        self.wb_bus.stb.eq(0),
                    ]
                    m.d.sync += self.debug_trigger.eq(1)

                    with m.If(self.cpu.rw):
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
                    pass
            with m.State('wait-high'):
                # Wait for some time before taking the clock low.
                m.d.sync += self.debug_trigger.eq(0)
                with m.If(ctr == clks_wait_high):
                    m.next = 'clk-falling-edge'

        return m
