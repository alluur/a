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
10. [Modules and imports](#10-modules-and-imports) (including `a_module` / `a_import`)
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
* Allowed parameter and result types: integers, `char`, `bool`, `enum`, pointers, `func`, and **structs and classes by value**
  (see below).
* Recursion works; the stack is 8 MiB (see [Memory](#11-memory)).
* There is no overloading. A *prototype* (`int f(int a);`) is accepted but never necessary.
* A function that reaches its end without `return` returns 0. `return;` also returns 0.
* `private` functions (`private int helper() {...}`) are only visible inside the file that defines them.

### Default parameter values

A parameter can have a default value: a constant expression (a number, character, `true`, `false`, `null`, a `const` name,
an enum member, simple arithmetic on them) after `=`. Parameters with defaults must be the last ones. A call may leave out
trailing arguments that have defaults:

```c
int area(int w, int h = 1, int scale = 100) { return w * h * scale / 100; }

area(5);            // 5 * 1 * 100 / 100
area(5, 4);         // 20
area(5, 4, 200);    // 40
```

This works for functions, methods and constructors (`new Counter()` / `Counter c;` with `Counter(int start = 1)`), and it is
how the standard library's `printf(fmt, a, b, c, d, e, f, g, h)` accepts one to eight values.
Text defaults are fine too: `char* sep = ", "`. (A function cannot have default values and `...` together.)

### Structs by value

A struct or class can be a parameter and a result. The caller makes a copy for the callee (so changes to the parameter do
not reach the original) and results are returned through a hidden destination:

```c
struct Point { int x; int y; }

Point add(Point a, Point b) {
    Point r;
    r.x = a.x + b.x;
    r.y = a.y + b.y;
    return r;
}

int main() {
    Point p = add(add(make(1, 2), make(3, 4)), make(5, 6));      // nested calls are fine
    printlnInt(add(p, p).x);
    return 0;
}
```

A struct result lives in a temporary of the caller's frame: `add(a, b).x` works, `Point q = add(a, b);` and `q = add(a, b);`
copy it. Calling a struct-returning function through a `func` pointer is not supported.

### Variable argument lists

A parameter list can end in `...`. The extra arguments are read with the built-in `va_arg(i)` (the i-th extra argument, from 0)
and counted by `va_count()`; both are only available inside such a function:

```c
int sum(int scale, ...) {
    int total = 0;
    for (int i = 0; i < va_count(); i++) {
        total += va_arg(i) * scale;
    }
    return total;
}

// a printf-like function: put the extra arguments in an array and use vformat
void logf(char* tag, char* fmt, ...) {
    int args[8];
    int n = va_count();
    for (int i = 0; i < n; i++) args[i] = va_arg(i);
    char buf[256];
    vformat(buf, 256, fmt, args, n);
    print(tag); print(": "); println(buf);
}

sum(10, 1, 2, 3);          // 60
logf("info", "%d items", 3);
```

All extra arguments are 64-bit values (numbers, characters, pointers, doubles as bit patterns). There is no check that `i` is
below `va_count()`. A function with `...` cannot be a method or be called through a `func` pointer.

### Function pointers

`func` is the type of a function pointer. The name of a function (or `&name`) is a `func` value; calling a `func` variable,
field, array element or parameter calls the function:

```c
int twice(int x) { return x * 2; }
int square(int x) { return x * x; }

int apply(func f, int v) { return f(v); }

struct Command { char* name; func run; }

int main() {
    func f = twice;
    printlnInt(f(21));                      // 42
    printlnInt(apply(&square, 9));          // 81
    func table[2];
    table[0] = twice;
    table[1] = square;
    printlnInt(table[1](7));                // 49
    return f == twice ? 0 : 1;              // func values can be compared
}
```

A `func` carries no signature: the arguments are not checked against the function, and the call returns an `int` (the
function's result as a 64-bit value). Only ordinary functions have an address (not methods or built-in `__...` functions).
`qsort`, `bsearch`, `atexit` and `signal` of the C library take `func` arguments.

### `typedef`, `static` and `union`

```c
typedef int Number;                    // another name for a type (at top level or inside a function)
typedef char* Text;
typedef Point* PointRef;

union Value {                          // all members share the same memory; the size is the largest member
    int i;
    char bytes[8];
    char* text;
}

static int helper() { return 1; }      // at top level: the same as private
int next() {
    static int calls;                  // inside a function: keeps its value between calls
    static int start = 100;            // optional constant initializer, set once
    calls++;
    return start + calls;
}
```

A `static` local is zero-initialized (or set from its constant initializer once, before the program starts), is visible only
in its block and may be an array (`static int table[16];`).

### `static if`, `::` and floating point

`static if (constant) { ... } else { ... }` is decided while compiling: the branch that is not chosen is parsed but never
compiled, so it may name things that do not exist on the current target. It works at file level (around declarations), inside
classes and inside function bodies. Use it with `__ARCH` (0 x64, 1 arm64, 2 riscv64, 3 loongarch64) and `__OS`
(0 Linux, 1 Windows, 2 Android) or with your own `const` values.

`::name` refers to the global `name` even when a module or local declaration shadows it (`::sqrt(x)` inside module `dmath`).

`double` (and `float`, which is an alias of `double`) is an IEEE 754 binary64 number. The compiler converts between `int` and
`double` automatically (an `int` operand of a mixed expression becomes a `double`; assigning a `double` to an `int` needs a cast
`(int) d`, which truncates toward zero). Supported: `+ - * /`, unary `-`, the six comparisons, `!` and truth tests
(`if (d)` is true when `d != 0`), `+= -= *= /=`, `?:`, struct fields, arrays, globals, parameters and return values.
Literals like `1.5`, `2e-3` and `1_000.25` are rounded exactly (to nearest, ties to even, like a C compiler).

`__bits(d)` returns the 64 raw bits of a double as an `int`; `__dbl(i)` does the reverse.

Arithmetic uses a built-in software implementation (`dfloat`, loaded only when a program uses doubles), so results are bit
for bit identical on every target. Helpers: `printDouble`, `printlnDouble`, `doubleToText`, `doubleToFixed(d, n)`,
`doubleToSci(d, n)`, `parseDouble(text)`, `isNaN`, `isInf`, `isFinite`. The `dmath` module has `sqrt cbrt pow exp exp2 expm1 log
log2 log10 log1p hypot sin cos tan asin acos atan atan2 sinh cosh tanh asinh acosh atanh floor ceil round trunc fabs fmod fmin
fmax copysign nan` and the constants `PI E TAU SQRT2 LN2 LN10 INFINITY EPSILON`.

`++` and `--` work on doubles too (they add or subtract 1.0).

### Initializer lists

Arrays and structs (locals, globals and `static` locals) can be filled with a `{...}` list. Values that are left out are 0,
a trailing comma is allowed, lists nest, and a `char` array can be filled from a string:

    int primes[6] = {2, 3, 5, 7, 11};            // the last element is 0
    Point p = {3, 4};
    Line l = {{1, 2}, {3, 4}, "ab"};              // nested structs, a char array field
    char name[16] = "Aytict";
    char* words[3] = {"alpha", "beta", "gamma"};
    double w[2] = {1.5, 2};                       // ints are converted

Too many values (`int a[2] = {1, 2, 3};`) or a string longer than the array is a compile error. Global and `static` lists
must be made of constants; local lists may use any expression.

### `defer`

`defer expression;` postpones an expression until the function returns, whether through `return` or by reaching the closing
brace. Deferred expressions run last-in first-out, after the return value has been computed, and can use every local that was
declared before the `defer`. It is meant for cleanup:

    int work(int fd) {
        defer close(fd);
        if (bad()) { return -1; }     // close(fd) still runs
        return process(fd);
    }

`defer` is only allowed directly in a function body (not inside `if`, loops or other blocks), at most 16 per function.

### `goto`, designated initializers and compound literals

These work as in C99.

`goto label;` jumps to `label:` anywhere in the same function, forwards or backwards. Labels are per function; a duplicate
label or a `goto` to a label that does not exist is a compile error (at most 64 labels per function).

    for (int i = 0; i < n; i++) {
        if (bad(i)) goto fail;
    }
    return 0;
fail:
    return -1;

Designated initializers pick the field or element by name or index; whatever follows continues from there, and everything
that is not named is 0:

    Point p = {.y = 5, .x = 3};
    int table[8] = {[1] = 10, [4] = 40, 50};      // table[5] is 50
    Box b = {.hi = {7, 8}, .tag = {1, 2, 3}};

Chained designators such as `.a.b = 1` are not supported; write `.a = {.b = 1}`.

A compound literal builds a nameless object inside a function. It lives until the function returns, and its address may
be taken:

    area((Point){6, 7});
    p = (Point){.x = 1, .y = 2};
    sum((int[]){1, 2, 3}, 3);                     // the size is counted from the list
    Point* q = &(Point){5, 6};

An unsized `(T[]){...}` list must be written without `[index] =` designators (the elements are counted).

### More C syntax

**Comma operator.** `a = 1, b = 2` evaluates both and has the value of the last one. It works anywhere a full expression is
allowed: statements, `for (i = 0, j = n; i < j; i++, j--)`, conditions and parentheses (not between function arguments).

**`sizeof` of values.** `sizeof(x)`, `sizeof x` and `sizeof(expr)` give the size of a variable, array or expression; the
expression is not evaluated and must not contain function calls. For an array name the result is the whole array, so
`sizeof(a) / sizeof(a[0])` is the element count. (An array that is a struct field cannot be measured this way; use `sizeof(Type)`.)

**C integer words.** `short`, `long`, `signed`, `unsigned` (also `long long`, `unsigned long int`, `long double`) are accepted
and mean the ordinary A types: all integers are the 64-bit signed `int`, `unsigned char` is `char`, `long double` is `double`.
No unsigned arithmetic happens, so use the `%u`/`%x` conversions or the unsigned helpers of the library when it matters.

**Adjacent string literals** are joined: `"Hello, " "world"` (also across lines).

**`typedef enum` and `typedef struct`.**

    typedef enum { RED, GREEN = 5, BLUE } Color;
    typedef struct { int x; int y; } Point;
    typedef struct Node { int val; struct Node* next; } Node;

**`struct`, `class`, `union` and `enum` in types.** `struct Point p;`, `struct Node* next;` and `sizeof(struct Point)` are
accepted next to the plain `Point p;`.

**`extern`.** `extern int counter;` is accepted and ignored: a whole program is compiled together, so the definition just has to
appear somewhere.

**Function pointer declarators.** `int (*op)(int, int) = add;`, `typedef int (*BinOp)(int, int);`, struct fields and parameters
such as `int apply(int (*f)(int, int), int a, int b)` are accepted. They all become the type `func`; as before the signature
is not checked.

### The preprocessor

Every source file is run through a C-style preprocessor before it is compiled. (The modules that are built into the compiler
do not need it.) Directives start with `#` at the beginning of a line (spaces before it are fine); a line that ends with `\`
continues on the next line.

| Directive | Meaning |
|-----------|---------|
| `#define NAME body` | object-like macro: `NAME` is replaced by `body` |
| `#define NAME(a, b) body` | function-like macro. In the body `#a` makes a string of the argument, `a ## b` pastes two tokens, `...` / `__VA_ARGS__` take the remaining arguments |
| `#undef NAME` | removes a macro |
| `#include "file"` / `#include <file>` | inserts a file. `"file"` is looked for next to the including file first, then as given, then in the `lib` directories |
| `#pragma once` | the file is only included once |
| `#ifdef X` `#ifndef X` `#if expr` `#elif expr` `#else` `#endif` | conditional compilation. `expr` may use `defined(X)`, integers, character constants, `+ - * / % << >> & | ^ ~ ! && || == != < > <= >=`; names that are not macros count as 0 |
| `#error text` | stops with an error. `#warning` and `#line` are accepted and ignored |

Predefined macros: `__A__` (1), `__ARCH__` (0 x64, 1 arm64, 2 riscv64, 3 loongarch64), `__OS__` (0 Linux, 1 Windows, 2 Android),
`__FILE__` and `__LINE__`. On the command line `-DNAME` and `-DNAME=value` define a macro, and `-E` prints the preprocessed
source instead of compiling it.

    #define SQUARE(x) ((x) * (x))
    #define LOG(...) println(__VA_ARGS__)
    #if defined(DEBUG) && __OS__ == 0
        LOG("debug build on Linux");
    #endif

Comments are removed and a macro call may span several lines, but the output always has the same number of lines as the
input, so error messages show the right line. The lines of an `#include`d file are joined into the line of the directive.
Macros are global: a macro defined in one file is also visible in files that are imported later. A macro is not expanded inside
itself (`#define A A + 1` is fine). For constants the compile-time features of A itself (`const`, `static if`) are usually the better choice; use
macros for code that has to differ between builds.

### Separate compilation: objects and the linker

Besides compiling a whole program from one source file, `ac` can compile files separately and link them, like a C toolchain:

    ac -c util.a -o util.ao          # compile one unit to an object file
    ac -c main.a -o main.ao
    ac main.ao util.ao -o prog       # link the objects into a program

Declarations are shared the C way, with a header that both units `#include`: function prototypes (`int add(int a, int b);`),
`extern` variables (`extern int counter;`), and the definitions of structs, classes and constants.

    // util.h
    int add(int a, int b);
    extern int counter;
    struct Pair { int x; int y; }

    // util.a                         // main.a
    #include "util.h"                 #include "util.h"
    int counter = 100;                int main() { printlnInt(add(20, 22)); return counter; }
    int add(int a, int b) { return a + b; }

* A unit that is compiled with `-c` contains the code and data of its own file (and of the files it `#include`s or `import`s
  from disk). The built-in library (`println`, `collections`, `net`, ...) is not part of an object: the link step
  compiles the parts of it that the objects use, so there is only one copy of it and library state (the heap, `rand`) is shared.
* Every function and global variable that is not `private` / `static` is visible to the other objects. Two objects that both
  define the same name give a link error (`duplicate definition of 'f'`); the methods of a class that is defined in a header are
  the exception, they may be defined once in every object. A name that nobody defines gives `undefined reference to 'f'`.
* `static` (or `private`) functions and variables belong to their own object.
* The link step needs the same target for all objects (`-t`) and the same compiler version; an object records both. The order
  of the objects on the command line does not matter. `main` must be defined in exactly one object.
* Calls between objects go through a relocation (an indirect call), so the first call of a function from another object is
  a little slower than a call inside one unit.
* Because every unit is compiled without seeing the others, an `import` of a user file in two objects makes two copies of that
  file (and a duplicate definition). Put shared declarations in a header and the definitions in exactly one unit.
* Object files are made for one target: `-t windows -c x.a` produces a Windows object.

### Inline assembly

`asm` puts machine code of your choice into a function. The program lists the code for every CPU it should run on;
the compiler uses the section of the CPU it is compiling for (`x64`, `arm64`, `riscv64`, `loongarch64`) and skips the others.

```c
int add2(int a, int b) {
    return asm(a, b) {                       // a goes into the register A, b into B (a third operand into D)
        x64: 0x48, 0x01, 0xC8;               // add rax, rcx           (x64 values are bytes)
        arm64: 0x8B010000;                   // add x0, x0, x1         (the other CPUs: 32 bit instruction words)
        riscv64: 0x00B50533;                 // add a0, a0, a1
        loongarch64: 0x00109484;             // add.d a0, a0, a1
    };                                       // the value of the expression is the register A afterwards
}
asm() { x64: 0x90; arm64: 0xD503201F; riscv64: 0x00000013; loongarch64: 0x03400000; }     // as a statement the ';' is optional
```

| | x64 (Linux, Windows, Android) | arm64 | riscv64 | loongarch64 |
|---|---|---|---|---|
| A, B, D | rax, rcx, rdx | x0, x1, x2 | a0, a1, a2 | $a0, $a1, $a2 |
| free to clobber | rsi, rdi, r8-r11 | x3-x5, x9-x17 | t0-t6, a3-a7 | $t0-$t8, $a3-$a7 |
| keep intact | rsp, rbp, rbx, r12-r15 | sp, x29, x30 | sp, s0, ra | $sp, $fp, $ra |

* At most three operands. Section names: `x64` (`x86_64`, `amd64`), `arm64` (`aarch64`), `riscv64` (`rv64`), `loongarch64` (`la64`).
  An unknown name is an error, and so is a block without a section for the CPU being compiled.
* There is no assembler in the compiler: get the instruction words from an assembler (`llvm-mc -show-encoding`, `as`) or from
  a manual. `docs/gen_cpu.py` shows how the `cpu` module's blocks are generated from assembler text with `llvm-mc`.
* The code must not change the stack pointer permanently, must keep the registers listed under "keep intact" and may not jump
  out of the block (jumps inside it are fine, offsets are relative). The `cpu` and `thread` modules are written with `asm`.

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

### Inheritance and virtual methods

A class can extend one base class: `class Dog : Animal { ... }`. The base class must be defined first.

```c
class Animal {
    protected int legs;                       // visible in Animal and in classes derived from it
    public Animal(int l) { legs = l; }
    public virtual int speak() { return 1; }  // called through the object's real class
    public int describe() { return speak() * 1000 + legs; }
}
class Dog : Animal {
    public Dog() { super(4); }                // run the base class constructor
    public int speak() { return 2; }          // overrides Animal.speak (already virtual)
}
class Puppy : Dog {
    public int speak() { return super.speak() + 10; }   // call the base class version directly
}
Animal* a = new Puppy();
printlnInt(a->describe());                    // 12004: speak() resolves to Puppy.speak
```

* The derived object starts with the fields of the base class, so a `Dog*` can be used wherever an
  `Animal*` is expected (pointer types convert freely in A).
* `virtual` gives a method a slot in the class's vtable. A method with the same name as a virtual method of
  a base class overrides it, with or without the keyword. The signature is not compared.
* `protected` members can be used by the class itself and by derived classes. `private` members stay
  private to the class that declares them, even from derived classes.
* `super(args);` calls the base class constructor (put it first in your constructor). A class without a
  constructor of its own uses the base class constructor. `super.name(args)` calls a base class method
  without virtual dispatch.
* Objects of a class with virtual methods get their vtable pointer when they are created with `new`,
  declared as a local, or declared as a global. Copying an object copies the pointer as well (no
  slicing protection, no destructors, no multiple inheritance, no abstract classes).
* A virtual method must have a body, otherwise the program fails to link with `undefined function`.

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

### Module files: `a_module` and `a_import`

The clearest way to write a reusable module is a **module file** with the extension `.am`. The module
name and its content are written in one block:

```c
// file shapes.am
a_module shapes
{
    const SIDES = 4;
    public int area(int w, int h) { return w * h; }
    private int secret() { return 42; }          // only visible inside shapes.am
    public class Box { public int w; public int h; public Box(int a, int b) { w = a; h = b; } }
}
```

Both `.a` and `.am` files can import a module file with `a_import`:

```c
a_import('shapes.am');                            // use it as shapes.area(...)
a_import('shapes.am', 'area, Box');               // also use area and Box without the prefix
a_import('shapes.am', '*');                       // ... or every public member
```

* The first argument is the file name. It is looked up like `import "file"`: next to the importing file,
  then `lib/`, `/usr/lib/a/` and `/usr/local/lib/a/`. Single quotes (`'...'`) and double quotes both work
  inside `a_import( ... )`.
* The optional second argument lists the members to bring into the importing file's own namespace, separated
  by commas or blanks. A name that is not a public member of the file is a compile error
  (`the module has no public member called 'secret'`), and so is a name that is already declared.
  The members can still be reached as `shapes.area`.
* A module file can itself contain `a_import` lines (before or inside the block). A file is compiled
  once, however many files import it. Several files can contribute to the same module name.
* `a_module` blocks cannot be nested. The older forms `module name;` and `import name;` keep working; the
  standard library still uses them.

## 11. Memory

* **Stack:** locals and parameters. 8 MiB (the usual default on Linux and Android, and set explicitly in Windows executables).
* **Globals:** `data` (initialised) and zero-filled `bss`.
* **Heap:** `new` and `alloc(n)` take memory from a 64 MiB region (and, when that is used up, from further blocks that the
  operating system provides), always zeroed. **`new` and `alloc` never free** — the memory lives until the program exits,
  which is perfect for compilers, tools and short-lived programs. The allocator is a plain bump pointer, so it is also very
  fast. Programs that run for a long time can use `malloc` / `calloc` / `realloc` / `free` from the `cstdlib` module (a
  real allocator that reuses freed blocks, see [CLIB.md](CLIB.md)).
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

`format(buf, max, fmt, a, b, ...)` and `printf(fmt, a, b, ...)` take up to eight values (leave out the unused ones;
text is passed as it is). `vformat(buf, max, fmt, values, count)` takes the values as an array and returns the length the
complete text has. The formats are those of C: flags `- 0 + space #`, width and precision (also `*`), `h hh l ll z` length
modifiers, and the conversions `d i u x X o b c s p %` (`%b` is binary). Every value is 64 bits wide; `%u` and `%x` show
negative numbers as unsigned 64-bit values.

```c
printf("%-10s|%5d|%#08x\n", "total", 1600, 255);       // total     | 1600|0x0000ff
```

Floating point conversions (`%f %e %g %a`) are in `printfd` of the `cfloat` module.

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

**Environment and file system**

`getEnv(argc, argv, "NAME")` (value as a heap string, `null` if unset), `fileExists(path)`, `fileDelete(path)`,
`makeDir(path)`.

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
| `net.resolve(host)` | an address, `"localhost"` or a **host name** to an IPv4 address, `-1` if unknown. `connect` calls it, so `net.connect("example.org", 80)` works |
| `net.setTimeout(h, ms)` | time limit for receiving and sending on a socket (`0` = wait forever); a timed out `recv` returns a negative number |
| `net.localPort(h)` | the port a socket is bound to |
| `net.udpSocket()` / `net.udpBind(port)` | a UDP socket / one bound to a port (`0` = pick a free one) |
| `net.sendTo(h, ip, port, buf, n)` | send one datagram |
| `net.recvFrom(h, buf, max, &ip, &port)` | receive one datagram and learn who sent it (`ip`, `port` may be `null`) |
| `net.dnsBuildQuery(name, id, buf)` / `net.dnsParseReply(buf, n, id)` | the DNS packets themselves |
| `net.setDns("8.8.8.8", 53)` | use this DNS server instead of the system's |
| `net.poll(handles, events, revents, n, ms)` | wait for several sockets at once (`net.READABLE`, `net.WRITABLE`; results also `net.FAILED`, `net.HUNGUP`); returns how many are ready, `0` on time out. `net.waitReadable(h, ms)` / `net.waitWritable(h, ms)` for one socket |
| `net.connectTimeout(host, port, ms)` | connect with a time limit |
| `net.shutdown(h, how)` | `0` stop reading, `1` stop writing (the peer sees the end of the data), `2` both |
| `net.peer(h, &ip, &port)` / `net.localIp(h)` / `net.localPort(h)` | the addresses of a connection |
| `net.setNoDelay` / `setKeepAlive` / `setBroadcast` / `setReuse(h, on)` | socket options; `net.joinMulticast(h, group)` joins a multicast group |
| `net.hostName()` | the name of this computer |

Host names are resolved like this: on **Windows** by the system (`gethostbyname`); on **Linux and Android** from
`/etc/hosts`, then by a DNS query over UDP to the servers in `/etc/resolv.conf` (then `8.8.8.8` and `1.1.1.1`).
Limits: IPv4 only, no IPv6 and no TLS; calls block (use `setTimeout`, there is no `select`).
On Linux and Android the module uses socket system calls; on Windows it calls Winsock
(`ws2_32.dll`, started automatically) through the built-in `__winapi`.

### `http` - HTTP client and server

`import http;` builds HTTP/1.1 on top of `net` (plain `http://`, no TLS).

```c
import http;
import net;

void hello(http.Request* q, int client) {              // the handler of http.serve
    char name[64];
    if (http.queryValue(q, "name", name, 64)) {
        char text[128];
        format(text, 128, "hello %s", name);
        http.respond(client, 200, "text/plain", text);
    } else {
        http.respond(client, 404, "text/plain", "who?");
    }
}

int main() {
    // client
    http.Response* r = http.get("http://example.org/index.html");     // follows redirects
    if (r == null) { println(http.error()); return 1; }
    printlnInt(r->status);  println(r->body);  println(r->header("Content-Type"));
    http.post("http://localhost:8080/items", "{\"id\":1}", "application/json");

    // server: answers 100 requests on port 8080 (0 = forever)
    http.serve(8080, hello, 100);
    return 0;
}
```

| Function | Description |
|---|---|
| `http.get(url)`, `http.post(url, body, contentType)`, `http.request(method, url, extraHeaders, body, bodyLen)` | one request, returns an `http.Response*` (`status`, `headers`, `body`, `bodyLen`, `header(name)`) or `null`; `http.error()` tells why |
| `http.parseUrl(url, u)` | splits a URL into an `http.Url` (`scheme host port path`) |
| `http.sendRequest(h, ...)`, `http.readResponse(h)` | the two halves of a request on a connection you made yourself. Bodies with `Content-Length`, `chunked` and "until closed" are all understood |
| `http.readRequest(h, q)` | server side: reads a request into an `http.Request` (`method path query version headers body bodyLen header(name)`) |
| `http.queryValue(q, "name", buf, max)` | a URL decoded query parameter |
| `http.respond(h, status, contentType, body)`, `http.respondBytes(...)` | send a response |
| `http.serve(port, handler, count)` | accept loop that calls `handler(request, client)` |
| `http.statusText(code)`, `http.headerOf(raw, name, buf, max)` | helpers |

## 12b. Built-in modules

These modules are written in A and built into the compiler. `import name;` makes them available, they add
code only to programs that import them, and a file of the same name next to your source takes precedence.

| Module | Contents |
|---|---|
| `math` | `gcd lcm pow powMod isqrt isPrime nextPrime factorial fibonacci binomial clamp sign mod floorDiv popcount ilog2 digitSum sum minOf maxOf randRange shuffle` (integers only) |
| `bigint` | arbitrary precision integers: class `BigInt`; `fromInt parse add sub mul mulSmall divSmall pow factorial fibonacci cmp negate`; `toString() digits() toInt()` |
| `decimal` | exact fixed point decimals (money): `parse format mul div rescale percentOf formatMoney` |
| `random` | class `Random` with its own seed: `next range nextBool chance shuffle pick token`; `clockSeed()` |
| `sort` | `sortInts(a, n)`, `sortStrings(a, n)`, `reverseInts`, `isSorted`, `binarySearch(a, n, key)` |
| `collections` | `IntList`, `StrList`, `StrMap` (string to int), `IntMap` (int to int), `IntSet`, `StrSet`, `IntQueue`, `IntHeap` (min-heap), `PriorityQueue` |
| `strings` | class `StringBuilder`; `concat repeat reverse count lastIndexOf replace padLeft padRight isBlank capitalize upper lower split join` |
| `regex` | `matches(pattern, text)`, `search(pattern, text, &len)`, `test`, `replaceAll` with `. ^ $ * + ? [a-z] [^x] \d \w \s` (no groups or `\|`) |
| `utf8` | `length decode encode isValid byteOffset toCodepoints fromCodepoints reverse` |
| `json` | `parse(text)`, `stringify(v)`, `pretty(v)`, builders `newObject newArray newInt newString newBool newNull`; class `Json` with `get at size keyAt set push asInt asString asBool intOr stringOr boolOr` |
| `csv` | `parseLine(line, sep, out, max)`, `quote(field, sep)`, `joinLine(fields, n, sep)` |
| `path` | `join basename dirname extension stem withExtension isAbsolute normalize` |
| `os` | `getCwd rename fileSize listDir(path, out, max)` (plus `fileExists fileDelete makeDir` in the standard library) |
| `datetime` | `now() nowMillis() toUnix() dayOfWeek() isLeapYear() daysInMonth() weekdayName() monthName()` and class `DateTime` (UTC) |
| `encoding` | `base64Encode/Decode`, `hexEncode/Decode`, `urlEncode/Decode` |
| `hash` | `crc32 adler32 fnv1a djb2 sha256` |
| `cli` | class `ArgParser`: `addFlag addOption parse flag option optionInt positional positionalCount printHelp` (short, long, `--x=value`, combined `-abc`) |
| `log` | leveled logging with timestamps and colours: `debug info warn error` (+ `f` variants), `setLevel setFd setTimestamps` |
| `testing` | `assertEq assertStrEq check summary` for unit tests |
| `clib` (and `cctype climits cerrno cassert cstring cstdlib cstdio ctime cunistd cmath cfloat ccomplex clocale cwchar`) | the C standard library, see [12c](#12c-the-c-library) and [CLIB.md](CLIB.md) |
| `net` | TCP / UDP networking and DNS, see [12a](#12a-networking) |
| `http` | HTTP/1.1 client and server, see [12a](#12a-networking) |
| `netaddr`, `packet`, `netif`, `dns`, `conn`, `websocket`, `netutil`, `rawnet` | addresses, packets (ARP, IP, ICMP, UDP, TCP, pcap), interfaces / ARP table / routes / connections, DNS records, buffered connections and a poller, WebSocket, ping / Wake-on-LAN / NTP, raw frames: see [12e](#12e-the-networking-modules) |
| `cpu`, `thread` | atomics, barriers, timers, CPU identification, threads: see [12f](#12f-the-processor-cpu-and-thread) |
| `fixed`, `nn`, `codec` | fixed-point numbers, neural networks, text / binary / image converters, see [12d](#12d-fixed-point-numbers-neural-networks-and-converters) |

```c
import collections;
import sort;
import hash;

int main() {
    collections.IntList* list = new collections.IntList();
    list->push(30); list->push(10); list->push(20);
    sort.sortInts(list->items(), list->size());          // 10 20 30
    collections.StrMap ages;                              // objects can live on the stack too
    ages.put("ann", 31);
    println(hash.sha256("abc", 3));                       // ba7816bf...
    return ages.get("ann", 0);
}
```

Notes: collections never free memory (see section 11), `StrMap` copies its keys, out-of-range
`IntList.get` returns 0, and iteration over a map goes through its slots
(`for (int s = 0; s < m.capacity(); s++) if (m.keyAt(s) != null) ...`).

## 12d. Fixed-point numbers, neural networks and converters

A has no `float` type, so the AI modules run on **fixed-point numbers**: an `int` that holds the value times
2<sup>20</sup> (`fixed.ONE` is 1.0, resolution about 0.000001, products must stay below ±2048). They are
integer-only, so every platform and CPU computes exactly the same numbers.

```c
import fixed;
int a = fixed.fromText("2.5");   int b = fixed.fromInt(3);
fixed.putln(fixed.mul(a, b), 3);                              // 7.500
```

`fixed`: `ONE FB HALF LN2 PI E`; `fromInt toInt ratio fromParts fromText toText put putln`; `mul div abs min max clamp sign floor round
sqrt exp log pow sin cos sigmoid tanh relu`; random numbers `seed next rand randRange gauss`.

### `nn` - neural networks

`import nn;` - all vectors and matrices are plain `int` arrays of fixed-point numbers.

| Class | Kind |
|---|---|
| `nn.Perceptron(n)` | one neuron with a step output: `train fit predict` |
| `nn.Network(count, sizes, hiddenAct, outAct)` | multi-layer feed-forward network (MLP) with back-propagation and momentum. Activations `ACT_LINEAR ACT_SIGMOID ACT_TANH ACT_RELU ACT_LEAKY ACT_SOFTMAX`, loss `LOSS_MSE` / `LOSS_CE`. `forward predict train trainEpoch fit evaluate accuracy save load parameters` |
| `nn.Autoencoder(inputs, hidden, code)` | squeezes data into a short code: `fit train encode decode reconstruct` |
| `nn.Hopfield(n)` | associative memory for ±1 patterns: `store recall energy` |
| `nn.SOM(w, h, dim)` | self-organizing (Kohonen) map: `fit train bmu quantizationError` |
| `nn.Elman(in, hidden, out)` | simple recurrent network: `step run trainSequence resetState` (back-propagation through time) |
| `nn.LSTM(in, hidden, out)` | long short-term memory network with the same methods as `Elman` |
| `nn.ConvNet(w, h, filters, ksize, classes)` | convolution → relu → 2x2 max-pool → dense softmax: `forward predict train fit accuracy` |

Helpers: `nn.vec(n)`, `nn.argmax`, `nn.softmax`, `nn.mseLoss`, `nn.ceLoss`.

```c
import nn;
import fixed;

int main() {
    int ONE = fixed.ONE;
    int sizes[3]; sizes[0] = 2; sizes[1] = 4; sizes[2] = 1;
    nn.Network* net = new nn.Network(3, sizes, nn.ACT_TANH, nn.ACT_SIGMOID);
    int x[8] = ...;                                   // XOR: four samples of two numbers
    net->fit(x, targets, 4, 3000, fixed.fromText("0.5"), 0);
    int* y = net->forward(&x[2]);                     // y[0] is about 1.0
}
```

### `codec` - text, binary and image converters

`import codec;` converts between text, binary and pictures, and produces the vectors the networks want.

| Group | Functions |
|---|---|
| text ↔ binary | `textToBinary(text, sep)` `"Hi"` → `"01001000 01101001"`, `binaryToText`, `bytesToBinary`, `binaryToBytes`, `intToBinary`, `binaryToInt`, `bytesToBits`, `bitsToBytes` |
| image ↔ binary | `imageToBinary(img, threshold)` (rows of `0`/`1`, `1` = dark), `binaryToImage(text)`, `imageToBits`, `bitsToImage`, `imageToBytes`, `bytesToImage`, `packBits`, `unpackBits` |
| text ↔ image | `textToImage(text, scale)` draws text with a built-in 5x7 font; `imageToText(img, scale)` reads it back (scale `0` = detect; noisy pictures are fine); `imageToTextWith(img, scale, recogniser)` lets **your network** recognise each character |
| for networks | `textToVector`, `vectorToText`, `bitsToVector`, `vectorToBits`, `bitsToSigns`, `signsToBits` (Hopfield), `oneHot`, `fromOneHot`, `imageToVector`, `vectorToImage`, `glyphVector`, `glyphChar`, `fontSet(chars, x, t)` (training data for a character recogniser) |
| files | `writePgm readPgm writePbm readPbm writeBmp readBmp` (BMP reads 1, 8, 24 and 32 bit) |
| display | `toAscii(img, step)` |

A `codec.Image` has `w`, `h` and one byte per pixel in `px` (0 = black); methods `get set fill copy crop scaleUp resize invert threshold`.

```c
codec.Image* page = codec.textToImage("CAFE 2024", 3);        // text -> picture
println(codec.imageToText(page, 3));                          // picture -> text
// let a trained network read it: int recognise(int* glyph) { return alphabet[net->predict(glyph)]; }
println(codec.imageToTextWith(page, 3, recognise));
```

## 12f. The processor: `cpu` and `thread`

`import cpu;` is built on `asm` blocks and works the same on x86-64, ARM64, RISC-V 64 and LoongArch64:

| Function | Description |
|---|---|
| `cpu.cycles()` | a monotonic counter (cycles on x86-64, the fixed rate system timer elsewhere) |
| `cpu.pause()`, `cpu.fence()` | spin-loop hint, full memory barrier |
| `cpu.atomicAdd(&n, v)` `atomicSub` `atomicInc` `atomicDec` | atomic update, returns the **old** value |
| `cpu.atomicSwap(&n, v)`, `cpu.atomicCas(&n, expected, desired)` | exchange / compare-and-swap, return the old value |
| `cpu.atomicLoad(&n)`, `cpu.atomicStore(&n, v)` | with memory barriers |
| `cpu.lock(&flag)`, `unlock`, `tryLock` | a spin lock on an `int` (0 = free) |
| `cpu.archName()`, `cpu.arch()` | which CPU the program was built for |
| `cpu.cpuid(leaf, sub, reg)`, `cpu.vendor()`, `cpu.brand()` | x86-64 CPU identification (empty / 0 on other CPUs) |
| `cpu.hwcap()`, `cpu.hwcap2()` | the capability bits the Linux / Android kernel reports |

`import thread;` starts real operating system threads (the `clone` system call, started by an asm block) on Linux and Android:

```c
import thread;
import cpu;

int counter;
int worker(int n) {                              // int function(int)
    for (int i = 0; i < 1000; i++) cpu.atomicAdd(&counter, 1);
    return n * 10;
}

int main() {
    thread.Thread* a = thread.spawn(worker, 1);
    thread.Thread* b = thread.spawn(worker, 2);
    printlnInt(thread.join(a) + thread.join(b));   // 30
    printlnInt(counter);                           // 2000
    thread.parallelFor(1000, body, 4);             // body(i) for i = 0 .. 999 on 4 threads
}
```

`thread.spawn(fn, arg)`, `thread.join(t)`, `thread.finished(t)`, `thread.parallelFor(n, body, workers)` (0 = one per processor),
`thread.cpuCount()`, `thread.currentId()`, `thread.yield()`, `thread.supported()`.
**The runtime of A is not thread safe:** `alloc` / `new`, printing and the file functions must not be used from several threads at the
same time (guard them with `cpu.lock`); compute into arrays or counters and print from the main thread. On Windows `spawn` runs the
function at once in the calling thread (`supported()` is false), so programs give the same results there.

## 12e. The networking modules

The modules below are layered on `net` and work on Linux, Android and Windows (where a feature needs the
operating system it says so). The packet-level modules (`netaddr`, `packet`) are pure computation and work everywhere.

| Module | What it is |
|---|---|
| `netaddr` | addresses and numbers: `htons htonl ntohs ntohl`; IPv4 `ipFromBytes ipParse ipToText isPrivate isLoopback isMulticast isLinkLocal ipClass reverseName`; subnets `maskFromPrefix prefixFromMask network broadcast hostCount firstHost lastHost inSubnet parseCidr` (`"192.168.1.77/26"`); MAC `macParse macToText macIsBroadcast macIsMulticast macRandom`; IPv6 `ip6Parse ip6ToText` (with `::`), `ip6IsLoopback ip6FromV4 ip6ToV4`; `serviceName(443)` = `"https"`, `servicePort("ssh")`, `isHostname`, `checksum` (RFC 1071) |
| `packet` | build and read packets with correct checksums: `ethBuild/ethParse` (VLAN tags too), ARP `arpBuild arpParse arpRequestFrame arpReplyFrame`, IPv4 `ipBuild ipParse`, ICMP `icmpEcho icmpParse`, UDP `udpBuild udpParse udpChecksumOk`, TCP `tcpBuild tcpParse tcpChecksumOk` (flags `TCP_SYN TCP_ACK ...`, MSS option); `describe(frame, n)` prints one line like tcpdump, `hexdump`; `PcapWriter` / `PcapReader` for `.pcap` files that Wireshark opens |
| `netif` | what the system knows (ifconfig, `arp -a`, route, netstat): `interfaceCount/interfaceAt/findInterface/localAddress` (name, `ip`, `mask`, `mac`, `mtu`, up/loopback, byte counters), `arpCount/arpAt/arpLookup`, `routeCount/routeAt/defaultGateway`, `connectionCount/connectionAt/stateName` (open TCP and UDP sockets), `dnsServers`; the text parsers `parseNetDev parseArp parseRoutes parseSockets`. Linux and Android read `/proc` and ask the kernel; Windows uses `iphlpapi.dll` |
| `dns` | DNS with record types `A NS CNAME SOA PTR MX TXT AAAA SRV`: `query(name, type)` then `recordAt(i)`, `recordText`, `lookupA`, `reverse(ip)`, `setServer`; packet functions `buildQuery parseReply buildReply`, and `startQuery` / `finishQuery` for programs that run a DNS server themselves |
| `conn` | buffered connections: `conn.open(host, port, ms)` gives a `Connection` with `readLine readExact read readByte write writeLine flush close peer`; `Listener(port)` with `accept(ms)`; `Poller` (`add wait readyTag`) serves many clients in one thread (see `examples/chat_server.a`) |
| `http` | HTTP client and server (section 12a) plus `basicAuth`, `postForm`, `download`, `mimeType`, `serveFile`, `serveStatic(port, dir, count)` |
| `websocket` | RFC 6455: `connect("ws://host:port/path")`, `accept(connection, path, max)`, then `sendText sendBinary ping receive close`; pings are answered, fragments joined, large frames work; the frame functions `buildFrame parseHeader unmask acceptKey` |
| `netutil` | `ping(host, ms)` (ICMP: -1 no answer, -2 not allowed), `tcpPing`, `portOpen`, `wakeOnLan("aa:bb:..")`, `ntpTime(server)` |
| `rawnet` | raw Ethernet frames (Linux and Android, needs root / CAP_NET_RAW): `open("eth0") send recv`, `arping(interface, ip, ms, mac)`, `capture(interface, "dump.pcap", count, ms)` |

```c
import netif;  import netaddr;  import conn;  import websocket;

char mac[6];
if (netif.arpLookup(netaddr.ipParse("192.168.1.1"), mac)) println(netaddr.macToText(mac));    // the system's ARP cache

conn.Connection* c = conn.open("example.org", 80, 5000);
c->writeLine("GET / HTTP/1.0"); c->writeLine(""); c->flush();
char line[256];
while (c->readLine(line, 256) >= 0) println(line);

websocket.WebSocket* ws = websocket.connect("ws://localhost:8081/");
ws->sendText("hello");
```

Limits: IPv4 only for sockets (IPv6 addresses can be parsed and printed), no TLS, no TCP implementation of your own
(`packet` builds the segments; `rawnet` can send them on Linux).

## 12c. The C library

`import clib;` provides the C standard library with its C names and behaviour (`<ctype.h> <errno.h> <limits.h> <locale.h>
<math.h> <setjmp.h> <signal.h> <stdio.h> <stdlib.h> <string.h> <time.h> <wchar.h>` and parts of `<unistd.h>`,
`<sys/stat.h>`, `<dirent.h>`): `malloc free`, `fopen fgets fprintf sscanf popen`, `strtol getenv system qsort`,
`strstr strtok memmove`, `time localtime strftime mktime`, `stat opendir getopt`, `<complex.h>`, and all of `<math.h>` — `sqrt sin cos pow exp
log erf tgamma ...` with **correctly rounded** results — and more. The modules (`cstring`, `cstdio`, `cmath` ...) can also be
imported one at a time. A has no floating point types, so a `double` is an `int` holding the IEEE 754 bit pattern and the
operations are functions (`dadd`, `dmul`, `sqrt`), printed with `printfd("%.3f", x)`. Everything is documented in
[CLIB.md](CLIB.md), including the places where A differs from C.

```c
import clib;

int main() {
    int x = sqrt(dlit("2"));                       // 1.4142135623730951
    printfd("%.17g %s\n", x, strerror(ENOENT));
    FILE* f = fopen("data.txt", "r");
    if (f == null) { perror("data.txt"); return 1; }
    char line[100];
    while (fgets(line, 100, f) != null) { fputs(line, stdout); }
    fclose(f);
    return 0;
}
```

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
| `__winapi(slot, a1, a2, a3, a4)` | call an imported Windows function by import-table slot (returns -1 elsewhere); used by `net` and the C library |
| `__winapix(slot, a1, …, a10)` | the same with up to ten arguments |
| `setjmp(buf)` / `longjmp(buf, value)` | non-local jump: `buf` is an array of 4 ints (`int env[4];`); `setjmp` returns 0, `longjmp` makes it return again with `value` (1 if 0). The frame that called `setjmp` must still be active |
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

* Classes with methods, constructors and `public` / `private`; modules (`import`) as well as the C-style `#include`.
* `int` is 64-bit; `char` is unsigned; `bool` is a real type.
* All variables start zeroed; `new` returns zeroed memory; `new` has no `free` (`malloc` / `free` come with `cstdlib`).
* Functions may be used before their definition without prototypes.
* `const NAME = value;` declares a compile-time constant.
* No unsigned arithmetic or bit-fields. Function pointers exist as the type `func`; parameters can have default values.
* Structs can be passed and returned by value (a hidden copy), `typedef`, `union`, `static` locals, default values (also text) and
  variadic functions (`...` with `va_arg`) exist; unsigned arithmetic and bit-fields do not. A C-style preprocessor (`#define`, `#include`, `#if` ...) is built in, and units can be compiled separately and linked (`ac -c`).
* `switch` labels must be constant expressions (like C), and `case` values must fit in 32 bits.
