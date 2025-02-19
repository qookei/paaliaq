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

	ldx (imm header-str)
	jsr puts

	jsr clear-sdram

	ldx (imm choice-str)
	jsr puts

	#:choice
	jsr getc
	and #xFF
	cmp ,(char->integer #\0)
	beq serial-boot

	ldx (imm bad-choice-str)
	jsr puts
	bra choice)

  (.byte header-str ,@(map char->integer (string->list "Paaliaq boot0\r\nSDRAM init...   ")) 0)
  (.byte choice-str ,@(map char->integer (string->list "\r\nPress 0 for serial boot.\r\n")) 0)
  (.byte bad-choice-str ,@(map char->integer (string->list "Bad choice\r\n")) 0)

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

  (.byte bye-str ,@(map char->integer (string->list "Bye, going to ")) 0)
  (.byte crnl-str ,@(map char->integer (string->list "\r\n")) 0)

  (proc show-bank .a-bits 16 .xy-bits 16
	lda #x08
	jsr putc
	lda #x08
	jsr putc
	lda (dp 2)
	jmp puthex-byte)

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

  (proc getc
	php phb
	phe ,(bank-plb MMIO-BANK)
	plb plb

	sep #b00100000 .a-bits 8
	#:rx-empty
	bit (abs ,UART0-STATUS)
	bvc rx-empty

	lda (abs ,UART0-RX-DATA)

	plb plp
	rts)

  (.byte hex-digits ,@(map char->integer (string->list "0123456789abcdef")))))
