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
    mov dword [dyn_nexp], 0
    mov dword [dyn_nrel], 0
    cmp dword [shared_mode], 0
    je .exe
    ; a shared library: the extern "C" functions are exported (by their C entries), the absolute addresses in the data
    ; get RELATIVE relocations
    mov dword [dyn_on], 1
    xor ecx, ecx
.ex:
    cmp ecx, [sym_count]
    jae .exd
    mov rax, rcx
    shl rax, 6
    cmp dword [symtab + rax + SYM_KIND], S_FUNC
    jne .exn
    test dword [symtab + rax + SYM_FLAGS], F_CEXPORT
    jz .exn
    test dword [symtab + rax + SYM_FLAGS], F_USED
    jz .exn
    mov edx, [dyn_nexp]
    cmp edx, IMP_MAX
    jae err_toobig
    mov [exp_sym + rdx*4], ecx
    inc dword [dyn_nexp]
.exn:
    inc ecx
    jmp .ex
.exd:
    xor ecx, ecx
.rc:
    cmp ecx, [rel_count]
    jae .exe
    mov rax, rcx
    shl rax, 4
    mov eax, [rel_buf + rax + 4]
    cmp eax, R_DATA64
    je .rcy
    cmp eax, R_CODE64
    jne .rcn
.rcy:
    inc dword [dyn_nrel]
.rcn:
    inc ecx
    jmp .rc
.exe:
    cmp dword [dyn_nimp], 0
    jne .dyn
    cmp dword [shared_mode], 0
    je .out
.dyn:
    mov dword [dyn_on], 1
    cmp dword [target], TGT_WINDOWS
    je .out                             ; (build_pe places the slots in its import table)
    cmp dword [shared_mode], 0
    jne .notandroid                     ; (a shared library is fine on Android)
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
    add r12d, [dyn_nexp]
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
    ; the exports (a shared library): defined symbols whose value is the address of the C entry
    xor ecx, ecx
.xl:
    cmp ecx, [dyn_nexp]
    jae .xd
    mov eax, r12d
    sub eax, [dyn_nexp]
    add eax, ecx                        ; symbol index
    lea rdx, [rax + rax*2]
    shl rdx, 3
    add rdx, [dyn_symoff]
    lea r13, [data_buf + rdx]
    mov eax, [exp_sym + rcx*4]
    mov edx, [sym_cthunk + rax*4]
    shl rax, 6
    mov rsi, [symtab + rax + SYM_NAME]
    push rcx
    push rdx
    mov ecx, [symtab + rax + SYM_NLEN]
    call dyn_str
    pop rdx
    pop rcx
    mov [r13], eax                      ; st_name
    mov byte [r13+4], 0x12              ; STB_GLOBAL, STT_FUNC
    mov word [r13+6], 1                 ; st_shndx: .text
    shl rdx, 6
    mov rax, [symtab + rdx + SYM_VAL]
    add rax, [code_vaddr]
    mov [r13+8], rax                    ; st_value
    inc ecx
    jmp .xl
.xd:
    ; DT_HASH over all the symbols (nbucket = nchain = number of symbols)
    lea edi, [r12*8 + 8]
    mov esi, 8
    call data_alloc_zero
    mov [dyn_hashoff], rax
    mov [data_buf + rax], r12d
    mov [data_buf + rax + 4], r12d
    lea r15, [data_buf + rax + 8]       ; buckets; the chains follow
    lea r13, [r15 + r12*4]
    mov ecx, 1
.hl:
    cmp ecx, r12d
    jae .hd
    lea rdx, [rcx + rcx*2]
    shl rdx, 3
    add rdx, [dyn_symoff]
    mov eax, [data_buf + rdx]           ; st_name
    lea rsi, [dyn_strtab + rax]
    call elf_hash
    xor edx, edx
    div r12d                            ; edx = bucket
    mov eax, [r15 + rdx*4]
    mov [r13 + rcx*4], eax              ; chain[i] = old head
    mov [r15 + rdx*4], ecx              ; bucket = i
    inc ecx
    jmp .hl
.hd:
    ; relocations: one per imported symbol (+ exit), then the RELATIVE ones (filled by dyn_relative)
    lea r14d, [r12 - 1]
    sub r14d, [dyn_nexp]
    mov eax, r14d
    add eax, [dyn_nrel]
    lea edi, [rax + rax*2]
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
    cmp dword [shared_mode], 0
    je .nosoname
    call choose_outname                 ; DT_SONAME: the file name of the library
    mov rsi, rax
.sb:
    mov dl, [rax]
    test dl, dl
    jz .sbd
    inc rax
    cmp dl, '/'
    jne .sb
    mov rsi, rax
    jmp .sb
.sbd:
    mov rdi, rsi
    call cstrlen
    mov ecx, eax
    call dyn_str
    mov [dyn_soname], eax
.nosoname:
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
    mov eax, r14d
    add eax, [dyn_nrel]
    lea rax, [rax + rax*2]
    shl rax, 3
    mov [r13+104], rax                  ; (DT_RELASZ with the RELATIVE relocations)
    add r13, 160
    cmp dword [shared_mode], 0
    je .dnull
    mov qword [r13], 14                 ; DT_SONAME
    mov eax, [dyn_soname]
    mov [r13+8], rax
    add r13, 16
.dnull:
    mov qword [r13], 0                  ; DT_NULL
    mov qword [r13+8], 0
    add r13, 16
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
dyn_nexp:       resd 1
dyn_nrel:       resd 1
dyn_soname:     resd 1
dyn_data_end:   resq 1
exp_sym:        resd IMP_MAX
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

; elf_hash: rsi = NUL terminated name -> eax = the SysV ELF hash
elf_hash:
    xor eax, eax
.l: movzx edx, byte [rsi]
    test edx, edx
    jz .d
    shl eax, 4
    add eax, edx
    mov edx, eax
    and edx, 0xF0000000
    jz .n
    mov r8d, edx
    shr r8d, 24
    xor eax, r8d
    not edx
    and eax, edx
.n: inc rsi
    jmp .l
.d: ret

; shared_roots: (emit_prologue of a shared library) the extern "C" functions and their C entries are the roots of the program
shared_roots:
    push rbx
    xor ebx, ebx
.l: cmp ebx, [sym_count]
    jae .d
    mov rax, rbx
    shl rax, 6
    cmp dword [symtab + rax + SYM_KIND], S_FUNC
    jne .n
    test dword [symtab + rax + SYM_FLAGS], F_CEXPORT
    jz .n
    lea rdi, [symtab + rax]
    call record_edge
    mov eax, [sym_cthunk + rbx*4]
    shl rax, 6
    lea rdi, [symtab + rax]
    call record_edge
.n: inc ebx
    jmp .l
.d: pop rbx
    ret

; dyn_relative: (a shared library, after apply_relocs) a RELATIVE relocation for every absolute address in the data
dyn_relative:
    push rbx
    mov ebx, R_X86_64_RELATIVE
    cmp dword [arch], ARCH_A64
    jne .t1
    mov ebx, R_AARCH64_RELATIVE
.t1:
    cmp dword [arch], ARCH_RV64
    jne .t2
    mov ebx, R_RISCV_RELATIVE
.t2:
    cmp dword [arch], ARCH_LA64
    jne .t3
    mov ebx, R_LARCH_RELATIVE
.t3:
    mov eax, [dyn_nimp]                 ; first RELATIVE entry
    cmp qword [dyn_cexit], 0
    je .f
    inc eax
.f: lea rdx, [rax + rax*2]
    shl rdx, 3
    add rdx, [dyn_relaoff]              ; rdx = its offset in the data
    xor ecx, ecx
.l: cmp ecx, [rel_count]
    jae .d
    mov rax, rcx
    shl rax, 4
    mov r8d, [rel_buf + rax + 4]
    cmp r8d, R_DATA64
    je .y
    cmp r8d, R_CODE64
    jne .n
.y: mov eax, [rel_buf + rax]            ; position in the data
    mov r9, [data_buf + rax]            ; the final address (the library is linked at 0)
    add rax, [data_vaddr]
    mov [data_buf + rdx], rax           ; r_offset
    mov [data_buf + rdx + 8], rbx       ; r_info (no symbol)
    mov [data_buf + rdx + 16], r9       ; r_addend
    add rdx, 24
.n: inc ecx
    jmp .l
.d: pop rbx
    ret

; elf_section_headers: rdi = file offset of the data, rax = file size so far -> appends .shstrtab and the section headers
; (.text .data .bss .dynsym .dynstr .hash .rela.dyn .dynamic) and returns the new file size in rax
elf_section_headers:
    push rbx
    push r12
    push r13
    mov r12, rdi                        ; data file offset
    lea rbx, [outbuf + rax]             ; .shstrtab
    mov r13, rax
    mov rsi, shstrtab_text
    mov rdi, rbx
    mov ecx, shstrtab_text_end - shstrtab_text
    rep movsb
    mov rax, r13
    add rax, shstrtab_text_end - shstrtab_text
    add rax, 7
    and rax, -8
    mov [outbuf + 40], rax              ; e_shoff
    mov word [outbuf + 58], 64          ; e_shentsize
    mov word [outbuf + 60], 10          ; e_shnum
    mov word [outbuf + 62], 9           ; e_shstrndx
    lea rdi, [outbuf + rax]
    push rax
    push rdi
    mov ecx, 10 * 64
    xor eax, eax
    rep stosb
    pop rdi
    ; 1 .text
    add rdi, 64
    mov dword [rdi], shs_text - shstrtab_text
    mov dword [rdi+4], 1
    mov qword [rdi+8], 6
    mov rax, [code_vaddr]
    mov [rdi+16], rax
    mov rax, [elf_code_off]
    mov [rdi+24], rax
    mov rax, [code_pos]
    mov [rdi+32], rax
    mov qword [rdi+48], 16
    ; 2 .data
    add rdi, 64
    mov dword [rdi], shs_data - shstrtab_text
    mov dword [rdi+4], 1
    mov qword [rdi+8], 3
    mov rax, [data_vaddr]
    mov [rdi+16], rax
    mov [rdi+24], r12
    mov rax, [dyn_data_end]
    mov [rdi+32], rax
    mov qword [rdi+48], 16
    ; 3 .bss
    add rdi, 64
    mov dword [rdi], shs_bss - shstrtab_text
    mov dword [rdi+4], 8
    mov qword [rdi+8], 3
    mov rax, [bss_vaddr]
    mov [rdi+16], rax
    mov rax, [data_pos]
    add rax, r12
    mov [rdi+24], rax
    mov rax, [bss_pos]
    mov [rdi+32], rax
    mov qword [rdi+48], 16
    ; 4 .dynsym
    add rdi, 64
    mov dword [rdi], shs_dynsym - shstrtab_text
    mov dword [rdi+4], 11
    mov qword [rdi+8], 2
    mov rax, [dyn_symoff]
    call .sec_at
    mov rax, [dyn_hashoff]
    mov eax, [data_buf + rax + 4]       ; nchain = number of symbols
    imul rax, 24
    mov [rdi+32], rax
    mov dword [rdi+40], 5               ; sh_link: .dynstr
    mov dword [rdi+44], 1               ; sh_info: the first global symbol
    mov qword [rdi+48], 8
    mov qword [rdi+56], 24
    ; 5 .dynstr
    add rdi, 64
    mov dword [rdi], shs_dynstr - shstrtab_text
    mov dword [rdi+4], 3
    mov qword [rdi+8], 2
    mov rax, [dyn_stroff]
    call .sec_at
    mov eax, [dyn_strsz]
    mov [rdi+32], rax
    mov qword [rdi+48], 1
    ; 6 .hash
    add rdi, 64
    mov dword [rdi], shs_hash - shstrtab_text
    mov dword [rdi+4], 5
    mov qword [rdi+8], 2
    mov rax, [dyn_hashoff]
    call .sec_at
    mov rax, [dyn_hashoff]
    mov eax, [data_buf + rax + 4]
    lea rax, [rax*8 + 8]
    mov [rdi+32], rax
    mov dword [rdi+40], 4
    mov qword [rdi+48], 8
    mov qword [rdi+56], 4
    ; 7 .rela.dyn
    add rdi, 64
    mov dword [rdi], shs_rela - shstrtab_text
    mov dword [rdi+4], 4
    mov qword [rdi+8], 2
    mov rax, [dyn_relaoff]
    call .sec_at
    mov rax, [dyn_off]
    mov rax, [data_buf + rax + 0]       ; (DT_RELASZ is read back from the dynamic array below)
    call .relasz
    mov [rdi+32], rax
    mov dword [rdi+40], 4
    mov qword [rdi+48], 8
    mov qword [rdi+56], 24
    ; 8 .dynamic
    add rdi, 64
    mov dword [rdi], shs_dynamic - shstrtab_text
    mov dword [rdi+4], 6
    mov qword [rdi+8], 3
    mov rax, [dyn_off]
    call .sec_at
    mov rax, [dyn_size]
    mov [rdi+32], rax
    mov dword [rdi+40], 5
    mov qword [rdi+48], 8
    mov qword [rdi+56], 16
    ; 9 .shstrtab
    add rdi, 64
    mov dword [rdi], shs_shstrtab - shstrtab_text
    mov dword [rdi+4], 3
    mov [rdi+24], r13
    mov qword [rdi+32], shstrtab_text_end - shstrtab_text
    mov qword [rdi+48], 1
    pop rax
    add rax, 10 * 64
    pop r13
    pop r12
    pop rbx
    ret
; .sec_at: rax = offset in the data -> sh_addr and sh_offset of the section at rdi
.sec_at:
    push rax
    add rax, [data_vaddr]
    mov [rdi+16], rax
    pop rax
    add rax, r12
    mov [rdi+24], rax
    ret
; .relasz: -> rax = the DT_RELASZ value of the dynamic array
.relasz:
    mov rax, [dyn_off]
    lea rsi, [data_buf + rax]
.rz:
    cmp qword [rsi], 0
    je .rz0
    cmp qword [rsi], 8
    je .rzf
    add rsi, 16
    jmp .rz
.rzf:
    mov rax, [rsi+8]
    ret
.rz0:
    xor eax, eax
    ret

section .rodata
shstrtab_text:  db 0
shs_text:       db ".text", 0
shs_data:       db ".data", 0
shs_bss:        db ".bss", 0
shs_dynsym:     db ".dynsym", 0
shs_dynstr:     db ".dynstr", 0
shs_hash:       db ".hash", 0
shs_rela:       db ".rela.dyn", 0
shs_dynamic:    db ".dynamic", 0
shs_shstrtab:   db ".shstrtab", 0
shstrtab_text_end:
section .text
