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
| GUI | a display server with window manager, VNC and framebuffer backends, a widget toolkit (menus, tabs, dialogs, tables, trees, toolbars, calendar, notifications, ...), a taskbar, remote display with cookie authentication, a VNC password and a web browser backend, a LAN chat, a web browser (forms, cookies), a network tools app, a terminal emulator, a screen locker and a display manager, all written in A (see [docs/GUI.md](docs/GUI.md)) |
| Terminal UI | a toolkit for full screen programs in the terminal: keys with all modifiers, mouse, paste, resize; colours downgraded to what the terminal has; a diff renderer that writes only what changed; menus, dialogs, lists, trees, tables, tabs, a file and a colour picker, a command palette, an event loop with timers and child process pipes. Works on Linux terminals and the AOS terminals (see [docs/TUI.md](docs/TUI.md), `examples/tui/`) |
| Algorithms | data structures (`ds`: deque, ring buffers, heaps with handles, AVL ordered map and set, hash maps, trie with wildcard search, union-find, bit set, Fenwick and segment trees with lazy updates, interval set, LRU cache, Bloom filter, count-min sketch), string algorithms (`strx`: KMP, Horspool, Rabin-Karp, Aho-Corasick, edit distances, Myers diff with unified output, suffix array, fuzzy matching, glob, natural order), random numbers (`rng`: SplitMix64, xoshiro256**, PCG, MT19937, a ChaCha20 CSPRNG, NumPy compatible distributions (binomial with n * min(p, 1 - p) above 30 is exact but not NumPy's algorithm), sampling, alias method, UUIDs), statistics (`stats`: descriptive statistics with the nine quantile definitions, streaming and windowed statistics, histograms, QR based regression with p values, accurate special functions and 11 distributions, t / chi-square / F / Mann-Whitney tests, confidence intervals, bootstrap, k-means, PCA), linear algebra (`matrix`: LU, Cholesky, Householder QR, least squares, Jacobi eigenvalues, SVD, sparse CSR matrices with conjugate gradient, complex matrices) and numerical methods (`optim`: root finding, minimisation, integration, ODE solvers, interpolation and splines, polynomial roots, FFT for any length, simplex linear programming), see [docs/ALGO.md](docs/ALGO.md) |
| Networking | TCP/UDP sockets, DNS, HTTP client and server, WebSocket, raw packets, and **TLS 1.3 written from scratch** (client and server, certificate checking, RSA/ECDSA/X25519, AES-GCM/ChaCha20-Poly1305): `https://` in `http`, `gnet` and the `abrowse` browser, `examples/httpsd.a` (see [docs/TLS.md](docs/TLS.md)) |
| Messaging and logging | `mqtt` and `mqttd` (an MQTT 3.1.1 client and a broker: QoS 0 / 1 / 2, sessions, wills, wildcards, retained messages, TLS), `redis` and `redisd` (a RESP2 client with pipelining, transactions and pub/sub, and a small in-memory server), `syslog` and `syslogd` (RFC 5424 / 3164 messages, a sender over UDP / TCP / TLS, a collector with filters, rotating files, a ring buffer and forwarding); every protocol client **and** server, with limits, tests with injected packet loss and malformed input, and strict memory tests (see [docs/NET.md](docs/NET.md)) |
| Web protocols | strict WebSocket (RFC 6455 and permessage-deflate, `wss://`, UTF-8 and close code checks, keepalive), `wshub` (a poll based server for thousands of WebSocket clients with rooms, send queues, timeouts, TLS, static files, event streams), Server-Sent Events, `httpx` (a client with redirects, cookies, keep-alive, retries, streaming; a router with middleware, static files with ETag and Range, CORS, auth, multipart) and JSON-RPC 2.0 over streams, HTTP and WebSocket (see [docs/NET.md](docs/NET.md), `examples/hub_demo.a`) |
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
`table`, `colors`, `wordfreq`, `clock`, `checksums`, `primes`, `jsonpretty`, `grep`, `bignum`, `dirlist`, `quiz`, `bank`, `modules`, `net_server` / `net_client`, `algo_bench` (speed of the `ds`, `strx` and `rng` modules), `numeric/algo2_bench` (speed of `matrix`, `stats` and `optim`) and more.
Built-in modules: `math`, `bigint`, `decimal`, `random`, `sort`, `collections`, `strings`, `regex` (groups, back references, lazy quantifiers, look-ahead), `utf8`, `json`, `csv`,
`path`, `os`, `datetime`, `encoding`, `hash` (CRC-32, MD5, SHA-1/2, HMAC), `zlib` (gzip / zlib / deflate), `tar`, `ini`, `bits`, `bytebuf` (byte buffers, endian readers, sizes), `algo` (sorting, searching, graphs, string algorithms), `arith` (checked arithmetic, number theory, fractions), `ds` (deque, heaps with handles, AVL ordered map and set, hash maps, trie, union-find, bit set, Fenwick and segment trees, interval set, LRU cache, Bloom filter, count-min sketch), `strx` (KMP / Horspool / Rabin-Karp / Aho-Corasick, edit distances, Myers diff with unified output, suffix array, fuzzy matching, glob, natural order), `rng` (SplitMix64, xoshiro256**, PCG, MT19937, a ChaCha20 CSPRNG, NumPy compatible distributions (binomial with n * min(p, 1 - p) above 30 excepted), shuffle and sampling, alias method, UUID v4), `stats` (descriptive statistics, regression, distributions and tests), `matrix` (dense and sparse linear algebra: LU, Cholesky, QR, eigenvalues, SVD, conjugate gradient) and `optim` (roots, minima, integrals, ODEs, interpolation, FFT, linear programming; see [`docs/ALGO.md`](docs/ALGO.md)), `cli`, `log`, `testing`, `asys` (system layer: freeable memory, atomic file writes, directory listing, child processes), the editor core of AIDE (`acode` text buffer and editor, `asyntax` highlighting, `atheme` themes, `aproject` project tree, search and build jobs, `afind` search and replace, `aidecore` the project file, build plans, snippets, templates, recovery and session of an IDE front end; see [`docs/AIDE.md`](docs/AIDE.md)), `gcode` (the GUI widgets of the AIDE code editor: `CodeEditor`, file explorer, tabs, find / replace, output and problems, terminal pane, colour picker, theme editor, settings, docking layout, command palette; see [`docs/GUI.md`](docs/GUI.md#the-code-editor-widgets-gcode); `examples/gui/codedemo.a` is a small editor built from them), `net` (TCP, UDP, DNS, poll), `http`, `netaddr`, `packet` (ARP / IP / ICMP / UDP / TCP / pcap), `netif` (interfaces, ARP table, routes, sockets), `dns`, `conn`, `websocket`, `wshub`, `sse`, `httpx`, `jsonrpc`, `mqtt`, `mqttd`, `redis`, `redisd`, `syslog`, `syslogd`, `netio`, `netsrv` (see [`docs/NET.md`](docs/NET.md)), `netutil` (ping, Wake-on-LAN, NTP), `rawnet`, `fixed`, `nn` (perceptron, MLP, autoencoder, Hopfield, SOM, Elman, LSTM, CNN), `codec` (text / binary / image converters), and **the C standard library** (`import clib;`):
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
* **Iteration and selection:** `foreach (int x in values)` over arrays, text, ranges (`0..n`, `rev 0..n`), `(pointer, count)` and classes with
  `count()` / `get(i)`; `switch` on text (fast for hundreds of labels), `case 1, 2:` and `case 10..20:`; labeled `break outer;` / `continue outer;`.
* **Operators:** `||=`, `&&=`, `??=` (short-circuit assignment), `^^`, `<=>`, `??`, operator overloading; `static_assert(cond, "message")`.
* **Inference, tuples, lambdas, interpolation:** `var n = 5;` (also in `for` and `foreach`); tuples and multiple results
  (`(int, int) divmod(int a, int b) { return (a / b, a % b); }`, `(int q, int r) = divmod(7, 2);`, `(a, b) = (b, a);`, `t.0`);
  lambdas (`algo.sortBy(a, n, (int x, int y) => x - y)`, `x => x * 2`; no captures: pass values as parameters) and string interpolation
  (`$"x = {x}, pi = {pi:.3f}"`) lowered to the same formatter as `printf`, which takes any number of values and prints doubles
  exactly (`%e %f %g`, correctly rounded, also `%v` for the shortest text that reads back).
* **Classes:** single inheritance, `virtual`, `abstract` classes and methods, `override` / `final` with signature checks, `static` fields and
  methods (`Counter.count`, `Util.square(3)`), and the run time checks `x is Dog` / `x as Dog`.
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
  foreach.asm     the foreach statement
  tuple.asm       tuples: types, literals, patterns
  lambda.asm      lambdas
  interp.asm      string interpolation
  switch.asm      the switch statement (integers and text)
  decl.asm        functions, classes, enums, globals, modules
  cg_x86.asm      x86-64 backend
  cg_a64.asm      AArch64 backend
  main.asm        command line, imports, ELF and PE writers
  util.asm        errors, files, buffers
lib/std.a       standard library (written in A, embedded into the compiler)
lib/*.a         built-in modules, among them the C library (cstdio.a, cmath.a ...) and the terminal toolkit (term.a, tscreen.a, tui.a, tuix.a)
examples/       example programs
tests/          regression tests + runner (tests/run.sh)
docs/           language reference, targets guide, compiler internals, AIDE editor core, data structures / string algorithms / random numbers (ALGO.md), man page
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

`tests/tui.sh` runs the terminal toolkit's programs in a pseudo terminal and checks the screen with a terminal emulator written in
Python (typing, menus, mouse, resize, paste, suspend to a shell, signals, `TERM` variants); `tests/gui.sh` tests the graphical stack,
`tests/https.sh` the TLS code, `tests/net.sh` the WebSocket, HTTP, SSE and JSON-RPC modules against python websockets, curl and raw frames, `tests/net2.sh` the MQTT, Redis and syslog servers against a raw MQTT client, `redis-cli` and `logger`
(the normal suite runs them client against server in one thread, `t340` ... `t370`). The gcode widgets (`t240` ... `t267`) are tested in-process: the display server runs inside the test program on
its Headless backend, the test types, clicks and drags through it and compares pixels, so the same checks run on all five targets.

## Limitations and roadmap

Version 0.1.0 is deliberately small. Known limitations — all of them are on the roadmap:

* **No floating point types** yet (`float` / `double`): the `cmath` module does IEEE 754 arithmetic and all of `<math.h>` in
  software on doubles held in ints. No `unsigned` or sized integer types.
* Function pointers are the type `func` (no signature checking); no bit-fields; a C-style preprocessor (`#define`, `#include`, `#if`) is built in.
  `typedef`, `union`, `static` locals, structs by value, default parameter values and `...` with `va_arg` exist.

* **Single inheritance only:** `class D : B`, `virtual`, `abstract`, `override`, `final`, `super`, `protected`; no multiple inheritance, interfaces (an abstract class with only abstract methods does the job) or destructors.
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
