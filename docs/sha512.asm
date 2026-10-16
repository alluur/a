bits 64
; sha512Block(h, p, w): A = h (eight 64 bit words), B = p (128 bytes), D = w (scratch, 80 64-bit words)
%macro RND 9
    mov rax, %5
    ror rax, 14
    mov rcx, %5
    ror rcx, 18
    xor rax, rcx
    mov rcx, %5
    ror rcx, 41
    xor rax, rcx
    mov rcx, %6
    xor rcx, %7
    and rcx, %5
    xor rcx, %7
    add rax, rcx
    add rax, %8
    add rax, [rsi + rbx*8 + 8*%9]
    add rax, [rdi + rbx*8 + 8*%9]
    add %4, rax
    mov rcx, %1
    ror rcx, 28
    mov rdx, %1
    ror rdx, 34
    xor rcx, rdx
    mov rdx, %1
    ror rdx, 39
    xor rcx, rdx
    mov rdx, %1
    xor rdx, %2
    mov rbp, %2
    xor rbp, %3
    and rdx, rbp
    xor rdx, %2
    add rax, rcx
    add rax, rdx
    mov %8, rax
%endmacro
start:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    push rax
    mov rdi, rdx
    jmp L1
Ktab:
    dq 0x428A2F98D728AE22, 0x7137449123EF65CD, 0xB5C0FBCFEC4D3B2F, 0xE9B5DBA58189DBBC
    dq 0x3956C25BF348B538, 0x59F111F1B605D019, 0x923F82A4AF194F9B, 0xAB1C5ED5DA6D8118
    dq 0xD807AA98A3030242, 0x12835B0145706FBE, 0x243185BE4EE4B28C, 0x550C7DC3D5FFB4E2
    dq 0x72BE5D74F27B896F, 0x80DEB1FE3B1696B1, 0x9BDC06A725C71235, 0xC19BF174CF692694
    dq 0xE49B69C19EF14AD2, 0xEFBE4786384F25E3, 0x0FC19DC68B8CD5B5, 0x240CA1CC77AC9C65
    dq 0x2DE92C6F592B0275, 0x4A7484AA6EA6E483, 0x5CB0A9DCBD41FBD4, 0x76F988DA831153B5
    dq 0x983E5152EE66DFAB, 0xA831C66D2DB43210, 0xB00327C898FB213F, 0xBF597FC7BEEF0EE4
    dq 0xC6E00BF33DA88FC2, 0xD5A79147930AA725, 0x06CA6351E003826F, 0x142929670A0E6E70
    dq 0x27B70A8546D22FFC, 0x2E1B21385C26C926, 0x4D2C6DFC5AC42AED, 0x53380D139D95B3DF
    dq 0x650A73548BAF63DE, 0x766A0ABB3C77B2A8, 0x81C2C92E47EDAEE6, 0x92722C851482353B
    dq 0xA2BFE8A14CF10364, 0xA81A664BBC423001, 0xC24B8B70D0F89791, 0xC76C51A30654BE30
    dq 0xD192E819D6EF5218, 0xD69906245565A910, 0xF40E35855771202A, 0x106AA07032BBD1B8
    dq 0x19A4C116B8D2D0C8, 0x1E376C085141AB53, 0x2748774CDF8EEB99, 0x34B0BCB5E19B48A8
    dq 0x391C0CB3C5C95A63, 0x4ED8AA4AE3418ACB, 0x5B9CCA4F7763E373, 0x682E6FF3D6B2B8A3
    dq 0x748F82EE5DEFB2FC, 0x78A5636F43172F60, 0x84C87814A1F0AB72, 0x8CC702081A6439EC
    dq 0x90BEFFFA23631E28, 0xA4506CEBDE82BDE9, 0xBEF9A3F7B2C67915, 0xC67178F2E372532B
    dq 0xCA273ECEEA26619C, 0xD186B8C721C0C207, 0xEADA7DD6CDE0EB1E, 0xF57D4F7FEE6ED178
    dq 0x06F067AA72176FBA, 0x0A637DC5A2C898A6, 0x113F9804BEF90DAE, 0x1B710B35131C471B
    dq 0x28DB77F523047D84, 0x32CAAB7B40C72493, 0x3C9EBE0A15C9BEBC, 0x431D67C49C100D4C
    dq 0x4CC5D4BECB3E42B6, 0x597F299CFC657E2A, 0x5FCB6FAB3AD6FAEC, 0x6C44198C4A475817
L1:
    lea rsi, [rel Ktab]
    xor ebx, ebx
.load:
    mov rax, [rcx + rbx*8]
    bswap rax
    mov [rdi + rbx*8], rax
    inc ebx
    cmp ebx, 16
    jb .load
.sch:
    mov rax, [rdi + rbx*8 - 120]
    mov rcx, rax
    ror rax, 1
    mov rdx, rcx
    ror rdx, 8
    xor rax, rdx
    shr rcx, 7
    xor rax, rcx
    mov rcx, [rdi + rbx*8 - 16]
    mov rdx, rcx
    ror rcx, 19
    mov rbp, rdx
    ror rbp, 61
    xor rcx, rbp
    shr rdx, 6
    xor rcx, rdx
    add rax, rcx
    add rax, [rdi + rbx*8 - 128]
    add rax, [rdi + rbx*8 - 56]
    mov [rdi + rbx*8], rax
    inc ebx
    cmp ebx, 80
    jb .sch
    mov rax, [rsp]
    mov r8, [rax]
    mov r9, [rax + 8]
    mov r10, [rax + 16]
    mov r11, [rax + 24]
    mov r12, [rax + 32]
    mov r13, [rax + 40]
    mov r14, [rax + 48]
    mov r15, [rax + 56]
    xor ebx, ebx
.rounds:
    RND r8, r9, r10, r11, r12, r13, r14, r15, 0
    RND r15, r8, r9, r10, r11, r12, r13, r14, 1
    RND r14, r15, r8, r9, r10, r11, r12, r13, 2
    RND r13, r14, r15, r8, r9, r10, r11, r12, 3
    RND r12, r13, r14, r15, r8, r9, r10, r11, 4
    RND r11, r12, r13, r14, r15, r8, r9, r10, 5
    RND r10, r11, r12, r13, r14, r15, r8, r9, 6
    RND r9, r10, r11, r12, r13, r14, r15, r8, 7
    add ebx, 8
    cmp ebx, 80
    jb .rounds
    mov rax, [rsp]
    add [rax], r8
    add [rax + 8], r9
    add [rax + 16], r10
    add [rax + 24], r11
    add [rax + 32], r12
    add [rax + 40], r13
    add [rax + 48], r14
    add [rax + 56], r15
    pop rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
end:
