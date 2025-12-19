from amaranth import *
from amaranth.lib import wiring, io
from amaranth.lib.wiring import In, Out
from amaranth_soc import wishbone
from amaranth_soc.memory import MemoryMap

import math


class SDRAMSignature(wiring.Signature):
    def __init__(self):
        super().__init__({
            'ba':   Out(2),
            'a':    Out(13),
            'dq_i': In(16),
            'dq_o': Out(16),
            'dqm':  Out(2),
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

        sdram = platform.request("sdram", dir="-")

        m.submodules.clk = clk = io.DDRBuffer("o", sdram.clk)
        m.submodules.cke = cke = io.Buffer("o", sdram.clk_en)
        m.submodules.ba = ba = io.Buffer("o", sdram.ba)
        m.submodules.a = a = io.Buffer("o", sdram.a)
        m.submodules.dq = dq = io.Buffer("io", sdram.dq)
        m.submodules.dqm = dqm = io.Buffer("o", sdram.dqm)
        m.submodules.we = we = io.Buffer("o", sdram.we)
        m.submodules.ras = ras = io.Buffer("o", sdram.ras)
        m.submodules.cas = cas = io.Buffer("o", sdram.cas)

        m.d.comb += [
            clk.o[0].eq(0),
            clk.o[1].eq(1),
            cke.o.eq(1),
            ba.o.eq(self.sdram.ba),
            a.o.eq(self.sdram.a),
            dq.oe.eq(self.sdram.we),
            dq.o.eq(self.sdram.dq_o),
            dqm.o.eq(self.sdram.dqm),
            self.sdram.dq_i.eq(dq.i),
            we.o.eq(self.sdram.we),
            ras.o.eq(self.sdram.ras),
            cas.o.eq(self.sdram.cas),
        ]

        return m


class SDRAMController(wiring.Component):
    wb_bus: In(wishbone.Signature(addr_width=23, data_width=8))
    sdram: Out(SDRAMSignature())

    def __init__(self, *, target_clk):
        super().__init__()

        self._target_clk = target_clk
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

        def write(bank, column, data, sel):
            return [
                self.sdram.ras.eq(0),
                self.sdram.cas.eq(1),
                self.sdram.we.eq(1),
                self.sdram.ba.eq(bank),
                self.sdram.dq_o.eq(data),
                self.sdram.dqm.eq(~sel),
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
            return int(math.ceil(ns * self._target_clk / 1000000000))

        init_clks = ns_to_clks(200000)
        init_ctr = Signal(range(init_clks + 1))

        precharge_clks = 3 # tRP
        precharge_ctr = Signal(range(precharge_clks + 1))

        refresh_clks = 10 # tRFC
        refresh_ctr = Signal(range(refresh_clks + 1))
        init_refreshes = Signal(1)

        activate_clks = 3 # tRCD
        activate_ctr = Signal(range(activate_clks + 1))

        write_clks = 2 # tDPL
        write_ctr = Signal(range(write_clks + 1))

        cas_clks = 3 if self._target_clk > 100e6 else 2
        read_ctr = Signal(range(cas_clks + 1))

        tRES = 64000000
        refreshes_per_tRES = 8192
        time_between_refreshes = tRES // refreshes_per_tRES
        refresh_stb_clks = ns_to_clks(time_between_refreshes)
        refresh_stb_ctr = Signal(range(refresh_stb_clks + 1))
        # Currently we can slip by 1 refresh if the time comes during
        # a read/write.  If that happens, we will do one immediately
        # after the operation completes.

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

        byte = self.wb_bus.adr.bit_select(0, 1)
        column = self.wb_bus.adr.bit_select(1, 9)
        row = self.wb_bus.adr.bit_select(10, 12)
        bank = self.wb_bus.adr.bit_select(22, 2)

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
                m.d.sync += self.sdram.dqm.eq(0)
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
                        with m.If(self.wb_bus.we):
                            m.d.sync += write_ctr.eq(0)
                            byte_val  = self.wb_bus.dat_w << (byte * 8)
                            m.d.sync += write(bank, column, byte_val, 1 << byte)
                            m.next = 'write-data'
                        with m.Else():
                            m.d.sync += read_ctr.eq(0)
                            m.d.sync += read(bank, column)
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
                    with m.If(self.wb_bus.we):
                        m.d.sync += write_ctr.eq(0)
                        byte_val  = self.wb_bus.dat_w << (byte * 8)
                        m.d.sync += write(bank, column, byte_val, 1 << byte)
                        m.next = 'write-data'
                    with m.Else():
                        m.d.sync += read_ctr.eq(0)
                        m.d.sync += read(bank, column)
                        m.next = 'read-data'
            with m.State('read-data'):
                m.d.sync += noop()
                m.d.sync += read_ctr.eq(read_ctr + 1)
                with m.If(read_ctr == cas_clks):
                    m.d.sync += self.wb_bus.dat_r.eq(self.sdram.dq_i.word_select(byte, 8))
                    m.d.sync += trans_ack.eq(1)
                    m.d.sync += trans_pending.eq(0)
                    m.next = 'idle'
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
