KAS ?= toolchain/paaliaq-as
KASFLAGS =

rtl/build/top.bit: rtl/*.py build/src/boot/memtest.bin
	(cd rtl; pdm run build-ecp5)

build/%.o: %.scm
	mkdir -p ${dir $@}
	$(KAS) $(KASFLAGS) $< -o $@

build/src/boot/memtest.elf: build/src/boot/memtest.o
	mkdir -p ${dir $@}
	guile-3.0 -L toolchain toolchain/reloc.scm "#x008000" $< $@

build/src/boot/memtest.bin: build/src/boot/memtest.elf
	mkdir -p ${dir $@}
	objcopy -Ielf32-little -Obinary -j.text $< $@
	truncate -s 32K $@

.PHONY: clean
clean:
	-rm -r build
	-rm -r rtl/build
