; =============================================================================
;  expr.asm - types, expressions, constant expressions, calls
;
;  Code generation model (single pass, no AST):
;    * every expression leaves its value (or, for lvalues, its address) in RAX
;    * e_type  = static type of the expression, e_lval = 1 if RAX holds an address
;    * binary operators: left in RAX is pushed, right is computed, then
;      RCX = right, RAX = left (popped)
;    * calling convention: arguments pushed left to right (this first),
;      caller removes them, result in RAX; the callee finds parameter i of n at
;      [rbp + 16 + 8*(n-1-i)]
; =============================================================================
section .rodata
CSTR msg_undeclared, "undeclared identifier"
CSTR msg_nomember,   "no such member"
CSTR msg_privmember, "member is private to its class"
CSTR msg_unktype,    "unknown type"
CSTR alloc_name,     "alloc"
compound_map: db '+', '-', '*', '/', '%', '&', '|', '^', T_SHL, T_SHR

section .text

; ---- load / store by type ------------------------------------------------------
; emit_load_type: rdi = type. Emits  rax = *(type*)rax  (no-op for aggregates)
emit_load_type:
    call type_ls
    cmp eax, 8
    je .q
    cmp eax, 1
    je .b
    ret
.q: EM 0x48, 0x8B, 0x00
    ret
.b: EM 0x48, 0x0F, 0xB6, 0x00
    ret

; emit_store_type: rdi = type. Emits  *(type*)rcx = rax  (memcpy for aggregates:
; rax = source address, rcx = destination address)
emit_store_type:
    push rdi
    call type_ls
    cmp eax, 8
    je .q
    cmp eax, 1
    je .b
    call type_size
    push rax
    EM 0x48, 0x89, 0xC6, 0x48, 0x89, 0xCF, 0x48, 0x89, 0xC8, 0xB9
    pop rdi
    call emit_d
    EM 0xF3, 0xA4
    jmp .out
.q: EM 0x48, 0x89, 0x01
    jmp .out
.b: EM 0x88, 0x01
.out:
    pop rdi
    ret

; to_rvalue: turn an lvalue (address in rax) into its value
to_rvalue:
    cmp qword [e_lval], 0
    je .ret
    mov qword [e_lval], 0
    mov rdi, [e_type]
    bt rdi, TF_ARRAY_BIT
    jc .arr
    jmp emit_load_type
.arr:
    btr rdi, TF_ARRAY_BIT
    mov [e_type], rdi
.ret:
    ret

; ---- binary operators ----------------------------------------------------------
; scale rcx (or rax) by the size of the pointee of type rdi
scale_rcx:
    call type_pointee_size
    cmp eax, 1
    je .r
    EM 0x48, 0x69, 0xC9
    mov edi, eax
    call emit_d
.r: ret

scale_rax:
    call type_pointee_size
    cmp eax, 1
    je .r
    EM 0x48, 0x69, 0xC0
    mov edi, eax
    call emit_d
.r: ret

; binop_emit: edi = operator token, rsi = left type, rdx = right type.
; Emits code for  rax = rax OP rcx  and sets e_type / e_lval
binop_emit:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12, rsi
    mov r13, rdx
    mov qword [e_lval], 0
    mov qword [e_type], TY_INT
    cmp ebx, '+'
    je .add
    cmp ebx, '-'
    je .sub
    cmp ebx, '*'
    je .mul
    cmp ebx, '/'
    je .div
    cmp ebx, '%'
    je .mod
    cmp ebx, '&'
    je .and
    cmp ebx, '|'
    je .or
    cmp ebx, '^'
    je .xor
    cmp ebx, T_SHL
    je .shl
    cmp ebx, T_SHR
    je .shr
    cmp ebx, T_EQ
    je .eq
    cmp ebx, T_NE
    je .ne
    cmp ebx, '<'
    je .lt
    cmp ebx, '>'
    je .gt
    cmp ebx, T_LE
    je .le
    cmp ebx, T_GE
    je .ge
    ERR "internal error: unknown binary operator"
.add:
    test r12d, 0xFF00
    jz .add_li
    mov rdi, r12
    call scale_rcx
    mov [e_type], r12
    jmp .doadd
.add_li:
    test r13d, 0xFF00
    jz .doadd
    mov rdi, r13
    call scale_rax
    mov [e_type], r13
.doadd:
    EM 0x48, 0x01, 0xC8
    jmp .out
.sub:
    test r12d, 0xFF00
    jz .dosub
    test r13d, 0xFF00
    jnz .ptrdiff
    mov rdi, r12
    call scale_rcx
    mov [e_type], r12
.dosub:
    EM 0x48, 0x29, 0xC8
    jmp .out
.ptrdiff:
    EM 0x48, 0x29, 0xC8
    mov rdi, r12
    call type_pointee_size
    cmp eax, 1
    je .out
    push rax
    EM 0x48, 0xC7, 0xC1
    pop rdi
    call emit_d
    EM 0x48, 0x99, 0x48, 0xF7, 0xF9
    jmp .out
.mul:
    EM 0x48, 0x0F, 0xAF, 0xC1
    jmp .out
.div:
    EM 0x48, 0x99, 0x48, 0xF7, 0xF9
    jmp .out
.mod:
    EM 0x48, 0x99, 0x48, 0xF7, 0xF9, 0x48, 0x89, 0xD0
    jmp .out
.and:
    EM 0x48, 0x21, 0xC8
    jmp .out
.or:
    EM 0x48, 0x09, 0xC8
    jmp .out
.xor:
    EM 0x48, 0x31, 0xC8
    jmp .out
.shl:
    EM 0x48, 0xD3, 0xE0
    jmp .out
.shr:
    EM 0x48, 0xD3, 0xF8
    jmp .out
.eq:
    mov r8d, 0x94
    jmp .cmp
.ne:
    mov r8d, 0x95
    jmp .cmp
.lt:
    mov r8d, 0x9C
    jmp .cmp
.gt:
    mov r8d, 0x9F
    jmp .cmp
.le:
    mov r8d, 0x9E
    jmp .cmp
.ge:
    mov r8d, 0x9D
.cmp:
    EM 0x48, 0x39, 0xC8, 0x0F
    mov edi, r8d
    call emit_b
    EM 0xC0, 0x0F, 0xB6, 0xC0
.out:
    pop r13
    pop r12
    pop rbx
    ret

; ---- types in source -----------------------------------------------------------
; is_type_start -> eax = 1 if the current token begins a type
is_type_start:
    push rbx
    push r12
    call is_type_start_impl
    pop r12
    pop rbx
    ret

is_type_start_impl:
    mov eax, [tk]
    cmp eax, K_INT
    je .yes
    cmp eax, K_CHAR
    je .yes
    cmp eax, K_BOOL
    je .yes
    cmp eax, K_VOID
    je .yes
    cmp eax, T_ID
    jne .no
    mov rdi, [tk_ptr]
    mov esi, [tk_len]
    call sym_lookup
    test rax, rax
    jz .no
    mov ecx, [rax+SYM_KIND]
    cmp ecx, S_STRUCT
    je .yes
    cmp ecx, S_ENUM
    je .yes
    cmp ecx, S_MODULE
    jne .no
    ; module.Type ?  look ahead
    mov r12d, [rax+SYM_VAL]
    sub rsp, 128
    mov rdi, rsp
    call lex_save
    call next_token
    xor ebx, ebx
    cmp qword [tk], '.'
    jne .la_done
    call next_token
    cmp qword [tk], T_ID
    jne .la_done
    mov rdi, [tk_ptr]
    mov esi, [tk_len]
    mov edx, r12d
    call sym_find_global
    test rax, rax
    jz .la_done
    mov ecx, [rax+SYM_KIND]
    cmp ecx, S_STRUCT
    je .la_yes
    cmp ecx, S_ENUM
    jne .la_done
.la_yes:
    mov ebx, 1
.la_done:
    mov rsi, rsp
    call lex_restore
    add rsp, 128
    mov eax, ebx
    ret
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; parse_type -> rax = type; consumes the type and any '*' suffixes
parse_type:
    push rbx
    push r12
    mov eax, [tk]
    cmp eax, K_INT
    je .int
    cmp eax, K_CHAR
    je .char
    cmp eax, K_BOOL
    je .bool
    cmp eax, K_VOID
    je .void
    cmp eax, T_ID
    jne .unk
    mov rdi, [tk_ptr]
    mov esi, [tk_len]
    call sym_lookup
    test rax, rax
    jz .unk
    mov ecx, [rax+SYM_KIND]
    cmp ecx, S_MODULE
    jne .have
    mov r12d, [rax+SYM_VAL]
    call next_token
    mov edi, '.'
    call expect
    cmp qword [tk], T_ID
    jne .unk
    mov rdi, [tk_ptr]
    mov esi, [tk_len]
    mov edx, r12d
    call sym_find_global
    test rax, rax
    jz .unk
    mov ecx, [rax+SYM_KIND]
.have:
    cmp ecx, S_STRUCT
    je .struct
    cmp ecx, S_ENUM
    je .enum
.unk:
    mov edi, msg_unktype
    cmp qword [tk], T_ID
    je fatal_error_tok
    jmp fatal_error
.int:
    mov ebx, TY_INT
    jmp .star0
.char:
    mov ebx, TY_CHAR
    jmp .star0
.bool:
    mov ebx, TY_BOOL
    jmp .star0
.void:
    mov ebx, TY_VOID
    jmp .star0
.enum:
    call check_access
    mov ebx, TY_INT
    jmp .star0
.struct:
    call check_access
    mov rbx, [rax+SYM_VAL]
    shl rbx, 16
    or rbx, TY_STRUCT
.star0:
    call next_token
.star:
    cmp qword [tk], '*'
    jne .done
    add rbx, TY_PTR1
    call next_token
    jmp .star
.done:
    mov rax, rbx
    pop r12
    pop rbx
    ret

; enum_find: edi = enum symbol index, rsi = name, edx = len -> rax = const symbol / 0
enum_find:
    mov r8d, edi
    mov r9, rsi
    mov r11d, edx
    mov eax, [sym_count]
.l:
    test eax, eax
    jz .none
    dec eax
    mov r10, rax
    shl r10, 6
    add r10, symtab
    test dword [r10+SYM_FLAGS], F_ENUMVAL
    jz .l
    cmp [r10+SYM_OWNER], r8d
    jne .l
    cmp [r10+SYM_NLEN], r11d
    jne .l
    mov rdi, [r10+SYM_NAME]
    mov rsi, r9
    mov ecx, r11d
    repe cmpsb
    jne .l
    mov rax, r10
    ret
.none:
    xor eax, eax
    ret

; ---- calls ---------------------------------------------------------------------
; emit_call_sym: rdi = function symbol. Emits  call rel32  (patch chain if the
; function is not defined yet)
emit_call_sym:
    push rax
    push rdx
    EM 0xE8
    mov rax, [rdi+SYM_VAL]
    cmp rax, -1
    je .fwd
    mov rdx, rax
    mov rax, [code_pos]
    add rax, 4
    sub rdx, rax
    push rdi
    mov edi, edx
    call emit_d
    pop rdi
    jmp .out
.fwd:
    mov eax, [rdi+SYM_PATCH]
    mov rdx, [code_pos]
    mov [rdi+SYM_PATCH], edx
    push rdi
    mov edi, eax
    call emit_d
    pop rdi
.out:
    pop rdx
    pop rax
    ret

; gen_call: rdi = function symbol, esi = number of extra stack slots already pushed
; by the caller (1 when 'this' was pushed). Current token must be '('.
gen_call:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13d, esi
    xor ebx, ebx
    mov edi, '('
    call expect
    cmp qword [tk], ')'
    je .args_done
.arg:
    call parse_assign
    call to_rvalue
    mov rax, [e_type]
    test eax, 0xFF00
    jnz .push
    cmp al, TY_STRUCT
    jne .push
    ERR "structs cannot be passed by value, pass a pointer"
.push:
    EM 0x50
    inc ebx
    cmp qword [tk], ','
    jne .args_done
    call next_token
    jmp .arg
.args_done:
    mov edi, ')'
    call expect
    cmp ebx, [r12+SYM_NPAR]
    je .ok
    ERR "wrong number of arguments in call"
.ok:
    mov rdi, r12
    call emit_call_sym
    lea eax, [rbx+r13]
    test eax, eax
    jz .noadd
    cmp eax, 15
    ja .big
    EM 0x48, 0x83, 0xC4
    shl eax, 3
    mov edi, eax
    call emit_b
    jmp .noadd
.big:
    EM 0x48, 0x81, 0xC4
    shl eax, 3
    mov edi, eax
    call emit_d
.noadd:
    mov rax, [r12+SYM_TYPE]
    mov [e_type], rax
    mov qword [e_lval], 0
    pop r13
    pop r12
    pop rbx
    ret

; ---- primary expressions -------------------------------------------------------
parse_primary:
    push rbx
    push r12
    push r13
    push r14
    mov eax, [tk]
    cmp eax, T_NUM
    je .num
    cmp eax, T_STR
    je .str
    cmp eax, T_ID
    je .id
    cmp eax, '('
    je .paren
    cmp eax, K_TRUE
    je .true
    cmp eax, K_FALSE
    je .false
    cmp eax, K_NULL
    je .null
    cmp eax, K_THIS
    je .this
    cmp eax, K_SIZEOF
    je .sizeof
    cmp eax, K_NEW
    je .new
    ERR "expected an expression"

.num:
    mov rdi, [tk_val]
    call emit_imm_rax
    mov qword [e_type], TY_INT
    mov qword [e_lval], 0
    call next_token
    jmp .out

.str:
    mov rsi, [tk_ptr]
    mov rdx, [tk_len]
    call data_add_string
    mov edx, eax
    mov esi, R_DATA
    call emit_lea_rip
    mov qword [e_type], TY_CHAR | TY_PTR1
    mov qword [e_lval], 0
    call next_token
    jmp .out

.true:
    EM 0xB8, 1, 0, 0, 0
    mov qword [e_type], TY_BOOL
    mov qword [e_lval], 0
    call next_token
    jmp .out
.false:
    EM 0x31, 0xC0
    mov qword [e_type], TY_BOOL
    mov qword [e_lval], 0
    call next_token
    jmp .out
.null:
    EM 0x31, 0xC0
    mov qword [e_type], TY_VOID | TY_PTR1
    mov qword [e_lval], 0
    call next_token
    jmp .out

.this:
    cmp dword [cur_class], -1
    jne .this1
    ERR "'this' used outside of a method"
.this1:
    EM 0x48, 0x8B, 0x85
    mov edi, [cur_this_off]
    call emit_d
    mov eax, [cur_class]
    shl rax, 16
    or rax, TY_STRUCT | TY_PTR1
    mov [e_type], rax
    mov qword [e_lval], 0
    call next_token
    jmp .out

.sizeof:
    call next_token
    mov edi, '('
    call expect
    call parse_type
    mov rdi, rax
    call type_size
    mov rbx, rax
    mov edi, ')'
    call expect
    mov rdi, rbx
    call emit_imm_rax
    mov qword [e_type], TY_INT
    mov qword [e_lval], 0
    jmp .out

.paren:
    call next_token
    call is_type_start
    test eax, eax
    jnz .cast
    call parse_expr
    mov edi, ')'
    call expect
    jmp .out
.cast:
    call parse_type
    mov rbx, rax
    mov edi, ')'
    call expect
    call parse_unary
    call to_rvalue
    test ebx, 0xFF00
    jnz .cdone
    cmp bl, TY_CHAR
    je .cchar
    cmp bl, TY_BOOL
    je .cbool
    jmp .cdone
.cchar:
    EM 0x0F, 0xB6, 0xC0
    jmp .cdone
.cbool:
    EM 0x48, 0x85, 0xC0, 0x0F, 0x95, 0xC0, 0x0F, 0xB6, 0xC0
.cdone:
    mov [e_type], rbx
    mov qword [e_lval], 0
    jmp .out

; ---- new T(args)
.new:
    call next_token
    call parse_type
    mov rbx, rax
    test ebx, 0xFF00
    jnz .new_bad
    cmp bl, TY_STRUCT
    je .new_ok
.new_bad:
    ERR "'new' needs a class or struct type"
.new_ok:
    mov r12, rbx
    shr r12, 16
    and r12d, 0xFFFF
    mov rdi, rbx
    call type_size
    mov r13, rax
    mov rdi, alloc_name
    mov esi, 5
    xor edx, edx
    call sym_find_global
    test rax, rax
    jnz .new_a
    ERR "the standard library function 'alloc' is missing"
.new_a:
    mov r14, rax
    mov rdi, r13
    call emit_imm_rax
    EM 0x50
    mov rdi, r14
    call emit_call_sym
    EM 0x48, 0x83, 0xC4, 0x08
    mov edi, r12d
    call struct_find_ctor
    test rax, rax
    jz .new_noctor
    mov r14, rax
    cmp qword [tk], '('
    je .new_c
    ERR "constructor call needs parentheses"
.new_c:
    EM 0x50, 0x50
    mov rdi, r14
    mov esi, 1
    call gen_call
    EM 0x58
    jmp .new_done
.new_noctor:
    cmp qword [tk], '('
    jne .new_done
    call next_token
    mov edi, ')'
    call expect
.new_done:
    lea rax, [rbx + TY_PTR1]
    mov [e_type], rax
    mov qword [e_lval], 0
    jmp .out

; ---- identifiers
.id:
    mov r13, [tk_ptr]
    mov r14d, [tk_len]
    mov rdi, r13
    mov esi, r14d
    call sym_lookup
    mov r12, rax
    test r12, r12
    jz .tryclass
    cmp dword [r12+SYM_KIND], S_LOCAL
    je .consume
.tryclass:
    cmp dword [cur_class], -1
    je .nocls
    mov edi, [cur_class]
    mov rsi, r13
    mov edx, r14d
    call struct_find_field
    test rax, rax
    jnz .implicit_field
    mov edi, [cur_class]
    mov rsi, r13
    mov edx, r14d
    call struct_find_method
    test rax, rax
    jnz .implicit_method
.nocls:
    test r12, r12
    jnz .consume
    mov edi, msg_undeclared
    call fatal_error_tok
.consume:
    call next_token
.dispatch:
    mov eax, [r12+SYM_KIND]
    cmp eax, S_LOCAL
    je .local
    cmp eax, S_GLOBAL
    je .global
    cmp eax, S_CONST
    je .const
    cmp eax, S_FUNC
    je .func
    cmp eax, S_MODULE
    je .module
    cmp eax, S_ENUM
    je .enumname
    ERR "a type name cannot be used as a value"

.local:
    EM 0x48, 0x8D, 0x85
    mov edi, [r12+SYM_VAL]
    call emit_d
    mov rax, [r12+SYM_TYPE]
    mov [e_type], rax
    mov qword [e_lval], 1
    jmp .out

.global:
    mov rax, r12
    call check_access
    mov edx, [r12+SYM_VAL]
    mov esi, R_DATA
    test dword [r12+SYM_FLAGS], F_BSS
    jz .g1
    mov esi, R_BSS
.g1:
    call emit_lea_rip
    mov rax, [r12+SYM_TYPE]
    mov [e_type], rax
    mov qword [e_lval], 1
    jmp .out

.const:
    mov rax, r12
    call check_access
    test dword [r12+SYM_FLAGS], F_STRCONST
    jnz .conststr
    mov rdi, [r12+SYM_VAL]
    call emit_imm_rax
    mov rax, [r12+SYM_TYPE]
    mov [e_type], rax
    mov qword [e_lval], 0
    jmp .out
.conststr:
    mov edx, [r12+SYM_VAL]
    mov esi, R_DATA
    call emit_lea_rip
    mov qword [e_type], TY_CHAR | TY_PTR1
    mov qword [e_lval], 0
    jmp .out

.func:
    mov rax, r12
    call check_access
    cmp qword [tk], '('
    je .func1
    ERR "function pointers are not supported yet, call the function"
.func1:
    mov rdi, r12
    xor esi, esi
    call gen_call
    jmp .out

.module:
    mov ebx, [r12+SYM_VAL]
    mov edi, '.'
    call expect
    cmp qword [tk], T_ID
    je .mod1
    ERR "expected a member name after the module name"
.mod1:
    mov rdi, [tk_ptr]
    mov esi, [tk_len]
    mov edx, ebx
    call sym_find_global
    test rax, rax
    jnz .mod2
    mov edi, msg_nomember
    call fatal_error_tok
.mod2:
    mov r12, rax
    call next_token
    jmp .dispatch

.enumname:
    mov rax, r12
    call sym_index
    mov ebx, eax
    mov edi, '.'
    call expect
    cmp qword [tk], T_ID
    je .en1
    ERR "expected an enum member name"
.en1:
    mov edi, ebx
    mov rsi, [tk_ptr]
    mov edx, [tk_len]
    call enum_find
    test rax, rax
    jnz .en2
    mov edi, msg_nomember
    call fatal_error_tok
.en2:
    mov r12, rax
    call next_token
    jmp .const

.implicit_field:
    mov r12, rax
    EM 0x48, 0x8B, 0x85
    mov edi, [cur_this_off]
    call emit_d
    mov edi, [r12+FD_OFFSET]
    test edi, edi
    jz .if1
    EM 0x48, 0x05
    call emit_d
.if1:
    mov rax, [r12+FD_TYPE]
    mov [e_type], rax
    mov qword [e_lval], 1
    call next_token
    jmp .out

.implicit_method:
    mov r12, rax
    call next_token
    cmp qword [tk], '('
    je .im1
    ERR "methods can only be called, not used as values"
.im1:
    EM 0x48, 0x8B, 0x85
    mov edi, [cur_this_off]
    call emit_d
    EM 0x50
    mov rdi, r12
    mov esi, 1
    call gen_call

.out:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---- postfix: calls on members, indexing, member access, ++ / -- ----------------
parse_postfix:
    push rbx
    push r12
    push r13
    push r14
    call parse_primary
.loop:
    mov eax, [tk]
    cmp eax, '['
    je .index
    cmp eax, '.'
    je .member
    cmp eax, T_ARROW
    je .member
    cmp eax, T_INC
    je .postinc
    cmp eax, T_DEC
    je .postdec
.out:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.index:
    call to_rvalue
    mov rax, [e_type]
    test eax, 0xFF00
    jnz .ix1
    ERR "indexing a value that is not a pointer or array"
.ix1:
    mov rdi, [e_type]
    call type_pointee_size
    mov r12, rax
    mov rbx, [e_type]
    sub rbx, TY_PTR1
    EM 0x50
    call next_token
    call parse_expr
    call to_rvalue
    cmp r12, 1
    je .ix2
    EM 0x48, 0x69, 0xC0
    mov rdi, r12
    call emit_d
.ix2:
    EM 0x59
    EM 0x48, 0x01, 0xC8
    mov edi, ']'
    call expect
    mov [e_type], rbx
    mov qword [e_lval], 1
    jmp .loop

.member:
    mov rax, [e_type]
    cmp al, TY_STRUCT
    jne .notstruct
    mov edx, eax
    shr edx, 8
    and edx, 0xFF
    test edx, edx
    jz .mdirect
    cmp edx, 1
    jne .notstruct
    call to_rvalue
    jmp .mb
.mdirect:
    cmp qword [e_lval], 0
    jne .mb0
    ERR "member access on a value that has no address"
.mb0:
    mov qword [e_lval], 0
.mb:
    mov rbx, [e_type]
    shr rbx, 16
    and ebx, 0xFFFF
    call next_token
    cmp qword [tk], T_ID
    je .mb1
    ERR "expected a member name"
.mb1:
    mov r13, [tk_ptr]
    mov r14d, [tk_len]
    mov edi, ebx
    mov rsi, r13
    mov edx, r14d
    call struct_find_field
    test rax, rax
    jz .trymethod
    mov r12, rax
    cmp dword [r12+FD_VIS], 0
    je .fok
    cmp ebx, [cur_class]
    je .fok
    mov edi, msg_privmember
    call fatal_error_tok
.fok:
    mov edi, [r12+FD_OFFSET]
    test edi, edi
    jz .f1
    EM 0x48, 0x05
    call emit_d
.f1:
    mov rax, [r12+FD_TYPE]
    mov [e_type], rax
    mov qword [e_lval], 1
    call next_token
    jmp .loop
.trymethod:
    mov edi, ebx
    mov rsi, r13
    mov edx, r14d
    call struct_find_method
    test rax, rax
    jnz .m1
    mov edi, msg_nomember
    call fatal_error_tok
.m1:
    mov r12, rax
    test dword [r12+SYM_FLAGS], F_PRIVATE
    jz .m2
    cmp ebx, [cur_class]
    je .m2
    mov edi, msg_privmember
    call fatal_error_tok
.m2:
    call next_token
    cmp qword [tk], '('
    je .m3
    ERR "methods can only be called, not used as values"
.m3:
    EM 0x50
    mov rdi, r12
    mov esi, 1
    call gen_call
    jmp .loop
.notstruct:
    ERR "member access on a value that is not a struct, class or pointer to one"

.postinc:
    call next_token
    mov edi, 1
    mov esi, 1
    call emit_incdec_postfix
    jmp .loop
.postdec:
    call next_token
    mov edi, 1
    mov esi, -1
    call emit_incdec_postfix
    jmp .loop

; emit_incdec: edi = 1 for postfix result (old value), 0 for prefix (new value);
; esi = +1 / -1. Operand must be an lvalue (address in rax).
emit_incdec_postfix:
    push rbx
    push r12
    push r13
    mov r12d, edi
    movsxd r13, esi
    cmp qword [e_lval], 0
    jne .lv
    ERR "operand of ++/-- must be a variable"
.lv:
    mov rbx, [e_type]
    bt rbx, TF_ARRAY_BIT
    jnc .noarr
    ERR "cannot modify an array"
.noarr:
    mov rdi, rbx
    call type_ls
    test eax, eax
    jnz .scalar
    ERR "cannot increment a struct"
.scalar:
    test ebx, 0xFF00
    jz .step1
    mov rdi, rbx
    call type_pointee_size
    imul r13, rax
.step1:
    EM 0x48, 0x89, 0xC1
    mov rdi, rbx
    call emit_load_type
    test r12d, r12d
    jz .nopost
    EM 0x48, 0x89, 0xC2
.nopost:
    EM 0x48, 0x05
    mov rdi, r13
    call emit_d
    mov rdi, rbx
    call emit_store_type
    test r12d, r12d
    jz .fin
    EM 0x48, 0x89, 0xD0
.fin:
    mov [e_type], rbx
    mov qword [e_lval], 0
    pop r13
    pop r12
    pop rbx
    ret

; ---- unary ---------------------------------------------------------------------
parse_unary:
    mov eax, [tk]
    cmp eax, '-'
    je .neg
    cmp eax, '+'
    je .plus
    cmp eax, '!'
    je .not
    cmp eax, '~'
    je .compl
    cmp eax, '*'
    je .deref
    cmp eax, '&'
    je .addr
    cmp eax, T_INC
    je .preinc
    cmp eax, T_DEC
    je .predec
    jmp parse_postfix
.neg:
    call next_token
    call parse_unary
    call to_rvalue
    EM 0x48, 0xF7, 0xD8
    mov qword [e_type], TY_INT
    ret
.plus:
    call next_token
    call parse_unary
    call to_rvalue
    ret
.not:
    call next_token
    call parse_unary
    call to_rvalue
    EM 0x48, 0x85, 0xC0, 0x0F, 0x94, 0xC0, 0x0F, 0xB6, 0xC0
    mov qword [e_type], TY_BOOL
    ret
.compl:
    call next_token
    call parse_unary
    call to_rvalue
    EM 0x48, 0xF7, 0xD0
    mov qword [e_type], TY_INT
    ret
.deref:
    call next_token
    call parse_unary
    call to_rvalue
    mov rax, [e_type]
    test eax, 0xFF00
    jnz .d1
    ERR "cannot dereference a value that is not a pointer"
.d1:
    sub rax, TY_PTR1
    cmp rax, TY_VOID
    jne .d2
    ERR "cannot dereference a void pointer"
.d2:
    mov [e_type], rax
    mov qword [e_lval], 1
    ret
.addr:
    call next_token
    call parse_unary
    cmp qword [e_lval], 0
    jne .a1
    ERR "cannot take the address of a value"
.a1:
    mov rax, [e_type]
    bt rax, TF_ARRAY_BIT
    jnc .a2
    btr rax, TF_ARRAY_BIT
    jmp .a3
.a2:
    add rax, TY_PTR1
.a3:
    mov [e_type], rax
    mov qword [e_lval], 0
    ret
.preinc:
    call next_token
    call parse_unary
    xor edi, edi
    mov esi, 1
    jmp emit_incdec_postfix
.predec:
    call next_token
    call parse_unary
    xor edi, edi
    mov esi, -1
    jmp emit_incdec_postfix

; ---- binary / logical / ternary / assignment ----------------------------------
; parse_binary: edi = minimum precedence (3..10)
parse_binary:
    push rbx
    push r12
    push r13
    mov ebx, edi
    call parse_unary
.loop:
    mov eax, [tk]
    cmp eax, 255
    ja .done
    movzx ecx, byte [binprec+rax]
    test ecx, ecx
    jz .done
    cmp ecx, ebx
    jb .done
    mov r12d, eax
    mov r13d, ecx
    call to_rvalue
    push qword [e_type]
    EM 0x50
    call next_token
    lea edi, [r13+1]
    call parse_binary
    call to_rvalue
    EM 0x48, 0x89, 0xC1, 0x58
    pop rsi
    mov rdx, [e_type]
    mov edi, r12d
    call binop_emit
    jmp .loop
.done:
    pop r13
    pop r12
    pop rbx
    ret

parse_logand:
    push rbx
    mov edi, 3
    call parse_binary
    cmp qword [tk], T_ANDAND
    jne .out
    call to_rvalue
    push 0
.l:
    EM 0x48, 0x85, 0xC0, 0x0F, 0x84
    mov rdi, rsp
    call chain_slot
    call next_token
    mov edi, 3
    call parse_binary
    call to_rvalue
    cmp qword [tk], T_ANDAND
    je .l
    EM 0x48, 0x85, 0xC0, 0x0F, 0x84
    mov rdi, rsp
    call chain_slot
    EM 0xB8, 1, 0, 0, 0, 0xEB, 0x02
    pop rdi
    call patch_here
    EM 0x31, 0xC0
    mov qword [e_type], TY_BOOL
.out:
    pop rbx
    ret

parse_logor:
    push rbx
    call parse_logand
    cmp qword [tk], T_OROR
    jne .out
    call to_rvalue
    push 0
.l:
    EM 0x48, 0x85, 0xC0, 0x0F, 0x85
    mov rdi, rsp
    call chain_slot
    call next_token
    call parse_logand
    call to_rvalue
    cmp qword [tk], T_OROR
    je .l
    EM 0x48, 0x85, 0xC0, 0x0F, 0x85
    mov rdi, rsp
    call chain_slot
    EM 0x31, 0xC0, 0xEB, 0x05
    pop rdi
    call patch_here
    EM 0xB8, 1, 0, 0, 0
    mov qword [e_type], TY_BOOL
.out:
    pop rbx
    ret

parse_ternary:
    push rbx
    call parse_logor
    cmp qword [tk], '?'
    jne .out
    call to_rvalue
    push 0                      ; else chain
    push 0                      ; end chain
    EM 0x48, 0x85, 0xC0, 0x0F, 0x84
    lea rdi, [rsp+8]
    call chain_slot
    call next_token
    call parse_assign
    call to_rvalue
    mov rbx, [e_type]
    EM 0xE9
    mov rdi, rsp
    call chain_slot
    mov rdi, [rsp+8]
    call patch_here
    mov edi, ':'
    call expect
    call parse_ternary
    call to_rvalue
    pop rdi
    call patch_here
    add rsp, 8
    mov [e_type], rbx
.out:
    pop rbx
    ret

parse_expr:
parse_assign:
    push rbx
    push r12
    push r13
    call parse_ternary
    mov eax, [tk]
    cmp eax, '='
    je .plain
    cmp eax, T_ADDEQ
    jb .ret
    cmp eax, T_SHREQ
    ja .ret
    jmp .compound
.ret:
    pop r13
    pop r12
    pop rbx
    ret
.plain:
    cmp qword [e_lval], 0
    jne .p1
    ERR "left side of assignment is not assignable"
.p1:
    mov rbx, [e_type]
    bt rbx, TF_ARRAY_BIT
    jnc .p2
    ERR "cannot assign to an array"
.p2:
    EM 0x50
    call next_token
    call parse_assign
    call to_rvalue
    EM 0x59
    mov rdi, rbx
    call emit_store_type
    mov [e_type], rbx
    mov qword [e_lval], 0
    jmp .ret
.compound:
    mov r12d, eax
    cmp qword [e_lval], 0
    jne .c1
    ERR "left side of assignment is not assignable"
.c1:
    mov rbx, [e_type]
    bt rbx, TF_ARRAY_BIT
    jnc .c2
    ERR "cannot assign to an array"
.c2:
    mov rdi, rbx
    call type_ls
    test eax, eax
    jnz .c3
    ERR "compound assignment needs a scalar variable"
.c3:
    EM 0x50
    mov rdi, rbx
    call emit_load_type
    EM 0x50
    call next_token
    call parse_assign
    call to_rvalue
    mov r13, [e_type]
    EM 0x48, 0x89, 0xC1, 0x58
    sub r12d, T_ADDEQ
    movzx edi, byte [compound_map+r12]
    mov rsi, rbx
    mov rdx, r13
    call binop_emit
    EM 0x59
    mov rdi, rbx
    call emit_store_type
    mov [e_type], rbx
    mov qword [e_lval], 0
    jmp .ret

; =============================================================================
;  constant expressions  ->  rax = value, edx = 1 when rax is a string literal's
;  data offset
; =============================================================================
const_expr:
    mov edi, 1
    jmp const_binary

const_binary:
    push rbx
    push r12
    push r13
    push r14
    mov ebx, edi
    call const_unary
    mov r12, rax
    mov r14d, edx
.loop:
    mov eax, [tk]
    cmp eax, 255
    ja .done
    movzx ecx, byte [binprec+rax]
    test ecx, ecx
    jz .done
    cmp ecx, ebx
    jb .done
    mov r13d, eax
    push rcx
    call next_token
    pop rcx
    lea edi, [rcx+1]
    call const_binary
    or edx, r14d
    jz .arith
    ERR "arithmetic on a string constant"
.arith:
    mov rcx, rax
    mov rax, r12
    mov edi, r13d
    call const_apply
    mov r12, rax
    xor r14d, r14d
    jmp .loop
.done:
    mov rax, r12
    mov edx, r14d
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; const_apply: edi = operator, rax = left, rcx = right -> rax
const_apply:
    cmp edi, '+'
    je .add
    cmp edi, '-'
    je .sub
    cmp edi, '*'
    je .mul
    cmp edi, '/'
    je .div
    cmp edi, '%'
    je .mod
    cmp edi, '&'
    je .and
    cmp edi, '|'
    je .or
    cmp edi, '^'
    je .xor
    cmp edi, T_SHL
    je .shl
    cmp edi, T_SHR
    je .shr
    cmp edi, T_ANDAND
    je .land
    cmp edi, T_OROR
    je .lor
    cmp edi, T_EQ
    je .eq
    cmp edi, T_NE
    je .ne
    cmp edi, '<'
    je .lt
    cmp edi, '>'
    je .gt
    cmp edi, T_LE
    je .le
    jmp .ge
.add: add rax, rcx
    ret
.sub: sub rax, rcx
    ret
.mul: imul rax, rcx
    ret
.div: test rcx, rcx
    jz .dz
    cqo
    idiv rcx
    ret
.mod: test rcx, rcx
    jz .dz
    cqo
    idiv rcx
    mov rax, rdx
    ret
.dz:
    ERR "division by zero in constant expression"
.and: and rax, rcx
    ret
.or: or rax, rcx
    ret
.xor: xor rax, rcx
    ret
.shl: shl rax, cl
    ret
.shr: sar rax, cl
    ret
.land:
    test rax, rax
    setne al
    test rcx, rcx
    setne cl
    and al, cl
    movzx eax, al
    ret
.lor:
    or rax, rcx
    setne al
    movzx eax, al
    ret
.eq: cmp rax, rcx
    sete al
    movzx eax, al
    ret
.ne: cmp rax, rcx
    setne al
    movzx eax, al
    ret
.lt: cmp rax, rcx
    setl al
    movzx eax, al
    ret
.gt: cmp rax, rcx
    setg al
    movzx eax, al
    ret
.le: cmp rax, rcx
    setle al
    movzx eax, al
    ret
.ge: cmp rax, rcx
    setge al
    movzx eax, al
    ret

const_unary:
    push rbx
    push r12
    mov eax, [tk]
    cmp eax, T_NUM
    je .num
    cmp eax, T_STR
    je .str
    cmp eax, '-'
    je .neg
    cmp eax, '+'
    je .plus
    cmp eax, '~'
    je .compl
    cmp eax, '!'
    je .not
    cmp eax, '('
    je .paren
    cmp eax, K_TRUE
    je .true
    cmp eax, K_FALSE
    je .zero
    cmp eax, K_NULL
    je .zero
    cmp eax, K_SIZEOF
    je .sizeof
    cmp eax, T_ID
    je .id
    ERR "a constant expression is required here"
.num:
    mov rax, [tk_val]
    xor edx, edx
    push rax
    push rdx
    call next_token
    pop rdx
    pop rax
    jmp .out
.str:
    mov rsi, [tk_ptr]
    mov rdx, [tk_len]
    call data_add_string
    push rax
    call next_token
    pop rax
    mov edx, 1
    jmp .out
.true:
    call next_token
    mov eax, 1
    xor edx, edx
    jmp .out
.zero:
    call next_token
    xor eax, eax
    xor edx, edx
    jmp .out
.neg:
    call next_token
    call const_unary
    neg rax
    jmp .out
.plus:
    call next_token
    call const_unary
    jmp .out
.compl:
    call next_token
    call const_unary
    not rax
    jmp .out
.not:
    call next_token
    call const_unary
    test rax, rax
    sete al
    movzx eax, al
    jmp .out
.paren:
    call next_token
    mov edi, 1
    call const_binary
    push rax
    push rdx
    mov edi, ')'
    call expect
    pop rdx
    pop rax
    jmp .out
.sizeof:
    call next_token
    mov edi, '('
    call expect
    call parse_type
    mov rdi, rax
    call type_size
    push rax
    mov edi, ')'
    call expect
    pop rax
    xor edx, edx
    jmp .out
.id:
    mov rdi, [tk_ptr]
    mov esi, [tk_len]
    call sym_lookup
    test rax, rax
    jnz .id1
    mov edi, msg_undeclared
    call fatal_error_tok
.id1:
    mov r12, rax
    call next_token
.id_dispatch:
    mov eax, [r12+SYM_KIND]
    cmp eax, S_CONST
    je .id_const
    cmp eax, S_MODULE
    je .id_mod
    cmp eax, S_ENUM
    je .id_enum
    ERR "name is not a constant"
.id_const:
    mov rax, r12
    call check_access
    mov rax, [r12+SYM_VAL]
    xor edx, edx
    test dword [r12+SYM_FLAGS], F_STRCONST
    jz .out
    mov edx, 1
    jmp .out
.id_mod:
    mov ebx, [r12+SYM_VAL]
    mov edi, '.'
    call expect
    cmp qword [tk], T_ID
    je .im1
    ERR "expected a member name after the module name"
.im1:
    mov rdi, [tk_ptr]
    mov esi, [tk_len]
    mov edx, ebx
    call sym_find_global
    test rax, rax
    jnz .im2
    mov edi, msg_nomember
    call fatal_error_tok
.im2:
    mov r12, rax
    call next_token
    jmp .id_dispatch
.id_enum:
    mov rax, r12
    call sym_index
    mov ebx, eax
    mov edi, '.'
    call expect
    cmp qword [tk], T_ID
    je .ie1
    ERR "expected an enum member name"
.ie1:
    mov edi, ebx
    mov rsi, [tk_ptr]
    mov edx, [tk_len]
    call enum_find
    test rax, rax
    jnz .ie2
    mov edi, msg_nomember
    call fatal_error_tok
.ie2:
    mov r12, rax
    call next_token
    jmp .id_const
.out:
    pop r12
    pop rbx
    ret
