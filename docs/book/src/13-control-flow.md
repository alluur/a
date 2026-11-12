# Control flow

Control flow decides which statements run, and how often. A has the statements you know from C: `if`, `while`, `do`, `for`, `switch`, `break`, `continue`, `goto` and `return`. It adds two that move decisions to compile time or to the end of a function: `static if` and `defer`.

In this chapter:

- `if`, `else if` and `else`
- `while`, `do ... while` and `for`
- `break` and `continue`
- `switch` with fall-through
- `goto` and labels
- `defer`, for cleanup
- `static if`, for decisions made while compiling

## if and else

`if (condition) statement` runs the statement when the condition is true. The condition is any integer or pointer: zero and `null` are false, everything else is true. (A `double` also works: it is false when it equals 0.) Add `else` for the other case; `else if` chains several tests. The body of `if`, `else`, `while` and `for` is either a single statement or a `{ block }`.

{{sample lang/if_else}}

What to notice:

- The chain is tested from the top, and the first true condition wins: 83 is not at least 90, but it is at least 80, so the grade is `B`.
- `if (x > 3) println(...)` needs no braces. A block is clearer as soon as a second statement is added, and it avoids the classic mistake of indenting a statement that is not part of the `if`.
- A number or pointer is a condition by itself: `if (x)` means `if (x != 0)`.

## while

`while (condition) body` tests the condition **before** each round, so the body may never run.

{{sample lang/while_loop}}

What to notice:

- The Collatz loop needs 111 rounds for 27, and no counter is needed in the loop head: the condition says when to stop.
- When the condition is false from the start (`never < 5` is false for 10), the body is skipped completely.
- `value /= 10` counts the digits of a number: a typical `while` that shrinks its variable until it reaches 0.

## do ... while

`do body while (condition);` tests **after** each round, so the body runs at least once. Note the semicolon after the closing parenthesis.

{{sample lang/do_while}}

What to notice:

- The second loop ran its body once although `n < 5` was false.
- The last block shows when this matters: producing the digits of 0 must produce one digit, "0". A `while (value > 0)` loop would produce none.

## for

`for (init; condition; step) body` has three parts. `init` runs once; the `condition` is tested before each round; `step` runs after each round. Each part may be empty, and `init` may declare a variable that lives only in the loop.

{{sample lang/for_loops}}

What to notice:

- The step can be any expression: `i -= 3` counted down.
- `for (; j < 3; )` leaves out `init` and `step`; `for (;;)` has no condition and runs until a `break` or a `return`.
- The comma operator runs two expressions in one part: `a += 3, b -= 3`. The loop variables `a` and `b` are declared together in the `init` part.
- A variable declared in the head belongs to the loop: using `i` after the loop is the compile error `undeclared identifier 'i'`.

## break and continue

`break` leaves the innermost loop (or `switch`). `continue` skips the rest of the current round and starts the next one. In a `for` loop, `continue` still runs the step expression.

{{sample lang/break_continue}}

What to notice:

- The first loop skipped the even numbers with `continue` and stopped at 9 with `break`, so it printed 1 3 5 7.
- The inner `break` left only the inner loop; the outer loop continued with the next row.
- A search loop that records the position and `break`s is the usual pattern.

## switch

`switch (value)` jumps to the `case` whose label equals the value, or to `default` when there is none. Labels are **constant expressions** (numbers, characters, `const` names, enum members) of any size. Using a variable as a label gives `name is not a constant`. A label can also be a list (`case 1, 2:`), a range (`case 'a'..'z':`) or a text; those are in [More language features](#chap-more-language-features).

Execution **falls through**: after the matching case runs, it continues into the next one unless a `break` (or `return`) stops it. Two labels in a row share the same code.

{{sample lang/switch_basic}}

What to notice:

- `case 1:` and `case 2:` share one result because `case 1:` has no code of its own.
- The `level` switch shows the fall-through: it started at `case 3` and ran through `case 2` and `case 1` until the `break`. `case 0` was never reached.
- Inside a `switch` that is inside a loop, `continue` belongs to the loop: `case 1: continue;` skipped the rest of that round, including `[after 1]`. `break` leaves only the `switch`, so `[after 3]` was still printed.
- `switch` compares integers (including `char` and enum values). When the value is a `char*`, the labels are compared as **text** (the compiler used to compare addresses, which is why older programs use `if` with `streq`); see [More language features](#chap-more-language-features).

## goto

`goto label;` jumps to `label:` in the same function, forwards or backwards. Labels belong to a function (at most 64 of them) and a label name may be used only once in a function (two functions may use the same name). A `goto` to a label that does not exist is the error `goto to a label that is not defined in this function`; a second label with the same name is `duplicate label`.

{{sample lang/goto_demo}}

What to notice:

- The first function uses `goto again` as a loop and `goto found` / `goto missing` as exits. The same function is easy to write with `for` and `return`, which is clearer; use `goto` when it removes complexity.
- The nested loops are the classic good use: `goto done` leaves **both** loops at once, where a plain `break` would leave only one.

## defer

`defer expression;` postpones the expression until the function returns, whether through `return` or by reaching the closing brace. Deferred expressions run **last in, first out**, after the return value has been computed, and they may use every local declared before the `defer`. It is meant for cleanup: closing a file, freeing a block, leaving a lock.

{{sample lang/defer_demo}}

What to notice:

- Both `process` calls printed their deferred lines, including the early `return -1`. The order is reversed: the expression deferred last runs first.
- In `measure`, the result 20 was computed first, then `total += local` ran with the **current** value of `local` (10, not the 5 it had at the `defer`).
- `defer` is only allowed directly in a function body, not inside `if`, loops or other blocks (`defer is only allowed directly in a function body`), and at most 16 per function (`too many defer statements in one function (16)`).
- Only an expression can be deferred, typically a function call. To defer several steps, wrap them in a small function.

## static if

`static if (constant) { ... } else { ... }` is decided **while compiling**. The branch that is not chosen is skipped: it may name things that do not exist on the current target and is never compiled. It works around declarations at file level and around statements inside function bodies. It does not work between the members of a class: a `static if` in a class body is an error (`unknown type`). Both branches need braces (`static if (X) stmt;` is the error `expected '{' after static if (...)`). The condition is a constant expression, and a variable is rejected with `name is not a constant`: your own `const` values, or the built-in constants `__ARCH` (0 x86-64, 1 ARM64, 2 RISC-V 64, 3 LoongArch 64) and `__OS` (0 Linux, 1 Windows, 2 Android). The standard prelude itself uses `static if (__ARCH == 0)` to pick faster x86-64 routines.

{{sample lang/static_if}}

What to notice:

- The functions `osName` and `bits` are defined once, in the form the target needs. The unchosen `bits` body calls a function that is declared nowhere: it is never compiled, so no error.
- Inside `main`, `static if` selects statements, like `#if` would in C, but it is part of the language and understands your `const` names.
- Compare this with the preprocessor in [chapter 18](#chap-preprocessor-and-assembly): use `static if` and `const` for decisions about the target or build mode, and macros only for code that has to be textually different.

## Summary

- `if`, `else if` and `else` test integers and pointers; zero and `null` are false.
- `while` tests before each round, `do ... while` after it, `for` has init, condition and step, each of them optional.
- `break` leaves the innermost loop or `switch`; `continue` starts the next round of the innermost loop.
- `switch` labels are constant expressions; without `break` execution falls through. A switch on a `char*` compares text.
- `goto` and labels work within one function. To leave nested loops, a labeled `break` is the cleaner way ([More language features](#chap-more-language-features)).
- `defer` runs an expression at function exit, last in first out, at most 16 per function and only at the top level of the body.
- `static if` selects code at compile time using constants such as `__ARCH` and `__OS`. It works at file level and in function bodies, not inside a class body.

## Where next

- [More language features](#chap-more-language-features) adds `foreach`, the text `switch`, labeled `break` and `continue`.
- [Functions](#chap-functions) covers parameters, results, recursion and function pointers.
- [Preprocessor and assembly](#chap-preprocessor-and-assembly) has the C-style `#if` for text-level decisions.
- [Memory and pointers](#chap-memory-and-pointers) shows `defer` together with `malloc` and `free`.
