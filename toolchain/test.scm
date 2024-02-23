(use-modules (srfi srfi-9))
(use-modules (ice-9 match))
(use-modules (ice-9 binary-ports))
(use-modules (ice-9 textual-ports))
(use-modules (scheme base))
(use-modules (ice-9 pretty-print))

(use-modules (elf))

(define-record-type <elf-symbol>
  (make-elf-symbol name offset binding type visibility)
  elf-symbol?
  (name elf-symbol-name)
  (offset elf-symbol-offset)
  (binding elf-symbol-binding)
  (type elf-symbol-type)
  (visibility elf-symbol-visibility))

(define (elf-symbol-here name binding type visibility)
  (make-elf-symbol name -1 binding type visibility))

(define (%offset-elf-symbol sym offset)
  (make-elf-symbol (elf-symbol-name sym)
		   offset
		   (elf-symbol-binding sym)
		   (elf-symbol-type sym)
		   (elf-symbol-visibility sym)))

(define-record-type <elf-reloc>
  (make-elf-reloc offset type symbol-name addend)
  elf-reloc?

  (offset elf-reloc-offset)
  (type elf-reloc-type)
  (symbol-name elf-reloc-symbol-name)
  (addend elf-reloc-addend))

(define (elf-reloc-here type symbol-name addend)
  (make-elf-reloc -1 type symbol-name addend))

(define (%offset-elf-reloc reloc offset)
  (make-elf-reloc offset
		  (elf-reloc-type reloc)
		  (elf-reloc-symbol-name reloc)
		  (elf-reloc-addend reloc)))

(define (%process-section-body items)
  (let ([data-bv (open-output-bytevector)])
    (let loop ([items items]
	       [symbols '()]
	       [relocations '()])
      (match items
	[() (list symbols relocations (get-output-bytevector data-bv))]
	[((? bytevector? bv) . rest)
	 (put-bytevector data-bv bv)
	 (loop rest
	       symbols
	       relocations)]
	[((? elf-symbol? sym) . rest)
	 (loop rest
	       (cons (%offset-elf-symbol sym (ftell data-bv))
		     symbols)
	       relocations)]
	[((? elf-reloc? reloc) . rest)
	 (loop rest
	       symbols
	       (cons (%offset-elf-reloc reloc (ftell data-bv))
		     relocations))]))))

(define (%intern-string htab bv-port str)
  (match (hash-ref htab str)
    [#f (let ([idx (ftell bv-port)])
	  (hash-set! htab str idx)
	  (put-string bv-port str)
	  (put-u8 bv-port 0)
	  idx)]
    [idx idx]))

(define-record-type <elf-scn>
  (make-elf-scn type name flags data syms relocs link info addralign entsize)
  elf-scn?

  (type elf-scn-type)
  (name elf-scn-name)
  (flags elf-scn-flags)
  (data elf-scn-data)
  (syms elf-scn-syms)
  (relocs elf-scn-relocs)
  (link elf-scn-link)
  (info elf-scn-info)
  (addralign elf-scn-addralign)
  (entsize elf-scn-entsize))

(define (%.text syms relocs data)
  (make-elf-scn SHT_PROGBITS
		".text"
		(+ SHF_ALLOC SHF_EXECINSTR)
		data syms relocs
		SHN_UNDEF SHN_UNDEF
		1 0))

(define (.text . body)
  (apply %.text (%process-section-body body)))

(define (%emit-section scn intern-shstrtab! shdr-port data-port)
  (let ([scn-bv (make-bytevector +sizeof-shdr+)]
	[scn-idx (/ (ftell shdr-port) +sizeof-shdr+)])
    (set! (sh_type scn-bv) (elf-scn-type scn))
    (set! (sh_name scn-bv) (intern-shstrtab! (elf-scn-name scn)))
    (set! (sh_flags scn-bv) (elf-scn-flags scn))

    (set! (sh_addr scn-bv) 0)
    (set! (sh_offset scn-bv) (+ +sizeof-ehdr+ (ftell data-port))) ;; TODO
    (set! (sh_size scn-bv) (bytevector-length (elf-scn-data scn)))

    ;; SHT_NOBITS don't have their data actually written out
    (if (not (= (elf-scn-type scn)
		SHT_NOBITS))
	(put-bytevector data-port (elf-scn-data scn)))

    (set! (sh_link scn-bv) (elf-scn-link scn))
    (set! (sh_info scn-bv) (elf-scn-info scn))
    (set! (sh_addralign scn-bv) (elf-scn-addralign scn))
    (set! (sh_entsize scn-bv) (elf-scn-entsize scn))

    (put-bytevector shdr-port scn-bv)
    scn-idx))

(define (%emit-ehdr port shoff shnum shstrndx)
  (let ([ehdr-bv (make-bytevector +sizeof-ehdr+)])
    (set! (ei_mag ehdr-bv) EI_MAG)
    (set! (ei_class ehdr-bv) ELFCLASS32)
    (set! (ei_data ehdr-bv) ELFDATA2LSB)
    (set! (ei_version ehdr-bv) EV_CURRENT)
    (set! (ei_osabi ehdr-bv) ELFOSABI_SYSV) ;; ??

    (set! (e_type ehdr-bv) ET_REL)
    (set! (e_machine ehdr-bv) EM_65816)
    (set! (e_version ehdr-bv) EV_CURRENT)

    (set! (e_shoff ehdr-bv) shoff)
    (set! (e_shnum ehdr-bv) shnum)
    (set! (e_shstrndx ehdr-bv) shstrndx)

    (set! (e_ehsize ehdr-bv) +sizeof-ehdr+)
    (set! (e_shentsize ehdr-bv) +sizeof-shdr+)
    (set! (e_phentsize ehdr-bv) +sizeof-phdr+)

    (put-bytevector port ehdr-bv)))

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

(define (%.rela tgt-name tgt-idx symtab-idx symtab-hash relocs)
  (make-elf-scn SHT_RELA
		(string-append ".rela" tgt-name)
		(+ SHF_INFO_LINK)
		(%generate-rela-data symtab-hash relocs) '() '()
		symtab-idx tgt-idx
		4 +sizeof-rela+))

(define (%.strtab name strtab-bv)
  (make-elf-scn SHT_STRTAB
		name
		0
		strtab-bv '() '()
		SHN_UNDEF SHN_UNDEF
		1 0))

(define (%.symtab symtab-bv strtab-idx)
  (make-elf-scn SHT_SYMTAB
		".symtab"
		0
		symtab-bv '() '()
		strtab-idx SHN_UNDEF
		4 +sizeof-sym+))

(define (%.null)
  (make-elf-scn SHT_NULL
		""
		0
		#vu8() '() '()
		SHN_UNDEF SHN_UNDEF
		0 0))



(define (%emit-sym port sym scn-idx intern-strtab! symtab-hash)
  (let ([sym-bv (make-bytevector +sizeof-sym+)])
    (set! (st_name sym-bv) (intern-strtab! (elf-symbol-name sym)))
    (set! (st_value sym-bv) (elf-symbol-offset sym))
    (set! (st_size sym-bv) 0) ;; ??
    (set! (st_info sym-bv) (ELF32_ST_INFO (elf-symbol-binding sym)
					  (elf-symbol-type sym)))
    (set! (st_other sym-bv) (elf-symbol-visibility sym))
    (set! (st_shndx sym-bv) scn-idx)
    (hash-set! symtab-hash (elf-symbol-name sym) (/ (ftell port) +sizeof-sym+))
    (put-bytevector port sym-bv)))

(define (%emit-elf port sections)
  (letrec ([data-port (open-output-bytevector)]
	   [shdr-port (open-output-bytevector)]
	   ;; .shstrtab string interning
	   [shstrtab-port (open-output-bytevector)]
	   [shstrtab-hash (make-hash-table)]
	   [intern-shstrtab
	    (λ (name)
	      (%intern-string shstrtab-hash shstrtab-port name))]
	   ;; .strtab string interning
	   [strtab-port (open-output-bytevector)]
	   [strtab-hash (make-hash-table)]
	   [intern-strtab
	    (λ (name)
	      (%intern-string strtab-hash strtab-port name))]
	   ;; .symtab & .rela
	   [symtab-port (open-output-bytevector)]
	   [symtab-hash (make-hash-table)]
	   [rela-scns (make-hash-table)]
	   ;; Helpers
	   [emit-scn
	    (λ (scn)
	      (%emit-section scn intern-shstrtab shdr-port data-port))])

    ;; Add the empty strings at the start of the string tables
    (intern-shstrtab "")
    (intern-strtab "")

    ;; Emit the null section at index 0
    (%emit-section (%.null) intern-shstrtab shdr-port data-port)

    ;; Emit all the user-provided sections
    (for-each
     (λ (scn)
       (let ([scn-idx (emit-scn scn)])
	 ;; Eagerly emit symbols to the symbol table, as we only need
	 ;; the index of this section.
	 (for-each
	  (λ (sym)
	    (%emit-sym symtab-port sym scn-idx intern-strtab symtab-hash))
	  (elf-scn-syms scn))

	 ;; Lazily emit relocations. Defer generating .rela sections
	 ;; to later, so we know all the indices to link to.
	 (hash-set! rela-scns (elf-scn-name scn) (cons scn-idx
						       (elf-scn-relocs scn)))))
     sections)

    ;; Check all relocations and insert UNDEF symbols into the symbol table
    ;; if necessary.
    (hash-for-each
     (λ (scn-name info)
       (for-each
	(λ (rel)
	  (if (not (hash-ref symtab-hash (elf-reloc-symbol-name rel)))
	      (%emit-sym symtab-port
			 (make-elf-symbol (elf-reloc-symbol-name rel)
					  0
					  STB_GLOBAL
					  STT_NOTYPE
					  STV_DEFAULT)
			 SHN_UNDEF intern-strtab symtab-hash)))
	(cdr info)))
     rela-scns)

    ;; Emit .strtab and all the sections that link to it
    (let* ([strtab-idx (emit-scn (%.strtab ".strtab"
					   (get-output-bytevector strtab-port)))]
	   ;; We need the index of the symbol table for the link in .rela
	   [symtab-idx (emit-scn (%.symtab (get-output-bytevector symtab-port)
					   strtab-idx))])
      ;; Emit all the .rela sections
      (hash-for-each
       (λ (scn-name info)
	 (emit-scn (%.rela scn-name
			   (car info)
			   symtab-idx
			   symtab-hash
			   (cdr info))))
       rela-scns))


    ;; Finally, emit .shstrtab itself
    ;; Intern the string so that we don't modify the string table anymore
    (intern-shstrtab ".shstrtab")
    (let ([shstrtab-idx (emit-scn (%.strtab ".shstrtab"
					    (get-output-bytevector shstrtab-port)))])
      ;; Now that we've emitted all the sections, piece the file together
      ;; First the Ehdr ...
      (%emit-ehdr port
		  (+ +sizeof-ehdr+ (ftell data-port))
		  (hash-count (const #t) shstrtab-hash)
		  shstrtab-idx)
      ;; ... then the data ...
      (put-bytevector port (get-output-bytevector data-port))
      ;; ... then the section table
      (put-bytevector port (get-output-bytevector shdr-port)))))


(call-with-output-file "TEST.elf"
  (λ (port)
    (%emit-elf
     port
     (list
      (.text
       (elf-symbol-here "main" STB_GLOBAL STT_FUNC STV_DEFAULT)
       #vu8(#xc3)
       ))))
  #:binary #t)
