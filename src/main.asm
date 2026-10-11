; =============================================================================
;  main.asm - command line, files/imports, builtins, ELF64 + PE32+ writers
; =============================================================================
section .rodata

s_dash_o:       db "-o", 0
s_dash_t:       db "-t", 0
s_dash_v:       db "-v", 0
s_dash_r:       db "-r", 0
s_dash_h:       db "-h", 0
s_help:         db "--help", 0
s_version:      db "--version", 0
s_linux:        db "linux", 0
s_windows:      db "windows", 0
s_win:          db "win", 0
s_win64:        db "win64", 0
s_android:      db "android", 0
s_linux_x64:    db "linux-x64", 0
s_linux_arm64:  db "linux-arm64", 0
s_android_arm64: db "android-arm64", 0
s_android_x64:  db "android-x64", 0
s_ext_arm_elf:  db ".arm64.elf", 0
s_ext_x64_bin:  db ".x64.bin", 0
s_ver_default:  db "1", 0
s_rel_default:  db "debug", 0
s_ext_linux:    db ".elf", 0
s_ext_win:      db ".exe", 0
s_ext_android:  db ".bin", 0
s_std_name:     db "<std>", 0
s_main:         db "main", 0
s_exit_name:    db "__exit", 0
s_libdir1:      db "lib/", 0
s_libdir2:      db "/usr/lib/a/", 0
s_libdir3:      db "/usr/local/lib/a/", 0

s_usage:
    db "A compiler ", VERSION_NAME, " (version code ", '0'+VERSION_CODE, ")  -  Aytict, https://aytict.fi", 10
    db "Usage: ac [options] source.a", 10
    db 10
    db "Options:", 10
    db "  -o FILE     output file (default: NAME-VERSION-RELEASE.EXT)", 10
    db "  -t TARGET   linux (default) | windows | android | linux-arm64 | android-x64", 10
    db "              linux = linux-x64, android = android-arm64, windows = windows x64", 10
    db "  -v CODE     version code used in the default output name (default 1)", 10
    db "  -r TYPE     release type used in the default output name (default debug)", 10
    db "  -h          show this help", 10
    db "  --version   show the compiler version", 10
    db 0
s_version_text: db "ac ", VERSION_NAME, 10, 0
s_err_noinput:  db "no input file (try: ac -h)", 0
s_err_badopt:   db "unknown option or missing value (try: ac -h)", 0
s_err_badtgt:   db "unknown target, use linux, windows, android, linux-arm64 or android-x64", 0
s_err_read:     db "cannot read the input file", 0
s_err_nomain:   db "no 'main' function found", 0
s_err_write:    db "cannot write the output file", 0
s_err_undef:    db "undefined function", 0
s_err_missing:  db "internal error: standard library function missing:", 0
s_err_nofile:   db "cannot find the imported file", 0
s_err_mainpar:  db "main may take at most (int argc, char** argv)", 0

; embedded standard library written in A
std_src:
    incbin "lib/std.a"
    db 0
std_src_end:

; ---- builtin functions: name, parameter count, linux blob, windows blob ----------
%define IAT_GetStdHandle    0
%define IAT_WriteFile       1
%define IAT_ReadFile        2
%define IAT_ExitProcess     3
%define IAT_CreateFileA     4
%define IAT_CloseHandle     5
%define IAT_GetCommandLineA 6
%define IAT_COUNT           7

bn_write:   db "__write", 0
bn_read:    db "__read", 0
bn_exit:    db "__exit", 0
bn_syscall: db "__syscall", 0
bn_cmdline: db "__cmdline", 0
s_win_init: db "__win_init_args", 0
s_win_argv: db "__win_argv_get", 0

align 8
; name, parameter count, then start/end of the runtime code for: x86-64 Linux/Android,
; Windows x64, AArch64 Linux/Android (64 bytes per entry)
builtin_tab:
    dq bn_write,   3, bl_lin_write,   bl_lin_write_end,   bl_win_write,   bl_win_write_end,   bl_a64_write,   bl_a64_write_end
    dq bn_read,    3, bl_lin_read,    bl_lin_read_end,    bl_win_read,    bl_win_read_end,    bl_a64_read,    bl_a64_read_end
    dq bn_exit,    1, bl_lin_exit,    bl_lin_exit_end,    bl_win_exit,    bl_win_exit_end,    bl_a64_exit,    bl_a64_exit_end
    dq bn_syscall, 7, bl_lin_syscall, bl_lin_syscall_end, 0,              0,                  bl_a64_syscall, bl_a64_syscall_end
    dq bn_cmdline, 0, bl_lin_cmdline, bl_lin_cmdline_end, bl_win_cmdline, bl_win_cmdline_end, bl_a64_cmdline, bl_a64_cmdline_end
    dq 0

; Linux / Android x86-64 runtime (raw syscalls). Arguments were pushed left to
; right by the caller, so the last argument is at [rsp+8].
bl_lin_write:
    mov rdx, [rsp+8]
    mov rsi, [rsp+16]
    mov rdi, [rsp+24]
    mov eax, 1
    syscall
    ret
bl_lin_write_end:
bl_lin_read:
    mov rdx, [rsp+8]
    mov rsi, [rsp+16]
    mov rdi, [rsp+24]
    xor eax, eax
    syscall
    ret
bl_lin_read_end:
bl_lin_exit:
    mov rdi, [rsp+8]
    mov eax, 231
    syscall
    ret
bl_lin_exit_end:
bl_lin_syscall:
    mov r9,  [rsp+8]
    mov r8,  [rsp+16]
    mov r10, [rsp+24]
    mov rdx, [rsp+32]
    mov rsi, [rsp+40]
    mov rdi, [rsp+48]
    mov rax, [rsp+56]
    syscall
    ret
bl_lin_syscall_end:

bl_lin_cmdline:
    xor eax, eax
    ret
bl_lin_cmdline_end:

; Windows x64 runtime (kernel32 imports through the IAT)
bl_win_cmdline:
    mov r12, rsp
    and rsp, -16
    sub rsp, 32
    IATCALL IAT_GetCommandLineA
    mov rsp, r12
    ret
bl_win_cmdline_end:
bl_win_write:
    mov rdi, [rsp+8]
    mov rsi, [rsp+16]
    mov rax, [rsp+24]
    mov r12, rsp
    mov rcx, -10
    sub rcx, rax
    sub rsp, 64
    and rsp, -16
    IATCALL IAT_GetStdHandle
    mov rcx, rax
    mov rdx, rsi
    mov r8, rdi
    lea r9, [rsp+48]
    mov qword [rsp+32], 0
    mov qword [rsp+48], 0
    IATCALL IAT_WriteFile
    mov eax, [rsp+48]
    mov rsp, r12
    ret
bl_win_write_end:
bl_win_read:
    mov rdi, [rsp+8]
    mov rsi, [rsp+16]
    mov rax, [rsp+24]
    mov r12, rsp
    mov rcx, -10
    sub rcx, rax
    sub rsp, 64
    and rsp, -16
    IATCALL IAT_GetStdHandle
    mov rcx, rax
    mov rdx, rsi
    mov r8, rdi
    lea r9, [rsp+48]
    mov qword [rsp+32], 0
    mov qword [rsp+48], 0
    IATCALL IAT_ReadFile
    mov eax, [rsp+48]
    mov rsp, r12
    ret
bl_win_read_end:
bl_win_exit:
    mov rcx, [rsp+8]
    and rsp, -16
    sub rsp, 32
    IATCALL IAT_ExitProcess
    ret
bl_win_exit_end:

; import names (in the order of the IAT_* indices)
imp_names:
    db "GetStdHandle", 0
    db "WriteFile", 0
    db "ReadFile", 0
    db "ExitProcess", 0
    db "CreateFileA", 0
    db "CloseHandle", 0
    db "GetCommandLineA", 0
    db 0
s_kernel32: db "KERNEL32.DLL", 0

section .text

; ---- small string helpers -----------------------------------------------------------
; cstr_eq: rdi, rsi -> eax = 1 if equal
cstr_eq:
.l: mov al, [rdi]
    cmp al, [rsi]
    jne .no
    test al, al
    jz .yes
    inc rdi
    inc rsi
    jmp .l
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; cstr_copy: rdi = destination, rsi = source -> rdi points at the terminating NUL
cstr_copy:
.l: mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .d
    inc rdi
    inc rsi
    jmp .l
.d: ret

; ---- source files --------------------------------------------------------------------
; file_try: rdi = path -> rax = file entry or 0
file_try:
    push rbx
    push r12
    push r13
    mov r12, rdi
    xor ebx, ebx
.search:
    cmp ebx, [file_count]
    jae .load
    mov rax, rbx
    shl rax, 6
    add rax, file_table
    mov rdi, [rax]
    mov rsi, r12
    push rax
    call cstr_eq
    mov rdx, rax
    pop rax
    test edx, edx
    jnz .out
    inc ebx
    jmp .search
.load:
    mov rdi, r12
    call read_file
    test rax, rax
    jz .fail
    mov r13, rax
    mov rbx, rdx
    ; keep a copy of the path
    mov rdi, r12
    call cstrlen
    lea rdi, [rax+1]
    mov r8, rax
    call name_alloc
    push rax
    mov rdi, rax
    mov rsi, r12
    call cstr_copy
    pop rsi
    mov eax, [file_count]
    cmp eax, FILE_MAX
    jb .add
    jmp err_toobig
.add:
    inc dword [file_count]
    mov rcx, rax
    shl rcx, 6
    add rcx, file_table
    mov [rcx], rsi
    mov [rcx+8], r13
    mov [rcx+16], rbx
    mov [rcx+24], eax
    mov dword [rcx+28], 0
    mov rax, rcx
    jmp .out
.fail:
    xor eax, eax
.out:
    pop r13
    pop r12
    pop rbx
    ret

; file_include: importbuf = relative path. Finds the file and compiles it.
file_include:
    push rbx
    push r12
    ; 1) next to the importing file
    mov rsi, [cur_file_name]
    mov rdi, candbuf
    mov rbx, rsi
    xor r12, r12                    ; last slash position + 1
    mov rcx, rsi
.sl:
    mov al, [rcx]
    test al, al
    jz .sd
    inc rcx
    cmp al, '/'
    jne .sl
    mov r12, rcx
    jmp .sl
.sd:
    mov rcx, rbx
.cp:
    cmp rcx, r12
    jae .cpd
    mov al, [rcx]
    mov [rdi], al
    inc rdi
    inc rcx
    jmp .cp
.cpd:
    mov rsi, importbuf
    call cstr_copy
    mov rdi, candbuf
    call file_try
    test rax, rax
    jnz .found
    ; 2) lib/ in the current directory, 3) installed libraries
    mov rbx, s_libdir1
    call .try_prefix
    test rax, rax
    jnz .found
    mov rbx, s_libdir2
    call .try_prefix
    test rax, rax
    jnz .found
    mov rbx, s_libdir3
    call .try_prefix
    test rax, rax
    jnz .found
    ; 4) lib/ next to the main source file
    mov rax, [main_dir]
    mov rdi, candbuf
    mov rsi, rax
    call cstr_copy
    mov rsi, s_libdir1
    call cstr_copy
    mov rsi, importbuf
    call cstr_copy
    mov rdi, candbuf
    call file_try
    test rax, rax
    jnz .found
    mov qword [tk_ptr], importbuf
    mov rdi, importbuf
    call cstrlen
    mov [tk_len], eax
    mov edi, s_err_nofile
    call fatal_error_tok
.found:
    mov rdi, rax
    call compile_file
    pop r12
    pop rbx
    ret
.try_prefix:
    mov rdi, candbuf
    mov rsi, rbx
    call cstr_copy
    mov rsi, importbuf
    call cstr_copy
    mov rdi, candbuf
    jmp file_try

; compile_file: rdi = file entry. Parses it as a unit (once per pass).
compile_file:
    push rbx
    push r12
    mov r12, rdi
    mov eax, [r12+28]
    cmp eax, [pass]
    je .skip
    mov eax, [pass]
    mov [r12+28], eax
    sub rsp, 128
    mov rdi, rsp
    call lex_save
    mov rax, [r12+8]
    mov [src_ptr], rax
    add rax, [r12+16]
    mov [src_end], rax
    mov qword [src_line], 1
    mov qword [tk_line], 1
    mov rax, [r12]
    mov [cur_file_name], rax
    mov eax, [r12+24]
    mov [cur_file_id], eax
    mov dword [cur_module], 0
    call next_token
    call parse_items
    mov rsi, rsp
    call lex_restore
    add rsp, 128
.skip:
    pop r12
    pop rbx
    ret

; compile_all: one complete pass over std + the main source
compile_all:
    mov dword [cur_module], 0
    mov dword [cur_class], -1
    mov qword [cur_func], 0
    mov rdi, file_table
    call compile_file
    mov rdi, file_table
    add rdi, 64
    jmp compile_file

; ---- builtins ------------------------------------------------------------------------------
; builtin_col -> eax = byte offset of the (start, end) columns for the current target
builtin_col:
    mov eax, 16
    cmp dword [arch], ARCH_A64
    jne .x
    mov eax, 48
    ret
.x: cmp dword [target], TGT_WINDOWS
    jne .r
    mov eax, 32
.r: ret

register_builtins:
    push rbx
    push r12
    call builtin_col
    mov r12d, eax
    mov rbx, builtin_tab
.l:
    mov rdi, [rbx]
    test rdi, rdi
    jz .done
    cmp qword [rbx+r12], 0
    je .next
    call cstrlen
    mov esi, eax
    mov rdi, [rbx]
    mov edx, S_FUNC
    call sym_new
    mov qword [rax+SYM_VAL], -1
    mov rcx, [rbx+8]
    mov [rax+SYM_NPAR], ecx
    mov qword [rax+SYM_TYPE], TY_INT
    mov dword [rax+SYM_FLAGS], F_BUILTIN | F_DEFINED
.next:
    add rbx, 64
    jmp .l
.done:
    pop r12
    pop rbx
    ret

; emit_blob: rsi = start, rdx = end. Copies the bytes and records IAT fixups.
emit_blob:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
    mov rbx, [code_pos]
    mov ecx, edx
    sub ecx, esi
    call emit_bytes
    mov rdx, iatfix_start
.l:
    cmp rdx, iatfix_end
    jae .done
    mov rax, [rdx]
    cmp rax, r12
    jb .n
    cmp rax, r13
    jae .n
    sub rax, r12
    add rax, rbx
    mov edi, eax
    mov esi, R_IAT
    push rdx
    mov edx, [rdx+8]
    call add_reloc
    pop rdx
.n:
    add rdx, 16
    jmp .l
.done:
    pop r13
    pop r12
    pop rbx
    ret

; find_main -> rax = symbol of the program's main function
find_main:
    xor edx, edx
.l:
    cmp edx, [sym_count]
    jae .none
    mov rax, rdx
    shl rax, 6
    add rax, symtab
    cmp dword [rax+SYM_KIND], S_FUNC
    jne .n
    cmp dword [rax+SYM_NLEN], 4
    jne .n
    test dword [rax+SYM_FLAGS], F_METHOD | F_BUILTIN
    jnz .n
    mov rcx, [rax+SYM_NAME]
    cmp dword [rcx], 'main'
    jne .n
    ret
.n:
    inc edx
    jmp .l
.none:
    xor eax, eax
    ret

; emit_prologue: program entry stub and builtin runtime (pass 2 start)
emit_prologue:
    push rbx
    push r12
    call find_main
    test rax, rax
    jnz .m1
    mov dword [cur_file_name], 0
    mov qword [cur_file_name], 0
    mov edi, s_err_nomain
    call fatal_error
.m1:
    mov r12, rax
    mov ebx, [r12+SYM_NPAR]
    cmp ebx, 2
    jbe .m2
    mov qword [cur_file_name], 0
    mov edi, s_err_mainpar
    call fatal_error
.m2:
    cmp dword [target], TGT_WINDOWS
    je .win
    ; Linux / Android: argc and argv come from the initial stack
    mov edi, ebx
    CG entry_args
    jmp .call
.win:
    ; Windows: the standard library parses GetCommandLineA() into argc / argv
    test ebx, ebx
    jz .call
    mov rdi, s_win_init
    call emit_call_named
    CG push_a
    cmp ebx, 2
    jb .call
    mov rdi, s_win_argv
    call emit_call_named
    CG push_a
.call:
    mov rdi, r12
    call emit_call_sym
    CG push_a
    mov rdi, s_exit_name
    call emit_call_named
    ; builtin runtime blobs
    call builtin_col
    mov r12d, eax
    mov rbx, builtin_tab
.bl:
    cmp qword [rbx], 0
    je .done
    mov r8, [rbx+r12]
    test r8, r8
    jz .bnext
    mov r9, [rbx+r12+8]
    push r8
    push r9
    mov rdi, [rbx]
    call cstrlen
    mov esi, eax
    mov rdi, [rbx]
    xor edx, edx
    call sym_find_global
    mov rdi, rax
    call define_function
    pop rdx
    pop rsi
    call emit_blob
.bnext:
    add rbx, 64
    jmp .bl
.done:
    pop r12
    pop rbx
    ret

; emit_call_named: rdi = name of a global (module 0) function -> emits a call to it
emit_call_named:
    push rbx
    mov rbx, rdi
    call cstrlen
    mov esi, eax
    mov rdi, rbx
    xor edx, edx
    call sym_find_global
    test rax, rax
    jnz .ok
    mov qword [cur_file_name], 0
    mov [tk_ptr], rbx
    mov rdi, rbx
    call cstrlen
    mov [tk_len], eax
    mov edi, s_err_missing
    call fatal_error_tok
.ok:
    mov rdi, rax
    pop rbx
    jmp emit_call_sym

; check_undefined: every called function must have been defined
check_undefined:
    xor edx, edx
.l:
    cmp edx, [sym_count]
    jae .ok
    mov rax, rdx
    shl rax, 6
    add rax, symtab
    cmp dword [rax+SYM_KIND], S_FUNC
    jne .n
    cmp dword [rax+SYM_PATCH], 0
    je .n
    mov rcx, [rax+SYM_NAME]
    mov [tk_ptr], rcx
    mov ecx, [rax+SYM_NLEN]
    mov [tk_len], ecx
    mov qword [cur_file_name], 0
    mov edi, s_err_undef
    call fatal_error_tok
.n:
    inc edx
    jmp .l
.ok:
    ret

; ---- relocations ---------------------------------------------------------------------------
; apply_relocs: [code_vaddr] [data_vaddr] [bss_vaddr] [iat_vaddr] must be set
apply_relocs:
    cmp dword [arch], ARCH_A64
    je apply_relocs_a64
    jmp apply_relocs_x86

; install_backend: edi = architecture; fills the primitive table
install_backend:
    mov [arch], edi
    mov esi, cg_tab_x86
    mov dword [slot_bytes], 8
    cmp edi, ARCH_A64
    jne .copy
    mov esi, cg_tab_a64
    mov dword [slot_bytes], 16
.copy:
    mov edi, cg_vt
    mov ecx, CGI_COUNT
    rep movsq
    ret

; ---- ELF64 -----------------------------------------------------------------------------------
%define ELF_BASE 0x400000
%define ELF_CODE_OFF 0x100

; build_elf -> rax = image size (image at outbuf)
build_elf:
    push rbx
    push r12
    push r13
    mov r13d, 0x1000                        ; page / segment alignment
    mov ebx, 0x3E                           ; e_machine x86-64
    cmp dword [arch], ARCH_A64
    jne .a
    mov r13d, 0x4000                        ; AArch64: 16 KiB (works on 4K and 16K kernels)
    mov ebx, 0xB7                           ; EM_AARCH64
.a:
    mov rax, [code_pos]
    add rax, ELF_CODE_OFF
    lea rax, [rax + r13 - 1]
    mov rcx, r13
    neg rcx
    and rax, rcx
    mov r12, rax                            ; data file offset
    mov rax, ELF_BASE + ELF_CODE_OFF
    mov [code_vaddr], rax
    mov rax, ELF_BASE
    add rax, r12
    mov [data_vaddr], rax
    mov rcx, [data_pos]
    add rcx, 15
    and rcx, -16
    add rax, rcx
    mov [bss_vaddr], rax
    mov qword [iat_vaddr], 0
    call apply_relocs
    ; copy code and data
    mov rsi, code_buf
    mov rdi, outbuf + ELF_CODE_OFF
    mov rcx, [code_pos]
    rep movsb
    mov rsi, data_buf
    lea rdi, [outbuf + r12]
    mov rcx, [data_pos]
    rep movsb
    ; ELF header
    mov rdi, outbuf
    mov dword [rdi], 0x464C457F
    mov byte [rdi+4], 2
    mov byte [rdi+5], 1
    mov byte [rdi+6], 1
    mov word [rdi+16], 2
    mov [rdi+18], bx
    mov dword [rdi+20], 1
    mov rax, [code_vaddr]
    mov [rdi+24], rax
    mov qword [rdi+32], 64
    mov word [rdi+52], 64
    mov word [rdi+54], 56
    mov word [rdi+56], 3
    mov word [rdi+58], 64
    ; PT_LOAD headers + code (R+X)
    mov dword [rdi+64], 1
    mov dword [rdi+68], 5
    mov qword [rdi+72], 0
    mov qword [rdi+80], ELF_BASE
    mov qword [rdi+88], ELF_BASE
    mov rax, [code_pos]
    add rax, ELF_CODE_OFF
    mov [rdi+96], rax
    mov [rdi+104], rax
    mov [rdi+112], r13
    ; PT_LOAD data + bss (R+W)
    mov dword [rdi+120], 1
    mov dword [rdi+124], 6
    mov [rdi+128], r12
    mov rax, [data_vaddr]
    mov [rdi+136], rax
    mov [rdi+144], rax
    mov rax, [data_pos]
    mov [rdi+152], rax
    mov rcx, [data_pos]
    add rcx, 15
    and rcx, -16
    add rcx, [bss_pos]
    mov [rdi+160], rcx
    mov [rdi+168], r13
    ; PT_GNU_STACK
    mov dword [rdi+176], 0x6474E551
    mov dword [rdi+180], 6
    mov qword [rdi+224], 16
    lea rax, [r12 + 0]
    add rax, [data_pos]
    pop r13
    pop r12
    pop rbx
    ret

; ---- PE32+ (Windows x64) -----------------------------------------------------------------
%define PE_BASE 0x140000000
%define PE_IDATA_ILT 40
%define PE_IDATA_IAT (40 + (IAT_COUNT+1)*8)
%define PE_IDATA_NAMES (PE_IDATA_IAT + (IAT_COUNT+1)*8)

; align_up: rax = value, rcx = alignment (power of two) -> rax
%macro ALIGNUP 2
    add %1, %2 - 1
    and %1, -%2
%endmacro

; build_pe -> rax = image size
build_pe:
    push rbx
    push r12
    push r13
    push r14
    push r15
    ; --- section layout
    mov r12, [code_pos]                     ; text virtual size
    mov rax, r12
    ALIGNUP rax, 0x200
    mov r13, rax                            ; text raw size
    mov rax, 0x1000
    add rax, r12
    ALIGNUP rax, 0x1000
    mov r14, rax                            ; data rva
    mov rax, [data_pos]
    ALIGNUP rax, 16
    mov rbx, rax                            ; aligned data size
    add rax, [bss_pos]
    cmp rax, 16
    jae .v1
    mov eax, 16
.v1:
    mov r15, rax                            ; data virtual size
    mov rax, [data_pos]
    ALIGNUP rax, 0x200
    mov [pe_data_rawsz], rax
    lea rax, [r14 + r15]
    ALIGNUP rax, 0x1000
    mov [pe_idata_rva], rax                 ; idata rva
    ; --- build the import section in a scratch buffer
    call build_idata                        ; rax = idata size
    mov [pe_idata_size], rax
    ALIGNUP rax, 0x200
    mov [pe_idata_rawsz], rax
    ; --- virtual addresses for relocation
    mov rax, PE_BASE + 0x1000
    mov [code_vaddr], rax
    mov rax, PE_BASE
    add rax, r14
    mov [data_vaddr], rax
    add rax, rbx
    mov [bss_vaddr], rax
    mov rax, PE_BASE
    add rax, [pe_idata_rva]
    add rax, PE_IDATA_IAT
    mov [iat_vaddr], rax
    call apply_relocs
    ; --- raw offsets
    mov rax, 0x200
    mov [pe_text_raw], rax
    add rax, r13
    mov [pe_data_raw], rax
    add rax, [pe_data_rawsz]
    mov [pe_idata_raw], rax
    ; --- copy section bodies
    mov rsi, code_buf
    lea rdi, [outbuf + 0x200]
    mov rcx, r12
    rep movsb
    mov rsi, data_buf
    mov rdi, outbuf
    add rdi, [pe_data_raw]
    mov rcx, [data_pos]
    rep movsb
    mov rsi, idata_buf
    mov rdi, outbuf
    add rdi, [pe_idata_raw]
    mov rcx, [pe_idata_size]
    rep movsb
    ; --- headers
    mov rdi, outbuf
    mov word [rdi], 0x5A4D
    mov dword [rdi+0x3C], 0x40
    mov dword [rdi+0x40], 0x00004550
    mov word [rdi+0x44], 0x8664
    mov word [rdi+0x46], 3
    mov word [rdi+0x54], 0xF0
    mov word [rdi+0x56], 0x0023
    lea rdi, [outbuf + 0x58]                ; optional header
    mov word [rdi], 0x20B
    mov byte [rdi+2], 14
    mov [rdi+4], r13d                       ; SizeOfCode
    mov rax, [pe_data_rawsz]
    add rax, [pe_idata_rawsz]
    mov [rdi+8], eax                        ; SizeOfInitializedData
    mov rax, [bss_pos]
    mov [rdi+12], eax
    mov dword [rdi+16], 0x1000              ; entry point
    mov dword [rdi+20], 0x1000
    mov rax, PE_BASE
    mov [rdi+24], rax
    mov dword [rdi+32], 0x1000
    mov dword [rdi+36], 0x200
    mov word [rdi+40], 6
    mov word [rdi+48], 6
    mov rax, [pe_idata_rva]
    add rax, [pe_idata_size]
    ALIGNUP rax, 0x1000
    mov [rdi+56], eax                       ; SizeOfImage
    mov dword [rdi+60], 0x200
    mov word [rdi+68], 3                    ; console subsystem
    mov word [rdi+70], 0x8100               ; NX compatible, no ASLR
    mov qword [rdi+72], 0x100000
    mov qword [rdi+80], 0x1000
    mov qword [rdi+88], 0x100000
    mov qword [rdi+96], 0x1000
    mov dword [rdi+108], 16
    mov rax, [pe_idata_rva]
    mov [rdi+112+8], eax                    ; import directory
    mov dword [rdi+112+8+4], 40
    add rax, PE_IDATA_IAT
    mov [rdi+112+96], eax                   ; IAT directory
    mov dword [rdi+112+96+4], (IAT_COUNT+1)*8
    ; section table at 0x148
    lea rdi, [outbuf + 0x148]
    ; .text
    mov dword [rdi], '.tex'
    mov byte [rdi+4], 't'
    mov [rdi+8], r12d
    mov dword [rdi+12], 0x1000
    mov [rdi+16], r13d
    mov rax, [pe_text_raw]
    mov [rdi+20], eax
    mov dword [rdi+36], 0x60000020
    ; .data
    add rdi, 40
    mov dword [rdi], '.dat'
    mov byte [rdi+4], 'a'
    mov [rdi+8], r15d
    mov [rdi+12], r14d
    mov rax, [pe_data_rawsz]
    mov [rdi+16], eax
    mov rax, [pe_data_raw]
    mov [rdi+20], eax
    mov dword [rdi+36], 0xC0000040
    ; .idata
    add rdi, 40
    mov dword [rdi], '.ida'
    mov byte [rdi+4], 't'
    mov byte [rdi+5], 'a'
    mov rax, [pe_idata_size]
    mov [rdi+8], eax
    mov rax, [pe_idata_rva]
    mov [rdi+12], eax
    mov rax, [pe_idata_rawsz]
    mov [rdi+16], eax
    mov rax, [pe_idata_raw]
    mov [rdi+20], eax
    mov dword [rdi+36], 0xC0000040
    mov rax, [pe_idata_raw]
    add rax, [pe_idata_rawsz]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; build_idata: builds the import section contents into idata_buf using the RVA in
; [pe_idata_rva]. -> rax = size
build_idata:
    push rbx
    push r12
    push r13
    mov rdi, idata_buf
    mov rbx, [pe_idata_rva]
    ; name table starts at PE_IDATA_NAMES
    mov r12d, PE_IDATA_NAMES                ; running offset
    mov rsi, imp_names
    xor r13d, r13d                          ; import index
.imp:
    cmp byte [rsi], 0
    je .names_done
    ; hint/name entry at offset r12 (2 byte aligned)
    lea rax, [rbx + r12]
    mov [idata_buf + PE_IDATA_ILT + r13*8], rax
    mov [idata_buf + PE_IDATA_IAT + r13*8], rax
    lea rdi, [idata_buf + r12 + 2]
.nm:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .nm
    sub rdi, idata_buf
    add rdi, 1
    and rdi, -2
    mov r12, rdi
    inc r13d
    jmp .imp
.names_done:
    ; dll name
    lea rdi, [idata_buf + r12]
    mov r13, rdi
    mov rsi, s_kernel32
    call cstr_copy
    sub r13, idata_buf                      ; offset of dll name
    lea rax, [r12 + 13]
    mov r12, rax
    ; import descriptor
    mov rax, rbx
    add rax, PE_IDATA_ILT
    mov [idata_buf], eax                    ; OriginalFirstThunk
    lea rax, [rbx + r13]
    mov [idata_buf + 12], eax               ; Name
    mov rax, rbx
    add rax, PE_IDATA_IAT
    mov [idata_buf + 16], eax               ; FirstThunk
    mov rax, r12
    pop r13
    pop r12
    pop rbx
    ret

; ---- entry -------------------------------------------------------------------------------------
global _start
_start:
    lea rax, [rsp - 6*1024*1024]
    mov [stack_limit], rax
    mov r14, [rsp]                          ; argc
    lea r15, [rsp+8]                        ; argv
    mov qword [opt_version], s_ver_default
    mov qword [opt_release], s_rel_default
    mov r13d, 1
.arg:
    cmp r13, r14
    jae .args_done
    mov rbx, [r15+r13*8]
    inc r13
    mov rdi, rbx
    mov rsi, s_dash_o
    call cstr_eq
    test eax, eax
    jnz .o
    mov rdi, rbx
    mov rsi, s_dash_t
    call cstr_eq
    test eax, eax
    jnz .t
    mov rdi, rbx
    mov rsi, s_dash_v
    call cstr_eq
    test eax, eax
    jnz .v
    mov rdi, rbx
    mov rsi, s_dash_r
    call cstr_eq
    test eax, eax
    jnz .r
    mov rdi, rbx
    mov rsi, s_dash_h
    call cstr_eq
    test eax, eax
    jnz .help
    mov rdi, rbx
    mov rsi, s_help
    call cstr_eq
    test eax, eax
    jnz .help
    mov rdi, rbx
    mov rsi, s_version
    call cstr_eq
    test eax, eax
    jnz .showver
    cmp byte [rbx], '-'
    je .badopt
    mov [opt_input], rbx
    jmp .arg
.value:
    cmp r13, r14
    jae .badopt
    mov rax, [r15+r13*8]
    inc r13
    ret
.o: call .value
    mov [opt_output], rax
    jmp .arg
.v: call .value
    mov [opt_version], rax
    jmp .arg
.r: call .value
    mov [opt_release], rax
    jmp .arg
.t: call .value
    mov rbx, rax
    mov rdi, rbx
    mov rsi, s_linux
    call cstr_eq
    test eax, eax
    jnz .t_linux
    mov rdi, rbx
    mov rsi, s_linux_x64
    call cstr_eq
    test eax, eax
    jnz .t_linux
    mov rdi, rbx
    mov rsi, s_linux_arm64
    call cstr_eq
    test eax, eax
    jnz .t_linux_arm
    mov rdi, rbx
    mov rsi, s_windows
    call cstr_eq
    test eax, eax
    jnz .t_win
    mov rdi, rbx
    mov rsi, s_win
    call cstr_eq
    test eax, eax
    jnz .t_win
    mov rdi, rbx
    mov rsi, s_win64
    call cstr_eq
    test eax, eax
    jnz .t_win
    mov rdi, rbx
    mov rsi, s_android
    call cstr_eq
    test eax, eax
    jnz .t_android
    mov rdi, rbx
    mov rsi, s_android_arm64
    call cstr_eq
    test eax, eax
    jnz .t_android
    mov rdi, rbx
    mov rsi, s_android_x64
    call cstr_eq
    test eax, eax
    jnz .t_android_x64
    mov edi, s_err_badtgt
    call fatal_error
.t_linux:
    mov dword [target], TGT_LINUX
    mov dword [arch], ARCH_X64
    jmp .arg
.t_linux_arm:
    mov dword [target], TGT_LINUX
    mov dword [arch], ARCH_A64
    jmp .arg
.t_win:
    mov dword [target], TGT_WINDOWS
    mov dword [arch], ARCH_X64
    jmp .arg
.t_android:
    mov dword [target], TGT_ANDROID
    mov dword [arch], ARCH_A64
    jmp .arg
.t_android_x64:
    mov dword [target], TGT_ANDROID
    mov dword [arch], ARCH_X64
    jmp .arg
.badopt:
    mov edi, s_err_badopt
    call fatal_error
.help:
    mov edi, 1
    mov esi, s_usage
    call print_cstr
    xor edi, edi
    call sys_exit
.showver:
    mov edi, 1
    mov esi, s_version_text
    call print_cstr
    xor edi, edi
    call sys_exit

.args_done:
    cmp qword [opt_input], 0
    jne .have_input
    mov edi, s_err_noinput
    call fatal_error
.have_input:
    call init_tables
    mov edi, [arch]
    call install_backend
    ; --- directory of the main file (for lib/ lookups)
    mov rsi, [opt_input]
    mov rdi, maindirbuf
    xor r12, r12
    mov rcx, rsi
.md:
    mov al, [rcx]
    test al, al
    jz .mdd
    inc rcx
    cmp al, '/'
    jne .md
    mov r12, rcx
    jmp .md
.mdd:
    mov rcx, rsi
.mdc:
    cmp rcx, r12
    jae .mdz
    mov al, [rcx]
    mov [rdi], al
    inc rdi
    inc rcx
    jmp .mdc
.mdz:
    mov byte [rdi], 0
    mov qword [main_dir], maindirbuf
    ; --- register the two root files: std (index 0) and the program (index 1)
    mov rdi, s_std_name
    mov rsi, std_src
    mov rdx, std_src_end - std_src - 1
    call add_embedded_file
    mov rdi, [opt_input]
    call file_try
    test rax, rax
    jnz .loaded
    mov edi, s_err_read
    call fatal_error
.loaded:
    ; --- pass 1
    call register_builtins
    mov dword [pass], 1
    call compile_all
    ; --- pass 2
    mov dword [pass], 2
    mov dword [loop_sp], 0
    call emit_prologue
    call compile_all
    mov qword [cur_file_name], 0
    call check_undefined
    ; --- write the image
    cmp dword [target], TGT_WINDOWS
    je .pe
    call build_elf
    jmp .written
.pe:
    call build_pe
.written:
    mov rdx, rax
    call choose_outname
    mov rdi, rax
    mov rsi, outbuf
    call write_file
    test rax, rax
    jns .ok
    mov qword [cur_file_name], 0
    mov edi, s_err_write
    call fatal_error
.ok:
    xor edi, edi
    call sys_exit

; add_embedded_file: rdi = name, rsi = source, rdx = length -> file entry 0
add_embedded_file:
    mov eax, [file_count]
    inc dword [file_count]
    mov rcx, rax
    shl rcx, 6
    add rcx, file_table
    mov [rcx], rdi
    mov [rcx+8], rsi
    mov [rcx+16], rdx
    mov [rcx+24], eax
    mov dword [rcx+28], 0
    ret

; init_tables: operator precedence table
init_tables:
    mov byte [binprec + T_OROR], 1
    mov byte [binprec + T_ANDAND], 2
    mov byte [binprec + '|'], 3
    mov byte [binprec + '^'], 4
    mov byte [binprec + '&'], 5
    mov byte [binprec + T_EQ], 6
    mov byte [binprec + T_NE], 6
    mov byte [binprec + '<'], 7
    mov byte [binprec + '>'], 7
    mov byte [binprec + T_LE], 7
    mov byte [binprec + T_GE], 7
    mov byte [binprec + T_SHL], 8
    mov byte [binprec + T_SHR], 8
    mov byte [binprec + '+'], 9
    mov byte [binprec + '-'], 9
    mov byte [binprec + '*'], 10
    mov byte [binprec + '/'], 10
    mov byte [binprec + '%'], 10
    mov dword [cur_class], -1
    ret

; choose_outname -> rax = output path (-o value or NAME-VERSION-RELEASE.EXT)
choose_outname:
    mov rax, [opt_output]
    test rax, rax
    jz .gen
    ret
.gen:
    mov rsi, [opt_input]
    mov rcx, rsi
.b: mov al, [rcx]
    test al, al
    jz .bd
    inc rcx
    cmp al, '/'
    jne .b
    mov rsi, rcx
    jmp .b
.bd:
    ; rsi = basename; strip a trailing ".a"
    mov rdi, outnamebuf
    mov rcx, rsi
.len:
    cmp byte [rcx], 0
    je .ld
    inc rcx
    jmp .len
.ld:
    sub rcx, rsi
    cmp rcx, 2
    jbe .copy
    cmp byte [rsi+rcx-1], 'a'
    jne .copy
    cmp byte [rsi+rcx-2], '.'
    jne .copy
    sub rcx, 2
.copy:
    rep movsb
    mov byte [rdi], '-'
    inc rdi
    mov rsi, [opt_version]
    call cstr_copy
    mov byte [rdi], '-'
    inc rdi
    mov rsi, [opt_release]
    call cstr_copy
    mov rsi, s_ext_linux
    cmp dword [target], TGT_WINDOWS
    jne .e1
    mov rsi, s_ext_win
    jmp .e3
.e1:
    cmp dword [target], TGT_ANDROID
    je .and
    ; Linux: .elf for x86-64, .arm64.elf for AArch64
    cmp dword [arch], ARCH_A64
    jne .e3
    mov rsi, s_ext_arm_elf
    jmp .e3
.and:
    ; Android: .bin for AArch64 (default), .x64.bin for x86-64
    mov rsi, s_ext_android
    cmp dword [arch], ARCH_A64
    je .e3
    mov rsi, s_ext_x64_bin
.e3:
    call cstr_copy
    mov rax, outnamebuf
    ret

; ---- compiler memory ----------------------------------------------------------------------------
section .bss align=64
arena:          resb ARENA_MAX
namepool:       resb NAMEPOOL_MAX
code_buf:       resb CODE_MAX
data_buf:       resb DATA_MAX
rel_buf:        resb REL_MAX * 16
symtab:         resb SYM_MAX * 64
struct_tab:     resb STRUCT_MAX * 32
field_tab:      resb FIELD_MAX * 32
ptype_pool:     resq PTYPE_MAX
file_table:     resb FILE_MAX * 64
outbuf:         resb OUT_MAX
idata_buf:      resb 4096
strbuf:         resb 65536
errbuf:         resb 512
importbuf:      resb 1024
candbuf:        resb 2048
maindirbuf:     resb 1024
outnamebuf:     resb 1024
loop_stack:     resb MAXLOOP * 32
case_val:       resq 1024
case_pos:       resq 1024
ptmp_type:      resq MAXPARAM
ptmp_name:      resq MAXPARAM
ptmp_nlen:      resd MAXPARAM
binprec:        resb 256

err_msg:        resq 1
cg_vt:          resq CGI_COUNT
arch:           resd 1
slot_bytes:     resd 1
stack_limit:    resq 1
cur_file_name:  resq 1
arena_pos:      resq 1
namepool_pos:   resq 1
code_pos:       resq 1
data_pos:       resq 1
bss_pos:        resq 1
ptype_pos:      resq 1
rel_count:      resd 1
sym_count:      resd 1
struct_count:   resd 1
field_count:    resd 1
file_count:     resd 1
cur_module:     resd 1
cur_file_id:    resd 1
next_module_id: resd 1
pass:           resd 1
target:         resd 1
cur_class:      resd 1
cur_this_off:   resd 1
frame_size:     resd 1
loop_sp:        resd 1
case_sp:        resd 1
ptmp_count:     resd 1
agg_vis:        resd 1
agg_mnlen:      resd 1
agg_isctor:     resd 1
src_ptr:        resq 1
src_end:        resq 1
src_line:       resq 1
tk:             resq 1
tk_val:         resq 1
tk_ptr:         resq 1
tk_len:         resq 1
tk_line:        resq 1
e_type:         resq 1
e_lval:         resq 1
ret_chain:      resq 1
cur_func:       resq 1
frame_patch:    resq 1
agg_mname:      resq 1
agg_mtype:      resq 1
agg_gtype:      resq 1
main_dir:       resq 1
opt_input:      resq 1
opt_output:     resq 1
opt_version:    resq 1
opt_release:    resq 1
code_vaddr:     resq 1
data_vaddr:     resq 1
bss_vaddr:      resq 1
iat_vaddr:      resq 1
pe_data_rawsz:  resq 1
pe_idata_rva:   resq 1
pe_idata_size:  resq 1
pe_idata_rawsz: resq 1
pe_text_raw:    resq 1
pe_data_raw:    resq 1
pe_idata_raw:   resq 1
section .iatfix
iatfix_end:
section .text
