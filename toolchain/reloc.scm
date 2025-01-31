(use-modules (paaliaq toolchain elf read))
(use-modules (paaliaq toolchain elf emit))
(use-modules (paaliaq toolchain elf format))
(use-modules (paaliaq toolchain elf defines))
(use-modules (ice-9 pretty-print))
(use-modules (ice-9 match))
(use-modules (ice-9 format))
(use-modules (srfi srfi-9 gnu))
(use-modules (rnrs bytevectors))

(define (branch-target-fits? offset len)
  (match len
    [1 (and (>= offset -128) (< offset 128))]
    [2 (and (>= offset -32768) (< offset 32768))]
    [_ (error "Illegal branch target width:" len)]))

(define (%reloc-size type)
  (cond
   [(eq? type R_W65C816_ABS24) 3]
   [(eq? type R_W65C816_ABS16) 2]
   [(eq? type R_W65C816_BANK) 1]
   [(eq? type R_W65C816_REL8) 1]
   [(eq? type R_W65C816_REL16) 2]
   [else #f]))

(define (%relocate-symbols base syms)
  (map (λ (sym)
	 (set-field sym
		    (elf-symbol-offset)
		    (+ base (elf-symbol-offset sym))))
       syms))

(define (relocate scn base symbol-table)
  (for-each
   (λ (reloc)
     (let* ([type (elf-reloc-type reloc)]
	    [symbol-name (elf-reloc-symbol-name reloc)]
	    [len (%reloc-size (elf-reloc-type reloc))]
	    [target (+ (assoc-ref symbol-table symbol-name)
		       (elf-reloc-addend reloc))]
	    [target-bank (logand #xFF (ash target -16))]
	    [source (+ base (elf-reloc-offset reloc))]
	    [source-bank (logand #xFF (ash source -16))])
       (cond
	[(or (eq? type R_W65C816_REL8)
	     (eq? type R_W65C816_REL16))
	  (let ([offset (- target (+ source len))])
	    (if (branch-target-fits? offset len)
		(bytevector-sint-set! (elf-scn-data scn)
				      (elf-reloc-offset reloc)
				      offset 'little len)
		(error "Branch target too far ~a ~x ~x ~a"
		       symbol-name source target offset)))]
	[(or (eq? type R_W65C816_ABS16)
	     (eq? type R_W65C816_ABS24))
	 ;; TODO: Add a separate relocation type for jumps. This is
	 ;; needed both for far call veneers, and because these
	 ;; conditions can hold in valid cases, e.g. if it's a data
	 ;; access and DBR=target-bank.
	 (if (and (eq? type R_W65C816_ABS16)
		  (not (eq? source-bank target-bank)))
	     (format #t "warning: ABS16 relocation truncated to fit: source ~,02X != target ~,02X (symbol ~a)~%"
		     source-bank target-bank symbol-name))
	 (bytevector-uint-set! (elf-scn-data scn)
			       (elf-reloc-offset reloc)
			       (logand target (if (eq? len 2)
						  #xFFFF
						  #xFFFFFF))
			       'little len)]
	[(eq? type R_W65C816_BANK)
	 (bytevector-u8-set! (elf-scn-data scn)
			     (elf-reloc-offset reloc)
			     target-bank)]
	[else (error "bailing out, unknown reloc" reloc)])))
   (elf-scn-relocs scn))
  (set-fields scn
	      [(elf-scn-addr) base]
	      [(elf-scn-relocs) '()]
	      [(elf-scn-syms) (%relocate-symbols base (elf-scn-syms scn))]))

(define (make-symbol-table scn base)
  (map (λ (sym)
	 (cons (elf-symbol-name sym)
	       (+ base (elf-symbol-offset sym))))
       (elf-scn-syms scn)))

(define (do-file base in-name out-name)
  (let* ([in-elf (call-with-input-file in-name read-elf-object #:binary #t)]
	 [symbol-table (make-symbol-table (car in-elf) base)]
	 [out-elf (relocate (car in-elf) base symbol-table)])
    (if (> (length in-elf) 1)
	(error "TODO: support more than one section"))
    (pretty-print symbol-table)
    (pretty-print out-elf)
    (pretty-print (bytevector-u8-ref (elf-scn-data out-elf) 68))
    (call-with-output-file out-name
      (λ (port)
	(emit-elf-object port
			 (list out-elf)
			 #:type ET_EXEC
			 #:entry (assoc-ref symbol-table "_start")))
      #:binary #t)))

(do-file (string->number (cadr (command-line)))
	 (caddr (command-line))
	 (cadddr (command-line)))
