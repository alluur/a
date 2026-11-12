# Functions

A function gives a name to a piece of work. In A, functions are plain and fast: arguments are passed by value, there is no overloading, and the compiler needs no prototypes. Around them are several tools that make them more useful: default parameter values, variable argument lists, function pointers, `static` locals and structs passed by value. This chapter also covers the data constructs that appear in function code (`typedef`, `union`, initializer lists, compound literals) and the C syntax that A accepts.

In this chapter:

- defining and calling functions, default values, recursion
- structs by value, variable argument lists, function pointers
- `typedef`, `static`, `private` and `union`
- initializer lists, designated initializers and compound literals
- more C syntax that works in A

## Defining and calling functions

A function has a result type, a name, a parameter list and a body: `int add(int a, int b) { return a + b; }`. The result type `void` means that nothing is returned. Parameters and results are passed **by value**: the callee gets copies. Allowed types are integers, `char`, `bool`, `double`, enums, pointers, `func`, and structs and classes.

{{sample lang/functions_basic}}

What to notice:

- `later()` calls `helper()` before it is defined, and `main` calls `multiply` whose definition comes last. Order does not matter.
- A function that reaches its end without `return` returns 0: `noReturn(21)` printed 0. `return;` in a `void` function (or in any function) also returns 0.
- A prototype such as `int multiply(int a, int b);` is accepted, but never necessary.
- Arguments are evaluated from left to right, so `add(add(1, 2), add(3, 4))` is well defined.
- There is **no overloading**: one name, one function. Two functions of the same name are the error `redefinition of 'add'`. This includes the names the prelude already uses: you cannot define your own `max`, `min`, `find` or `strlen` at the top level (`redefinition of 'max'`). Inside a module or a class the same names are fine.
- `private int helper() { ... }` (or `static`) makes a function invisible outside its own file; see [modules](#chap-enums-and-modules).

## Default parameter values

A parameter can have a default value: a constant expression (a number, a character, `true`, `false`, `null`, a `const` name, an enum member, or arithmetic on them) after `=`. Parameters with defaults must come last, and a call may leave out trailing arguments that have defaults. The same works for methods and constructors, and it is how `printf` takes up to eight values.

{{sample lang/default_params}}

What to notice:

- `area(5)` is `area(5, 1, 100)`. You cannot skip a parameter in the middle: to give `scale` you must also give `h`.
- Text defaults work: `char* greeting = "Hello"`.
- A default that is not a constant is an error (`name is not a constant`); so is a parameter without a default after one that has one (`parameters after one with a default value need default values too`); and a function cannot have both default values and `...`.

## Structs by value

A struct or class can be a parameter and a result. The caller makes a copy for the callee, so changes to the parameter do not reach the original. A struct result is returned through a hidden destination in the caller's frame, so `add(a, b).x` works and `Point q = add(a, b);` copies the result.

{{sample lang/struct_by_value}}

What to notice:

- `shift(p)` changed only its copy: `p.x` stayed 9. `shiftInPlace(&p)` took a **pointer** and changed the original.
- Calls nest: the result of `make` is a temporary that `add` receives as an argument.
- Copying a big struct on every call costs time. For large structs that a function only reads or changes, pass a pointer.
- Calling a struct-returning function through a `func` pointer is not supported. The compiler does not stop you, but the program crashes.

## Variable argument lists

A parameter list can end in `...`. Inside such a function, `va_count()` is the number of extra arguments and `va_arg(i)` is the i-th one, counting from 0. Both exist only in a function declared with `...`; anywhere else they are the compile error `va_arg and va_count can only be used in a function declared with ...`.

{{sample lang/varargs_sum}}

What to notice:

- All extra arguments are 64-bit values: numbers, characters, pointers (strings included), doubles as bit patterns.
- There is **no check** that `i` is below `va_count()`; the loop must stay within the count.
- `logf` shows how to make your own `printf`: copy the extras into an array and hand it to `vformat` (see [first programs](#chap-first-programs)).
- A function with `...` cannot be a method, cannot have default values, and cannot be called through a `func` pointer or used as a value (`a function with ... cannot be used as a value`).

## Function pointers

`func` is the type of a function pointer. The name of a function, or `&name`, is a `func` value. Calling a `func` variable, field, array element or parameter calls the function it points to. A `func` carries **no signature**: the compiler does not compare the arguments with the function's parameters, and the call returns an `int` (the result as a 64-bit value).

{{sample lang/func_pointers}}

What to notice:

- `apply(&square, 9)` and `apply(square, 9)` are the same.
- A `func` can be a variable, an array element (`table[1](7)`) or a field of a struct (`cmds[i].run(5)`); this is how you build tables of commands or callbacks.
- Function pointers can be compared with `==`.
- Only ordinary functions have an address: not methods, not functions with `...`, and not the built-in `__...` runtime functions. The C library functions `qsort`, `bsearch` and `atexit` (module `cstdlib`) and `signal` (module `cunistd`) take `func` arguments.

## Recursion

A function may call itself. Each call has its own parameters and locals on the **stack**, which is 8 MiB by default (on Linux the operating system decides; see [memory and pointers](#chap-memory-and-pointers)).

{{sample lang/recursion}}

What to notice:

- `20!` is the largest factorial that fits in a 64-bit `int`: `21!` would wrap around.
- `fib(20)` makes 21,891 calls, and the program ran instantly: calls are cheap.
- `depth(100000)` recursed a hundred thousand levels without trouble. A recursion without an end (or with a huge local array in each frame) runs out of stack, and the program crashes with a segmentation fault; the shell then reports exit code 139.
- Recursion is the natural fit for trees and divide-and-conquer; for a plain counting loop, use `for`.

## typedef

`typedef type Name;` gives another name to a type. It works at the top level and inside functions.

{{sample lang/typedef_demo}}

What to notice:

- `Text` and `PointRef` are only names: `Text` **is** `char*`. Nothing new is created.
- A typedef documents what a type stands for (`Number`, `Index`) and shortens long types such as `char**`.
- For structs you rarely need `typedef`: a `struct Point { ... }` can be used as plain `Point`. The C forms `typedef struct { ... } Point;` and `struct Point p;` are also accepted (see below).

## static and private

Two meanings of `static` here (a third one, inside a class, is in [More language features](#chap-more-language-features): a `static` field or method belongs to the class, not to an object):

- **At the top level**, `static` is the same as `private`: the function or global can only be used inside its own file.
- **Inside a function**, a `static` local keeps its value between calls. It is zero at the start, or set once from its constant initializer before the program starts. It is visible only in its block, and it may be an array.

{{sample lang/static_locals}}

What to notice:

- `next()` returned 101, 102, 103: `calls` survived between calls while `start` was set only once.
- The `counts` array is shared by all calls of `histogram`. Static data makes a function remember things; it also makes it harder to test and not safe to use from several threads.
- A `static` local's initializer must be a constant, as with globals.

## union

A `union` is like a `struct` whose members all share the same memory. Its size is that of the largest member. Use it to look at the same bytes in different ways, or to store one of several alternatives together with a tag that says which one.

{{sample lang/union_demo}}

What to notice:

- `Value` is 8 bytes: the `int`, the 8-byte array and the pointer overlap. `Tagged` is 16 bytes: `kind` plus the 8-byte union.
- Writing `v.number = 0x0102030405060708` and reading `v.bytes` shows the byte order of the processor: x86-64 stores the **least** significant byte first.
- `Tagged` is the standard pattern for a "variant": `kind` says which member is valid. The language does not check that you read the member you wrote.

## Initializer lists

Arrays and structs (locals, globals and `static` locals) can be filled with a `{...}` list. Values that are left out are 0, a trailing comma is allowed, lists nest, and a `char` array can be filled from a string. Too many values (`int a[2] = {1, 2, 3};`) or a string longer than the array is a compile error (`too many values in the initializer list`, `the string is longer than the array`). Lists for globals and `static` locals must be made of constants; local lists may use any expression.

{{sample lang/init_lists}}

What to notice:

- `a[5] = {1, 2, 3}` zeroed elements 3 and 4; `primes[5]` is 0 for the same reason.
- `Line` shows nesting: the inner braces fill `Point` fields, and `"ab"` fills the `char label[4]` field.
- The list for `computed` uses local variables, which is fine for a local array.

## Designated initializers

A designated initializer picks a field by name (`.y = 5`) or an element by index (`[4] = 40`). Whatever follows continues from there, and everything that is not named is 0. Chained designators such as `.a.b = 1` are not supported: write `.a = {.b = 1}`.

{{sample lang/designated_init}}

What to notice:

- Fields can be named in any order, and `Box`'s unnamed field `lo` is zero.
- In `{[1] = 10, [4] = 40, 50}` the 50 follows `[4]`, so it goes to index 5. Slot 0 and the others are 0.

## Compound literals

A compound literal builds a nameless object where you need it: `(Point){6, 7}`, or `(int[]){1, 2, 3}` for an array whose size is counted from the list. It lives until the function returns, and you may take its address. An unsized `(T[]){...}` list must be written without `[index] =` designators.

{{sample lang/compound_literals}}

What to notice:

- A literal can be an argument (`area((Point){6, 7})`), the right side of an assignment, or the target of `&`.
- `sum((int[]){1, 2, 3, 4}, 4)` passes a temporary array without declaring a variable for it.
- `Point* q = &(Point){5, 6};` is valid inside the function; do not return that pointer to the caller, the object ends with the function.

## More C syntax

A accepts several C forms so that existing code ports easily. They all behave as the main syntax described above.

**Comma operator, `sizeof`, C integer words and adjacent strings:**

{{sample lang/c_comma_sizeof}}

What to notice:

- `a = 1, b = 2` evaluates both and has the value of the last one. It works in statements, `for` heads and parentheses, but not between function arguments, where the comma separates arguments.
- `sizeof(x)`, `sizeof x` and `sizeof(expr)` all work (the 7-element `int` array has size 56); the expression is not evaluated and must not contain a call (`sizeof cannot contain a function call`).
- `short`, `long`, `signed`, `unsigned`, `long long`, `unsigned long int` and `long double` are accepted and mean the ordinary A types: all integers are the 64-bit signed `int`, `unsigned char` is `char`, and `long double` is `double`. `sizeof(short)` is 8, and `unsigned u = -1;` stays -1. Use `int16` or `uint16` (and the other `int8` ... `uint64` types) when you need a width or unsigned arithmetic.
- Adjacent string literals are joined, also across lines.

**`typedef enum`, `typedef struct`, the `struct` keyword and `extern`:**

{{sample lang/c_typedef_struct}}

What to notice:

- `typedef struct Node { int val; struct Node* next; } Node;` is the C way to write a self-referencing type; in A a plain `struct Node { int val; Node* next; }` is enough.
- `struct Node* n` and plain `Node* n` mean the same thing; `class`, `union` and `enum` may be used in front of a type name in the same way.
- `extern int counter;` is accepted and ignored in a single program, because the whole program is compiled together and the definition just has to appear somewhere. It matters for [separate compilation](#chap-preprocessor-and-assembly).

**Function pointer declarators:**

{{sample lang/func_pointer_types}}

What to notice:

- `int (*op)(int, int) = add;`, `typedef int (*BinOp)(int, int);` and parameters such as `int (*f)(int, int)` are accepted. They all become the type `func`: the signature is not checked.
- `Ops` shows function pointers as struct fields, both spelled out and through the typedef.

## Summary

- Functions pass parameters and results by value and may be defined in any order; there is no overloading, and prelude names cannot be redefined at the top level.
- A parameter may have a constant default value; parameters with defaults come last.
- Structs and classes can be passed and returned by value; use pointers for large structs or when the callee must change the original.
- `...`, `va_count()` and `va_arg(i)` give variable argument lists; `func` holds a function pointer without a signature.
- `typedef` renames a type; `static` locals keep their value; at the top level `static` means `private`.
- `union` members share memory; initializer lists, designated initializers and compound literals build structs and arrays in place.
- C forms such as `typedef struct`, the comma operator, `sizeof x`, integer words and function pointer declarators are accepted.

## Where next

- [Structs and classes](#chap-structs-and-classes) turns structs into types with methods.
- [Memory and pointers](#chap-memory-and-pointers) explains the stack and the heap behind recursion and `alloc`.
- [Control flow](#chap-control-flow) shows `defer`, which makes cleanup in functions simple.
