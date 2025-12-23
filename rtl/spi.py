from amaranth import *
from amaranth.lib import wiring, io
from amaranth.lib.wiring import In, Out
from amaranth_soc import wishbone
from amaranth_soc.memory import MemoryMap
from amaranth.lib.fifo import SyncFIFO

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


class SPIController(wiring.Component):
    csr_bus: In(csr.Signature(addr_width=4, data_width=8))


    class ConfigRegister(csr.Register, access="rw"):
        kick: csr.Field(csr.action.RW1S, 1)
        _unused: csr.Field(csr.action.ResR0WA, 7)


    class TxDataRegister(csr.Register, access="w"):
        data: csr.Field(csr.action.W, 8)

    class RxDataRegister(csr.Register, access="r"):
        data: csr.Field(csr.action.R, 8)


    def __init__(self, *, target_clk):
        super().__init__()

        regs = csr.Builder(addr_width=4, data_width=8)

        self._config = regs.add("Config", self.ConfigRegister())
        self._tx_data = regs.add("TxData", self.TxDataRegister())
        self._rx_data = regs.add("RxData", self.RxDataRegister())

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

        m.submodules.rx_fifo = rx_fifo = SyncFIFO(width=8, depth=32)
        m.submodules.tx_fifo = tx_fifo = SyncFIFO(width=8, depth=32)

        m.d.comb += [
            cs.o.eq(1),
            cs.oe.eq(1),
            clk.oe.eq(1),
            dq0.oe.eq(1),
            dq1.oe.eq(0),
        ]

        out_sr = Signal(8)
        in_sr = Signal(8)

        out_bit_ctr = Signal(range(8))
        in_bit_ctr = Signal(range(8))

        no_more_bytes = Signal()

        with m.FSM():
            with m.State("idle"):
                m.d.comb += cs.o.eq(0)

                with m.If(self._config.f.kick.data):
                    m.d.sync += out_sr.eq(tx_fifo.r_data)
                    m.d.comb += tx_fifo.r_en.eq(1)
                    m.d.sync += [
                        out_bit_ctr.eq(0),
                        in_bit_ctr.eq(0),
                        in_sr.eq(0),
                    ]

                    m.next = "clk-0-before-1"

            with m.State("clk-0-before-1"):
                m.d.sync += [
                    clk.o.eq(0),
                    Cat(out_sr, dq0.o).eq(Cat(0, out_sr)),
                    out_bit_ctr.eq(out_bit_ctr + 1),
                ]

                m.next = "clk-1"

            with m.State("clk-0-after-1"):
                m.d.sync += [
                    clk.o.eq(0),
                    Cat(out_sr, dq0.o).eq(Cat(0, out_sr)),
                    in_sr.eq(Cat(dq1.i, in_sr)),
                    out_bit_ctr.eq(out_bit_ctr + 1),
                    in_bit_ctr.eq(in_bit_ctr + 1),
                ]

                with m.If(out_bit_ctr == 7):
                    m.d.sync += out_sr.eq(tx_fifo.r_data)
                    m.d.comb += tx_fifo.r_en.eq(1)

                    m.d.sync += no_more_bytes.eq(~tx_fifo.r_rdy)

                with m.If(in_bit_ctr == 7):
                    m.d.comb += [
                        rx_fifo.w_data.eq(Cat(dq1.i, in_sr)),
                        rx_fifo.w_en.eq(1),
                    ]

                with m.If(no_more_bytes & (in_bit_ctr == 7)):
                    m.next = "idle"
                    m.d.comb += self._config.f.kick.clear.eq(1)
                with m.Else():
                    m.next = "clk-1"

            with m.State("clk-1"):
                m.d.sync += clk.o.eq(1)
                m.next = "clk-0-after-1"


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

        return m
