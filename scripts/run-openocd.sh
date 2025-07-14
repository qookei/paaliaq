#!/usr/bin/env bash

SCRIPTDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

openocd -f "${SCRIPTDIR}/cmsis-dap.cfg" \
	-f /usr/share/openocd/scripts/fpga/lattice_ecp5.cfg \
	-f "${SCRIPTDIR}/jtag-debug.tcl"
