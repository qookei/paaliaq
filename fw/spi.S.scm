(define MMIO-BANK #x01)

(define SPI0-CONFIG #x0600)
(define SPI0-TX-DATA #x0602)
(define SPI0-RX-DATA #x0603)
(define SPI0-SEGMENT #x0604)


(list
 (.text
  (proc spi-test .a-bits 16 .xy-bits 16
	phb
	phe #x0101
	plb plb

	;; Enable reset

	;; 1x rate, TX, 1 byte
	lda (imm #x0000)
	sta (abs ,SPI0-SEGMENT)

	,.a8
	lda #x66
	sta (abs ,SPI0-TX-DATA)
	,.a16

	;; Kick with divisor=1
	lda (imm #x0101)
	sta (abs ,SPI0-CONFIG)

	#:wait-1
	lda (abs ,SPI0-CONFIG)
	bit (imm 1)
	bne wait-1

	;; Software reset

	;; 1x rate, TX, 1 byte
	lda (imm #x0000)
	sta (abs ,SPI0-SEGMENT)

	,.a8
	lda #x99
	sta (abs ,SPI0-TX-DATA)
	,.a16

	;; Kick with divisor=1
	lda (imm #x0101)
	sta (abs ,SPI0-CONFIG)

	#:wait-2
	lda (abs ,SPI0-CONFIG)
	bit (imm 1)
	bne wait-2

	ldx (imm 0)
	#:wait-3
	inc (x-reg)
	cpx (imm 1024)
	bne wait-3

	;; 1x rate, TX, 4 bytes
	lda (imm #x0003)
	sta (abs ,SPI0-SEGMENT)
	;; 1x rate, no-op, 1 byte
	lda (imm #x8000)
	sta (abs ,SPI0-SEGMENT)
	;; 1x rate, RX, 256 bytes
	lda (imm #x40FF)
	sta (abs ,SPI0-SEGMENT)

	,.a8
	lda #x0b
	sta (abs ,SPI0-TX-DATA)
	stz (abs ,SPI0-TX-DATA)
	stz (abs ,SPI0-TX-DATA)
	stz (abs ,SPI0-TX-DATA)
	,.a16

	;; Kick with divisor=1
	lda (imm #x0101)
	sta (abs ,SPI0-CONFIG)

	#:wait
	lda (abs ,SPI0-CONFIG)
	bit (imm 1)
	bne wait

	,.a8
	ldx (imm 0)
	#:read
	lda (abs ,SPI0-RX-DATA)
	sta (x-far-abs #x800000)

	inc (x-reg)
	cpx (imm #x100)
	bne read
	,.a16

	plb

	ldy (imm #x0080)
	ldx (imm #x0000)
	jsr dump-256-bytes

	rts)

  ))
