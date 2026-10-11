# The A language — reference

This document describes version 0.1.0. A is a small language in the C tradition: it compiles to
native code, has no garbage collector and no hidden runtime, and it keeps the syntax you already
know. Where A differs from C the text says so.

Contents
1. [Programs and comments](#1-programs-and-comments)
2. [Types](#2-types)
3. [Literals](#3-literals)
4. [Variables and constants](#4-variables-and-constants)
5. [Operators](#5-operators)
6. [Statements](#6-statements)
7. [Functions](#7-functions)
8. [Structs and classes](#8-structs-and-classes)
9. [Enums](#9-enums)
10. [Modules and imports](#10-modules-and-imports)
11. [Memory](#11-memory)
12. [Standard library](#12-standard-library)
13. [Built-in runtime functions](#13-built-in-runtime-functions)
14. [Compile errors](#14-compile-errors)
15. [Differences from C](#15-differences-from-c)

---

## 1. Programs and comments

A program is a set of source files (`.a`). Execution starts in `main`:

```c
int main() { return 0; }                       // exit code 0
int main(int argc, char** argv) { ... }        // with command line arguments
```

The value returned from `main` is the process exit code. `main` may be declared with no
parameters, only `argc`, or `argc` and `argv`.

Comments are `// to the end of the line` and `/* block comments */` (they do not nest).
Whitespace is insignificant; statements end with `;`.

Top level declarations may appear in **any order**: a function can be called before the line where
it is defined. (Types, constants and enums, however, must be declared before they are used.)

## 2. Types

| Type | Size | Notes |
|---|---|---|
| `int` (alias `long`) | 8 bytes | signed 64-bit integer |
| `char` (alias `byte`) | 1 byte | unsigned 8-bit, used for text and raw bytes |
| `bool` | 1 byte | `true` / `false`; any value stored in a `bool` becomes 0 or 1 |
| `void` | – | no value; also `void*` as a generic pointer |
| `T*` | 8 bytes | pointer to `T`, e.g. `int*`, `char**`, `Node*` |
| `T name[N]` | `N * sizeof(T)` | fixed array, `N` is a constant expression |
| `struct S` / `class C` | sum of the fields | see [section 8](#8-structs-and-classes) |
| `enum E` | 8 bytes | behaves like `int` |

`sizeof(Type)` gives the size in bytes: `sizeof(int)` is 8, `sizeof(char)` is 1,
`sizeof(int*)` is 8, `sizeof(Point)` is the size of the struct.

Arrays decay to a pointer to their first element when used as a value (`int* p = arr;`).
Pointers may be compared with `==` / `!=`, added to or subtracted from integers (scaled by the
element size), and subtracted from each other.

Casts use C syntax: `(char)x` truncates to 8 bits, `(bool)x` turns any non-zero value into 1,
`(int)p` and `(char*)p` reinterpret without changing the value.

## 3. Literals

| Kind | Examples |
|---|---|
| Integers | `42`, `1_000_000`, `0xFF`, `0b1010` (underscores are ignored) |
| Characters | `'a'`, `'\n'`, `'\0'`, `'\x41'` — type `char`, value usable as an integer |
| Strings | `"hello\n"` — type `char*`, NUL terminated, stored in writable data |
| Booleans | `true`, `false` |
| Null pointer | `null` |

Escape sequences: `\n` `\t` `\r` `\0` `\e` (escape, 27) `\\` `\"` `\'` and `\xHH`.

## 4. Variables and constants

```c
int a;                    // zero-initialised
int b = 5, c = b * 2;     // several declarators; initialisers may be any expression
char name[32];            // array, zeroed
Point p;                  // struct, zeroed
Point q = p;              // copies the whole struct
const MAX = 100;          // compile-time constant (type inferred: int)
const TITLE = "A";        // constants may also be strings
const int MASK = 0xF0;    // optionally with a type
```

* **Every variable is zero-initialised** — locals, arrays, structs and heap memory.
* **Scope:** a variable lives until the end of the block it is declared in; an inner declaration
  may shadow an outer one. A `for` loop variable lives in the loop.
* **Globals** are declared outside functions. An initialiser must be a *constant expression*
  (numbers, constants, enum values, `sizeof`, string literals and operators on them);
  uninitialised globals live in a zero-filled `bss` area and cost no file size.
* **Constants** are evaluated by the compiler and cannot be assigned to or have their address
  taken. Constant expressions support all arithmetic, bitwise, comparison and logical operators.

## 5. Operators

From highest to lowest precedence:

| Level | Operators | Notes |
|---|---|---|
| 1 | `a[i]`  `a.b`  `a->b`  `f(x)`  `x++`  `x--` | `.` and `->` are interchangeable on pointers |
| 2 | `-x`  `+x`  `!x`  `~x`  `*p`  `&x`  `++x`  `--x`  `(type)x` | right to left |
| 3 | `*`  `/`  `%` | signed; truncating division like C |
| 4 | `+`  `-` | pointer ± integer scales by the element size |
| 5 | `<<`  `>>` | `>>` is an arithmetic shift |
| 6 | `<`  `<=`  `>`  `>=` | result is 0 or 1 |
| 7 | `==`  `!=` | |
| 8 | `&` | bitwise and |
| 9 | `^` | bitwise xor |
| 10 | `\|` | bitwise or |
| 11 | `&&` | short-circuit |
| 12 | `\|\|` | short-circuit |
| 13 | `c ? a : b` | right to left |
| 14 | `=  +=  -=  *=  /=  %=  &=  \|=  ^=  <<=  >>=` | right to left |

`!`, `&&`, `||` and the comparison operators always produce 0 or 1. Any integer or pointer can be
used as a condition: zero / `null` is false, everything else is true.

Integer division by zero crashes on x86-64 (the CPU raises a fault) and yields 0 on ARM64. Do not
rely on either.

## 6. Statements

```c
if (x > 0) { ... } else if (x == 0) { ... } else { ... }
while (cond) { ... }
do { ... } while (cond);
for (int i = 0; i < n; i++) { ... }       // each of the three parts may be empty
for (;;) { if (done) break; }             // infinite loop
break;                                    // leave the innermost loop or switch
continue;                                 // next iteration of the innermost loop
return expr;   return;
```

The body of `if`, `else`, `while`, `for` may be a single statement or a `{ block }`.

### switch

```c
switch (value) {
    case 1:  println("one"); break;
    case 2:                                // falls through, like C
    case 3:  println("two or three"); break;
    case Color.Red: ...                    // case labels are constant expressions
    default: println("other");
}
```

`break` leaves the switch; without it execution continues into the next case (fall-through).
`continue` inside a `switch` applies to the enclosing loop.

## 7. Functions

```c
int add(int a, int b) { return a + b; }
void greet(char* who) { print("hi "); println(who); }
int later() { return helper() + 1; }       // helper is defined further down - that is fine
int helper() { return 41; }
```

* Parameters and results are passed by value. Arguments are evaluated **left to right**.
* Allowed parameter and result types: integers, `char`, `bool`, `enum`, pointers.
  **Structs cannot be passed or returned by value** — pass a pointer (`Point*`).
  The compiler reports an error if you try.
* Recursion works; the stack is 8 MiB (see [Memory](#11-memory)).
* There is no overloading and no default argument. A *prototype* (`int f(int a);`) is accepted
  but never necessary.
* A function that reaches its end without `return` returns 0. `return;` also returns 0.
* `private` functions (`private int helper() {...}`) are only visible inside the file that defines them.

## 8. Structs and classes

`struct` and `class` are the same construct with different defaults:

| | members are… |
|---|---|
| `struct` | public unless marked `private` |
| `class` | private unless marked `public` |

```c
class Account {
    private int balance;                   // modifier before a member ...
    public char* owner;

    public Account(char* owner, int opening) {   // constructor: same name as the class
        this.owner = owner;                // 'this' is a pointer to the object
        balance = opening;                 // members can also be used without 'this'
    }

    public void deposit(int amount) { balance += amount; }
    public int get() { return balance; }
    private void audit() { ... }           // only callable from Account's own methods
}

class Shape {
public:                                    // ... or C++ style access labels
    int id;
private:
    int secret;
}
```

* **Fields** are laid out in order with natural alignment (8 bytes for everything except `char`/`bool`
  fields). A struct field may itself be a struct or an array. A class may point to itself (`Node* next`).
* **Methods** are functions declared inside the class. Inside a method, the class's fields and
  methods are in scope without a prefix; **they shadow global functions of the same name**
  (so a method called `print` hides the global `print` inside the class — use another name).
* **Constructors:** a method named like the class, no return type. It runs when you write
  `Account a("Ann", 100);` (object on the stack) or `new Account("Ann", 100)` (on the heap).
  Without a constructor an object is simply zeroed.
* **Creating objects**

  ```c
  Account a("Ann", 100);                   // stack
  Account* p = new Account("Bob", 50);     // heap: new returns a pointer
  Point pt;  Point* hp = new Point;        // plain structs
  ```
* **Calling** a method uses `.` on an object and `.` or `->` on a pointer: `a.deposit(5)`, `p->deposit(5)`.
* **Access control** is checked at compile time. Using a private member from outside the class is an
  error: `error: member is private to its class 'balance'`.
* Structs can be copied with `=` and initialisers (`Point q = p;`), and compared field by field by hand.
  There is no inheritance and no virtual dispatch yet.

## 9. Enums

```c
enum Color { Red, Green = 5, Blue }         // Red = 0, Green = 5, Blue = 6
Color c = Color.Blue;                       // qualified use
Color d = Red;                              // unqualified also works
```

Enum constants are `int` constants usable in `switch` labels, array sizes and other constant
expressions. A trailing comma is allowed.

## 10. Modules and imports

A file can declare the module it belongs to; other files import it by name.

```c
// file geometry.a
module geometry;

const SIDES = 4;
public int area(int w, int h) { return w * h; }
private int secret() { return 42; }          // invisible outside this file
public class Box { ... }
```

```c
// file main.a
import geometry;                             // finds geometry.a
import util.math;                            // finds util/math.a
import "extras/tools.a";                     // explicit file name

int main() {
    printlnInt(geometry.area(3, 4));         // qualified access
    geometry.Box* b = new geometry.Box();    // types can be qualified too
    return geometry.SIDES;
}
```

* `import name;` searches, in this order: the directory of the importing file, `lib/` in the current
  directory, `/usr/lib/a/`, `/usr/local/lib/a/`, and `lib/` next to the main source file.
  Dots in the name become directory separators.
* A file is compiled **once** even if several files import it.
* Names declared in a `module` are accessed as `module.name`; inside the module they can be used
  unqualified. A file without a `module` line puts its names into the global namespace.
* `private` makes a top-level declaration (function, global, constant, class, enum) visible only inside its own file;
  everything else is `public`. `public` may be written explicitly.
* Different modules can use the same names without conflict (`math.square` and an own `square`).

## 11. Memory

* **Stack:** locals and parameters. 8 MiB (the usual default on Linux and Android, and set explicitly in Windows executables).
* **Globals:** `data` (initialised) and zero-filled `bss`.
* **Heap:** `new` and `alloc(n)` take memory from a 64 MiB region, always zeroed. **Memory is never
  freed** — it lives until the program exits, which is perfect for compilers, tools and short-lived programs.
  The allocator is a plain bump pointer, so it is also very fast.
* Pointers are plain addresses; there is no bounds checking.

## 12. Standard library

Everything in `lib/std.a` is compiled into your program automatically; no import is needed.

**Output**

| Function | Description |
|---|---|
| `print(char* s)` / `println(char* s)` | write a string (and a newline) to standard output |
| `printInt(int n)` / `printlnInt(int n)` | write a number |
| `printChar(char c)` | write one byte |
| `printBool(bool b)` | `true` / `false` |
| `printHex(int n)` | lowercase hexadecimal |
| `eprint(s)` / `eprintln(s)` | same for standard error |

**Input** (standard input is buffered)

| Function | Description |
|---|---|
| `int readChar()` | next byte, `-1` at the end of the input |
| `int readLine(char* buf, int max)` | a line without `\n` / `\r\n`; returns its length, `-1` at the end |
| `char* input(char* prompt)` | prints the prompt, returns the typed line as a heap string (`null` at the end) |
| `int askInt(char* prompt)` | asks until a whole number is typed |
| `bool confirm(char* prompt)` | yes / no question (`y` or `Y` = yes) |
| `char* readAll()` | the rest of standard input |
| `bool parseInt(char* s, int* out)` | strict number parsing (`false` if the text is not a number) |
| `int atoi(char* s)` | lenient number parsing |

**Formatted output**

`format(buf, max, fmt, a, b, c, d)` and `printf(fmt, a, b, c, d)` take up to four values (pass `0` for
unused ones; pass strings as `(int)text`). Specifiers: `%d` number, `%x` hex, `%c` character, `%s` string,
`%%`; widths pad with spaces (`%5d`, left aligned `%-8s`) or zeros (`%05d`).

```c
printf("%-10s|%5d|\n", (int)"total", 1600, 0, 0);       // total     | 1600|
```

`printRepeat(ch, n)` writes a character `n` times.

**Terminal**

| Function | Description |
|---|---|
| `printColor(ANSI_RED, "text")` | coloured text, plain when output is not a terminal. Colours: `ANSI_RED`, `ANSI_GREEN`, `ANSI_YELLOW`, `ANSI_BLUE`, `ANSI_MAGENTA`, `ANSI_CYAN`, `ANSI_GRAY`, `ANSI_BOLD`, `ANSI_RESET` |
| `clearScreen()`, `cursorTo(row, col)` | ANSI screen control |
| `isTerminal(fd)` | `true` if 0 / 1 / 2 is a terminal rather than a file or pipe |
| `ansiInit()` | enables escape codes on the Windows console (called automatically by the above) |

**Command line arguments** (`int main(int argc, char** argv)`)

`hasArg(argc, argv, "-v")`, `argIndex(argc, argv, flag)` (index or -1), `argValue(argc, argv, "-o", fallback)`
(the argument after the flag).

**Time**

`millis()` milliseconds counter (use differences), `sleepMs(ms)`.

**Strings and characters**

`strlen`, `streq(a, b)`, `strcmp(a, b)`, `strcpy(dst, src)`, `strcat(dst, src)`, `strdup(s)`,
`memcpy(dst, src, n)`, `memset(dst, value, n)`, `indexOf(s, c)`, `startsWith(s, prefix)`,
`intToStr(n, buf)`, `isDigit(c)`, `isAlpha(c)`, `isUpper(c)`, `isLower(c)`, `isSpace(c)`,
`toUpper(c)`, `toLower(c)`, `endsWith(s, suffix)`, `find(s, sub)`, `contains(s, sub)`,
`substr(s, start, len)`, `trim(s)`, `strUpper(s)`, `strLower(s)`, `streqi(a, b)`, `hexToStr(n, buf)`.

**Math and random numbers**

`abs(x)`, `min(a, b)`, `max(a, b)`, `srand(seed)`, `rand()` (0 … 2³¹−1, xorshift).

**Files** (same on Linux, Android and Windows)

| Function | Description |
|---|---|
| `int fileOpen(char* path, int mode)` | `FILE_READ`, `FILE_WRITE` (create/truncate) or `FILE_APPEND`; negative on error |
| `int fileRead(int h, char* buf, int n)` | bytes read, 0 at end of file |
| `int fileWrite(int h, char* buf, int n)` | bytes written |
| `void fileClose(int h)` | |
| `char* readFile(char* path)` | whole file as a NUL-terminated string on the heap, `null` on error |
| `bool writeFile(char* path, char* text)` | create/overwrite a file |

**Networking** is a separate module: `import net;` (built into the compiler, no files to install). See
[section 12a](#12a-networking).

**Process and memory**

`exit(code)`, `alloc(n)` (zeroed heap memory, never freed).

## 12a. Networking

`import net;` gives TCP over IPv4 on Linux, Android and Windows with identical code. Handles are
`int`s; functions return a negative number on failure.

```c
import net;

int main() {
    int s = net.listen(9000, 8);              // server: all interfaces, backlog 8
    int c = net.accept(s);                    // blocks until a client connects
    char line[256];
    net.recvLine(c, line, 256);               // one line, without the newline
    net.sendText(c, "echo: ");
    net.sendText(c, line);
    net.close(c);

    int h = net.connect("127.0.0.1", 80);     // client
    char* page = net.httpGet("93.184.216.34", 80, "/");
    return 0;
}
```

| Function | Description |
|---|---|
| `net.connect(host, port)` | connect to a server, returns a handle |
| `net.listen(port, backlog)` / `net.listenOn(host, port, backlog)` | start a server (`listen` binds `0.0.0.0`) |
| `net.accept(server)` | wait for a client, returns its handle |
| `net.send(h, buf, n)` | sends all `n` bytes, returns `n` |
| `net.sendText(h, text)` | sends a string, returns `true` on success |
| `net.recv(h, buf, max)` | bytes received, `0` when the peer closed |
| `net.recvLine(h, buf, max)` | one line (`\n` or `\r\n` removed), `-1` when closed |
| `net.close(h)` | close a socket |
| `net.httpGet(host, port, path)` | tiny HTTP/1.0 client, returns the body (plain HTTP only) |
| `net.parseIp(text)` | `"1.2.3.4"` to a number, `-1` if invalid |

Limits of this first version: IPv4 and TCP only (no UDP, IPv6, TLS), hosts must be IP addresses or
`localhost` (no DNS yet), calls block (no timeouts or `select`).
On Linux and Android the module uses socket system calls; on Windows it calls Winsock
(`ws2_32.dll`, started automatically) through the built-in `__winapi`.

## 13. Built-in runtime functions

These are provided by the compiler for the target platform; the standard library is built on them.
They are plain functions with a leading `__`.

| Function | Description |
|---|---|
| `__write(fd, buf, n)` | write to a file descriptor (0 = stdin, 1 = stdout, 2 = stderr; other values are handles from `__open`) |
| `__read(fd, buf, n)` | read |
| `__open(path, mode)` / `__close(h)` | files; `mode` is 0 read, 1 write, 2 append |
| `__exit(code)` | terminate the process |
| `__syscall(nr, a1, …, a6)` | raw system call (Linux and Android only; numbers differ between x86-64 and ARM64) |
| `__winapi(slot, a1, a2, a3, a4)` | call an imported Windows function by import-table slot (returns -1 elsewhere); used by `net` |
| `__OS`, `__ARCH` | predefined constants: OS 0 Linux, 1 Windows, 2 Android; architecture 0 x86-64, 1 ARM64 |
| `__cmdline()` | the Windows command line (used to build `argv`; returns `null` elsewhere) |

## 14. Compile errors

The compiler stops at the first error and prints the position, the message, the source line and a
caret:

```
prog.a:3: error: expected ';'
      return x;
      ^
```

Typical messages: `undeclared identifier 'x'`, `wrong number of arguments in call`,
`member is private to its class 'balance'`, `access to private declaration 'helper'`,
`undefined function 'f'`, `left side of assignment is not assignable`,
`functions cannot return a struct by value, return a pointer`.
The process exit code is 1; on success it is 0.

## 15. Differences from C

* Classes with methods, constructors and `public` / `private`; modules instead of `#include`.
* `int` is 64-bit; `char` is unsigned; `bool` is a real type.
* All variables start zeroed; `new` returns zeroed memory; there is no `free`.
* Functions may be used before their definition without prototypes.
* `const NAME = value;` declares a compile-time constant.
* No floating point, `unsigned`, `typedef`, `union`, function pointers, bit-fields or preprocessor — yet.
* Struct values cannot be function arguments or results.
* `switch` labels must be constant expressions (like C), and `case` values must fit in 32 bits.
