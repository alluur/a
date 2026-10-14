; =============================================================================
;  Object files and the linker
;
;    ac -c part.a -o part.ao        compile one unit to a relocatable object
;    ac main.ao part.ao -o prog     link objects into a program
;
;  An object holds the code and data of the files that were compiled (never the built-in libraries: calls to those and
;  to functions of other objects are relocations that name the symbol). The link step compiles the libraries that the
;  objects need, appends the objects to that code, resolves every symbol and writes the executable.
;
;  File layout (all numbers little endian):
;    header (64 bytes)   magic 'AOBJ', version, arch, target, flags (bit 0: uses the floating point runtime),
;                        code_len, data_len, bss_len, nrel, nsym, strtab_len, nneeds
;    code, data (each padded to 8 bytes)
;    relocations  nrel x 16 bytes   offset, kind (| 0x100: symbol in the target), target, 0
;    symbols      nsym x 24 bytes    name offset, kind (0 function, 1 data variable, 2 bss variable), flags
;                                    (1 weak, 2 undefined, 4 local), value, parameter count, 0
;    needs        nneeds x 4 bytes   string table offsets of the library modules to import when linking
;    string table symbol keys "module:Class:name" and module file names, NUL terminated
; =============================================================================

%define OBJ_VERSION     1
%define OH_MAGIC        0
%define OH_VERSION      4
%define OH_ARCH         8
%define OH_TARGET       12
%define OH_FLAGS        16
%define OH_CODE         20
%define OH_DATA         24
%define OH_BSS          28
%define OH_NREL         32
%define OH_NSYM         36
%define OH_STR          40
%define OH_NNEEDS       44
%define OBJ_HDR         64
%define OS_SIZE         24
%define OS_NAME         0
%define OS_KIND         4
%define OS_FLAGS        8
%define OS_VALUE        12
%define OS_NPAR         16
%define OSF_WEAK        1
%define OSF_UNDEF       2
%define OSF_LOCAL       4
%define OR_EXT          0x100
%define OBJ_MAXSYM      16384
%define OBJ_STR_MAX     (1024*1024)

section .text

; swap_foreign: exchanges the data / bss allocation positions with those of the area used for library data
swap_foreign:
    mov rax, [data_pos]
    xchg rax, [data_pos_f]
    mov [data_pos], rax
    mov rax, [bss_pos]
    xchg rax, [bss_pos_f]
    mov [bss_pos], rax
    ret

; obj_note_need: rdi = file entry of a built-in library module that the unit imports
obj_note_need:
    push rcx
    xor ecx, ecx
.l: cmp ecx, [obj_nneeds]
    jae .add
    cmp [obj_needs + rcx*8], rdi
    je .out
    inc ecx
    jmp .l
.add:
    cmp ecx, 64
    jae .out
    mov [obj_needs + rcx*8], rdi
    inc dword [obj_nneeds]
.out:
    pop rcx
    ret

; obj_mark_roots: (object mode, after pass 2) every function of the unit is kept
obj_mark_roots:
    xor ecx, ecx
.l: cmp ecx, [sym_count]
    jae .done
    mov rdi, rcx
    shl rdi, 6
    add rdi, symtab
    cmp dword [rdi+SYM_KIND], S_FUNC
    jne .n
    push rcx
    call sym_is_external
    pop rcx
    test eax, eax
    jnz .n
    mov rdi, rcx
    shl rdi, 6
    add rdi, symtab
    or dword [rdi+SYM_FLAGS], F_USED
.n: inc ecx
    jmp .l
.done:
    ret

; ---- the string table of an object being written ---------------------------------------------------------------------------------
; obj_str_add: rsi = bytes, ecx = count (no terminator)
obj_str_add:
    push rdi
    mov edi, [obj_strlen]
    lea eax, [rdi + rcx + 2]
    cmp eax, OBJ_STR_MAX
    jb .ok
    ERR "too many symbols for an object"
.ok:
    lea rdi, [obj_str + rdi]
    add [obj_strlen], ecx
    rep movsb
    pop rdi
    ret

obj_str_char:
    push rdi
    mov edi, [obj_strlen]
    cmp edi, OBJ_STR_MAX - 2
    jb .ok
    ERR "too many symbols for an object"
.ok:
    mov [obj_str + rdi], al
    inc dword [obj_strlen]
    pop rdi
    ret

; obj_key: rdi = symbol -> eax = offset of its key "module:Class:name" in the string table
obj_key:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13d, [obj_strlen]
    ; the module
    mov ebx, [r12+SYM_MOD]
    test ebx, ebx
    jz .nomod
    xor ecx, ecx
.m: cmp ecx, [sym_count]
    jae .nomod
    mov rax, rcx
    shl rax, 6
    add rax, symtab
    inc ecx
    cmp dword [rax+SYM_KIND], S_MODULE
    jne .m
    cmp [rax+SYM_VAL], rbx
    jne .m
    mov rsi, [rax+SYM_NAME]
    mov ecx, [rax+SYM_NLEN]
    call obj_str_add
.nomod:
    mov al, ':'
    call obj_str_char
    ; the class of a method
    test dword [r12+SYM_FLAGS], F_METHOD | F_CTOR
    jz .nocls
    mov eax, [r12+SYM_OWNER]
    cmp eax, -1
    je .nocls
    shl rax, 5
    add rax, struct_tab
    mov rsi, [rax+ST_NAME]
    mov ecx, [rax+ST_NLEN]
    call obj_str_add
.nocls:
    mov al, ':'
    call obj_str_char
    test dword [r12+SYM_FLAGS], F_CTOR
    jz .name
    mov rsi, s_obj_ctor
    mov ecx, 6
    call obj_str_add
    jmp .end
.name:
    mov rsi, [r12+SYM_NAME]
    mov ecx, [r12+SYM_NLEN]
    call obj_str_add
.end:
    xor eax, eax
    call obj_str_char
    mov eax, r13d
    pop r13
    pop r12
    pop rbx
    ret

; obj_entry: rdi = symbol -> eax = index of its entry in the symbol table of the object (created when new)
obj_entry:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rdi
    mov rax, rdi
    sub rax, symtab
    shr rax, 6
    mov r13d, eax
    mov eax, [obj_symmap + r13*4]
    cmp eax, -1
    jne .out
    mov ebx, [obj_nsyms]
    cmp ebx, OBJ_MAXSYM
    jb .room
    ERR "too many symbols for an object"
.room:
    inc dword [obj_nsyms]
    mov [obj_symmap + r13*4], ebx
    mov rax, rbx
    imul rax, OS_SIZE
    lea r14, [obj_syms + rax]
    mov rdi, r12
    call obj_key
    mov [r14+OS_NAME], eax
    mov dword [r14+OS_KIND], 0
    mov dword [r14+OS_FLAGS], 0
    mov dword [r14+OS_VALUE], 0
    mov eax, [r12+SYM_NPAR]
    mov [r14+OS_NPAR], eax
    cmp dword [r12+SYM_KIND], S_FUNC
    jne .var
    mov rdi, r12
    call sym_is_external
    test eax, eax
    jz .deffunc
    mov dword [r14+OS_FLAGS], OSF_UNDEF
    jmp .done
.deffunc:
    mov rax, [r12+SYM_VAL]
    mov [r14+OS_VALUE], eax
    mov ecx, 0
    test dword [r12+SYM_FLAGS], F_METHOD | F_CTOR
    jz .notmeth
    mov ecx, OSF_WEAK
    jmp .fl
.notmeth:
    test dword [r12+SYM_FLAGS], F_PRIVATE
    jz .fl
    mov ecx, OSF_LOCAL
.fl:
    mov [r14+OS_FLAGS], ecx
    jmp .done
.var:
    mov dword [r14+OS_KIND], 1
    test dword [r12+SYM_FLAGS], F_BSS
    jz .v1
    mov dword [r14+OS_KIND], 2
.v1:
    test dword [r12+SYM_FLAGS], F_EXTERN
    jnz .undefvar
    mov rax, [r12+SYM_VAL]
    cmp dword [r14+OS_KIND], 2
    je .v2
    cmp rax, FOREIGN_DATA_BASE
    jae .undefvar
    jmp .v3
.v2:
    cmp rax, FOREIGN_BSS_BASE
    jae .undefvar
.v3:
    mov [r14+OS_VALUE], eax
    test dword [r12+SYM_FLAGS], F_PRIVATE
    jz .done
    mov dword [r14+OS_FLAGS], OSF_LOCAL
    jmp .done
.undefvar:
    mov dword [r14+OS_FLAGS], OSF_UNDEF
    mov dword [r14+OS_VALUE], 0
.done:
    mov eax, ebx
.out:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; write_object: builds the object file in outbuf -> rax = its size
write_object:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    cmp qword [data_pos], FOREIGN_DATA_BASE
    jb .dataok
    ERR "too much data for an object"
.dataok:
    mov dword [obj_nsyms], 0
    mov dword [obj_strlen], 0
    ; no symbol has an entry yet
    mov ecx, [sym_count]
    mov rdi, obj_symmap
    mov eax, -1
    rep stosd
    ; 1) the relocations decide which symbols are mentioned
    xor r12d, r12d                      ; index
    xor r13d, r13d                      ; relocations kept
.rl:
    cmp r12d, [rel_count]
    jae .rdone
    mov rbx, r12
    shl rbx, 4
    add rbx, rel_buf
    inc r12d
    mov eax, [rbx+4]
    cmp eax, R_DATA64
    je .rdatareloc
    cmp eax, R_CODE64
    je .rdatareloc
    cmp eax, R_CODE
    je .rfunc
    cmp eax, R_DATA
    je .rglob
    cmp eax, R_BSS
    je .rglob
    cmp eax, R_CHKSTK
    je .rkeep
    ERR "internal error: this relocation cannot be written to an object"
.rdatareloc:
    cmp dword [rbx], FOREIGN_DATA_BASE
    jae .rl                             ; belongs to library data: left out
    cmp dword [rbx+4], R_CODE64
    jne .rkeep
.rfunc:
    mov edi, [rbx+8]
    shl rdi, 6
    add rdi, symtab
    call obj_entry
    jmp .rkeep
.rglob:
    mov eax, [rbx+12]
    test eax, eax
    jz .rglobloc
    dec eax
    mov rdi, rax
    shl rdi, 6
    add rdi, symtab
    call obj_entry
    jmp .rkeep
.rglobloc:
    mov eax, [rbx+8]
    cmp dword [rbx+4], R_BSS
    je .rgb
    cmp eax, FOREIGN_DATA_BASE
    jae .rbad
    jmp .rkeep
.rgb:
    cmp eax, FOREIGN_BSS_BASE
    jb .rkeep
.rbad:
    ERR "internal error: a reference to library data in an object"
.rkeep:
    inc r13d
    jmp .rl
.rdone:
    mov ebp, r13d                       ; number of relocations
    ; 2) the functions of this unit, 3) its global variables
    xor r12d, r12d
.sl:
    cmp r12d, [sym_count]
    jae .sdone
    mov rdi, r12
    shl rdi, 6
    add rdi, symtab
    inc r12d
    mov eax, [rdi+SYM_KIND]
    cmp eax, S_FUNC
    je .sfunc
    cmp eax, S_GLOBAL
    jne .sl
    ; a global variable that is defined in this unit and not private
    test dword [rdi+SYM_FLAGS], F_EXTERN | F_PRIVATE
    jnz .sl
    mov rax, [rdi+SYM_VAL]
    test dword [rdi+SYM_FLAGS], F_BSS
    jz .sgd
    cmp rax, FOREIGN_BSS_BASE
    jae .sl
    jmp .sadd
.sgd:
    cmp rax, FOREIGN_DATA_BASE
    jae .sl
    jmp .sadd
.sfunc:
    cmp qword [rdi+SYM_VAL], -1
    je .sl
    push rdi
    call sym_is_external
    pop rdi
    test eax, eax
    jnz .sl
.sadd:
    call obj_entry
    jmp .sl
.sdone:
    ; the library modules the link step has to import
    xor r12d, r12d
    xor r12d, r12d
.nl:
    cmp r12d, [obj_nneeds]
    jae .ndone
    mov rbx, [obj_needs + r12*8]
    mov rdi, [rbx]
    push rdi
    call cstrlen
    pop rsi
    mov ecx, eax
    mov r13d, [obj_strlen]
    mov [obj_needoff + r12*4], r13d
    call obj_str_add
    xor eax, eax
    call obj_str_char
    inc r12d
    jmp .nl
.ndone:
    ; 4) assemble the file
    mov rdi, outbuf
    xor eax, eax
    mov ecx, OBJ_HDR / 8
    rep stosq
    mov dword [outbuf + OH_MAGIC], 0x4A424F41
    mov dword [outbuf + OH_VERSION], OBJ_VERSION
    mov eax, [arch]
    mov [outbuf + OH_ARCH], eax
    mov eax, [target]
    mov [outbuf + OH_TARGET], eax
    xor eax, eax
    cmp dword [need_float], 0
    je .nf
    mov eax, 1
.nf:
    mov [outbuf + OH_FLAGS], eax
    mov rax, [code_pos]
    mov [outbuf + OH_CODE], eax
    mov rax, [data_pos]
    mov [outbuf + OH_DATA], eax
    mov rax, [bss_pos]
    mov [outbuf + OH_BSS], eax
    mov [outbuf + OH_NREL], ebp
    mov eax, [obj_nsyms]
    mov [outbuf + OH_NSYM], eax
    mov eax, [obj_strlen]
    mov [outbuf + OH_STR], eax
    mov eax, [obj_nneeds]
    mov [outbuf + OH_NNEEDS], eax
    lea rdi, [outbuf + OBJ_HDR]
    ; code
    mov rsi, code_buf
    mov rcx, [code_pos]
    rep movsb
    sub rdi, outbuf
    add rdi, 7
    and rdi, -8
    add rdi, outbuf
    mov rsi, data_buf
    mov rcx, [data_pos]
    rep movsb
    sub rdi, outbuf
    add rdi, 7
    and rdi, -8
    add rdi, outbuf
    ; relocations
    xor r12d, r12d
.wl:
    cmp r12d, [rel_count]
    jae .wdone
    mov rbx, r12
    shl rbx, 4
    add rbx, rel_buf
    inc r12d
    mov eax, [rbx+4]
    cmp eax, R_DATA64
    je .wd
    cmp eax, R_CODE64
    jne .wk
.wd:
    cmp dword [rbx], FOREIGN_DATA_BASE
    jae .wl
.wk:
    mov ecx, [rbx]
    mov [rdi], ecx
    mov ecx, [rbx+8]
    mov edx, eax
    cmp eax, R_CODE
    je .wsym
    cmp eax, R_CODE64
    je .wsym
    cmp eax, R_DATA
    je .wmaybe
    cmp eax, R_BSS
    jne .wput
.wmaybe:
    mov ecx, [rbx+12]
    test ecx, ecx
    jz .wput0
    dec ecx
    or edx, OR_EXT
    jmp .wsym2
.wput0:
    mov ecx, [rbx+8]
    jmp .wput
.wsym:
    mov ecx, [rbx+8]
.wsym2:
    push rdx
    push rdi
    mov edi, ecx
    shl rdi, 6
    add rdi, symtab
    call obj_entry
    pop rdi
    pop rdx
    mov ecx, eax
.wput:
    mov [rdi+4], edx
    mov [rdi+8], ecx
    mov dword [rdi+12], 0
    add rdi, 16
    jmp .wl
.wdone:
    ; symbols
    mov rsi, obj_syms
    mov eax, [obj_nsyms]
    imul ecx, eax, OS_SIZE
    rep movsb
    ; needs
    mov rsi, obj_needoff
    mov ecx, [obj_nneeds]
    shl ecx, 2
    rep movsb
    ; string table
    mov rsi, obj_str
    mov ecx, [obj_strlen]
    rep movsb
    mov rax, rdi
    sub rax, outbuf
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
s_obj_ctor:     db "<ctor>", 0

section .bss
alignb 16
obj_syms:       resb OBJ_MAXSYM * OS_SIZE
obj_str:        resb OBJ_STR_MAX
obj_symmap:     resd SYM_MAX
obj_needs:      resq 64
obj_needoff:    resd 64
obj_nsyms:      resd 1
obj_strlen:     resd 1
obj_nneeds:     resd 1
section .text

; =============================================================================
;  The linker
; =============================================================================
%define LO_BUF          0
%define LO_CODE         8
%define LO_DATA         16
%define LO_REL          24
%define LO_SYM          32
%define LO_NEEDS        40
%define LO_STR          48
%define LO_CLEN         56
%define LO_DLEN         64
%define LO_BLEN         72
%define LO_NREL         80
%define LO_NSYM         88
%define LO_NNEEDS       96
%define LO_CBASE        104
%define LO_DBASE        112
%define LO_BBASE        120
%define LO_PATH         128
%define LO_REC          136             ; pointer to nsym records of 16 bytes: value (qword), symtab index (dword), section kind (dword)
%define LO_SIZE         192
%define LK_MAXEXP       65536

section .text

; lk_pretty: rsi = symbol key "module:Class:name" -> rsi = "module.Class.name" (empty parts left out), in a buffer
lk_pretty:
    push rdi
    push rax
    push rcx
    mov rdi, lk_prettybuf
    xor ecx, ecx                        ; 1 = something was written, a separator is needed before the next part
.l: mov al, [rsi]
    test al, al
    jz .d
    inc rsi
    cmp al, ':'
    jne .c
    test ecx, ecx
    jz .l
    mov al, '.'
    mov byte [rdi], al
    inc rdi
    xor ecx, ecx
    mov ecx, 0
    jmp .l
.c: mov [rdi], al
    inc rdi
    mov ecx, 1
    jmp .l
.d: cmp rdi, lk_prettybuf
    jbe .e
    cmp byte [rdi-1], '.'
    jne .e
    dec rdi
.e: mov byte [rdi], 0
    mov rsi, lk_prettybuf
    pop rcx
    pop rax
    pop rdi
    ret

; lk_fail_sym: rdi = message, rsi = symbol key
lk_fail_sym:
    call lk_pretty
    jmp lk_fail

; lk_fail: rdi = message, rsi = text to show in quotes
lk_fail:
    mov [tk_ptr], rsi
    push rdi
    mov rdi, rsi
    call cstrlen
    mov [tk_len], eax
    pop rdi
    mov qword [cur_file_name], 0
    jmp fatal_error_tok

; lk_obj: eax = index -> rax = the object's table entry
lk_obj:
    imul rax, rax, LO_SIZE
    add rax, lk_objs
    ret

; link_load_objects: reads the object files -> rax = the file entry of the program text ("import" lines for the library modules
; the objects use and a declaration of main)
link_load_objects:
    push rbx
    push r12
    push r13
    push r14
    push r15
    xor r12d, r12d
.o: cmp r12d, [opt_nobjs]
    jae .loaded
    mov rdi, [opt_objs + r12*8]
    call read_file
    test rax, rax
    jnz .read
    mov rdi, s_lk_noread
    mov rsi, [opt_objs + r12*8]
    call lk_fail
.read:
    mov r13, rax                        ; contents
    mov r14, rdx                        ; size
    mov eax, r12d
    call lk_obj
    mov rbx, rax
    mov rax, [opt_objs + r12*8]
    mov [rbx+LO_PATH], rax
    cmp r14, OBJ_HDR
    jb .bad
    cmp dword [r13 + OH_MAGIC], 0x4A424F41
    jne .bad
    cmp dword [r13 + OH_VERSION], OBJ_VERSION
    jne .bad
    mov eax, [r13 + OH_ARCH]
    cmp eax, [arch]
    jne .other
    mov eax, [r13 + OH_TARGET]
    cmp eax, [target]
    jne .other
    test dword [r13 + OH_FLAGS], 1
    jz .nf
    mov dword [need_float], 1
.nf:
    mov [rbx+LO_BUF], r13
    mov eax, [r13 + OH_CODE]
    mov [rbx+LO_CLEN], rax
    mov eax, [r13 + OH_DATA]
    mov [rbx+LO_DLEN], rax
    mov eax, [r13 + OH_BSS]
    mov [rbx+LO_BLEN], rax
    mov eax, [r13 + OH_NREL]
    mov [rbx+LO_NREL], rax
    mov eax, [r13 + OH_NSYM]
    mov [rbx+LO_NSYM], rax
    mov eax, [r13 + OH_NNEEDS]
    mov [rbx+LO_NNEEDS], rax
    lea rdi, [r13 + OBJ_HDR]
    mov [rbx+LO_CODE], rdi
    mov rax, [rbx+LO_CLEN]
    add rax, 7
    and rax, -8
    add rdi, rax
    mov [rbx+LO_DATA], rdi
    mov rax, [rbx+LO_DLEN]
    add rax, 7
    and rax, -8
    add rdi, rax
    mov [rbx+LO_REL], rdi
    mov rax, [rbx+LO_NREL]
    shl rax, 4
    add rdi, rax
    mov [rbx+LO_SYM], rdi
    mov rax, [rbx+LO_NSYM]
    imul rax, rax, OS_SIZE
    add rdi, rax
    mov [rbx+LO_NEEDS], rdi
    mov rax, [rbx+LO_NNEEDS]
    shl rax, 2
    add rdi, rax
    mov [rbx+LO_STR], rdi
    mov eax, [r13 + OH_STR]
    add rdi, rax
    lea rax, [r13 + r14]
    cmp rdi, rax
    ja .bad
    ; room for the resolved symbol records
    mov rax, [rbx+LO_NSYM]
    shl rax, 4
    mov rcx, [lk_poolpos]
    lea rdx, [rcx + rax]
    cmp rdx, LK_POOL_SIZE
    jbe .pool
    jmp err_toobig
.pool:
    mov [lk_poolpos], rdx
    add rcx, lk_pool
    mov [rbx+LO_REC], rcx
    inc r12d
    jmp .o
.bad:
    mov rdi, s_lk_bad
    mov rsi, [opt_objs + r12*8]
    call lk_fail
.other:
    mov rdi, s_lk_target
    mov rsi, [opt_objs + r12*8]
    call lk_fail

.loaded:
    ; ---- the text of the program: imports of the library modules, then a declaration of main
    mov rdi, lk_src
    xor r12d, r12d
.n1:cmp r12d, [opt_nobjs]
    jae .nmain
    mov eax, r12d
    call lk_obj
    mov rbx, rax
    xor r13d, r13d
.n2:cmp r13, [rbx+LO_NNEEDS]
    jae .n9
    mov rax, [rbx+LO_NEEDS]
    mov eax, [rax + r13*4]
    add rax, [rbx+LO_STR]
    mov rsi, rax                        ; "<name>"
    cmp byte [rsi], '<'
    jne .n8
    inc rsi
    ; "import name;"
    mov r14, rdi                        ; where this line starts
    mov dword [rdi], 'impo'
    mov dword [rdi+4], 'rt  '
    add rdi, 7
.n3:mov al, [rsi]
    cmp al, '>'
    je .n4
    test al, al
    jz .n4
    cmp al, '/'
    jne .n3a
    mov al, '.'
.n3a:
    mov [rdi], al
    inc rdi
    inc rsi
    jmp .n3
.n4:mov word [rdi], ';' | (10 << 8)
    add rdi, 2
    ; the same line twice is harmless, but keep the program text short
    mov rsi, lk_src
    mov rcx, r14
    sub rcx, rsi
.n5:test rcx, rcx
    jz .n8
    mov rax, rdi
    sub rax, r14
    cmp rcx, rax
    jb .n8
    push rsi
    push rdi
    push rcx
    mov rdi, rsi
    mov rsi, r14
    mov rcx, rax
    repe cmpsb
    pop rcx
    pop rdi
    pop rsi
    jne .n6
    mov rdi, r14                        ; a duplicate: drop it again
    jmp .n8
.n6:inc rsi
    dec rcx
    jmp .n5
.n8:inc r13
    jmp .n2
.n9:inc r12d
    jmp .n1
.nmain:
    ; main(): find its definition to know the number of parameters
    mov [lk_srcend], rdi
    mov rsi, s_lk_mainkey
    call lk_find_export_raw             ; rax = symbol entry or 0, rdx = object
    test rax, rax
    jnz .m1
    mov rdi, s_lk_nomain
    mov rsi, s_lk_main
    call lk_fail
.m1:
    mov ecx, [rax + OS_NPAR]
    mov rdi, [lk_srcend]
    mov rsi, s_lk_proto0
    call cstr_copy
    cmp ecx, 1
    jb .m3
    mov rsi, s_lk_proto1
    call cstr_copy
    cmp ecx, 2
    jb .m3
    mov rsi, s_lk_proto2
    call cstr_copy
.m3:mov rsi, s_lk_proto9
    call cstr_copy
    mov rdx, rdi
    sub rdx, lk_src
    mov rdi, s_lk_progname
    mov rsi, lk_src
    call add_embedded_file
    mov eax, [file_count]
    dec eax
    shl rax, 6
    add rax, file_table
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; lk_find_export_raw: rsi = key -> rax = symbol entry of a defined, non-local symbol of an object with that key (0 if none),
; rdx = the object's table entry
lk_find_export_raw:
    push rbx
    push r12
    push r13
    mov r13, rsi
    xor r12d, r12d
.o: cmp r12d, [opt_nobjs]
    jae .none
    mov eax, r12d
    call lk_obj
    mov rbx, rax
    xor ecx, ecx
.s: cmp rcx, [rbx+LO_NSYM]
    jae .next
    mov rax, rcx
    imul rax, rax, OS_SIZE
    add rax, [rbx+LO_SYM]
    inc rcx
    test dword [rax+OS_FLAGS], OSF_UNDEF | OSF_LOCAL
    jnz .s
    mov edx, [rax+OS_NAME]
    add rdx, [rbx+LO_STR]
    push rax
    push rcx
    mov rdi, rdx
    mov rsi, r13
    call cstr_eq
    mov rdx, rax
    pop rcx
    pop rax
    test edx, edx
    jz .s
    mov rdx, rbx
    jmp .out
.next:
    inc r12d
    jmp .o
.none:
    xor eax, eax
.out:
    pop r13
    pop r12
    pop rbx
    ret

; lk_split_key: rsi = key -> r8 = module name, r9d = its length, r10 = class, r11d = its length, rsi = name, ecx = its length
lk_split_key:
    mov r8, rsi
    xor r9d, r9d
.a: mov al, [rsi+r9]
    cmp al, ':'
    je .b
    inc r9d
    jmp .a
.b: lea r10, [rsi + r9 + 1]
    xor r11d, r11d
.c: mov al, [r10+r11]
    cmp al, ':'
    je .d
    inc r11d
    jmp .c
.d: lea rsi, [r10 + r11 + 1]
    xor ecx, ecx
.e: cmp byte [rsi+rcx], 0
    je .f
    inc ecx
    jmp .e
.f: ret

; lk_find_sym: rsi = key, edi = 1 for a function, 0 for a variable -> rax = symbol of the program being linked (a library symbol), 0 if none
lk_find_sym:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r15d, edi
    call lk_split_key
    mov r12, rsi                        ; name
    mov r13d, ecx
    xor ebx, ebx                        ; module id
    test r9d, r9d
    jz .nomod
    xor edx, edx
.m: cmp edx, [sym_count]
    jae .fail
    mov rax, rdx
    shl rax, 6
    add rax, symtab
    inc edx
    cmp dword [rax+SYM_KIND], S_MODULE
    jne .m
    cmp [rax+SYM_NLEN], r9d
    jne .m
    push rdx
    push r8
    push r9
    mov rdi, [rax+SYM_NAME]
    mov rsi, r8
    mov ecx, r9d
    repe cmpsb
    pop r9
    pop r8
    pop rdx
    jne .m
    mov ebx, [rax+SYM_VAL]
.nomod:
    test r11d, r11d
    jz .plain
    ; a method: find the class
    xor edx, edx
.c: cmp edx, [struct_count]
    jae .fail
    mov rax, rdx
    shl rax, 5
    add rax, struct_tab
    cmp [rax+ST_NLEN], r11d
    jne .cn
    push rdx
    push r10
    push r11
    mov rdi, [rax+ST_NAME]
    mov rsi, r10
    mov ecx, r11d
    repe cmpsb
    pop r11
    pop r10
    pop rdx
    je .cfound
.cn:inc edx
    jmp .c
.cfound:
    mov edi, edx
    cmp r13d, 6
    jne .meth
    mov rsi, r12
    push rdi
    mov rdi, s_obj_ctor
    mov ecx, 6
    repe cmpsb
    pop rdi
    jne .meth
    call struct_find_ctor_here
    jmp .done
.meth:
    mov rsi, r12
    mov edx, r13d
    call struct_find_method_here
    jmp .done
.plain:
    mov rdi, r12
    mov esi, r13d
    mov edx, ebx
    call sym_find_global
    test rax, rax
    jz .done
    mov ecx, S_FUNC
    test r15d, r15d
    jnz .k
    mov ecx, S_GLOBAL
.k: cmp [rax+SYM_KIND], ecx
    je .done
.fail:
    xor eax, eax
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; link_mark_roots: (after pass 2) the library functions that the objects call are kept
link_mark_roots:
    push rbx
    push r12
    push r13
    xor r12d, r12d
.o: cmp r12d, [opt_nobjs]
    jae .done
    mov eax, r12d
    call lk_obj
    mov rbx, rax
    xor r13d, r13d
.s: cmp r13, [rbx+LO_NSYM]
    jae .next
    mov rax, r13
    imul rax, rax, OS_SIZE
    add rax, [rbx+LO_SYM]
    inc r13
    test dword [rax+OS_FLAGS], OSF_UNDEF
    jz .s
    cmp dword [rax+OS_KIND], 0
    jne .s
    mov esi, [rax+OS_NAME]
    add rsi, [rbx+LO_STR]
    mov edi, 1
    call lk_find_sym
    test rax, rax
    jz .s
    or dword [rax+SYM_FLAGS], F_USED
    jmp .s
.next:
    inc r12d
    jmp .o
.done:
    pop r13
    pop r12
    pop rbx
    ret

; lk_hidden: rbx = object, edi = entry index -> eax = symtab index of a function symbol with the entry's address
lk_hidden:
    push rcx
    push rdx
    push r12
    mov r12, rdi
    shl r12, 4
    add r12, [rbx+LO_REC]
    mov eax, [r12+8]
    cmp eax, -1
    jne .have
    mov rdi, s_lk_progname
    mov esi, 1
    mov edx, S_FUNC
    call sym_new
    mov rcx, [r12]
    mov [rax+SYM_VAL], rcx
    mov dword [rax+SYM_FLAGS], F_DEFINED | F_USED
    mov rcx, rax
    sub rcx, symtab
    shr rcx, 6
    mov [r12+8], ecx
    mov eax, ecx
.have:
    pop r12
    pop rdx
    pop rcx
    ret

; link_place: (after pass 3) the objects are put behind the code and data of the libraries and every symbol is resolved
link_place:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    ; ---- 1) place the sections
    xor r12d, r12d
.p: cmp r12d, [opt_nobjs]
    jae .placed
    mov eax, r12d
    call lk_obj
    mov rbx, rax
    mov rax, [code_pos]
    add rax, 15
    and rax, -16
    mov [rbx+LO_CBASE], rax
    mov rcx, [rbx+LO_CLEN]
    lea rdx, [rax + rcx]
    cmp rdx, CODE_MAX - 4096
    jb .c1
    jmp err_toobig
.c1:
    lea rdi, [code_buf + rax]
    mov rsi, [rbx+LO_CODE]
    rep movsb
    mov [code_pos], rdx
    mov rax, [data_pos]
    add rax, 15
    and rax, -16
    mov [rbx+LO_DBASE], rax
    mov rcx, [rbx+LO_DLEN]
    lea rdx, [rax + rcx]
    cmp rdx, DATA_MAX - 16
    jb .d1
    jmp err_toobig
.d1:
    lea rdi, [data_buf + rax]
    mov rsi, [rbx+LO_DATA]
    rep movsb
    mov [data_pos], rdx
    mov rax, [bss_pos]
    add rax, 15
    and rax, -16
    mov [rbx+LO_BBASE], rax
    add rax, [rbx+LO_BLEN]
    cmp rax, BSS_LIMIT
    jb .b1
    jmp err_toobig
.b1:
    mov [bss_pos], rax
    ; initialise the records
    mov rdi, [rbx+LO_REC]
    mov rcx, [rbx+LO_NSYM]
.ri:test rcx, rcx
    jz .rid
    mov qword [rdi], 0
    mov dword [rdi+8], -1
    mov dword [rdi+12], 0
    add rdi, 16
    dec rcx
    jmp .ri
.rid:
    inc r12d
    jmp .p
.placed:
    ; ---- 2) the symbols that the objects define
    xor r12d, r12d
.e: cmp r12d, [opt_nobjs]
    jae .exported
    mov eax, r12d
    call lk_obj
    mov rbx, rax
    xor r13d, r13d
.es:cmp r13, [rbx+LO_NSYM]
    jae .enext
    mov rbp, r13
    imul rbp, rbp, OS_SIZE
    add rbp, [rbx+LO_SYM]               ; the entry
    mov r14, r13
    shl r14, 4
    add r14, [rbx+LO_REC]               ; its record
    inc r13
    test dword [rbp+OS_FLAGS], OSF_UNDEF
    jnz .es
    ; the value
    mov eax, [rbp+OS_VALUE]
    mov ecx, [rbp+OS_KIND]
    mov [r14+12], ecx
    test ecx, ecx
    jnz .e1
    add rax, [rbx+LO_CBASE]
    jmp .e3
.e1:cmp ecx, 1
    jne .e2
    add rax, [rbx+LO_DBASE]
    jmp .e3
.e2:add rax, [rbx+LO_BBASE]
.e3:mov [r14], rax
    test dword [rbp+OS_FLAGS], OSF_LOCAL
    jnz .es
    ; export it: a second definition of the same name is an error unless both are weak
    mov esi, [rbp+OS_NAME]
    add rsi, [rbx+LO_STR]
    mov r15, rsi
    xor ecx, ecx
.ex:cmp ecx, [lk_nexp]
    jae .newexp
    mov rax, rcx
    shl rax, 5
    add rax, lk_exp
    inc ecx
    mov rdi, [rax]
    mov rsi, r15
    push rax
    push rcx
    call cstr_eq
    mov rdx, rax
    pop rcx
    pop rax
    test edx, edx
    jz .ex
    test dword [rbp+OS_FLAGS], OSF_WEAK
    jz .dup
    test dword [rax+20], OSF_WEAK
    jnz .es                             ; both weak: the first one stays
.dup:
    mov rdi, s_lk_dup
    mov rsi, r15
    call lk_fail_sym
.newexp:
    mov ecx, [lk_nexp]
    cmp ecx, LK_MAXEXP
    jb .ne1
    jmp err_toobig
.ne1:
    inc dword [lk_nexp]
    shl rcx, 5
    add rcx, lk_exp
    mov [rcx], r15
    mov rax, [r14]
    mov [rcx+8], rax
    mov eax, [rbp+OS_KIND]
    mov [rcx+16], eax
    mov eax, [rbp+OS_FLAGS]
    mov [rcx+20], eax
    jmp .es
.enext:
    inc r12d
    jmp .e
.exported:
    ; ---- 3) main
    mov rsi, s_lk_mainkey
    call lk_find_export_raw
    test rax, rax
    jnz .hasmain
    mov rdi, s_lk_nomain
    mov rsi, s_lk_main
    call lk_fail
.hasmain:
    ; the value of main is in the object's record
    sub rax, [rdx+LO_SYM]
    xor edx, edx
    mov ecx, OS_SIZE
    ; (rax / OS_SIZE = index; the object is found again below)
    div rcx
    mov r13, rax
    call find_main
    test rax, rax
    jnz .fm
    mov rdi, s_lk_nomain
    mov rsi, s_lk_main
    call lk_fail
.fm:
    mov r15, rax                        ; the symbol of main
    mov rsi, s_lk_mainkey
    call lk_find_export_raw
    mov rbx, rdx
    mov rax, r13
    shl rax, 4
    add rax, [rbx+LO_REC]
    mov rsi, [rax]                      ; the address of main
    mov [r15+SYM_VAL], rsi
    or dword [r15+SYM_FLAGS], F_DEFINED
    mov edi, [r15+SYM_PATCH]
    mov dword [r15+SYM_PATCH], 0
    CG patch_chain
    ; ---- 4) the symbols that the objects need
    xor r12d, r12d
.u: cmp r12d, [opt_nobjs]
    jae .resolved
    mov eax, r12d
    call lk_obj
    mov rbx, rax
    xor r13d, r13d
.us:cmp r13, [rbx+LO_NSYM]
    jae .unext
    mov rbp, r13
    imul rbp, rbp, OS_SIZE
    add rbp, [rbx+LO_SYM]
    mov r14, r13
    shl r14, 4
    add r14, [rbx+LO_REC]
    inc r13
    test dword [rbp+OS_FLAGS], OSF_UNDEF
    jz .us
    mov esi, [rbp+OS_NAME]
    add rsi, [rbx+LO_STR]
    mov r15, rsi
    ; in another object?
    xor ecx, ecx
.ux:cmp ecx, [lk_nexp]
    jae .lib
    mov rax, rcx
    shl rax, 5
    add rax, lk_exp
    inc ecx
    mov rdi, [rax]
    mov rsi, r15
    push rax
    push rcx
    call cstr_eq
    mov rdx, rax
    pop rcx
    pop rax
    test edx, edx
    jz .ux
    mov ecx, [rax+16]
    mov edx, [rbp+OS_KIND]
    test edx, edx
    jz .uf
    test ecx, ecx
    jz .uerr                            ; a variable asked for, a function found
    mov rcx, [rax+8]
    mov [r14], rcx
    mov ecx, [rax+16]
    mov [r14+12], ecx
    jmp .us
.uf:
    test ecx, ecx
    jnz .uerr
    mov rcx, [rax+8]
    mov [r14], rcx
    mov dword [r14+12], 0
    jmp .us
.uerr:
    mov rdi, s_lk_kind
    mov rsi, r15
    call lk_fail_sym
.lib:
    ; a function or variable of the built-in libraries
    mov rsi, r15
    mov edi, 1
    cmp dword [rbp+OS_KIND], 0
    je .l1
    xor edi, edi
.l1:call lk_find_sym
    test rax, rax
    jnz .lfound
    mov rdi, s_lk_undef
    mov rsi, r15
    call lk_fail_sym
.lfound:
    cmp dword [rbp+OS_KIND], 0
    jne .lvar
    mov rcx, [rax+SYM_VAL]
    cmp rcx, -1
    jne .lf2
    mov rdi, s_lk_undef
    mov rsi, r15
    call lk_fail_sym
.lf2:
    mov [r14], rcx
    mov dword [r14+12], 0
    sub rax, symtab
    shr rax, 6
    mov [r14+8], eax
    jmp .us
.lvar:
    mov rcx, [rax+SYM_VAL]
    mov [r14], rcx
    mov edx, 1
    test dword [rax+SYM_FLAGS], F_BSS
    jz .lv2
    mov edx, 2
.lv2:
    mov [r14+12], edx
    jmp .us
.unext:
    inc r12d
    jmp .u
.resolved:
    ; ---- 5) the relocations
    xor r12d, r12d
.r: cmp r12d, [opt_nobjs]
    jae .done
    mov eax, r12d
    call lk_obj
    mov rbx, rax
    xor r13d, r13d
.rs:cmp r13, [rbx+LO_NREL]
    jae .rnext
    mov rbp, r13
    shl rbp, 4
    add rbp, [rbx+LO_REL]
    inc r13
    mov r14d, [rbp]                     ; position
    mov r15d, [rbp+4]                   ; kind
    mov r8d, [rbp+8]                    ; target
    mov eax, r15d
    and eax, 0xFF
    cmp eax, R_DATA
    je .rd
    cmp eax, R_BSS
    je .rb
    cmp eax, R_DATA64
    je .rd64
    cmp eax, R_CODE
    je .rc
    cmp eax, R_CODE64
    je .rc64
    cmp eax, R_CHKSTK
    je .rchk
    mov rdi, s_lk_bad
    mov rsi, [rbx+LO_PATH]
    call lk_fail
.rd:
    test r15d, OR_EXT
    jnz .rext
    mov edi, r14d
    add rdi, [rbx+LO_CBASE]
    mov esi, R_DATA
    mov edx, r8d
    add rdx, [rbx+LO_DBASE]
    call add_reloc
    jmp .rs
.rb:
    test r15d, OR_EXT
    jnz .rext
    mov edi, r14d
    add rdi, [rbx+LO_CBASE]
    mov esi, R_BSS
    mov edx, r8d
    add rdx, [rbx+LO_BBASE]
    call add_reloc
    jmp .rs
.rext:
    ; a variable that is defined elsewhere
    mov rax, r8
    shl rax, 4
    add rax, [rbx+LO_REC]
    mov edx, [rax]
    mov esi, R_DATA
    cmp dword [rax+12], 2
    jne .rx1
    mov esi, R_BSS
.rx1:
    mov edi, r14d
    add rdi, [rbx+LO_CBASE]
    call add_reloc
    jmp .rs
.rd64:
    mov rax, [rbx+LO_DBASE]
    mov edi, r14d
    add rdi, rax
    add [data_buf + rdi], rax           ; the word holds an offset in the data of the object
    mov esi, R_DATA64
    xor edx, edx
    call add_reloc
    jmp .rs
.rc:
    mov edi, r8d
    call lk_hidden
    mov edx, eax
    mov edi, r14d
    add rdi, [rbx+LO_CBASE]
    mov esi, R_CODE
    call add_reloc
    jmp .rs
.rc64:
    mov edi, r8d
    call lk_hidden
    mov edx, eax
    mov edi, r14d
    add rdi, [rbx+LO_DBASE]
    mov esi, R_CODE64
    call add_reloc
    jmp .rs
.rchk:
    mov eax, r14d
    add rax, [rbx+LO_CBASE]             ; position of the displacement
    mov rcx, [chkstk_pos]
    sub rcx, rax
    sub rcx, 4
    mov [code_buf + rax], ecx
    jmp .rs
.rnext:
    inc r12d
    jmp .r
.done:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
s_lk_noread:    db "cannot read the object file", 0
s_lk_bad:       db "not a valid object file", 0
s_lk_target:    db "the object was made for another target or architecture", 0
s_lk_nomain:    db "undefined reference to", 0
s_lk_main:      db "main", 0
s_lk_mainkey:   db "::main", 0
s_lk_dup:       db "duplicate definition of", 0
s_lk_kind:      db "a variable and a function share the name", 0
s_lk_undef:     db "undefined reference to", 0
s_lk_proto0:    db "int main(", 0
s_lk_proto1:    db "int argc", 0
s_lk_proto2:    db ", char** argv", 0
s_lk_proto9:    db ");", 10, 0
s_lk_progname:  db "<link>", 0

section .bss
alignb 16
LK_POOL_SIZE equ (8*1024*1024)
lk_objs:        resb 64 * LO_SIZE
lk_pool:        resb LK_POOL_SIZE
lk_exp:         resb LK_MAXEXP * 32
lk_src:         resb 16384
lk_srcend:      resq 1
lk_prettybuf:   resb 512
lk_poolpos:     resq 1
lk_nexp:        resd 1
section .text
