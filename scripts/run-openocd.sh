#!/usr/bin/env bash

SCRIPTDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

openocd -f "${SCRIPTDIR}/ftdi-ft2232-cjmcu.cfg" \
	-f /usr/share/openocd/scripts/fpga/lattice_ecp5.cfg \
	-f "${SCRIPTDIR}/jtag-debug.tcl"
