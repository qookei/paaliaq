(define-module (paaliaq toolchain linker relocations)
  #:use-module (paaliaq toolchain elf util)
  #:use-module (paaliaq toolchain elf defines)
  #:use-module (paaliaq toolchain elf format)

  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9 gnu)
  #:use-module (srfi srfi-26)

  #:use-module (ice-9 format)
  #:use-module (ice-9 match)

  #:use-module (rnrs bytevectors)

  #:export (apply-relocations))


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

(define (%query-symbol-or-die symbol-table symbol-name)
  (or (hash-ref symbol-table symbol-name)
      (error
       (format #f "Reference to undefined symbol ~a" symbol-name))))

(define (apply-relocation scn base symbol-table reloc)
  (let* ([type (elf-reloc-type reloc)]
	 [len (%reloc-size (elf-reloc-type reloc))]

	 [symbol-name (elf-reloc-symbol-name reloc)]

	 [target (+ (%query-symbol-or-die symbol-table symbol-name)
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
	    (error
	     (format #f "Branch target too far ~a ~x ~x ~a"
		     symbol-name source target offset))))]
     [(or (eq? type R_W65C816_ABS16)
	  (eq? type R_W65C816_ABS24))
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


(define (apply-relocations scn base symbol-table)
  (for-each
   (λ (reloc)
     (apply-relocation scn base symbol-table reloc))
   (elf-scn-relocs scn))
  (set-fields scn
	      [(elf-scn-addr) base]
	      [(elf-scn-relocs) '()]
	      [(elf-scn-syms) (offset-symbols base (elf-scn-syms scn))]))
