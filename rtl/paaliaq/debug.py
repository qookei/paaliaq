from amaranth import *
from amaranth.lib import wiring, cdc, stream
from amaranth.lib.fifo import SyncFIFOBuffered
from amaranth.lib.wiring import In, Out
from amaranth_soc import wishbone
from amaranth_stdio import serial


class UARTDebugPhy(wiring.Component):
    req_stream: Out(stream.Signature(8))
    resp_stream: In(stream.Signature(8))

    def __init__(self, *, baudrate=115200, tx_fifo_depth=16, rx_fifo_depth=16):
        super().__init__()

        self._baudrate = baudrate
        self._tx_fifo_depth = tx_fifo_depth
        self._rx_fifo_depth = rx_fifo_depth

    def elaborate(self, platform):
        m = Module()

        m.submodules.uart_phy = uart_phy = serial.AsyncSerial(
            divisor=int(platform.soc_clk // self._baudrate),
            data_bits=8, parity=serial.Parity.NONE,
            pins=platform.get_debug_uart())

        m.submodules.rx_fifo = rx_fifo = SyncFIFOBuffered(width=8, depth=self._rx_fifo_depth)
        m.submodules.tx_fifo = tx_fifo = SyncFIFOBuffered(width=8, depth=self._tx_fifo_depth)

        m.d.comb += [
            uart_phy.tx.data.eq(tx_fifo.r_data),
            uart_phy.tx.ack.eq(uart_phy.tx.rdy & tx_fifo.r_rdy),
        ]
        m.d.sync += tx_fifo.r_en.eq(uart_phy.tx.ack)

        m.d.comb += [
            uart_phy.rx.ack.eq(rx_fifo.w_rdy),
            rx_fifo.w_data.eq(uart_phy.rx.data),
        ]
        m.d.sync += rx_fifo.w_en.eq(uart_phy.rx.rdy)

        wiring.connect(m, wiring.flipped(self.req_stream),  rx_fifo.r_stream)
        wiring.connect(m, wiring.flipped(self.resp_stream), tx_fifo.w_stream)

        return m


# TODO: This is a copy of the JTAGDebugProbe.
# Ideally, I'd get rid of this code duplication.

# An UART debug bridge providing remote access to the system bus. Has
# a relatively simple interface:
#
# Host always sends 5 bytes: command, 24 bit address, write data.
# Target always responds with 1 byte: read data.
#
# For reads, write data is ignored, for writes, read data has an
# unspecified value. All accesses have their associated side effects.
class UARTDebugBridge(wiring.Component):
    wb_bus: Out(wishbone.Signature(addr_width=24, data_width=8))

    def elaborate(self, platform):
        m = Module()

        m.submodules.phy = phy = UARTDebugPhy()

        # Since our data bus is only 8 bits wide, SEL_O is just always 1.
        m.d.comb += self.wb_bus.sel.eq(1)
        # Bus is held only for the duration of the command.
        m.d.comb += self.wb_bus.stb.eq(self.wb_bus.cyc)

        cmd = Signal(8)
        addr = Signal(24)
        r_data, w_data = Signal(8), Signal(8)

        with m.FSM():
            def rx_state(state, to_state, dest):
                with m.State(state):
                    m.d.comb += phy.req_stream.ready.eq(1)

                    with m.If(phy.req_stream.ready & phy.req_stream.valid):
                        m.d.sync += dest.eq(phy.req_stream.payload)
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
                m.d.comb += phy.resp_stream.valid.eq(1)
                m.d.comb += phy.resp_stream.payload.eq(r_data)

                with m.If(phy.resp_stream.ready & phy.resp_stream.valid):
                    m.next = "recv-cmd"

        return m
