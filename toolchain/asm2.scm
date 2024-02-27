(define-module (asm2))

(use-modules (ice-9 match) (srfi srfi-1) (srfi srfi-26)
	     (srfi srfi-9) (srfi srfi-9 gnu)
	     (ice-9 pretty-print) (asm-tables))

(define-record-type <assy-state>
  (make-assy-state labels a-size xy-size offset)
  assy-state?

  (labels assy-labels)
  (a-size assy-a-size)
  (xy-size assy-xy-size)
  (offset assy-offset))


;; NOTE: We also emit single numbers for individual bytes instead of bytevectors

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

(define (%operand-reloc reloc symbol)
  (match symbol
    ;; Literal values
    [((? number? value))
     '()]
    ;; Symbol with an addend
    [((? symbol? symbol) (? number? addend))
     (list (list reloc (symbol->string symbol) addend))]
    ;; Just the symbol
    [((? symbol? symbol))
     (list (list reloc (symbol->string symbol) 0))]
    ;; Bank of the symbol
    [(#:bank (? symbol? symbol))
     (list (list 'R_W65C816_BANK (symbol->string symbol) 0))]
    [_ (error "illegal operand symbol" symbol)]))

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
    [(3 . _) '(0 0 0)]))

(define (%from-to-reloc symbol)
  (match symbol
    ;; Literal values
    [((? number? value) . rest)
     (list '() rest)]
    [(#:bank (? symbol? symbol) . rest)
     (list (list (list 'R_W65C816_BANK (symbol->string symbol) 0)) rest)]
    [_ (error "illegal operand(s) symbol for mvn/mvp" symbol)]))

(define (%reloc-and-bytes-for insn operand state)
  (match (%simplify-operand-kind insn operand state)
    [(0 'none) '()]
    [(1 'none (? number? value)) (%operand-value 1 value)]
    [(size 'abs . symbol)
     (append (%operand-reloc
	      (match size
		[1 'THIS-SHOULDN'T-REACH-THE-ELF]
		[2 'R_W65C816_ABS16]
		[3 'R_W65C816_ABS24])
	      symbol)
	     (%operand-value size symbol))]
    [(size 'rel . symbol)
     (append (%operand-reloc
	      (match size
		[1 'R_W65C816_REL8]
		[2 'R_W65C816_REL16])
	      symbol)
	     (%operand-value size symbol))]
    [(0 'from-to . symbols)
     (match-let* (([reloc1 rest1] (%from-to-reloc symbols))
		  ([reloc2 rest2] (%from-to-reloc rest1)))
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
    [_ (error "syntax error, unrecognized form" input)]))

(define (%lower-local-label-relocs proc-name input state)
  (map
   (λ (elem)
     (if (list? elem) ;; TODO: elf-reloc?
	 (match (assoc (second elem) (assy-labels state))
	   [(_ . offset) (list (first elem) proc-name (third elem))]
	   [#f elem])
	 elem))
   input))

(define (%assemble-many proc-name input state)
  (let loop ([input input]
	     [output '()]
	     [state state])
    (if (null? input)
	(list (%lower-local-label-relocs proc-name output state) state)
	(match-let (([rest insn-output new-state] (%assemble-one input state)))
	  (loop rest (append output insn-output) new-state)))))

(pretty-print
 (%assemble-many
  "foo"
  '(.a-bits 16
    lda #x42
  #:x
    sta (dp #x12)
    bra x
    brl x
    lda (imm #:bank asdf)
    nop
    mvn (#:bank foo #:bank bar)
    jmp (tbl +10)
    jsl (tbl +10)
    jml (ind-abs tbl +10)
   )
  (make-assy-state '() 1 1 0)))