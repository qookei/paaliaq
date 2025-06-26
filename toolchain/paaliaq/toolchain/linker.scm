(use-modules (paaliaq toolchain linker input)
	     (paaliaq toolchain linker output))
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
  -b, --base=BASE       use BASE as the base address (default is 0x8000)
  -e, --entry=ENTRY     use ENTRY as the entry point (default is `_start')

Miscellaneous:
  -v, --version         display the version information and exit
  -h, --help            display this help message and exit

NOTE: Do not invoke the Scheme script directly, please use the paaliaq-ld shell
wrapper script.
"))

(define +default-section-rules+
  '((".everything"
     (section ".head.text")

     (symbol "__stext")
     (section ".text*")
     (symbol "__etext")

     (symbol "__srodata")
     (section ".rodata*")
     (symbol "__erodata")

     (symbol "__sdata")
     (section ".data*")
     (symbol "__edata")

     (symbol "__sbss")
     (section ".bss*")
     (symbol "__ebss"))))


;; TODO(qookie): Linker script, library paths (? maybe just take .a
;; files as arguments?)
(define (main args)
  (let* ([option-spec '([version   (single-char #\v) (value #f)]
			[help      (single-char #\h) (value #f)]
			[output    (single-char #\o) (value #t)]
			[base      (single-char #\b) (value #t)]
			[entry     (single-char #\e) (value #t)])]
	 [options (getopt-long args option-spec)])
    (match (list (option-ref options 'version #f)
		 (option-ref options 'help #f)
		 (option-ref options '() #f))
      [(#t _  _) (version)]
      [(#f #t _) (help)]
      [(#f #f '()) (error "missing required positional argument: FILE")]
      [(#f #f input-paths)
       (let ([output-name (option-ref options 'output "a.out")]
	     [entry-name (option-ref options 'entry "_start")]
	     [base (option-ref options 'base "#x8000")])
	 (if (any (λ (path)
		    (string=? path output-name))
		  input-paths)
	     (error "bailing out, refusing to overwrite input file with output file"))
	 (match-let ([(symbol-origins . output-sections)
		      (process-inputs-into-sections input-paths +default-section-rules+)])
	   (emit-output-elf output-name
			    output-sections
			    (string->number base)
			    entry-name)))])))
