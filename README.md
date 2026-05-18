# Paaliaq

Paaliaq is a WDC W65C816-based single board computer and the
accompanying software, with support for e.g. modern memory management
features, and kernel/user priviledge separation.

The project is currently in early stages of development, with most of
the current work focusing on the chipset implemntation. Proper
documentation TBD.

## Specifications

Using the QMTECH XC7A100T Wukong board with the following
specifications as the base FPGA board:

 - Xilinx Artix-7 100T FPGA
 - 32MiB of SDR SDRAM
 - 8MiB SPI flash (holding the bitstream, with free space after it)
 - SD card slot
 - Ethernet port with GMII PHY
 - Some LEDs and buttons
 - 4 PMODs, 40 pin header exposing 34 FPGA I/Os (see below for usage).

Attached to the FPGA board's 40 pin header is an adapter board holding
a DIP40 variant of the 65C816 CPU, currently running at approximately
4 MHz.

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
 - `fw` - The source code for the firmware (embedded in BRAM).
 - `kern` - The source code for the kernel (loaded over serial).

## License

This project is licensed under the GNU General Public License, either
version 3, or (at your opinion) any later version.
