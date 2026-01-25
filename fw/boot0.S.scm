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

  (.asciz hw-rev-str "Running on HW rev ")
  (.asciz rev-unk-str "<unknown-revision>")
  (.asciz rev-dirty-str "-dirty")

  (.asciz sdram-init-str "SDRAM init...    ")
  (.asciz sdram-init-done-str " done!\r\n")

  (.asciz pmc-clks-str "CPU clocks=")
  (.asciz pmc-ms-str " timer ms=")

  (.asciz choices-str "Press: 1 for memory test, 2 for UART echo, 3 for MMU test.\r\n")
  (.asciz bad-choice-str "Incorrect selection.\r\n")

  (.asciz crnl-str "\r\n"))

 (.text
  (proc main .a-bits 16 .xy-bits 16
	jsr video-clear

	ldx (imm header-str)
	jsr puts

	jsr print-hw-rev

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

	cmp ,(char->integer #\1)
	beq do-memory-test

	cmp ,(char->integer #\2)
	beq do-echo

	cmp ,(char->integer #\3)
	beq do-mmu-test

	cmp ,(char->integer #\r)
	beq maybe-do-zmodem-1

	#:bad-choice
	ldx (imm bad-choice-str)
	jsr puts
	jsr video-scroll
	bra choice

	#:do-memory-test
	jmp memory-test
	#:do-echo
	jmp echo
	#:do-mmu-test
	jsr mmu-test
	bra prompt
	#:maybe-do-zmodem-1
	jsr getc
	cmp ,(char->integer #\z)
	bne bad-choice

	jsr getc
	cmp ,(char->integer #\return)
	bne bad-choice

	jmp zmodem-receive)

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


  (proc echo .a-bits 16 .xy-bits 16
	#:loop
	jsr getc

	;; Perform ICRNL
	cmp ,(char->integer #\cr)
	bne just-putc
	jsr nl
	bra loop

	#:just-putc
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
	rts)


  (proc print-hw-rev .a-bits 16 .xy-bits 16
	ldx hw-rev-str
	jsr puts

	lda (far-abs #x010700)
	sta (dp 0)
	lda (far-abs #x010702)
	sta (dp 2)

	sep #b00100000 .a-bits 8
	lda (dp 3)
	rep #b00100000 .a-bits 16
	bpl unknown
	jsr puthex-nibble
	lda (dp 1)
	jsr puthex-word
	lda (dp 0)
	jsr puthex-byte

	sep #b00100000 .a-bits 8
	bit (dp 3)
	rep #b00100000 .a-bits 16
	bvc done

	ldx rev-dirty-str
	jsr puts
	bra done

	#:unknown
	ldx rev-unk-str
	jsr puts

	#:done
	jsr nl
	rts)


  )
 )
