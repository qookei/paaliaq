#include <iostream>
#include <memory>
#include "verilated.h"
#include "Vtop.h"
#include "bus-drivers.hpp"
#include "cpu.hpp"
#include <verilated_vcd_c.h>

int main(int argc, char **argv) {
	Verilated::traceEverOn(true);
	Verilated::commandArgs(argc, argv);

	auto top = std::make_unique<Vtop>();
	fpga_bus_driver driver{};
	w65c816 cpu{driver};

	auto trace = std::make_unique<VerilatedVcdC>();
	top->trace(trace.get(), 99);
	trace->open("sim-trace.vcd");

	top->clk = 0;
	top->rst = 1;
	top->eval();
	Verilated::timeInc(1);
	top->rst = 0;
	top->eval();
	Verilated::timeInc(1);

	uint64_t ctr = 0;

	while (!Verilated::gotFinish()) {
		driver.bus_tick([&] { cpu.tick(); },
				top->cpu_clk, top->cpu_addr,
				top->cpu_data_o, top->cpu_data_i,
				top->cpu_rwb, top->cpu_vpa, top->cpu_vda,
				top->cpu_vp, top->cpu_abort,
				false);
		top->eval();
		Verilated::timeInc(1);
		top->clk = !top->clk;
		trace->dump(ctr++);
		trace->flush();
	}
}
