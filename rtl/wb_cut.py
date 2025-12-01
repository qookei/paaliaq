from amaranth import *

from amaranth_soc import wishbone

from amaranth.lib import wiring
from amaranth.lib.wiring import In, Out


# A NON-PIPELINED (!!!) Wishbone combinatorial cut.
# Cuts all combinatorial paths in the bus by registering all the signals.
# Assumes that a Wishbone transaction cannot be terminated once STB is asserted.
class WishboneCut(wiring.Component):
    def __init__(self, target_bus):
        self._tgt_bus = target_bus

        super().__init__({
            "wb_bus": In(wishbone.Signature(
                addr_width=target_bus.addr_width,
                data_width=target_bus.data_width,
                granularity=target_bus.granularity,
                features=target_bus.features,
            ))
        })

        target_bus.memory_map.freeze()
        self.wb_bus.memory_map = target_bus.memory_map

    def elaborate(self, platform):
        m = Module()

        # Main transaction handshake logic:
        # ---
        # STB must go low the next cycle after ACK goes high. Due to
        # the fact STB is registered, the subordinate would see it
        # high in the cycle it presented ACK (because that's also when
        # the manager would just see ACK).

        # TODO(qookie): Add support for ERR (and RTY).
        # ERR and RTY act as additional ACKs.

        in_stb_q = Signal()
        m.d.sync += in_stb_q.eq(self.wb_bus.stb)

        # The manager raising STB raises our registered variant.
        with m.If(~in_stb_q & self.wb_bus.stb):
            m.d.sync += self._tgt_bus.stb.eq(1)

        # The subordintate acknowledging the transaction lowers our
        # registered STB immediately. The assumption is that a
        # transaction does not terminate before acknowledgement
        # (that is, the manager does not lower STB before seeing ACK).
        with m.If(self._tgt_bus.ack):
            m.d.sync += self._tgt_bus.stb.eq(0)

        # ---
        # The remaining signals can just be registered directly.
        m.d.sync += [
            self._tgt_bus.adr.eq(self.wb_bus.adr),
            self._tgt_bus.dat_w.eq(self.wb_bus.dat_w),
            self.wb_bus.dat_r.eq(self._tgt_bus.dat_r),
            self._tgt_bus.cyc.eq(self.wb_bus.cyc),
            self._tgt_bus.sel.eq(self.wb_bus.sel),
            self._tgt_bus.we.eq(self.wb_bus.we),
            self.wb_bus.ack.eq(self._tgt_bus.ack),
        ]

        return m

    pass
