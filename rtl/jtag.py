from amaranth import *
from amaranth.lib import wiring, cdc
from amaranth.lib.fifo import AsyncFIFOBuffered
from amaranth.lib.wiring import In, Out
from amaranth_soc import wishbone


# Based (loosely) on the implementations from LiteX and Hazard3:
# https://github.com/enjoy-digital/litex/blob/master/litex/soc/cores/jtag.py
# https://github.com/Wren6991/Hazard3/blob/stable/hdl/debug/dtm/hazard3_ecp5_jtag_dtm.v
#
# Uses the same hack as the Hazard3 impl, where all the logic is done
# on (or near) TCK negedge by inverting TCK.  To account for JTDO{1,2}
# being registered on TCK negedge, we have the first data bit ready
# after JCE{1,2} goes high (=> in Capture-DR state). To account for
# TDI being registered, we also do shifting in Update-DR, and instead
# use the negative edge of Update-DR to trigger a FIFO write.
#
# The interface this component provides is simple: two FIFOs buffering
# the incoming and outgoing data, with ER2 being the dedicated input
# register, and ER1 being the dedicated output register.
class JTAGG(wiring.Component):
    tx_data: In(8)
    tx_rdy: Out(1)
    tx_stb: In(1)

    rx_data: Out(8)
    rx_rdy: Out(1)
    rx_stb: In(1)

    def elaborate(self, platform):
        m = Module()

        tck = Signal()

        tdo = Signal()
        tdi = Signal()

        jce1, jce1_d = Signal(), Signal()
        jce2, jce2_d = Signal(), Signal()
        shift, update = Signal(), Signal()

        capture1 = jce1 & ~jce1_d
        capture2 = jce2 & ~jce2_d

        m.d.jtag += jce1_d.eq(jce1)
        m.d.jtag += jce2_d.eq(jce2)

        m.submodules.jtagg = jtagg = Instance(
            "JTAGG",
            o_JTCK=tck,
            i_JTDO1=tdo,
            i_JTDO2=tdo,
            o_JTDI=tdi,
            o_JSHIFT=shift,
            o_JUPDATE=update,
            o_JCE1=jce1,
            o_JCE2=jce2,
        )

        cd_jtag = ClockDomain("jtag", local=True)
        m.domains += cd_jtag

        m.d.comb += cd_jtag.clk.eq(~tck)
        m.submodules += cdc.ResetSynchronizer(arst=ResetSignal(), domain="jtag")

        m.submodules.tx_fifo = tx_fifo = AsyncFIFOBuffered(
            width=8,
            depth=16,
            r_domain="jtag",
            w_domain="sync")

        m.d.comb += [
            tx_fifo.w_data.eq(self.tx_data),
            tx_fifo.w_en.eq(self.tx_stb),
            self.tx_rdy.eq(tx_fifo.w_rdy),
        ]

        m.submodules.rx_fifo = rx_fifo = AsyncFIFOBuffered(
            width=8,
            depth=16,
            w_domain="jtag",
            r_domain="sync")

        m.d.comb += [
            self.rx_data.eq(rx_fifo.r_data),
            rx_fifo.r_en.eq(self.rx_stb),
            self.rx_rdy.eq(rx_fifo.r_rdy),
        ]

        sel = Signal()

        data_sr = Signal(8)

        with m.If(capture1):
            m.d.jtag += data_sr.eq(Mux(tx_fifo.r_rdy, tx_fifo.r_data, 0xFF))
            m.d.jtag += tx_fifo.r_en.eq(1)
            m.d.jtag += sel.eq(0)
        with m.Else():
            m.d.jtag += tx_fifo.r_en.eq(0)
        with m.If(capture2):
            m.d.jtag += sel.eq(1)

        m.d.comb += tdo.eq(data_sr)
        with m.If(shift | update):
            m.d.jtag += data_sr.eq(Cat(data_sr[1:], tdi))

        update_d = Signal();
        m.d.jtag += update_d.eq(update)
        update_negedge = update_d & ~update
        do_write = Signal()

        with m.If(update_negedge & sel):
            m.d.jtag += rx_fifo.w_data.eq(data_sr)
            m.d.jtag += rx_fifo.w_en.eq(1)
        with m.Else():
            m.d.jtag += rx_fifo.w_en.eq(0)

        return m


# A JTAG debug probe providing remote access to the system bus. Has a
# relatively simple interface:
#
# Host always sends 5 bytes: command, 24 bit address, write data.
# Target always responds with 1 byte: read data.
#
# For reads, write data is ignored, for writes, read data has an
# unspecified value. All accesses have their associated side effects.
class JTAGDebugProbe(wiring.Component):
    wb_bus: Out(wishbone.Signature(addr_width=24, data_width=8))

    def elaborate(self, platform):
        m = Module()

        m.submodules.jtagg = jtagg = JTAGG()

        # Since our data bus is only 8 bits wide, SEL_O is just always 1.
        m.d.comb += self.wb_bus.sel.eq(1)
        # Bus is held only for the duration of the command.
        m.d.comb += self.wb_bus.stb.eq(self.wb_bus.cyc)

        cmd = Signal(8)
        addr = Signal(24)
        r_data, w_data = Signal(8), Signal(8)

        m.d.sync += jtagg.tx_stb.eq(0)
        m.d.sync += jtagg.rx_stb.eq(0)

        with m.FSM():
            def rx_state(state, to_state, dest):
                with m.State(state):
                    with m.If(jtagg.rx_rdy):
                        m.d.sync += [
                            dest.eq(jtagg.rx_data),
                            jtagg.rx_stb.eq(1),
                        ]
                        m.next = state + "-clr-stb"
                with m.State(state + "-clr-stb"):
                    m.next = to_state

            rx_state("recv-cmd", "recv-addr0", cmd)
            rx_state("recv-addr0", "recv-addr1", addr.bit_select(0, 8))
            rx_state("recv-addr1", "recv-addr2", addr.bit_select(8, 8))
            rx_state("recv-addr2", "recv-w-data", addr.bit_select(16, 8))
            rx_state("recv-w-data", "transaction", w_data)

            with m.State("transaction"):
                with m.If(~self.wb_bus.cyc):
                    # Not yet started.
                    m.d.sync += [
                        self.wb_bus.adr.eq(addr),
                        self.wb_bus.dat_w.eq(w_data),
                        self.wb_bus.cyc.eq(1),
                        self.wb_bus.we.eq(cmd == ord('w')),
                    ]
                with m.Elif(self.wb_bus.ack):
                    # Completed.
                    m.d.sync += [
                        self.wb_bus.cyc.eq(0),
                        r_data.eq(self.wb_bus.dat_r),
                    ]
                    m.next = "send-r-data"

            with m.State("send-r-data"):
                with m.If(jtagg.tx_rdy):
                    m.d.sync += [
                        jtagg.tx_data.eq(r_data),
                        jtagg.tx_stb.eq(1),
                    ]
                    m.next = "recv-cmd"

        return m
