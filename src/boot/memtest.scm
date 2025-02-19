(define SDRAM-BASE #x800000)
(define SDRAM-END #x1000000)

(define MMIO-BANK #x01)

(define UART0-STATUS #x0001)
(define UART0-TX-DATA #x0002)
(define UART0-RX-DATA #x0003)

(define TIMER-TIME #x0014)

(define (bank-nr addr)
  (ash addr -16))

(define (bank-plb bank)
  (* #x0101 bank))

(define (far bank addr)
  (logior addr (ash bank 16)))

(list
 (.text
  (proc _start
	clc
	xce
	sei

	rep #b00110000 .a-bits 16 .xy-bits 16
	ldx (imm #x7FFF)
	txs

	#:tests

	ldx (imm test0-str)
	jsr puts
	jsr test0
	jsr log-test-result

	ldx (imm test1-str)
	jsr puts
	jsr test1
	jsr log-test-result

	ldx (imm test2-str)
	jsr puts
	jsr test2
	jsr log-test-result

	ldx (imm test3-str)
	jsr puts
	jsr test3
	jsr log-test-result

	ldx (imm test4-str)
	jsr puts
	jsr test4
	jsr log-test-result

	bra tests)

  (.byte pass-str ,@(map char->integer (string->list " PASS\r\n")) 0)
  (.byte fail-str ,@(map char->integer (string->list " FAIL\r\n")) 0)
  (.byte write-str ,@(map char->integer (string->list " writing 80 ")) 0)
  (.byte check-str ,@(map char->integer (string->list " checking 80 ")) 0)
  (.byte test0-str ,@(map char->integer (string->list "Test 0 - zero fill   ... ")) 0)
  (.byte test1-str ,@(map char->integer (string->list "Test 1 - walking 1s  ... ")) 0)
  (.byte test2-str ,@(map char->integer (string->list "Test 2 - walking 0s  ... ")) 0)
  (.byte test3-str ,@(map char->integer (string->list "Test 3 - random fill ... ")) 0)
  (.byte test4-str ,@(map char->integer (string->list "Test 4 - bit fade    ... ")) 0)
  (.byte sleep-str ,@(map char->integer (string->list " sleeping for ~2 minutes ")) 0)

  (proc log-test-result .a-bits 16 .xy-bits 16
	bcs fail
	ldx (imm pass-str)
	jmp puts

	#:fail
	lda (dp 2)
	jsr puthex-word
	lda (dp 0)
	jsr puthex-word
	ldx (imm fail-str)
	jmp puts)

  (proc show-bank .a-bits 16 .xy-bits 16
	lda #x08
	jsr putc
	lda #x08
	jsr putc
	lda #x08
	jsr putc
	lda (dp 2)
	jsr puthex-byte
	lda #x20
	jmp putc)


  (proc test0 .a-bits 16 .xy-bits 16
	lda ,(bank-nr SDRAM-BASE)
	sta (dp 2)
	stz (dp 0)

	ldx (imm write-str)
	jsr puts

	#:fill-loop
	sep #b00100000 .a-bits 8
	lda 0
	sta (ind-far-dp 0)
	rep #b00100000 .a-bits 16

	inc (dp 0)
	bne fill-loop
	inc (dp 2)
	lda (dp 2)
	cmp ,(bank-nr SDRAM-END)
	beq fill-done
	jsr show-bank
	bra fill-loop

	#:fill-done
	lda ,(bank-nr SDRAM-BASE)
	sta (dp 2)
	stz (dp 0)

	ldx (imm check-str)
	jsr puts

	#:test-loop
	sep #b00100000 .a-bits 8
	lda (ind-far-dp 0)
	rep #b00100000 .a-bits 16
	bne fail

	inc (dp 0)
	bne test-loop
	inc (dp 2)
	lda (dp 2)
	cmp ,(bank-nr SDRAM-END)
	beq test-done
	jsr show-bank
	bra test-loop

	#:test-done
	clc
	rts

	#:fail
	sec
	rts)


  (proc test1 .a-bits 16 .xy-bits 16
	lda ,(bank-nr SDRAM-BASE)
	sta (dp 2)
	stz (dp 0)

	ldx (imm write-str)
	jsr puts

	ldy #x0001

	#:fill-loop
	sep #b00100000 .a-bits 8
	tya
	sta (ind-far-dp 0)
	asl (a-reg)
	bne fill-continue
	lda #x01
	#:fill-continue
	tay
	rep #b00100000 .a-bits 16

	inc (dp 0)
	bne fill-loop
	inc (dp 2)
	lda (dp 2)
	cmp ,(bank-nr SDRAM-END)
	beq fill-done
	jsr show-bank
	bra fill-loop

	#:fill-done
	lda ,(bank-nr SDRAM-BASE)
	sta (dp 2)
	stz (dp 0)

	ldx (imm check-str)
	jsr puts

	ldy #x0001

	#:test-loop
	sep #b00100000 .a-bits 8
	tya
	cmp (ind-far-dp 0)
	bne fail
	asl (a-reg)
	bne test-continue
	lda #x01
	#:test-continue
	tay
	rep #b00100000 .a-bits 16

	inc (dp 0)
	bne test-loop
	inc (dp 2)
	lda (dp 2)
	cmp ,(bank-nr SDRAM-END)
	beq test-done
	jsr show-bank
	bra test-loop

	#:test-done
	clc
	rts

	#:fail
	rep #b00100000 .a-bits 16
	sec
	rts)


  (proc test2 .a-bits 16 .xy-bits 16
	lda ,(bank-nr SDRAM-BASE)
	sta (dp 2)
	stz (dp 0)

	ldx (imm write-str)
	jsr puts

	ldy #x0001

	#:fill-loop
	sep #b00100000 .a-bits 8
	tya
	eor #xFF
	sta (ind-far-dp 0)
	eor #xFF
	asl (a-reg)
	bne fill-continue
	lda #x01
	#:fill-continue
	tay
	rep #b00100000 .a-bits 16

	inc (dp 0)
	bne fill-loop
	inc (dp 2)
	lda (dp 2)
	cmp ,(bank-nr SDRAM-END)
	beq fill-done
	jsr show-bank
	bra fill-loop

	#:fill-done
	lda ,(bank-nr SDRAM-BASE)
	sta (dp 2)
	stz (dp 0)

	ldx (imm check-str)
	jsr puts

	ldy #x0001

	#:test-loop
	sep #b00100000 .a-bits 8
	tya
	eor #xFF
	cmp (ind-far-dp 0)
	bne fail
	eor #xFF
	asl (a-reg)
	bne test-continue
	lda #x01
	#:test-continue
	tay
	rep #b00100000 .a-bits 16

	inc (dp 0)
	bne test-loop
	inc (dp 2)
	lda (dp 2)
	cmp ,(bank-nr SDRAM-END)
	beq test-done
	jsr show-bank
	bra test-loop

	#:test-done
	clc
	rts

	#:fail
	rep #b00100000 .a-bits 16
	sec
	rts)


  (proc rand
	php .a-bits 16 .xy-bits 16
	sep #b00100000 .a-bits 8

	ldy 8
	lda (dp 16)

	#:loop
	asl (a-reg)
	rol (dp 17)
	rol (dp 18)
	bcc skip-eor
	eor #x1B
	#:skip-eor
	dec (y-reg)
	bne loop
	sta (dp 16)

	plp rts)


  (proc test3 .a-bits 16 .xy-bits 16
	lda ,(bank-nr SDRAM-BASE)
	sta (dp 2)
	stz (dp 0)

	lda #x1234
	sta (dp 16)
	sta (dp 18)

	ldx (imm write-str)
	jsr puts

	#:fill-loop
	sep #b00100000 .a-bits 8
	jsr rand
	sta (ind-far-dp 0)
	rep #b00100000 .a-bits 16

	inc (dp 0)
	bne fill-loop
	inc (dp 2)
	lda (dp 2)
	cmp ,(bank-nr SDRAM-END)
	beq fill-done
	jsr show-bank
	bra fill-loop

	#:fill-done
	lda ,(bank-nr SDRAM-BASE)
	sta (dp 2)
	stz (dp 0)

	ldx (imm check-str)
	jsr puts

	lda #x1234
	sta (dp 16)
	sta (dp 18)

	#:test-loop
	sep #b00100000 .a-bits 8
	jsr rand
	cmp (ind-far-dp 0)
	rep #b00100000 .a-bits 16
	bne fail

	inc (dp 0)
	bne test-loop
	inc (dp 2)
	lda (dp 2)
	cmp ,(bank-nr SDRAM-END)
	beq test-done
	jsr show-bank
	bra test-loop

	#:test-done
	clc
	rts

	#:fail
	sec
	rts)


  (proc wait-1min .a-bits 16 .xy-bits 16
	lda (far-abs ,(far MMIO-BANK TIMER-TIME))
	dec (a-reg)
	pha

	#:loop
	lda (far-abs ,(far MMIO-BANK TIMER-TIME))
	cmp (stk 1)
	bne loop

	pla
	rts)


  (proc test4 .a-bits 16 .xy-bits 16
	lda ,(bank-nr SDRAM-BASE)
	sta (dp 2)
	stz (dp 0)

	lda #x5678
	sta (dp 16)
	sta (dp 18)

	ldx (imm write-str)
	jsr puts

	#:fill-loop
	sep #b00100000 .a-bits 8
	jsr rand
	sta (ind-far-dp 0)
	rep #b00100000 .a-bits 16

	inc (dp 0)
	bne fill-loop
	inc (dp 2)
	lda (dp 2)
	cmp ,(bank-nr SDRAM-END)
	beq fill-done
	jsr show-bank
	bra fill-loop

	#:fill-done
	lda ,(bank-nr SDRAM-BASE)
	sta (dp 2)
	stz (dp 0)

	ldx (imm sleep-str)
	jsr puts

	jsr wait-1min
	jsr wait-1min

	ldx (imm check-str)
	jsr puts

	lda #x5678
	sta (dp 16)
	sta (dp 18)

	#:test-loop
	sep #b00100000 .a-bits 8
	jsr rand
	cmp (ind-far-dp 0)
	rep #b00100000 .a-bits 16
	bne fail

	inc (dp 0)
	bne test-loop
	inc (dp 2)
	lda (dp 2)
	cmp ,(bank-nr SDRAM-END)
	beq test-done
	jsr show-bank
	bra test-loop

	#:test-done
	clc
	rts

	#:fail
	sec
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
