#!/usr/bin/env python

import serial
from contextlib import contextmanager


class UARTDebugHost:
    def __init__(self, port, baud=2000000):
        self._ser = serial.Serial(port, baud)

    def _cmd(self, op, addr, wr_data):
        self._ser.write(bytes([
            ord(op),
            (addr >> 0)  & 0xFF,
            (addr >> 8)  & 0xFF,
            (addr >> 16) & 0xFF,
            wr_data,
        ]))

        return self._ser.read()[0]

    def peek8(self, address):
        return self._cmd('r', address, 0)

    def poke8(self, address, value):
        self._cmd('w', address, value)

    def _peek_n(self, address, width):
        v = 0
        for i in range(width):
            v |= self.peek8(address + i) << (i * 8)
        return v

    def _poke_n(self, address, data, width):
        for i in range(width):
            self.poke8(address + i, (data >> (i * 8)) & 0xFF)

    def peek16(self, address): return self._peek_n(address, 2)
    def poke16(self, address, data): self._poke_n(address, data, 2)

    def peek24(self, address): return self._peek_n(address, 3)
    def poke24(self, address, data): self._poke_n(address, data, 3)

    def peek32(self, address): return self._peek_n(address, 4)
    def poke32(self, address, data): self._poke_n(address, data, 4)

    def trace_enable(self):
        self.poke8(0x10408, 0x04)

    def trace_disable(self):
        self.poke8(0x10408, 0x00)

    def tracee_ready(self):
        v = self.peek8(0x10408)
        if (v & 0x30) != 0:
            return False
        return (v & 0x08) != 0

    @contextmanager
    def tracing(self):
        self.trace_enable()
        try:
            yield None
        finally:
            self.trace_disable()

    def trace_step(self):
        while not self.tracee_ready():
            pass

        va = self.peek24(0x1040c)

        bus_misc = self.peek8(0x10409)
        vpa, vda, vpb, rwb = (
            bus_misc & (1 << 0) != 0,
            bus_misc & (1 << 1) != 0,
            bus_misc & (1 << 2) != 0,
            bus_misc & (1 << 3) != 0,
        )

        pa = self.peek24(0x10414) if vpa or vda else 0

        self.poke8(0x10408, 0x0c)

        data = self.peek8(0x10411 if rwb else 0x10410)

        pa_str = f"{pa:06x}" if vpa or vda else "??????"
        data_str = f"{data:02x}" if vpa or vda else "??"
        vpa_str = "P" if vpa else "-"
        vda_str = "D" if vda else "-"
        vpb_str = "-" if vpb else "V"
        rwb_str = ("R" if rwb else "W") if vpa or vda else "-"

        print(f'{va:06x} {pa_str} {vpa_str}{vda_str}{vpb_str}{rwb_str} {data_str}')

    def debug_enable(self):
        self.poke8(0x10408, 0x06)

        while (self.peek8(0x10408) & 0x01) == 0:
            self.poke8(0x10408, 0x0c)

    def debug_step(self, ctrl):
        while not self.tracee_ready():
            pass

        va = self.peek24(0x1040c)

        bus_misc = self.peek8(0x10409)
        vpa, vda, vpb, rwb = (
            bus_misc & (1 << 0) != 0,
            bus_misc & (1 << 1) != 0,
            bus_misc & (1 << 2) != 0,
            bus_misc & (1 << 3) != 0,
        )

        self.poke8(0x10408, 0x0c)

        done, resume = ctrl.should_resume_after(va, vpa, vda, vpb, rwb)
        if done and resume:
            # Clear dbg_enable (RW1C)
            self.poke8(0x10408, 0x0d)

        if not (vda or vpa):
            ctrl.noop(va, rwb)
        elif rwb:
            self.poke8(0x1040a, ctrl.read(va, vpa, vda, vpb))
        else:
            ctrl.write(va, vpa, vda, vpb, self.peek8(0x10410))

        return done

    def debug_with(self, ctrl):
        self.debug_enable()
        while not self.debug_step(ctrl):
            pass
