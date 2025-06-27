PRIVDIR = $(BUILDDIR)/fw.p

SRCS = boot0.S.scm uart.S.scm memory-test.S.scm
OBJS = $(patsubst %.S.scm,$(PRIVDIR)/%.o,$(SRCS))


.PHONY: all
all: $(BUILDDIR)/boot0.bin

$(PRIVDIR)/%.o: %.S.scm
	mkdir -p ${dir $@}
	$(KAS) $(KASFLAGS) $^ -o $@

$(PRIVDIR)/boot0.elf: KLDFLAGS += -b 8000
$(PRIVDIR)/boot0.elf: $(OBJS)
	mkdir -p ${dir $@}
	$(KLD) $(KLDFLAGS) $^ -o $@

$(BUILDDIR)/boot0.bin: $(PRIVDIR)/boot0.elf
	mkdir -p ${dir $@}
	objcopy -Ielf32-little -Obinary -j.everything $^ $@
	truncate -s 32K $@
	printf "\x00\x80" | dd of=$@ bs=1 seek=32764 conv=notrunc

.PHONY: clean
clean:
	-rm -r $(PRIVDIR)
	-rm $(BUILDDIR)/boot0.bin
