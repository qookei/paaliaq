(define-module (paaliaq toolchain assembler tables)
  #:export (complex-opcodes
	    simple-opcodes
	    all-opcodes

	    complex-instructions
	    simple-instructions
	    branch-instructions))

(define branch-opcodes
  '([(bpl rel         ) . #x10] [(bmi rel         ) . #x30] [(bvc rel         ) . #x50]
    [(bvs rel         ) . #x70] [(bra rel         ) . #x80] [(brl rel         ) . #x82]
    [(bcc rel         ) . #x90] [(bcs rel         ) . #xb0] [(bne rel         ) . #xd0]
    [(beq rel         ) . #xf0]))


(define jump-opcodes
  '([(jsr abs         ) . #x20] [(jsl far-abs     ) . #x22] [(jmp abs         ) . #x4c]
    [(jmp far-abs     ) . #x5c] [(jmp ind-abs     ) . #x6c] [(jml ind-abs     ) . #xdc]
    [(jmp ind-x-abs   ) . #x7c] [(jsr ind-x-abs   ) . #xfc]))


(define ora-opcodes
  '([(ora ind-x-dp    ) . #x01] [(ora stk         ) . #x03] [(ora dp          ) . #x05]
    [(ora ind-far-dp  ) . #x07] [(ora imm         ) . #x09] [(ora abs         ) . #x0d]
    [(ora far-abs     ) . #x0f] [(ora y-ind-dp    ) . #x11] [(ora ind-dp      ) . #x12]
    [(ora y-ind-stk   ) . #x13] [(ora x-dp        ) . #x15] [(ora y-ind-far-dp) . #x17]
    [(ora x-abs       ) . #x1d] [(ora x-far-abs   ) . #x1f] [(ora y-abs       ) . #x19]))


(define and-opcodes
  '([(and ind-x-dp    ) . #x21] [(and stk         ) . #x23] [(and dp          ) . #x25]
    [(and ind-far-dp  ) . #x27] [(and imm         ) . #x29] [(and abs         ) . #x2d]
    [(and far-abs     ) . #x2f] [(and y-ind-dp    ) . #x31] [(and ind-dp      ) . #x32]
    [(and y-ind-stk   ) . #x33] [(and x-dp        ) . #x35] [(and y-ind-far-dp) . #x37]
    [(and x-abs       ) . #x3d] [(and x-far-abs   ) . #x3f] [(and y-abs       ) . #x39]))


(define eor-opcodes
  '([(eor ind-x-dp    ) . #x41] [(eor stk         ) . #x43] [(eor dp          ) . #x45]
    [(eor ind-far-dp  ) . #x47] [(eor imm         ) . #x49] [(eor abs         ) . #x4d]
    [(eor far-abs     ) . #x4f] [(eor y-ind-dp    ) . #x51] [(eor ind-dp      ) . #x52]
    [(eor y-ind-stk   ) . #x53] [(eor x-dp        ) . #x55] [(eor y-ind-far-dp) . #x57]
    [(eor x-abs       ) . #x5d] [(eor x-far-abs   ) . #x5f] [(eor y-abs       ) . #x59]))


(define adc-opcodes
  '([(adc ind-x-dp    ) . #x61] [(adc stk         ) . #x63] [(adc dp          ) . #x65]
    [(adc ind-far-dp  ) . #x67] [(adc imm         ) . #x69] [(adc abs         ) . #x6d]
    [(adc far-abs     ) . #x6f] [(adc y-ind-dp    ) . #x71] [(adc ind-dp      ) . #x72]
    [(adc y-ind-stk   ) . #x73] [(adc x-dp        ) . #x75] [(adc y-ind-far-dp) . #x77]
    [(adc x-abs       ) . #x7d] [(adc x-far-abs   ) . #x7f] [(adc y-abs       ) . #x79]))


(define sbc-opcodes
  '([(sbc ind-x-dp    ) . #xe1] [(sbc stk         ) . #xe3] [(sbc dp          ) . #xe5]
    [(sbc ind-far-dp  ) . #xe7] [(sbc imm         ) . #xe9] [(sbc abs         ) . #xed]
    [(sbc far-abs     ) . #xef] [(sbc y-ind-dp    ) . #xf1] [(sbc ind-dp      ) . #xf2]
    [(sbc y-ind-stk   ) . #xf3] [(sbc x-dp        ) . #xf5] [(sbc y-ind-far-dp) . #xf7]
    [(sbc x-abs       ) . #xfd] [(sbc x-far-abs   ) . #xff] [(sbc y-abs       ) . #xf9]))


(define inc-opcodes
  '([(inc a-reg       ) . #x1a] [(inc x-reg       ) . #xe8] [(inc y-reg       ) . #xc8]
    [(inc dp          ) . #xe6] [(inc abs         ) . #xee] [(inc x-dp        ) . #xf6]
    [(inc x-abs       ) . #xfe]))


(define dec-opcodes
  '([(dec a-reg       ) . #x3a] [(dec x-reg       ) . #xCA] [(dec y-reg       ) . #x88]
    [(dec dp          ) . #xc6] [(dec abs         ) . #xce] [(dec x-dp        ) . #xd6]
    [(dec x-abs       ) . #xde]))


(define lda-opcodes
  '([(lda ind-x-dp    ) . #xa1] [(lda stk         ) . #xa3] [(lda dp          ) . #xa5]
    [(lda ind-far-dp  ) . #xa7] [(lda imm         ) . #xa9] [(lda abs         ) . #xad]
    [(lda far-abs     ) . #xaf] [(lda y-ind-dp    ) . #xb1] [(lda ind-dp      ) . #xb2]
    [(lda y-ind-stk   ) . #xb3] [(lda x-dp        ) . #xb5] [(lda y-ind-far-dp) . #xb7]
    [(lda x-abs       ) . #xbd] [(lda x-far-abs   ) . #xbf] [(lda y-abs       ) . #xb9]))


(define sta-opcodes
  '([(sta ind-x-dp    ) . #x81] [(sta stk         ) . #x83] [(sta dp          ) . #x85]
    [(sta ind-far-dp  ) . #x87] [(sta abs         ) . #x8d] [(sta far-abs     ) . #x8f]
    [(sta y-ind-dp    ) . #x91] [(sta ind-dp      ) . #x92] [(sta y-ind-stk   ) . #x93]
    [(sta x-dp        ) . #x95] [(sta y-ind-far-dp) . #x97] [(sta x-abs       ) . #x9d]
    [(sta x-far-abs   ) . #x9f] [(sta y-abs       ) . #x99]))


(define cmp-opcodes
  '([(cmp ind-x-dp    ) . #xc1] [(cmp stk         ) . #xc3] [(cmp dp          ) . #xc5]
    [(cmp ind-far-dp  ) . #xc7] [(cmp imm         ) . #xc9] [(cmp abs         ) . #xcd]
    [(cmp far-abs     ) . #xcf] [(cmp y-ind-dp    ) . #xd1] [(cmp ind-dp      ) . #xd2]
    [(cmp y-ind-stk   ) . #xd3] [(cmp x-dp        ) . #xd5] [(cmp y-ind-far-dp) . #xd7]
    [(cmp x-abs       ) . #xdd] [(cmp x-far-abs   ) . #xdf] [(cmp y-abs       ) . #xd9]))


(define cpxy-opcodes
  '([(cpy imm         ) . #xc0] [(cpy dp          ) . #xc4] [(cpy abs         ) . #xcc]
    [(cpx imm         ) . #xe0] [(cpx dp          ) . #xe4] [(cpx abs         ) . #xec]))


(define bit-opcodes
  '([(bit dp          ) . #x24] [(bit abs         ) . #x2c] [(bit x-dp        ) . #x34]
    [(bit x-abs       ) . #x3c] [(bit imm         ) . #x89]))


(define rotate-opcodes
  '([(asl dp          ) . #x06] [(asl a-reg       ) . #x0a] [(asl abs         ) . #x0e]
    [(asl x-dp        ) . #x16] [(asl x-abs       ) . #x1e] [(rol dp          ) . #x26]
    [(rol a-reg       ) . #x2a] [(rol abs         ) . #x2e] [(rol x-dp        ) . #x36]
    [(rol x-abs       ) . #x3e] [(lsr dp          ) . #x46] [(lsr a-reg       ) . #x4a]
    [(lsr abs         ) . #x4e] [(lsr x-dp        ) . #x56] [(lsr x-abs       ) . #x5e]
    [(ror dp          ) . #x66] [(ror a-reg       ) . #x6a] [(ror abs         ) . #x6e]
    [(ror x-dp        ) . #x76] [(ror x-abs       ) . #x7e]))


(define ldxy-opcodes
  '([(ldy imm         ) . #xa0] [(ldy dp          ) . #xa4] [(ldy abs         ) . #xac]
    [(ldy x-dp        ) . #xb4] [(ldy x-abs       ) . #xbc] [(ldx imm         ) . #xa2]
    [(ldx dp          ) . #xa6] [(ldx abs         ) . #xae] [(ldx y-dp        ) . #xb6]
    [(ldx y-abs       ) . #xbe]))


(define stxy-opcodes
  '([(sty dp          ) . #x84] [(sty abs         ) . #x8c] [(sty x-dp        ) . #x94]
    [(stx dp          ) . #x86] [(stx abs         ) . #x8e] [(stx y-dp        ) . #x96]))


(define stz-opcodes
  '([(stz dp          ) . #x64] [(stz x-dp        ) . #x74] [(stz abs         ) . #x9c]
    [(stz x-abs       ) . #x9e]))


(define test-opcodes
  '([(tsb dp          ) . #x04] [(tsb abs         ) . #x0c] [(trb dp          ) . #x14]
    [(trb abs         ) . #x1c]))


(define push-opcodes
  '([(phe imm         ) . #xf4] [(phe rel         ) . #x62] [(phe ind-dp      ) . #xd4]))


(define flag-opcodes
  '([(rep imm         ) . #xc2] [(sep imm         ) . #xe2]))


(define misc-opcodes
  '([(brk imm         ) . #x00] [(cop imm         ) . #x02] [(mvp seg-from-to ) . #x44]
    [(mvn seg-from-to ) . #x54]))


(define complex-opcodes
  (append branch-opcodes jump-opcodes flag-opcodes
	  push-opcodes rotate-opcodes test-opcodes
	  misc-opcodes ldxy-opcodes stxy-opcodes
	  stz-opcodes cpxy-opcodes ora-opcodes
	  and-opcodes eor-opcodes adc-opcodes
	  sbc-opcodes bit-opcodes inc-opcodes
	  dec-opcodes lda-opcodes sta-opcodes
	  cmp-opcodes))


(define simple-opcodes
  '([(php none        ) . #x08] [(phd none        ) . #x0b] [(clc none        ) . #x18]
    [(tcs none        ) . #x1b] [(plp none        ) . #x28] [(pld none        ) . #x2b]
    [(sec none        ) . #x38] [(tsc none        ) . #x3b] [(rti none        ) . #x40]
    [(wdm none        ) . #x42] [(pha none        ) . #x48] [(phk none        ) . #x4b]
    [(cli none        ) . #x58] [(phy none        ) . #x5a] [(tcd none        ) . #x5b]
    [(rts none        ) . #x60] [(pla none        ) . #x68] [(rtl none        ) . #x6b]
    [(sei none        ) . #x78] [(ply none        ) . #x7a] [(tdc none        ) . #x7b]
    [(txa none        ) . #x8a] [(phb none        ) . #x8b] [(tya none        ) . #x98]
    [(txs none        ) . #x9a] [(tay none        ) . #xa8] [(tax none        ) . #xaa]
    [(plb none        ) . #xab] [(clv none        ) . #xb8] [(tsx none        ) . #xba]
    [(tyx none        ) . #xbb] [(wai none        ) . #xcb] [(cld none        ) . #xd8]
    [(phx none        ) . #xda] [(stp none        ) . #xdb] [(nop none        ) . #xea]
    [(xba none        ) . #xeb] [(sed none        ) . #xf8] [(plx none        ) . #xfa]
    [(xce none        ) . #xfb] [(txy none        ) . #x9b]))


(define all-opcodes
  (append simple-opcodes complex-opcodes))


(define simple-instructions
  (map caar simple-opcodes))


(define complex-instructions
  (map caar complex-opcodes))


(define branch-instructions
  (map caar branch-opcodes))
