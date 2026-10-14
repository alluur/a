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
.q: CG load8_a
    ret
.b: CG load1_a
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
    mov rdi, rax
    CG copy_mem
    jmp .out
.q: CG store8
    jmp .out
.b: test edi, 0xFF00
    jnz .b1
    cmp dil, TY_BOOL
    jne .b1
    CG tobool
.b1:
    CG store1
.out:
    pop rdi
    ret

; ---- peephole support ----------------------------------------------------------------
; The generator remembers where the most recent "interesting" instruction started and
; ended (pk_*: address of a local, imm_*: constant in A, ld_*: local loaded, cmp_*: a
; comparison). A marker is valid only while code_pos still equals its end position, i.e.
; nothing has been emitted since. Rewinding the code buffer clears every marker.

; tail_is: rdi = end position of a peephole marker -> eax = 1 if that instruction is the
; last thing emitted AND no jump target was bound after it (a label at the very end means
; the code before it is only part of a bigger construct, e.g. the end of a ?: branch)
tail_is:
    xor eax, eax
    test rdi, rdi
    jz .no
    cmp rdi, [code_pos]
    jne .no
    cmp rdi, [last_label]
    je .no
    mov eax, 1
.no:
    ret

; rewind_code: rdi = new code position (preserves all registers)
rewind_code:
    mov [code_pos], rdi
    mov qword [pk_end], 0
    mov qword [imm_end], 0
    mov qword [ld_end], 0
    mov qword [cmp_end], 0
    mov qword [pi_end], 0
    ret

; gen_imm_a: rdi = value. Emits  A = value  and records it for the optimiser
gen_imm_a:
    push rax
    mov rax, [code_pos]
    mov [imm_pos], rax
    mov [imm_val], rdi
    CG imm_a
    mov rax, [code_pos]
    mov [imm_end], rax
    pop rax
    ret

; finish_operands: rdi = code position of the "push A" emitted before the right operand,
; rsi = code position right after it. Right operand is in A, left operand on the stack.
; Leaves B = right and A = left, using a single instruction when the right operand was
; just a constant or a plain local variable.
finish_operands:
    cmp rsi, [imm_pos]
    jne .noimm
    push rdi
    mov rdi, [imm_end]
    call tail_is
    pop rdi
    test eax, eax
    jz .noimm
    mov r8, [imm_val]
    call rewind_code
    mov rdi, r8
    CG imm_b
    ret
.noimm:
    cmp rsi, [ld_pos]
    jne .plain
    push rdi
    mov rdi, [ld_end]
    call tail_is
    pop rdi
    test eax, eax
    jz .plain
    mov r8d, [ld_off]
    mov r9d, [ld_size]
    call rewind_code
    mov edi, r8d
    cmp r9d, 8
    jne .b1
    CG load_local_b
    ret
.b1:
    CG load_local_b1
    ret
.plain:
    CG mov_b_a
    CG pop_a
    ret

; cond_jz / cond_jnz: rdi = &chain head. The condition is in A; if it was just computed
; by a comparison the compare-and-jump is fused.
cond_jz:
    push rbx
    mov rbx, rdi
    cmp qword [e_type], TY_DOUBLE
    jne .nd
    call truth_value
.nd:
    mov rdi, [cmp_end]
    call tail_is
    test eax, eax
    jz .plain
    mov eax, [cmp_cc]
    movzx r8d, byte [cc_invert + rax]
    mov rdi, [cmp_pos]
    call rewind_code
    mov edi, r8d
    mov rsi, rbx
    CG jcmp_chain
    pop rbx
    ret
.plain:
    mov rdi, rbx
    CG jz_chain
    pop rbx
    ret

cond_jnz:
    push rbx
    mov rbx, rdi
    cmp qword [e_type], TY_DOUBLE
    jne .nd
    call truth_value
.nd:
    mov rdi, [cmp_end]
    call tail_is
    test eax, eax
    jz .plain
    mov r8d, [cmp_cc]
    mov rdi, [cmp_pos]
    call rewind_code
    mov edi, r8d
    mov rsi, rbx
    CG jcmp_chain
    pop rbx
    ret
.plain:
    mov rdi, rbx
    CG jnz_chain
    pop rbx
    ret

section .rodata
cc_invert: db CC_NE, CC_EQ, CC_GE, CC_LE, CC_GT, CC_LT
section .text

; to_rvalue: turn an lvalue (address in rax) into its value
to_rvalue:
    cmp qword [e_lval], 0
    je .ret
    mov qword [e_lval], 0
    mov rdi, [e_type]
    bt rdi, TF_ARRAY_BIT
    jc .arr
    ; a local variable whose address was just computed: load it directly
    mov rdi, [pk_end]
    call tail_is
    test eax, eax
    jz .plain
    mov rdi, [e_type]
    call type_ls
    cmp eax, 8
    je .f8
    cmp eax, 1
    je .f1
.plain:
    mov rdi, [e_type]
    jmp emit_load_type
.f8:
    mov r8d, [pk_off]
    mov rdi, [pk_pos]
    call rewind_code
    mov [ld_pos], rdi
    mov edi, r8d
    CG load_local_a
    mov dword [ld_size], 8
    jmp .fdone
.f1:
    mov r8d, [pk_off]
    mov rdi, [pk_pos]
    call rewind_code
    mov [ld_pos], rdi
    mov edi, r8d
    CG load_local_a1
    mov dword [ld_size], 1
.fdone:
    mov [ld_off], r8d
    mov rax, [code_pos]
    mov [ld_end], rax
    ret
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
    mov edi, eax
    CG mul_imm_b
.r: ret

scale_rax:
    call type_pointee_size
    cmp eax, 1
    je .r
    mov edi, eax
    CG mul_imm_a
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
    CG add
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
    CG sub
    jmp .out
.ptrdiff:
    CG sub
    mov rdi, r12
    call type_pointee_size
    cmp eax, 1
    je .out
    mov edi, eax
    CG imm_b
    CG div
    jmp .out
.mul:
    CG mul
    jmp .out
.div:
    CG div
    jmp .out
.mod:
    CG mod
    jmp .out
.and:
    CG and
    jmp .out
.or:
    CG or
    jmp .out
.xor:
    CG xor
    jmp .out
.shl:
    CG shl
    jmp .out
.shr:
    CG sar
    jmp .out
.eq:
    mov r8d, CC_EQ
    call .cmark
    CG cmp_eq
    jmp .cdone
.ne:
    mov r8d, CC_NE
    call .cmark
    CG cmp_ne
    jmp .cdone
.lt:
    mov r8d, CC_LT
    call .cmark
    CG cmp_lt
    jmp .cdone
.gt:
    mov r8d, CC_GT
    call .cmark
    CG cmp_gt
    jmp .cdone
.le:
    mov r8d, CC_LE
    call .cmark
    CG cmp_le
    jmp .cdone
.ge:
    mov r8d, CC_GE
    call .cmark
    CG cmp_ge
.cdone:
    mov rax, [code_pos]
    mov [cmp_end], rax
    jmp .out
.cmark:
    mov rax, [code_pos]
    mov [cmp_pos], rax
    mov [cmp_cc], r8d
    ret
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
    cmp eax, K_STRUCT
    je .yes
    cmp eax, K_CLASS
    je .yes
    cmp eax, K_UNION
    je .yes
    cmp eax, K_ENUM
    je .yes
    cmp eax, K_INTMOD
    je .yes
    cmp eax, K_DOUBLE
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
    cmp ecx, S_TYPEDEF
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
    cmp ecx, S_TYPEDEF
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
    cmp eax, K_STRUCT
    je .tagkw
    cmp eax, K_CLASS
    je .tagkw
    cmp eax, K_UNION
    je .tagkw
    cmp eax, K_ENUM
    jne .notag
.tagkw:
    call next_token                     ; C style:  struct Point p;   enum Color c;
    mov eax, [tk]
.notag:
    cmp eax, K_INTMOD
    jne .nomod
    ; short / long / signed / unsigned [long] [int | char | double]: every one of them is an int, char or double
.mod:
    call next_token
    cmp qword [tk], K_INTMOD
    je .mod
    mov eax, [tk]
    cmp eax, K_INT
    je .int
    cmp eax, K_CHAR
    je .char
    cmp eax, K_DOUBLE
    je .double
    mov ebx, TY_INT
    jmp .star
.nomod:
    cmp eax, K_INT
    je .int
    cmp eax, K_DOUBLE
    je .double
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
    cmp ecx, S_TYPEDEF
    je .typedef
.unk:
    mov edi, msg_unktype
    cmp qword [tk], T_ID
    je fatal_error_tok
    jmp fatal_error
.int:
    mov ebx, TY_INT
    jmp .star0
.double:
    mov ebx, TY_DOUBLE
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
    test dword [rax+SYM_FLAGS], F_FUNCTYPE
    jz .star0
    mov ebx, TY_FUNC
    jmp .star0
.struct:
    call check_access
    mov rbx, [rax+SYM_VAL]
    shl rbx, 16
    or rbx, TY_STRUCT
    jmp .star0
.typedef:
    call check_access
    mov rbx, [rax+SYM_TYPE]
.star0:
    call next_token
.star:
    cmp qword [tk], '*'
    jne .done
    add rbx, TY_PTR1
    call next_token
    jmp .star
.done:
    cmp qword [tk], '('
    je .fpcheck
.ret:
    mov rax, rbx
    pop r12
    pop rbx
    ret
; int (*name)(params)  -  a C function pointer declarator. The signature is not checked (see "func"): the type becomes func,
; the current token becomes the name, and the lexer jumps over ")(params)" when the name is consumed.
.fpcheck:
    sub rsp, 128
    mov rdi, rsp
    call lex_save
    call next_token
    cmp qword [tk], '*'
    jne .fpno
    call next_token
    cmp qword [tk], T_ID
    jne .fpno
    call next_token
    cmp qword [tk], ')'
    jne .fpno
    call next_token
    cmp qword [tk], '('
    jne .fpno
    xor r12d, r12d
.fpscan:
    mov rax, [tk]
    cmp rax, T_EOF
    je .fpno
    cmp rax, '('
    jne .fp1
    inc r12d
.fp1:
    cmp rax, ')'
    jne .fp2
    dec r12d
    jz .fpend
.fp2:
    call next_token
    jmp .fpscan
.fpend:
    call next_token                     ; the token after the parameter list
    mov rdi, fp_after
    call lex_save
    mov rsi, rsp
    call lex_restore                    ; back to the '('
    add rsp, 128
    call next_token                     ; '*'
    call next_token                     ; the name
    mov dword [fp_pending], 1
    mov ebx, TY_FUNC
    jmp .ret
.fpno:
    mov rsi, rsp
    call lex_restore
    add rsp, 128
    jmp .ret

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
; emit_call_sym: rdi = function symbol. Emits a call (patch chain if the
; function is not defined yet)
emit_call_sym:
    call record_edge
    cmp dword [obj_mode], 0
    je .direct
    call sym_is_external
    test eax, eax
    jz .direct
    ; a function of another object or of the built-in libraries: through its address (a relocation the linker resolves)
    CG lea_func_a
    CG call_a
    ret
.direct:
    CG call_sym
    ret

; sym_is_external: rdi = function symbol -> eax = 1 when its body is not part of the object being compiled
sym_is_external:
    test dword [rdi+SYM_FLAGS], F_BUILTIN
    jnz .yes
    test dword [rdi+SYM_FLAGS], F_DEFINED
    jz .yes
    mov eax, [rdi+SYM_FILE]
    shl rax, 6
    add rax, file_table
    cmp dword [rax+32], 0
    jne .yes
    xor eax, eax
    ret
.yes:
    mov eax, 1
    ret

; emit_funcaddr_sym: rdi = function symbol. A = the address of the function (a "func" value)
emit_funcaddr_sym:
    call record_edge
    CG lea_func_a
    ret

; record_edge: rdi = function symbol that the current function uses.
; Pass 2 records the call graph: edge  cur_func -> callee  (no caller = called from the entry stub)
record_edge:
    inc dword [call_ctr]
    cmp dword [pass], 2
    jne .out
    push rax
    push rcx
    mov rax, [cur_func]
    test rax, rax
    jnz .edge
    or dword [rdi+SYM_FLAGS], F_USED
    jmp .recorded
.edge:
    mov ecx, [edge_count]
    cmp ecx, EDGE_MAX
    jae err_toobig
    sub rax, symtab
    shr rax, 6
    mov [edge_from + rcx*4], eax
    mov rax, rdi
    sub rax, symtab
    shr rax, 6
    mov [edge_to + rcx*4], eax
    inc dword [edge_count]
.recorded:
    pop rcx
    pop rax
.out:
    ret

; gen_call: rdi = function symbol, esi = number of extra stack slots already pushed
; by the caller (1 when 'this' was pushed). Current token must be '('.
gen_call:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r15d, [force_direct]            ; super.method(): no virtual dispatch
    mov dword [force_direct], 0
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
    ; int <-> double conversion to the declared parameter type
    mov rax, [r12+SYM_EXTRA]
    test rax, rax
    jz .argcv
    cmp ebx, [r12+SYM_NPAR]
    jae .argcv
    mov rdi, [rax+rbx*8]
    call coerce_to
.argcv:
    mov rax, [e_type]
    test eax, 0xFF00
    jnz .push
    cmp al, TY_STRUCT
    jne .push
    ; a struct argument: copy it into a temporary of the caller's frame and pass the address of the copy
    mov rdi, rax
    call type_size
    mov r9d, eax
    add eax, 7
    and eax, -8
    add [frame_size], eax
    mov edi, [frame_size]
    neg edi
    CG lea_local_b
    mov edi, r9d
    CG copy_mem
.push:
    ; bool parameters are normalised to 0 / 1
    mov rax, [r12+SYM_EXTRA]
    test rax, rax
    jz .pushit
    cmp ebx, [r12+SYM_NPAR]
    jae .pushit
    mov rax, [rax+rbx*8]
    cmp rax, TY_BOOL
    jne .pushit
    CG tobool
.pushit:
    CG push_a
    inc ebx
    cmp qword [tk], ','
    jne .args_done
    call next_token
    jmp .arg
.args_done:
    mov edi, ')'
    call expect
    test dword [r12+SYM_FLAGS], F_VARIADIC
    jz .fixedargs
    ; variadic callee: after the arguments comes the number of extra ones
    cmp ebx, [r12+SYM_NPAR]
    jae .vcount
    ERR "wrong number of arguments in call"
.vcount:
    mov edi, ebx
    sub edi, [r12+SYM_NPAR]
    CG imm_a
    CG push_a
    inc ebx
    jmp .ok
.fixedargs:
    cmp ebx, [r12+SYM_NPAR]
    je .ok
    jb .fewer
    ERR "wrong number of arguments in call"
.fewer:
    ; fewer arguments than parameters: the missing ones need default values
    mov rax, [r12+SYM_EXTRA]
    test rax, rax
    jnz .hasdef
    ERR "wrong number of arguments in call"
.hasdef:
    mov ecx, [r12+SYM_NPAR]
    lea edx, [rcx*2]
    mov edx, [rax+rdx*8]
    cmp ebx, edx
    jae .fill
    ERR "wrong number of arguments in call"
.fill:
    cmp ebx, ecx
    jae .ok
    lea esi, [rcx+rbx]
    mov rdi, [rax+rsi*8]
    mov rcx, rdi
    shr rcx, 48
    cmp ecx, 0x5A5A
    jne .fillnum
    mov rcx, 0x5A5A000000000000         ; a text default: its address in the data section
    xor rdi, rcx
    mov edx, edi
    call obj_localize_string
    mov esi, R_DATA
    CG lea_global_a
    jmp .fillpush
.fillnum:
    call gen_imm_a
.fillpush:
    CG push_a
    inc ebx
    mov rax, [r12+SYM_EXTRA]
    mov ecx, [r12+SYM_NPAR]
    jmp .fill
.ok:
    ; a function that returns a struct: pass the address of a temporary for the result as the last argument
    mov r14d, 0
    mov rax, [r12+SYM_TYPE]
    test eax, 0xFF00
    jnz .noretst
    cmp al, TY_STRUCT
    jne .noretst
    mov rdi, rax
    call type_size
    add eax, 7
    and eax, -8
    add [frame_size], eax
    mov edi, [frame_size]
    neg edi
    CG lea_local_a
    CG push_a
    inc ebx
    mov r14d, 1
.noretst:
    test dword [r12+SYM_FLAGS], F_VIRTUAL
    jz .direct
    test r15d, r15d
    jnz .direct
    ; virtual method: this -> vtable -> slot -> call
    mov edi, ebx
    CG load_stack_a
    mov eax, [r12+SYM_OWNER]
    mov edi, [st_vptr + rax*4]
    dec edi
    jz .novo
    CG add_imm_a
.novo:
    CG load8_a
    mov rdx, r12
    sub rdx, symtab
    shr rdx, 6
    mov edi, [sym_vslot + rdx*4]
    shl edi, 3
    jz .nosl
    CG add_imm_a
.nosl:
    CG load8_a
    CG call_a
    jmp .called
.direct:
    mov rdi, r12
    call emit_call_sym
.called:
    lea edi, [rbx+r13]
    CG drop
.noadd:
    mov rax, [r12+SYM_TYPE]
    mov [e_type], rax
    mov qword [e_lval], r14                  ; a struct result is an address (the temporary)
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; va_check: va_arg / va_count are only available in a function whose parameter list ends in ...
va_check:
    mov rax, [cur_func]
    test rax, rax
    jz .bad
    test dword [rax+SYM_FLAGS], F_VARIADIC
    jnz .ok
.bad:
    ERR "va_arg and va_count can only be used in a function declared with ..."
.ok:
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
    cmp eax, K_SUPER
    je .super
    cmp eax, K_ASM
    je .asm
    cmp eax, T_FLT
    je .flt
    cmp eax, T_SCOPE
    je .scope
    ERR "expected an expression"

.flt:
    mov rdi, [tk_val]
    call gen_imm_a
    mov qword [e_type], TY_DOUBLE
    mov qword [e_lval], 0
    call next_token
    jmp .out

; ::name  -  a name of the global namespace even inside a module that has the same name
.scope:
    call next_token
    cmp qword [tk], T_ID
    je .sc1
    ERR "expected a name after '::'"
.sc1:
    mov rdi, [tk_ptr]
    mov esi, [tk_len]
    xor edx, edx
    call sym_find_global
    test rax, rax
    jnz .sc2
    mov edi, msg_undeclared
    call fatal_error_tok
.sc2:
    mov r12, rax
    call next_token
    jmp .dispatch

.num:
    mov rdi, [tk_val]
    call gen_imm_a
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
    CG lea_global_a
    mov qword [e_type], TY_CHAR | TY_PTR1
    mov qword [e_lval], 0
    call next_token
    jmp .out

.true:
    mov edi, 1
    call gen_imm_a
    mov qword [e_type], TY_BOOL
    mov qword [e_lval], 0
    call next_token
    jmp .out
.false:
    xor edi, edi
    call gen_imm_a
    mov qword [e_type], TY_BOOL
    mov qword [e_lval], 0
    call next_token
    jmp .out
.null:
    xor edi, edi
    call gen_imm_a
    mov qword [e_type], TY_VOID | TY_PTR1
    mov qword [e_lval], 0
    call next_token
    jmp .out

.this:
    cmp dword [cur_class], -1
    jne .this1
    ERR "'this' used outside of a method"
.this1:
    mov edi, [cur_this_off]
    CG load_local_a
    mov eax, [cur_class]
    shl rax, 16
    or rax, TY_STRUCT | TY_PTR1
    mov [e_type], rax
    mov qword [e_lval], 0
    call next_token
    jmp .out

;  ---- inline assembly:  asm(a, b, c) { x64: 0x48, 0x01, 0xD8; arm64: 0x8B010000; riscv64: ...; loongarch64: ...; }
; The operands (at most three, evaluated left to right) are loaded into the registers A, B and D of the CPU, the
; machine code of the section for the CPU being compiled is copied into the function (bytes for x64, 32 bit
; words for the others) and the value of the expression is the register A afterwards.
.asm:
    call next_token
    xor r13d, r13d
    cmp qword [tk], '('
    jne .asm_body
    call next_token
    cmp qword [tk], ')'
    je .asm_close
.asm_arg:
    call parse_assign
    call to_rvalue
    CG push_a
    inc r13d
    cmp r13d, 3
    jbe .asm_a1
    ERR "asm takes at most three operands (they go into the registers A, B and D)"
.asm_a1:
    cmp qword [tk], ','
    jne .asm_close
    call next_token
    jmp .asm_arg
.asm_close:
    mov edi, ')'
    call expect
    cmp r13d, 3
    jne .asm_p2
    CG pop_a
    CG mov_d_a
    CG pop_a
    CG mov_b_a
    CG pop_a
    jmp .asm_body
.asm_p2:
    cmp r13d, 2
    jne .asm_p1
    CG pop_a
    CG mov_b_a
    CG pop_a
    jmp .asm_body
.asm_p1:
    cmp r13d, 1
    jne .asm_body
    CG pop_a
.asm_body:
    mov edi, '{'
    call expect
    xor r14d, r14d                  ; found a section for this CPU
.asm_sec:
    cmp qword [tk], '}'
    je .asm_end
    cmp qword [tk], T_ID
    je .asm_lab
    ERR "expected a CPU name (x64, arm64, riscv64, loongarch64) in the asm block"
.asm_lab:
    mov rdi, [tk_ptr]
    mov esi, [tk_len]
    call asm_arch_match
    mov r12d, eax
    call next_token
    mov edi, ':'
    call expect
.asm_val:
    call const_expr
    test r12d, r12d
    jz .asm_next
    mov r14d, 1
    cmp dword [arch], ARCH_X64
    jne .asm_word
    lea rcx, [rax+128]
    cmp rcx, 383
    jbe .asm_byte
    ERR "x64 asm values are single bytes (-128 .. 255)"
.asm_byte:
    mov edi, eax
    call emit_b
    jmp .asm_next
.asm_word:
    mov rcx, rax
    shr rcx, 32
    jz .asm_wok
    cmp ecx, 0xFFFFFFFF
    je .asm_wok
    ERR "asm values for this CPU are 32 bit instruction words"
.asm_wok:
    mov edi, eax
    call emit_d
.asm_next:
    cmp qword [tk], ','
    jne .asm_semi
    call next_token
    jmp .asm_val
.asm_semi:
    cmp qword [tk], ';'
    jne .asm_sec
    call next_token
    jmp .asm_sec
.asm_end:
    call next_token
    test r14d, r14d
    jnz .asm_ok
    ERR "this asm block has no code for the CPU being compiled"
.asm_ok:
    mov qword [e_type], TY_INT
    mov qword [e_lval], 0
    jmp .out

; ---- super(args) calls the constructor of the base class, super.method(args) a base class method
.super:
    cmp dword [cur_class], -1
    jne .sup1
    ERR "'super' used outside of a method"
.sup1:
    mov eax, [cur_class]
    mov eax, [st_base + rax*4]
    test eax, eax
    jnz .sup2
    ERR "'super' used in a class that has no base class"
.sup2:
    lea r13d, [rax-1]
    call next_token
    cmp qword [tk], '('
    je .supctor
    cmp qword [tk], '.'
    je .supmeth
    ERR "'super' must be followed by '(' or '.'"
.supctor:
    mov edi, r13d
    call struct_find_ctor
    test rax, rax
    jnz .supc1
    ERR "the base class has no constructor"
.supc1:
    mov r12, rax
    mov edi, [cur_this_off]
    CG load_local_a
    CG push_a
    mov rdi, r12
    mov esi, 1
    call gen_call
    jmp .out
.supmeth:
    call next_token
    cmp qword [tk], T_ID
    je .supm1
    ERR "expected a method name after 'super.'"
.supm1:
    mov edi, r13d
    mov rsi, [tk_ptr]
    mov edx, [tk_len]
    call struct_find_method
    test rax, rax
    jnz .supm2
    mov edi, msg_nomember
    call fatal_error_tok
.supm2:
    mov r12, rax
    call method_vis_ok
    test eax, eax
    jnz .supm3
    mov edi, msg_privmember
    call fatal_error_tok
.supm3:
    call next_token
    cmp qword [tk], '('
    je .supm4
    ERR "methods can only be called, not used as values"
.supm4:
    mov edi, [cur_this_off]
    CG load_local_a
    CG push_a
    mov dword [force_direct], 1
    mov rdi, r12
    mov esi, 1
    call gen_call
    jmp .out

.sizeof:
    call next_token
    xor r13d, r13d                      ; 1 = the operand is in parentheses
    cmp qword [tk], '('
    jne .sz_expr
    mov r13d, 1
    call next_token
    call is_type_start
    test eax, eax
    jz .sz_expr
    call parse_type
    mov rdi, rax
    call type_size
    mov rbx, rax
    mov edi, ')'
    call expect
    jmp .sz_done
.sz_expr:
    ; the name of an array: its size is the element size times the element count
    cmp qword [tk], T_ID
    jne .sz_gen
    mov rdi, [tk_ptr]
    mov esi, [tk_len]
    call sym_lookup
    test rax, rax
    jz .sz_gen
    mov r12, rax
    mov ecx, [r12+SYM_KIND]
    cmp ecx, S_LOCAL
    je .sz_sym
    cmp ecx, S_GLOBAL
    jne .sz_gen
.sz_sym:
    mov rax, [r12+SYM_TYPE]
    bt rax, TF_ARRAY_BIT
    jnc .sz_gen
    sub rsp, 128
    mov rdi, rsp
    call lex_save
    call next_token
    xor ebx, ebx                        ; 1 = the identifier stands alone
    test r13d, r13d
    jz .sz_alone
    cmp qword [tk], ')'
    jne .sz_back
    mov ebx, 1
    jmp .sz_back
.sz_alone:
    mov ebx, 1
    cmp qword [tk], '['
    je .sz_no
    cmp qword [tk], '.'
    je .sz_no
    cmp qword [tk], T_ARROW
    jne .sz_back
.sz_no:
    xor ebx, ebx
.sz_back:
    test ebx, ebx
    jz .sz_restore
    add rsp, 128                        ; keep the position after the identifier
    test r13d, r13d
    jz .sz_arr
    mov edi, ')'
    call expect
.sz_arr:
    mov rdi, [r12+SYM_TYPE]
    btr rdi, TF_ARRAY_BIT
    sub rdi, TY_PTR1
    call type_size
    imul rax, [r12+SYM_EXTRA]
    mov rbx, rax
    jmp .sz_done
.sz_restore:
    mov rsi, rsp
    call lex_restore
    add rsp, 128
.sz_gen:
    ; any other expression: only its type matters, the code is thrown away
    mov r12, [code_pos]
    mov r14d, [rel_count]
    push qword [call_ctr]
    test r13d, r13d
    jz .sz_unary
    call parse_expr
    jmp .sz_typed
.sz_unary:
    call parse_unary
.sz_typed:
    pop rax
    cmp eax, [call_ctr]
    je .sz_nocall
    ERR "sizeof cannot contain a function call"
.sz_nocall:
    mov [rel_count], r14d
    mov rdi, r12
    call rewind_code
    mov rdi, [e_type]
    bt rdi, TF_ARRAY_BIT
    jnc .sz_scalar
    ERR "sizeof of this array expression is not supported, use the name of the array"
.sz_scalar:
    call type_size
    mov rbx, rax
    test r13d, r13d
    jz .sz_done
    mov edi, ')'
    call expect
.sz_done:
    mov rdi, rbx
    call gen_imm_a
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
    xor r13d, r13d                      ; array element count of a compound literal, -1 = counted from the list
    cmp qword [tk], '['
    jne .cast1
    call next_token
    mov r13, -1
    cmp qword [tk], ']'
    je .castbr
    call const_expr
    mov r13, rax
.castbr:
    mov edi, ']'
    call expect
    add rbx, TY_PTR1
    bts rbx, TF_ARRAY_BIT
.cast1:
    mov edi, ')'
    call expect
    cmp qword [tk], '{'
    je .complit
    test r13, r13
    jz .castval
    ERR "an array type can only be used in a compound literal"
.castval:
    call parse_unary
    call to_rvalue
    cmp rbx, TY_DOUBLE
    je .cconv
    cmp qword [e_type], TY_DOUBLE
    je .cconv
    test ebx, 0xFF00
    jnz .cdone
    cmp bl, TY_CHAR
    je .cchar
    cmp bl, TY_BOOL
    je .cbool
    jmp .cdone
.cchar:
    CG zext8
    jmp .cdone
.cbool:
    CG tobool
    jmp .cdone
.cconv:
    mov rdi, rbx
    call coerce_to                      ; int <-> double
.cdone:
    mov [e_type], rbx
    mov qword [e_lval], 0
    jmp .out

; (Type){ ... }   (Type[n]){ ... }   (Type[]){ ... }  - a nameless local object that lives until the function returns
.complit:
    cmp qword [cur_func], 0
    jne .cl1
    ERR "a compound literal can only be used inside a function"
.cl1:
    test r13, r13
    jns .cl2
    call count_list_elems
    mov r13, rax
.cl2:
    bt rbx, TF_ARRAY_BIT
    jc .cl_arr
    test ebx, 0xFF00
    jnz .cl_bad
    cmp bl, TY_STRUCT
    je .cl_size
.cl_bad:
    ERR "a compound literal needs a struct or array type"
.cl_arr:
    test r13, r13
    jg .cl_size
    ERR "array size must be positive"
.cl_size:
    mov rdi, rbx
    bt rbx, TF_ARRAY_BIT
    jnc .cl3
    btr rdi, TF_ARRAY_BIT
    sub rdi, TY_PTR1
    call type_size
    imul rax, r13
    jmp .cl4
.cl3:
    call type_size
.cl4:
    add rax, 7
    and rax, -8
    mov r14, rax
    add [frame_size], eax
    mov r12d, [frame_size]
    neg r12
    mov edi, r12d
    mov esi, r14d
    CG zero_local
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call init_local_list
    mov edi, r12d
    CG lea_local_a
    mov [e_type], rbx
    mov qword [e_lval], 1
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
    CG imm_a
    CG push_a
    mov rdi, r14
    call emit_call_sym
    mov edi, 1
    CG drop
    mov edi, r12d
    call emit_vptr_init
    mov edi, r12d
    call struct_find_ctor
    test rax, rax
    jz .new_noctor
    mov r14, rax
    cmp qword [tk], '('
    je .new_c
    ERR "constructor call needs parentheses"
.new_c:
    CG push_a
    CG push_a
    mov rdi, r14
    mov esi, 1
    call gen_call
    CG pop_a
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

; ---- __bits(x): the 64 bits of a value as an int (a double's IEEE bits);  __dbl(i): an int's bits taken as a double
.bitsfn:
    call next_token
    mov edi, '('
    call expect
    call parse_assign
    call to_rvalue
    mov edi, ')'
    call expect
    mov qword [e_type], TY_INT
    mov qword [e_lval], 0
    jmp .out
.dblfn:
    call next_token
    mov edi, '('
    call expect
    call parse_assign
    call to_rvalue
    mov edi, ')'
    call expect
    mov qword [e_type], TY_DOUBLE
    mov qword [e_lval], 0
    jmp .out

; ---- va_arg(i) and va_count(): the extra arguments of a function declared with ...
.vaarg:
    call va_check
    call next_token
    mov edi, '('
    call expect
    call parse_expr
    call to_rvalue
    mov edi, ')'
    call expect
    CG mov_b_a
    mov edi, [cur_va_cnt]
    CG load_local_a
    CG sub
    mov edi, [slot_bytes]
    CG mul_imm_a
    CG mov_b_a
    mov edi, 16
    CG lea_local_a
    CG add
    CG load8_a
    mov qword [e_type], TY_INT
    mov qword [e_lval], 0
    jmp .out
.vacount:
    call va_check
    call next_token
    mov edi, '('
    call expect
    mov edi, ')'
    call expect
    mov edi, [cur_va_cnt]
    CG load_local_a
    mov qword [e_type], TY_INT
    mov qword [e_lval], 0
    jmp .out

; ---- identifiers
.id:
    mov r13, [tk_ptr]
    mov r14d, [tk_len]
    cmp r14d, 6
    jne .nova1
    cmp dword [r13], 'va_a'
    jne .nova1
    cmp word [r13+4], 'rg'
    je .vaarg
.nova1:
    cmp r14d, 6
    jne .nobits
    cmp dword [r13], '__bi'
    jne .nobits
    cmp word [r13+4], 'ts'
    je .bitsfn
.nobits:
    cmp r14d, 5
    jne .nodbl
    cmp dword [r13], '__db'
    jne .nodbl
    cmp byte [r13+4], 'l'
    je .dblfn
.nodbl:
    cmp r14d, 8
    jne .nova2
    cmp dword [r13], 'va_c'
    jne .nova2
    cmp dword [r13+4], 'ount'
    je .vacount
.nova2:
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
    test dword [r12+SYM_FLAGS], F_BYREF
    jz .local1
    mov edi, [r12+SYM_VAL]
    CG load_local_a
    mov rax, [r12+SYM_TYPE]
    mov [e_type], rax
    mov qword [e_lval], 1
    jmp .out
.local1:
    mov rax, [code_pos]
    mov [pk_pos], rax
    mov edi, [r12+SYM_VAL]
    mov [pk_off], edi
    CG lea_local_a
    mov rax, [code_pos]
    mov [pk_end], rax
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
    test dword [r12+SYM_FLAGS], F_EXTERN
    jz .g2
    cmp dword [obj_mode], 0
    jne .gext
    ERR "extern variable is not defined in this program"
.g2:
    cmp dword [obj_mode], 0
    je .g3
    ; a variable of the built-in libraries lives in the program that is linked later
    cmp esi, R_BSS
    je .g2b
    cmp edx, FOREIGN_DATA_BASE
    jae .gext
    jmp .g3
.g2b:
    cmp edx, FOREIGN_BSS_BASE
    jb .g3
.gext:
    mov rax, r12
    call sym_index
    inc eax
    mov [ext_reloc_sym], eax
    xor edx, edx
.g3:
    CG lea_global_a
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
    call gen_imm_a
    mov rax, [r12+SYM_TYPE]
    mov [e_type], rax
    mov qword [e_lval], 0
    jmp .out
.conststr:
    mov edx, [r12+SYM_VAL]
    call obj_localize_string
    mov esi, R_DATA
    CG lea_global_a
    mov qword [e_type], TY_CHAR | TY_PTR1
    mov qword [e_lval], 0
    jmp .out

.func:
    mov rax, r12
    call check_access
    cmp qword [tk], '('
    je .func1
    ; a function used as a value: its address, type "func"
    test dword [r12+SYM_FLAGS], F_BUILTIN | F_METHOD
    jz .funcval
    ERR "only ordinary functions can be used as values"
.funcval:
    test dword [r12+SYM_FLAGS], F_VARIADIC
    jz .funcval2
    ERR "a function with ... cannot be used as a value"
.funcval2:
    mov rdi, r12
    call emit_funcaddr_sym
    mov qword [e_type], TY_FUNC
    mov qword [e_lval], 0
    jmp .out
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
    mov eax, [r12+FD_VIS]
    mov edx, [r12+FD_OWNER]
    call member_ok
    test eax, eax
    jnz .ifok
    mov edi, msg_privmember
    call fatal_error_tok
.ifok:
    mov edi, [cur_this_off]
    CG load_local_a
    mov edi, [r12+FD_OFFSET]
    test edi, edi
    jz .if1
    CG add_imm_a
.if1:
    mov rax, [r12+FD_TYPE]
    mov [e_type], rax
    mov qword [e_lval], 1
    call next_token
    jmp .out

.implicit_method:
    mov r12, rax
    call method_vis_ok
    test eax, eax
    jnz .imok
    mov edi, msg_privmember
    call fatal_error_tok
.imok:
    call next_token
    cmp qword [tk], '('
    je .im1
    ERR "methods can only be called, not used as values"
.im1:
    mov edi, [cur_this_off]
    CG load_local_a
    CG push_a
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
    cmp eax, '('
    je .callptr
.out:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; call through a function pointer:  fp(a, b)  -  the target is pushed first, then the arguments;
; the target is fetched back from below the arguments. The result is an int.
.callptr:
    cmp qword [e_type], TY_FUNC
    jne .out
    call to_rvalue
    CG push_a
    call next_token
    xor ebx, ebx
    cmp qword [tk], ')'
    je .cp_done
.cp_arg:
    call parse_assign
    call to_rvalue
    CG push_a
    inc ebx
    cmp qword [tk], ','
    jne .cp_done
    call next_token
    jmp .cp_arg
.cp_done:
    mov edi, ')'
    call expect
    mov edi, ebx
    CG load_stack_a
    CG call_a
    lea edi, [rbx+1]
    CG drop
    mov qword [e_type], TY_INT
    mov qword [e_lval], 0
    jmp .loop

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
    CG push_a
    call next_token
    call parse_expr
    call to_rvalue
    mov edi, TY_INT
    call coerce_to                      ; a double index is truncated
    cmp r12, 1
    je .ix2
    mov rdi, r12
    CG mul_imm_a
.ix2:
    CG pop_b
    CG add
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
    mov eax, [r12+FD_VIS]
    mov edx, [r12+FD_OWNER]
    call member_ok
    test eax, eax
    jnz .fok
    mov edi, msg_privmember
    call fatal_error_tok
.fok:
    mov edi, [r12+FD_OFFSET]
    test edi, edi
    jz .f1
    CG add_imm_a
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
    call method_vis_ok
    test eax, eax
    jnz .m2
    mov edi, msg_privmember
    call fatal_error_tok
.m2:
    call next_token
    cmp qword [tk], '('
    je .m3
    ERR "methods can only be called, not used as values"
.m3:
    CG push_a
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
    push r14
    push r15
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
    cmp rbx, TY_DOUBLE
    je .dbl
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
    mov rdi, [pk_end]
    call tail_is
    test eax, eax
    jz .stepg
    ; local variable: load, modify, store back - no address register needed
    mov r14d, [pk_off]
    mov rdi, [pk_pos]
    call rewind_code
    mov [pi_pos], rdi
    mov [pi_off], r14d
    mov [pi_type], rbx
    mov [pi_step], r13
    mov edi, r14d
    mov rsi, rbx
    call load_local_typed
    test r12d, r12d
    jz .l1
    CG mov_d_a
.l1:
    mov rdi, r13
    CG add_imm_a
    mov edi, r14d
    mov rsi, rbx
    call store_local_typed
    test r12d, r12d
    jz .fin
    CG mov_a_d
    mov rax, [code_pos]
    mov [pi_end], rax
    jmp .fin
.stepg:
    CG mov_b_a
    mov rdi, rbx
    call emit_load_type
    test r12d, r12d
    jz .nopost
    CG mov_d_a
.nopost:
    mov rdi, r13
    CG add_imm_a
    mov rdi, rbx
    call emit_store_type
    test r12d, r12d
    jz .fin
    CG mov_a_d
.fin:
    mov [e_type], rbx
    mov qword [e_lval], 0
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
; a double: x +/- 1.0 through the float runtime; the stack holds [address, old value, new value] while storing
.dbl:
    CG push_a                           ; address
    mov rdi, rbx
    call emit_load_type
    CG push_a                           ; old value (the result of a postfix operation)
    CG push_a                           ; left operand
    mov rdi, 0x3FF0000000000000
    call gen_imm_a
    mov edi, '+'
    test r13, r13
    jg .dop
    mov edi, '-'
.dop:
    mov esi, TY_DOUBLE
    mov edx, TY_DOUBLE
    call float_binop
    CG push_a                           ; new value
    mov edi, 2
    CG load_stack_a
    CG mov_b_a
    CG pop_a
    mov rdi, rbx
    call emit_store_type
    test r12d, r12d
    jz .dpre
    CG pop_a                            ; old value
    mov edi, 1
    CG drop
    jmp .fin
.dpre:
    mov edi, 2
    CG drop
    jmp .fin

; discard_result: called after an expression statement. If the whole statement was a
; postfix ++ / -- of a local variable, the old value is not needed: regenerate it as
; a plain  load / add / store.
discard_result:
    mov rdi, [pi_end]
    call tail_is
    test eax, eax
    jz .ret
    mov rdi, [pi_pos]
    call rewind_code
    mov edi, [pi_off]
    mov rsi, [pi_type]
    call load_local_typed
    mov rdi, [pi_step]
    CG add_imm_a
    mov edi, [pi_off]
    mov rsi, [pi_type]
    call store_local_typed
.ret:
    ret

; ---- unary ---------------------------------------------------------------------
parse_unary:
    STACKCHK
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
    push qword [code_pos]
    call parse_unary
    call to_rvalue
    pop rax
    cmp qword [e_type], TY_DOUBLE
    je .negdbl
    cmp rax, [imm_pos]
    jne .negreal
    mov rdi, [imm_end]
    call tail_is
    test eax, eax
    jz .negreal
    mov r8, [imm_val]
    mov rdi, [imm_pos]
    call rewind_code
    neg r8
    mov rdi, r8
    call gen_imm_a
    mov qword [e_type], TY_INT
    ret
.negreal:
    CG neg
    mov qword [e_type], TY_INT
    ret
.negdbl:
    cmp rax, [imm_pos]
    jne .negdbl_rt
    mov rdi, [imm_end]
    call tail_is
    test eax, eax
    jz .negdbl_rt
    mov r8, [imm_val]
    mov rdi, [imm_pos]
    call rewind_code
    mov rcx, 0x8000000000000000
    xor r8, rcx
    mov rdi, r8
    call gen_imm_a
    mov qword [e_type], TY_DOUBLE
    ret
.negdbl_rt:
    mov rdi, fn_dneg
    call call_rt1
    mov qword [e_type], TY_DOUBLE
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
    call truth_value
    CG lnot
    mov qword [e_type], TY_BOOL
    ret
.compl:
    call next_token
    call parse_unary
    call to_rvalue
    CG not
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
    cmp qword [e_type], TY_FUNC
    jne .a0
    ret                             ; &function is the function value itself
.a0:
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
    push r14
    push r15
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
    mov r14, [code_pos]
    CG push_a
    push qword [code_pos]
    call next_token
    lea edi, [r13+1]
    call parse_binary
    call to_rvalue
    ; a double on either side: the soft-float routines take over (left value is on the stack, right one in A)
    mov rax, [rsp+8]
    cmp rax, TY_DOUBLE
    je .dbl
    cmp qword [e_type], TY_DOUBLE
    je .dbl
    pop rsi
    mov rdi, r14
    call finish_operands
    pop rsi
    mov rdx, [e_type]
    mov edi, r12d
    call binop_emit
    jmp .loop
.dbl:
    pop rcx
    pop rsi
    mov rdx, [e_type]
    mov edi, r12d
    call float_binop
    jmp .loop
.done:
    pop r15
    pop r14
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
    mov rdi, rsp
    call cond_jz
    call next_token
    mov edi, 3
    call parse_binary
    call to_rvalue
    cmp qword [tk], T_ANDAND
    je .l
    mov rdi, rsp
    call cond_jz
    push 0
    mov edi, 1
    CG imm_a
    mov rdi, rsp
    CG jmp_chain
    mov rdi, [rsp+8]
    call patch_here
    xor edi, edi
    CG imm_a
    pop rdi
    call patch_here
    add rsp, 8
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
    mov rdi, rsp
    call cond_jnz
    call next_token
    call parse_logand
    call to_rvalue
    cmp qword [tk], T_OROR
    je .l
    mov rdi, rsp
    call cond_jnz
    push 0
    xor edi, edi
    CG imm_a
    mov rdi, rsp
    CG jmp_chain
    mov rdi, [rsp+8]
    call patch_here
    mov edi, 1
    CG imm_a
    pop rdi
    call patch_here
    add rsp, 8
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
    lea rdi, [rsp+8]
    call cond_jz
    call next_token
    call parse_assign
    call to_rvalue
    mov rbx, [e_type]
    mov rdi, rsp
    CG jmp_chain
    mov rdi, [rsp+8]
    call patch_here
    mov edi, ':'
    call expect
    call parse_ternary
    call to_rvalue
    mov rax, [e_type]
    cmp rax, rbx
    je .same
    cmp rbx, TY_DOUBLE
    je .conv2
    cmp rax, TY_DOUBLE
    jne .same
    ERR "the two results of ?: are an int and a double: cast one of them"
.conv2:
    mov rdi, rbx
    call coerce_to
.same:
    pop rdi
    call patch_here
    add rsp, 8
    mov [e_type], rbx
.out:
    pop rbx
    ret

; load_local_typed: edi = frame offset, rsi = type of the variable. A = the variable
load_local_typed:
    push rdi
    mov rdi, rsi
    call type_ls
    pop rdi
    cmp eax, 1
    je .b
    CG load_local_a
    ret
.b: CG load_local_a1
    ret

; store_local_typed: edi = frame offset, rsi = type. Stores A into the variable
; (bool variables are normalised to 0 / 1). A keeps the stored value.
store_local_typed:
    push rdi
    mov rdi, rsi
    call type_ls
    mov r9d, eax
    test esi, 0xFF00
    jnz .st
    cmp sil, TY_BOOL
    jne .st
    CG tobool
.st:
    pop rdi
    cmp r9d, 1
    je .b
    CG store_local_a
    ret
.b: CG store_local_a1
    ret

; parse_expr: an expression with the comma operator,  a, b  evaluates a, then b, and has the value of b
parse_expr:
    call parse_assign
.more:
    cmp qword [tk], ','
    jne .r
    call next_token
    call parse_assign
    jmp .more
.r: ret

parse_assign:
    STACKCHK
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
    ; fast path: assignment to a plain local scalar, no address needs to be kept
    mov rdi, [pk_end]
    call tail_is
    test eax, eax
    jz .p3
    mov rdi, rbx
    call type_ls
    test eax, eax
    jz .p3
    mov r12d, [pk_off]
    mov r13d, eax
    mov rdi, [pk_pos]
    call rewind_code
    call next_token
    call parse_assign
    call to_rvalue
    mov rdi, rbx
    call coerce_to
    mov edi, r12d
    mov rsi, rbx
    call store_local_typed
    mov [e_type], rbx
    mov qword [e_lval], 0
    jmp .ret
.p3:
    CG push_a
    call next_token
    call parse_assign
    call to_rvalue
    mov rdi, rbx
    call coerce_to
    CG pop_b
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
    cmp rbx, TY_DOUBLE
    je .cdbl
    mov rdi, rbx
    call type_ls
    test eax, eax
    jnz .c3
    ERR "compound assignment needs a scalar variable"
.c3:
    mov rdi, [pk_end]
    call tail_is
    test eax, eax
    jz .cgen
    ; local scalar: right side first, then load, operate, store - nothing on the stack
    push r14
    push r15
    mov r14d, [pk_off]
    mov rdi, [pk_pos]
    call rewind_code
    mov r15, [code_pos]
    call next_token
    call parse_assign
    call to_rvalue
    mov r13, [e_type]
    cmp r15, [imm_pos]
    jne .c3ld
    mov rdi, [imm_end]
    call tail_is
    test eax, eax
    jz .c3ld
    mov r8, [imm_val]
    mov rdi, [imm_pos]
    call rewind_code
    mov edi, r14d
    mov rsi, rbx
    call load_local_typed
    mov rdi, r8
    CG imm_b
    jmp .c3op
.c3ld:
    cmp r15, [ld_pos]
    jne .c3gen
    mov rdi, [ld_end]
    call tail_is
    test eax, eax
    jz .c3gen
    mov r8d, [ld_off]
    mov r9d, [ld_size]
    mov rdi, [ld_pos]
    call rewind_code
    mov edi, r14d
    mov rsi, rbx
    call load_local_typed
    mov edi, r8d
    cmp r9d, 8
    jne .c3b1
    CG load_local_b
    jmp .c3op
.c3b1:
    CG load_local_b1
    jmp .c3op
.c3gen:
    CG mov_b_a
    mov edi, r14d
    mov rsi, rbx
    call load_local_typed
.c3op:
    cmp r13, TY_DOUBLE
    jne .c3op1
    ERR "an int variable cannot be updated with a double operator (write i = i + d; with a cast)"
.c3op1:
    sub r12d, T_ADDEQ
    movzx edi, byte [compound_map+r12]
    mov rsi, rbx
    mov rdx, r13
    call binop_emit
    mov edi, r14d
    mov rsi, rbx
    call store_local_typed
    mov [e_type], rbx
    mov qword [e_lval], 0
    pop r15
    pop r14
    jmp .ret
.cgen:
    CG push_a
    mov rdi, rbx
    call emit_load_type
    CG push_a
    call next_token
    call parse_assign
    call to_rvalue
    mov r13, [e_type]
    cmp r13, TY_DOUBLE
    jne .cgen1
    ERR "an int variable cannot be updated with a double operator (write i = i + d; with a cast)"
.cgen1:
    CG mov_b_a
    CG pop_a
    sub r12d, T_ADDEQ
    movzx edi, byte [compound_map+r12]
    mov rsi, rbx
    mov rdx, r13
    call binop_emit
    CG pop_b
    mov rdi, rbx
    call emit_store_type
    mov [e_type], rbx
    mov qword [e_lval], 0
    jmp .ret

; compound assignment on a double:  x += e  x -= e  x *= e  x /= e
.cdbl:
    CG push_a                           ; the address
    mov rdi, rbx
    call emit_load_type
    CG push_a                           ; the old value is the left operand
    call next_token
    call parse_assign
    call to_rvalue
    mov r13, [e_type]
    sub r12d, T_ADDEQ
    movzx edi, byte [compound_map+r12]
    mov rsi, rbx
    mov rdx, r13
    call float_binop
    CG pop_b
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

; asm_arch_match: rdi = name, esi = length -> eax = 1 if the name is the CPU being compiled, 0 for another known CPU;
; an unknown name is an error
asm_arch_match:
    push rbx
    mov rbx, asm_cpu_names
.l:
    cmp qword [rbx], 0
    je .unknown
    mov rdx, [rbx]
    push rdi
    push rsi
    mov rcx, rdi
    mov rdi, rcx
    ; compare (rdi, esi) with the zero terminated name at rdx
    xor eax, eax
.c:
    cmp eax, esi
    jae .end
    mov r8b, [rdx+rax]
    cmp r8b, [rdi+rax]
    jne .no
    inc eax
    jmp .c
.end:
    cmp byte [rdx+rax], 0
    jne .no
    pop rsi
    pop rdi
    mov eax, [rbx+8]
    xor ecx, ecx
    cmp eax, [arch]
    sete cl
    mov eax, ecx
    pop rbx
    ret
.no:
    pop rsi
    pop rdi
    add rbx, 16
    jmp .l
.unknown:
    mov edi, msg_asmcpu
    call fatal_error_tok
CSTR msg_asmcpu, "unknown CPU name in the asm block, use x64, arm64, riscv64 or loongarch64:"
section .rodata
a_x64:   db "x64", 0
a_x8664: db "x86_64", 0
a_amd64: db "amd64", 0
a_arm64: db "arm64", 0
a_aarch: db "aarch64", 0
a_rv64:  db "riscv64", 0
a_rv:    db "rv64", 0
a_la64:  db "loongarch64", 0
a_la:    db "la64", 0
align 8
asm_cpu_names:
    dq a_x64, ARCH_X64
    dq a_x8664, ARCH_X64
    dq a_amd64, ARCH_X64
    dq a_arm64, ARCH_A64
    dq a_aarch, ARCH_A64
    dq a_rv64, ARCH_RV64
    dq a_rv, ARCH_RV64
    dq a_la64, ARCH_LA64
    dq a_la, ARCH_LA64
    dq 0
section .text

; const_double: a constant for a double: [-] floating literal, or an integer constant expression (converted) -> rax = IEEE bits
const_double:
    push rbx
    xor ebx, ebx
    cmp qword [tk], '-'
    jne .nn
    sub rsp, 128
    mov rdi, rsp
    call lex_save
    call next_token
    cmp qword [tk], T_FLT
    jne .notflt
    add rsp, 128
    mov ebx, 1
    jmp .lit
.notflt:
    mov rsi, rsp
    call lex_restore
    add rsp, 128
    jmp .intconst
.nn:
    cmp qword [tk], T_FLT
    jne .intconst
.lit:
    mov rax, [tk_val]
    test ebx, ebx
    jz .lit2
    mov rcx, 0x8000000000000000
    xor rax, rcx
.lit2:
    push rax
    call next_token
    pop rax
    pop rbx
    ret
.intconst:
    call const_expr
    cvtsi2sd xmm0, rax
    movq rax, xmm0
    pop rbx
    ret

; peek_is_flt -> eax = 1 if the current token is a floating literal or a '-' in front of one
peek_is_flt:
    xor eax, eax
    cmp qword [tk], T_FLT
    jne .m
    mov eax, 1
    ret
.m: cmp qword [tk], '-'
    jne .no
    sub rsp, 128
    mov rdi, rsp
    call lex_save
    call next_token
    xor eax, eax
    cmp qword [tk], T_FLT
    sete al
    push rax
    mov rsi, rsp
    add rsi, 8
    call lex_restore
    pop rax
    add rsp, 128
    ret
.no:
    ret

; count_list_elems: the current token is the '{' of an initializer list -> rax = number of top level elements (the position is not changed)
count_list_elems:
    push rbx
    push r12
    push r13
    sub rsp, 128
    mov rdi, rsp
    call lex_save
    xor ebx, ebx                        ; depth
    xor r12d, r12d                      ; finished elements
    xor r13d, r13d                      ; 1 = the current element has started
.l: mov rax, [tk]
    cmp rax, T_EOF
    je .eof
    cmp rax, '{'
    je .open
    cmp rax, '('
    je .open
    cmp rax, '['
    je .open
    cmp rax, '}'
    je .close
    cmp rax, ')'
    je .close
    cmp rax, ']'
    je .close
    cmp rax, ','
    je .comma
    mov r13d, 1
    jmp .nx
.open:
    test ebx, ebx
    jz .o1
    mov r13d, 1
.o1:
    inc ebx
    jmp .nx
.close:
    dec ebx
    jz .done
    jmp .nx
.comma:
    cmp ebx, 1
    jne .nx
    test r13d, r13d
    jz .nx
    inc r12d
    xor r13d, r13d
.nx:
    call next_token
    jmp .l
.eof:
    ERR "unexpected end of file in an initializer list"
.done:
    add r12d, r13d
    mov rsi, rsp
    call lex_restore
    add rsp, 128
    mov eax, r12d
    add rsp, 0
    pop r13
    pop r12
    pop rbx
    ret

; obj_localize_string: edx = data offset of a string -> edx = offset of a copy in this object's own data when the string
; belongs to a built-in library (object mode only)
obj_localize_string:
    cmp dword [obj_mode], 0
    je .r
    cmp edx, FOREIGN_DATA_BASE
    jb .r
    cmp dword [foreign_active], 0
    jne .r                              ; library code is not emitted in an object anyway
    push rax
    push rsi
    push rdi
    push rcx
    lea rdi, [data_buf + rdx]
    mov rsi, rdi
    xor ecx, ecx
.l: cmp byte [rsi+rcx], 0
    je .e
    inc ecx
    jmp .l
.e: mov rdx, rcx
    push rdi
    pop rsi
    call data_add_string
.got:
    mov edx, eax
    pop rcx
    pop rdi
    pop rsi
    pop rax
.r: ret
