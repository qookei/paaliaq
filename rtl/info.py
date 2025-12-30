from amaranth import *
from amaranth.lib import wiring, io
from amaranth.lib.cdc import FFSynchronizer
from amaranth.lib.wiring import In, Out
from amaranth_soc import csr

import os, math


class ECP5DTR(wiring.Component):
    temp: Out(signed(8))

    def __init__(self, target_clk):
        super().__init__()
        self._target_clk = target_clk

    def elaborate(self, platform):
        m = Module()

        trig_pulse = Signal()
        dtrout = Signal(8)

        m.submodules.dtr = dtr = Instance(
            "DTR",
            ("i", "STARTPULSE", trig_pulse),
            *[("o", f"DTROUT{i}", dtrout[i]) for i in range(8)],
        )

        valid = Signal()
        m.submodules.done_sync = done_sync = FFSynchronizer(
            dtrout[7], valid,
            o_domain="sync",
        )
        valid_d = Signal()
        m.d.sync += valid_d.eq(valid)
        valid_posedge = valid & ~valid_d

        dtr_temp = Signal(6)
        with m.If(valid_posedge):
            m.d.sync += dtr_temp.eq(dtrout[:5])

        # Not very precise at slightly above ambient, but oh well...
        # Values from:
        # FPGA-TN-02210-1.4 Power Consumption and Management for
        # ECP5 and ECP5-5G Devices
        # 4.2. Equivalent Junction Temperature for DTROUT values
        temp_map = Array([
            -58, -56, -54, -52, -45, -44, -43, -42,
            -41, -40, -39, -38, -37, -36, -30, -20,
            -10,  -4,   0,   4,  10,  21,  22,  23,
             24,  25,  26,  27,  28,  29,  40,  50,
             60,  70,  76,  80,  81,  82,  83,  84,
             85,  86,  87,  88,  89,  95,  96,  97,
             98,  99, 100, 101, 102, 103, 104, 105,
            106, 107, 108, 116, 120, 124, 128, 132,
        ])

        m.d.sync += self.temp.eq(temp_map[dtr_temp])

        # Generate a trigger every 1ms

        def ns_to_clks(ns):
            return int(math.ceil(ns * self._target_clk / 1000000000))

        trig_clks = ns_to_clks(1000000)
        pulse_clks = ns_to_clks(5)
        trig_ctr = Signal(range(trig_clks + 1))

        m.d.sync += trig_ctr.eq(trig_ctr + 1)
        with m.If(trig_ctr == trig_clks):
            m.d.sync += trig_ctr.eq(0)

        m.d.comb += trig_pulse.eq(trig_ctr < pulse_clks)

        return m


class SystemInfo(wiring.Component):
    csr_bus: In(csr.Signature(addr_width=4, data_width=8))


    class GitRevisionRegister(csr.Register, access="r"):
        git_rev: csr.Field(csr.action.R, 28)
        _unused: csr.Field(csr.action.ResR0WA, 2)
        dirty:   csr.Field(csr.action.R, 1)
        valid:   csr.Field(csr.action.R, 1)


    class TemperatureRegister(csr.Register, access="r"):
        temperature: csr.Field(csr.action.R, signed(8))


    class FrequencyRegister(csr.Register, access="r"):
        frequency: csr.Field(csr.action.R, 8)


    def __init__(self, *, target_clk):
        super().__init__()

        regs = csr.Builder(addr_width=4, data_width=8)

        self._rev = regs.add("GitRevision", self.GitRevisionRegister())
        self._temp = regs.add("Temperature", self.TemperatureRegister())
        self._freq = regs.add("Frequency", self.FrequencyRegister())

        mmap = regs.as_memory_map()
        self._bridge = csr.Bridge(mmap)
        self.csr_bus.memory_map = mmap

        self._target_clk = target_clk


    def elaborate(self, platform):
        m = Module()

        m.submodules.bridge = self._bridge
        wiring.connect(m, wiring.flipped(self.csr_bus), self._bridge.bus)

        # Temperature register
        m.submodules.dtr = dtr = ECP5DTR(target_clk=self._target_clk)
        m.d.comb += self._temp.f.temperature.r_data.eq(dtr.temp)

        # Git Revision of the RTL
        rev = os.getenv("GIT_REV")
        if rev is None or rev == "<unknown-rev>":
            print("Warning: Git revision is unknown")
            m.d.comb += self._rev.f.valid.eq(0)
        else:
            rev, *dirty = rev.split("-")
            assert len(rev) == 7

            m.d.comb += [
                self._rev.f.git_rev.r_data.eq(int(rev, 16)),
                self._rev.f.dirty.r_data.eq(dirty == ["dirty"]),
                self._rev.f.valid.r_data.eq(1),
            ]

        # SoC clock frequency
        m.d.comb += self._freq.f.frequency.r_data.eq(int(self._target_clk / 1000000))

        return m
