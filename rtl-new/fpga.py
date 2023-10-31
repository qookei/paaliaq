from amaranth import *
from amaranth.build import *
from amaranth.vendor import LatticeICE40Platform
from amaranth_boards.resources import *

from top import TopLevel

class FpgaTopLevel(Elaboratable):
    def __init__(self):
        self.top = TopLevel()

    def elaborate(self, platform):
        m = Module()

        m.submodules += self.top

        cpu_data_pins = platform.request('cpu_data', 0)
        m.d.sync += [
            cpu_data_pins.oe.eq(self.top.cpu.cpu_data_oe),
            cpu_data_pins.o.eq(self.top.cpu.cpu_data_o),
            self.top.cpu.cpu_data_i.eq(cpu_data_pins.i)
        ]

        m.d.sync += self.top.cpu.cpu_addr.eq(platform.request('cpu_addr', 0).i)

        m.d.sync += platform.request('cpu_clk', 0).o.eq(self.top.cpu.cpu_clk)

        m.d.sync += self.top.cpu.cpu_vda.eq(platform.request('cpu_vda', 0).i)
        m.d.sync += self.top.cpu.cpu_vpa.eq(platform.request('cpu_vpa', 0).i)
        m.d.sync += self.top.cpu.cpu_rwb.eq(platform.request('cpu_rwb', 0).i)

        ram_data_pins = platform.request('ram_data', 0)
        m.d.sync += [
            ram_data_pins.oe.eq(self.top.extram.ram_data_oe),
            ram_data_pins.o.eq(self.top.extram.ram_data_o),
            self.top.extram.ram_data_i.eq(ram_data_pins.i)
        ]

        m.d.sync += platform.request('ram_addr', 0).o.eq(self.top.extram.ram_addr)
        m.d.sync += platform.request('ram_cs', 0).o.eq(self.top.extram.ram_cs)
        m.d.sync += platform.request('ram_we', 0).o.eq(self.top.extram.ram_we)
        m.d.sync += platform.request('ram_oe', 0).o.eq(self.top.extram.ram_oe)

        return m

class PaaliaqPlatform(LatticeICE40Platform):
    device      = "iCE40HX1K"
    package     = "TQ144"
    default_clk = "clk12"
    resources   = [
        Resource("clk12", 0, Pins("129", dir="io"),
                 Clock(100e6), Attrs(GLOBAL=True, IO_STANDARD="SB_LVCMOS")),

        Resource("cpu_data", 0, Pins("81 87 88 90 91 93 94 95", dir="io"),
                 Attrs(IO_STANDARD="SB_LVCMOS")),

        Resource("cpu_addr", 0, Pins("73 74 75 76 78 79 80 106 105 104 102 101 99 98 97 96", dir="i"),
                 Attrs(IO_STANDARD="SB_LVCMOS")),

        Resource("cpu_clk", 0, Pins("50", dir="o"),
                 Attrs(IO_STANDARD="SB_LVCMOS")),

        Resource("cpu_vda", 0, Pins("47", dir="i"),
                 Attrs(IO_STANDARD="SB_LVCMOS")),

        Resource("cpu_vpa", 0, Pins("45", dir="i"),
                 Attrs(IO_STANDARD="SB_LVCMOS")),

        Resource("cpu_rwb", 0, Pins("42", dir="i"),
                 Attrs(IO_STANDARD="SB_LVCMOS")),

        Resource("ram_addr", 0, Pins("112 113 114 115 116 9 10 11 12 19 2 1 144 143 142 135 134 122 121 3 120", dir="o"),
                 Attrs(IO_STANDARD="SB_LVCMOS")),

        Resource("ram_data", 0, Pins("118 119 4 7 141 139 138 137", dir="io"),
                 Attrs(IO_STANDARD="SB_LVCMOS")),

        Resource("ram_cs", 0, Pins("117", dir="o"),
                 Attrs(IO_STANDARD="SB_LVCMOS")),

        Resource("ram_we", 0, Pins("8", dir="o"),
                 Attrs(IO_STANDARD="SB_LVCMOS")),

        Resource("ram_oe", 0, Pins("136", dir="o"),
                 Attrs(IO_STANDARD="SB_LVCMOS")),

        #*LEDResources(
        #    pins="C3 B3 C4 C5 A1 A2 B4 B5",
        #    attrs=Attrs(IO_STANDARD="SB_LVCMOS")
        #), # D2..D9

        #UARTResource(0,
        #    rx="B10", tx="B12", rts="B13", cts="A15", dtr="A16", dsr="B14", dcd="B15",
        #    attrs=Attrs(IO_STANDARD="SB_LVCMOS", PULLUP=1),
        #    role="dce"
        #),

        #*SPIFlashResources(0,
        #    cs_n="R12", clk="R11", copi="P12", cipo="P11",
        #    attrs=Attrs(IO_STANDARD="SB_LVCMOS")
        #),
    ]
    connectors  = []

if __name__ == '__main__':
    PaaliaqPlatform().build(FpgaTopLevel())
