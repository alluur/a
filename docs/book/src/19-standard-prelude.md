# The standard prelude

Every A program starts with a library already in it. The **standard prelude**, the file `lib/std.a`, is compiled into every program automatically, with no `import`. It has the functions you met in [First programs](#chap-first-programs) (`println`, `printf`, `readLine`) and many more for strings, numbers, files, the environment and time. Underneath it sits a handful of **built-in runtime functions** that the compiler itself provides. This chapter tours both, shows what the compiler says when something is wrong, and ends with a table of the differences from C.

In this chapter:

- the prelude as a tour: strings, characters, numbers, random numbers, the environment, time and the terminal
- two worked examples: copying a file in pieces and a small text statistics tool
- the built-in runtime functions (`__write`, `__open`, `__syscall`, ...)
- typical compile errors and how to read them
- the differences between A and C

## What the prelude contains

All of these are ordinary A functions. You can read them in `lib/std.a`. Because they are always there, **their names are taken**: defining a function called `max`, `min`, `find`, `contains`, `trim` or `strlen` at the top level is the error `redefinition of 'max'`. Local variables, methods of classes and functions inside modules may use the same names.

| Group | Functions |
|---|---|
| Output | `print` `println` `printInt` `printlnInt` `printChar` `printBool` `printHex` `printRepeat` `eprint` `eprintln` `printf` `format` `vformat` |
| Input | `readChar` `readLine` `readAll` `input` `askInt` `confirm` `parseInt` `atoi` |
| Strings | `strlen` `streq` `streqi` `strcmp` `strcpy` `strcat` `strdup` `indexOf` `startsWith` `endsWith` `find` `contains` `substr` `trim` `strUpper` `strLower` |
| Memory | `memcpy` `memset` `alloc` |
| Characters | `isDigit` `isAlpha` `isUpper` `isLower` `isSpace` `toUpper` `toLower` |
| Numbers | `abs` `min` `max` `srand` `rand` `intToStr` `hexToStr` |
| Files | `fileOpen` `fileRead` `fileWrite` `fileClose` `readFile` `writeFile` `fileExists` `fileDelete` `makeDir` and the constants `FILE_READ` `FILE_WRITE` `FILE_APPEND` |
| Command line and environment | `argIndex` `hasArg` `argValue` `getEnv` |
| Time | `millis` `sleepMs` |
| Terminal | `printColor` `isTerminal` `clearScreen` `cursorTo` `ansiInit` and the constants `ANSI_RED` `ANSI_GREEN` `ANSI_YELLOW` `ANSI_BLUE` `ANSI_MAGENTA` `ANSI_CYAN` `ANSI_GRAY` `ANSI_BOLD` `ANSI_RESET` |
| Process | `exit` |

Names that start with `__` (`__heap`, `__write`, `__enum_name` ...) belong to the runtime and the compiler: do not use them for your own things, and do not rely on the ones that are not documented.

The output, input, file and formatting functions were introduced in [chapter 10](#chap-first-programs). Here are the rest.

## Strings

A string in A is a `char*` that points to bytes ending with a zero byte. There is no built-in string type that knows its length or copies itself: you pass pointers around, and the string functions work on them. (The `strings` module adds a `StringBuilder` for building text piece by piece.)

| Function | Result |
|---|---|
| `strlen(s)` | the number of characters before the zero byte |
| `streq(a, b)` / `streqi(a, b)` | `true` if the strings are equal / equal ignoring case |
| `strcmp(a, b)` | negative, zero or positive: the difference of the first bytes that differ |
| `strcpy(dst, src)` | copies `src` including the zero byte into `dst`, returns `dst` |
| `strcat(dst, src)` | appends `src` to the end of `dst`, returns `dst` |
| `strdup(s)` | a copy of `s` on the heap |
| `memcpy(dst, src, n)` / `memset(dst, value, n)` | copy / fill `n` bytes (they return nothing) |

{{sample std/string_basics}}

What to notice:

- `strcpy` and `strcat` do **not** check the size of the destination. `buf` held 32 bytes and the text needed 13 (12 characters and the zero byte): you must make sure the buffer is big enough, or use `format` with a size.
- Never compare strings with `==`: that compares the pointers. Use `streq`, or `strcmp` when you need the order.
- `strdup` made a copy, so changing `copy[0]` left `buf` alone. The copy lives on the heap and is never freed.
- `memset` and `memcpy` work on bytes, and `memcpy` returns nothing: it does not return `dst` as in C.

### Searching and cutting

| Function | Result |
|---|---|
| `indexOf(s, c)` | the index of the first character `c`, or -1 |
| `find(s, sub)` | the index of the first occurrence of `sub`, or -1 |
| `contains(s, sub)` | `true` if `sub` occurs in `s` |
| `startsWith(s, prefix)` / `endsWith(s, suffix)` | `true` if `s` begins / ends with the text |
| `substr(s, start, len)` | a new heap string of `len` characters starting at `start` |
| `trim(s)` | cuts white space at both ends **in place** and returns the new start |

{{sample std/string_search}}

What to notice:

- All the positions are zero-based indices, with -1 for "not found".
- `substr` copies; the original is untouched. It does not check that `start` and `len` are inside the string.
- `trim` writes a zero byte over the trailing white space of the string you pass in and returns a pointer to its first non-space character. So the string must be writable (an array is), and you keep using the **returned** pointer (`clean`), because leading white space is skipped by moving the start, not by moving the text.

### Characters and case

The character tests take any `int` and work on ASCII only: `isDigit`, `isAlpha`, `isUpper`, `isLower` and `isSpace` (space, tab, newline, carriage return). `toUpper(c)` and `toLower(c)` convert one character; `strUpper(s)` and `strLower(s)` convert a whole string in place. For Unicode text see the `utf8` module.

{{sample std/char_classes}}

What to notice:

- `isSpace` and the others return `bool`, so they can be used directly in conditions and counted.
- `strUpper` changed `word` in place. It works on arrays and on string literals, because literals are writable data. Copy with `strdup` first when you must keep the original.

## Numbers

### Converting between numbers and text

`intToStr(n, buf)` writes the decimal form of `n` into `buf` (at least 21 bytes, for the largest 64-bit number with a sign) and returns `buf`. `hexToStr(n, buf)` writes the lowercase hexadecimal form (the buffer needs at least 17 bytes; a negative number gives its 16 digits of two's complement) and returns nothing. Going the other way, `atoi(s)` is lenient: it reads an optional minus sign and then digits, and stops at the first other character, so it returns 0 for text that is not a number. A leading space or `+` also gives 0. `parseInt(s, &value)` is strict: it accepts white space around a number and an optional `+` or `-`, stores the value and returns `true`, or returns `false` for anything else and leaves `value` alone.

{{sample std/number_text}}

What to notice:

- `atoi("12abc")` is 12 and `atoi("abc")` is 0: you cannot tell bad input from a real 0. Use `parseInt` when the input comes from a user or a file.
- `parseInt` accepted `"  -8  "` and `"+5"` but rejected `"12abc"` and the empty string; the variable `value` kept its `-999` for those.
- For numbers with a decimal point see `parseDouble` in [chapter 11](#chap-types-and-values).

### abs, min and max

`abs(x)`, `min(a, b)` and `max(a, b)` work on `int`. Combine them to clamp a value into a range: `min(max(x, lo), hi)`.

{{sample std/min_max_abs}}

What to notice:

- The functions take exactly two numbers (`min`, `max`); for a list of values keep a running result in a loop, as the last block does. The `math` module has `minOf` and `maxOf` for arrays and `clamp` for ranges.
- The sample does not show it, but `abs` of the smallest 64-bit number (-9223372036854775808) stays negative, because its positive twin does not exist in 64 bits.

### Random numbers

`rand()` returns a pseudo random number between 0 and 2<sup>31</sup> - 1 (an xorshift generator), and `srand(seed)` sets the starting point. The sequence depends only on the seed, and it is the same on every system and processor.

{{sample std/random_numbers}}

What to notice:

- Seeding with 2024 twice produced the same three numbers: that is what makes tests and simulations reproducible.
- Without `srand`, the generator starts from a fixed seed, so a program prints the **same** "random" numbers on every run. For different numbers each time use `srand(millis())` once at the start. The `random` module has a class with its own seed for several independent streams.
- `rand() % 6` maps to 0 to 5: the dice example adds up to exactly 600 rolls. The result is close to uniform but not exact.

## The environment and time

`getEnv(argc, argv, "NAME")` returns the value of an environment variable as a new heap string, or `null` if it is not set. It needs `argc` and `argv` from `main`, because on Linux and Android the environment follows `argv` in memory. `fileExists`, `fileDelete` and `makeDir` handle the file system (see [chapter 10](#chap-first-programs)).

{{sample std/env_vars}}

What to notice:

- The sample is run with a tiny environment in which `TERM` is `dumb` and `LANG` is `C`; on your machine the values will be your own.
- `getEnv(...) ?? "unset"` gives a default for a missing variable. The `??` operator (see [chapter 12](#chap-variables-and-operators)) takes the right side when the left side is `null` (or 0).

`millis()` returns a monotonic millisecond counter that starts at an arbitrary moment, so only **differences** are meaningful. `sleepMs(ms)` waits.

{{sample std/time_sleep}}

What to notice:

- The program printed only comparisons, because the actual times vary: it slept at least 120 ms, and well under a second.
- `millis()` is for measuring and timeouts. For dates and clocks use the `datetime` module, or `time` and `strftime` in the C library.

## The terminal

`printColor(color, text)` prints text in one of the `ANSI_...` colours **when standard output is a terminal**, and plain text otherwise, so the same program can write to the screen and to a log file. `isTerminal(fd)` tells whether file descriptor 0, 1 or 2 is a terminal. `clearScreen()` and `cursorTo(row, col)` (rows and columns start at 1) write ANSI escape codes; `ansiInit()` turns on escape codes in the Windows console and is called by these functions for you. For full screen interfaces use the `term`, `tscreen` and `tui` modules.

{{sample std/terminal_colors}}

What to notice:

- Output went to a file here, so `printColor` printed `ok`, `failed` and `bold` as plain text and `isTerminal(1)` was 0.
- The `ANSI_` constants are ordinary strings (`ANSI_RED` is five bytes: ESC, `[`, `3`, `1`, `m`). You can combine them yourself when the output is a terminal.

## Files in pieces

[Chapter 10](#chap-first-programs) showed `readFile`, `writeFile` and the handle functions one at a time. Here they work together in a function that copies a file:

{{sample std/file_copy}}

What to notice:

- Two handles are open at the same time, and each error path closes what was opened.
- `fileRead` returned fewer bytes than asked at the end of the file (96 bytes as 64 plus 32), then 0.
- The function returns the number of bytes copied, or -1 on error. A count is never negative, so -1 can safely mean "failed"; the caller does not learn which step failed.

## A small tool

The functions above are enough for real tools. This program reads standard input and reports lines, words, characters, how many words are numbers and their sum, and the longest word. Its input is:

```text
The year 2024 had 366 days
and  we wrote 12 chapters
   
about programming-languages
```

{{sample std/text_stats}}

What to notice:

- `readLine` reads the lines, `trim` and `isSpace` split them into words, `substr` copies each word, and `parseInt` decides whether the word is a number: `2024`, `366` and `12` are, so the sum is 2402.
- `programming-languages` (21 characters) is the longest word; the program keeps a pointer to it and replaces it whenever a longer one turns up.
- The words made with `substr` stay on the heap: fine for a tool that ends soon, but for a very long input use a buffer that you reuse.

## Built-in runtime functions

These functions are provided by the compiler for the target platform. The standard prelude is built on them. They are plain functions with a leading `__`.

| Function | Description |
|---|---|
| `__write(fd, buf, n)` | writes `n` bytes to a file descriptor (1 is standard output, 2 standard error; other values are handles from `__open`) and returns the number written |
| `__read(fd, buf, n)` | reads up to `n` bytes (fd 0 is standard input) and returns the count, 0 at the end |
| `__open(path, mode)` / `__close(h)` | opens a file (`mode` is 0 read, 1 write, 2 append) / closes it |
| `__exit(code)` | ends the process at once |
| `__syscall(nr, a1, ..., a6)` | a raw system call (Linux and Android only; the numbers differ between x86-64 and ARM64) |
| `__winapi(slot, a1, a2, a3, a4)` | calls an imported Windows function by import table slot (returns -1 elsewhere) |
| `__winapix(slot, a1, ..., a10)` | the same with up to ten arguments |
| `__OS`, `__ARCH` | constants: OS 0 Linux, 1 Windows, 2 Android; architecture 0 x86-64, 1 ARM64, 2 RISC-V 64, 3 LoongArch 64 |
| `__cmdline()` | the Windows command line (used to build `argv`); `null` elsewhere |
| `__bits(d)` / `__dbl(i)` | the raw 64 bits of a `double` and back |
| `setjmp(buf)` / `longjmp(buf, v)` | non-local jumps, see [chapter 17](#chap-memory-and-pointers) |
| `va_arg(i)` / `va_count()` | extra arguments of a `...` function, see [chapter 14](#chap-functions) |

{{sample std/runtime_builtins}}

What to notice:

- `__write(1, msg, n)` is what `print` does: no buffering and no newline added.
- `__open`, `__read`, `__write` and `__close` handle files without the prelude's wrappers. `fileOpen(path, mode)` calls `__open(path, mode)` directly.
- `__exit(5)` ended the process with exit code 5 immediately. Unlike `exit`, it does not run `atexit` functions and does not write out buffered file output, so use `exit` in normal programs.
- On this system `__OS` and `__ARCH` are 0 and 0, and `__cmdline()` is `null`.

A raw system call goes straight to the kernel. The system call numbers belong to the platform, not to A, so the code chooses them with `static if`:

{{sample std/syscall_write}}

What to notice:

- `write` is number 1 on x86-64 and 64 on ARM64, RISC-V and LoongArch. `__syscall` is for Linux and Android only; on Windows you would call imported functions with `__winapi`.
- The six arguments after the number are always given; unused ones are 0. The call returned 29, the number of bytes written.
- Prefer the prelude and the library modules (`asys`, the C library) for anything portable. `__syscall` is for the code that builds those libraries.

## Compile errors

The compiler stops at the **first** error and prints the file and line, a message, the source line with a caret under the position, and exits with code 1 (0 means success). The caret marks the token the compiler was looking at when it noticed the problem, which is sometimes just after the real mistake.

A **missing semicolon** is reported at the start of the next line, because only there can the compiler see that the statement did not end:

```sh
$ cat syntax.a
int main() {
    int x = 5
    return x;
}
$ ac syntax.a -o x
syntax.a:3: error: expected ';'
      return x;
      ^
```

An **unknown name**, usually a typo:

```sh
$ cat undeclared.a
int main() {
    int total = 10;
    printlnInt(totl);
    return 0;
}
$ ac undeclared.a -o x
undeclared.a:3: error: undeclared identifier 'totl'
      printlnInt(totl);
                 ^
```

A **wrong number of arguments**:

```sh
$ cat arguments.a
int add(int a, int b) {
    return a + b;
}

int main() {
    printlnInt(add(1));
    return 0;
}
$ ac arguments.a -o x
arguments.a:6: error: wrong number of arguments in call
      printlnInt(add(1));
                       ^
```

A **private member** used from outside its class:

```sh
$ cat private.a
class Account {
    private int balance;
    public Account(int opening) { balance = opening; }
}

int main() {
    Account a(100);
    printlnInt(a.balance);
    return 0;
}
$ ac private.a -o x
private.a:8: error: member is private to its class 'balance'
      printlnInt(a.balance);
                   ^
```

Other messages you will meet:

| Message | Usually means |
|---|---|
| `left side of assignment is not assignable` | assigning to a constant, a literal or a call |
| `cannot take the address of a value` | `&` applied to a constant or an expression |
| `redefinition of 'max'` | a second function with that name, or a name that the prelude already defines |
| `name is not a constant` | a variable where a constant is required: array size, `case` label, default value, global initializer |
| `too many values in the initializer list` | more values than array elements or fields |
| `the string is longer than the array` | a `char` array initialised with a longer string |
| `unterminated string literal` | a missing closing `"` |
| `unexpected end of file, missing '}'` | unbalanced braces |
| `unknown type 'B'` | a misspelt type, or a class used before it is defined, in a parameter list or a field (in a function body the same mistake is reported as `undeclared identifier 'B'`) |
| `no such member 'z'` | a field or enum member that does not exist |
| `member access on a value that is not a struct, class or pointer to one` | `x.y` where `x` is an `int` or a `char*` |
| `access to private declaration 'secret'` | a `private` function or constant of a module used from another file |
| `cannot find the imported file 'x.a'` | an `import` that no search directory can satisfy |
| `undefined reference to 'f'` / `duplicate definition of 'f'` | link errors from `ac a.ao b.ao` |
| `#error ...` | a deliberate stop from the preprocessor |

::: tip

Fix errors from the top: the compiler reports only one, and the first mistake can make the following lines look wrong. If a message points at a line that looks fine, check the line above it for a missing `;`, `)` or `}`.

:::

## Differences from C

A looks like C, and most C knowledge carries over. This table lists what is different, so that nothing surprises you.

| | C | A |
|---|---|---|
| `int` | 32 bits | 64 bits (`long` is the same type); `short`, `long`, `signed`, `unsigned` are accepted and mean plain `int` |
| `char` | signed or unsigned | always unsigned |
| other widths | `int32_t`, `uint8_t` ... | `int8` ... `int64`, `uint8` ... `uint64`; `size_t` family exists |
| unsigned arithmetic | all unsigned types | only the unsigned fixed width types (`uint8` ... `uint64`) |
| overflow of `int` | undefined | wraps modulo 2<sup>64</sup> |
| variables | uninitialised | always zeroed (locals, arrays, structs, heap) |
| booleans | `_Bool` / `stdbool.h` | `bool`, `true`, `false` are built in; `null` instead of `NULL` |
| declaration order | prototypes needed | functions may be used before their definition |
| constants | `#define` or `const` | `const NAME = value;` is a compile-time constant |
| arrays | variable length arrays, multi-dimensional | constant sizes only, one dimension |
| bit-fields | yes | none |
| strings | read-only literals | string literals are writable |
| classes | none | `class`, methods, constructors, `public` / `private` / `protected`, inheritance, `virtual`, operator overloading |
| constructors | none | run for `Class c(args);` and `new`, **not** for `Class c;` |
| memory | `malloc` / `free` | `new` and `alloc` never free; `malloc` / `free` from `cstdlib`; `memcpy` returns nothing |
| modules | headers only | `module` / `import`, `a_module` / `a_import`, and `#include` |
| function pointers | typed | type `func`, signature not checked |
| struct values | by value | by value too (a hidden copy); `==` does not compare the fields |
| default arguments | none | `int f(int a, int b = 1)` |
| variable arguments | `va_list` | `...`, `va_arg(i)`, `va_count()` |
| `printf` | any number of arguments, `%f` | up to 8 values, `%b` for binary, no `%f` (it is printed as the two characters `%f`; see `printfd`) |
| floating point | `float`, `double` in hardware | `double` (and `float` as an alias) in software, same result everywhere |
| `switch` | constant labels | constant labels that fit in 32 bits |
| extras | | `defer`, `static if`, `??`, `<=>`, `xor` / `^^`, `and` / `or` / `not`, designated initializers, compound literals |
| preprocessor | yes | yes, a C-style one, plus `static if` and `const` for most uses |
| separate compilation | object files and a linker | `ac -c` and linking of `.ao` files |

## Summary

- The standard prelude is compiled into every program: no `import`, but its names cannot be redefined at the top level.
- Strings are `char*` ended by a zero byte; `strcpy` and `strcat` do not check sizes; compare with `streq`, never with `==`.
- `atoi` is lenient and `parseInt` strict; `rand` is deterministic for a given seed and starts from a fixed seed.
- `getEnv(argc, argv, name)`, `millis()`, `sleepMs(ms)` and `printColor` cover the environment, time and the terminal.
- The built-in `__write`, `__read`, `__open`, `__close`, `__exit` and `__syscall` are what the prelude is made of; use them rarely.
- The compiler reports the first error with file, line, message and a caret; most messages are short and point to the cause.
- A differs from C mainly in its 64-bit `int`, zeroed variables, classes and modules, `new` without `free`, and the extra statements `defer` and `static if`.

## Where next

- [First programs](#chap-first-programs) covers the output, input and file functions in detail.
- [Types and values](#chap-types-and-values) and [Memory and pointers](#chap-memory-and-pointers) explain the types behind these functions.
- [Text and strings](#chap-text-and-strings), [collections and algorithms](#chap-collections-and-algorithms) and [numbers](#chap-numbers) continue with the library modules.
- The API reference of the library modules starts with [strings](#api-strings), [collections](#api-collections) and [math](#api-math).
