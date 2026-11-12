# Memory and pointers

A runs close to the machine: there is no garbage collector, no hidden runtime and no bounds checking. In return you always know where a value lives and what it costs. This chapter explains where memory comes from, how pointers work, how to allocate and free memory, and how to jump out of deeply nested code with `setjmp` and `longjmp`.

In this chapter:

- the three places memory lives: stack, globals and heap
- pointers, pointer arithmetic and the relation between arrays and pointers
- `new` and `alloc`, and `malloc` / `free`
- raw bytes with `memcpy`, `memset` and casts
- non-local jumps with `setjmp` and `longjmp`

## Where values live

| Place | What lives there | Lifetime |
|---|---|---|
| **Stack** | locals and parameters, 8 MiB | until the function returns |
| **Globals** | `data` (initialised) and zero-filled `bss` | the whole program |
| **Heap** | `new`, `alloc`, `malloc`, `calloc`, `realloc` | until the program ends, or until `free` |

Pointers are plain addresses: 8 bytes, with no information about what they point to or how much memory is there. A does not check array bounds, and it does not stop you from using memory after it was freed. The compiler checks types and access, not memory.

## Pointers

A pointer holds the address of a value. `&x` is the address of `x`; `*p` follows the pointer `p` to the value; `T*` is the type "pointer to `T`". A pointer to a pointer is `T**`. Passing a pointer to a function lets the function change the caller's variable (an **output parameter**).

{{sample lang/pointers}}

What to notice:

- `p` held the address of `n`, so `*p = 20` changed `n`.
- `**pp` follows two pointers. `int** pp = &p;` is how you pass a pointer by reference.
- `swap(&a, &b)` works because the function receives addresses. Without the `&` it would swap copies.
- `null` is the pointer that points to nothing. Following it (`*none`) crashes the program with a segmentation fault; test pointers that may be `null`.

## Pointer arithmetic

Adding an integer to a pointer moves it by that many **elements**, not bytes: for an `int*` the step is 8 bytes, for a `char*` it is 1, for a `uint16*` it is 2. Subtracting two pointers gives the number of elements between them. Pointers of the same array can be compared with `<`, `>`, `==` and so on. `p[i]` is the same as `*(p + i)`.

{{sample lang/pointer_arith}}

What to notice:

- `*(p + 1)` and `p[2]` are the same kind of expression; `p[-1]` reaches the element before `p`.
- `p - start` is 4: elements, not bytes. Converting pointers to `int` shows the byte distances: moving the `char*` two steps is 2 bytes, and one step of the `uint16*` is also 2 bytes.
- Arithmetic never checks the range. `p + 100` is a valid pointer value that points to whatever is there.

## Arrays and pointers

An array name used as a value is the address of its first element: it **decays** to a pointer. When you pass an array to a function, the function gets only the pointer, so the length has to be passed along. `&data[2]` is a pointer into the middle of an array, which makes slices easy.

{{sample lang/arrays_pointers}}

What to notice:

- `sum(&data[2], 3)` added the elements 3, 4 and 5 (indices 2, 3, 4): a pointer plus a count is a slice.
- `sizeof(data)` is 48 in `main`, but `sizeof(values)` inside the function is 8: a parameter is just a pointer.
- Strings are `char` arrays ended by a zero byte, so functions walk them until the zero. `&s[3]` is the string starting at the fourth character.

## The stack

Every function call gets a **frame** on the stack for its parameters and local variables. The frame disappears when the function returns, so a pointer to a local must not be used after that. The stack is 8 MiB on Linux and Android and is set to the same size in Windows executables. Deep recursion and big local arrays use it up; when it is full the program crashes (a segmentation fault).

{{sample lang/stack_locals}}

What to notice:

- `sumTo(100)` used 100 frames of 32 KiB each, about 3 MB of stack, and that worked. The same recursion with 255 levels (8 MiB / 32 KiB is about 256) overflowed the stack and crashed in a test.
- `local` was a stack array and is gone after `greeting` returns. The function copied the text into heap memory from `alloc` and returned **that** pointer.
- Returning the address of a local (`return local;`) is a bug that the compiler does not catch.

## The heap: new and alloc

`new Type` and `alloc(n)` take memory from the heap. The heap is a 64 MiB region inside the program and, when that is used up, further blocks that the operating system provides. All of it is **zeroed**, and **`new` and `alloc` never free**: the memory lives until the program ends. The allocator is a plain bump pointer, so it is very fast and never fragments, which suits compilers, tools and short-lived programs.

{{sample lang/heap_new_alloc}}

What to notice:

- `new Point` and `alloc(n)` returned zeroed memory: the first line shows four zeros. `alloc` returns a `char*`; cast it for other types: `(int*) alloc(5 * sizeof(int))`.
- Blocks follow each other, rounded up to a multiple of 16 bytes: 10 bytes took 16, 17 bytes took 32. A hundred thousand 16 byte blocks used 1,600,000 bytes. This is an implementation detail, shown here so that you can see what a bump allocator does.
- Allocating is as cheap as incrementing a pointer. Reading a whole file with `readFile` or all input with `readAll` also takes its memory from the heap.
- A program that runs for hours and keeps allocating will eventually run out of memory. For those programs use `malloc` and `free`.

## malloc and free

The `cstdlib` module (part of the C library, see [chapter 19](#chap-standard-prelude)) has a **real allocator**: `malloc(n)` returns memory that you hand back with `free(p)`, `calloc(count, size)` returns zeroed memory, and `realloc(p, n)` changes the size of a block and keeps its contents. Freed blocks are reused.

{{sample lang/malloc_free}}

What to notice:

- `malloc` does not zero the memory; `calloc` does. Neither is checked against your use: write only inside the `n` bytes you asked for.
- `realloc` may move the block, so always assign its result back to the pointer.
- `defer free(values);` releases the memory on every way out of the function. Declare the `defer` right after the allocation (see [chapter 13](#chap-control-flow)).
- After `free(p)` the pointer is invalid but not `null`. Using it is a bug the language does not detect. Set it to `null` yourself if it stays in scope.
- The loop of 100000 allocations and frees reuses the same block over and over, so the memory does not grow. Only blocks from `malloc`, `calloc` and `realloc` may be passed to `free`; memory from `new` and `alloc` cannot be given back.

## Raw bytes

`memset(dst, value, n)` fills `n` bytes, `memcpy(dst, src, n)` copies `n` bytes. A cast to `char*` or `uint8*` lets you look at the bytes of any value.

{{sample lang/memory_bytes}}

What to notice:

- `memcpy((char*) &q, (char*) &p, sizeof(Pair))` copied a whole struct; the cast changes the pointer type only. For a struct, `q = p;` does the same job.
- The bytes of `0x04030201` are 1, 2, 3, 4: x86-64 is **little endian**, the least significant byte comes first.
- `memcpy` copies forward. Do not use it for overlapping ranges.

## setjmp and longjmp

`setjmp(buf)` saves the current position in `buf`, an array of 4 `int`s, and returns 0. A later `longjmp(buf, value)`, from this function or from any function it has called, jumps back so that **`setjmp` returns again**, this time with `value` (1 if you pass 0). It is the way to abandon deeply nested work: an exception without special syntax. The function that called `setjmp` must still be active.

{{sample lang/setjmp_longjmp}}

What to notice:

- `setjmp` returned 0 first. `deep(0)` recursed until `fail(7)` called `longjmp(env, 7)`; control returned to the `setjmp` line, now with the value 7, and `deep` never finished (`not reached` was not printed).
- A `longjmp` with the value 0 returns 1 from `setjmp`: that is how the second block ended up with `last value 1`.
- Nothing is cleaned up on the way: deferred expressions of the skipped frames do not run, and memory that the skipped functions allocated with `malloc` is not freed. Use it for error recovery at a few well-chosen places, not as a general control structure.
- Several `jmp_buf`-style arrays can be active at once, which makes nested handlers possible.

## Summary

- Stack: locals, 8 MiB, gone when the function returns. Globals: the whole program. Heap: `new`, `alloc`, `malloc`.
- `&x` takes an address, `*p` follows it, `T*` is the type; pointer arithmetic is scaled by the element size and not range checked.
- An array decays to a pointer to its first element; pass the length separately.
- `new` and `alloc` give zeroed memory from a fast bump allocator and never free it; `malloc`, `calloc`, `realloc` and `free` (from `cstdlib`) can reuse memory.
- `defer free(p);` is the safe way to pair an allocation with its release.
- `memcpy` and `memset` work on raw bytes; casts to `char*` or `uint8*` show the bytes of a value.
- `setjmp` and `longjmp` jump out of nested calls and skip all cleanup.

## Where next

- [Preprocessor and assembly](#chap-preprocessor-and-assembly) shows the lowest level of the language: macros and machine code.
- [The standard prelude](#chap-standard-prelude) lists the string and memory functions every program has.
- The [API reference of cstdlib](#api-cstdlib) lists the allocation functions and more.
