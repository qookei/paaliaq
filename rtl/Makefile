SV2V ?= sv2v


build/top.bit: *.py external/P65C816.v
	PYTHONWARNINGS=all pdm run build-ecp5 --target-clk=125 --allow-timing-fail


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
