from amaranth import *
from amaranth.lib import wiring, io
from amaranth.lib.wiring import In, Out

from dataclasses import dataclass, field


class TMDSEncoder(wiring.Component):
    active: In(1)
    data_in: In(8)
    c0: In(1)
    c1: In(1)

    data_out: Out(10)


    def elaborate(self, platform):
        m = Module()

        data_min = Signal(9)
        m.d.comb += data_min[0].eq(self.data_in[0])

        in_1_cnt = sum(self.data_in)

        with m.If((in_1_cnt > 4) | ((in_1_cnt == 4) & ~self.data_in[0])):
            m.d.comb += data_min[8].eq(0)
            for i in range(1, 8):
                m.d.comb += data_min[i].eq(~(self.data_in[i] ^ data_min[i - 1]))
        with m.Else():
            m.d.comb += data_min[8].eq(1)
            for i in range(1, 8):
                m.d.comb += data_min[i].eq(self.data_in[i] ^ data_min[i - 1])

        in_balance = in_1_cnt - 4
        total_balance = Signal(signed(4))

        out = Signal(10)

        with m.If((in_balance == 0) | (total_balance == 0)):
            with m.If(data_min[8]):
                m.d.comb += out.eq(Cat(data_min, 0))
                m.d.sync += total_balance.eq(total_balance + in_balance)
            with m.Else():
                m.d.comb += out.eq(Cat(~data_min[0:8], 0, 1))
                m.d.sync += total_balance.eq(total_balance - in_balance)
        with m.Else():
            with m.If(in_balance[3] == total_balance[3]):
                m.d.comb += out.eq(Cat(~data_min[0:8], data_min[8], 1))
                m.d.sync += total_balance.eq(total_balance + data_min[8] - in_balance)
            with m.Else():
                m.d.comb += out.eq(Cat(data_min, 0))
                m.d.sync += total_balance.eq(total_balance - (~data_min[8]) + in_balance)

        with m.If(self.active):
            m.d.sync += self.data_out.eq(out)
        with m.Else():
            m.d.sync += [
                total_balance.eq(0),
                self.data_out.eq(
                    Array([
                        0b0010101011,
                        0b0010101010,
                        0b1101010100,
                        0b1101010101,
                    ])[Cat(self.c1, self.c0)]
                ),
            ]

        return m


@dataclass
class VideoMode:
    width: int
    height: int
    pixel_clock: int

    h_front_porch: int
    h_back_porch: int
    h_sync: int
    h_total: int = field(init=False)
    h_active_start: int = field(init=False)
    h_active_end: int = field(init=False)
    h_sync_start: int = field(init=False)

    v_front_porch: int
    v_back_porch: int
    v_sync: int
    v_total: int = field(init=False)
    v_active_start: int = field(init=False)
    v_active_end: int = field(init=False)
    v_sync_start: int = field(init=False)


    def __post_init__(self):
        self.v_total = self.v_front_porch + self.height + self.v_back_porch + self.v_sync
        self.h_total = self.h_front_porch + self.width  + self.h_back_porch + self.h_sync

        self.v_active_start = self.v_back_porch
        self.v_active_end = self.v_back_porch + self.height
        self.v_sync_start = self.v_active_end + self.v_front_porch

        self.h_active_start = self.h_back_porch
        self.h_active_end = self.h_back_porch + self.width
        self.h_sync_start = self.h_active_end + self.h_front_porch


DMT_MODE_640x480_60Hz = VideoMode(
    width=640,
    height=480,
    pixel_clock=25000000,
    h_front_porch=16,
    h_back_porch=48,
    h_sync=96,
    v_front_porch=10,
    v_back_porch=33,
    v_sync=2,
)

DMT_MODE_800x600_60Hz = VideoMode(
    width=800,
    height=600,
    pixel_clock=40000000,
    h_front_porch=40,
    h_back_porch=88,
    h_sync=128,
    v_front_porch=1,
    v_back_porch=23,
    v_sync=4,
)

DMT_MODE_1024x768_60Hz = VideoMode(
    width=1024,
    height=768,
    pixel_clock=65000000,
    h_front_porch=24,
    h_back_porch=160,
    h_sync=136,
    v_front_porch=3,
    v_back_porch=29,
    v_sync=6,
)

CTA_MODE_1280x720_60Hz = VideoMode(
    width=1280,
    height=720,
    pixel_clock=75000000,
    h_front_porch=110,
    h_back_porch=220,
    h_sync=40,
    v_front_porch=5,
    v_back_porch=20,
    v_sync=5,
)

SMPTE_MODE_1920x1080_30Hz = VideoMode(
    width=1920,
    height=1080,
    pixel_clock=75000000,
    h_front_porch=88,
    h_back_porch=148,
    h_sync=44,
    v_front_porch=4,
    v_back_porch=36,
    v_sync=5,
)


class VideoSequencer(wiring.Component):
    h_sync: Out(1)
    v_sync: Out(1)
    active: Out(1)

    h_pos: Out(16)
    v_pos: Out(16)

    h_start: Out(1)
    v_start: Out(1)


    def __init__(self, mode, pipeline_depth=0):
        super().__init__()
        self.mode = mode
        self.pipeline_depth = pipeline_depth

    def elaborate(self, platform):
        m = Module()

        mode = self.mode

        if self.pipeline_depth > mode.h_active_start:
            raise ValueError("Requested pixel pipeline is too deep")

        h_pos = Signal(range(mode.h_total))
        v_pos = Signal(range(mode.v_total))

        h_active = (h_pos >= mode.h_active_start) & (h_pos < mode.h_active_end)
        v_active = (v_pos >= mode.v_active_start) & (v_pos < mode.v_active_end)

        m.d.sync += [
            self.h_sync.eq(h_pos >= mode.h_sync_start),
            self.h_sync.eq(v_pos >= mode.v_sync_start),
            self.active.eq(h_active & v_active),
        ]

        h_edge = h_pos == mode.h_total - 1
        v_edge = v_pos == mode.v_total - 1

        m.d.sync += h_pos.eq(h_pos + 1)
        with m.If(h_edge):
            m.d.sync += [
                h_pos.eq(0),
                v_pos.eq(Mux(v_edge, 0, v_pos + 1)),
            ]

        pipeline_h_active_start = mode.h_active_start - self.pipeline_depth
        pipeline_h_active_end = mode.h_active_end - self.pipeline_depth

        pipeline_h_active = (h_pos >= pipeline_h_active_start) & (h_pos < pipeline_h_active_end)
        pipeline_active = pipeline_h_active & v_active

        m.d.sync += [
            self.h_start.eq(h_pos == pipeline_h_active_start - 1),
            self.v_start.eq(h_edge & v_edge),
            self.h_pos.eq(Mux(pipeline_active, h_pos - pipeline_h_active_start, 0)),
            self.v_pos.eq(Mux(pipeline_active, v_pos - mode.v_active_start, 0)),
        ]

        return m


class HDMIEncoder(wiring.Component):
    red: In(8)
    green: In(8)
    blue: In(8)

    h_sync: In(1)
    v_sync: In(1)
    active: In(1)


    def elaborate(self, platform):
        m = Module()

        m.submodules.enc0 = enc0 = DomainRenamer("pixel")(TMDSEncoder())
        m.submodules.enc1 = enc1 = DomainRenamer("pixel")(TMDSEncoder())
        m.submodules.enc2 = enc2 = DomainRenamer("pixel")(TMDSEncoder())

        hdmi = platform.request("hdmi", dir="-")

        m.submodules.hdmi_clk_p = hdmi_clk_p = io.DDRBuffer(
            "o",
            hdmi.clk_p,
            o_domain="tmds",
        )

        m.submodules.hdmi_clk_n = hdmi_clk_n = io.DDRBuffer(
            "o",
            hdmi.clk_n,
            o_domain="tmds",
        )

        m.submodules.hdmi_data_p = hdmi_data_p = io.DDRBuffer(
            "o",
            hdmi.data_p,
            o_domain="tmds",
        )

        m.submodules.hdmi_data_n = hdmi_data_n = io.DDRBuffer(
            "o",
            hdmi.data_n,
            o_domain="tmds",
        )

        clk_sr = Signal(10)
        red_sr = Signal(10)
        green_sr = Signal(10)
        blue_sr = Signal(10)

        tmds_sr_ctr = Signal(5, init=1)

        m.d.tmds += [
            tmds_sr_ctr.eq(tmds_sr_ctr.rotate_left(1)),

            clk_sr.eq(clk_sr >> 2),
            red_sr.eq(red_sr >> 2),
            green_sr.eq(green_sr >> 2),
            blue_sr.eq(blue_sr >> 2),
        ]

        with m.If(tmds_sr_ctr[0]):
            m.d.tmds += [
                clk_sr.eq(0b0000011111),
                blue_sr.eq(enc0.data_out),
                green_sr.eq(enc1.data_out),
                red_sr.eq(enc2.data_out),
            ]

        m.d.comb += [
            # Wire up component inputs to encoders
            enc0.c0.eq(self.h_sync),
            enc0.c1.eq(self.v_sync),
            enc0.active.eq(self.active),
            enc1.active.eq(self.active),
            enc2.active.eq(self.active),
            enc0.data_in.eq(self.blue),
            enc1.data_in.eq(self.green),
            enc2.data_in.eq(self.red),
            # Wire up shift registers to DDR buffers
            hdmi_clk_p.o.eq(clk_sr[:2]),
            hdmi_clk_n.o.eq(clk_sr[:2]),
            hdmi_data_p.o[0].eq(Cat(blue_sr[0], green_sr[0], red_sr[0])),
            hdmi_data_p.o[1].eq(Cat(blue_sr[1], green_sr[1], red_sr[1])),
            hdmi_data_n.o[0].eq(Cat(blue_sr[0], green_sr[0], red_sr[0])),
            hdmi_data_n.o[1].eq(Cat(blue_sr[1], green_sr[1], red_sr[1])),
        ]

        return m
