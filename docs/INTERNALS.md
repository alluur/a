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
current CPU (`__ARCH`: 0 x86-64, 1 ARM64, 2 RISC-V 64, 3 LoongArch64; the last three share the generic system call numbers). Windows has no stable syscalls, so the PE image imports
`WS2_32.DLL` as a second descriptor (IAT slots 40-48, slot 39 is the null terminator of the kernel32
thunks) and `net.a` reaches it through the generic builtin `__winapi(slot, a1..a4)`, a small blob
that does `call [IAT + slot*8]` with the Windows x64 convention. Adding another Windows API needs
only a new import name in `imp_names_ws2` (or a new DLL list) and a slot constant in A code.

## Windows imports

The PE import table has three DLLs: `KERNEL32.DLL` (slots 0..38), `WS2_32.DLL` (slots 40..59: sockets, UDP, `WSAPoll`, name lookup)
and `IPHLPAPI.DLL` (slots 61..68: adapter, ARP, route, TCP and UDP tables, ICMP echo). The slots are the first argument of
`__winapi` / `__winapix`; the null terminators between the lists occupy slots 39 and 60. `build_idata` writes the three
descriptors, so a new function only needs a name in `imp_names*` and a slot constant in the A code.

## Module files (`a_module` / `a_import`)

`a_module NAME { ... }` is `module_enter` (shared with `module NAME;`) plus a recursive `parse_items` that stops
at `}` (`in_amodule`; `compile_file` clears it for imported files). `a_import(file [, names])` copies the file
name into `importbuf`, uses the normal `file_include` and then, in pass 1, `import_names` creates an `S_ALIAS`
symbol (`SYM_VAL` = index of the real symbol) in the importing module for each listed public member of the file
that was just compiled (`last_file_id`). `sym_lookup` and `sym_find_global` resolve aliases through
`alias_resolve`. Inside `a_import( ... )` the lexer reads `'text'` as a string (`sq_string`). The name list is
kept on the stack because nested imports reuse `importbuf`.

## CPU backends

`src/cg_x86.asm`, `cg_a64.asm`, `cg_rv64.asm` and `cg_la64.asm` implement the same list of primitives (`CGLIST` in `defs.inc`);
`install_backend` copies the table of the chosen CPU into `cg_vt`. A new CPU needs: the primitives, `apply_relocs_*`, a column
of runtime blobs in `builtin_tab` (write, read, exit, syscall, open, close, setjmp, longjmp ...), a row in `target_table`,
the ELF machine number in `build_elf` and the `__ARCH` value. Instruction words are built with assembly-time macros
(`RV_I(...)`, `LA_2RI12(...)`) and were checked with `llvm-mc` (`llvm-mc --disassemble -triple=riscv64` /
`loongarch64` on the bytes of an output file). Both new backends use 16 byte stack slots and the frame layout of AArch64
(`[fp+16]` = the last parameter), so the compiler core did not change.

* **RISC-V 64:** A = a0, B = a1, D = a2, scratch t0-t3, frame pointer s0. Jumps and calls are `auipc` + `jalr` pairs; while a
  forward chain is open the second word holds the link. 64 bit constants take at most 8 instructions.
* **LoongArch64:** A = $a0, B = $a1, D = $a2, scratch $t0-$t3, frame pointer $fp. Jumps and calls are single `b` / `bl`
  instructions (+-128 MiB); data and function addresses are `pcaddu12i` + `addi.d`.

## Object files and the linker (`src/link.asm`)

`ac -c` runs the normal three passes with `obj_mode` set and writes the result as an object (`write_object`); `ac a.ao b.ao`
(`link_mode`) compiles only the library part and then appends the objects (`link_place`).

**Object mode.** Functions that live in a built-in library file (file table flag at offset 32), prototypes without a body
and builtins are *external* (`sym_is_external`). A call to one is emitted as `lea_func_a` + `call_a`, i.e. an `R_CODE`
relocation that names the symbol, so no backend needs to know about linking. Global variables of the libraries and `extern`
variables are accessed with an `R_DATA` / `R_BSS` relocation whose spare dword (`rel_buf+12`, set through `ext_reloc_sym`)
holds the symbol index. While a library file is compiled the data and bss allocation positions are swapped for a separate
area (`swap_foreign`, offsets from `FOREIGN_DATA_BASE` / `FOREIGN_BSS_BASE`), so the object contains only the unit's own data;
library relocations in the data section are dropped and library string constants are copied (`obj_localize_string`).
There is no entry stub and no runtime blob in an object; the Windows stack probe call is an `R_CHKSTK` relocation.

**Format.** Header, code, data, relocations (`offset, kind[|0x100 symbol], target`), symbols (`name, kind, flags, value, npar`),
the library modules to import (`needs`) and a string table; see the comment at the top of `src/link.asm`. A symbol key is
`module:Class:name` (`<ctor>` for constructors).

**Link.** `link_load_objects` reads the objects and synthesizes the "main" file of the program: `import` lines for the needed
library modules and a prototype of `main`. The three passes then compile the library; `link_mark_roots` keeps the library
functions the objects call; `link_place` copies code / data / bss behind the library output, builds the export table
(a second strong definition is an error, methods are weak), resolves every undefined symbol against the other objects and then
the library symbol table, creates hidden function symbols for `R_CODE` / `R_CODE64` targets, and adds the relocations
(`R_DATA64` words are rebased in place) to `rel_buf`. After that the usual `check_undefined` and `build_elf` / `build_pe` run.

Tests: `tests/link.sh` (every directory of `tests/link` is a multi-file program).

## The graphics stack (`lib/gfx.a`, `adp`, `wsrv`, `gui`, `wvnc`, `wfb`, `dm`)

All of it is ordinary A code in embedded modules (see docs/GUI.md for the user view). Notes for the compiler side:

* The modules rely on `class X;` forward declarations (completed by the real definition in pass 1, `parse_aggregate`), on
  `super();` in derived constructors (base constructors are not run implicitly), on classes derived across modules with
  virtual methods (`wsrv.Backend` -> `wvnc.Vnc`), and on `func` fields called with an argument for the widget callbacks.
* `net.poll` uses a static buffer (a server polls many times a second; the bump allocator never frees).
* The fonts are 4-bit coverage bitmaps in hex strings (`lib/gfxfont.a`, made by `docs/gen_font.py`, below the 64 KB string
  limit of the lexer) decoded at first use.
* `tests/t111_gui_server.a` runs a display server and its clients in one process (`gui.idleHook`); rendering checksums are
  compared between all targets. `tests/gui.sh` runs real processes with a VNC client (`tests/gui/rfbclient.py`).
* `guix` is a separate module on top of `gui` (derived widgets across modules). The only changes `gui` needed: `Window.popup`
  (a window-sized widget drawn after the root and given all mouse/key events: menus and the combo list are popups that paint
  their own panels and do their own hit tests), `Window.keyPreview` (the menu bar sees keys first, for accelerators),
  `Widget.wantsScroll` (the wheel goes to the first widget under the pointer, walking up the parents, that scrolls),
  `Widget.reveal` (called up the parent chain when a widget gets the focus; the scroll view scrolls to it), tooltips
  (a `Display` timer started when the pointer moves onto a widget with a `tooltip`), and `Widget.onContext`.
* `F_LOCK` windows: layer 3, the server's `findWin`, `setFocus` and `topFocusable` consider only the lock window while one is
  mapped, `Alt+Tab`/`Alt+F4` are swallowed. The lock window is forced to the screen size and gets an `E_RESIZE` at its first
  present. The tests use `settle()` loops of the server and the client with `Display.sync()` because a full-screen frame
  needs many reads on the server side.
* `tests/t115_gui_widgets.a` (menus, popups, accelerators, combo, radio, tabs, scrolling, spin box, splitter, tooltip, all the
  dialogs, with a directory made by the test), `tests/t116_gui_lock.a` (lock, wrong password, delay, unlock).
* `gterm`: the screen is an array of `Line*` (two ints per cell: code point + flags, foreground + background colour), so scrolling
  moves pointers; the history is a ring of 2000 lines. The parser is a small state machine fed byte by byte (`feedByte`); it
  is the only way output reaches the grid, so `feed()` and the pseudo terminal share one path. The pty is opened by hand:
  `/dev/ptmx`, `TIOCSPTLCK`, `TIOCGPTN` (the ioctl numbers are the same on all four CPU families), `fork`, `setsid`, open the
  slave (it becomes the controlling terminal), `dup2`, close every other descriptor (also the display socket, so the display
  server notices when the terminal program ends), `execv`. The master is polled by `gui.Display.watch`.
* `tests/t117_gui_term.a` covers the escape sequences, keys, selection and a real shell on a pty (`.out.windows`: `no pty`).
* `gimg` decodes PNG with a puff-style inflate (canonical Huffman decoding by code length counts); `tests/t118_gimg.a` embeds images made
  by another program (PNG of every kind, BMP, PPM) as hex and compares pixel hashes. Maximized windows (`wsrv.Win.maximized`) keep
  their old rectangle and get an `E_RESIZE`; dragging and the resize grip are off while maximized. `tests/t119_gui_table.a`:
  maximize, TableView, TreeView.
* Minimizing: `Win.minimized` and `Win.shown()` (visible, mapped, not minimized) replace the old visibility tests in the server;
  `listed()` decides which windows a taskbar sees. The window list is pulled (a taskbar polls every 400 ms), the server never
  pushes it. Notifications are undecorated `F_ABOVE | F_NOFOCUS` windows in six slots. `tests/t120_gui_extras.a` covers all of it.
* Display authentication: `wsrv.Client.authed/nonce/born`; `handleRequest` answers `Q_HELLO` with `E_AUTH` when a cookie is set and ignores
  everything but `Q_AUTH` until it verifies (`hash.hmacSha256`, compared with `hash.equalConstantTime`). `secure.unique` gives
  the nonce (getrandom/`/dev/urandom`; a SHA-256 mix of counter, clock and an address on Windows, where only uniqueness is needed
  for a challenge). `wvnc` adds security type 2 with `des.vncResponse` (the DES tables are checked against `openssl enc -des-ecb`
  in `tests/gui/rfbclient.py`, an independent implementation). `tests/t121_gui_auth.a`: RFC 4231 HMAC vectors, the DES vector,
  the handshake in one process. `tests/t122_gui_net.a`: `gnet.Fetch` against a tiny server stepped from `gui.idleHook`.
* A name clash to know about: `cstdlib` defines a function `random`, so a module called `random` cannot be imported by a file that
  imports `cstdlib` (the secure helpers live in `secure`).
* `wweb`: a `wsrv.Backend` like `wvnc`. A viewer is first an HTTP request (read up to the empty line; GET `/` serves the page with the
  token put in, `/ws` with an `Upgrade` header becomes a WebSocket) and then a frame parser (browser frames are always masked,
  messages are at most 4 KB). The output goes through a queue that is written without blocking (`net.waitWritable(fd, 0)`); a
  browser that falls 6 MB behind gets its queue dropped and the whole screen again. The pixel format is run-length coded
  (`queueBand`); the page and `tests/gui/webclient.py` decode it. The test in `tests/gui.sh` compares the web screen pixel for
  pixel with a VNC viewer of the same server, and the page was also tried in Chromium (Playwright) for the click and the cursor.
* `gnet.Conn/Listener/Beacon/Chat` run entirely on `Display.watch` and `Display.after`; `t123_gui_chat` runs three chats and the
  display connection in one process, so the discovery, the connection rule and the messages are tested without extra programs.
* `ghtml`: the parser (`parseHtml`) fills a `Doc` of `Block`s (paragraph, heading, list item, pre, rule) that hold `Item`s (a word, an
  image, a line break or a gap between table cells) with a style and a size in percent. `layoutAll` places every item in page
  coordinates (greedy line filling, the line height is the tallest item, items are centred vertically on their line) and runs
  again when the width changes or a picture arrives; painting and link hit tests only look at the blocks in view. Markdown is
  converted to HTML text first, so there is one renderer. `tests/t125_gui_html.a` covers text, entities, URLs, Markdown, links,
  scrolling and a screenshot checksum; `tests/gui.sh` runs `abrowse` against a local web server.
* Forms in `ghtml`: the parser makes a `Control` (type, name, value, widget) for every input, textarea, select (its options are added to a
  `guix.ComboBox` when the option closes) and button (whose label is the text up to `</button>`), and an item of kind `K_CONTROL`
  that reserves the widget's size in the line. The widgets are real children of the `HtmlView`; `positionControls` moves them with
  the scrolling (`clampScroll` calls it) and hides the ones outside the view. `Widget.reveal` of the view scrolls a control into view
  when it gets the focus. `queryOf` builds the data in the order of the controls. Anchors are recorded when a tag with `id` or an `a name`
  is opened (the index of the block that follows, or the empty current block that is reused). `tests/t126_gui_forms.a` runs
  the page, the clicks and keys, and a tiny web server in the same process for the POST, cookie and redirect cases.
