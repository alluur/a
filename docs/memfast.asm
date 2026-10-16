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
; ---- strlen: A = s. Eight bytes at a time (aligned loads never cross a page; no SSE, so it also runs where the kernel has not
; enabled the vector unit, e.g. AOS processes). A byte is zero where (x - 0x01..01) & ~x & 0x80..80 has its high bit set.
strlen_start:
    mov rsi, rax
    mov rdi, rax
    and rdi, -8
    mov r10, 0x0101010101010101
    mov r11, 0x8080808080808080
    mov r8, [rdi]
    mov ecx, esi
    and ecx, 7
    shl ecx, 3
    mov r9, 1
    shl r9, cl
    dec r9                  ; the bytes before s become 0xFF so they cannot look like the end
    or r8, r9
.loop:
    mov rax, r8
    sub rax, r10
    mov r9, r8
    not r9
    and rax, r9
    and rax, r11
    jnz .found
    add rdi, 8
    mov r8, [rdi]
    jmp .loop
.found:
    bsf rax, rax
    shr rax, 3
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
