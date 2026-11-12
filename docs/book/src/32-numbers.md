# Numbers

An `int` in A is a 64-bit signed integer. That is enough for most programs, and it wraps around silently when it overflows. For everything else the standard library has a module: checked arithmetic and number theory, random numbers, integers of any size, exact decimals for money, floating point and fixed-point fractions. This chapter helps you pick the right one and shows each in action.

**In this chapter**

* `math` and `arith`: everyday integer mathematics, overflow checks, number theory and exact fractions;
* `random`: a generator with its own seed;
* `bigint` and `bn`: integers of any size, and fixed-size numbers with modular arithmetic;
* `decimal`: exact decimal numbers for money;
* `double`, `dfloat` and `dmath`: IEEE 754 floating point and the mathematical functions;
* `fixed`: fast fixed-point fractions that are exactly the same on every CPU.

## Which number type do you need?

| You need | Use | Exact? |
|---|---|---|
| whole numbers up to about 9.2 * 10^18 | `int` with [`math`](#api-math) and [`arith`](#api-arith) | yes, wraps on overflow |
| to detect overflow, or clamp instead of wrapping | `arith` (`checkedAdd`, `satAdd` ...) | yes |
| fractions such as 1/3 without rounding | `arith.Rational` | yes |
| integers with hundreds of digits | `bigint` | yes |
| `a^b mod m` with 256-bit or larger numbers (RSA, elliptic curves) | `bn` | yes |
| money, prices, percentages | `decimal` | yes, to the scale you choose |
| square roots, logarithms, sine, scientific values | `double` and `dmath` | no: rounded like on any CPU |
| fast fractions with a fixed resolution (neural networks, signal processing) | `fixed` | no: resolution 2^-20 |
| random numbers | `random` | not applicable |

Floating point and fixed-point arithmetic are done in software with integer instructions. That makes the results **bit for bit identical on every target** (x86-64, ARM64, RISC-V, LoongArch, Windows, Android), which a hardware floating point unit does not promise, at the price of speed.

## Integers: `math` and `arith`

The `math` module is the small, fast collection: greatest common divisor, powers, primes, a floor-style modulo, a few array statistics. It works on plain 64-bit integers and does **not** check for overflow.

{{sample numbers/math_integers}}

What to notice:

* `%` and `/` truncate towards zero, like in C: `-7 % 3` is -1 and `-7 / 2` is -3. `mod(a, m)` returns 0 to `m - 1` when `m` is positive, and `floorDiv` rounds towards minus infinity.
* `isqrt` is the integer square root, rounded down. `isPrime`, `nextPrime`, `powMod`, `factorial`, `fibonacci` and `binomial` are what you expect; `factorial(21)` or `fibonacci(93)` no longer fit in an `int`.
* The statistics functions take an array and a length: `sum`, `minOf`, `maxOf`.

The global random generator of the standard library is a seeded one. With the same `srand` you get the same numbers on every run and every target, which is what you want in tests and simulations.

{{sample numbers/math_random}}

What to notice:

* `rand()` returns a number from 0 to 2^31 - 1. Use `% n` to get a range.
* `math.randRange(lo, hi)` includes both ends; `math.shuffle(a, n)` shuffles in place. Both use the global generator.
* Seeding again with the same value repeats the sequence.

See the [API reference of `math`](#api-math).

### Overflow: `arith`

`arith` is the careful sibling of `math`. It can tell you that a calculation overflowed, or give the nearest representable value instead of a wrapped one.

{{sample numbers/arith_overflow}}

What to notice:

* `big + 1` wraps to the smallest `int`. No error, no signal.
* `addOverflows`, `subOverflows` and `mulOverflows` answer yes or no. `checkedAdd(a, b, &r)` stores the result only when it fits and returns false otherwise, so `r` keeps its old value.
* `satAdd`, `satSub` and `satMul` stick at the largest or smallest `int`. `clampBits(v, bits, signed)` clamps into the range of a narrower integer.

### Division with a rounding rule

{{sample numbers/arith_division}}

What to notice:

* `/` truncates towards zero, `floorDiv` goes down, `ceilDiv` goes up, `roundDiv` rounds to the nearest and halves away from zero. The table shows all four for every sign combination.
* `avg(a, b)` is the average that cannot overflow, even when `a + b` would.
* `isqrt`, `iroot(n, k)` and `isSquare` are exact for every 64-bit number.

### Number theory

{{sample numbers/arith_number_theory}}

What to notice:

* `factorize(n, primes, max)` stores the prime factors, with repeats, and returns how many. It handles numbers like 600851475143 instantly.
* `isPrime` is exact for every 64-bit number, including 2^61 - 1.
* `mulMod`, `powMod` and `modInverse` work without overflow for any positive modulus: `mulMod` multiplies two `int` values modulo `m` correctly, even when the product needs more than 64 bits. `modInverse` returns -1 when no inverse exists.
* `totient(n)` is Euler's totient (how many numbers up to `n` have no common factor with it), `divisorCount(n)` counts the divisors and `nextPrime(n)` is the first prime above `n`.
* `extGcd(a, b, &x, &y)` solves `a*x + b*y = gcd(a, b)`.

### Counting and digits

{{sample numbers/arith_sequences}}

What to notice:

* The limits are in the names of the functions: `fibonacci(92)` is the largest that fits, `factorial` goes up to 20, `catalan` up to 33.
* `digitCount`, `digitSum`, `reverseDigits` and `isPalindrome` work on the decimal digits of a number.

### Exact fractions: `Rational`

`arith.Rational` is a struct with the operators `+ - * /`, comparisons and negation, so fractions read like ordinary arithmetic. It is always kept in lowest terms with a positive denominator.

{{sample numbers/arith_rational}}

What to notice:

* `arith.rat(1, 3)` makes a fraction; `rat(5)` is 5/1. `str()` writes `1/2`, and a whole number without the denominator.
* `H(10)` is computed exactly: 7381/2520. A floating point sum would have rounding errors.
* `floor()`, `ceil()` and `round()` convert to an integer.
* The numerators and denominators are `int`, so very long sums overflow. Use `bigint` when you need more.
* `rat(1, 0)` gives the fraction 0/1 (which `str()` writes as `0`) instead of crashing.

See the [API reference of `arith`](#api-arith).

## Random numbers: `random`

`rand()` is one shared generator. `random.Random` is an object with **its own state**: two objects with the same seed produce the same numbers, and use of one does not disturb the other. It is a xorshift generator: fast and good for games, tests and simulations, and **not** suitable for cryptography.

{{sample numbers/random_generator}}

What to notice:

* `a` and `b` have the same seed and print the same six numbers.
* `range(lo, hi)` includes both ends. `nextBool()`, `chance(percent)`, `pick(strings, n)`, `shuffle(a, n)` and `token(n)` (random letters and digits) cover the usual needs. `next()` returns a non-negative 55-bit number.
* `reseed(seed)` restarts a generator.
* `random.clockSeed()` makes a seed from the clock. It is the only call in the module that is *not* repeatable.

See the [API reference of `random`](#api-random).

## Integers of any size: `bigint`

A `BigInt` holds an integer with as many digits as memory allows. Values are **immutable**: every operation returns a new `BigInt`, and the arguments stay as they are.

{{sample numbers/bigint_factorial}}

What to notice:

* `bigint.factorial(50)` has 65 digits, `fibonacci(300)` 63 and `pow(two, 200)` 61. `digits()` counts the decimal digits.
* The functions return pointers (`bigint.BigInt*`) and the text comes from `toString()`.

{{sample numbers/bigint_arithmetic}}

What to notice:

* `parse(text)` accepts digits with an optional `-` or `+` in front and returns `null` for anything else. `fromInt(n)` converts an `int`; `toInt()` goes back, and only means something when the value fits in 63 bits.
* `add`, `sub`, `mul`, `negate`, `pow`, `cmp` (-1, 0 or 1), `isZero()`.
* **Division is only by small numbers** (below 2^31): `divSmall(a, d, &rem)` returns the quotient and stores the remainder. There is no big-by-big division yet. `mulSmall(a, m)` multiplies by a small non-negative number.

{{sample numbers/bigint_digits}}

What to notice:

* Because `toString()` gives you the digits, a puzzle like "the digit sum of 2^1000" is a loop over characters.
* A `while` loop that adds two big numbers finds that the first Fibonacci number with 1000 digits is number 4782.

See the [API reference of `bigint`](#api-bigint).

## Big numbers for cryptography: `bn`

`bn` is a different tool for a different job. A `bn.Num` has a **fixed number of limbs** (30 bits each) that you choose, and the module is built around modular arithmetic with an odd modulus using Montgomery multiplication. RSA, elliptic curves and X25519 in the standard library are built on it. All numbers that meet in one operation have the same limb count.

{{sample numbers/bn_modpow}}

What to notice:

* `bn.fromBytes(bytes, len, limbs)` reads big-endian bytes; `toBytes(num, out, len)` writes them. 9 limbs hold 270 bits, enough for the 255-bit prime.
* `bn.mont(modulus)` builds the context for one modulus (it must be odd). `bn.powMod(ctx, base, exp)` then computes `base^exp mod m`.
* The sample checks Fermat's little theorem for the prime 2^255 - 19: `2^(p-1) mod p` is 1. For 15, which is not prime, `2^14 mod 15` is 4.
* `bitLength`, `cmp`, `add`, `sub` (which return the carry or borrow), `isZero` and `bit(num, i)` complete the basic set.

A toy RSA shows the use. The primes here are tiny so that you can read the numbers; real keys use primes of 1024 bits or more.

{{sample numbers/bn_rsa_toy}}

What to notice:

* The private exponent `d` comes from `arith.modInverse(e, phi)`.
* Encrypting and decrypting are the same operation with a different exponent, `powMod(m, message, e)` and `powMod(m, cipher, d)`.

::: warning
The code of `bn` is **not constant time**: how long it runs can depend on the secret numbers. The header of the module says so plainly. Use it for verification and for short-lived keys, not for long-lived secrets. [The cryptography chapter](#chap-cryptography) shows the complete tools.
:::

See the [API reference of `bn`](#api-bn).

## Exact decimals for money: `decimal`

Floating point cannot store 0.10 exactly, and an invoice that is a cent off is a bug. `decimal` stores a number as a whole number of units of 10^-scale in an ordinary `int`: with scale 2, `1999` means 19.99. Addition and subtraction are the plain `+` and `-`; everything else is a function that takes the scale.

{{sample numbers/decimal_money}}

What to notice:

* `parse("19.99", 2)` is 1999, `format(value, 2)` turns it back into text. `formatMoney(cents)` adds thousands separators.
* `percentOf(v, percent, percentScale)` takes the percentage with its own scale: 190 with scale 1 is 19.0 %. Extra digits are rounded **half away from zero**.
* `0.10 + 0.20` is exactly `0.30`.
* `parse` rounds extra digits (`-12.345` with scale 2 is -1235). For text that is not a number it returns 0, so call `isValid` first when you must tell "0" from "garbage".

Different scales meet when you convert currencies or compute rates.

{{sample numbers/decimal_scales}}

What to notice:

* `rescale(v, fromScale, toScale)` changes the scale. Going to a larger scale is exact, going to a smaller one rounds half away from zero.
* `mul(a, b, scale)` and `div(a, b, scale)` take two values of the **same** scale and give a result in that scale, rounded. The intermediate product (`a * b` for `mul`, `a * 10^scale` for `div`) must fit in 63 bits, so keep the scales reasonable.
* `div` by zero returns 0 instead of crashing.

See the [API reference of `decimal`](#api-decimal).

## Floating point: `double`, `dfloat` and `dmath`

A has a `double` type: an IEEE 754 binary64 number, the same as in C. `float` is an alias, also 64 bits. You can write literals (`2.5`, `1e-3`), mix `int` and `double` in expressions and compare doubles with the usual operators. The runtime module `dfloat` is loaded automatically when a program uses a floating point value; `dmath` adds the mathematical functions.

{{sample numbers/dfloat_basics}}

What to notice:

* An `int` mixed with a `double` becomes a `double`. To turn a `double` into an `int`, write a **cast**; it truncates towards zero: `(int) -7.75` is -7. Note that `n / 2` with two `int` operands is still an integer division, even when it is assigned to a `double`.
* `printlnDouble` prints the **shortest text that reads back as exactly the same number**: `0.30000000000000004` for `0.1 + 0.2`, `1e+22` for ten sextillion. `doubleToFixed(d, 3)` rounds to a number of decimals (exactly, not with a floating point trick), `doubleToSci(d, 2)` writes scientific notation and `doubleToText(d)` is the shortest form as a string.
* `parseDouble(text)` reads a number; text without digits gives 0.
* Overflow gives infinity, and infinity minus infinity gives NaN, which is not equal to anything, not even itself. `isInf`, `isNaN` and `isFinite` test for these.
* `printf("%d", x)` prints integers only. `printf("%f", x)` does not format a `double`: it prints the characters `%f`. Use the helpers above, or `printfd` from the `cfloat` module (see [the C library tour](#chap-c-library-tour)).

A double is 64 bits wide. `__bits(d)` returns them as an `int` and `__dbl(i)` builds a double from bits.

{{sample numbers/dfloat_bits}}

What to notice:

* The layout is 1 sign bit, 11 exponent bits (biased by 1023) and 52 fraction bits. `1.0` is `0x3FF0000000000000`.
* `0.1` is `0x3FB999999999999A`: the fraction repeats `9` and is rounded up at the end, which is why 0.1 cannot be exact.
* Adding 1 to the bit pattern gives the **next larger** double: `1.0000000000000002`. The gap above 1.0 is `dmath.EPSILON`, so `1.0 + 1e-16 == 1.0`.
* The C library of A works with the same numbers as plain `int` bit patterns (`dlit`, `dadd`, `printfd`); a `double` is the same 64 bits in a typed variable.

### Mathematics: `dmath`

`dmath` has the functions of C's `<math.h>` for `double` values: `sqrt cbrt pow exp exp2 expm1 log log2 log10 log1p hypot`, the trigonometric and hyperbolic functions and their inverses, `floor ceil round trunc fabs fmod fmin fmax copysign`, the constants `PI E TAU SQRT2 LN2 LN10 INFINITY EPSILON` and `nan()`.

{{sample numbers/dmath_functions}}

What to notice:

* `sqrt` is exact. `exp`, `log`, `sin`, `pow` and the others are computed with about 100 bits and rounded once, so they are almost always the correctly rounded result and the same on every CPU: `log10(1000)` is exactly 3.0 and `sin(PI / 2)` exactly 1.0.
* Trigonometry works in **radians**. `asin(0.5) * 180 / PI` converts to degrees.
* `round` rounds halves away from zero (`round(-2.5)` is -3.0), `floor` goes down, `ceil` up, `trunc` towards zero.
* `sqrt(-1)` is NaN.

{{sample numbers/dmath_simulation}}

What to notice:

* Calculations read like in any language with floating point: `speed * dmath.cos(rad)`. The result is formatted with `doubleToFixed`.
* The table is the same on every target, down to the last digit.

See the [API reference of `dmath`](#api-dmath) and [`dfloat`](#api-dfloat).

## Fixed-point numbers: `fixed`

A **fixed-point** number is an `int` that holds a value times 2^20. `fixed.ONE` is 1.0 (1048576), the resolution is about 0.000001 and the usable range is about +-2048 when you multiply. Addition and subtraction are the plain `+` and `-`; multiplication, division and everything else are functions. The number type of the neural network module `nn` is this one, because it is fast, needs no software floating point and is exactly reproducible.

{{sample numbers/fixed_basics}}

What to notice:

* `fromInt`, `fromText("2.5")`, `ratio(a, b)` and `fromParts(whole, millionths)` create values; `toInt` goes back (rounding towards minus infinity) and `toText(x, decimals, buf)` / `put` / `putln` print them.
* `1/3` prints as `0.33333302` with 8 decimals: the resolution is 2^-20, so the seventh decimal is already uncertain. Print with 3 to 6 decimals.
* `floor`, `round`, `abs`, `clamp`, `sign`, `min` and `max` are there. The smallest step is `0.000000954`.

{{sample numbers/fixed_functions}}

What to notice:

* `sqrt`, `exp`, `log`, `pow`, `sin`, `cos` and the neural network functions `sigmoid`, `tanh` and `relu` are in integer arithmetic. The values are good to about 5 or 6 decimals: `log(e)` gives `0.999997`.
* `exp` is limited to +-25, `sqrt` returns 0 for negative numbers, `log` of a non-positive number gives -25.0.
* `mul` multiplies the raw 64-bit numbers first, so the product has to fit: the module advises to keep it below 2^62, which is about 2048 for both factors. `2000 * 2000` works; `3000 * 3000` overflows and prints a negative number.

The module also has a seeded random number generator.

{{sample numbers/fixed_random}}

What to notice:

* `seed(s)` makes the sequence repeatable. `rand()` is uniform in [0, 1), `randRange(lo, hi)` in [lo, hi), `gauss()` approximately normal with mean 0 and deviation 1. `next()` is the raw non-negative integer.
* The mean of 2000 `gauss()` values is close to 0, as it should be.
* The `nn` module takes its start weights and its sample order from this generator. Call `fixed.seed` before you create a network if you want repeatable training.

See the [API reference of `fixed`](#api-fixed).

## Summary

* `int` wraps silently on overflow. Use `arith` to detect or clamp it, and `bigint` when the numbers really are huge.
* `math` is the small fast toolbox; `arith` adds overflow checks, rounding rules, number theory (exact for every 64-bit number) and the `Rational` fractions.
* `random.Random` has its own seed and state; `srand` and `rand` are the shared generator. Both repeat for the same seed.
* `bigint` is immutable and divides only by small numbers; `bn` is for modular arithmetic with fixed sizes, the base of RSA and elliptic curves.
* `decimal` keeps money exact as scaled integers.
* `double` is an IEEE 754 type implemented in software, identical on every target; `dmath` has the mathematical functions.
* `fixed` gives fast, reproducible fractions with a resolution of about one millionth.

## Where next

* [Collections and algorithms](#chap-collections-and-algorithms): `bits` and `algo.sieve` for more number work.
* [Data formats](#chap-data-formats): `nn` uses `fixed`.
* [The C library tour](#chap-c-library-tour): the same floating point numbers as `int` bit patterns, with `printfd`, `strtod` and `<math.h>`.
* [Cryptography](#chap-cryptography): where `bn` is used.
* API references: [`math`](#api-math), [`arith`](#api-arith), [`random`](#api-random), [`bigint`](#api-bigint), [`bn`](#api-bn), [`decimal`](#api-decimal), [`dmath`](#api-dmath), [`dfloat`](#api-dfloat), [`fixed`](#api-fixed).
