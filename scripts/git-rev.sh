#!/bin/bash

if ! git describe --always --dirty 2>/dev/null; then
    echo "<unknown-rev>"
fi
