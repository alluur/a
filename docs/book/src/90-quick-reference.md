# Quick reference

One page of facts to keep open while you write A. Everything here is explained in the chapters; the full detail is in the [language reference](#chap-language-reference).

## Keywords

| Group | Words |
|---|---|
| Control flow | `if` `else` `switch` `case` `default` `while` `do` `for` `foreach` `in` `rev` `break` `continue` `return` `goto` `defer` |
| Declarations | `const` `static` `static_assert` `extern` `typedef` `struct` `class` `union` `enum` |
| Classes | `public` `private` `protected` `virtual` `abstract` `override` `final` `super` `this` `new` `is` `as` |
| Modules | `module` `import` `a_module` `a_import` |
| Types | `int` `long` `char` `byte` `bool` `double` `float` `void` `func` `int8` `int16` `int32` `int64` `uint8` `uint16` `uint32` `uint64` `size_t` `uintptr_t` `ssize_t` `intptr_t` `ptrdiff_t` |
| Values | `true` `false` `null` |
| Operators as words | `and` `or` `not` `xor` `sizeof` |
| Low level | `asm` |
| Newer syntax | `var` (a word only where a declaration starts) `=>` (lambda) `$"..."` (interpolated string) `(T1, T2)` (tuple) `_` (skip a tuple element) |

Of the newer words only `foreach` is reserved. `var`, `in`, `rev`, `abstract`, `override`, `final`, `is`, `as` and `static_assert` mean something only in the place where they are used, and can still be names; `rev` stops working in `foreach (x in rev a)` while a variable, field or function called `rev` is visible (see [More language features](#chap-more-language-features)).

## Types

| Type | Size | Notes |
|---|---|---|
| `int` (also `long`) | 8 bytes | signed 64-bit |
| `char` (also `byte`) | 1 byte | unsigned 8-bit; text and raw bytes |
| `bool` | 1 byte | `true` / `false`; stores 0 or 1 |
| `double` (also `float`) | 8 bytes | IEEE 754 binary64, arithmetic in software; `1.5`, `2e-3` literals |
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
| Characters | `'a'` `'\n'` `'\0'` `'\x41'` (the type is `int`: `sizeof('a')` is 8) |
| Strings | `"hello\n"` (type `char*`, NUL terminated) |
| Booleans and null | `true` `false` `null` |

Escape sequences: `\n` `\t` `\r` `\0` `\e` (escape, 27) `\\` `\"` `\'` `\xHH`.

## Operators, highest precedence first

| Level | Operators | Notes |
|---|---|---|
| 1 | `a[i]` `a.b` `a->b` `f(x)` `x++` `x--` `x is C` `x as C` | `.` and `->` are interchangeable on pointers; `is` / `as` ask for the class of an object |
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
| 14a | <code>&#124;&#124;=</code> `&&=` `??=` | assign only when the target is 0 / `null` (`||=`, `??=`) or true (`&&=`); the right side runs only then |

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
| `printf(fmt, ...)` | formatted output, any number of values; `%d %s %c %x %u %b %f %e %g %v` |
| `$"x = {x}"` | a text with values in it: `{x:5}`, `{pi:.2f}` (see below) |
| `exit(code)` | leave the program |

More in [Your first programs](#chap-first-programs) and [the standard prelude](#chap-standard-prelude).

## Inference, tuples, lambdas and interpolation on one screen

| You write | Meaning |
|---|---|
| `var n = 5;` `var (a, b) = f();` | a local whose type is the type of the initializer; needs an initializer; locals only |
| `(int, double) f() { return (1, 2); }` | a function that returns a tuple (2 to 16 elements, passed by value) |
| `(int q, int r) = divmod(7, 2);` `(a, b) = (b, a);` | declare from a tuple, assign to variables that exist (a swap); `_` skips an element |
| `t.0` `t.1` | the elements of a tuple; `==` on tuples compares addresses, not elements |
| `x => x + 1` `(a, b) => a * b` `(int x) -> double => x * 0.5` | a lambda: a `func` value with no captures; the result is an `int` unless `->` says otherwise |
| `(int x) => { return x; }` | a lambda with a block body |
| `$"{x}"` `{x:5}` `{x:-5}` `{x:05}` `{x:#x}` `{pi:.2f}` | the text of a conversion without the `%`; flags, width, `.precision`, length, letter, in this order |
| `{{` `}}` | a brace in an interpolated string |

| Conversion | Prints |
|---|---|
| `%f` `%F` | a double with a decimal point (6 digits after it by default) |
| `%e` `%E` | scientific notation |
| `%g` `%G` | the shorter of the two, without trailing zeros |
| `%v` | the shortest text that reads back as the same double (`0.1`, `1e+22`) |

A `double` passes through `printf` as its 64 bits: `%f` is right, `%d` shows the bits (write `(int) d`), and `%f` with an `int` is wrong (write `(double) n`). More in [Type inference, tuples, lambdas and string interpolation](#chap-inference-tuples-lambdas-interpolation).
