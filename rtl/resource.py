from amaranth import *
from amaranth.build import *


def W65C816Resource(*args, clk, rst, addr, data, rwb, vda, vpa, vpb,
                    irq, nmi, abort, conn=None, attrs=None):
    io = []

    io.append(Subsignal("clk", Pins(clk, dir="o", conn=conn, assert_width=1)))
    io.append(Subsignal("rst", Pins(rst, dir="o", conn=conn, assert_width=1)))

    io.append(Subsignal("addr", Pins(addr, dir="i", conn=conn, assert_width=16)))
    io.append(Subsignal("data", Pins(data, dir="io", conn=conn, assert_width=8)))

    io.append(Subsignal("rwb", Pins(rwb, dir="i", conn=conn, assert_width=1)))
    io.append(Subsignal("vda", Pins(vda, dir="i", conn=conn, assert_width=1)))
    io.append(Subsignal("vpa", Pins(vpa, dir="i", conn=conn, assert_width=1)))
    io.append(Subsignal("vpb", Pins(vpb, dir="i", conn=conn, assert_width=1)))

    io.append(Subsignal("irq",   Pins(irq,   dir="o", conn=conn, assert_width=1)))
    io.append(Subsignal("nmi",   Pins(nmi,   dir="o", conn=conn, assert_width=1)))
    io.append(Subsignal("abort", Pins(abort, dir="o", conn=conn, assert_width=1)))

    if attrs is not None:
        io.append(attrs)
    return Resource.family(*args, default_name="w65c816", ios=io)


def HDMIResource(*args, clk_p, clk_n, data_p, data_n, conn=None, attrs=None):
    io = []

    io.append(Subsignal("clk", DiffPairs(clk_p, clk_n, dir="o", conn=conn, assert_width=1)))
    io.append(Subsignal("data", DiffPairs(data_p, data_n, dir="o", conn=conn, assert_width=3)))

    if attrs is not None:
        io.append(attrs)
    return Resource.family(*args, default_name="hdmi", ios=io)


def SPIResource(*args, cs_n, clk, dq0, dq1, dq2, dq3, conn=None, attrs=None):
    io = []

    io.append(Subsignal("cs_n", PinsN(cs_n, dir="o", conn=conn, assert_width=1)))
    if clk is not None:
        io.append(Subsignal("clk", Pins(clk, dir="o", conn=conn, assert_width=1)))
    io.append(Subsignal("dq0", Pins(dq0, dir="io", conn=conn)))
    io.append(Subsignal("dq1", Pins(dq1, dir="io", conn=conn)))
    io.append(Subsignal("dq2", Pins(dq2, dir="io", conn=conn)))
    io.append(Subsignal("dq3", Pins(dq3, dir="io", conn=conn)))

    if attrs is not None:
        io.append(attrs)
    return Resource.family(*args, default_name="spi", ios=io)
