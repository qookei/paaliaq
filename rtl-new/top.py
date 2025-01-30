from amaranth import *

from amaranth_soc import wishbone
from amaranth_soc.wishbone.sram import *

from amaranth.lib import wiring

from cpu import P65C816SoftCore, W65C816WishboneBridge

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
        0x18,             # 00FE00   CLC
        0xFB,             # 00FE01   XCE
        0xA2, 0x00, 0xFF, # 00FE02   LDX #$FF00
        0x9A,             # 00FE05   TXS
        0x02, 0xAA,       # 00FE06   COP #$AA

                          # 00FE08 cop:
        0xE2, 0x20,       # 00FE08   SEP #$20
        0xEE, 0x00, 0xFE, # 00FE0A   INC $FE00
        0x80, 0xFE        # 00FE0D   BRA -2
    ]

    code = [
                          # 00FE00 reset:
        0xEA,             # 00FE00   NOP
        0x1A,             # 00FE01   INC A
        0x48,             # 00FE02   PHA
        0x4C, 0x00, 0xFE  # 00FE03   JMP reset
    ]

    return code + [0] * (0x200 - len(code) - len(vector_table)) + vector_table



class TopLevel(Elaboratable):
    def __init__(self):
        self.ram = WishboneSRAM(size=512, data_width=8, writable=False, init=generate_boot_ram_contents())

        self.cpu = P65C816SoftCore()
        self.cpu_bridge = W65C816WishboneBridge()

        self.dec = wishbone.Decoder(addr_width=24, data_width=8)
        self.dec.add(self.ram.wb_bus, addr=0x00FE00)


    def elaborate(self, platform):
        m = Module()

        m.submodules.ram = self.ram
        m.submodules.cpu = self.cpu
        m.submodules.cpu_bridge = self.cpu_bridge
        m.submodules.dec = self.dec

        wiring.connect(m, self.cpu_bridge.cpu, self.cpu.iface)
        wiring.connect(m, self.cpu_bridge.wb_bus, self.dec.bus)

        return m





if __name__ == '__main__':
    from amaranth.back import verilog

    # TODO(qookie): Fix this.
    with open("top.v", "w") as f:
        top = TopLevel()
        f.write(verilog.convert(top, ports=[
            # CPU connections
            top.cpu.cpu_addr_lower,
            top.cpu.cpu_addr_upper,
            top.cpu.cpu_data_i,
            top.cpu.cpu_data_o,
            top.cpu.cpu_data_oe,
            top.cpu.cpu_clk,
            top.cpu.cpu_rwb,
            top.cpu.cpu_vda,
            top.cpu.cpu_vpa,
            top.cpu.cpu_vp,
            top.cpu.cpu_abort,
            # External RAM connections
            #top.extram.ram_addr,
            #top.extram.ram_data_i,
            #top.extram.ram_data_o,
            #top.extram.ram_data_oe,
            #top.extram.ram_oe,
            #top.extram.ram_we,
            #top.extram.ram_cs,
        ]))
