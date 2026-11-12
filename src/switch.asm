; =============================================================================
;  switch.asm - the switch statement
;
;    switch (n) { case 1: ... case 2, 3: ... case 10..20: ... default: ... }      integers; a..b includes both ends
;    switch (s) { case "get": ... case "put", "post": ... default: ... }         text (char*), compared like streq; null matches nothing
;
;  The value is kept in a hidden local, the statements are compiled first and the dispatch code comes after them and jumps back
;  into the body (so a label is just a code position). The dispatch is made when the closing brace is seen:
;    integers: a compare chain for fewer than 8 plain labels, else a binary search over the sorted ranges;
;    text:     up to 4 labels one streq() after the other, else the FNV-1a hash of the value (__swhash in lib/std.a, the same
;              function runs in the compiler for the labels) is searched in the sorted hashes and the text is compared only
;              with the labels that have that hash.
;  Duplicate labels (equal numbers, overlapping ranges, equal texts) are errors at the label.
; =============================================================================
section .rodata
w_swhash:   db "__swhash", 0
w_streq:    db "streq", 0
align 8
section .text

; sw_hash: rdi = C string -> eax = FNV-1a (32 bit) of the bytes up to the NUL. Must give the same result as __swhash in lib/std.a
sw_hash:
    mov eax, 0x811C9DC5
.l: movzx ecx, byte [rdi]
    test ecx, ecx
    jz .d
    xor eax, ecx
    imul eax, eax, 0x01000193
    inc rdi
    jmp .l
.d: ret

; sw_label: edi = first label of this switch, esi = 1 for a switch on text. Parses one label (after 'case' or ',') and registers it.
sw_label:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx, edi
    mov r14d, esi
    call const_expr                     ; rax = number / data offset of a text, edx = 1 for a text
    mov r12, rax
    test r14d, r14d
    jnz .text
    test edx, edx
    jz .int
    ERR "this case label is a text, but the switch is not on text"
.int:
    mov r13, r12                        ; low = high for a single number
    cmp qword [tk], T_DOTDOT
    jne .idup
    call next_token
    call const_expr
    test edx, edx
    jz .i2
    ERR "a case range needs numbers"
.i2:
    mov r13, rax
    cmp r13, r12
    jge .idup
    ERR "empty case range: the first number is larger than the last"
.idup:
    mov r15d, ebx
.il:
    cmp r15d, [case_sp]
    jae .add
    cmp r12, [case_hi + r15*8]
    jg .inext
    cmp r13, [case_val + r15*8]
    jl .inext
    ERR "duplicate case label"
.inext:
    inc r15d
    jmp .il
.text:
    test edx, edx
    jnz .t1
    ERR "this case label must be a text: the switch is on text"
.t1:
    lea rdi, [data_buf + r12]
    call sw_hash
    mov r13, rax                        ; the key
    mov r15d, ebx
.tl:
    cmp r15d, [case_sp]
    jae .add
    cmp r13, [case_key + r15*8]
    jne .tnext
    lea rdi, [data_buf + r12]
    mov eax, [case_val + r15*8]
    lea rsi, [data_buf + rax]
    call cstr_eq
    test eax, eax
    jz .tnext
    ERR "duplicate case label"
.tnext:
    inc r15d
    jmp .tl
.add:
    mov eax, [case_sp]
    cmp eax, CASE_MAX
    jb .room
    ERR "too many case labels (at most 4096 in the switch statements that are open together)"
.room:
    inc dword [case_sp]
    mov [case_val + rax*8], r12
    test r14d, r14d
    jnz .addt
    mov [case_hi + rax*8], r13
    mov [case_key + rax*8], r12
    jmp .addp
.addt:
    mov [case_hi + rax*8], r12
    mov [case_key + rax*8], r13
.addp:
    mov rcx, [code_pos]
    mov [case_pos + rax*8], rcx
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

parse_switch:
    push rbx
    push r12
    push r13
    push r14
    push r15
    call next_token
    mov edi, '('
    call expect
    call parse_expr
    call to_rvalue
    mov edi, ')'
    call expect
    xor r15d, r15d
    cmp qword [e_type], TY_CHAR | TY_PTR1
    sete r15b                           ; a switch on text
    add dword [frame_size], 8
    mov ebx, [frame_size]
    neg rbx
    mov edi, ebx
    CG store_local_a
    xor edi, edi
    mov esi, 1
    call loop_push
    mov r12, rax
    mov r13d, [case_sp]
    push r15                            ; [rsp+16] = 1 for a switch on text
    push 0                              ; [rsp+8]  = code position of 'default:' (0 = none)
    push 0                              ; [rsp]    = chain of the jump to the dispatch code
    mov rdi, rsp
    CG jmp_chain
    mov edi, '{'
    call expect
    mov r14d, [sym_count]
.items:
    mov eax, [tk]
    cmp eax, '}'
    je .done
    cmp eax, K_CASE
    je .case
    cmp eax, K_DEFAULT
    je .default
    cmp eax, T_EOF
    jne .stmt
    ERR "unexpected end of file in switch"
.stmt:
    call parse_stmt
    jmp .items
.case:
    call next_token
.lab:
    mov edi, r13d
    mov esi, [rsp+16]
    call sw_label
    cmp qword [tk], ','
    jne .colon
    call next_token                     ; case A, B, C:
    jmp .lab
.colon:
    mov edi, ':'
    call expect
    jmp .items
.default:
    call next_token
    mov edi, ':'
    call expect
    cmp qword [rsp+8], 0
    je .d1
    ERR "duplicate 'default' label"
.d1:
    mov rax, [code_pos]
    mov [rsp+8], rax
    jmp .items
.done:
    call next_token
    mov [sym_count], r14d
    ; the end of the body falls out of the switch
    mov rdi, r12
    CG jmp_chain
    ; the dispatch code
    pop rdi
    call patch_here
    pop rax                             ; default position
    pop rdx                             ; text flag
    mov edi, ebx
    mov esi, r13d
    mov rcx, r12
    call sw_dispatch
    mov rdi, [r12]
    call patch_here
    mov [case_sp], r13d
    call loop_pop
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; sw_emit_default: jump to 'default:' or, when there is none, out of the switch
sw_emit_default:
    mov rax, [sw_def]
    test rax, rax
    jz .none
    mov rdi, rax
    CG jmp_back
    ret
.none:
    mov rdi, [sw_rec]
    CG jmp_chain
    ret

; sw_dispatch: edi = frame offset of the value, esi = first label of this switch, rdx = 1 for text, rax = position of 'default:' (0 = none),
; rcx = loop record. Emits the code that jumps to the label of the value.
sw_dispatch:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx, edi
    mov r13d, esi
    mov [sw_def], rax
    mov [sw_rec], rcx
    mov r14d, [case_sp]
    sub r14d, r13d                      ; number of labels
    test rdx, rdx
    jnz .text
    ; ---- integers
    test r14d, r14d
    jz .none
    cmp r14d, 8
    jae .generic
    mov r15d, r13d
.scan:
    cmp r15d, [case_sp]
    jae .chain
    mov rax, [case_val + r15*8]
    cmp rax, [case_hi + r15*8]
    jne .generic                        ; a range
    movsxd rcx, eax
    cmp rcx, rax
    jne .generic                        ; a number that does not fit a 32 bit immediate
    inc r15d
    jmp .scan
.chain:
    mov r15d, r13d
.cl:
    cmp r15d, [case_sp]
    jae .none
    mov edi, ebx
    mov rsi, [case_val + r15*8]
    mov rdx, [case_pos + r15*8]
    CG case_jump
    inc r15d
    jmp .cl
.generic:
    mov [sw_vslot], ebx
    mov dword [sw_text], 0
    mov edi, r14d
    mov esi, r13d
    call sw_sort
    xor edi, edi
    mov esi, r14d
    call sw_tree
    jmp .out
.none:
    call sw_emit_default
    jmp .out

    ; ---- text
.text:
    test r14d, r14d
    jz .none
    mov edi, ebx
    CG load_local_a
    push 0
    mov rdi, rsp
    CG jnz_chain
    call sw_emit_default                ; a null text matches nothing
    pop rdi
    call patch_here
    cmp r14d, 4
    ja .hash
    mov r15d, r13d                      ; a few labels: streq against each in turn
.tl:
    cmp r15d, [case_sp]
    jae .none
    mov edi, ebx
    CG load_local_a
    CG push_a
    mov edx, [case_val + r15*8]
    call obj_localize_string
    mov esi, R_DATA
    CG lea_global_a
    CG push_a
    mov rdi, w_streq
    call emit_call_named
    mov edi, 2
    CG drop
    push 0
    mov rdi, rsp
    CG jz_chain
    mov rdi, [case_pos + r15*8]
    CG jmp_back
    pop rdi
    call patch_here
    inc r15d
    jmp .tl
.hash:
    add dword [frame_size], 8
    mov eax, [frame_size]
    neg eax
    mov [sw_vslot], eax                 ; the hash of the value
    mov [sw_sval], ebx
    mov dword [sw_text], 1
    mov edi, ebx
    CG load_local_a
    CG push_a
    mov rdi, w_swhash
    call emit_call_named
    mov edi, 1
    CG drop
    mov edi, [sw_vslot]
    CG store_local_a
    mov edi, r14d
    mov esi, r13d
    call sw_sort
    xor edi, edi
    mov esi, r14d
    call sw_tree
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; sw_sort: edi = number of labels, esi = index of the first one. case_ord[0..n) = the labels ordered by key (stable)
sw_sort:
    xor ecx, ecx
.init:
    cmp ecx, edi
    jae .sort
    lea eax, [rsi + rcx]
    mov [case_ord + rcx*4], eax
    inc ecx
    jmp .init
.sort:
    mov r8d, 1
.i:
    cmp r8d, edi
    jae .done
    mov eax, [case_ord + r8*4]
    mov r9, [case_key + rax*8]
    mov r10d, r8d
.j:
    test r10d, r10d
    jz .place
    mov r11d, [case_ord + r10*4 - 4]
    mov rdx, [case_key + r11*8]
    cmp rdx, r9
    jle .place
    mov [case_ord + r10*4], r11d
    dec r10d
    jmp .j
.place:
    mov [case_ord + r10*4], eax
    inc r8d
    jmp .i
.done:
    ret

; sw_tree: edi = first, esi = end (positions in case_ord). Emits a binary search over the keys of those labels; every path ends in
; a jump to a label body or to the default. The value to look at is in the local sw_vslot.
sw_tree:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx, edi
    mov r12d, esi
    mov eax, r12d
    sub eax, ebx
    cmp eax, 3
    jbe .leaf
    shr eax, 1
    lea r13d, [rbx + rax]               ; the split point
    cmp dword [sw_text], 0
    je .split
    ; labels with the same hash stay together: the key at the split point must differ from the one before it
    mov r14d, r13d
.dn:
    cmp r14d, ebx
    jbe .up
    mov eax, [case_ord + r14*4]
    mov rdx, [case_key + rax*8]
    mov eax, [case_ord + r14*4 - 4]
    cmp rdx, [case_key + rax*8]
    jne .got
    dec r14d
    jmp .dn
.got:
    mov r13d, r14d
    jmp .split
.up:
    mov r14d, r13d
.upl:
    inc r14d
    cmp r14d, r12d
    jae .leaf                           ; the whole range has one hash
    mov eax, [case_ord + r14*4]
    mov rdx, [case_key + rax*8]
    mov eax, [case_ord + r14*4 - 4]
    cmp rdx, [case_key + rax*8]
    je .upl
    mov r13d, r14d
.split:
    mov edi, [sw_vslot]
    CG load_local_a
    mov eax, [case_ord + r13*4]
    mov rdi, [case_key + rax*8]
    CG imm_b
    push 0
    mov edi, CC_LT
    mov rsi, rsp
    CG jcmp_chain                       ; value < key at the split point: the lower half
    mov edi, r13d
    mov esi, r12d
    call sw_tree                        ; the upper half
    pop rdi
    call patch_here
    mov edi, ebx
    mov esi, r13d
    call sw_tree                        ; the lower half
    jmp .out

.leaf:
    cmp dword [sw_text], 0
    jne .tleaf
    ; integers: every label is a range lo..hi; the value stays in A
    mov edi, [sw_vslot]
    CG load_local_a
    mov r13d, ebx
.il:
    cmp r13d, r12d
    jae .idone
    mov r14d, [case_ord + r13*4]
    mov rdi, [case_val + r14*8]
    CG imm_b
    mov rax, [case_val + r14*8]
    cmp rax, [case_hi + r14*8]
    je .single
    push 0
    mov edi, CC_LT
    mov rsi, rsp
    CG jcmp_chain
    mov rdi, [case_hi + r14*8]
    CG imm_b
    mov edi, CC_GT
    mov rsi, rsp
    CG jcmp_chain
    mov rdi, [case_pos + r14*8]
    CG jmp_back
    pop rdi
    call patch_here
    jmp .inext
.single:
    push 0
    mov edi, CC_NE
    mov rsi, rsp
    CG jcmp_chain
    mov rdi, [case_pos + r14*8]
    CG jmp_back
    pop rdi
    call patch_here
.inext:
    inc r13d
    jmp .il
.idone:
    call sw_emit_default
    jmp .out

.tleaf:
    ; text: for every group of labels with one hash: if the hash matches, compare the text with each label of the group
    mov r13d, ebx
.tl:
    cmp r13d, r12d
    jae .tdone
    mov r14d, [case_ord + r13*4]
    mov r15, [case_key + r14*8]
    mov edi, [sw_vslot]
    CG load_local_a
    mov rdi, r15
    CG imm_b
    push 0                              ; chain to the next group
    mov edi, CC_NE
    mov rsi, rsp
    CG jcmp_chain
.te:
    mov r14d, [case_ord + r13*4]
    mov edi, [sw_sval]
    CG load_local_a
    CG push_a
    mov edx, [case_val + r14*8]
    call obj_localize_string
    mov esi, R_DATA
    CG lea_global_a
    CG push_a
    mov rdi, w_streq
    call emit_call_named
    mov edi, 2
    CG drop
    push 0
    mov rdi, rsp
    CG jz_chain
    mov rdi, [case_pos + r14*8]
    CG jmp_back
    pop rdi
    call patch_here
    inc r13d
    cmp r13d, r12d
    jae .tgrp
    mov eax, [case_ord + r13*4]
    cmp r15, [case_key + rax*8]
    je .te
.tgrp:
    pop rdi
    call patch_here
    jmp .tl
.tdone:
    call sw_emit_default
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
