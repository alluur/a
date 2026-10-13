; =============================================================================
;  decl.asm - top level declarations: functions, classes, structs, enums,
;             globals, constants, imports and modules
;
;  The compiler runs two passes over the sources.
;    pass 1 registers every declaration (types, signatures, globals, constants)
;           and skips function bodies
;    pass 2 compiles the function bodies; all declarations are already known so
;           functions and methods can be used before they are defined.
; =============================================================================
section .rodata
CSTR msg_redef,    "redefinition of"
CSTR msg_kindmix,  "name is already declared as something else:"
CSTR msg_toplevel, "expected a declaration"

section .text

; ---- token skipping -----------------------------------------------------------------
; skip_block: current token is '{'; consume up to and including the matching '}'
skip_block:
    push rbx
    xor ebx, ebx
.l:
    mov eax, [tk]
    cmp eax, '{'
    jne .a
    inc ebx
.a:
    cmp eax, '}'
    jne .b
    dec ebx
.b:
    cmp eax, T_EOF
    jne .c
    ERR "unexpected end of file, missing '}'"
.c:
    call next_token
    test ebx, ebx
    jnz .l
    pop rbx
    ret

; skip_to_semi: consume tokens up to and including the next ';' outside braces
skip_to_semi:
    push rbx
    xor ebx, ebx
.l:
    mov eax, [tk]
    cmp eax, T_EOF
    jne .a
    ERR "unexpected end of file, missing ';'"
.a:
    cmp eax, '{'
    jne .b
    inc ebx
.b:
    cmp eax, '}'
    jne .c
    dec ebx
.c:
    cmp eax, ';'
    jne .n
    test ebx, ebx
    jnz .n
    call next_token
    pop rbx
    ret
.n:
    call next_token
    jmp .l

; ---- parameters -----------------------------------------------------------------------
; parse_params: current token is '('. Fills ptmp_* and ptmp_count, consumes ')'.
parse_params:
    push rbx
    push r12
    mov edi, '('
    call expect
    mov dword [ptmp_count], 0
    mov dword [ptmp_nreq], 0x7FFFFFFF
    mov dword [ptmp_variadic], 0
    cmp qword [tk], ')'
    je .end
.p:
    cmp qword [tk], '.'
    jne .ptype
    ; "..." : any number of further arguments (they are read with va_arg(i), counted by va_count())
    call next_token
    mov edi, '.'
    call expect
    mov edi, '.'
    call expect
    mov dword [ptmp_variadic], 1
    cmp dword [ptmp_nreq], 0x7FFFFFFF
    je .end
    ERR "a function with default values cannot also take ..."
.ptype:
    call parse_type
    mov rbx, rax
    cmp rbx, TY_VOID
    jne .nv
    cmp qword [tk], ')'
    je .end
.nv:
.ok:
    mov eax, [ptmp_count]
    cmp eax, MAXPARAM
    jb .st
    ERR "too many parameters"
.st:
    mov [ptmp_type+rax*8], rbx
    mov qword [ptmp_name+rax*8], 0
    mov dword [ptmp_nlen+rax*4], 0
    cmp qword [tk], T_ID
    jne .noname
    mov rcx, [tk_ptr]
    mov [ptmp_name+rax*8], rcx
    mov ecx, [tk_len]
    mov [ptmp_nlen+rax*4], ecx
    call next_token
.noname:
    ; optional default value:  type name = constant
    mov r12d, [ptmp_count]
    mov qword [ptmp_def+r12*8], 0
    cmp qword [tk], '='
    jne .nodef
    call next_token
    call const_expr
    cmp edx, 1
    jne .defok
    mov rcx, 0x5A5A000000000000         ; a text: its data offset with a marker in the top 16 bits
    or rax, rcx
.defok:
    mov [ptmp_def+r12*8], rax
    cmp r12d, [ptmp_nreq]
    jae .defdone
    mov [ptmp_nreq], r12d
    jmp .defdone
.nodef:
    cmp dword [ptmp_nreq], 0x7FFFFFFF
    je .defdone
    ERR "parameters after one with a default value need default values too"
.defdone:
    inc dword [ptmp_count]
    cmp qword [tk], ','
    jne .end
    call next_token
    jmp .p
.end:
    mov edi, ')'
    call expect
    pop r12
    pop rbx
    ret

; ---- function registration ---------------------------------------------------------
; func_register: rdi = name, esi = len, rdx = return type, ecx = owner struct index
; (-1 for plain functions), r8d = flags. Finds or creates the symbol and stores
; the signature from ptmp_*. -> rax = symbol
func_register:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13d, esi
    mov r14, rdx
    mov r15d, ecx
    mov ebx, r8d
.retok:
    cmp r15d, -1
    jne .member
    mov rdi, r12
    mov esi, r13d
    mov edx, [cur_module]
    call sym_find_global
    test rax, rax
    jz .new
    cmp dword [rax+SYM_KIND], S_FUNC
    je .have
    mov edi, msg_kindmix
    call fatal_error_tok
.member:
    test ebx, F_CTOR
    jz .m2
    mov edi, r15d
    call struct_find_ctor_here
    jmp .m3
.m2:
    mov edi, r15d
    mov rsi, r12
    mov edx, r13d
    call struct_find_method_here
.m3:
    test rax, rax
    jnz .have
.new:
    mov rdi, r12
    mov esi, r13d
    mov edx, S_FUNC
    call sym_new
    mov qword [rax+SYM_VAL], -1
    mov [rax+SYM_OWNER], r15d
.have:
    mov [rax+SYM_TYPE], r14
    or [rax+SYM_FLAGS], ebx
    cmp dword [ptmp_variadic], 0
    je .notvar
    or dword [rax+SYM_FLAGS], F_VARIADIC
.notvar:
    mov ecx, [ptmp_count]
    mov [rax+SYM_NPAR], ecx
    ; copy the parameter types into the pool
    mov rdx, [ptype_pos]
    lea rsi, [rdx+rcx*2+1]
    cmp rsi, PTYPE_MAX
    ja err_toobig
    mov [ptype_pos], rsi
    lea rdi, [ptype_pool+rdx*8]
    mov [rax+SYM_EXTRA], rdi
    xor esi, esi
.cp:
    cmp esi, ecx
    jae .cpd
    mov rdx, [ptmp_type+rsi*8]
    mov [rdi+rsi*8], rdx
    mov rdx, [ptmp_def+rsi*8]
    lea r8d, [rsi+rcx]
    mov [rdi+r8*8], rdx
    inc esi
    jmp .cp
.cpd:
    ; pool layout: types[n], default values[n], number of required parameters
    mov edx, [ptmp_nreq]
    cmp edx, ecx
    jbe .nreq
    mov edx, ecx
.nreq:
    lea r8d, [rcx*2]
    mov [rdi+r8*8], rdx
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; define_function: rdi = function symbol; its code starts at the current position
define_function:
    push rax
    push rsi
    push rdi
    mov rax, [code_pos]
    mov [last_label], rax
    mov [rdi+SYM_VAL], rax
    mov eax, [rdi+SYM_PATCH]
    mov dword [rdi+SYM_PATCH], 0
    mov rsi, [code_pos]
    mov rdi, rax
    CG patch_chain
    pop rdi
    pop rsi
    pop rax
    ret

; compile_function: rdi = function symbol, current token '{', ptmp_* holds the
; parameters of this declaration (pass 2 only)
compile_function:
    ; final pass: functions that nothing calls are not emitted
    cmp dword [pass], 3
    jne .go
    test dword [rdi+SYM_FLAGS], F_USED
    jnz .go
    jmp skip_block
.go:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13d, [sym_count]
    mov [cur_func], r12
    call define_function
    CG prologue
    mov dword [frame_size], 0
    mov qword [ret_chain], 0
    mov dword [loop_sp], 0
    ; total number of stack slots = params (+ this)
    mov ebx, [r12+SYM_NPAR]
    xor r14d, r14d
    ; a function that returns a struct gets the address of the result as a hidden last argument
    mov rax, [r12+SYM_TYPE]
    test eax, 0xFF00
    jnz .noretstruct
    cmp al, TY_STRUCT
    jne .noretstruct
    inc ebx
.noretstruct:
    test dword [r12+SYM_FLAGS], F_METHOD
    jz .params
    inc ebx
    mov r14d, 1
    lea eax, [rbx-1]
    imul eax, [slot_bytes]
    add eax, 16
    mov [cur_this_off], eax
.params:
    test dword [r12+SYM_FLAGS], F_VARIADIC
    jz .pstart
    test r14d, r14d
    jz .vok
    ERR "methods cannot take ..."
.vok:
    ; the caller pushed the arguments in order and then the number of extra ones; remember that number
    add dword [frame_size], 8
    mov eax, [frame_size]
    neg eax
    mov [cur_va_cnt], eax
    mov edi, 16
    CG load_local_a
    mov edi, [cur_va_cnt]
    CG store_local_a
.pstart:
    xor ecx, ecx
.pl:
    cmp ecx, [ptmp_count]
    jae .pd
    cmp qword [ptmp_name+rcx*8], 0
    je .pn
    push rcx
    mov rdi, [ptmp_name+rcx*8]
    mov esi, [ptmp_nlen+rcx*4]
    mov edx, S_LOCAL
    call sym_new
    pop rcx
    mov rdx, [ptmp_type+rcx*8]
    mov [rax+SYM_TYPE], rdx
    test edx, 0xFF00
    jnz .notstructp
    cmp dl, TY_STRUCT
    jne .notstructp
    or dword [rax+SYM_FLAGS], F_BYREF   ; the slot holds the address of a copy made by the caller
.notstructp:
    test dword [r12+SYM_FLAGS], F_VARIADIC
    jz .posoff
    ; variadic: the named parameter sits (1 + extras + ...) slots up the stack; copy it into a local of its own
    push rax
    add dword [frame_size], 8
    mov esi, [frame_size]
    neg esi
    movsxd rsi, esi
    push rsi
    mov edi, [cur_va_cnt]
    CG load_local_a
    mov edi, [slot_bytes]
    CG mul_imm_a
    CG mov_b_a
    mov eax, ebx
    sub eax, ecx
    imul eax, [slot_bytes]
    add eax, 16
    mov edi, eax
    CG lea_local_a
    CG add
    CG load8_a
    pop rsi
    mov edi, esi
    CG store_local_a
    pop rax
    mov [rax+SYM_VAL], rsi
    jmp .pn
.posoff:
    lea edx, [rcx+r14]
    mov esi, ebx
    dec esi
    sub esi, edx
    imul esi, [slot_bytes]
    add esi, 16
    mov [rax+SYM_VAL], rsi
.pn:
    inc ecx
    jmp .pl
.pd:
    call parse_block
    xor edi, edi
    CG imm_a
    mov rdi, [ret_chain]
    call patch_here
    CG epilogue
    mov edi, [frame_size]
    add edi, 15
    and edi, -16
    CG set_frame
    mov [sym_count], r13d
    mov qword [cur_func], 0
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---- enum ---------------------------------------------------------------------------------
; parse_enum: edi = visibility
parse_enum:
    push rbx
    push r12
    push r13
    push r14
    mov r14d, edi
    call next_token
    cmp qword [tk], T_ID
    je .n1
    ERR "expected an enum name"
.n1:
    cmp dword [pass], 1
    jne .skip
    mov rdi, [tk_ptr]
    mov esi, [tk_len]
    mov edx, S_ENUM
    call sym_new
    mov rbx, rax
    test r14d, r14d
    jz .v1
    or dword [rbx+SYM_FLAGS], F_PRIVATE
.v1:
    mov rax, rbx
    call sym_index
    mov r12d, eax
    call next_token
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
    mov [rbx+SYM_OWNER], r12d
    test r14d, r14d
    jz .m3
    or dword [rbx+SYM_FLAGS], F_PRIVATE
.m3:
    inc r13
    cmp qword [tk], ','
    jne .end
    call next_token
    jmp .m
.end:
    mov edi, '}'
    call expect
    jmp .semi
.skip:
    call next_token
    call skip_block
.semi:
    cmp qword [tk], ';'
    jne .out
    call next_token
.out:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---- struct / class ----------------------------------------------------------------------
; parse_aggregate: edi = visibility of the declaration. Current token struct/class.
parse_aggregate:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r15d, edi
    xor r14d, r14d
    cmp qword [tk], K_CLASS
    sete r14b
    xor eax, eax
    cmp qword [tk], K_UNION
    sete al
    mov [agg_union], eax
    call next_token
    cmp qword [tk], T_ID
    je .n1
    ERR "expected a class or struct name"
.n1:
    mov r12, [tk_ptr]
    mov r13d, [tk_len]
    cmp dword [pass], 1
    jne .p2
    mov eax, [struct_count]
    cmp eax, STRUCT_MAX
    jae err_toobig
    mov ebx, eax
    inc dword [struct_count]
    shl rax, 5
    add rax, struct_tab
    mov [rax+ST_NAME], r12
    mov [rax+ST_NLEN], r13d
    mov ecx, [field_count]
    mov [rax+ST_FIRST], ecx
    mov dword [rax+ST_NFIELDS], 0
    mov dword [rax+ST_SIZE], 0
    mov [rax+ST_ISCLASS], r14d
    mov rdi, r12
    mov esi, r13d
    mov edx, S_STRUCT
    call sym_new
    mov [rax+SYM_VAL], rbx
    test r15d, r15d
    jz .s1
    or dword [rax+SYM_FLAGS], F_PRIVATE
.s1:
    jmp .named
.p2:
    mov rdi, r12
    mov esi, r13d
    mov edx, [cur_module]
    call sym_find_global
    test rax, rax
    jnz .p2ok
    ERR "internal error: type not found in pass 2"
.p2ok:
    mov rbx, [rax+SYM_VAL]
.named:
    mov r15d, r14d                  ; default member visibility: classes private
    call next_token
    cmp qword [tk], ':'
    jne .nobase
    ; class D : B  - single inheritance, the base class must be complete
    call next_token
    call parse_type
    movzx ecx, al
    cmp ecx, TY_STRUCT
    jne .badbase
    test eax, 0xFF00
    jnz .badbase
    shr rax, 16
    and eax, 0xFFFF
    mov r12d, eax
    cmp r12d, ebx
    je .badbase
    mov rax, r12
    shl rax, 5
    add rax, struct_tab
    cmp dword [rax+ST_SIZE], 0
    jne .base_ok
    ERR "the base class must be defined before the derived class"
.badbase:
    ERR "expected the name of a class after ':'"
.base_ok:
    cmp dword [pass], 1
    jne .nobase
    lea eax, [r12+1]
    mov [st_base + rbx*4], eax
.nobase:
    cmp qword [tk], ';'
    jne .body
    jmp next_token_ret
.body:
    mov edi, '{'
    call expect
    mov [cur_class], ebx
    cmp dword [pass], 1
    jne .mloop
    mov eax, [st_base + rbx*4]
    test eax, eax
    jz .mloop
    lea esi, [rax-1]
    mov edi, ebx
    call inherit_base
.mloop:
    cmp qword [tk], '}'
    je .mend
    cmp qword [tk], T_EOF
    jne .m0
    ERR "unexpected end of file in class body"
.m0:
    mov [agg_vis], r15d
    cmp qword [tk], K_PUBLIC
    jne .m1
    mov dword [agg_vis], 0
    jmp .mod
.m1:
    cmp qword [tk], K_PRIVATE
    jne .m1b
    mov dword [agg_vis], 1
    jmp .mod
.m1b:
    cmp qword [tk], K_PROTECTED
    jne .nomod
    mov dword [agg_vis], 2
.mod:
    call next_token
    cmp qword [tk], ':'
    jne .nomod
    call next_token
    mov eax, [agg_vis]
    mov r15d, eax
    jmp .mloop
.nomod:
    mov dword [agg_virtual], 0
    cmp qword [tk], K_VIRTUAL
    jne .nv
    mov dword [agg_virtual], 1
    call next_token
.nv:
    ; constructor?  (identifier equal to the class name)
    cmp qword [tk], T_ID
    jne .typed
    mov rax, rbx
    shl rax, 5
    add rax, struct_tab
    mov rdi, [tk_ptr]
    mov esi, [tk_len]
    mov rdx, [rax+ST_NAME]
    mov ecx, [rax+ST_NLEN]
    call names_eq
    test eax, eax
    jz .typed
    ; same name as the class: constructor only when '(' follows
    mov rax, [tk_ptr]
    mov [agg_mname], rax
    mov eax, [tk_len]
    mov [agg_mnlen], eax
    sub rsp, 128
    mov rdi, rsp
    call lex_save
    call next_token
    cmp qword [tk], '('
    je .isctor
    mov rsi, rsp
    call lex_restore
    add rsp, 128
    jmp .typed
.isctor:
    add rsp, 128
    mov qword [agg_mtype], TY_VOID
    mov dword [agg_isctor], 1
    jmp .method
.typed:
    mov dword [agg_isctor], 0
    call parse_type
    mov [agg_mtype], rax
    cmp qword [tk], T_ID
    je .t1
    ERR "expected a member name"
.t1:
    mov rax, [tk_ptr]
    mov [agg_mname], rax
    mov eax, [tk_len]
    mov [agg_mnlen], eax
    call next_token
    cmp qword [tk], '('
    je .method
; ---- field
    cmp dword [pass], 1
    je .f1
    call skip_to_semi
    jmp .mloop
.f1:
    mov r13, [agg_mtype]
    mov rdi, r13
    call type_ls
    mov r14d, eax                       ; 1 = byte aligned
    cmp qword [tk], '['
    jne .fscalar
    call next_token
    call const_expr
    test rax, rax
    jg .fa
    ERR "array size must be positive"
.fa:
    mov r12, rax
    mov edi, ']'
    call expect
    mov rdi, r13
    call type_size
    imul rax, r12
    add r13, TY_PTR1
    bts r13, TF_ARRAY_BIT
    jmp .fsize
.fscalar:
    mov rdi, r13
    call type_size
.fsize:
    mov r12, rax                        ; size
    mov rax, rbx
    shl rax, 5
    add rax, struct_tab
    mov ecx, [rax+ST_SIZE]
    mov edx, 8
    cmp r14d, 1
    jne .fal
    mov edx, 1
.fal:
    lea rsi, [rdx-1]
    add rcx, rsi
    not rsi
    and rcx, rsi                        ; aligned offset
    cmp dword [agg_union], 0
    je .notunion
    xor ecx, ecx                        ; every member of a union starts at offset 0
.notunion:
    ; new field entry
    mov esi, [field_count]
    cmp esi, FIELD_MAX
    jae err_toobig
    inc dword [field_count]
    mov rdi, rsi
    shl rdi, 5
    add rdi, field_tab
    mov rdx, [agg_mname]
    mov [rdi+FD_NAME], rdx
    mov edx, [agg_mnlen]
    mov [rdi+FD_NLEN], edx
    mov edx, [agg_vis]
    mov [rdi+FD_VIS], edx
    mov [rdi+FD_OWNER], ebx
    mov [rdi+FD_TYPE], r13
    mov [rdi+FD_OFFSET], ecx
    inc dword [rax+ST_NFIELDS]
    add rcx, r12
    cmp dword [agg_union], 0
    je .setsize
    cmp ecx, [rax+ST_SIZE]              ; the size of a union is the size of its largest member
    jbe .nosize
.setsize:
    mov [rax+ST_SIZE], ecx
.nosize:
    mov edi, ';'
    call expect
    jmp .mloop
; ---- method / constructor
.method:
    call parse_params
    mov r8d, F_METHOD
    cmp dword [agg_vis], 0
    je .mf1
    cmp dword [agg_vis], 2
    je .mfp
    or r8d, F_PRIVATE
    jmp .mf1
.mfp:
    or r8d, F_PROTECTED
.mf1:
    cmp dword [agg_isctor], 0
    je .mf2
    or r8d, F_CTOR
.mf2:
    mov rdi, [agg_mname]
    mov esi, [agg_mnlen]
    mov rdx, [agg_mtype]
    mov ecx, ebx
    call func_register
    mov r13, rax
    cmp dword [pass], 1
    jne .nov
    call register_virtual
.nov:
    cmp qword [tk], ';'
    jne .mb
    call next_token
    jmp .mloop
.mb:
    cmp qword [tk], '{'
    je .mb1
    ERR "expected '{' or ';' after the method declaration"
.mb1:
    cmp dword [pass], 1
    jne .mb2
    test dword [r13+SYM_FLAGS], F_DEFINED
    jz .mb3
    mov edi, msg_redef
    mov rax, [agg_mname]
    mov [tk_ptr], rax
    mov eax, [agg_mnlen]
    mov [tk_len], eax
    call fatal_error_tok
.mb3:
    or dword [r13+SYM_FLAGS], F_DEFINED
    call skip_block
    jmp .mloop
.mb2:
    mov rdi, r13
    call compile_function
    jmp .mloop
.mend:
    call next_token
    mov dword [cur_class], -1
    cmp dword [pass], 1
    jne .semi
    mov rax, rbx
    shl rax, 5
    add rax, struct_tab
    mov ecx, [rax+ST_SIZE]
    add ecx, 7
    and ecx, -8
    jnz .sz
    mov ecx, 8
.sz:
    mov [rax+ST_SIZE], ecx
    ; the vtable of a class with virtual methods: one code address per slot, filled in by the linker
    mov r12d, [st_vcount + rbx*4]
    test r12d, r12d
    jz .semi
    lea rdi, [r12*8]
    mov esi, 8
    call data_alloc
    lea ecx, [rax+1]
    mov [st_vt + rbx*4], ecx
    mov r13d, eax
    xor r14d, r14d
.vt:
    cmp r14d, r12d
    jae .semi
    mov rax, rbx
    shl rax, 6
    add rax, r14
    mov edx, [vt_method + rax*4]
    lea edi, [r13 + r14*8]
    mov esi, R_CODE64
    call add_reloc
    inc r14d
    jmp .vt
.semi:
    cmp qword [tk], ';'
    jne .out
    call next_token
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
next_token_ret:
    call next_token
    jmp parse_aggregate.out

; inherit_base: edi = derived struct index, esi = base struct index. The derived class starts with a
; copy of the fields (and the vtable layout) of its base, so the base part lives at offset 0.
inherit_base:
    push rbx
    push r12
    mov r8d, edi
    mov r9d, esi
    mov rax, r8
    shl rax, 5
    add rax, struct_tab
    mov r10, rax                        ; derived entry
    mov rax, r9
    shl rax, 5
    add rax, struct_tab                 ; base entry
    mov ecx, [rax+ST_NFIELDS]
    mov [r10+ST_NFIELDS], ecx
    mov edx, [rax+ST_SIZE]
    mov [r10+ST_SIZE], edx
    mov esi, [rax+ST_FIRST]
    mov edi, [field_count]
    mov [r10+ST_FIRST], edi
    ; copy the field entries
    lea edx, [rdi+rcx]
    cmp edx, FIELD_MAX
    jae err_toobig
    mov [field_count], edx
    mov rdx, rsi
    shl rdx, 5
    add rdx, field_tab
    shl rdi, 5
    add rdi, field_tab
    mov rsi, rdx
    shl ecx, 5
    rep movsb
    ; vtable layout
    mov eax, [st_vptr + r9*4]
    mov [st_vptr + r8*4], eax
    mov ecx, [st_vcount + r9*4]
    mov [st_vcount + r8*4], ecx
    mov rsi, r9
    shl rsi, 6
    lea rsi, [vt_method + rsi*4]
    mov rdi, r8
    shl rdi, 6
    lea rdi, [vt_method + rdi*4]
    rep movsd
    pop r12
    pop rbx
    ret

; register_virtual: r13 = method symbol just registered, ebx = class (pass 1). A method with the name of a
; virtual method of a base class overrides it; otherwise 'virtual' gives it a new vtable slot.
register_virtual:
    test dword [r13+SYM_FLAGS], F_CTOR | F_VIRTUAL
    jnz .ret
    mov eax, [st_base + rbx*4]
    test eax, eax
    jz .own
    lea edi, [rax-1]
    mov rsi, [agg_mname]
    mov edx, [agg_mnlen]
    call struct_find_method
    test rax, rax
    jz .own
    test dword [rax+SYM_FLAGS], F_VIRTUAL
    jz .own
    sub rax, symtab
    shr rax, 6
    mov ecx, [sym_vslot + rax*4]       ; override: same slot
    jmp .set
.own:
    cmp dword [agg_virtual], 0
    je .ret
    mov ecx, [st_vcount + rbx*4]
    cmp ecx, VT_MAX
    jb .room
    ERR "too many virtual methods in one class"
.room:
    inc dword [st_vcount + rbx*4]
    cmp dword [st_vptr + rbx*4], 0
    jne .set
    ; the first virtual method of the hierarchy: reserve room for the vtable pointer
    mov rax, rbx
    shl rax, 5
    add rax, struct_tab
    mov edx, [rax+ST_SIZE]
    add edx, 7
    and edx, -8
    lea esi, [rdx+1]
    mov [st_vptr + rbx*4], esi
    add edx, 8
    mov [rax+ST_SIZE], edx
.set:
    or dword [r13+SYM_FLAGS], F_VIRTUAL
    mov rax, r13
    sub rax, symtab
    shr rax, 6
    mov [sym_vslot + rax*4], ecx
    mov rdx, rbx
    shl rdx, 6
    add rdx, rcx
    mov [vt_method + rdx*4], eax
.ret:
    ret

; ---- module / import -------------------------------------------------------------------------
parse_module:
    push rbx
    call next_token
    cmp qword [tk], T_ID
    je .n1
    ERR "expected a module name"
.n1:
    call module_enter
    call next_token
    mov edi, ';'
    call expect
    pop rbx
    ret

; module_enter: the current token is the module name. Finds or creates the module and makes it the
; current one -> eax = the module that was current before
module_enter:
    push rbx
    mov rdi, [tk_ptr]
    mov esi, [tk_len]
    xor edx, edx
    call sym_find_global
    test rax, rax
    jz .create
    cmp dword [rax+SYM_KIND], S_MODULE
    je .have
    mov edi, msg_kindmix
    call fatal_error_tok
.create:
    mov ebx, [cur_module]
    mov dword [cur_module], 0
    mov rdi, [tk_ptr]
    mov esi, [tk_len]
    mov edx, S_MODULE
    call sym_new
    mov [cur_module], ebx
    inc dword [next_module_id]
    mov ecx, [next_module_id]
    mov [rax+SYM_VAL], rcx
.have:
    mov ecx, [rax+SYM_VAL]
    mov eax, [cur_module]
    mov [cur_module], ecx
    pop rbx
    ret

; a_module NAME { declarations }
parse_amodule:
    push rbx
    cmp dword [in_amodule], 0
    je .ok0
    ERR "a_module blocks cannot be nested"
.ok0:
    call next_token
    cmp qword [tk], T_ID
    je .n1
    ERR "expected a module name after 'a_module'"
.n1:
    call module_enter
    mov ebx, eax
    call next_token
    mov edi, '{'
    call expect
    mov dword [in_amodule], 1
    call parse_items
    mov dword [in_amodule], 0
    cmp qword [tk], '}'
    je .close
    ERR "expected '}' at the end of the a_module block"
.close:
    mov [cur_module], ebx
    call next_token
    pop rbx
    ret

; a_import('file.am');   a_import('file.am', 'name1, name2');   a_import('file.am', '*');
; The names in the second string are also made available without the module prefix.
parse_aimport:
    push rbx
    sub rsp, 1024                       ; the name list lives on the stack: nested imports reuse the buffers
    mov dword [sq_string], 1
    call next_token
    mov edi, '('
    call expect
    cmp qword [tk], T_STR
    je .s1
    ERR "a_import needs the file name of the module as a string, for example a_import('math.am');"
.s1:
    mov rsi, [tk_ptr]
    mov ecx, [tk_len]
    cmp ecx, 500
    jb .s2
    ERR "import path too long"
.s2:
    mov rdi, importbuf
    rep movsb
    mov byte [rdi], 0
    mov byte [rsp], 0
    call next_token
    cmp qword [tk], ','
    jne .noargs
    call next_token
    cmp qword [tk], T_STR
    je .n1
    ERR "the second argument of a_import is a string with the names to import"
.n1:
    mov rsi, [tk_ptr]
    mov ecx, [tk_len]
    cmp ecx, 1000
    jb .n2
    ERR "import name list too long"
.n2:
    mov rdi, rsp
    rep movsb
    mov byte [rdi], 0
    call next_token
.noargs:
    mov dword [sq_string], 0
    mov edi, ')'
    call expect
    call file_include
    cmp dword [pass], 1
    jne .semi
    cmp byte [rsp], 0
    je .semi
    mov rdi, rsp
    call import_names
.semi:
    mov edi, ';'
    call expect
    add rsp, 1024
    pop rbx
    ret

CSTR msg_noimport, "the module has no public member called"

; import_names: makes the names listed in selbuf (separated by commas / blanks) of the file that was
; just imported (last_file_id) usable without the module prefix. '*' = every public member.
import_names:
    push rbx
    push r12
    push r13
    mov rbx, rdi
.next:
    movzx eax, byte [rbx]
    test al, al
    jz .done
    cmp al, ' '
    jbe .sep
    cmp al, ','
    je .sep
    cmp al, ';'
    je .sep
    mov r12, rbx
.scan:
    movzx eax, byte [rbx]
    test al, al
    jz .got
    cmp al, ' '
    jbe .got
    cmp al, ','
    je .got
    cmp al, ';'
    je .got
    inc rbx
    jmp .scan
.got:
    mov r13, rbx
    sub r13, r12
    cmp r13d, 1
    jne .one
    cmp byte [r12], '*'
    jne .one
    call import_all
    jmp .next
.one:
    mov rdi, r12
    mov esi, r13d
    call import_find
    test rax, rax
    jnz .have
    mov [tk_ptr], r12
    mov [tk_len], r13d
    mov edi, msg_noimport
    call fatal_error_tok
.have:
    mov rdi, rax
    xor esi, esi
    call import_alias
    jmp .next
.sep:
    inc rbx
    jmp .next
.done:
    pop r13
    pop r12
    pop rbx
    ret

; import_find: rdi = name, esi = length -> rax = public symbol of that name declared in the imported file (or 0)
import_find:
    mov r8, rdi
    mov r9d, esi
    mov eax, [sym_count]
.l:
    test eax, eax
    jz .none
    dec eax
    mov r10, rax
    shl r10, 6
    add r10, symtab
    cmp [r10+SYM_NLEN], r9d
    jne .l
    mov edx, [last_file_id]
    cmp [r10+SYM_FILE], edx
    jne .l
    call import_ok
    test ecx, ecx
    jz .l
    mov rdi, [r10+SYM_NAME]
    mov rsi, r8
    mov ecx, r9d
    repe cmpsb
    jne .l
    mov rax, r10
    ret
.none:
    xor eax, eax
    ret

; import_ok: r10 = symbol -> ecx = 1 if it can be imported by name (a public global, constant, function, type)
import_ok:
    xor ecx, ecx
    mov edx, [r10+SYM_KIND]
    cmp edx, S_GLOBAL
    jb .no
    cmp edx, S_TYPEDEF
    ja .no
    cmp edx, S_MODULE
    je .no
    test dword [r10+SYM_FLAGS], F_METHOD | F_PRIVATE | F_BUILTIN
    jnz .no
    mov ecx, 1
.no:
    ret

; import_alias: rdi = symbol, esi = 1 to skip names that already exist (for '*')
import_alias:
    push rbx
    push r12
    mov rbx, rdi
    mov r12d, esi
    mov rdi, [rbx+SYM_NAME]
    mov esi, [rbx+SYM_NLEN]
    mov edx, [cur_module]
    call sym_find_global
    test rax, rax
    jz .make
    test r12d, r12d
    jnz .out
    mov rax, [rbx+SYM_NAME]
    mov [tk_ptr], rax
    mov eax, [rbx+SYM_NLEN]
    mov [tk_len], eax
    mov edi, msg_redef
    call fatal_error_tok
.make:
    mov rdi, [rbx+SYM_NAME]
    mov esi, [rbx+SYM_NLEN]
    mov edx, S_ALIAS
    call sym_new
    mov rcx, rbx
    sub rcx, symtab
    shr rcx, 6
    mov [rax+SYM_VAL], rcx
.out:
    pop r12
    pop rbx
    ret

; import_all: aliases every public member of the imported file
import_all:
    push rbx
    push r12
    xor ebx, ebx
    mov r12d, [sym_count]
.l:
    cmp ebx, r12d
    jae .done
    mov r10, rbx
    shl r10, 6
    add r10, symtab
    mov edx, [last_file_id]
    cmp [r10+SYM_FILE], edx
    jne .n
    call import_ok
    test ecx, ecx
    jz .n
    mov rdi, r10
    mov esi, 1
    call import_alias
.n:
    inc ebx
    jmp .l
.done:
    pop r12
    pop rbx
    ret

; parse_import:  import name;   import a.b.c;   import "file.a";
parse_import:
    push rbx
    push r12
    call next_token
    mov r12, importbuf
    cmp qword [tk], T_STR
    je .str
    cmp qword [tk], T_ID
    je .id
    ERR "expected a module name or a file name string after 'import'"
.str:
    mov rsi, [tk_ptr]
    mov ecx, [tk_len]
    cmp ecx, 500
    jb .s1
    ERR "import path too long"
.s1:
    mov rdi, r12
    rep movsb
    mov byte [rdi], 0
    call next_token
    jmp .go
.id:
    mov rsi, [tk_ptr]
    mov ecx, [tk_len]
    cmp ecx, 200
    jb .i1
    ERR "import path too long"
.i1:
    mov rdi, r12
    rep movsb
    mov r12, rdi
    call next_token
    cmp qword [tk], '.'
    jne .idend
    mov byte [r12], '/'
    inc r12
    call next_token
    cmp qword [tk], T_ID
    je .id
    ERR "expected a name after '.' in import"
.idend:
    mov dword [r12], 0x0000612E          ; ".a"
.go:
    call file_include
    mov edi, ';'
    call expect
    pop r12
    pop rbx
    ret

; ---- global variables ------------------------------------------------------------------
; parse_global_vars: r12 = base type, name in agg_mname/agg_mnlen, vis in agg_vis,
; current token after the first name.
parse_global_vars:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, [agg_gtype]
    cmp dword [pass], 1
    je .again
    call skip_to_semi
    jmp .out
.again:
    mov rbx, r12
    xor r14d, r14d                      ; element count (0 = scalar)
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
    ; an object with virtual methods lives in the data section so that its vtable pointer can be set
    mov rdi, rbx
    call type_vptr
    test eax, eax
    jz .plainbss
    dec eax
    mov r13d, eax                       ; offset of the pointer inside the object
    mov rdi, r15
    mov esi, 8
    call data_alloc
    mov r9, rax
    mov rdx, rbx
    shr edx, 16
    mov edx, [st_vt + rdx*4]
    dec edx
    lea rcx, [r9 + r13]
    mov [data_buf + rcx], rdx
    mov edi, ecx
    mov esi, R_DATA64
    xor edx, edx
    push r9
    call add_reloc
    pop r13
    xor edx, edx
    jmp .reg
.plainbss:
    ; zero initialised -> bss
    mov rdi, r15
    mov esi, 8
    call bss_alloc
    mov r13, rax
    mov r13d, r13d
    mov edx, F_BSS
    jmp .reg
.init:
    bt rbx, TF_ARRAY_BIT
    jnc .i0
    ERR "array initializers are not supported, assign the elements in code"
.i0:
    call next_token
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
    ; pointer to a string: needs the final data address
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
    push r13
    mov edx, S_GLOBAL
    call sym_new
    pop r13
    pop rdx
    mov [rax+SYM_TYPE], rbx
    mov [rax+SYM_VAL], r13
    or [rax+SYM_FLAGS], edx
    mov [rax+SYM_EXTRA], r14
    cmp dword [agg_vis], 0
    je .v1
    or dword [rax+SYM_FLAGS], F_PRIVATE
.v1:
    cmp qword [tk], ','
    jne .end
    call next_token
    cmp qword [tk], T_ID
    je .c1
    ERR "expected a variable name"
.c1:
    mov rax, [tk_ptr]
    mov [agg_mname], rax
    mov eax, [tk_len]
    mov [agg_mnlen], eax
    call next_token
    jmp .again
.end:
    mov edi, ';'
    call expect
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---- top level -------------------------------------------------------------------------------
parse_items:
    push rbx
    push r12
    push r13
    push r14
    push r15
.loop:
    cmp qword [tk], T_EOF
    je .done
    cmp dword [in_amodule], 0
    je .toplvl
    cmp qword [tk], '}'
    je .done
.toplvl:
    xor ebx, ebx
    cmp qword [tk], K_PUBLIC
    jne .v1
    call next_token
    jmp .vdone
.v1:
    cmp qword [tk], K_PRIVATE
    jne .v2
    mov ebx, 1
    call next_token
    jmp .vdone
.v2:
    cmp qword [tk], K_STATIC
    jne .vdone
    mov ebx, 1                          ; static = private to the file
    call next_token
.vdone:
    mov [agg_vis], ebx
    mov eax, [tk]
    cmp eax, K_IMPORT
    je .import
    cmp eax, K_MODULE
    je .module
    cmp eax, K_AMODULE
    je .amodule
    cmp eax, K_AIMPORT
    je .aimport
    cmp eax, K_STRUCT
    je .aggr
    cmp eax, K_CLASS
    je .aggr
    cmp eax, K_UNION
    je .aggr
    cmp eax, K_TYPEDEF
    je .typedef
    cmp eax, K_ENUM
    je .enum
    cmp eax, K_CONST
    je .const
    call is_type_start
    test eax, eax
    jnz .decl
    mov edi, msg_toplevel
    cmp qword [tk], T_ID
    je fatal_error_tok
    jmp fatal_error
.import:
    call parse_import
    jmp .loop
.module:
    call parse_module
    jmp .loop
.amodule:
    call parse_amodule
    jmp .loop
.aimport:
    call parse_aimport
    jmp .loop
.aggr:
    mov edi, ebx
    call parse_aggregate
    jmp .loop
.enum:
    mov edi, ebx
    call parse_enum
    jmp .loop
.typedef:
    cmp dword [pass], 1
    jne .tdskip
    call parse_typedef
    cmp dword [agg_vis], 0
    je .loop
    mov eax, [sym_count]
    dec eax
    shl rax, 6
    add rax, symtab
    or dword [rax+SYM_FLAGS], F_PRIVATE
    jmp .loop
.tdskip:
    call skip_to_semi
    jmp .loop
.const:
    cmp dword [pass], 1
    jne .cskip
    call parse_const_decl
    cmp dword [agg_vis], 0
    je .loop
    ; mark the constant just created as private
    mov eax, [sym_count]
    dec eax
    shl rax, 6
    add rax, symtab
    or dword [rax+SYM_FLAGS], F_PRIVATE
    jmp .loop
.cskip:
    call skip_to_semi
    jmp .loop
.decl:
    call parse_type
    mov [agg_gtype], rax
    mov r12, rax
    cmp qword [tk], T_ID
    je .d1
    ERR "expected a name"
.d1:
    mov rax, [tk_ptr]
    mov [agg_mname], rax
    mov eax, [tk_len]
    mov [agg_mnlen], eax
    call next_token
    cmp qword [tk], '('
    je .func
    call parse_global_vars
    jmp .loop
.func:
    call parse_params
    mov r8d, 0
    cmp dword [agg_vis], 0
    je .f1
    mov r8d, F_PRIVATE
.f1:
    mov rdi, [agg_mname]
    mov esi, [agg_mnlen]
    mov rdx, r12
    mov ecx, -1
    call func_register
    mov r13, rax
    cmp qword [tk], ';'
    jne .fb
    call next_token
    jmp .loop
.fb:
    cmp qword [tk], '{'
    je .fb1
    ERR "expected '{' or ';' after the function declaration"
.fb1:
    cmp dword [pass], 1
    jne .fb2
    test dword [r13+SYM_FLAGS], F_DEFINED
    jz .fb3
    mov edi, msg_redef
    mov rax, [agg_mname]
    mov [tk_ptr], rax
    mov eax, [agg_mnlen]
    mov [tk_len], eax
    call fatal_error_tok
.fb3:
    or dword [r13+SYM_FLAGS], F_DEFINED
    call skip_block
    jmp .loop
.fb2:
    mov rdi, r13
    call compile_function
    jmp .loop
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
