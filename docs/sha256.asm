bits 64
; sha256Block(h, p, w): A = h (eight 64 bit slots holding 32 bit words), B = p (64 bytes), D = w (scratch, 64 32-bit words)
%macro RND 9
    mov eax, %5
    ror eax, 6
    mov ecx, %5
    ror ecx, 11
    xor eax, ecx
    mov ecx, %5
    ror ecx, 25
    xor eax, ecx
    mov ecx, %6
    xor ecx, %7
    and ecx, %5
    xor ecx, %7
    add eax, ecx
    add eax, %8
    add eax, [rsi + rbx*4 + 4*%9]
    add eax, [rdi + rbx*4 + 4*%9]
    add %4, eax
    mov ecx, %1
    ror ecx, 2
    mov edx, %1
    ror edx, 13
    xor ecx, edx
    mov edx, %1
    ror edx, 22
    xor ecx, edx
    mov edx, %1
    xor edx, %2
    mov ebp, %2
    xor ebp, %3
    and edx, ebp
    xor edx, %2
    add eax, ecx
    add eax, edx
    mov %8, eax
%endmacro
start:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    push rax                  ; the state pointer, at [rsp]
    mov rdi, rdx              ; w
    jmp L1
Ktab:
    dd 0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5
    dd 0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174
    dd 0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da
    dd 0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967
    dd 0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85
    dd 0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070
    dd 0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3
    dd 0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
L1:
    lea rsi, [rel Ktab]
    xor ebx, ebx
.load:
    mov eax, [rcx + rbx*4]
    bswap eax
    mov [rdi + rbx*4], eax
    inc ebx
    cmp ebx, 16
    jb .load
.sch:
    mov eax, [rdi + rbx*4 - 60]
    mov ecx, eax
    ror eax, 7
    mov edx, ecx
    ror edx, 18
    xor eax, edx
    shr ecx, 3
    xor eax, ecx
    mov ecx, [rdi + rbx*4 - 8]
    mov edx, ecx
    ror ecx, 17
    mov ebp, edx
    ror ebp, 19
    xor ecx, ebp
    shr edx, 10
    xor ecx, edx
    add eax, ecx
    add eax, [rdi + rbx*4 - 64]
    add eax, [rdi + rbx*4 - 28]
    mov [rdi + rbx*4], eax
    inc ebx
    cmp ebx, 64
    jb .sch
    mov rax, [rsp]
    mov r8d, [rax]
    mov r9d, [rax + 8]
    mov r10d, [rax + 16]
    mov r11d, [rax + 24]
    mov r12d, [rax + 32]
    mov r13d, [rax + 40]
    mov r14d, [rax + 48]
    mov r15d, [rax + 56]
    xor ebx, ebx
.rounds:
    RND r8d, r9d, r10d, r11d, r12d, r13d, r14d, r15d, 0
    RND r15d, r8d, r9d, r10d, r11d, r12d, r13d, r14d, 1
    RND r14d, r15d, r8d, r9d, r10d, r11d, r12d, r13d, 2
    RND r13d, r14d, r15d, r8d, r9d, r10d, r11d, r12d, 3
    RND r12d, r13d, r14d, r15d, r8d, r9d, r10d, r11d, 4
    RND r11d, r12d, r13d, r14d, r15d, r8d, r9d, r10d, 5
    RND r10d, r11d, r12d, r13d, r14d, r15d, r8d, r9d, 6
    RND r9d, r10d, r11d, r12d, r13d, r14d, r15d, r8d, 7
    add ebx, 8
    cmp ebx, 64
    jb .rounds
    mov rax, [rsp]
    mov ecx, [rax]
    add r8d, ecx
    mov [rax], r8
    mov ecx, [rax + 8]
    add r9d, ecx
    mov [rax + 8], r9
    mov ecx, [rax + 16]
    add r10d, ecx
    mov [rax + 16], r10
    mov ecx, [rax + 24]
    add r11d, ecx
    mov [rax + 24], r11
    mov ecx, [rax + 32]
    add r12d, ecx
    mov [rax + 32], r12
    mov ecx, [rax + 40]
    add r13d, ecx
    mov [rax + 40], r13
    mov ecx, [rax + 48]
    add r14d, ecx
    mov [rax + 48], r14
    mov ecx, [rax + 56]
    add r15d, ecx
    mov [rax + 56], r15
    pop rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
end:
