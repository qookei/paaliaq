(define-module (paaliaq toolchain assembler core)
  #:use-module (paaliaq toolchain assembler tables)
  #:use-module (paaliaq toolchain elf defines)
  #:use-module (paaliaq toolchain elf format)

  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (srfi srfi-9 gnu)
  #:use-module (srfi srfi-26)

  #:export (make-assy-state
	    assy-state?
	    assy-labels
	    assy-a-size
	    assy-xy-size
	    assy-offset

	    make-default-assy-state

	    assemble-many
	    assemble
	    data-table))


(define-record-type <assy-state>
  (make-assy-state labels a-size xy-size offset)
  assy-state?

  (labels assy-labels)
  (a-size assy-a-size)
  (xy-size assy-xy-size)
  (offset assy-offset))

(define (make-default-assy-state)
  (make-assy-state '() 1 1 0))

;; -----------------------------------------------------------------------------

;; NOTE: We also emit single numbers for individual bytes instead of bytevectors

(define (%simplify-operand-kind insn operand state)
  (append-reverse
   (match (list insn (car operand))
     ;; No operand
     [(_ (or 'a-reg 'x-reg 'y-reg 'none))
      (list 'none 0)]
     ;; Operand with no relocation allowed
     [(_ (or 'dp 'ind-dp 'ind-far-dp 'ind-x-dp
	     'y-ind-dp 'y-ind-far-dp 'x-dp
	     'y-dp 'stk 'y-ind-stk))
      (list 'none 1)]
     ;; Immediate
     [((or 'ldx 'ldy 'cpx 'cpy) 'imm)
      (list 'abs (assy-xy-size state))]
     [((or 'rep 'sep 'brk 'cop) 'imm)
      (list 'abs 1)]
     [('phe 'imm)
      (list 'abs 2)]
     [(_ 'imm)
      (list 'abs (assy-a-size state))]
     ;; Absolute
     [(_ (or 'far-abs 'x-far-abs))
      (list 'abs 3)]
     [(_ (or 'abs 'ind-abs 'ind-x-abs 'x-abs 'y-abs))
      (list 'abs 2)]
     ;; Relative
     [('brl 'rel)
      (list 'rel 2)]
     [(_ 'rel)
      (list 'rel 1)]
     ;; Misc
     [(_ 'seg-from-to)
      (list 'from-to 0)])
   (cdr operand)))

(define (%regular-operand-reloc reloc symbol)
  (match symbol
    ;; Literal values
    [((? number? value))
     '()]
    ;; Symbol with an addend
    [((? symbol? symbol) (? number? addend))
     (if (= reloc R_W65C816_NONE)
	 (error "bailing out, refusing to emit R_W65C816_NONE" symbol addend))
     (list (make-elf-reloc -1 reloc (symbol->string symbol) addend))]
    ;; Just the symbol
    [((? symbol? symbol))
     (if (= reloc R_W65C816_NONE)
	 (error "bailing out, refusing to emit R_W65C816_NONE" symbol))
     (list (make-elf-reloc -1 reloc (symbol->string symbol) 0))]
    ;; Bank of the symbol
    [(#:bank (? symbol? symbol))
     (list (make-elf-reloc -1 R_W65C816_BANK (symbol->string symbol) 0))]
    [_ (error "illegal operand symbol" symbol)]))

(define (%from-to-operand-reloc symbol)
  (match symbol
    ;; Literal values
    [((? number? value) . rest)
     (list '() rest)]
    [(#:bank (? symbol? symbol) . rest)
     (list (list (make-elf-reloc -1 R_W65C816_BANK (symbol->string symbol) 0)) rest)]
    [_ (error "illegal operand(s) symbol for mvn/mvp" symbol)]))

(define (%operand-value size symbol)
  (match (cons size symbol)
    ;; Literal values
    [(size (? number? value) . _)
     (if (> value (expt 2 (* size 8)))
	 (error "immediate value out of range" value (* size 8))
	 (map (λ (i) (logand (ash value (* i -8)) #xff))
	      (iota size)))]
    ;; Anything else
    [(1 . _) '(0)]
    [(2 . _) '(0 0)]
    [(3 . _) '(0 0 0)]
    [(4 . _) '(0 0 0 0)]))

(define (%reloc-and-bytes-for insn operand state)
  (match (%simplify-operand-kind insn operand state)
    [(0 'none) '()]
    [(1 'none (? number? value)) (%operand-value 1 value)]
    [(size 'abs . symbol)
     (append (%regular-operand-reloc
	      (match size
		[1 R_W65C816_NONE]
		[2 R_W65C816_ABS16]
		[3 R_W65C816_ABS24])
	      symbol)
	     (%operand-value size symbol))]
    [(size 'rel . symbol)
     (append (%regular-operand-reloc
	      (match size
		[1 R_W65C816_REL8]
		[2 R_W65C816_REL16])
	      symbol)
	     (%operand-value size symbol))]
    [(0 'from-to . symbols)
     (match-let* (([reloc1 rest1] (%from-to-operand-reloc symbols))
		  ([reloc2 rest2] (%from-to-operand-reloc rest1)))
       (if (null? rest2)
	   (append reloc1 (%operand-value 1 symbols)
		   reloc2 (%operand-value 1 rest1))
	   (error "illegal mvn/mvp, unconsumed" rest2)))]))


(define (%real-insn insn operand state)
  (match (assoc (list insn (car operand)) all-opcodes)
    [(_ . opcode)
     (let ([operand-data (%reloc-and-bytes-for insn operand state)])
       (list (cons opcode operand-data)
	     (set-field state
			[assy-offset]
			(+ 1 (assy-offset state)
			   (count number? operand-data)))))]
    [_ (error "no such instruction" insn (car operand))]))

;; -----------------------------------------------------------------------------

(define (%normalize-operand insn operand)
  (define (immediate? operand)
    (if (list? operand)
	(match (assoc (list insn (car operand)) complex-opcodes)
	  [#f #t]
	  [_ #f])
	#t))

  (define (into-normal body)
    (if (list? body) body (list body)))

  (match (list insn operand)
    [('jsl (? immediate? (= into-normal imm)))
     (cons 'far-abs imm)]
    [((or 'jsr 'jmp) (? immediate? (= into-normal imm)))
     (cons 'abs imm)]
    [((? (cut member <> branch-instructions)) (? immediate? (= into-normal imm)))
     (cons 'rel imm)]
    [((or 'mvn 'mvp) (? immediate? (= into-normal imm)))
     (cons 'seg-from-to imm)]
    [(_ (? immediate? (= into-normal imm)))
     (cons 'imm imm)]
    [_ operand]))

(define (%handle-reg-size bits)
  (match bits
    [8 1]
    [16 2]
    [_ (error "invalid register size" bits)]))

(define (%assemble-one input state)
  (match input
    [('.a-bits (? number? bits) . rest)
     (list rest
	   '()
	   (set-field state [assy-a-size] (%handle-reg-size bits)))]
    [('.xy-bits (? number? bits) . rest)
     (list rest
	   '()
	   (set-field state [assy-xy-size] (%handle-reg-size bits)))]
    [((? keyword? (= keyword->symbol label)) . rest)
     (list rest
	   '()
	   (set-field state [assy-labels] (acons (symbol->string label)
						 (assy-offset state)
						 (assy-labels state))))]
    [((? (cut member <> simple-instructions) insn) . rest)
     (cons rest (%real-insn insn '(none) state))]
    [((? (cut member <> complex-instructions) insn)
      (= (cut %normalize-operand insn <>) operand) . rest)
     (cons rest (%real-insn insn operand state))]
    [_ (error "unrecognized form" input)]))

;; -----------------------------------------------------------------------------

(define (%lower-local-label-relocs proc-name input state)
  (map
   (λ (elem)
     (if (elf-reloc? elem)
	 (match (assoc (elf-reloc-symbol-name elem) (assy-labels state))
	   [(_ . offset)
	    (set-fields elem
			([elf-reloc-symbol-name] proc-name)
			([elf-reloc-addend] (+ offset (elf-reloc-addend elem))))]
	   [#f elem])
	 elem))
   input))

(define (assemble-many proc-name input state)
  (let loop ([input input]
	     [output '()]
	     [state state])
    (if (null? input)
	(list (%lower-local-label-relocs proc-name output state) state)
	(match-let (([rest insn-output new-state] (%assemble-one input state)))
	  (loop rest (append output insn-output) new-state)))))

(define (assemble proc-name input)
  (car (assemble-many proc-name input (make-default-assy-state))))

;; -----------------------------------------------------------------------------

(define (data-table item-size input)
  (map
   (compose
    (λ (item)
      (append (%regular-operand-reloc
	       (match item-size
		 [1 R_W65C816_NONE]
		 [2 R_W65C816_ABS16]
		 [3 R_W65C816_ABS24]
		 [4 R_W65C816_NONE])
	       item)
	      (%operand-value item-size item)))
    (λ (item)
      (if (list? item)
	  item
	  (list item))))
   input))
