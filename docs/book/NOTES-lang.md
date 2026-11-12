# Notes of the language guide (chapters 10 to 19)

Chapters: `src/10-first-programs.md` ... `src/19-standard-prelude.md`. Samples: `samples/lang/` (98) and `samples/std/` (13).
Everything was compiled and run with `build/ac` (x86-64 Linux); all samples also compile for the 8 targets (`samples.py --targets lang std`).

## (a) Compiler and library behaviour that is surprising or probably a bug

Each reproduction was run on this branch.

### 1. `Class c;` does not run the constructor (the docs say it does)

`docs/LANGUAGE.md` section 7 says default parameters work for constructors with `Counter c;`. In fact only `Counter c();`,
`Counter c(args);` and `new Counter(...)` run the constructor; `Counter c;` just zeroes the object. `tests/t38_defaults.a` expects this
(the expected output 12 would be 13 otherwise), so it is probably intended, but the docs are wrong and it is a trap.

```c
class Counter { public int value; public Counter(int start = 1) { value = start; } }
int main() {
    Counter a;            // 0: constructor not run
    Counter b();          // 1
    Counter c(5);         // 5
    Counter* d = new Counter();   // 1
    printf("%d %d %d %d\n", a.value, b.value, c.value, d->value);    // prints: 0 1 5 1
    return 0;
}
```

The book (chapter 15, sample `lang/class_objects`) documents the real behaviour.

### 2. A bare `sqrt(x)` after `import dmath;` gives a wrong result without a diagnostic

`dmath` imports `cmath`, whose global `sqrt` takes a bit pattern. Inside the `dmath` module `::sqrt` is used for that; in user code
`sqrt(2.0)` silently calls the bit pattern version with the converted integer 2:

```c
import dmath;
int main() {
    printlnDouble(dmath.sqrt(2.0));    // 1.4142135623730951
    printlnDouble(sqrt(2.0));          // 2.1906148709472164e+18   (wrong, no error)
    return 0;
}
```

### 3. `printfd` with a `double` variable prints nonsense

`printfd`, `sprintfd`, ... take raw bit patterns. Since `double` exists, `printfd("%.2f", d)` converts `d` to an `int` (3.0 becomes 3, the
bits of the double 1.5e-323) and prints `0.00`. Nothing warns about passing a `double` to an `int` parameter. Correct: `printfd("%.2f", __bits(d))`.

### 4. `==` on two struct values compiles and does not compare the fields

```c
struct P { int x; int y; }
int main() { P a; P b; if (a == b) println("eq"); return 0; }    // compiles, prints nothing
```

Two zeroed structs are "not equal". `operator==` works as documented.

### 5. Smaller things

* Duplicate `case` labels in one `switch` are not diagnosed: `switch (x) { case 5: break; case 5: break; }` compiles.
* `void v() {}  int x = v();` compiles (the value is 0).
* `func f = make; S x = f();` (a struct returning function called through a `func`) compiles although the docs say it is not supported.
* Calling an `int` like a function (`int x = 1; return x();`) reports `expected ';'`, which is a confusing message.
* `readLine(buf, max)` with a line longer than `max - 1` returns the line in pieces, and an exactly `max - 1` long line is followed by an empty line
  for the newline that is left (`abcdefghij` with `max` 6: `abcde`, `fghij`, ``). Not documented anywhere.
* `-D NAME` defines the macro with the value 1 (as C does); not documented.
* `__FILE__` is the path exactly as given to `ac`, so it differs from run to run in the sample checker (absolute temp path). Samples only print its ending.

## (b) Places where the reference documents are wrong or incomplete

| File, section | Claim | What really happens |
|---|---|---|
| `LANGUAGE.md` 1 | "Types, constants and enums must be declared before they are used" | Structs, constants and enums can be used before their declaration (a function body using `GREETING` and `struct P` defined at the end of the file compiled and ran). Only a **base class** must come first (`unknown type 'B'`). The chapters advise declaring them first anyway. |
| `LANGUAGE.md` 7, defaults | `Counter c;` runs `Counter(int start = 1)` | see (a) 1 |
| `LANGUAGE.md` 13 | `__OS`, `__ARCH`: "architecture 0 x86-64, 1 ARM64" | also 2 RISC-V 64 and 3 LoongArch 64 (section 7 says so) |
| `LANGUAGE.md` 14 | typical message `functions cannot return a struct by value, return a pointer` | no longer true: structs are returned by value. The message list in the book uses messages copied from real output. |
| `LANGUAGE.md` 7 ("static if") | the branch that is not chosen "is parsed but never compiled" | a syntax error in it is accepted (`this_is_never_compiled(;` in `tests/t90_static_if.a`): it is skipped by matching braces. |
| `LANGUAGE.md` 12 | `printf` "up to eight values" | correct; a ninth value is `wrong number of arguments in call` (verified) |
| `LANGUAGE.md` 12c, `CLIB.md` | "A has no floating point types", "Structs cannot be passed or returned by value", "There are no variable argument lists" | all three are out of date: `double`, structs by value and `...` / `va_arg` exist. |
| `LANGUAGE.md` 5 | division by zero "yields 0 on ARM64" | not verified (no ARM machine); on x86-64 it kills the program with SIGFPE (shell exit status 136), verified |
| `WRITING.md` | "No floats" | fixed by the coordinator; chapter 11 has a full section on `double` |
| `LANGUAGE.md` | `memcpy`, `memset` | the prelude versions return `void`, not the destination pointer as C's do (`std.a`) |
| `LANGUAGE.md` 12 | `format(...)` "returns the length" | `format` returns the number of characters **stored** (at most `max - 1`); `vformat` returns the length the full text needs |

Facts that the docs do not state and that the chapters use (all verified): top level functions cannot reuse a prelude name (`redefinition of 'max'`; locals,
methods and module functions can); a struct's size is rounded up to a multiple of 8; `Kind : uint8` enums shrink; the `int a[n]` error is
`name is not a constant`; labels are limited to 64 and `defer` to 16 per function (both messages checked); a global array with an initializer is
stored in the program file in full (8 MB for `int t[1000000] = {1, 2, 3};`) while an uninitialised one costs nothing; the stack overflows between 200 and 255 levels of a
recursion with a 32 KiB frame (8 MiB); `longjmp` does not run `defer`red expressions; `alloc` blocks are rounded to 16 bytes.

## (c) Not covered, and what was not verified

* **Separate compilation is not a checked sample.** `samples.py` compiles `main.a` alone, so a two-unit program (`util.h`, `util.a`, `main.a`) cannot be a sample.
  Chapter 18 shows the three files and the commands as `sh` transcripts that were produced by actually running them (the files are shown with `cat`).
  A directive such as `// book: link=util.a` (compile every listed unit with `-c`, then link) in `samples.py` would allow a real sample.
* Directory samples (`lang/module_*`, `lang/pp_include`, `lang/modules_demo`) are written on the assumption that `{{sample dir}}` shows `main.a` and all other
  files of the directory (`.a`, `.am`, `.h`). The chapters name the files in the text in case only `main.a` is shown.
* Nothing was run on another processor or operating system: ARM64, RISC-V, LoongArch, Windows and Android only **compile** (`--targets`). In particular the
  machine code words for arm64, riscv64 and loongarch64 in `lang/asm_add` come from `LANGUAGE.md` and `tests/t86_asm.a` and were not executed.
  Windows behaviour of `getEnv`, `isTerminal`, `__winapi`, Ctrl-Z for end of input and the ARM64 division by zero are not verified.
* The import search order beyond "next to the importing file" and "`lib/` in the current directory" (`/usr/lib/a/`, `/usr/local/lib/a/`, `lib/` next to the main
  file) and `#include <file>` in the library directories are taken from the docs.
* Not written about (belong to other chapters or are outside the language guide): networking, `http`, the C library (`clib` and the `c*` modules apart from `malloc` / `free`
  and `printfd`), the GUI and TUI, threads, `atexit`/`signal`/`qsort` (only mentioned as consumers of `func`), `os.listDir`, `cpu`, `bits`, `json`, `collections` beyond one
  `import` example.
* Not in the guide because they do not exist on this branch (checked with the compiler): `foreach`, string `switch`, lambdas, tuples, generics, `??=`, multi-dimensional arrays,
  variable length arrays, bit-fields.
* The sample count is 111 (98 in `lang`, 13 in `std`), more than the 70 to 90 asked for, because every feature got its own sample; `lang/modules_demo` is the coordinator's and is kept.
  `// book:` directives are on line 2 (the title is line 1) in `args`, `exit_code`, `runtime_builtins` and `syscall_write`.
