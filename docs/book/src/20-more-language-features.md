# More language features

The chapters before this one teach the core of A: types, control flow, functions, classes and modules. This chapter covers the features that make everyday code shorter and safer. You can write a whole program without them, but once you know them you will probably use `foreach` and the text `switch` in almost every program.

In this chapter:

- **`foreach`**: a loop over arrays, text, ranges and your own classes.
- **`switch` on text**, with lists of labels and ranges.
- **Labeled `break` and `continue`**: leave or continue an outer loop.
- **`||=`, `&&=` and `??=`**: assign only when the target says so.
- **`static_assert`**: facts that the compiler checks.
- **Abstract classes, `override` and `final`**: classes that are checked.
- **Static members**: fields and methods that belong to a class.
- **`is` and `as`**: ask an object for its class.

::: note
These features need a compiler that has them; they are part of the compiler that this book describes, and every sample in the chapter was compiled and run (also for all nine targets, and under emulation for ARM64, RISC-V and LoongArch). Programs that do not use them are not affected. Of the new words only `foreach` is reserved: `in`, `rev`, `abstract`, `override`, `final`, `is`, `as` and `static_assert` are words only in the place where they have a meaning, and a variable may still be called `final` or `rev`.
:::

## foreach

A `for` loop over an array needs an index, a limit and a step. `foreach` says only what you mean: "for every element". The variable is declared in the loop header.

{{sample lang/foreach_basic}}

What to notice:

- `foreach (int p in primes)` visits the elements in order. With two variables, `foreach (int i, int p in primes)`, the first one is the index.
- `rev` in front of the subject goes backwards: `foreach (int p in rev primes)`.
- A text gives its bytes up to the final 0, which is not visited. A `char` variable holds each byte: `a=97 b=98 c=99`.
- A **range** is a subject too. `1..4` is **half open** (1, 2, 3), `1..=4` is **closed** (1, 2, 3, 4), and `rev 0..=3` counts down from 3 to 0. A range has only one variable, and it is empty when the end is not above the start.
- The type of the variable may be left out: `foreach (x in primes)` gives `x` the type of the elements.
- The subject is evaluated **once**, before the first round. A function call in it runs one time.

### What can be iterated

| The subject is | The elements are |
|---|---|
| an array whose length the compiler knows: a local, global or `static` array, an array field (`s.items`, `this.items`), a compound literal `(int[]){1, 2, 3}` | the array elements |
| a text (`char*`, also a literal) | the bytes before the final 0; a `null` text has none |
| a range `a..b` or `a..=b` | the integers in it; `rev` counts down |
| `pointer, count`: `foreach (T x in p, n)` | `n` elements from `p` |
| an object of a class with `count()` (or `size()`, `len()`, `length()`) and `get(i)` (or `operator[]`) | `get(0)` up to `get(n - 1)` |

An array **parameter** is just a pointer, so its length is not known: the compiler tells you to use the `pointer, count` form (`foreach (T x in pointer, count)`). A `char buf[32]` has 32 elements, not the length of the text inside it.

### Changing the elements

{{sample lang/foreach_pointers}}

What to notice:

- The variable is a **copy**. `foreach (Item it in items) it.qty = 0;` changed nothing in the array: the output after the first loop is unchanged.
- To change the elements, declare the variable as a **pointer to the element type**: `foreach (Item* it in items)` gives the address of each element, and `it->qty += 5` changed the array. This works for arrays, text and `pointer, count`, but not for ranges or classes.
- `foreach (T x in p, n)` is how you walk a parameter or `argv`. `argv + 1, argc - 1` skips the program name.
- A `null` text and an empty range run no rounds. They do not crash.
- `break`, `continue`, `return` and `goto` work as in the other loops, and loops nest.

### Your own classes

A class can be the subject of a `foreach` when it has a method without parameters that tells the number of elements (`count()`, `size()`, `len()` or `length()`, looked up in that order) and a method `get(i)` or `operator[](i)` that returns element `i`.

{{sample lang/foreach_class}}

What to notice:

- `Squares` has only `count()` and `get()`. Nothing else is needed.
- `collections.IntList` and `StrList` already have `size()` and `get()`, so `foreach` works with them without any change. The element type is the result type of `get`.
- The number of elements is read **once**, before the first round. A loop body that adds elements to the list does not make the loop longer.
- The maps and sets of `collections` have no `get(i)`, so they are not iterable with `foreach`. Walk their slots with `capacity()`, `usedAt()`, `keyAt()` and `valueAt()` (see [collections](#chap-collections-and-algorithms)).

## switch on text, lists and ranges

A `switch` whose value is a `char*` compares the **text** of the labels, byte by byte, like `streq`. Before this feature a text label compared addresses, which is why older code uses `if` and `streq` chains.

{{sample lang/switch_text}}

What to notice:

- `case "put", "post":` gives several labels to one case. A text `const` such as `QUIT` is a label too.
- The text `built` was made at run time and still matches `"put"`, because the bytes are compared, not the addresses.
- A **`null` text matches no label** and goes to `default`. It does not crash.
- The value is evaluated once. Fall-through and `break` work as for numbers.
- A switch with many text labels is fast: up to 4 labels are compared one after the other, more than that are found with a binary search over hash values, then compared byte by byte. The language reference gives 0.09 microseconds per decision for 1000 labels, against 3 microseconds for a chain of 1000 `streq` calls (figures from the reference, not measured again for this book).

The number switch got new label forms too.

{{sample lang/switch_ranges}}

What to notice:

- `case ' ', '\t', '\n':` is a **list** of labels for one case. A list may mix constants and enum members.
- `case 'a'..'z':` is a **range**. Unlike the half open range of `foreach`, a range label includes **both** ends, so `'0'..'9'` is the digits. A range with the lower end above the upper end is an error.
- Labels may be of any size now. The older limit of 32 bits (`case 5000000000:` was an error) is gone, and the value `size(int64 n)` can be a 64-bit number.
- A switch with no `default` does nothing when no label matches and execution continues after it: `when()` ends with `return "?"` for that case, which no weekday reaches.
- **Duplicate labels are compile errors**: equal numbers, overlapping ranges and equal texts, also within one `case a, b:`. A text label in a number switch is an error too, and the other way round.

## Labeled break and continue

A label in front of a loop (`while`, `do`, `for`, `foreach`) or a `switch` names it. `break name;` leaves that statement, and `continue name;` starts the next round of that loop.

{{sample lang/labeled_loops}}

What to notice:

- `break search;` left **both** loops at once, which is what you would otherwise write with a flag variable or a `goto`.
- `continue rows;` jumped to the next round of the outer `while`, so the `println("")` after the inner loop was skipped; the row had already ended its line.
- In the last part `break` alone would only leave the `switch`. `break loop;` leaves the `for (;;)` loop. A `switch` cannot be continued, but a `continue` inside one belongs to the loop around it.
- The name is looked up from the innermost statement outwards. A name that no enclosing statement has is the error `no enclosing loop or switch has the label 'outer'`.
- A label is also a `goto` target, so a name can be used once per function.

## ||=, &&= and ??=

`a ||= b` and `a ??= b` assign `b` only when `a` is 0, `null` or `false`. `a &&= b` assigns only when `a` is true. In both cases `b` is **evaluated only when it is assigned**, so a slow or side-effecting call on the right is skipped when it is not needed.

{{sample lang/logical_assign}}

What to notice:

- `name ??= "anonymous"` is the way to give a default to a `null` pointer. The second `??=` left the name alone.
- `expensive(42)` ran once. In the second `cache ||= expensive(99)` the cache was not 0, so the function was not called and nothing was printed for it.
- `ready &&= expensive(0) != 0` ran the right side because `ready` was true, and stored false. The next `&&=` saw false and did not evaluate its right side. `expensive` ran twice in all.
- The target's address is computed **once**: `slots[next++] ||= 100` advanced `next` by one, not two. Only the empty slot 0 was set; slot 1 already held 7.
- `x ||= y` is not `x = x || y`. It does not store the 0 or 1 that `||` produces: a true target stays as it is, and otherwise `y` itself is stored.
- The target has to be an integer, `bool`, enum or pointer. Doubles, structs and arrays are compile errors.
- The ten other compound assignments (`+=`, `-=`, `<<=` and the rest) work on every integer width, on doubles (`+= -= *= /=`), on pointers (`+=` and `-=` step by the element size) and, through the operator methods, on classes.

## static_assert

`static_assert(condition);` or `static_assert(condition, "message");` checks a constant expression **while compiling**. A false condition stops the compilation with your message. It generates no code and is allowed at the top level, in a class body and in a function.

{{sample lang/static_assert_demo}}

What to notice:

- The first assertion guards a layout: if somebody adds a field to `Header`, the program stops compiling instead of sending the wrong number of bytes over the network. A real failure looks like this (here the header has one field more than 8 bytes allow):

```text
e6.a:2: error: static assertion failed: the header is sent over the wire as 8 bytes
  static_assert(sizeof(Header) == 8, "the header is sent over the wire as 8 bytes");
  ^
```

- `Color.count` is the number of members of an enum and is a constant, so it can be used here.
- The condition has to be a constant: `sizeof`, your own `const` values, enum members and the built-in `__ARCH` and `__OS`. The message must be a text in quotes.
- A `const` cannot be declared inside a class (`const N = 4;` and `static const N = 4;` both give `unknown type`). Declare the constant at the top level, as the sample does.

## Abstract classes, override and final

An **abstract class** is a class that is not complete on its own. It declares methods that every concrete subclass must provide, and it can already use them in its own methods.

{{sample lang/abstract_shapes}}

What to notice:

- `abstract int area();` has no body. `virtual int sides() = 0;` is the same thing in the C++ spelling. A class with an abstract method has to be declared `abstract` as well, or the compiler says so.
- **No object of an abstract class can exist**: `new Shape()` is a compile error, and so are a local variable, a field, a by-value parameter or a by-value result of that type. Use a **pointer** to the abstract class, as `shapes` does. A class that is not abstract has to implement every abstract method it inherits, and the error names the method that is missing.
- `ratio()` is written once in `Shape` and calls the abstract methods. Each object answered with its own area and number of sides.
- `override` before a method says "this replaces a virtual method of a base class", and the compiler **checks** it: the base class must have such a virtual method, and the result and the parameter types must be the same. Without the word, a method with the same name still overrides, but nothing is compared (see [structs and classes](#chap-structs-and-classes)). Use `override` for every new method so that a typo or a changed signature is an error.
- `final` on a method forbids any further override. `final class Square` cannot be a base class. A class cannot be both `abstract` and `final`.
- An abstract class whose methods are all abstract is what other languages call an interface. There is only single inheritance in A.

## Static members

A **static field** is a variable that belongs to the class instead of to each object. A **static method** is a function in the class's scope that has no `this`.

{{sample lang/static_members}}

What to notice:

- `static int made;` exists once for the whole class and starts at 0. `static int step = 5;` and `static int table[4] = {...}` take a constant initializer (also arrays, structs and texts).
- Inside the class and its subclasses a static member is used by its plain name (`made++`). Outside it is `Counter.made`, `Counter.bump()` and `Counter.square(7)`. In a module it is `module.Class.name`.
- A static method cannot use `this`, instance fields or instance methods. It can use the static members, including private ones. It cannot be virtual, `abstract`, `override` or `final`.
- A static field **hides a global variable of the same name** inside the class. A static field and an instance field of one class cannot have the same name.
- You use statics with the class name, not through an object: `c->square(2)` is an error that says so.
- `sizeof(Counter.table)` and `foreach (int v in Counter.table)` work because the length of the array is known.
- A `Counter a;` without parentheses would **not** have run the constructor, as explained in [structs and classes](#chap-structs-and-classes). The sample writes `Counter a();`.

## is and as

Sometimes you hold an `Animal*` and need to know whether it really is a `Dog`. `x is Class` is true when the object is of that class or of a class derived from it. `x as Class` gives the same pointer as a `Class*`, or `null` when the object is of another class.

{{sample lang/is_as}}

What to notice:

- `a is Dog` is also true for a `Puppy`, because a `Puppy` is a `Dog`. `a is Puppy` is false for a plain `Dog`.
- `a as Dog` gives `null` for the `Cat` and for the plain `Animal`, so the test `d != null` is the safe way to use the result. There is no check when you call through the result directly (`(a as Dog)->bark()`), so that is your responsibility.
- A `null` pointer is nothing: `is` gives 0 and `as` gives `null`. The sample's `meet(null)` printed it without a crash.
- The left side has to be a pointer to a class **with virtual methods**: the object finds its class through its vtable pointer, so a class without any virtual method has no run time class and the compiler says so (`'is' and 'as': this class has no virtual methods, so its objects do not know their class`).
- Objects that have no vtable pointer are "not a Dog" for every class: the elements of an array of objects (`Dog dogs[2];`; make an array of pointers with `new` instead), and objects in raw memory. The same objects cannot make virtual calls either.
- With separate compilation (`ac -c`), a class that is included from a header has its own copy of the vtable in each unit. `is` and `as` still work between units, because the compiler also compares the class name.

## All together

The program `examples/tier2.a` of the Debian package uses them all in one place: an abstract class with a static counter, `override final`, `is` and `as`, a `foreach` over an array and over a compound literal of texts, a text `switch`, a labeled `break` and the logical assignments.

{{sample lang/tier2_tour}}

## What the compiler says

The new checks give messages that tell you what to do. These are real messages, each one from a program with exactly one mistake.

| You wrote | The compiler says |
|---|---|
| `foreach (int x in v)` where `v` is a parameter `int* v` | `foreach over a pointer needs the number of elements: foreach (T x in pointer, count)` |
| `case 1: ... case 1..5:` in one switch | `duplicate case label` |
| the same text label twice in a text switch | `duplicate case label` |
| `new Shape()` for an abstract class | `an abstract class has no objects of its own: create an object of a subclass and use a pointer to the abstract class` |
| `override int f(char* x)` when the base has `f(int x)` | `the result or parameter types differ from the method that is overridden 'f'` |
| `override int f()` of a method that is `final` | `cannot override a final method 'f'` |
| `break outer;` with no loop called `outer` | `no enclosing loop or switch has the label 'outer'` |
| `p is Plain` for a class without virtual methods | `'is' and 'as': this class has no virtual methods, so its objects do not know their class` |
| `c->square(2)` for a static method | `a static method is called with the name of its class (Class.name(...)), not through an object` |

## Summary

- `foreach (T x in subject)` loops over arrays, text, ranges (`a..b` half open, `a..=b` closed), `pointer, count`, and classes that have `count()` and `get(i)`. `rev` goes backwards, `foreach (int i, T x in ...)` adds the index, and a **pointer** variable changes the elements.
- A `switch` on a `char*` compares text, accepts lists (`case "a", "b":`) and treats `null` as no match. Number labels may also be lists and inclusive ranges, can be any size, and duplicates are errors.
- `break name;` and `continue name;` use a label in front of a loop or switch.
- `||=`, `&&=` and `??=` assign only when needed and evaluate the right side only then.
- `static_assert(condition, "message")` checks a constant while compiling.
- `abstract`, `override` and `final` make class hierarchies checked by the compiler; there are no objects of an abstract class.
- `static` fields and methods belong to the class; use them with the class name.
- `x is Class` and `x as Class` ask an object for its class; the class needs virtual methods.

## Where next

- [Structs and classes](#chap-structs-and-classes) for the basics that this chapter builds on, including the trap of `Class c;`.
- [The language reference](#chap-language-reference) has every rule and limit of these features.
- [Collections and algorithms](#chap-collections-and-algorithms) for `IntList` and `StrList`, which work with `foreach`.
