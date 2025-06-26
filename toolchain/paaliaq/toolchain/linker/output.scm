(define-module (paaliaq toolchain linker output)
  #:use-module (paaliaq toolchain linker relocations)
  #:use-module (paaliaq toolchain elf emit)
  #:use-module (paaliaq toolchain elf defines)
  #:use-module (paaliaq toolchain elf format)

  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9 gnu)
  #:use-module (srfi srfi-26)

  #:use-module (ice-9 format)
  #:use-module (ice-9 match)

  #:use-module (rnrs bytevectors)

  #:export (emit-output-elf))


;; TODO(qookie): This is just a bodge for now. This will need a rework
;; to support multiple segments, and to actually emit segments into
;; ELF PHDRs.

;; The general order of operations will be:
;; 1. Generate sections for stuff like the executable headers, strtab,
;; symtab, etc. in case they're supposed to be in a segment.
;; 2. Pack sections into segments and determine their final addresses.
;; 3. Lay out the final file.

;; For now though, we just pack everything into a single section,
;; relocate that, and write it out to a file (basically what the old
;; code did, except with support for multiple sections and input
;; files).


(define (add-section-to-symbol-table ht section base)
  (for-each
   (λ (symbol)
     (hash-set! ht
		(elf-symbol-name symbol)
		(+ base (elf-symbol-offset symbol))))
   (elf-scn-syms section)))


(define (emit-output-elf out-name output-sections base entry-name)
  (if (> (length output-sections) 1)
      (error "TODO: Support more than one output section"))
  (let ([symbol-table (make-hash-table)]
	[in-scn (car output-sections)])
    (add-section-to-symbol-table symbol-table in-scn base)
    (call-with-output-file out-name
      (λ (port)
	(emit-elf-object port
			 (list (apply-relocations in-scn base symbol-table))
			 #:type ET_EXEC
			 #:entry (hash-ref symbol-table entry-name)))
      #:binary #t)))
