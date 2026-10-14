; =============================================================================
;  util.asm - error reporting, file I/O, buffers, emit helpers
; =============================================================================
section .text

; ---- process / output ---------------------------------------------------------
sys_exit:                       ; edi = exit code
    mov eax, SYS_EXIT_GROUP
    syscall

; rdi = cstring -> rax = length
cstrlen:
    xor eax, eax
.l: cmp byte [rdi+rax], 0
    je .d
    inc rax
    jmp .l
.d: ret

; print_cstr: edi = fd, rsi = cstring
print_cstr:
    push rdi
    push rsi
    mov rdi, rsi
    call cstrlen
    mov rdx, rax
    pop rsi
    pop rdi
    mov eax, SYS_WRITE
    syscall
    ret

; print_u64: edi = fd, rsi = value
print_u64:
    sub rsp, 32
    mov r8d, edi
    mov rax, rsi
    lea r9, [rsp+31]
    mov ecx, 10
.l: xor edx, edx
    div rcx
    add dl, '0'
    mov [r9], dl
    dec r9
    test rax, rax
    jnz .l
    inc r9
    lea rdx, [rsp+32]
    sub rdx, r9
    mov rsi, r9
    mov edi, r8d
    mov eax, SYS_WRITE
    syscall
    add rsp, 32
    ret

CSTR s_colon,   ":"
CSTR s_errsep,  ": error: "
CSTR s_acerr,   "ac: error: "
CSTR s_nl,      10
CSTR s_indent,  "  "

; fatal_error: edi = message (cstring). Prints
;     file:line: error: message
;       <the source line>
;       <caret under the offending token>
; and exits with status 1
fatal_error:
    mov [err_msg], rdi
    mov rsi, [cur_file_name]
    test rsi, rsi
    jz .nofile
    mov edi, 2
    call print_cstr
    mov esi, s_colon
    mov edi, 2
    call print_cstr
    mov rsi, [tk_line]
    mov edi, 2
    call print_u64
    mov esi, s_errsep
    jmp .msg
.nofile:
    mov esi, s_acerr
.msg:
    mov edi, 2
    call print_cstr
    mov rsi, [err_msg]
    mov edi, 2
    call print_cstr
    mov esi, s_nl
    mov edi, 2
    call print_cstr
    call print_source_line
    mov edi, 1
    jmp sys_exit

; print_source_line: shows the line of the current token and a caret below it
print_source_line:
    cmp qword [cur_file_name], 0
    je .ret
    mov rsi, [cur_src_base]
    test rsi, rsi
    jz .ret
    mov rcx, [tk_line]
    cmp rcx, 1
    jbe .found
.skip:
    mov al, [rsi]
    test al, al
    jz .ret
    inc rsi
    cmp al, 10
    jne .skip
    dec rcx
    cmp rcx, 1
    ja .skip
.found:
    ; rsi = start of the line
    mov r8, rsi
    xor edx, edx
.len:
    mov al, [rsi+rdx]
    test al, al
    jz .lend
    cmp al, 10
    je .lend
    inc rdx
    jmp .len
.lend:
    test rdx, rdx
    jz .ret
    push r8
    push rdx
    mov edi, 2
    mov esi, s_indent
    call print_cstr
    pop rdx
    pop rsi
    push rsi
    push rdx
    mov edi, 2
    mov eax, SYS_WRITE
    syscall
    mov edi, 2
    mov esi, s_nl
    call print_cstr
    pop rdx
    pop r8
    ; caret line: copy the line's leading whitespace (tabs) and use spaces elsewhere
    mov rax, [tk_start]
    sub rax, r8
    js .ret
    cmp rax, rdx
    ja .ret
    mov rdi, errbuf
    mov byte [rdi], ' '
    mov byte [rdi+1], ' '
    add rdi, 2
    xor ecx, ecx
.pad:
    cmp rcx, rax
    jae .caret
    mov bl, ' '
    cmp byte [r8+rcx], 9
    jne .pp
    mov bl, 9
.pp:
    mov [rdi], bl
    inc rdi
    inc rcx
    jmp .pad
.caret:
    mov byte [rdi], '^'
    mov byte [rdi+1], 10
    mov byte [rdi+2], 0
    mov edi, 2
    mov esi, errbuf
    call print_cstr
.ret:
    ret

; fatal_error with the identifier currently held in tk_ptr/tk_len appended:
; edi = message prefix (cstring), message becomes  "<prefix> 'name'"
fatal_error_tok:
    push rdi
    mov rdi, errbuf
    pop rsi
.c1: mov al, [rsi]
    test al, al
    jz .c2
    mov [rdi], al
    inc rdi
    inc rsi
    jmp .c1
.c2: mov byte [rdi], ' '
    mov byte [rdi+1], 0x27
    add rdi, 2
    mov rsi, [tk_ptr]
    mov ecx, [tk_len]
    cmp ecx, 200
    jbe .c3
    mov ecx, 200
.c3: test ecx, ecx
    jz .c4
    rep movsb
.c4: mov byte [rdi], 0x27
    mov byte [rdi+1], 0
    mov edi, errbuf
    jmp fatal_error

err_nested:
    ERR "source is nested too deeply"

err_toobig:
    ERR "program or compiler limit exceeded (too large)"

; ---- files ---------------------------------------------------------------------
; read_file: rdi = path (cstring) -> rax = pointer to NUL-terminated contents (0 on
; failure), rdx = size
read_file:
    push rbx
    push r12
    push r13
    xor esi, esi
    xor edx, edx
    mov eax, SYS_OPEN
    syscall
    test rax, rax
    js .fail
    mov r12, rax
    mov r13, arena
    add r13, [arena_pos]
    xor ebx, ebx
.rd:
    mov rax, [arena_pos]
    add rax, rbx
    add rax, (1<<20) + 64
    cmp rax, ARENA_MAX
    ja err_toobig
    mov rdi, r12
    lea rsi, [r13+rbx]
    mov edx, (1<<20)
    mov eax, SYS_READ
    syscall
    test rax, rax
    js .failc
    jz .eof
    add rbx, rax
    jmp .rd
.eof:
    mov rdi, r12
    mov eax, SYS_CLOSE
    syscall
    mov byte [r13+rbx], 0
    lea rax, [rbx+16]
    and rax, -16
    add [arena_pos], rax
    mov rax, r13
    mov rdx, rbx
    jmp .out
.failc:
    mov rdi, r12
    mov eax, SYS_CLOSE
    syscall
.fail:
    xor eax, eax
    xor edx, edx
.out:
    pop r13
    pop r12
    pop rbx
    ret

; write_file: rdi = path, rsi = buffer, rdx = length -> rax = 0 ok, -1 error
write_file:
    push r12
    push r13
    push r14
    mov r13, rsi
    mov r14, rdx
    mov esi, 0x241              ; O_WRONLY | O_CREAT | O_TRUNC
    mov edx, 0x1ED              ; 0755
    mov eax, SYS_OPEN
    syscall
    test rax, rax
    js .fail
    mov r12, rax
.wr:
    test r14, r14
    jz .done
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    mov eax, SYS_WRITE
    syscall
    test rax, rax
    jle .failc
    add r13, rax
    sub r14, rax
    jmp .wr
.done:
    mov rdi, r12
    mov esi, 0x1ED
    mov eax, SYS_FCHMOD
    syscall
    mov rdi, r12
    mov eax, SYS_CLOSE
    syscall
    xor eax, eax
    jmp .out
.failc:
    mov rdi, r12
    mov eax, SYS_CLOSE
    syscall
.fail:
    mov rax, -1
.out:
    pop r14
    pop r13
    pop r12
    ret

; ---- misc ------------------------------------------------------------------------
; arena_alloc: rdi = size -> rax = zeroed memory (never freed)
name_alloc:
    mov rax, [namepool_pos]
    lea rdx, [rax+rdi+1]
    cmp rdx, NAMEPOOL_MAX
    ja err_toobig
    mov [namepool_pos], rdx
    add rax, namepool
    ret

; ---- emit helpers (all preserve every register except flags) --------------------
; edi = byte
emit_b:
    push rax
    mov rax, [code_pos]
    cmp rax, CODE_MAX - 64
    jae err_toobig
    mov [code_buf+rax], dil
    inc rax
    mov [code_pos], rax
    pop rax
    ret

; edi = dword
emit_d:
    push rax
    mov rax, [code_pos]
    cmp rax, CODE_MAX - 64
    jae err_toobig
    mov [code_buf+rax], edi
    add rax, 4
    mov [code_pos], rax
    pop rax
    ret

; rdi = qword
emit_q:
    push rax
    mov rax, [code_pos]
    cmp rax, CODE_MAX - 64
    jae err_toobig
    mov [code_buf+rax], rdi
    add rax, 8
    mov [code_pos], rax
    pop rax
    ret

; rsi = bytes, ecx = count
emit_bytes:
    push rax
    push rdi
    push rcx
    push rsi
    push rdx
    mov rax, [code_pos]
    mov ecx, ecx
    lea rdx, [rax+rcx]
    cmp rdx, CODE_MAX - 64
    jae err_toobig
    mov [code_pos], rdx
    lea rdi, [code_buf+rax]
    rep movsb
    pop rdx
    pop rsi
    pop rcx
    pop rdi
    pop rax
    ret

; add_reloc: edi = position, esi = kind, edx = target
add_reloc:
    push rax
    mov eax, [rel_count]
    cmp eax, REL_MAX
    jae err_toobig
    inc dword [rel_count]
    shl rax, 4
    mov [rel_buf+rax], edi
    mov [rel_buf+rax+4], esi
    mov [rel_buf+rax+8], edx
    push rcx
    mov ecx, [ext_reloc_sym]            ; object mode: the relocation names an external global
    mov [rel_buf+rax+12], ecx
    mov dword [ext_reloc_sym], 0
    pop rcx
    pop rax
    ret

; patch_here: rdi = chain head value; patches to current code position
patch_here:
    push rsi
    mov rsi, [code_pos]
    mov [last_label], rsi
    CG patch_chain
    pop rsi
    ret

; ---- data / bss allocation of the compiled program -------------------------------
; data_alloc: rdi = size, esi = alignment -> rax = offset in data section
data_alloc:
    mov rax, [data_pos]
    lea rcx, [rsi-1]
    add rax, rcx
    not rcx
    and rax, rcx
    lea rdx, [rax+rdi]
    cmp rdx, DATA_MAX
    ja err_toobig
    mov [data_pos], rdx
    ret

; bss_alloc: rdi = size, esi = alignment -> rax = offset in bss
bss_alloc:
    mov rax, [bss_pos]
    lea rcx, [rsi-1]
    add rax, rcx
    not rcx
    and rax, rcx
    lea rdx, [rax+rdi]
    cmp rdx, BSS_LIMIT
    ja err_toobig
    mov [bss_pos], rdx
    ret

; data_add_string: rsi = bytes, rdx = length -> rax = data offset (NUL terminated)
data_add_string:
    push rdi
    push rcx
    push rsi
    push rdx
    lea rdi, [rdx+1]
    mov esi, 1
    call data_alloc
    pop rdx
    pop rsi
    push rax
    lea rdi, [data_buf+rax]
    mov rcx, rdx
    rep movsb
    mov byte [rdi], 0
    pop rax
    pop rcx
    pop rdi
    ret

; names_eq: rdi, esi = name 1 ; rdx, ecx = name 2 -> eax = 1 if equal
names_eq:
    cmp esi, ecx
    jne .no
    push rdi
    push rsi
    push rdx
    mov esi, esi
    mov rcx, rsi
    mov rsi, rdx
    repe cmpsb
    pop rdx
    pop rsi
    pop rdi
    jne .no
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret
