(define MMIO-BANK #x01)

(define VIDEO-CHAR #x0500)
(define VIDEO-STATUS #x0501)

(define (bank-plb bank)
  (* #x0101 bank))

(list
 (.text
  (proc video-putc
	php phb
	phe ,(bank-plb MMIO-BANK)
	plb plb

	,.a8
	#:not-ready
	bit (abs ,VIDEO-STATUS)
	bpl not-ready

	sta (abs ,VIDEO-CHAR)

	plb plp
	rts)))
