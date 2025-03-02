from amaranth import *
from amaranth.lib import wiring
from amaranth.lib.wiring import In, Out
from amaranth_soc import wishbone
from amaranth_soc.memory import MemoryMap

import math


class SDRAMSignature(wiring.Signature):
    def __init__(self):
        super().__init__({
            'ba':   Out(2),
            'a':    Out(11),
            'dq_i': In(32),
            'dq_o': Out(32),
            'we':   Out(1),
            'ras':  Out(1),
            'cas':  Out(1),
        })


class SDRAMConnector(wiring.Component):
    sdram: In(SDRAMSignature())

    def __init__(self, sdram_domain='sdram'):
        super().__init__()

        self._sdram_domain = sdram_domain


    def elaborate(self, platform):
        m = Module()

        sdram = platform.request('sdram')
        m.d.comb += sdram.clk.o.eq(ClockSignal(self._sdram_domain))

        m.d.comb += [
            sdram.ba.o.eq(self.sdram.ba),
            sdram.a.o.eq(self.sdram.a),
            sdram.dq.oe.eq(self.sdram.we),
            sdram.dq.o.eq(self.sdram.dq_o),
            self.sdram.dq_i.eq(sdram.dq.i),
            sdram.we.o.eq(self.sdram.we),
            sdram.ras.o.eq(self.sdram.ras),
            sdram.cas.o.eq(self.sdram.cas),
        ]

        return m


class SDRAMController(wiring.Component):
    wb_bus: In(wishbone.Signature(addr_width=23, data_width=8))
    sdram: Out(SDRAMSignature())

    def __init__(self):
        super().__init__()

        self.wb_bus.memory_map = MemoryMap(addr_width=23, data_width=8)
        self.wb_bus.memory_map.add_resource(self, name=('mem',), size=(1<<23))
        self.wb_bus.memory_map.freeze()

    def elaborate(self, platform):
        m = Module()

        def noop():
            return [
                self.sdram.ras.eq(0),
                self.sdram.cas.eq(0),
                self.sdram.we.eq(0),
                self.sdram.dq_o.eq(0),
            ]

        def mode_register_set(cas_latency):
            return [
                self.sdram.ras.eq(1),
                self.sdram.cas.eq(1),
                self.sdram.we.eq(1),
                self.sdram.ba.eq(0),
                # Burst length 1, sequential
                self.sdram.a.eq(cas_latency << 4),
            ]

        def precharge_all():
            return [
                self.sdram.ras.eq(1),
                self.sdram.cas.eq(0),
                self.sdram.we.eq(1),
                self.sdram.a.bit_select(10, 1).eq(1),
            ]

        def autorefresh():
            return [
                self.sdram.ras.eq(1),
                self.sdram.cas.eq(1),
                self.sdram.we.eq(0),
            ]

        def activate_row(bank, row):
            return [
                self.sdram.ras.eq(1),
                self.sdram.cas.eq(0),
                self.sdram.we.eq(0),
                self.sdram.ba.eq(bank),
                self.sdram.a.eq(row),
            ]

        def read(bank, column):
            return [
                self.sdram.ras.eq(0),
                self.sdram.cas.eq(1),
                self.sdram.we.eq(0),
                self.sdram.ba.eq(bank),
                self.sdram.a.eq(column),
            ]

        def write(bank, column, data):
            return [
                self.sdram.ras.eq(0),
                self.sdram.cas.eq(1),
                self.sdram.we.eq(1),
                self.sdram.ba.eq(bank),
                self.sdram.dq_o.eq(data),
                self.sdram.a.eq(column),
            ]

        def precharge(bank):
            return [
                self.sdram.ras.eq(1),
                self.sdram.cas.eq(0),
                self.sdram.we.eq(1),
                self.sdram.ba.eq(bank),
                self.sdram.a.eq(0),
            ]

        def ns_to_clks(ns):
            return int(math.ceil(ns * platform.target_clk_frequency / 1000000000))

        init_clks = ns_to_clks(200000)
        init_ctr = Signal(range(init_clks + 1))

        tRP = 15
        precharge_clks = ns_to_clks(tRP) + 1
        precharge_ctr = Signal(range(precharge_clks + 1))

        tRFC = 55
        refresh_clks = ns_to_clks(tRFC)
        refresh_ctr = Signal(range(refresh_clks + 1))
        init_refreshes = Signal(1)

        tRCD = 15
        activate_clks = ns_to_clks(tRCD) + 1
        activate_ctr = Signal(range(activate_clks + 1))

        write_clks = 2 # tRDL
        write_ctr = Signal(range(write_clks + 1))

        cas_clks = 2
        read_ctr = Signal(range(cas_clks + 1))

        tRES = 64000000
        refreshes_per_tRES = 4096
        time_between_refreshes = tRES // refreshes_per_tRES
        refresh_stb_clks = ns_to_clks(time_between_refreshes)
        refresh_stb_ctr = Signal(range(refresh_stb_clks + 1))
        # Currently we can slip by 1 refresh if the time comes during
        # a read/write.  If that happens, we will do one immediately
        # after the operation completes (AIUI the refreshes don't need
        # to happen at exactly when the counter indicates, as long as
        # we manage to do 4096 of them within 64ms).

        # TODO(qookie): Verify that we indeed make it in time?
        # I doubt we miss anything, and even if we slip a bit, the
        # chip in the board I have seems to have some sort of
        # superpower, and retains data for a lot longer than the 64ms
        # refresh cycle time.
        pending_refresh = Signal()

        with m.If(refresh_stb_ctr == refresh_stb_clks):
            m.d.sync += pending_refresh.eq(1)
            m.d.sync += refresh_stb_ctr.eq(0)
        with m.Else():
            m.d.sync += refresh_stb_ctr.eq(refresh_stb_ctr + 1)

        prev_wb_stb = Signal()
        m.d.sync += prev_wb_stb.eq(self.wb_bus.cyc & self.wb_bus.stb)

        trans_pending = Signal()
        with m.If(self.wb_bus.cyc & self.wb_bus.stb & ~prev_wb_stb):
            m.d.sync += trans_pending.eq(1)

        trans_ack = Signal()
        m.d.comb += self.wb_bus.ack.eq(trans_ack & self.wb_bus.stb)

        byte = self.wb_bus.adr.bit_select(0, 2)
        column = self.wb_bus.adr.bit_select(2, 8)
        row = self.wb_bus.adr.bit_select(10, 11)
        bank = self.wb_bus.adr.bit_select(21, 2)

        banks_active = Signal(4)
        current_rows = Array([Signal(8) for _ in range(4)])

        with m.FSM():
            # Initialization states
            with m.State('init-wait'):
                m.d.sync += noop()
                m.d.sync += init_ctr.eq(init_ctr + 1)
                with m.If(init_ctr == init_clks):
                    m.d.sync += precharge_ctr.eq(0)
                    m.d.sync += precharge_all()
                    m.next = 'init-precharge'
            with m.State('init-precharge'):
                m.d.sync += noop()
                m.d.sync += precharge_ctr.eq(precharge_ctr + 1)
                with m.If(precharge_ctr == precharge_clks):
                    m.d.sync += refresh_ctr.eq(0)
                    m.d.sync += autorefresh()
                    m.next = 'init-refresh'
            with m.State('init-refresh'):
                m.d.sync += noop()
                m.d.sync += refresh_ctr.eq(refresh_ctr + 1)
                with m.If(refresh_ctr == refresh_clks):
                    m.d.sync += init_refreshes.eq(init_refreshes + 1)
                    m.d.sync += refresh_ctr.eq(0)
                    m.d.sync += autorefresh()
                    with m.If(init_refreshes == 1):
                        m.d.sync += mode_register_set(cas_latency=cas_clks)
                        m.next = 'init-mode-reg'
            with m.State('init-mode-reg'):
                m.d.sync += noop()
                m.next = 'init-idle-1'
            with m.State('init-idle-1'):
                m.next = 'init-idle-2'
            with m.State('init-idle-2'):
                m.next = 'idle'
            # Main state machine
            with m.State('idle'):
                m.d.sync += trans_ack.eq(0)
                m.d.sync += noop()
                with m.If(pending_refresh):
                    m.d.sync += pending_refresh.eq(0)
                    with m.If(banks_active.any()):
                        # Precharge before refresh if any bank is not idle.
                        m.d.sync += precharge_ctr.eq(0)
                        m.d.sync += precharge_all()
                        m.next = 'precharge-then-refresh'
                    with m.Else():
                        m.d.sync += refresh_ctr.eq(0)
                        m.d.sync += autorefresh()
                        m.next = 'refresh'
                with m.Elif(trans_pending):
                    # The target row is already active in the target bank.
                    with m.If(banks_active.bit_select(bank, 1) & (row == current_rows[bank])):
                        # Go do the read/write immediately.
                        m.d.sync += read_ctr.eq(0)
                        m.d.sync += read(bank, column)
                        with m.If(self.wb_bus.we):
                            m.next = 'read-before-write-data'
                        with m.Else():
                            m.next = 'read-data'
                    # The target bank is idle.
                    with m.Elif(~banks_active.bit_select(bank, 1)):
                        # Activate the row and go do the read/write.
                        m.d.sync += activate_ctr.eq(0)
                        m.d.sync += activate_row(bank, row)
                        m.next = 'activate-row'
                    # The target bank is active but on the wrong row.
                    with m.Else():
                        # Precharge the bank, activate the row, and go do the read/write.
                        m.d.sync += precharge_ctr.eq(0)
                        m.d.sync += precharge(bank)
                        m.next = 'precharge-then-activate'
            with m.State('precharge-then-activate'):
                m.d.sync += noop()
                m.d.sync += precharge_ctr.eq(precharge_ctr + 1)
                with m.If(precharge_ctr == precharge_clks):
                    m.d.sync += banks_active.bit_select(bank, 1).eq(0)
                    m.d.sync += activate_ctr.eq(0)
                    m.d.sync += activate_row(bank, row)
                    m.next = 'activate-row'
            with m.State('activate-row'):
                m.d.sync += noop()
                m.d.sync += activate_ctr.eq(activate_ctr + 1)
                with m.If(activate_ctr == activate_clks):
                    m.d.sync += banks_active.bit_select(bank, 1).eq(1)
                    m.d.sync += current_rows[bank].eq(row)
                    m.d.sync += read_ctr.eq(0)
                    m.d.sync += read(bank, column)
                    with m.If(self.wb_bus.we):
                        m.next = 'read-before-write-data'
                    with m.Else():
                        m.next = 'read-data'
            with m.State('read-data'):
                m.d.sync += noop()
                m.d.sync += read_ctr.eq(read_ctr + 1)
                with m.If(read_ctr == cas_clks):
                    m.d.sync += self.wb_bus.dat_r.eq(self.sdram.dq_i.word_select(byte, 8))
                    m.d.sync += trans_ack.eq(1)
                    m.d.sync += trans_pending.eq(0)
                    m.next = 'idle'
            with m.State('read-before-write-data'):
                m.d.sync += noop()
                m.d.sync += read_ctr.eq(read_ctr + 1)
                with m.If(read_ctr == cas_clks):
                    m.d.sync += write_ctr.eq(0)
                    byte_mask = ~(C(0xFF, 32) << (byte * 8))
                    byte_val  = self.wb_bus.dat_w << (byte * 8)
                    m.d.sync += write(bank, column, (self.sdram.dq_i & byte_mask) | byte_val)
                    m.next = 'write-data'
            with m.State('write-data'):
                m.d.sync += noop()
                m.d.sync += write_ctr.eq(write_ctr + 1)
                with m.If(write_ctr == write_clks):
                    m.d.sync += self.sdram.dq_o.eq(0)
                    m.d.sync += trans_ack.eq(1)
                    m.d.sync += trans_pending.eq(0)
                    m.next = 'idle'
            with m.State('precharge-then-refresh'):
                m.d.sync += noop()
                m.d.sync += precharge_ctr.eq(precharge_ctr + 1)
                with m.If(precharge_ctr == precharge_clks):
                    m.d.sync += banks_active.eq(0)
                    m.d.sync += refresh_ctr.eq(0)
                    m.d.sync += autorefresh()
                    m.next = 'refresh'
            with m.State('refresh'):
                m.d.sync += noop()
                m.d.sync += refresh_ctr.eq(refresh_ctr + 1)
                with m.If(refresh_ctr == refresh_clks):
                    m.next = 'idle'

        return m
