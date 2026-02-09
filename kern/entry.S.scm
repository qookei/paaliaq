(define TIMER-TIME #x010104)
(define PMC-CLKS #x010400)

(list
 (.head.text
  (proc _start
	;; We know we are in native mode
	rep #b00110000 .a-bits 16 .xy-bits 16

	;; Set data bank
	phe #x8080
	plb plb

	;; Set stack pointer
	ldx (imm #xEFFF)
	txs

	jmp kmain))

 (.rodata
  (.asciz header-str (format #f "Paaliaq kernel, rev ~a.\r\n"
			     (getenv "GIT_REV")))

  (.asciz hw-rev-str "Running on HW rev ")
  (.asciz rev-unk-str "<unknown-revision>")
  (.asciz rev-dirty-str "-dirty")
  (.asciz all-done-str "All done for now.\r\n")

  (.asciz crnl-str "\r\n"))

 (.text
  (proc kmain .a-bits 16 .xy-bits 16
	ldx 25
	#:loop
	phx
	ldx crnl-str
	jsr puts
	plx
	dec (x-reg)
	bne loop

	ldx (imm header-str)
	jsr puts

	jsr print-hw-rev

	jsr pmm-init
	jsr irq-init

	cop #x42

	ldx all-done-str
	jsr puts

	stp)


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
	ldx crnl-str
	jsr puts
	rts)


  )
 )
