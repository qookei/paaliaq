export TOPLEVEL = $(CURDIR)
export BUILDDIR = $(CURDIR)/build

export GIT_REV = $(shell $(TOPLEVEL)/scripts/git-rev.sh)

export KAS ?= $(TOPLEVEL)/toolchain/paaliaq-as
export KLD ?= $(TOPLEVEL)/toolchain/paaliaq-ld
export KASFLAGS =
export KLDFLAGS =

.PHONY: all
all: fw rtl

.PHONY: rtl fw
rtl: $(BUILDDIR)/paaliaq-bitstream.bit
fw: $(BUILDDIR)/boot0.bin

.PHONY: program
program: $(BUILDDIR)/paaliaq-bitstream.bit
	scripts/openocd-program.sh

$(BUILDDIR)/boot0.bin:
	cd fw && $(MAKE)

$(BUILDDIR)/paaliaq-bitstream.bit: $(BUILDDIR)/boot0.bin
	cd rtl && $(MAKE) BOOT0_BIN_PATH=$(BUILDDIR)/boot0.bin

.PHONY: clean
clean:
	cd fw && $(MAKE) clean
	cd rtl && $(MAKE) clean
	-rm -r $(BUILDDIR)
