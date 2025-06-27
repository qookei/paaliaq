(define MMIO-BANK #x01)

(define UART0-STATUS #x0001)
(define UART0-TX-DATA #x0002)
(define UART0-RX-DATA #x0003)


(define (bank-plb bank)
  (* #x0101 bank))


(list
 (.rodata
  (.asciz hex-digits "0123456789abcdef"))
 (.text
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

    (proc getc
	php phb
	phe ,(bank-plb MMIO-BANK)
	plb plb

	sep #b00100000 .a-bits 8
	#:rx-empty
	bit (abs ,UART0-STATUS)
	bvc rx-empty

	lda (abs ,UART0-RX-DATA)

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
	jmp puthex-nibble)

  (proc puthex-word
	.a-bits 16 .xy-bits 16
	pha
	xba
	jsr puthex-byte
	pla
	jmp puthex-byte)))
