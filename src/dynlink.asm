; =============================================================================
;  dynlink.asm - dynamic linking of C libraries (extern "library" declarations)
;
;  ELF: a program with used C imports gets PT_PHDR, PT_INTERP and PT_DYNAMIC: DT_NEEDED for every library, a symbol table
;  with the imported functions, a trivial hash table and one relocation per import that makes the dynamic linker store the
;  function's address in the import's pointer slot (8 bytes each, after the data). The weak import "exit" fills std's
;  __cexit, so that A's exit() also runs the C library's exit (stdio buffers are flushed).
; =============================================================================
section .text

; dyn_prepare: decides whether the output is dynamically linked ([dyn_on]), numbers the used imports (imp_slot), reserves
; their pointer slots after the data and turns the R_IMPORT relocations into R_DATA ones. Windows: see build_pe.
dyn_prepare:
    push rbx
    push r12
    mov dword [dyn_on], 0
    mov dword [dyn_nimp], 0
    mov qword [dyn_cexit], 0
    xor ecx, ecx
.lu:
    cmp ecx, LIB_MAX
    jae .lu_done
    mov dword [lib_used + rcx*4], 0
    inc ecx
    jmp .lu
.lu_done:
    xor ecx, ecx
.l: cmp ecx, [imp_count]
    jae .ld
    mov dword [imp_slot + rcx*4], -1
    mov eax, [imp_sym + rcx*4]
    shl rax, 6
    test dword [symtab + rax + SYM_FLAGS], F_USED
    jz .n
    mov eax, [dyn_nimp]
    mov [imp_slot + rcx*4], eax
    inc dword [dyn_nimp]
    mov eax, [imp_lib + rcx*4]
    mov dword [lib_used + rax*4], 1
.n: inc ecx
    jmp .l
.ld:
    cmp dword [dyn_nimp], 0
    je .out
    mov dword [dyn_on], 1
    cmp dword [target], TGT_WINDOWS
    je .out                             ; (build_pe places the slots in its import table)
    cmp dword [target], TGT_ANDROID
    jne .notandroid
    mov qword [cur_file_name], 0
    mov edi, s_err_android_dyn
    call fatal_error
.notandroid:
    ; std's __cexit: a C function pointer that the weak import of exit fills
    mov rdi, s_cexit_name
    mov esi, 7
    xor edx, edx
    call sym_find_global
    test rax, rax
    jz .nocexit
    test dword [rax+SYM_FLAGS], F_CFUNC
    jz .nocexit
    test dword [rax+SYM_FLAGS], F_CIMPORT
    jnz .nocexit
    mov [dyn_cexit], rax
.nocexit:
    mov edi, [dyn_nimp]
    shl edi, 3
    mov esi, 8
    call data_alloc_zero
    mov [dyn_slots], rax
    ; R_IMPORT (import index) -> R_DATA (its slot)
    xor ecx, ecx
.r: cmp ecx, [rel_count]
    jae .out
    mov rax, rcx
    shl rax, 4
    add rax, rel_buf
    cmp dword [rax+4], R_IMPORT
    jne .rn
    mov edx, [rax+8]
    mov edx, [imp_slot + rdx*4]
    cmp edx, -1
    jne .rok
    ERR "internal error: an unused C import is referenced"
.rok:
    shl edx, 3
    add rdx, [dyn_slots]
    mov dword [rax+4], R_DATA
    mov [rax+8], edx
.rn:
    inc ecx
    jmp .r
.out:
    pop r12
    pop rbx
    ret

; data_alloc_zero: like data_alloc (rdi = size, esi = alignment -> rax = offset), and the space is cleared (the data buffer
; beyond data_pos may hold bytes of an earlier pass)
data_alloc_zero:
    push rdi
    call data_alloc
    pop rcx
    push rax
    lea rdi, [data_buf + rax]
    xor eax, eax
    rep stosb
    pop rax
    ret

; dyn_str: rsi = text, ecx = length -> eax = its offset in the dynamic string table (appended, NUL terminated)
dyn_str:
    push rdi
    push rcx
    mov eax, [dyn_strsz]
    lea rdi, [dyn_strtab + rax]
    lea edx, [eax + ecx + 1]
    cmp edx, DYN_STR_MAX
    jae err_toobig
    rep movsb
    mov byte [rdi], 0
    mov [dyn_strsz], edx
    pop rcx
    pop rdi
    ret

; dyn_build: ELF only, after dyn_prepare and once [data_vaddr] is known. Appends the dynamic string table, symbol table, hash
; table, relocations and the dynamic section to the data and sets dyn_off / dyn_size (the PT_DYNAMIC part of the data).
dyn_build:
    push rbx
    push r12
    push r13
    push r14
    push r15
    ; strings: "", the libraries, the symbols
    mov dword [dyn_strsz], 1
    mov byte [dyn_strtab], 0
    xor ebx, ebx
.libs:
    cmp ebx, [lib_count]
    jae .libs_done
    cmp dword [lib_used + rbx*4], 0
    je .lnext
    mov eax, [lib_off + rbx*4]
    lea rdi, [lib_names + rax]
    call cstrlen
    mov ecx, eax
    mov eax, [lib_off + rbx*4]
    lea rsi, [lib_names + rax]
    call dyn_str
    mov [dyn_libstr + rbx*4], eax
.lnext:
    inc ebx
    jmp .libs
.libs_done:
    ; the symbol table: index 0 is the null symbol, then the used imports in slot order, then exit (weak) for __cexit
    mov r12d, [dyn_nimp]
    inc r12d                            ; symbols
    cmp qword [dyn_cexit], 0
    je .ns
    inc r12d
.ns:
    lea edi, [r12 + r12*2]
    shl edi, 3                          ; 24 bytes each
    mov esi, 8
    call data_alloc_zero
    mov [dyn_symoff], rax
    xor ecx, ecx
.sl:
    cmp ecx, [imp_count]
    jae .sdone
    mov eax, [imp_slot + rcx*4]
    cmp eax, -1
    je .snext
    inc eax                             ; symbol index = slot + 1
    lea rdx, [rax + rax*2]
    shl rdx, 3
    add rdx, [dyn_symoff]
    lea r13, [data_buf + rdx]
    mov eax, [imp_sym + rcx*4]
    shl rax, 6
    mov rsi, [symtab + rax + SYM_NAME]
    push rcx
    mov ecx, [symtab + rax + SYM_NLEN]
    call dyn_str
    pop rcx
    mov [r13], eax                      ; st_name
    mov byte [r13+4], 0x12              ; STB_GLOBAL, STT_FUNC
.snext:
    inc ecx
    jmp .sl
.sdone:
    cmp qword [dyn_cexit], 0
    je .hash
    mov eax, [dyn_nimp]
    inc eax
    lea rdx, [rax + rax*2]
    shl rdx, 3
    add rdx, [dyn_symoff]
    lea r13, [data_buf + rdx]
    mov rsi, s_exit_name
    mov ecx, 4
    call dyn_str
    mov [r13], eax
    mov byte [r13+4], 0x22              ; STB_WEAK, STT_FUNC
.hash:
    ; DT_HASH: one empty bucket (nothing is exported), nchain = number of symbols
    lea edi, [r12*4 + 8]
    mov esi, 8
    call data_alloc_zero
    mov [dyn_hashoff], rax
    mov dword [data_buf + rax], 1
    mov [data_buf + rax + 4], r12d
    ; relocations: one per symbol (not the null one)
    lea r14d, [r12 - 1]
    lea edi, [r14 + r14*2]
    shl edi, 3
    mov esi, 8
    call data_alloc_zero
    mov [dyn_relaoff], rax
    mov r15, rax
    mov eax, R_X86_64_GLOB_DAT
    cmp dword [arch], ARCH_A64
    jne .t1
    mov eax, R_AARCH64_GLOB_DAT
.t1:
    cmp dword [arch], ARCH_RV64
    jne .t2
    mov eax, R_RISCV_64
.t2:
    cmp dword [arch], ARCH_LA64
    jne .t3
    mov eax, R_LARCH_64
.t3:
    mov ebx, eax                        ; relocation type
    xor ecx, ecx                        ; symbol - 1
.rl:
    cmp ecx, r14d
    jae .rdone
    mov rax, rcx
    shl rax, 3
    add rax, [dyn_slots]                ; the slot of import ecx (slot order = symbol order)
    cmp ecx, [dyn_nimp]
    jb .rslot
    mov rax, [dyn_cexit]
    mov rax, [rax+SYM_VAL]              ; exit -> __cexit's slot
.rslot:
    add rax, [data_vaddr]
    lea rdx, [rcx + rcx*2]
    shl rdx, 3
    add rdx, r15
    mov [data_buf + rdx], rax           ; r_offset
    lea rax, [rcx + 1]
    shl rax, 32
    or rax, rbx
    mov [data_buf + rdx + 8], rax       ; r_info
    mov qword [data_buf + rdx + 16], 0  ; r_addend
    inc ecx
    jmp .rl
.rdone:
    ; the string table itself
    mov edi, [dyn_strsz]
    mov esi, 8
    call data_alloc_zero
    mov [dyn_stroff], rax
    lea rdi, [data_buf + rax]
    mov rsi, dyn_strtab
    mov ecx, [dyn_strsz]
    rep movsb
    ; the dynamic section
    mov edi, (DYN_ENTRIES_FIXED + LIB_MAX) * 16
    mov esi, 8
    call data_alloc_zero
    mov [dyn_off], rax
    lea r13, [data_buf + rax]
    xor ebx, ebx
.dn:
    cmp ebx, [lib_count]
    jae .dfix
    cmp dword [lib_used + rbx*4], 0
    je .dnn
    mov qword [r13], 1                  ; DT_NEEDED
    mov eax, [dyn_libstr + rbx*4]
    mov [r13+8], rax
    add r13, 16
.dnn:
    inc ebx
    jmp .dn
.dfix:
    mov rdi, [data_vaddr]
    mov qword [r13], 4                  ; DT_HASH
    mov rax, [dyn_hashoff]
    add rax, rdi
    mov [r13+8], rax
    mov qword [r13+16], 5               ; DT_STRTAB
    mov rax, [dyn_stroff]
    add rax, rdi
    mov [r13+24], rax
    mov qword [r13+32], 6               ; DT_SYMTAB
    mov rax, [dyn_symoff]
    add rax, rdi
    mov [r13+40], rax
    mov qword [r13+48], 10              ; DT_STRSZ
    mov eax, [dyn_strsz]
    mov [r13+56], rax
    mov qword [r13+64], 11              ; DT_SYMENT
    mov qword [r13+72], 24
    mov qword [r13+80], 7               ; DT_RELA
    mov rax, [dyn_relaoff]
    add rax, rdi
    mov [r13+88], rax
    mov qword [r13+96], 8               ; DT_RELASZ
    lea rax, [r14 + r14*2]
    shl rax, 3
    mov [r13+104], rax
    mov qword [r13+112], 9              ; DT_RELAENT
    mov qword [r13+120], 24
    mov qword [r13+128], 30             ; DT_FLAGS: DF_BIND_NOW
    mov qword [r13+136], 8
    mov qword [r13+144], 21             ; DT_DEBUG
    mov qword [r13+152], 0
    mov qword [r13+160], 0              ; DT_NULL
    mov qword [r13+168], 0
    add r13, 176
    lea rax, [data_buf]
    add rax, [dyn_off]
    sub r13, rax
    mov [dyn_size], r13
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; dyn_interp: -> rsi = the program interpreter of the target (the dynamic linker), ecx = length with the NUL
dyn_interp:
    mov rsi, s_interp_x64
    mov ecx, s_interp_x64_end - s_interp_x64
    cmp dword [arch], ARCH_A64
    jne .1
    mov rsi, s_interp_a64
    mov ecx, s_interp_a64_end - s_interp_a64
.1: cmp dword [arch], ARCH_RV64
    jne .2
    mov rsi, s_interp_rv
    mov ecx, s_interp_rv_end - s_interp_rv
.2: cmp dword [arch], ARCH_LA64
    jne .3
    mov rsi, s_interp_la
    mov ecx, s_interp_la_end - s_interp_la
.3: ret

section .rodata
s_cexit_name:   db "__cexit", 0
s_err_android_dyn: db "extern 'library' functions need dynamic linking, which Android executables do not support yet (use dlopen through a shared library, or the Linux targets)", 0
s_interp_x64:   db "/lib64/ld-linux-x86-64.so.2", 0
s_interp_x64_end:
s_interp_a64:   db "/lib/ld-linux-aarch64.so.1", 0
s_interp_a64_end:
s_interp_rv:    db "/lib/ld-linux-riscv64-lp64d.so.1", 0
s_interp_rv_end:
s_interp_la:    db "/lib64/ld-linux-loongarch-lp64d.so.1", 0
s_interp_la_end:

section .bss
dyn_on:         resd 1
dyn_nimp:       resd 1
dyn_cexit:      resq 1
dyn_slots:      resq 1
dyn_strsz:      resd 1
dyn_strtab:     resb DYN_STR_MAX
dyn_libstr:     resd LIB_MAX
dyn_symoff:     resq 1
dyn_hashoff:    resq 1
dyn_relaoff:    resq 1
dyn_stroff:     resq 1
dyn_off:        resq 1
dyn_size:       resq 1
section .text

; ---- Windows: the libraries of extern "library" declarations in the PE import table --------------------------------------------
; pe_prepare: numbers the used C imports by library after the built-in IAT slots (each library's slots end with a null one),
; turns their R_IMPORT relocations into R_IAT ones and sets the import section layout (pe_ilt, pe_iat, pe_names, pe_total).
pe_prepare:
    push rbx
    push r12
    call dyn_prepare                        ; (marks the used imports and libraries)
    mov dword [pe_nuser], 0
    mov r12d, IAT_SLOTS                     ; next slot
    xor ebx, ebx
.lib:
    cmp ebx, [lib_count]
    jae .libs_done
    cmp dword [lib_used + rbx*4], 0
    je .lnext
    inc dword [pe_nuser]
    mov [lib_first + rbx*4], r12d
    xor ecx, ecx
.imp:
    cmp ecx, [imp_count]
    jae .impd
    cmp [imp_lib + rcx*4], ebx
    jne .inext
    cmp dword [imp_slot + rcx*4], -1
    je .inext
    mov [imp_slot + rcx*4], r12d
    inc r12d
.inext:
    inc ecx
    jmp .imp
.impd:
    inc r12d                                ; the null slot that ends this library's thunks
.lnext:
    inc ebx
    jmp .lib
.libs_done:
    mov [pe_total], r12d
    ; R_IMPORT (import index) -> R_IAT (slot)
    xor ecx, ecx
.r: cmp ecx, [rel_count]
    jae .layout
    mov rax, rcx
    shl rax, 4
    add rax, rel_buf
    cmp dword [rax+4], R_IMPORT
    jne .rn
    mov edx, [rax+8]
    mov edx, [imp_slot + rdx*4]
    mov dword [rax+4], R_IAT
    mov [rax+8], edx
.rn:
    inc ecx
    jmp .r
.layout:
    mov eax, [pe_nuser]
    add eax, 6                              ; 5 built-in descriptors, the user ones, the null one
    imul eax, 20
    add eax, 7
    and eax, -8
    mov [pe_ilt], rax
    mov ecx, [pe_total]
    shl ecx, 3
    add rax, rcx
    mov [pe_iat], rax
    add rax, rcx
    mov [pe_names], rax
    pop r12
    pop rbx
    ret

; pe_user_idata: (inside build_idata) rbx = section RVA, r12 = offset of the free name area -> writes the descriptors, DLL names,
; hint/name entries and thunks of the used libraries; advances r12
pe_user_idata:
    push r13
    push r14
    push r15
    xor r13d, r13d                          ; library
    mov r14d, 5                             ; descriptor
.lib:
    cmp r13d, [lib_count]
    jae .done
    cmp dword [lib_used + r13*4], 0
    je .lnext
    ; the DLL name
    mov eax, [lib_off + r13*4]
    lea rsi, [lib_names + rax]
    lea rdi, [idata_buf + r12]
    mov r15, r12
    call cstr_copy
    sub rdi, idata_buf
    lea r12, [rdi + 2]
    and r12, -2
    ; the descriptor
    imul eax, r14d, 20
    lea rdi, [idata_buf + rax]
    mov ecx, [lib_first + r13*4]
    shl ecx, 3
    mov rax, [pe_ilt]
    add rax, rcx
    add rax, rbx
    mov [rdi], eax                          ; OriginalFirstThunk
    lea rax, [rbx + r15]
    mov [rdi+12], eax                       ; Name
    mov rax, [pe_iat]
    add rax, rcx
    add rax, rbx
    mov [rdi+16], eax                       ; FirstThunk
    ; the functions: hint / name entries and their thunks
    xor ecx, ecx
.imp:
    cmp ecx, [imp_count]
    jae .impd
    cmp [imp_lib + rcx*4], r13d
    jne .inext
    mov edx, [imp_slot + rcx*4]
    cmp edx, -1
    je .inext
    lea rax, [rbx + r12]                    ; RVA of the hint / name entry
    mov rdi, [pe_ilt]
    lea rdi, [idata_buf + rdi + rdx*8]
    mov [rdi], rax
    mov rdi, [pe_iat]
    lea rdi, [idata_buf + rdi + rdx*8]
    mov [rdi], rax
    mov word [idata_buf + r12], 0           ; hint
    mov eax, [imp_sym + rcx*4]
    shl rax, 6
    mov rsi, [symtab + rax + SYM_NAME]
    mov edx, [symtab + rax + SYM_NLEN]
    lea rdi, [idata_buf + r12 + 2]
    push rcx
    mov ecx, edx
    rep movsb
    pop rcx
    mov byte [rdi], 0
    sub rdi, idata_buf
    lea r12, [rdi + 2]
    and r12, -2
.inext:
    inc ecx
    jmp .imp
.impd:
    inc r14d
.lnext:
    inc r13d
    jmp .lib
.done:
    pop r15
    pop r14
    pop r13
    ret

section .bss
pe_nuser:       resd 1
pe_total:       resd 1
pe_ilt:         resq 1
pe_iat:         resq 1
pe_names:       resq 1
lib_first:      resd LIB_MAX
section .text
