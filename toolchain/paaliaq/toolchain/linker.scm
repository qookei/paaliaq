(use-modules (paaliaq toolchain assembler dsl)
	     (paaliaq toolchain elf emit))
(use-modules (ice-9 getopt-long)
	     (ice-9 match)
	     (srfi srfi-1))


(define (version)
  (display "\
ld (paaliaq ld) 0.1
Copyright (C) 2025  qookie
License GPLv3+: GNU GPL version 3 or later <https://gnu.org/licenses/gpl.html>.
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.
"))


(define (help)
  (display "\
paaliaq-ld [OPTION]... FILE [FILE]...
Link object FILEs together into a single output ELF file.

Output control:
  -o, --output=FILE     write the output to FILE (default is `a.out')

Miscellaneous:
  -v, --version         display the version information and exit
  -h, --help            display this help message and exit

NOTE: Do not invoke the Scheme script directly, please use the paaliaq-ld shell
wrapper script.
"))


;; TODO(qookie): Linker script, library paths (? maybe just take .a
;; files as arguments?)
(define (main args)
  (let* ([option-spec '([version   (single-char #\v) (value #f)]
			[help      (single-char #\h) (value #f)]
			[output    (single-char #\o) (value #t)])]
	 [options (getopt-long args option-spec)])
    (match (list (option-ref options 'version #f)
		 (option-ref options 'help #f)
		 (option-ref options '() #f))
      [(#t _  _) (version)]
      [(#f #t _) (help)]
      [(#f #f '()) (error "missing required positional argument: FILE")]
      [(#f #f input-paths)
       (let ([output-name (option-ref options 'output "a.out")])
	 (if (any (λ (path)
		    (string=? path output-name))
		  input-paths)
	     (error "bailing out, refusing to overwrite input file with output file")
	     (error "TODO: link files together :)" input-paths output-name)))])))
