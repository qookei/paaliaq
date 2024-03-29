(use-modules (paaliaq toolchain assembler dsl)
	     (paaliaq toolchain elf emit))
(use-modules (ice-9 getopt-long)
	     (ice-9 match))


(define (version)
  (display "\
as (paaliaq as) 0.1
Copyright (C) 2024  qookie
License GPLv3+: GNU GPL version 3 or later <https://gnu.org/licenses/gpl.html>.
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.
"))


(define (help)
  (display "\
paaliaq-as [OPTION]... FILE
Evaluate FILE with assembler facilities in scope and emit an object file.

Output control:
  -o, --output=FILE     write the output to FILE (default is `a.out')

Input control:
  -l, --load-path=PATH  add PATH to the %load-path

Miscellaneous:
  -v, --version         display the version information and exit
  -h, --help            display this help message and exit

The input FILE is evaluated with the assembler DSL in scope, and with the
toolchain path added to %load-path. The result of the input evaluation is used
to emit an ELF object file.

NOTE: Do not invoke the Scheme script directly, please use the paaliaq-as shell
wrapper script.
"))


(define (main args)
  (let* ([option-spec '([version   (single-char #\v) (value #f)]
			[help      (single-char #\h) (value #f)]
			[output    (single-char #\o) (value #t)]
			[load-path (single-char #\l) (value #t)])]
	 [options (getopt-long args option-spec)])
    (match (list (option-ref options 'version #f)
		 (option-ref options 'help #f)
		 (option-ref options '() #f))
      [(#t _  _) (version)]
      [(#f #t _) (help)]
      [(#f #f '()) (error "missing required positional argument: FILE")]
      [(#f #f (input-path . _))
       (add-to-load-path (option-ref options 'load-path ""))
       (let ([output-name (option-ref options 'output "a.out")]
	     [body (load (canonicalize-path input-path))])
	 (if (string=? input-path output-name)
	     (error "bailing out, refusing to overwrite input file with output file" input-path)
	     (call-with-output-file
		 output-name
	       (λ (port)
		 (emit-elf-object port body))
	       #:binary #t)))])))
