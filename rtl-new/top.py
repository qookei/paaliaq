from amaranth import *

from amaranth_soc.wishbone import *

from cpu import CPUInterface
from ram import RAM
from extram import ExternalRAM

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

    return code + [0] * (0x200 - len(code) - len(vector_table)) + vector_table

class TopLevel(Elaboratable):
    def __init__(self):
        self.ram = RAM(generate_boot_ram_contents())
        self.extram = ExternalRAM(21)

        self.dec = Decoder(addr_width=24, data_width=8, granularity=8)
        self.dec.add(self.ram.new_bus(), addr=0x00FE00)
        self.dec.add(self.extram.new_bus(), addr=0x010000)

        self.cpu = CPUInterface(self.dec)

    def elaborate(self, platform):
        m = Module()

        m.submodules += self.ram
        m.submodules += self.extram
        m.submodules += self.cpu

        return m

if __name__ == '__main__':
    from amaranth.back import verilog

    with open("top.v", "w") as f:
        top = TopLevel()
        f.write(verilog.convert(top, ports=[
            # CPU connections
            top.cpu.cpu_addr,
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
            top.extram.ram_addr,
            top.extram.ram_data_i,
            top.extram.ram_data_o,
            top.extram.ram_data_oe,
            top.extram.ram_oe,
            top.extram.ram_we,
            top.extram.ram_cs,
        ]))
