(list
 (.data
  (.word video-colors #x000F))
 (.bss
  (.zero video-cursor-x 2)
  (.zero video-cursor-y 2))
 (.text
  (proc video-update-cursor .a-bits 16 .xy-bits 16
	lda (far-abs video-cursor-x)
	sta (far-abs #x010500)
	lda (far-abs video-cursor-y)
	sta (far-abs #x010502)

	rts)

  (proc video-scroll .a-bits 16 .xy-bits 16
	phb

	lda ,(1- (* 128 47 4))
	ldx ,(* 128 4)
	ldy 0
	mvn (seg-from-to #x10 #x10)

	lda #x0020
	sta (abs ,(* 128 47 4))
	lda (far-abs video-colors)
	sta (abs ,(+ (* 128 47 4) 1))

	ldx ,(* 128 47 4)
	ldy ,(+ 4 (* 128 47 4))
	lda ,(- (* 128 4) 5)
	mvn (seg-from-to #x10 #x10)

	lda 47
	sta (far-abs video-cursor-y)
	jsr video-update-cursor

	plb
	rts)

  (proc video-clear .a-bits 16 .xy-bits 16
	phb

	phe #x1010
	plb plb

	lda #x0020
	sta (abs #x0000)
	lda (far-abs video-colors)
	sta (abs #x0001)
	ldx #x0000
	ldy #x0004
	lda ,(- (* 128 48 4) 5)
	mvn (seg-from-to #x10 #x10)

	lda 0
	sta (far-abs video-cursor-x)
	sta (far-abs video-cursor-y)
	jsr video-update-cursor

	plb
	rts)

  (proc video-putc
	php
	rep #b00100000 .a-bits 16 .xy-bits 16

	cmp ,(char->integer #\backspace)
	beq backspace
	cmp ,(char->integer #\cr)
	beq carriage-return
	cmp ,(char->integer #\lf)
	beq linefeed
	bra do-print

	#:carriage-return
	stz (abs video-cursor-x)
	bra done

	#:linefeed
	inc (abs video-cursor-y)
	lda (abs video-cursor-y)
	cmp 48
	bne done
	jsr video-scroll
	bra done


	#:backspace
	lda (abs video-cursor-x)
	beq done
	dec (abs video-cursor-x)
	bra done

	#:do-print
	pha

	lda (abs video-cursor-y)
	xba
	lsr (a-reg)
	clc
	adc (abs video-cursor-x)
	asl (a-reg)
	asl (a-reg)
	tax

	pla

	phb
	phe #x1010
	plb plb

	sep #b00100000 .a-bits 8
	sta (x-abs #x0000)
	rep #b00100000 .a-bits 16
	lda (far-abs video-colors)
	sta (x-abs #x0001)

	plb

	inc (abs video-cursor-x)
	lda (abs video-cursor-x)
	cmp 128
	bne done

	stz (abs video-cursor-x)
	inc (abs video-cursor-y)
	lda (abs video-cursor-y)
	cmp 48
	bne done
	jsr video-scroll

	#:done
	jsr video-update-cursor
	plp
	rts)

  (proc video-show-colors .a-bits 16 .xy-bits 16
	ldx (imm 0)

	#:loop
	phx
	txa
	xba
	sta (abs video-colors)
	lda ,(char->integer #\space)
	jsr video-putc
	lda ,(char->integer #\space)
	jsr video-putc
	plx

	inc (x-reg)
	cpx (imm 256)
	beq done
	txa
	and (imm #x000F)
	bne loop
	phx
	lda ,(char->integer #\cr)
	jsr video-putc
	lda ,(char->integer #\lf)
	jsr video-putc
	plx
	bra loop

	#:done
	lda #x000F
	sta (abs video-colors)

	lda ,(char->integer #\cr)
	jsr video-putc
	lda ,(char->integer #\lf)
	jsr video-putc

	lda #x000F
	sta (abs video-colors)

	lda ,(char->integer #\cr)
	jsr video-putc
	lda ,(char->integer #\lf)
	jsr video-putc

	rts)
  ))
