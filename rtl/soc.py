from amaranth import *

from amaranth_soc import wishbone, event
from amaranth_soc.wishbone.sram import *

from amaranth.lib import wiring
from amaranth.lib.wiring import In, Out

from cpu import W65C816BusSignature, W65C816WishboneBridge

from jtag import JTAGDebugProbe

from uart import UARTPeripheral

from sdram import SDRAMController, SDRAMSignature
from mmu import MMU

from wb_cut import WishboneCut

from video import TextFramebuffer


from amaranth_soc import csr
from amaranth_soc.csr.wishbone import WishboneCSRBridge
from amaranth_soc.csr.event import EventMonitor


def generate_boot_ram_contents(src_file):
    with open(src_file, 'rb') as f:
        out = [0] * 0x8000 + list(f.read())
        out[0xFFFC] = 0x00
        out[0xFFFD] = 0x80
        return out


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


    def __init__(self, *, target_clk):
        regs = csr.Builder(addr_width=4, data_width=8)

        self._target_clk = target_clk

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
        clks_per_tick = int(self._target_clk / rate)

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
        print(f' - [{resource.start:#010x}, {resource.end:#010x}) - {path}')


class SoC(wiring.Component):
    cpu: In(W65C816BusSignature())
    sdram: Out(SDRAMSignature())

    tx: Out(1)
    rx: In(1)

    def __init__(self, *, target_clk, boot_rom_path):
        super().__init__()
        self._target_clk = target_clk
        self._boot_rom = generate_boot_ram_contents(boot_rom_path)


    def elaborate(self, platform):
        m = Module()
        evt_map = event.EventMap()

        m.submodules.wb_arb = wb_arb = wishbone.Arbiter(addr_width=24, data_width=8)

        m.submodules.cpu_bridge = cpu_bridge = W65C816WishboneBridge(target_clk=self._target_clk)
        wb_arb.add(cpu_bridge.wb_bus)

        m.submodules.jtag_debug = jtag_debug = JTAGDebugProbe()
        wb_arb.add(jtag_debug.wb_bus)

        m.submodules.wb_dec = wb_dec = wishbone.Decoder(addr_width=24, data_width=8)

        m.submodules.iram = iram = WishboneSRAM(size=0x10000, data_width=8, init=self._boot_rom)
        m.submodules.iram_cut = iram_cut = WishboneCut(iram.wb_bus)
        wb_dec.add(iram_cut.wb_bus, addr=0x000000, name='iram')

        m.submodules.sdram_ctrl = sdram_ctrl = SDRAMController(target_clk=self._target_clk)
        m.submodules.sdram_cut = sdram_cut = WishboneCut(sdram_ctrl.wb_bus)
        wb_dec.add(sdram_cut.wb_bus, addr=0x800000, name='sdram')
        wiring.connect(m, sdram_ctrl.sdram, wiring.flipped(self.sdram))

        m.submodules.csr_dec = csr_dec = csr.Decoder(addr_width=12, data_width=8, alignment=8)

        m.submodules.uart = uart = UARTPeripheral(target_clk=self._target_clk)
        csr_dec.add(uart.bus, name='uart')
        m.d.comb += [
            self.tx.eq(uart.tx),
            uart.rx.eq(self.rx),
        ]

        m.submodules.timer = timer = SystemTimer(target_clk=self._target_clk)
        csr_dec.add(timer.bus, name='timer')
        evt_map.add(timer.irq)

        m.submodules.evt_monitor = evt_monitor = EventMonitor(evt_map, data_width=8)
        csr_dec.add(evt_monitor.bus, name='intc')

        m.submodules.mmu = mmu = MMU()
        csr_dec.add(mmu.csr_bus, name='mmu')
        wb_arb.add(mmu.wb_bus)
        wiring.connect(m, cpu_bridge.mmu, mmu.iface)

        csr_dec.add(cpu_bridge.csr_bus, name='dbg')

        m.submodules.gen = gen = TextFramebuffer(
            ClockSignal(platform.default_clk),
            platform.default_clk_frequency)
        m.submodules.gen_cut = gen_cut = WishboneCut(gen.wb_bus)
        wb_dec.add(gen_cut.wb_bus, addr=0x100000, name="text")
        csr_dec.add(gen.csr_bus, name="text")

        # This freezes the CSR memory map.
        m.submodules.csr_wb = csr_wb = WishboneCSRBridge(csr_dec.bus)
        m.submodules.csr_cut = csr_cut = WishboneCut(csr_wb.wb_bus)

        wb_dec.add(csr_cut.wb_bus, addr=0x010000, name='csr')

        print_memory_map(wb_dec.bus.memory_map)

        wiring.connect(m, wb_arb.bus, wb_dec.bus)

        wiring.connect(m, cpu_bridge.cpu, wiring.flipped(self.cpu))
        wiring.connect(m, cpu_bridge.irq, evt_monitor.src)

        return m
