from amaranth import *
from amaranth.lib import wiring
from amaranth.lib.wiring import In, Out
from amaranth_soc import wishbone, event

from mmu import MMUSignature

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


class W65C816Connector(wiring.Component):
    iface: Out(W65C816BusSignature())

    def elaborate(self, platform):
        m = Module()

        cpu = platform.request('w65c816')
        m.d.comb += [
            self.iface.addr_lo.eq(cpu.addr.i),
            self.iface.addr_hi.eq(cpu.data.i),
            cpu.data.o.eq(self.iface.r_data),
            cpu.data.oe.eq(self.iface.r_data_en),
            self.iface.w_data.eq(cpu.data.i),
            self.iface.rw.eq(cpu.rwb.i),
            self.iface.vda.eq(cpu.vda.i),
            self.iface.vpa.eq(cpu.vpa.i),
            self.iface.vpb.eq(cpu.vpb.i),
            cpu.irq.o.eq(self.iface.irq),
            cpu.nmi.o.eq(self.iface.nmi),
            cpu.abort.o.eq(self.iface.abort),
        ]

        return m


class PMCSignature(wiring.Signature):
    def __init__(self):
        super().__init__({
            'clks': Out(32),
            'insns': Out(32),
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
    irq: In(event.Source().signature)
    mmu: In(MMUSignature())
    pmc: Out(PMCSignature())


    def elaborate(self, platform):
        m = Module()

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
            return int((ns * platform.target_clk_frequency) / 1000000000)

        # Note: times of less than 15ns or so need 1 FPGA clock cycle,
        # so they don't have associated counters, and instead just an
        # intermediate state. This affects:
        # - the time we drive the data bus after the clock goes low,
        # - the time we wait before driving the clock high.

        clks_latch_addr = ns_to_cycles(tADS - tDHR)
        latch_addr_ctr = Signal(range(clks_latch_addr + 1))
        print(f'Will latch address after {clks_latch_addr} clocks')

        clks_w_data_valid = ns_to_cycles(tMDS)
        w_data_valid_ctr = Signal(range(clks_w_data_valid + 1))
        print(f'Will wait for w_data for {clks_w_data_valid} clocks')

        clks_wait_high = ns_to_cycles(tPWH - tMDS)
        wait_high_ctr = Signal(range(clks_wait_high + 1))
        print(f'Will wait high for {clks_wait_high} clocks')

        clks_rst_low = ns_to_cycles(tPWL)
        rst_low_ctr = Signal(range(clks_rst_low + 1))
        print(f'Will hold clock during reset low for {clks_rst_low} clocks')

        clks_rst_high = ns_to_cycles(tPWH)
        rst_high_ctr = Signal(range(clks_rst_high + 1))
        print(f'Will hold clock during reset high for {clks_rst_high} clocks')

        m.d.comb += self.cpu.nmi.eq(~self.mmu.abort)
        m.d.comb += self.cpu.irq.eq(~self.irq.i)
        m.d.comb += self.cpu.abort.eq(~self.mmu.abort)

        # TODO(qookie):
        m.d.comb += self.mmu.user.eq(0)

        # Since our data bus is only 8 bits wide, SEL_O is just always 1.
        m.d.comb += self.wb_bus.sel.eq(1)
        # Since we only perform one bus cycle per CPU cycle, CYC_O and
        # STB_O are always the same.
        m.d.comb += self.wb_bus.stb.eq(self.wb_bus.cyc)

        clk_ctr = Signal(32)
        insn_ctr = Signal(32)

        m.d.comb += [
            self.pmc.clks.eq(clk_ctr),
            self.pmc.insns.eq(insn_ctr),
        ]

        with m.FSM():
            with m.State('rst-clk-low'):
                m.d.sync += [
                    self.cpu.rst.eq(0),
                    self.cpu.clk.eq(0),
                    rst_low_ctr.eq(rst_low_ctr + 1)
                ]
                with m.If(rst_low_ctr == clks_rst_low):
                    m.next = 'rst-clk-high'
            with m.State('rst-clk-high'):
                m.d.sync += [
                    self.cpu.clk.eq(1),
                    rst_high_ctr.eq(rst_high_ctr + 1)
                ]
                with m.If(rst_high_ctr == clks_rst_high):
                    m.next = 'clk-falling-edge'
                    m.d.sync += self.cpu.rst.eq(1)
            with m.State('clk-falling-edge'):
                m.d.sync += [
                    self.cpu.clk.eq(0),
                    clk_ctr.eq(clk_ctr + 1)
                ]
                m.next = 'clear-r_data_en'
            with m.State('clear-r_data_en'):
                m.d.sync += [
                    self.cpu.r_data_en.eq(0),
                    latch_addr_ctr.eq(0)
                ]
                m.next = 'latch-address'
            with m.State('latch-address'):
                m.d.sync += latch_addr_ctr.eq(latch_addr_ctr + 1)
                with m.If(latch_addr_ctr == clks_latch_addr):
                    m.d.sync += [
                        self.mmu.vaddr.eq(Cat(self.cpu.addr_lo, self.cpu.addr_hi)),
                        self.mmu.write.eq(~self.cpu.rw),
                        self.mmu.ifetch.eq(self.cpu.vpa),
                    ]
                    with m.If(self.cpu.vpa & self.cpu.vda):
                        m.d.sync += insn_ctr.eq(insn_ctr + 1)
                    m.next = 'mmu-stb-hi'
            with m.State('mmu-stb-hi'):
                m.d.sync += self.mmu.stb.eq(self.cpu.vda | self.cpu.vpa)
                m.next = 'mmu-stb-lo'
            with m.State('mmu-stb-lo'):
                m.d.sync += self.mmu.stb.eq(0)
                m.next = 'clk-rising-edge'
            with m.State('clk-rising-edge'):
                m.d.sync += [
                    self.cpu.clk.eq(1),
                    w_data_valid_ctr.eq(0)
                ]
                m.next = 'initiate-transaction'
            with m.State('initiate-transaction'):
                m.d.sync += w_data_valid_ctr.eq(w_data_valid_ctr + 1)
                with m.If(w_data_valid_ctr == clks_w_data_valid):
                    # XXX: Is this right?
                    m.d.sync += [
                        self.wb_bus.adr.eq(self.mmu.paddr),
                        self.wb_bus.cyc.eq((self.cpu.vda | self.cpu.vpa) & self.cpu.abort),
                        self.wb_bus.we.eq(~self.cpu.rw),
                        self.wb_bus.dat_w.eq(self.cpu.w_data),
                        wait_high_ctr.eq(0)
                    ]
                    m.next = 'complete-transaction'
            with m.State('complete-transaction'):
                m.d.sync += wait_high_ctr.eq(wait_high_ctr + 1)
                with m.If(~self.wb_bus.cyc): # No-op cycle
                    m.next = 'wait-high'

                    m.d.sync += self.debug_trigger.eq(1)
                with m.Elif(self.wb_bus.ack): # Access complete
                    m.next = 'wait-high'

                    m.d.sync += self.wb_bus.cyc.eq(0)
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
                m.d.sync += wait_high_ctr.eq(wait_high_ctr + 1)
                # Wait for some time before taking the clock low.
                m.d.sync += self.debug_trigger.eq(0)
                with m.If(wait_high_ctr >= clks_wait_high):
                    m.next = 'clk-falling-edge'

        return m
