# Paaliaq toolchain

This directory contains the sources for the toolchain designed for use
with the system.

The toolchain is written in Scheme and uses [GNU Guile](https://www.gnu.org/software/guile/)
as the Scheme implementation.

In contrast to regular assemblers, this assembler can be thought of more
as a set of functions and libraries that provide an assembly-looking DSL,
with the full power of Scheme for implementing assembler macros and such.

The main component of the assembler is the `paaliaq-as` script, which
contains the core functionality (translating instruction mnemonics into
bytes and such), and handles processing the command-line arguments and
loading the user-specified sources.
