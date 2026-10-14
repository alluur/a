# A

**A** is a small, C-like systems programming language with a compiler written entirely in
**x86-64 assembly**. It compiles straight to native machine code — no C compiler, no assembler,
no external linker and no libc are needed, neither to build the compiler (just `nasm` and `ld`) nor to
run it. The compiler writes finished executables itself, and it has a built-in C-style preprocessor and a built-in linker
(`ac -c a.a`, then `ac a.ao b.ao -o program`).

```c
class Counter {
    private int n;
    public Counter(int start) { n = start; }
    public void inc() { n++; }
    public int get() { return n; }
}

int main() {
    Counter c(40);
    c.inc();
    c.inc();
    print("the answer is ");
    printlnInt(c.get());      // the answer is 42
    return 0;
}
```

| | |
|---|---|
| Language | C-like syntax: variables, constants, functions, structs, **classes** (`public` / `private`), enums, modules, pointers, arrays, `if` / `else if` / `else`, `while`, `do`, `for`, `switch`, logical and arithmetic operators |
| Compiler | ~9,000 lines of NASM assembly, a single binary of about 470 KB (it carries the source of the standard library and the C library), three passes with dead function elimination, direct machine-code generation, generated code about as fast as `gcc -O0` |
| Targets | **Linux** x86-64, ARM64, RISC-V 64 and LoongArch64 · **Windows** x86-64 · **Android** ARM64, x86-64 and RISC-V 64 |
| GUI | a display server with window manager, VNC and framebuffer backends, a widget toolkit (menus, tabs, dialogs, tables, trees, toolbars, calendar, notifications, ...), a taskbar, remote display with cookie authentication and a VNC password, a network tools app, a terminal emulator, a screen locker and a display manager, all written in A (see [docs/GUI.md](docs/GUI.md)) |
| Output | static native executables (ELF64 / PE32+), typically 4–10 KB for a small program; relocatable objects (`.ao`) for separate compilation |
| Status | version 0.1.0 — complete enough for real programs, see [Limitations](#limitations-and-roadmap) |

Created by [Aytict](https://aytict.fi).

---

## Quick start

Requirements to **build the compiler**: `nasm` (2.14 or newer), `ld` (binutils) and `make`.
The compiler itself runs on **Linux x86-64**.

```sh
make                       # builds build/ac
./build/ac examples/hello.a -o hello
./hello                    # Hello from A!
```

Install it system wide (`/usr/local/bin/ac`) or build a Debian package:

```sh
sudo make install
make deb                   # -> dist/a-1-release.deb
sudo dpkg -i dist/a-1-release.deb
```

### Compiling for every platform

```sh
ac hello.a                          # Linux x86-64        -> hello-1-debug.elf
ac -t linux-arm64 hello.a           # Linux ARM64         -> hello-1-debug.arm64.elf
ac -t windows hello.a               # Windows x86-64      -> hello-1-debug.exe
ac -t android hello.a               # Android ARM64       -> hello-1-debug.bin
ac -t linux-riscv64 hello.a         # Linux RISC-V 64     -> hello-1-debug.riscv64.elf
ac -t linux-loongarch64 hello.a     # Linux LoongArch64   -> hello-1-debug.loongarch64.elf
ac -t android-x64 hello.a           # Android x86-64      -> hello-1-debug.x64.bin
```

Output files are named **`{app_name}-{version-code}-{release-type}.{ext}`** by default. Choose the
parts with `-v` and `-r`, or give an explicit name with `-o`:

```sh
ac -t windows -v 7 -r release hello.a        # hello-7-release.exe
ac -o /tmp/hello hello.a                     # exactly /tmp/hello
```

Example programs live in [`examples/`](examples/): `greet`, `calc` (interactive REPL), `wordcount`, `cat`, `todo`,
`table`, `colors`, `wordfreq`, `clock`, `checksums`, `primes`, `jsonpretty`, `grep`, `bignum`, `dirlist`, `quiz`, `bank`, `modules`, `net_server` / `net_client` and more.
Built-in modules: `math`, `bigint`, `decimal`, `random`, `sort`, `collections`, `strings`, `regex`, `utf8`, `json`, `csv`,
`path`, `os`, `datetime`, `encoding`, `hash`, `cli`, `log`, `testing`, `net` (TCP, UDP, DNS, poll), `http`, `netaddr`, `packet` (ARP / IP / ICMP / UDP / TCP / pcap), `netif` (interfaces, ARP table, routes, sockets), `dns`, `conn`, `websocket`, `netutil` (ping, Wake-on-LAN, NTP), `rawnet`, `fixed`, `nn` (perceptron, MLP, autoencoder, Hopfield, SOM, Elman, LSTM, CNN), `codec` (text / binary / image converters), and **the C standard library** (`import clib;`):
`ctype errno limits string stdlib stdio time math (correctly rounded libm) complex unistd signal locale wchar` with the C names,
see [`docs/CLIB.md`](docs/CLIB.md).

Details for every platform (adb, Termux, Wine, QEMU) are in [`docs/TARGETS.md`](docs/TARGETS.md).

---

## The language in one page

```c
// ---- constants and enums ----------------------------------------------------
const MAX = 100;
const GREETING = "hello";
enum Color { Red, Green = 5, Blue }

// ---- structs and classes ----------------------------------------------------
struct Point { int x; int y; }            // struct members are public by default

class Stack {                              // class members are private by default
    private int data[16];
    private int top;
    public void push(int v) { data[top] = v; top++; }
    public int pop()        { top--; return data[top]; }
    public bool empty()     { return top == 0; }
}

// ---- functions (may be used before they are defined) ------------------------
int fib(int n) { if (n < 2) return n; return fib(n - 1) + fib(n - 2); }

int main() {
    int total = 0;
    for (int i = 0; i < 10; i++) {
        if (i % 2 == 0 && i != 4) { total += fib(i); }
        else if (i == 4)          { continue; }
        else                      { total -= 1; }
    }
    Stack s;                               // objects live on the stack...
    s.push(1); s.push(2);
    Point* p = new Point;                  // ...or on the heap
    p->x = s.pop();
    printlnInt(total + p->x);
    switch (total % 3) {
        case 0: println("zero"); break;
        case 1: println("one");  break;
        default: println("two");
    }
    return 0;
}
```

* **Types:** `int` (64-bit signed, also `long`), `char`/`byte` (8-bit), `bool`, `void`,
  pointers `T*`, fixed arrays `T name[N]`, `struct`, `class`, `enum`.
* **Modules:** `module geometry;` at the top of a file, `import geometry;` (or `import a.b.c;`)
  elsewhere, then `geometry.area(...)`. `private` hides a declaration from other files.
* **Everything is zero-initialised**, including locals and heap memory.
* **No hidden runtime:** the "standard library" is written in A itself (`lib/std.a`) and
  compiled into your program, on top of a handful of built-in system-call stubs.

The full reference is in [`docs/LANGUAGE.md`](docs/LANGUAGE.md); a tour of the examples is in
[`examples/`](examples/).

---

## Project layout

```
src/            the compiler (NASM assembly)
  ac.asm          top-level file, includes everything else
  defs.inc        constants, macros, the code-generator primitive list
  lexer.asm       tokenizer
  symtab.asm      symbols, structs, types
  expr.asm        types, expressions, constant expressions, calls
  stmt.asm        statements and local variables
  decl.asm        functions, classes, enums, globals, modules
  cg_x86.asm      x86-64 backend
  cg_a64.asm      AArch64 backend
  main.asm        command line, imports, ELF and PE writers
  util.asm        errors, files, buffers
lib/std.a       standard library (written in A, embedded into the compiler)
lib/*.a         built-in modules, among them the C library (cstdio.a, cmath.a ...)
examples/       example programs
tests/          regression tests + runner (tests/run.sh)
docs/           language reference, targets guide, compiler internals, man page
```

## Testing

```sh
make test          # native Linux x86-64
make test-all      # all targets: Linux, Windows (via Wine), ARM64 & Android (via QEMU)
```

A **differential fuzzer** (`tests/fuzz/difffuzz.py`) compares random programs compiled by `ac` with the
same programs compiled by GCC, on every target (see [`docs/INTERNALS.md`](docs/INTERNALS.md)).

`tests/run.sh` compiles every `tests/t*.a`, runs it and compares stdout and the exit code with the
`.out` / `.exit` files next to it (`.err` files hold the expected text of a compile error).
`TARGET=windows tests/run.sh`, `TARGET=linux-arm64 tests/run.sh`, … select another target.

## Limitations and roadmap

Version 0.1.0 is deliberately small. Known limitations — all of them are on the roadmap:

* **No floating point types** yet (`float` / `double`): the `cmath` module does IEEE 754 arithmetic and all of `<math.h>` in
  software on doubles held in ints. No `unsigned` or sized integer types.
* Function pointers are the type `func` (no signature checking); no bit-fields; a C-style preprocessor (`#define`, `#include`, `#if`) is built in.
  `typedef`, `union`, `static` locals, structs by value, default parameter values and `...` with `va_arg` exist.

* **Single inheritance only:** `class D : B`, `virtual`, `super`, `protected`; no multiple inheritance, abstract classes or destructors.
* **`new` / `alloc` never free** (a bump allocator); `malloc` / `free` of the C library do.
* **Light type checking:** pointer types convert freely; this is a systems language in the C
  tradition. Syntax errors, undeclared names, wrong argument counts, private access and similar
  mistakes are reported with the source line.
* **Android:** executables run from `adb shell` or Termux. Packaging as an `.apk` is not
  implemented yet (it needs a shared-library output and signing).
* The compiler **runs on Linux x86-64** (on other hosts use QEMU or a container).
* Windows executables were verified under **Wine**; Android/ARM64 executables under **QEMU user
  mode**. Real-device reports are very welcome.

---

*A — made with care by [Aytict](https://aytict.fi).*
