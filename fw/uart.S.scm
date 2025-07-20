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
