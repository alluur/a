; placeholder: AArch64 backend (filled in below)
section .text
%macro A64STUB 1
a64_%1:
    ERR "AArch64 backend not implemented yet"
%endmacro
CGLIST A64STUB
apply_relocs_a64:
    ERR "AArch64 backend not implemented yet"
section .rodata
%macro CGT_A64 1
    dq a64_%1
%endmacro
cg_tab_a64:
    CGLIST CGT_A64
section .text
