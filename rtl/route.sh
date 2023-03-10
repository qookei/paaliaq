#!/bin/sh

set -ex

if [ $# -lt 1 ]; then
	echo "Missing argument: <PCF file>"
	exit 1
fi

PCF="$1"

nextpnr-ice40 --hx1k --package tq144 --json TopLevel.json --pcf "$PCF" --asc TopLevel.asc --freq 64 --randomize-seed
