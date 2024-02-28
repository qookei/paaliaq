(define-module (paaliaq toolchain elf defines)
  #:use-module (srfi srfi-9)
  #:export (make-elf-symbol
	    elf-symbol?
	    elf-symbol-name
	    elf-symbol-offset
	    elf-symbol-binding
	    elf-symbol-type
	    elf-symbol-visibility
	    elf-symbol-size

	    make-elf-reloc
	    elf-reloc?
	    elf-reloc-offset
	    elf-reloc-type
	    elf-reloc-symbol-name
	    elf-reloc-addend

	    make-elf-scn
	    elf-scn?
	    elf-scn-type
	    elf-scn-name
	    elf-scn-flags
	    elf-scn-data
	    elf-scn-syms
	    elf-scn-relocs
	    elf-scn-link
	    elf-scn-info
	    elf-scn-addralign
	    elf-scn-entsize))


(define-record-type <elf-symbol>
  (make-elf-symbol name offset binding type visibility size)
  elf-symbol?

  (name elf-symbol-name)
  (offset elf-symbol-offset)
  (binding elf-symbol-binding)
  (type elf-symbol-type)
  (visibility elf-symbol-visibility)
  (size elf-symbol-size))


(define-record-type <elf-reloc>
  (make-elf-reloc offset type symbol-name addend)
  elf-reloc?

  (offset elf-reloc-offset)
  (type elf-reloc-type)
  (symbol-name elf-reloc-symbol-name)
  (addend elf-reloc-addend))


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
