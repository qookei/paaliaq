(define SDRAM-BASE #x800000)
(define SDRAM-END #x1000000)

(define MMIO-BANK #x01)

(define UART0-STATUS #x0001)
(define UART0-TX-DATA #x0002)
(define UART0-RX-DATA #x0003)

(define TIMER-TIME #x0014)

(define PMC-CLKS #x0040)

(define (bank-nr addr)
  (ash addr -16))

(define (bank-plb bank)
  (* #x0101 bank))

(define (far bank addr)
  (logior addr (ash bank 16)))

(list
 (.text
  (proc _start
	rep #b00110000 .a-bits 16 .xy-bits 16
	ldx (imm #x7FFF)
	txs

	phe ,(bank-plb MMIO-BANK)
	plb plb

	lda (abs ,PMC-CLKS)
	ldx (abs ,(+ PMC-CLKS 2))
	pha phx
	ldx (abs ,TIMER-TIME)
	lda (abs ,(+ TIMER-TIME 2))

	phe ,(bank-plb 0)
	plb plb

	phx
	jsr puthex-word
	pla
	jsr puthex-word

	ldx (imm crnl-str)
	jsr puts

	pla
	jsr puthex-word
	pla
	jsr puthex-word

	ldx (imm crnl-str)
	jsr puts

	#:done
	bra done)

  (.byte crnl-str ,@(map char->integer (string->list "\r\n")) 0)

  (proc show-bank .a-bits 16 .xy-bits 16
	lda #x08
	jsr putc
	lda #x08
	jsr putc
	lda (dp 2)
	jmp puthex-byte)

  (proc puthex-nibble
	.a-bits 16 .xy-bits 16
	and (imm #x0F)
	tax
	lda (x-abs hex-digits)
	jmp putc)

  (proc puthex-byte
	.a-bits 16 .xy-bits 16
	pha
	lsr (a-reg)
	lsr (a-reg)
	lsr (a-reg)
	lsr (a-reg)
	jsr puthex-nibble
	pla
	and (imm #x0F)
	jmp puthex-nibble)

  (proc puthex-word
	.a-bits 16 .xy-bits 16
	pha
	xba
	jsr puthex-byte
	pla
	jmp puthex-byte)

  (proc putc
	php phb
	phe ,(bank-plb MMIO-BANK)
	plb plb

	sep #b00100000 .a-bits 8
	#:tx-full
	bit (abs ,UART0-STATUS)
	bpl tx-full

	sta (abs ,UART0-TX-DATA)

	plb plp
	rts)

  (proc puts
	.a-bits 16 .xy-bits 16
	sep #b00100000 .a-bits 8

	#:more
	lda (x-abs 0)
	beq done
	phx
	jsr putc
	plx
	inc (x-reg)
	bra more

	#:done
	rep #b00100000 .a-bits 16
	rts)

  (.byte hex-digits ,@(map char->integer (string->list "0123456789abcdef")))))
