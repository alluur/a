; =============================================================================
;  cg_a64.asm - AArch64 backend (Linux ARM64, Android ARM64)
;
;  Abstract registers: A = x0, B = x1, D = x2; x3-x5 and x16 are scratch for the
;  primitives themselves, x29 = frame pointer, x30 = link register.
;  One stack slot = 16 bytes (sp must stay 16 byte aligned); a "push" is
;  str x0,[sp,#-16]!.  Parameter i of n lives at [x29 + 16 + 16*(n-1-i)].
;  All instruction words come from GNU as output and were verified with objdump.
; =============================================================================
section .text

; emit a literal instruction word
%macro A64 1
    push rdi
    mov edi, %1
    call emit_d
    pop rdi
%endmacro

; ---- helpers ----------------------------------------------------------------------------
; a64_movimm: edi = register number, rsi = 64 bit value. Emits movz/movk/movn.
a64_movimm:
    push rax
    push rcx
    push rdx
    push rdi
    push rsi
    push r8
    push r9
    push r10
    mov r8d, edi
    mov rax, rsi
    cmp rax, 0xFFFF
    ja .notz
    mov edi, 0xD2800000
    mov ecx, eax
    shl ecx, 5
    or edi, ecx
    or edi, r8d
    call emit_d
    jmp .out
.notz:
    mov rdx, rax
    not rdx
    cmp rdx, 0xFFFF
    ja .general
    mov edi, 0x92800000
    mov ecx, edx
    shl ecx, 5
    or edi, ecx
    or edi, r8d
    call emit_d
    jmp .out
.general:
    xor r9d, r9d
    mov r10d, 1
.g1:
    cmp r9d, 4
    jae .out
    mov ecx, r9d
    shl ecx, 4
    mov rdx, rax
    shr rdx, cl
    and edx, 0xFFFF
    jz .gnext
    mov edi, 0xF2800000
    test r10d, r10d
    jz .gk
    mov edi, 0xD2800000
    xor r10d, r10d
.gk:
    mov ecx, r9d
    shl ecx, 21
    or edi, ecx
    shl edx, 5
    or edi, edx
    or edi, r8d
    call emit_d
.gnext:
    inc r9d
    jmp .g1
.out:
    pop r10
    pop r9
    pop r8
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rax
    ret

; a64_addr_local: edi = destination register, esi = signed frame offset.
; Emits  rd = x29 + offset
a64_addr_local:
    push rax
    push rcx
    push rdi
    push rsi
    mov r11d, edi                   ; rd
    movsxd rax, esi
    test rax, rax
    js .neg
    cmp rax, 4095
    ja .bigpos
    mov edi, 0x910003A0             ; add rd, x29, #imm
    mov ecx, eax
    shl ecx, 10
    or edi, ecx
    or edi, r11d
    call emit_d
    jmp .out
.bigpos:
    mov edi, 16
    mov rsi, rax
    call a64_movimm
    mov edi, 0x8B1003A0             ; add rd, x29, x16
    or edi, r11d
    call emit_d
    jmp .out
.neg:
    neg rax
    cmp rax, 4095
    ja .bigneg
    mov edi, 0xD10003A0             ; sub rd, x29, #imm
    mov ecx, eax
    shl ecx, 10
    or edi, ecx
    or edi, r11d
    call emit_d
    jmp .out
.bigneg:
    mov edi, 16
    mov rsi, rax
    call a64_movimm
    mov edi, 0xCB1003A0             ; sub rd, x29, x16
    or edi, r11d
    call emit_d
.out:
    pop rsi
    pop rdi
    pop rcx
    pop rax
    ret

; ---- stack and register moves ------------------------------------------------------------
a64_push_a:     A64 0xF81F0FE0
                ret
a64_push_b:     A64 0xF81F0FE1
                ret
a64_pop_a:      A64 0xF84107E0
                ret
a64_pop_b:      A64 0xF84107E1
                ret
a64_mov_b_a:    A64 0xAA0003E1
                ret
a64_mov_a_b:    A64 0xAA0103E0
                ret
a64_mov_d_a:    A64 0xAA0003E2
                ret
a64_mov_a_d:    A64 0xAA0203E0
                ret

; edi = slots
a64_drop:
    push rdi
    test edi, edi
    jz .out
    cmp edi, 255
    jbe .ok
    ERR "too many arguments in a call"
.ok:
    shl edi, 4
    shl edi, 10
    or edi, 0x910003FF              ; add sp, sp, #(16*n)
    call emit_d
.out:
    pop rdi
    ret

a64_imm_a:
    push rdi
    push rsi
    mov rsi, rdi
    xor edi, edi
    call a64_movimm
    pop rsi
    pop rdi
    ret

a64_imm_b:
    push rdi
    push rsi
    mov rsi, rdi
    mov edi, 1
    call a64_movimm
    pop rsi
    pop rdi
    ret

; ---- locals and globals -------------------------------------------------------------------
a64_lea_local_a:
    push rdi
    push rsi
    mov esi, edi
    xor edi, edi
    call a64_addr_local
    pop rsi
    pop rdi
    ret

a64_lea_local_b:
    push rdi
    push rsi
    mov esi, edi
    mov edi, 1
    call a64_addr_local
    pop rsi
    pop rdi
    ret

a64_load_local_a:
    push rdi
    push rsi
    movsxd rax, edi
    push rax
    cmp rax, -256
    jl .far
    cmp rax, 255
    jg .far
    and eax, 0x1FF
    shl eax, 12
    or eax, 0xF84003A0              ; ldur x0, [x29, #off]
    mov edi, eax
    call emit_d
    jmp .out
.far:
    mov esi, edi
    mov edi, 16
    call a64_addr_local
    A64 0xF9400200                  ; ldr x0, [x16]
.out:
    pop rax
    pop rsi
    pop rdi
    ret

a64_store_local_a:
    push rdi
    push rsi
    movsxd rax, edi
    push rax
    cmp rax, -256
    jl .far
    cmp rax, 255
    jg .far
    and eax, 0x1FF
    shl eax, 12
    or eax, 0xF80003A0              ; stur x0, [x29, #off]
    mov edi, eax
    call emit_d
    jmp .out
.far:
    mov esi, edi
    mov edi, 16
    call a64_addr_local
    A64 0xF9000200                  ; str x0, [x16]
.out:
    pop rax
    pop rsi
    pop rdi
    ret

; generic "local at frame offset" access: word templates for the near (ldur/stur) and
; far (address in x16) forms are passed in r8d / r9d
a64_local_access:
    push rdi
    push rsi
    push rax
    movsxd rax, edi
    cmp rax, -256
    jl .far
    cmp rax, 255
    jg .far
    and eax, 0x1FF
    shl eax, 12
    or eax, r8d
    mov edi, eax
    call emit_d
    jmp .out
.far:
    mov esi, edi
    mov edi, 16
    call a64_addr_local
    mov edi, r9d
    call emit_d
.out:
    pop rax
    pop rsi
    pop rdi
    ret

a64_load_local_a1:
    push r8
    push r9
    mov r8d, 0x384003A0             ; ldurb w0, [x29, #off]
    mov r9d, 0x39400200             ; ldrb  w0, [x16]
    call a64_local_access
    pop r9
    pop r8
    ret
a64_load_local_b:
    push r8
    push r9
    mov r8d, 0xF84003A1             ; ldur x1, [x29, #off]
    mov r9d, 0xF9400201             ; ldr  x1, [x16]
    call a64_local_access
    pop r9
    pop r8
    ret
a64_load_local_b1:
    push r8
    push r9
    mov r8d, 0x384003A1             ; ldurb w1, [x29, #off]
    mov r9d, 0x39400201             ; ldrb  w1, [x16]
    call a64_local_access
    pop r9
    pop r8
    ret
a64_store_local_a1:
    push r8
    push r9
    mov r8d, 0x380003A0             ; sturb w0, [x29, #off]
    mov r9d, 0x39000200             ; strb  w0, [x16]
    call a64_local_access
    pop r9
    pop r8
    ret

; edi = frame offset, esi = size
a64_zero_local:
    push rdi
    push rsi
    push rdx
    mov edx, esi
    mov esi, edi
    mov edi, 2
    call a64_addr_local             ; x2 = &local
    cmp edx, 8
    jne .loop
    A64 0xF900005F                  ; str xzr, [x2]
    jmp .out
.loop:
    mov edi, 3
    mov esi, edx
    call a64_movimm                 ; x3 = size
    A64 0x3800145F                  ; strb wzr, [x2], #1
    A64 0xF1000463                  ; subs x3, x3, #1
    A64 0x54FFFFC1                  ; b.ne -8
.out:
    pop rdx
    pop rsi
    pop rdi
    ret

; esi = kind (R_DATA / R_BSS), edx = target
a64_lea_global_a:
    push rdi
    mov edi, [code_pos]
    call add_reloc
    A64 0x90000000                  ; adrp x0, #0   (patched at link time)
    A64 0x91000000                  ; add  x0, x0, #0
    pop rdi
    ret

; ---- memory ----------------------------------------------------------------------------------
a64_load8_a:    A64 0xF9400000
                ret
a64_load1_a:    A64 0x39400000
                ret
a64_store8:     A64 0xF9000020
                ret
a64_store1:     A64 0x39000020
                ret

; edi = size: copy A -> B, result A = B
a64_copy_mem:
    push rdi
    push rsi
    mov esi, edi
    A64 0xAA0003E2                  ; mov x2, x0
    A64 0xAA0103E3                  ; mov x3, x1
    A64 0xAA0103E0                  ; mov x0, x1
    mov edi, 4
    call a64_movimm                 ; x4 = size
    A64 0x38401445                  ; ldrb w5, [x2], #1
    A64 0x38001465                  ; strb w5, [x3], #1
    A64 0xF1000484                  ; subs x4, x4, #1
    A64 0x54FFFFA1                  ; b.ne -12
    pop rsi
    pop rdi
    ret

; ---- arithmetic ----------------------------------------------------------------------------------
; edi = signed 32 bit immediate
a64_add_imm_a:
    push rdi
    push rsi
    movsxd rax, edi
    push rax
    test rax, rax
    js .neg
    cmp rax, 4095
    ja .big
    shl eax, 10
    or eax, 0x91000000              ; add x0, x0, #imm
    mov edi, eax
    call emit_d
    jmp .out
.neg:
    neg rax
    cmp rax, 4095
    ja .bigneg
    shl eax, 10
    or eax, 0xD1000000              ; sub x0, x0, #imm
    mov edi, eax
    call emit_d
    jmp .out
.bigneg:
    neg rax
.big:
    mov rsi, rax
    mov edi, 16
    call a64_movimm
    A64 0x8B100000                  ; add x0, x0, x16
.out:
    pop rax
    pop rsi
    pop rdi
    ret

a64_mul_imm_a:
    push rdi
    push rsi
    mov edi, edi
    mov rsi, rdi
    mov edi, 16
    call a64_movimm
    A64 0x9B107C00                  ; mul x0, x0, x16
    pop rsi
    pop rdi
    ret

a64_mul_imm_b:
    push rdi
    push rsi
    mov edi, edi
    mov rsi, rdi
    mov edi, 16
    call a64_movimm
    A64 0x9B107C21                  ; mul x1, x1, x16
    pop rsi
    pop rdi
    ret

a64_add:        A64 0x8B010000
                ret
a64_sub:        A64 0xCB010000
                ret
a64_mul:        A64 0x9B017C00
                ret
a64_div:        A64 0x9AC10C00
                ret
a64_mod:        A64 0x9AC10C02
                A64 0x9B018040
                ret
a64_and:        A64 0x8A010000
                ret
a64_or:         A64 0xAA010000
                ret
a64_xor:        A64 0xCA010000
                ret
a64_shl:        A64 0x9AC12000
                ret
a64_sar:        A64 0x9AC12800
                ret

a64_cmp_eq:     A64 0xEB01001F
                A64 0x9A9F17E0
                ret
a64_cmp_ne:     A64 0xEB01001F
                A64 0x9A9F07E0
                ret
a64_cmp_lt:     A64 0xEB01001F
                A64 0x9A9FA7E0
                ret
a64_cmp_gt:     A64 0xEB01001F
                A64 0x9A9FD7E0
                ret
a64_cmp_le:     A64 0xEB01001F
                A64 0x9A9FC7E0
                ret
a64_cmp_ge:     A64 0xEB01001F
                A64 0x9A9FB7E0
                ret

a64_neg:        A64 0xCB0003E0
                ret
a64_not:        A64 0xAA2003E0
                ret
a64_lnot:       A64 0xF100001F
                A64 0x9A9F17E0
                ret
a64_zext8:      A64 0x92401C00
                ret
a64_tobool:     A64 0xF100001F
                A64 0x9A9F07E0
                ret

; ---- jumps ---------------------------------------------------------------------------------------
; a64_chain_slot: rdi = &head. Emits a 'b' whose imm26 holds the previous chain head
a64_chain_slot:
    push rax
    push rdx
    push rdi
    mov rdx, rdi
    mov rax, [code_pos]
    mov edi, [rdx]
    shr edi, 2
    or edi, 0x14000000
    call emit_d
    mov [rdx], rax
    pop rdi
    pop rdx
    pop rax
    ret

a64_jz_chain:
    A64 0xB5000040                  ; cbnz x0, +8
    jmp a64_chain_slot
a64_jnz_chain:
    A64 0xB4000040                  ; cbz x0, +8
    jmp a64_chain_slot
a64_jmp_chain:
    jmp a64_chain_slot

; edi = condition code CC_*, rsi = &chain head: cmp A,B; jump to the chain if A cc B.
; Emitted as  cmp x0,x1 ; b.<not cc> +8 ; b chain   (full branch range)
a64_jcmp_chain:
    push rax
    push rdi
    push rsi
    A64 0xEB01001F                  ; cmp x0, x1
    mov eax, edi
    movzx edi, byte [a64_inv_cond + rax]
    or edi, 0x54000040              ; b.<inverse> +8
    call emit_d
    mov rdi, rsi
    call a64_chain_slot
    pop rsi
    pop rdi
    pop rax
    ret
section .rodata
; inverse ARM condition codes for eq ne lt gt le ge  ->  ne eq ge le gt lt
a64_inv_cond: db 1, 0, 0xA, 0xD, 0xC, 0xB
section .text

; rdi = target position
a64_jmp_back:
    push rdi
    push rax
    mov rax, rdi
    sub rax, [code_pos]
    sar rax, 2
    and eax, 0x03FFFFFF
    or eax, 0x14000000
    mov edi, eax
    call emit_d
    pop rax
    pop rdi
    ret

a64_jnz_back:
    A64 0xB4000040                  ; cbz x0, +8
    jmp a64_jmp_back

; edi = frame offset, rsi = value, rdx = target position
a64_case_jump:
    push rdi
    push rsi
    push rdx
    push rax
    call a64_load_local_a
    mov edi, 16
    call a64_movimm                 ; x16 = value (rsi)
    A64 0xEB10001F                  ; cmp x0, x16
    A64 0x54000041                  ; b.ne +8
    mov rdi, rdx
    call a64_jmp_back
    pop rax
    pop rdx
    pop rsi
    pop rdi
    ret

; rdi = chain head, rsi = target
a64_patch_chain:
    push rax
    push rcx
    push rdx
    push rdi
.l: test rdi, rdi
    jz .d
    mov eax, [code_buf+rdi]
    mov edx, eax
    and edx, 0x03FFFFFF
    shl edx, 2
    mov rcx, rsi
    sub rcx, rdi
    sar rcx, 2
    and ecx, 0x03FFFFFF
    and eax, 0xFC000000
    or eax, ecx
    mov [code_buf+rdi], eax
    mov edi, edx
    jmp .l
.d: pop rdi
    pop rdx
    pop rcx
    pop rax
    ret

; rdi = function symbol
a64_call_sym:
    push rax
    push rdx
    push rdi
    mov rax, [rdi+SYM_VAL]
    cmp rax, -1
    je .fwd
    sub rax, [code_pos]
    sar rax, 2
    and eax, 0x03FFFFFF
    or eax, 0x94000000
    mov edi, eax
    call emit_d
    jmp .out
.fwd:
    mov eax, [rdi+SYM_PATCH]
    mov rdx, [code_pos]
    mov [rdi+SYM_PATCH], edx
    shr eax, 2
    or eax, 0x94000000
    mov edi, eax
    call emit_d
.out:
    pop rdi
    pop rdx
    pop rax
    ret

; rdi = function symbol -> A = its address (adrp + add, resolved when the layout is known: R_CODE)
a64_lea_func_a:
    push rdi
    push rsi
    push rdx
    sub rdi, symtab
    shr rdi, 6
    mov edx, edi
    mov edi, [code_pos]
    mov esi, R_CODE
    call add_reloc
    A64 0x90000000                  ; adrp x0, #0
    A64 0x91000000                  ; add  x0, x0, #0
    pop rdx
    pop rsi
    pop rdi
    ret

a64_call_a:
    A64 0xD63F0000                  ; blr x0
    ret

; edi = n: x0 = [sp + 16*n]
a64_load_stack_a:
    push rdi
    shl edi, 1
    cmp edi, 4095
    jbe .ok
    ERR "too many arguments in a call"
.ok:
    shl edi, 10
    or edi, 0xF94003E0              ; ldr x0, [sp, #imm]
    call emit_d
    pop rdi
    ret

; ---- functions ---------------------------------------------------------------------------------------
a64_prologue:
    A64 0xA9BF7BFD                  ; stp x29, x30, [sp, #-16]!
    A64 0x910003FD                  ; mov x29, sp
    push rax
    mov rax, [code_pos]
    mov [frame_patch], rax
    pop rax
    A64 0xD14003FF                  ; sub sp, sp, #hi, lsl #12   (patched)
    A64 0xD10003FF                  ; sub sp, sp, #lo            (patched)
    ret

a64_epilogue:
    A64 0x910003BF                  ; mov sp, x29
    A64 0xA8C17BFD                  ; ldp x29, x30, [sp], #16
    A64 0xD65F03C0                  ; ret
    ret

; edi = frame size (multiple of 16)
a64_set_frame:
    push rax
    push rcx
    push rdx
    mov rcx, [frame_patch]
    mov eax, edi
    shr eax, 12
    cmp eax, 4096
    jb .ok
    ERR "stack frame of a function is too large"
.ok:
    shl eax, 10
    or eax, 0xD14003FF
    mov [code_buf+rcx], eax
    mov edx, edi
    and edx, 0xFFF
    shl edx, 10
    or edx, 0xD10003FF
    mov [code_buf+rcx+4], edx
    pop rdx
    pop rcx
    pop rax
    ret

; edi = number of main() parameters: argc = [sp], argv = sp + 8 at process start
a64_entry_args:
    push rdi
    A64 0xF94003E0                  ; ldr x0, [sp]
    A64 0x910023E1                  ; add x1, sp, #8
    pop rdi
    cmp edi, 1
    jb .out
    A64 0xF81F0FE0                  ; push x0
    cmp edi, 2
    jb .out
    A64 0xF81F0FE1                  ; push x1
.out:
    ret

; ---- relocations ----------------------------------------------------------------------------------------
; R_DATA / R_BSS: adrp+add pair at the position; R_DATA64: absolute data pointer
apply_relocs_a64:
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
    cmp esi, R_DATA64
    je .d64
    cmp esi, R_CODE
    je .code
    jmp .n
.code:
    shl rdx, 6
    add rdx, symtab
    mov r8, [rdx+SYM_VAL]
    add r8, [code_vaddr]
    jmp .adrp
.data:
    mov r8, [data_vaddr]
    add r8, rdx
    jmp .adrp
.bss:
    mov r8, [bss_vaddr]
    add r8, rdx
.adrp:
    mov r9, [code_vaddr]
    add r9, rdi                     ; pc of the adrp
    mov r10, r8
    shr r10, 12
    mov r11, r9
    shr r11, 12
    sub r10, r11                    ; page delta (signed)
    mov eax, r10d
    and eax, 3
    shl eax, 29
    mov edx, r10d
    sar edx, 2
    and edx, 0x7FFFF
    shl edx, 5
    or eax, edx
    or eax, 0x90000000
    mov [code_buf+rdi], eax
    mov eax, r8d
    and eax, 0xFFF
    shl eax, 10
    or eax, 0x91000000
    mov [code_buf+rdi+4], eax
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
%macro CGT_A64 1
    dq a64_%1
%endmacro
cg_tab_a64:
    CGLIST CGT_A64

; Linux / Android AArch64 runtime (raw syscalls). With a 16 byte stack slot per
; argument and the return address in x30, the last argument is at [sp].
bl_a64_write:
    dd 0xF94003E2                   ; ldr x2, [sp]
    dd 0xF9400BE1                   ; ldr x1, [sp, #16]
    dd 0xF94013E0                   ; ldr x0, [sp, #32]
    dd 0xD2800808                   ; mov x8, #64    (write)
    dd 0xD4000001                   ; svc #0
    dd 0xD65F03C0                   ; ret
bl_a64_write_end:
bl_a64_read:
    dd 0xF94003E2
    dd 0xF9400BE1
    dd 0xF94013E0
    dd 0xD28007E8                   ; mov x8, #63    (read)
    dd 0xD4000001
    dd 0xD65F03C0
bl_a64_read_end:
bl_a64_exit:
    dd 0xF94003E0                   ; ldr x0, [sp]
    dd 0xD2800BC8                   ; mov x8, #94    (exit_group)
    dd 0xD4000001
    dd 0xD65F03C0
bl_a64_exit_end:
bl_a64_syscall:
    dd 0xF94003E5                   ; ldr x5, [sp]
    dd 0xF9400BE4                   ; ldr x4, [sp, #16]
    dd 0xF94013E3                   ; ldr x3, [sp, #32]
    dd 0xF9401BE2                   ; ldr x2, [sp, #48]
    dd 0xF94023E1                   ; ldr x1, [sp, #64]
    dd 0xF9402BE0                   ; ldr x0, [sp, #80]
    dd 0xF94033E8                   ; ldr x8, [sp, #96]
    dd 0xD4000001                   ; svc #0
    dd 0xD65F03C0
bl_a64_syscall_end:
bl_a64_open:
    dd 0xF9400BE1                   ; ldr x1, [sp, #16]   path
    dd 0xF94003E3                   ; ldr x3, [sp]        mode (0 read, 1 write, 2 append)
    dd 0xD2800002                   ; mov x2, #0
    dd 0xF100047F                   ; cmp x3, #1
    dd 0x54000061                   ; b.ne +12
    dd 0xD2804822                   ; mov x2, #0x241      O_WRONLY|O_CREAT|O_TRUNC
    dd 0x14000004                   ; b +16
    dd 0xF100087F                   ; cmp x3, #2
    dd 0x54000041                   ; b.ne +8
    dd 0xD2808822                   ; mov x2, #0x441      O_WRONLY|O_CREAT|O_APPEND
    dd 0x92800C60                   ; mov x0, #-100       AT_FDCWD
    dd 0xD2803483                   ; mov x3, #0644
    dd 0xD2800708                   ; mov x8, #56         openat
    dd 0xD4000001                   ; svc #0
    dd 0xD65F03C0                   ; ret
bl_a64_open_end:
bl_a64_close:
    dd 0xF94003E0                   ; ldr x0, [sp]
    dd 0xD2800728                   ; mov x8, #57         close
    dd 0xD4000001
    dd 0xD65F03C0
bl_a64_close_end:
bl_a64_fail:
    dd 0x92800000                   ; mov x0, #-1
    dd 0xD65F03C0                   ; ret
bl_a64_fail_end:
bl_a64_setjmp:
    dd 0xF94003E0                   ; ldr x0, [sp]
    dd 0xF900001D                   ; str x29, [x0]
    dd 0x910003E1                   ; mov x1, sp
    dd 0xF9000401                   ; str x1, [x0, #8]
    dd 0xF900081E                   ; str x30, [x0, #16]
    dd 0xD2800000                   ; mov x0, #0
    dd 0xD65F03C0                   ; ret
bl_a64_setjmp_end:
bl_a64_longjmp:
    dd 0xF94003E0                   ; ldr x0, [sp]         value
    dd 0xF9400BE1                   ; ldr x1, [sp, #16]    buffer
    dd 0xB5000040                   ; cbnz x0, +8
    dd 0xD2800020                   ; mov x0, #1
    dd 0xF940003D                   ; ldr x29, [x1]
    dd 0xF9400422                   ; ldr x2, [x1, #8]
    dd 0xF940083E                   ; ldr x30, [x1, #16]
    dd 0x9100005F                   ; mov sp, x2
    dd 0xD61F03C0                   ; br x30
bl_a64_longjmp_end:
bl_a64_cmdline:
    dd 0xD2800000                   ; mov x0, #0
    dd 0xD65F03C0
bl_a64_cmdline_end:
section .text
