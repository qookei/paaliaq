# Paaliaq

Paaliaq is a WDC W65C816-based single board computer and the
accompanying software, with support for e.g. modern memory management
features, and kernel/user priviledge separation.

The project is currently in early stages of development, with most of
the current work focusing on the chipset implemntation. Proper
documentation TBD.

## Specifications

Using the iCESugar-pro SoM with the following specifications as the
base FPGA board:

 - Lattice ECP5 LFE5U-25F FPGA
 - 32MiB of SDR SDRAM
 - 32MiB SPI flash (holding the bitstream, with free space after it)
 - SD card slot
 - RGB led

The project is currently using a soft-core 65C816 implementation, with
future plans for a custom PCB holding an actual 65C816 chip, a SODIMM
slot for the FPGA SoM and breaking out various IO interfaces (HDMI,
UARTs, GPIO, etc).

## How?

Supporting the features mentioned above is made possible due to the
inclusion of the `ABORTB` signal on the 65C816 CPU, which allows the
currently executing instruction to be aborted, preventing register
changes and memory reads/writes, and allowing the instruction to
potentially be retried after returning from the handler.

To facilitate this, the FPGA contains not only the memory controller
and various peripherals, but also a page-based memory management unit,
which performs address translation and permission checks, signaling
errors to the CPU via the aforementioned abort signal.

## Directory structure and building

Each of the following subdirectories has instructions on how to build
it's contents:

 - `rtl` - The source code for the FPGA implementation of the chipset.
 - `toolchain` - The source code for the toolchain (assembler, etc).

## License

This project is licensed under the GNU General Public License, either
version 3, or (at your opinion) any later version.
