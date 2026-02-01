(define +nr-pages+ (quotient (* 8 1024 1024) 4096))
(define +page-entry-size+ 16)

(define +page-entry-array-size+ (* +nr-pages+ +page-entry-size+))
(define +page-entry-array-base+ #x810000)
(define +page-entry-array-end+ (+ #x810000 +page-entry-array-size+))

(define +sdram-base-nr+ (quotient #x800000 4096))
(define +first-free-page-nr+ (quotient +page-entry-array-end+ 4096))
(define +top-of-mem-nr+ (quotient #x1000000 4096))

;; Physical memory layout:
;; [#x800000, #x810000) - the kernel image
;; [#x810000, #x818000) - struct page array
;; [#x818000, #x81ffff] - free memory
;;
;; This will likely move around a bunch (e.g. as the kernel grows above 64K),
;; but this is a good starting point.
;;
;; struct page layout:
;; [0, 1) - state
;;   - 0 - reserved
;;   - 1 - unused
;;   - 2 - taken
;; [1, 3) - free list link
;;   offset into the array for the next page in the chain
;; [3, 16) - currently unused
;;
;; struct page array offsets are computed as:
;;   (PFN - #x800) << 4
;; And conversely, to turn the offset into a PFN:
;;   (offset >> 4) + #x800

(define +page-entry-state+ 0)
(define +page-entry-link+ 1)

(list
 (.data
  (.word pmm-nr-free 0)
  (.word pmm-free-list-head 0))

 (.rodata
  (.asciz pmm-init-str "pmm: init\r\n")
  (.asciz pmm-nr-free-str "pmm: number of free pages: #x")
  (.asciz pmm-not-our-str "pmm: not our page #x")
  (.asciz pmm-not-our-trailing-str "000\r\n"))

 (.text
  (proc pmm-init .a-bits 16 .xy-bits 16
	ldx pmm-init-str
	jsr puts

	;; Mark all usable pages as free
	ldx ,+first-free-page-nr+
	#:loop
	phx
	jsr pmm-free
	plx
	inc (x-reg)
	cpx ,+top-of-mem-nr+
	bne loop

	ldx pmm-nr-free-str
	jsr puts
	lda (abs pmm-nr-free)
	jsr puthex-word
	ldx crnl-str
	jsr puts

	rts)

  (proc pmm-alloc .a-bits 16 .xy-bits 16
	php sei

	;; Any pages left?
	lda (abs pmm-nr-free)
	beq done

	;; Unlink page
	ldx (abs pmm-free-list-head)
	lda (x-far-abs ,(+ +page-entry-array-base+ +page-entry-link+))
	sta (abs pmm-free-list-head)

	;; Mark as taken
	lda 2
	sep #b00100000 .a-bits 8
	sta (x-far-abs ,(+ +page-entry-array-base+ +page-entry-state+))
	rep #b00100000 .a-bits 16

	txa
	;; Turn into PFN
	lsr (a-reg)
	lsr (a-reg)
	lsr (a-reg)
	lsr (a-reg)
	clc
	adc ,+sdram-base-nr+

	#:done
	plp
	rts)

  (proc pmm-free .a-bits 16 .xy-bits 16
	php sei

	inc (abs pmm-nr-free)

	lda (stk 4)
	cmp ,+sdram-base-nr+
	bcs do-free

	;; Not a page that's managed by the PMM
	;; TODO: proper panic function
	pha
	ldx pmm-not-our-str
	jsr puts
	pla
	jsr puthex-word
	ldx pmm-not-our-trailing-str
	jsr puts

	stp

	#:do-free
	sec
	sbc ,+sdram-base-nr+
	asl (a-reg)
	asl (a-reg)
	asl (a-reg)
	asl (a-reg)
	tax

	;; Link page into free list
	lda (abs pmm-free-list-head)
	stx (abs pmm-free-list-head)
	sta (x-far-abs ,(+ +page-entry-array-base+ +page-entry-link+))

	;; Mark as free
	lda 1
	sep #b00100000 .a-bits 8
	sta (x-far-abs ,(+ +page-entry-array-base+ +page-entry-state+))
	rep #b00100000 .a-bits 16

	plp rts)
  )
 )
