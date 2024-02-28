(define-module (paaliaq toolchain elf sections)
  #:use-module (paaliaq toolchain elf defines)
  #:use-module (paaliaq toolchain elf format)
  ;; Only select {open,get}-output-bytevector to avoid warnings
  ;; about (scheme base) redeclaring core procedures
  #:use-module ((scheme base) #:select (open-output-bytevector
					get-output-bytevector))
  #:use-module (ice-9 binary-ports)
  #:use-module (rnrs bytevectors)
  #:export ($.null
	    $.strtab
	    $.symtab
	    $.rela
	    $.text
	    $.rodata
	    $.data
	    $.bss))


(define ($.null)
  (make-elf-scn SHT_NULL
		""
		0
		#vu8() '() '()
		SHN_UNDEF SHN_UNDEF
		0 0))


(define ($.strtab name strtab-bv)
  (make-elf-scn SHT_STRTAB
		name
		0
		strtab-bv '() '()
		SHN_UNDEF SHN_UNDEF
		1 0))


(define ($.symtab symtab-bv strtab-idx)
  (make-elf-scn SHT_SYMTAB
		".symtab"
		0
		symtab-bv '() '()
		strtab-idx 1 ;; TODO: index of last STB_LOCAL symbol + 1
		4 +sizeof-sym+))


(define (%generate-rela-data symtab-hash relocs)
  (let ([rela-port (open-output-bytevector)])
    (for-each
     (λ (rel)
       (let ([rela-bv (make-bytevector +sizeof-rela+)])
	 (set! (r_offset rela-bv) (elf-reloc-offset rel))
	 (set! (r_info rela-bv)
	       (ELF32_R_INFO (hash-ref symtab-hash (elf-reloc-symbol-name rel))
			     (elf-reloc-type rel)))
	 (set! (r_addend rela-bv) (elf-reloc-addend rel))
	 (put-bytevector rela-port rela-bv)))
     relocs)
    (get-output-bytevector rela-port)))

(define ($.rela tgt-name tgt-idx symtab-idx symtab-hash relocs)
  (make-elf-scn SHT_RELA
		(string-append ".rela" tgt-name)
		(+ SHF_INFO_LINK)
		(%generate-rela-data symtab-hash relocs) '() '()
		symtab-idx tgt-idx
		4 +sizeof-rela+))


(define ($.text syms relocs data)
  (make-elf-scn SHT_PROGBITS
		".text"
		(+ SHF_ALLOC SHF_EXECINSTR)
		data syms relocs
		SHN_UNDEF SHN_UNDEF
		1 0))


(define ($.rodata syms relocs data)
  (make-elf-scn SHT_PROGBITS
		".rodata"
		(+ SHF_ALLOC)
		data syms relocs
		SHN_UNDEF SHN_UNDEF
		1 0))


(define ($.data syms relocs data)
  (make-elf-scn SHT_PROGBITS
		".data"
		(+ SHF_ALLOC SHF_WRITE)
		data syms relocs
		SHN_UNDEF SHN_UNDEF
		1 0))


(define ($.bss syms size)
  (make-elf-scn SHT_NOBITS
		".bss"
		(+ SHF_ALLOC SHF_WRITE)
		(make-bytevector size) syms '()
		SHN_UNDEF SHN_UNDEF
		1 0))
