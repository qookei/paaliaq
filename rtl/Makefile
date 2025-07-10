SV2V ?= sv2v


build/top.bit: *.py external/65c816.v
	pdm run build-ecp5 --target-clk=125 --allow-timing-fail


external/snestang:
	mkdir -p external
	git clone https://github.com/nand2mario/snestang external/snestang

external/65c816.v: external/snestang
	mkdir -p external
	$(SV2V) external/snestang/src/65C816/*.v external/snestang/src/65C816/*.sv \
		-w external/65c816.v


.PHONY: clean
clean:
	-rm -rf external
	-rm -rf build
