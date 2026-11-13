; =============================================================================
;  foreach.asm - the foreach statement
;
;    foreach (T x in values) stmt           values: an array of known length, text (char*), a range a..b, a class
;    foreach (int i, T x in values) stmt    with a count() and get(i), or  (pointer, count)
;    foreach (x in values) stmt             the type of the variable is taken from the elements
;    foreach (T x in rev values) stmt       the same, last element first
;
;  The iterated expression is evaluated once into hidden locals; the loop variable is a copy of the current element
;  (or, when it is declared as a pointer to the element type, the address of the element). See docs/LANGUAGE.md.
;
;  Code shape (counted loops):   init counter ; top: if counter >= limit goto exit ; x = element ; body ;
;  continue: counter++ ; goto top ; exit:        (rev: the counter is decremented at the top and continue goes to the top)
; =============================================================================
section .rodata
w_in:       db "in", 0
w_rev:      db "rev", 0
w_strlen:   db "strlen", 0
w_get:      db "get", 0
w_cnt0:     db "count", 0
w_cnt1:     db "size", 0
w_cnt2:     db "len", 0
w_cnt3:     db "length", 0
align 8
fe_count_names: dq w_cnt0, w_cnt1, w_cnt2, w_cnt3, 0

section .text

%define FK_ARRAY        1       ; array of known length
%define FK_TEXT         2       ; char*, up to the NUL
%define FK_RANGE        3       ; a..b
%define FK_CLASS        4       ; class with count() and get(i) / operator[]
%define FK_PTRCNT       5       ; pointer and element count (also rev text)

; frame of parse_foreach (qwords)
%define FE_NAME         0       ; element variable: name pointer, length, declared type (-1 = infer)
%define FE_NLEN         8
%define FE_TYPE         16
%define FE_INAME        24      ; index variable (same layout)
%define FE_INLEN        32
%define FE_ITYPE        40
%define FE_HASIDX       48
%define FE_KIND         56
%define FE_REV          64
%define FE_ETYPE        72      ; element type
%define FE_ESIZE        80
%define FE_LEN          88      ; number of elements of an array
%define FE_HBASE        96      ; frame offsets of the hidden locals: base pointer / object, counter, limit
%define FE_HIDX         104
%define FE_HN           112
%define FE_VOFF         120     ; frame offsets of the variables
%define FE_IOFF         128
%define FE_VTYPE        136     ; type of the element variable
%define FE_REF          144     ; 1: the variable gets the address of the element
%define FE_CANREF       152
%define FE_GET          160     ; class protocol: method symbols
%define FE_CNTM         168
%define FE_SYM          176     ; symbol count to restore
%define FE_NULLCHK      184     ; the base pointer may be null: an empty loop
%define FE_TEXTREV      192     ; rev text: the length is computed first
%define FE_INCL         200     ; 1: a..=b
%define FE_BYTES        208

; fe_slot: a fresh 8 byte hidden local -> rax = its frame offset (negative)
fe_slot:
    add dword [frame_size], 8
    mov eax, [frame_size]
    neg eax
    movsxd rax, eax
    ret

; fe_decl: rdi = {name pointer, name length, type}. Reads  [type] name
fe_decl:
    push rbx
    mov rbx, rdi
    mov qword [rbx+16], -1
    call is_var_start                   ; foreach (var x in values): the same as leaving the type out
    test eax, eax
    jz .typed
    call next_token
    jmp .name
.typed:
    call is_type_start
    test eax, eax
    jz .name
    call parse_type
    mov [rbx+16], rax
.name:
    cmp qword [tk], T_ID
    je .ok
    ERR "expected the name of the foreach variable"
.ok:
    mov rax, [tk_ptr]
    mov [rbx], rax
    mov eax, [tk_len]
    mov [rbx+8], rax
    call next_token
    pop rbx
    ret

; fe_is_rev: eax = 1 when the current token is the word rev (and the program has nothing else called rev in sight)
fe_is_rev:
    cmp qword [tk], T_ID
    jne .no
    mov rdi, w_rev
    call tk_is_word
    test eax, eax
    jz .no
    mov rdi, [tk_ptr]
    mov esi, [tk_len]
    call sym_lookup
    test rax, rax
    jnz .no
    cmp dword [cur_class], -1
    je .yes
    mov edi, [cur_class]
    mov rsi, [tk_ptr]
    mov edx, [tk_len]
    call struct_find_field
    test rax, rax
    jnz .no
    mov edi, [cur_class]
    mov rsi, [tk_ptr]
    mov edx, [tk_len]
    call struct_find_method
    test rax, rax
    jnz .no
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; fe_find_method: edi = struct index, rsi = C string -> rax = method symbol or 0
fe_find_method:
    push rbx
    push r12
    mov ebx, edi
    mov r12, rsi
    mov rdi, rsi
    call cstrlen
    mov edx, eax
    mov edi, ebx
    mov rsi, r12
    call struct_find_method
    pop r12
    pop rbx
    ret

; fe_int_check: the value in A must be an integer (range bounds, counts)
fe_int_check:
    mov rdi, [e_type]
    call is_intlike
    test eax, eax
    jnz .ok
    ERR "foreach: a range bound or an element count must be an integer"
.ok:
    ret

parse_foreach:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, FE_BYTES
    mov rbx, rsp
    mov rdi, rbx
    xor eax, eax
    mov ecx, FE_BYTES / 8
    rep stosq
    mov eax, [sym_count]
    mov [rbx+FE_SYM], rax
    call next_token                     ; foreach
    mov edi, '('
    call expect
    lea rdi, [rbx+FE_NAME]
    call fe_decl
    cmp qword [tk], ','
    jne .noidx
    ; foreach (int i, T x in ...): the first name is the index
    mov rax, [rbx+FE_NAME]
    mov [rbx+FE_INAME], rax
    mov rax, [rbx+FE_NLEN]
    mov [rbx+FE_INLEN], rax
    mov rax, [rbx+FE_TYPE]
    mov [rbx+FE_ITYPE], rax
    mov qword [rbx+FE_HASIDX], 1
    call next_token
    lea rdi, [rbx+FE_NAME]
    call fe_decl
.noidx:
    cmp qword [tk], T_ID
    jne .noin
    mov rdi, w_in
    call tk_is_word
    test eax, eax
    jnz .in
.noin:
    ERR "expected 'in' after the foreach variable"
.in:
    call next_token
    call fe_is_rev
    mov [rbx+FE_REV], rax
    test eax, eax
    jz .iter
    call next_token
.iter:
    call parse_ternary
    cmp qword [tk], T_DOTDOT
    je .range
    cmp qword [tk], T_DOTDOTEQ
    je .range
    cmp qword [tk], ','
    je .ptrcount
    mov rax, [e_type]
    bt rax, TF_ARRAY_BIT
    jc .array
    test eax, 0xFF00
    jnz .ptr
    cmp al, TY_STRUCT
    je .classv
.bad:
    ERR "foreach needs an array, a range (a..b), text (char*) or a class with count() and get()"

; ---- a..b
.range:
    cmp qword [rbx+FE_HASIDX], 0
    je .rng1
    ERR "foreach over a range has one variable (the value); there is no separate index"
.rng1:
    call to_rvalue
    call fe_int_check
    call fe_slot
    mov [rbx+FE_HIDX], rax
    call fe_slot
    mov [rbx+FE_HN], rax
    mov rdi, [rbx+FE_HIDX]
    cmp qword [rbx+FE_REV], 0
    je .rng2
    mov rdi, [rbx+FE_HN]
.rng2:
    CG store_local_a                    ; rev: the lower bound goes to the limit slot, the counter starts at the upper bound
    xor eax, eax
    cmp qword [tk], T_DOTDOTEQ
    sete al
    mov [rbx+FE_INCL], rax              ; a..=b includes b
    call next_token                     ; .. or ..=
    call parse_ternary
    call to_rvalue
    call fe_int_check
    mov rdi, [rbx+FE_HN]
    cmp qword [rbx+FE_REV], 0
    je .rng3
    mov rdi, [rbx+FE_HIDX]
.rng3:
    CG store_local_a
    mov qword [rbx+FE_KIND], FK_RANGE
    mov qword [rbx+FE_ETYPE], TY_INT
    mov qword [rbx+FE_ESIZE], 8
    jmp .common

; ---- an array of known length
.array:
    mov rdi, rax
    call type_array_len
    test rax, rax
    jnz .arr1
    ERR "foreach: the length of this array is not known here; use foreach (T x in pointer, count)"
.arr1:
    mov [rbx+FE_LEN], rax
    call to_rvalue                      ; A = address of the first element
    mov rax, [e_type]
    sub rax, TY_PTR1
    mov [rbx+FE_ETYPE], rax
    mov rdi, rax
    call type_size
    mov [rbx+FE_ESIZE], rax
    call fe_slot
    mov [rbx+FE_HBASE], rax
    mov edi, eax
    CG store_local_a
    call fe_slot
    mov [rbx+FE_HIDX], rax
    mov qword [rbx+FE_KIND], FK_ARRAY
    mov qword [rbx+FE_CANREF], 1
    jmp .common

; ---- text or a pointer to a class
.ptr:
    cmp rax, TY_CHAR | TY_PTR1
    je .text
    mov ecx, eax
    and ecx, 0xFFFF
    cmp ecx, TY_STRUCT | TY_PTR1
    je .classp
    ERR "foreach over a pointer needs the number of elements: foreach (T x in pointer, count)"

.text:
    call to_rvalue
    call fe_slot
    mov [rbx+FE_HBASE], rax
    mov edi, eax
    CG store_local_a
    call fe_slot
    mov [rbx+FE_HIDX], rax
    mov qword [rbx+FE_ETYPE], TY_CHAR
    mov qword [rbx+FE_ESIZE], 1
    mov qword [rbx+FE_KIND], FK_TEXT
    mov qword [rbx+FE_CANREF], 1
    mov qword [rbx+FE_NULLCHK], 1       ; a null text is an empty text
    cmp qword [rbx+FE_REV], 0
    je .common
    ; rev text: the length is computed before the loop (after the null test), then it is a counted loop
    call fe_slot
    mov [rbx+FE_HN], rax
    mov qword [rbx+FE_KIND], FK_PTRCNT
    mov qword [rbx+FE_TEXTREV], 1
    jmp .common

; ---- pointer, count
.ptrcount:
    call to_rvalue
    mov rax, [e_type]
    test eax, 0xFF00
    jnz .pc1
    ERR "foreach (x in p, n): the value before the comma must be a pointer"
.pc1:
    sub rax, TY_PTR1
    mov [rbx+FE_ETYPE], rax
    cmp rax, TY_VOID
    jne .pc2
    ERR "foreach over a void* is not possible: cast it to a typed pointer"
.pc2:
    mov rdi, rax
    call type_size
    mov [rbx+FE_ESIZE], rax
    call fe_slot
    mov [rbx+FE_HBASE], rax
    mov edi, eax
    CG store_local_a
    call next_token                     ; ,
    call parse_ternary
    call to_rvalue
    call fe_int_check
    call fe_slot
    mov [rbx+FE_HN], rax
    mov edi, eax
    CG store_local_a
    call fe_slot
    mov [rbx+FE_HIDX], rax
    mov qword [rbx+FE_KIND], FK_PTRCNT
    mov qword [rbx+FE_CANREF], 1
    jmp .common

; ---- a class (value or pointer) with count() / size() / len() / length() and get(i) / operator[](i)
.classv:
    call to_rvalue                      ; a class value is its address
    jmp .class
.classp:
    call to_rvalue
    mov qword [rbx+FE_NULLCHK], 1       ; a null pointer is an empty collection
.class:
    mov rax, [e_type]
    shr eax, 16
    and eax, 0xFFFF
    mov r12d, eax                       ; struct index
    xor r13d, r13d
.cnt:
    mov rsi, [fe_count_names + r13*8]
    test rsi, rsi
    jz .nocount
    mov edi, r12d
    call fe_find_method
    inc r13d
    test rax, rax
    jz .cnt
    cmp dword [rax+SYM_NPAR], 0
    jne .cnt
    mov [rbx+FE_CNTM], rax
    jmp .get
.nocount:
    ERR "foreach over a class needs a method count() (or size(), len(), length()) without parameters"
.get:
    mov edi, r12d
    mov rsi, w_get
    call fe_find_method
    test rax, rax
    jz .getop
    cmp dword [rax+SYM_NPAR], 1
    je .gotget
.getop:
    mov edi, r12d
    mov rsi, [opn_index]
    mov edx, 10
    call struct_find_method
    test rax, rax
    jz .noget
    cmp dword [rax+SYM_NPAR], 1
    je .gotget
.noget:
    ERR "foreach over a class needs a method get(int i) or an operator[](int i)"
.gotget:
    mov [rbx+FE_GET], rax
    ; the methods must be callable from here
    mov r12, rax
    call method_vis_ok
    test eax, eax
    jnz .vis1
    mov edi, msg_privmember
    call fatal_error_tok
.vis1:
    mov r12, [rbx+FE_CNTM]
    call method_vis_ok
    test eax, eax
    jnz .vis2
    mov edi, msg_privmember
    call fatal_error_tok
.vis2:
    mov rax, [rbx+FE_GET]
    mov rax, [rax+SYM_TYPE]
    mov [rbx+FE_ETYPE], rax
    test eax, eax
    jnz .gt1
    ERR "the get method of this class returns void"
.gt1:
    call fe_slot
    mov [rbx+FE_HBASE], rax
    mov edi, eax
    CG store_local_a                    ; the object is evaluated once
    call fe_slot
    mov [rbx+FE_HN], rax
    call fe_slot
    mov [rbx+FE_HIDX], rax
    mov qword [rbx+FE_KIND], FK_CLASS
    jmp .common

; ---- the variables
.common:
    mov edi, ')'
    call expect
    mov rax, [rbx+FE_TYPE]
    cmp rax, -1
    jne .vt
    mov rax, [rbx+FE_ETYPE]
.vt:
    mov [rbx+FE_VTYPE], rax
    mov rcx, [rbx+FE_ETYPE]
    cmp rax, rcx
    je .copy
    lea rdx, [rcx + TY_PTR1]
    cmp rax, rdx
    jne .notref
    cmp qword [rbx+FE_CANREF], 0
    jne .isref
    ERR "foreach over a class or a range gives values: the variable cannot be a pointer to the element"
.isref:
    mov qword [rbx+FE_REF], 1
    jmp .typed
.notref:
    ; both pointers: copy (pointer types convert freely); both plain scalars: copy with a conversion
    test eax, 0xFF00
    jnz .vptr
    cmp al, TY_STRUCT
    je .mismatch
    test ecx, 0xFF00
    jnz .mismatch
    cmp cl, TY_STRUCT
    je .mismatch
    jmp .copy
.vptr:
    test ecx, 0xFF00
    jnz .copy
.mismatch:
    ERR "the type of the foreach variable does not fit the type of the elements"
.copy:
.typed:
    cmp qword [rbx+FE_HASIDX], 0
    je .noivar
    mov rax, [rbx+FE_ITYPE]
    cmp rax, -1
    jne .it1
    mov eax, TY_INT
    mov [rbx+FE_ITYPE], rax
.it1:
    mov rdi, rax
    call is_intlike
    test eax, eax
    jnz .it2
    ERR "the index variable of foreach must be an integer"
.it2:
    call fe_slot
    mov [rbx+FE_IOFF], rax
    mov rdi, [rbx+FE_INAME]
    mov esi, [rbx+FE_INLEN]
    mov edx, S_LOCAL
    call sym_new
    mov rcx, [rbx+FE_ITYPE]
    mov [rax+SYM_TYPE], rcx
    mov rcx, [rbx+FE_IOFF]
    mov [rax+SYM_VAL], rcx
.noivar:
    ; the element variable (a struct is copied into a slot of its own size)
    mov r15d, 8
    cmp qword [rbx+FE_REF], 0
    jne .vsize
    mov rdi, [rbx+FE_VTYPE]
    call type_size
    add eax, 7
    and eax, -8
    mov r15d, eax
.vsize:
    add [frame_size], r15d
    mov eax, [frame_size]
    neg eax
    movsxd rax, eax
    mov [rbx+FE_VOFF], rax
    mov rdi, [rbx+FE_NAME]
    mov esi, [rbx+FE_NLEN]
    mov edx, S_LOCAL
    call sym_new
    mov rcx, [rbx+FE_VTYPE]
    cmp qword [rbx+FE_REF], 0
    je .vsym
    mov rcx, [rbx+FE_ETYPE]
    add rcx, TY_PTR1
.vsym:
    mov [rax+SYM_TYPE], rcx
    mov rcx, [rbx+FE_VOFF]
    mov [rax+SYM_VAL], rcx

    ; ---- the loop record, the null test, the length of a rev text, the count of a class
    xor edi, edi
    xor esi, esi
    call loop_push
    mov r12, rax
    cmp qword [rbx+FE_NULLCHK], 0
    je .nonull
    mov edi, [rbx+FE_HBASE]
    CG load_local_a
    mov rdi, r12
    CG jz_chain
.nonull:
    cmp qword [rbx+FE_TEXTREV], 0
    je .nostrlen
    mov edi, [rbx+FE_HBASE]
    CG load_local_a
    CG push_a
    mov rdi, w_strlen
    call emit_call_named
    mov edi, 1
    CG drop
    mov edi, [rbx+FE_HN]
    CG store_local_a
.nostrlen:
    cmp qword [rbx+FE_KIND], FK_CLASS
    jne .nocnt2
    mov edi, [rbx+FE_HBASE]
    CG load_local_a
    CG push_a
    mov dword [op_call], 2
    mov rdi, [rbx+FE_CNTM]
    mov esi, 1
    call gen_call                       ; the count is read once, before the first element
    mov edi, [rbx+FE_HN]
    CG store_local_a
.nocnt2:
    ; ---- initial counter
    mov rax, [rbx+FE_KIND]
    cmp rax, FK_RANGE
    je .ini_done
    cmp rax, FK_TEXT
    je .ini0
    cmp qword [rbx+FE_REV], 0
    je .ini0
    cmp rax, FK_ARRAY
    jne .inin
    mov rdi, [rbx+FE_LEN]
    CG imm_a
    jmp .inst
.inin:
    mov edi, [rbx+FE_HN]
    CG load_local_a
.inst:
    mov edi, [rbx+FE_HIDX]
    CG store_local_a
    jmp .ini_done
.ini0:
    xor edi, edi
    CG imm_a
    mov edi, [rbx+FE_HIDX]
    CG store_local_a
.ini_done:
    mov r13, [code_pos]                 ; the top of the loop
    cmp qword [rbx+FE_INCL], 0
    jne .lp                             ; a closed range tests for the last value before it steps: continue lands there
    cmp qword [rbx+FE_REV], 0
    je .lp
    mov [r12+16], r13                   ; rev: continue goes straight to the top
.lp:

    ; ---- the test at the top
    cmp qword [rbx+FE_INCL], 0
    je .c_open
    ; a..=b: the limit slot holds b itself (no b+1, which would wrap for the largest int); the loop ends when the counter is past it
    mov edi, [rbx+FE_HIDX]
    CG load_local_a
    mov edi, [rbx+FE_HN]
    CG load_local_b
    mov edi, CC_GT
    cmp qword [rbx+FE_REV], 0
    je .c_inc1
    mov edi, CC_LT
.c_inc1:
    mov rsi, r12
    CG jcmp_chain
    jmp .c_done
.c_open:
    mov rax, [rbx+FE_KIND]
    cmp rax, FK_TEXT
    je .c_text
    mov edi, [rbx+FE_HIDX]
    CG load_local_a
    cmp qword [rbx+FE_REV], 0
    jne .c_rev
    cmp qword [rbx+FE_KIND], FK_ARRAY           ; (rax does not survive the backend primitives on every CPU)
    jne .c_a1
    mov rdi, [rbx+FE_LEN]
    CG imm_b
    jmp .c_a2
.c_a1:
    mov edi, [rbx+FE_HN]
    CG load_local_b
.c_a2:
    mov edi, CC_GE
    mov rsi, r12
    CG jcmp_chain
    jmp .c_done
.c_rev:
    cmp qword [rbx+FE_KIND], FK_RANGE
    je .c_r1
    xor edi, edi
    CG imm_b
    jmp .c_r2
.c_r1:
    mov edi, [rbx+FE_HN]
    CG load_local_b
.c_r2:
    mov edi, CC_LE
    mov rsi, r12
    CG jcmp_chain
    mov edi, -1
    CG add_imm_a
    mov edi, [rbx+FE_HIDX]
    CG store_local_a
    jmp .c_done
.c_text:
    mov edi, [rbx+FE_HBASE]
    CG load_local_a
    CG load1_a
    mov rdi, r12
    CG jz_chain
.c_done:

    ; ---- the element
    mov rax, [rbx+FE_KIND]
    cmp rax, FK_CLASS
    je .f_class
    cmp rax, FK_RANGE
    je .f_range
    cmp rax, FK_TEXT
    je .f_text
    mov edi, [rbx+FE_HIDX]
    CG load_local_b
    mov rdi, [rbx+FE_ESIZE]
    cmp rdi, 1
    je .f_c1
    CG mul_imm_b
.f_c1:
    mov edi, [rbx+FE_HBASE]
    CG load_local_a
    CG add
    jmp .f_addr
.f_text:
    mov edi, [rbx+FE_HBASE]
    CG load_local_a
.f_addr:
    cmp qword [rbx+FE_REF], 0
    je .f_val
    mov edi, [rbx+FE_VOFF]
    CG store_local_a
    jmp .f_idx
.f_val:
    mov rdi, [rbx+FE_ETYPE]
    call emit_load_type
    jmp .f_store
.f_range:
    mov edi, [rbx+FE_HIDX]
    CG load_local_a
    jmp .f_store
.f_class:
    mov edi, [rbx+FE_HBASE]
    CG load_local_a
    CG push_a
    mov edi, [rbx+FE_HIDX]
    CG load_local_a
    mov qword [e_type], TY_INT
    mov dword [op_call], 1
    mov rdi, [rbx+FE_GET]
    mov esi, 1
    call gen_call
.f_store:
    mov rax, [rbx+FE_ETYPE]
    mov [e_type], rax
    mov rdi, [rbx+FE_VTYPE]
    call coerce_to
    mov rdi, [rbx+FE_VTYPE]
    call type_ls
    test eax, eax
    jz .f_agg
    mov edi, [rbx+FE_VOFF]
    mov rsi, [rbx+FE_VTYPE]
    call store_local_typed
    jmp .f_idx
.f_agg:
    mov edi, [rbx+FE_VOFF]
    CG lea_local_b
    mov rdi, [rbx+FE_VTYPE]
    call emit_store_type
.f_idx:
    cmp qword [rbx+FE_HASIDX], 0
    je .f_done
    mov edi, [rbx+FE_HIDX]
    CG load_local_a
    mov edi, [rbx+FE_IOFF]
    mov rsi, [rbx+FE_ITYPE]
    call store_local_typed
.f_done:

    ; ---- the body
    call parse_stmt
    cmp qword [rbx+FE_INCL], 0
    je .step_open
    ; a..=b: leave the loop after the last value; only otherwise step (the counter never goes past b, so nothing wraps)
    mov rdi, [r12+8]
    call patch_here                     ; continue lands here
    mov edi, [rbx+FE_HIDX]
    CG load_local_a
    mov edi, [rbx+FE_HN]
    CG load_local_b
    mov edi, CC_EQ
    mov rsi, r12
    CG jcmp_chain
    mov edi, [rbx+FE_HIDX]
    CG load_local_a
    mov edi, 1
    cmp qword [rbx+FE_REV], 0
    je .step_incl
    mov edi, -1
.step_incl:
    CG add_imm_a
    mov edi, [rbx+FE_HIDX]
    CG store_local_a
    jmp .back
.step_open:
    cmp qword [rbx+FE_REV], 0
    jne .back
    mov rdi, [r12+8]
    call patch_here                     ; continue lands here
    cmp qword [rbx+FE_KIND], FK_TEXT
    jne .inc_cnt
    mov edi, [rbx+FE_HBASE]
    CG load_local_a
    mov edi, 1
    CG add_imm_a
    mov edi, [rbx+FE_HBASE]
    CG store_local_a
.inc_cnt:
    mov edi, [rbx+FE_HIDX]
    CG load_local_a
    mov edi, 1
    CG add_imm_a
    mov edi, [rbx+FE_HIDX]
    CG store_local_a
.back:
    mov rdi, r13
    CG jmp_back
    mov rdi, [r12]
    call patch_here
    call loop_pop
    mov rax, [rbx+FE_SYM]
    mov [sym_count], eax
    add rsp, FE_BYTES
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
