(define-module (paaliaq toolchain elf util)
  #:use-module (paaliaq toolchain elf defines)
  #:use-module (srfi srfi-9 gnu)
  #:export (offset-relocations offset-symbols))


(define (offset-relocations offset relocs)
  (map
   (λ (reloc)
     (set-field reloc
		(elf-reloc-offset)
		(+ (elf-reloc-offset reloc) offset)))
   relocs))

(define (offset-symbols offset symbols)
  (map
   (λ (sym)
     (set-field sym
		(elf-symbol-offset)
		(+ (elf-symbol-offset sym) offset)))
   symbols))
