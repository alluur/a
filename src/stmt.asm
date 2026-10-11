; =============================================================================
;  stmt.asm - statements and local declarations
; =============================================================================
section .text

; ---- loop / switch bookkeeping --------------------------------------------------
; loop record (32 bytes): +0 break chain, +8 continue chain, +16 continue target
; (0 = use chain), +24 kind (0 loop, 1 switch)

; loop_push: rdi = continue target (0 for chain), esi = kind -> rax = record
loop_push:
    mov eax, [loop_sp]
    cmp eax, MAXLOOP
    jae .full
    inc dword [loop_sp]
    shl rax, 5
    add rax, loop_stack
    mov qword [rax], 0
    mov qword [rax+8], 0
    mov [rax+16], rdi
    mov [rax+24], rsi
    ret
.full:
    ERR "statements are nested too deeply"

loop_pop:
    dec dword [loop_sp]
    ret

; ---- blocks -----------------------------------------------------------------------
parse_block:
    push rbx
    mov ebx, [sym_count]
    mov edi, '{'
    call expect
.l:
    cmp qword [tk], '}'
    je .e
    cmp qword [tk], T_EOF
    jne .s
    ERR "unexpected end of file, missing '}'"
.s:
    call parse_stmt
    jmp .l
.e:
    mov edi, '}'
    call expect
    mov [sym_count], ebx
    pop rbx
    ret

parse_stmt:
    mov eax, [tk]
    cmp eax, '{'
    je parse_block
    cmp eax, K_IF
    je parse_if
    cmp eax, K_WHILE
    je parse_while
    cmp eax, K_DO
    je parse_do
    cmp eax, K_FOR
    je parse_for
    cmp eax, K_RETURN
    je parse_return
    cmp eax, K_BREAK
    je parse_break
    cmp eax, K_CONTINUE
    je parse_continue
    cmp eax, K_SWITCH
    je parse_switch
    cmp eax, K_CONST
    je parse_local_const
    cmp eax, ';'
    je .empty
    cmp eax, K_PUBLIC
    je .badmod
    cmp eax, K_PRIVATE
    je .badmod
    call is_type_start
    test eax, eax
    jnz parse_local_decl
    call parse_expr
    mov edi, ';'
    jmp expect
.empty:
    jmp next_token
.badmod:
    ERR "access modifiers are only allowed on declarations of modules and classes"

; condition in parentheses -> test + jz emitted; edi = address of chain head
parse_cond_jz:
    push rbx
    mov rbx, rdi
    mov edi, '('
    call expect
    call parse_expr
    call to_rvalue
    mov edi, ')'
    call expect
    EM 0x48, 0x85, 0xC0, 0x0F, 0x84
    mov rdi, rbx
    call chain_slot
    pop rbx
    ret

parse_if:
    call next_token
    push 0
    mov rdi, rsp
    call parse_cond_jz
    call parse_stmt
    cmp qword [tk], K_ELSE
    jne .noelse
    call next_token
    push 0
    EM 0xE9
    mov rdi, rsp
    call chain_slot
    mov rdi, [rsp+8]
    call patch_here
    call parse_stmt
    pop rdi
    call patch_here
    add rsp, 8
    ret
.noelse:
    pop rdi
    jmp patch_here

parse_while:
    push rbx
    push r12
    call next_token
    mov rbx, [code_pos]
    mov rdi, rbx
    xor esi, esi
    call loop_push
    mov r12, rax
    mov rdi, r12
    call parse_cond_jz
    call parse_stmt
    mov rdi, rbx
    call emit_jmp_back
    mov rdi, [r12]
    call patch_here
    call loop_pop
    pop r12
    pop rbx
    ret

parse_do:
    push rbx
    push r12
    call next_token
    mov rbx, [code_pos]
    xor edi, edi
    xor esi, esi
    call loop_push
    mov r12, rax
    call parse_stmt
    mov rdi, [r12+8]
    call patch_here
    cmp qword [tk], K_WHILE
    je .w
    ERR "expected 'while' after the body of a do loop"
.w:
    call next_token
    mov edi, '('
    call expect
    call parse_expr
    call to_rvalue
    mov edi, ')'
    call expect
    mov edi, ';'
    call expect
    EM 0x48, 0x85, 0xC0, 0x0F, 0x85
    mov rdi, rbx
    sub rdi, [code_pos]
    sub rdi, 4
    call emit_d
    mov rdi, [r12]
    call patch_here
    call loop_pop
    pop r12
    pop rbx
    ret

parse_for:
    push rbx
    push r12
    push r13
    call next_token
    mov edi, '('
    call expect
    mov r13d, [sym_count]
    cmp qword [tk], ';'
    jne .init
    call next_token
    jmp .cond
.init:
    call is_type_start
    test eax, eax
    jz .initexpr
    call parse_local_decl
    jmp .cond
.initexpr:
    call parse_expr
    mov edi, ';'
    call expect
.cond:
    mov rbx, [code_pos]
    xor edi, edi
    xor esi, esi
    call loop_push
    mov r12, rax
    cmp qword [tk], ';'
    je .nocond
    call parse_expr
    call to_rvalue
    EM 0x48, 0x85, 0xC0, 0x0F, 0x84
    mov rdi, r12
    call chain_slot
.nocond:
    mov edi, ';'
    call expect
    push 0
    EM 0xE9
    mov rdi, rsp
    call chain_slot
    mov rax, [code_pos]
    mov [r12+16], rax
    cmp qword [tk], ')'
    je .noinc
    call parse_expr
.noinc:
    mov edi, ')'
    call expect
    mov rdi, rbx
    call emit_jmp_back
    pop rdi
    call patch_here
    call parse_stmt
    mov rdi, [r12+16]
    call emit_jmp_back
    mov rdi, [r12]
    call patch_here
    call loop_pop
    mov [sym_count], r13d
    pop r13
    pop r12
    pop rbx
    ret

parse_return:
    call next_token
    cmp qword [tk], ';'
    je .void
    call parse_expr
    call to_rvalue
    jmp .j
.void:
    EM 0x31, 0xC0
.j:
    mov edi, ';'
    call expect
    EM 0xE9
    mov rdi, ret_chain
    jmp chain_slot

parse_break:
    call next_token
    mov edi, ';'
    call expect
    mov eax, [loop_sp]
    test eax, eax
    jnz .ok
    ERR "'break' outside of a loop or switch"
.ok:
    dec eax
    shl rax, 5
    add rax, loop_stack
    push rax
    EM 0xE9
    pop rdi
    jmp chain_slot

parse_continue:
    call next_token
    mov edi, ';'
    call expect
    mov eax, [loop_sp]
.find:
    test eax, eax
    jnz .chk
    ERR "'continue' outside of a loop"
.chk:
    dec eax
    mov rdx, rax
    shl rdx, 5
    add rdx, loop_stack
    cmp qword [rdx+24], 0
    jne .find
    cmp qword [rdx+16], 0
    je .chain
    mov rdi, [rdx+16]
    jmp emit_jmp_back
.chain:
    push rdx
    EM 0xE9
    pop rdi
    add rdi, 8
    jmp chain_slot

; ---- switch ------------------------------------------------------------------------
; switch (expr) { case C: ... default: ... }
; The value is kept in a hidden local; the case comparisons are emitted after
; the body and jump back into it.
parse_switch:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call next_token
    mov edi, '('
    call expect
    call parse_expr
    call to_rvalue
    mov edi, ')'
    call expect
    add dword [frame_size], 8
    mov ebx, [frame_size]
    neg rbx
    EM 0x48, 0x89, 0x85
    mov edi, ebx
    call emit_d
    xor edi, edi
    mov esi, 1
    call loop_push
    mov r12, rax
    mov r13d, [case_sp]
    push 0
    EM 0xE9
    push 0
    mov rdi, rsp
    call chain_slot
    mov edi, '{'
    call expect
    mov r14d, [sym_count]
.items:
    mov eax, [tk]
    cmp eax, '}'
    je .done
    cmp eax, K_CASE
    je .case
    cmp eax, K_DEFAULT
    je .default
    cmp eax, T_EOF
    jne .stmt
    ERR "unexpected end of file in switch"
.stmt:
    call parse_stmt
    jmp .items
.case:
    call next_token
    call const_expr
    mov r15, rax
    mov edi, ':'
    call expect
    mov eax, [case_sp]
    cmp eax, 1024
    jb .c1
    ERR "too many case labels"
.c1:
    inc dword [case_sp]
    mov [case_val+rax*8], r15
    mov rcx, [code_pos]
    mov [case_pos+rax*8], rcx
    jmp .items
.default:
    call next_token
    mov edi, ':'
    call expect
    cmp qword [rsp+8], 0
    je .d1
    ERR "duplicate 'default' label"
.d1:
    mov rax, [code_pos]
    mov [rsp+8], rax
    jmp .items
.done:
    call next_token
    mov [sym_count], r14d
    ; end of the body falls out of the switch
    EM 0xE9
    lea rdi, [r12]
    call chain_slot
    ; dispatch code
    pop rdi
    call patch_here
    mov r15d, r13d
.disp:
    cmp r15d, [case_sp]
    jae .nomore
    EM 0x48, 0x8B, 0x85
    mov edi, ebx
    call emit_d
    EM 0x48, 0x3D
    mov edi, [case_val+r15*8]
    call emit_d
    EM 0x0F, 0x84
    mov rdi, [case_pos+r15*8]
    sub rdi, [code_pos]
    sub rdi, 4
    call emit_d
    inc r15d
    jmp .disp
.nomore:
    pop rax
    test rax, rax
    jz .nodef
    mov rdi, rax
    call emit_jmp_back
    jmp .end
.nodef:
    EM 0xE9
    lea rdi, [r12]
    call chain_slot
.end:
    mov rdi, [r12]
    call patch_here
    mov [case_sp], r13d
    call loop_pop
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---- local declarations ------------------------------------------------------------
parse_local_decl:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call parse_type
    mov r12, rax
    cmp rax, TY_VOID
    jne .decl
    ERR "a variable cannot have type void"
.decl:
    cmp qword [tk], T_ID
    je .d1
    ERR "expected a variable name"
.d1:
    mov r13, [tk_ptr]
    mov r14d, [tk_len]
    call next_token
    mov rbx, r12
    cmp qword [tk], '['
    jne .scalar
    call next_token
    call const_expr
    test rax, rax
    jg .a1
    ERR "array size must be positive"
.a1:
    mov r15, rax
    mov edi, ']'
    call expect
    mov rdi, r12
    call type_size
    imul rax, r15
    add rbx, TY_PTR1
    bts rbx, TF_ARRAY_BIT
    jmp .size
.scalar:
    mov rdi, rbx
    call type_size
.size:
    add rax, 7
    and rax, -8
    mov r15, rax
    add [frame_size], eax
    mov rdi, r13
    mov esi, r14d
    mov edx, S_LOCAL
    call sym_new
    mov [rax+SYM_TYPE], rbx
    mov r14d, [frame_size]
    neg r14
    mov [rax+SYM_VAL], r14
    ; --- aggregate or scalar?
    bt rbx, TF_ARRAY_BIT
    jc .agg
    mov rdi, rbx
    call type_ls
    test eax, eax
    jz .agg
    ; scalar
    cmp qword [tk], '='
    jne .zero
    call next_token
    call parse_assign
    call to_rvalue
    EM 0x48, 0x8D, 0x8D
    mov edi, r14d
    call emit_d
    mov rdi, rbx
    call emit_store_type
    jmp .next
.zero:
    EM 0x48, 0xC7, 0x85
    mov edi, r14d
    call emit_d
    EM 0, 0, 0, 0
    jmp .next
.agg:
    EM 0x48, 0x8D, 0xBD
    mov edi, r14d
    call emit_d
    EM 0x31, 0xC0, 0xB9
    mov edi, r15d
    call emit_d
    EM 0xF3, 0xAA
    bt rbx, TF_ARRAY_BIT
    jc .next
    cmp qword [tk], '('
    je .ctor
    cmp qword [tk], '='
    jne .next
    call next_token
    call parse_assign
    call to_rvalue
    EM 0x48, 0x8D, 0x8D
    mov edi, r14d
    call emit_d
    mov rdi, rbx
    call emit_store_type
    jmp .next
.ctor:
    mov rdi, rbx
    shr rdi, 16
    and edi, 0xFFFF
    call struct_find_ctor
    test rax, rax
    jnz .c1
    ERR "this class has no constructor"
.c1:
    mov r15, rax
    EM 0x48, 0x8D, 0x85
    mov edi, r14d
    call emit_d
    EM 0x50
    mov rdi, r15
    mov esi, 1
    call gen_call
.next:
    cmp qword [tk], ','
    jne .end
    call next_token
    jmp .decl
.end:
    mov edi, ';'
    call expect
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---- const declaration (global when pass 1, local inside functions) -------------
; const NAME = expr;   const TYPE NAME = expr;
parse_const_decl:
    push rbx
    push r12
    push r13
    call next_token
    mov rbx, TY_INT
    call is_type_start
    test eax, eax
    jz .named
    call parse_type
    mov rbx, rax
.named:
    cmp qword [tk], T_ID
    je .n1
    ERR "expected a constant name"
.n1:
    mov r12, [tk_ptr]
    mov r13d, [tk_len]
    call next_token
    mov edi, '='
    call expect
    call const_expr
    push rax
    push rdx
    mov edi, ';'
    call expect
    mov rdi, r12
    mov esi, r13d
    mov edx, S_CONST
    call sym_new
    pop rdx
    pop rcx
    mov [rax+SYM_VAL], rcx
    mov [rax+SYM_TYPE], rbx
    test edx, edx
    jz .out
    or dword [rax+SYM_FLAGS], F_STRCONST
    mov qword [rax+SYM_TYPE], TY_CHAR | TY_PTR1
.out:
    pop r13
    pop r12
    pop rbx
    ret

parse_local_const:
    jmp parse_const_decl
