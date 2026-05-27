import argparse
import itertools
import json
import random
import sys
import time
import tqdm

from dataclasses import dataclass
from debug import UARTDebugHost
from functools import cache
from pathlib import Path
from pprint import pprint


SPINNER_CHARS = ["|", "/", "-", "\\"]
spinner_pos = 0

verbose = False
verbose_cycles = False
quiet_run = False


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


def compare_result(test, actual_mem, actual_cycles, actual_state):
    success = True

    if test.final_state != actual_state:
        success = False
        if verbose:
            print("CPU state differs from expected final state:")
            print("    expected | actual")

            def _diff2(name, attr):
                final_v, actual_v = getattr(test.final_state, attr), getattr(actual_state, attr)
                marker = "  <-- different" if final_v != actual_v else ""
                print(f"  {name:>3}:   ${final_v:02x} | ${actual_v:02x}   {marker}")

            def _diff4(name, attr):
                final_v, actual_v = getattr(test.final_state, attr), getattr(actual_state, attr)
                marker = "  <-- different" if final_v != actual_v else ""
                print(f"  {name:>3}: ${final_v:04x} | ${actual_v:04x} {marker}")

            marker = "  <-- different" if test.final_state.emul != actual_state.emul else ""
            print(f"    E: {test.final_state.emul:>5} | {actual_state.emul:>5} {marker}")
            _diff4("A", "a")
            _diff4("X", "x")
            _diff4("Y", "y")
            _diff4("S", "s")
            _diff4("D", "d")
            _diff2("P", "p")
            _diff4("PC", "pc")
            _diff2("PBR", "pbr")
            _diff2("DBR", "dbr")
    if test.cycles != actual_cycles:
        success = False
        if verbose:
            print("CPU bus activity differs from expected activity:")
            print( "               expected | actual")
            for i in range(max(len(test.cycles), len(actual_cycles))):
                final_c = test.cycles[i] if i < len(test.cycles) else None
                actual_c = actual_cycles[i] if i < len(actual_cycles) else None

                if final_c:
                    data_str = "??" if final_c[1] is None else f"{final_c[1]:02x}"
                    final_str = f"{final_c[0]:06x} {data_str} {final_c[2]}"
                else:
                    final_str = "   <missing>  "

                if actual_c:
                    data_str = "??" if actual_c[1] is None else f"{actual_c[1]:02x}"
                    actual_str = f"{actual_c[0]:06x} {data_str} {actual_c[2]}"
                else:
                    actual_str = "  <missing>   "

                marker = "  <-- different" if final_c != actual_c else ""

                print(f"  {i + 1:>5}. {final_str} | {actual_str}{marker}")
    if any(actual_mem.get(i, 0) != test.final_mem[i] for i in test.final_mem.keys()):
        success = False
        if verbose:
            print("Final memory contents differ from expected contents:")
            print("            expected != actual")
            for addr in test.final_mem.keys():
                final_v, actual_v = test.final_mem[i], actual_mem.get(i, 0)
                if final_v != actual_v:
                    print(f"  Byte at ${addr:06x}: {final_v:02x} != {actual_v:02x}")

    return success


@cache
def load_test_file(test_file):
    with open(test_file, "r") as f:
        data = json.load(f)

    return [parse_test(test) for test in data]


def parse_test(test):
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

        if verbose_cycles:
            print(f"{addr:06x} {data_str} {ctrl_str}")
        elif not quiet_run:
            global spinner_pos
            print(f"\b{SPINNER_CHARS[spinner_pos]}", end="", flush=True)
            spinner_pos = (spinner_pos + 1) % len(SPINNER_CHARS)

    def noop(self, addr, vpb, rwb):
        self._note_cycle(addr, None, False, False, vpb, rwb)

    def read(self, addr, vpa, vda, vpb):
        if vpa and vda:
            self.ifetch_done = True
        if self.wait_for_first_ifetch and not self.ifetch_done:
            value = 0xFF
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
        self.terminating = False

    def should_resume_after(self, addr, vpa, vda, vpb, rwb):
        self.terminating = len(self.bus_activity) >= self.cycles and vda and vpa
        return self.terminating, False

    def do_read(self, addr):
        if self.terminating:
            return 0xEA
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
        p = state.p & 0xFF
        dbr = state.dbr
        pcl, pch, pbr = state.pc & 0xFF, (state.pc >> 8) & 0xFF, state.pbr

        clc_sec_emul = 0x38 if state.emul else 0x18

        read_data = [
            0x18,                   # CLC
            0xFB,                   # XCE
            0xAB,  dbr,             # PLB
            0xC2, 0x30,             # REP #$30
            0xA9,   dl,  dh,        # LDA #dp
            0x5B,                   # TCD
            0xA9,   sl,  sh,        # LDA #sp
            0x1B,                   # TCS
            0xA9,   al,  ah,        # LDA #a
            0xA2,   xl,  xh,        # LDX #x
            0xA0,   yl,  yh,        # LDY #y
            clc_sec_emul,           # CLC/SEC
            0xFB,                   # XCE
            0xC2, 0xFF,             # REP #$FF
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
            0xC2, 0x30,             # REP #$30
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
        self.state.pc = (php_ifetch[0] - 1) & 0xFFFF  # Off by 1 due to the NOP
        self.state.pbr = (php_ifetch[0] >> 16) & 0xFF
        self.state.dbr = w["dbr"]


def run_test(client, test):
    if not quiet_run:
        print(f"Running test \"{test.name}\"")

    # Prepare halt loop for after test is over
    client.poke8(0x000000, 0x5C)
    client.poke8(0x000001, 0x00)
    client.poke8(0x000002, 0x00)
    client.poke8(0x000003, 0x00)

    init_ctrl = InitDriver(test.initial_state)
    test_ctrl = MemoryDriver(dict(test.initial_mem), len(test.cycles))
    fini_ctrl = FiniDriver()

    start_ts = time.monotonic()

    def _step_with_log(ctrl, msg):
        if verbose_cycles:
            print(f"  {msg}:")
        elif not quiet_run:
            print(f"  {msg}...  ", end="", flush=True)
        client.debug_with(ctrl)
        if not verbose_cycles and not quiet_run:
            print("\bdone")

    with client.tracing():
        _step_with_log(init_ctrl, "Setting up initial state")
        _step_with_log(test_ctrl, "Running test")
        _step_with_log(fini_ctrl, "Collecting final state")

    end_ts = time.monotonic()

    success = compare_result(test, test_ctrl.mem, test_ctrl.bus_activity[:-1], fini_ctrl.state)

    if not quiet_run:
        print(f"Test \"{test.name}\" {'PASS' if success else 'FAIL'}, in {end_ts - start_ts:.2f} seconds")

    return success


def main(port, baud, tests):
    client = UARTDebugHost(port, baud)

    results = {}

    for test in (tqdm.tqdm(tests) if quiet_run else tests):
        results[test.name] = run_test(client, test)

    n_ran = len(results)
    n_pass = len([result for result in results.values() if result])
    pct_pass = n_pass / n_ran * 100

    print("\n\nAll done!")
    print(f"Summary:  {n_pass} successes out of {n_ran} tests ({pct_pass:.2f}%).")
    if n_pass != n_ran:
        print("Summary of failing tests:")
        for mode in ["e", "n"]:
            for opcode in range(256):
                fails = []
                for i in indices:
                    name = f"{opcode:02x} {mode} {i}"
                    if name in results and not results[name]:
                        fails.append(i)
                if fails:
                    print(f"  Opcode {opcode:02x} (mode {mode}) has {len(fails)} failures")
                    print(f"    First {min(10, len(fails))} are at indices: {fails[:10]}")
        if not verbose:
            print("Rerun with --verbose to see a detailed breakdown.")


def collect_tests(test_dir, selected_tests, emul, native, select, limit, random_sample, exclude):
    if not selected_tests:
        selected_tests = range(256)
    else:
        selected_tests = [int(nr, 16) for nr in selected_tests]

    exclude = [int(nr, 16) for nr in exclude]
    selected_tests = [nr for nr in selected_tests if nr not in exclude]

    if random_sample:
        indices = random.sample(range(1, 10001), k=limit)
    elif select:
        indices = select
    else:
        indices = range(1, limit + 1)

    test_files = []

    if not native and not emul:
        native = True
        emul = True

    if native:
        test_files += [
            test_dir / f"{nr:02x}.n.json" for nr in selected_tests
        ]
    if emul:
        test_files += [
            test_dir / f"{nr:02x}.e.json" for nr in selected_tests
        ]

    tests = list(itertools.product(test_files, indices))
    random.shuffle(tests)

    print(f"Collected {len(tests)} tests.")

    for test_file, index in tests:
        test_cases = load_test_file(test_file)
        yield test_cases[index - 1]


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--serial-port", type=str, default="/dev/ttyUSB2")
    parser.add_argument("--serial-baud", type=int, default=2000000)
    parser.add_argument("--test-dir", type=str, required=True)
    parser.add_argument("--tests", type=str, nargs="*")
    parser.add_argument("--emul", action="store_true")
    parser.add_argument("--native", action="store_true")
    parser.add_argument("--select", type=int, nargs="*")
    parser.add_argument("--limit", type=int, default=10000)
    parser.add_argument("--exclude", type=str, nargs="*")
    parser.add_argument("--random-sample", action="store_true")
    parser.add_argument("--quiet-run", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--verbose-cycles", action="store_true")

    args = parser.parse_args()

    if args.verbose_cycles:
        verbose_cycles = True
    if args.verbose:
        verbose = True
    if args.quiet_run:
        quiet_run = True

    if args.verbose and args.quiet_run:
        print("--verbose and --quiet-run are exclusive.")
        sys.exit()

    if args.verbose_cycles and args.quiet_run:
        print("--verbose-cycles and --quiet-run are exclusive.")
        sys.exit()

    tests = collect_tests(
        Path(args.test_dir),
        args.tests,
        args.emul,
        args.native,
        args.select,
        args.limit,
        args.random_sample,
        args.exclude,
    )

    main(args.serial_port, args.serial_baud, list(tests))
