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
            "vaddr": In(24),
            "paddr": Out(24),
            # Handshaking signals.
            "stb": In(1),
            "valid": Out(1),
            # Input control signals.
            "write": In(1),
            "ifetch": In(1),
            "user": In(1),
            # Output control signals.
            "abort": Out(1),
        })


class PageTableEntry(data.Struct):
    present:    1
    writable:   1
    executable: 1
    _unused:    1
    pfn:        12


def initial_pts():
    return [{'pfn': i, 'executable': 1, 'writable': 1, 'present': 1} for i in range(1 << 11)]

class MMU(wiring.Component):
    csr_bus: In(csr.Signature(addr_width=4, data_width=8))
    wb_bus: Out(wishbone.Signature(addr_width=24, data_width=8))

    iface: Out(MMUSignature())


    class FaultReasonRegister(csr.Register, access="r"):
        addr:        csr.Field(csr.action.R, 24)
        _unused:     csr.Field(csr.action.ResR0WA, 4)
        user:        csr.Field(csr.action.R, 1)
        ifetch:      csr.Field(csr.action.R, 1)
        write:       csr.Field(csr.action.R, 1)
        non_present: csr.Field(csr.action.R, 1)

    class PtPointerRegister(csr.Register, access="rw"):
        ptr: csr.Field(csr.action.RW, 32)

    class TlbFlushRegister(csr.Register, access="rw"):
        full:    csr.Field(csr.action.W, 1)
        _unused: csr.Field(csr.action.ResR0WA, 3)
        pfn:     csr.Field(csr.action.W, 12)


    def __init__(self):
        super().__init__()

        regs = csr.Builder(addr_width=4, data_width=8)

        self._fault_reason = regs.add('FaultReason', self.FaultReasonRegister())
        self._pt_ptr    = regs.add('PtPointer', self.PtPointerRegister())
        self._tlb_flush = regs.add('TlbFlush', self.TlbFlushRegister())

        mmap = regs.as_memory_map()
        self._bridge = csr.Bridge(mmap)
        self.csr_bus.memory_map = mmap


    def elaborate(self, platform):
        m = Module()

        m.submodules.bridge = self._bridge
        wiring.connect(m, wiring.flipped(self.csr_bus), self._bridge.bus)

        m.submodules.tlb = tlb = Memory(
            shape=PageTableEntry,
            depth=(1 << 11),
            init=initial_pts()
        )
        rd_port = tlb.read_port()
        wr_port = tlb.write_port()

        m.d.comb += rd_port.addr.eq(self.iface.vaddr.bit_select(12, 11))

        # Fixed Wishbone signals (since we only do reads)
        m.d.comb += [
            self.wb_bus.sel.eq(1),
            self.wb_bus.stb.eq(self.wb_bus.cyc),
            self.wb_bus.we.eq(0),
        ]

        supervisor_page = (self.iface.vaddr & 0x800000) | ((self.iface.vaddr & 0xFFE000) == 0x00E000)

        tlb_entry = Signal(PageTableEntry)

        pt_low = Signal(8)

        with m.If(self.iface.valid & ~self.iface.stb):
            m.d.sync += self.iface.valid.eq(0)

        pending_flush = Signal()
        full_flush = Signal()
        flush_pfn = Signal(11)

        with m.FSM():
            with m.State("idle"):
                with m.If(pending_flush):
                    m.next = "flush"
                with m.Elif(self.iface.stb & ~self.iface.valid):
                    with m.If(self.iface.vaddr & 0x800000):
                        m.d.sync += [
                            tlb_entry.pfn.eq(self.iface.vaddr.bit_select(12, 12)),
                            tlb_entry.executable.eq(1),
                            tlb_entry.writable.eq(1),
                            tlb_entry.present.eq(1),
                        ]
                        m.next = "act"
                    with m.Else():
                        m.next = "fetch"
            with m.State("fetch"):
                m.d.sync += tlb_entry.eq(rd_port.data)
                m.next = "act"
            with m.State("act"):
                with m.If(wr_port.en):
                    m.d.sync += wr_port.en.eq(0)

                with m.If(tlb_entry.present):
                    abort_write  = self.iface.write  & ~tlb_entry.writable
                    abort_ifetch = self.iface.ifetch & ~tlb_entry.executable
                    abort_user   = supervisor_page & self.iface.user
                    abort        = abort_write | abort_ifetch | abort_user

                    with m.If(abort):
                        m.d.sync += [
                            # Fault reason register
                            self._fault_reason.f.addr.r_data.eq(self.iface.vaddr),
                            self._fault_reason.f.non_present.r_data.eq(0),
                            self._fault_reason.f.write.r_data.eq(abort_write),
                            self._fault_reason.f.ifetch.r_data.eq(abort_ifetch),
                            self._fault_reason.f.user.r_data.eq(abort_user),
                        ]

                    m.d.sync += [
                        # CPU interface
                        self.iface.paddr.eq(Cat(self.iface.vaddr.bit_select(0, 12), tlb_entry.pfn)),
                        self.iface.abort.eq(abort),
                        self.iface.valid.eq(1),
                    ]
                    m.next = "idle"
                with m.Else():
                    # TLB miss
                    # Begin fetching first byte of page table entry
                    pt_entry = self.iface.vaddr.bit_select(12, 11) << 1
                    m.d.sync += [
                        self.wb_bus.adr.eq(self._pt_ptr.f.ptr.data + pt_entry),
                        self.wb_bus.cyc.eq(1),
                    ]
                    m.next = "wait-first-byte"
            with m.State("wait-first-byte"):
                with m.If(self.wb_bus.ack):
                    m.d.sync += [
                        self.wb_bus.cyc.eq(0),
                        pt_low.eq(self.wb_bus.dat_r),
                    ]
                    # Since the flags are in the low part of the entry, we can
                    # avoid having to load the high byte if the entry is marked
                    # as non-present anyway.
                    with m.If(self.wb_bus.dat_r & 1):
                        m.next = "fetch-second-byte"
                    with m.Else():
                        # PT miss
                        m.d.sync += [
                            # CPU interface
                            self.iface.abort.eq(1),
                            self.iface.valid.eq(1),
                            # Fault reason register
                            self._fault_reason.f.addr.r_data.eq(self.iface.vaddr),
                            self._fault_reason.f.non_present.r_data.eq(1),
                            self._fault_reason.f.write.r_data.eq(self.iface.write),
                            self._fault_reason.f.ifetch.r_data.eq(self.iface.ifetch),
                            self._fault_reason.f.user.r_data.eq(self.iface.user),
                        ]
                        m.next = "idle"
            with m.State("fetch-second-byte"):
                m.d.sync += [
                    self.wb_bus.adr.eq(self.wb_bus.adr + 1),
                    self.wb_bus.cyc.eq(1),
                ]
                m.next = "wait-second-byte"
            with m.State("wait-second-byte"):
                with m.If(self.wb_bus.ack):
                    m.d.sync += [
                        self.wb_bus.cyc.eq(0),
                        tlb_entry.eq(Cat(pt_low, self.wb_bus.dat_r)),
                        wr_port.addr.eq(self.iface.vaddr.bit_select(12, 11)),
                        wr_port.data.eq(Cat(pt_low, self.wb_bus.dat_r)),
                        wr_port.en.eq(1),
                    ]
                    m.next = "act"
            with m.State("flush"):
                with m.If(~pending_flush):
                    m.d.sync += wr_port.en.eq(0)
                    m.next = "idle"
                with m.Else():
                    m.d.sync += [
                        wr_port.data.eq(0),
                        wr_port.addr.eq(flush_pfn),
                        wr_port.en.eq(1),
                        flush_pfn.eq(flush_pfn + 1),
                    ]
                    # If not flushing the whole TLB, stop after one write.
                    with m.If(~full_flush):
                        m.d.sync += pending_flush.eq(0)
                    # If flushing the whole TLB, stop after the last TLB index.
                    with m.Elif(flush_pfn == ((1 << 11) - 1)):
                        m.d.sync += pending_flush.eq(0)

        with m.If(self._tlb_flush.f.pfn.w_stb):
            m.d.sync += flush_pfn.eq(self._tlb_flush.f.pfn.w_data)
        with m.If(self._tlb_flush.f.full.w_stb):
            m.d.sync += [
                full_flush.eq(self._tlb_flush.f.full.w_data),
                pending_flush.eq(1),
            ]

        return m
