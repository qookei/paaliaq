(list
 (.head.text
  (proc _start .a-bits 8 .xy-bits 8
	clc
	xce
	sei

	rep #b00110000 .a-bits 16 .xy-bits 16
	ldx (imm #x7FFF)
	txs

	jmp main))

 (.rodata
  (.asciz header-str (format #f "\r\n\r\n\r\nPaaliaq boot0, rev ~a.\r\n"
			     (getenv "GIT_REV")))

  (.asciz sdram-init-str "SDRAM init...    ")
  (.asciz sdram-init-done-str " done!\r\n")

  (.asciz choices-str "Press: 0 for serial boot, 1 for memory test.\r\n")
  (.asciz bad-choice-str "Incorrect selection.\r\n")

  (.asciz bye-str "Bye, going to ")
  (.asciz crnl-str "\r\n"))

 (.text
  (proc main .a-bits 16 .xy-bits 16
	ldx (imm header-str)
	jsr puts

	ldx (imm sdram-init-str)
	jsr puts
	jsr clear-sdram
	ldx (imm sdram-init-done-str)
	jsr puts

	ldx (imm choices-str)
	jsr puts

	jsr video-test

	#:choice
	jsr getc
	and #xFF

	cmp ,(char->integer #\0)
	beq do-serial-boot

	cmp ,(char->integer #\1)
	beq do-memory-test

	ldx (imm bad-choice-str)
	jsr puts
	bra choice

	#:do-serial-boot
	jmp serial-boot
	#:do-memory-test
	jmp memory-test)

  (proc video-test .a-bits 16 .xy-bits 16
	phb
	phe #x1010
	plb plb

	lda #x1234
	sta (dp 16)
	sta (dp 18)

	ldx 0

	sep #b00100000 .a-bits 8
	#:loop
	jsr rand
	sta (x-abs #x0000)

	inc (x-reg)
	cpx ,(* 128 48 2)
	bne loop
	rep #b00100000 .a-bits 16

	plb
	rts)

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

  (proc clear-sdram .a-bits 16 .xy-bits 16
	lda #x0080
	sta (dp 2)
	stz (dp 0)

	#:loop
	jsr show-bank
	lda 0
	sta (ind-far-dp 0)

	lda #xfffe
	ldx #x0000
	ldy #x0001
	phb
	#:mvn-insn
	mvn (seg-from-to #x80 #x80)
	plb

	sep #b00100000 .a-bits 8
	inc (abs mvn-insn 1)
	inc (abs mvn-insn 2)
	inc (dp 2)
	rep #b00100000 .a-bits 16
	bne loop

	rts)


  (proc serial-boot .a-bits 16 .xy-bits 16
	;; 0,1,2 - cur ptr
	;; 4,5,6 - entry ptr
	;; 8,9 - bytes left

	;; Get load address
	jsr getc
	sta (dp 0)
	sta (dp 4)
	jsr getc
	sta (dp 1)
	sta (dp 5)
	jsr getc
	sta (dp 2)
	sta (dp 6)

	sep #b00100000 .a-bits 8
	stz (dp 3)
	stz (dp 7)
	rep #b00100000 .a-bits 16

	;; Get load size
	jsr getc
	sta (dp 8)
	jsr getc
	sta (dp 9)

	#:load-loop
	jsr getc
	sep #b00100000 .a-bits 8
	sta (ind-far-dp 0)
	rep #b00100000 .a-bits 16

	inc (dp 0)
	bne dec-left
	inc (dp 2)

	#:dec-left
	dec (dp 8)
	bne load-loop

	ldx (imm bye-str)
	jsr puts
	lda (dp 6)
	jsr puthex-byte
	lda (dp 4)
	jsr puthex-word
	ldx (imm crnl-str)
	jsr puts

	jml (ind-abs #x0004))))
