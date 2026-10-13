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
    jmp alias_resolve
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
    jmp alias_resolve
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
    jmp alias_resolve
.none:
    xor eax, eax
    ret

; alias_resolve: rax = symbol -> the real symbol if it is a name imported with a_import(file, 'names')
alias_resolve:
    cmp dword [rax+SYM_KIND], S_ALIAS
    jne .r
    mov eax, [rax+SYM_VAL]
    shl rax, 6
    add rax, symtab
.r: ret

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

; class_is_a: edi = struct index, esi = struct index -> eax = 1 if the first is the second or derives from it
class_is_a:
.l:
    cmp edi, esi
    je .yes
    mov eax, [st_base + rdi*4]
    test eax, eax
    jz .no
    lea edi, [rax-1]
    jmp .l
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; member_ok: eax = visibility (0 public, 1 private, 2 protected), edx = struct index of the declaring class
; -> eax = 1 if the code being compiled may use the member
member_ok:
    test eax, eax
    jz .yes
    mov ecx, [cur_class]
    cmp ecx, -1
    je .no
    cmp eax, 1
    jne .prot
    cmp ecx, edx
    jne .no
.yes:
    mov eax, 1
    ret
.prot:
    mov edi, ecx
    mov esi, edx
    jmp class_is_a
.no:
    xor eax, eax
    ret

; method_vis_ok: r12 = method symbol -> eax = 1 if the code being compiled may call it
method_vis_ok:
    xor eax, eax
    test dword [r12+SYM_FLAGS], F_PRIVATE
    jz .np
    mov eax, 1
    jmp .go
.np:
    test dword [r12+SYM_FLAGS], F_PROTECTED
    jz .yes
    mov eax, 2
.go:
    mov edx, [r12+SYM_OWNER]
    jmp member_ok
.yes:
    mov eax, 1
    ret

; type_vptr: rdi = type -> eax = vtable pointer offset + 1 of a plain struct type (0 for anything else)
type_vptr:
    xor eax, eax
    movzx ecx, dil
    cmp ecx, TY_STRUCT
    jne .r
    test edi, 0xFF00
    jnz .r
    mov edx, edi
    shr edx, 16
    mov eax, [st_vptr + rdx*4]
.r: ret

; emit_vptr_init: edi = struct index. A = address of a new object of that class: stores the vtable pointer into it
; (A is preserved)
emit_vptr_init:
    push rbx
    mov ebx, edi
    mov eax, [st_vptr + rbx*4]
    test eax, eax
    jz .out
    lea edi, [rax-1]
    CG push_a
    test edi, edi
    jz .o0
    CG add_imm_a
.o0:
    CG mov_b_a
    mov esi, R_DATA
    mov edx, [st_vt + rbx*4]
    dec edx
    CG lea_global_a
    CG store8
    CG pop_a
.out:
    pop rbx
    ret

; struct_find_method: edi = struct index, rsi = name, edx = len -> rax = symbol or 0
; (looks in the class and then in its base classes; constructors are found with struct_find_ctor)
struct_find_method:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12, rsi
    mov r13d, edx
.try:
    mov edi, ebx
    mov rsi, r12
    mov edx, r13d
    call struct_find_method_here
    test rax, rax
    jnz .out
    mov eax, [st_base + rbx*4]
    test eax, eax
    jz .out
    lea ebx, [rax-1]
    jmp .try
.out:
    pop r13
    pop r12
    pop rbx
    ret

struct_find_method_here:
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

; struct_find_ctor: edi = struct index -> rax = constructor symbol or 0 (a class without
; constructor of its own uses the one of its base class)
struct_find_ctor_here:
    mov eax, [sym_count]
.hl:
    test eax, eax
    jz .hnone
    dec eax
    mov r10, rax
    shl r10, 6
    add r10, symtab
    test dword [r10+SYM_FLAGS], F_CTOR
    jz .hl
    cmp [r10+SYM_OWNER], edi
    jne .hl
    mov rax, r10
    ret
.hnone:
    xor eax, eax
    ret

struct_find_ctor:
.again:
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
    mov eax, [st_base + rdi*4]
    test eax, eax
    jz .nobase
    lea edi, [rax-1]
    jmp .again
.nobase:
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
