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
    push r12
    mov ebx, [sym_count]
    mov r12d, [fn_body_flag]
    mov dword [fn_body_flag], 0
    inc dword [blk_nest]
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
    test r12d, r12d
    jz .e1
    cmp dword [defer_n], 0
    je .e1
    call emit_defers                    ; falling off the end of the function body
.e1:
    mov edi, '}'
    call expect
    dec dword [blk_nest]
    mov [sym_count], ebx
    pop r12
    pop rbx
    ret

; defer expression;   runs when the function returns (last deferred, first run). Only directly in a function body.
parse_defer:
    cmp dword [blk_nest], 1
    je .ok
    ERR "defer is only allowed directly in a function body"
.ok:
    mov eax, [defer_n]
    cmp eax, 16
    jb .room
    ERR "too many defer statements in one function (16)"
.room:
    call next_token
    mov eax, [defer_n]
    shl eax, 7
    lea rdi, [defer_buf + rax]
    call lex_save
    inc dword [defer_n]
    jmp skip_to_semi

; emit_defers: compiles the deferred expressions again, last one first (the value in A is the caller's business)
emit_defers:
    push rbx
    mov ebx, [defer_n]
.l: test ebx, ebx
    jz .d
    dec ebx
    sub rsp, 128
    mov rdi, rsp
    call lex_save
    mov eax, ebx
    shl eax, 7
    lea rsi, [defer_buf + rax]
    call lex_restore
    call parse_expr
    call discard_result
    mov rsi, rsp
    call lex_restore
    add rsp, 128
    jmp .l
.d: pop rbx
    ret

parse_stmt:
    STACKCHK
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
    cmp eax, K_DEFER
    je parse_defer
    cmp eax, K_BREAK
    je parse_break
    cmp eax, K_CONTINUE
    je parse_continue
    cmp eax, K_SWITCH
    je parse_switch
    cmp eax, K_CONST
    je parse_local_const
    cmp eax, K_TYPEDEF
    je parse_typedef
    cmp eax, K_STATIC
    je parse_static_stmt
    cmp eax, ';'
    je .empty
    cmp eax, K_PUBLIC
    je .badmod
    cmp eax, K_PRIVATE
    je .badmod
    cmp eax, K_ASM
    je parse_asm_stmt
    call is_type_start
    test eax, eax
    jnz parse_local_decl
    call parse_expr
    call discard_result
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
    mov rdi, rbx
    call cond_jz
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
    mov rdi, rsp
    CG jmp_chain
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
    CG jmp_back
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
    mov rdi, rbx
    CG jnz_back
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
    push r14
    push r15
    call next_token
    mov edi, '('
    call expect
    mov r13d, [sym_count]
    cmp qword [tk], T_ID
    jne .notrange
    mov rax, [tk_ptr]
    mov [rng_name], rax
    mov eax, [tk_len]
    mov [rng_nlen], eax
    sub rsp, 128
    mov rdi, rsp
    call lex_save
    call next_token
    cmp qword [tk], T_ID
    jne .norange
    cmp dword [tk_len], 2
    jne .norange
    mov rax, [tk_ptr]
    cmp word [rax], 0x6E69              ; "in"
    jne .norange
    add rsp, 128
    jmp .range
.norange:
    mov rsi, rsp
    call lex_restore
    add rsp, 128
.notrange:
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
    mov rdi, r12
    call cond_jz
.nocond:
    mov edi, ';'
    call expect
    push 0
    mov rdi, rsp
    CG jmp_chain
    mov rax, [code_pos]
    mov [r12+16], rax
    cmp qword [tk], ')'
    je .noinc
    call parse_expr
    call discard_result
.noinc:
    mov edi, ')'
    call expect
    mov rdi, rbx
    CG jmp_back
    pop rdi
    call patch_here
    call parse_stmt
    mov rdi, [r12+16]
    CG jmp_back
    mov rdi, [r12]
    call patch_here
    call loop_pop
    mov [sym_count], r13d
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; for (i in start..end) statement      for (i in start..=end) statement      (i is a new int, end is evaluated once)
.range:
    call next_token                     ; past 'in'
    add dword [frame_size], 16
    mov r14d, [frame_size]
    neg r14
    lea r15, [r14 + 8]                  ; the hidden slot for the end value
    call parse_assign
    call to_rvalue
    mov edi, TY_INT
    call coerce_to
    mov edi, r14d
    mov esi, TY_INT
    call store_local_typed
    cmp qword [tk], T_RANGE
    je .r1
    ERR "expected '..' in a range loop"
.r1:
    call next_token
    xor ebx, ebx
    cmp qword [tk], '='
    jne .r2
    mov ebx, 1                          ; inclusive
    call next_token
.r2:
    call parse_assign
    call to_rvalue
    mov edi, TY_INT
    call coerce_to
    test ebx, ebx
    jz .r3
    mov edi, 1
    CG add_imm_a
.r3:
    mov edi, r15d
    mov esi, TY_INT
    call store_local_typed
    mov edi, ')'
    call expect
    mov rdi, [rng_name]
    mov esi, [rng_nlen]
    mov edx, S_LOCAL
    call sym_new
    mov qword [rax+SYM_TYPE], TY_INT
    mov [rax+SYM_VAL], r14
    mov rbx, [code_pos]
    xor edi, edi
    xor esi, esi
    call loop_push
    mov r12, rax
    mov edi, r14d
    CG load_local_a
    mov edi, r15d
    CG load_local_b
    CG cmp_lt
    mov rdi, r12
    call cond_jz
    push 0
    mov rdi, rsp
    CG jmp_chain
    mov rax, [code_pos]
    mov [r12+16], rax
    mov edi, r14d
    CG load_local_a
    mov edi, 1
    CG add_imm_a
    mov edi, r14d
    CG store_local_a
    mov rdi, rbx
    CG jmp_back
    pop rdi
    call patch_here
    call parse_stmt
    mov rdi, [r12+16]
    CG jmp_back
    mov rdi, [r12]
    call patch_here
    call loop_pop
    mov [sym_count], r13d
    pop r15
    pop r14
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
    mov rax, [cur_func]
    test rax, rax
    jz .j
    mov rdi, [rax+SYM_TYPE]
    call coerce_to                      ; int <-> double
    mov rax, [cur_func]
    cmp qword [rax+SYM_TYPE], TY_BOOL
    jne .notbool
    CG tobool
    jmp .j
.notbool:
    ; a struct result is copied to the address that the caller passed as the hidden last argument
    mov rdx, [rax+SYM_TYPE]
    test edx, 0xFF00
    jnz .j
    cmp dl, TY_STRUCT
    jne .j
    mov edi, 16
    CG load_local_b
    mov rdi, rdx
    call emit_store_type                ; the copy leaves the destination address in A
    jmp .j
.void:
    xor edi, edi
    CG imm_a
.j:
    mov edi, ';'
    call expect
    cmp dword [defer_n], 0
    je .nodefer
    CG push_a
    call emit_defers
    CG pop_a
.nodefer:
    mov rdi, ret_chain
    CG jmp_chain
    ret

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
    mov rdi, rax
    CG jmp_chain
    ret

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
    CG jmp_back
    ret
.chain:
    lea rdi, [rdx+8]
    CG jmp_chain
    ret

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
    mov edi, ebx
    CG store_local_a
    xor edi, edi
    mov esi, 1
    call loop_push
    mov r12, rax
    mov r13d, [case_sp]
    push 0
    push 0
    mov rdi, rsp
    CG jmp_chain
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
    mov rdi, r12
    CG jmp_chain
    ; dispatch code
    pop rdi
    call patch_here
    mov r15d, r13d
.disp:
    cmp r15d, [case_sp]
    jae .nomore
    mov edi, ebx
    mov rsi, [case_val+r15*8]
    mov rdx, [case_pos+r15*8]
    CG case_jump
    inc r15d
    jmp .disp
.nomore:
    pop rax
    test rax, rax
    jz .nodef
    mov rdi, rax
    CG jmp_back
    jmp .end
.nodef:
    mov rdi, r12
    CG jmp_chain
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
    mov [init_count], rax
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
    mov rdi, rbx
    call coerce_to
    mov edi, r14d
    mov rsi, rbx
    call store_local_typed
    jmp .next
.zero:
    mov edi, r14d
    mov esi, 8
    CG zero_local
    jmp .next
.agg:
    mov edi, r14d
    mov esi, r15d
    CG zero_local
    bt rbx, TF_ARRAY_BIT
    jnc .notarr
    cmp qword [tk], '='
    jne .next
    call next_token
    mov rdi, rbx
    mov rsi, r14
    mov rdx, [init_count]
    call init_elem
    jmp .next
.notarr:
    mov rdi, rbx
    call type_vptr
    test eax, eax
    jz .novp
    mov edi, r14d
    CG lea_local_a
    mov edi, ebx
    shr edi, 16
    call emit_vptr_init
.novp:
    cmp qword [tk], '('
    je .ctor
    cmp qword [tk], '='
    jne .next
    call next_token
    cmp qword [tk], '{'
    jne .nolist
    mov rdi, rbx
    mov rsi, r14
    xor edx, edx
    call init_local_list
    jmp .next
.nolist:
    call parse_assign
    call to_rvalue
    mov edi, r14d
    CG lea_local_b
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
    mov edi, r14d
    CG lea_local_a
    CG push_a
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
    cmp rbx, TY_DOUBLE
    je .dconst
    cmp rbx, TY_INT
    jne .iconst
    call peek_is_flt
    test eax, eax
    jz .iconst
    mov rbx, TY_DOUBLE
.dconst:
    call const_double
    xor edx, edx
    jmp .chave
.iconst:
    call const_expr
.chave:
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

; typedef Type Name;   (top level in pass 1, or inside a function body)
parse_typedef:
    push rbx
    push r12
    push r13
    call next_token
    call parse_type
    mov rbx, rax
    cmp qword [tk], T_ID
    je .n1
    ERR "expected a name for the new type"
.n1:
    mov r12, [tk_ptr]
    mov r13d, [tk_len]
    call next_token
    mov edi, ';'
    call expect
    mov rdi, r12
    mov esi, r13d
    mov edx, S_TYPEDEF
    call sym_new
    mov [rax+SYM_TYPE], rbx
    pop r13
    pop r12
    pop rbx
    ret

; static Type name [= constant] [, name ...];   a local variable that keeps its value between calls
; static if (constant) { statements } else { ... }   or   static TYPE name ...;
parse_static_stmt:
    call next_token
    cmp qword [tk], K_IF
    je parse_static_if_stmt
parse_static_local:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call parse_type
    mov r12, rax                        ; element type
    cmp qword [tk], T_ID
    je .name
    ERR "expected a variable name"
.name:
    mov rax, [tk_ptr]
    mov [agg_mname], rax
    mov eax, [tk_len]
    mov [agg_mnlen], eax
    call next_token
    mov rbx, r12
    xor r14d, r14d                      ; array element count (0 = scalar)
    cmp qword [tk], '['
    jne .noarr
    call next_token
    call const_expr
    test rax, rax
    jg .a1
    ERR "array size must be positive"
.a1:
    mov r14, rax
    mov edi, ']'
    call expect
    add rbx, TY_PTR1
    bts rbx, TF_ARRAY_BIT
    mov rdi, r12
    call type_size
    imul rax, r14
    jmp .sized
.noarr:
    mov rdi, rbx
    call type_size
.sized:
    mov r15, rax
    cmp r15, 8
    jae .big
    mov r15d, 8
.big:
    cmp qword [tk], '='
    je .init
    mov rdi, r15
    mov esi, 8
    call bss_alloc
    mov r13d, eax
    mov edx, F_BSS
    jmp .reg
.init:
    call next_token
    cmp qword [tk], '{'
    je .glist
    bt rbx, TF_ARRAY_BIT
    jnc .i0
.glist:
    mov rdi, r15
    mov esi, 8
    call data_alloc
    mov r13, rax
    mov dword [init_mode], 1
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r14
    call init_elem
    mov dword [init_mode], 0
    xor edx, edx
    jmp .reg
.i0:
    call const_expr
    push rax
    push rdx
    mov rdi, 8
    mov esi, 8
    call data_alloc
    mov r13, rax
    pop rdx
    pop rcx
    mov [data_buf+r13], rcx
    test edx, edx
    jz .i1
    mov edi, r13d
    mov esi, R_DATA64
    xor edx, edx
    call add_reloc
.i1:
    xor edx, edx
.reg:
    push rdx
    mov rdi, [agg_mname]
    mov esi, [agg_mnlen]
    mov edx, S_GLOBAL
    call sym_new
    pop rdx
    mov [rax+SYM_TYPE], rbx
    mov [rax+SYM_VAL], r13
    or [rax+SYM_FLAGS], edx
    mov [rax+SYM_EXTRA], r14
    cmp qword [tk], ','
    jne .end
    call next_token
    cmp qword [tk], T_ID
    je .name
    ERR "expected a variable name"
.end:
    mov edi, ';'
    call expect
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; asm(...) { ... }   as a statement: the closing semicolon is optional
parse_asm_stmt:
    call parse_expr
    call discard_result
    cmp qword [tk], ';'
    jne .out
    jmp next_token
.out:
    ret

; static if (constant) { statements } [else { statements } | else static if (...) { ... }]   (current token 'if')
parse_static_if_stmt:
    push rbx
    call next_token
    mov edi, '('
    call expect
    call const_expr
    test rax, rax
    setnz bl
    movzx ebx, bl
    mov edi, ')'
    call expect
    cmp qword [tk], '{'
    je .blk
    ERR "expected '{' after static if (...)"
.blk:
    test ebx, ebx
    jz .skip_then
    call parse_block
    jmp .after_then
.skip_then:
    call skip_block
.after_then:
    cmp qword [tk], K_ELSE
    jne .done
    call next_token
    cmp qword [tk], K_STATIC
    je .else_static
    cmp qword [tk], '{'
    je .else_block
    ERR "expected '{' or 'static if' after else"
.else_block:
    test ebx, ebx
    jnz .skip_else
    call parse_block
    jmp .done
.skip_else:
    call skip_block
    jmp .done
.else_static:
    call next_token
    cmp qword [tk], K_IF
    je .nested
    ERR "expected 'if' after 'else static'"
.nested:
    test ebx, ebx
    jnz .skip_nested
    call parse_static_if_stmt
    jmp .done
.skip_nested:
    call skip_static_if
.done:
    pop rbx
    ret

; ---- initializer lists ---------------------------------------------------------------------------------------------------
; init_elem: rdi = type of the object, rsi = frame offset of its first byte, rdx = element count (arrays).
; Initializes one object from the current tokens: a {...} list, a string for a char array, or an ordinary expression.
; The object has been zeroed before, so values that are left out stay 0.
init_elem:
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp qword [tk], '{'
    jne .nobrace
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call init_local_list
    jmp .out
.nobrace:
    bt rbx, TF_ARRAY_BIT
    jnc .value
    cmp qword [tk], T_STR
    je .str
    ERR "an array is initialized with a {...} list (or a string for a char array)"
.str:
    mov rax, rbx
    btr rax, TF_ARRAY_BIT
    sub rax, TY_PTR1
    cmp rax, TY_CHAR
    je .s1
    ERR "only a char array can be initialized with a string"
.s1:
    mov rcx, [tk_len]
    cmp rcx, r13
    jbe .s2
    ERR "the string is longer than the array"
.s2:
    xor r14d, r14d
.sl:
    cmp r14, [tk_len]
    jae .sdone
    mov rax, [tk_ptr]
    cmp dword [init_mode], 0
    je .sl_code
    movzx eax, byte [rax + r14]
    lea rcx, [r12 + r14]
    mov [data_buf + rcx], al
    inc r14
    jmp .sl
.sl_code:
    movzx edi, byte [rax + r14]
    call gen_imm_a
    lea edi, [r12 + r14]
    CG lea_local_b
    CG store1
    inc r14
    jmp .sl
.sdone:
    call next_token
    jmp .out
.value:
    cmp dword [init_mode], 0
    jne .dvalue
    call parse_assign
    call to_rvalue
    mov rdi, rbx
    call coerce_to
    mov edi, r12d
    CG lea_local_b
    mov rdi, rbx
    call emit_store_type
    jmp .out
.dvalue:
    cmp rbx, TY_DOUBLE
    jne .dint
    call const_double
    xor edx, edx
    jmp .dgot
.dint:
    call const_expr
.dgot:
    push rax
    push rdx
    mov rdi, rbx
    call type_ls
    pop rdx
    pop rcx
    cmp eax, 8
    je .dq
    cmp eax, 1
    je .db
    ERR "a struct value cannot be used here, use a {...} list"
.db:
    mov [data_buf + r12], cl
    jmp .out
.dq:
    mov [data_buf + r12], rcx
    test edx, edx
    jz .out
    mov edi, r12d
    mov esi, R_DATA64
    xor edx, edx
    call add_reloc
.out:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; init_local_list: rdi = type (struct or array), rsi = frame offset, rdx = element count (arrays). Current token: '{'
init_local_list:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov rbx, rdi
    mov r12, rsi
    mov r14, rdx
    call next_token
    bt rbx, TF_ARRAY_BIT
    jc .array
    test ebx, 0xFF00
    jnz .bad
    cmp bl, TY_STRUCT
    je .struct
.bad:
    ERR "this type cannot be initialized with a {...} list"
.struct:
    mov edi, ebx
    shr edi, 16
    and edi, 0xFFFF
    call struct_ptr
    mov r15, rax
    mov r14d, [r15+ST_NFIELDS]
    mov eax, [r15+ST_FIRST]
    shl rax, 5
    add rax, field_tab
    mov r13, rax
.sloop:
    cmp qword [tk], '}'
    je .close
    test r14d, r14d
    jnz .s1
    ERR "too many values in the initializer list"
.s1:
    mov rdi, [r13+FD_TYPE]
    mov esi, [r13+FD_OFFSET]
    add rsi, r12
    xor edx, edx
    bt rdi, TF_ARRAY_BIT
    jnc .s2
    cmp r14d, 1
    jbe .last
    mov ecx, [r13+FD_SIZEOF+FD_OFFSET]
    jmp .bnd
.last:
    mov ecx, [r15+ST_SIZE]
.bnd:
    sub ecx, [r13+FD_OFFSET]
    push rcx
    push rdi
    push rsi
    btr rdi, TF_ARRAY_BIT
    sub rdi, TY_PTR1
    call type_size
    mov r8, rax
    pop rsi
    pop rdi
    pop rax
    xor edx, edx
    div r8
    mov rdx, rax
.s2:
    call init_elem
    add r13, FD_SIZEOF
    dec r14d
    cmp qword [tk], ','
    jne .close
    call next_token
    jmp .sloop
.array:
    mov r15, rbx
    btr r15, TF_ARRAY_BIT
    sub r15, TY_PTR1
    mov rdi, r15
    call type_size
    mov r13, rax
    xor ebp, ebp
.aloop:
    cmp qword [tk], '}'
    je .close
    cmp rbp, r14
    jb .a1
    ERR "too many values in the initializer list"
.a1:
    mov rsi, rbp
    imul rsi, r13
    add rsi, r12
    mov rdi, r15
    xor edx, edx
    call init_elem
    inc rbp
    cmp qword [tk], ','
    jne .close
    call next_token
    jmp .aloop
.close:
    mov edi, '}'
    call expect
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
