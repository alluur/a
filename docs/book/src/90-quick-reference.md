# Quick reference

One page of facts to keep open while you write A. Everything here is explained in the chapters; the full detail is in the [language reference](#chap-language-reference).

## Keywords

| Group | Words |
|---|---|
| Control flow | `if` `else` `switch` `case` `default` `while` `do` `for` `break` `continue` `return` `goto` `defer` |
| Declarations | `const` `static` `extern` `typedef` `struct` `class` `union` `enum` |
| Classes | `public` `private` `protected` `virtual` `super` `this` `new` |
| Modules | `module` `import` `a_module` `a_import` |
| Types | `int` `long` `char` `byte` `bool` `void` `func` `int8` `int16` `int32` `int64` `uint8` `uint16` `uint32` `uint64` `size_t` `uintptr_t` `ssize_t` `intptr_t` `ptrdiff_t` |
| Values | `true` `false` `null` |
| Operators as words | `and` `or` `not` `xor` `sizeof` |
| Low level | `asm` |

## Types

| Type | Size | Notes |
|---|---|---|
| `int` (also `long`) | 8 bytes | signed 64-bit |
| `char` (also `byte`) | 1 byte | unsigned 8-bit; text and raw bytes |
| `bool` | 1 byte | `true` / `false`; stores 0 or 1 |
| `void` | none | no value; `void*` is the generic pointer |
| `T*` | 8 bytes | pointer to `T` |
| `T name[N]` | `N * sizeof(T)` | fixed array, `N` a constant expression |
| `int8` `int16` `int32` `int64` | 1, 2, 4, 8 | signed, exactly that width |
| `uint8` `uint16` `uint32` `uint64` | 1, 2, 4, 8 | unsigned (`uint8` is `char`) |
| `size_t` `uintptr_t` | 8 bytes | `uint64` |
| `ssize_t` `intptr_t` `ptrdiff_t` | 8 bytes | `int64` |
| `enum E` | 8 bytes | like `int`; `enum E : uint8 { ... }` picks the storage type |

## Literals

| Kind | Examples |
|---|---|
| Integers | `42` `1_000_000` `0xFF` `0b1010` (underscores are ignored) |
| Characters | `'a'` `'\n'` `'\0'` `'\x41'` (type `char`) |
| Strings | `"hello\n"` (type `char*`, NUL terminated) |
| Booleans and null | `true` `false` `null` |

Escape sequences: `\n` `\t` `\r` `\0` `\e` (escape, 27) `\\` `\"` `\'` `\xHH`.

## Operators, highest precedence first

| Level | Operators | Notes |
|---|---|---|
| 1 | `a[i]` `a.b` `a->b` `f(x)` `x++` `x--` | `.` and `->` are interchangeable on pointers |
| 2 | `-x` `+x` `!x` `~x` `*p` `&x` `++x` `--x` `(type)x` | right to left |
| 3 | `*` `/` `%` | signed, truncating like C |
| 4 | `+` `-` | pointer plus integer scales by the element size |
| 5 | `<<` `>>` | `>>` is an arithmetic shift |
| 6 | `<` `<=` `>` `>=` `<=>` | result 0 or 1; `a <=> b` is -1, 0 or 1 |
| 7 | `==` `!=` | |
| 8 | `&` | bitwise and |
| 9 | `^` | bitwise xor |
| 10 | <code>&#124;</code> | bitwise or |
| 11 | `&&` | short circuit |
| 12 | <code>&#124;&#124;</code> | short circuit |
| 12a | `^^` `xor` | logical exclusive or, both sides run |
| 13 | `c ? a : b` `a ?? b` | right to left; `a ?? b` is `a` unless it is 0 / `null` |
| 14 | `=` `+=` `-=` `*=` `/=` `%=` `&=` <code>&#124;=</code> `^=` `<<=` `>>=` | right to left |

The words `and`, `or`, `not` and `xor` mean `&&`, <code>&#124;&#124;</code>, `!` and `^^`.

## The compiler on one screen

| Command | Result |
|---|---|
| `ac prog.a` | `prog-1-debug.elf` in the current directory |
| `ac -o prog prog.a` | exactly `prog` |
| `ac -t windows prog.a` | `prog-1-debug.exe` |
| `ac -t linux-arm64 prog.a` | `prog-1-debug.arm64.elf` |
| `ac -v 12 -r release prog.a` | `prog-12-release.elf` |
| `ac -c unit.a` / `ac a.ao b.ao -o prog` | object file / link |
| `ac -D NAME=VALUE prog.a` | define a macro |
| `ac -E prog.a` | show the preprocessed source |
| `ac --version` / `ac -h` | version / help |

Targets: `linux` `linux-arm64` `linux-riscv64` `linux-loongarch64` `windows` `android` `android-x64` `android-riscv64` `android-loongarch64`. Details in [the compiler chapter](#chap-compiler).

## Output you will use every day

| Call | Does |
|---|---|
| `print(s)` `println(s)` | text, without / with a newline |
| `printInt(n)` `printlnInt(n)` | an integer |
| `printf(fmt, ...)` | formatted output, up to eight values; `%d %s %c %x %u` |
| `exit(code)` | leave the program |

More in [Your first programs](#chap-first-programs) and [the standard prelude](#chap-standard-prelude).
