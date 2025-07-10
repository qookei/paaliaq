from amaranth import *
from amaranth.lib import wiring
from amaranth.lib.wiring import In, Out
from amaranth_soc import wishbone, event, csr

from mmu import MMUSignature

class W65C816BusSignature(wiring.Signature):
    def __init__(self):
        super().__init__({
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
            ("o", "WE_N", self.iface.rw),
            ("o", "VPA", self.iface.vpa),
            ("o", "VDA", self.iface.vda),
            ("o", "VPB", self.iface.vpb),
            ("o", "MLB", self.iface.mlb),
        )

        return m


class W65C816WishboneBridge(wiring.Component):
    cpu: In(W65C816BusSignature())
    irq: In(event.Source().signature)
    mmu: In(MMUSignature())

    wb_bus: Out(wishbone.Signature(addr_width=24, data_width=8))
    csr_bus: In(csr.Signature(addr_width=5, data_width=8))


    class CounterRegister(csr.Register, access="r"):
        value: csr.Field(csr.action.R, 32)

    class DbgConfigRegister(csr.Register, access="rw"):
        dbg_enable: csr.Field(csr.action.RW1C, 1)
        dbg_en_next_insn: csr.Field(csr.action.RW1S, 1)
        trace_enable: csr.Field(csr.action.RW, 1)
        trace_halted: csr.Field(csr.action.RW1C, 1)
        _unused: csr.Field(csr.action.ResR0WA, 4)

    class InDataRegister(csr.Register, access="w"):
        data: csr.Field(csr.action.W, 8)
    class OutDataRegister(csr.Register, access="r"):
        data: csr.Field(csr.action.R, 8)

    class DbgAddrRegister(csr.Register, access="r"):
        addr: csr.Field(csr.action.R, 24)

    class DbgBusRegister(csr.Register, access="r"):
        vpa: csr.Field(csr.action.R, 1)
        vda: csr.Field(csr.action.R, 1)
        vpb: csr.Field(csr.action.R, 1)
        rwb: csr.Field(csr.action.R, 1)
        _unused: csr.Field(csr.action.ResR0WA, 4)


    def __init__(self, *, target_clk):
        super().__init__()
        self._target_clk = target_clk

        regs = csr.Builder(addr_width=5, data_width=8)

        self._clks = regs.add("Clks", self.CounterRegister())
        self._insns = regs.add("Insns", self.CounterRegister())
        self._dbg_config = regs.add("DbgConfig", self.DbgConfigRegister())
        self._dbg_bus = regs.add("DbgBus", self.DbgBusRegister())
        self._dbg_rdata = regs.add("DbgRData", self.InDataRegister())
        self._dbg_vaddr = regs.add("DbgVAddr", self.DbgAddrRegister())
        self._dbg_wdata = regs.add("DbgWData", self.OutDataRegister())
        self._dbg_trace_rdata = regs.add("DbgTrcRData", self.OutDataRegister())
        self._dbg_paddr = regs.add("DbgPAddr", self.DbgAddrRegister())

        mmap = regs.as_memory_map()
        self._bridge = csr.Bridge(mmap)
        self.csr_bus.memory_map = mmap


    def elaborate(self, platform):
        m = Module()

        m.submodules.bridge = self._bridge
        wiring.connect(m, wiring.flipped(self.csr_bus), self._bridge.bus)

        #     1   2  3     4 5    6         1
        #     |   |  |     | |    |         |
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
        # 4) At this point we wait for any ongoing write transaction to complete.
        # 5) We bring the CPU clock up, after which the CPU will probe ABORT.
        # -) After point 5, we initiate a read transaction if the CPU is reading.
        #    We need to wait for a minimum amount of cycles, after which we stretch
        #    the clock until it completes before going back to point 1.
        # 5) If writing, the CPU outputs the write data on the data bus at this point.
        #    We initiate the write transaction here.
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
            return int((ns * self._target_clk) / 1000000000)

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

        clks_wait_noop = ns_to_cycles(tPWH)
        wait_noop_ctr = Signal(range(clks_wait_noop + 1))
        print(f'No-op cycles will wait for {clks_wait_noop} clocks')

        clks_wait_read = ns_to_cycles(tPWH)
        wait_read_ctr = Signal(range(clks_wait_read + 1))
        print(f'Read cycles will wait for {clks_wait_read} clocks')

        clks_wait_write = ns_to_cycles(tPWH - tMDS)
        wait_write_ctr = Signal(range(clks_wait_write + 1))
        print(f'Write cycles will wait for {clks_wait_write} clocks')

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
            self._clks.f.value.r_data.eq(clk_ctr),
            self._insns.f.value.r_data.eq(insn_ctr),
        ]

        read_in_progress = Signal()
        write_in_progress = Signal()

        dbg_en = self._dbg_config.f.dbg_enable.data
        trace_en = self._dbg_config.f.trace_enable.data
        trace_halted = self._dbg_config.f.trace_halted.data

        dbg_this_cycle = Signal()

        with m.If(self.wb_bus.cyc & self.wb_bus.ack):
            m.d.sync += [
                read_in_progress.eq(0),
                write_in_progress.eq(0),
                self.wb_bus.cyc.eq(0),
            ]
            with m.If(read_in_progress):
                m.d.sync += [
                    self.cpu.r_data.eq(self.wb_bus.dat_r),
                    self.cpu.r_data_en.eq(1),
                    self._dbg_trace_rdata.f.data.r_data.eq(self.wb_bus.dat_r),
                ]

        with m.If(dbg_this_cycle & self._dbg_rdata.f.data.w_stb):
            m.d.sync += [
                read_in_progress.eq(0),
                self.cpu.r_data.eq(self._dbg_rdata.f.data.w_data),
                self.cpu.r_data_en.eq(1),
            ]

        with m.If(dbg_this_cycle & self._dbg_wdata.f.data.r_stb):
            m.d.sync += write_in_progress.eq(0)

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
                        self._dbg_vaddr.f.addr.r_data.eq(Cat(self.cpu.addr_lo, self.cpu.addr_hi)),
                        self._dbg_bus.f.vpa.r_data.eq(self.cpu.vpa),
                        self._dbg_bus.f.vda.r_data.eq(self.cpu.vda),
                        self._dbg_bus.f.vpb.r_data.eq(self.cpu.vpb),
                        self._dbg_bus.f.rwb.r_data.eq(self.cpu.rw),

                        self.mmu.vaddr.eq(Cat(self.cpu.addr_lo, self.cpu.addr_hi)),
                        self.mmu.write.eq(~self.cpu.rw),
                        self.mmu.ifetch.eq(self.cpu.vpa),
                    ]
                    with m.If(self.cpu.vpa & self.cpu.vda):
                        m.d.sync += insn_ctr.eq(insn_ctr + 1)
                        with m.If(self._dbg_config.f.dbg_en_next_insn.data):
                            m.d.comb += [
                                self._dbg_config.f.dbg_enable.set.eq(1),
                                self._dbg_config.f.dbg_en_next_insn.clear.eq(1),
                            ]
                    m.next = 'mmu-stb-hi'
            with m.State('mmu-stb-hi'):
                m.d.sync += self.mmu.stb.eq(self.cpu.vda | self.cpu.vpa)
                m.next = 'mmu-stb-lo'
            with m.State('mmu-stb-lo'):
                m.d.sync += self.mmu.stb.eq(0)

                with m.If(write_in_progress):
                    m.next = 'mmu-stb-lo'
                with m.Else():
                    m.d.comb += self._dbg_config.f.trace_halted.set.eq(1)
                    m.next = 'clk-rising-edge'
            with m.State('clk-rising-edge'):
                m.d.sync += [
                    self.cpu.clk.eq(1),
                    self.wb_bus.adr.eq(self.mmu.paddr),
                    self._dbg_paddr.f.addr.r_data.eq(self.mmu.paddr),
                    dbg_this_cycle.eq(dbg_en),
                ]
                with m.If(trace_en & trace_halted):
                    pass
                with m.Elif(~((self.cpu.vda | self.cpu.vpa) & self.cpu.abort)):
                    m.d.sync += wait_noop_ctr.eq(0)
                    m.next = 'noop-cycle'
                with m.Elif(self.cpu.rw):
                    m.next = 'initiate-read'
                with m.Else():
                    m.d.sync += w_data_valid_ctr.eq(0)
                    m.next = 'initiate-write'

            with m.State('noop-cycle'):
                m.d.sync += wait_noop_ctr.eq(wait_noop_ctr + 1)
                with m.If(wait_noop_ctr == clks_wait_noop):
                    m.next = 'clk-falling-edge'

            with m.State('initiate-read'):
                m.d.sync += [
                    wait_read_ctr.eq(0),
                    read_in_progress.eq(1),
                    self.wb_bus.cyc.eq(~dbg_en),
                    self.wb_bus.we.eq(0),
                ]
                m.next = 'complete-read'
            with m.State('complete-read'):
                with m.If(wait_read_ctr != clks_wait_read):
                    m.d.sync += wait_read_ctr.eq(wait_read_ctr + 1)
                with m.Elif(~read_in_progress):
                    m.next = 'clk-falling-edge'

            with m.State('initiate-write'):
                with m.If(w_data_valid_ctr != clks_w_data_valid):
                    m.d.sync += w_data_valid_ctr.eq(w_data_valid_ctr + 1)
                with m.Elif(w_data_valid_ctr == clks_w_data_valid):
                    m.d.sync += [
                        write_in_progress.eq(1),
                        wait_write_ctr.eq(0),
                        self.wb_bus.cyc.eq(~dbg_en),
                        self.wb_bus.we.eq(1),
                        self.wb_bus.dat_w.eq(self.cpu.w_data),
                        self._dbg_wdata.f.data.r_data.eq(self.cpu.w_data),
                    ]
                    m.next = 'complete-write'
            with m.State('complete-write'):
                m.d.sync += wait_write_ctr.eq(wait_write_ctr + 1)
                with m.If(wait_write_ctr == clks_wait_write):
                    m.next = 'clk-falling-edge'

        return m
