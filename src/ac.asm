; =============================================================================
;  ac - the A language compiler
;  Written entirely in x86-64 assembly (NASM syntax), no libc, no linker needed
;  to run: it reads .a source files and writes native executables directly.
;
;  Build:  nasm -f elf64 -i src/ src/ac.asm -o build/ac.o && ld -o build/ac build/ac.o
;  (c) Aytict - https://aytict.fi
; =============================================================================
bits 64
default abs

%include "defs.inc"

; the Windows runtime fixup table starts here (entries are added by IATCALL)
[section .iatfix]
iatfix_start:

section .text
%include "util.asm"
%include "lexer.asm"
%include "symtab.asm"
%include "expr.asm"
%include "stmt.asm"
%include "decl.asm"
%include "main.asm"
