# Variables and operators

Variables hold values, and operators combine them. A keeps both close to C, with a few differences that remove classic traps: every variable starts as zero, a constant is a real compile-time value, and the logical operators come with word forms. This chapter covers declarations, constants, scope, and every operator group in order of precedence.

In this chapter:

- declaring variables, constants and globals
- scope and shadowing
- arithmetic, comparison, logical and bitwise operators
- shifts, `?:`, `??`, `++`, `--` and compound assignment
- operator precedence

## Declaring variables

A declaration names a type and one or more variables. Every variable is **zero-initialised**: locals, arrays, structs and the memory from `new` and `alloc` start as zero, so you never read a random leftover value.

{{sample lang/variables}}

What to notice:

- `int b = 5, c = b * 2;` declares two variables; an initializer may be any expression, including one that uses an earlier variable.
- An array, a struct, a `bool` and a pointer are all zero at the start; a zero pointer is `null`.
- `Point q = p;` copies the whole struct. `q.x = 9` changes only the copy.
- An assignment is an expression with a value, so `int d = a = 3;` sets both. Use that sparingly.

## Constants

`const NAME = value;` declares a **compile-time constant**. The compiler evaluates it, so it can be used wherever a constant expression is needed (array sizes, `case` labels, default parameters, other constants). A constant cannot be assigned to and its address cannot be taken.

{{sample lang/constants}}

What to notice:

- The type is inferred (`int` for `MAX`, a string for `TITLE`), or you can write it: `const int MASK = 0xF0;`.
- A typed constant is cut to its type: `const uint8 SMALL = 300;` is 44.
- Constant expressions support the arithmetic, bitwise, comparison and `&&`, `||`, `!` operators (but not `?:`, `??` and `^^`/`xor`), so `AREA` and `FLAG` are computed at compile time. `MAX / 10` sized the array `values`.
- The two commented lines would not compile: `MAX = 5;` gives `left side of assignment is not assignable`, and `&MAX` gives `cannot take the address of a value`. Both messages are real compiler output.

## Scope and shadowing

A variable lives until the end of the block (`{ ... }`) it was declared in. A declaration in an inner block may **shadow**, that is hide, a variable of the same name from an outer block. A variable declared in the head of a `for` loop lives in the loop only.

{{sample lang/scope_shadow}}

What to notice:

- The inner `x` was a different variable: after the block, the outer `x` still had its value 1.
- `x += i` in the loop changed the outer `x`, which is why it ended at 4 (1 + 0 + 1 + 2).
- The loop variable `i` exists only inside the loop. Using `i` after the loop is the error `undeclared identifier 'i'`, and a later loop may declare its own `i`.
- A local named `counter` hides the global `counter`. Shadowing is legal, but it makes code harder to read: prefer different names.
- You can also use a name for a local that the prelude uses for a function (`max`, `min`), because locals hide functions. You cannot *define a function* with such a name at the top level, see [the standard prelude chapter](#chap-standard-prelude).

## Global variables

A variable declared outside any function is a **global**. Every function can use it. A global's initializer must be a constant expression: numbers, constants, enum members, `sizeof`, strings and operators on them (the same operators as in a `const`: no `?:`, `??` or `^^`/`xor`). Without an initializer a global is zero.

{{sample lang/globals}}

What to notice:

- `total` has no initializer: it lives in a zero-filled area (`bss`) that costs nothing in the program file. A global `int big[10000000];` (80 MB) adds nothing to the program file: a program with an empty `main` is about 4 KB with or without it. A global array **with** an initializer is stored in the file in full: `int table[1000000] = {1, 2, 3};` made an 8 MB program in a test.
- `start` shows that constants may appear in the initializer: `BASE * 4 + 2`.
- A global is initialised before `main` starts, so its initializer must be constant: `int g = f();` and `int g = n + 1;` (with `n` another variable) are rejected with `name is not a constant`. Set such values at the start of `main` instead.

## Arithmetic

The arithmetic operators are `+`, `-`, `*`, `/` and `%`, and the unary `-` and `+`. On integers they work on 64-bit values: signed, except that a `uint64` is divided and compared as unsigned (`+`, `-`, `*` and `/` also work on `double`). Division truncates toward zero, like in C, and the remainder has the sign of the left operand.

{{sample lang/arithmetic}}

What to notice:

- `-7 / 2` is -3, not -4, and `-7 % 3` is -1. The identity `(a / b) * b + a % b == a` always holds.
- Overflow wraps silently (see [types](#chap-types-and-values)).
- Dividing by zero is not detected by the language. On x86-64 the processor raises a fault and the program is killed (the shell reports 136); on ARM64 the result is 0, according to the language reference. Check the divisor yourself.

## Comparison and logical operators

The comparison operators are `<`, `<=`, `>`, `>=`, `==`, `!=` and the three-way `<=>`. The logical operators are `&&`, `||` and `!`. All of these give **0 or 1**, except `<=>`, which gives -1, 0 or 1. Any integer or pointer can be a condition: zero and `null` are false, everything else is true.

{{sample lang/comparison_logic}}

What to notice:

- `12 && 3` is 1, not 3: logical operators never return one of their operands.
- `a <=> b` is -1, 0 or 1. It makes a compare function for sorting a one-liner, and it compares a `uint64` as unsigned.
- Pointers can be compared with `==` and `!=`, and with `<`, `>` when they point into the same array.
- `==` on two `char*` values compares the addresses, not the text. Compare strings with `streq` (see [the standard prelude chapter](#chap-standard-prelude)).

### Short-circuit evaluation

`&&` and `||` stop as soon as the answer is known. `a && b` does not evaluate `b` when `a` is false, and `a || b` does not evaluate `b` when `a` is true.

{{sample lang/short_circuit}}

What to notice:

- Only `checking left` was printed in each case: the right side never ran, so its side effect (the second message and the call count) did not happen.
- This is the standard way to guard a risky test: `text != null && text[0] == 'x'` is safe even for a `null` pointer.

## Bitwise operators and shifts

`&`, `|`, `^` and `~` work on the individual bits of a 64-bit value (and, or, exclusive or, complement). `<<` shifts left and `>>` shifts right. `>>` is an **arithmetic** shift on signed values: it copies the sign bit, so a negative number stays negative. On a `uint64` it is a logical shift. Keep the shift count between 0 and 63: for larger counts the result depends on the processor (on x86-64 the count is taken modulo 64, so `1 << 64` is 1).

{{sample lang/bitwise_ops}}

What to notice:

- `%b` prints binary: `a & b` is `1000`, `a | b` is `1110`, `a ^ b` is `110`. `~a` is -13: all 64 bits are inverted.
- Flags in one number are set with `|=`, cleared with `&= ~FLAG` and flipped with `^=`.
- Shifting a negative `int` right keeps the sign (`-16 >> 2` is -4); the same bit pattern in a `uint64` shifts in zeros, which is why `big >> 63` is 1 and `(int) big >> 63` is -1.

## The conditional operator ?: and ??

`condition ? a : b` is `a` when the condition is true and `b` otherwise. Only the chosen branch is evaluated. It groups from right to left, so chains read naturally.

`a ?? b` ("a, or else b") is `a` unless `a` is 0 or `null`; then it is `b`. The right side is only evaluated in that case.

{{sample lang/ternary}}

What to notice:

- `n < 0 ? "negative" : n == 0 ? "zero" : "positive"` is a chain: the second `?:` is the third operand of the first one.
- `??` treats **0 as missing** too, so `count ?? 10` gave 10. Use it for pointers and for values where 0 means "not set", not where 0 is a valid answer.

## Increment and decrement

`++` and `--` add or subtract one. After the variable (`i++`) the expression has the **old** value; before it (`++i`) it has the **new** value. They work on integers, `char`, pointers (they move by one element) and doubles.

{{sample lang/incdec}}

What to notice:

- `printf("%d\n", i++)` printed 5 and left `i` at 6; `++i` printed 7.
- `data[k++] = 11;` uses the old `k` as the index and then increments it: the idiom for filling an array.
- `*p++` reads the character `p` points to and then steps to the next one: the walk over a string in the last loop.

## Compound assignment

`a op= b` means `a = a op b`, with `a` evaluated once. The compound operators are `+=`, `-=`, `*=`, `/=`, `%=`, `&=`, `|=`, `^=`, `<<=` and `>>=`.

{{sample lang/compound_assign}}

What to notice:

- Each line applies one operator to the running value of `a`, so you can follow the arithmetic step by step.
- In `table[calls++] += 100` the index expression ran once: `calls` is 1 afterwards, not 2.

## Word operators and exclusive or

`and`, `or` and `not` are alternative spellings of `&&`, `||` and `!`. `xor` (or `^^`) is the logical exclusive or: true when exactly one side is true. Both sides always run (there is no short circuit), and the result is 0 or 1.

{{sample lang/word_operators}}

What to notice:

- `a > 1 and not (b > 0) or retry` reads like English and means `a > 1 && !(b > 0) || retry`.
- `3 xor 4` is 0: both sides are true, and `xor` is true only when exactly one side is. The bitwise exclusive or is the single character `^` (`3 ^ 4` is 7).

## Precedence

Operators with higher precedence are applied first. The table lists them from highest to lowest; operators on one line have equal precedence.

| Level | Operators | Notes |
|---|---|---|
| 1 | `a[i]`  `a.b`  `a->b`  `f(x)`  `x++`  `x--` | `.` and `->` are interchangeable on pointers |
| 2 | `-x`  `+x`  `!x`  `~x`  `*p`  `&x`  `++x`  `--x`  `(type)x` | right to left |
| 3 | `*`  `/`  `%` | |
| 4 | `+`  `-` | pointer plus or minus an integer scales by the element size |
| 5 | `<<`  `>>` | |
| 6 | `<`  `<=`  `>`  `>=`  `<=>` | |
| 7 | `==`  `!=` | |
| 8 | `&` | bitwise and |
| 9 | `^` | bitwise exclusive or |
| 10 | `\|` | bitwise or |
| 11 | `&&` | short circuit |
| 12 | `^^`  `xor` | logical exclusive or: both sides run |
| 13 | `\|\|` | short circuit |
| 14 | `c ? a : b`  `a ?? b` | right to left |
| 15 | `=  +=  -=  *=  /=  %=  &=  \|=  ^=  <<=  >>=` | right to left |

The word forms `and`, `or` and `not` have the precedence of `&&`, `||` and `!`, and `xor` that of `^^`.

{{sample lang/precedence}}

What to notice:

- `1 + 2 << 3` is `(1 + 2) << 3` = 24: `+` binds tighter than `<<`.
- `6 & 3 == 3` is `6 & (3 == 3)` = 0, because `==` binds tighter than `&`. This is the same trap as in C: put parentheses around bit tests, `(6 & 3) == 2`, as the next line of the sample does.
- Assignment groups from the right: `a = b = c = 7` sets all three.
- When in doubt, add parentheses. They cost nothing.

## Summary

- Every variable starts as zero; arrays, structs and memory from `new` and `alloc` too.
- `const NAME = value;` is a compile-time constant; a typed constant is cut to its type.
- A variable lives to the end of its block; an inner declaration may shadow an outer one; globals need constant initializers.
- Arithmetic is 64-bit and wraps; division truncates toward zero; division by zero is not checked.
- Comparisons and logical operators give 0 or 1; `&&` and `||` short-circuit; `and`, `or`, `not`, `xor` and `^^` are the word forms.
- `>>` keeps the sign of a signed value; `&`, `|`, `^`, `~` work bit by bit.
- `?:` chooses, `??` replaces 0 or `null`, `++` and `--` come in prefix and postfix form, and the arithmetic and bitwise operators and the shifts have compound assignments such as `+=` and `<<=`.

## Where next

- [Control flow](#chap-control-flow) uses these expressions in `if`, loops and `switch`.
- [Functions](#chap-functions) shows how to give a computation a name.
- [Memory and pointers](#chap-memory-and-pointers) explains pointer arithmetic with `+`, `-` and `++`.
