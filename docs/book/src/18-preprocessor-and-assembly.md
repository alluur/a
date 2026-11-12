# Preprocessor, linking and assembly

This chapter is about the lowest layers of the language. The **preprocessor** rewrites the source text before the compiler sees it: macros, conditional compilation and file inclusion. **Separate compilation** lets you compile files one at a time and join them with the linker, as a C toolchain does. **Inline assembly** puts machine code of your choice into a function. You will rarely need all three, but when you do, nothing else will do.

In this chapter:

- `#define`, `#include`, `#if` and the other directives
- predefined macros and the `-D` and `-E` options
- compiling units with `ac -c` and linking the `.ao` files
- inline assembly with `asm`

## Macros

Every source file is run through a C-style preprocessor before it is compiled. A directive starts with `#` at the beginning of a line (spaces before it are fine). A line that ends with `\` continues on the next line.

| Directive | Meaning |
|---|---|
| `#define NAME body` | an object-like macro: `NAME` is replaced by `body` |
| `#define NAME(a, b) body` | a function-like macro. In the body `#a` makes a string of the argument, `a ## b` pastes two tokens, `...` and `__VA_ARGS__` take the remaining arguments |
| `#undef NAME` | removes a macro |
| `#include "file"` / `#include <file>` | inserts a file |
| `#pragma once` | the file is only included once |
| `#ifdef X`, `#ifndef X`, `#if expr`, `#elif expr`, `#else`, `#endif` | conditional compilation |
| `#error text` | stops with an error |
| `#warning`, `#line` | accepted and ignored |

{{sample lang/pp_define}}

What to notice:

- `SQUARE(N + 1)` became `((5 + 1) * (5 + 1))` = 36. The parentheses in the macro body are what make that work: a macro replaces **text**, so always put parentheses around parameters and around the whole body.
- `#x` turns an argument into a string (`NAME_OF(hello world)` is `"hello world"`); `a##b` joins two names into one, here to generate the functions `get_width` and `get_height`.
- `LOG(...)` forwards all its arguments with `__VA_ARGS__`.
- `REPEAT` uses a backslash at the end of each line to spread the macro over several lines.
- Names inside string literals are not replaced, and a macro is not expanded inside its own body (`#define A A + 1` is fine).
- `#undef N` removes the macro, so the next `#define N 10` may give it a new value: the last line of the output shows 10.
- The preprocessor keeps the number of lines unchanged, so error messages show the right line.

::: tip

For constants, the compile-time features of A itself, `const` and `static if`, are usually the better choice: they are typed, scoped and checked. Use macros for code that has to differ between builds, or to generate declarations.

:::

## Conditional compilation

`#ifdef X` and `#ifndef X` test whether a macro is defined; `#if expr` tests a number. In `expr` you can use `defined(X)`, integers (decimal, `0x`, `0b`), parentheses, unary `-` and the operators `+ - * / % << >> & | ^ ~ ! && || == != < > <= >=`. The conditional operator `? :` is not supported. Do not use character constants that contain a letter, such as `'a'`: the preprocessor reads the letter as an unknown name and turns it into 0, so `'a' == 'b'` is true. Compare with numbers instead (`97`). A name that is not a macro counts as 0. The lines that are not selected are skipped completely: they need not be valid A code.

{{sample lang/pp_conditional}}

What to notice:

- `FEATURE_FAST` is defined without a value, which is enough for `#ifdef`.
- Only one of the `#if` / `#elif` / `#else` branches defined `LABEL`. The branch `VERSION >= 40 && defined(FEATURE_FAST)` was the first true one.
- The block under `#if 0` contains text that is not valid A, and the compiler never sees it. This is also the way to comment out code that contains block comments.
- `UNDEFINED_NAME == 0` is true inside `#if`, because an unknown name counts as 0. The same name in ordinary code is an `undeclared identifier` error.
- `#error text` stops the compilation with that text: put it in a branch that must never be taken, such as a missing `-D` option:

```text
pperror.a:2: error: #error
  #error PLATFORM must be defined with -D
```

## Including files

`#include "file"` inserts the file at that place. The compiler looks next to the including file first, then at the path as given, then in the library directories (a `lib/` directory in the current directory, `/usr/lib/a/`, `/usr/local/lib/a/`, and a `lib/` directory next to the main source file). `#include <file>` is looked up in exactly the same way: the compiler does not tell the two forms apart. Includes may be nested 12 levels deep. The same file can be included many times; guard it so that its content appears only once, either with `#pragma once` at the top, or with the classic `#ifndef` guard.

{{sample lang/pp_include}}

The directory of this sample holds `main.a`, `defs.h` (which starts with `#pragma once`) and `guarded.h` (which uses `#ifndef GUARDED_H`).

What to notice:

- `defs.h` was included twice and `guarded.h` twice, yet `helper` and `guarded` are defined once. Without a guard the second include would be a `redefinition of 'helper'` error.
- Header files are plain text: the `.h` extension is only a convention. Headers hold macros, constants, type definitions and prototypes; the next section uses them to share declarations between compiled units.
- For A code that you want to reuse, modules (see [chapter 16](#chap-enums-and-modules)) are usually the better tool than `#include`.

## Predefined macros and compiler options

These macros always exist:

| Macro | Value |
|---|---|
| `__A__` | 1 |
| `__ARCH__` | 0 x86-64, 1 ARM64, 2 RISC-V 64, 3 LoongArch 64 |
| `__OS__` | 0 Linux, 1 Windows, 2 Android |
| `__FILE__` | the name of the source file, as given to the compiler |
| `__LINE__` | the current line number |

`__ARCH` and `__OS` (without the trailing underscores) are **constants** of the language with the same values: use them with `static if`.

{{sample lang/pp_predefined}}

What to notice:

- The values describe the target the program is being compiled for, not the machine the compiler runs on: `ac -t windows` makes `__OS__` 1.
- `__FILE__` is the path as the compiler was given it (inside an included file it is the path of that file), so the sample only checks the ending. Do not print it into output that must be reproducible.

The options of `ac` that matter here:

| Option | Meaning |
|---|---|
| `-D NAME` / `-D NAME=value` / `-DNAME=value` | defines a macro; may be repeated |
| `-E` | prints the preprocessed source instead of compiling it |
| `-o FILE` | the name of the output file |
| `-t TARGET` | the target: `linux` (default), `windows`, `android`, `linux-arm64`, `linux-riscv64`, `linux-loongarch64`, and others |
| `-c` | compiles to an object file instead of a program (next section) |

This program uses two macros that you can set from outside:

{{sample lang/pp_flags}}

Here is how the compiler is called with and without them, and what `-E` shows. The program is `pp_flags.a`:

```sh
$ ac pp_flags.a -o plain && ./plain
level 1
done
$ ac -D DEBUG pp_flags.a -o debug && ./debug
trace: starting
level 1
done
$ ac -D DEBUG -D LEVEL=3 pp_flags.a -o both && ./both
trace: starting
level 3
done
$ ac -DLEVEL=7 pp_flags.a -o seven && ./seven
level 7
done
$ ac -E -D DEBUG pp_flags.a | grep -v '^$'
int main() {
    println("trace: " "starting");
    printf("level %d\n", 1);
    println("done");
    return 0;
}
```

What to notice:

- With no options, `DEBUG` is undefined: `TRACE` expands to nothing, and `LEVEL` gets its default from the `#ifndef` block.
- `-D DEBUG` defines the macro with the value 1, which `#ifdef` accepts. `-D LEVEL=3` and `-DLEVEL=7` give a value.
- `-E` shows exactly what the compiler would see: blank lines stand for the removed directives, `TRACE` has turned into a `println` call, and `LEVEL` into `1`. This is the quickest way to debug a macro.

## Separate compilation and linking

Besides compiling a whole program from one file, `ac` can compile files **separately** and link them, like a C toolchain. `ac -c shapes.a -o shapes.ao` compiles one **unit** to an object file; `ac main.ao shapes.ao -o prog` links objects into a program. Units share declarations the C way, through a header that both `#include`: function prototypes, `extern` variables, and the definitions of structs, classes and constants.

{{sample lang/link_units}}

The directory of this sample holds three files. `shapes.h` has the shared declarations: a constant, a struct, a class, an `extern` variable and the prototypes of three functions. `shapes.a` holds their definitions. `main.a` is the program. Its first lines contain `// book: link`, a directive for the book's sample checker: the checker builds the sample exactly the way you would by hand, with these commands:

```sh
ac -c main.a -o main.ao
ac -c shapes.a -o shapes.ao
ac main.ao shapes.ao -o prog
./prog
```

The link errors are easy to provoke. These commands use `main.ao` and `shapes.ao` from above; the messages are the real ones:

```sh
$ ac main.ao -o broken
ac: error: undefined reference to 'corner'
$ ac -c main.a -o again.ao && ac main.ao again.ao shapes.ao -o broken
ac: error: duplicate definition of 'main'
$ ac -c shapes.a -o second.ao && ac main.ao shapes.ao second.ao -o broken
ac: error: duplicate definition of 'created'
$ ac -t linux-arm64 -c shapes.a -o shapes-arm.ao && ac main.ao shapes-arm.ao -o mixed
ac: error: the object was made for another target or architecture 'shapes-arm.ao'
```

What to notice:

- Each `ac -c` produced one `.ao` file, and the link step joined the two into one program. The program's output is the recorded output above.
- `Point` and `Counter` are defined in the header, so both units know them. The methods of a class that is defined in a header may be compiled into every unit that includes it; together with `static` functions, it is a definition that may appear in more than one unit.
- `created` is one variable: it is defined in `shapes.a` (`int created = 0;`), declared with `extern` in the header, and `main.a` reads and writes the very same variable. The `100` that `main` stores is what `createdTwice()` in `shapes.a` sees.
- `scale()` is `static`, so only `shapes.a` can call it. Two units may each have their own `static` function of the same name.
- The order of the objects on the command line does not matter, and `main` must be defined in exactly one object.
- A name that nobody defines is `undefined reference to 'corner'`. A name defined in two objects is `duplicate definition of 'main'`; this applies to global variables as well (`created` above). A `static` or `private` name that another unit declares is also an undefined reference, because it is not visible there.
- Every function and global variable that is not `private` or `static` is visible to the other objects; `static` and `private` ones belong to their own object.
- A unit contains the code and data of its own file, and of the files it `#include`s or `import`s from disk. The built-in library (`println`, `collections`, `net`, ...) is not part of an object: the link step compiles the parts the objects use, so there is only one copy, and library state (the heap, `rand`) is shared.
- Because every unit is compiled without seeing the others, an `import` of a user file in two units would make two copies of it. Put shared declarations in a header and the definitions in exactly one unit.
- All objects must be made for the same target (`-t`): an object records its target and architecture, and mixing them is an error (`the object was made for another target or architecture`). An object also records the version of the object file format; a file that this compiler cannot read is rejected with `not a valid object file`.
- Calls between objects go through a relocation (an indirect call), so a call to another object is a little slower than a call inside one unit.

Use separate compilation for big programs that you rebuild often, or when you want to link A units with others built at another time. Use `import` and modules (see [chapter 16](#chap-enums-and-modules)) for everything else.

## Inline assembly

`asm` puts machine code into a function. The program lists the code for **every CPU** it should run on; the compiler uses the section of the CPU it is compiling for (`x64`, `arm64`, `riscv64`, `loongarch64`) and skips the others. In an expression, the operands (at most three) are loaded into the registers A, B and D before the code runs, and the value of the expression is the register A afterwards. As a statement, the `;` after the closing brace is optional.

| | x64 (Linux, Windows, Android) | arm64 | riscv64 | loongarch64 |
|---|---|---|---|---|
| A, B, D | rax, rcx, rdx | x0, x1, x2 | a0, a1, a2 | $a0, $a1, $a2 |
| free to clobber | rsi, rdi, r8-r11 | x3-x5, x9-x17 | t0-t6, a3-a7 | $t0-$t8, $a3-$a7 |
| keep intact | rsp, rbp, rbx, r12-r15 | sp, x29, x30 | sp, s0, ra | $sp, $fp, $ra |

The register table comes from the language reference. Its last two rows are rules for the code you write; the compiler does not check them. The code is given as numbers: bytes on x64, and 32-bit instruction words on the other CPUs. There is no assembler in the compiler: get the numbers from an assembler (`llvm-mc -show-encoding`, `as`) or from a manual.

{{sample lang/asm_add}}

What to notice:

- `a` went into register A and `b` into B; `add rax, rcx` (the bytes `0x48, 0x01, 0xC8`) added them, and the result stayed in A, which is the value of the expression.
- The `asm()` statement with no operands is a no-operation on every CPU. The program continued after it.
- The section names are `x64` (also `x86_64`, `amd64`), `arm64` (`aarch64`), `riscv64` (`rv64`) and `loongarch64` (`la64`). An unknown name is an error (`unknown CPU name in the asm block`).
- The book's checker compiles this sample for all nine targets, but only **runs** it on x86-64: the arm64, riscv64 and loongarch64 words were not executed when the book was checked.
- The code must not change the stack pointer permanently, must keep the registers listed under "keep intact", and must not jump out of the block (jumps inside it are fine; offsets are relative). The standard prelude uses `asm` for fast `strlen`, `memcpy` and `memset` on x86-64, and the `cpu` and `thread` modules are written with it.

A block must have a section for the CPU being compiled, otherwise the compiler stops with `this asm block has no code for the CPU being compiled`. When you only have code for one processor, combine `asm` with `static if` and give the other targets a version written in A:

{{sample lang/asm_cpu_specific}}

What to notice:

- On x86-64 the first definition is compiled (`shl rax, 3`); on every other CPU the `else` branch is, and the `asm` block inside the first branch is never looked at.
- Inline assembly makes a program non-portable and bypasses every check the compiler makes. Reach for it only for operations that A cannot express, such as special instructions; the standard modules `cpu` (timer, memory barriers, atomic operations) and `thread` already wrap many of them, and `bits` offers bit tricks written in plain A.

## Summary

- The preprocessor runs on every file: `#define` for macros (with `#`, `##` and `__VA_ARGS__`), `#include` and `#pragma once`, `#if` family for conditions, `#error`.
- Always parenthesise macro parameters and bodies. Prefer `const` and `static if` where they can do the job.
- `__A__`, `__ARCH__`, `__OS__`, `__FILE__` and `__LINE__` are predefined; `-D NAME=value` defines a macro and `-E` shows the preprocessed text.
- `ac -c x.a -o x.ao` compiles a unit; `ac a.ao b.ao -o prog` links; units share a header with prototypes, `extern` variables and type definitions.
- `static` and `private` keep names inside their own object; undefined and duplicate names are link errors.
- `asm(operands) { x64: ...; arm64: ...; riscv64: ...; loongarch64: ...; }` embeds machine code; give code for every CPU or use `static if`.

## Where next

- [Control flow](#chap-control-flow) describes `static if`, the language-level alternative to `#if`.
- [Enums and modules](#chap-enums-and-modules) covers `import` and modules, the usual way to split a program.
- [The standard prelude](#chap-standard-prelude) lists the built-in runtime functions.
- The [API reference of cpu](#api-cpu) shows what a library built on `asm` looks like.
