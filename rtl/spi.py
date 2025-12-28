from amaranth import *
from amaranth.lib import wiring, io, enum, data
from amaranth.lib.fifo import SyncFIFOBuffered
from amaranth.lib.wiring import In, Out
from amaranth_soc import csr


class ECP5USRMCLK(wiring.Component):
    oe: In(1)
    o:  In(1)

    def elaborate(self, platform):
        m = Module()

        m.submodules.usrmclk = usrmclk = Instance(
            "USRMCLK",
            ("i", "USRMCLKI",  self.o),
            ("i", "USRMCLKTS", ~self.oe),
        )

        return m


class Segment(data.Struct):
    class BitWidth(enum.Enum, shape=2):
        X1 = 0
        X2 = 1
        X4 = 2

    class Direction(enum.Enum, shape=2):
        TRANSMIT = 0
        RECEIVE  = 1
        NONE     = 2

    size:      12
    bit_width: BitWidth
    direction: Direction


class SPIController(wiring.Component):
    csr_bus: In(csr.Signature(addr_width=4, data_width=8))


    class ConfigRegister(csr.Register, access="rw"):
        kick: csr.Field(csr.action.RW1S, 1)
        _unused: csr.Field(csr.action.ResR0WA, 7)
        divisor: csr.Field(csr.action.RW, 8)

    class TxDataRegister(csr.Register, access="w"):
        data: csr.Field(csr.action.W, 8)

    class RxDataRegister(csr.Register, access="r"):
        data: csr.Field(csr.action.R, 8)

    class SegmentRegister(csr.Register, access="w"):
        segment: csr.Field(csr.action.W, Segment)


    def __init__(self, *, target_clk):
        super().__init__()

        regs = csr.Builder(addr_width=4, data_width=8)

        self._config = regs.add("Config", self.ConfigRegister())
        self._tx_data = regs.add("TxData", self.TxDataRegister())
        self._rx_data = regs.add("RxData", self.RxDataRegister())
        self._segment = regs.add("Segment", self.SegmentRegister())


        mmap = regs.as_memory_map()
        self._bridge = csr.Bridge(mmap)
        self.csr_bus.memory_map = mmap

        self._target_clk = target_clk


    def elaborate(self, platform):
        m = Module()

        m.submodules.bridge = self._bridge
        wiring.connect(m, wiring.flipped(self.csr_bus), self._bridge.bus)

        spi = platform.request("spi", dir="-")

        m.submodules.cs = cs = io.Buffer("o", spi.cs_n)

        if hasattr(spi, "clk"):
            m.submodules.clk = clk = io.Buffer("o", spi.clk)
        else:
            m.submodules.clk = clk = ECP5USRMCLK()

        m.submodules.dq0 = dq0 = io.Buffer("io", spi.dq0)
        m.submodules.dq1 = dq1 = io.Buffer("io", spi.dq1)
        m.submodules.dq2 = dq2 = io.Buffer("io", spi.dq2)
        m.submodules.dq3 = dq3 = io.Buffer("io", spi.dq3)

        dq_i  = Cat(dq0.i,  dq1.i,  dq2.i,  dq3.i)
        dq_o  = Cat(dq0.o,  dq1.o,  dq2.o,  dq3.o)
        dq_oe = Cat(dq0.oe, dq1.oe, dq2.oe, dq3.oe)

        m.submodules.rx_fifo = rx_fifo = SyncFIFOBuffered(width=8, depth=2048)
        m.submodules.tx_fifo = tx_fifo = SyncFIFOBuffered(width=8, depth=2048)

        m.submodules.segment_fifo = segment_fifo = SyncFIFOBuffered(
            width=Shape.cast(Segment).width,
            depth=8
        )

        cur_segment, next_segment = Signal(Segment), Signal(Segment)
        m.d.comb += next_segment.eq(segment_fifo.r_data)

        m.d.comb += [
            cs.o.eq(1),
            clk.oe.eq(1),
        ]

        out_sr = Signal(8)
        in_sr = Signal(8)

        bits_per_clk = Signal(range(8))
        with m.Switch(cur_segment.bit_width):
            with m.Case(Segment.BitWidth.X1):
                m.d.comb += bits_per_clk.eq(1)
            with m.Case(Segment.BitWidth.X2):
                m.d.comb += bits_per_clk.eq(2)
            with m.Case(Segment.BitWidth.X4):
                m.d.comb += bits_per_clk.eq(4)

        bit_max = 8 - bits_per_clk
        bit_ctr = Signal(range(8))

        half_ctr = Signal(9)
        half_redge = Signal(9)
        half_mid = Signal(9)

        oe_stb, tx_stb, rx_stb, advance_stb = Signal(), Signal(), Signal(), Signal()

        with m.If(oe_stb):
            with m.If(cur_segment.direction == Segment.Direction.TRANSMIT):
                with m.Switch(cur_segment.bit_width):
                    with m.Case(Segment.BitWidth.X1):
                        m.d.sync += dq_oe.eq(0b0001)
                    with m.Case(Segment.BitWidth.X2):
                        m.d.sync += dq_oe.eq(0b0011)
                    with m.Case(Segment.BitWidth.X4):
                        m.d.sync += dq_oe.eq(0b1111)
            with m.Else():
                # Make all IOs tristate when not transmitting.
                # Transfer width doesn't matter since we don't support sending
                # and receiving at once.
                m.d.sync += dq_oe.eq(0b0000)


        with m.If(tx_stb & (cur_segment.direction == Segment.Direction.TRANSMIT)):
            tx_data = Signal(12)
            with m.If(bit_ctr == 0):
                m.d.comb += [
                    tx_data.eq(tx_fifo.r_data),
                    tx_fifo.r_en.eq(1),
                ]
            with m.Else():
                m.d.comb += tx_data.eq(out_sr)

            m.d.sync += Cat(out_sr, dq_o).eq(tx_data << bits_per_clk)


        m.d.comb += rx_fifo.w_data.eq(in_sr)
        m.d.sync += rx_fifo.w_en.eq(0)
        with m.If(rx_stb & (cur_segment.direction == Segment.Direction.RECEIVE)):
            with m.If(bit_ctr == bit_max):
                m.d.sync += rx_fifo.w_en.eq(1)

            with m.Switch(cur_segment.bit_width):
                with m.Case(Segment.BitWidth.X1):
                    m.d.sync += in_sr.eq(Cat(dq1.i, in_sr))
                with m.Case(Segment.BitWidth.X2):
                    m.d.sync += in_sr.eq(Cat(dq_i[:2], in_sr))
                with m.Case(Segment.BitWidth.X4):
                    m.d.sync += in_sr.eq(Cat(dq_i[:4], in_sr))


        with m.If(advance_stb):
            m.d.sync += bit_ctr.eq(bit_ctr + bits_per_clk)

            with m.If(bit_ctr == bit_max):
                m.d.sync += cur_segment.size.eq(cur_segment.size - 1)
                # Segment complete
                with m.If(cur_segment.size == 0):
                    with m.If(~segment_fifo.r_rdy):
                        # No more segments, we're done.
                        m.d.comb += self._config.f.kick.clear.eq(1)
                    with m.Else():
                        # There is a next segment
                        m.d.sync += cur_segment.eq(next_segment)
                        m.d.comb += segment_fifo.r_en.eq(1)


        with m.FSM():
            with m.State("idle"):
                m.d.comb += cs.o.eq(0)

                with m.If(self._config.f.kick.data):
                    with m.If(segment_fifo.r_rdy):
                        m.d.sync += cur_segment.eq(segment_fifo.r_data)
                        m.d.comb += segment_fifo.r_en.eq(1)

                        actual_half = self._config.f.divisor.data + 1

                        m.d.sync += [
                            bit_ctr.eq(0),
                            half_ctr.eq(0),
                            half_redge.eq(actual_half),
                            half_mid.eq(actual_half // 2),
                        ]

                        m.next = "clk=0"
                    with m.Else():
                        m.d.comb += self._config.f.kick.clear.eq(1)

            with m.State("clk=0"):
                m.d.comb += clk.o.eq(0)
                m.d.sync += half_ctr.eq(half_ctr + 1)

                with m.If(~self._config.f.kick.data):
                    with m.If(half_ctr == half_redge):
                        m.d.sync += half_ctr.eq(0)
                        m.next = "idle"
                with m.Else():
                    with m.If(half_ctr == 0):
                        m.d.comb += oe_stb.eq(1)

                    with m.If(half_ctr == half_mid):
                        m.d.comb += tx_stb.eq(1)

                    with m.If(half_ctr == half_redge):
                        m.d.sync += half_ctr.eq(0)
                        m.next = "clk=1"

            with m.State("clk=1"):
                m.d.comb += clk.o.eq(1)
                m.d.sync += half_ctr.eq(half_ctr + 1)

                with m.If(half_ctr == 0):
                    m.d.comb += rx_stb.eq(1)

                with m.If(half_ctr == half_redge):
                    m.d.sync += half_ctr.eq(0)
                    m.d.comb += advance_stb.eq(1)
                    m.next = "clk=0"


        # FIFO CSR interface

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


        with m.If(self._segment.f.segment.w_stb):
            m.d.sync += [
                segment_fifo.w_data.eq(self._segment.f.segment.w_data),
                segment_fifo.w_en.eq(1)
            ]
        with m.Else():
            m.d.sync += segment_fifo.w_en.eq(0)

        return m
