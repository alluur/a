; =============================================================================
;  symtab.asm - symbols, structs, fields, types
; =============================================================================
section .text

; sym_new: rdi = name ptr, esi = name len, edx = kind -> rax = symbol pointer
sym_new:
    mov eax, [sym_count]
    cmp eax, SYM_MAX
    jae err_toobig
    inc dword [sym_count]
    shl rax, 6
    add rax, symtab
    mov [rax+SYM_NAME], rdi
    mov [rax+SYM_NLEN], esi
    mov [rax+SYM_KIND], edx
    mov qword [rax+SYM_TYPE], 0
    mov qword [rax+SYM_VAL], 0
    mov dword [rax+SYM_FLAGS], 0
    mov ecx, [cur_module]
    mov [rax+SYM_MOD], ecx
    mov qword [rax+SYM_EXTRA], 0
    mov dword [rax+SYM_OWNER], -1
    mov ecx, [cur_file_id]
    mov [rax+SYM_FILE], ecx
    mov dword [rax+SYM_NPAR], 0
    mov dword [rax+SYM_PATCH], 0
    ret

; sym_index: rax = symbol pointer -> rax = index
sym_index:
    sub rax, symtab
    shr rax, 6
    ret

; sym_lookup: rdi = name, esi = len -> rax = symbol (locals first, then current
; module, then the global module 0) or 0
sym_lookup:
    push rbx
    mov r8, rdi
    mov r9d, esi
    mov eax, [sym_count]
.pa:
    test eax, eax
    jz .pb0
    dec eax
    mov r10, rax
    shl r10, 6
    add r10, symtab
    cmp [r10+SYM_NLEN], r9d
    jne .pa
    mov edx, [r10+SYM_KIND]
    cmp edx, S_LOCAL
    je .pa_name
    test dword [r10+SYM_FLAGS], F_METHOD
    jnz .pa
    mov edx, [r10+SYM_MOD]
    cmp edx, [cur_module]
    jne .pa
.pa_name:
    mov rdi, [r10+SYM_NAME]
    mov rsi, r8
    mov ecx, r9d
    repe cmpsb
    jne .pa
    mov rax, r10
    pop rbx
    ret
.pb0:
    cmp dword [cur_module], 0
    je .none
    mov eax, [sym_count]
.pb:
    test eax, eax
    jz .none
    dec eax
    mov r10, rax
    shl r10, 6
    add r10, symtab
    cmp [r10+SYM_NLEN], r9d
    jne .pb
    cmp dword [r10+SYM_KIND], S_LOCAL
    je .pb
    test dword [r10+SYM_FLAGS], F_METHOD
    jnz .pb
    cmp dword [r10+SYM_MOD], 0
    jne .pb
    mov rdi, [r10+SYM_NAME]
    mov rsi, r8
    mov ecx, r9d
    repe cmpsb
    jne .pb
    mov rax, r10
    pop rbx
    ret
.none:
    xor eax, eax
    pop rbx
    ret

; sym_find_global: rdi = name, esi = len, edx = module id -> rax = symbol or 0
sym_find_global:
    mov r8, rdi
    mov r9d, esi
    mov r11d, edx
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
    cmp dword [r10+SYM_KIND], S_LOCAL
    je .l
    test dword [r10+SYM_FLAGS], F_METHOD
    jnz .l
    cmp [r10+SYM_MOD], r11d
    jne .l
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

; check_access: rax = symbol. Errors if it is private to another file.
check_access:
    test dword [rax+SYM_FLAGS], F_PRIVATE
    jz .ok
    mov ecx, [rax+SYM_FILE]
    cmp ecx, [cur_file_id]
    je .ok
    push rax
    mov edi, msg_private
    call fatal_error_tok
.ok:
    ret
CSTR msg_private, "access to private declaration"

; ---- structs -----------------------------------------------------------------
; struct_ptr: edi = index -> rax = pointer to struct entry
struct_ptr:
    mov eax, edi
    shl rax, 5
    add rax, struct_tab
    ret

; struct_find_field: edi = struct index, rsi = name, edx = len -> rax = field ptr or 0
struct_find_field:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13d, edx
    call struct_ptr
    mov rbx, rax
    mov ecx, [rbx+ST_NFIELDS]
    mov eax, [rbx+ST_FIRST]
    shl rax, 5
    add rax, field_tab
.l:
    test ecx, ecx
    jz .none
    cmp [rax+FD_NLEN], r13d
    jne .next
    push rcx
    push rax
    mov rdi, [rax+FD_NAME]
    mov rsi, r12
    mov ecx, r13d
    repe cmpsb
    pop rax
    pop rcx
    je .found
.next:
    add rax, FD_SIZEOF
    dec ecx
    jmp .l
.none:
    xor eax, eax
.found:
    pop r13
    pop r12
    pop rbx
    ret

; struct_find_method: edi = struct index, rsi = name, edx = len -> rax = symbol or 0
; (constructors are found with name == class name via struct_find_ctor)
struct_find_method:
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
    test dword [r10+SYM_FLAGS], F_METHOD
    jz .l
    test dword [r10+SYM_FLAGS], F_CTOR
    jnz .l
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

; struct_find_ctor: edi = struct index -> rax = constructor symbol or 0
struct_find_ctor:
    mov eax, [sym_count]
.l:
    test eax, eax
    jz .none
    dec eax
    mov r10, rax
    shl r10, 6
    add r10, symtab
    test dword [r10+SYM_FLAGS], F_CTOR
    jz .l
    cmp [r10+SYM_OWNER], edi
    jne .l
    mov rax, r10
    ret
.none:
    xor eax, eax
    ret

; ---- types -------------------------------------------------------------------
; type_size: rdi = type -> rax = size in bytes of a value of that type
type_size:
    test edi, 0xFF00
    jnz .ptr
    movzx eax, dil
    cmp eax, TY_INT
    je .eight
    cmp eax, TY_FUNC
    je .eight
    cmp eax, TY_STRUCT
    je .struct
    mov eax, 1
    ret
.eight:
    mov eax, 8
    ret
.ptr:
    mov eax, 8
    ret
.struct:
    mov eax, edi
    shr eax, 16
    and eax, 0xFFFF
    shl rax, 5
    mov eax, [struct_tab+rax+ST_SIZE]
    ret

; type_pointee_size: rdi = pointer type -> rax = size of what it points to
type_pointee_size:
    btr rdi, TF_ARRAY_BIT
    sub rdi, TY_PTR1
    jmp type_size

; type_ls: rdi = type -> eax = 0 aggregate (no scalar load), 1 byte, 8 qword
type_ls:
    test edi, 0xFF00
    jnz .q
    movzx eax, dil
    cmp eax, TY_CHAR
    je .b
    cmp eax, TY_BOOL
    je .b
    cmp eax, TY_STRUCT
    je .agg
    cmp eax, TY_VOID
    je .agg
.q: mov eax, 8
    ret
.b: mov eax, 1
    ret
.agg:
    xor eax, eax
    ret
