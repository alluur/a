; =============================================================================
;  tuple.asm - tuples and multiple return values
;
;    (int, int) divmod(int a, int b) { return (a / b, a % b); }
;    (int q, int r) = divmod(7, 2);           declares q and r
;    var (q, r) = divmod(7, 2);               the same, the types are taken from the tuple
;    (a, b) = (b, a);                         assigns to variables that exist (all values are computed first: a swap)
;    (int, double) t = (1, 2);                a tuple variable; the literal is converted element by element
;    t.0   t.1                                the elements of a tuple
;
;  A tuple type is a hidden struct: element i is a field with the natural alignment of its type (the same rules as for a
;  struct) and the struct is made once for every list of element types (tuple_type looks for an existing one first), so
;  (int, int) is the same type everywhere. It is passed, returned and copied by value like any struct: a function that
;  returns a tuple gets the address of the result as a hidden last argument, a tuple argument is a copy made by the caller.
;
;  The fields of the hidden structs are kept at the top of field_tab (field_limit goes down), so that a tuple type made in
;  the middle of a class declaration does not split the fields of that class.
;
;  A tuple literal  (a, b, ...)  evaluates the elements left to right and pushes them; then the type is known, a temporary
;  is allocated in the frame and the elements are stored into it (the result is the temporary, an lvalue like a compound
;  literal). When the context knows the tuple type (return, initialization, assignment, argument) it is passed in
;  tup_expect and the elements are converted to the element types (int to double, ...); tup_expect_tok is the token where
;  the expression starts, so that only a literal that is the whole expression gets the expectation.
; =============================================================================
section .rodata
tup_name:       db "<tuple>", 0
tup_fname:      db "#", 0
w_underscore:   db "_", 0
CSTR msg_tup_mismatch, "tuple types do not match: both sides need the same number of elements with the same types (a tuple literal is converted element by element)"
CSTR msg_tup_void,     "a tuple element cannot be void"
CSTR msg_tup_many,     "too many tuple elements (at most 16)"
CSTR msg_tup_arity,    "this tuple has a different number of elements than the type that is expected here"
CSTR msg_tup_one,      "a tuple needs at least two elements"
CSTR msg_tup_notrhs,   "the value on the right of the tuple pattern is not a tuple (it has to come from a function that returns (T1, T2) or from a literal (a, b))"
CSTR msg_tup_patn,     "the tuple pattern has a different number of names than the tuple has elements"
CSTR msg_tup_lhs,      "a tuple assignment needs variables on the left side (things that can be assigned to)"
section .text

%define TUPLE_MAX       16

; type_is_tuple: rdi = type -> eax = 1 when it is a tuple (not a pointer to one)
type_is_tuple:
    xor eax, eax
    test edi, 0xFF00
    jnz .r
    cmp dil, TY_STRUCT
    jne .r
    mov ecx, edi
    shr ecx, 16
    and ecx, 0xFFFF
    test dword [st_flags + rcx*4], SF_TUPLE
    jz .r
    mov eax, 1
.r: ret

; tuple_field: rdi = tuple type, esi = element number -> rax = field entry
tuple_field:
    shr rdi, 16
    and edi, 0xFFFF
    shl rdi, 5
    add rdi, struct_tab
    mov eax, [rdi+ST_FIRST]
    add eax, esi
    shl rax, 5
    add rax, field_tab
    ret

; tuple_count: rdi = tuple type -> eax = number of elements
tuple_count:
    shr rdi, 16
    and edi, 0xFFFF
    shl rdi, 5
    mov eax, [struct_tab + rdi + ST_NFIELDS]
    ret

; tuple_type: rsi = pointer to n types (qwords), edx = n (2..16) -> rax = the tuple type, made when it does not exist yet
tuple_type:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rsi
    mov r13d, edx
    xor ebx, ebx
.s: cmp ebx, [struct_count]
    jae .make
    test dword [st_flags + rbx*4], SF_TUPLE
    jz .sn
    mov rax, rbx
    shl rax, 5
    add rax, struct_tab
    cmp [rax+ST_NFIELDS], r13d
    jne .sn
    mov ecx, [rax+ST_FIRST]
    shl rcx, 5
    add rcx, field_tab
    xor edx, edx
.sc:
    cmp edx, r13d
    jae .found
    mov rsi, [r12 + rdx*8]
    cmp rsi, [rcx+FD_TYPE]
    jne .sn
    add rcx, FD_SIZEOF
    inc edx
    jmp .sc
.found:
    mov rax, rbx
    shl rax, 16
    or rax, TY_STRUCT
    jmp .out
.sn:
    inc ebx
    jmp .s
.make:
    mov eax, [struct_count]
    cmp eax, STRUCT_MAX
    jae err_toobig
    mov ebx, eax
    inc dword [struct_count]
    mov eax, [field_limit]
    sub eax, r13d
    cmp eax, [field_count]
    jb err_toobig
    mov [field_limit], eax
    mov r14d, eax                       ; index of the first field
    mov rdi, rbx
    shl rdi, 5
    add rdi, struct_tab
    mov qword [rdi+ST_NAME], tup_name
    mov dword [rdi+ST_NLEN], 7
    mov [rdi+ST_FIRST], r14d
    mov [rdi+ST_NFIELDS], r13d
    mov dword [rdi+ST_ISCLASS], 0
    mov dword [rdi+ST_SYM], 0
    mov dword [st_flags + rbx*4], SF_TUPLE
    xor r15d, r15d                      ; running size
    xor ecx, ecx
.f: cmp ecx, r13d
    jae .fdone
    mov rdi, [r12 + rcx*8]
    call type_ls
    call ls_align
    mov esi, eax                        ; alignment (type_ls, ls_align and type_size only change eax)
    mov rdi, [r12 + rcx*8]
    call type_size                      ; rax = size
    lea rdi, [rsi-1]
    add r15, rdi
    not rdi
    and r15, rdi                        ; aligned offset
    mov r8, r14
    add r8, rcx
    shl r8, 5
    add r8, field_tab
    mov qword [r8+FD_NAME], tup_fname
    mov dword [r8+FD_NLEN], 1
    mov dword [r8+FD_VIS], 0
    mov rdx, [r12 + rcx*8]
    mov [r8+FD_TYPE], rdx
    mov [r8+FD_OFFSET], r15d
    mov [r8+FD_OWNER], ebx
    add r15, rax
    inc ecx
    jmp .f
.fdone:
    add r15, 7
    and r15, -8
    jnz .sz
    mov r15d, 8
.sz:
    mov rdi, rbx
    shl rdi, 5
    add rdi, struct_tab
    mov [rdi+ST_SIZE], r15d
    mov rax, rbx
    shl rax, 16
    or rax, TY_STRUCT
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; parse_tuple_type: the current token is '(' -> rax = the tuple type ( T1, T2, ... ), the token after ')' is current
parse_tuple_type:
    push rbx
    sub rsp, TUPLE_MAX * 8
    STACKCHK
    call next_token
    xor ebx, ebx
.e: call parse_type
    cmp rax, TY_VOID
    jne .e1
    ERR "a tuple element cannot be void"
.e1:
    cmp ebx, TUPLE_MAX
    jb .e2
    ERR "too many tuple elements (at most 16)"
.e2:
    mov [rsp + rbx*8], rax
    mov rdi, rax
    call check_concrete
    inc ebx
    cmp qword [tk], ','
    jne .close
    call next_token
    jmp .e
.close:
    mov edi, ')'
    call expect
    cmp ebx, 2
    jae .ok
    ERR "a tuple type needs at least two elements"
.ok:
    mov rsi, rsp
    mov edx, ebx
    call tuple_type
    add rsp, TUPLE_MAX * 8
    pop rbx
    ret

; tuple_start_la: the current token is '(' -> eax = 1 when a tuple type starts here: '(' type ',' ...  (a cast  (int)x  is no tuple)
tuple_start_la:
    push rbx
    STACKCHK
    sub rsp, 128
    mov rdi, rsp
    call lex_save
    call next_token
    xor ebx, ebx
    call is_type_start
    test eax, eax
    jz .back
    call parse_type
    cmp qword [tk], ','
    jne .back
    mov ebx, 1
.back:
    mov rsi, rsp
    call lex_restore
    add rsp, 128
    mov eax, ebx
    pop rbx
    ret

; tuple_expect_here: rdi = the type the expression that starts at the current token has to have. A tuple type is remembered
; so that a tuple literal at this very token is converted to it. (preserves rdi)
tuple_expect_here:
    test edi, 0xFF00
    jnz .r
    cmp dil, TY_STRUCT
    jne .r
    call type_is_tuple
    test eax, eax
    jz .r
    mov [tup_expect], rdi
    mov rax, [tk_start]
    mov [tup_expect_tok], rax
.r: ret

; tuple_check: rdi = the type wanted for the value in A (type e_type). A tuple on either side has to match exactly.
tuple_check:
    cmp rdi, [e_type]
    je .ok
    push rdi
    call type_is_tuple
    pop rdi
    test eax, eax
    jnz .bad
    mov rdi, [e_type]
    call type_is_tuple
    test eax, eax
    jz .ok
.bad:
    ERR "tuple types do not match: both sides need the same number of elements with the same types (a tuple literal is converted element by element)"
.ok:
    ret

; parse_tuple_rest: the first element of a literal has been parsed (A, e_type) and the current token is ','.
; rdi = the expected tuple type (0 = none). Leaves the literal in A (a temporary of the frame, e_lval = 1) and consumes the ')'.
parse_tuple_rest:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, TUPLE_MAX * 8
    mov r13, rdi
    xor ebx, ebx
    xor r14d, r14d
    test r13, r13
    jz .elem
    mov r14, r13                        ; expected tuple type
.elem:
    call to_rvalue
    test r13, r13
    jz .noexp
    mov rdi, r14
    call tuple_count
    cmp ebx, eax
    jb .e1
    ERR "this tuple has a different number of elements than the type that is expected here"
.e1:
    mov rdi, r14
    mov esi, ebx
    call tuple_field
    mov r15, [rax+FD_TYPE]
    mov rdi, r15
    call coerce_to
    mov rdi, r15
    call tuple_check
    mov [rsp + rbx*8], r15
    jmp .push
.noexp:
    mov rax, [e_type]
    cmp rax, TY_VOID
    jne .nv
    ERR "a tuple element cannot be void"
.nv:
    mov [rsp + rbx*8], rax
.push:
    CG push_a
    inc ebx
    cmp qword [tk], ','
    jne .done
    cmp ebx, TUPLE_MAX
    jb .more
    ERR "too many tuple elements (at most 16)"
.more:
    call next_token
    test r13, r13
    jz .parse
    mov rdi, r14
    call tuple_count
    cmp ebx, eax
    jae .parse
    mov rdi, r14
    mov esi, ebx
    call tuple_field
    mov rdi, [rax+FD_TYPE]
    call tuple_expect_here
.parse:
    call parse_assign
    jmp .elem
.done:
    mov edi, ')'
    call expect
    test r13, r13
    jz .mk
    mov rdi, r14
    call tuple_count
    cmp eax, ebx
    je .mk
    ERR "this tuple has a different number of elements than the type that is expected here"
.mk:
    mov rsi, rsp
    mov edx, ebx
    call tuple_type
    mov r12, rax                        ; the tuple type
    mov rdi, rax
    call type_size
    add [frame_size], eax
    mov r15d, [frame_size]
    neg r15                             ; frame offset of the temporary
    ; the elements are on the stack, the last one on top: store them from the end
    mov r13d, ebx
.st:
    test r13d, r13d
    jz .stdone
    dec r13d
    CG pop_a
    mov rdi, r12
    mov esi, r13d
    call tuple_field
    mov r14, rax
    mov esi, [r14+FD_OFFSET]
    lea edi, [r15 + rsi]
    CG lea_local_b
    mov rdi, [r14+FD_TYPE]
    call emit_store_type
    jmp .st
.stdone:
    mov edi, r15d
    CG lea_local_a
    mov [e_type], r12
    mov qword [e_lval], 1
    add rsp, TUPLE_MAX * 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; tuple_peek_char: eax = the first character after the current token that is not white space
tuple_peek_char:
    mov rsi, [src_ptr]
.l: movzx eax, byte [rsi]
    cmp eax, ' '
    je .n
    cmp eax, 9
    je .n
    cmp eax, 10
    je .n
    cmp eax, 13
    je .n
    ret
.n: inc rsi
    jmp .l

; tuple_stmt_kind: the current token is '('. eax = 1 when the statement is a pattern assignment  (a, b) = ...  (T a, T b) = ...
tuple_stmt_kind:
    push rbx
    push r12
    sub rsp, 128
    mov rdi, rsp
    call lex_save
    xor ebx, ebx                        ; depth
    xor r12d, r12d                      ; commas at depth 1
.l: mov rax, [tk]
    cmp rax, '('
    jne .a
    inc ebx
    jmp .nx
.a: cmp rax, ')'
    jne .b
    dec ebx
    jz .end
    jmp .nx
.b: cmp rax, ','
    jne .c
    cmp ebx, 1
    jne .nx
    inc r12d
    jmp .nx
.c: cmp rax, T_EOF
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
    test r12d, r12d
    jz .no
    cmp qword [tk], '='
    jne .no
    mov ebx, 1
    jmp .back
.no:
    xor ebx, ebx
.back:
    mov rsi, rsp
    call lex_restore
    add rsp, 128
    mov eax, ebx
    pop r12
    pop rbx
    ret

; tuple_pattern_check: edi = number of names in the pattern; the value on the right is in A (type e_type)
tuple_pattern_check:
    push rbx
    mov ebx, edi
    mov rdi, [e_type]
    call type_is_tuple
    test eax, eax
    jnz .t
    ERR "the value on the right of the tuple pattern is not a tuple (it has to come from a function that returns (T1, T2) or from a literal (a, b))"
.t: mov rdi, [e_type]
    call tuple_count
    cmp eax, ebx
    je .ok
    ERR "the tuple pattern has a different number of names than the tuple has elements"
.ok:
    pop rbx
    ret

; frame of the pattern statements (qwords)
%define TS_TYPE         0               ; per element: the declared type (-1 = taken from the tuple) / the type of the target (0 = discarded)
%define TS_NAME         128             ; per element: name pointer (0 = discard with _)
%define TS_NLEN         256
%define TS_N            384
%define TS_TUPLE        392             ; the type of the tuple on the right
%define TS_BYTES        400

; parse_var_tuple: after  var  the current token is '('.   var (a, b) = value;
parse_var_tuple:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, TS_BYTES
    mov rbx, rsp
    mov r15d, 1                         ; names only
    call next_token
    jmp parse_tuple_decl_go

; parse_tuple_stmt: the current token is '(' of a pattern assignment (see tuple_stmt_kind)
parse_tuple_stmt:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, TS_BYTES
    mov rbx, rsp
    xor r15d, r15d
    call next_token
    ; declaration or assignment?  Look at the first element that is not a plain _ : a type or var in front of a name
    sub rsp, 128
    mov rdi, rsp
    call lex_save
.skip:
    cmp qword [tk], T_ID
    jne .look
    mov rdi, w_underscore
    call tk_is_word
    test eax, eax
    jz .look
    call tuple_peek_char
    cmp eax, ','
    jne .look
    call next_token
    call next_token
    jmp .skip
.look:
    cmp qword [tk], '('
    jne .look2
    call next_token                     ; ( (int a, int b), c ) = ... : a nested pattern
    call is_var_start
    test eax, eax
    jnz .nested
    call is_type_start
    test eax, eax
    jnz .nested
    xor r12d, r12d
    jmp .la_done
.nested:
    mov r12d, 2
    jmp .la_done
.look2:
    call is_var_start
    mov r12d, eax
    test eax, eax
    jnz .la_done
    call is_type_start
    mov r12d, eax
.la_done:
    mov rsi, rsp
    call lex_restore
    add rsp, 128
    cmp r12d, 2
    jne .form
    ERR "a tuple pattern cannot be nested: write (a, b) = value; for the elements that are tuples themselves use a variable"
.form:
    test r12d, r12d
    jnz parse_tuple_decl_go
    jmp parse_tuple_assign

; the declaration form: names (with types or var) are read, then the value, then the variables are declared in order
parse_tuple_decl_go:
    xor r12d, r12d
.dl:
    cmp r12d, TUPLE_MAX
    jb .d0
    ERR "too many names in the tuple pattern (at most 16)"
.d0:
    mov qword [rbx + TS_TYPE + r12*8], -1
    cmp qword [tk], T_ID                ; a plain _ : the element is not wanted
    jne .d0a
    mov rdi, w_underscore
    call tk_is_word
    test eax, eax
    jz .d0a
    call tuple_peek_char
    cmp eax, ','
    je .dname
    cmp eax, ')'
    je .dname
.d0a:
    test r15d, r15d
    jnz .dname
    call is_var_start
    test eax, eax
    jz .dtyped
    call next_token
    jmp .dname
.dtyped:
    call is_type_start
    test eax, eax
    jnz .dt1
    ERR "expected a type or var in front of the name (a tuple pattern cannot be nested)"
.dt1:
    call parse_type
    cmp rax, TY_VOID
    jne .dt2
    ERR "a variable cannot have type void"
.dt2:
    mov [rbx + TS_TYPE + r12*8], rax
.dname:
    cmp qword [tk], T_ID
    je .dn0
    ERR "expected a variable name"
.dn0:
    mov rdi, w_underscore
    call tk_is_word
    test eax, eax
    jz .dn1
    mov qword [rbx + TS_NAME + r12*8], 0         ; _ discards the element
    jmp .dn2
.dn1:
    mov rax, [tk_ptr]
    mov [rbx + TS_NAME + r12*8], rax
    mov eax, [tk_len]
    mov [rbx + TS_NLEN + r12*8], rax
.dn2:
    call next_token
    inc r12d
    cmp qword [tk], ','
    jne .dend
    call next_token
    jmp .dl
.dend:
    cmp r12d, 2
    jae .dend1
    ERR "a tuple pattern needs at least two names"
.dend1:
    mov [rbx + TS_N], r12
    mov edi, ')'
    call expect
    mov edi, '='
    call expect
    ; all types written: the literal on the right is converted to them
    xor ecx, ecx
.ex:
    cmp ecx, r12d
    jae .exall
    cmp qword [rbx + TS_TYPE + rcx*8], -1
    je .exno
    inc ecx
    jmp .ex
.exall:
    mov rsi, rbx
    mov edx, r12d
    call tuple_type                     ; (the types are the first TUPLE_MAX qwords of the frame)
    mov rdi, rax
    call tuple_expect_here
.exno:
    call parse_assign
    call to_rvalue
    mov edi, r12d
    call tuple_pattern_check
    mov rax, [e_type]
    mov [rbx + TS_TUPLE], rax
    add dword [frame_size], 8
    mov r13d, [frame_size]
    neg r13                             ; hidden local: the address of the tuple
    mov edi, r13d
    CG store_local_a
    xor r14d, r14d
.dv:
    cmp r14d, r12d
    jae .dvdone
    cmp qword [rbx + TS_NAME + r14*8], 0
    je .dvnext
    mov rdi, [rbx + TS_TUPLE]
    mov esi, r14d
    call tuple_field
    mov r15, rax                        ; the field entry of the element
    mov edi, r13d
    CG load_local_a
    mov edi, [r15+FD_OFFSET]
    test edi, edi
    jz .dv1
    CG add_imm_a
.dv1:
    mov rdi, [r15+FD_TYPE]
    call emit_load_type
    mov rax, [r15+FD_TYPE]
    mov [e_type], rax
    mov rdi, [rbx + TS_TYPE + r14*8]
    cmp rdi, -1
    jne .dv2
    mov rdi, [r15+FD_TYPE]              ; var: the variable gets the type of the element
.dv2:
    push rdi
    call coerce_to
    mov rdi, [rsp]
    call tuple_check
    pop rdx                             ; the type of the variable
    mov rdi, [rbx + TS_NAME + r14*8]
    mov rsi, [rbx + TS_NLEN + r14*8]
    call var_declare
.dvnext:
    inc r14d
    jmp .dv
.dvdone:
    mov edi, ';'
    call expect
    add rsp, TS_BYTES
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; the assignment form:  (a, b[i], *p, _) = value;   the addresses of the targets are pushed first (left to right), then the
; value is computed into a temporary, then the targets are assigned from left to right and the addresses are dropped
parse_tuple_assign:
    xor r12d, r12d
.al:
    cmp r12d, TUPLE_MAX
    jb .a0
    ERR "too many names in the tuple pattern (at most 16)"
.a0:
    cmp qword [tk], T_ID
    jne .target
    mov rdi, w_underscore
    call tk_is_word
    test eax, eax
    jz .target
    call tuple_peek_char
    cmp eax, ','
    je .wild
    cmp eax, ')'
    jne .target
.wild:
    call next_token
    xor edi, edi
    CG imm_a
    CG push_a                           ; a slot, so that the slots of the targets keep their numbers
    mov qword [rbx + TS_TYPE + r12*8], 0
    jmp .anext
.target:
    call parse_unary
    cmp qword [e_lval], 0
    jne .t1
    ERR "a tuple assignment needs variables on the left side (things that can be assigned to)"
.t1:
    mov rax, [e_type]
    bt rax, TF_ARRAY_BIT
    jnc .t2
    ERR "cannot assign to an array"
.t2:
    mov [rbx + TS_TYPE + r12*8], rax
    CG push_a
.anext:
    inc r12d
    cmp qword [tk], ','
    jne .aend
    call next_token
    jmp .al
.aend:
    cmp r12d, 2
    jae .aend1
    ERR "a tuple pattern needs at least two names"
.aend1:
    mov edi, ')'
    call expect
    mov edi, '='
    call expect
    ; the targets give the expected type of a literal on the right (unless one of them is discarded)
    xor ecx, ecx
.ex:
    cmp ecx, r12d
    jae .exall
    cmp qword [rbx + TS_TYPE + rcx*8], 0
    je .exno
    inc ecx
    jmp .ex
.exall:
    mov rsi, rbx
    mov edx, r12d
    call tuple_type
    mov rdi, rax
    call tuple_expect_here
.exno:
    call parse_assign
    call to_rvalue
    mov edi, r12d
    call tuple_pattern_check
    ; copy the value into a temporary of its own: the targets may be part of it
    mov rax, [e_type]
    mov [rbx + TS_TUPLE], rax
    mov rdi, rax
    call type_size
    mov r14d, eax
    add [frame_size], eax
    mov r13d, [frame_size]
    neg r13
    mov edi, r13d
    CG lea_local_b
    mov edi, r14d
    CG copy_mem
    xor r14d, r14d
.av:
    cmp r14d, r12d
    jae .avdone
    cmp qword [rbx + TS_TYPE + r14*8], 0
    je .avnext
    mov rdi, [rbx + TS_TUPLE]
    mov esi, r14d
    call tuple_field
    mov r15, rax
    mov esi, [r15+FD_OFFSET]
    lea edi, [r13 + rsi]
    CG lea_local_a
    mov rdi, [r15+FD_TYPE]
    call emit_load_type
    mov rax, [r15+FD_TYPE]
    mov [e_type], rax
    mov rdi, [rbx + TS_TYPE + r14*8]
    push rdi
    call coerce_to
    mov rdi, [rsp]
    call tuple_check
    CG push_a                           ; the value
    mov edi, r12d
    sub edi, r14d
    CG load_stack_a                     ; the address of the target (it was pushed below the value)
    CG mov_b_a
    CG pop_a
    pop rdi
    call emit_store_type
.avnext:
    inc r14d
    jmp .av
.avdone:
    mov edi, r12d
    CG drop
    mov edi, ';'
    call expect
    add rsp, TS_BYTES
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
