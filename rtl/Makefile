SV2V ?= sv2v


$(BUILDDIR)/paaliaq-bitstream.bit: paaliaq/*.py external/P65C816.v $(BOOT0_BIN_PATH)
	mkdir -p $(BUILDDIR)/rtl.p
	PYTHONWARNINGS=all pdm run build-artix7 --target-clk=200 \
		--allow-timing-fail --boot-rom $(BOOT0_BIN_PATH) \
		--build-dir $(BUILDDIR)/rtl.p
	cp $(BUILDDIR)/rtl.p/top.bit $(BUILDDIR)/paaliaq-bitstream.bit


external/P65C816.v:
	mkdir -p external
	git clone https://github.com/nand2mario/snestang external/snestang
	$(SV2V) external/snestang/src/65C816/*.v external/snestang/src/65C816/*.sv \
		-w external/P65C816.v


.PHONY: clean
clean:
	-rm -rf external/snestang
	-rm -rf build

.PHONY: deep-clean
deep-clean: clean
	-rm -rf external/P65C816.v
