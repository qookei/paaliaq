KAS ?= toolchain/paaliaq-as
KLD ?= toolchain/paaliaq-ld
KASFLAGS =
KLDFLAGS =

BUILDDIR = build

.PRECIOUS: $(BUILDDIR)/%.o

all: rtl/build/top.bit build/memtest.bin build/pmc.bin

rtl/build/top.bit: rtl/*.py $(BUILDDIR)/boot0.bin
	(cd rtl; pdm run build-ecp5 --target-clk=125)

$(BUILDDIR)/%.o: %.scm
	mkdir -p ${dir $@}
	$(KAS) $(KASFLAGS) $< -o $@

%.elf: %.o
	mkdir -p ${dir $@}
	$(KLD) $(KLDFLAGS) $< -o $@

$(BUILDDIR)/src/boot/boot0.elf: KLDFLAGS += -b 8000
$(BUILDDIR)/src/boot/memtest.elf: KLDFLAGS += -b 9000
$(BUILDDIR)/src/boot/pmc.elf: KLDFLAGS += -b 9000

$(BUILDDIR)/boot0.bin: $(BUILDDIR)/src/boot/boot0.elf
	mkdir -p ${dir $@}
	objcopy -Ielf32-little -Obinary -j.everything $< $@
	truncate -s 32K $@

$(BUILDDIR)/src/boot/memtest.bin: $(BUILDDIR)/src/boot/memtest.elf
	mkdir -p ${dir $@}
	objcopy -Ielf32-little -Obinary -j.everything $< $@

$(BUILDDIR)/memtest.bin: $(BUILDDIR)/src/boot/memtest.bin
	mkdir -p ${dir $@}
	(printf "0\x00\x90\x00\x00\x04"; cat $<) > $@
	truncate -s 1030 $@

$(BUILDDIR)/src/boot/pmc.bin: $(BUILDDIR)/src/boot/pmc.elf
	mkdir -p ${dir $@}
	objcopy -Ielf32-little -Obinary -j.everything $< $@

$(BUILDDIR)/pmc.bin: $(BUILDDIR)/src/boot/pmc.bin
	mkdir -p ${dir $@}
	(printf "0\x00\x90\x00\x00\x01"; cat $<) > $@
	truncate -s 262 $@

.PHONY: clean
clean:
	-rm -r $(BUILDDIR)
	-rm -r rtl/build
