(define MMU-FAULT-REASON #x010300)
(define MMU-PT-PTR #x010304)
(define MMU-TLB-FLUSH #x010308)


(list
 (.rodata
  (.asciz mmu-test-str "MMU test\r\n")
  (.asciz page-fault-str "Page fault! reason=")
  (.asciz a=-str ", A="))

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

	;; Install abort handler
	lda (imm abort-handler)
	sta (far-abs #x00FFE8)

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

	;; Write page table entry for #x200000, map to #x801000 as RWX
	lda (imm #x8017)
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

	;; Test abort behavior for edge cases

	;; Write page table entry for #x1FF000, unmap
	lda (imm #x0000)
	sta (far-abs page-table ,(ash #x1FF000 -11))

	;; Write page table entry for #x201000, unmap
	lda (imm #x0000)
	sta (far-abs page-table ,(ash #x201000 -11))

	;; Write page table entry for #x004000, unmap
	lda (imm #x0000)
	sta (far-abs page-table ,(ash #x004000 -11))

	;; Flush TLB entries for #x1FF000, #x201000, #x004000
	lda (imm #x1FF0)
	sta (far-abs ,MMU-TLB-FLUSH)
	lda (imm #x2010)
	sta (far-abs ,MMU-TLB-FLUSH)
	lda (imm #x0040)
	sta (far-abs ,MMU-TLB-FLUSH)

	;; Prepare data on edges
	lda (imm #xAABB)
	sta (far-abs #x200000)
	lda (imm #xCCDD)
	sta (far-abs #x200FFE)
	lda (imm #xEEFF)

	;; Try fully unmapped write
	sta (far-abs #x201000)
	nop
	;; Try torn write
	sta (far-abs #x1FFFFF)
	nop
	;; Torn write to #x200FFF not tested -- the low byte would
	;; actually get written successfully...

	;; Try fully unmapped read
	lda (far-abs #x201000)
	nop
	;; Try torn reads
	lda (far-abs #x1FFFFF)
	nop
	lda (far-abs #x200FFF)
	nop

	;; Try aborting indirect read
	phd
	phe (imm #x4000)
	pld

	lda (ind-far-dp #x00)
	nop nop nop

	pld

	;; Try aborting instruction fetches
	;; First, try aborting on the opcode fetch

	;; Far call #x1FFFFF, then abort handler adds 4 => next insn executed is at #x200003

	;; Place RTL at the new address
	lda (imm #x6B6B)
	sta (far-abs #x200002)
	;; Jump to unmapped page
	jsl (far-abs #x1FFFFF)

	;; TODO: Test instruction fetch faults
	;; To test: operand bytes

	;; Write page table entry for #x200000, unmap
	lda (imm #x0000)
	sta (far-abs page-table ,(ash #x200000 -11))

	;; Flush TLB entry for #x200000
	lda (imm #x2000)
	sta (far-abs ,MMU-TLB-FLUSH)

	rts)

  (proc abort-handler
	,.a16xy16
	pha
	phx
	phy

	ldx (imm page-fault-str)
	jsr puts

	lda (far-abs ,MMU-FAULT-REASON)
	tax
	lda (far-abs ,(+ MMU-FAULT-REASON 2))
	jsr puthex-dword

	ldx (imm a=-str)
	jsr puts

	lda (stk 5)
	jsr puthex-word

	jsr nl

	;; Skip the faulting insns (sta far-abs).
	;; Lo word
	lda (stk 8)
	clc
	adc (imm 4)
	sta (stk 8)
	;; Hi word
	lda (stk 10)
	adc (imm 0)
	sta (stk 10)

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
	,.a8
	lda (y-ind-far-dp 0)
	,.a16
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
