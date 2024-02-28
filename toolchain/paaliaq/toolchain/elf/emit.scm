(define-module (paaliaq toolchain elf emit)
  #:use-module (paaliaq toolchain elf sections)
  #:use-module (paaliaq toolchain elf defines)
  #:use-module (paaliaq toolchain elf format)
  ;; Only select {open,get}-output-bytevector to avoid warnings
  ;; about (scheme base) redeclaring core procedures
  #:use-module ((scheme base) #:select (open-output-bytevector
					get-output-bytevector))
  #:use-module (rnrs bytevectors)
  #:use-module (ice-9 binary-ports)
  #:use-module (ice-9 textual-ports)

  #:export (emit-elf-object))


(define (%intern-string htab bv-port str)
  (let ([maybe-idx (hash-ref htab str)]
	[new-idx (ftell bv-port)])
    (if maybe-idx
	maybe-idx
	(begin
	  (hash-set! htab str new-idx)
	  (put-string bv-port str)
	  (put-u8 bv-port 0)
	  new-idx))))

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


(define (%emit-sym port sym scn-idx intern-strtab! symtab-hash)
  (let ([sym-bv (make-bytevector +sizeof-sym+)])
    (set! (st_name sym-bv) (intern-strtab! (elf-symbol-name sym)))
    (set! (st_value sym-bv) (elf-symbol-offset sym))
    (set! (st_size sym-bv) (elf-symbol-size sym))
    (set! (st_info sym-bv) (ELF32_ST_INFO (elf-symbol-binding sym)
					  (elf-symbol-type sym)))
    (set! (st_other sym-bv) (elf-symbol-visibility sym))
    (set! (st_shndx sym-bv) scn-idx)
    (hash-set! symtab-hash (elf-symbol-name sym) (/ (ftell port) +sizeof-sym+))
    (put-bytevector port sym-bv)))

(define (emit-elf-object port sections)
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
    (%emit-section ($.null) intern-shstrtab shdr-port data-port)

    ;; Emit an empty symbol at index 0
    (%emit-sym symtab-port
	       (make-elf-symbol "" 0 0 0 0 0)
	       SHN_UNDEF intern-strtab symtab-hash)

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
					  STV_DEFAULT
					  0)
			 SHN_UNDEF intern-strtab symtab-hash)))
	(cdr info)))
     rela-scns)

    ;; Emit .strtab and all the sections that link to it
    (let* ([strtab-idx (emit-scn ($.strtab ".strtab"
					   (get-output-bytevector strtab-port)))]
	   ;; We need the index of the symbol table for the link in .rela
	   [symtab-idx (emit-scn ($.symtab (get-output-bytevector symtab-port)
					   strtab-idx))])
      ;; Emit all the .rela sections
      (hash-for-each
       (λ (scn-name info)
	 (emit-scn ($.rela scn-name
			   (car info)
			   symtab-idx
			   symtab-hash
			   (cdr info))))
       rela-scns))


    ;; Finally, emit .shstrtab itself
    ;; Intern the string so that we don't modify the string table anymore
    (intern-shstrtab ".shstrtab")
    (let ([shstrtab-idx (emit-scn ($.strtab ".shstrtab"
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
