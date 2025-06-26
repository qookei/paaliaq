(define-module (paaliaq toolchain linker input)
  #:use-module (paaliaq toolchain elf read)
  #:use-module (paaliaq toolchain elf defines)
  #:use-module (paaliaq toolchain elf format)

  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9 gnu)
  #:use-module (srfi srfi-26)

  #:use-module (ice-9 match)
  #:use-module (ice-9 format)

  #:use-module (rnrs bytevectors)
  #:use-module ((scheme base) #:select (bytevector-append))

  #:export (process-inputs-into-sections))


(define (read-input-file name)
  (cons name
	(call-with-input-file
	    name
	  read-elf-object
	  #:binary #t)))

(define (collect-input-files names)
  (map read-input-file names))

;; -----------------------------------------------------------------------------

;; TODO(qookie): Ideally this would support more complex patterns.
(define (section-name-matches? scn-name pattern)
  (if (string=? (string-take-right pattern 1) "*")
      (string-prefix? (string-drop-right pattern 1) scn-name)
      (string=? scn-name pattern)))

(define (find-sections-by-pattern input-files pattern)
  (stable-sort
   (append-map
    (λ (input-file)
      (filter-map
       (λ (scn)
	 (and (section-name-matches? (elf-scn-name scn) pattern)
	      (cons (car input-file) scn)))
       ;; CAR is the file name
       ;; CDR is the list of sections in the file
       (cdr input-file)))
    input-files)
   (λ (l r)
     (> (elf-scn-addralign (cdr l))
	(elf-scn-addralign (cdr r))))))

(define (%make-align-scn align)
  (cons "<linker script>"
	(make-elf-scn SHT_NOBITS
		      "<artificial-align>"
		      0 0
		      #vu8()
		      '()
		      '()
		      0 0
		      align
		      0)))

(define (%make-symbol-scn name)
  (cons "<linker script>"
	(make-elf-scn SHT_NOBITS
		      "<artificial-symbol>"
		      0 0
		      #vu8()
		      (list
		       (make-elf-symbol name
					0
					STB_GLOBAL STT_OBJECT
					STV_DEFAULT 0))
		      '()
		      0 0
		      1
		      0)))

(define (process-section-rule rule input-files)
  (match rule
    [('align align) (list (%make-align-scn align))]
    [('symbol name) (list (%make-symbol-scn name))]
    [('section pattern)
     (find-sections-by-pattern input-files pattern)]))

(define (process-section-rules rules input-files)
  (append-map
   (cut process-section-rule <> input-files)
   rules))

(define (process-sections-rules rules input-files)
  (map
   (λ (scn-rules)
     (cons (car scn-rules)
	   (process-section-rules (cdr scn-rules) input-files)))
   rules))

;; -----------------------------------------------------------------------------

(define (%compute-symbol-origins ht in-section)
  (for-each
   (λ (sym)
     (let* ([name (elf-symbol-name sym)]
	    [existing (hash-ref ht name)])
       (if existing
	   (error
	    (format #f "Duplicate symbol `~a', first defined in `~a', then redefined in `~a'"
		    name existing (car in-section))))
       (hash-set! ht name (car in-section))))
   (elf-scn-syms (cdr in-section))))

(define (compute-symbol-origins output-groupings)
  (let ([ht (make-hash-table)])
    (for-each
     (λ (input-sections)
       (for-each
	(cut %compute-symbol-origins ht <>)
	(cdr input-sections)))
     output-groupings)
    ht))

;; -----------------------------------------------------------------------------

(define (%offset-relocs offset relocs)
  (map
   (λ (reloc)
     (set-field reloc
		(elf-reloc-offset)
		(+ (elf-reloc-offset reloc) offset)))
   relocs))

(define (%offset-symbols offset symbols)
  (map
   (λ (sym)
     (set-field sym
		(elf-symbol-offset)
		(+ (elf-symbol-offset sym) offset)))
   symbols))

(define (%build-output-section  out-name . in-sections)
  (let next ([input-scns in-sections]
	     [flags 0]
	     [has-bits #f]
	     [max-align 1]
	     [data #vu8()]
	     [relocs '()]
	     [symbols '()])
    (if (null? input-scns)
	(make-elf-scn (if has-bits SHT_PROGBITS SHT_NOBITS)
		      out-name
		      flags 0
		      data
		      symbols
		      relocs
		      0 0
		      max-align
		      0)
	(let* ([scn (cdar input-scns)]
	       [rest (cdr input-scns)]
	       [offset (bytevector-length data)]
	       [misalign (logand offset (1- (elf-scn-addralign scn)))]
	       [padding-needed (if (> misalign 0)
				   (- (elf-scn-addralign scn) misalign)
				   0)]
	       [padding-bytes (make-bytevector padding-needed 0)]
	       [new-data (bytevector-append data padding-bytes (elf-scn-data scn))])
	  (next rest
		(logior flags (elf-scn-flags scn))
		(or has-bits (equal? (elf-scn-type scn) SHT_PROGBITS))
		(max max-align (elf-scn-addralign scn))
		new-data
		(append relocs (%offset-relocs offset (elf-scn-relocs scn)))
		(append symbols (%offset-symbols offset (elf-scn-syms scn))))))))

(define (build-output-sections output-groupings)
  (map (λ (x) (apply %build-output-section x)) output-groupings))

;; -----------------------------------------------------------------------------

(define (process-inputs-into-sections input-file-names rules)
  (let* ([input-files (collect-input-files input-file-names)]
	 [output-groupings (process-sections-rules rules input-files)])
    (cons (compute-symbol-origins output-groupings)
	  (build-output-sections output-groupings))))
