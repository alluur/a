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
    cmp qword [tk], ')'
    je .end
.p:
    call parse_type
    mov rbx, rax
    cmp rbx, TY_VOID
    jne .nv
    cmp qword [tk], ')'
    je .end
.nv:
    test ebx, 0xFF00
    jnz .ok
    cmp bl, TY_STRUCT
    jne .ok
    ERR "structs cannot be passed by value, use a pointer"
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
    call struct_find_ctor
    jmp .m3
.m2:
    mov edi, r15d
    mov rsi, r12
    mov edx, r13d
    call struct_find_method
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
    mov ecx, [ptmp_count]
    mov [rax+SYM_NPAR], ecx
    ; copy the parameter types into the pool
    mov rdx, [ptype_pos]
    lea rsi, [rdx+rcx]
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
    inc esi
    jmp .cp
.cpd:
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
    mov [rdi+SYM_VAL], rax
    mov eax, [rdi+SYM_PATCH]
    mov dword [rdi+SYM_PATCH], 0
    mov rsi, [code_pos]
    mov rdi, rax
    call patch_chain
    pop rdi
    pop rsi
    pop rax
    ret

; compile_function: rdi = function symbol, current token '{', ptmp_* holds the
; parameters of this declaration (pass 2 only)
compile_function:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13d, [sym_count]
    mov [cur_func], r12
    call define_function
    EM 0x55, 0x48, 0x89, 0xE5, 0x48, 0x81, 0xEC
    mov rax, [code_pos]
    mov [frame_patch], rax
    xor edi, edi
    call emit_d
    mov dword [frame_size], 0
    mov qword [ret_chain], 0
    mov dword [loop_sp], 0
    ; total number of stack slots = params (+ this)
    mov ebx, [r12+SYM_NPAR]
    xor r14d, r14d
    test dword [r12+SYM_FLAGS], F_METHOD
    jz .params
    inc ebx
    mov r14d, 1
    lea eax, [rbx-1]
    shl eax, 3
    add eax, 16
    mov [cur_this_off], eax
.params:
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
    lea edx, [rcx+r14]
    mov esi, ebx
    dec esi
    sub esi, edx
    shl esi, 3
    add esi, 16
    mov [rax+SYM_VAL], rsi
.pn:
    inc ecx
    jmp .pl
.pd:
    call parse_block
    EM 0x31, 0xC0
    mov rdi, [ret_chain]
    call patch_here
    EM 0xC9, 0xC3
    mov eax, [frame_size]
    add eax, 15
    and eax, -16
    mov rcx, [frame_patch]
    mov [code_buf+rcx], eax
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
    cmp dword [pass], 2
    je .skip
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
    cmp qword [tk], ';'
    jne .body
    jmp next_token_ret
.body:
    mov edi, '{'
    call expect
    mov [cur_class], ebx
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
    jne .nomod
    mov dword [agg_vis], 1
.mod:
    call next_token
    cmp qword [tk], ':'
    jne .nomod
    call next_token
    mov eax, [agg_vis]
    mov r15d, eax
    jmp .mloop
.nomod:
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
    mov rax, [tk_ptr]
    mov [agg_mname], rax
    mov eax, [tk_len]
    mov [agg_mnlen], eax
    mov qword [agg_mtype], TY_VOID
    mov dword [agg_isctor], 1
    call next_token
    cmp qword [tk], '('
    je .method
    ERR "a member named like its class must be a constructor"
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
    cmp dword [pass], 2
    jne .f1
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
    mov [rdi+FD_TYPE], r13
    mov [rdi+FD_OFFSET], ecx
    inc dword [rax+ST_NFIELDS]
    add rcx, r12
    mov [rax+ST_SIZE], ecx
    mov edi, ';'
    call expect
    jmp .mloop
; ---- method / constructor
.method:
    call parse_params
    mov r8d, F_METHOD
    cmp dword [agg_vis], 0
    je .mf1
    or r8d, F_PRIVATE
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

; ---- module / import -------------------------------------------------------------------------
parse_module:
    push rbx
    call next_token
    cmp qword [tk], T_ID
    je .n1
    ERR "expected a module name"
.n1:
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
    mov [cur_module], ecx
    call next_token
    mov edi, ';'
    call expect
    pop rbx
    ret

; parse_import:  import name;   import a.b.c;   import "file.a";
parse_import:
    push rbx
    push r12
    call next_token
    mov rdi, importbuf
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
    rep movsb
    call next_token
    cmp qword [tk], '.'
    jne .idend
    mov byte [rdi], '/'
    inc rdi
    call next_token
    cmp qword [tk], T_ID
    je .id
    ERR "expected a name after '.' in import"
.idend:
    mov dword [rdi], 0x0000612E          ; ".a"
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
    cmp dword [pass], 2
    jne .again
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
    xor ebx, ebx
    cmp qword [tk], K_PUBLIC
    jne .v1
    call next_token
    jmp .vdone
.v1:
    cmp qword [tk], K_PRIVATE
    jne .vdone
    mov ebx, 1
    call next_token
.vdone:
    mov [agg_vis], ebx
    mov eax, [tk]
    cmp eax, K_IMPORT
    je .import
    cmp eax, K_MODULE
    je .module
    cmp eax, K_STRUCT
    je .aggr
    cmp eax, K_CLASS
    je .aggr
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
.aggr:
    mov edi, ebx
    call parse_aggregate
    jmp .loop
.enum:
    mov edi, ebx
    call parse_enum
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
