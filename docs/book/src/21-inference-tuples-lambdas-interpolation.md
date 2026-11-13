# Type inference, tuples, lambdas and string interpolation

This chapter covers a second batch of newer language features: `var`, tuples, lambdas, string interpolation, and the exact printing of `double` values by `printf`. They build on [More language features](#chap-more-language-features). Each sample was compiled and run, and compiled for all nine targets.

## var

`var` lets the compiler take the type from the initializer. It always needs an initializer, and it is for **local variables** only (not parameters, fields or globals).

{{sample lang/var_inference}}

What to notice:

- `var p = &n;` is an `int*`, and a function result that is a struct is copied into the new variable.
- `var a = 1, s = "two";` declares two variables, each with its own type.
- `foreach (var x in values)` takes the element type of the array.
- The initializer is evaluated **before** the name exists, so `var x = x + 1;` uses an outer `x`. An array becomes a pointer to its first element.

## Tuples and multiple results

A tuple is a fixed list of values of different types. A function can return several values by returning a tuple.

{{sample lang/tuples_basic}}

What to notice:

- `(int q, int r) = divmod(7, 2);` declares both variables at once. `var (q2, r2) = ...` takes the types from the tuple, and `_` throws an element away.
- `(a, b) = (b, a);` is a swap: all values on the right are computed first.
- A tuple is a value: `.0`, `.1`, `.2` read and write its elements, and it can be stored in variables, fields and arrays. Two to sixteen elements are allowed. `sizeof((int, int))` is 16.
- A literal `(a, b)` is a tuple only where a tuple is expected (a `return`, an initializer, an assignment to a pattern). Elsewhere it is still the old comma operator, so existing programs do not change.
- Patterns cannot be nested: `((a, b), c) = ...` is an error.

## Lambdas

A lambda is an anonymous function. Its value is a `func`, so you can store it, pass it and call it like the address of a named function.

{{sample lang/lambdas_basic}}

What to notice:

- Forms: `(int x) => x * 2`, `(a, b) => a + b` (untyped parameters are `int`), `x => x + 1`, and a block body that uses `return`.
- A lambda can be called where it is written: `((int a) => a + 100)(5)`.
- Library functions that want a compare function, such as `algo.sortBy`, accept one directly.
- **No captures.** A lambda does not see the local variables or `this` of the function around it. Using one is a compile error that tells you to pass it as a parameter or use a global. Globals, constants and functions are visible.
- A lambda can only be written inside a function, not in a global initializer. Like every call through a `func`, its result is an `int` (a `double` result comes back as its 64 bit pattern; read it with `__dbl`).

## String interpolation

`$"text {expression:spec}"` builds a text. The part after the colon is a `printf` conversion without the `%`.

{{sample lang/interpolation}}

What to notice:

- Any expression is allowed inside the braces, also function calls. `{{` and `}}` are literal braces.
- Without a letter the type chooses the conversion: `double` prints the shortest exact text, `bool` prints `true` or `false`, a text prints as text.
- The spec parts must come in the order of `printf`: flags, width, `.precision`, length, letter. `{x:06}` pads with zeros and `{name:-8}` pads on the right.
- The result is an ordinary text, so it can be stored or passed on. It is built by the same formatter as `printf` and `format`, so they print the same characters.

## Exact floating point output

`printf`, `format` and interpolation print doubles **exactly**: the digits are the true value of the binary number, rounded half to even, on every target.

{{sample lang/float_formats}}

{{sample lang/float_exact}}

{{sample lang/float_special}}

What to notice:

- `printf("%.2f", x)` is right for a `double x`. A `double` passes through `...` as its 64 bits and `%f %e %g %v` read them back.
- `%v` prints the shortest text that reads back as the same number (`0.30000000000000004` for `0.1 + 0.2`).
- An `int` is **not** converted: `printf("%f", 3)` shows a tiny number, and `%d` with a `double` shows its bits. Write `(double) n`, or `(int) x`. Interpolated strings know the types and convert for you.
- `inf`, `nan` and negative zero have fixed spellings, shown in the last sample.

{{sample lang/format_bits}}

{{sample lang/format_limits}}

`format` and `vformat` never write more than the buffer size minus one and always end with a zero. They return the length the whole text would have had.

## Summary

- `var x = expression;` takes the type from the initializer (locals only).
- Tuples `(T1, T2)` return several values; `(int a, int b) = f();` destructures, `(a, b) = (b, a);` swaps.
- Lambdas `(a, b) => a + b` are `func` values without captures.
- `$"... {expr:spec} ..."` builds a text with the `printf` formatter.
- `printf` prints doubles exactly; an `int` passed to `%f` or a `double` passed to `%d` is not converted.

## Where next

- [More language features](#chap-more-language-features) for `foreach`, the text `switch` and the class features.
- [Numbers](#chap-numbers) for `double` arithmetic and `dmath`.
- [The language reference](#chap-language-reference) for every rule and limit.
