; =============================================================================
;  lambda.asm - anonymous functions
;
;    func twice = (int x) => x * 2;                 expression body: its value is returned
;    func add = (a, b) => a + b;                    parameters without a type are int
;    func inc = x => x + 1;                         one parameter without parentheses
;    func show = (char* s) => { print(s); return 1; };    block body
;    func half = (double x) -> double => x * 0.5;   optional result type (the default is int)
;    algo.sortBy(a, n, (int* p, int* q) => *p - *q);
;
;  A lambda is an ordinary function whose code is placed inline, jumped over by the enclosing function:
;      jmp over ; start: prologue, parameters, body, epilogue ; over: A = address of start
;  The address is made by the backend primitive lea_code_a (position independent, no relocation, no symbol), so a lambda
;  works in objects, in the linker and in every pass. The value of a lambda is a `func`, like the address of a function, and it is
;  called the same way: through a func value every call returns an int (a double result is read with __dbl).
;
;  While the body is compiled the state of the function that contains it is saved (frame size, labels, loops, defers, ...) and
;  restored afterwards. cur_func stays the enclosing function, so the call graph (dead function elimination) sees the calls of
;  the body as calls of the enclosing function: the lambda exists exactly when that function does.
;
;  Captures: a lambda does not see the local variables, parameters or `this` of the enclosing function. Using one is a compile
;  error that says "pass it as a parameter" (parse_primary checks every local against lam_sym_base, the symbol count at the start
;  of the innermost lambda). Globals, static locals, constants, enums, functions and types are visible.
; =============================================================================
section .rodata
CSTR msg_lam_capture, "a lambda cannot use a local variable of the enclosing function (pass it as a parameter, or use a global); this one is"
section .text

%define LAM_PMAX        16

; frame of parse_lambda
%define LF_PTYPE        0               ; parameters: type, name pointer, name length (16 qwords each)
%define LF_PNAME        128
%define LF_PNLEN        256
%define LF_NPAR         384
%define LF_RET          392             ; the result type
%define LF_RETDECL      400             ; 1 when it was written with ->
%define LF_OVER         408             ; chain head of the jump over the lambda
%define LF_START        416             ; code position of the lambda
%define LF_BARE         424
%define LF_S            432             ; the saved state of the enclosing function: 20 qwords
%define LF_ARR          592             ; saved arrays: defer_buf 2048, lbl_tab 2048, loop_stack 2048, loop_lbl_ptr 512, loop_lbl_len 256
%define LF_BYTES        (LF_ARR + 6912)

; the saved scalars: offset, variable, size
%macro LSAVE 3
%if %3 == 4
    mov eax, [%2]
%else
    mov rax, [%2]
%endif
    mov [rsp + LF_S + %1], rax
%endmacro
%macro LREST 3
    mov rax, [rsp + LF_S + %1]
%if %3 == 4
    mov [%2], eax
%else
    mov [%2], rax
%endif
%endmacro

%macro LSTATE 1                         ; apply macro %1 (LSAVE or LREST) to every scalar of the function state
    %1 0,   frame_size, 4
    %1 8,   ret_chain, 8
    %1 16,  defer_n, 4
    %1 24,  lbl_n, 4
    %1 32,  blk_nest, 4
    %1 40,  loop_sp, 4
    %1 48,  cur_va_cnt, 4
    %1 56,  cur_this_off, 4
    %1 64,  cur_static, 4
    %1 72,  stmt_lbl_ptr, 8
    %1 80,  stmt_lbl_len, 4
    %1 88,  pend_lbl_ptr, 8
    %1 96,  pend_lbl_len, 4
    %1 104, frame_patch, 8
    %1 112, ret_type, 8
    %1 120, lam_depth, 4
    %1 128, lam_sym_base, 4
    %1 136, sym_count, 4
    %1 144, fn_body_flag, 4
%endmacro

; lambda_ahead: the current token is the first one after '(' . eax = 1 when the matching ')' is followed by =>  (or by
; -> type =>): the parenthesis holds the parameters of a lambda. The lexer is restored.
lambda_ahead:
    push rbx
    STACKCHK
    sub rsp, 128
    mov rdi, rsp
    call lex_save
.l: mov rax, [tk]
    cmp rax, '('
    je .no                              ; the parameters of a lambda are names and types: never a '(' inside. (Stopping here also
                                        ; keeps the scan short for nested (a, (a, (a, ... text: no quadratic compile time)
    cmp rax, ')'
    je .end
    cmp rax, T_EOF
    je .no
    cmp rax, ';'
    je .no
    cmp rax, '{'
    je .no
    cmp rax, '}'
    je .no
.nx:
    call next_token
    jmp .l
.end:
    call next_token
    cmp qword [tk], T_FATARROW
    je .yes
    cmp qword [tk], T_ARROW
    jne .no
    call next_token
    call is_type_start
    test eax, eax
    jz .no
    call parse_type
    cmp qword [tk], T_FATARROW
    je .yes
.no:
    xor ebx, ebx
    jmp .back
.yes:
    mov ebx, 1
.back:
    mov rsi, rsp
    call lex_restore
    add rsp, 128
    mov eax, ebx
    pop rbx
    ret

; parse_lambda: edi = 1 when the only parameter is the identifier that is the current token (x => ...); otherwise the
; current token is the first one after '(' . Leaves the address of the lambda in A (type func).
parse_lambda:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, LF_BYTES
    STACKCHK
    cmp qword [cur_func], 0
    jne .infn
    ERR "a lambda can only be used inside a function"
.infn:
    mov [rsp + LF_BARE], rdi
    xor ebx, ebx                        ; number of parameters
    test edi, edi
    jnz .bare
    cmp qword [tk], ')'
    je .pend
.pl:
    cmp ebx, LAM_PMAX
    jb .p0
    ERR "a lambda takes at most 16 parameters"
.p0:
    mov qword [rsp + LF_PTYPE + rbx*8], TY_INT
    call is_type_start
    test eax, eax
    jz .pname
    call parse_type
    cmp rax, TY_VOID
    jne .p1
    ERR "a parameter cannot have type void"
.p1:
    mov rdi, rax
    mov [rsp + LF_PTYPE + rbx*8], rax
    call check_concrete
.pname:
    cmp qword [tk], T_ID
    je .p2
    ERR "expected a parameter name (a lambda parameter is  type name  or just  name  for an int)"
.p2:
    mov rax, [tk_ptr]
    mov [rsp + LF_PNAME + rbx*8], rax
    mov rax, [tk_len]
    mov [rsp + LF_PNLEN + rbx*8], rax
    call next_token
    inc ebx
    cmp qword [tk], ','
    jne .pend
    call next_token
    jmp .pl
.bare:
    mov qword [rsp + LF_PTYPE], TY_INT
    mov rax, [tk_ptr]
    mov [rsp + LF_PNAME], rax
    mov rax, [tk_len]
    mov [rsp + LF_PNLEN], rax
    mov ebx, 1
    call next_token
    jmp .params_done
.pend:
    mov edi, ')'
    call expect
.params_done:
    mov [rsp + LF_NPAR], rbx
    mov qword [rsp + LF_RET], TY_INT
    mov qword [rsp + LF_RETDECL], 0
    cmp qword [tk], T_ARROW
    jne .noret
    call next_token
    call parse_type
    mov [rsp + LF_RET], rax
    mov qword [rsp + LF_RETDECL], 1
    test eax, 0xFF00
    jnz .noret
    cmp al, TY_STRUCT
    jne .noret
    ERR "a lambda cannot return a struct or tuple by value: return a pointer"
.noret:
    mov edi, T_FATARROW
    call expect
    ; ---- save the state of the function that contains the lambda
    LSTATE LSAVE
    lea rdi, [rsp + LF_ARR]
    mov rsi, defer_buf
    mov ecx, 2048
    rep movsb
    mov rsi, lbl_tab
    mov ecx, 2048
    rep movsb
    mov rsi, loop_stack
    mov ecx, 2048
    rep movsb
    mov rsi, loop_lbl_ptr
    mov ecx, 512
    rep movsb
    mov rsi, loop_lbl_len
    mov ecx, 256
    rep movsb
    ; ---- jump over the lambda, start its function
    mov qword [rsp + LF_OVER], 0
    lea rdi, [rsp + LF_OVER]
    CG jmp_chain
    mov rdi, [code_pos]
    mov [last_label], rdi
    mov [rsp + LF_START], rdi
    call rewind_code                    ; no peephole marker may reach into the lambda
    CG prologue
    mov dword [frame_size], 0
    mov qword [ret_chain], 0
    mov dword [defer_n], 0
    mov dword [lbl_n], 0
    mov dword [blk_nest], 0
    mov dword [loop_sp], 0
    mov dword [cur_static], 1           ; no 'this'
    mov qword [stmt_lbl_ptr], 0
    mov dword [stmt_lbl_len], 0
    mov qword [pend_lbl_ptr], 0
    mov dword [pend_lbl_len], 0
    mov dword [fn_body_flag], 0
    inc dword [lam_depth]
    mov eax, [sym_count]
    mov [lam_sym_base], eax
    mov rax, [rsp + LF_RET]
    mov [ret_type], rax
    ; the parameters are locals; parameter i of n is at [fp + 16 + slot * (n-1-i)]
    xor r12d, r12d
.mp:
    cmp r12d, ebx
    jae .mpd
    mov rdi, [rsp + LF_PNAME + r12*8]
    mov rsi, [rsp + LF_PNLEN + r12*8]
    mov edx, S_LOCAL
    call sym_new
    mov rdx, [rsp + LF_PTYPE + r12*8]
    mov [rax+SYM_TYPE], rdx
    test edx, 0xFF00
    jnz .mp1
    cmp dl, TY_STRUCT
    jne .mp1
    or dword [rax+SYM_FLAGS], F_BYREF
.mp1:
    mov ecx, ebx
    dec ecx
    sub ecx, r12d
    imul ecx, [slot_bytes]
    add ecx, 16
    movsxd rcx, ecx
    mov [rax+SYM_VAL], rcx
    inc r12d
    jmp .mp
.mpd:
    ; ---- the body
    cmp qword [tk], '{'
    je .block
    call parse_assign
    call to_rvalue
    mov rax, [e_type]
    test eax, 0xFF00
    jnz .e1
    cmp al, TY_STRUCT
    jne .e1
    ERR "a lambda cannot return a struct or tuple by value: return a pointer"
.e1:
    cmp qword [rsp + LF_RETDECL], 0
    je .finish
    mov rdi, [rsp + LF_RET]
    call coerce_to                      ; (double x) -> double => x * 2  :  the value is converted to the declared result type
    mov rdi, [rsp + LF_RET]
    call emit_normalize
    jmp .finish
.block:
    mov dword [fn_body_flag], 1
    call parse_block
    call lbl_check
    xor edi, edi
    CG imm_a
.finish:
    mov rdi, [ret_chain]
    call patch_here
    CG epilogue
    mov edi, [frame_size]
    add edi, 15
    and edi, -16
    CG set_frame
    ; ---- restore the state of the enclosing function
    lea rsi, [rsp + LF_ARR]
    mov rdi, defer_buf
    mov ecx, 2048
    rep movsb
    mov rdi, lbl_tab
    mov ecx, 2048
    rep movsb
    mov rdi, loop_stack
    mov ecx, 2048
    rep movsb
    mov rdi, loop_lbl_ptr
    mov ecx, 512
    rep movsb
    mov rdi, loop_lbl_len
    mov ecx, 256
    rep movsb
    LSTATE LREST
    ; ---- A = the address of the lambda
    mov rdi, [rsp + LF_OVER]
    call patch_here
    mov rdi, [code_pos]
    call rewind_code
    mov rdi, [rsp + LF_START]
    CG lea_code_a
    mov qword [e_type], TY_FUNC
    mov qword [e_lval], 0
    add rsp, LF_BYTES
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
