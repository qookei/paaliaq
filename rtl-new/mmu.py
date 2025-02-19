from amaranth import *
from amaranth.lib import data, wiring
from amaranth.lib.wiring import In, Out
from amaranth.lib.memory import Memory
from amaranth_soc import wishbone, event
from amaranth_soc import csr

class MMUSignature(wiring.Signature):
    def __init__(self):
        super().__init__({
            # Input and output addresses.
            'vaddr': In(24),
            'paddr': Out(24),
            # Input control signals.
            'stb': In(1),
            'write': In(1),
            'ifetch': In(1),
            'user': In(1),
            # Output control signals.
            'abort': Out(1),
        })


class PageTableEntry(data.Struct):
    pfn:        12
    executable: 1
    writable:   1
    unused:     1
    present:    1


def initial_pts():
    return [{'pfn': i, 'executable': 1, 'writable': 1, 'present': 1} for i in range(1 << 12)]

class MMU(wiring.Component):
    bus: In(csr.Signature(addr_width=4, data_width=8))

    iface: Out(MMUSignature())


    class FaultReasonRegister(csr.Register, access="r"):
        addr:        csr.Field(csr.action.R, 24)
        _unused:     csr.Field(csr.action.ResR0WA, 4)
        user:        csr.Field(csr.action.R, 1)
        ifetch:      csr.Field(csr.action.R, 1)
        write:       csr.Field(csr.action.R, 1)
        non_present: csr.Field(csr.action.R, 1)

    class PtIndexRegister(csr.Register, access="w"):
        index: csr.Field(csr.action.W, 16)

    class PtWriteRegister(csr.Register, access="w"):
        entry: csr.Field(csr.action.W, PageTableEntry)


    def __init__(self):
        super().__init__()

        regs = csr.Builder(addr_width=4, data_width=8)

        self._fault_reason = regs.add('FaultReason', self.FaultReasonRegister())
        self._pt_index = regs.add('PtIndex', self.PtIndexRegister())
        self._pt_write = regs.add('PtWrite', self.PtWriteRegister())

        mmap = regs.as_memory_map()
        self._bridge = csr.Bridge(mmap)
        self.bus.memory_map = mmap


    def elaborate(self, platform):
        m = Module()

        m.submodules.bridge = self._bridge
        wiring.connect(m, wiring.flipped(self.bus), self._bridge.bus)

        m.submodules.pt = pt = Memory(shape=PageTableEntry,
                                      depth=(1 << 12),
                                      init=initial_pts())
        rd_port = pt.read_port()
        wr_port = pt.write_port()

        m.d.comb += rd_port.addr.eq(self.iface.vaddr.bit_select(12, 12))

        supervisor_page = (self.iface.vaddr & 0x800000) | ((self.iface.vaddr & 0xFFE000) == 0x00E000)

        abort_miss   = ~rd_port.data.present
        abort_write  = self.iface.write  & ~rd_port.data.writable
        abort_ifetch = self.iface.ifetch & ~rd_port.data.executable
        abort_user   = supervisor_page & self.iface.user
        abort = abort_miss | abort_write | abort_ifetch | abort_user

        paddr = Cat(self.iface.vaddr.bit_select(0, 12), rd_port.data.pfn)

        with m.If(self.iface.stb):
            m.d.sync += [
                self.iface.paddr.eq(paddr),
                self.iface.abort.eq(abort_miss | abort_write | abort_ifetch)
            ]

            with m.If(abort):
                m.d.sync += [
                    self._fault_reason.f.addr.r_data.eq(self.iface.vaddr),
                    self._fault_reason.f.non_present.r_data.eq(abort_miss),
                    self._fault_reason.f.write.r_data.eq(abort_write),
                    self._fault_reason.f.ifetch.r_data.eq(abort_ifetch),
                    self._fault_reason.f.user.r_data.eq(abort_user),
                ]


        index = Signal(12)

        with m.If(self._pt_index.f.index.w_stb):
            m.d.sync += index.eq(self._pt_index.f.index.w_data)

        m.d.comb += wr_port.data.eq(self._pt_write.f.entry.w_data)

        with m.If(self._pt_write.f.entry.w_stb):
            m.d.sync += [
                wr_port.en.eq(1),
                wr_port.addr.eq(index),
                index.eq(index + 1),
            ]
        with m.Else():
            m.d.sync += wr_port.en.eq(0)

        return m
