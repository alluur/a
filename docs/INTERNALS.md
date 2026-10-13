# How the compiler works

This document is for people who want to read, debug or extend `ac`. The compiler is a single
NASM translation unit (`src/ac.asm` includes the other files) assembled with `nasm -f elf64` and
linked with `ld`. It uses no libc: it talks to Linux through `syscall` only.

## Pipeline

```
 source ──► lexer ──► parser + code generator ──► relocation ──► ELF / PE writer ──► file
            (on demand)   (one pass, no AST)         (addresses)
```

* There is **no AST and no intermediate representation**. A recursive-descent parser emits machine
  code while it parses. Expression results are left in an accumulator, so the generated code is a
  simple stack machine — small, predictable and easy to debug.
* The compiler makes **three passes** over the sources:
  1. *Declarations:* every type, constant, enum, global variable, function signature, class member
     and module is registered. Function bodies are skipped (token-level brace matching).
  2. *Check:* every function body is compiled (so every error is reported, even in code nobody
     calls) and the call graph is recorded. Everything is known, so functions can be called before
     their definition, and calls to not-yet-emitted functions are patched through chains.
  3. *Output:* the reachable functions are found from `main` (`compute_reachable`), the code buffer
     is reset and only those functions are compiled again (dead function elimination). A
     hello-world is about 4 KB although the standard library has hundreds of functions.
* Imports are processed in both passes; a file is parsed once per pass.

## Source files

| File | Content |
|---|---|
| `defs.inc` | numeric constants, token kinds, symbol/struct layouts, the `EM`, `ERR`, `CSTR`, `IATCALL` macros and the backend primitive list (`CGLIST`) |
| `util.asm` | error reporting with source line, file I/O, `emit_*` helpers, data/bss allocation, relocation list |
| `lexer.asm` | tokenizer: keywords, numbers, strings/escapes, operators, `lex_save`/`lex_restore` (lookahead and imports) |
| `symtab.asm` | symbol table, struct and field tables, type helpers |
| `expr.asm` | type parsing, constant expressions, primary/postfix/unary/binary/logical/assignment parsing, calls |
| `stmt.asm` | blocks, `if`/`while`/`do`/`for`/`switch`, `break`/`continue`/`return`, local declarations, `const` |
| `decl.asm` | functions, classes/structs, enums, globals, modules, imports, top-level loop |
| `cg_x86.asm` | x86-64 backend (Linux, Android x86-64, Windows) |
| `cg_a64.asm` | AArch64 backend (Linux, Android) |
| `main.asm` | command line, file table and `import` search, builtin runtime blobs, ELF and PE writers, buffers |
| `../lib/std.a` | the standard library, written in A and embedded with `incbin` |

## Conventions inside the compiler

* Registers: all routines preserve `rbx`, `rbp`, `rsp`, `r12`–`r15`; arguments are in `rdi`, `rsi`,
  `rdx`, `rcx`, `r8`, `r9`; results in `rax`. The `emit_*` helpers and all backend primitives preserve
  **every** register, so parser code never needs to save state around code emission.
* Global parser state lives in memory: current token (`tk`, `tk_val`, `tk_ptr`, `tk_len`, `tk_line`),
  the expression result (`e_type`, `e_lval`), the current class (`cur_class`), function
  (`cur_func`), frame size, loop stack, and so on.
* All data structures are static `bss` arrays (see the bottom of `main.asm`); there is no
  allocator. The buffers cost no file size. Limits: 65,536 symbols, 4,096 structs, 16 MiB of code,
  8 MiB of data.

## Types

A type is one 64-bit value:

```
bits  0..7   kind: 0 void, 1 int, 2 char, 3 bool, 4 struct/class
bits  8..15  pointer depth
bits 16..31  struct index (for kind 4)
bit   32     "array" flag (an array lvalue; it decays to a pointer when used as a value)
```

Inheritance: a derived class copies the field entries of its base class into its own field list (so lookup
needs no chain walk) and starts its layout after the base size. `st_base`, `st_vptr`, `st_vcount`, `st_vt` and
`vt_method` (symtab-side arrays indexed by struct) hold the base class, the vtable pointer offset, the number of
slots, the vtable's data offset and the method symbol of every slot. The vtable is an array of code addresses in
the data section, filled by `R_CODE64` relocations; virtual methods are roots of the dead-function elimination.
`gen_call` dispatches a call of an `F_VIRTUAL` method through `this -> vptr -> slot` (`load_stack_a`, `call_a`)
unless it comes from `super.`; objects get their vtable pointer from `emit_vptr_init` (new, locals) or a
`R_DATA64` relocation (globals).

Enums are `int`. Sizes: pointers 8, `int` 8, `char`/`bool` 1, structs from the struct table.

## Expression code generation

Every `parse_*` routine leaves its result in the abstract accumulator **A**:

* `e_lval = 1`: A holds the **address** of an lvalue and `e_type` its type; `to_rvalue` loads the
  value (arrays decay, structs stay addresses).
* `e_lval = 0`: A holds the value.

Binary operators: parse left → `to_rvalue` → `push A` → parse right → `to_rvalue` → `B = A; pop A`
→ operator primitive (`A = A op B`). Logical `&&`, `||`, `?:` and conditions use *jump chains*
(below). Pointer arithmetic is scaled in `binop_emit`.

### Calling convention

* Arguments are pushed **left to right** (`this` first for methods); the caller removes them.
* Result in A.
* Callee: parameter `i` of `n` is at `[fp + 16 + slot*(n-1-i)]` (slot = 8 bytes on x86-64, 16 bytes
  on AArch64); locals are at negative offsets from the frame pointer.
* Methods are ordinary functions with a hidden first parameter `this`.

### Jump chains

Forward jumps are emitted with a placeholder whose payload is the position of the previous
placeholder for the same target (a linked list threaded through the code). `patch_chain` walks the
list and writes the real offsets once the target is known. The same mechanism patches calls to
functions that are defined later (`SYM_PATCH`).

## The peephole optimiser

The generator is a stack machine, but common shapes are tightened on the fly. The parser records
*markers* — where the most recent instruction of a kind started and ended — and rewrites the tail
of the code buffer when a later construct proves the pattern:

| Marker | Rewrite |
|---|---|
| `pk_*` (address of a local) | `lea x; load` becomes one `load_local` (`to_rvalue`), `x = e` becomes `store_local`, `x++` / `x += e` operate in place |
| `imm_*` (constant in A) | `a OP constant` loads the constant straight into B; `-constant` is folded |
| `ld_*` (local just loaded) | `a OP local` loads the local straight into B (no push / pop) |
| `cmp_*` (comparison) | compare + `setcc` + test + branch becomes a single compare-and-jump (`jcmp_chain`) |
| `pi_*` (postfix `i++`) | when the old value is unused (`i++;`), regenerated as load / add / store |

Safety rules — every rewrite must hold *all* of these, otherwise it is skipped:

1. the marker's end position equals `code_pos` (nothing was emitted since);
2. no jump target was bound at that position (`last_label`; see `tail_is`), because a label at the
   end means the code before it is only a branch of a bigger construct such as `c ? a : b`;
3. for operands: the marker's *start* equals the position where the operand began
   (`imm_pos` / `ld_pos` == the position right after the `push`);
4. `rewind_code` truncates the code buffer **and clears every marker** — a stale marker whose end
   happens to coincide with a later position was a real bug once (fuzzer seed 3, AArch64).

The result runs at roughly the speed of `gcc -O0`.

## Backends

The parser never emits bytes directly. It calls **backend primitives** through a table:

```nasm
CG push_a            ; expands to  call [cg_vt + CGI_push_a*8]
```

`CGLIST` in `defs.inc` lists them (push/pop, immediates, local/global addresses, loads and stores,
arithmetic, comparisons, jumps and chains, calls, prologue/epilogue, …). `cg_x86.asm` and
`cg_a64.asm` each implement the whole list; `install_backend` copies the right table into `cg_vt`
at start-up.

Abstract machine: **A** (accumulator: `rax` / `x0`), **B** (second operand: `rcx` / `x1`),
**D** (temporary: `rdx` / `x2`), and a stack of one-slot values.

To add a new architecture:
1. add `ARCH_xxx` in `defs.inc`, write `cg_xxx.asm` with `xxx_<primitive>` for every name in `CGLIST`
   (the assembler reports any missing one), plus a `cg_tab_xxx` table, `apply_relocs_xxx` and runtime
   blobs for `__write`, `__read`, `__exit`, `__open`, `__close`, `__syscall`, `__cmdline`;
2. add the columns to `builtin_tab` and the target parsing in `main.asm`;
3. teach `build_elf` the machine type.

### Relocations

References to data/bss are recorded while generating code (`R_DATA`, `R_BSS`, `R_IAT`, `R_DATA64`)
and resolved when the final layout is known: x86-64 uses RIP-relative `rel32`, AArch64 uses
`adrp` + `add` pairs. All code is position independent, only 64-bit pointers stored in data (string
constants in global initialisers) need absolute addresses and the images are linked at a fixed
base.

## Output formats

**ELF64** (`build_elf`): two `PT_LOAD` segments — headers + code (R+X) and data + bss (R+W) — and a
`PT_GNU_STACK`. Code starts at file offset `0x100`; the data segment is page aligned (4 KiB on
x86-64, 16 KiB on AArch64). The entry point is a small stub that gets `argc`/`argv` from the stack,
calls `main`, and calls `__exit`.

**PE32+** (`build_pe`): `.text`, `.data` (data + bss as virtual size) and `.idata` (imports from
`KERNEL32.DLL`). Image base `0x140000000`, file alignment `0x200`, section alignment `0x1000`, no
relocations, 8 MiB stack reserve. Calls to Windows go through the import address table
(`call [rip+IAT]`); the entry stub builds `argc`/`argv` with `__win_init_args` (in `std.a`).
Every function prologue calls a `chkstk` helper that touches the stack pages in order.

## Default parameter values and function pointers

* `func_register` stores the parameters of a function in the pool `ptype_pool` as `types[n]`, `defaults[n]`, `required`
  (`SYM_EXTRA` points at it). `gen_call` pushes the default values of the missing trailing arguments (constants,
  evaluated by `const_expr` when the declaration is parsed) after the explicit ones.
* `func` is a predefined `S_ENUM` symbol with the flag `F_FUNCTYPE`; `parse_type` turns it into the type kind `TY_FUNC`
  (8 bytes like `int`). A function name that is not followed by `(` becomes a `TY_FUNC` value: `emit_funcaddr_sym` records
  the call-graph edge (so dead function elimination keeps the function) and emits `lea_func_a`, which leaves a placeholder
  and a `R_CODE` relocation (the symbol index); `apply_relocs` resolves it when the code layout is final (`rel32` on
  x86-64, `adrp` + `add` on AArch64). A call through a value (`parse_postfix`, `.callptr`) pushes the target first, then
  the arguments, fetches the target back with `load_stack_a` and uses `call_a`; the callee cannot tell the difference.
* `setjmp` / `longjmp` are builtin blobs (`bl_lin_setjmp`, `bl_a64_setjmp` ...): they save and restore the frame pointer, the
  stack pointer after the return and the return address; the generated code keeps no state in other registers.
* The entry stub calls the standard library's `exit` (not `__exit`), which runs the `atexit` functions and writes out the
  buffers registered in `__wreg` (see `cstdio`).

## Debugging tips

```sh
# disassemble the generated code of any output (raw bytes at file offset 0x100 for ELF)
objdump -D -b binary -mi386:x86-64 -M intel --start-address=0x100 prog.elf | less
aarch64-linux-gnu-objdump -D -b binary -maarch64 --start-address=0x100 prog.arm64.elf | less
objdump -d -M intel prog.exe                                 # PE files have proper headers

gdb ./build/ac                                               # debug the compiler itself
(gdb) run examples/hello.a -o /tmp/h
qemu-aarch64 -g 1234 prog.arm64.elf &                        # debug ARM64 output with gdb-multiarch
```

Errors raised by the compiler print `file:line: error: …` with the line and a caret, using `tk_line`
and `tk_start` of the current token.

## Testing

`tests/run.sh [pattern]` compiles and runs each `tests/t*.a`. Expected stdout is `tNN_name.out`,
the expected exit code `tNN_name.exit` (default 0), stdin `tNN_name.in`, and `tNN_name.err` holds a
fragment of the message for tests that must fail to compile (`t9x_err_*`). The same suite is run
for every target (see [TARGETS.md](TARGETS.md)).

### Differential fuzzing

`tests/fuzz/difffuzz.py [count] [seed] [target]` generates random programs (arithmetic, comparisons,
`char`/`bool` wrap-around, arrays, globals, calls, `if` / `for` / `while` / `switch`, increments and
compound assignments) once in A and once in C, builds them with `ac` and `gcc -O0 -fwrapv`, runs both
and compares the output. `target` can be any `-t` value, so the same random programs validate the x86-64,
ARM64 (via QEMU) and Windows (via Wine) backends against the same C reference.

When a program differs, the script keeps it as `/tmp/difffuzz_fail_<seed>_<n>.[ac]`.
`tests/fuzz/reduce.py seed n [target]` drops statements, and `tests/fuzz/ddmin.py file.a file.c [target]`
drops individual lines, until a minimal reproducer remains. Every compiler bug found this way got a
regression test (`t19_peephole`, `t20_regress_marker`, …).

## Built-in modules

`lib/*.a` other than `std.a` are embedded with the `EMB "name", "lib/name.a"` macro in `main.asm`
(a table of name, label, source, length, file entry). `import name;` looks for a real file next to the
importing source first, then at the embedded table, then in `lib/` directories. Adding a module means
creating the file and one `EMB` line. Modules are only compiled when imported.

## The C library modules

`lib/c*.a` (see [CLIB.md](CLIB.md), generated by `docs/gen_clib.py`) are ordinary embedded modules without a `module` line, so
their names are global. They use only the builtins and each other: `cstdio` imports `cstdlib`, `cfloat` (for `%f` in
`scanf`) and `cerrno`; `cmath` is self-contained and implements IEEE 754 doubles in software: `__fpack` rounds and
packs, the basic operations are exact, and the elementary functions are computed in double-double arithmetic
(`__dd_*`, about 106 bits) and rounded once, which makes them correctly rounded in practice. The tests
`t45_cmath_arith`, `t46_cmath_funcs` and `t47_cfloat` are generated by `tests/fuzz/gen_*_test.py` from mpmath, gcc and
Python results.

## The `net` module and `__winapi`

`lib/net.a` is embedded in the compiler like `std.a` but only compiled when a program says `import net;`.
It is plain A code. On Linux / Android it calls `__syscall` with the socket system call numbers of the
current CPU (`__ARCH` picks x86-64 or ARM64). Windows has no stable syscalls, so the PE image imports
`WS2_32.DLL` as a second descriptor (IAT slots 40-48, slot 39 is the null terminator of the kernel32
thunks) and `net.a` reaches it through the generic builtin `__winapi(slot, a1..a4)`, a small blob
that does `call [IAT + slot*8]` with the Windows x64 convention. Adding another Windows API needs
only a new import name in `imp_names_ws2` (or a new DLL list) and a slot constant in A code.

## Module files (`a_module` / `a_import`)

`a_module NAME { ... }` is `module_enter` (shared with `module NAME;`) plus a recursive `parse_items` that stops
at `}` (`in_amodule`; `compile_file` clears it for imported files). `a_import(file [, names])` copies the file
name into `importbuf`, uses the normal `file_include` and then, in pass 1, `import_names` creates an `S_ALIAS`
symbol (`SYM_VAL` = index of the real symbol) in the importing module for each listed public member of the file
that was just compiled (`last_file_id`). `sym_lookup` and `sym_find_global` resolve aliases through
`alias_resolve`. Inside `a_import( ... )` the lexer reads `'text'` as a string (`sq_string`). The name list is
kept on the stack because nested imports reuse `importbuf`.
