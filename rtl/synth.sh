#!/bin/sh

set -ex

yosys -p "read_verilog hw/gen/TopLevel.v; synth_ice40 -top TopLevel -json TopLevel.json"
