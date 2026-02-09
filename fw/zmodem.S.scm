(define hdrbuf #x80)
(define ZDLE #x18)

(list
 (.rodata
  (.asciz aborted-str "\r\n\r\n\r\n\r\n\r\nZMODEM transfer aborted!\r\n")
  (.asciz zrinit-str "**\x18B0100000000aa51\x0d\x8a")
  (.asciz zrpos-str "**\x18B0900000000a87c\x0d\x8a")
  (.asciz zfin-str "**\x18B0800000000022d\x0d\x8a")
  (.asciz uart-overflow-str "\r\nUART RX buffer overflow occurred!\r\n")
  (.asciz bye-loaded-str "\r\nBye! Jumping to #x800000...\r\n"))

 (.text
  (proc zmodem-cancel .a-bits 16 .xy-bits 16
	lda (imm ,(char->integer #\can))
	jsr uart-putc
	lda (imm ,(char->integer #\can))
	jsr uart-putc
	lda (imm ,(char->integer #\can))
	jsr uart-putc
	lda (imm ,(char->integer #\can))
	jsr uart-putc
	lda (imm ,(char->integer #\can))
	jsr uart-putc

	ldx (imm aborted-str)
	jsr puts
	#:loop
	bra loop)

  (proc zmodem-rx-hex-byte .a-bits 16 .xy-bits 16
	jsr getc

	cmp ,(char->integer #\a)
	bcs hi-alpha
	sec
	sbc ,(char->integer #\0)
	bra next
	#:hi-alpha
	sbc ,(- (char->integer #\a) 10)
	#:next

	asl (a-reg)
	asl (a-reg)
	asl (a-reg)
	asl (a-reg)
	pha

	jsr getc

	cmp ,(char->integer #\a)
	bcs lo-alpha
	sec
	sbc ,(char->integer #\0)
	bra combine
	#:lo-alpha
	sbc ,(- (char->integer #\a) 10)
	#:combine

	ora (stk 1)
	plx

	rts)

  (proc zmodem-rx-bin-byte .a-bits 16 .xy-bits 16
	#:again
	jsr getc

	;; Fast path for printable characters
	bit #x60
	bne done

	;; Ignore XON/XOFF (with or without MSB)
	cmp ,(char->integer #\dc1)
	beq again
	cmp ,(logior #x80 (char->integer #\dc1))
	beq again
	cmp ,(char->integer #\dc3)
	beq again
	cmp ,(logior #x80 (char->integer #\dc3))
	beq again

	cmp ,ZDLE
	beq again2
	rts

	#:again2
	;; ZDLE escape sequence
	jsr getc

	;; Ignore XON/XOFF (with or without MSB)
	cmp ,(char->integer #\dc1)
	beq again2
	cmp ,(logior #x80 (char->integer #\dc1))
	beq again2
	cmp ,(char->integer #\dc3)
	beq again2
	cmp ,(logior #x80 (char->integer #\dc3))
	beq again2

	;; All the ZCRC* codes
	cmp ,(char->integer #\h)
	beq ZCRC*
	cmp ,(char->integer #\i)
	beq ZCRC*
	cmp ,(char->integer #\j)
	beq ZCRC*
	cmp ,(char->integer #\k)
	beq ZCRC*
	bra not-ZCRC*

	#:ZCRC*
	ora #x0100
	rts

	#:not-ZCRC*

	;; ZRUB0/1
	cmp ,(char->integer #\l)
	bne not-ZRUB0
	lda #x7f
	rts
	#:not-ZRUB0
	cmp ,(char->integer #\m)
	bne not-ZRUB1
	lda #xff
	rts
	#:not-ZRUB1

	;; Assume this is an escaped control character
	eor #x40

	#:done
	rts)

  (proc zmodem-rx-header .a-bits 16 .xy-bits 16
	jsr zmodem-rx-bin-byte
	cmp ,(char->integer #\*)
	bne abort

	jsr getc
	cmp ,(char->integer #\*)
	bne bin-hdr

	jsr getc
	cmp ,ZDLE
	bne abort

	jsr getc
	cmp ,(char->integer #\B)
	bne abort

	ldx (imm 0)
	#:hex-rcv-loop
	phx
	jsr zmodem-rx-hex-byte

	plx
	sta (x-dp ,hdrbuf)

	inc (x-reg)
	cpx (imm 7)
	bne hex-rcv-loop

	jsr getc
	cmp ,(char->integer #\return)
	bne abort

	jsr getc
	cmp ,(logior #x80 (char->integer #\linefeed))
	bne abort

	bra done

	#:bin-hdr
	cmp ,ZDLE
	bne abort

	jsr getc

	ldy (imm 7)
	cmp ,(char->integer #\A)
	beq got-len
	ldy (imm 9)
	cmp ,(char->integer #\C)
	bne abort
	#:got-len

	ldx (imm 0)
	#:bin-rcv-loop
	phx phy
	jsr zmodem-rx-bin-byte

	ply plx
	sta (x-dp ,hdrbuf)

	inc (x-reg)
	dec (y-reg)
	bne bin-rcv-loop

	#:done
	rts
	#:abort
	jmp zmodem-cancel)

  (proc zmodem-send-zrinit .a-bits 16 .xy-bits 16
	ldx zrinit-str
	jsr uart-puts
	rts)

  (proc zmodem-send-zrpos .a-bits 16 .xy-bits 16
	ldx zrpos-str
	jsr uart-puts
	rts)

  (proc zmodem-send-zfin .a-bits 16 .xy-bits 16
	ldx zfin-str
	jsr uart-puts
	rts)

  (proc zmodem-read-until-nul .a-bits 16 .xy-bits 16
	#:loop
	jsr getc
	cmp 0
	bne loop

	rts)

  (proc zmodem-read-until-xon .a-bits 16 .xy-bits 16
	#:loop
	jsr getc
	cmp #x11
	bne loop

	rts)

  (proc zmodem-rx-file-data .a-bits 16 .xy-bits 16
	;; Receive ZDATA
	jsr zmodem-rx-header
	lda (dp ,hdrbuf)
	and #xff
	cmp #x0a
	beq prepare
	jmp zmodem-cancel

	#:prepare
	stz (dp 0)
	lda #x0080
	sta (dp 2)

	;; Receive actual data bytes
	#:loop
	jsr zmodem-rx-bin-byte

	cmp #x100
	bcs special

	sep #b00100000 .a-bits 8
	sta (ind-far-dp 0)
	rep #b00100000 .a-bits 16

	inc (dp 0)
	bne no-carry
	inc (dp 2)
	#:no-carry
	bra loop

	#:special
	cmp #x168
	beq ZCRCE
	cmp #x169
	beq ZCRCG
	cmp #x16a
	beq ZCRCQ
	cmp #x16b
	beq ZCRCW
	bra loop

	#:ZCRCE
	;; Skip CRC, then we're done
	jsr zmodem-rx-bin-byte
	jsr zmodem-rx-bin-byte
	rts

	#:ZCRCG
	;; Skip CRC, then data continues
	jsr zmodem-rx-bin-byte
	jsr zmodem-rx-bin-byte
	bra loop

	#:ZCRCQ
	;; Skip CRC, then ZACK, then data continues
	jsr zmodem-rx-bin-byte
	jsr zmodem-rx-bin-byte
	;; TODO
	jmp zmodem-cancel

	#:ZCRCW
	;; Skip CRC, then ZACK, then end of frame
	jsr zmodem-rx-bin-byte
	jsr zmodem-rx-bin-byte
	;; TODO
	jmp zmodem-cancel)

  ;; Extremely minimal error checking
  ;; Assumes the link is perfect, and that the sender knows what they're doing
  ;; No CRC checks, only tested with lszrz's sz command.
  (proc zmodem-receive .a-bits 16 .xy-bits 16
	;; First, expect ZRQINIT
	jsr zmodem-rx-header
	lda (dp ,hdrbuf)
	and #xff
	bne abort
	;; Respond with ZRINIT
	jsr zmodem-send-zrinit

	;; Then, expect ZFILE
	jsr zmodem-rx-header
	lda (dp ,hdrbuf)
	and #xff
	cmp #x04
	bne abort

	;; Receive filename (don't care)
	jsr zmodem-read-until-nul
	;; Receive file info (don't care)
	jsr zmodem-read-until-nul

	;; Receive ZCRCW (don't care)
	jsr zmodem-read-until-xon

	;; Respond with ZRPOS to start
	jsr zmodem-send-zrpos

	;; Finally, receive the actual data
	jsr zmodem-rx-file-data

	;; Receive ZEOF
	jsr zmodem-rx-header
	lda (dp ,hdrbuf)
	and #xff
	cmp #x0b
	bne abort

	;; Respond with ZRINIT
	jsr zmodem-send-zrinit

	;; Receive ZFIN
	jsr zmodem-rx-header
	lda (dp ,hdrbuf)
	and #xff
	cmp #x08
	bne abort

	;; Respond with ZFIN
	jsr zmodem-send-zfin

	;; Receive final "OO"
	jsr getc
	jsr getc

	;; Check if we overflowed the UART buffer at some point
	sep #b00100000 .a-bits 8
	lda (far-abs #x010001)
	rep #b00100000 .a-bits 16
	bit #x10
	bne overflow

	ldx bye-loaded-str
	jsr puts

	;; Jump to the loaded binary
	jmp (far-abs #x800000)

	#:loop
	bra loop

	#:overflow
	ldx uart-overflow-str
	jsr puts
	bra loop

	#:abort
	jmp zmodem-cancel)))
