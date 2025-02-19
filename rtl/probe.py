from amaranth import *
from amaranth.lib import wiring
from amaranth.lib.wiring import In, Out

from uart import UARTTransmitter

class W65C816DebugProbe(wiring.Component):
    tx: Out(1)

    # TODO(qookie): Connect cpu_bridge via wiring.connect instead of
    # consuming it like this? The problem is that we don't consume all
    # the signals, and don't want to drive any inputs.
    def __init__(self, cpu_bridge):
        super().__init__()

        self.cpu_bridge = cpu_bridge


    def elaborate(self, platform):
        m = Module()

        m.submodules.uart_tx = uart_tx = UARTTransmitter(fifo_depth=32)
        m.d.comb += self.tx.eq(uart_tx.tx)

        clk_edge_sr = Signal(2)
        m.d.sync += clk_edge_sr.eq((clk_edge_sr << 1) | self.cpu_bridge.debug_trigger)

        out_latch = Signal(8)

        def to_hex(o, i):
            with m.Switch(i):
                for i in range(16):
                    with m.Case(i):
                        m.d.sync += o.eq(ord(f'{i:x}'))

        def emit_char(seq, v):
            with m.State(f'tx-{seq}'):
                m.d.sync += uart_tx.w_data.eq(v)
                m.d.sync += uart_tx.w_en.eq(1)
                m.next = f'tx-{seq}-done'

            with m.State(f'tx-{seq}-done'):
                m.d.sync += uart_tx.w_en.eq(0)
                m.next = f'tx-{seq + 1}'

        vaddr_char0 = Signal(8)
        vaddr_char1 = Signal(8)
        vaddr_char2 = Signal(8)
        vaddr_char3 = Signal(8)
        vaddr_char4 = Signal(8)
        vaddr_char5 = Signal(8)

        paddr_char0 = Signal(8)
        paddr_char1 = Signal(8)
        paddr_char2 = Signal(8)
        paddr_char3 = Signal(8)
        paddr_char4 = Signal(8)
        paddr_char5 = Signal(8)

        data_char0 = Signal(8)
        data_char1 = Signal(8)

        vda = Signal()
        vpa = Signal()
        rwb = Signal()
        vpb = Signal()
        abort = Signal()

        with m.FSM():
            with m.State('idle'):
                with m.If(clk_edge_sr == 0b01):
                    to_hex(vaddr_char0, self.cpu_bridge.cpu.addr_lo.bit_select(0, 4))
                    to_hex(vaddr_char1, self.cpu_bridge.cpu.addr_lo.bit_select(4, 4))
                    to_hex(vaddr_char2, self.cpu_bridge.cpu.addr_lo.bit_select(8, 4))
                    to_hex(vaddr_char3, self.cpu_bridge.cpu.addr_lo.bit_select(12, 4))
                    to_hex(vaddr_char4, self.cpu_bridge.cpu.addr_hi.bit_select(0, 4))
                    to_hex(vaddr_char5, self.cpu_bridge.cpu.addr_hi.bit_select(4, 4))

                    to_hex(paddr_char0, self.cpu_bridge.mmu.iface.paddr.bit_select(0, 4))
                    to_hex(paddr_char1, self.cpu_bridge.mmu.iface.paddr.bit_select(4, 4))
                    to_hex(paddr_char2, self.cpu_bridge.mmu.iface.paddr.bit_select(8, 4))
                    to_hex(paddr_char3, self.cpu_bridge.mmu.iface.paddr.bit_select(12, 4))
                    to_hex(paddr_char4, self.cpu_bridge.mmu.iface.paddr.bit_select(16, 4))
                    to_hex(paddr_char5, self.cpu_bridge.mmu.iface.paddr.bit_select(20, 4))

                    with m.If(self.cpu_bridge.cpu.r_data_en):
                        to_hex(data_char0, self.cpu_bridge.cpu.r_data.bit_select(0, 4))
                        to_hex(data_char1, self.cpu_bridge.cpu.r_data.bit_select(4, 4))
                    with m.Else():
                        to_hex(data_char0, self.cpu_bridge.cpu.w_data.bit_select(0, 4))
                        to_hex(data_char1, self.cpu_bridge.cpu.w_data.bit_select(4, 4))

                    m.d.sync += [
                        vda.eq(self.cpu_bridge.cpu.vda),
                        vpa.eq(self.cpu_bridge.cpu.vpa),
                        rwb.eq(self.cpu_bridge.cpu.rw),
                        vpb.eq(self.cpu_bridge.cpu.vpb),
                        abort.eq(self.cpu_bridge.cpu.abort),
                    ]

                    m.next = 'tx-0'

            emit_char(0, vaddr_char5)
            emit_char(1, vaddr_char4)
            emit_char(2, vaddr_char3)
            emit_char(3, vaddr_char2)
            emit_char(4, vaddr_char1)
            emit_char(5, vaddr_char0)

            emit_char(6, C(ord(' '), 8))

            emit_char(7, paddr_char5)
            emit_char(8, paddr_char4)
            emit_char(9, paddr_char3)
            emit_char(10, paddr_char2)
            emit_char(11, paddr_char1)
            emit_char(12, paddr_char0)

            emit_char(13, C(ord(' '), 8))

            emit_char(14, data_char1)
            emit_char(15, data_char0)

            emit_char(16, C(ord(' '), 8))

            emit_char(17, Mux(vda, C(ord('D'), 8), C(ord('-'), 8)))
            emit_char(18, Mux(vpa, C(ord('P'), 8), C(ord('-'), 8)))
            emit_char(19, Mux(rwb, C(ord('R'), 8), C(ord('W'), 8)))
            emit_char(20, Mux(vpb, C(ord('-'), 8), C(ord('V'), 8)))
            emit_char(21, Mux(abort, C(ord('-'), 8), C(ord('A'), 8)))
            emit_char(22, C(ord('\r'), 8))
            emit_char(23, C(ord('\n'), 8))

            with m.State('tx-24'):
                m.next = 'idle'

        return m
