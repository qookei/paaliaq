(define MMIO-BANK #x01)

(define UART0-STATUS #x0001)
(define UART0-TX-DATA #x0002)
(define UART0-RX-DATA #x0003)


(define (bank-plb bank)
  (* #x0101 bank))


(list
 (.text
  (proc uart-putc
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

  (proc uart-puts .a-bits 16 .xy-bits 16
	sep #b00100000 .a-bits 8

	#:more
	lda (x-abs 0)
	beq done
	phx
	jsr uart-putc
	plx
	inc (x-reg)
	bra more

	#:done
	rep #b00100000 .a-bits 16
	rts)

  (proc uart-getc
	php phb
	phe ,(bank-plb MMIO-BANK)
	plb plb

	sep #b00100000 .a-bits 8
	#:rx-empty
	bit (abs ,UART0-STATUS)
	bvc rx-empty

	lda (abs ,UART0-RX-DATA)

	plb plp
	rts)))
