from amaranth import *
# from amaranth_soc.wishbone import *

class CPUInterface(Elaboratable):
    def __init__(self, bus_port):
        # CPU's address pins
        self.cpu_addr = Signal(16)

        # CPU's data pins
        self.cpu_data_i = Signal(8)
        self.cpu_data_o = Signal(8)
        self.cpu_data_oe = Signal()

        # Misc CPU outputs
        self.cpu_clk = Signal()
        self.cpu_rwb = Signal()
        self.cpu_vda = Signal()
        self.cpu_vpa = Signal()
        self.cpu_vp = Signal()

        # Misc CPU inputs
        self.cpu_abort = Signal()

        self.bus_port = bus_port

        # Internal signals

        self.ctr = Signal(8)

        self.cpu_addr_latch = Signal(24)

    def elaborate(self, platform):
        m = Module()

        m.submodules += self.bus_port

        m.d.comb += self.cpu_abort.eq(1)

        #     1   2  3       4    5         1
        #     |   |  |       |    |         |
        # ____                ______________
        #     \______________/              \____
        # 1) We bring the CPU clock down, after which, if the CPU is reading, it will
        #    look the data bus for the read result.
        # 2) After a bit, we let go of the data bus if we're outputting anything.
        #    This is needed because in a moment the CPU will output the bank address
        #    on the data bus.
        # 3) The CPU outputs the bank address on the data bus. Additionally, the rest
        #    of the address, and RWB/VDA/VPA/VP are all valid at this point.
        # -) Between 3 and 4, we need to perform address translation with the MMU, to
        #    figure out the state for ABORT.
        #    Address translation may take more than we have time (at 8MHz), in which
        #    case we delay the entry to state 4, stretching the clock.
        # 4) We bring the CPU clock up, after which the CPU will probe ABORT.
        # -) After point 4, we can initiate a read transaction if the CPU is reading.
        #    We need to wait for a minimum amount of cycles, after which we stretch
        #    the clock until it completes before going back to point 1.
        # 5) If writing, the CPU outputs the write data on the data bus at this point.
        #    We can initiate the write transaction here.
        #    In theory, we could let the write transaction run until point 4 of the
        #    next clock cycle before we have to block (and even longer if the next
        #    cycle is a no-op [VDA=VPA=0]), but for simplicity, the read & write paths
        #    will converge on blocking before point 1 is reached.
        # Timings for the various points (at 8MHz @ 3.3V):
        #  1 -> 2) tDHW & tDHR: min 10 ns (upper bound up to 1 -> 3 time)
        #  1 -> 3) tADS & tBAS: max 40 ns
        # 4? -> 5) tMDS: max 40 ns

        m.d.sync += self.ctr.eq(self.ctr + 1)

        # TODO: Replace uses of ctr with discrete states

        CTR_T2_AT = 2
        CTR_T3_AT = 6

        CTR_T5_AT = 4
        CTR_T6_AT = 8

        with m.FSM():
            with m.State('T1'):
                m.d.sync += [
                    self.cpu_clk.eq(0),
                    self.ctr.eq(0)
                ]
                m.next = 'T2'
            with m.State('T2'):
                with m.If(self.ctr != CTR_T2_AT):
                    m.next = 'T2'
                with m.Else():
                    m.d.sync += self.cpu_data_oe.eq(0)
                    m.next = 'T3'
            with m.State('T3'):
                with m.If(self.ctr != CTR_T3_AT):
                    m.next = 'T3'
                with m.Else():
                    m.d.sync += self.cpu_addr_latch.eq(
                        (self.cpu_data_i << 16) | self.cpu_addr
                    )
                    m.next = 'T4'
            with m.State('T4'):
                m.d.sync += [
                    self.cpu_clk.eq(1),
                    self.ctr.eq(0)
                ]
                m.next = 'T5'
            with m.State('T5'):
                with m.If(self.ctr != CTR_T5_AT):
                    m.next = 'T5'
                with m.Else():
                    # XXX: Is this right?
                    m.d.sync += [
                        self.bus_port.bus.adr.eq(self.cpu_addr_latch),
                        self.bus_port.bus.cyc.eq(self.cpu_vda | self.cpu_vpa),
                        # self.bus_port.bus.stb.eq(self.cpu_vda | self.cpu_vpa),
                        self.bus_port.bus.we.eq(~self.cpu_rwb),
                        self.bus_port.bus.dat_w.eq(self.cpu_data_i),
                    ]
                    m.next = 'T6'
            with m.State('T6'):
                # Not in diagram above, here we wait until either the transaction completes
                # (and set the data bus output for reads), or we wait for the minimum amount
                # of cycles to pass.
                with m.If(self.ctr != CTR_T6_AT):
                    m.next = 'T6'
                with m.Elif(~self.bus_port.bus.cyc): # No-op cycle
                    m.next = 'T1'
                with m.Elif(self.bus_port.bus.ack): # Access complete
                    m.next = 'T1'

                    m.d.sync += [
                        self.bus_port.bus.cyc.eq(0),
                        self.bus_port.bus.stb.eq(0),
                    ]

                    with m.If(self.cpu_rwb): # XXX: One cycle may not be enough setup time
                        m.d.sync += [
                            self.cpu_data_o.eq(self.bus_port.bus.dat_r),
                            self.cpu_data_oe.eq(1)
                        ]
                with m.Else():
                    # Access still in progress
                    # FIXME: Add a timeout? If no one responds to our bus transaction,
                    # we get stuck here...
                    m.next = 'T6'

        return m
