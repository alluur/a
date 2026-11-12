# Types and values

A is a statically typed language: every variable, parameter and result has a type that the compiler knows. There are few types, and the sizes are exact, so you always know how much memory a value takes and what happens when a number gets too big. This chapter goes through each type and each kind of literal.

In this chapter:

- the integer types, `char`, `bool`, `void`, pointers and arrays
- the fixed width integers `int8` ... `uint64` and the `size_t` family
- casts, `sizeof` and what happens on overflow
- integer, character, string and boolean literals
- `double`, the floating point type

## The types at a glance

| Type | Size | Notes |
|---|---|---|
| `int` (alias `long`) | 8 bytes | signed 64-bit integer |
| `char` (alias `byte`) | 1 byte | unsigned 8-bit integer, used for text and raw bytes |
| `bool` | 1 byte | `true` / `false`; any value stored in a `bool` becomes 0 or 1 |
| `void` | none | no value; `void*` is a pointer to anything |
| `T*` | 8 bytes | pointer to `T`: `int*`, `char**`, `Node*` |
| `T name[N]` | `N * sizeof(T)` | fixed size array, `N` is a constant expression |
| `struct S`, `class C` | the fields, each aligned to its own size, rounded up to a multiple of 8 | see [structs and classes](#chap-structs-and-classes) |
| `enum E` | 8 bytes | behaves like `int`; `enum E : uint8` picks a smaller type |
| `int8` `int16` `int32` `int64` | 1, 2, 4, 8 bytes | signed integers of exactly that width |
| `uint8` `uint16` `uint32` `uint64` | 1, 2, 4, 8 bytes | unsigned integers |
| `size_t` `uintptr_t` | 8 bytes | `uint64` |
| `ssize_t` `intptr_t` `ptrdiff_t` | 8 bytes | `int64` |
| `double` (alias `float`) | 8 bytes | IEEE 754 binary64 (the usual 64-bit floating point format), see the end of this chapter |
| `func` | 8 bytes | pointer to a function, see [functions](#chap-functions) |

## int and long

`int` is a signed 64-bit integer, and `long` is another name for it. There is no 32-bit `int` as in C: if you port C code, a value that overflowed at 2 billion in C will keep growing here.

{{sample lang/int_types}}

What to notice:

- The largest `int` is 9223372036854775807 (2<sup>63</sup> - 1).
- Overflow is silent: adding 1 to the largest value gives the smallest one, and subtracting 1 from that comes back. The result is always the correct value modulo 2<sup>64</sup>. A is not a language that traps arithmetic overflow, so check ranges yourself where it matters.
- `3037000500 * 3037000500` is a little more than 2<sup>63</sup>, so the product wrapped around to a negative number.

## char and byte

`char` is one **unsigned** byte, with values 0 to 255. It holds characters of text and raw data. `byte` is another name for it. A character literal such as `'a'` is a `char` and is also an integer, so you can calculate with it.

{{sample lang/char_byte}}

What to notice:

- `'a' + 1` is the number 98; printed with `%c` it is the letter `b`.
- A `char` cannot be negative: `200 + 100` is 300 and only the low 8 bits (44) are stored.
- Text is an array of `char` that ends with a zero byte. `println(letters)` prints until it finds that zero. The type of a string literal is `char*`.

## bool

`bool` holds `true` or `false`. It takes one byte, and whatever you store in it is reduced to 0 or 1, so `bool b = 25;` stores 1. Comparisons and `!`, `&&`, `||` always produce 0 or 1.

{{sample lang/bool_type}}

What to notice:

- `printf` shows booleans as numbers; `printBool` writes the words `true` and `false`.
- `(bool) 256` is 1: unlike a cast to `char`, a cast to `bool` tests whether the value is non-zero.

## void and null

`void` as a result type means "no value". `void*` is a generic pointer: any pointer converts to it, and a cast converts it back. `null` is the null pointer, the pointer to nothing. Every integer or pointer can be used as a condition: zero and `null` are false, everything else is true.

{{sample lang/void_null}}

What to notice:

- `(int) nothing` is 0: `null` is the number zero. Pointers that are not initialised are `null`, because every variable starts as zero.
- `if (!nothing)` is the usual way to test for `null`; `nothing == null` says the same thing more explicitly.
- Dereferencing a `null` pointer crashes the program (a segmentation fault on Linux). A gives no warning, so test before you follow a pointer that may be `null`.

## Fixed size arrays

`T name[N]` is an array of `N` elements stored next to each other. `N` must be a constant expression: a number, a `const`, `sizeof`, or arithmetic on them. A variable is not allowed (`int a[n]` is the compile error `name is not a constant`); for sizes only known at run time use `alloc` (see [memory and pointers](#chap-memory-and-pointers)). Arrays are zeroed when they are created, indices start at 0, and A does not check them.

{{sample lang/fixed_arrays}}

What to notice:

- `sizeof(primes) / sizeof(primes[0])` is the number of elements. This only works on the array itself.
- The initializer `{2, 3, 5, 7, 11}` filled five of the six elements; the last one is 0. A `char` array can be filled from a string: `char name[16] = "Aytict";`.
- When an array is used as a value it **decays** to a pointer to its first element: `int* first = squares;`.
- There are no multi-dimensional arrays (`int grid[3][4]` is a syntax error). Use one array of `rows * cols` elements and compute the index, or an array of pointers.

## Fixed width integers

When the width matters (file formats, network protocols, hardware) use `int8`, `int16`, `int32`, `int64` and `uint8`, `uint16`, `uint32`, `uint64`. They have exactly the size in their name in variables, struct fields, arrays, pointers, parameters and results. Struct fields are naturally aligned: a `uint16` starts at an even offset, a `uint32` at a multiple of 4, and the size of a struct is rounded up to a multiple of 8.

{{sample lang/sized_ints}}

What to notice:

- A value is cut to the width of the type when it is **stored**: `uint8 b = 300` keeps 44, `int8 s = 200` becomes -56. Reading a signed type **sign-extends** it (the value keeps its sign when it is widened to 64 bits: -56 stays -56), reading an unsigned type **zero-extends** it (the new upper bits are zero).
- `w - 1` is calculated as a plain `int` (the literal `1` is one), so it is -1, and the store cuts it to 32 bits: 4294967295. When **both** operands are the same 32-bit type (`uint32 - uint32`, `int32 + int32`) the result itself is cut to 32 bits. `int8`, `int16` and `uint16` are promoted to `int` in arithmetic, as in C: `u + 1` is 65536 and becomes 0 only when it is stored into a `uint16`.
- A `uint64` makes division, remainder, right shift and comparisons unsigned. `printf("%d")` shows a `uint64` above 2<sup>63</sup> as a negative number; use `%u` for those.
- `Header` is 24 bytes: `kind` is at offset 0, `length` at 2, `id` at 4, `delta` at 8, `offset` at 10, `code` at 12 and `stamp` at 16. Each field sits at a multiple of its own size.
- `short`, `long`, `signed` and `unsigned` are accepted but mean plain 64-bit `int`: use the names above whenever the width matters.
- Integer literals may carry the C suffixes `u`, `l`, `ul`, `ull`: they are accepted and ignored, every literal is a 64-bit `int`.

## size_t, uintptr_t and friends

`size_t` and `uintptr_t` are names for `uint64`; `ssize_t`, `intptr_t` and `ptrdiff_t` are names for `int64`. They document the purpose of a value: a size or count, a pointer stored as a number, or the distance between two pointers.

{{sample lang/size_types}}

What to notice:

- All five are 8 bytes. Subtracting two pointers gives the distance in **elements**, not bytes.
- `(size_t) -1` is the largest `size_t`: unsigned values compare as large numbers.
- A pointer can be turned into an integer and back with a cast. This is for tools and system code, not for everyday work.

## Casts

A cast, written `(type) value`, converts a value. A cast to a narrower integer type truncates, a cast to a wider type extends, and `(bool)` tests for non-zero. Pointers can be cast to any other pointer type and to and from integers: nothing in the value changes, only the way the compiler looks at it.

{{sample lang/casts}}

What to notice:

- `(char) 0x1234ABCD` keeps the low byte, `0xCD` = 205. `(int8)` reads the same byte as signed: -51.
- `(uint16) -1` is 65535 and `(uint32) -1` is 4294967295: the cast first truncates, then extends as the type requires.
- Widen before you calculate when you need the extra range: `(int) small + 10` is 260, but storing 260 in a `uint8` would give 4.
- Assigning a wider integer to a narrower variable (`char c = 300;`) is allowed without a cast and truncates in the same way.

## sizeof

`sizeof(Type)` and `sizeof(expression)` (also without parentheses: `sizeof x`) give the size in bytes. For an array name the result is the size of the whole array. The expression is not evaluated, and it must not contain a function call.

{{sample lang/sizeof_demo}}

What to notice:

- `Mixed { char tag; int value; char flag; }` takes 24 bytes: each `int` field sits at a multiple of 8, and the struct is padded to a multiple of 8.
- `sizeof(numbers) / sizeof(numbers[0])` counts the elements; `x` is still 5 after `sizeof(x + 1)` because nothing is evaluated.
- An array that is a **field** of a struct cannot be measured with `sizeof(s.field)`; use `sizeof(Type)` of the element type and the declared length.

## Integer literals

| Kind | Examples |
|---|---|
| decimal | `42`, `1_000_000` |
| hexadecimal | `0xFF`, `0xDEADBEEF` |
| binary | `0b1010` |
| character | `'a'`, `'\n'`, `'\0'`, `'\x41'` (type `char`) |
| boolean | `true`, `false` |
| null pointer | `null` |

Underscores in numbers are ignored, so `1_000_000` is easier to read than `1000000`. A literal is a 64-bit integer; the suffixes `u`, `l`, `ul`, `ull` are accepted and ignored.

{{sample lang/literals}}

What to notice:

- `-0x10` is the negation of 16. A minus sign is an operator, not part of the literal.
- A character literal is a number: `'0'` is 48, `'A'` is 65, `'\x41'` is also 65.
- The quote that is not the delimiter needs no escape: `'"'` and `"it's"` are fine; `'\''` and `"\""` are the escaped forms.

## String literals and escapes

A string literal such as `"hello\n"` has the type `char*` and ends with a zero byte. The escape sequences are:

| Escape | Character |
|---|---|
| `\n` `\t` `\r` | newline, tab, carriage return |
| `\0` | the zero byte |
| `\e` | escape (27) |
| `\\` `\"` `\'` | backslash, double quote, single quote |
| `\xHH` | the byte with the hexadecimal value `HH` (exactly two digits) |

Two or more literals next to each other are joined into one, also across lines.

{{sample lang/string_escapes}}

What to notice:

- Each escape stands for **one** character: the table of numbers (`10 9 13 0 27 92`) shows their values. `\x` needs exactly two hex digits, and any escape not in the table (`\a`, `\b`, `\101`, `\u0041` ...) is the compile error `invalid escape sequence`.
- `strlen` counts the characters before the zero byte, so a `\0` inside a string literal ends it as far as the string functions are concerned.
- `editable` is an array that was filled from a literal, so it is your own copy and you may change it. The literal itself also sits in writable data, but do not modify literals, and do not rely on two equal literals sharing, or not sharing, the same address.

## Floating point with double

`double` is an IEEE 754 binary64 number, the same format as the `double` of C, and `float` is another name for it: both are 8 bytes. The compiler calls a built-in **software** implementation (the module `dfloat`, loaded only when a program uses a floating point value), so results are bit for bit identical on every processor and system. The price is speed: every operation is a function call, much slower than a hardware instruction, which is fine for tools, simulations and plots, but not for heavy number crunching. This section stays at the language level; [the numbers chapter](#chap-numbers) goes deeper into `double`, `dfloat` and `dmath`.

### Literals, conversions and operators

A floating point literal has a decimal point or an exponent: `1.5`, `2e-3`, `1_000.25`. It is rounded exactly (to nearest, ties to even), like a C compiler does. An `int` in a mixed expression is converted to `double`. Assigning a `double` to an `int` needs a **cast**, which truncates toward zero. The operators `+ - * /`, unary `-`, the six comparisons, `+= -= *= /=`, `++`, `--`, `?:` and the truth test (`if (d)` is true when `d != 0`) all work.

{{sample lang/double_values}}

What to notice:

- `n * a` converts `n` first; `n / 2` divides two `int`s **before** the conversion, so it is 1, not 1.5. Write `n / 2.0` for a real division.
- `(int) -7.75` is -7: truncation toward zero, not rounding down. `(int) 7.9` is 7.
- Comparisons give 0 or 1, and may mix `int` and `double` (`n > 2.5`).
- `total++` adds 1.0.
- `float` and `double` are the same type, so `sizeof(float)` is 8.

### Doubles in data

A double can be a variable, a global, a struct field, an array element, a parameter and a result, like any other type. A pointer to `double` steps by 8 bytes.

{{sample lang/double_data}}

What to notice:

- `v.x = 3;` converted the `int` 3 to `3.0` when it was stored.
- `dot` receives two structs by value, and `scaled` returns a struct of doubles: all the rules of [the functions chapter](#chap-functions) apply.
- `samples[i] = i * 0.25;` is an `int` times a `double`: the result is a double.

### Printing, parsing and inspecting

`printf` from the prelude does not understand `%f` (it prints the two characters `%f` as they are). Use the double helpers: `printlnDouble(d)` and `printDouble(d)` write the **shortest text that reads back as exactly the same number**; `doubleToText(d)` returns the same text as a string; `doubleToFixed(d, n)` rounds to `n` decimals; `doubleToSci(d, n)` writes scientific notation; `parseDouble(text)` reads a number; `isNaN`, `isInf` and `isFinite` classify a value. `__bits(d)` returns the 64 raw bits of a double as an `int`, and `__dbl(i)` builds a double from 64 bits.

{{sample lang/double_text}}

What to notice:

- `0.1 + 0.2` prints as `0.30000000000000004`, and `2.0 / 3` as `0.6666666666666666`: those are the shortest texts that identify the numbers. Binary floating point cannot hold 0.1 exactly; every IEEE system behaves like this.
- Division by zero gives infinity and `inf - inf` is **NaN** ("not a number"). A NaN is not equal to anything, not even itself: `nan == nan` is 0. Use `isNaN`.
- `__bits(1.0)` is `3ff0000000000000`. Adding 1 to the bits of `1.0` gives the next larger double, `1.0000000000000002`.
- The C library functions `printfd`, `sprintfd` and the like (module `cfloat`, which a program that uses `double` loads automatically) understand `%f %e %g %a` but take **bit patterns**, not doubles. With `double d = 2.5;`, `printfd("%.2f\n", __bits(d))` prints `2.50`, but `printfd("%.2f\n", d)` prints `0.00`: the parameters are `int`, so `d` is first converted to the integer 2 and that is read as a bit pattern (a tiny number). There is no warning.

### Mathematics

The mathematical functions live in the `dmath` module: `sqrt cbrt pow exp exp2 expm1 log log2 log10 log1p hypot sin cos tan asin acos atan atan2 sinh cosh tanh asinh acosh atanh floor ceil round trunc fabs fmod fmin fmax copysign`, the constants `PI E TAU SQRT2 LN2 LN10 INFINITY EPSILON`, and `nan()`. They are the functions of C's `<math.h>`, computed in software: `sqrt` is exact and the others are within 1 unit in the last place (nearly always correctly rounded), the same on every processor.

{{sample lang/double_math}}

What to notice:

- Call them with the module name: `dmath.sqrt(2)`. `import dmath;` does **not** bring the bare names into scope: `PI` alone is the compile error `undeclared identifier 'PI'`.
- A bare `sqrt(...)` is a different function, and it compiles without a warning. Names that are declared in a `module` are reached as `module.name`; a name from a file without a `module` line is global and can be written bare. The C library module `cmath` has no `module` line, so its `sqrt` is the global `sqrt`. It is loaded automatically in every program that uses `double` (and by `import dmath;`), and it takes and returns an `int` that holds a **bit pattern**. `sqrt(2.0)` therefore converts `2.0` to the integer 2, takes the square root of that bit pattern, and hands back the bits of the answer as an `int`, which `printlnDouble` then shows as the number `2.1906148709472164e+18`: nonsense. `dmath.sqrt(2.0)` prints `1.4142135623730951`. Inside `dmath` every function is just `__dbl(::sqrt(__bits(x)))`: it feeds the bits to the global function (`::name` means "the global name") and turns the answer back into a `double`.
- The functions take `int` arguments too, as in `dmath.sqrt(2)`: the compiler converts them to `double`.
- `dmath.round(area)` is a `double` (`20.0`); the `(int)` cast makes it an integer.
- `sin(PI / 6)` is `0.49999999999999994`, as in C: the result is exact for the rounded input, which is not exactly pi / 6.

::: note

Older parts of the C library reference describe a double as an `int` that holds the bit pattern, handled by functions such as `dlit("2.5")`, `itod(1)` and `dadd(a, b)`. Those functions still exist, and `printfd` still expects bit patterns, but with the `double` type you can simply write `a + b`.

:::

## Summary

- `int` and `long` are signed 64-bit and wrap around on overflow; `char` and `byte` are unsigned 8-bit; `bool` is 0 or 1.
- `T*` is a pointer, `void*` points to anything, `null` points to nothing and is false in a condition.
- `T name[N]` is a fixed size array with a constant size; arrays decay to pointers, are zeroed and are not bounds checked.
- `int8` ... `uint64` have exactly the size in their name; values are cut to the width when stored and arithmetic on 32-bit pairs wraps at 32 bits.
- `size_t` is `uint64`; `ssize_t`, `intptr_t` and `ptrdiff_t` are `int64`.
- A cast `(type) x` truncates, extends or reinterprets; `sizeof` gives sizes in bytes at compile time.
- Literals: `42`, `0xFF`, `0b1010`, `1_000`, `'a'`, `"text\n"`, `true`, `false`, `null`; adjacent strings are joined.
- `double` (alias `float`) is IEEE 754 binary64, done in software: identical on every target, but not fast. Mix it with `int` freely, cast with `(int)` to truncate, print with `printlnDouble` or `doubleToFixed`, and call the maths functions as `dmath.sqrt(x)`.

## Where next

- [Variables and operators](#chap-variables-and-operators) shows how to declare and combine values.
- [Memory and pointers](#chap-memory-and-pointers) goes deeper into pointers and the heap.
- [The numbers chapter](#chap-numbers) covers `double`, `dfloat` and `dmath` in depth; the [API reference of dmath](#api-dmath) lists the functions.
