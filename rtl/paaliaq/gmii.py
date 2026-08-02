from amaranth import *
from amaranth.lib import wiring, io, memory, data, stream
from amaranth.lib.crc.catalog import CRC32_ETHERNET
from amaranth.lib.wiring import In, Out
from amaranth_soc import csr
from amaranth_soc.memory import MemoryMap


class FramedByte(data.Struct):
    value: 8
    error: 1
    last: 1


class GMIITx(wiring.Component):
    data: In(stream.Signature(FramedByte))

    def __init__(self, gmii):
        super().__init__()
        self.gmii = gmii

    def elaborate(self, platform):
        m = Module()

        m.submodules.tx_en = tx_en = io.FFBuffer("o", self.gmii.tx_en)
        m.submodules.tx_er = tx_er = io.FFBuffer("o", self.gmii.tx_er)
        m.submodules.txd   = txd   = io.FFBuffer("o", self.gmii.txd)

        m.d.comb += [
            tx_en.o.eq(0),
            tx_er.o.eq(0),
            txd.o.eq(0),
        ]

        pre_ctr = Signal(range(8))
        crc_ctr = Signal(range(4))
        ipg_ctr = Signal(range(12))

        m.submodules.crc = crc = CRC32_ETHERNET().create()

        with m.FSM():
            with m.State("idle"):
                with m.If(self.data.valid):
                    m.d.sync += pre_ctr.eq(0)
                    m.next = "tx-preamble"
            with m.State("tx-preamble"):
                m.d.comb += [
                    tx_en.o.eq(1),
                    tx_er.o.eq(0),
                    txd.o.eq(Mux(pre_ctr == 7, 0xD5, 0x55)),
                ]
                m.d.sync += pre_ctr.eq(pre_ctr + 1)
                with m.If(pre_ctr == 7):
                    m.d.comb += crc.start.eq(1)
                    m.next = "tx-data"
            with m.State("tx-data"):
                # TODO: We need self.data.valid to be 1 all throughout here.
                # Currently we just assume...
                m.d.comb += [
                    # Stream control
                    self.data.ready.eq(1),
                    # GMII interface control
                    tx_en.o.eq(1),
                    tx_er.o.eq(~self.data.valid | self.data.payload.error),
                    txd.o.eq(self.data.payload.value),
                    # CRC32 processor control
                    crc.valid.eq(1),
                    crc.data.eq(self.data.payload.value),
                ]
                with m.If(self.data.payload.last):
                    m.d.sync += crc_ctr.eq(0)
                    m.next = "tx-crc"
            with m.State("tx-crc"):
                m.d.comb += [
                    tx_en.o.eq(1),
                    tx_er.o.eq(0),
                    txd.o.eq(crc.crc.word_select(crc_ctr, 8)),
                ]
                m.d.sync += crc_ctr.eq(crc_ctr + 1)
                with m.If(crc_ctr == 3):
                    m.d.sync += ipg_ctr.eq(0)
                    m.next = "ipg"
            with m.State("ipg"):
                m.d.sync += ipg_ctr.eq(ipg_ctr + 1)
                with m.If(ipg_ctr == 11):
                    m.next = "idle"

        return m


class GMIIRx(wiring.Component):
    data: Out(stream.Signature(FramedByte))

    def __init__(self, gmii):
        super().__init__()
        self.gmii = gmii

    def elaborate(self, platform):
        m = Module()

        m.submodules.rx_dv = rx_dv = io.FFBuffer("i", self.gmii.rx_dv)
        m.submodules.rx_er = rx_er = io.FFBuffer("i", self.gmii.rx_er)
        m.submodules.rxd   = rxd   = io.FFBuffer("i", self.gmii.rxd)

        rx_dv_q, rx_er_q, rxd_q = Signal(), Signal(), Signal(8)
        m.d.sync += [
            rx_dv_q.eq(rx_dv.i),
            rx_er_q.eq(rx_er.i),
            rxd_q.eq(rxd.i),
        ]

        with m.If(self.data.valid & self.data.ready):
            m.d.sync += self.data.valid.eq(0)

        with m.If(rx_dv_q):
            m.d.sync += self.data.valid.eq(1)
            with m.If(~self.data.valid | self.data.ready):
                m.d.sync += self.data.payload.value.eq(rxd_q)
                m.d.sync += self.data.payload.error.eq(rx_er_q)
                m.d.sync += self.data.payload.last.eq(rx_dv_q & ~rx_dv.i)

        return m


class GMIITxDemo(wiring.Component):
    data: Out(stream.Signature(FramedByte))

    def elaborate(self, platform):
        m = Module()

        data = [
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x12, 0x34,
            0x56, 0x78, 0xAB, 0xCD, 0xAA, 0xAA, 0x41, 0x42,
            0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A,
            0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x50, 0x51, 0x52,
            0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A,
            0x5B, 0x5C, 0x5D, 0x5E, 0x5F, 0x60, 0x61, 0x62,
            0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A,
            0x6B, 0x6C, 0x6D, 0x6E,
        ]

        ctr = Signal(range(len(data)))
        arr = Array(data)

        last = ctr == len(data) - 1
        m.d.comb += [
            self.data.valid.eq(1),
            self.data.payload.value.eq(arr[ctr]),
            self.data.payload.error.eq(0),
            self.data.payload.last.eq(last),
        ]

        with m.If(self.data.ready):
            m.d.sync += ctr.eq(Mux(last, 0, ctr + 1))

        return m


class GMIICRG(Elaboratable):
    def __init__(self, gmii):
        super().__init__()
        self.gmii = gmii

    def elaborate(self, platform):
        m = Module()

        # Hold PHY reset inactive.
        m.submodules.phyrst = phyrst = io.Buffer("o", self.gmii.phyrst)
        m.d.comb += phyrst.o.eq(0)

        # Here we assume that both RX and TX delays are enabled on the PHY side.
        # Thanks to this, we can assume RX data is center aligned, and we can
        # send TX data edge aligned, and the delay will align it to meet setup time.
        m.submodules.rx_clk = rx_clk = io.Buffer("i", self.gmii.rx_clk)
        m.submodules.tx_clk = tx_clk = io.Buffer("o", self.gmii.gtx_clk)
        m.d.comb += ClockSignal().eq(rx_clk.i)
        m.d.comb += tx_clk.o.eq(ClockSignal())

        return m


class GMIIMac(wiring.Component):
    csr_bus: wiring.In(csr.Signature(addr_width=4, data_width=8))

    def __init__(self):
        super().__init__()

        regs = csr.Builder(addr_width=4, data_width=8)
        mmap = regs.as_memory_map()

        self._bridge = csr.Bridge(mmap)
        self.csr_bus.memory_map = mmap

    def elaborate(self, platform):
        m = Module()

        m.domains.gmii = ClockDomain(local=True)
        gmii = platform.request("gmii", dir="-")

        m.submodules.crg = crg = DomainRenamer("gmii")(GMIICRG(gmii))
        m.submodules.tx  = tx  = DomainRenamer("gmii")(GMIITx(gmii))
        m.submodules.rx  = rx  = DomainRenamer("gmii")(GMIIRx(gmii))

        m.submodules.tx_demo = tx_demo = DomainRenamer("gmii")(GMIITxDemo())
        wiring.connect(m, tx.data, tx_demo.data)

        return m
