; =============================================================================
;  cg_la64.asm - LoongArch64 backend (Linux LA64)
;
;  Abstract registers: A = $a0 (r4), B = $a1 (r5), D = $a2 (r6); $t0-$t3 (r12-r15) are scratch for the
;  primitives themselves, $fp (r22) = frame pointer, $ra (r1) = return address.
;  One stack slot = 16 bytes (sp stays 16 byte aligned). Parameter i of n lives at [fp + 16 + 16*(n-1-i)].
;  Jumps and calls are single b / bl instructions (reach +-128 MiB); while a chain of forward jumps is open the
;  26 bit offset field of an instruction holds the position of the previous one. Instruction words were
;  checked against llvm-mc.
; =============================================================================
section .text

; ---- instruction word builders (assembly time) -------------------------------------------------
%define LA_3R(op,rk,rj,rd)       ((op)|((rk)<<10)|((rj)<<5)|(rd))
%define LA_2RI12(op,imm,rj,rd)   ((op)|(((imm)&0xFFF)<<10)|((rj)<<5)|(rd))
%define LA_1RI20(op,imm,rd)      ((op)|(((imm)&0xFFFFF)<<5)|(rd))
%define LA_2RI16(op,off,rj,rd)   ((op)|((((off)>>2)&0xFFFF)<<10)|((rj)<<5)|(rd))
%define LA_I26(op,off)           ((op)|((((off)>>2)&0xFFFF)<<10)|((((off)>>18)&0x3FF)))
%define LA_1RI21(op,off,rj)      ((op)|((((off)>>2)&0xFFFF)<<10)|((rj)<<5)|((((off)>>18)&0x1F)))

%define LA_ADDI_D  0x02C00000
%define LA_SLTUI   0x02400000
%define LA_XORI    0x03C00000
%define LA_ANDI    0x03400000
%define LA_ORI     0x03800000
%define LA_LU52I   0x03000000
%define LA_LD_D    0x28C00000
%define LA_LD_BU   0x2A000000
%define LA_ST_D    0x29C00000
%define LA_ST_B    0x29000000
%define LA_LU12I   0x14000000
%define LA_LU32I   0x16000000
%define LA_PCADDU12I 0x1C000000
%define LA_ADD_D   0x00108000
%define LA_SUB_D   0x00118000
%define LA_MUL_D   0x001D8000
%define LA_DIV_D   0x00220000
%define LA_MOD_D   0x00228000
%define LA_AND     0x00148000
%define LA_OR      0x00150000
%define LA_XOR     0x00158000
%define LA_NOR     0x00140000
%define LA_SLL_D   0x00188000
%define LA_SRA_D   0x00198000
%define LA_SLT     0x00120000
%define LA_SLTU    0x00128000
%define LA_JIRL    0x4C000000
%define LA_B       0x50000000
%define LA_BL      0x54000000
%define LA_BEQ     0x58000000
%define LA_BNE     0x5C000000
%define LA_BLT     0x60000000
%define LA_BGE     0x64000000
%define LA_BEQZ    0x40000000
%define LA_BNEZ    0x44000000
%define LA_SYSCALL 0x002B0000

; registers
%define ZERO 0
%define RA   1
%define SP   3
%define A0   4
%define A1   5
%define A2   6
%define A3   7
%define A4   8
%define A5   9
%define A7   11
%define T0   12
%define T1   13
%define T2   14
%define T3   15
%define FP   22

; emit a literal instruction word
%macro LA 1
    push rdi
    mov edi, %1
    call emit_d
    pop rdi
%endmacro

; ---- helpers ----------------------------------------------------------------------------
; la64_li: edi = register number, rsi = 64 bit value
la64_li:
    push rax
    push rcx
    push rdx
    push rdi
    push rsi
    push r8
    mov r8d, edi                    ; rd
    mov rax, rsi
    mov rdx, rax
    shl rdx, 52
    sar rdx, 52                     ; sign extended low 12 bits
    cmp rdx, rax
    jne .not12
    mov edi, LA_ADDI_D              ; addi.d rd, zero, imm
    and edx, 0xFFF
    shl edx, 10
    or edi, edx
    or edi, r8d
    call emit_d
    jmp .out
.not12:
    ; lu12i.w rd, bits 31..12
    mov edi, LA_LU12I
    mov edx, eax
    shr edx, 12
    and edx, 0xFFFFF
    shl edx, 5
    or edi, edx
    or edi, r8d
    call emit_d
    mov edx, eax
    and edx, 0xFFF
    jz .no_ori
    mov edi, LA_ORI                 ; ori rd, rd, bits 11..0
    shl edx, 10
    or edi, edx
    mov ecx, r8d
    shl ecx, 5
    or edi, ecx
    or edi, r8d
    call emit_d
.no_ori:
    movsxd rdx, eax
    cmp rdx, rax
    je .out                         ; a sign extended 32 bit value is complete
    mov edi, LA_LU32I               ; lu32i.d rd, bits 51..32
    mov rdx, rax
    shr rdx, 32
    and edx, 0xFFFFF
    shl edx, 5
    or edi, edx
    or edi, r8d
    call emit_d
    mov edi, LA_LU52I               ; lu52i.d rd, rd, bits 63..52
    mov rdx, rax
    shr rdx, 52
    and edx, 0xFFF
    shl edx, 10
    or edi, edx
    mov ecx, r8d
    shl ecx, 5
    or edi, ecx
    or edi, r8d
    call emit_d
.out:
    pop r8
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rax
    ret

; la64_addr_local: edi = destination register, esi = signed frame offset. Emits  rd = fp + offset
la64_addr_local:
    push rax
    push rcx
    push rdi
    push rsi
    mov r11d, edi
    movsxd rax, esi
    cmp rax, -2048
    jl .far
    cmp rax, 2047
    jg .far
    mov edi, LA_ADDI_D + (FP << 5)  ; addi.d rd, fp, imm
    and eax, 0xFFF
    shl eax, 10
    or edi, eax
    or edi, r11d
    call emit_d
    jmp .out
.far:
    mov edi, T0
    mov rsi, rax
    call la64_li                    ; t0 = offset
    mov edi, LA_ADD_D + (T0 << 10) + (FP << 5)   ; add.d rd, fp, t0
    or edi, r11d
    call emit_d
.out:
    pop rsi
    pop rdi
    pop rcx
    pop rax
    ret

; ---- stack and register moves ------------------------------------------------------------
la64_push_a:    LA LA_2RI12(LA_ADDI_D, -16, SP, SP)
                LA LA_2RI12(LA_ST_D, 0, SP, A0)
                ret
la64_push_b:    LA LA_2RI12(LA_ADDI_D, -16, SP, SP)
                LA LA_2RI12(LA_ST_D, 0, SP, A1)
                ret
la64_pop_a:     LA LA_2RI12(LA_LD_D, 0, SP, A0)
                LA LA_2RI12(LA_ADDI_D, 16, SP, SP)
                ret
la64_pop_b:     LA LA_2RI12(LA_LD_D, 0, SP, A1)
                LA LA_2RI12(LA_ADDI_D, 16, SP, SP)
                ret
la64_mov_b_a:   LA LA_3R(LA_OR, ZERO, A0, A1)
                ret
la64_mov_a_b:   LA LA_3R(LA_OR, ZERO, A1, A0)
                ret
la64_mov_d_a:   LA LA_3R(LA_OR, ZERO, A0, A2)
                ret
la64_mov_a_d:   LA LA_3R(LA_OR, ZERO, A2, A0)
                ret

; edi = slots
la64_drop:
    push rdi
    push rsi
    test edi, edi
    jz .out
    cmp edi, 255
    jbe .ok
    ERR "too many arguments in a call"
.ok:
    shl edi, 4
    cmp edi, 2047
    ja .big
    shl edi, 10
    or edi, LA_ADDI_D + (SP << 5) + SP   ; addi.d sp, sp, 16*n
    call emit_d
    jmp .out
.big:
    mov esi, edi
    mov edi, T0
    call la64_li
    LA LA_3R(LA_ADD_D, T0, SP, SP)
.out:
    pop rsi
    pop rdi
    ret

la64_imm_a:
    push rdi
    push rsi
    mov rsi, rdi
    mov edi, A0
    call la64_li
    pop rsi
    pop rdi
    ret

la64_imm_b:
    push rdi
    push rsi
    mov rsi, rdi
    mov edi, A1
    call la64_li
    pop rsi
    pop rdi
    ret

; ---- locals and globals -------------------------------------------------------------------
la64_lea_local_a:
    push rdi
    push rsi
    mov esi, edi
    mov edi, A0
    call la64_addr_local
    pop rsi
    pop rdi
    ret

la64_lea_local_b:
    push rdi
    push rsi
    mov esi, edi
    mov edi, A1
    call la64_addr_local
    pop rsi
    pop rdi
    ret

; access a frame offset: edi = offset, r8d = instruction with rj = fp and imm 0, r9d = same with rj = t0
la64_local_access:
    push rdi
    push rsi
    push rax
    movsxd rax, edi
    cmp rax, -2048
    jl .far
    cmp rax, 2047
    jg .far
    and eax, 0xFFF
    shl eax, 10
    or eax, r8d
    mov edi, eax
    call emit_d
    jmp .out
.far:
    mov esi, edi
    mov edi, T0
    call la64_addr_local
    mov edi, r9d
    call emit_d
.out:
    pop rax
    pop rsi
    pop rdi
    ret

%macro LA_LOCAL 4                   ; name, instruction base, register
la64_%1:
    push r8
    push r9
    mov r8d, %2 + (FP << 5) + %3
    mov r9d, %2 + (T0 << 5) + %3
    call la64_local_access
    pop r9
    pop r8
    ret
%endmacro
LA_LOCAL load_local_a,  LA_LD_D,  A0, 0
LA_LOCAL load_local_a1, LA_LD_BU, A0, 0
LA_LOCAL load_local_b,  LA_LD_D,  A1, 0
LA_LOCAL load_local_b1, LA_LD_BU, A1, 0
LA_LOCAL store_local_a, LA_ST_D,  A0, 0
LA_LOCAL store_local_a1, LA_ST_B, A0, 0

; edi = frame offset, esi = size
la64_zero_local:
    push rdi
    push rsi
    push rdx
    mov edx, esi
    mov esi, edi
    mov edi, T0
    call la64_addr_local            ; t0 = &local
    cmp edx, 8
    jne .loop
    LA LA_2RI12(LA_ST_D, 0, T0, ZERO)   ; st.d zero, t0, 0
    jmp .out
.loop:
    mov edi, T1
    mov esi, edx
    call la64_li                    ; t1 = size
    LA LA_2RI12(LA_ST_B, 0, T0, ZERO)   ; st.b zero, t0, 0
    LA LA_2RI12(LA_ADDI_D, 1, T0, T0)
    LA LA_2RI12(LA_ADDI_D, -1, T1, T1)
    LA LA_1RI21(LA_BNEZ, -12, T1)
.out:
    pop rdx
    pop rsi
    pop rdi
    ret

; esi = kind (R_DATA / R_BSS), edx = target
la64_lea_global_a:
    push rdi
    mov edi, [code_pos]
    call add_reloc
    LA LA_1RI20(LA_PCADDU12I, 0, A0)    ; pcaddu12i a0, 0   (patched at link time)
    LA LA_2RI12(LA_ADDI_D, 0, A0, A0)   ; addi.d a0, a0, 0
    pop rdi
    ret

; ---- memory ----------------------------------------------------------------------------------
la64_load8_a:   LA LA_2RI12(LA_LD_D, 0, A0, A0)
                ret
la64_load1_a:   LA LA_2RI12(LA_LD_BU, 0, A0, A0)
                ret
la64_store8:    LA LA_2RI12(LA_ST_D, 0, A1, A0)       ; st.d a0, a1, 0
                ret
la64_store1:    LA LA_2RI12(LA_ST_B, 0, A1, A0)
                ret

; edi = size: copy A -> B, result A = B
la64_copy_mem:
    push rdi
    push rsi
    mov esi, edi
    LA LA_3R(LA_OR, ZERO, A0, T0)       ; move t0, a0   (source)
    LA LA_3R(LA_OR, ZERO, A1, T1)       ; move t1, a1   (destination)
    LA LA_3R(LA_OR, ZERO, A1, A0)       ; move a0, a1
    mov edi, T2
    call la64_li                        ; t2 = size
    LA LA_2RI12(LA_LD_BU, 0, T0, T3)    ; ld.bu t3, t0, 0
    LA LA_2RI12(LA_ST_B, 0, T1, T3)     ; st.b t3, t1, 0
    LA LA_2RI12(LA_ADDI_D, 1, T0, T0)
    LA LA_2RI12(LA_ADDI_D, 1, T1, T1)
    LA LA_2RI12(LA_ADDI_D, -1, T2, T2)
    LA LA_1RI21(LA_BNEZ, -20, T2)
    pop rsi
    pop rdi
    ret

; ---- arithmetic ----------------------------------------------------------------------------------
; edi = signed 32 bit immediate
la64_add_imm_a:
    push rdi
    push rsi
    movsxd rax, edi
    cmp rax, -2048
    jl .big
    cmp rax, 2047
    jg .big
    and eax, 0xFFF
    shl eax, 10
    or eax, LA_ADDI_D + (A0 << 5) + A0
    mov edi, eax
    call emit_d
    jmp .out
.big:
    mov rsi, rax
    mov edi, T0
    call la64_li
    LA LA_3R(LA_ADD_D, T0, A0, A0)
.out:
    pop rsi
    pop rdi
    ret

la64_mul_imm_a:
    push rdi
    push rsi
    mov edi, edi
    mov rsi, rdi
    mov edi, T0
    call la64_li
    LA LA_3R(LA_MUL_D, T0, A0, A0)
    pop rsi
    pop rdi
    ret

la64_mul_imm_b:
    push rdi
    push rsi
    mov edi, edi
    mov rsi, rdi
    mov edi, T0
    call la64_li
    LA LA_3R(LA_MUL_D, T0, A1, A1)
    pop rsi
    pop rdi
    ret

la64_add:       LA LA_3R(LA_ADD_D, A1, A0, A0)
                ret
la64_sub:       LA LA_3R(LA_SUB_D, A1, A0, A0)
                ret
la64_mul:       LA LA_3R(LA_MUL_D, A1, A0, A0)
                ret
la64_div:       LA LA_3R(LA_DIV_D, A1, A0, A0)
                ret
la64_mod:       LA LA_3R(LA_MOD_D, A1, A0, A0)
                ret
la64_and:       LA LA_3R(LA_AND, A1, A0, A0)
                ret
la64_or:        LA LA_3R(LA_OR, A1, A0, A0)
                ret
la64_xor:       LA LA_3R(LA_XOR, A1, A0, A0)
                ret
la64_shl:       LA LA_3R(LA_SLL_D, A1, A0, A0)
                ret
la64_sar:       LA LA_3R(LA_SRA_D, A1, A0, A0)
                ret

la64_cmp_eq:    LA LA_3R(LA_SUB_D, A1, A0, A0)
                LA LA_2RI12(LA_SLTUI, 1, A0, A0)
                ret
la64_cmp_ne:    LA LA_3R(LA_SUB_D, A1, A0, A0)
                LA LA_3R(LA_SLTU, A0, ZERO, A0)       ; sltu a0, zero, a0
                ret
la64_cmp_lt:    LA LA_3R(LA_SLT, A1, A0, A0)          ; slt a0, a0, a1
                ret
la64_cmp_gt:    LA LA_3R(LA_SLT, A0, A1, A0)          ; slt a0, a1, a0
                ret
la64_cmp_le:    LA LA_3R(LA_SLT, A0, A1, A0)
                LA LA_2RI12(LA_XORI, 1, A0, A0)
                ret
la64_cmp_ge:    LA LA_3R(LA_SLT, A1, A0, A0)
                LA LA_2RI12(LA_XORI, 1, A0, A0)
                ret

la64_neg:       LA LA_3R(LA_SUB_D, A0, ZERO, A0)
                ret
la64_not:       LA LA_3R(LA_NOR, ZERO, A0, A0)
                ret
la64_lnot:      LA LA_2RI12(LA_SLTUI, 1, A0, A0)
                ret
la64_zext8:     LA LA_2RI12(LA_ANDI, 255, A0, A0)
                ret
la64_tobool:    LA LA_3R(LA_SLTU, A0, ZERO, A0)
                ret

; ---- jumps ---------------------------------------------------------------------------------------
; the 26 bit field of b / bl: low 16 bits of the word offset at bit 10, the high 10 bits at bit 0
; la64_chain_slot: rdi = &head. Emits a 'b' whose offset field holds the previous chain head (as a word offset)
la64_chain_slot:
    push rax
    push rdx
    push rdi
    push rcx
    mov rdx, rdi
    mov rax, [code_pos]
    mov ecx, [rdx]                  ; previous head
    shr ecx, 2
    mov edi, ecx
    and edi, 0xFFFF
    shl edi, 10
    shr ecx, 16
    and ecx, 0x3FF
    or edi, ecx
    or edi, LA_B
    call emit_d
    mov [rdx], rax
    pop rcx
    pop rdi
    pop rdx
    pop rax
    ret

la64_jz_chain:
    LA LA_1RI21(LA_BNEZ, 8, A0)     ; bnez a0, +8
    jmp la64_chain_slot
la64_jnz_chain:
    LA LA_1RI21(LA_BEQZ, 8, A0)     ; beqz a0, +8
    jmp la64_chain_slot
la64_jmp_chain:
    jmp la64_chain_slot

; edi = condition code CC_*, rsi = &chain head: cmp A,B; jump to the chain if A cc B holds
la64_jcmp_chain:
    push rax
    push rdi
    push rsi
    mov eax, edi
    mov edi, [la64_inv_branch + rax*4]
    call emit_d
    mov rdi, rsi
    call la64_chain_slot
    pop rsi
    pop rdi
    pop rax
    ret
section .rodata
; inverse branches (offset +8) for eq ne lt gt le ge:  bne  beq  bge(a0,a1)  bge(a1,a0)  blt(a1,a0)  blt(a0,a1)
la64_inv_branch:
    dd LA_2RI16(LA_BNE, 8, A0, A1)
    dd LA_2RI16(LA_BEQ, 8, A0, A1)
    dd LA_2RI16(LA_BGE, 8, A0, A1)
    dd LA_2RI16(LA_BGE, 8, A1, A0)
    dd LA_2RI16(LA_BLT, 8, A1, A0)
    dd LA_2RI16(LA_BLT, 8, A0, A1)
section .text

; rdi = target position
la64_jmp_back:
    push rdi
    push rax
    push rcx
    mov rax, rdi
    sub rax, [code_pos]
    sar rax, 2
    mov edi, eax
    and edi, 0xFFFF
    shl edi, 10
    mov ecx, eax
    shr ecx, 16
    and ecx, 0x3FF
    or edi, ecx
    or edi, LA_B
    call emit_d
    pop rcx
    pop rax
    pop rdi
    ret

la64_jnz_back:
    LA LA_1RI21(LA_BEQZ, 8, A0)     ; beqz a0, +8
    jmp la64_jmp_back

; edi = frame offset, rsi = value, rdx = target position
la64_case_jump:
    push rdi
    push rsi
    push rdx
    push rax
    call la64_load_local_a
    mov edi, T1
    call la64_li                    ; t1 = value (rsi)
    LA LA_2RI16(LA_BNE, 8, A0, T1)  ; bne a0, t1, +8
    mov rdi, rdx
    call la64_jmp_back
    pop rax
    pop rdx
    pop rsi
    pop rdi
    ret

; rdi = chain head, rsi = target position
la64_patch_chain:
    push rax
    push rcx
    push rdx
    push rdi
    push r8
.l: test rdi, rdi
    jz .d
    mov eax, [code_buf+rdi]
    mov edx, eax
    and edx, 0x3FF                  ; high 10 bits of the stored link
    shl edx, 16
    mov ecx, eax
    shr ecx, 10
    and ecx, 0xFFFF
    or edx, ecx
    shl edx, 2                      ; the next chain position
    mov r8d, edx
    mov rcx, rsi
    sub rcx, rdi
    sar rcx, 2                      ; word offset
    and eax, 0xFC000000
    mov edx, ecx
    and edx, 0xFFFF
    shl edx, 10
    or eax, edx
    shr ecx, 16
    and ecx, 0x3FF
    or eax, ecx
    mov [code_buf+rdi], eax
    mov edi, r8d
    jmp .l
.d: pop r8
    pop rdi
    pop rdx
    pop rcx
    pop rax
    ret

; rdi = function symbol
la64_call_sym:
    push rax
    push rcx
    push rdx
    push rdi
    mov rax, [rdi+SYM_VAL]
    cmp rax, -1
    je .fwd
    sub rax, [code_pos]
    sar rax, 2
    mov edi, eax
    and edi, 0xFFFF
    shl edi, 10
    mov ecx, eax
    shr ecx, 16
    and ecx, 0x3FF
    or edi, ecx
    or edi, LA_BL
    call emit_d
    jmp .out
.fwd:
    mov eax, [rdi+SYM_PATCH]
    mov rdx, [code_pos]
    mov [rdi+SYM_PATCH], edx
    shr eax, 2
    mov edi, eax
    and edi, 0xFFFF
    shl edi, 10
    shr eax, 16
    and eax, 0x3FF
    or edi, eax
    or edi, LA_BL
    call emit_d
.out:
    pop rdi
    pop rdx
    pop rcx
    pop rax
    ret

; rdi = function symbol -> A = its address (pcaddu12i + addi.d, resolved when the layout is known: R_CODE)
la64_lea_func_a:
    push rdi
    push rsi
    push rdx
    sub rdi, symtab
    shr rdi, 6
    mov edx, edi
    mov edi, [code_pos]
    mov esi, R_CODE
    call add_reloc
    LA LA_1RI20(LA_PCADDU12I, 0, A0)
    LA LA_2RI12(LA_ADDI_D, 0, A0, A0)
    pop rdx
    pop rsi
    pop rdi
    ret

la64_call_a:
    LA LA_2RI16(LA_JIRL, 0, A0, RA)         ; jirl ra, a0, 0
    ret

; edi = n: a0 = [sp + 16*n]
la64_load_stack_a:
    push rdi
    shl edi, 4
    cmp edi, 2047
    jbe .ok
    ERR "too many arguments in a call"
.ok:
    shl edi, 10
    or edi, LA_LD_D + (SP << 5) + A0
    call emit_d
    pop rdi
    ret

; ---- functions ---------------------------------------------------------------------------------------
la64_prologue:
    LA LA_2RI12(LA_ADDI_D, -16, SP, SP)
    LA LA_2RI12(LA_ST_D, 0, SP, FP)         ; st.d fp, sp, 0
    LA LA_2RI12(LA_ST_D, 8, SP, RA)         ; st.d ra, sp, 8
    LA LA_2RI12(LA_ADDI_D, 0, SP, FP)       ; addi.d fp, sp, 0
    push rax
    mov rax, [code_pos]
    mov [frame_patch], rax
    pop rax
    LA LA_1RI20(LA_LU12I, 0, T0)            ; lu12i.w t0, hi        (patched)
    LA LA_2RI12(LA_ORI, 0, T0, T0)          ; ori t0, t0, lo        (patched)
    LA LA_3R(LA_SUB_D, T0, SP, SP)          ; sub.d sp, sp, t0
    ret

la64_epilogue:
    LA LA_2RI12(LA_ADDI_D, 0, FP, SP)       ; addi.d sp, fp, 0
    LA LA_2RI12(LA_LD_D, 8, SP, RA)         ; ld.d ra, sp, 8
    LA LA_2RI12(LA_LD_D, 0, SP, FP)         ; ld.d fp, sp, 0
    LA LA_2RI12(LA_ADDI_D, 16, SP, SP)
    LA LA_2RI16(LA_JIRL, 0, RA, ZERO)       ; ret
    ret

; edi = frame size (multiple of 16)
la64_set_frame:
    push rax
    push rcx
    push rdx
    mov rcx, [frame_patch]
    mov eax, edi
    shr eax, 12
    and eax, 0xFFFFF
    shl eax, 5
    or eax, LA_LU12I + T0
    mov [code_buf+rcx], eax
    mov edx, edi
    and edx, 0xFFF
    shl edx, 10
    or edx, LA_ORI + (T0 << 5) + T0
    mov [code_buf+rcx+4], edx
    pop rdx
    pop rcx
    pop rax
    ret

; edi = number of main() parameters: argc = [sp], argv = sp + 8 at process start
la64_entry_args:
    push rdi
    LA LA_2RI12(LA_LD_D, 0, SP, A0)         ; ld.d a0, sp, 0
    LA LA_2RI12(LA_ADDI_D, 8, SP, A1)       ; addi.d a1, sp, 8
    pop rdi
    cmp edi, 1
    jb .out
    LA LA_2RI12(LA_ADDI_D, -16, SP, SP)
    LA LA_2RI12(LA_ST_D, 0, SP, A0)
    cmp edi, 2
    jb .out
    LA LA_2RI12(LA_ADDI_D, -16, SP, SP)
    LA LA_2RI12(LA_ST_D, 0, SP, A1)
.out:
    ret

; ---- relocations ----------------------------------------------------------------------------------------
; R_DATA / R_BSS / R_CODE: pcaddu12i + addi.d pair (pc relative); R_DATA64 / R_CODE64: absolute pointer in the data section
apply_relocs_la64:
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
    cmp esi, R_CODE64
    je .c64
    jmp .n
.c64:
    shl rdx, 6
    add rdx, symtab
    mov r8, [rdx+SYM_VAL]
    add r8, [code_vaddr]
    add [data_buf+rdi], r8
    jmp .n
.code:
    shl rdx, 6
    add rdx, symtab
    mov r8, [rdx+SYM_VAL]
    add r8, [code_vaddr]
    jmp .pcrel
.data:
    mov r8, [data_vaddr]
    add r8, rdx
    jmp .pcrel
.bss:
    mov r8, [bss_vaddr]
    add r8, rdx
.pcrel:
    mov r9, [code_vaddr]
    add r9, rdi                     ; pc of the pcaddu12i
    mov rax, r8
    sub rax, r9
    lea r10, [rax + 0x800]
    sar r10, 12
    and r10d, 0xFFFFF
    shl r10d, 5
    or r10d, LA_PCADDU12I + A0
    mov [code_buf+rdi], r10d
    and eax, 0xFFF
    shl eax, 10
    or eax, LA_ADDI_D + (A0 << 5) + A0
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
%macro CGT_LA64 1
    dq la64_%1
%endmacro
cg_tab_la64:
    CGLIST CGT_LA64

; Linux LoongArch64 runtime (raw syscalls, the generic Linux system call numbers). With a 16 byte stack slot per
; argument and the return address in $ra, the last argument is at [sp].
%define LA_RET LA_2RI16(LA_JIRL, 0, RA, ZERO)
%define LA_LI12(r,v) LA_2RI12(LA_ADDI_D, v, ZERO, r)
bl_la64_write:
    dd LA_2RI12(LA_LD_D, 0, SP, A2)         ; ld.d a2, sp, 0
    dd LA_2RI12(LA_LD_D, 16, SP, A1)
    dd LA_2RI12(LA_LD_D, 32, SP, A0)
    dd LA_LI12(A7, 64)                      ; li a7, 64   (write)
    dd LA_SYSCALL
    dd LA_RET
bl_la64_write_end:
bl_la64_read:
    dd LA_2RI12(LA_LD_D, 0, SP, A2)
    dd LA_2RI12(LA_LD_D, 16, SP, A1)
    dd LA_2RI12(LA_LD_D, 32, SP, A0)
    dd LA_LI12(A7, 63)                      ; li a7, 63   (read)
    dd LA_SYSCALL
    dd LA_RET
bl_la64_read_end:
bl_la64_exit:
    dd LA_2RI12(LA_LD_D, 0, SP, A0)
    dd LA_LI12(A7, 94)                      ; li a7, 94   (exit_group)
    dd LA_SYSCALL
    dd LA_RET
bl_la64_exit_end:
bl_la64_syscall:
    dd LA_2RI12(LA_LD_D, 0, SP, A5)
    dd LA_2RI12(LA_LD_D, 16, SP, A4)
    dd LA_2RI12(LA_LD_D, 32, SP, A3)
    dd LA_2RI12(LA_LD_D, 48, SP, A2)
    dd LA_2RI12(LA_LD_D, 64, SP, A1)
    dd LA_2RI12(LA_LD_D, 80, SP, A0)
    dd LA_2RI12(LA_LD_D, 96, SP, A7)
    dd LA_SYSCALL
    dd LA_RET
bl_la64_syscall_end:
bl_la64_open:
    dd LA_2RI12(LA_LD_D, 16, SP, A1)        ; ld.d a1, sp, 16     path
    dd LA_2RI12(LA_LD_D, 0, SP, T0)         ; ld.d t0, sp, 0      mode (0 read, 1 write, 2 append)
    dd LA_LI12(A2, 0)                       ; li a2, 0
    dd LA_LI12(T1, 1)                       ; li t1, 1
    dd LA_2RI16(LA_BEQ, 16, T0, T1)         ; beq t0, t1, write
    dd LA_LI12(T1, 2)                       ; li t1, 2
    dd LA_2RI16(LA_BEQ, 16, T0, T1)         ; beq t0, t1, append
    dd LA_I26(LA_B, 16)                     ; b openat
    dd LA_LI12(A2, 0x241)                   ; write:  li a2, 0x241
    dd LA_I26(LA_B, 8)                      ; b openat
    dd LA_LI12(A2, 0x441)                   ; append: li a2, 0x441
    dd LA_LI12(A0, -100)                    ; openat: li a0, -100  (AT_FDCWD)
    dd LA_LI12(A3, 0x1A4)                   ; li a3, 0644
    dd LA_LI12(A7, 56)                      ; li a7, 56   (openat)
    dd LA_SYSCALL
    dd LA_RET
bl_la64_open_end:
bl_la64_close:
    dd LA_2RI12(LA_LD_D, 0, SP, A0)
    dd LA_LI12(A7, 57)                      ; li a7, 57   (close)
    dd LA_SYSCALL
    dd LA_RET
bl_la64_close_end:
bl_la64_fail:
    dd LA_LI12(A0, -1)
    dd LA_RET
bl_la64_fail_end:
bl_la64_setjmp:
    dd LA_2RI12(LA_LD_D, 0, SP, A0)         ; ld.d a0, sp, 0
    dd LA_2RI12(LA_ST_D, 0, A0, FP)         ; st.d fp, a0, 0
    dd LA_2RI12(LA_ST_D, 8, A0, SP)         ; st.d sp, a0, 8
    dd LA_2RI12(LA_ST_D, 16, A0, RA)        ; st.d ra, a0, 16
    dd LA_LI12(A0, 0)
    dd LA_RET
bl_la64_setjmp_end:
bl_la64_longjmp:
    dd LA_2RI12(LA_LD_D, 0, SP, A0)         ; value
    dd LA_2RI12(LA_LD_D, 16, SP, A1)        ; buffer
    dd LA_1RI21(LA_BNEZ, 8, A0)             ; bnez a0, +8
    dd LA_LI12(A0, 1)
    dd LA_2RI12(LA_LD_D, 0, A1, FP)         ; ld.d fp, a1, 0
    dd LA_2RI12(LA_LD_D, 8, A1, A2)         ; ld.d a2, a1, 8
    dd LA_2RI12(LA_LD_D, 16, A1, RA)        ; ld.d ra, a1, 16
    dd LA_3R(LA_OR, ZERO, A2, SP)           ; move sp, a2
    dd LA_RET
bl_la64_longjmp_end:
bl_la64_cmdline:
    dd LA_LI12(A0, 0)
    dd LA_RET
bl_la64_cmdline_end:
section .text
