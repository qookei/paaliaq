(define MMU-FAULT-REASON #x010300)
(define MMU-PT-PTR #x010304)
(define MMU-TLB-FLUSH #x010308)


(list
 (.rodata
  (.asciz mmu-test-str "MMU test\r\n")
  (.asciz page-fault-str "Page fault! reason="))

 (.data
  (.word page-table
	 ,@(map
	    (λ (pfn)
	      (logior (ash pfn 4) ;; Physical address
		      (ash 1   2) ;; Executable
		      (ash 1   1) ;; Writable
		      (ash 1   0) ;; Present
		      ))
	   (iota #x800))))

 (.text
  (proc mmu-test .a-bits 16 .xy-bits 16
	ldx (imm mmu-test-str)
	jsr puts

	;; Load new page table
	lda (imm page-table)
	sta (far-abs ,MMU-PT-PTR)
	lda (imm 0)
	sta (far-abs ,(+ MMU-PT-PTR 2))

	;; Flush entire TLB
	lda (imm #x0001)
	sta (far-abs ,MMU-TLB-FLUSH)

	;; Write page table entry for #x200000, map to #x800000 as RW
	lda (imm #x8003)
	sta (far-abs page-table ,(ash #x200000 -11))

	;; Flush TLB entry for #x200000
	lda (imm #x2000)
	sta (far-abs ,MMU-TLB-FLUSH)

	;; Write some data
	lda (imm #x1234)
	sta (far-abs #x200000)

	;; Write page table entry for #x200000, map to #x801000 as RW
	lda (imm #x8013)
	sta (far-abs page-table ,(ash #x200000 -11))

	;; Flush TLB entry for #x200000
	lda (imm #x2000)
	sta (far-abs ,MMU-TLB-FLUSH)

	;; Write some data
	lda (imm #x5678)
	sta (far-abs #x200002)

	;; Check the underlying physical pages
	ldy (imm #x0080)
	ldx (imm #x0000)
	jsr dump-16-bytes
	ldy (imm #x0080)
	ldx (imm #x1000)
	jsr dump-16-bytes

	;; Write page table entry for #x200000, unmap
	lda (imm #x0000)
	sta (far-abs page-table ,(ash #x200000 -11))

	;; Flush TLB entry for #x200000
	lda (imm #x2000)
	sta (far-abs ,MMU-TLB-FLUSH)

	;; Install NMI handler
	lda (imm nmi-handler)
	sta (far-abs #x00FFEA)

	;; Test aborts
	lda (far-abs #x200ABC)
	nop
	sta (far-abs #x200ABC)

	rts)

  (proc nmi-handler
	rep #b00110000 .a-bits 16 .xy-bits 16
	pha
	phx
	phy

	ldx (imm page-fault-str)
	jsr puts

	lda (far-abs ,MMU-FAULT-REASON)
	tax
	lda (far-abs ,(+ MMU-FAULT-REASON 2))
	jsr puthex-dword
	jsr nl

	ply
	plx
	pla
	rti)

  (proc dump-16-bytes
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
	and (imm #x0F)
	bne loop

	jsr nl
	plp
	rts)))
