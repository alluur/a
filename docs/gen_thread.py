#!/usr/bin/env python3
"""Generates the asm block that starts a thread (clone) in lib/thread.a, from assembler text checked by llvm-mc.
usage: docs/gen_thread.py   (rewrites the @CLONE@ marker area of lib/thread.a.in into lib/thread.a)"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asmgen import *

# The block gets the address of a record of 8 ints in A:
#   [0] clone flags  [1] top of the new stack  [2] address for the parent tid  [3] address of the child tid (cleared at exit)
#   [4] function     [5] argument              [6] result (written by the thread)
# It makes the clone system call; the new thread calls function(argument), stores the result and exits.
# The parent gets the thread id (or a negative error number) in A.
# (clone's argument order: x86-64 and LoongArch use flags, stack, ptid, ctid, tls; AArch64 and RISC-V use flags, stack, ptid, tls, ctid)
CLONE = {
 'x64': """
movq %rax, %r12
movq 0(%r12), %rdi
movq 8(%r12), %rsi
movq 16(%r12), %rdx
movq 24(%r12), %r10
xorl %r8d, %r8d
movl $56, %eax
syscall
testq %rax, %rax
jnz 1f
pushq 40(%r12)
callq *32(%r12)
movq %rax, 48(%r12)
movl $60, %eax
xorl %edi, %edi
syscall
1:
""",
 'arm64': """
mov x9, x0
ldr x0, [x9, #0]
ldr x1, [x9, #8]
ldr x2, [x9, #16]
mov x3, #0
ldr x4, [x9, #24]
mov x8, #220
svc #0
cbnz x0, 1f
ldr x1, [x9, #40]
str x1, [sp, #-16]!
ldr x10, [x9, #32]
blr x10
str x0, [x9, #48]
mov x0, #0
mov x8, #93
svc #0
1:
""",
 'riscv64': """
mv t6, a0
ld a0, 0(t6)
ld a1, 8(t6)
ld a2, 16(t6)
li a3, 0
ld a4, 24(t6)
li a7, 220
ecall
bnez a0, 1f
ld t0, 40(t6)
addi sp, sp, -16
sd t0, 0(sp)
ld t1, 32(t6)
jalr t1
sd a0, 48(t6)
li a0, 0
li a7, 93
ecall
1:
""",
 'loongarch64': """
move $t8, $a0
ld.d $a0, $t8, 0
ld.d $a1, $t8, 8
ld.d $a2, $t8, 16
ld.d $a3, $t8, 24
li.d $a4, 0
li.d $a7, 220
syscall 0
bnez $a0, 1f
ld.d $t0, $t8, 40
addi.d $sp, $sp, -16
st.d $t0, $sp, 0
ld.d $t1, $t8, 32
jirl $ra, $t1, 0
st.d $a0, $t8, 48
li.d $a0, 0
li.d $a7, 93
syscall 0
1:
"""}

here = os.path.dirname(os.path.abspath(__file__))
tmpl = open(os.path.join(here, 'thread.a.in')).read()
out = tmpl.replace('@CLONE@', asm_block(CLONE, 'rec'))
open(os.path.join(here, '..', 'lib', 'thread.a'), 'w').write(out)
print('lib/thread.a written')
