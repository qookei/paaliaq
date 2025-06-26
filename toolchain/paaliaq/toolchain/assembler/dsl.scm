(define-module (paaliaq toolchain assembler dsl)
  #:use-module (paaliaq toolchain assembler core)
  #:use-module (paaliaq toolchain elf sections)
  #:use-module (paaliaq toolchain elf defines)
  #:use-module (paaliaq toolchain elf format)
  ;; Only select {open,get}-output-bytevector to avoid warnings
  ;; about (scheme base) redeclaring core procedures
  #:use-module ((scheme base) #:select (open-output-bytevector
					get-output-bytevector))
  #:use-module (ice-9 binary-ports)
  #:use-module (rnrs bytevectors)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9 gnu)

  #:export (.head.text
	    .text
	    .rodata
	    .data
	    .bss

	    proc
	    .byte
	    .word
	    .fword
	    .dword
	    .zero

	    random-label
	    label-decl

	    proc-prologue
	    proc-epilogue

	    local
	    param
	    y-ind-param
	    y-ind-far-param))


(define (%data-size body)
  (match body
    ['() 0]
    [(? elf-symbol?) 0]
    [(? elf-reloc?) 0]
    [(? number?) 1]
    [(? bytevector? bv) (bytevector-length bv)]
    [(? list? sub) (fold (λ (sub prev)
			   (+ prev (%data-size sub)))
			 0 sub)]))

(define (%parse-scn-body data-bv items)
  (let loop ([items items]
	     [symbols '()]
	     [relocations '()])
    (match items
      [() (list symbols relocations)]
      [((? list? sub-items) . rest)
       (match-let ([(sub-symbols sub-relocations)
		    (%parse-scn-body data-bv sub-items)])
	 (loop rest
	       (append-reverse sub-symbols symbols)
	       (append-reverse sub-relocations relocations)))]
      [((? number? value) . rest)
       (put-u8 data-bv value)
       (loop rest
	     symbols
	     relocations)]
      [((? bytevector? bv) . rest)
       (put-bytevector data-bv bv)
       (loop rest
	     symbols
	     relocations)]
      [((? elf-symbol? sym) . rest)
       (loop rest
	     (cons (set-field sym [elf-symbol-offset] (ftell data-bv))
		   symbols)
	     relocations)]
      [((? elf-reloc? reloc) . rest)
       (loop rest
	     symbols
	     (cons (set-field reloc [elf-reloc-offset] (ftell data-bv))
		   relocations))])))

(define (%make-scn make body)
  (let* ([data-bv (open-output-bytevector)]
	 [syms+relocs (%parse-scn-body data-bv body)])
    (make (first syms+relocs) (second syms+relocs) (get-output-bytevector data-bv))))


(define (.head.text . body)
  (%make-scn $.head.text body))

(define (.text . body)
  (%make-scn $.text body))

(define (.data . body)
  (%make-scn $.data body))

(define (.rodata . body)
  (%make-scn $.rodata body))

(define (.bss . body)
  (%make-scn $.bss body))


(define-syntax-rule (proc name body ...)
  (let* ([proc-name (symbol->string 'name)]
	 [assy-body (assemble proc-name `(body ...))])
    (list (make-elf-symbol proc-name
			   -1
			   STB_GLOBAL
			   STT_FUNC
			   STV_DEFAULT
			   (%data-size assy-body))
	  assy-body)))


(define-syntax define-data-syntax
  (syntax-rules ::: ()
    [(_ data-kind size)
     (define-syntax data-kind
       (syntax-rules ()
	 [(_ name body ...)
	  (let* ([data-name (symbol->string 'name)]
		 [data-body (data-table size `(body ...))])
	    (list (make-elf-symbol
		   data-name
		   -1
		   STB_GLOBAL
		   STT_OBJECT
		   STV_DEFAULT
		   (%data-size data-body))
		  data-body))]))]))

(define-data-syntax .byte 1)
(define-data-syntax .word 2)
(define-data-syntax .fword 3)
(define-data-syntax .dword 4)


(define-syntax-rule (.zero name size)
  (let ([data-name (symbol->string 'name)])
    (list (make-elf-symbol data-name
			   -1
			   STB_GLOBAL
			   STT_OBJECT
			   STV_DEFAULT
			   size)
	  (bytevector->u8-list (make-bytevector size)))))


(define (random-label)
  (string->symbol
   (format #f
	   "anon-label-~a"
	   (random #e1e16))))

(define (label-decl label)
  (symbol->keyword label))


(define (proc-prologue locals)
  `(phd					; Push previous DP
    .a-bits 16 .xy-bits 16
    tsc
    ;; If there are any locals, make room for them
    ,(if (> locals 0)
	 `(sec
	   sbc ,locals
	   tcs)				; SP -= locals
	 '())
    inc (a-reg)
    tcd))				; DP = SP + 1

(define* (proc-epilogue locals #:key a x y carry?)
  ;; If there are any locals, get rid of them
  `(,(if (> locals 0)
	 `(tsc
	   clc
	   adc ,locals
	   tcs)				; SP += locals
	 '())
    ;; Fill in wanted out registers
    ,(if carry?
	 (let ([lbl (random-label)])
	   `(clc
	     lda ,carry?
	     beq ,lbl
	     sec
	     ,(label-decl lbl)))
	 '())
    ,(if a `(lda ,a) '())
    ,(if x `(ldx ,x) '())
    ,(if y `(ldy ,y) '())
    pld					; Pop previous DP
    rts))


;; TODO: What about other addressing modes, like indirect, x indexed, etc?

(define (local n)
  `(dp ,n))

(define (param locals n)
  ;; n bytes into params, skip locals, skip saved DP, skip return address
  `(dp ,(+ n locals 2 2)))

(define (y-ind-param locals n)
  ;; n bytes into params, skip locals, skip saved DP, skip return address
  `(y-ind-dp ,(+ n locals 2 2)))

(define (y-ind-far-param locals n)
  ;; n bytes into params, skip locals, skip saved DP, skip return address
  `(y-ind-far-dp ,(+ n locals 2 2)))
