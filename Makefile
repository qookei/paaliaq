KAS ?= toolchain/paaliaq-as
KASFLAGS =

rtl/build/top.bit: rtl/*.py build/boot0.bin
	(cd rtl; pdm run build-ecp5)

build/%.o: %.scm
	mkdir -p ${dir $@}
	$(KAS) $(KASFLAGS) $< -o $@


build/src/boot/boot0.elf: build/src/boot/boot0.o
	mkdir -p ${dir $@}
	guile-3.0 -L toolchain toolchain/reloc.scm "#x008000" $< $@

build/boot0.bin: build/src/boot/boot0.elf
	mkdir -p ${dir $@}
	objcopy -Ielf32-little -Obinary -j.text $< $@
	truncate -s 32K $@


build/src/boot/memtest.elf: build/src/boot/memtest.o
	mkdir -p ${dir $@}
	guile-3.0 -L toolchain toolchain/reloc.scm "#x009000" $< $@

build/src/boot/memtest.bin: build/src/boot/memtest.elf
	mkdir -p ${dir $@}
	objcopy -Ielf32-little -Obinary -j.text $< $@

build/memtest.bin: build/src/boot/memtest.bin
	mkdir -p ${dir $@}
	(printf "0\x00\x90\x00\x00\x08"; cat $<) > $@
	truncate -s 2054 $@


.PHONY: clean
clean:
	-rm -r build
	-rm -r rtl/build
