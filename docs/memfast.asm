bits 64
; ---- memcpy: A = dst, B = src, D = n
memcpy_start:
    mov rdi, rax
    mov rsi, rcx
    mov rcx, rdx
    test rcx, rcx
    jle .done
    cmp rcx, 32
    jae .big
.small:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rcx
    jnz .small
    jmp .done
.big:
    rep movsb
.done:
memcpy_end:
; ---- memset: A = dst, B = value, D = n
memset_start:
    mov rdi, rax
    mov rax, rcx
    mov rcx, rdx
    test rcx, rcx
    jle .done
    cmp rcx, 32
    jae .big
.small:
    mov [rdi], al
    inc rdi
    dec rcx
    jnz .small
    jmp .done
.big:
    rep stosb
.done:
memset_end:
; ---- strlen: A = s
strlen_start:
    mov rsi, rax
    mov rdi, rax
    and rdi, -16
    pxor xmm0, xmm0
    movdqa xmm1, [rdi]
    pcmpeqb xmm1, xmm0
    pmovmskb eax, xmm1
    mov ecx, esi
    and ecx, 15
    shr eax, cl
    test eax, eax
    jz .loop
    bsf eax, eax
    jmp .done
.loop:
    add rdi, 16
    movdqa xmm1, [rdi]
    pcmpeqb xmm1, xmm0
    pmovmskb eax, xmm1
    test eax, eax
    jz .loop
    bsf eax, eax
    add rax, rdi
    sub rax, rsi
.done:
strlen_end:
; ---- memset64: A = dst, B = value, D = count of 8 byte words
fill64_start:
    mov rdi, rax
    mov rax, rcx
    mov rcx, rdx
    test rcx, rcx
    jle .done
    rep stosq
.done:
fill64_end:
; ---- memcmp-free equality helper none
