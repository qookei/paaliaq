#!/bin/bash

# Precompile all toolchain source files to improve performance, since
# autocompilation is turned off in the wrapper scripts (as to not
# autocompile the input files).

find paaliaq -type f -exec ${GUILD:-guild-3.0} compile -L . {} \;
