export TOPLEVEL = $(CURDIR)
export BUILDDIR = $(CURDIR)/build

export GIT_REV = $(shell $(TOPLEVEL)/scripts/git-rev.sh)

export KAS ?= $(TOPLEVEL)/toolchain/paaliaq-as
export KLD ?= $(TOPLEVEL)/toolchain/paaliaq-ld
export KASFLAGS =
export KLDFLAGS =


all: rtl/build/top.bit fw

.PHONY: fw
fw:
	cd fw && $(MAKE)

rtl/build/top.bit: rtl/*.py fw
	(cd rtl; pdm run build-ecp5 --target-clk=125)

.PHONY: clean
clean:
	cd fw && $(MAKE) clean
	-rm -r $(BUILDDIR)
	-rm -r rtl/build
