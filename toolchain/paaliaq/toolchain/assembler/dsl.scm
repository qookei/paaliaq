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

  #:export (.text
	    .rodata
	    .data
	    .bss

	    proc
	    .byte
	    .word
	    .fword
	    .dword
	    .zero))


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
