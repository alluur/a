; =============================================================================
;  ccall.asm - calling C functions and being called by C (the backend primitives ccall and cthunk)
;
;  A passes arguments on the stack (x86-64: 8 byte slots, the others: 16 byte slots, the last argument on top); C wants
;  them in registers. ccall emits a sequence that loads every argument from its A slot into the register (or C stack slot)
;  that the target's C ABI assigns, aligns the stack, calls the address in A and returns the result in A. cthunk emits the
;  reverse: a C entry point that stores the C arguments into A slots, calls an A function and returns its result the C way.
;  Both are described by cc_n (arguments), cc_nfixed (the rest are the ... arguments), cc_cls (CC_* of every argument) and
;  cc_ret. Floats travel as binary32 in the low half of their slot (the caller of ccall stores them with dtof).
; =============================================================================
section .text

; cc_classify: edi = integer argument registers, esi = float argument registers, edx = flags (1: a float that finds no free
; float register goes in an integer register, 2: the ... arguments that are floats go in integer registers).
; Fills cc_loc, cc_nstack and cc_nfp.
cc_classify:
    push rbx
    push r12
    push r13
    push r14
    xor ecx, ecx                        ; argument
    xor r8d, r8d                        ; integer registers used
    xor r9d, r9d                        ; float registers used
    xor r10d, r10d                      ; stack slots used
.l: cmp ecx, [cc_n]
    jae .done
    movzx eax, byte [cc_cls + rcx]
    cmp eax, CC_DBL
    je .fp
    cmp eax, CC_FLT
    jne .int
.fp:
    cmp ecx, [cc_nfixed]
    jb .fixed
    test edx, 2
    jnz .int
.fixed:
    cmp r9d, esi
    jae .fpfull
    lea eax, [r9 + 0x40]
    inc r9d
    jmp .set
.fpfull:
    test edx, 1
    jnz .int
    jmp .stack
.int:
    cmp r8d, edi
    jae .stack
    mov eax, r8d
    inc r8d
    jmp .set
.stack:
    lea eax, [r10 + 0x80]
    inc r10d
.set:
    mov [cc_loc + rcx], al
    inc ecx
    jmp .l
.done:
    mov [cc_nstack], r10d
    mov [cc_nfp], r9d
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---- x86-64 ----------------------------------------------------------------------------------------------------------------
; x86 helpers: emit an instruction with a [rbx + disp32] or [rbp + disp32] operand
; x86_cc_rm: edi = REX prefix (0 = none), esi = opcode bytes (1 to 3, low byte first), edx = reg field, ecx = displacement,
; r8d = base (3 = rbx, 5 = rbp)
x86_cc_rm:
    push rdi
    test edi, edi
    jz .norex
    call emit_b
.norex:
    mov edi, esi
.op:
    call emit_b
    shr esi, 8
    mov edi, esi
    test esi, esi
    jnz .op
    lea edi, [rdx*8 + 0x80]
    and edi, 0xB8
    or edi, r8d
    call emit_b
    mov edi, ecx
    call emit_d
    pop rdi
    ret

; the integer argument registers of the System V and the Windows ABI (register numbers)
x86_sysv_regs: db 7, 6, 2, 1, 8, 9
x86_win_regs:  db 1, 2, 8, 9

; x86_cc_disp: ecx = argument -> ecx = displacement of its A slot from rbx (rbx = the stack after "push rbx")
x86_cc_disp:
    mov eax, [cc_n]
    sub eax, ecx
    lea ecx, [rax*8]                    ; 8 + 8 * (n - 1 - i)
    ret

; x86_cc_loadint: eax = register number, ecx = argument: mov reg, [rbx + slot]
x86_cc_loadint:
    push rdi
    push rsi
    push rdx
    push rcx
    push r8
    mov edx, eax
    mov edi, 0x48
    cmp edx, 8
    jb .r
    mov edi, 0x4C
.r: call x86_cc_disp
    mov esi, 0x8B
    mov r8d, 3
    call x86_cc_rm
    pop r8
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    ret

; x86_cc_loadfp: eax = xmm register, ecx = argument: movsd / movss xmm, [rbx + slot] (by the class)
x86_cc_loadfp:
    push rdi
    push rsi
    push rdx
    push rcx
    push r8
    mov edx, eax
    movzx eax, byte [cc_cls + rcx]
    mov edi, 0xF2
    cmp eax, CC_FLT
    jne .d
    mov edi, 0xF3
.d: call x86_cc_disp
    mov esi, 0x100F
    mov r8d, 3
    call x86_cc_rm
    pop r8
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    ret

; x86_cc_result: the C result (rax / xmm0) -> A
x86_cc_result:
    cmp dword [cc_ret], CC_DBL
    je .d
    cmp dword [cc_ret], CC_FLT
    jne .r
    EM 0xF3, 0x0F, 0x5A, 0xC0           ; cvtss2sd xmm0, xmm0
.d: EM 0x66, 0x48, 0x0F, 0x7E, 0xC0     ; movq rax, xmm0
.r: ret

x86_ccall:
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    push rbx
    EM 0x49, 0x89, 0xC2                 ; mov r10, rax
    EM 0x53                             ; push rbx
    EM 0x48, 0x89, 0xE3                 ; mov rbx, rsp
    EM 0x48, 0x83, 0xE4, 0xF0           ; and rsp, -16
    cmp dword [target], TGT_WINDOWS
    je .win
    mov edi, 6
    mov esi, 8
    xor edx, edx
    call cc_classify
    test dword [cc_nstack], 1
    jz .even
    EM 0x48, 0x83, 0xEC, 0x08           ; sub rsp, 8  (the stack arguments end 16 byte aligned)
.even:
    mov ecx, [cc_n]                     ; stack arguments, the last one first
.sl:
    test ecx, ecx
    jz .regs
    dec ecx
    cmp byte [cc_loc + rcx], 0x80
    jb .sl
    push rcx
    call x86_cc_disp
    xor edi, edi
    mov esi, 0xFF
    mov edx, 6
    mov r8d, 3
    call x86_cc_rm                      ; push qword [rbx + slot]
    pop rcx
    jmp .sl
.regs:
    xor ecx, ecx
.rl:
    cmp ecx, [cc_n]
    jae .call
    movzx eax, byte [cc_loc + rcx]
    cmp eax, 0x80
    jae .rn
    cmp eax, 0x40
    jae .rfp
    movzx eax, byte [x86_sysv_regs + rax]
    call x86_cc_loadint
    jmp .rn
.rfp:
    sub eax, 0x40
    call x86_cc_loadfp
.rn:
    inc ecx
    jmp .rl
.call:
    mov edi, 0xB8                       ; mov eax, number of vector registers (for C functions with ...)
    call emit_b
    mov edi, [cc_nfp]
    call emit_d
    jmp .docall
.win:
    ; Windows x64: the first four arguments in rcx rdx r8 r9 / xmm0-3 by position, 32 bytes of shadow space, the rest above it
    mov eax, [cc_n]
    sub eax, 4
    jns .w1
    xor eax, eax
.w1:
    lea eax, [rax*8 + 32 + 15]
    and eax, -16
    push rax
    EM 0x48, 0x81, 0xEC                 ; sub rsp, imm32
    pop rdi
    call emit_d
    mov ecx, 4
.wst:
    cmp ecx, [cc_n]
    jae .wregs
    push rcx
    call x86_cc_disp
    mov edi, 0x48
    mov esi, 0x8B
    xor edx, edx
    mov r8d, 3
    call x86_cc_rm                      ; mov rax, [rbx + slot]
    pop rcx
    push rcx
    EM 0x48, 0x89, 0x84, 0x24           ; mov [rsp + 32 + 8 * (i - 4)], rax
    lea edi, [rcx*8]
    call emit_d
    pop rcx
    inc ecx
    jmp .wst
.wregs:
    xor ecx, ecx
.wl:
    cmp ecx, [cc_n]
    jae .docall
    cmp ecx, 4
    jae .docall
    movzx eax, byte [cc_cls + rcx]
    cmp eax, CC_DBL
    je .wfp
    cmp eax, CC_FLT
    je .wfp
.wint:
    movzx eax, byte [x86_win_regs + rcx]
    call x86_cc_loadint
    jmp .wn
.wfp:
    mov eax, ecx
    call x86_cc_loadfp
    cmp ecx, [cc_nfixed]
    jae .wint                           ; a ... argument: in the integer register too
.wn:
    inc ecx
    jmp .wl
.docall:
    EM 0x41, 0xFF, 0xD2                 ; call r10
    EM 0x48, 0x89, 0xDC                 ; mov rsp, rbx
    EM 0x5B                             ; pop rbx
    call x86_cc_result
    pop rbx
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    ret

; x86 cthunk: rdi = the A function
x86_cthunk:
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r12
    mov r12, rdi
    EM 0x55, 0x48, 0x89, 0xE5           ; push rbp / mov rbp, rsp
    cmp dword [target], TGT_WINDOWS
    je .win
    EM 0x53, 0x41, 0x54, 0x41, 0x55, 0x41, 0x56, 0x41, 0x57     ; push rbx r12 r13 r14 r15
    mov edi, 6
    mov esi, 8
    xor edx, edx
    call cc_classify
    xor ecx, ecx
.l: cmp ecx, [cc_n]
    jae .call
    movzx eax, byte [cc_loc + rcx]
    cmp eax, 0x80
    jae .stk
    cmp eax, 0x40
    jae .fp
    movzx eax, byte [x86_sysv_regs + rax]
    call x86_cc_pushreg
    jmp .n
.fp:
    sub eax, 0x40
    call x86_cc_pushxmm
    jmp .n
.stk:
    sub eax, 0x80
    push rcx
    lea ecx, [rax*8 + 16]               ; [rbp + 16 + 8 * s]
    xor edi, edi
    mov esi, 0xFF
    mov edx, 6
    mov r8d, 5
    call x86_cc_rm                      ; push qword [rbp + 16 + 8s]
    pop rcx
.n: inc ecx
    jmp .l
.call:
    mov rdi, r12
    call x86_call_sym
    call x86_ct_drop
    call x86_ct_result
    EM 0x41, 0x5F, 0x41, 0x5E, 0x41, 0x5D, 0x41, 0x5C, 0x5B, 0x5D, 0xC3
    jmp .out
.win:
    EM 0x53, 0x56, 0x57, 0x41, 0x54, 0x41, 0x55, 0x41, 0x56, 0x41, 0x57   ; push rbx rsi rdi r12 r13 r14 r15
    xor ecx, ecx
.wl:
    cmp ecx, [cc_n]
    jae .wcall
    cmp ecx, 4
    jae .wstk
    movzx eax, byte [cc_cls + rcx]
    cmp eax, CC_DBL
    je .wfp
    cmp eax, CC_FLT
    je .wfp
    movzx eax, byte [x86_win_regs + rcx]
    call x86_cc_pushreg
    jmp .wn
.wfp:
    mov eax, ecx
    call x86_cc_pushxmm
    jmp .wn
.wstk:
    push rcx
    lea ecx, [rcx*8 + 16]               ; [rbp + 16 + 32 + 8 * (i - 4)]
    xor edi, edi
    mov esi, 0xFF
    mov edx, 6
    mov r8d, 5
    call x86_cc_rm
    pop rcx
.wn:
    inc ecx
    jmp .wl
.wcall:
    mov rdi, r12
    call x86_call_sym
    call x86_ct_drop
    call x86_ct_result
    EM 0x41, 0x5F, 0x41, 0x5E, 0x41, 0x5D, 0x41, 0x5C, 0x5F, 0x5E, 0x5B, 0x5D, 0xC3
.out:
    pop r12
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    ret

; x86_cc_pushreg: eax = register number: push it
x86_cc_pushreg:
    push rdi
    cmp eax, 8
    jb .lo
    push rax
    mov edi, 0x41
    call emit_b
    pop rax
    sub eax, 8
.lo:
    lea edi, [rax + 0x50]
    call emit_b
    pop rdi
    ret

; x86_cc_pushxmm: eax = xmm register, ecx = argument: its bits (a double) or binary32 bits (a float) pushed as one A slot
x86_cc_pushxmm:
    push rdi
    push rax
    movzx edi, byte [cc_cls + rcx]
    cmp edi, CC_FLT
    je .f
    EM 0x66, 0x48, 0x0F, 0x7E           ; movq rax, xmm
    jmp .m
.f: EM 0x66, 0x0F, 0x7E                 ; movd eax, xmm
.m: pop rax
    lea edi, [rax*8 + 0xC0]
    call emit_b
    EM 0x50                             ; push rax
    pop rdi
    ret

; x86_ct_drop: removes the cc_n argument slots of the thunk's call
x86_ct_drop:
    cmp dword [cc_n], 0
    je .r
    EM 0x48, 0x81, 0xC4                 ; add rsp, imm32
    push rdi
    mov edi, [cc_n]
    shl edi, 3
    call emit_d
    pop rdi
.r: ret

; x86_ct_result: the A result (rax) -> the C result register
x86_ct_result:
    cmp dword [cc_ret], CC_DBL
    je .d
    cmp dword [cc_ret], CC_FLT
    je .f
    ret
.d: EM 0x66, 0x48, 0x0F, 0x6E, 0xC0     ; movq xmm0, rax
    ret
.f: EM 0x66, 0x48, 0x0F, 0x6E, 0xC0, 0xF2, 0x0F, 0x5A, 0xC0     ; movq xmm0, rax / cvtsd2ss xmm0, xmm0
    ret

; ---- shared helpers for the 16-byte-slot CPUs ----------------------------------------------------------------------------------
; cc_off16: ecx = argument -> eax = offset of its A slot above the saved register (16 + 16 * (n - 1 - i))
cc_off16:
    mov eax, [cc_n]
    sub eax, ecx
    shl eax, 4
    ret

; emitw: edi = an instruction word
%define emitw call emit_d

; ---- AArch64 -----------------------------------------------------------------------------------------------------------------
a64_ccall:
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    A64 0xAA0003F0                      ; mov x16, x0
    A64 0xF81F0FF3                      ; str x19, [sp, #-16]!
    A64 0x910003F3                      ; mov x19, sp
    mov edi, 8
    mov esi, 8
    xor edx, edx
    call cc_classify
    mov eax, [cc_nstack]
    test eax, eax
    jz .regs
    lea edi, [rax*8 + 15]
    and edi, -16
    shl edi, 10
    or edi, 0xD10003FF                  ; sub sp, sp, #bytes
    emitw
    xor ecx, ecx
.st:
    cmp ecx, [cc_n]
    jae .regs
    movzx edx, byte [cc_loc + rcx]
    cmp edx, 0x80
    jb .stn
    sub edx, 0x80
    call cc_off16
    mov edi, eax                        ; (offset / 8) << 10
    shl edi, 7
    or edi, 0xF9400269                  ; ldr x9, [x19, #off]
    emitw
    mov edi, edx
    shl edi, 10
    or edi, 0xF90003E9                  ; str x9, [sp, #8k]
    emitw
.stn:
    inc ecx
    jmp .st
.regs:
    xor ecx, ecx
.rl:
    cmp ecx, [cc_n]
    jae .call
    movzx edx, byte [cc_loc + rcx]
    cmp edx, 0x80
    jae .rn
    call cc_off16
    cmp edx, 0x40
    jae .rfp
    shr eax, 3
    shl eax, 10
    lea edi, [rax + rdx]
    or edi, 0xF9400260                  ; ldr xk, [x19, #off]
    emitw
    jmp .rn
.rfp:
    sub edx, 0x40
    cmp byte [cc_cls + rcx], CC_FLT
    je .rflt
    shr eax, 3
    shl eax, 10
    lea edi, [rax + rdx]
    or edi, 0xFD400260                  ; ldr dk, [x19, #off]
    emitw
    jmp .rn
.rflt:
    shr eax, 2
    shl eax, 10
    lea edi, [rax + rdx]
    or edi, 0xBD400260                  ; ldr sk, [x19, #off]
    emitw
.rn:
    inc ecx
    jmp .rl
.call:
    A64 0xD63F0200                      ; blr x16
    A64 0x9100027F                      ; mov sp, x19
    A64 0xF84107F3                      ; ldr x19, [sp], #16
    cmp dword [cc_ret], CC_DBL
    je .rd
    cmp dword [cc_ret], CC_FLT
    jne .out
    A64 0x1E22C000                      ; fcvt d0, s0
.rd:
    A64 0x9E660000                      ; fmov x0, d0
.out:
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    ret

a64_cthunk:
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r12
    mov r12, rdi
    A64 0xA9BF7BFD                      ; stp x29, x30, [sp, #-16]!
    A64 0x910003FD                      ; mov x29, sp
    A64 0xA9BF53F3                      ; stp x19, x20, [sp, #-16]!   (the registers C expects to be kept)
    A64 0xA9BF5BF5
    A64 0xA9BF63F7
    A64 0xA9BF6BF9
    A64 0xA9BF73FB                      ; stp x27, x28, [sp, #-16]!
    mov edi, 8
    mov esi, 8
    xor edx, edx
    call cc_classify
    xor ecx, ecx
.l: cmp ecx, [cc_n]
    jae .call
    movzx edx, byte [cc_loc + rcx]
    cmp edx, 0x80
    jae .stk
    cmp edx, 0x40
    jae .fp
    mov edi, 0xF81F0FE0
    add edi, edx         ; str xk, [sp, #-16]!
    emitw
    jmp .n
.fp:
    sub edx, 0x40
    mov edi, 0xFC1F0FE0
    add edi, edx         ; str dk, [sp, #-16]!
    cmp byte [cc_cls + rcx], CC_FLT
    jne .fpw
    mov edi, 0xBC1F0FE0
    add edi, edx         ; str sk, [sp, #-16]!
.fpw:
    emitw
    jmp .n
.stk:
    sub edx, 0x80
    lea edi, [rdx + 2]                  ; ldr x9, [x29, #16 + 8s]
    shl edi, 10
    or edi, 0xF94003A9
    emitw
    A64 0xF81F0FE9                      ; str x9, [sp, #-16]!
.n: inc ecx
    jmp .l
.call:
    mov rdi, r12
    call a64_call_sym
    A64 0xD10143BF                      ; sub sp, x29, #80
    cmp dword [cc_ret], CC_DBL
    je .rd
    cmp dword [cc_ret], CC_FLT
    jne .rr
    A64 0x9E670000                      ; fmov d0, x0
    A64 0x1E624000                      ; fcvt s0, d0
    jmp .rr
.rd:
    A64 0x9E670000                      ; fmov d0, x0
.rr:
    A64 0xA8C173FB                      ; ldp x27, x28, [sp], #16
    A64 0xA8C16BF9
    A64 0xA8C163F7
    A64 0xA8C15BF5
    A64 0xA8C153F3                      ; ldp x19, x20, [sp], #16
    A64 0xA8C17BFD                      ; ldp x29, x30, [sp], #16
    A64 0xD65F03C0                      ; ret
    pop r12
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    ret

; ---- RISC-V 64 ---------------------------------------------------------------------------------------------------------------
; rv_i: edi = imm, esi = rs1, edx = funct3, ecx = rd, r8d = opcode -> emits the I-type instruction
rv_i:
    push rdi
    and edi, 0xFFF
    shl edi, 20
    shl esi, 15
    or edi, esi
    shl edx, 12
    or edi, edx
    shl ecx, 7
    or edi, ecx
    or edi, r8d
    emitw
    pop rdi
    ret

; rv_s: edi = imm, esi = rs2, edx = rs1, ecx = funct3, r8d = opcode -> emits the S-type instruction
rv_s:
    push rdi
    push rax
    mov eax, edi
    and eax, 0x1F
    shl eax, 7
    shr edi, 5
    and edi, 0x7F
    shl edi, 25
    or edi, eax
    shl esi, 20
    or edi, esi
    shl edx, 15
    or edi, edx
    shl ecx, 12
    or edi, ecx
    or edi, r8d
    emitw
    pop rax
    pop rdi
    ret

; rv_cc_off: ecx = argument -> eax = offset of its slot from s1 (fails when it does not fit 12 bits)
rv_cc_off:
    call cc_off16
    cmp eax, 2047
    jbe .ok
    ERR "too many arguments for a C function on this CPU"
.ok:
    ret

rv64_ccall:
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r12
    push r13
    RV 0x00050313                       ; addi t1, a0, 0
    RV 0xFF010113                       ; addi sp, sp, -16
    RV 0x00913023                       ; sd s1, 0(sp)
    RV 0x00010493                       ; addi s1, sp, 0
    mov edi, 8
    mov esi, 8
    mov edx, 3                          ; floats spill into integer registers, ... floats go in integer registers
    call cc_classify
    mov eax, [cc_nstack]
    test eax, eax
    jz .regs
    lea edi, [rax*8 + 15]
    and edi, -16
    neg edi
    mov esi, 2
    xor edx, edx
    mov ecx, 2
    mov r8d, 0x13
    call rv_i                           ; addi sp, sp, -bytes
    xor r12d, r12d
.st:
    cmp r12d, [cc_n]
    jae .regs
    movzx r13d, byte [cc_loc + r12]
    cmp r13d, 0x80
    jb .stn
    mov ecx, r12d
    call rv_cc_off
    mov edi, eax
    mov esi, 9
    mov edx, 3
    mov ecx, 5
    mov r8d, 0x03
    call rv_i                           ; ld t0, off(s1)
    lea edi, [r13*8 - 0x400]
    mov esi, 5
    mov edx, 2
    mov ecx, 3
    mov r8d, 0x23
    call rv_s                           ; sd t0, 8k(sp)
.stn:
    inc r12d
    jmp .st
.regs:
    xor r12d, r12d
.rl:
    cmp r12d, [cc_n]
    jae .call
    movzx r13d, byte [cc_loc + r12]
    cmp r13d, 0x80
    jae .rn
    mov ecx, r12d
    call rv_cc_off
    mov edi, eax
    mov esi, 9
    cmp r13d, 0x40
    jae .rfp
    mov edx, 3                          ; ld
    cmp byte [cc_cls + r12], CC_I32
    jne .ri
    mov edx, 2                          ; lw: a 32-bit integer is passed sign extended
.ri:
    lea ecx, [r13 + 10]                 ; a0 + k
    mov r8d, 0x03
    call rv_i
    jmp .rn
.rfp:
    mov edx, 3                          ; fld
    cmp byte [cc_cls + r12], CC_FLT
    jne .rf
    mov edx, 2                          ; flw
.rf:
    lea ecx, [r13 - 0x40 + 10]          ; fa0 + k
    mov r8d, 0x07
    call rv_i
.rn:
    inc r12d
    jmp .rl
.call:
    RV 0x000300E7                       ; jalr ra, 0(t1)
    RV 0x00048113                       ; addi sp, s1, 0
    RV 0x00013483                       ; ld s1, 0(sp)
    RV 0x01010113                       ; addi sp, sp, 16
    cmp dword [cc_ret], CC_DBL
    je .rd
    cmp dword [cc_ret], CC_FLT
    jne .out
    RV 0x42050553                       ; fcvt.d.s fa0, fa0
.rd:
    RV 0xE2050553                       ; fmv.x.d a0, fa0
.out:
    pop r13
    pop r12
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    ret

; the registers a C function must keep (ra, s0 .. s11) and their places in the thunk's 112 byte frame
rv_saved_regs: db 1, 8, 9, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27

rv64_cthunk:
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r12
    push r13
    push r14
    mov r14, rdi
    RV 0xF9010113                       ; addi sp, sp, -112
    xor r12d, r12d
.sv:
    movzx esi, byte [rv_saved_regs + r12]
    mov edi, 104
    lea eax, [r12*8]
    sub edi, eax
    mov edx, 2
    mov ecx, 3
    mov r8d, 0x23
    call rv_s                           ; sd reg, (104 - 8i)(sp)
    inc r12d
    cmp r12d, 13
    jb .sv
    RV 0x07010413                       ; addi s0, sp, 112
    mov edi, 8
    mov esi, 8
    mov edx, 1
    call cc_classify
    xor r12d, r12d
.l: cmp r12d, [cc_n]
    jae .call
    RV 0xFF010113                       ; addi sp, sp, -16
    movzx r13d, byte [cc_loc + r12]
    cmp r13d, 0x80
    jae .stk
    xor edi, edi
    mov edx, 2
    cmp r13d, 0x40
    jae .fp
    lea esi, [r13 + 10]
    mov ecx, 3
    mov r8d, 0x23
    call rv_s                           ; sd ak, 0(sp)
    jmp .n
.fp:
    lea esi, [r13 - 0x40 + 10]
    mov ecx, 3
    cmp byte [cc_cls + r12], CC_FLT
    jne .fpd
    mov ecx, 2
.fpd:
    mov r8d, 0x27
    call rv_s                           ; fsd / fsw fak, 0(sp)
    jmp .n
.stk:
    lea edi, [r13*8 - 0x400]
    mov esi, 8
    mov edx, 3
    mov ecx, 5
    mov r8d, 0x03
    call rv_i                           ; ld t0, 8s(s0)
    xor edi, edi
    mov esi, 5
    mov edx, 2
    mov ecx, 3
    mov r8d, 0x23
    call rv_s                           ; sd t0, 0(sp)
.n: inc r12d
    jmp .l
.call:
    mov rdi, r14
    call rv64_call_sym
    RV 0xF9040113                       ; addi sp, s0, -112
    cmp dword [cc_ret], CC_DBL
    je .rd
    cmp dword [cc_ret], CC_FLT
    jne .rr
    RV 0xF2050553                       ; fmv.d.x fa0, a0
    RV 0x40157553                       ; fcvt.s.d fa0, fa0
    jmp .rr
.rd:
    RV 0xF2050553                       ; fmv.d.x fa0, a0
.rr:
    xor r12d, r12d
.rs:
    movzx ecx, byte [rv_saved_regs + r12]
    mov edi, 104
    lea eax, [r12*8]
    sub edi, eax
    mov esi, 2
    mov edx, 3
    mov r8d, 0x03
    call rv_i                           ; ld reg, (104 - 8i)(sp)
    inc r12d
    cmp r12d, 13
    jb .rs
    RV 0x07010113                       ; addi sp, sp, 112
    RV 0x00008067                       ; ret
    pop r14
    pop r13
    pop r12
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    ret

; ---- LoongArch64 -------------------------------------------------------------------------------------------------------------
; la_ri: edi = opcode, esi = imm12, edx = rj, ecx = rd -> emits the 2RI12 instruction
la_ri:
    push rdi
    and esi, 0xFFF
    shl esi, 10
    or edi, esi
    shl edx, 5
    or edi, edx
    or edi, ecx
    emitw
    pop rdi
    ret

la64_ccall:
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r12
    push r13
    LA 0x0015008D                       ; or $t1, $a0, $zero
    LA 0x02FFC063                       ; addi.d $sp, $sp, -16
    LA 0x29C00077                       ; st.d $s0, $sp, 0
    LA 0x00150077                       ; or $s0, $sp, $zero
    mov edi, 8
    mov esi, 8
    mov edx, 3
    call cc_classify
    mov eax, [cc_nstack]
    test eax, eax
    jz .regs
    lea esi, [rax*8 + 15]
    and esi, -16
    neg esi
    mov edi, 0x02C00000
    mov edx, 3
    mov ecx, 3
    call la_ri                          ; addi.d $sp, $sp, -bytes
    xor r12d, r12d
.st:
    cmp r12d, [cc_n]
    jae .regs
    movzx r13d, byte [cc_loc + r12]
    cmp r13d, 0x80
    jb .stn
    mov ecx, r12d
    call rv_cc_off
    mov esi, eax
    mov edi, 0x28C00000
    mov edx, 23
    mov ecx, 12
    call la_ri                          ; ld.d $t0, $s0, off
    lea esi, [r13*8 - 0x400]
    mov edi, 0x29C00000
    mov edx, 3
    mov ecx, 12
    call la_ri                          ; st.d $t0, $sp, 8k
.stn:
    inc r12d
    jmp .st
.regs:
    xor r12d, r12d
.rl:
    cmp r12d, [cc_n]
    jae .call
    movzx r13d, byte [cc_loc + r12]
    cmp r13d, 0x80
    jae .rn
    mov ecx, r12d
    call rv_cc_off
    mov esi, eax
    mov edx, 23
    cmp r13d, 0x40
    jae .rfp
    mov edi, 0x28C00000                 ; ld.d
    cmp byte [cc_cls + r12], CC_I32
    jne .ri
    mov edi, 0x28800000                 ; ld.w: sign extended
.ri:
    lea ecx, [r13 + 4]                  ; $a0 + k
    call la_ri
    jmp .rn
.rfp:
    mov edi, 0x2B800000                 ; fld.d
    cmp byte [cc_cls + r12], CC_FLT
    jne .rf
    mov edi, 0x2B000000                 ; fld.s
.rf:
    lea ecx, [r13 - 0x40]               ; $fa0 + k
    call la_ri
.rn:
    inc r12d
    jmp .rl
.call:
    LA 0x4C0001A1                       ; jirl $ra, $t1, 0
    LA 0x001502E3                       ; or $sp, $s0, $zero
    LA 0x28C00077                       ; ld.d $s0, $sp, 0
    LA 0x02C04063                       ; addi.d $sp, $sp, 16
    cmp dword [cc_ret], CC_DBL
    je .rd
    cmp dword [cc_ret], CC_FLT
    jne .out
    LA 0x01192400                       ; fcvt.d.s $fa0, $fa0
.rd:
    LA 0x0114B804                       ; movfr2gr.d $a0, $fa0
.out:
    pop r13
    pop r12
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    ret

; the registers a C function must keep: $ra, $fp, $s0 .. $s8 (in the thunk's 96 byte frame)
la_saved_regs: db 1, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31

la64_cthunk:
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r12
    push r13
    push r14
    mov r14, rdi
    mov edi, 0x02C00000
    mov esi, -96
    mov edx, 3
    mov ecx, 3
    call la_ri                          ; addi.d $sp, $sp, -96
    xor r12d, r12d
.sv:
    movzx ecx, byte [la_saved_regs + r12]
    mov esi, 88
    lea eax, [r12*8]
    sub esi, eax
    mov edi, 0x29C00000
    mov edx, 3
    call la_ri                          ; st.d reg, $sp, 88 - 8i
    inc r12d
    cmp r12d, 11
    jb .sv
    LA 0x02C18076                       ; addi.d $fp, $sp, 96
    mov edi, 8
    mov esi, 8
    mov edx, 1
    call cc_classify
    xor r12d, r12d
.l: cmp r12d, [cc_n]
    jae .call
    LA 0x02FFC063                       ; addi.d $sp, $sp, -16
    movzx r13d, byte [cc_loc + r12]
    cmp r13d, 0x80
    jae .stk
    xor esi, esi
    mov edx, 3
    cmp r13d, 0x40
    jae .fp
    mov edi, 0x29C00000
    lea ecx, [r13 + 4]
    call la_ri                          ; st.d $ak, $sp, 0
    jmp .n
.fp:
    mov edi, 0x2BC00000                 ; fst.d
    cmp byte [cc_cls + r12], CC_FLT
    jne .fpd
    mov edi, 0x2B400000                 ; fst.s
.fpd:
    lea ecx, [r13 - 0x40]
    call la_ri
    jmp .n
.stk:
    lea esi, [r13*8 - 0x400]
    mov edi, 0x28C00000
    mov edx, 22
    mov ecx, 12
    call la_ri                          ; ld.d $t0, $fp, 8s
    xor esi, esi
    mov edi, 0x29C00000
    mov edx, 3
    mov ecx, 12
    call la_ri                          ; st.d $t0, $sp, 0
.n: inc r12d
    jmp .l
.call:
    mov rdi, r14
    call la64_call_sym
    LA 0x02FE82C3                       ; addi.d $sp, $fp, -96
    cmp dword [cc_ret], CC_DBL
    je .rd
    cmp dword [cc_ret], CC_FLT
    jne .rr
    LA 0x0114A880                       ; movgr2fr.d $fa0, $a0
    LA 0x01191800                       ; fcvt.s.d $fa0, $fa0
    jmp .rr
.rd:
    LA 0x0114A880                       ; movgr2fr.d $fa0, $a0
.rr:
    xor r12d, r12d
.rs:
    movzx ecx, byte [la_saved_regs + r12]
    mov esi, 88
    lea eax, [r12*8]
    sub esi, eax
    mov edi, 0x28C00000
    mov edx, 3
    call la_ri                          ; ld.d reg, $sp, 88 - 8i
    inc r12d
    cmp r12d, 11
    jb .rs
    LA 0x02C18063                       ; addi.d $sp, $sp, 96
    LA 0x4C000020                       ; jirl $zero, $ra, 0
    pop r14
    pop r13
    pop r12
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    ret
