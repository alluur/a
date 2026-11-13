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
    mov edx, eax
    ; a label in front of the statement ("outer: for (...)") names this loop for  break outer;  continue outer;
    mov rcx, [stmt_lbl_ptr]
    mov [loop_lbl_ptr + rdx*8], rcx
    mov ecx, [stmt_lbl_len]
    mov [loop_lbl_len + rdx*4], ecx
    mov qword [stmt_lbl_ptr], 0
    mov dword [stmt_lbl_len], 0
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
    mov qword [tup_expect_tok], 0       ; (a tuple expectation lives only within the statement that made it)
    mov rax, [pend_lbl_ptr]             ; the label (if any) that stands directly in front of this statement
    mov [stmt_lbl_ptr], rax
    mov eax, [pend_lbl_len]
    mov [stmt_lbl_len], eax
    mov qword [pend_lbl_ptr], 0
    mov dword [pend_lbl_len], 0
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
    cmp eax, K_FOREACH
    je parse_foreach
    cmp eax, K_RETURN
    je parse_return
    cmp eax, K_EXTERN
    je skip_to_semi
    cmp eax, K_DEFER
    je parse_defer
    cmp eax, K_GOTO
    je parse_goto
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
    cmp eax, T_ID
    jne .notlabel
    mov rdi, w_static_assert
    call tk_is_word
    test eax, eax
    jnz parse_static_assert
    mov rax, [tk_ptr]
    mov [lbl_tmp], rax
    mov eax, [tk_len]
    mov [lbl_tlen], eax
    sub rsp, 128
    mov rdi, rsp
    call lex_save
    call next_token
    cmp qword [tk], ':'
    jne .nolabel
    add rsp, 128
    mov rsi, [lbl_tmp]
    mov edx, [lbl_tlen]
    call lbl_get
    cmp dword [rax+LB_DEF], 0
    je .newlabel
    ERR "duplicate label"
.newlabel:
    mov dword [rax+LB_DEF], 1
    mov rcx, [code_pos]
    mov [rax+LB_POS], rcx
    mov rdi, [rax+LB_CHAIN]
    mov qword [rax+LB_CHAIN], 0
    call patch_here
    call next_token                     ; past ':'
    cmp qword [tk], '}'
    je .lblend
    mov rax, [lbl_tmp]
    mov [pend_lbl_ptr], rax
    mov eax, [lbl_tlen]
    mov [pend_lbl_len], eax
    jmp parse_stmt
.lblend:
    ret
.nolabel:
    mov rsi, rsp
    call lex_restore
    add rsp, 128
.notlabel:
    cmp qword [tk], '('
    jne .nottuple
    call tuple_stmt_kind                ; (a, b) = value;   (int a, int b) = value;
    test eax, eax
    jnz parse_tuple_stmt
.nottuple:
    call is_var_start
    test eax, eax
    jnz parse_var_decl
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
    call next_token
    mov edi, '('
    call expect
    mov r13d, [sym_count]
    cmp qword [tk], ';'
    jne .init
    call next_token
    jmp .cond
.init:
    cmp qword [tk], '('
    jne .init0
    call tuple_stmt_kind                ; for ((a, b) = (0, 1); ...)
    test eax, eax
    jz .init0
    call parse_tuple_stmt               ; (it consumes the ';')
    jmp .cond
.init0:
    call is_var_start
    test eax, eax
    jz .init_t
    call parse_var_decl
    jmp .cond
.init_t:
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
    cmp qword [tk], '('
    jne .incexpr
    call tuple_stmt_kind                ; for (...; ...; (a, b) = (b, a + b))
    test eax, eax
    jz .incexpr
    mov dword [tup_noterm], 1
    call parse_tuple_stmt               ; (the ')' of the for is not consumed)
    mov dword [tup_noterm], 0
    jmp .noinc
.incexpr:
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
    pop r13
    pop r12
    pop rbx
    ret

parse_return:
    call next_token
    cmp qword [tk], ';'
    je .void
    cmp qword [cur_func], 0
    je .nx
    mov rdi, [ret_type]
    call tuple_expect_here              ; return (a, b);  in a function that returns a tuple
.nx:
    call parse_expr
    call to_rvalue
    cmp qword [cur_func], 0
    je .j
    mov rdi, [ret_type]
    call coerce_to                      ; int <-> double
    mov rdi, [ret_type]
    call tuple_check
    cmp qword [ret_type], TY_BOOL
    jne .notbool
    CG tobool
    jmp .j
.notbool:
    mov rdi, [ret_type]
    call emit_normalize                 ; a narrow result is returned truncated and extended
    ; a struct result is copied to the address that the caller passed as the hidden last argument
    mov rdx, [ret_type]
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

; find_loop_label: rsi = name, edx = length -> rax = the record of the innermost loop or switch that has this label (0 = none)
find_loop_label:
    mov ecx, [loop_sp]
.l:
    test ecx, ecx
    jz .none
    dec ecx
    cmp [loop_lbl_len + rcx*4], edx
    jne .l
    mov rdi, [loop_lbl_ptr + rcx*8]
    test rdi, rdi
    jz .l
    push rsi
    push rcx
    mov r8d, edx
    mov r9, rsi
    mov rsi, r9
    mov ecx, r8d
    repe cmpsb
    pop rcx
    pop rsi
    jne .l
    mov rax, rcx
    shl rax, 5
    add rax, loop_stack
    ret
.none:
    xor eax, eax
    ret

parse_break:
    call next_token
    cmp qword [tk], T_ID
    jne .plain
    mov rsi, [tk_ptr]
    mov edx, [tk_len]
    call find_loop_label
    test rax, rax
    jnz .lab1
    mov edi, msg_nolabel
    call fatal_error_tok
.lab1:
    push rax
    call next_token
    mov edi, ';'
    call expect
    pop rdi
    CG jmp_chain
    ret
.plain:
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
    cmp qword [tk], T_ID
    jne .plain
    mov rsi, [tk_ptr]
    mov edx, [tk_len]
    call find_loop_label
    test rax, rax
    jnz .lab1
    mov edi, msg_nolabel
    call fatal_error_tok
.lab1:
    mov rdx, rax
    cmp qword [rdx+24], 0
    je .lab2
    ERR "'continue' needs a loop, this label is on a switch"
.lab2:
    push rdx
    call next_token
    mov edi, ';'
    call expect
    pop rdx
    jmp .target
.plain:
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
.target:
    cmp qword [rdx+16], 0
    je .chain
    mov rdi, [rdx+16]
    CG jmp_back
    ret
.chain:
    lea rdi, [rdx+8]
    CG jmp_chain
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
    jne .decl0
    ERR "a variable cannot have type void"
.decl0:
    mov rdi, rax
    call check_concrete                 ; no variables of an abstract class
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
    push rax
    mov rdi, rbx
    mov rsi, r15
    call type_with_len
    mov rbx, rax
    pop rax
    jmp .size
.scalar:
    mov qword [init_count], 0
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
    mov rcx, [init_count]
    mov [rax+SYM_EXTRA], rcx
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
    mov rdi, rbx
    call tuple_check
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
    mov ecx, '}'
    call init_local_list
    jmp .next
.nolist:
    mov rdi, rbx
    call tuple_expect_here              ; (int, double) t = (1, 2);
    call parse_assign
    call to_rvalue
    mov rdi, rbx
    call tuple_check
    mov rdi, rbx
    call struct_check                   ; P p = 5;  used to compile and crash
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


; ---- var: the type of a local variable is taken from its initializer ------------------------------------------------------
;   var x = expr;     var a = 1, b = "text";     for (var i = 0; ...)     foreach (var x in values)
; `var` is not a keyword: it is the declaration word only where a new name can follow it and nothing named var is in scope.
section .rodata
w_var: db "var", 0
section .text

; is_var_start: eax = 1 when the current token is the word var, not declared as anything in the current scope, followed by a name or '('
is_var_start:
    cmp qword [tk], T_ID
    jne .no
    cmp dword [tk_len], 3
    jne .no
    mov rax, [tk_ptr]
    cmp word [rax], 'va'
    jne .no
    cmp byte [rax+2], 'r'
    jne .no
    push rbx
    mov rdi, rax
    mov esi, 3
    call sym_lookup
    test rax, rax
    jnz .no1
    cmp dword [cur_class], -1
    je .look
    mov edi, [cur_class]                ; a field or method called var of the class being compiled is not the declaration word
    mov rsi, [tk_ptr]
    mov edx, 3
    call struct_find_field
    test rax, rax
    jnz .no1
    mov edi, [cur_class]
    mov rsi, [tk_ptr]
    mov edx, 3
    call struct_find_method
    test rax, rax
    jnz .no1
.look:
    sub rsp, 128
    mov rdi, rsp
    call lex_save
    call next_token
    xor ebx, ebx
    cmp qword [tk], T_ID
    je .yes
    cmp qword [tk], '('
    jne .back
.yes:
    mov ebx, 1
.back:
    mov rsi, rsp
    call lex_restore
    add rsp, 128
    mov eax, ebx
    pop rbx
    ret
.no1:
    pop rbx
.no:
    xor eax, eax
    ret

; var_declare: rdi = name pointer, esi = name length, rdx = type of the variable (the value is in A, converted to that type).
; Creates the local variable and stores A (or, for a struct, the object that A points to) into it.
var_declare:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13d, esi
    mov rbx, rdx
    mov rdi, rbx
    call check_concrete
    mov rdi, rbx
    call type_size
    add rax, 7
    and rax, -8
    jnz .sz
    mov eax, 8
.sz:
    add [frame_size], eax
    mov rdi, r12
    mov esi, r13d
    mov edx, S_LOCAL
    call sym_new
    mov qword [rax+SYM_EXTRA], 0
    mov [rax+SYM_TYPE], rbx
    mov r14d, [frame_size]
    neg r14
    mov [rax+SYM_VAL], r14
    mov rdi, rbx
    call type_ls
    test eax, eax
    jz .agg
    mov edi, r14d
    mov rsi, rbx
    call store_local_typed
    jmp .out
.agg:
    mov edi, r14d                       ; a struct or class value: A is the address of the source object, copy it
    CG lea_local_b
    mov rdi, rbx
    call emit_store_type
.out:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; parse_var_decl: the current token is `var`; reads  var name = expr {, name = expr} ;
parse_var_decl:
    push rbx
    push r12
    push r13
    call next_token
    cmp qword [tk], '('
    je .tuple
.decl:
    cmp qword [tk], T_ID
    je .d1
    ERR "expected a variable name after var"
.d1:
    mov r12, [tk_ptr]
    mov r13d, [tk_len]
    call next_token
    cmp qword [tk], '='
    je .init
    ERR "var needs an initializer: the type of the variable is taken from it (var x = value;)"
.init:
    call next_token
    cmp qword [tk], '{'
    jne .i1
    ERR "cannot infer the type of the variable from a {...} list: write the type"
.i1:
    call tuple_expect_any               ; var t = (1, "a");  a parenthesized list that starts the initializer is a tuple
    xor ebx, ebx
    cmp qword [tk], K_NULL
    jne .i2
    mov ebx, 1                          ; remember a plain null: its type (void*) says nothing
.i2:
    call parse_assign
    call to_rvalue
    mov rax, [e_type]
    cmp rax, TY_VOID
    jne .i3
    ERR "cannot infer the type of the variable: the initializer has no value (it is void)"
.i3:
    test ebx, ebx
    jz .i4
    cmp rax, TY_VOID | TY_PTR1
    jne .i4
    ERR "cannot infer the type of the variable from null: write the type, for example  char* p = null;"
.i4:
    mov rdi, r12
    mov esi, r13d
    mov rdx, [e_type]
    call var_declare
    cmp qword [tk], ','
    jne .end
    call next_token
    jmp .decl
.end:
    mov edi, ';'
    call expect
    pop r13
    pop r12
    pop rbx
    ret
.tuple:
    pop r13
    pop r12
    pop rbx
    jmp parse_var_tuple

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
    mov rdi, rbx
    call const_truncate                 ; const uint8 K = 300;  is 44
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
    cmp qword [tk], K_ENUM
    jne .plain
    call parse_typedef_enum
    pop r13
    pop r12
    pop rbx
    ret
.plain:
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
    mov rdi, rax
    call check_concrete
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
    mov rdi, rbx
    mov rsi, r14
    call type_with_len
    mov rbx, rax
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
    jc .glist
    cmp qword [tk], '('
    jne .i0
    mov rdi, rbx                        ; static (int, int) t = (5, 6);  a tuple literal of constants
    call type_is_tuple
    test eax, eax
    jz .i0
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
    mov rdi, rbx
    call struct_global_check
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
    mov ecx, '}'
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
    TY_DECAY rax
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
    mov rdi, rbx
    call tuple_expect_here              ; (int, int) a[2] = {(1, 2), (3, 4)};  a tuple literal is converted to the element type
    call parse_assign
    call to_rvalue
    mov rdi, rbx
    call coerce_to
    mov rdi, rbx
    call tuple_check
    mov rdi, rbx
    call struct_check                   ; P a[2] = {5, 6};  used to compile and crash
    mov edi, r12d
    CG lea_local_b
    mov rdi, rbx
    call emit_store_type
    jmp .out
.dvalue:
    cmp qword [tk], '('
    jne .dv0
    mov rdi, rbx
    call type_is_tuple
    test eax, eax
    jz .dv0
    mov rdi, rbx                        ; a tuple literal of constants in a global (or static) initializer: (5, 6)
    mov rsi, r12
    mov rdx, r13
    mov ecx, ')'
    call init_local_list
    jmp .out
.dv0:
    mov rdi, rbx
    call struct_global_check
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
    test eax, eax
    jz .dbad
    and eax, 7
    cmp eax, 2
    je .dw
    mov [data_buf + r12], ecx           ; int32 / uint32
    jmp .out
.dw:
    mov [data_buf + r12], cx            ; int16 / uint16
    jmp .out
.dbad:
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

; init_local_list: rdi = type (struct or array), rsi = frame offset, rdx = element count (arrays), ecx = the closing token ('}' for a
; {...} list; ')' for the literal (a, b) of a tuple with constant elements in a global initializer). Current token: the opening one
init_local_list:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    push qword [init_close]             ; (nested lists have their own closing token)
    mov [init_close], rcx
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
    mov rax, [init_close]
    cmp [tk], rax
    je .close
    cmp qword [tk], '.'
    jne .nodesig
    call next_token
    cmp qword [tk], T_ID
    je .d1
    ERR "expected a field name after '.'"
.d1:
    mov edi, ebx
    shr edi, 16
    and edi, 0xFFFF
    mov rsi, [tk_ptr]
    mov edx, [tk_len]
    call struct_find_field
    test rax, rax
    jnz .d2
    ERR "this struct has no field with that name"
.d2:
    mov r13, rax
    mov eax, [r15+ST_FIRST]
    shl rax, 5
    add rax, field_tab
    mov rcx, r13
    sub rcx, rax
    shr rcx, 5
    mov r14d, [r15+ST_NFIELDS]
    sub r14d, ecx
    call next_token
    mov edi, '='
    call expect
.nodesig:
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
    TY_DECAY rdi
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
    TY_DECAY r15
    sub r15, TY_PTR1
    mov rdi, r15
    call type_size
    mov r13, rax
    xor ebp, ebp
.aloop:
    mov rax, [init_close]
    cmp [tk], rax
    je .close
    cmp qword [tk], '['
    jne .anodesig
    call next_token
    call const_expr
    mov rbp, rax
    mov edi, ']'
    call expect
    mov edi, '='
    call expect
.anodesig:
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
    cmp qword [init_close], ')'
    jne .cl2
    test r14d, r14d                     ; a tuple literal gives all the elements
    jz .cl2
    ERR "this tuple has a different number of elements than the type that is expected here"
.cl2:
    mov rdi, [init_close]
    call expect
    pop qword [init_close]
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---- goto and labels -----------------------------------------------------------------------------------------------------
; lbl_get: rsi = name, edx = length -> rax = the label's entry (created when it is new)
lbl_get:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13d, edx
    xor ebx, ebx
.l: cmp ebx, [lbl_n]
    jae .new
    mov rax, rbx
    shl rax, 5
    add rax, lbl_tab
    cmp [rax+LB_LEN], r13d
    jne .next
    push rax
    mov rdi, [rax+LB_NAME]
    mov rsi, r12
    mov ecx, r13d
    repe cmpsb
    pop rax
    je .out
.next:
    inc ebx
    jmp .l
.new:
    cmp ebx, 64
    jb .room
    ERR "too many labels in one function (64)"
.room:
    inc dword [lbl_n]
    mov rax, rbx
    shl rax, 5
    add rax, lbl_tab
    mov [rax+LB_NAME], r12
    mov [rax+LB_LEN], r13d
    mov dword [rax+LB_DEF], 0
    mov qword [rax+LB_POS], 0
    mov qword [rax+LB_CHAIN], 0
.out:
    pop r13
    pop r12
    pop rbx
    ret

; goto label;
parse_goto:
    call next_token
    cmp qword [tk], T_ID
    je .ok
    ERR "expected a label name after goto"
.ok:
    mov rsi, [tk_ptr]
    mov edx, [tk_len]
    call lbl_get
    push rax
    call next_token
    mov edi, ';'
    call expect
    pop rax
    cmp dword [rax+LB_DEF], 0
    jne .back
    lea rdi, [rax+LB_CHAIN]
    CG jmp_chain
    ret
.back:
    mov rdi, [rax+LB_POS]
    CG jmp_back
    ret

; lbl_check: at the end of a function every label that was jumped to must exist
lbl_check:
    xor ecx, ecx
.l: cmp ecx, [lbl_n]
    jae .ok
    mov rax, rcx
    shl rax, 5
    add rax, lbl_tab
    inc ecx
    cmp dword [rax+LB_DEF], 0
    jne .l
    cmp qword [rax+LB_CHAIN], 0
    je .l
    ERR "goto to a label that is not defined in this function"
.ok:
    ret

; typedef enum [Tag] { A, B = 5, C } Name;      the enum type is int, the members are global constants
parse_typedef_enum:
    push rbx
    push r12
    push r13
    cmp qword [cur_func], 0
    jne .go
    cmp dword [pass], 1
    je .go
    call skip_to_semi
    jmp .out
.go:
    call next_token
    cmp qword [tk], T_ID
    jne .body
    call next_token                     ; the tag is not needed, the typedef name is the type
.body:
    mov edi, '{'
    call expect
    xor r13d, r13d
.m:
    cmp qword [tk], '}'
    je .end
    cmp qword [tk], T_ID
    je .m1
    ERR "expected an enum member name"
.m1:
    mov rdi, [tk_ptr]
    mov esi, [tk_len]
    mov edx, S_CONST
    call sym_new
    mov rbx, rax
    call next_token
    cmp qword [tk], '='
    jne .m2
    call next_token
    call const_expr
    mov r13, rax
.m2:
    mov [rbx+SYM_VAL], r13
    mov qword [rbx+SYM_TYPE], TY_INT
    or dword [rbx+SYM_FLAGS], F_ENUMVAL
    mov dword [rbx+SYM_OWNER], -1
    inc r13
    cmp qword [tk], ','
    jne .end
    call next_token
    jmp .m
.end:
    mov edi, '}'
    call expect
    cmp qword [tk], T_ID
    je .name
    ERR "expected a name for the new type"
.name:
    mov rdi, [tk_ptr]
    mov esi, [tk_len]
    mov edx, S_TYPEDEF
    call sym_new
    mov qword [rax+SYM_TYPE], TY_INT
    call next_token
    mov edi, ';'
    call expect
.out:
    pop r13
    pop r12
    pop rbx
    ret

; ---- static_assert(condition, "message");   checked while compiling, at top level, in classes and in function bodies
section .rodata
w_static_assert: db "static_assert", 0
CSTR msg_nolabel, "no enclosing loop or switch has the label"
CSTR msg_assert, "static assertion failed"
section .text

parse_static_assert:
    push rbx
    push r12
    push r13
    mov r12, [tk_start]
    mov r13, [tk_line]
    call next_token
    mov edi, '('
    call expect
    call const_expr
    mov rbx, rax
    mov byte [assertbuf], 0
    cmp qword [tk], ','
    jne .nomsg
    call next_token
    cmp qword [tk], T_STR
    je .msg
    ERR "static_assert: the message must be a text in quotes"
.msg:
    ; "static assertion failed: " + the message (cut at 400 bytes)
    mov rdi, assertbuf
    mov rsi, msg_assert
    call cstr_copy
    mov byte [rdi], ':'
    mov byte [rdi+1], ' '
    add rdi, 2
    mov rsi, [tk_ptr]
    mov rcx, [tk_len]
    cmp rcx, 400
    jbe .cp
    mov ecx, 400
.cp:
    rep movsb
    mov byte [rdi], 0
    call next_token
.nomsg:
    mov edi, ')'
    call expect
    mov edi, ';'
    call expect
    test rbx, rbx
    jnz .ok
    mov [tk_start], r12                 ; the error points at the static_assert
    mov [tk_line], r13
    mov edi, assertbuf
    cmp byte [assertbuf], 0
    jne .fail
    mov edi, msg_assert
.fail:
    jmp fatal_error
.ok:
    pop r13
    pop r12
    pop rbx
    ret
