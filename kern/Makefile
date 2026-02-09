PRIVDIR = $(BUILDDIR)/kern.p

SRCS = entry.S.scm uart.S.scm stdio.S.scm pmm.S.scm irq.S.scm
OBJS = $(patsubst %.S.scm,$(PRIVDIR)/%.o,$(SRCS))


.PHONY: all
all: $(BUILDDIR)/vmpaaliaq.bin

$(PRIVDIR)/%.o: %.S.scm
	mkdir -p ${dir $@}
	$(KAS) $(KASFLAGS) $^ -o $@

$(PRIVDIR)/vmpaaliaq.elf: KLDFLAGS += -b 800000
$(PRIVDIR)/vmpaaliaq.elf: $(OBJS)
	mkdir -p ${dir $@}
	$(KLD) $(KLDFLAGS) $^ -o $@

$(BUILDDIR)/vmpaaliaq.bin: $(PRIVDIR)/vmpaaliaq.elf
	mkdir -p ${dir $@}
	objcopy -Ielf32-little -Obinary -j.everything $^ $@

.PHONY: clean
clean:
	-rm -r $(PRIVDIR)
	-rm $(BUILDDIR)/vmpaaliaq.bin
