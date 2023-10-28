(define-module (as-helper assemble) #: export (assemble))

(use-modules (ice-9 match) (ice-9 format) (srfi srfi-1) (srfi srfi-26)
	     (ice-9 binary-ports) (rnrs bytevectors)
	     (as-helper utility))

(define single-byte-opcodes
  `((php . #x08) (phd . #x0b) (clc . #x18) (tcs . #x1b)
    (plp . #x28) (pld . #x2b) (sec . #x38) (tsc . #x3b)
    (rti . #x40) (wdm . #x42) (pha . #x48) (phk . #x4b)
    (cli . #x58) (phy . #x5a) (tcd . #x5b) (rts . #x60)
    (pla . #x68) (rtl . #x6b) (sei . #x78) (ply . #x7a)
    (tdc . #x7b) (txa . #x8a) (phb . #x8b) (tya . #x98)
    (txs . #x9a) (tay . #xa8) (tax . #xaa) (plb . #xab)
    (clv . #xb8) (tsx . #xba) (tyx . #xbb) (wai . #xcb)
    (cld . #xd8) (phx . #xda) (stp . #xdb) (nop . #xea)
    (xba . #xeb) (sed . #xf8) (plx . #xfa) (xce . #xfb)
    (txy . #x9b)))

(define branch-opcodes
  `(((bpl rel         ) . #x10) ((bmi rel         ) . #x30) ((bvc rel         ) . #x50)
    ((bvs rel         ) . #x70) ((bra rel         ) . #x80) ((brl long-rel    ) . #x82)
    ((bcc rel         ) . #x90) ((bcs rel         ) . #xb0) ((bne rel         ) . #xd0)
    ((beq rel         ) . #xf0)))

(define jump-opcodes
  `(((jsr abs         ) . #x20) ((jsl far-abs     ) . #x22) ((jmp abs         ) . #x4c)
    ((jmp far-abs     ) . #x5c) ((jmp ind-abs     ) . #x6c) ((jml ind-abs     ) . #xdc)
    ((jmp ind-x-abs   ) . #x7c) ((jsr ind-x-abs   ) . #xfc)))

(define ora-opcodes
  `(((ora ind-x-dp    ) . #x01) ((ora stk         ) . #x03) ((ora dp          ) . #x05)
    ((ora ind-far-dp  ) . #x07) ((ora imm         ) . #x09) ((ora abs         ) . #x0d)
    ((ora far-abs     ) . #x0f) ((ora y-ind-dp    ) . #x11) ((ora ind-dp      ) . #x12)
    ((ora y-ind-stk   ) . #x13) ((ora x-dp        ) . #x15) ((ora y-ind-far-dp) . #x17)
    ((ora x-abs       ) . #x1d) ((ora x-far-abs   ) . #x1f) ((ora y-abs       ) . #x19)))

(define and-opcodes
  `(((and ind-x-dp    ) . #x21) ((and stk         ) . #x23) ((and dp          ) . #x25)
    ((and ind-far-dp  ) . #x27) ((and imm         ) . #x29) ((and abs         ) . #x2d)
    ((and far-abs     ) . #x2f) ((and y-ind-dp    ) . #x31) ((and ind-dp      ) . #x32)
    ((and y-ind-stk   ) . #x33) ((and x-dp        ) . #x35) ((and y-ind-far-dp) . #x37)
    ((and x-abs       ) . #x3d) ((and x-far-abs   ) . #x3f) ((and y-abs       ) . #x39)))

(define eor-opcodes
  `(((eor ind-x-dp    ) . #x41) ((eor stk         ) . #x43) ((eor dp          ) . #x45)
    ((eor ind-far-dp  ) . #x47) ((eor imm         ) . #x49) ((eor abs         ) . #x4d)
    ((eor far-abs     ) . #x4f) ((eor y-ind-dp    ) . #x51) ((eor ind-dp      ) . #x52)
    ((eor y-ind-stk   ) . #x53) ((eor x-dp        ) . #x55) ((eor y-ind-far-dp) . #x57)
    ((eor x-abs       ) . #x5d) ((eor x-far-abs   ) . #x5f) ((eor y-abs       ) . #x59)))

(define adc-opcodes
  `(((adc ind-x-dp    ) . #x61) ((adc stk         ) . #x63) ((adc dp          ) . #x65)
    ((adc ind-far-dp  ) . #x67) ((adc imm         ) . #x69) ((adc abs         ) . #x6d)
    ((adc far-abs     ) . #x6f) ((adc y-ind-dp    ) . #x71) ((adc ind-dp      ) . #x72)
    ((adc y-ind-stk   ) . #x73) ((adc x-dp        ) . #x75) ((adc y-ind-far-dp) . #x77)
    ((adc x-abs       ) . #x7d) ((adc x-far-abs   ) . #x7f) ((adc y-abs       ) . #x79)))

(define sbc-opcodes
  `(((sbc ind-x-dp    ) . #xe1) ((sbc stk         ) . #xe3) ((sbc dp          ) . #xe5)
    ((sbc ind-far-dp  ) . #xe7) ((sbc imm         ) . #xe9) ((sbc abs         ) . #xed)
    ((sbc far-abs     ) . #xef) ((sbc y-ind-dp    ) . #xf1) ((sbc ind-dp      ) . #xf2)
    ((sbc y-ind-stk   ) . #xf3) ((sbc x-dp        ) . #xf5) ((sbc y-ind-far-dp) . #xf7)
    ((sbc x-abs       ) . #xfd) ((sbc x-far-abs   ) . #xff) ((sbc y-abs       ) . #xf9)))

(define inc-opcodes
  `(((inc a-reg       ) . #x1a) ((inc x-reg       ) . #xe8) ((inc y-reg       ) . #xc8)
    ((inc dp          ) . #xe6) ((inc abs         ) . #xee) ((inc x-dp        ) . #xf6)
    ((inc x-abs       ) . #xfe)))

(define dec-opcodes
  `(((dec a-reg       ) . #x3a) ((dec x-reg       ) . #xCA) ((dec y-reg       ) . #x88)
    ((dec dp          ) . #xc6) ((dec abs         ) . #xce) ((dec x-dp        ) . #xd6)
    ((dec x-abs       ) . #xde)))

(define lda-opcodes
  `(((lda ind-x-dp    ) . #xa1) ((lda stk         ) . #xa3) ((lda dp          ) . #xa5)
    ((lda ind-far-dp  ) . #xa7) ((lda imm         ) . #xa9) ((lda abs         ) . #xad)
    ((lda far-abs     ) . #xaf) ((lda y-ind-dp    ) . #xb1) ((lda ind-dp      ) . #xb2)
    ((lda y-ind-stk   ) . #xb3) ((lda x-dp        ) . #xb5) ((lda y-ind-far-dp) . #xb7)
    ((lda x-abs       ) . #xbd) ((lda x-far-abs   ) . #xbf) ((lda y-abs       ) . #xb9)))

(define sta-opcodes
  `(((sta ind-x-dp    ) . #x81) ((sta stk         ) . #x83) ((sta dp          ) . #x85)
    ((sta ind-far-dp  ) . #x87) ((sta abs         ) . #x8d) ((sta far-abs     ) . #x8f)
    ((sta y-ind-dp    ) . #x91) ((sta ind-dp      ) . #x92) ((sta y-ind-stk   ) . #x93)
    ((sta x-dp        ) . #x95) ((sta y-ind-far-dp) . #x97) ((sta x-abs       ) . #x9d)
    ((sta x-far-abs   ) . #x9f) ((sta y-abs       ) . #x99)))

(define cmp-opcodes
  `(((cmp ind-x-dp    ) . #xc1) ((cmp stk         ) . #xc3) ((cmp dp          ) . #xc5)
    ((cmp ind-far-dp  ) . #xc7) ((cmp imm         ) . #xc9) ((cmp abs         ) . #xcd)
    ((cmp far-abs     ) . #xcf) ((cmp y-ind-dp    ) . #xd1) ((cmp ind-dp      ) . #xd2)
    ((cmp y-ind-stk   ) . #xd3) ((cmp x-dp        ) . #xd5) ((cmp y-ind-far-dp) . #xd7)
    ((cmp x-abs       ) . #xdd) ((cmp x-far-abs   ) . #xdf) ((cmp y-abs       ) . #xd9)))

(define cpxy-opcodes
  `(((cpy imm         ) . #xc0) ((cpy dp          ) . #xc4) ((cpy abs         ) . #xcc)
    ((cpx imm         ) . #xe0) ((cpx dp          ) . #xe4) ((cpx abs         ) . #xec)))

(define bit-opcodes
  `(((bit dp          ) . #x24) ((bit abs         ) . #x2c) ((bit x-dp        ) . #x34)
    ((bit x-abs       ) . #x3c) ((bit imm         ) . #x89)))

(define rotate-opcodes
  `(((asl dp          ) . #x06) ((asl a-reg       ) . #x0a) ((asl abs         ) . #x0e)
    ((asl x-dp        ) . #x16) ((asl x-abs       ) . #x1e) ((rol dp          ) . #x26)
    ((rol a-reg       ) . #x2a) ((rol abs         ) . #x2e) ((rol x-dp        ) . #x36)
    ((rol x-abs       ) . #x3e) ((lsr dp          ) . #x46) ((lsr a-reg       ) . #x4a)
    ((lsr abs         ) . #x4e) ((lsr x-dp        ) . #x56) ((lsr x-abs       ) . #x5e)
    ((ror dp          ) . #x66) ((ror a-reg       ) . #x6a) ((ror abs         ) . #x6e)
    ((ror x-dp        ) . #x76) ((ror x-abs       ) . #x7e)))

(define ldxy-opcodes
  `(((ldy imm         ) . #xa0) ((ldy dp          ) . #xa4) ((ldy abs         ) . #xac)
    ((ldy x-dp        ) . #xb4) ((ldy x-abs       ) . #xbc) ((ldx imm         ) . #xa2)
    ((ldx dp          ) . #xa6) ((ldx abs         ) . #xae) ((ldx y-dp        ) . #xb6)
    ((ldx y-abs       ) . #xbe)))

(define stxy-opcodes
  `(((sty dp          ) . #x84) ((sty abs         ) . #x8c) ((sty x-dp        ) . #x94)
    ((stx dp          ) . #x86) ((stx abs         ) . #x8e) ((stx y-dp        ) . #x96)))

(define stz-opcodes
  `(((stz dp          ) . #x64) ((stz x-dp        ) . #x74) ((stz abs         ) . #x9c)
    ((stz x-abs       ) . #x9e)))

(define test-opcodes
  `(((tsb dp          ) . #x04) ((tsb abs         ) . #x0c) ((trb dp          ) . #x14)
    ((trb abs         ) . #x1c)))

(define push-opcodes
  `(((phe imm         ) . #xf4) ((phe rel         ) . #x62) ((phe ind-dp      ) . #xd4)))

(define flag-opcodes
  `(((rep imm         ) . #xc2) ((sep imm         ) . #xe2)))

(define misc-opcodes
  `(((brk imm         ) . #x00) ((cop imm         ) . #x00) ((mvp seg-from-to ) . #x44)
    ((mvn seg-from-to ) . #x54)))

(define multi-byte-opcodes
  `(,@branch-opcodes ,@jump-opcodes ,@flag-opcodes ,@push-opcodes
		     ,@rotate-opcodes ,@test-opcodes ,@misc-opcodes
		     ,@ldxy-opcodes ,@stxy-opcodes ,@stz-opcodes ,@cpxy-opcodes
		     ,@ora-opcodes ,@and-opcodes ,@eor-opcodes ,@adc-opcodes ,@sbc-opcodes ,@bit-opcodes
		     ,@inc-opcodes ,@dec-opcodes ,@lda-opcodes ,@sta-opcodes ,@cmp-opcodes))

(define (insn-to-opcode insn table)
  (match (assoc insn table)
    ((k . v) (list v))
    (_ (error "No such instruction:" insn))))

(define (in-list? table insn)
  (match (assoc insn table)
    ((k . v) #t) (_ #f)))

(define (in-list-without-mode? table insn)
  (match (assoc insn table (lambda (insn alistcar) (eq? insn (car alistcar))))
    ((k . v) #t) (_ #f)))

(define (label-decl? symbol)
  (and
   (symbol? symbol)
   (string=? (string-take-right (symbol->string symbol) 1) ":")))

(define (has-operand? insn)
  (match insn
    ((? label-decl?) #f)
    ;; Pseudoinstructions
    ((or '.assume-a-wide '.assume-a-narrow
	 '.assume-xy-wide '.assume-xy-narrow) #f)
    ((or '.adjust-frame '.data) #t)
    ;; Real instructions
    ((? (cut in-list? single-byte-opcodes <>)) #f)
    ((? (cut in-list-without-mode? multi-byte-opcodes <>)) #t)
    (_ (error "Illegal insn:" insn))))

(define (imm-size insn a-size xy-size)
  (match insn
    ((or 'ldx 'ldy 'cpx 'cpy) xy-size)
    ((or 'rep 'sep 'brk 'cop) 1)
    ((or 'phe) 2)
    (_ a-size)))

(define (branch-size insn)
  (match insn
    ('brl 2) (_ 1)))

(define all-addr-modes
  '(imm abs far-abs ind-abs
	ind-x-abs x-abs x-far-abs
	y-abs dp ind-dp ind-far-dp
	ind-x-dp y-ind-dp y-ind-far-dp
	x-dp y-dp stk y-ind-stk rel
	long-rel seg-from-to a-reg
	x-reg y-reg))

(define (is-immediate? oper)
  (if (list? oper)
      (not (any (cut eq? (car oper) <>) all-addr-modes))
      #t))

(define (normalize-oper insn oper)
  (if (is-immediate? oper)
      (match insn
	((? (cut in-list-without-mode? branch-opcodes <>)) `(rel ,oper))
	('jsl `(far-abs ,oper))
	((? (cut in-list-without-mode? jump-opcodes <>)) `(abs ,oper))
	(_ `(imm ,oper)))
      oper))

(define (value-now value)
  (if (number? value) value 0))

(define (oper-to-bytes insn oper a-size xy-size)
  (match oper
    (('imm v)
     (value-to-n-bytes (value-now v) (imm-size insn a-size xy-size)))

    (((or 'abs 'far-abs 'ind-abs 'ind-x-abs
	  'x-abs 'x-far-abs 'y-abs) v)
     (value-to-n-bytes (value-now v) 2))

    (((or 'dp 'ind-dp 'ind-far-dp 'ind-x-dp
	  'y-ind-dp 'y-ind-far-dp 'x-dp
	  'y-dp 'stk 'y-ind-stk) v)
     (value-to-n-bytes (value-now v) 1))

    (((or 'rel 'long-rel) v)
     ;; Always emit a relocation since the concrete PC value is not known here
     (value-to-n-bytes 0 (branch-size oper)))

    (('seg-from-to src dst)
     `(,(value-to-n-bytes (value-now src) 1)
       ,(value-to-n-bytes (value-now dst) 1)))

    (((or 'a-reg 'x-reg 'y-reg)) `())))


(define (reloc-if-needed value reloc-type reloc-at reloc-stack-off reloc-size)
  (if (number? value)
      `()
      `((,reloc-type ,reloc-at ,reloc-stack-off ,reloc-size ,value))))

(define (oper-to-reloc pc insn oper a-size xy-size stack-off)
  (match oper
    (('imm v)
     (reloc-if-needed v 'reloc-abs (+ pc 1) stack-off (imm-size insn a-size xy-size)))

    (((or 'abs 'far-abs 'ind-abs 'ind-x-abs
	  'x-abs 'x-far-abs 'y-abs) v)
     (reloc-if-needed v 'reloc-abs (+ pc 1) stack-off 2))

    (((or 'dp 'ind-dp 'ind-far-dp 'ind-x-dp
	  'y-ind-dp 'y-ind-far-dp 'x-dp
	  'y-dp) v)
     (reloc-if-needed v 'reloc-abs (+ pc 1) stack-off 1))

    (((or 'stk 'y-ind-stk) v)
     (reloc-if-needed v 'reloc-frame-rel (+ pc 1) stack-off 1))

    (((or 'rel 'long-rel) v)
     `((reloc-branch ,(+ pc 1) ,stack-off ,(branch-size oper) ,(cadr oper))))

    (('seg-from-to src dst)
     `(,@(reloc-if-needed src 'reloc-abs (+ pc 1) stack-off 1)
       ,@(reloc-if-needed dst 'reloc-abs (+ pc 2) stack-off 1)))

    (((or 'a-reg 'x-reg 'y-reg)) `())))

(define (multibyte-to-bytes insn oper a-size xy-size)
  (let ((norm (normalize-oper insn oper)))
    (append
     (insn-to-opcode `(,insn ,(car norm)) multi-byte-opcodes)
     (oper-to-bytes insn norm a-size xy-size))))

(define (multibyte-to-relocs pc insn oper a-size xy-size stack-off)
  (let ((norm (normalize-oper insn oper)))
    (oper-to-reloc pc insn norm a-size xy-size stack-off)))

(define (data-to-bytes size data)
  (apply append
	 (map
	  (lambda (datum)
	    (value-to-n-bytes (value-now datum) size))
	  data)))

(define (data-to-relocs pc size data stack-off)
  (let ((i 0))
    (apply append
	   (map-in-order
	    (lambda (datum)
	      (set! i (+ i size))
	      (reloc-if-needed datum 'reloc-abs (+ pc i (- size)) stack-off size))
	    data))))

(define (label-decl-to-name decl)
  (string->symbol (string-drop-right (symbol->string decl) 1)))

(define (label-to-decl name)
  (string->symbol (string-append (symbol->string name) ":")))

(define (skip-one-insn insns)
  (if (has-operand? (car insns))
      (cddr insns)
      (cdr insns)))

(define (current-insn insns)
  (if (has-operand? (car insns))
      `(,(car insns) ,(cadr insns)) (car insns)))

(define (assemble insns)
  (let ((cur-insns insns) (bytes '()) (relocs '()) (labels '()) (a-size 1) (xy-size 1) (stack-off 0))
    (while (not (null? cur-insns))
      (match (current-insn cur-insns)
	('.assume-a-narrow (set! a-size 1))
	('.assume-a-wide (set! a-size 2))
	('.assume-xy-narrow (set! xy-size 1))
	('.assume-xy-wide (set! xy-size 2))
	(('.adjust-frame by) (set! stack-off (+ stack-off by)))
	(('.data (entry-size entries))
	 (set! relocs (append relocs
			      (data-to-relocs (length bytes) entry-size entries stack-off)))
	 (set! bytes (append bytes
			     (data-to-bytes entry-size entries))))
	((? label-decl? label-token)
	 (set! labels (cons `(,(label-decl-to-name label-token) . ,(length bytes)) labels)))
	(((? has-operand? insn) oper)
	 (set! relocs (append relocs
			      (multibyte-to-relocs (length bytes) insn oper a-size xy-size stack-off)))
	 (set! bytes (append bytes
			     (multibyte-to-bytes insn oper a-size xy-size))))
	(insn (set! bytes
		    (append bytes (insn-to-opcode insn single-byte-opcodes)))))
      (set! cur-insns (skip-one-insn cur-insns)))
    `(,bytes ,relocs ,labels)))
