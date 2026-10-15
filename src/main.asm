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
s_linux_riscv64: db "linux-riscv64", 0
s_linux_rv64:   db "linux-rv64", 0
s_android_riscv64: db "android-riscv64", 0
s_android_rv64: db "android-rv64", 0
s_linux_loong:  db "linux-loongarch64", 0
s_linux_la64:   db "linux-la64", 0
s_android_loong: db "android-loongarch64", 0
s_ext_arm_elf:  db ".arm64.elf", 0
s_ext_x64_bin:  db ".x64.bin", 0
s_ext_rv_elf:   db ".riscv64.elf", 0
s_ext_rv_bin:   db ".riscv64.bin", 0
s_ext_la_elf:   db ".loongarch64.elf", 0
s_ext_la_bin:   db ".loongarch64.bin", 0
align 8
; target name, operating system, CPU architecture
target_table:
    dq s_linux
    dd TGT_LINUX, ARCH_X64
    dq s_linux_x64
    dd TGT_LINUX, ARCH_X64
    dq s_linux_arm64
    dd TGT_LINUX, ARCH_A64
    dq s_linux_riscv64
    dd TGT_LINUX, ARCH_RV64
    dq s_linux_rv64
    dd TGT_LINUX, ARCH_RV64
    dq s_linux_loong
    dd TGT_LINUX, ARCH_LA64
    dq s_linux_la64
    dd TGT_LINUX, ARCH_LA64
    dq s_windows
    dd TGT_WINDOWS, ARCH_X64
    dq s_win
    dd TGT_WINDOWS, ARCH_X64
    dq s_win64
    dd TGT_WINDOWS, ARCH_X64
    dq s_android
    dd TGT_ANDROID, ARCH_A64
    dq s_android_arm64
    dd TGT_ANDROID, ARCH_A64
    dq s_android_x64
    dd TGT_ANDROID, ARCH_X64
    dq s_android_riscv64
    dd TGT_ANDROID, ARCH_RV64
    dq s_android_rv64
    dd TGT_ANDROID, ARCH_RV64
    dq s_android_loong
    dd TGT_ANDROID, ARCH_LA64
    dq 0
s_ver_default:  db "1", 0
s_rel_default:  db "debug", 0
s_ext_linux:    db ".elf", 0
s_ext_win:      db ".exe", 0
s_ext_android:  db ".bin", 0
s_std_name:     db "<std>", 0
s_dfloat_name:  db "dfloat.a", 0
s_main:         db "main", 0
s_exit_name:    db "exit", 0
s_libdir1:      db "lib/", 0
s_libdir2:      db "/usr/lib/a/", 0
s_libdir3:      db "/usr/local/lib/a/", 0

s_usage:
    db "A compiler ", VERSION_NAME, " (version code ", '0'+VERSION_CODE, ")  -  Aytict, https://aytict.fi", 10
    db "Usage: ac [options] source.a          compile a program", 10
    db "       ac -c [options] source.a       compile to an object file (.ao)", 10
    db "       ac [options] a.ao b.ao ...     link object files into a program", 10
    db 10
    db "Options:", 10
    db "  -o FILE     output file (default: NAME-VERSION-RELEASE.EXT)", 10
    db "  -t TARGET   linux (default) | windows | android | linux-arm64 | android-x64 |", 10
    db "              linux-riscv64 | android-riscv64 | linux-loongarch64 | android-loongarch64", 10
    db "              linux = linux-x64, android = android-arm64, windows = windows x64", 10
    db "  -c          compile to an object file instead of a program", 10
    db "  -D NAME[=V] define a preprocessor macro (may be repeated)", 10
    db "  -E          print the preprocessed source and stop", 10
    db "  -v CODE     version code used in the default output name (default 1)", 10
    db "  -r TYPE     release type used in the default output name (default debug)", 10
    db "  -h          show this help", 10
    db "  --version   show the compiler version", 10
    db 0
s_version_text: db "ac ", VERSION_NAME, 10, 0
s_err_noinput:  db "no input file (try: ac -h)", 0
s_err_mixed:    db "object files (.ao) cannot be combined with source files or -c", 0
s_link_prog:    db "a.a", 0
s_err_onesrc:   db "only one source file can be compiled at a time (use -c and link the objects)", 0
s_ext_ao:       db ".ao", 0
s_err_badopt:   db "unknown option or missing value (try: ac -h)", 0
s_err_badtgt:   db "unknown target, use linux, windows, android, linux-arm64, android-x64, linux-riscv64, android-riscv64 or linux-loongarch64", 0
s_err_read:     db "cannot read the input file", 0
s_err_nomain:   db "no 'main' function found", 0
s_err_write:    db "cannot write the output file", 0
s_err_undef:    db "undefined function", 0
s_err_missing:  db "internal error: standard library function missing:", 0
s_err_nofile:   db "cannot find the imported file", 0
s_err_mainpar:  db "main may take at most (int argc, char** argv)", 0

; embedded modules written in A. EMB "name", "file": makes "import name;" work without any
; file on disk (a file next to the importing source still wins).
%macro EMB 2
    [section .rodata]
%%nm:   db %1, ".a", 0
%%lb:   db "<", %1, ">", 0
%%src:  incbin %2
        db 0
%%end:
    [section .data]
        dq %%nm, %%lb, %%src, %%end - %%src - 1, 0
    __SECT__
%endmacro

section .data
align 8
embedded_mods:
section .text
EMB "net",         "lib/net.a"
EMB "http",        "lib/http.a"
EMB "netaddr",     "lib/netaddr.a"
EMB "packet",      "lib/packet.a"
EMB "netif",       "lib/netif.a"
EMB "dns",         "lib/dns.a"
EMB "conn",        "lib/conn.a"
EMB "websocket",   "lib/websocket.a"
EMB "netutil",     "lib/netutil.a"
EMB "rawnet",      "lib/rawnet.a"
EMB "cpu",         "lib/cpu.a"
EMB "dfloat",      "lib/dfloat.a"
EMB "dmath",       "lib/dmath.a"
EMB "thread",      "lib/thread.a"
EMB "fixed",       "lib/fixed.a"
EMB "nn",          "lib/nn.a"
EMB "codec",       "lib/codec.a"
EMB "math",        "lib/math.a"
EMB "sort",        "lib/sort.a"
EMB "collections", "lib/collections.a"
EMB "strings",     "lib/strings.a"
EMB "datetime",    "lib/datetime.a"
EMB "encoding",    "lib/encoding.a"
EMB "hash",        "lib/hash.a"
EMB "secure",        "lib/secure.a"
EMB "des",           "lib/des.a"
EMB "bn",            "lib/bn.a"
EMB "rsa",           "lib/rsa.a"
EMB "ec",            "lib/ec.a"
EMB "x25519",       "lib/x25519.a"
EMB "aes",          "lib/aes.a"
EMB "chacha",       "lib/chacha.a"
EMB "x509",         "lib/x509.a"
EMB "tls",          "lib/tls.a"
EMB "gnet",          "lib/gnet.a"
EMB "ghtml",         "lib/ghtml.a"
EMB "wwebpage",      "lib/wwebpage.a"
EMB "wweb",          "lib/wweb.a"
EMB "os",          "lib/os.a"
EMB "path",        "lib/path.a"
EMB "csv",         "lib/csv.a"
EMB "regex",       "lib/regex.a"
EMB "utf8",        "lib/utf8.a"
EMB "random",      "lib/random.a"
EMB "decimal",     "lib/decimal.a"
EMB "bigint",      "lib/bigint.a"
EMB "log",         "lib/log.a"
EMB "testing",     "lib/testing.a"
EMB "cli",         "lib/cli.a"
EMB "json",        "lib/json.a"
EMB "cctype",      "lib/cctype.a"
EMB "climits",     "lib/climits.a"
EMB "cerrno",      "lib/cerrno.a"
EMB "cassert",     "lib/cassert.a"
EMB "cstring",     "lib/cstring.a"
EMB "cstdlib",     "lib/cstdlib.a"
EMB "cstdio",      "lib/cstdio.a"
EMB "ctime",       "lib/ctime.a"
EMB "cunistd",     "lib/cunistd.a"
EMB "cmath",       "lib/cmath.a"
EMB "cfloat",      "lib/cfloat.a"
EMB "clib",        "lib/clib.a"
EMB "clocale",     "lib/clocale.a"
EMB "cwchar",      "lib/cwchar.a"
EMB "ccomplex",    "lib/ccomplex.a"
EMB "gfxfont",      "lib/gfxfont.a"
EMB "gfx",          "lib/gfx.a"
EMB "adp",          "lib/adp.a"
EMB "wsrv",         "lib/wsrv.a"
EMB "gui",          "lib/gui.a"
EMB "guix",         "lib/guix.a"
EMB "glock",        "lib/glock.a"
EMB "gterm",         "lib/gterm.a"
EMB "gimg",          "lib/gimg.a"
EMB "wvnc",         "lib/wvnc.a"
EMB "wfb",          "lib/wfb.a"
EMB "syscrypt",     "lib/syscrypt.a"
EMB "dm",           "lib/dm.a"
section .data
        dq 0
section .rodata
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
%define IAT_K32             39
%define IAT_SLOTS           (IAT_K32 + 1 + 20 + 1 + 8 + 1 + 1 + 1)   ; kernel32 + null + ws2_32 + null + iphlpapi + null + advapi32 + null

bn_write:   db "__write", 0
bn_read:    db "__read", 0
bn_exit:    db "__exit", 0
bn_syscall: db "__syscall", 0
bn_cmdline: db "__cmdline", 0
bn_open:    db "__open", 0
bn_winapi:  db "__winapi", 0
bn_winapix: db "__winapix", 0
bn_setjmp:  db "setjmp", 0
bn_longjmp: db "longjmp", 0
s_os_name:  db "__OS", 0
s_arch_name: db "__ARCH", 0
s_func_name: db "func", 0
bn_close:   db "__close", 0
s_win_init: db "__win_init_args", 0
s_win_argv: db "__win_argv_get", 0

align 8
; name, parameter count, then start/end of the runtime code for: x86-64 Linux/Android,
; Windows x64, AArch64, RISC-V 64, LoongArch64 Linux/Android (96 bytes per entry)
builtin_tab:
    dq bn_write, 3, bl_lin_write, bl_lin_write_end, bl_win_write, bl_win_write_end, bl_a64_write, bl_a64_write_end, bl_rv64_write, bl_rv64_write_end, bl_la64_write, bl_la64_write_end
    dq bn_read, 3, bl_lin_read, bl_lin_read_end, bl_win_read, bl_win_read_end, bl_a64_read, bl_a64_read_end, bl_rv64_read, bl_rv64_read_end, bl_la64_read, bl_la64_read_end
    dq bn_exit, 1, bl_lin_exit, bl_lin_exit_end, bl_win_exit, bl_win_exit_end, bl_a64_exit, bl_a64_exit_end, bl_rv64_exit, bl_rv64_exit_end, bl_la64_exit, bl_la64_exit_end
    dq bn_syscall, 7, bl_lin_syscall, bl_lin_syscall_end, bl_win_fail, bl_win_fail_end, bl_a64_syscall, bl_a64_syscall_end, bl_rv64_syscall, bl_rv64_syscall_end, bl_la64_syscall, bl_la64_syscall_end
    dq bn_winapi, 5, bl_lin_fail, bl_lin_fail_end, bl_win_winapi, bl_win_winapi_end, bl_a64_fail, bl_a64_fail_end, bl_rv64_fail, bl_rv64_fail_end, bl_la64_fail, bl_la64_fail_end
    dq bn_winapix, 11, bl_lin_fail, bl_lin_fail_end, bl_win_winapix, bl_win_winapix_end, bl_a64_fail, bl_a64_fail_end, bl_rv64_fail, bl_rv64_fail_end, bl_la64_fail, bl_la64_fail_end
    dq bn_setjmp, 1, bl_lin_setjmp, bl_lin_setjmp_end, bl_lin_setjmp, bl_lin_setjmp_end, bl_a64_setjmp, bl_a64_setjmp_end, bl_rv64_setjmp, bl_rv64_setjmp_end, bl_la64_setjmp, bl_la64_setjmp_end
    dq bn_longjmp, 2, bl_lin_longjmp, bl_lin_longjmp_end, bl_lin_longjmp, bl_lin_longjmp_end, bl_a64_longjmp, bl_a64_longjmp_end, bl_rv64_longjmp, bl_rv64_longjmp_end, bl_la64_longjmp, bl_la64_longjmp_end
    dq bn_cmdline, 0, bl_lin_cmdline, bl_lin_cmdline_end, bl_win_cmdline, bl_win_cmdline_end, bl_a64_cmdline, bl_a64_cmdline_end, bl_rv64_cmdline, bl_rv64_cmdline_end, bl_la64_cmdline, bl_la64_cmdline_end
    dq bn_open, 2, bl_lin_open, bl_lin_open_end, bl_win_open, bl_win_open_end, bl_a64_open, bl_a64_open_end, bl_rv64_open, bl_rv64_open_end, bl_la64_open, bl_la64_open_end
    dq bn_close, 1, bl_lin_close, bl_lin_close_end, bl_win_close, bl_win_close_end, bl_a64_close, bl_a64_close_end, bl_rv64_close, bl_rv64_close_end, bl_la64_close, bl_la64_close_end
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

bl_lin_fail:
    mov rax, -1
    ret
bl_lin_fail_end:
bl_win_fail:
    mov rax, -1
    ret
bl_win_fail_end:
; __winapi(index, a1, a2, a3, a4): call the imported function in IAT slot 'index'
bl_win_winapi:
    mov rcx, [rsp+32]
    mov rdx, [rsp+24]
    mov r8,  [rsp+16]
    mov r9,  [rsp+8]
    mov rax, [rsp+40]
    mov r12, rsp
    sub rsp, 48
    and rsp, -16
    IATLEA
    db 0x41, 0xFF, 0x14, 0xC2
    mov rsp, r12
    ret
bl_win_winapi_end:
; __winapix(index, a1 .. a10): like __winapi but with up to ten arguments (stack arguments a5..a10)
bl_win_winapix:
    mov r12, rsp
    sub rsp, 112
    and rsp, -16
    mov rax, [r12+48]
    mov [rsp+32], rax
    mov rax, [r12+40]
    mov [rsp+40], rax
    mov rax, [r12+32]
    mov [rsp+48], rax
    mov rax, [r12+24]
    mov [rsp+56], rax
    mov rax, [r12+16]
    mov [rsp+64], rax
    mov rax, [r12+8]
    mov [rsp+72], rax
    mov rcx, [r12+80]
    mov rdx, [r12+72]
    mov r8,  [r12+64]
    mov r9,  [r12+56]
    mov rax, [r12+88]
    IATLEA
    db 0x41, 0xFF, 0x14, 0xC2
    mov rsp, r12
    ret
bl_win_winapix_end:
bl_lin_cmdline:
    xor eax, eax
    ret
bl_lin_cmdline_end:
; setjmp(buf): saves the frame pointer, the stack pointer after the return and the return address in buf[0..2];
; returns 0. longjmp(buf, val) makes that setjmp call return val (1 if val is 0) again.
; (the same code for Linux, Android and Windows: the generated code keeps no state in other registers)
bl_lin_setjmp:
    mov rax, [rsp+8]
    mov [rax], rbp
    lea rdx, [rsp+8]
    mov [rax+8], rdx
    mov rdx, [rsp]
    mov [rax+16], rdx
    xor eax, eax
    ret
bl_lin_setjmp_end:
bl_lin_longjmp:
    mov rax, [rsp+8]
    mov rdx, [rsp+16]
    test rax, rax
    jnz .v
    mov eax, 1
.v: mov rbp, [rdx]
    mov rcx, [rdx+16]
    mov rsp, [rdx+8]
    jmp rcx
bl_lin_longjmp_end:
; __open(path, mode): mode 0 = read, 1 = write (create / truncate), 2 = append
bl_lin_open:
    mov rdi, [rsp+16]
    mov rax, [rsp+8]
    xor esi, esi
    cmp rax, 1
    jne .n1
    mov esi, 0x241
    jmp .go
.n1:
    cmp rax, 2
    jne .go
    mov esi, 0x441
.go:
    mov edx, 0x1A4
    mov eax, 2
    syscall
    ret
bl_lin_open_end:
bl_lin_close:
    mov rdi, [rsp+8]
    mov eax, 3
    syscall
    ret
bl_lin_close_end:

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
    sub rsp, 64
    and rsp, -16
    cmp rax, 2
    ja .have
    mov rcx, -10
    sub rcx, rax
    IATCALL IAT_GetStdHandle
.have:
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
    sub rsp, 64
    and rsp, -16
    cmp rax, 2
    ja .have
    mov rcx, -10
    sub rcx, rax
    IATCALL IAT_GetStdHandle
.have:
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
bl_win_open:
    mov rcx, [rsp+16]
    mov rax, [rsp+8]
    mov edx, 0x80000000
    mov r10d, 3
    cmp rax, 1
    jne .n1
    mov edx, 0x40000000
    mov r10d, 2
    jmp .go
.n1:
    cmp rax, 2
    jne .go
    mov edx, 4
    mov r10d, 4
.go:
    mov r12, rsp
    sub rsp, 80
    and rsp, -16
    mov r8d, 3
    xor r9d, r9d
    mov [rsp+32], r10
    mov qword [rsp+40], 0x80
    mov qword [rsp+48], 0
    IATCALL IAT_CreateFileA
    mov rsp, r12
    ret
bl_win_open_end:
bl_win_close:
    mov rcx, [rsp+8]
    mov r12, rsp
    sub rsp, 48
    and rsp, -16
    IATCALL IAT_CloseHandle
    mov rsp, r12
    ret
bl_win_close_end:
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
    db "SetConsoleMode", 0      ; slot 7
    db "Sleep", 0               ; slot 8
    db "GetTickCount64", 0      ; slot 9
    db "GetFileType", 0         ; slot 10
    db "GetSystemTimeAsFileTime", 0   ; slot 11
    db "GetEnvironmentVariableA", 0   ; slot 12
    db "DeleteFileA", 0         ; slot 13
    db "CreateDirectoryA", 0    ; slot 14
    db "MoveFileA", 0           ; slot 15
    db "GetCurrentDirectoryA", 0 ; slot 16
    db "GetFileSize", 0         ; slot 17
    db "FindFirstFileA", 0      ; slot 18
    db "FindNextFileA", 0       ; slot 19
    db "FindClose", 0           ; slot 20
    db "SetFilePointerEx", 0    ; slot 21
    db "SetCurrentDirectoryA", 0 ; slot 22
    db "RemoveDirectoryA", 0    ; slot 23
    db "GetCurrentProcessId", 0 ; slot 24
    db "GetFileAttributesA", 0  ; slot 25
    db "MoveFileExA", 0         ; slot 26
    db "SetEndOfFile", 0        ; slot 27
    db "FlushFileBuffers", 0    ; slot 28
    db "GetFileSizeEx", 0       ; slot 29
    db "CreateProcessA", 0      ; slot 30
    db "WaitForSingleObject", 0 ; slot 31
    db "GetExitCodeProcess", 0  ; slot 32
    db "GetFileAttributesExA", 0 ; slot 33
    db "VirtualAlloc", 0        ; slot 34
    db "GetFullPathNameA", 0    ; slot 35
    db "SetEnvironmentVariableA", 0 ; slot 36
    db "CreatePipe", 0          ; slot 37
    db "SetHandleInformation", 0 ; slot 38
    db 0
; WS2_32.DLL imports: slots 40..59 (slot 39 is the null terminator of the kernel32 list)
imp_names_ws2:
    db "WSAStartup", 0
    db "socket", 0
    db "connect", 0
    db "bind", 0
    db "listen", 0
    db "accept", 0
    db "send", 0
    db "recv", 0
    db "closesocket", 0
    db "sendto", 0              ; slot 49
    db "recvfrom", 0            ; slot 50
    db "setsockopt", 0          ; slot 51
    db "gethostbyname", 0       ; slot 52
    db "getsockname", 0         ; slot 53
    db "shutdown", 0            ; slot 54
    db "getpeername", 0         ; slot 55
    db "WSAPoll", 0             ; slot 56
    db "ioctlsocket", 0         ; slot 57
    db "getsockopt", 0          ; slot 58
    db "gethostname", 0         ; slot 59
    db 0
; IPHLPAPI.DLL imports: slots 61..68 (slot 60 is the null terminator of the ws2_32 list)
imp_names_iph:
    db "GetAdaptersInfo", 0     ; slot 61
    db "GetIpNetTable", 0       ; slot 62
    db "GetIpForwardTable", 0   ; slot 63
    db "GetTcpTable", 0         ; slot 64
    db "IcmpCreateFile", 0      ; slot 65
    db "IcmpSendEcho", 0        ; slot 66
    db "IcmpCloseHandle", 0     ; slot 67
    db "GetUdpTable", 0         ; slot 68
    db 0
; ADVAPI32.DLL imports: slot 70 (slot 69 is the null terminator of the iphlpapi list)
imp_names_adv:
    db "SystemFunction036", 0   ; slot 70: RtlGenRandom
    db 0
s_advapi32: db "ADVAPI32.DLL", 0
s_iphlpapi: db "IPHLPAPI.DLL", 0
s_kernel32: db "KERNEL32.DLL", 0
s_ws2_32:   db "WS2_32.DLL", 0

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
    ; the preprocessor
    mov rsi, r13
    mov rdx, rbx
    mov rdi, r12
    call pp_file
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
    mov dword [rcx+32], 0                ; read from disk
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
    ; modules built into the compiler
    mov rbx, embedded_mods
.emb:
    cmp qword [rbx], 0
    je .noemb
    mov rdi, importbuf
    mov rsi, [rbx]
    call cstr_eq
    test eax, eax
    jz .embnext
    mov rax, [rbx+32]
    jmp .found
.embnext:
    add rbx, 40
    jmp .emb
.noemb:
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
    cmp dword [obj_mode], 0
    je .go
    cmp dword [rax+32], 0
    je .go
    call obj_note_need                  ; the link step has to import this module as well
.go:
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
    ; object mode: the data of the built-in libraries is not part of the object
    xor ebx, ebx
    cmp dword [obj_mode], 0
    je .noswap
    cmp dword [r12+32], 0
    je .noswap
    cmp dword [foreign_active], 0
    jne .noswap
    mov dword [foreign_active], 1
    mov ebx, 1
    call swap_foreign
.noswap:
    sub rsp, 128
    mov rdi, rsp
    call lex_save
    mov rax, [r12+8]
    ; skip a UTF-8 byte order mark (Windows editors add it)
    cmp byte [rax], 0xEF
    jne .nobom
    cmp byte [rax+1], 0xBB
    jne .nobom
    cmp byte [rax+2], 0xBF
    jne .nobom
    add rax, 3
.nobom:
    mov [src_ptr], rax
    mov [cur_src_base], rax
    add rax, [r12+16]
    mov [src_end], rax
    mov qword [src_line], 1
    mov qword [tk_line], 1
    mov rax, [r12]
    mov [cur_file_name], rax
    mov eax, [r12+24]
    mov [cur_file_id], eax
    mov dword [cur_module], 0
    mov eax, [in_amodule]               ; the imported file starts outside of any a_module block
    mov [rsp+112], eax
    mov dword [in_amodule], 0
    mov eax, [block_depth]
    mov [rsp+116], eax
    mov dword [block_depth], 0
    call next_token
    call parse_items
    mov rsi, rsp
    call lex_restore
    mov eax, [rsp+112]
    mov [in_amodule], eax
    mov eax, [rsp+116]
    mov [block_depth], eax
    add rsp, 128
    test ebx, ebx
    jz .skip
    call swap_foreign
    mov dword [foreign_active], 0
.skip:
    mov eax, [r12+24]
    mov [last_file_id], eax
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
    mov rdi, [main_entry]
    call compile_file
    ; the soft-float runtime (cmath + cfloat + printDouble ...) when the program mentions double or a floating literal
    cmp dword [need_float], 0
    je .nofloat
    mov dword [cur_module], 0
    mov dword [cur_class], -1
    mov rdi, [float_entry]
    call compile_file
.nofloat:
    ret

; ---- builtins ------------------------------------------------------------------------------
; builtin_col -> eax = byte offset of the (start, end) columns for the current target
builtin_col:
    mov eax, 16
    cmp dword [arch], ARCH_A64
    jne .a1
    mov eax, 48
    ret
.a1:
    cmp dword [arch], ARCH_RV64
    jne .a2
    mov eax, 64
    ret
.a2:
    cmp dword [arch], ARCH_LA64
    jne .x
    mov eax, 80
    ret
.x: cmp dword [target], TGT_WINDOWS
    jne .r
    mov eax, 32
.r: ret

register_builtins:
    push rbx
    push r12
    ; predefined constants __OS (0 Linux, 1 Windows, 2 Android) and __ARCH (0 x86-64, 1 ARM64)
    mov rdi, s_os_name
    mov esi, 4
    mov edx, S_CONST
    call sym_new
    mov dword [rax+SYM_TYPE], TY_INT
    mov ecx, [target]
    mov [rax+SYM_VAL], rcx
    mov rdi, s_arch_name
    mov esi, 6
    mov edx, S_CONST
    call sym_new
    mov qword [rax+SYM_TYPE], TY_INT
    mov ecx, [arch]
    mov [rax+SYM_VAL], rcx
    ; the type name "func" (a function pointer)
    mov rdi, s_func_name
    mov esi, 4
    mov edx, S_ENUM
    call sym_new
    mov dword [rax+SYM_FLAGS], F_BUILTIN | F_DEFINED | F_FUNCTYPE
    mov qword [rax+SYM_OWNER], -1
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
    add rbx, 96
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
    ; Windows stack probe helper (used by every function prologue)
    cmp dword [target], TGT_WINDOWS
    jne .nochk
    mov rax, [code_pos]
    mov [chkstk_pos], rax
    mov rsi, chkstk_blob
    mov ecx, chkstk_blob_end - chkstk_blob
    call emit_bytes
.nochk:
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
    add rbx, 96
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

; begin_codegen_pass: resets the output state before a code generating pass
begin_codegen_pass:
    mov qword [code_pos], 0
    mov eax, [rel_base]
    mov [rel_count], eax
    mov dword [loop_sp], 0
    mov dword [case_sp], 0
    mov dword [edge_count], 0
    xor edi, edi
    call rewind_code
    mov qword [last_label], 0
    ; every function starts again as "not yet defined"
    xor edx, edx
.l:
    cmp edx, [sym_count]
    jae .done
    mov rax, rdx
    shl rax, 6
    add rax, symtab
    cmp dword [rax+SYM_KIND], S_FUNC
    jne .n
    mov qword [rax+SYM_VAL], -1
    mov dword [rax+SYM_PATCH], 0
.n:
    inc edx
    jmp .l
.done:
    cmp dword [obj_mode], 0
    jne .noprologue                     ; an object has no entry stub and no runtime blobs
    jmp emit_prologue
.noprologue:
    ret

; compute_reachable: marks every function reachable from the entry stub as F_USED
compute_reachable:
    ; virtual methods are reachable through the vtables
    xor ecx, ecx
.vroot:
    cmp ecx, [sym_count]
    jae .again
    mov rax, rcx
    shl rax, 6
    add rax, symtab
    test dword [rax+SYM_FLAGS], F_VIRTUAL
    jz .vnext
    or dword [rax+SYM_FLAGS], F_USED
.vnext:
    inc ecx
    jmp .vroot
.again:
    xor r8d, r8d                    ; changed
    xor ecx, ecx
.e:
    cmp ecx, [edge_count]
    jae .chk
    mov eax, [edge_from + rcx*4]
    shl rax, 6
    add rax, symtab
    test dword [rax+SYM_FLAGS], F_USED
    jz .skip
    mov eax, [edge_to + rcx*4]
    shl rax, 6
    add rax, symtab
    test dword [rax+SYM_FLAGS], F_USED
    jnz .skip
    or dword [rax+SYM_FLAGS], F_USED
    mov r8d, 1
.skip:
    inc ecx
    jmp .e
.chk:
    test r8d, r8d
    jnz .again
    ret

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
    ; functions whose address is used as a value must be defined
    xor edx, edx
.r:
    cmp edx, [rel_count]
    jae .rdone
    mov rax, rdx
    shl rax, 4
    add rax, rel_buf
    cmp dword [rax+4], R_CODE
    je .rchk
    cmp dword [rax+4], R_CODE64
    jne .rn
.rchk:
    mov eax, [rax+8]
    shl rax, 6
    add rax, symtab
    cmp qword [rax+SYM_VAL], -1
    jne .rn
    mov rcx, [rax+SYM_NAME]
    mov [tk_ptr], rcx
    mov ecx, [rax+SYM_NLEN]
    mov [tk_len], ecx
    mov qword [cur_file_name], 0
    mov edi, s_err_undef
    call fatal_error_tok
.rn:
    inc edx
    jmp .r
.rdone:
    ret

; ---- relocations ---------------------------------------------------------------------------
; apply_relocs: [code_vaddr] [data_vaddr] [bss_vaddr] [iat_vaddr] must be set
apply_relocs:
    cmp dword [arch], ARCH_A64
    je apply_relocs_a64
    cmp dword [arch], ARCH_RV64
    je apply_relocs_rv64
    cmp dword [arch], ARCH_LA64
    je apply_relocs_la64
    jmp apply_relocs_x86

; install_backend: edi = architecture; fills the primitive table
install_backend:
    mov [arch], edi
    mov esi, cg_tab_x86
    mov dword [slot_bytes], 8
    cmp edi, ARCH_A64
    jne .rv
    mov esi, cg_tab_a64
    mov dword [slot_bytes], 16
    jmp .copy
.rv:
    cmp edi, ARCH_RV64
    jne .la
    mov esi, cg_tab_rv64
    mov dword [slot_bytes], 16
    jmp .copy
.la:
    cmp edi, ARCH_LA64
    jne .copy
    mov esi, cg_tab_la64
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
    cmp dword [arch], ARCH_RV64
    jne .b
    mov ebx, 0xF3                           ; EM_RISCV
.b:
    cmp dword [arch], ARCH_LA64
    jne .c
    mov r13d, 0x10000                       ; LoongArch: 64 KiB covers every page size
    mov ebx, 0x102                          ; EM_LOONGARCH
.c:
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
%define PE_IDATA_ILT 100
%define PE_IDATA_IAT (100 + IAT_SLOTS*8)
%define PE_IDATA_NAMES (PE_IDATA_IAT + IAT_SLOTS*8)

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
    mov qword [rdi+72], 0x800000
    mov qword [rdi+80], 0x10000
    mov qword [rdi+88], 0x100000
    mov qword [rdi+96], 0x1000
    mov dword [rdi+108], 16
    mov rax, [pe_idata_rva]
    mov [rdi+112+8], eax                    ; import directory
    mov dword [rdi+112+8+4], 80
    add rax, PE_IDATA_IAT
    mov [rdi+112+96], eax                   ; IAT directory
    mov dword [rdi+112+96+4], IAT_SLOTS*8
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

; idata_list: rsi = list of import names (ends with an empty string), rbx = section RVA,
; r12 = running offset of the name area, r13 = IAT slot index. Advances rsi / r12 / r13.
idata_list:
.imp:
    cmp byte [rsi], 0
    je .done
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
.done:
    inc rsi
    ret

; build_idata: builds the import section contents (KERNEL32 + WS2_32) into idata_buf using
; the RVA in [pe_idata_rva]. -> rax = size
build_idata:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov rbx, [pe_idata_rva]
    mov r12d, PE_IDATA_NAMES
    xor r13d, r13d
    mov rsi, imp_names
    call idata_list
    inc r13d                                ; null slot ends the kernel32 thunk array
    mov rsi, imp_names_ws2
    call idata_list
    inc r13d                                ; null slot ends the ws2_32 thunk array
    mov rsi, imp_names_iph
    call idata_list
    inc r13d                                ; null slot ends the iphlpapi thunk array
    mov rsi, imp_names_adv
    call idata_list
    ; DLL name strings
    lea rdi, [idata_buf + r12]
    mov r14, rdi
    mov rsi, s_kernel32
    call cstr_copy
    lea rax, [r12 + 13]
    mov r12, rax
    lea rdi, [idata_buf + r12]
    mov r13, rdi
    mov rsi, s_ws2_32
    call cstr_copy
    lea rax, [r12 + 11]
    mov r12, rax
    lea rdi, [idata_buf + r12]
    mov r15, rdi
    mov rsi, s_iphlpapi
    call cstr_copy
    lea rax, [r12 + 13]
    mov r12, rax
    lea rdi, [idata_buf + r12]
    mov rbp, rdi
    mov rsi, s_advapi32
    call cstr_copy
    lea rax, [r12 + 13]
    mov r12, rax
    sub rbp, idata_buf
    sub r14, idata_buf
    sub r13, idata_buf
    sub r15, idata_buf
    ; descriptor 0: KERNEL32
    lea rax, [rbx + PE_IDATA_ILT]
    mov [idata_buf], eax
    lea rax, [rbx + r14]
    mov [idata_buf + 12], eax
    lea rax, [rbx + PE_IDATA_IAT]
    mov [idata_buf + 16], eax
    ; descriptor 1: WS2_32 (its thunks start after the 8 kernel32 slots)
    lea rax, [rbx + PE_IDATA_ILT + (IAT_K32+1)*8]
    mov [idata_buf + 20], eax
    lea rax, [rbx + r13]
    mov [idata_buf + 32], eax
    lea rax, [rbx + PE_IDATA_IAT + (IAT_K32+1)*8]
    mov [idata_buf + 36], eax
    ; descriptor 2: IPHLPAPI
    lea rax, [rbx + PE_IDATA_ILT + (IAT_K32+1+20+1)*8]
    mov [idata_buf + 40], eax
    lea rax, [rbx + r15]
    mov [idata_buf + 52], eax
    lea rax, [rbx + PE_IDATA_IAT + (IAT_K32+1+20+1)*8]
    mov [idata_buf + 56], eax
    ; descriptor 3: ADVAPI32
    lea rax, [rbx + PE_IDATA_ILT + (IAT_K32+1+20+1+8+1)*8]
    mov [idata_buf + 60], eax
    lea rax, [rbx + rbp]
    mov [idata_buf + 72], eax
    lea rax, [rbx + PE_IDATA_IAT + (IAT_K32+1+20+1+8+1)*8]
    mov [idata_buf + 76], eax
    mov rax, r12
    pop rbp
    pop r15
    pop r14
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
    cmp word [rbx], 0x442D              ; -D
    je .define
    cmp word [rbx], 0x452D              ; -E
    jne .notE
    cmp byte [rbx+2], 0
    jne .notE
    mov dword [opt_E], 1
    jmp .arg
.notE:
    cmp word [rbx], 0x632D              ; -c : compile to an object file
    jne .notC
    cmp byte [rbx+2], 0
    jne .notC
    mov dword [obj_mode], 1
    jmp .arg
.notC:
    cmp byte [rbx], '-'
    je .badopt
    mov rdi, rbx
    call cstrlen
    cmp rax, 3
    jb .source
    cmp byte [rbx+rax-1], 'o'
    jne .source
    cmp byte [rbx+rax-2], 'a'
    jne .source
    cmp byte [rbx+rax-3], '.'
    jne .source
    ; an object file: the program is linked
    mov ecx, [opt_nobjs]
    cmp ecx, 64
    jae .badopt
    mov [opt_objs + rcx*8], rbx
    inc dword [opt_nobjs]
    mov dword [link_mode], 1
    jmp .arg
.source:
    cmp qword [opt_input], 0
    je .src1
    mov edi, s_err_onesrc
    call fatal_error
.src1:
    mov [opt_input], rbx
    jmp .arg
.define:
    ; -DNAME   -DNAME=value   -D NAME=value
    lea rax, [rbx+2]
    cmp byte [rax], 0
    jne .def1
    call .value
.def1:
    mov ecx, [opt_ndefs]
    cmp ecx, 32
    jae .badopt
    mov [opt_defs + rcx*8], rax
    inc dword [opt_ndefs]
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
    mov r12, target_table
.tt:
    mov rsi, [r12]
    test rsi, rsi
    jz .tbad
    mov rdi, rbx
    call cstr_eq
    test eax, eax
    jnz .tfound
    add r12, 16
    jmp .tt
.tfound:
    mov eax, [r12+8]
    mov [target], eax
    mov eax, [r12+12]
    mov [arch], eax
    jmp .arg
.tbad:
    mov edi, s_err_badtgt
    call fatal_error
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
    mov qword [data_pos_f], FOREIGN_DATA_BASE
    mov qword [bss_pos_f], FOREIGN_BSS_BASE
    cmp dword [link_mode], 0
    je .nolink
    cmp qword [opt_input], 0
    je .linkname
    mov edi, s_err_mixed
    call fatal_error
.linkname:
    cmp dword [obj_mode], 0
    je .linkok
    mov edi, s_err_mixed
    call fatal_error
.linkok:
    mov qword [opt_input], s_link_prog      ; output name a-<version>-<release>
.nolink:
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
    mov rbx, embedded_mods
.regemb:
    cmp qword [rbx], 0
    je .regdone
    mov rdi, [rbx+8]
    mov rsi, [rbx+16]
    mov rdx, [rbx+24]
    call add_embedded_file
    mov [rbx+32], rcx
    add rbx, 40
    jmp .regemb
.regdone:
    ; the entry of the embedded float runtime
    mov rbx, embedded_mods
.findfl:
    cmp qword [rbx], 0
    je .regdone2
    mov rdi, [rbx]
    mov rsi, s_dfloat_name
    call cstr_eq
    test eax, eax
    jnz .foundfl
    add rbx, 40
    jmp .findfl
.foundfl:
    mov rax, [rbx+32]
    mov [float_entry], rax
.regdone2:
    call pp_init
    cmp dword [link_mode], 0
    je .srcmain
    call link_load_objects              ; reads the objects and makes the program text that imports their modules
    jmp .mainset
.srcmain:
    mov rdi, [opt_input]
    call file_try
.mainset:
    mov [main_entry], rax
    cmp dword [opt_E], 0
    je .noE
    ; -E: print the preprocessed source and stop
    test rax, rax
    jz .noE
    mov rsi, [rax+8]
    mov rdx, [rax+16]
    mov edi, 1
    mov eax, SYS_WRITE
    syscall
    xor edi, edi
    jmp sys_exit
.noE:
    mov rax, [main_entry]
    test rax, rax
    jnz .loaded
    mov edi, s_err_read
    call fatal_error
.loaded:
    ; --- pass 1
    call register_builtins
    mov dword [pass], 1
    call compile_all
    ; --- pass 2: compile everything (reports every error) and record the call graph
    mov eax, [sym_count]
    mov [sym_base], eax
    mov eax, [rel_count]
    mov [rel_base], eax
    mov rax, [data_pos]
    mov [data_base], rax
    mov rax, [data_pos_f]
    mov [data_base_f], rax
    mov dword [pass], 2
    call begin_codegen_pass
    call compile_all
    cmp dword [obj_mode], 0
    je .o_noroots
    call obj_mark_roots                 ; every function of this unit is part of the object
.o_noroots:
    cmp dword [link_mode], 0
    je .l_noroots
    call link_mark_roots                ; library functions that the objects call must be kept
.l_noroots:
    call compute_reachable
    ; --- pass 3: the real output, only functions reachable from main
    mov eax, [sym_base]
    mov [sym_count], eax
    mov rax, [data_base]
    mov [data_pos], rax
    mov rax, [data_base_f]
    mov [data_pos_f], rax
    mov dword [pass], 3
    call begin_codegen_pass
    call compile_all
    mov qword [cur_file_name], 0
    cmp dword [obj_mode], 0
    jne .write_obj
    cmp dword [link_mode], 0
    je .l_noplace
    call link_place                     ; puts the objects behind the library code and resolves the symbols
.l_noplace:
    call check_undefined
    ; --- write the image
    cmp dword [target], TGT_WINDOWS
    je .pe
    call build_elf
    jmp .written
.pe:
    call build_pe
    jmp .written
.write_obj:
    call write_object
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
    mov dword [rcx+32], 1                ; built into the compiler
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
    mov rsi, s_ext_ao
    cmp dword [obj_mode], 0
    jne .e3
    mov rsi, s_ext_linux
    cmp dword [target], TGT_WINDOWS
    jne .e1
    mov rsi, s_ext_win
    jmp .e3
.e1:
    ; Linux: .elf (x86-64), .arm64.elf, .riscv64.elf, .loongarch64.elf; Android: .bin, .x64.bin, .riscv64.bin, ...
    cmp dword [target], TGT_ANDROID
    je .and
    cmp dword [arch], ARCH_A64
    jne .e1a
    mov rsi, s_ext_arm_elf
    jmp .e3
.e1a:
    cmp dword [arch], ARCH_RV64
    jne .e1b
    mov rsi, s_ext_rv_elf
    jmp .e3
.e1b:
    cmp dword [arch], ARCH_LA64
    jne .e3
    mov rsi, s_ext_la_elf
    jmp .e3
.and:
    mov rsi, s_ext_android
    cmp dword [arch], ARCH_A64
    je .e3
    mov rsi, s_ext_x64_bin
    cmp dword [arch], ARCH_X64
    je .e3
    mov rsi, s_ext_rv_bin
    cmp dword [arch], ARCH_RV64
    je .e3
    mov rsi, s_ext_la_bin
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
idata_buf:      resb 8192
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
ptmp_def:       resq MAXPARAM
ptmp_name:      resq MAXPARAM
ptmp_nlen:      resd MAXPARAM
binprec:        resb 256

err_msg:        resq 1
data_base:      resq 1
sym_base:       resd 1
rel_base:       resd 1
edge_count:     resd 1
edge_from:      resd EDGE_MAX
edge_to:        resd EDGE_MAX
main_entry:     resq 1
pk_pos:         resq 1
last_label:     resq 1
pk_end:         resq 1
imm_pos:        resq 1
imm_end:        resq 1
imm_val:        resq 1
ld_pos:         resq 1
ld_end:         resq 1
cmp_pos:        resq 1
cmp_end:        resq 1
pk_off:         resd 1
pi_pos:         resq 1
pi_end:         resq 1
pi_step:        resq 1
pi_type:        resq 1
pi_off:         resd 1
ld_off:         resd 1
ld_size:        resd 1
cmp_cc:         resd 1
cur_src_base:   resq 1
tk_start:       resq 1
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
ptmp_nreq:      resd 1
ptmp_variadic:  resd 1
cur_va_cnt:     resd 1
agg_vis:        resd 1
agg_union:      resd 1
agg_virtual:    resd 1
in_amodule:     resd 1
need_float:     resd 1
float_entry:    resq 1
lf_tmp:         resq 1
lf_dlen:        resq 1
lf_alen:        resq 1
lf_blen:        resq 1
lf_ex:          resd 1
init_count:     resq 1
obj_mode:       resd 1                  ; ac -c : the output is an object file
link_mode:      resd 1                  ; the inputs are object files
ext_reloc_sym:  resd 1
foreign_active: resd 1
extern_decl:    resd 1
opt_nobjs:      resd 1
data_pos_f:     resq 1
bss_pos_f:      resq 1
data_base_f:    resq 1
opt_objs:       resq 64
opt_E:          resd 1
init_mode:      resd 1
defer_n:        resd 1
agg_anon_ptr:   resq 1
agg_anon_len:   resd 1
agg_anon_nt:    resd 1
fp_pending:     resd 1
fp_after:       resb 128
call_ctr:       resd 1
lbl_n:          resd 1
lbl_tmp:        resq 1
lbl_tlen:       resd 1
alignb 16
lbl_tab:        resb 32*64
blk_nest:       resd 1
fn_body_flag:   resd 1
alignb 16
defer_buf:      resb 128*16
alignb 16
lf_bnD:         resd 512
lf_bnA:         resd 1024
lf_bnB:         resd 1024
block_depth:    resd 1
sq_string:      resd 1
str_term:       resd 1
last_file_id:   resd 1
selbuf:         resb 1024
force_direct:   resd 1
agg_base:       resd 1
st_base:        resd STRUCT_MAX         ; index of the base class + 1 (0 = none)
st_vptr:        resd STRUCT_MAX         ; offset of the vtable pointer in the object + 1 (0 = none)
st_vcount:      resd STRUCT_MAX         ; number of virtual methods
st_vt:          resd STRUCT_MAX         ; offset of the vtable in the data section + 1
vt_method:      resd STRUCT_MAX * VT_MAX ; per class: symbol index of the method in each vtable slot
sym_vslot:      resd SYM_MAX            ; per virtual method symbol: its vtable slot
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
chkstk_pos:     resq 1
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
