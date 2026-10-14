; =============================================================================
;  lexer.asm - tokenizer
;  state: src_ptr, src_end, src_line, tk, tk_val, tk_ptr, tk_len, tk_line
; =============================================================================
section .rodata

kw_table:
    KW "int",      K_INT
    KW "char",     K_CHAR
    KW "byte",     K_CHAR
    KW "bool",     K_BOOL
    KW "void",     K_VOID
    KW "if",       K_IF
    KW "else",     K_ELSE
    KW "while",    K_WHILE
    KW "do",       K_DO
    KW "for",      K_FOR
    KW "break",    K_BREAK
    KW "continue", K_CONTINUE
    KW "return",   K_RETURN
    KW "struct",   K_STRUCT
    KW "class",    K_CLASS
    KW "enum",     K_ENUM
    KW "const",    K_CONST
    KW "public",   K_PUBLIC
    KW "private",  K_PRIVATE
    KW "import",   K_IMPORT
    KW "module",   K_MODULE
    KW "new",      K_NEW
    KW "this",     K_THIS
    KW "sizeof",   K_SIZEOF
    KW "true",     K_TRUE
    KW "false",    K_FALSE
    KW "null",     K_NULL
    KW "switch",   K_SWITCH
    KW "case",     K_CASE
    KW "default",  K_DEFAULT
    KW "typedef",  K_TYPEDEF
    KW "union",    K_UNION
    KW "static",   K_STATIC
    KW "virtual",  K_VIRTUAL
    KW "super",    K_SUPER
    KW "protected", K_PROTECTED
    KW "a_module", K_AMODULE
    KW "a_import", K_AIMPORT
    KW "asm",      K_ASM
    KW "double",   K_DOUBLE
    KW "float",    K_DOUBLE
    KW "defer",    K_DEFER
    KW "goto",     K_GOTO
    KW "extern",   K_EXTERN
    KW "short",    K_INTMOD
    KW "long",     K_INTMOD
    KW "signed",   K_INTMOD
    KW "unsigned", K_INTMOD
    db 0

ops3:
    db "<<=", T_SHLEQ
    db ">>=", T_SHREQ
    db 0
ops2:
    db "==", T_EQ
    db "!=", T_NE
    db "<=", T_LE
    db ">=", T_GE
    db "<<", T_SHL
    db ">>", T_SHR
    db "&&", T_ANDAND
    db "||", T_OROR
    db "++", T_INC
    db "--", T_DEC
    db "->", T_ARROW
    db "+=", T_ADDEQ
    db "-=", T_SUBEQ
    db "*=", T_MULEQ
    db "/=", T_DIVEQ
    db "%=", T_MODEQ
    db "&=", T_ANDEQ
    db "|=", T_OREQ
    db "^=", T_XOREQ
    db "::", T_SCOPE
    db 0
singles:
    db "(){}[];,.:?~=!<>&|^+-*/%", 0

section .text

; kw_lookup: rsi = ident, ecx = len -> eax = keyword token or T_ID
kw_lookup:
    push rbx
    push rdi
    push rdx
    push r8
    mov rbx, kw_table
.next:
    movzx edx, byte [rbx]
    test edx, edx
    jz .none
    cmp edx, ecx
    jne .skip
    xor r8d, r8d
.cmp:
    cmp r8d, ecx
    jae .hit
    mov al, [rbx+1+r8]
    cmp al, [rsi+r8]
    jne .skip
    inc r8d
    jmp .cmp
.hit:
    movzx eax, byte [rbx+1+rdx]
    jmp .out
.skip:
    lea rbx, [rbx+rdx+2]
    jmp .next
.none:
    mov eax, T_ID
.out:
    pop r8
    pop rdx
    pop rdi
    pop rbx
    ret

; match_ops: rsi = text, rdi = table, ecx = op length -> eax = token or 0
match_ops:
    push rdx
    push r8
.entry:
    cmp byte [rdi], 0
    je .none
    xor r8d, r8d
.c: cmp r8d, ecx
    jae .hit
    mov al, [rdi+r8]
    cmp al, [rsi+r8]
    jne .skip
    inc r8d
    jmp .c
.hit:
    movzx eax, byte [rdi+rcx]
    jmp .out
.skip:
    lea rdi, [rdi+rcx+1]
    jmp .entry
.none:
    xor eax, eax
.out:
    pop r8
    pop rdx
    ret

; hexval: al = char -> eax = value 0..15 or -1
hexval:
    movzx eax, al
    cmp al, '0'
    jb .no
    cmp al, '9'
    jbe .num
    or al, 0x20
    cmp al, 'a'
    jb .no
    cmp al, 'f'
    ja .no
    sub eax, 'a' - 10
    ret
.num:
    sub eax, '0'
    ret
.no:
    mov eax, -1
    ret

; lex_escape: rsi -> char after the backslash. Returns eax = decoded char,
; rsi advanced past the escape sequence.
lex_escape:
    movzx eax, byte [rsi]
    inc rsi
    cmp al, 'n'
    je .n
    cmp al, 't'
    je .t
    cmp al, 'r'
    je .r
    cmp al, '0'
    je .z
    cmp al, 'e'
    je .e
    cmp al, '\'
    je .ret
    cmp al, '"'
    je .ret
    cmp al, 0x27
    je .ret
    cmp al, 'x'
    je .x
    ERR "invalid escape sequence"
.n: mov eax, 10
    ret
.t: mov eax, 9
    ret
.r: mov eax, 13
    ret
.z: xor eax, eax
    ret
.e: mov eax, 27
    ret
.ret:
    ret
.x: movzx eax, byte [rsi]
    call hexval
    cmp eax, -1
    je .bad
    mov edx, eax
    movzx eax, byte [rsi+1]
    call hexval
    cmp eax, -1
    je .bad
    shl edx, 4
    or eax, edx
    add rsi, 2
    ret
.bad:
    ERR "invalid \\x escape"

; next_token: advances the lexer to the next token
next_token:
    cmp dword [fp_pending], 0
    jne .fpresume
    push rbx
    push r12
    mov rsi, [src_ptr]
.again:
    movzx eax, byte [rsi]
    cmp al, ' '
    je .adv
    cmp al, 9
    je .adv
    cmp al, 13
    je .adv
    cmp al, 10
    je .nl
    test al, al
    jz .eof
    cmp al, '/'
    jne .tok
    mov dl, [rsi+1]
    cmp dl, '/'
    je .line_cmt
    cmp dl, '*'
    je .blk_cmt
    jmp .tok
.adv:
    inc rsi
    jmp .again
.nl:
    inc qword [src_line]
    inc rsi
    jmp .again
.line_cmt:
    add rsi, 2
.lc:
    mov al, [rsi]
    test al, al
    jz .again
    cmp al, 10
    je .again
    inc rsi
    jmp .lc
.blk_cmt:
    add rsi, 2
.bc:
    mov al, [rsi]
    test al, al
    jz .bc_err
    cmp al, 10
    jne .bc2
    inc qword [src_line]
.bc2:
    cmp al, '*'
    jne .bc3
    cmp byte [rsi+1], '/'
    jne .bc3
    add rsi, 2
    jmp .again
.bc3:
    inc rsi
    jmp .bc
.bc_err:
    ERR "unterminated block comment"

.eof:
    mov [tk_start], rsi
    mov qword [tk], T_EOF
    mov rax, [src_line]
    mov [tk_line], rax
    mov [src_ptr], rsi
    jmp .done

.tok:
    mov rdx, [src_line]
    mov [tk_line], rdx
    mov [tk_start], rsi
    cmp al, '_'
    je .ident
    mov dl, al
    or dl, 0x20
    cmp dl, 'a'
    jb .notalpha
    cmp dl, 'z'
    jbe .ident
.notalpha:
    cmp al, '0'
    jb .notdigit
    cmp al, '9'
    jbe .number
.notdigit:
    cmp al, '"'
    je .string
    cmp al, 0x27
    je .char
    jmp .op

; ---- identifier / keyword
.ident:
    mov r12, rsi
.id1:
    inc rsi
    movzx eax, byte [rsi]
    cmp al, '_'
    je .id1
    cmp al, '0'
    jb .id2
    cmp al, '9'
    jbe .id1
.id2:
    mov dl, al
    or dl, 0x20
    cmp dl, 'a'
    jb .id3
    cmp dl, 'z'
    jbe .id1
.id3:
    mov rcx, rsi
    sub rcx, r12
    mov [tk_ptr], r12
    mov [tk_len], rcx
    mov [src_ptr], rsi
    mov rsi, r12
    call kw_lookup
    mov [tk], rax
    cmp eax, K_DOUBLE
    jne .done
    mov dword [need_float], 1           ; the soft-float runtime is compiled when a program uses double
    jmp .done

; ---- numbers
.number:
    xor r12, r12
    cmp al, '0'
    jne .dec
    mov dl, [rsi+1]
    or dl, 0x20
    cmp dl, 'x'
    je .hex
    cmp dl, 'b'
    je .bin
.dec:
    movzx eax, byte [rsi]
    cmp al, '_'
    je .decskip
    sub eax, '0'
    cmp eax, 9
    ja .decend
    imul r12, r12, 10
    add r12, rax
.decskip:
    inc rsi
    jmp .dec
.decend:
    ; a '.' followed by a digit, or an exponent, makes it a floating point literal
    mov al, [rsi]
    cmp al, '.'
    jne .dexp
    movzx eax, byte [rsi+1]
    sub eax, '0'
    cmp eax, 9
    jbe .isflt
    jmp .numdone
.dexp:
    or al, 0x20
    cmp al, 'e'
    jne .numdone
    movzx eax, byte [rsi+1]
    cmp al, '+'
    je .dexp2
    cmp al, '-'
    je .dexp2
    sub eax, '0'
    cmp eax, 9
    jbe .isflt
    jmp .numdone
.dexp2:
    movzx eax, byte [rsi+2]
    sub eax, '0'
    cmp eax, 9
    ja .numdone
.isflt:
    mov rsi, [tk_start]
    call lex_float
    mov qword [tk], T_FLT
    mov [tk_val], rax
    mov [src_ptr], rsi
    mov dword [need_float], 1
    jmp .done
.hex:
    add rsi, 2
    mov r8, rsi
.hx:
    mov al, [rsi]
    cmp al, '_'
    je .hxskip
    call hexval
    cmp eax, -1
    je .hxend
    shl r12, 4
    or r12, rax
.hxskip:
    inc rsi
    jmp .hx
.hxend:
    cmp rsi, r8
    jne .numdone
    ERR "hexadecimal literal has no digits"
.bin:
    add rsi, 2
    mov r8, rsi
.bn:
    movzx eax, byte [rsi]
    cmp al, '_'
    je .bnskip
    sub eax, '0'
    cmp eax, 1
    ja .bnend
    shl r12, 1
    or r12, rax
.bnskip:
    inc rsi
    jmp .bn
.bnend:
    cmp rsi, r8
    jne .numdone
    ERR "binary literal has no digits"
.numdone:
    mov qword [tk], T_NUM
    mov [tk_val], r12
    mov [src_ptr], rsi
    jmp .done

; ---- character literal
.char:
    cmp dword [sq_string], 0
    je .char0
    mov byte [str_term], 0x27           ; inside a_import( ... ) 'text' is a string
    jmp .string_go
.char0:
    inc rsi
    movzx eax, byte [rsi]
    test al, al
    jz .char_err
    inc rsi
    cmp al, '\'
    jne .ch1
    call lex_escape
.ch1:
    cmp byte [rsi], 0x27
    jne .char_err
    inc rsi
    mov qword [tk], T_NUM
    mov [tk_val], rax
    mov [src_ptr], rsi
    jmp .done
.char_err:
    ERR "malformed character literal"

; ---- string literal
.string:
    mov byte [str_term], '"'
.string_go:
    inc rsi
    mov rdi, strbuf
.s1:
    movzx eax, byte [rsi]
    test al, al
    jz .s_err
    cmp al, 10
    je .s_err
    cmp al, [str_term]
    je .s_end
    inc rsi
    cmp al, '\'
    jne .s_put
    call lex_escape
.s_put:
    cmp rdi, strbuf + 65000
    jae .s_err2
    mov [rdi], al
    inc rdi
    jmp .s1
.s_end:
    inc rsi
    cmp byte [str_term], '"'
    jne .s_fin
    ; "abc" "def" : adjacent string literals are one string
    push r8
    push rcx
    mov r8, rsi
    xor ecx, ecx
.sk:movzx eax, byte [r8]
    cmp al, ' '
    je .skn
    cmp al, 9
    je .skn
    cmp al, 13
    je .skn
    cmp al, 10
    jne .skd
    inc ecx
.skn:
    inc r8
    jmp .sk
.skd:
    cmp al, '"'
    jne .skno
    add [src_line], rcx
    lea rsi, [r8+1]
    pop rcx
    pop r8
    jmp .s1
.skno:
    pop rcx
    pop r8
.s_fin:
    mov byte [rdi], 0
    sub rdi, strbuf
    mov qword [tk], T_STR
    mov qword [tk_ptr], strbuf
    mov [tk_len], rdi
    mov [src_ptr], rsi
    jmp .done
.s_err:
    ERR "unterminated string literal"
.s_err2:
    ERR "string literal too long"

; ---- operators
.op:
    mov rdi, ops3
    mov ecx, 3
    call match_ops
    test eax, eax
    jz .op2
    add rsi, 3
    jmp .opok
.op2:
    mov rdi, ops2
    mov ecx, 2
    call match_ops
    test eax, eax
    jz .op1
    add rsi, 2
    jmp .opok
.op1:
    movzx eax, byte [rsi]
    mov rdi, singles
.sl:
    cmp byte [rdi], 0
    je .badchar
    cmp [rdi], al
    je .found
    inc rdi
    jmp .sl
.found:
    inc rsi
.opok:
    mov [tk], rax
    mov [src_ptr], rsi
    jmp .done
.badchar:
    ERR "unexpected character in source"

.done:
    pop r12
    pop rbx
    ret
.fpresume:
    mov dword [fp_pending], 0
    mov rsi, fp_after
    jmp lex_restore

; lex_save: rdi = 128 byte buffer. Saves the complete lexer + file state.
lex_save:
    mov rax, [src_ptr]
    mov [rdi], rax
    mov rax, [src_end]
    mov [rdi+8], rax
    mov rax, [src_line]
    mov [rdi+16], rax
    mov rax, [tk]
    mov [rdi+24], rax
    mov rax, [tk_val]
    mov [rdi+32], rax
    mov rax, [tk_ptr]
    mov [rdi+40], rax
    mov rax, [tk_len]
    mov [rdi+48], rax
    mov rax, [tk_line]
    mov [rdi+56], rax
    mov eax, [cur_file_id]
    mov [rdi+64], rax
    mov eax, [cur_module]
    mov [rdi+72], rax
    mov rax, [cur_file_name]
    mov [rdi+80], rax
    mov rax, [cur_src_base]
    mov [rdi+88], rax
    mov rax, [tk_start]
    mov [rdi+96], rax
    ret

; lex_restore: rsi = buffer written by lex_save
lex_restore:
    mov rax, [rsi]
    mov [src_ptr], rax
    mov rax, [rsi+8]
    mov [src_end], rax
    mov rax, [rsi+16]
    mov [src_line], rax
    mov rax, [rsi+24]
    mov [tk], rax
    mov rax, [rsi+32]
    mov [tk_val], rax
    mov rax, [rsi+40]
    mov [tk_ptr], rax
    mov rax, [rsi+48]
    mov [tk_len], rax
    mov rax, [rsi+56]
    mov [tk_line], rax
    mov rax, [rsi+64]
    mov [cur_file_id], eax
    mov rax, [rsi+72]
    mov [cur_module], eax
    mov rax, [rsi+80]
    mov [cur_file_name], rax
    mov rax, [rsi+88]
    mov [cur_src_base], rax
    mov rax, [rsi+96]
    mov [tk_start], rax
    ret

; expect: edi = token kind. Consumes it or reports an error
expect:
    cmp [tk], rdi
    jne .bad
    jmp next_token
.bad:
    cmp edi, 128
    jae .gen
    cmp edi, T_ID
    je .id
    cmp edi, 32
    jb .gen
    mov [expect_msg+10], dil
    mov edi, expect_msg
    jmp fatal_error
.id:
    ERR "expected an identifier"
.gen:
    ERR "unexpected token"

; accept: edi = token kind -> eax = 1 (consumed) or 0
accept:
    cmp [tk], rdi
    jne .no
    call next_token
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

section .data
expect_msg: db "expected 'X'", 0
section .text

; ---- floating point literals ----------------------------------------------------------------------------------------
; lex_float: rsi = start of a decimal literal  digits [. digits] [e [+-] digits]  ->  rax = the IEEE double bits, rsi = after it.
; The result is correctly rounded (to nearest, ties to even): short literals with a small exponent are converted exactly
; with double arithmetic; for everything else an x87 estimate is checked and corrected against the exact value, which is held
; in a big integer (all digits up to 800), so the answer is never off by an ulp.
lex_float:
    push rbx
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11
    push r12
    xor r8d, r8d                    ; mantissa (first 17 significant digits)
    xor r9d, r9d                    ; decimal exponent belonging to r8
    xor r10d, r10d                  ; significant digits in r8
    xor ebx, ebx                    ; 1 = a digit beyond the 17th was not zero
    mov qword [lf_dlen], 0          ; the exact digits as a big integer
    mov dword [lf_ex], 0            ; exponent belonging to the big integer
    xor r12d, r12d                  ; digits in the big integer
.i: movzx eax, byte [rsi]
    cmp al, '_'
    je .iskip
    sub eax, '0'
    cmp eax, 9
    ja .iend
    call .bigdigit
    cmp r10d, 17
    jae .idrop
    imul r8, r8, 10
    add r8, rax
    test r8, r8
    jz .iskip
    inc r10d
    jmp .iskip
.idrop:
    inc r9d                         ; an integer digit that does not fit: the value is 10 times bigger
    test eax, eax
    jz .iskip
    mov ebx, 1
.iskip:
    inc rsi
    jmp .i
.iend:
    cmp byte [rsi], '.'
    jne .exp
    movzx eax, byte [rsi+1]
    sub eax, '0'
    cmp eax, 9
    ja .exp
    inc rsi
.f: movzx eax, byte [rsi]
    cmp al, '_'
    je .fskip
    sub eax, '0'
    cmp eax, 9
    ja .exp
    call .bigdigit
    dec dword [lf_ex]
    cmp r10d, 17
    jae .fdrop
    imul r8, r8, 10
    add r8, rax
    dec r9d
    test r8, r8
    jz .fskip
    inc r10d
.fskip:
    inc rsi
    jmp .f
.fdrop:
    test eax, eax
    jz .fskip
    mov ebx, 1
    jmp .fskip
.exp:
    mov al, [rsi]
    or al, 0x20
    cmp al, 'e'
    jne .conv
    xor edx, edx                    ; exponent sign
    lea rcx, [rsi+1]
    movzx eax, byte [rcx]
    cmp al, '+'
    je .eplus
    cmp al, '-'
    jne .edig
    mov edx, 1
.eplus:
    inc rcx
.edig:
    movzx eax, byte [rcx]
    sub eax, '0'
    cmp eax, 9
    ja .conv                        ; not an exponent after all
    xor r11d, r11d
.ed:movzx eax, byte [rcx]
    sub eax, '0'
    cmp eax, 9
    ja .edone
    cmp r11d, 100000
    jae .eskip
    imul r11d, r11d, 10
    add r11d, eax
.eskip:
    inc rcx
    jmp .ed
.edone:
    mov rsi, rcx
    test edx, edx
    jz .epos
    neg r11d
.epos:
    add r9d, r11d
    add [lf_ex], r11d
.conv:
    test r8, r8
    jz .zero
    ; magnitude shortcuts: about 10^(digits + exponent)
    lea eax, [r10 + r9]
    cmp eax, 312
    jg .inf
    cmp eax, -330
    jl .zero
    ; exact fast path: mantissa below 2^53 with no dropped digits and a power of ten below 10^22
    test ebx, ebx
    jnz .slow
    mov rax, 0x20000000000000
    cmp r8, rax
    jae .slow
    cmp r9d, 22
    jg .slow
    cmp r9d, -22
    jl .slow
    cvtsi2sd xmm0, r8
    test r9d, r9d
    jz .fast_done
    js .fast_div
    mov eax, r9d
    mulsd xmm0, [lf_pow10 + rax*8]
    jmp .fast_done
.fast_div:
    mov eax, r9d
    neg eax
    divsd xmm0, [lf_pow10 + rax*8]
.fast_done:
    movq rax, xmm0
    jmp .out
.slow:
    ; an estimate with the x87 unit (extended precision): mantissa r8 (+ a sticky digit) times 10^r9
    test ebx, ebx
    jz .nostick
    imul r8, r8, 10
    inc r8
    dec r9d
.nostick:
    mov [lf_tmp], r8
    fild qword [lf_tmp]
    mov eax, r9d
    xor ecx, ecx
    test eax, eax
    jns .sabs
    neg eax
    mov ecx, 1
.sabs:
    cmp eax, 8000
    jbe .sloop0
    mov eax, 8000
.sloop0:
    xor edx, edx
.sloop:
    test eax, eax
    jz .sdone
    test al, 1
    jz .snext
    mov r11, rdx
    shl r11, 4
    fld tword [lf_pow10x + r11]
    test ecx, ecx
    jnz .sdiv
    fmulp st1, st0
    jmp .snext
.sdiv:
    fdivp st1, st0
.snext:
    shr eax, 1
    inc edx
    jmp .sloop
.sdone:
    fstp qword [lf_tmp]
    mov rax, [lf_tmp]
    call lf_correct                 ; exact check against the big integer: rax = candidate bits -> rax = correct bits
    jmp .out
.inf:
    mov rax, 0x7FF0000000000000
    jmp .out
.zero:
    xor eax, eax
.out:
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

; .bigdigit: eax = digit. D = D * 10 + digit (leading zeros are skipped, at most 800 digits are kept)
.bigdigit:
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    mov ecx, eax
    test r12d, r12d
    jnz .bd1
    test ecx, ecx
    jz .bdout                       ; a leading zero
.bd1:
    cmp r12d, 800
    jae .bdextra
    inc r12d
    mov rdi, lf_bnD
    mov rsi, lf_dlen
    mov edx, 10
    call bn_mul_small
    mov rdi, lf_bnD
    mov rsi, lf_dlen
    mov edx, ecx
    call bn_add_small
    jmp .bdout
.bdextra:
    inc dword [lf_ex]               ; an integer digit beyond 800: only its place value counts (a nonzero one makes the value bigger, which the sticky flag covers)
    test ecx, ecx
    jz .bdout
    ; keep the information that something nonzero follows: D*10+1 and exponent - 1 is not needed here; the estimate is exact enough
.bdout:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    ret

; ---- big integers (little endian dword limbs; the length is a qword in memory) ------------------------------------------
; bn_mul_small: rdi = limbs, rsi = &length, edx = multiplier (32 bit)
bn_mul_small:
    push rax
    push rcx
    push r8
    push r9
    mov edx, edx
    mov rcx, [rsi]
    xor r8d, r8d
    xor r9d, r9d
.l: cmp r9, rcx
    jae .d
    mov eax, [rdi + r9*4]
    imul rax, rdx
    add rax, r8
    mov [rdi + r9*4], eax
    shr rax, 32
    mov r8, rax
    inc r9
    jmp .l
.d: test r8, r8
    jz .o
    mov [rdi + rcx*4], r8d
    inc qword [rsi]
.o: pop r9
    pop r8
    pop rcx
    pop rax
    ret

; bn_add_small: rdi = limbs, rsi = &length, edx = value (32 bit)
bn_add_small:
    push rax
    push rcx
    push r9
    mov eax, edx
    mov rcx, [rsi]
    xor r9d, r9d
.l: cmp r9, rcx
    jae .app
    add [rdi + r9*4], eax
    jnc .o
    mov eax, 1
    inc r9
    jmp .l
.app:
    mov [rdi + rcx*4], eax
    inc qword [rsi]
.o: pop r9
    pop rcx
    pop rax
    ret

; bn_shl: rdi = limbs, rsi = &length, edx = bits to shift left
bn_shl:
    push rax
    push rcx
    push rdx
    push r8
    push r9
    push r10
    mov rcx, [rsi]
    test rcx, rcx
    jz .o
    mov r8d, edx
    shr r8d, 5                      ; whole limbs
    and edx, 31                     ; remaining bits
    ; first the bit shift, from the top: new top limb collects the bits that fall out
    test edx, edx
    jz .words
    mov r9, rcx                     ; i = length
    mov r10d, 32
    sub r10d, edx
    ; top limb: old[len-1] >> (32 - b)
    mov eax, [rdi + rcx*4 - 4]
    push rcx
    mov ecx, r10d
    shr eax, cl
    pop rcx
    mov [rdi + rcx*4], eax
    inc qword [rsi]
    mov r9, rcx
.sl:dec r9
    mov eax, [rdi + r9*4]
    push rcx
    mov ecx, edx
    shl eax, cl
    pop rcx
    test r9, r9
    jz .slz
    mov r11d, [rdi + r9*4 - 4]
    push rcx
    mov ecx, r10d
    shr r11d, cl
    pop rcx
    or eax, r11d
.slz:
    mov [rdi + r9*4], eax
    test r9, r9
    jnz .sl
    mov rcx, [rsi]
.words:
    test r8d, r8d
    jz .trim
    ; move limbs up by r8d words
    mov r9, rcx
.mv:dec r9
    mov eax, [rdi + r9*4]
    lea r10, [r9 + r8]
    mov [rdi + r10*4], eax
    test r9, r9
    jnz .mv
    xor r9d, r9d
.zf:cmp r9d, r8d
    jae .nl
    mov dword [rdi + r9*4], 0
    inc r9d
    jmp .zf
.nl:add rcx, r8
    mov [rsi], rcx
.trim:
    mov rcx, [rsi]
.tl:test rcx, rcx
    jz .td
    cmp dword [rdi + rcx*4 - 4], 0
    jne .td
    dec rcx
    jmp .tl
.td:mov [rsi], rcx
.o: pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rax
    ret

; bn_cmp: rdi = a, rsi = &lenA, rdx = b, rcx = &lenB -> eax = -1, 0, 1  (leading zero limbs are ignored)
bn_cmp:
    push r8
    push r9
    mov r8, [rsi]
.ta:test r8, r8
    jz .tb0
    cmp dword [rdi + r8*4 - 4], 0
    jne .tb0
    dec r8
    jmp .ta
.tb0:
    mov r9, [rcx]
.tb:test r9, r9
    jz .cmp
    cmp dword [rdx + r9*4 - 4], 0
    jne .cmp
    dec r9
    jmp .tb
.cmp:
    cmp r8, r9
    jb .less
    ja .more
.lp:test r8, r8
    jz .eq
    mov eax, [rdi + r8*4 - 4]
    cmp eax, [rdx + r8*4 - 4]
    jb .less
    ja .more
    dec r8
    jmp .lp
.eq:xor eax, eax
    jmp .o
.less:
    mov eax, -1
    jmp .o
.more:
    mov eax, 1
.o: pop r9
    pop r8
    ret

; bn_copy: rdi = destination limbs, rsi = source limbs, rdx = &length of the source, rcx = &length of the destination
bn_copy:
    push rax
    push r8
    mov r8, [rdx]
    mov [rcx], r8
    xor eax, eax
.l: cmp rax, r8
    jae .d
    mov r9d, [rsi + rax*4]
    mov [rdi + rax*4], r9d
    inc rax
    jmp .l
.d: pop r8
    pop rax
    ret

; bn_mul_pow10: rdi = limbs, rsi = &length, edx = n (the number is multiplied by 10^n)
bn_mul_pow10:
    push rax
    push rdx
    mov eax, edx
.l: cmp eax, 9
    jb .r
    mov edx, 1000000000
    call bn_mul_small
    sub eax, 9
    jmp .l
.r: test eax, eax
    jz .o
    mov edx, [lf_small10 + rax*4]
    call bn_mul_small
.o: pop rdx
    pop rax
    ret

; lf_compare: rax = X (up to 56 bits), ecx = p (signed) -> eax = sign of  (D * 10^lf_ex)  -  (X * 2^p)
lf_compare:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    mov r8d, ecx                    ; p
    ; A = D, B = X
    push rax
    mov rdi, lf_bnA
    mov rsi, lf_bnD
    mov rdx, lf_dlen
    mov rcx, lf_alen
    call bn_copy
    pop rax
    mov dword [lf_bnB], eax
    shr rax, 32
    mov dword [lf_bnB + 4], eax
    mov qword [lf_blen], 2
    ; powers of ten go to the side that needs them
    mov r9d, [lf_ex]
    test r9d, r9d
    js .neg10
    mov rdi, lf_bnA
    mov rsi, lf_alen
    mov edx, r9d
    call bn_mul_pow10
    jmp .pow2
.neg10:
    neg r9d
    mov rdi, lf_bnB
    mov rsi, lf_blen
    mov edx, r9d
    call bn_mul_pow10
.pow2:
    test r8d, r8d
    js .negp
    mov rdi, lf_bnB
    mov rsi, lf_blen
    mov edx, r8d
    call bn_shl
    jmp .cmp
.negp:
    neg r8d
    mov rdi, lf_bnA
    mov rsi, lf_alen
    mov edx, r8d
    call bn_shl
.cmp:
    mov rdi, lf_bnA
    mov rsi, lf_alen
    mov rdx, lf_bnB
    mov rcx, lf_blen
    call bn_cmp
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; lf_correct: rax = a candidate double (bits, non negative) -> rax = the double that is nearest to the exact value D * 10^lf_ex
lf_correct:
    push rbx
    push rcx
    push rdx
    push r12
    push r13
    push r14
    mov r12, rax                    ; candidate bits
    mov r14d, 8                     ; at most a few corrections
.again:
    dec r14d
    jz .done
    mov rax, 0x7FF0000000000000
    cmp r12, rax
    jae .toinf
    ; decompose: r13 = m, ebx = q
    mov rax, r12
    mov rdx, rax
    shr rdx, 52
    and edx, 0x7FF                  ; exponent field
    mov r13, 0xFFFFFFFFFFFFF
    and r13, rax                    ; fraction
    test edx, edx
    jnz .normal
    mov ebx, -1074
    jmp .dec_done
.normal:
    mov rcx, 0x10000000000000
    or r13, rcx
    lea ebx, [rdx - 1075]
.dec_done:
    ; upper midpoint (2m + 1) * 2^(q-1)
    lea rax, [r13*2 + 1]
    lea ecx, [rbx - 1]
    call lf_compare
    cmp eax, 0
    jg .up
    jl .checklow
    ; a tie: an even mantissa keeps the candidate
    test r13b, 1
    jz .done
    jmp .up
.up:
    inc r12
    jmp .again
.checklow:
    test r12, r12
    jz .done
    ; lower midpoint: (2m - 1) * 2^(q-1), or (4m - 1) * 2^(q-2) at a power of two (the spacing below is half)
    mov rcx, 0x10000000000000
    cmp r13, rcx
    jne .lowstd
    cmp r12, rcx
    jbe .lowstd                     ; the smallest normal number: neighbours are equally spaced
    lea rax, [r13*4 - 1]
    lea ecx, [rbx - 2]
    jmp .lowcmp
.lowstd:
    lea rax, [r13*2 - 1]
    lea ecx, [rbx - 1]
.lowcmp:
    call lf_compare
    cmp eax, 0
    jl .down
    jg .done
    test r13b, 1
    jz .done
.down:
    dec r12
    jmp .again
.toinf:
    ; the candidate is infinity: the value is only infinite when it reaches the midpoint (2^54 - 1) * 2^970
    mov rax, 0x3FFFFFFFFFFFFF
    mov ecx, 970
    call lf_compare
    test eax, eax
    jns .isinf
    mov r12, 0x7FEFFFFFFFFFFFFF
    jmp .done
.isinf:
    mov r12, 0x7FF0000000000000
.done:
    mov rax, r12
    pop r14
    pop r13
    pop r12
    pop rdx
    pop rcx
    pop rbx
    ret

section .rodata
align 8
lf_small10:
    dd 1, 10, 100, 1000, 10000, 100000, 1000000, 10000000, 100000000
lf_pow10:
    dq 1.0e0, 1.0e1, 1.0e2, 1.0e3, 1.0e4, 1.0e5, 1.0e6, 1.0e7, 1.0e8, 1.0e9, 1.0e10, 1.0e11
    dq 1.0e12, 1.0e13, 1.0e14, 1.0e15, 1.0e16, 1.0e17, 1.0e18, 1.0e19, 1.0e20, 1.0e21, 1.0e22
align 16
lf_pow10x:                          ; 10^1, 10^2, 10^4 ... 10^4096 in extended precision (16 bytes each)
    dt 1.0e1
    times 6 db 0
    dt 1.0e2
    times 6 db 0
    dt 1.0e4
    times 6 db 0
    dt 1.0e8
    times 6 db 0
    dt 1.0e16
    times 6 db 0
    dt 1.0e32
    times 6 db 0
    dt 1.0e64
    times 6 db 0
    dt 1.0e128
    times 6 db 0
    dt 1.0e256
    times 6 db 0
    dt 1.0e512
    times 6 db 0
    dt 1.0e1024
    times 6 db 0
    dt 1.0e2048
    times 6 db 0
    dt 1.0e4096
    times 6 db 0
section .text
