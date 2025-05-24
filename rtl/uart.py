from amaranth import *
from amaranth.lib import wiring
from amaranth.lib.wiring import In, Out
from amaranth.lib.fifo import SyncFIFOBuffered
from amaranth.lib.cdc import FFSynchronizer

from amaranth_soc import csr

from amaranth_stdio import serial


# TODO: Take pins from UARTResource? That way the FFSychronizer stuff
# is done for us by serial.AsyncSerial.
class UARTPeripheral(wiring.Component):
    bus: In(csr.Signature(addr_width=3, data_width=8))

    tx: Out(1)
    rx: In(1)

    class ConfigRegister(csr.Register, access="rw"):
        _unused: csr.Field(csr.action.ResR0WA, 8)

    class StatusRegister(csr.Register, access="rw"):
        _unused: csr.Field(csr.action.ResR0WA, 4)
        rx_overf_err: csr.Field(csr.action.RW1C, 1)
        rx_frame_err: csr.Field(csr.action.RW1C, 1)
        rx_not_empty: csr.Field(csr.action.R, 1)
        tx_not_full:  csr.Field(csr.action.R, 1)


    class TxDataRegister(csr.Register, access="w"):
        data: csr.Field(csr.action.W, 8)

    class RxDataRegister(csr.Register, access="r"):
        data: csr.Field(csr.action.R, 8)


    def __init__(self, *, target_clk, baudrate=115200, tx_fifo_depth=16, rx_fifo_depth=16):
        super().__init__()

        regs = csr.Builder(addr_width=3, data_width=8)

        self._config = regs.add("Config", self.ConfigRegister())
        self._status = regs.add("Status", self.StatusRegister())
        self._tx_data = regs.add("TxData", self.TxDataRegister())
        self._rx_data = regs.add("RxData", self.RxDataRegister())

        mmap = regs.as_memory_map()
        self._bridge = csr.Bridge(mmap)
        self.bus.memory_map = mmap

        self._target_clk = target_clk
        self._baudrate = baudrate
        self._tx_fifo_depth = tx_fifo_depth
        self._rx_fifo_depth = rx_fifo_depth


    def elaborate(self, platform):
        m = Module()

        m.submodules.bridge = self._bridge
        wiring.connect(m, wiring.flipped(self.bus), self._bridge.bus)

        m.submodules.uart_phy = uart_phy = serial.AsyncSerial(
            divisor=int(self._target_clk // self._baudrate),
            data_bits=8, parity=serial.Parity.NONE)

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

        m.submodules += FFSynchronizer(self.rx, uart_phy.rx.i, init=1)
        m.d.comb += self.tx.eq(uart_phy.tx.o)

        m.d.comb += [
            self._status.f.tx_not_full.r_data.eq(tx_fifo.w_rdy),
            self._status.f.rx_not_empty.r_data.eq(rx_fifo.r_rdy),
            self._status.f.rx_frame_err.set.eq(uart_phy.rx.err.frame),
            self._status.f.rx_overf_err.set.eq(uart_phy.rx.err.overflow),
        ]

        with m.If(self._tx_data.f.data.w_stb):
            m.d.sync += [
                tx_fifo.w_data.eq(self._tx_data.f.data.w_data),
                tx_fifo.w_en.eq(1)
            ]
        with m.Else():
            m.d.sync += tx_fifo.w_en.eq(0)

        m.d.comb += [
            self._rx_data.f.data.r_data.eq(rx_fifo.r_data),
            rx_fifo.r_en.eq(self._rx_data.f.data.r_stb)
        ]

        return m
