; =============================================================================
;  lexer.asm - tokenizer
;  state: src_ptr, src_end, src_line, tk, tk_val, tk_ptr, tk_len, tk_line
; =============================================================================
section .rodata

kw_table:
    KW "int",      K_INT
    KW "long",     K_INT
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
    mov qword [tk], T_EOF
    mov rax, [src_line]
    mov [tk_line], rax
    mov [src_ptr], rsi
    jmp .done

.tok:
    mov rdx, [src_line]
    mov [tk_line], rdx
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
    ja .numdone
    imul r12, r12, 10
    add r12, rax
.decskip:
    inc rsi
    jmp .dec
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
    inc rsi
    mov rdi, strbuf
.s1:
    movzx eax, byte [rsi]
    test al, al
    jz .s_err
    cmp al, 10
    je .s_err
    cmp al, '"'
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
