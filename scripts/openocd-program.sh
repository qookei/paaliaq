#!/usr/bin/env bash

set -ex

SCRIPTDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
BUILDDIR="${SCRIPTDIR}/../build"

if [[ "$1" == "remote" ]]; then
    echo "pld load ecp5.pld ${BUILDDIR}/paaliaq-bitstream.bit" | socat - TCP-CONNECT:localhost:4444
else
    openocd -f "${SCRIPTDIR}/cmsis-dap.cfg" \
	-f /usr/share/openocd/scripts/fpga/lattice_ecp5.cfg \
	-c "init; pld load ecp5.pld ${BUILDDIR}/paaliaq-bitstream.bit; exit"
fi
