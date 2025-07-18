export TOPLEVEL = $(CURDIR)
export BUILDDIR = $(CURDIR)/build

export GIT_REV = $(shell $(TOPLEVEL)/scripts/git-rev.sh)

export KAS ?= $(TOPLEVEL)/toolchain/paaliaq-as
export KLD ?= $(TOPLEVEL)/toolchain/paaliaq-ld
export KASFLAGS =
export KLDFLAGS =


all: rtl/build/top.bit fw

.PHONY: program
program: rtl/build/top.bit
	scripts/openocd-program.sh

.PHONY: fw
fw:
	cd fw && $(MAKE)

rtl/build/top.bit: fw
	cd rtl && $(MAKE) BOOT0_BIN_PATH=$(BUILDDIR)/boot0.bin

.PHONY: clean
clean:
	cd fw && $(MAKE) clean
	cd rtl && $(MAKE) clean
	-rm -r $(BUILDDIR)
