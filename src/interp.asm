; =============================================================================
;  interp.asm - string interpolation
;
;    $"x = {x}, pi = {pi:.3f}, name = {name:-10}|, hex = {n:#x}, braces {{ }}"
;
;  The lexer returns the whole literal as one token (T_ISTR, tk_ptr / tk_len = the raw text between the quotes). The parser
;  here lowers it to the library formatter, so both agree by construction:
;
;      __interp("x = %d, pi = %.3f, ...", x, pi, ...)       (lib/std.a: vformat twice, the second time into alloc(len + 1))
;
;  Text is copied (escape sequences are decoded, a % becomes %%), every  {expr}  or  {expr:spec}  becomes a conversion and its
;  value is pushed. The expression is parsed by the normal expression parser with the lexer put inside the literal
;  (src_ptr = the text after the brace), so it can be anything, including calls, member access and lambdas.
;  The spec is the text of a printf conversion without the leading %: flags - + space 0 #, a width, a precision, a length
;  (l h z ...) and, optionally, the conversion letter. Without a letter the type of the expression chooses one:
;      double -> v (shortest text that reads back)   bool -> true / false   char -> c   uint64 -> u   other integers -> d
;      char* -> s   other pointers and func -> p
;  An integer with e E f F g G v is converted to double first ({n:.2f}); a double needs one of those letters.
;  The result is a char* made by alloc: it lives until the program ends, like everything from `new` (see docs/LANGUAGE.md).
; =============================================================================
section .rodata
fn_interp:   db "__interp", 0
fn_boolstr:  db "__boolstr", 0
interp_convs: db "diuxXobcspeEfFgGv", 0
interp_flags: db "-+ #0123456789.lhzjtLq", 0
section .text

; frame of parse_interp
%define IF_RAW          0
%define IF_LEN          8
%define IF_FMT          16              ; data section offset of the format text
%define IF_MAX          24              ; size reserved for it
%define IF_SPEC         32
%define IF_SLEN         40
%define IF_LEX          48              ; 128 bytes: the lexer state after the literal
%define IF_BYTES        176

; interp_put: al = a character -> appended to the format text (r13 = position). A % is doubled. (preserves everything but rax, rcx, rdx)
%macro INTERP_PUT 0
    mov rdx, [rsp + IF_FMT]
    mov rcx, [rsp + IF_MAX]
    sub rcx, 4
    cmp r13, rcx
    jb %%ok
    ERR "internal error: the format text of an interpolated string is too long"
%%ok:
    mov [data_buf + rdx + r13], al
    inc r13
%endmacro

parse_interp:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, IF_BYTES
    STACKCHK
    cmp qword [cur_func], 0
    jne .infn
    ERR "an interpolated string can only be used inside a function"
.infn:
    mov rax, [tk_ptr]
    mov [rsp + IF_RAW], rax
    mov rax, [tk_len]
    mov [rsp + IF_LEN], rax
    lea rdi, [rsp + IF_LEX]
    call lex_save                       ; the position after the literal
    mov rax, [rsp + IF_LEN]
    lea rdi, [rax*2 + 16]
    mov [rsp + IF_MAX], rdi
    mov esi, 1
    call data_alloc                     ; room for the format text, filled in below
    mov [rsp + IF_FMT], rax
    mov edx, eax
    mov esi, R_DATA
    CG lea_global_a
    CG push_a                           ; the first argument of __interp
    xor ebx, ebx                        ; number of values
    xor r12d, r12d                      ; position in the raw text
    xor r13d, r13d                      ; position in the format text
.loop:
    cmp r12, [rsp + IF_LEN]
    jae .done
    mov rsi, [rsp + IF_RAW]
    movzx eax, byte [rsi + r12]
    cmp al, 0x5C
    je .esc
    cmp al, '{'
    je .brace
    cmp al, '}'
    je .rbrace
    cmp al, '%'
    je .pct
.lit:
    INTERP_PUT
    inc r12
    jmp .loop
.pct:
    mov al, '%'
    INTERP_PUT
    mov al, '%'
    INTERP_PUT
    inc r12
    jmp .loop
.esc:
    lea rsi, [rsi + r12 + 1]
    call lex_escape                     ; eax = the character, rsi after the sequence
    test eax, eax
    jnz .esc1
    ERR "a \\0 cannot be used in an interpolated string (it ends the format text)"
.esc1:
    mov rcx, rsi
    sub rcx, [rsp + IF_RAW]
    mov r12, rcx
    cmp al, '%'
    jne .esc2
    INTERP_PUT
.esc2:
    INTERP_PUT
    jmp .loop
.rbrace:
    cmp byte [rsi + r12 + 1], '}'
    je .rb2
    ERR "a single } in an interpolated string: write }} for a brace"
.rb2:
    mov al, '}'
    INTERP_PUT
    add r12, 2
    jmp .loop
.brace:
    cmp byte [rsi + r12 + 1], '{'
    jne .expr
    mov al, '{'
    INTERP_PUT
    add r12, 2
    jmp .loop
.expr:
    lea rax, [rsi + r12 + 1]
    mov [src_ptr], rax
    call next_token
    cmp qword [tk], '}'
    jne .e1
    ERR "an empty {} in an interpolated string"
.e1:
    call parse_assign
    call to_rvalue
    mov qword [rsp + IF_SLEN], 0
    cmp qword [tk], ':'
    je .spec
    cmp qword [tk], '}'
    je .conv
    ERR "expected } or : after the expression in an interpolated string"
.spec:
    mov rsi, [src_ptr]
    mov [rsp + IF_SPEC], rsi
.sp1:
    movzx eax, byte [rsi]
    cmp al, '}'
    je .sp2
    test eax, eax
    jz .sp3
    cmp al, '"'
    je .sp3
    inc rsi
    jmp .sp1
.sp3:
    ERR "the format after : in an interpolated string needs a closing }"
.sp2:
    mov rax, rsi
    sub rax, [rsp + IF_SPEC]
    mov [rsp + IF_SLEN], rax
    inc rsi
    mov [src_ptr], rsi
.conv:
    ; ---- the position after the closing brace
    mov rax, [src_ptr]
    sub rax, [rsp + IF_RAW]
    cmp rax, [rsp + IF_LEN]
    jbe .c0
    ERR "the } of an interpolated string is missing"
.c0:
    mov r12, rax
    ; ---- the conversion letter of the spec (0 when it has none) and the check of the other characters
    xor r14d, r14d                      ; the letter written by the programmer
    mov rcx, [rsp + IF_SLEN]
    mov r15, rcx                        ; length of the spec without the letter
    test rcx, rcx
    jz .c2
    mov rsi, [rsp + IF_SPEC]
    movzx eax, byte [rsi + rcx - 1]
    mov rdi, interp_convs
.c1:
    cmp byte [rdi], 0
    je .c2
    cmp [rdi], al
    je .c1a
    inc rdi
    jmp .c1
.c1a:
    mov r14d, eax
    dec r15
.c2:
    xor ecx, ecx
.c3:
    cmp rcx, r15
    jae .c5
    mov rsi, [rsp + IF_SPEC]
    movzx eax, byte [rsi + rcx]
    mov rdi, interp_flags
.c4:
    cmp byte [rdi], 0
    jne .c4a
    ERR "bad format in an interpolated string: after the colon come flags - + space 0 #, a width, .precision, l h z and a conversion letter"
.c4a:
    cmp [rdi], al
    je .c4b
    inc rdi
    jmp .c4
.c4b:
    inc rcx
    jmp .c3
.c5:
    ; ---- the type of the value decides the default letter and the conversions
    mov rax, [e_type]
    cmp rax, TY_DOUBLE
    je .tdouble
    test eax, 0xFF00
    jnz .tptr
    cmp al, TY_FUNC
    je .tfunc
    cmp al, TY_STRUCT
    je .tstruct
    cmp al, TY_VOID
    je .tvoid
    mov rdi, rax
    call is_intlike
    test eax, eax
    jnz .tint
    ERR "this value cannot be put into an interpolated string"
.tstruct:
    ERR "a struct, class or tuple cannot be put into an interpolated string: use its members"
.tvoid:
    ERR "a void value cannot be put into an interpolated string"
.tdouble:
    test r14d, r14d
    jnz .td1
    mov r14d, 'v'
    jmp .push
.td1:
    mov rdi, interp_floatconvs
    call interp_in
    test eax, eax
    jnz .push
    ERR "a double needs one of the letters e E f F g G v in an interpolated string"
.tint:
    mov rax, [e_type]
    test r14d, r14d
    jnz .ti1
    mov r14d, 'd'
    cmp rax, TY_CHAR
    jne .ti0
    mov r14d, 'c'
    jmp .push
.ti0:
    cmp rax, TY_U64
    jne .ti0b
    mov r14d, 'u'
    jmp .push
.ti0b:
    cmp rax, TY_BOOL
    jne .push
    ; bool: the text true / false
    mov rdi, fn_boolstr
    call call_rt1
    mov r14d, 's'
    jmp .push
.ti1:
    mov rdi, interp_floatconvs
    call interp_in
    test eax, eax
    jz .ti2
    mov edi, TY_DOUBLE
    call coerce_to                      ; an integer with %f: converted to double
    jmp .push
.ti2:
    cmp r14d, 's'
    je .tibad
    cmp r14d, 'p'
    jne .push
.tibad:
    ERR "an integer cannot be formatted with s or p in an interpolated string: it is not text"
.tfunc:
.tptr:
    test r14d, r14d
    jnz .tp1
    mov r14d, 'p'
    cmp qword [e_type], TY_CHAR | TY_PTR1
    jne .push
    mov r14d, 's'
    jmp .push
.tp1:
    mov rdi, interp_ptrconvs
    call interp_in
    test eax, eax
    jnz .push
    ERR "a pointer or text needs one of the letters s p x X d u in an interpolated string"
.push:
    CG push_a
    inc ebx
    ; ---- % spec letter
    mov al, '%'
    INTERP_PUT
    xor ebp, ebp
.s1:
    cmp rbp, r15
    jae .s2
    mov rsi, [rsp + IF_SPEC]
    movzx eax, byte [rsi + rbp]
    INTERP_PUT                          ; (it clobbers rcx and rdx, and addresses the frame through rsp: no push here)
    inc rbp
    jmp .s1
.s2:
    mov eax, r14d
    INTERP_PUT
    jmp .loop
.done:
    xor eax, eax
    INTERP_PUT
    mov edi, ebx
    CG imm_a
    CG push_a                           ; the number of values
    mov rdi, fn_interp
    call emit_call_named
    lea edi, [rbx + 2]
    CG drop
    lea rsi, [rsp + IF_LEX]
    call lex_restore
    call next_token                     ; past the literal
    mov qword [e_type], TY_CHAR | TY_PTR1
    mov qword [e_lval], 0
    add rsp, IF_BYTES
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
interp_floatconvs: db "eEfFgGv", 0
interp_ptrconvs:   db "spxXdu", 0
section .text

; interp_in: rdi = a string of letters, r14d = a letter -> eax = 1 when the letter is in the string
interp_in:
.l: cmp byte [rdi], 0
    je .no
    cmp [rdi], r14b
    je .yes
    inc rdi
    jmp .l
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret
