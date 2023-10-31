(define-module (elf))

(use-modules (rnrs bytevectors)
	     (rnrs bytevectors gnu))

(define-syntax-rule (define-field name at size)
  (define-public name
    (make-procedure-with-setter
     (λ (bv)
       (bytevector-uint-ref bv at 'little size))
     (λ (bv value)
       (bytevector-uint-set! bv at value 'little size)))))

(define-syntax-rule (define-slice name at size)
  (define-public (name bv) (bytevector-slice bv at size)))


;; --------------------
;; Elf32_Ehdr
;; --------------------

(define-slice e_ident 0 16)
(define-public EI_MAG0 0)
(define-public EI_MAG1 1)
(define-public EI_MAG2 2)
(define-public EI_MAG3 3)
(define-field ei_mag EI_MAG0 4)
(define-public EI_MAG #x464c457f)

(define-public EI_CLASS 4)
(define-field ei_class EI_CLASS 1)
(define-public ELFCLASS32 1)

(define-public EI_DATA 5)
(define-field ei_data EI_DATA 1)
(define-public ELFDATA2LSB 1)

(define-public EI_VERSION 6)
(define-field ei_version EI_VERSION 1)

(define-public EI_OSABI 7)
(define-field ei_osabi EI_OSABI 1)

(define-public ELFOSABI_SYSV 0)
(define-public ELFOSABI_HPUX 1)
(define-public ELFOSABI_NETBSD 2)
(define-public ELFOSABI_GNU 3)
(define-public ELFOSABI_SOLARIS 6)
(define-public ELFOSABI_AIX 7)
(define-public ELFOSABI_IRIX 8)
(define-public ELFOSABI_FREEBSD 9)
(define-public ELFOSABI_TRU64 10)
(define-public ELFOSABI_MODESTO 11)
(define-public ELFOSABI_OPENBSD 12)
(define-public ELFOSABI_ARM_AEABI 64)
(define-public ELFOSABI_ARM 97)
(define-public ELFOSABI_STANDALONE 255)

(define-public EI_ABIVERSION 8)
(define-field ei_abiversion EI_ABIVERSION 1)

(define-public EI_PAD 9)
(define-slice ei_pad EI_PAD (- 16 EI_PAD))

(define-field e_type 16 2)
(define-public ET_NONE 0)
(define-public ET_REL 1)
(define-public ET_EXEC 2)
(define-public ET_DYN 3)
(define-public ET_CORE 4)

(define-field e_machine 18 2)
(define-public EM_65816 257)

(define-field e_version 20 4)
(define-public EV_CURRENT 1)

(define-field e_entry 24 4)
(define-field e_phoff 28 4)
(define-field e_shoff 32 4)

(define-field e_flags 36 4)
;; No flags are currently defined

(define-field e_ehsize 40 2)
(define-field e_phentsize 42 2)
(define-field e_phnum 44 2)
(define-field e_shentsize 46 2)
(define-field e_shnum 48 2)
(define-field e_shstrndx 50 2)

(define-public +sizeof-ehdr+ 52)

;; --------------------
;; Elf32_Phdr
;; --------------------

(define-field p_type 0 4)
(define	PT_NULL 0)
(define-public PT_LOAD 1)
(define-public PT_DYNAMIC 2)
(define-public PT_INTERP 3)
(define-public PT_NOTE 4)
(define-public PT_PHDR 6)
(define-public PT_TLS 7)

(define-field p_offset 4 4)
(define-field p_vaddr 8 4)
(define-field p_paddr 12 4)
(define-field p_filesz 16 4)
(define-field p_memsz 20 4)

(define-field p_flags 24 4)
(define-public PF_X #b001)
(define-public PF_W #b010)
(define-public PF_R #b100)

(define-field p_align 28 4)

(define-public +sizeof-phdr+ 32)

;; --------------------
;; Elf32_Shdr
;; --------------------

(define-public SHN_UNDEF 0)

(define-field sh_name 0 4) ;; Offset into shstrtab
(define-field sh_type 4 4)
(define-public SHT_NULL 0)
(define-public SHT_PROGBITS 1)
(define-public SHT_SYMTAB 2)
(define-public SHT_STRTAB 3)
(define-public SHT_RELA 4)
(define-public SHT_HASH 5)
(define-public SHT_DYNAMIC 6)
(define-public SHT_NOTE 7)
(define-public SHT_NOBITS 8)
(define-public SHT_REL 9)
(define-public SHT_SHLIB 10)
(define-public SHT_DYNSYM 11)
(define-public SHT_INIT_ARRAY 14)
(define-public SHT_FINI_ARRAY 15)
(define-public SHT_PREINIT_ARRAY 16)

(define-field sh_flags 8 4)
(define-public SHF_WRITE #b00000000001)
(define-public SHF_ALLOC #b00000000010)
(define-public SHF_EXECINSTR #b00000000100)
(define-public SHF_MERGE #b00000010000)
(define-public SHF_STRINGS #b00000100000)
(define-public SHF_INFO_LINK #b00001000000)
(define-public SHF_LINK_ORDER #b00010000000)
(define-public SHF_TLS #b10000000000)

(define-field sh_addr 12 4)
(define-field sh_offset 16 4)
(define-field sh_size 20 4)
(define-field sh_link 24 4)
(define-field sh_info 28 4)
(define-field sh_addralign 32 4)
(define-field sh_entsize 36 4)

(define-public +sizeof-shdr+ 40)

;; --------------------
;; Elf32_Sym
;; --------------------

(define-field st_name 0 4)
(define-field st_value 4 4)
(define-field st_size 8 4)

(define-field st_info 12 1)
(define-public (ELF32_ST_BIND val) (ash val -4))
(define-public STB_LOCAL 0)
(define-public STB_GLOBAL 1)
(define-public STB_WEAK 2)

(define-public (ELF32_ST_TYPE val) (logand val #x0f))
(define-public STT_NOTYPE 0)
(define-public STT_OBJECT 1)
(define-public STT_FUNC 2)
(define-public STT_SECTION 3)
(define-public STT_FILE 4)
(define-public STT_COMMON 5)
(define-public STT_TLS 6)

(define-public (ELF32_ST_INFO bind type) (logior (ash bind 4) (logand type #x0f)))

(define-field st_other 13 1)
(define-public (ELF32_ST_VISIBILITY val) (logior val #x03))
(define-public STV_DEFAULT 0)
(define-public STV_INTERNAL 1)
(define-public STV_HIDDEN 2)
(define-public STV_PROTECTED 3)

(define-field st_shndx 14 2)

(define-public +sizeof-sym+ 16)

;; -----------------------
;; Elf32_Rel & Elf32_Rela
;; -----------------------

(define-field r_offset 0 4)
(define-field r_info 4 4)
(define-public (ELF32_R_SYM val) (ash val -8))
(define-public (ELF32_R_TYPE val) (logand val #xff))
(define-public (ELF32_R_INFO sym type) (logior (ash sym 8) (logand type #xff)))

(define-field r_addend 8 4)

(define-public +sizeof-rel+ 8)
(define-public +sizeof-rela+ 12)

;; --------------------
;; Elf32_Dyn
;; --------------------

(define-field d_tag 0 4)
(define-public DT_NULL 0)
(define-public DT_NEEDED 1)
(define-public DT_PLTRELSZ 2)
(define-public DT_PLTGOT 3)
(define-public DT_HASH 4)
(define-public DT_STRTAB 5)
(define-public DT_SYMTAB 6)
(define-public DT_RELA 7)
(define-public DT_RELASZ 8)
(define-public DT_RELAENT 9)
(define-public DT_STRSZ 10)
(define-public DT_SYMENT 11)
(define-public DT_INIT 12)
(define-public DT_FINI 13)
(define-public DT_SONAME 14)
(define-public DT_RPATH 15)
(define-public DT_SYMBOLIC 16)
(define-public DT_REL 17)
(define-public DT_RELSZ 18)
(define-public DT_RELENT 19)
(define-public DT_PLTREL 20)
(define-public DT_DEBUG 21)
(define-public DT_TEXTREL 22)
(define-public DT_JMPREL 23)
(define-public DT_BIND_NOW 24)
(define-public DT_INIT_ARRAY 25)
(define-public DT_FINI_ARRAY 26)
(define-public DT_INIT_ARRAYSZ 27)
(define-public DT_FINI_ARRAYSZ 28)
(define-public DT_RUNPATH 29)
(define-public DT_FLAGS 30)
(define-public DT_ENCODING 32)
(define-public DT_PREINIT_ARRAY 32)
(define-public DT_PREINIT_ARRAYSZ 33)
(define-public DT_SYMTAB_SHNDX 34)
(define-public DT_FLAGS_1 #x6ffffffb)

;; d_un union members
(define-field d_un.d_val 4 4)
(define-field d_un.d_ptr 4 4)

;; Values of `d_un.d_val' in the DT_FLAGS entry.
(define-public DF_ORIGIN #x00000001)
(define-public DF_SYMBOLIC #x00000002)
(define-public DF_TEXTREL #x00000004)
(define-public DF_BIND_NOW #x00000008)
(define-public DF_STATIC_TLS #x00000010)

;; State flags selectable in the `d_un.d_val' element of the DT_FLAGS_1
;; entry in the dynamic section.
(define-public DF_1_NOW #x00000001)
(define-public DF_1_GLOBAL #x00000002)
(define-public DF_1_GROUP #x00000004)
(define-public DF_1_NODELETE #x00000008)
(define-public DF_1_LOADFLTR #x00000010)
(define-public DF_1_INITFIRST #x00000020)
(define-public DF_1_NOOPEN #x00000040)
(define-public DF_1_ORIGIN #x00000080)
(define-public DF_1_DIRECT #x00000100)
(define-public DF_1_TRANS #x00000200)
(define-public DF_1_INTERPOSE #x00000400)
(define-public DF_1_NODEFLIB #x00000800)
(define-public DF_1_NODUMP #x00001000)
(define-public DF_1_CONFALT #x00002000)
(define-public DF_1_ENDFILTEE #x00004000)
(define-public DF_1_DISPRELDNE #x00008000)
(define-public DF_1_DISPRELPND #x00010000)
(define-public DF_1_NODIRECT #x00020000)
(define-public DF_1_IGNMULDEF #x00040000)
(define-public DF_1_NOKSYMS #x00080000)
(define-public DF_1_NOHDR #x00100000)
(define-public DF_1_EDITED #x00200000)
(define-public DF_1_NORELOC #x00400000)
(define-public DF_1_SYMINTPOSE #x00800000)
(define-public DF_1_GLOBAUDIT #x01000000)
(define-public DF_1_SINGLETON #x02000000)
(define-public DF_1_STUB #x04000000)
(define-public DF_1_PIE #x08000000)
(define-public DF_1_KMOD #x10000000)
(define-public DF_1_WEAKFILTER #x20000000)
(define-public DF_1_NOCOMMON #x40000000)

(define-public +sizeof-dyn+ 8)

;; -----------------------------
;; W65C816-specific definitions
;; -----------------------------

;; ! These relocations deviate from those proposed by llvm-mos and SNES-Dev !
;; The main difference is that the direct page is treated as temporary storage,
;; or an extra register file of sorts, not backed by the executable, as such
;; there is no support for placing symbols in it, and there are no relocations
;; against it.

;; Perhaps in the future we'll want to allow for this, in case we want to use
;; the direct page as more than just a register file (for which we don't need
;; explicit symbols, as we can just use assembler defines), such that the linker
;; can merge direct page symbols from multiple files (and bail if the direct page
;; would be too large).

;; Maybe we could handle the direct page with PT_TLS? It has similar semantics
;; to TLS (is separate for each thread, technically is it's own address space
;; for the symbols placed in it).
;; Even currently every thread in the same address space needs it's own direct page
;; to be separate for each thread, even if we use it as a register file (unless we
;; use it as a global storage)...

(define-public R_W65C816_NONE 0)  ;; No relocation
(define-public R_W65C816_ABS24 1) ;; 24-bit absolute
(define-public R_W65C816_ABS16 2) ;; 16-bit absolute
(define-public R_W65C816_BANK 3)  ;; Uppermost 8 bits of a 24-bit address
(define-public R_W65C816_REL8 4)  ;; 8-bit relative
(define-public R_W65C816_REL16 5) ;; 16-bit relative
