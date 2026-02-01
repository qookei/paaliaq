(list
 (.rodata
  (.asciz hex-digits "0123456789abcdef"))
 (.text
  (proc putc
	jsr uart-putc
	rts)

  (proc getc .a-bits 16 .xy-bits 16
	jsr uart-getc
	and #xFF
	rts)


  (proc puts .a-bits 16 .xy-bits 16
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
	jmp puthex-byte)

  (proc puthex-dword
	.a-bits 16 .xy-bits 16
	phx
	jsr puthex-word
	pla
	jmp puthex-word)))
