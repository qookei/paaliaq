(define-module (paaliaq toolchain elf read)
  #:use-module (paaliaq toolchain elf sections)
  #:use-module (paaliaq toolchain elf defines)
  #:use-module (paaliaq toolchain elf format)
  ;; Only select {open,get}-output-bytevector to avoid warnings
  ;; about (scheme base) redeclaring core procedures
  #:use-module ((scheme base) #:select (open-output-bytevector
					get-output-bytevector))
  #:use-module (rnrs bytevectors)
  #:use-module (rnrs bytevectors gnu)
  #:use-module (ice-9 binary-ports)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9 gnu)
  #:use-module (srfi srfi-26)

  #:export (read-elf-object))

(define (%read-bytes-at at num port)
  (seek port at SEEK_SET)
  (get-bytevector-n port num))

(define (%read-string-table port shoff shndx string)
  (let ([shdr-bv (%read-bytes-at (+ shoff (* shndx +sizeof-shdr+)) +sizeof-shdr+ port)])
    (seek port (+ (sh_offset shdr-bv) string) SEEK_SET)
    (let loop ([bytes '()])
      (if (= (lookahead-u8 port) 0)
	  ;; Assume that the string tables don't contain UTF-8 :^)
	  (list->string (map integer->char bytes))
	  (loop (append bytes (list (get-u8 port))))))))

(define (%read-ehdr port)
  (let ([ehdr-bv (%read-bytes-at 0 +sizeof-ehdr+ port)])
    (if (not (= (ei_mag ehdr-bv) EI_MAG))
	(error "ELF file has invalid magic"))
    (if (not (= (ei_class ehdr-bv) ELFCLASS32))
	(error "ELF file has invalid class"))
    (if (not (= (ei_data ehdr-bv) ELFDATA2LSB))
	(error "ELF file has invalid data format"))
    (if (not (= (ei_version ehdr-bv) EV_CURRENT))
	(error "ELF file has invalid version (e_ident)"))
    (if (not (= (e_type ehdr-bv) ET_REL))
	(error "ELF file has not a relocatable file"))
    (if (not (= (e_machine ehdr-bv) EM_65816))
	(error "ELF file has invalid machine"))
    (if (not (= (e_version ehdr-bv) EV_CURRENT))
	(error "ELF file has invalid version (e_version)"))
    (if (= (e_shoff ehdr-bv) 0)
	(error "ELF file has no sections (e_shoff)"))
    (if (not (= (e_ehsize ehdr-bv) +sizeof-ehdr+))
	(error "ELF file has invalid Ehdr size"))
    (if (not (= (e_shentsize ehdr-bv) +sizeof-shdr+))
	(error "ELF file has invalid Shdr size"))
    (if (= (e_shnum ehdr-bv) 0)
	(error "ELF file has no sections (e_shnum)"))
    (if (= (e_shstrndx ehdr-bv) 0)
	(error "ELF file has no section names"))
    (if (>= (e_shstrndx ehdr-bv) (e_shnum ehdr-bv))
	(error "ELF file section string table index is invalid"))

    (list (e_shoff ehdr-bv)
	  (e_shnum ehdr-bv)
	  (e_shstrndx ehdr-bv))))

(define (%read-section port shoff shstrndx shndx)
  (let ([shdr-bv (%read-bytes-at (+ shoff (* shndx +sizeof-shdr+)) +sizeof-shdr+ port)])
    (cons shndx
	  (make-elf-scn
	   (sh_type shdr-bv)
	   (%read-string-table port shoff shstrndx (sh_name shdr-bv))
	   (sh_flags shdr-bv)
	   (if (= (sh_type shdr-bv) SHT_NOBITS)
	       (make-bytevector (sh_size shdr-bv))
	       (%read-bytes-at (sh_offset shdr-bv) (sh_size shdr-bv) port))
	   'TBD 'TBD
	   (sh_link shdr-bv)
	   (sh_info shdr-bv)
	   (sh_addralign shdr-bv)
	   (sh_entsize shdr-bv)))))

(define (%parse-symtab port shoff symtab-scn)
  (let ([syms-hash (make-hash-table)]
	[scn-sym-hash (make-hash-table)])
    (for-each
     (λ (idx)
       (let* ([sym-bv (bytevector-slice (elf-scn-data symtab-scn) (* idx +sizeof-sym+) +sizeof-sym+)]
	      [tgt-scn (st_shndx sym-bv)])
	 (hash-set!
	  scn-sym-hash tgt-scn
	  (cons idx (hash-ref scn-sym-hash tgt-scn '())))
	 (hash-set!
	  syms-hash idx
	  (make-elf-symbol
	   (%read-string-table port shoff (elf-scn-link symtab-scn) (st_name sym-bv))
	   (st_value sym-bv)
	   (ELF32_ST_BIND (st_info sym-bv))
	   (ELF32_ST_TYPE (st_info sym-bv))
	   (ELF32_ST_VISIBILITY (st_other sym-bv))
	   (st_size sym-bv)))))
     (iota (/ (bytevector-length (elf-scn-data symtab-scn))
	      (elf-scn-entsize symtab-scn))))
    (list syms-hash scn-sym-hash)))

(define (%parse-rela syms-hash rela-scn)
  (map
   (λ (idx)
     (let ([rela-bv (bytevector-slice (elf-scn-data rela-scn) (* idx +sizeof-rela+) +sizeof-rela+)])
       (make-elf-reloc
	(r_offset rela-bv)
	(ELF32_R_TYPE (r_info rela-bv))
	(elf-symbol-name (hash-ref syms-hash (ELF32_R_SYM (r_info rela-bv))))
	(r_addend rela-bv))))
   (iota (/ (bytevector-length (elf-scn-data rela-scn))
	    (elf-scn-entsize rela-scn)))))

(define (%find-scn-by-name scns-alist name)
  (find (λ (scn-acons)
	  (string=? (elf-scn-name (cdr scn-acons)) name))
	scns-alist))

(define (%process-rela-scns scns-alist syms-hash)
  (filter
   identity
   (map (λ (scn-acons)
	  (if (eq? (elf-scn-type (cdr scn-acons)) SHT_RELA)
	      (cons (elf-scn-info (cdr scn-acons))
		    (%parse-rela syms-hash (cdr scn-acons)))
	      #f))
	scns-alist)))

(define (%read-all-sections port shoff shnum shstrndx)
  (map
   (cut %read-section port shoff shstrndx <>)
   (iota shnum)))

(define (%interesting-scn? scn)
  ;; Don't really care about anything else
  (or (eq? (elf-scn-type scn) SHT_PROGBITS)
      (eq? (elf-scn-type scn) SHT_NOBITS)))

(define (read-elf-object port)
  (match-let* ([(shoff shnum shstrndx) (%read-ehdr port)]
	       [scns-alist (%read-all-sections port shoff shnum shstrndx)]
	       [strtab-acons (%find-scn-by-name scns-alist ".symtab")]
	       [(syms-hash scn-sym-hash) (%parse-symtab port shoff (cdr strtab-acons))]
	       [rela-alist (%process-rela-scns scns-alist syms-hash)])
    (filter
     %interesting-scn?
     (map
      (λ (scn-acons)
	(set-fields
	 (cdr scn-acons)
	 [(elf-scn-syms)
	  (map (cut hash-ref syms-hash <>)
	       (hash-ref scn-sym-hash (car scn-acons) '()))]
	 [(elf-scn-relocs)
	  (match (assoc (car scn-acons) rela-alist)
	    [(_ . v) v]
	    [#f '()])]))
      scns-alist))))
