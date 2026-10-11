; =============================================================================
;  A language compiler  -  shared definitions and macros
;  (c) Aytict - https://aytict.fi
; =============================================================================
%ifndef DEFS_INC
%define DEFS_INC

%define VERSION_NAME    "0.1.0"
%define VERSION_CODE    1

; ---- Linux syscalls used by the compiler itself ------------------------------
%define SYS_READ        0
%define SYS_WRITE       1
%define SYS_OPEN        2
%define SYS_CLOSE       3
%define SYS_FCHMOD      91
%define SYS_EXIT_GROUP  231

; ---- sizes of the compiler's static buffers (bss, costs no file size) --------
%define CODE_MAX        (16*1024*1024)
%define DATA_MAX        (8*1024*1024)
%define BSS_LIMIT       (512*1024*1024)   ; max bss of a compiled program
%define REL_MAX         262144
%define SYM_MAX         65536
%define FIELD_MAX       32768
%define STRUCT_MAX      4096
%define PTYPE_MAX       131072
%define ARENA_MAX       (32*1024*1024)
%define OUT_MAX         (32*1024*1024)
%define NAMEPOOL_MAX    (1024*1024)
%define FILE_MAX        256
%define MAXLOOP         64
%define MAXPARAM        64

; ---- targets ------------------------------------------------------------------
%define TGT_LINUX       0
%define TGT_WINDOWS     1
%define TGT_ANDROID     2

; ---- token kinds -------------------------------------------------------------
; single character tokens use their ASCII code
%define T_EOF           0
%define T_ID            1
%define T_NUM           2
%define T_STR           3
%define T_EQ            128     ; ==
%define T_NE            129     ; !=
%define T_LE            130     ; <=
%define T_GE            131     ; >=
%define T_SHL           132     ; <<
%define T_SHR           133     ; >>
%define T_ANDAND        134     ; &&
%define T_OROR          135     ; ||
%define T_INC           136     ; ++
%define T_DEC           137     ; --
%define T_ARROW         138     ; ->
%define T_ADDEQ         139     ; +=
%define T_SUBEQ         140
%define T_MULEQ         141
%define T_DIVEQ         142
%define T_MODEQ         143
%define T_ANDEQ         144
%define T_OREQ          145
%define T_XOREQ         146
%define T_SHLEQ         147
%define T_SHREQ         148
; keywords
%define K_INT           160
%define K_CHAR          161
%define K_BOOL          162
%define K_VOID          163
%define K_IF            164
%define K_ELSE          165
%define K_WHILE         166
%define K_DO            167
%define K_FOR           168
%define K_BREAK         169
%define K_CONTINUE      170
%define K_RETURN        171
%define K_STRUCT        172
%define K_CLASS         173
%define K_ENUM          174
%define K_CONST         175
%define K_PUBLIC        176
%define K_PRIVATE       177
%define K_IMPORT        178
%define K_MODULE        179
%define K_NEW           180
%define K_THIS          181
%define K_SIZEOF        182
%define K_TRUE          183
%define K_FALSE         184
%define K_NULL          185
%define K_SWITCH        186
%define K_CASE          187
%define K_DEFAULT       188

; ---- symbol kinds ------------------------------------------------------------
%define S_LOCAL         1
%define S_GLOBAL        2
%define S_CONST         3
%define S_FUNC          4
%define S_STRUCT        5
%define S_ENUM          6
%define S_MODULE        7

; ---- symbol entry layout (64 bytes) ------------------------------------------
%define SYM_NAME        0       ; qword  pointer to name
%define SYM_NLEN        8       ; dword
%define SYM_KIND        12      ; dword
%define SYM_TYPE        16      ; qword  type (var type / return type / const type)
%define SYM_VAL         24      ; qword  local: rbp offset, global: section offset,
                                ;        const: value, func: code offset (-1 = undefined),
                                ;        struct: struct index, module: module id
%define SYM_FLAGS       32      ; dword
%define SYM_MOD         36      ; dword  module id the symbol belongs to
%define SYM_EXTRA       40      ; qword  func: ptr to param types, global: array count
%define SYM_OWNER       48      ; dword  struct index (methods) / enum symbol index (-1 = none)
%define SYM_FILE        52      ; dword  file id (for private)
%define SYM_NPAR        56      ; dword  number of declared params (without 'this')
%define SYM_PATCH       60      ; dword  head of forward-call patch chain
%define SYM_SIZE        64

%define F_PRIVATE       1
%define F_METHOD        2
%define F_DEFINED       4
%define F_BSS           8
%define F_CTOR          16
%define F_STRCONST      32
%define F_BUILTIN       64
%define F_ENUMVAL       128

; ---- struct table entry (32 bytes) -------------------------------------------
%define ST_NAME         0       ; qword
%define ST_NLEN         8       ; dword
%define ST_FIRST        12      ; dword first field index
%define ST_NFIELDS      16      ; dword
%define ST_SIZE         20      ; dword
%define ST_ISCLASS      24      ; dword
%define ST_SYM          28      ; dword  symbol index
%define ST_SIZEOF       32

; ---- field entry (32 bytes) --------------------------------------------------
%define FD_NAME         0       ; qword
%define FD_NLEN         8       ; dword
%define FD_VIS          12      ; dword 1 = private
%define FD_TYPE         16      ; qword
%define FD_OFFSET       24      ; dword
%define FD_SIZEOF       32

; ---- types -------------------------------------------------------------------
; bits 0-7 kind, bits 8-15 pointer depth, bits 16-31 struct index, bit 32 array
%define TY_VOID         0
%define TY_INT          1
%define TY_CHAR         2
%define TY_BOOL         3
%define TY_STRUCT       4
%define TY_PTR1         0x100
%define TF_ARRAY_BIT    32

; ---- relocations (code/data references that need final addresses) ------------
%define R_DATA          0       ; rel32 in code -> data + target
%define R_BSS           1       ; rel32 in code -> bss  + target
%define R_IAT           2       ; rel32 in code -> import slot target
%define R_DATA64        3       ; abs64 in data -> data + target
%define R_CODE32        4       ; rel32 in code -> code + target (unused)

; =============================================================================
;  macros
; =============================================================================

; emit raw machine code bytes into the output code buffer
%macro EM 1+
    [section .rodata]
%%b:    db %1
%%e:
    __SECT__
    push rsi
    push rcx
    mov esi, %%b
    mov ecx, %%e - %%b
    call emit_bytes
    pop rcx
    pop rsi
%endmacro

; fatal compile error with a constant message
%macro ERR 1
    [section .rodata]
%%s:    db %1, 0
    __SECT__
    mov edi, %%s
    jmp fatal_error
%endmacro

; constant string in .rodata, label returned in %1
%macro CSTR 2
    [section .rodata]
%1:     db %2, 0
    __SECT__
%endmacro

; keyword table entry: length, text, token id
%macro KW 2
        db %%e - %%s
%%s:    db %1
%%e:    db %2
%endmacro

; Windows import call inside a builtin blob: call [rip+iat slot %1]
%macro IATCALL 1
        db 0xFF, 0x15
%%d:    dd 0
    [section .iatfix]
        dq %%d
        dd %1
        dd 0
    __SECT__
%endmacro

; guard against runaway recursion in the compiler itself (deeply nested source)
%macro STACKCHK 0
    cmp rsp, [stack_limit]
    jb err_nested
%endmacro

; =============================================================================
;  code generator backend interface
;  The parser emits code only through these primitives. Abstract machine:
;    A = accumulator (rax / x0), B = secondary (rcx / x1), D = temp (rdx / x2),
;    a downward growing stack of one-slot values (push/pop).
;  Every primitive preserves all compiler registers (rax..r15) unless stated.
; =============================================================================
%macro CGLIST 1
    %1 push_a              ; push A
    %1 push_b              ; push B
    %1 pop_a               ; pop into A
    %1 pop_b               ; pop into B
    %1 drop                ; edi = number of stack slots to discard
    %1 mov_b_a             ; B = A
    %1 mov_a_b             ; A = B
    %1 mov_d_a             ; D = A
    %1 mov_a_d             ; A = D
    %1 imm_a               ; rdi = value -> A
    %1 imm_b               ; rdi = value -> B
    %1 lea_local_a         ; edi = frame offset -> A = &local
    %1 lea_local_b         ; edi = frame offset -> B = &local
    %1 load_local_a        ; edi = frame offset -> A = *(qword*)&local
    %1 store_local_a       ; edi = frame offset -> *(qword*)&local = A
    %1 load_local_a1       ; edi = frame offset -> A = *(byte*)&local (zero extended)
    %1 load_local_b        ; edi = frame offset -> B = *(qword*)&local
    %1 load_local_b1       ; edi = frame offset -> B = *(byte*)&local (zero extended)
    %1 store_local_a1      ; edi = frame offset -> *(byte*)&local = A
    %1 zero_local          ; edi = frame offset, esi = size: clears a local (clobbers A)
    %1 lea_global_a        ; esi = R_DATA/R_BSS, edx = target -> A = address
    %1 load8_a             ; A = *(qword*)A
    %1 load1_a             ; A = *(byte*)A (zero extended)
    %1 store8              ; *(qword*)B = A
    %1 store1              ; *(byte*)B = A
    %1 copy_mem            ; edi = size: copy A -> B, result A = B
    %1 add_imm_a           ; edi = signed 32 bit immediate: A += imm
    %1 mul_imm_a           ; edi = imm: A *= imm
    %1 mul_imm_b           ; edi = imm: B *= imm
    %1 add                 ; A = A + B
    %1 sub
    %1 mul
    %1 div
    %1 mod
    %1 and
    %1 or
    %1 xor
    %1 shl
    %1 sar
    %1 cmp_eq              ; A = (A == B)
    %1 cmp_ne
    %1 cmp_lt
    %1 cmp_gt
    %1 cmp_le
    %1 cmp_ge
    %1 neg
    %1 not
    %1 lnot
    %1 zext8
    %1 tobool
    %1 jz_chain            ; rdi = &chain head: jump if A == 0
    %1 jnz_chain
    %1 jmp_chain
    %1 jcmp_chain          ; edi = condition (CC_*), rdi.. see below: compares A with B and
                           ;   jumps to the chain at [rsi] when  A cc B  holds
    %1 jmp_back            ; rdi = target code position
    %1 jnz_back            ; rdi = target: jump if A != 0
    %1 case_jump           ; edi = frame offset, rsi = value, rdx = target: if local == value jump
    %1 patch_chain         ; rdi = chain head, rsi = target position
    %1 call_sym            ; rdi = function symbol
    %1 prologue            ; function entry; records the frame size patch position
    %1 epilogue            ; return to the caller
    %1 set_frame           ; edi = frame size in bytes (multiple of 16)
    %1 entry_args          ; edi = number of main() parameters (0..2): pushes argc/argv
%endmacro

%assign CGI_COUNT 0
%macro CGI_DEF 1
    %assign CGI_%1 CGI_COUNT
    %assign CGI_COUNT CGI_COUNT+1
%endmacro
CGLIST CGI_DEF

; call a backend primitive
%macro CG 1
    call [cg_vt + CGI_%1 * 8]
%endmacro

; comparison condition codes used by jcmp_chain
%define CC_EQ           0
%define CC_NE           1
%define CC_LT           2
%define CC_GT           3
%define CC_LE           4
%define CC_GE           5

; ---- targets / architectures ---------------------------------------------------
%define ARCH_X64        0
%define ARCH_A64        1

; Windows builtin blob: lea r10,[rip + start of the import address table]
%macro IATLEA 0
        db 0x4C, 0x8D, 0x15
%%d:    dd 0
    [section .iatfix]
        dq %%d
        dd 0
        dd 0
    __SECT__
%endmacro

%endif
