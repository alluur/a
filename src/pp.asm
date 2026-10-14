; =============================================================================
;  The preprocessor
;
;  Runs once on every source file that is read from disk (the built-in library modules do not need it).
;  Supported:  #define NAME body        #define NAME(a, b, ...) body     (# stringify, ## paste, __VA_ARGS__)
;              #undef   #include "file" / <file>   #pragma once   #error   #warning
;              #if #ifdef #ifndef #elif #else #endif       (defined(X), arithmetic, comparisons, && || ! ...)
;  Predefined: __A__  __ARCH__  __OS__  __FILE__  __LINE__      and -DNAME[=value] on the command line.
;  Comments are removed. The output has the same number of lines as the input; an #include is inserted
;  on the line of the directive (its lines are joined), so error messages keep the right line numbers.
; =============================================================================

%define PP_OUT_SIZE     (8*1024*1024)
%define PP_SCR_SIZE     (4*1024*1024)
%define PP_POOL_SIZE    (512*1024)
%define PP_LBUF_SIZE    (256*1024)
%define PP_MAXMAC       768
%define PP_MSIZE        64
%define PP_MAXARGS      16
%define PP_MAXCOND      64

; macro entry
%define M_NAME          0       ; qword  pointer (0 = free)
%define M_NLEN          8       ; dword
%define M_KIND          12      ; dword  0 object like, 1 function like
%define M_NPAR          16      ; dword
%define M_VARIADIC      20      ; dword
%define M_PARAMS        24      ; qword  array of (ptr, len) qword pairs
%define M_BODY          32      ; qword
%define M_BLEN          40      ; qword
%define M_OFF           48      ; dword  1 while it is being expanded

section .text

; ---- errors ---------------------------------------------------------------------------------------------------------------
; pp_error: rdi = message
pp_error:
    mov rax, [pp_line]
    mov [tk_line], rax
    mov rax, [pp_curfile]
    mov [cur_file_name], rax
    mov rax, [pp_srcbase]
    mov [cur_src_base], rax
    jmp fatal_error

%macro PPERR 1
    [section .rodata]
%%s:    db %1, 0
    __SECT__
    mov edi, %%s
    jmp pp_error
%endmacro

; ---- output helpers --------------------------------------------------------------------------------------------------------
; pp_putc: al = byte (preserves everything but flags)
pp_putc:
    push rdx
    mov rdx, [pp_op]
    cmp rdx, pp_mem + PP_OUT_SIZE + PP_SCR_SIZE - 8
    jae .full
    mov [rdx], al
    inc rdx
    mov [pp_op], rdx
    pop rdx
    ret
.full:
    PPERR "preprocessor output too large"

; pp_write: rsi = bytes, rcx = count (preserves everything but flags, rsi, rcx)
pp_write:
    push rdi
    push rax
    mov rdi, [pp_op]
    lea rax, [rdi + rcx]
    cmp rax, pp_mem + PP_OUT_SIZE + PP_SCR_SIZE - 8
    jae pp_putc.full
    rep movsb
    mov [pp_op], rdi
    pop rax
    pop rdi
    ret

; pp_isid: al = byte -> ZF clear (nonzero eax) when it is a letter, digit or '_'
pp_isid:
    cmp al, '_'
    je .y
    cmp al, '0'
    jb .n
    cmp al, '9'
    jbe .y
    cmp al, 'A'
    jb .n
    cmp al, 'Z'
    jbe .y
    cmp al, 'a'
    jb .n
    cmp al, 'z'
    jbe .y
.n: xor eax, eax
    ret
.y: mov eax, 1
    ret

; pp_isidstart: al = byte -> eax = 1 for a letter or '_'
pp_isidstart:
    cmp al, '_'
    je pp_isid.y
    cmp al, 'A'
    jb pp_isid.n
    cmp al, 'Z'
    jbe pp_isid.y
    cmp al, 'a'
    jb pp_isid.n
    cmp al, 'z'
    jbe pp_isid.y
    jmp pp_isid.n

; pp_scratch_base: -> rax = a 16 byte aligned address above everything that is in use in the scratch area
pp_scratch_base:
    mov rax, [pp_sp]
    mov rdx, [pp_op]
    cmp rdx, rax
    jbe .a
    mov rax, rdx
.a: add rax, 31
    and rax, -16
    ret

; ---- macros -------------------------------------------------------------------------------------------------------------------
; pp_find: rsi = name, ecx = length -> rax = macro entry or 0
pp_find:
    push rbx
    push rdi
    push r8
    mov ebx, [pp_mcount]
.l: test ebx, ebx
    jz .none
    dec ebx
    mov rax, rbx
    shl rax, 6
    add rax, pp_mtab
    cmp qword [rax+M_NAME], 0
    je .l
    cmp [rax+M_NLEN], ecx
    jne .l
    mov rdi, [rax+M_NAME]
    push rsi
    push rcx
    repe cmpsb
    pop rcx
    pop rsi
    jne .l
    jmp .out
.none:
    xor eax, eax
.out:
    pop r8
    pop rdi
    pop rbx
    ret

; pp_pool_copy: rsi = bytes, rcx = length -> rax = copy in the pool (NUL terminated)
pp_pool_copy:
    push rdi
    mov rax, [pp_poolpos]
    lea rdx, [rax + rcx + 1]
    cmp rdx, PP_POOL_SIZE
    jb .ok
    PPERR "too many macros (pool is full)"
.ok:
    mov [pp_poolpos], rdx
    add rax, pp_pool
    mov rdi, rax
    push rax
    rep movsb
    mov byte [rdi], 0
    pop rax
    pop rdi
    ret

; pp_skipws: rsi -> rsi after spaces and tabs
pp_skipws:
.l: mov al, [rsi]
    cmp al, ' '
    je .n
    cmp al, 9
    je .n
    ret
.n: inc rsi
    jmp .l

; pp_ident: rsi = text -> rcx = identifier length (0 if there is none)
pp_ident:
    xor ecx, ecx
    mov al, [rsi]
    call pp_isidstart
    test eax, eax
    jz .r
.l: inc ecx
    mov al, [rsi+rcx]
    call pp_isid
    test eax, eax
    jnz .l
.r: ret

; pp_do_define: rsi = text after "define" (NUL terminated line)
pp_do_define:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call pp_skipws
    call pp_ident
    test ecx, ecx
    jnz .name
    PPERR "expected a macro name after #define"
.name:
    mov r12, rsi                        ; name
    mov r13d, ecx
    add rsi, rcx
    mov r14, rsi
    ; an existing macro of that name is replaced
    mov rsi, r12
    mov ecx, r13d
    call pp_find
    test rax, rax
    jnz .have
    mov eax, [pp_mcount]
    cmp eax, PP_MAXMAC
    jb .room
    PPERR "too many macros"
.room:
    inc dword [pp_mcount]
    shl rax, 6
    add rax, pp_mtab
.have:
    mov rbx, rax
    mov rsi, r12
    mov ecx, r13d
    call pp_pool_copy
    mov [rbx+M_NAME], rax
    mov [rbx+M_NLEN], r13d
    mov dword [rbx+M_KIND], 0
    mov dword [rbx+M_NPAR], 0
    mov dword [rbx+M_VARIADIC], 0
    mov dword [rbx+M_OFF], 0
    mov qword [rbx+M_PARAMS], 0
    mov rsi, r14
    cmp byte [rsi], '('
    jne .body
    ; function like macro: parameter list
    mov dword [rbx+M_KIND], 1
    inc rsi
    ; the parameter array lives in the pool: 16 bytes per parameter
    mov rax, [pp_poolpos]
    add rax, 15
    and rax, -16
    lea rdx, [rax + PP_MAXARGS*16]
    cmp rdx, PP_POOL_SIZE
    jb .pok
    PPERR "too many macros (pool is full)"
.pok:
    mov [pp_poolpos], rdx
    add rax, pp_pool
    mov [rbx+M_PARAMS], rax
    mov r15, rax
    xor r12d, r12d                      ; parameter count
.par:
    call pp_skipws
    cmp byte [rsi], ')'
    je .pend
    cmp byte [rsi], '.'
    jne .pname
    cmp byte [rsi+1], '.'
    jne .pname
    cmp byte [rsi+2], '.'
    jne .pname
    add rsi, 3
    mov dword [rbx+M_VARIADIC], 1
    call pp_skipws
    cmp byte [rsi], ')'
    je .pend
    PPERR "'...' must be the last macro parameter"
.pname:
    call pp_ident
    test ecx, ecx
    jnz .pn1
    PPERR "expected a parameter name"
.pn1:
    cmp r12d, PP_MAXARGS
    jb .pn2
    PPERR "too many macro parameters"
.pn2:
    push rsi
    push rcx
    call pp_pool_copy
    pop rcx
    pop rsi
    mov rdx, r12
    shl rdx, 4
    mov [r15+rdx], rax
    mov [r15+rdx+8], rcx
    inc r12d
    add rsi, rcx
    call pp_skipws
    cmp byte [rsi], ','
    jne .par2
    inc rsi
    jmp .par
.par2:
    cmp byte [rsi], ')'
    je .pend
    PPERR "expected ',' or ')' in the macro parameter list"
.pend:
    inc rsi
    mov [rbx+M_NPAR], r12d
.body:
    call pp_skipws
    ; trim trailing white space
    mov rdi, rsi
.te:cmp byte [rdi], 0
    je .te2
    inc rdi
    jmp .te
.te2:
    cmp rdi, rsi
    jbe .tdone
    mov al, [rdi-1]
    cmp al, ' '
    je .tt
    cmp al, 9
    je .tt
    cmp al, 13
    jne .tdone
.tt:dec rdi
    jmp .te2
.tdone:
    mov rcx, rdi
    sub rcx, rsi
    mov [rbx+M_BLEN], rcx
    call pp_pool_copy
    mov [rbx+M_BODY], rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; pp_do_undef: rsi = text after "undef"
pp_do_undef:
    call pp_skipws
    call pp_ident
    test ecx, ecx
    jz .r
    call pp_find
    test rax, rax
    jz .r
    mov qword [rax+M_NAME], 0
.r: ret

; ---- expansion ----------------------------------------------------------------------------------------------------------
; pp_utoa: rax = value -> writes the decimal digits with pp_putc
pp_utoa:
    push rbx
    push rcx
    push rdx
    sub rsp, 32
    mov rbx, 10
    lea rcx, [rsp+31]
    mov byte [rcx], 0
.l: xor edx, edx
    div rbx
    add dl, '0'
    dec rcx
    mov [rcx], dl
    test rax, rax
    jnz .l
.w: mov al, [rcx]
    test al, al
    jz .d
    call pp_putc
    inc rcx
    jmp .w
.d: add rsp, 32
    pop rdx
    pop rcx
    pop rbx
    ret

; pp_expand: rsi = text, rcx = length. The expansion is appended to the output (pp_op).
; Returns eax = 1 when a macro call ran off the end of the text (only at the outermost level: more lines are needed).
pp_expand:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov r12, rsi
    lea r13, [rsi + rcx]
    inc dword [pp_depth]
    cmp dword [pp_depth], 64
    jbe .loop
    PPERR "macro expansion is nested too deeply"
.loop:
    cmp r12, r13
    jae .done0
    movzx eax, byte [r12]
    cmp al, '"'
    je .lit
    cmp al, 0x27
    je .lit
    cmp al, '0'
    jb .nonum
    cmp al, '9'
    jbe .num
.nonum:
    call pp_isidstart
    test eax, eax
    jnz .ident
    mov al, [r12]
    call pp_putc
    inc r12
    jmp .loop
.lit:
    mov bl, [r12]
    mov al, bl
    call pp_putc
    inc r12
.lit1:
    cmp r12, r13
    jae .loop
    mov al, [r12]
    call pp_putc
    inc r12
    cmp al, '\'
    jne .lit2
    cmp r12, r13
    jae .loop
    mov al, [r12]
    call pp_putc
    inc r12
    jmp .lit1
.lit2:
    cmp al, bl
    jne .lit1
    jmp .loop
.num:
    mov al, [r12]
    call pp_putc
    inc r12
    cmp r12, r13
    jae .loop
    mov al, [r12]
    cmp al, '.'
    je .num
    call pp_isid
    test eax, eax
    jnz .num
    jmp .loop

.ident:
    mov r14, r12                        ; start of the name
.id1:
    inc r12
    cmp r12, r13
    jae .id2
    mov al, [r12]
    call pp_isid
    test eax, eax
    jnz .id1
.id2:
    mov r15, r12
    sub r15, r14                        ; length
    ; __LINE__ and __FILE__
    cmp r15, 8
    jne .notline
    mov rsi, r14
    mov rdi, s_pp_line
    mov ecx, 8
    repe cmpsb
    jne .notline
    mov rax, [pp_line]
    call pp_utoa
    jmp .loop
.notline:
    cmp r15, 8
    jne .notfile
    mov rsi, r14
    mov rdi, s_pp_file
    mov ecx, 8
    repe cmpsb
    jne .notfile
    mov al, '"'
    call pp_putc
    mov rsi, [pp_curfile]
.fn:mov al, [rsi]
    test al, al
    jz .fn2
    cmp al, '\'
    jne .fn1
    call pp_putc
.fn1:
    call pp_putc
    inc rsi
    jmp .fn
.fn2:
    mov al, '"'
    call pp_putc
    jmp .loop
.notfile:
    mov rsi, r14
    mov ecx, r15d
    call pp_find
    test rax, rax
    jz .plain
    mov rbx, rax
    cmp dword [rbx+M_OFF], 0
    jne .plain
    cmp dword [rbx+M_KIND], 0
    jne .func
    ; object like: the body is rescanned with the macro switched off
    mov dword [rbx+M_OFF], 1
    mov rsi, [rbx+M_BODY]
    mov rcx, [rbx+M_BLEN]
    call pp_expand
    mov dword [rbx+M_OFF], 0
    jmp .loop
.plain:
    mov rsi, r14
    mov rcx, r15
    call pp_write
    jmp .loop

.func:
    mov rbp, r12                        ; remember the position after the name
.fs:cmp r12, r13
    jae .notcall
    mov al, [r12]
    cmp al, ' '
    je .fs1
    cmp al, 9
    je .fs1
    cmp al, 13
    je .fs1
    cmp al, 10
    jne .fs2
.fs1:
    inc r12
    jmp .fs
.fs2:
    cmp al, '('
    je .call
.notcall:
    mov r12, rbp
    jmp .plain
.call:
    ; allocate the argument table and the substitution area above everything that is in use
    call pp_scratch_base
    mov [pp_args], rax                  ; (saved per call below)
    push qword [pp_args]                ; args table
    push qword [pp_sp]                  ; old scratch top
    push qword [pp_op]                  ; where the result goes
    mov rdx, [rsp+16]
    lea rax, [rdx + PP_MAXARGS*16 + 64]
    cmp rax, pp_mem + PP_OUT_SIZE + PP_SCR_SIZE - 65536
    jb .sok
    PPERR "macro expansion needs too much memory"
.sok:
    mov [pp_sp], rax
    mov [pp_op], rax
    ; collect the arguments:  r12 -> '('
    inc r12
    xor ebp, ebp                        ; argument count
    mov rdi, [rsp+16]
    mov rsi, r12                        ; start of the current argument
    mov edx, 1                          ; paren depth
.a1:
    cmp r12, r13
    jae .a_eof
    mov al, [r12]
    cmp al, '"'
    je .a_str
    cmp al, 0x27
    je .a_str
    cmp al, '('
    jne .a2
    inc edx
    inc r12
    jmp .a1
.a2:
    cmp al, ')'
    jne .a3
    dec edx
    jz .a_end
    inc r12
    jmp .a1
.a3:
    cmp al, ','
    jne .a4
    cmp edx, 1
    jne .a4
    ; a comma ends the argument unless this is the variadic slot
    cmp dword [rbx+M_VARIADIC], 0
    je .a_split
    mov ecx, [rbx+M_NPAR]
    cmp ebp, ecx
    jae .a4
.a_split:
    cmp ebp, PP_MAXARGS
    jb .a_s1
    PPERR "too many macro arguments"
.a_s1:
    mov rcx, rbp
    shl rcx, 4
    mov [rdi+rcx], rsi
    mov rax, r12
    sub rax, rsi
    mov [rdi+rcx+8], rax
    inc ebp
    inc r12
    mov rsi, r12
    jmp .a1
.a4:
    inc r12
    jmp .a1
.a_str:
    mov r8b, [r12]
    inc r12
.a_s2:
    cmp r12, r13
    jae .a_eof
    mov al, [r12]
    inc r12
    cmp al, '\'
    jne .a_s3
    cmp r12, r13
    jae .a_eof
    inc r12
    jmp .a_s2
.a_s3:
    cmp al, r8b
    jne .a_s2
    jmp .a1
.a_eof:
    ; the call is not finished
    pop rax                             ; result position
    pop rcx
    mov [pp_sp], rcx
    mov [pp_op], rax
    add rsp, 8
    cmp dword [pp_depth], 1
    jne .a_eof_text
    mov eax, 1                          ; ask for more lines
    jmp .out
.a_eof_text:
    mov rsi, r14                        ; inside a macro body: keep the text as it is
    mov rcx, r13
    sub rcx, r14
    call pp_write
    mov r12, r13
    jmp .loop
.a_end:
    ; the last argument
    cmp ebp, PP_MAXARGS
    jb .a_e1
    PPERR "too many macro arguments"
.a_e1:
    mov rcx, rbp
    shl rcx, 4
    mov [rdi+rcx], rsi
    mov rax, r12
    sub rax, rsi
    mov [rdi+rcx+8], rax
    inc ebp
    inc r12                             ; past ')'
    ; the macro again (rbx was clobbered? no: rbx still the macro) - check the count
    mov ecx, [rbx+M_NPAR]
    cmp ebp, ecx
    jbe .cnt_ok
    cmp dword [rbx+M_VARIADIC], 0
    jne .cnt_ok
    ; F() for a macro without parameters is an empty call
    cmp ecx, 0
    jne .cnt_bad
    cmp ebp, 1
    jne .cnt_bad
    mov rax, [rdi+8]
    test rax, rax
    jz .cnt_ok
.cnt_bad:
    PPERR "wrong number of macro arguments"
.cnt_ok:
    mov ecx, [rbx+M_NPAR]
    cmp ebp, ecx
    jae .cnt_ok2
    PPERR "too few arguments for the macro"
.cnt_ok2:
    ; a variadic part that is left out is empty
    mov ecx, [rbx+M_NPAR]
    cmp dword [rbx+M_VARIADIC], 0
    je .fill
    inc ecx
.fill:
    cmp ebp, ecx
    jae .filled
    mov rax, rbp
    shl rax, 4
    mov qword [rdi+rax], 0
    mov qword [rdi+rax+8], 0
    inc ebp
    jmp .fill
.filled:
    ; substitute the arguments into the body (output goes to the scratch area at pp_op)
    mov rsi, rdi
    call pp_subst                       ; rbx = macro, rsi = argument table
    mov rax, [pp_op]                    ; end of the substituted text
    mov rbp, [pp_sp]                    ; start of it
    ; rescan: the result is produced above the substituted text and then moved down to the result position
    lea rcx, [rax + 32]
    and rcx, -16
    mov [pp_sp], rcx
    mov [pp_op], rcx
    mov r14, rcx                        ; start of the rescan output
    push rax
    mov dword [rbx+M_OFF], 1
    mov rsi, rbp
    mov rcx, rax
    sub rcx, rbp
    call pp_expand
    mov dword [rbx+M_OFF], 0
    pop rax
    mov rcx, [pp_op]
    sub rcx, r14                        ; length of the result
    pop rdi                             ; result position
    pop rax
    mov [pp_sp], rax                    ; old scratch top
    add rsp, 8                          ; table
    mov rsi, r14
    mov [pp_op], rdi
    rep movsb
    mov [pp_op], rdi
    jmp .loop

.done0:
    xor eax, eax
.out:
    dec dword [pp_depth]
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; pp_subst: rbx = function like macro, rsi = argument table (16 bytes per argument). Writes the body with the arguments
; substituted at pp_op.
pp_subst:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov rbp, rsi                        ; argument table
    mov r12, [rbx+M_BODY]
    mov r13, r12
    add r13, [rbx+M_BLEN]
    mov r15, [pp_op]                    ; start of this substitution (nothing may be removed below it)
    xor r14d, r14d                      ; 1 = the previous token was ##
.l: cmp r12, r13
    jae .done
    movzx eax, byte [r12]
    cmp al, '"'
    je .lit
    cmp al, 0x27
    je .lit
    cmp al, '#'
    je .hash
    cmp al, '0'
    jb .nonum
    cmp al, '9'
    jbe .num
.nonum:
    call pp_isidstart
    test eax, eax
    jnz .id
    mov al, [r12]
    cmp al, ' '
    je .space
    xor r14d, r14d
.space:
    call pp_putc
    inc r12
    jmp .l
.num:
    xor r14d, r14d
.n1:mov al, [r12]
    call pp_putc
    inc r12
    cmp r12, r13
    jae .l
    mov al, [r12]
    cmp al, '.'
    je .n1
    call pp_isid
    test eax, eax
    jnz .n1
    jmp .l
.lit:
    xor r14d, r14d
    mov r9b, [r12]
.lit1:
    mov al, [r12]
    call pp_putc
    inc r12
.lit2:
    cmp r12, r13
    jae .l
    mov al, [r12]
    call pp_putc
    inc r12
    cmp al, '\'
    jne .lit3
    cmp r12, r13
    jae .l
    mov al, [r12]
    call pp_putc
    inc r12
    jmp .lit2
.lit3:
    cmp al, r9b
    jne .lit2
    jmp .l
.hash:
    cmp byte [r12+1], '#'
    je .paste
    ; # param : the argument as a string
    lea rsi, [r12+1]
.h1:cmp rsi, r13
    jae .hlit
    mov al, [rsi]
    cmp al, ' '
    jne .h2
    inc rsi
    jmp .h1
.h2:
    push rsi
    call pp_ident
    pop rsi
    test ecx, ecx
    jz .hlit
    call pp_param_index                 ; eax = index or -1
    cmp eax, -1
    je .hlit
    mov r12, rsi
    add r12, rcx                        ; past the parameter name
    shl rax, 4
    mov rsi, [rbp+rax]
    mov rcx, [rbp+rax+8]
    call pp_stringify
    xor r14d, r14d
    jmp .l
.hlit:
    mov al, '#'
    call pp_putc
    inc r12
    jmp .l
.paste:
    ; remove the white space before ## and after it
.p1:mov rax, [pp_op]
    cmp rax, r15
    jbe .p2
    cmp byte [rax-1], ' '
    jne .p2
    dec qword [pp_op]
    jmp .p1
.p2:
    add r12, 2
.p3:cmp r12, r13
    jae .p4
    cmp byte [r12], ' '
    jne .p4
    inc r12
    jmp .p3
.p4:
    mov r14d, 1
    jmp .l
.id:
    mov rsi, r12
    call pp_ident                       ; rcx = length
    call pp_param_index
    cmp eax, -1
    je .idplain
    ; a parameter: raw when next to ##, expanded otherwise
    lea r8, [r12 + rcx]
    mov r12, r8
    shl rax, 4
    mov rsi, [rbp+rax]
    mov rdx, [rbp+rax+8]
    ; trim the argument
.t1:test rdx, rdx
    jz .t2
    mov al, [rsi]
    cmp al, ' '
    je .t1a
    cmp al, 9
    je .t1a
    cmp al, 10
    jne .t2
.t1a:
    inc rsi
    dec rdx
    jmp .t1
.t2:test rdx, rdx
    jz .t3
    mov al, [rsi+rdx-1]
    cmp al, ' '
    je .t2a
    cmp al, 9
    je .t2a
    cmp al, 10
    jne .t3
.t2a:
    dec rdx
    jmp .t2
.t3:
    mov rcx, rdx
    test r14d, r14d
    jnz .raw
    ; is ## the next thing in the body?
    mov r8, r12
.q1:cmp r8, r13
    jae .exp
    cmp byte [r8], ' '
    jne .q2
    inc r8
    jmp .q1
.q2:
    lea rax, [r8+1]
    cmp rax, r13
    jae .exp
    cmp byte [r8], '#'
    jne .exp
    cmp byte [r8+1], '#'
    je .raw
.exp:
    call pp_expand                      ; the argument is expanded completely first
    xor r14d, r14d
    jmp .l
.raw:
    call pp_write
    xor r14d, r14d
    jmp .l
.idplain:
    xor r14d, r14d
    mov rsi, r12
    add r12, rcx
    call pp_write
    jmp .l
.done:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; pp_param_index: rbx = macro, rsi = name, rcx = length -> eax = parameter index or -1 (rsi, rcx unchanged)
pp_param_index:
    push rdi
    push rdx
    push r8
    push r9
    mov r9, rcx
    xor edx, edx
    mov r8, [rbx+M_PARAMS]
.l: cmp edx, [rbx+M_NPAR]
    jae .va
    mov rax, rdx
    shl rax, 4
    cmp [r8+rax+8], r9
    jne .n
    push rsi
    push rcx
    mov rdi, [r8+rax]
    mov rcx, r9
    repe cmpsb
    pop rcx
    pop rsi
    jne .n
    mov eax, edx
    jmp .out
.n: inc edx
    jmp .l
.va:
    cmp dword [rbx+M_VARIADIC], 0
    je .none
    cmp r9, 11
    jne .none
    push rsi
    push rcx
    mov rdi, s_pp_va
    mov ecx, 11
    repe cmpsb
    pop rcx
    pop rsi
    jne .none
    mov eax, [rbx+M_NPAR]
    jmp .out
.none:
    mov eax, -1
.out:
    pop r9
    pop r8
    pop rdx
    pop rdi
    ret

; pp_stringify: rsi = text, rcx = length -> "text" (quotes and backslashes escaped)
pp_stringify:
    push rsi
    push rcx
    mov al, '"'
    call pp_putc
.l: test rcx, rcx
    jz .d
    mov al, [rsi]
    cmp al, '"'
    je .e
    cmp al, '\'
    jne .p
.e: push rax
    mov al, '\'
    call pp_putc
    pop rax
.p: call pp_putc
    inc rsi
    dec rcx
    jmp .l
.d: mov al, '"'
    call pp_putc
    pop rcx
    pop rsi
    ret

; ---- cleaning: comments out ---------------------------------------------------------------------------------------------------
; pp_clean: rsi = start, rdx = end, rdi = destination -> rax = end of the cleaned text (NUL terminated)
; Comments become a single space (a block comment that ends on a later line is remembered in pp_in_comment).
pp_clean:
    push rbx
    xor ebx, ebx                        ; open quote character
.l: cmp rsi, rdx
    jae .done
    mov al, [rsi]
    cmp dword [pp_in_comment], 0
    je .nc
    ; inside /* ... */
    cmp al, '*'
    jne .skip
    cmp rsi, rdx
    jae .skip
    lea rcx, [rsi+1]
    cmp rcx, rdx
    jae .skip
    cmp byte [rsi+1], '/'
    jne .skip
    mov dword [pp_in_comment], 0
    add rsi, 2
    mov byte [rdi], ' '
    inc rdi
    jmp .l
.skip:
    inc rsi
    jmp .l
.nc:
    test ebx, ebx
    jz .noq
    mov [rdi], al
    inc rdi
    inc rsi
    cmp al, '\'
    jne .q1
    cmp rsi, rdx
    jae .l
    mov al, [rsi]
    mov [rdi], al
    inc rdi
    inc rsi
    jmp .l
.q1:
    cmp al, bl
    jne .l
    xor ebx, ebx
    jmp .l
.noq:
    cmp al, '"'
    je .openq
    cmp al, 0x27
    je .openq
    cmp al, '/'
    jne .copy
    lea rcx, [rsi+1]
    cmp rcx, rdx
    jae .copy
    cmp byte [rsi+1], '*'
    je .bc
    cmp byte [rsi+1], '/'
    jne .copy
    mov rsi, rdx                        ; // comment: the rest of the line
    jmp .l
.bc:
    mov dword [pp_in_comment], 1
    add rsi, 2
    jmp .l
.openq:
    movzx ebx, al
.copy:
    mov [rdi], al
    inc rdi
    inc rsi
    jmp .l
.done:
    mov byte [rdi], 0
    mov rax, rdi
    pop rbx
    ret

; ---- conditions -----------------------------------------------------------------------------------------------------------------
; pp_active_calc: sets pp_active from the condition stack
pp_active_calc:
    mov dword [pp_active], 1
    mov eax, [pp_cdepth]
    test eax, eax
    jz .r
    movzx eax, byte [pp_cstack + rax - 1]
    and eax, 5                          ; parent active, this branch active
    cmp eax, 5
    je .r
    mov dword [pp_active], 0
.r: ret

; pp_eval: rsi = expression text (NUL terminated) -> eax = value of the #if expression
pp_eval:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push qword [pp_op]
    push qword [pp_sp]
    mov r12, rsi
    ; step 1: defined(X) -> 1 / 0
    call pp_scratch_base
    mov r14, rax                        ; T1
    mov [pp_op], rax
.s1:mov al, [r12]
    test al, al
    jz .s1d
    call pp_isidstart
    test eax, eax
    jnz .s1id
    cmp byte [r12], '0'
    jb .s1c
    cmp byte [r12], '9'
    ja .s1c
.s1n:                                   ; a number: copy it (0x1F, 10UL ...)
    mov al, [r12]
    call pp_putc
    inc r12
    mov al, [r12]
    call pp_isid
    test eax, eax
    jnz .s1n
    jmp .s1
.s1c:
    mov al, [r12]
    call pp_putc
    inc r12
    jmp .s1
.s1id:
    mov rsi, r12
    call pp_ident
    cmp ecx, 7
    jne .s1plain
    push rcx
    push rsi
    mov rdi, s_pp_defined
    mov ecx, 7
    repe cmpsb
    pop rsi
    pop rcx
    jne .s1plain
    add r12, 7
    mov rsi, r12
    call pp_skipws
    xor ebx, ebx
    cmp byte [rsi], '('
    jne .d1
    inc rsi
    call pp_skipws
    mov ebx, 1
.d1:call pp_ident
    test ecx, ecx
    jnz .d2
    PPERR "expected a name after defined"
.d2:push rsi
    push rcx
    call pp_find
    mov r13, rax
    pop rcx
    pop rsi
    add rsi, rcx
    call pp_skipws
    test ebx, ebx
    jz .d3
    cmp byte [rsi], ')'
    je .d4
    PPERR "missing ')' after defined(...)"
.d4:inc rsi
.d3:mov r12, rsi
    mov al, '0'
    test r13, r13
    jz .d5
    mov al, '1'
.d5:call pp_putc
    jmp .s1
.s1plain:
    mov rsi, r12
    add r12, rcx
    call pp_write
    jmp .s1
.s1d:
    xor eax, eax
    call pp_putc
    mov rax, [pp_op]
    ; step 2: macro expansion
    lea rcx, [rax + 32]
    and rcx, -16
    mov [pp_sp], rcx
    mov [pp_op], rcx
    mov r15, rcx                        ; T2
    mov rsi, r14
    mov rcx, rax
    sub rcx, r14
    dec rcx
    call pp_expand
    xor eax, eax
    call pp_putc
    ; step 3: remaining names are 0 (true is 1)
    mov rax, [pp_op]
    lea rcx, [rax + 32]
    and rcx, -16
    mov [pp_sp], rcx
    mov [pp_op], rcx
    mov r14, rcx                        ; T3
    mov r12, r15
.s3:mov al, [r12]
    test al, al
    jz .s3d
    cmp al, '0'
    jb .s3a
    cmp al, '9'
    ja .s3a
.s3n:
    mov al, [r12]
    call pp_putc
    inc r12
    mov al, [r12]
    call pp_isid
    test eax, eax
    jnz .s3n
    jmp .s3
.s3a:
    call pp_isidstart
    test eax, eax
    jnz .s3id
    mov al, [r12]
    call pp_putc
    inc r12
    jmp .s3
.s3id:
    mov rsi, r12
    call pp_ident
    add r12, rcx
    mov al, '0'
    cmp ecx, 4
    jne .s3w
    cmp dword [rsi], 'true'
    jne .s3w
    mov al, '1'
.s3w:
    call pp_putc
    jmp .s3
.s3d:
    xor eax, eax
    call pp_putc
    mov rax, [pp_op]
    dec rax
    ; step 4: evaluate with the compiler's constant expression parser
    sub rsp, 128
    mov rdi, rsp
    call lex_save
    mov [src_ptr], r14
    mov [src_end], rax
    mov rax, [pp_line]
    mov [src_line], rax
    mov [tk_line], rax
    mov rax, [pp_curfile]
    mov [cur_file_name], rax
    call next_token
    cmp qword [tk], T_EOF
    jne .e1
    PPERR "expected an expression after #if"
.e1:call const_expr
    mov rbx, rax
    cmp qword [tk], T_EOF
    je .e2
    PPERR "this #if expression cannot be evaluated"
.e2:mov rsi, rsp
    call lex_restore
    add rsp, 128
    xor eax, eax
    test rbx, rbx
    setnz al
    pop qword [pp_sp]
    pop qword [pp_op]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; pp_cpush: al = flags (bit0 parent active, bit1 a branch was taken, bit2 this branch active)
pp_cpush:
    mov ecx, [pp_cdepth]
    cmp ecx, PP_MAXCOND
    jb .ok
    PPERR "#if is nested too deeply"
.ok:
    mov [pp_cstack + rcx], al
    inc dword [pp_cdepth]
    jmp pp_active_calc

; ---- directives ------------------------------------------------------------------------------------------------------------
; pp_is: rsi = text, ecx = length, rdi = constant string -> eax = 1 when equal
pp_is:
    push rsi
    push rdi
    push rcx
    push rdx
    mov rdx, rcx
.l: test rdx, rdx
    jz .end
    mov al, [rdi]
    test al, al
    jz .no
    cmp al, [rsi]
    jne .no
    inc rsi
    inc rdi
    dec rdx
    jmp .l
.end:
    cmp byte [rdi], 0
    jne .no
    mov eax, 1
    jmp .out
.no:xor eax, eax
.out:
    pop rdx
    pop rcx
    pop rdi
    pop rsi
    ret

%macro PPDIR 2
    mov rdi, %1
    call pp_is
    test eax, eax
    jnz %2
%endmacro

; pp_directive: pp_lbuf holds the cleaned directive line without the '#'
pp_directive:
    push rbx
    push r12
    mov rsi, pp_lbuf
    call pp_skipws
    call pp_ident
    mov r12, rsi
    add r12, rcx                        ; text after the directive name
    ; --- conditionals are always tracked
    PPDIR s_pp_ifdef, .ifdef
    PPDIR s_pp_ifndef, .ifndef
    PPDIR s_pp_if, .if
    PPDIR s_pp_elif, .elif
    PPDIR s_pp_else, .else
    PPDIR s_pp_endif, .endif
    cmp dword [pp_active], 0
    je .out
    PPDIR s_pp_define, .define
    PPDIR s_pp_undef, .undef
    PPDIR s_pp_include, .include
    PPDIR s_pp_error, .error
    PPDIR s_pp_pragma, .pragma
    PPDIR s_pp_warning, .out
    PPDIR s_pp_line_d, .out
    test ecx, ecx
    jz .out                             ; a lone '#'
    PPERR "unknown preprocessor directive"
.define:
    mov rsi, r12
    call pp_do_define
    jmp .out
.undef:
    mov rsi, r12
    call pp_do_undef
    jmp .out
.error:
    PPERR "#error"
.pragma:
    mov rsi, r12
    call pp_skipws
    call pp_ident
    mov rdi, s_pp_once
    call pp_is
    test eax, eax
    jz .out
    ; remember the file: it is not included a second time
    mov rax, [pp_curfile]
    mov ecx, [pp_oncecount]
    cmp ecx, 64
    jae .out
    mov [pp_once + rcx*8], rax
    inc dword [pp_oncecount]
    jmp .out
.include:
    mov rsi, r12
    call pp_include
    jmp .out
.ifdef:
    mov bl, 1
    jmp .ifd
.ifndef:
    mov bl, 0
.ifd:
    cmp dword [pp_active], 0
    jne .ifd1
    mov al, 2                           ; parent inactive: no branch can become active
    call pp_cpush
    jmp .out
.ifd1:
    mov rsi, r12
    call pp_skipws
    call pp_ident
    test ecx, ecx
    jnz .ifd2
    PPERR "expected a name after #ifdef / #ifndef"
.ifd2:
    call pp_find
    test rax, rax
    setnz al
    movzx eax, al
    cmp bl, 1
    je .ifd3
    xor eax, 1
.ifd3:
    ; flags: parent active (1), taken (2) and this branch (4)
    mov edx, eax
    mov al, 1
    test edx, edx
    jz .ifd4
    or al, 6
.ifd4:
    call pp_cpush
    jmp .out
.if:
    cmp dword [pp_active], 0
    jne .if1
    mov al, 2
    call pp_cpush
    jmp .out
.if1:
    mov rsi, r12
    call pp_eval
    mov edx, eax
    mov al, 1
    test edx, edx
    jz .if2
    or al, 6
.if2:
    call pp_cpush
    jmp .out
.elif:
    mov ecx, [pp_cdepth]
    test ecx, ecx
    jnz .el1
    PPERR "#elif without #if"
.el1:
    movzx eax, byte [pp_cstack + rcx - 1]
    test al, 1
    jz .out                             ; the parent is inactive
    test al, 2
    jz .el2
    and al, ~4                          ; a branch was taken already
    mov [pp_cstack + rcx - 1], al
    call pp_active_calc
    jmp .out
.el2:
    mov rsi, r12
    call pp_eval_keep
    mov ecx, [pp_cdepth]
    movzx edx, byte [pp_cstack + rcx - 1]
    test eax, eax
    jz .el3
    or dl, 6
.el3:
    mov [pp_cstack + rcx - 1], dl
    call pp_active_calc
    jmp .out
.else:
    mov ecx, [pp_cdepth]
    test ecx, ecx
    jnz .es1
    PPERR "#else without #if"
.es1:
    movzx eax, byte [pp_cstack + rcx - 1]
    test al, 1
    jz .out
    test al, 2
    jz .es2
    and al, ~4
    jmp .es3
.es2:
    or al, 6
.es3:
    mov [pp_cstack + rcx - 1], al
    call pp_active_calc
    jmp .out
.endif:
    mov ecx, [pp_cdepth]
    test ecx, ecx
    jnz .en1
    PPERR "#endif without #if"
.en1:
    dec dword [pp_cdepth]
    call pp_active_calc
.out:
    pop r12
    pop rbx
    ret

; pp_eval_keep: pp_eval that keeps rcx/rdx free for the caller
pp_eval_keep:
    jmp pp_eval

; pp_include: rsi = text after "include"
pp_include:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call pp_skipws
    mov al, [rsi]
    mov bl, '"'
    cmp al, '"'
    je .q
    mov bl, '>'
    cmp al, '<'
    je .q
    PPERR 'expected "file" or <file> after #include'
.q: inc rsi
    mov r12, rsi
.f: mov al, [rsi]
    test al, al
    jnz .f1
    PPERR "unterminated #include"
.f1:cmp al, bl
    je .f2
    inc rsi
    jmp .f
.f2:mov r13, rsi
    sub r13, r12                        ; name length
    cmp r13, 400
    jbe .nl
    PPERR "include path too long"
.nl:
    cmp dword [pp_incdepth], 12
    jb .depth
    PPERR "#include is nested too deeply"
.depth:
    ; candidates: next to the including file, as given, lib/ directories
    xor r14d, r14d
.try:
    mov rdi, pp_path
    cmp r14d, 0
    jne .c1
    ; the directory of the current file
    mov rsi, [pp_curfile]
    mov rcx, rsi
    xor edx, edx
.d1:mov al, [rcx]
    test al, al
    jz .d2
    inc rcx
    cmp al, '/'
    jne .d1
    mov rdx, rcx
    jmp .d1
.d2:test rdx, rdx
    jz .next
    mov rcx, rdx
    sub rcx, rsi
    rep movsb
    jmp .name
.c1:
    cmp r14d, 1
    je .name
    cmp r14d, 2
    jne .c3
    mov rsi, s_libdir1
    call cstr_copy
    jmp .name
.c3:
    cmp r14d, 3
    jne .c4
    mov rsi, s_libdir2
    call cstr_copy
    jmp .name
.c4:
    cmp r14d, 4
    jne .c5
    mov rsi, s_libdir3
    call cstr_copy
    jmp .name
.c5:
    cmp r14d, 5
    jne .fail
    mov rsi, [main_dir]
    call cstr_copy
    mov rsi, s_libdir1
    call cstr_copy
.name:
    mov rsi, r12
    mov rcx, r13
    rep movsb
    mov byte [rdi], 0
    mov rdi, pp_path
    ; already included with #pragma once?
    xor ecx, ecx
.o1:cmp ecx, [pp_oncecount]
    jae .o9
    push rcx
    mov rdi, [pp_once + rcx*8]
    mov rsi, pp_path
    call cstr_eq
    pop rcx
    test eax, eax
    jnz .skip
    inc ecx
    jmp .o1
.o9:mov rdi, pp_path
    call read_file
    test rax, rax
    jnz .got
.next:
    inc r14d
    jmp .try
.fail:
    PPERR "cannot open the #include file"
.skip:
    jmp .done
.got:
    mov r15, rax                        ; text
    add rdx, rax                        ; end
    mov rbx, rdx
    ; keep the path (it names the file for nested includes, #pragma once and __FILE__)
    mov rdi, pp_path
    call cstrlen
    mov rcx, rax
    mov rsi, pp_path
    call pp_pool_copy
    ; save the state of the including file
    push qword [pp_curfile]
    push qword [pp_srcbase]
    push qword [pp_line]
    push qword [pp_in_comment]
    push qword [pp_op]
    mov [pp_curfile], rax
    mov [pp_srcbase], r15
    mov qword [pp_line], 1
    mov dword [pp_in_comment], 0
    inc dword [pp_incdepth]
    mov r13d, [pp_cdepth]
    mov rsi, r15
    mov rdx, rbx
    call pp_run
    cmp r13d, [pp_cdepth]
    je .balanced
    PPERR "unterminated #if in the included file"
.balanced:
    dec dword [pp_incdepth]
    ; the included lines are joined into one line (so the line numbers of the including file stay right)
    pop rsi                             ; start of the included output
    mov rdi, [pp_op]
    push rsi
.j: cmp rsi, rdi
    jae .jd
    cmp byte [rsi], 10
    jne .j1
    mov byte [rsi], ' '
.j1:inc rsi
    jmp .j
.jd:pop rsi
    pop qword [pp_in_comment]
    pop qword [pp_line]
    pop qword [pp_srcbase]
    pop qword [pp_curfile]
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---- the main loop -------------------------------------------------------------------------------------------------------------
; pp_run: rsi = text, rdx = end of the text. Appends the preprocessed text to the output.
pp_run:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov r12, rsi
    mov r13, rdx
    ; keep a byte order mark in front
    cmp byte [r12], 0xEF
    jne .line
    cmp byte [r12+1], 0xBB
    jne .line
    cmp byte [r12+2], 0xBF
    jne .line
    mov al, 0xEF
    call pp_putc
    mov al, 0xBB
    call pp_putc
    mov al, 0xBF
    call pp_putc
    add r12, 3
.line:
    cmp r12, r13
    jae .done
    mov rax, [pp_op]
    cmp rax, pp_mem + PP_OUT_SIZE
    jb .oksz
    PPERR "preprocessor output too large"
.oksz:
    mov rsi, r12
.ws:mov al, [rsi]
    cmp al, ' '
    je .ws1
    cmp al, 9
    jne .ws2
.ws1:
    inc rsi
    cmp rsi, r13
    jb .ws
.ws2:
    cmp dword [pp_in_comment], 0
    jne .normal
    cmp rsi, r13
    jae .normal
    cmp byte [rsi], '#'
    jne .normal
    ; ---- a directive: join continuation lines
    inc rsi
    mov rdi, pp_dbuf
    xor ebp, ebp                        ; physical lines after the first
.d1:cmp rsi, r13
    jae .d3
    mov al, [rsi]
    cmp al, 10
    je .d2
    mov [rdi], al
    inc rdi
    inc rsi
    jmp .d1
.d2:                                    ; end of a line: a backslash before it continues the directive
    cmp rdi, pp_dbuf
    jbe .d3
    cmp byte [rdi-1], 13
    jne .d2b
    dec rdi
.d2b:
    cmp rdi, pp_dbuf
    jbe .d3
    cmp byte [rdi-1], '\'
    jne .d3
    dec rdi
    inc rsi
    inc ebp
    mov byte [rdi], ' '
    inc rdi
    jmp .d1
.d3:
    mov r12, rsi
    cmp r12, r13
    jae .d4
    inc r12                             ; past the newline
.d4:
    push rbp
    mov rsi, pp_dbuf
    mov rdx, rdi
    mov rdi, pp_lbuf
    call pp_clean
    call pp_directive
    pop rbp
    ; one newline for the directive line and one for every continuation line
    mov al, 10
    call pp_putc
    inc qword [pp_line]
.d5:test ebp, ebp
    jz .line
    mov al, 10
    call pp_putc
    inc qword [pp_line]
    dec ebp
    jmp .d5

.normal:
    ; ---- an ordinary line
    mov rsi, r12
.e1:cmp rsi, r13
    jae .e2
    cmp byte [rsi], 10
    je .e2
    inc rsi
    jmp .e1
.e2:mov rdx, rsi                        ; end of the line
    mov rsi, r12
    mov rdi, pp_lbuf
    call pp_clean
    mov r14, rax                        ; end of the cleaned text
    mov r12, rdx
    cmp r12, r13
    jae .e3
    inc r12
.e3:xor ebp, ebp                        ; extra lines used up by a macro call that continues
    cmp dword [pp_active], 0
    je .emit
    cmp dword [pp_mcount], 0
    je .copy
.again:
    mov rax, [pp_op]
    mov [pp_lineop], rax
    mov rsi, pp_lbuf
    mov rcx, r14
    sub rcx, pp_lbuf
    mov dword [pp_depth], 0
    call pp_expand
    test eax, eax
    jz .emit
    ; the call goes on in the next line: join it and try again
    mov rax, [pp_lineop]
    mov [pp_op], rax
    cmp r12, r13
    jae .unterminated
    cmp ebp, 64
    jae .unterminated
    mov byte [r14], ' '
    inc r14
    mov rsi, r12
.j1:cmp rsi, r13
    jae .j2
    cmp byte [rsi], 10
    je .j2
    inc rsi
    jmp .j1
.j2:mov rdx, rsi
    mov rsi, r12
    mov rdi, r14
    call pp_clean
    mov r14, rax
    mov r12, rdx
    cmp r12, r13
    jae .j3
    inc r12
.j3:inc ebp
    inc qword [pp_line]
    jmp .again
.unterminated:
    PPERR "unterminated macro call"
.copy:
    mov rsi, pp_lbuf
    mov rcx, r14
    sub rcx, pp_lbuf
    call pp_write
.emit:
    mov al, 10
    call pp_putc
    inc qword [pp_line]
.x1:test ebp, ebp
    jz .line
    mov al, 10
    call pp_putc
    dec ebp
    jmp .x1
.done:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---- entry points --------------------------------------------------------------------------------------------------------------
; pp_define_cstr: rsi = "NAME" or "NAME=value" (as given to -D)
pp_define_cstr:
    push rbx
    mov rdi, pp_lbuf
    mov rbx, rsi
.c: mov al, [rsi]
    test al, al
    jz .noval
    cmp al, '='
    je .val
    mov [rdi], al
    inc rdi
    inc rsi
    jmp .c
.val:
    mov byte [rdi], ' '
    inc rdi
    inc rsi
.v: mov al, [rsi]
    mov [rdi], al
    inc rdi
    inc rsi
    test al, al
    jnz .v
    jmp .go
.noval:
    mov word [rdi], ' 1'
    mov byte [rdi+2], 0
.go:
    mov rsi, pp_lbuf
    call pp_do_define
    pop rbx
    ret

; pp_init: predefined macros and the -D definitions (after the options are known)
pp_init:
    push rbx
    mov qword [pp_sp], pp_mem + PP_OUT_SIZE
    mov rsi, s_pp_def_a
    call pp_define_cstr
    ; __ARCH__ and __OS__
    mov rdi, pp_lbuf2
    mov rsi, s_pp_arch
    call cstr_copy
    mov eax, [arch]
    add al, '0'
    mov [rdi], al
    mov byte [rdi+1], 0
    mov rsi, pp_lbuf2
    call pp_define_cstr
    mov rdi, pp_lbuf2
    mov rsi, s_pp_os
    call cstr_copy
    mov eax, [target]
    add al, '0'
    mov [rdi], al
    mov byte [rdi+1], 0
    mov rsi, pp_lbuf2
    call pp_define_cstr
    ; command line definitions
    xor ebx, ebx
.d: cmp ebx, [opt_ndefs]
    jae .done
    mov rsi, [opt_defs + rbx*8]
    call pp_define_cstr
    inc ebx
    jmp .d
.done:
    pop rbx
    ret

; pp_file: rsi = text, rdx = length, rdi = path -> rax = the preprocessed text (in the arena), rdx = its length
pp_file:
    push rbx
    push r12
    push r13
    push qword [cur_file_name]
    push qword [cur_src_base]
    push qword [tk_line]
    mov [pp_curfile], rdi
    mov [pp_srcbase], rsi
    mov qword [pp_line], 1
    mov dword [pp_in_comment], 0
    mov dword [pp_cdepth], 0
    mov dword [pp_incdepth], 0
    mov dword [pp_depth], 0
    mov dword [pp_active], 1
    mov qword [pp_op], pp_mem
    mov qword [pp_sp], pp_mem + PP_OUT_SIZE
    mov r12, rsi
    add rdx, rsi
    mov rbx, rdi
    mov rsi, r12
    call pp_run
    cmp dword [pp_cdepth], 0
    je .ok
    mov rax, [pp_line]
    mov [pp_line], rax
    PPERR "unterminated #if (missing #endif)"
.ok:
    mov rcx, [pp_op]
    sub rcx, pp_mem
    mov r13, rcx                        ; length
    mov rdi, arena
    add rdi, [arena_pos]
    lea rax, [r13 + 16]
    add rax, [arena_pos]
    add rax, (1<<20)
    cmp rax, ARENA_MAX
    jbe .room
    jmp err_toobig
.room:
    mov r12, rdi
    mov rsi, pp_mem
    rep movsb
    mov byte [rdi], 0
    lea rax, [r13 + 16]
    and rax, -16
    add [arena_pos], rax
    mov rax, r12
    mov rdx, r13
    pop qword [tk_line]
    pop qword [cur_src_base]
    pop qword [cur_file_name]
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
s_pp_line:      db "__LINE__", 0
s_pp_file:      db "__FILE__", 0
s_pp_va:        db "__VA_ARGS__", 0
s_pp_defined:   db "defined", 0
s_pp_ifdef:     db "ifdef", 0
s_pp_ifndef:    db "ifndef", 0
s_pp_if:        db "if", 0
s_pp_elif:      db "elif", 0
s_pp_else:      db "else", 0
s_pp_endif:     db "endif", 0
s_pp_define:    db "define", 0
s_pp_undef:     db "undef", 0
s_pp_include:   db "include", 0
s_pp_error:     db "error", 0
s_pp_pragma:    db "pragma", 0
s_pp_warning:   db "warning", 0
s_pp_line_d:    db "line", 0
s_pp_once:      db "once", 0
s_pp_def_a:     db "__A__", 0
s_pp_arch:      db "__ARCH__=", 0
s_pp_os:        db "__OS__=", 0

section .bss
alignb 4096
pp_mem:         resb PP_OUT_SIZE + PP_SCR_SIZE
pp_pool:        resb PP_POOL_SIZE
pp_lbuf:        resb PP_LBUF_SIZE
pp_lbuf2:       resb 4096
pp_dbuf:        resb PP_LBUF_SIZE
pp_path:        resb 4096
pp_mtab:        resb PP_MAXMAC * PP_MSIZE
pp_cstack:      resb PP_MAXCOND
pp_once:        resq 64
opt_defs:       resq 32
opt_ndefs:      resd 1
pp_mcount:      resd 1
pp_cdepth:      resd 1
pp_active:      resd 1
pp_depth:       resd 1
pp_incdepth:    resd 1
pp_oncecount:   resd 1
pp_in_comment:  resq 1
pp_poolpos:     resq 1
pp_op:          resq 1
pp_sp:          resq 1
pp_lineop:      resq 1
pp_args:        resq 1
pp_line:        resq 1
pp_curfile:     resq 1
pp_srcbase:     resq 1
section .text
