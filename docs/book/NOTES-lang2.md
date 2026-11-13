# Notes on "More language features" (chapter 20): independent review

Reviewed against `build/ac` (the compiler is the truth), `docs/LANGUAGE.md` sections 4, 5, 6 and 8, and the tests `tests/t300*` to `t323*`.
All reproductions below were run with `build/ac` on x86-64 (scratch programs, not samples).

## (a) Compiler behaviour that looks like a bug or a trap

### 1. `static_assert(sizeof(ThisClass) ...)` inside the class body, before the last field, gives wrong answers

The class is not complete there. The assertion fails for the size the class really has, and the results contradict each other
(`==` 16 and `!=` 16 both fail; `!= 0` and `< 100` pass; no value from 1 to 100 compares equal). After the last field it is correct.

```c
class C { public: int a; static_assert(sizeof(C) == 16, "two ints"); int b; }   // error: static assertion failed: two ints
class D { public: int a; static_assert(sizeof(D) != 16, "x");        int b; }   // error: static assertion failed: x
class E { public: int a; int b; static_assert(sizeof(E) == 16, "ok"); }         // compiles; sizeof(E) is 16
int main() { return 0; }
```

(The compiler stops at the first error, so try the three classes one at a time.) Expected: either the right size or an error "the class is not complete here". Chapter 20 tells readers to put such an assertion after the
last field.

### 2. A function called `rev` (also a variable or a field) silently turns `foreach (x in rev a)` into a type error

`rev` is a word only inside a foreach header, and only while no variable or field of that name is visible (documented in `LANGUAGE.md`).
A **function** `rev` counts too (not documented), and the message does not say why:

```c
void rev(char* s) { /* reverse a text in place */ }
int main() {
    int a[3] = {1, 2, 3};
    foreach (int x in rev a) printf("%d ", x);     // error: foreach needs an array, a range (a..b), text (char*) or a class with count() and get()
    return 0;
}
```

Suggestion: in a foreach header, read `rev` as the reverse marker when it is followed by something that starts an expression (an
identifier, a number, `(`), even when a name `rev` exists, or say in the message that `rev` was read as a name. Chapter 20 warns about it.

### 3. `static_assert` at the start of a statement is always the assertion

`int static_assert = 1;` and `x + static_assert` compile, but `static_assert = 2;` as a statement is the error `expected '('`.
This is what `LANGUAGE.md` says ("a word only where a statement or declaration starts"), so it is only a trap.

### 4. "this class does not implement the abstract method" is reported at the wrong place and does not name the class

```c
abstract class Shape {
public:
    abstract int area();
    abstract int sides();
}

class Rect : Shape {
public:
    int w;
    override int area() { return w; }
}

int main() { return 0; }
```

The error is `line 13: this class does not implement the abstract method 'sides'` with the caret under `int main` (the first token
after the class), not at `class Rect`. At the end of a file it is reported one line after the last line. With a long class a reader
cannot tell which class is meant. Chapter 20 says so.

### 5. A class with static fields in a header cannot be shared between units (documented, but easy to trip over)

```c
// cnt.h:  #pragma once
//         class Counter { public: static int made; int id; Counter() { made++; id = made; } }
//         int other();
// a.a:    #include "cnt.h"   int other() { Counter c(); return c.id; }
// b.a:    #include "cnt.h"   int main() { Counter c(); printf("%d %d\n", c.id, other()); return 0; }
//   ac -c a.a -o a.ao;  ac -c b.a -o b.ao;  ac a.ao b.ao -o prog      ->   ac: error: duplicate definition of 'Counter.made'
```

`LANGUAGE.md` documents it ("define a class with static fields in one unit only"); the methods of header classes, by contrast, may be
defined in every unit. Chapter 20 now says it.

## (b) Places where the reference or the first draft of the chapter was wrong or incomplete

| Where | Claim | What really happens |
|---|---|---|
| chapter 20, foreach | "a range ... is empty when the end is not above the start" | only for `a..b` (`b <= a`). `a..=b` is empty when `b < a`: `1..=1` has one round (`LANGUAGE.md` says this correctly). |
| chapter 20, note | "Programs that do not use them are not affected" | `foreach` is a reserved word now (`int foreach = 1;` is an error), and a `switch` on a `char*` changed meaning (the old compiler compared addresses: even `run("get")` with `case "get":` did not match; checked with a build of the commit before the text switch). |
| chapter 20, note | "a variable may still be called `final` or `rev`" | true for `final`; `rev` stays usable as a name, but then `rev` no longer reverses in `foreach` (see 2 above). |
| chapter 20, labeled loops | "so the `println("")` after the inner loop was skipped" | only for rows 1 to 3 of the sample. Row 4 ends the inner loop normally and runs it. |
| chapter 20, collections | maps and sets are walked "with `capacity()`, `usedAt()`, `keyAt()` and `valueAt()`" | `usedAt()` exists only in `IntMap` and `IntSet`; `StrMap` and `StrSet` mark an empty slot with a `null` key (`valueAt` in `StrSet`). `IntQueue` and `IntHeap` have no `get(i)` either. |
| chapter 20, abstract | "Use `override` for every new method" | `override` on a method that overrides nothing is an error; the advice is for every method meant to replace a base method. |
| chapter 20, is/as | objects without a vtable pointer: "elements of an array of objects and raw memory" | also an object that is a field of another object (`class Kennel { Dog dog; }`): `&kennel.dog is Dog` is 0 (chapter 15 already says that a virtual call there crashes). |
| chapter 20, switch | "a switch whose value is a `char*`" | a `char` array and a `uint8*` are text for a `switch` too. A `void*` is not (`switch (v)` with `case "go":` is `this case label is a text, but the switch is not on text`; cast it). |
| chapter 15 | "(with or without the keyword; the signature is not compared)" | true without `override`; with `override` the signature is compared (`LANGUAGE.md` section 8). Reworded. |
| chapter 14 | "Two meanings of `static`" | a third one: a static member of a class (chapter 20). Pointer added. |
| chapter 37 | "`foreach` over the containers of this chapter" points to chapter 20 | chapter 20 had no such text; it now says that `ds.Deque`, `RingBuffer`, `OrderedSet` and `OrderedTextSet` have `size()` and `get(i)` (checked by running them). |
| chapter 12 (not edited, not my file) | precedence table | has no row for `x is C` and `x as C` (chapter 90 and `LANGUAGE.md` have it) and none for `\|\|=`, `&&=`, `??=`. Not wrong, but incomplete. |

## (c) Not verified

* Windows (`-t windows`) and the Android targets: only compiled (`samples.py --targets`), never run (no wine in this review).
* The performance figures for the text switch (0.09 and 3 microseconds per decision): copied from `LANGUAGE.md`, not measured. The
  threshold (4 labels one after the other, more than 4 hashed) was read in `src/switch.asm`, and a program with 20 text labels and
  20 ranges gives the same answer on x86-64, ARM64, RISC-V 64 and LoongArch 64 (qemu-user).
* Separate compilation with `is` / `as` was checked by building and running `tests/link/isas` by hand (output identical to
  `expected.out`), on x86-64 only.
