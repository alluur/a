; =============================================================================
;  float.asm - the type double (and float, which is the same type)
;
;  A double is an IEEE 754 binary64 held in a normal 64-bit slot (like the "double as int" bit patterns of the cmath module,
;  so both can be mixed with __bits / __dbl). All arithmetic is done by calls into the soft-float functions of cmath
;  (dadd dsub dmul ddiv dcmp itod dtoi dneg), which lib/dfloat.a loads when a program mentions double or a floating literal.
;  Values are converted between int and double wherever a type is known (assignment, initialisation, arguments, return, casts).
; =============================================================================
section .text

section .rodata
fn_dadd:  db "dadd", 0
fn_dsub:  db "dsub", 0
fn_dmul:  db "dmul", 0
fn_ddiv:  db "ddiv", 0
fn_dcmp:  db "dcmp", 0
fn_itod:  db "itod", 0
fn_dtoi:  db "dtoi", 0
fn_dneg:  db "dneg", 0
CSTR msg_dblop, "operator not available for double (use + - * / and comparisons)"
CSTR msg_dblmix, "a double can only be combined with an int or a double"
section .text

; call_rt1: rdi = name of a runtime function with one argument. A = argument -> A = result
call_rt1:
    push rdi
    CG push_a
    pop rdi
    call emit_call_named
    mov edi, 1
    CG drop
    ret

; is_intlike: rdi = type -> eax = 1 for plain int, char, bool (also enums)
is_intlike:
    xor eax, eax
    cmp rdi, TY_INT
    je .y
    cmp rdi, TY_CHAR
    je .y
    cmp rdi, TY_BOOL
    jne .n
.y: mov eax, 1
.n: ret

; coerce_to: rdi = wanted type. The value in A has the type e_type; int <-> double conversions are emitted
; (a double converted to int is truncated, to bool it is "not zero"). Other combinations are left alone.
coerce_to:
    push rbx
    mov rbx, rdi
    mov rax, [e_type]
    cmp rax, rbx
    je .out
    cmp rbx, TY_DOUBLE
    je .to_double
    cmp rax, TY_DOUBLE
    jne .out
    cmp rbx, TY_BOOL
    je .to_bool
    cmp rbx, TY_INT
    je .to_int
    cmp rbx, TY_CHAR
    jne .out
.to_int:
    mov rdi, fn_dtoi
    call call_rt1
    mov [e_type], rbx
    jmp .out
.to_bool:
    call double_to_bool
    jmp .out
.to_double:
    mov rdi, rax
    call is_intlike
    test eax, eax
    jz .out
    mov rdi, fn_itod
    call call_rt1
    mov qword [e_type], TY_DOUBLE
.out:
    pop rbx
    ret

; double_to_bool: A = a double -> A = (A != 0.0), e_type = bool
double_to_bool:
    CG push_a
    xor edi, edi
    CG imm_a
    CG push_a
    mov rdi, fn_dcmp
    call emit_call_named
    mov edi, 2
    CG drop
    CG tobool
    mov qword [e_type], TY_BOOL
    ret

; truth_value: turns a double condition into a bool; other types stay as they are
truth_value:
    cmp qword [e_type], TY_DOUBLE
    jne .r
    jmp double_to_bool
.r: ret

; float_binop: edi = operator token, rsi = left type, rdx = right type. The left value is on the stack (pushed), the right value is in A,
; and one of the operands is a double. Emits the call and sets e_type / e_lval.
float_binop:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12, rsi
    mov r13, rdx
    mov qword [e_lval], 0
    ; the operator
    mov rcx, fn_dadd
    cmp ebx, '+'
    je .opok
    mov rcx, fn_dsub
    cmp ebx, '-'
    je .opok
    mov rcx, fn_dmul
    cmp ebx, '*'
    je .opok
    mov rcx, fn_ddiv
    cmp ebx, '/'
    je .opok
    mov rcx, fn_dcmp
    cmp ebx, T_EQ
    je .opok
    cmp ebx, T_NE
    je .opok
    cmp ebx, '<'
    je .opok
    cmp ebx, '>'
    je .opok
    cmp ebx, T_LE
    je .opok
    cmp ebx, T_GE
    je .opok
    mov edi, msg_dblop
    jmp fatal_error
.opok:
    push rcx
    ; the operands must be double or an int-like type
    cmp r12, TY_DOUBLE
    je .l_ok
    mov rdi, r12
    call is_intlike
    test eax, eax
    jnz .l_ok
    mov edi, msg_dblmix
    jmp fatal_error
.l_ok:
    cmp r13, TY_DOUBLE
    je .r_dbl
    mov rdi, r13
    call is_intlike
    test eax, eax
    jnz .r_int
    mov edi, msg_dblmix
    jmp fatal_error
.r_int:
    ; right is an int, left a double: convert the right one
    mov rdi, fn_itod
    call call_rt1
    CG push_a
    jmp .call
.r_dbl:
    CG push_a                           ; stack: left, right
    cmp r12, TY_DOUBLE
    je .call
    ; left is an int: convert it in place (copy, convert, drop the old slot, push in order again)
    mov edi, 1
    CG load_stack_a
    mov rdi, fn_itod
    call call_rt1
    CG pop_b
    mov edi, 1
    CG drop
    CG push_a
    CG push_b
.call:
    pop rdi
    call emit_call_named
    mov edi, 2
    CG drop
    mov qword [e_type], TY_DOUBLE
    cmp ebx, '+'
    je .done
    cmp ebx, '-'
    je .done
    cmp ebx, '*'
    je .done
    cmp ebx, '/'
    je .done
    mov qword [e_type], TY_BOOL
    ; dcmp: -1 less, 0 equal, 1 greater, 2 unordered
    cmp ebx, T_EQ
    jne .c1
    CG lnot
    jmp .done
.c1:
    cmp ebx, T_NE
    jne .c2
    CG tobool
    jmp .done
.c2:
    cmp ebx, '<'
    jne .c3
    mov rdi, -1
    CG imm_b
    CG cmp_eq
    jmp .done
.c3:
    cmp ebx, '>'
    jne .c4
    mov edi, 1
    CG imm_b
    CG cmp_eq
    jmp .done
.c4:
    cmp ebx, T_LE
    jne .c5
    mov edi, 1
    CG add_imm_a                        ; -1 / 0 / 1 / 2  ->  0 / 1 / 2 / 3: less or equal = 0 or 1
    mov edi, 1
    CG imm_b
    CG cmp_le
    jmp .done
.c5:                                    ; >=: greater or equal = 1 or 0
    mov rdi, -2
    CG imm_b
    CG and
    CG lnot
.done:
    pop r13
    pop r12
    pop rbx
    ret
