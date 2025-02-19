from amaranth import *

from amaranth_soc import wishbone, event
from amaranth_soc.wishbone.sram import *

from amaranth.lib import wiring
from amaranth.lib.wiring import In, Out

from cpu import W65C816BusSignature, W65C816WishboneBridge


from uart import UARTPeripheral

from sdram import SDRAMController, SDRAMSignature
from mmu import MMU

from amaranth_soc import csr
from amaranth_soc.csr.wishbone import WishboneCSRBridge
from amaranth_soc.csr.event import EventMonitor

def generate_boot_ram_contents():
    vector_table = [
        0x00, 0x00, # 0x00FFE0 (resv.)
        0x00, 0x00, # 0x00FFE2 (resv.)
        0x08, 0xFE, # 0x00FFE4 (COP)
        0x00, 0x00, # 0x00FFE6 (BRK)
        0x00, 0x00, # 0x00FFE8 (ABORT)
        0x00, 0x00, # 0x00FFEA (NMI)
        0x00, 0x00, # 0x00FFEC (resv.)
        0x00, 0x00, # 0x00FFEE (IRQ)

        0x00, 0x00, # 0x00FFF0 (resv.)
        0x00, 0x00, # 0x00FFF2 (resv.)
        0x00, 0x00, # 0x00FFF4 (COP)
        0x00, 0x00, # 0x00FFF6 (resv.)
        0x00, 0x00, # 0x00FFF8 (ABORT)
        0x00, 0x00, # 0x00FFFA (NMI)
        0x00, 0xFE, # 0x00FFFC (RESET)
        0x00, 0x00, # 0x00FFFE (IRQ/BRK)
    ]

    code = [
                                # 00FE00 reset:
        0x18,                   # 00FE00   CLC
        0xFB,                   # 00FE01   XCE
        0xF4, 0x01, 0x01,       # 00FE02   PEA $0101
        0xAB, 0xAB,             # 00FE05   PLB : PLB
        0x2C, 0x01, 0x00,       # 00FE07   BIT $0001      UART_STATUS
        0x10, 0xFB,             # 00FE0A   BPL $FE07      bit 7 clear? (TX_FIFO_NOT_FULL)
        0x1A,                   # 00FE0C   INA
        0x8D, 0x02, 0x00,       # 00FE0D   STA $0002      TX_DATA
        0x4C, 0x07, 0xFE,       # 00FE0C   JMP $FE07
    ]

    return [0] * (0x10000 - 0x200) + code + [0] * (0x200 - len(code) - len(vector_table)) + vector_table


class SystemTimer(wiring.Component):
    bus: wiring.In(csr.Signature(addr_width=4, data_width=8))
    irq: wiring.Out(event.Source().signature)

    class ConfigRegister(csr.Register, access="rw"):
        irq_en: csr.Field(csr.action.RW, 1)
        _unused: csr.Field(csr.action.ResR0WA, 7)

    class TimeRegister(csr.Register, access="r"):
        time: csr.Field(csr.action.R, 32)

    class DeadlineRegister(csr.Register, access="rw"):
        deadline: csr.Field(csr.action.RW, 32)


    def __init__(self):
        regs = csr.Builder(addr_width=4, data_width=8)

        self._config = regs.add("Config", self.ConfigRegister())
        self._time = regs.add("Time", self.TimeRegister(), offset=4)
        self._deadline = regs.add("Deadline", self.DeadlineRegister())

        mmap = regs.as_memory_map()
        self._bridge = csr.Bridge(mmap)

        super().__init__()

        self.bus.memory_map = mmap

    def elaborate(self, platform):
        m = Module()

        m.submodules.bridge = self._bridge
        wiring.connect(m, wiring.flipped(self.bus), self._bridge.bus)

        time = Signal(32)

        rate = 1000 # Hz
        clks_per_tick = int(platform.target_clk_frequency / rate)

        ctr = Signal(range(clks_per_tick + 1))

        with m.If(ctr == clks_per_tick):
            m.d.sync += ctr.eq(0)
            m.d.sync += time.eq(time + 1)
        with m.Else():
            m.d.sync += ctr.eq(ctr + 1)

        with m.If(self._config.f.irq_en.data & (time >= self._deadline.f.deadline.data)):
            m.d.sync += self.irq.i.eq(1)
        with m.Else():
            m.d.sync += self.irq.i.eq(0)

        m.d.comb += [
            self._time.f.time.r_data.eq(time),
        ]

        return m


def print_memory_map(memory_map, depth=0):
    print('Memory map:')
    for resource in memory_map.all_resources():
        path = '::'.join([name[0] for name in resource.path])
        print(f' - {resource.start:#10x} - {resource.end:#10x} - {path}')


class TopLevel(wiring.Component):
    cpu: In(W65C816BusSignature())
    sdram: Out(SDRAMSignature())

    tx: Out(1)
    rx: In(1)

    def __init__(self):
        super().__init__()

        # TODO(qookie): This can be moved below after some refactoring.
        self.cpu_bridge = W65C816WishboneBridge()


    def elaborate(self, platform):
        m = Module()
        evt_map = event.EventMap()

        m.submodules.cpu_bridge = self.cpu_bridge

        m.submodules.wb_dec = wb_dec = wishbone.Decoder(addr_width=24, data_width=8)

        m.submodules.iram = iram = WishboneSRAM(size=0x10000, data_width=8,
                                                init=generate_boot_ram_contents('../toolchain/boot.bin'))
        wb_dec.add(iram.wb_bus, addr=0x000000, name='iram')

        m.submodules.sdram_ctrl = sdram_ctrl = SDRAMController()
        wb_dec.add(sdram_ctrl.wb_bus, addr=0x800000, name='sdram')
        wiring.connect(m, sdram_ctrl.sdram, wiring.flipped(self.sdram))

        m.submodules.csr_dec = csr_dec = csr.Decoder(addr_width=8, data_width=8)

        m.submodules.uart = uart = UARTPeripheral()
        csr_dec.add(uart.bus, name='uart')
        m.d.comb += [
            self.tx.eq(uart.tx),
            uart.rx.eq(self.rx),
        ]

        m.submodules.timer = timer = SystemTimer()
        csr_dec.add(timer.bus, name='timer')
        evt_map.add(timer.irq)

        m.submodules.evt_monitor = evt_monitor = EventMonitor(evt_map, data_width=8)
        csr_dec.add(evt_monitor.bus, name='intc')

        m.submodules.mmu = mmu = MMU()
        csr_dec.add(mmu.bus, name='mmu')
        wiring.connect(m, self.cpu_bridge.mmu, mmu.iface)

        # This freezes the CSR memory map.
        m.submodules.csr_wb = csr_wb = WishboneCSRBridge(csr_dec.bus)
        wb_dec.add(csr_wb.wb_bus, addr=0x010000, name='csr')

        print_memory_map(wb_dec.bus.memory_map)

        wiring.connect(m, self.cpu_bridge.cpu, wiring.flipped(self.cpu))
        wiring.connect(m, self.cpu_bridge.irq, evt_monitor.src)
        wiring.connect(m, self.cpu_bridge.wb_bus, wb_dec.bus)

        return m
