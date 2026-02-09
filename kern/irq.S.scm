(define (make-entry-proc handler-proc)
  `(()
    phb
    phd
    rep #b00110000 .a-bits 16 .xy-bits 16
    pha
    phx
    phy

    ;; Switch to kernel bank.
    phe #x8080
    plb plb

    ;; TODO: Increment task's IRQ depth. If the depth is now 1, switch
    ;; stack to the task's kernel stack.

    tsc
    inc (a-reg)
    pha
    jsr ,handler-proc
    pla

    ;; TODO: Decrement task's IRQ depth. If the depth reaches 0,
    ;; switch back to user stack before returning.

    ply
    plx
    pla
    pld
    plb
    rti))


(list
 (.rodata
  (.word vector-table
	 ,@(map (λ (i)
		  (+ #xFFA0 (* i 4)))
		(iota 16)))
  (.asciz cop-str "COP interrupt\r\n")
  (.asciz brk-str "BRK interrupt\r\n")
  (.asciz abort-str "ABORT interrupt\r\n")
  (.asciz nmi-str "NMI interrupt\r\n")
  (.asciz irq-str "IRQ interrupt\r\n"))

 (.text
  (proc irq-init .a-bits 16 .xy-bits 16
	phb

	;; Copy vector table into the right place
	lda ,(1- (* 2 16))
	ldx vector-table
	ldy #xFFE0
	mvn (#x00 #x80)

	;; Copy vector trampoline into the right place
	lda ,(1- (* 4 16))
	ldx vector-trampoline
	ldy #xFFA0
	mvn (#x00 #x80)

	plb
	rts)


  ;; Note: this trampoline will be copied to #x00FFA0, since vectors
  ;; have to be in bank 0.
  ;; Each entry takes 4 bytes to make computing offsets into the
  ;; trampoline easier.
  (proc vector-trampoline
	;; Native mode vectors
	stp nop nop nop			; reserved
	stp nop nop nop			; reserved
	jmp (far-abs %cop-entry)
	jmp (far-abs %brk-entry)
	jmp (far-abs %abort-entry)
	jmp (far-abs %nmi-entry)
	stp nop nop nop			; reserved
	jmp (far-abs %irq-entry)

	;; Emulation mode vectors
	;; For now, emulation mode is unsupported
	stp nop nop nop			; reserved
	stp nop nop nop			; reserved
	stp nop nop nop			; cop
	stp nop nop nop			; reserved
	stp nop nop nop			; abort
	stp nop nop nop			; nmi
	stp nop nop nop			; reset
	stp nop nop nop)		; irq/brk

  (proc %cop-entry ,(make-entry-proc 'cop-handler))
  (proc %brk-entry ,(make-entry-proc 'brk-handler))
  (proc %abort-entry ,(make-entry-proc 'abort-handler))
  (proc %nmi-entry ,(make-entry-proc 'nmi-handler))
  (proc %irq-entry ,(make-entry-proc 'irq-handler))

  (proc cop-handler .a-bits 16 .xy-bits 16
	ldx cop-str
	jsr puts
	rts)

  (proc brk-handler .a-bits 16 .xy-bits 16
	ldx brk-str
	jsr puts
	rts)

  (proc abort-handler .a-bits 16 .xy-bits 16
	ldx abort-str
	jsr puts
	rts)

  (proc nmi-handler .a-bits 16 .xy-bits 16
	ldx nmi-str
	jsr puts
	rts)

  (proc irq-handler .a-bits 16 .xy-bits 16
	ldx irq-str
	jsr puts
	rts)))
