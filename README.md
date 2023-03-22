# Paaliaq

Paaliaq is a WDC W65C816-based single board computer with support for
some modern features such as address translation, and kernel/user
priviledge separation.

## (Planned) Specifications

 - CPU: WDC W65C816 @ 8MHz
 - RAM: 2 MiB of SRAM
 - FPGA: Lattice Semi. iCE40 HX1K
 - Storage: 2 MiB SPI flash chip, used for storing the FPGA bitstream,
   boot code, and a file system.
 - Expansion ports: 3 UART interfaces, a SPI interface (shared with
   aformentioned flash chip), 8 GPIOs.

## How?

Supporting these features is made possible due to the inclusion of the
`ABORTB` signal on the W65C816 CPU, which allows the currently
executing instruction to be aborted, which prevents register content
changes, and allows the instruction to potentially be retried after a
return from the handler (for example to allow the implementation of
on-demand paging, swapping pages out, etc.).

Additionally, to help implement this, in place of a traditional set of
peripherals and logic chips one might expect, an FPGA is used to act as
an all-encompasing chipset, which implements all of the system
peripherals (such as timers, UARTs, SPI, etc.), the MMU, which performs
address translation, and an internal interconnect which routes accesses
to external RAM or other parts of the chip.

## Directory structure and building

Each of the following subdirectories has instructions on how to build
it's contents:

 - `rtl` - The source code for the FPGA implementation of the chipset.
 - `toolchain` - The source code for the toolchain (assembler, etc).

## License

This project is licensed under the GNU General Public License, either
version 3, or (at your opinion) any later version.
