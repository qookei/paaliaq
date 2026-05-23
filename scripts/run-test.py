import argparse
import json

from dataclasses import dataclass
from debug import UARTDebugHost
from pprint import pprint


@dataclass
class MachineState:
    emul: bool = False
    a: int = 0
    x: int = 0
    y: int = 0
    s: int = 0
    d: int = 0
    p: int = 0
    pc: int = 0
    pbr: int = 0
    dbr: int = 0


@dataclass
class TestCase:
    name: str

    initial_state: MachineState
    initial_mem: dict[int, int]

    final_state: MachineState
    final_mem: dict[int, int]

    cycles: list[list[int, int | None, str]]


def load_test(test_file, test_nr):
    with open(test_file, "r") as f:
        data = json.load(f)

    test = data[test_nr]

    initial_state = MachineState(
        emul=test["initial"]["e"] > 0,
        a=test["initial"]["a"],
        x=test["initial"]["x"],
        y=test["initial"]["y"],
        s=test["initial"]["s"],
        d=test["initial"]["d"],
        p=test["initial"]["p"],
        pc=test["initial"]["pc"],
        pbr=test["initial"]["pbr"],
        dbr=test["initial"]["dbr"],
    )
    initial_mem = {
        v[0]: v[1] for v in test["initial"]["ram"]
    }

    final_state = MachineState(
        emul=test["final"]["e"] > 0,
        a=test["final"]["a"],
        x=test["final"]["x"],
        y=test["final"]["y"],
        s=test["final"]["s"],
        d=test["final"]["d"],
        p=test["final"]["p"],
        pc=test["final"]["pc"],
        pbr=test["final"]["pbr"],
        dbr=test["final"]["dbr"],
    )
    final_mem = {
        v[0]: v[1] for v in test["final"]["ram"]
    }

    # Skip emxl in bus control since they're not wired up...
    cycles = [
        [v[0], v[1], v[2][:4]] for v in test["cycles"]
    ]

    return TestCase(
        name=test["name"],
        initial_state=initial_state,
        initial_mem=initial_mem,
        final_state=final_state,
        final_mem=final_mem,
        cycles=cycles,
    )


class BaseDriver:
    def __init__(self, wait_for_first_ifetch=False):
        self.bus_activity = []
        self.wait_for_first_ifetch = wait_for_first_ifetch
        self.ifetch_done = False

    def _note_cycle(self, addr, data, vpa, vda, vpb, rwb):
        vpa_c = "p" if vpa else "-"
        vda_c = "d" if vda else "-"
        vpb_c = "-" if vpb else "v"
        rwb_c = "r" if rwb else "w"

        ctrl_str = f"{vda_c}{vpa_c}{vpb_c}{rwb_c}"
        data_str = "??" if data is None else f"{data:02x}"

        self.bus_activity.append([addr, data, ctrl_str])
        print(f"{addr:06x} {data_str} {ctrl_str}")

    def noop(self, addr, rwb):
        self._note_cycle(addr, None, False, False, True, rwb)

    def read(self, addr, vpa, vda, vpb):
        if vpa and vda:
            self.ifetch_done = True
        if self.wait_for_first_ifetch and not self.ifetch_done:
            value = 0
        else:
            value = self.do_read(addr)
        self._note_cycle(addr, value, vpa, vda, vpb, True)

        return value

    def write(self, addr, vpa, vda, vpb, value):
        if not (self.wait_for_first_ifetch and not self.ifetch_done):
            self.do_write(addr, value)
        self._note_cycle(addr, value, vpa, vda, vpb, False)


class MemorylessDriver(BaseDriver):
    def __init__(self, read_data, write_seq):
        super().__init__(wait_for_first_ifetch=True)
        self.read_pos = 0
        self.read_data = read_data
        self.write_pos = 0
        self.write_seq = write_seq
        self.write_data = {}

    def do_read(self, addr):
        value = self.read_data[self.read_pos]
        self.read_pos += 1

        return value

    def do_write(self, addr, value):
        if self.read_pos == 0:
            return
        self.write_data[self.write_seq[self.write_pos]] = value
        self.write_pos += 1


class MemoryDriver(BaseDriver):
    def __init__(self, mem, cycles):
        super().__init__()
        self.cycles = cycles
        self.mem = mem
        print(f"{self.cycles=}")

    def should_resume_after(self, addr, vpa, vda, vpb, rwb):
        return self.cycles == len(self.bus_activity) + 1, False

    def do_read(self, addr):
        return self.mem.get(addr, 0)

    def do_write(self, addr, value):
        self.mem[addr] = value


class InitDriver(MemorylessDriver):
    def __init__(self, state):
        al, ah = state.a & 0xFF, (state.a >> 8) & 0xFF
        xl, xh = state.x & 0xFF, (state.x >> 8) & 0xFF
        yl, yh = state.y & 0xFF, (state.y >> 8) & 0xFF
        dl, dh = state.d & 0xFF, (state.d >> 8) & 0xFF
        sl, sh = state.s & 0xFF, (state.s >> 8) & 0xFF
        p, np = state.p & 0xFF, (~state.p) & 0xFF
        dbr = state.dbr

        pcl, pch, pbr = state.pc & 0xFF, (state.pc >> 8) & 0xFF, state.pbr

        clc_sec_emul = 0x38 if state.emul else 0x18

        read_data = [
            0x18,                   # CLC
            0xFB,                   # XCE
            0xAB,  dbr,             # PLB
            0xC2, 0x30,             # REP $30
            0xA9,   dl,  dh,        # LDA #dp
            0x5B,                   # TCD
            0xA9,   sl,  sh,        # LDA #sp
            0x1B,                   # TCS
            0xA9,   al,  ah,        # LDA #a
            0xA2,   xl,  xh,        # LDX #x
            0xA0,   yl,  yh,        # LDY #y
            clc_sec_emul,           # CLC/SEC
            0xFB,                   # XCE
            0xC2,   np,             # REP #~p
            0xE2,    p,             # SEP #p
            0x5C,  pcl,  pch,  pbr, # JMP test_entry
        ]
        super().__init__(read_data, [])

    def should_resume_after(self, addr, vpa, vda, vpb, rwb):
        return self.read_pos == len(self.read_data) - 1, False


class FiniDriver(MemorylessDriver):
    def __init__(self):
        read_data = [
            0x08,                   # PHP
            0x18,                   # CLC
            0xFB,                   # XCE
            0x08,                   # PHP
            0xC2, 0x30,             # REP $30
            0x8B,                   # PHB
            0x0B,                   # PHD
            0x48,                   # PHA
            0xDA,                   # PHX
            0x5A,                   # PHY
            0x5C, 0x00, 0x00, 0x00, # JMP $000000
        ]
        write_seq = [
            "p_orig",
            "p_c_emul",
            "dbr",
            "dh",
            "dl",
            "ah",
            "al",
            "xh",
            "xl",
            "yh",
            "yl",
        ]
        super().__init__(read_data, write_seq)
        self.state = MachineState()

    def should_resume_after(self, addr, vpa, vda, vpb, rwb):
        done = self.read_pos == len(self.read_data) - 1
        if done:
            self._update_state()
        return done, True

    def _update_state(self):
        first_ifetch = None
        for i, cycle in enumerate(self.bus_activity):
            if cycle[2] == "dp-r":
                first_ifetch = i
                break

        assert first_ifetch is not None

        php_ifetch = self.bus_activity[first_ifetch]
        php_write  = self.bus_activity[first_ifetch + 2]

        w = self.write_data
        self.state.emul = (w["p_c_emul"] & 1) != 0
        self.state.a = w["al"] | (w["ah"] << 8)
        self.state.x = w["xl"] | (w["xh"] << 8)
        self.state.y = w["yl"] | (w["yh"] << 8)
        assert php_write[2] == "d--w"
        self.state.s = php_write[0]
        self.state.d = w["dl"] | (w["dh"] << 8)
        self.state.p = w["p_orig"]
        assert php_ifetch[2] == "dp-r"
        self.state.pc = php_ifetch[0] & 0xFFFF
        self.state.pbr = (php_ifetch[0] >> 16) & 0xFF
        self.state.dbr = w["dbr"]


def run_test(port, baud, test_file, test_nr):
    client = UARTDebugHost(port, baud)
    test = load_test(test_file, test_nr)

    print(f"Running test \"{test.name}\"")

    # Prepare halt loop after test is over
    client.poke8(0x000000, 0x5C)
    client.poke8(0x000001, 0x00)
    client.poke8(0x000002, 0x00)
    client.poke8(0x000003, 0x00)

    init_ctrl = InitDriver(test.initial_state)
    test_ctrl = MemoryDriver(dict(test.initial_mem), len(test.cycles))
    fini_ctrl = FiniDriver()

    with client.tracing():
        print("Setting up initial state")
        client.debug_with(init_ctrl)
        print("Running test")
        client.debug_with(test_ctrl)
        print("Collecting final state")
        client.debug_with(fini_ctrl)

    pprint(test.cycles)
    pprint(test_ctrl.bus_activity)

    pprint(test.final_state)
    pprint(fini_ctrl.state)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--serial-port", type=str, default="/dev/ttyUSB2")
    parser.add_argument("--serial-baud", type=int, default=2000000)
    parser.add_argument("--test-file", type=str, required=True)
    parser.add_argument("--test-nr", type=int, required=True)

    args = parser.parse_args()
    run_test(args.serial_port, args.serial_baud, args.test_file, args.test_nr)
