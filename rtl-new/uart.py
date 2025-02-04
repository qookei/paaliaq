from amaranth import *
from amaranth.lib import wiring
from amaranth.lib.wiring import In, Out
from amaranth.lib.fifo import SyncFIFOBuffered

from amaranth_soc import csr

class UARTTransmitter(wiring.Component):
    tx: Out(1)

    w_rdy: Out(1)
    w_en: In(1)
    w_data: In(8)


    def __init__(self, *, baudrate=115200, fifo_depth=8):
        self._tx_fifo = SyncFIFOBuffered(width=8, depth=fifo_depth)
        self.baudrate = baudrate

        super().__init__()

    def elaborate(self, platform):
        m = Module()

        clocks_per_bit = int(platform.default_clk_frequency // self.baudrate)

        tx_timer = Signal(range(clocks_per_bit + 1))
        tx_sr = Signal(8)
        tx_bits = Signal(range(8))

        tx_stb = tx_timer == clocks_per_bit

        with m.If(tx_stb):
            m.d.sync += tx_timer.eq(0)
        with m.Else():
            m.d.sync += tx_timer.eq(tx_timer + 1)

        m.submodules.tx_fifo = self._tx_fifo
        m.d.comb += [
            self._tx_fifo.w_en.eq(self.w_en),
            self.w_rdy.eq(self._tx_fifo.w_rdy),
            self._tx_fifo.w_data.eq(self.w_data),
        ]

        with m.FSM():
            with m.State('idle'):
                m.d.sync += self.tx.eq(1)

                with m.If(tx_stb & self._tx_fifo.r_rdy):
                    m.d.sync += tx_sr.eq(self._tx_fifo.r_data)
                    m.d.sync += self._tx_fifo.r_en.eq(1)
                    m.d.sync += tx_bits.eq(7)
                    m.next = 'start'

            with m.State('start'):
                m.d.sync += self.tx.eq(0)
                m.d.sync += self._tx_fifo.r_en.eq(0)
                with m.If(tx_stb):
                    m.next = 'data'

            with m.State('data'):
                m.d.sync += self.tx.eq(tx_sr.bit_select(0, 1))
                with m.If(tx_stb):
                    m.d.sync += tx_sr.eq(tx_sr >> 1)
                    m.d.sync += tx_bits.eq(tx_bits - 1)
                    with m.If(tx_bits == 0):
                        m.next = 'stop'
                    with m.Else():
                        m.next = 'data'

            with m.State('stop'):
                m.d.sync += self.tx.eq(1)
                with m.If(tx_stb):
                    m.next = 'stop->idle'

            with m.State('stop->idle'):
                m.next = 'idle'

        return m


class UARTPeripheral(wiring.Component):
    bus: In(csr.Signature(addr_width=3, data_width=8))

    tx: Out(1)
    rx: In(1)

    class ConfigRegister(csr.Register, access="rw"):
        _unused: csr.Field(csr.action.ResR0WA, 8)

    class StatusRegister(csr.Register, access="r"):
        tx_not_full:  csr.Field(csr.action.R, 1)
        rx_not_empty: csr.Field(csr.action.R, 1)
        _unused: csr.Field(csr.action.ResR0WA, 6)


    class TxDataRegister(csr.Register, access="w"):
        data: csr.Field(csr.action.W, 8)

    class RxDataRegister(csr.Register, access="r"):
        data: csr.Field(csr.action.R, 8)


    def __init__(self, baudrate=115200, tx_fifo_depth=16):
        regs = csr.Builder(addr_width=3, data_width=8)

        self._config = regs.add("Config", self.ConfigRegister())
        self._status = regs.add("Status", self.StatusRegister())
        self._tx_data = regs.add("TxData", self.TxDataRegister())
        self._rx_data = regs.add("RxData", self.RxDataRegister())

        mmap = regs.as_memory_map()
        self._bridge = csr.Bridge(mmap)

        super().__init__()

        self.bus.memory_map = mmap

        self._baudrate = baudrate
        self._tx_fifo_depth = tx_fifo_depth


    def elaborate(self, platform):
        m = Module()

        m.submodules.bridge = self._bridge
        wiring.connect(m, wiring.flipped(self.bus), self._bridge.bus)

        m.submodules.uart_tx = uart_tx = UARTTransmitter(baudrate=self._baudrate,
                                                         fifo_depth=self._tx_fifo_depth)
        m.d.comb += self.tx.eq(uart_tx.tx)

        m.d.comb += [
            self._status.f.tx_not_full.r_data.eq(uart_tx.w_rdy),
            self._status.f.rx_not_empty.r_data.eq(0)
        ]

        with m.If(self._tx_data.f.data.w_stb):
            m.d.sync += [
                uart_tx.w_data.eq(self._tx_data.f.data.w_data),
                uart_tx.w_en.eq(1)
            ]
        with m.Else():
            m.d.sync += uart_tx.w_en.eq(0)

        return m
