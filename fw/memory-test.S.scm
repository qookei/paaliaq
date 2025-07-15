(define SDRAM-BASE #x800000)
(define SDRAM-END #x1000000)

(define MMIO-BANK #x01)

(define TIMER-TIME #x0014)


(define (bank-nr addr)
  (ash addr -16))

(define (far bank addr)
  (logior addr (ash bank 16)))


(list
 (.rodata
  (.asciz memory-test-str "Starting memory test.\r\n")

  (.asciz pass-str " PASS\r\n")
  (.asciz fail-str " FAIL\r\n")

  (.asciz write-str " writing 80 ")
  (.asciz check-str " checking 80 ")

  (.asciz test1-str "Test 1 - walking 1s  ... ")
  (.asciz test2-str "Test 2 - walking 0s  ... ")
  (.asciz test3-str "Test 3 - random fill ... ")
  (.asciz test4-str "Test 4 - bit fade    ... ")

  (.asciz sleep-str " sleeping for ~2 minutes "))

 (.text
  (proc memory-test .a-bits 16 .xy-bits 16
	ldx (imm memory-test-str)
	jsr puts

	#:tests

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


  (proc dump-256-bytes
	php .a-bits 16 .xy-bits 16

	sty (dp 2)
	stz (dp 0)

	txy

	#:heading
	lda (dp 2)
	jsr puthex-byte
	phy
	tya
	jsr puthex-word
	lda #x20
	jsr putc
	ply

	#:loop
	sep #b00100000 .a-bits 8
	lda (y-ind-far-dp 0)
	rep #b00100000 .a-bits 16
	phy
	jsr puthex-byte
	lda #x20
	jsr putc
	ply
	inc (y-reg)
	tya
	and (imm #xFF)
	beq done
	and (imm #x0F)
	bne loop
	jsr nl
	bra heading

	#:done
	jsr nl
	plp
	rts)

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
	jsr puts

	ldy (dp 2)
	lda (dp 0)
	and #xFF00
	tax
	jsr dump-256-bytes
	rts)

  (proc nl
	.a-bits 16 .xy-bits 16
	lda (imm ,(char->integer #\return))
	jsr putc
	lda (imm ,(char->integer #\linefeed))
	jmp putc)


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
	rts)))
