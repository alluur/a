# First programs

A program is useful when it can talk to the world around it: show results, read what the user types, look at its command line, report success or failure, and work with files. This chapter shows how to do all of that with the functions every A program has built in. You do not need an `import` for any of them: they come from the standard prelude, which [chapter 19](#chap-standard-prelude) describes in full.

In this chapter:

- the shape of a program: `main`, functions, comments
- printing with `print`, `printf` and `format`
- reading standard input
- command line arguments and exit codes
- reading and writing files

## The shape of a program

An A program is one or more source files with the extension `.a`. Execution starts in the function `main`. Around it you put constants, global variables, types and other functions.

{{sample lang/structure}}

What to notice:

- `main` returns an `int`. That number is the **exit code** of the process; `0` means success. `main` may also be written `int main(int argc)` or `int main(int argc, char** argv)` to receive the command line (see below).
- `compute()` is called before the line where it is defined. Functions may appear in any order, and you never need to write a prototype.
- A comment is either `// to the end of the line` or `/* a block */`. Block comments do not nest.
- Statements end with `;`. Whitespace is not significant.
- Declare types, constants and enums before the declarations that use them: a function signature, a field, an array size or another constant. A function body may refer to a type or constant that comes later, but putting them first always works. A class that extends another one must come after its base class.

::: note

If the compiler rejects your program, its message names the file, the line and the problem. [Chapter 19](#chap-standard-prelude) lists the typical messages.

:::

## Printing text and numbers

The simplest output functions each write one thing to **standard output**, the stream that normally ends up on the screen.

| Function | Writes |
|---|---|
| `print(s)` / `println(s)` | a string (and a newline) |
| `printInt(n)` / `printlnInt(n)` | a number in decimal |
| `printChar(c)` | one character |
| `printBool(b)` | `true` or `false` |
| `printHex(n)` | a number in lowercase hexadecimal, without a prefix |
| `printRepeat(c, n)` | the character `c`, `n` times |
| `eprint(s)` / `eprintln(s)` | a string to **standard error** |

{{sample lang/print_basics}}

What to notice:

- `println` adds the newline; `print` does not. `printChar(10)` writes the newline character itself.
- The last line of the program went to standard error, so it is not in the output block. Use `eprintln` for diagnostics: they stay visible when the normal output is redirected into a file.
- Output is not buffered: every call writes straight to the operating system. That is simple and predictable; for very large outputs build the text in a buffer first (see `format` below).
- `printHex(-1)` prints all 64 bits (`ffffffffffffffff`): every integer in A is 64 bits wide.

## Formatted output with printf

`printf(format, a, b, ...)` prints a template in which `%` conversions are replaced by the values that follow. It takes **up to eight values**; a ninth one is a compile error (`wrong number of arguments in call`). Text and pointers are passed as they are, and every value is a 64-bit number.

| Conversion | Meaning |
|---|---|
| `%d` `%i` | signed decimal |
| `%u` | unsigned decimal (all 64 bits) |
| `%x` `%X` | hexadecimal, lower or upper case |
| `%o` `%b` | octal, binary |
| `%c` | one character |
| `%s` | a string (`(null)` for a null pointer) |
| `%p` | a pointer, as `0x...` (`(nil)` for null) |
| `%%` | a percent sign |

Between `%` and the letter you can put flags `-` (left align), `0` (pad with zeros), `+` (always a sign), a space (a space for positive numbers) and `#` (a `0x`, `0` or `0b` prefix), then a minimum width, then `.precision` (at least that many digits for numbers, at most that many characters for `%s`). A `*` takes the width or precision from the next value. The C length modifiers `h hh l ll z j t` are accepted: `h` and `hh` cut the value to 16 or 8 bits, the others change nothing.

{{sample lang/printf_formats}}

What to notice:

- `[%05d]` pads with zeros, `[%-5d]` pads on the right, and `%+d` forces a sign.
- `%.3s` cuts a string to three characters, `%*d` takes its width from the argument list.
- `%u` shows the 64 bits of `-1` as an unsigned number. Use `%d` for ordinary numbers.
- `printf` does not format numbers with a decimal point. For `double` values see the end of [chapter 11](#chap-types-and-values).

## Formatting into a buffer

`format(buffer, size, template, ...)` works like `printf` but stores the text in a `char` array instead of printing it. You can then print it, compare it, send it over a network or write it to a file. It returns the number of characters it stored. `vformat(buffer, size, template, values, count)` takes the values as an array and returns the length the **complete** text would need, as C's `snprintf` does, so you can detect that a buffer was too small.

{{sample lang/format_buffer}}

What to notice:

- At most `size - 1` characters are stored and the text is always terminated with a zero byte, so a buffer that is too small gives a cut text, never an overflow.
- `format` returned 7 for the cut text (what it stored); `vformat` returned 15, the length of `12345 and 67890`.
- The `char` array `buf` is passed as it is: an array turns into a pointer when you pass it to a function (see [chapter 17](#chap-memory-and-pointers)).

## Tables and aligned columns

Width and precision make columns line up. `printRepeat` draws the rules.

{{sample lang/number_table}}

What to notice:

- `%-4s` and `%8s` align the header over the numbers: `%s` follows the same width rules as `%d`.
- Hexadecimal and binary use the same width mechanism: `%9x` and `%10b`.

## Reading standard input

Standard input is whatever the user types, or a file or another program's output when the shell redirects it. It is **buffered**: the prelude reads it in blocks of 4096 bytes. The input functions are:

| Function | Result |
|---|---|
| `readLine(buf, max)` | reads one line into `buf` without its line break (`\n` or `\r\n`; carriage returns are dropped), returns its length, `-1` at the end of the input |
| `readChar()` | the next byte, `-1` at the end of the input |
| `readAll()` | the rest of the input as one heap string |
| `input(prompt)` | prints the prompt, returns the line as a new string, `null` at the end |
| `askInt(prompt)` | asks until the line is a whole number |
| `confirm(prompt)` | asks a yes or no question: `y` or `Y` is yes |

In the samples of this book the input comes from a file, written below each program. In a terminal you type the lines yourself and finish with Ctrl-D (on Linux and Android).

Here is the input of the first example:

```text
first line
second line

last line without newline
```

{{sample lang/read_lines}}

What to notice:

- An empty line is a line: `readLine` returned `0` for it, and the loop went on. Only `-1` means the input is over.
- The last line had no newline at the end and was still delivered.
- `readLine` stores at most `max - 1` characters. A longer line is returned in pieces: a 10 character line read with a 6 byte buffer comes back as `abcde`, `fghij` and then an empty line for the newline that is left.

`readChar` and `readAll` give you more control. This program counts the words before the first full stop and then takes everything that is left:

```text
one two  three
four. And then
some more
```

{{sample lang/read_chars}}

What to notice:

- `isSpace` is one of the prelude's character tests. `trim` cuts white space at both ends of a string in place and returns the new start. Both are covered in [chapter 19](#chap-standard-prelude).
- `readAll()` takes the rest of the input, newline included, and returns it as a string that lives on the heap until the program ends.

The prompt functions are the shortest way to write an interactive program:

```text
Ada
forty
36
y
```

{{sample lang/prompts}}

What to notice:

- `askInt` rejected `forty` with a message and asked again; it returned 36 for the second answer. At the end of the input it would return 0.
- Because the answers come from a file here, they are not echoed, so `Your name: ` and `Your age: ` run together on one line. In a terminal each answer appears after its prompt.
- `input` returns a heap string (or `null` when the input has ended), so check for `null` when the program may be run without a terminal. It reads at most 1023 characters of a line; `confirm` returns `false` at the end of the input.

## Command line arguments

Declare `main` with two parameters to receive the arguments: `argc` is the count and `argv` is an array of strings. `argv[0]` is the name the program was started with; the arguments follow from index 1. Three helpers search the list: `hasArg(argc, argv, "-v")`, `argIndex(argc, argv, "-o")` (the index, or `-1`) and `argValue(argc, argv, "-o", fallback)` (the argument after the flag, or the fallback).

The program below was started as `./args alpha -v -o out.txt beta`:

{{sample lang/args}}

What to notice:

- `argc` counts the program name, so five arguments give `argc = 6`.
- `argValue` found `out.txt` after `-o` and used the fallback for the missing `-i`.
- The helpers look at the strings only; options and positional arguments are not distinguished. For a full option parser see the `cli` module in the [API reference](#api-cli).

## Exit codes

The number that `main` returns, or that you pass to `exit(code)`, is the exit code of the process. `0` means success; anything else tells the shell or the calling program that something went wrong. `exit` can be called from any function and ends the program at once. First it runs the functions registered with `atexit` (a function of the `cstdlib` module) and writes out data that is still waiting in buffered `cstdio` streams.

{{sample lang/exit_code}}

What to notice:

- The program printed the first message, then `fail` called `exit(3)`: `all fine` and `never printed` were never reached. In a shell, `echo $?` shows `3`.
- The message with the reason went to standard error with `eprintln`.
- The operating system keeps only the low 8 bits: `return 300` ends with exit code 44 and `return -1` with 255.
- A program that crashes has no exit code of its own: on Linux the shell reports 136 after an integer division by zero (the processor raises a fault) and 139 after a stack overflow or a bad pointer.

## Working with files

There are two levels of file functions. The simple ones work on whole files; the handle-based ones read and write in pieces. They are part of the prelude on every target, and a relative path is relative to the current directory.

| Function | Description |
|---|---|
| `writeFile(path, text)` | creates or overwrites a file, returns `true` on success |
| `readFile(path)` | the whole file as a string, `null` when it cannot be opened |
| `fileExists(path)` | `true` if the file can be opened for reading |
| `fileDelete(path)` | removes a file, returns `true` on success |
| `makeDir(path)` | creates a directory, returns `true` on success |
| `fileOpen(path, mode)` | a handle (an `int`), negative on failure; mode `FILE_READ`, `FILE_WRITE` (create or truncate) or `FILE_APPEND` |
| `fileRead(h, buf, n)` | reads up to `n` bytes, returns the count, `0` at the end of the file |
| `fileWrite(h, buf, n)` | writes `n` bytes, returns the count |
| `fileClose(h)` | closes the handle |

The samples run in a scratch directory, so they create their files there and delete them when they are done.

{{sample lang/files_whole}}

What to notice:

- `readFile` returns a zero-terminated string, so `strlen` works on it. The 17 bytes are `alpha\nbeta\ngamma\n`.
- A missing file gives `null`, not a crash: check for it.
- The memory that `readFile` returns lives on the heap until the program ends (see [chapter 17](#chap-memory-and-pointers)). A file that contains zero bytes is cut at the first one when you treat it as a string; use the handle functions for binary data.

When you want to process a file in pieces, or add to it, use handles:

{{sample lang/files_handles}}

What to notice:

- `FILE_WRITE` created the file, `FILE_APPEND` added to it, `FILE_READ` read it back.
- The loop asks for 5 bytes at a time: `5 + 5 + 3` is the 13 bytes of `first\nsecond\n`. `fileRead` returns `0` when nothing is left.
- Always close a handle. A `defer fileClose(h);` right after the `fileOpen` does it on every path out of the function (see [chapter 13](#chap-control-flow)).

Directories and existence checks:

{{sample lang/files_dirs}}

What to notice:

- `makeDir` returns `false` when the directory exists already.
- `fileDelete` also returns `false` when there is nothing to delete, so you can tell the two cases apart.
- Listing the contents of a directory is not part of the prelude; the `os` module has `listDir`, and `asys` and the C library have more.

## Summary

- A program starts in `main`; its return value is the exit code, and functions may be defined in any order.
- `print`, `println`, `printInt` and friends write to standard output without buffering; `eprint` and `eprintln` write to standard error.
- `printf` and `format` take a template with C style conversions and up to eight values; `vformat` takes an array and reports the full length.
- `readLine`, `readChar`, `readAll`, `input`, `askInt` and `confirm` read standard input; `-1` or `null` means the input has ended.
- `main(int argc, char** argv)` receives the command line; `hasArg`, `argIndex` and `argValue` search it.
- `exit(code)` ends the program from anywhere; the shell sees the low 8 bits of the code.
- `readFile` and `writeFile` handle whole files; `fileOpen`, `fileRead`, `fileWrite` and `fileClose` handle pieces.

## Where next

- [Types and values](#chap-types-and-values) explains `int`, `char`, `bool`, pointers and literals.
- [Control flow](#chap-control-flow) has `if`, loops, `switch` and `defer`.
- [The standard prelude](#chap-standard-prelude) lists every function that every program has, and the compile errors you will meet.
- The [API reference of cli](#api-cli) describes a complete command line parser.
