(define TIMER-TIME #x010104)
(define PMC-CLKS #x010400)

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

  (.asciz pmc-clks-str "CPU clocks=")
  (.asciz pmc-ms-str " timer ms=")

  (.asciz choices-str "Press: 0 for serial boot, 1 for memory test, 2 for UART echo, 3 for MMU test.\r\n")
  (.asciz bad-choice-str "Incorrect selection.\r\n")

  (.asciz bye-str "Bye, going to ")
  (.asciz crnl-str "\r\n"))

 (.text
  (proc main .a-bits 16 .xy-bits 16
	jsr video-clear

	ldx (imm header-str)
	jsr puts

	ldx (imm sdram-init-str)
	jsr puts
	jsr clear-sdram
	ldx (imm sdram-init-done-str)
	jsr puts

	jsr pmc-measure

	#:prompt
	ldx (imm choices-str)
	jsr puts

	#:choice
	jsr getc
	and #xFF

	cmp ,(char->integer #\0)
	beq do-serial-boot

	cmp ,(char->integer #\1)
	beq do-memory-test

	cmp ,(char->integer #\2)
	beq do-echo

	cmp ,(char->integer #\3)
	beq do-mmu-test

	ldx (imm bad-choice-str)
	jsr puts
	jsr video-scroll
	bra choice

	#:do-serial-boot
	jmp serial-boot
	#:do-memory-test
	jmp memory-test
	#:do-echo
	jmp echo
	#:do-mmu-test
	jsr mmu-test
	bra prompt)

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

	jml (ind-abs #x0004))


  (proc echo .a-bits 16 .xy-bits 16
	#:loop
	jsr getc
	jsr putc
	bra loop)


  (proc pmc-measure .a-bits 16 .xy-bits 16
	lda (far-abs ,TIMER-TIME)
	pha
	lda (far-abs ,(+ TIMER-TIME 2))
	pha
	lda (far-abs ,PMC-CLKS)
	pha
	lda (far-abs ,(+ PMC-CLKS 2))
	pha

	ldx (imm pmc-clks-str)
	jsr puts
	pla
	plx
	jsr puthex-dword

	ldx (imm pmc-ms-str)
	jsr puts
	pla
	plx
	jsr puthex-dword

	jsr nl
	rts))
 )
