from amaranth import *
from amaranth.lib import wiring
from amaranth.lib.wiring import In, Out
from amaranth.lib.fifo import SyncFIFOBuffered


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
