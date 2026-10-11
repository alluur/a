; =============================================================================
;  cg_x86.asm - x86-64 backend (Linux, Android x86-64, Windows)
;  Abstract registers: A = rax, B = rcx, D = rdx. One stack slot = 8 bytes.
; =============================================================================
section .text

x86_push_a:     EM 0x50
                ret
x86_push_b:     EM 0x51
                ret
x86_pop_a:      EM 0x58
                ret
x86_pop_b:      EM 0x59
                ret
x86_mov_b_a:    EM 0x48, 0x89, 0xC1
                ret
x86_mov_a_b:    EM 0x48, 0x89, 0xC8
                ret
x86_mov_d_a:    EM 0x48, 0x89, 0xC2
                ret
x86_mov_a_d:    EM 0x48, 0x89, 0xD0
                ret

; edi = slots
x86_drop:
    push rax
    push rdi
    lea eax, [rdi*8]
    test eax, eax
    jz .out
    cmp eax, 127
    ja .big
    EM 0x48, 0x83, 0xC4
    mov edi, eax
    call emit_b
    jmp .out
.big:
    EM 0x48, 0x81, 0xC4
    mov edi, eax
    call emit_d
.out:
    pop rdi
    pop rax
    ret

; rdi = value -> A
x86_imm_a:
    push rax
    movsxd rax, edi
    cmp rax, rdi
    jne .big
    EM 0x48, 0xC7, 0xC0
    call emit_d
    pop rax
    ret
.big:
    EM 0x48, 0xB8
    call emit_q
    pop rax
    ret

; rdi = value -> B
x86_imm_b:
    push rax
    movsxd rax, edi
    cmp rax, rdi
    jne .big
    EM 0x48, 0xC7, 0xC1
    call emit_d
    pop rax
    ret
.big:
    EM 0x48, 0xB9
    call emit_q
    pop rax
    ret

x86_lea_local_a:
    EM 0x48, 0x8D, 0x85
    jmp emit_d
x86_lea_local_b:
    EM 0x48, 0x8D, 0x8D
    jmp emit_d
x86_load_local_a:
    EM 0x48, 0x8B, 0x85
    jmp emit_d
x86_store_local_a:
    EM 0x48, 0x89, 0x85
    jmp emit_d

; edi = frame offset, esi = size
x86_zero_local:
    push rdi
    push rsi
    cmp esi, 8
    jne .rep
    EM 0x48, 0xC7, 0x85
    call emit_d
    EM 0, 0, 0, 0
    jmp .out
.rep:
    EM 0x48, 0x8D, 0xBD
    call emit_d
    EM 0x31, 0xC0, 0xB9
    mov edi, esi
    call emit_d
    EM 0xF3, 0xAA
.out:
    pop rsi
    pop rdi
    ret

; esi = kind, edx = target
x86_lea_global_a:
    push rdi
    EM 0x48, 0x8D, 0x05
    mov edi, [code_pos]
    push rdi
    xor edi, edi
    call emit_d
    pop rdi
    call add_reloc
    pop rdi
    ret

x86_load8_a:    EM 0x48, 0x8B, 0x00
                ret
x86_load1_a:    EM 0x48, 0x0F, 0xB6, 0x00
                ret
x86_store8:     EM 0x48, 0x89, 0x01
                ret
x86_store1:     EM 0x88, 0x01
                ret

; edi = size
x86_copy_mem:
    push rdi
    EM 0x48, 0x89, 0xC6, 0x48, 0x89, 0xCF, 0x48, 0x89, 0xC8, 0xB9
    call emit_d
    EM 0xF3, 0xA4
    pop rdi
    ret

x86_add_imm_a:
    EM 0x48, 0x05
    jmp emit_d
x86_mul_imm_a:
    EM 0x48, 0x69, 0xC0
    jmp emit_d
x86_mul_imm_b:
    EM 0x48, 0x69, 0xC9
    jmp emit_d

x86_add:        EM 0x48, 0x01, 0xC8
                ret
x86_sub:        EM 0x48, 0x29, 0xC8
                ret
x86_mul:        EM 0x48, 0x0F, 0xAF, 0xC1
                ret
x86_div:        EM 0x48, 0x99, 0x48, 0xF7, 0xF9
                ret
x86_mod:        EM 0x48, 0x99, 0x48, 0xF7, 0xF9, 0x48, 0x89, 0xD0
                ret
x86_and:        EM 0x48, 0x21, 0xC8
                ret
x86_or:         EM 0x48, 0x09, 0xC8
                ret
x86_xor:        EM 0x48, 0x31, 0xC8
                ret
x86_shl:        EM 0x48, 0xD3, 0xE0
                ret
x86_sar:        EM 0x48, 0xD3, 0xF8
                ret

; cmp A,B and set A to 0/1 with condition byte in dil
x86_cmp_cc:
    push rdi
    EM 0x48, 0x39, 0xC8, 0x0F
    pop rdi
    push rdi
    call emit_b
    EM 0xC0, 0x0F, 0xB6, 0xC0
    pop rdi
    ret
x86_cmp_eq:     push rdi
                mov dil, 0x94
                call x86_cmp_cc
                pop rdi
                ret
x86_cmp_ne:     push rdi
                mov dil, 0x95
                call x86_cmp_cc
                pop rdi
                ret
x86_cmp_lt:     push rdi
                mov dil, 0x9C
                call x86_cmp_cc
                pop rdi
                ret
x86_cmp_gt:     push rdi
                mov dil, 0x9F
                call x86_cmp_cc
                pop rdi
                ret
x86_cmp_le:     push rdi
                mov dil, 0x9E
                call x86_cmp_cc
                pop rdi
                ret
x86_cmp_ge:     push rdi
                mov dil, 0x9D
                call x86_cmp_cc
                pop rdi
                ret

x86_neg:        EM 0x48, 0xF7, 0xD8
                ret
x86_not:        EM 0x48, 0xF7, 0xD0
                ret
x86_lnot:       EM 0x48, 0x85, 0xC0, 0x0F, 0x94, 0xC0, 0x0F, 0xB6, 0xC0
                ret
x86_zext8:      EM 0x0F, 0xB6, 0xC0
                ret
x86_tobool:     EM 0x48, 0x85, 0xC0, 0x0F, 0x95, 0xC0, 0x0F, 0xB6, 0xC0
                ret

; ---- jumps ---------------------------------------------------------------------------
; chain_slot: rdi = address of a chain head variable. Emits a 4 byte link
; placeholder and makes the head point to it.
chain_slot:
    push rax
    push rdx
    push rdi
    mov rdx, rdi
    mov rax, [code_pos]
    mov edi, [rdx]
    call emit_d
    mov [rdx], rax
    pop rdi
    pop rdx
    pop rax
    ret

x86_jz_chain:
    EM 0x48, 0x85, 0xC0, 0x0F, 0x84
    jmp chain_slot
x86_jnz_chain:
    EM 0x48, 0x85, 0xC0, 0x0F, 0x85
    jmp chain_slot
x86_jmp_chain:
    EM 0xE9
    jmp chain_slot

; rdi = target
x86_jmp_back:
    push rdi
    push rax
    mov rax, rdi
    EM 0xE9
    mov rdi, rax
    sub rdi, [code_pos]
    sub rdi, 4
    call emit_d
    pop rax
    pop rdi
    ret

x86_jnz_back:
    push rdi
    push rax
    mov rax, rdi
    EM 0x48, 0x85, 0xC0, 0x0F, 0x85
    mov rdi, rax
    sub rdi, [code_pos]
    sub rdi, 4
    call emit_d
    pop rax
    pop rdi
    ret

; edi = frame offset, rsi = value (imm32), rdx = target position
x86_case_jump:
    push rdi
    push rax
    movsxd rax, esi
    cmp rax, rsi
    je .fits
    ERR "case value does not fit in 32 bits"
.fits:
    EM 0x48, 0x8B, 0x85
    call emit_d
    EM 0x48, 0x3D
    mov edi, esi
    call emit_d
    EM 0x0F, 0x84
    mov rdi, rdx
    sub rdi, [code_pos]
    sub rdi, 4
    call emit_d
    pop rax
    pop rdi
    ret

; rdi = chain head, rsi = target
x86_patch_chain:
    push rax
    push rcx
    push rdi
.l: test rdi, rdi
    jz .d
    mov eax, [code_buf+rdi]
    mov rcx, rsi
    sub rcx, rdi
    sub rcx, 4
    mov [code_buf+rdi], ecx
    mov rdi, rax
    jmp .l
.d: pop rdi
    pop rcx
    pop rax
    ret

; rdi = function symbol: emits call (patch chain if not defined yet)
x86_call_sym:
    push rax
    push rdx
    push rdi
    EM 0xE8
    mov rax, [rdi+SYM_VAL]
    cmp rax, -1
    je .fwd
    mov rdx, rax
    mov rax, [code_pos]
    add rax, 4
    sub rdx, rax
    mov edi, edx
    call emit_d
    jmp .out
.fwd:
    mov eax, [rdi+SYM_PATCH]
    mov rdx, [code_pos]
    mov [rdi+SYM_PATCH], edx
    mov edi, eax
    call emit_d
.out:
    pop rdi
    pop rdx
    pop rax
    ret

; ---- functions -----------------------------------------------------------------------
x86_prologue:
    push rax
    push rdi
    cmp dword [target], TGT_WINDOWS
    je .win
    EM 0x55, 0x48, 0x89, 0xE5, 0x48, 0x81, 0xEC
    mov rax, [code_pos]
    mov [frame_patch], rax
    xor edi, edi
    call emit_d
    jmp .out
.win:
    ; push rbp; mov rbp,rsp; mov eax,<frame>; call chkstk; sub rsp,rax
    EM 0x55, 0x48, 0x89, 0xE5, 0xB8
    mov rax, [code_pos]
    mov [frame_patch], rax
    xor edi, edi
    call emit_d
    EM 0xE8
    mov rdi, [chkstk_pos]
    sub rdi, [code_pos]
    sub rdi, 4
    call emit_d
    EM 0x48, 0x29, 0xC4
.out:
    pop rdi
    pop rax
    ret

x86_epilogue:
    EM 0xC9, 0xC3
    ret

; edi = frame size
x86_set_frame:
    push rcx
    mov rcx, [frame_patch]
    mov [code_buf+rcx], edi
    pop rcx
    ret

; edi = number of main() parameters. Linux/Android: argc = [rsp], argv = rsp+8
x86_entry_args:
    push rdi
    EM 0x48, 0x8B, 0x04, 0x24
    EM 0x48, 0x8D, 0x4C, 0x24, 0x08
    pop rdi
    cmp edi, 1
    jb .out
    EM 0x50
    cmp edi, 2
    jb .out
    EM 0x51
.out:
    ret

; ---- relocations ------------------------------------------------------------------------
; apply_relocs_x86: [code_vaddr] [data_vaddr] [bss_vaddr] [iat_vaddr] must be set
apply_relocs_x86:
    xor ecx, ecx
.l:
    cmp ecx, [rel_count]
    jae .done
    mov rax, rcx
    shl rax, 4
    add rax, rel_buf
    mov edi, [rax]                  ; position
    mov esi, [rax+4]                ; kind
    mov edx, [rax+8]                ; target
    cmp esi, R_DATA
    je .data
    cmp esi, R_BSS
    je .bss
    cmp esi, R_IAT
    je .iat
    cmp esi, R_DATA64
    je .d64
    jmp .n
.data:
    mov r8, [data_vaddr]
    add r8, rdx
    jmp .rel
.bss:
    mov r8, [bss_vaddr]
    add r8, rdx
    jmp .rel
.iat:
    mov r8, [iat_vaddr]
    lea r8, [r8+rdx*8]
.rel:
    mov r9, [code_vaddr]
    lea r9, [r9+rdi+4]
    sub r8, r9
    mov [code_buf+rdi], r8d
    jmp .n
.d64:
    mov r8, [data_vaddr]
    add [data_buf+rdi], r8
.n:
    inc ecx
    jmp .l
.done:
    ret

section .rodata
%macro CGT_X86 1
    dq x86_%1
%endmacro
cg_tab_x86:
    CGLIST CGT_X86
section .text

; Windows stack probe: eax = bytes about to be allocated. Touches every page in
; descending order so the guard page mechanism can commit the stack.
section .rodata
chkstk_blob:
    push rcx
    push rax
    lea rcx, [rsp+24]
.l: cmp rax, 4096
    jbe .last
    sub rcx, 4096
    test [rcx], al
    sub rax, 4096
    jmp .l
.last:
    sub rcx, rax
    test [rcx], al
    pop rax
    pop rcx
    ret
chkstk_blob_end:
section .text
