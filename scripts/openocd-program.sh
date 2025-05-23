#!/usr/bin/env bash

SCRIPTDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
RTLDIR="${SCRIPTDIR}/../rtl"


echo "pld load ecp5.pld ${RTLDIR}/build/top.bit" | socat - TCP-CONNECT:localhost:4444
