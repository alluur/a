; =============================================================================
;  cg_rv64.asm - RISC-V 64 backend (Linux RV64GC, Android RISC-V)
;
;  Abstract registers: A = a0 (x10), B = a1 (x11), D = a2 (x12); t0-t3 (x5-x7, x28) are scratch for the
;  primitives themselves, s0 (x8) = frame pointer, ra (x1) = return address.
;  One stack slot = 16 bytes (sp stays 16 byte aligned); a "push" is  addi sp,sp,-16 ; sd a0,0(sp).
;  Parameter i of n lives at [s0 + 16 + 16*(n-1-i)] (like the AArch64 backend).
;  Every jump and call is an  auipc + jalr  pair (reach +-2 GiB); while a chain of forward jumps is open the
;  second word of a pair holds the position of the previous one. Instruction words were checked against llvm-mc.
; =============================================================================
section .text

; ---- instruction word builders (assembly time) -------------------------------------------------
%define RV_R(f7,rs2,rs1,f3,rd,op) (((f7)<<25)|((rs2)<<20)|((rs1)<<15)|((f3)<<12)|((rd)<<7)|(op))
%define RV_I(imm,rs1,f3,rd,op)    ((((imm)&0xFFF)<<20)|((rs1)<<15)|((f3)<<12)|((rd)<<7)|(op))
%define RV_S(imm,rs2,rs1,f3,op)   (((((imm)>>5)&0x7F)<<25)|((rs2)<<20)|((rs1)<<15)|((f3)<<12)|(((imm)&0x1F)<<7)|(op))
%define RV_B(imm,rs2,rs1,f3)      (((((imm)>>12)&1)<<31)|((((imm)>>5)&0x3F)<<25)|((rs2)<<20)|((rs1)<<15)|((f3)<<12)|((((imm)>>1)&0xF)<<8)|((((imm)>>11)&1)<<7)|0x63)
%define RV_U(imm20,rd,op)         ((((imm20)&0xFFFFF)<<12)|((rd)<<7)|(op))

; registers
%define X0  0
%define RA  1
%define SP  2
%define T0  5
%define T1  6
%define T2  7
%define S0  8
%define A0  10
%define A1  11
%define A2  12
%define A5  15
%define A7  17
%define T3  28
%define A3_REG 13
%define RV_J_PLUS(o) ((((o)>>20)&1)<<31)|((((o)>>1)&0x3FF)<<21)|((((o)>>11)&1)<<20)|((((o)>>12)&0xFF)<<12)|0x6F

; emit a literal instruction word
%macro RV 1
    push rdi
    mov edi, %1
    call emit_d
    pop rdi
%endmacro

; ---- helpers ----------------------------------------------------------------------------
; rv64_li: edi = register number, rsi = 64 bit value. Emits the shortest sequence of addi / lui / slli.
rv64_li:
    push rax
    push rcx
    push rdx
    push rdi
    push rsi
    push r8
    push r9
    mov r8d, edi                    ; rd
    mov rax, rsi
    ; fits 12 bits signed?
    movsx rcx, ax
    mov rdx, rax
    shl rdx, 52
    sar rdx, 52                     ; sign extended low 12 bits
    cmp rdx, rax
    jne .not12
    mov edi, RV_I(0, 0, 0, 0, 0x13) ; addi rd, x0, imm
    mov ecx, r8d
    shl ecx, 7
    or edi, ecx
    and edx, 0xFFF
    shl edx, 20
    or edi, edx
    call emit_d
    jmp .out
.not12:
    movsxd rdx, eax
    cmp rdx, rax
    jne .wide
    ; 32 bit: lui + addiw
    mov r9d, eax
    add r9d, 0x800
    shr r9d, 12                     ; hi20
    mov edi, RV_U(0, 0, 0x37)
    mov ecx, r9d
    and ecx, 0xFFFFF
    shl ecx, 12
    or edi, ecx
    mov ecx, r8d
    shl ecx, 7
    or edi, ecx
    call emit_d
    mov edx, eax
    shl edx, 20                     ; low 12 bits at the right place for the immediate
    and edx, 0xFFF00000
    test edx, edx
    jz .out                         ; lo12 == 0: lui alone is enough
    mov edi, RV_I(0, 0, 0, 0, 0x1B) ; addiw rd, rd, lo12
    mov ecx, r8d
    shl ecx, 7
    or edi, ecx
    shl ecx, 8
    or edi, ecx                     ; rs1 = rd
    or edi, edx
    call emit_d
    jmp .out
.wide:
    ; high 32 bits sign extended, then three shifts of 11 + 11 + 10 bits each followed by addi of the chunk
    mov rsi, rax
    sar rsi, 32
    mov edi, r8d
    push rax
    call rv64_li
    pop rax
    mov r9, rax
    mov ecx, 11
    mov edx, 21
    call .shift_add
    mov ecx, 11
    mov edx, 10
    call .shift_add
    mov ecx, 10
    xor edx, edx
    call .shift_add
    jmp .out
; slli rd,rd,ecx ; addi rd,rd,(r9 >> edx) & ((1<<ecx)-1)
.shift_add:
    mov edi, RV_I(0, 0, 1, 0, 0x13)    ; slli rd, rd, shamt
    mov r10d, r8d
    shl r10d, 7
    or edi, r10d
    shl r10d, 8
    or edi, r10d
    mov r10d, ecx
    shl r10d, 20
    or edi, r10d
    call emit_d
    mov rax, r9
    xchg ecx, edx
    shr rax, cl
    xchg ecx, edx
    mov r10d, 1
    shl r10d, cl
    dec r10d
    and eax, r10d
    jz .sa_done
    mov edi, RV_I(0, 0, 0, 0, 0x13)    ; addi rd, rd, chunk
    mov r10d, r8d
    shl r10d, 7
    or edi, r10d
    shl r10d, 8
    or edi, r10d
    shl eax, 20
    or edi, eax
    call emit_d
.sa_done:
    ret
.out:
    pop r9
    pop r8
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rax
    ret

; rv64_addr_local: edi = destination register, esi = signed frame offset. Emits  rd = s0 + offset
rv64_addr_local:
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
    mov edi, RV_I(0, S0, 0, 0, 0x13)   ; addi rd, s0, imm
    and eax, 0xFFF
    shl eax, 20
    or edi, eax
    mov ecx, r11d
    shl ecx, 7
    or edi, ecx
    call emit_d
    jmp .out
.far:
    mov edi, T0
    mov rsi, rax
    call rv64_li                       ; t0 = offset
    mov edi, RV_R(0, T0, S0, 0, 0, 0x33) ; add rd, s0, t0
    mov ecx, r11d
    shl ecx, 7
    or edi, ecx
    call emit_d
.out:
    pop rsi
    pop rdi
    pop rcx
    pop rax
    ret

; ---- stack and register moves ------------------------------------------------------------
rv64_push_a:    RV RV_I(-16, SP, 0, SP, 0x13)          ; addi sp, sp, -16
                RV RV_S(0, A0, SP, 3, 0x23)            ; sd a0, 0(sp)
                ret
rv64_push_b:    RV RV_I(-16, SP, 0, SP, 0x13)
                RV RV_S(0, A1, SP, 3, 0x23)            ; sd a1, 0(sp)
                ret
rv64_pop_a:     RV RV_I(0, SP, 3, A0, 0x03)            ; ld a0, 0(sp)
                RV RV_I(16, SP, 0, SP, 0x13)           ; addi sp, sp, 16
                ret
rv64_pop_b:     RV RV_I(0, SP, 3, A1, 0x03)
                RV RV_I(16, SP, 0, SP, 0x13)
                ret
rv64_mov_b_a:   RV RV_I(0, A0, 0, A1, 0x13)            ; addi a1, a0, 0
                ret
rv64_mov_a_b:   RV RV_I(0, A1, 0, A0, 0x13)
                ret
rv64_mov_d_a:   RV RV_I(0, A0, 0, A2, 0x13)
                ret
rv64_mov_a_d:   RV RV_I(0, A2, 0, A0, 0x13)
                ret

; edi = slots
rv64_drop:
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
    shl edi, 20
    or edi, RV_I(0, SP, 0, SP, 0x13)   ; addi sp, sp, 16*n
    call emit_d
    jmp .out
.big:
    mov esi, edi
    mov edi, T0
    call rv64_li
    RV RV_R(0, T0, SP, 0, SP, 0x33)    ; add sp, sp, t0
.out:
    pop rsi
    pop rdi
    ret

rv64_imm_a:
    push rdi
    push rsi
    mov rsi, rdi
    mov edi, A0
    call rv64_li
    pop rsi
    pop rdi
    ret

rv64_imm_b:
    push rdi
    push rsi
    mov rsi, rdi
    mov edi, A1
    call rv64_li
    pop rsi
    pop rdi
    ret

; ---- locals and globals -------------------------------------------------------------------
rv64_lea_local_a:
    push rdi
    push rsi
    mov esi, edi
    mov edi, A0
    call rv64_addr_local
    pop rsi
    pop rdi
    ret

rv64_lea_local_b:
    push rdi
    push rsi
    mov esi, edi
    mov edi, A1
    call rv64_addr_local
    pop rsi
    pop rdi
    ret

; load from a frame offset: edi = offset, r8d = load word with rs1 = s0 and imm 0, r9d = the same with rs1 = t0
rv64_local_load:
    push rdi
    push rsi
    push rax
    movsxd rax, edi
    cmp rax, -2048
    jl .far
    cmp rax, 2047
    jg .far
    and eax, 0xFFF
    shl eax, 20
    or eax, r8d
    mov edi, eax
    call emit_d
    jmp .out
.far:
    mov esi, edi
    mov edi, T0
    call rv64_addr_local
    mov edi, r9d
    call emit_d
.out:
    pop rax
    pop rsi
    pop rdi
    ret

; store to a frame offset: edi = offset, r8d = store word with rs1 = s0 and imm 0, r9d = same with rs1 = t0
rv64_local_store:
    push rdi
    push rsi
    push rax
    push rcx
    movsxd rax, edi
    cmp rax, -2048
    jl .far
    cmp rax, 2047
    jg .far
    mov ecx, eax
    and ecx, 0x1F
    shl ecx, 7
    shr eax, 5
    and eax, 0x7F
    shl eax, 25
    or eax, ecx
    or eax, r8d
    mov edi, eax
    call emit_d
    jmp .out
.far:
    mov esi, edi
    mov edi, T0
    call rv64_addr_local
    mov edi, r9d
    call emit_d
.out:
    pop rcx
    pop rax
    pop rsi
    pop rdi
    ret

rv64_load_local_a:
    push r8
    push r9
    mov r8d, RV_I(0, S0, 3, A0, 0x03)      ; ld a0, 0(s0)
    mov r9d, RV_I(0, T0, 3, A0, 0x03)
    call rv64_local_load
    pop r9
    pop r8
    ret
rv64_load_local_a1:
    push r8
    push r9
    mov r8d, RV_I(0, S0, 4, A0, 0x03)      ; lbu a0, 0(s0)
    mov r9d, RV_I(0, T0, 4, A0, 0x03)
    call rv64_local_load
    pop r9
    pop r8
    ret
rv64_load_local_b:
    push r8
    push r9
    mov r8d, RV_I(0, S0, 3, A1, 0x03)
    mov r9d, RV_I(0, T0, 3, A1, 0x03)
    call rv64_local_load
    pop r9
    pop r8
    ret
rv64_load_local_b1:
    push r8
    push r9
    mov r8d, RV_I(0, S0, 4, A1, 0x03)
    mov r9d, RV_I(0, T0, 4, A1, 0x03)
    call rv64_local_load
    pop r9
    pop r8
    ret
rv64_store_local_a:
    push r8
    push r9
    mov r8d, RV_S(0, A0, S0, 3, 0x23)      ; sd a0, 0(s0)
    mov r9d, RV_S(0, A0, T0, 3, 0x23)
    call rv64_local_store
    pop r9
    pop r8
    ret
rv64_store_local_a1:
    push r8
    push r9
    mov r8d, RV_S(0, A0, S0, 0, 0x23)      ; sb a0, 0(s0)
    mov r9d, RV_S(0, A0, T0, 0, 0x23)
    call rv64_local_store
    pop r9
    pop r8
    ret

; edi = frame offset, esi = size
rv64_zero_local:
    push rdi
    push rsi
    push rdx
    mov edx, esi
    mov esi, edi
    mov edi, T0
    call rv64_addr_local            ; t0 = &local
    cmp edx, 8
    jne .loop
    RV RV_S(0, X0, T0, 3, 0x23)     ; sd x0, 0(t0)
    jmp .out
.loop:
    mov edi, T1
    mov esi, edx
    call rv64_li                    ; t1 = size
    RV RV_S(0, X0, T0, 0, 0x23)     ; sb x0, 0(t0)
    RV RV_I(1, T0, 0, T0, 0x13)     ; addi t0, t0, 1
    RV RV_I(-1, T1, 0, T1, 0x13)    ; addi t1, t1, -1
    RV RV_B(-12, X0, T1, 1)         ; bne t1, x0, -12
.out:
    pop rdx
    pop rsi
    pop rdi
    ret

; esi = kind (R_DATA / R_BSS), edx = target
rv64_lea_global_a:
    push rdi
    mov edi, [code_pos]
    call add_reloc
    RV RV_U(0, A0, 0x17)            ; auipc a0, 0   (patched at link time)
    RV RV_I(0, A0, 0, A0, 0x13)     ; addi a0, a0, 0
    pop rdi
    ret

; ---- memory ----------------------------------------------------------------------------------
rv64_load8_a:   RV RV_I(0, A0, 3, A0, 0x03)            ; ld a0, 0(a0)
                ret
rv64_load1_a:   RV RV_I(0, A0, 4, A0, 0x03)            ; lbu a0, 0(a0)
                ret
rv64_store8:    RV RV_S(0, A0, A1, 3, 0x23)            ; sd a0, 0(a1)
                ret
rv64_store1:    RV RV_S(0, A0, A1, 0, 0x23)            ; sb a0, 0(a1)
                ret

; edi = size: copy A -> B, result A = B
rv64_copy_mem:
    push rdi
    push rsi
    mov esi, edi
    RV RV_I(0, A0, 0, T0, 0x13)     ; mv t0, a0   (source)
    RV RV_I(0, A1, 0, T1, 0x13)     ; mv t1, a1   (destination)
    RV RV_I(0, A1, 0, A0, 0x13)     ; mv a0, a1
    mov edi, T2
    call rv64_li                    ; t2 = size
    RV RV_I(0, T0, 4, T3, 0x03)     ; lbu t3, 0(t0)
    RV RV_S(0, T3, T1, 0, 0x23)     ; sb t3, 0(t1)
    RV RV_I(1, T0, 0, T0, 0x13)     ; addi t0, t0, 1
    RV RV_I(1, T1, 0, T1, 0x13)     ; addi t1, t1, 1
    RV RV_I(-1, T2, 0, T2, 0x13)    ; addi t2, t2, -1
    RV RV_B(-20, X0, T2, 1)         ; bne t2, x0, -20
    pop rsi
    pop rdi
    ret

; ---- arithmetic ----------------------------------------------------------------------------------
; edi = signed 32 bit immediate
rv64_add_imm_a:
    push rdi
    push rsi
    movsxd rax, edi
    cmp rax, -2048
    jl .big
    cmp rax, 2047
    jg .big
    and eax, 0xFFF
    shl eax, 20
    or eax, RV_I(0, A0, 0, A0, 0x13)   ; addi a0, a0, imm
    mov edi, eax
    call emit_d
    jmp .out
.big:
    mov rsi, rax
    mov edi, T0
    call rv64_li
    RV RV_R(0, T0, A0, 0, A0, 0x33)    ; add a0, a0, t0
.out:
    pop rsi
    pop rdi
    ret

rv64_mul_imm_a:
    push rdi
    push rsi
    mov edi, edi
    mov rsi, rdi
    mov edi, T0
    call rv64_li
    RV RV_R(1, T0, A0, 0, A0, 0x33)    ; mul a0, a0, t0
    pop rsi
    pop rdi
    ret

rv64_mul_imm_b:
    push rdi
    push rsi
    mov edi, edi
    mov rsi, rdi
    mov edi, T0
    call rv64_li
    RV RV_R(1, T0, A1, 0, A1, 0x33)    ; mul a1, a1, t0
    pop rsi
    pop rdi
    ret

rv64_add:       RV RV_R(0, A1, A0, 0, A0, 0x33)        ; add a0, a0, a1
                ret
rv64_sub:       RV RV_R(0x20, A1, A0, 0, A0, 0x33)
                ret
rv64_mul:       RV RV_R(1, A1, A0, 0, A0, 0x33)
                ret
rv64_div:       RV RV_R(1, A1, A0, 4, A0, 0x33)        ; div a0, a0, a1
                ret
rv64_mod:       RV RV_R(1, A1, A0, 6, A0, 0x33)        ; rem a0, a0, a1
                ret
rv64_and:       RV RV_R(0, A1, A0, 7, A0, 0x33)
                ret
rv64_or:        RV RV_R(0, A1, A0, 6, A0, 0x33)
                ret
rv64_xor:       RV RV_R(0, A1, A0, 4, A0, 0x33)
                ret
rv64_shl:       RV RV_R(0, A1, A0, 1, A0, 0x33)        ; sll
                ret
rv64_sar:       RV RV_R(0x20, A1, A0, 5, A0, 0x33)     ; sra
                ret

rv64_cmp_eq:    RV RV_R(0x20, A1, A0, 0, A0, 0x33)     ; sub a0, a0, a1
                RV RV_I(1, A0, 3, A0, 0x13)            ; sltiu a0, a0, 1
                ret
rv64_cmp_ne:    RV RV_R(0x20, A1, A0, 0, A0, 0x33)
                RV RV_R(0, A0, X0, 3, A0, 0x33)        ; sltu a0, x0, a0
                ret
rv64_cmp_lt:    RV RV_R(0, A1, A0, 2, A0, 0x33)        ; slt a0, a0, a1
                ret
rv64_cmp_gt:    RV RV_R(0, A0, A1, 2, A0, 0x33)        ; slt a0, a1, a0
                ret
rv64_cmp_le:    RV RV_R(0, A0, A1, 2, A0, 0x33)        ; a0 = (a1 < a0)
                RV RV_I(1, A0, 4, A0, 0x13)            ; xori a0, a0, 1
                ret
rv64_cmp_ge:    RV RV_R(0, A1, A0, 2, A0, 0x33)
                RV RV_I(1, A0, 4, A0, 0x13)
                ret

rv64_neg:       RV RV_R(0x20, A0, X0, 0, A0, 0x33)     ; sub a0, x0, a0
                ret
rv64_not:       RV RV_I(-1, A0, 4, A0, 0x13)           ; xori a0, a0, -1
                ret
rv64_lnot:      RV RV_I(1, A0, 3, A0, 0x13)            ; sltiu a0, a0, 1
                ret
rv64_zext8:     RV RV_I(255, A0, 7, A0, 0x13)          ; andi a0, a0, 255
                ret
rv64_tobool:    RV RV_R(0, A0, X0, 3, A0, 0x33)        ; sltu a0, x0, a0
                ret

; ---- jumps ---------------------------------------------------------------------------------------
; rv64_chain_slot: rdi = &head. Emits  auipc t0,0 ; <previous head>  and makes this pair the new head
rv64_chain_slot:
    push rax
    push rdx
    push rdi
    mov rdx, rdi
    mov rax, [code_pos]
    mov edi, RV_U(0, T0, 0x17)
    call emit_d
    mov edi, [rdx]
    call emit_d
    mov [rdx], rax
    pop rdi
    pop rdx
    pop rax
    ret

rv64_jz_chain:
    RV RV_B(12, X0, A0, 1)          ; bne a0, x0, +12
    jmp rv64_chain_slot
rv64_jnz_chain:
    RV RV_B(12, X0, A0, 0)          ; beq a0, x0, +12
    jmp rv64_chain_slot
rv64_jmp_chain:
    jmp rv64_chain_slot

; edi = condition code CC_*, rsi = &chain head: jump to the chain if A cc B holds.
; Emitted as  b<inverse> ... , +12 ; auipc ; <link>
rv64_jcmp_chain:
    push rax
    push rdi
    push rsi
    mov eax, edi
    mov edi, [rv64_inv_branch + rax*4]
    call emit_d
    mov rdi, rsi
    call rv64_chain_slot
    pop rsi
    pop rdi
    pop rax
    ret
section .rodata
; inverse branches for eq ne lt gt le ge (offset +12):  bne  beq  bge(a0,a1)  bge(a1,a0)  blt(a1,a0)  blt(a0,a1)
rv64_inv_branch:
    dd RV_B(12, A1, A0, 1)
    dd RV_B(12, A1, A0, 0)
    dd RV_B(12, A1, A0, 5)
    dd RV_B(12, A0, A1, 5)
    dd RV_B(12, A0, A1, 4)
    dd RV_B(12, A1, A0, 4)
section .text

; rv64_jump_pair: rdi = target position. Emits  auipc t0,hi ; jalr x0,lo(t0)
rv64_jump_pair:
    push rax
    push rcx
    push rdx
    push rdi
    mov rax, rdi
    sub rax, [code_pos]             ; offset from the auipc
    call rv64_split
    mov edi, RV_U(0, T0, 0x17)
    or edi, edx                     ; hi20 << 12
    call emit_d
    mov edi, RV_I(0, T0, 0, 0, 0x67)
    shl ecx, 20
    or edi, ecx
    call emit_d
    pop rdi
    pop rdx
    pop rcx
    pop rax
    ret

; rv64_split: rax = offset -> edx = (hi20 << 12) as the U immediate field, ecx = lo12 (masked 12 bits)
rv64_split:
    lea rdx, [rax + 0x800]
    sar rdx, 12
    and edx, 0xFFFFF
    shl edx, 12
    mov rcx, rax
    and ecx, 0xFFF
    ret

; rdi = target position
rv64_jmp_back:
    jmp rv64_jump_pair

rv64_jnz_back:
    RV RV_B(12, X0, A0, 0)          ; beq a0, x0, +12
    jmp rv64_jump_pair

; edi = frame offset, rsi = value, rdx = target position
rv64_case_jump:
    push rdi
    push rsi
    push rdx
    push rax
    call rv64_load_local_a
    mov edi, T1
    call rv64_li                    ; t1 = value (rsi)
    RV RV_B(12, T1, A0, 1)          ; bne a0, t1, +12
    mov rdi, rdx
    call rv64_jump_pair
    pop rax
    pop rdx
    pop rsi
    pop rdi
    ret

; rdi = chain head, rsi = target position. Each pair in the chain gets its real auipc / jalr
rv64_patch_chain:
    push rax
    push rcx
    push rdx
    push rdi
    push r8
.l: test rdi, rdi
    jz .d
    mov r8d, [code_buf+rdi+4]       ; the next pair in the chain
    mov eax, [code_buf+rdi]         ; auipc rd, 0  (rd = t0 for jumps, ra for calls)
    mov r9d, eax
    shr r9d, 7
    and r9d, 31                     ; rd
    mov rax, rsi
    sub rax, rdi
    call rv64_split
    mov eax, edx
    shl r9d, 7
    or eax, r9d
    or eax, 0x17                    ; auipc rd, hi
    mov [code_buf+rdi], eax
    shr r9d, 7
    mov eax, RV_I(0, 0, 0, 0, 0x67) ; jalr x0/ra, lo(rd)
    shl ecx, 20
    or eax, ecx
    mov ecx, r9d
    shl ecx, 15
    or eax, ecx                     ; rs1 = rd
    cmp r9d, RA
    jne .j
    mov ecx, RA
    shl ecx, 7
    or eax, ecx                     ; a call links into ra
.j: mov [code_buf+rdi+4], eax
    mov edi, r8d
    jmp .l
.d: pop r8
    pop rdi
    pop rdx
    pop rcx
    pop rax
    ret

; rdi = function symbol
rv64_call_sym:
    push rax
    push rcx
    push rdx
    push rdi
    mov rax, [rdi+SYM_VAL]
    cmp rax, -1
    je .fwd
    sub rax, [code_pos]
    call rv64_split
    mov edi, RV_U(0, RA, 0x17)
    or edi, edx
    call emit_d
    mov edi, RV_I(0, RA, 0, RA, 0x67)
    shl ecx, 20
    or edi, ecx
    call emit_d
    jmp .out
.fwd:
    mov eax, [rdi+SYM_PATCH]
    mov rdx, [code_pos]
    mov [rdi+SYM_PATCH], edx
    mov ecx, eax
    mov edi, RV_U(0, RA, 0x17)
    call emit_d
    mov edi, ecx
    call emit_d
.out:
    pop rdi
    pop rdx
    pop rcx
    pop rax
    ret

; rdi = function symbol -> A = its address (auipc + addi, resolved when the layout is known: R_CODE)
rv64_lea_func_a:
    push rdi
    push rsi
    push rdx
    sub rdi, symtab
    shr rdi, 6
    mov edx, edi
    mov edi, [code_pos]
    mov esi, R_CODE
    call add_reloc
    RV RV_U(0, A0, 0x17)            ; auipc a0, 0
    RV RV_I(0, A0, 0, A0, 0x13)     ; addi a0, a0, 0
    pop rdx
    pop rsi
    pop rdi
    ret

rv64_call_a:
    RV RV_I(0, A0, 0, RA, 0x67)     ; jalr ra, 0(a0)
    ret

; edi = n: a0 = [sp + 16*n]
rv64_load_stack_a:
    push rdi
    shl edi, 4
    cmp edi, 2047
    jbe .ok
    ERR "too many arguments in a call"
.ok:
    shl edi, 20
    or edi, RV_I(0, SP, 3, A0, 0x03)   ; ld a0, imm(sp)
    call emit_d
    pop rdi
    ret

; ---- functions ---------------------------------------------------------------------------------------
rv64_prologue:
    RV RV_I(-16, SP, 0, SP, 0x13)   ; addi sp, sp, -16
    RV RV_S(0, S0, SP, 3, 0x23)     ; sd s0, 0(sp)
    RV RV_S(8, RA, SP, 3, 0x23)     ; sd ra, 8(sp)
    RV RV_I(0, SP, 0, S0, 0x13)     ; addi s0, sp, 0
    push rax
    mov rax, [code_pos]
    mov [frame_patch], rax
    pop rax
    RV RV_U(0, T0, 0x37)            ; lui t0, hi        (patched)
    RV RV_I(0, T0, 0, T0, 0x13)     ; addi t0, t0, lo   (patched)
    RV RV_R(0x20, T0, SP, 0, SP, 0x33) ; sub sp, sp, t0
    ret

rv64_epilogue:
    RV RV_I(0, S0, 0, SP, 0x13)     ; addi sp, s0, 0
    RV RV_I(8, SP, 3, RA, 0x03)     ; ld ra, 8(sp)
    RV RV_I(0, SP, 3, S0, 0x03)     ; ld s0, 0(sp)
    RV RV_I(16, SP, 0, SP, 0x13)    ; addi sp, sp, 16
    RV RV_I(0, RA, 0, X0, 0x67)     ; jalr x0, 0(ra)   (ret)
    ret

; edi = frame size (multiple of 16)
rv64_set_frame:
    push rax
    push rcx
    push rdx
    mov rcx, [frame_patch]
    mov eax, edi
    add eax, 0x800
    shr eax, 12
    shl eax, 12
    or eax, RV_U(0, T0, 0x37)
    mov [code_buf+rcx], eax
    mov edx, edi
    and edx, 0xFFF
    shl edx, 20
    or edx, RV_I(0, T0, 0, T0, 0x13)
    mov [code_buf+rcx+4], edx
    pop rdx
    pop rcx
    pop rax
    ret

; edi = number of main() parameters: argc = [sp], argv = sp + 8 at process start
rv64_entry_args:
    push rdi
    RV RV_I(0, SP, 3, A0, 0x03)     ; ld a0, 0(sp)
    RV RV_I(8, SP, 0, A1, 0x13)     ; addi a1, sp, 8
    pop rdi
    cmp edi, 1
    jb .out
    RV RV_I(-16, SP, 0, SP, 0x13)
    RV RV_S(0, A0, SP, 3, 0x23)
    cmp edi, 2
    jb .out
    RV RV_I(-16, SP, 0, SP, 0x13)
    RV RV_S(0, A1, SP, 3, 0x23)
.out:
    ret

; ---- relocations ----------------------------------------------------------------------------------------
; R_DATA / R_BSS / R_CODE: auipc + addi pair (pc relative); R_DATA64 / R_CODE64: absolute pointer in the data section
apply_relocs_rv64:
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
    add r9, rdi                     ; pc of the auipc
    mov rax, r8
    sub rax, r9
    lea r10, [rax + 0x800]
    sar r10, 12
    and r10d, 0xFFFFF
    shl r10d, 12
    or r10d, RV_U(0, A0, 0x17)
    mov [code_buf+rdi], r10d
    and eax, 0xFFF
    shl eax, 20
    or eax, RV_I(0, A0, 0, A0, 0x13)
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
%macro CGT_RV64 1
    dq rv64_%1
%endmacro
cg_tab_rv64:
    CGLIST CGT_RV64

; Linux / Android RISC-V 64 runtime (raw syscalls, the generic Linux system call numbers). With a 16 byte stack slot
; per argument and the return address in ra, the last argument is at [sp].
bl_rv64_write:
    dd RV_I(0, SP, 3, A2, 0x03)             ; ld a2, 0(sp)
    dd RV_I(16, SP, 3, A1, 0x03)            ; ld a1, 16(sp)
    dd RV_I(32, SP, 3, A0, 0x03)            ; ld a0, 32(sp)
    dd RV_I(64, X0, 0, A7, 0x13)            ; li a7, 64   (write)
    dd 0x00000073                           ; ecall
    dd RV_I(0, RA, 0, X0, 0x67)             ; ret
bl_rv64_write_end:
bl_rv64_read:
    dd RV_I(0, SP, 3, A2, 0x03)
    dd RV_I(16, SP, 3, A1, 0x03)
    dd RV_I(32, SP, 3, A0, 0x03)
    dd RV_I(63, X0, 0, A7, 0x13)            ; li a7, 63   (read)
    dd 0x00000073
    dd RV_I(0, RA, 0, X0, 0x67)
bl_rv64_read_end:
bl_rv64_exit:
    dd RV_I(0, SP, 3, A0, 0x03)             ; ld a0, 0(sp)
    dd RV_I(94, X0, 0, A7, 0x13)            ; li a7, 94   (exit_group)
    dd 0x00000073
    dd RV_I(0, RA, 0, X0, 0x67)
bl_rv64_exit_end:
bl_rv64_syscall:
    dd RV_I(0, SP, 3, A5, 0x03)             ; ld a5, 0(sp)
    dd RV_I(16, SP, 3, 14, 0x03)            ; ld a4, 16(sp)
    dd RV_I(32, SP, 3, 13, 0x03)            ; ld a3, 32(sp)
    dd RV_I(48, SP, 3, A2, 0x03)            ; ld a2, 48(sp)
    dd RV_I(64, SP, 3, A1, 0x03)            ; ld a1, 64(sp)
    dd RV_I(80, SP, 3, A0, 0x03)            ; ld a0, 80(sp)
    dd RV_I(96, SP, 3, A7, 0x03)            ; ld a7, 96(sp)
    dd 0x00000073
    dd RV_I(0, RA, 0, X0, 0x67)
bl_rv64_syscall_end:
bl_rv64_open:
    dd RV_I(16, SP, 3, A1, 0x03)            ; ld a1, 16(sp)     path
    dd RV_I(0, SP, 3, T0, 0x03)             ; ld t0, 0(sp)      mode (0 read, 1 write, 2 append)
    dd RV_I(0, X0, 0, A2, 0x13)             ; li a2, 0
    dd RV_I(1, X0, 0, T1, 0x13)             ; li t1, 1
    dd RV_B(16, T1, T0, 0)                  ; beq t0, t1, write
    dd RV_I(2, X0, 0, T1, 0x13)             ; li t1, 2
    dd RV_B(16, T1, T0, 0)                  ; beq t0, t1, append
    dd RV_J_PLUS(16)                        ; j openat
    dd RV_I(0x241, X0, 0, A2, 0x13)         ; write:  li a2, 0x241
    dd RV_J_PLUS(8)                         ; j openat
    dd RV_I(0x441, X0, 0, A2, 0x13)         ; append: li a2, 0x441
    dd RV_I(-100, X0, 0, A0, 0x13)          ; openat: li a0, -100  (AT_FDCWD)
    dd RV_I(0x1A4, X0, 0, A3_REG, 0x13)     ; li a3, 0644
    dd RV_I(56, X0, 0, A7, 0x13)            ; li a7, 56   (openat)
    dd 0x00000073
    dd RV_I(0, RA, 0, X0, 0x67)
bl_rv64_open_end:
bl_rv64_close:
    dd RV_I(0, SP, 3, A0, 0x03)
    dd RV_I(57, X0, 0, A7, 0x13)            ; li a7, 57   (close)
    dd 0x00000073
    dd RV_I(0, RA, 0, X0, 0x67)
bl_rv64_close_end:
bl_rv64_fail:
    dd RV_I(-1, X0, 0, A0, 0x13)            ; li a0, -1
    dd RV_I(0, RA, 0, X0, 0x67)
bl_rv64_fail_end:
bl_rv64_setjmp:
    dd RV_I(0, SP, 3, A0, 0x03)             ; ld a0, 0(sp)
    dd RV_S(0, S0, A0, 3, 0x23)             ; sd s0, 0(a0)
    dd RV_S(8, SP, A0, 3, 0x23)             ; sd sp, 8(a0)
    dd RV_S(16, RA, A0, 3, 0x23)            ; sd ra, 16(a0)
    dd RV_I(0, X0, 0, A0, 0x13)             ; li a0, 0
    dd RV_I(0, RA, 0, X0, 0x67)
bl_rv64_setjmp_end:
bl_rv64_longjmp:
    dd RV_I(0, SP, 3, A0, 0x03)             ; ld a0, 0(sp)     value
    dd RV_I(16, SP, 3, A1, 0x03)            ; ld a1, 16(sp)    buffer
    dd RV_B(8, X0, A0, 1)                   ; bne a0, x0, +8
    dd RV_I(1, X0, 0, A0, 0x13)             ; li a0, 1
    dd RV_I(0, A1, 3, S0, 0x03)             ; ld s0, 0(a1)
    dd RV_I(8, A1, 3, A2, 0x03)             ; ld a2, 8(a1)
    dd RV_I(16, A1, 3, RA, 0x03)            ; ld ra, 16(a1)
    dd RV_I(0, A2, 0, SP, 0x13)             ; mv sp, a2
    dd RV_I(0, RA, 0, X0, 0x67)             ; jalr x0, 0(ra)
bl_rv64_longjmp_end:
bl_rv64_cmdline:
    dd RV_I(0, X0, 0, A0, 0x13)             ; li a0, 0
    dd RV_I(0, RA, 0, X0, 0x67)
bl_rv64_cmdline_end:
section .text
