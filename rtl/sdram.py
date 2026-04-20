from amaranth import *
from amaranth.lib import wiring, io, enum, data
from amaranth.lib.fifo import SyncFIFO, SyncFIFOBuffered
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

        m.submodules.clk = clk = io.DDRBuffer("o", sdram.clk, o_domain="sdram")
        m.submodules.cke = cke = io.FFBuffer("o", sdram.clk_en)
        m.submodules.cs = cs = io.FFBuffer("o", sdram.cs)
        m.submodules.ba = ba = io.FFBuffer("o", sdram.ba)
        m.submodules.a = a = io.FFBuffer("o", sdram.a)
        m.submodules.dq = dq = io.FFBuffer("io", sdram.dq)
        m.submodules.dqm = dqm = io.FFBuffer("o", sdram.dqm)
        m.submodules.we = we = io.FFBuffer("o", sdram.we)
        m.submodules.ras = ras = io.FFBuffer("o", sdram.ras)
        m.submodules.cas = cas = io.FFBuffer("o", sdram.cas)

        m.d.comb += [
            clk.o[0].eq(1),
            clk.o[1].eq(0),
            cke.o.eq(1),
            cs.o.eq(1),
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


class Command(enum.Enum, shape=3):
    NOOP           = 0
    MRS            = 1
    ACTIVATE       = 2
    PRECHARGE_BANK = 3
    PRECHARGE_ALL  = 4
    READ           = 5
    WRITE          = 6
    REFRESH        = 7


class Transaction(data.Struct):
    write:  1
    bank:   2
    row:    13
    column: 9


class SDRAMController(wiring.Component):
    wb_bus: In(wishbone.Signature(addr_width=23, data_width=8))

    def __init__(self, *, target_clk):
        super().__init__()

        self._target_clk = target_clk
        self.wb_bus.memory_map = MemoryMap(addr_width=23, data_width=8)
        self.wb_bus.memory_map.add_resource(self, name=('mem',), size=(1<<23))
        self.wb_bus.memory_map.freeze()

    def elaborate(self, platform):
        m = Module()

        m.submodules.sdram_io = sdram_io = platform.get_sdram_ios()
        sdram_io = sdram_io.sdram

        # Command driver
        # --------------

        bank, address = Signal(2), Signal(13)

        cmd_bits = Cat(sdram_io.ras, sdram_io.cas, sdram_io.we)
        current_cmd = Signal(Command)
        m.d.comb += current_cmd.eq(Command.NOOP)

        with m.Switch(current_cmd):
            with m.Case(Command.NOOP):
                m.d.sync += cmd_bits.eq(0b000)
            with m.Case(Command.MRS):
                m.d.sync += [
                    cmd_bits.eq(0b111),
                    sdram_io.a.eq(address),
                ]
            with m.Case(Command.ACTIVATE):
                m.d.sync += [
                    cmd_bits.eq(0b001),
                    sdram_io.a.eq(address),
                    sdram_io.ba.eq(bank),
                ]
            with m.Case(Command.PRECHARGE_BANK):
                m.d.sync += [
                    cmd_bits.eq(0b101),
                    sdram_io.ba.eq(bank),
                ]
            with m.Case(Command.PRECHARGE_ALL):
                m.d.sync += [
                    cmd_bits.eq(0b101),
                    sdram_io.a.eq(1 << 10),
                ]
            with m.Case(Command.READ):
                m.d.sync += [
                    cmd_bits.eq(0b010),
                    sdram_io.a.eq(address),
                    sdram_io.ba.eq(bank),
                ]
            with m.Case(Command.WRITE):
                m.d.sync += [
                    cmd_bits.eq(0b110),
                    sdram_io.a.eq(address),
                    sdram_io.ba.eq(bank),
                ]
            with m.Case(Command.REFRESH):
                m.d.sync += cmd_bits.eq(0b011)

        m.submodules.tx_fifo = tx_fifo = SyncFIFOBuffered(width=Shape.cast(Transaction).width, depth=4)
        m.submodules.in_fifo = in_fifo = SyncFIFO(width=16, depth=32)
        m.submodules.out_fifo = out_fifo = SyncFIFO(width=16, depth=32)

        # Memory controller
        # -----------------

        cur_tx, next_tx = Signal(Transaction), Signal(Transaction)
        m.d.comb += next_tx.eq(tx_fifo.r_data)


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
        read_ctr = Signal(range(cas_clks + 2))

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

        burst_size = 1
        word_ctr = Signal(3)
        in_stb, out_stb = Signal(), Signal()

        m.d.sync += in_fifo.w_en.eq(0)
        m.d.sync += in_stb.eq(0)
        with m.If(in_stb):
            m.d.sync += [
                in_fifo.w_data.eq(sdram_io.dq_i),
                in_fifo.w_en.eq(1),
            ]

        m.d.sync += out_fifo.r_en.eq(0)
        with m.If(out_stb):
            m.d.sync += [
                sdram_io.dq_o.eq(out_fifo.r_data),
                out_fifo.r_en.eq(1),
            ]

        banks_active = Signal(4)
        current_rows = Array([Signal(9) for _ in range(4)])

        with m.FSM():
            with m.State("init-wait"):
                m.d.sync += init_ctr.eq(init_ctr + 1)
                with m.If(init_ctr == init_clks):
                    m.next = "init-precharge"

            with m.State("init-precharge"):
                m.d.comb += current_cmd.eq(Command.PRECHARGE_ALL)
                m.d.sync += precharge_ctr.eq(0)
                m.next = "init-wait-precharge"
            with m.State("init-wait-precharge"):
                m.d.sync += precharge_ctr.eq(precharge_ctr + 1)
                with m.If(precharge_ctr == precharge_clks):
                    m.next = "init-refresh"

            with m.State("init-refresh"):
                m.d.comb += current_cmd.eq(Command.REFRESH)
                m.d.sync += refresh_ctr.eq(0)
                m.next = "init-wait-refresh"
            with m.State("init-wait-refresh"):
                m.d.sync += refresh_ctr.eq(refresh_ctr + 1)
                with m.If(refresh_ctr == refresh_clks):
                    m.d.sync += init_refreshes.eq(init_refreshes + 1)
                    with m.If(init_refreshes == 1):
                        m.next = "init-mrs"
                    with m.Else():
                        m.next = "init-refresh"

            with m.State("init-mrs"):
                m.d.comb += [
                    current_cmd.eq(Command.MRS),
                    address.eq(cas_clks << 4),
                ]
                m.next = "init-mrs-idle-1"
            with m.State("init-mrs-idle-1"):
                m.next = "init-mrs-idle-2"
            with m.State("init-mrs-idle-2"):
                m.d.sync += pending_refresh.eq(0)
                m.next = "idle"

            with m.State("idle"):
                with m.If(pending_refresh):
                    m.d.sync += pending_refresh.eq(0)

                    with m.If(banks_active):
                        m.d.sync += banks_active.eq(0)
                        m.next = "refresh-precharge"
                    with m.Else():
                        m.next = "refresh"
                with m.Elif(tx_fifo.r_rdy):
                    m.d.sync += cur_tx.eq(next_tx)
                    m.d.comb += tx_fifo.r_en.eq(1)

                    m.d.sync += [
                        banks_active.bit_select(next_tx.bank, 1).eq(1),
                        current_rows[next_tx.bank].eq(next_tx.row),
                        word_ctr.eq(0),
                        read_ctr.eq(0),
                        write_ctr.eq(0),
                    ]

                    with m.If(banks_active.bit_select(next_tx.bank, 1)):
                        with m.If(next_tx.row == current_rows[next_tx.bank]):
                            # Target bank has the desired row already open.
                            # Read/write immediately.
                            with m.If(next_tx.write):
                                m.next = "write"
                            with m.Else():
                                m.next = "read"
                        with m.Else():
                            # Target bank has the wrong row open.
                            # Precharge, the activate, then read/write.
                            m.next = "precharge"
                    with m.Else():
                        # Target bank is idle.
                        # Activate, then read/write.
                        m.next = "activate"

            with m.State("precharge"):
                m.d.comb += [
                    current_cmd.eq(Command.PRECHARGE_BANK),
                    bank.eq(cur_tx.bank),
                ]
                m.d.sync += precharge_ctr.eq(0)
                m.next = "precharge-wait"
            with m.State("precharge-wait"):
                m.d.sync += precharge_ctr.eq(precharge_ctr + 1)
                with m.If(precharge_ctr == precharge_clks):
                    m.next = "activate"

            with m.State("activate"):
                m.d.comb += [
                    current_cmd.eq(Command.ACTIVATE),
                    bank.eq(cur_tx.bank),
                    address.eq(cur_tx.row),
                ]
                m.d.sync += activate_ctr.eq(0)
                m.next = "activate-wait"
            with m.State("activate-wait"):
                m.d.sync += activate_ctr.eq(activate_ctr + 1)
                with m.If(activate_ctr == activate_clks):
                    with m.If(next_tx.write):
                        m.next = "write"
                    with m.Else():
                        m.next = "read"

            with m.State("write"):
                with m.If(word_ctr == 0):
                    m.d.comb += [
                        current_cmd.eq(Command.WRITE),
                        bank.eq(cur_tx.bank),
                        address.eq(cur_tx.column),
                    ]

                m.d.comb += out_stb.eq(1)
                m.d.sync += word_ctr.eq(word_ctr + 1)
                with m.If(word_ctr == burst_size - 1):
                    m.next = "write-wait"
            with m.State("write-wait"):
                m.d.sync += write_ctr.eq(write_ctr + 1)
                with m.If(write_ctr == write_clks):
                    m.next = "idle"

            with m.State("read"):
                with m.If(read_ctr == 0):
                    m.d.comb += [
                        current_cmd.eq(Command.READ),
                        bank.eq(cur_tx.bank),
                        address.eq(cur_tx.column),
                    ]

                m.d.sync += read_ctr.eq(read_ctr + 1)
                with m.If(read_ctr == cas_clks + 1):
                    m.next = "read-data"
            with m.State("read-data"):
                m.d.sync += in_stb.eq(1)
                m.d.sync += word_ctr.eq(word_ctr + 1)
                with m.If(word_ctr == burst_size - 1):
                    m.next = "idle"

            with m.State("refresh-precharge"):
                m.d.comb += current_cmd.eq(Command.PRECHARGE_ALL)
                m.d.sync += precharge_ctr.eq(0)
                m.next = "refresh-precharge-wait"
            with m.State("refresh-precharge-wait"):
                m.d.sync += precharge_ctr.eq(precharge_ctr + 1)
                with m.If(precharge_ctr == precharge_clks):
                    m.next = "refresh"

            with m.State("refresh"):
                m.d.comb += current_cmd.eq(Command.REFRESH)
                m.d.sync += refresh_ctr.eq(0)
                m.next = "refresh-wait"
            with m.State("refresh-wait"):
                m.d.sync += refresh_ctr.eq(refresh_ctr + 1)
                with m.If(refresh_ctr == refresh_clks):
                    m.next = "idle"

        # Wishbone interface
        # ------------------

        with m.FSM():
            with m.State("idle"):
                with m.If(self.wb_bus.cyc & self.wb_bus.stb & self.wb_bus.sel):
                    column = self.wb_bus.adr.bit_select(0, 9)
                    bank = self.wb_bus.adr.bit_select(9, 2)
                    row = self.wb_bus.adr.bit_select(11, 12)

                    new_tx = Signal(Transaction)

                    m.d.comb += [
                        new_tx.write.eq(self.wb_bus.we),
                        new_tx.column.eq(column),
                        new_tx.bank.eq(bank),
                        new_tx.row.eq(row),
                        tx_fifo.w_data.eq(new_tx),
                        tx_fifo.w_en.eq(1),
                    ]

                    with m.If(self.wb_bus.we):
                        m.d.comb += [
                            out_fifo.w_data.eq(self.wb_bus.dat_w),
                            out_fifo.w_en.eq(1),
                        ]
                        m.next = "write"
                    with m.Else():
                        m.next = "read"

            with m.State("read"):
                with m.If(in_fifo.r_rdy):
                    m.d.comb += in_fifo.r_en.eq(1)
                    m.d.sync += [
                        self.wb_bus.dat_r.eq(in_fifo.r_data),
                        self.wb_bus.ack.eq(1),
                    ]
                    m.next = "complete"

            with m.State("write"):
                with m.If(out_fifo.w_level == 0):
                    m.d.sync += self.wb_bus.ack.eq(1)
                    m.next = "complete"

            with m.State("complete"):
                m.d.sync += self.wb_bus.ack.eq(0)
                m.next = "idle"

        return m
