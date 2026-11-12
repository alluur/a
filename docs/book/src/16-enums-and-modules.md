# Enums and modules

Two features help you organise a program as it grows. **Enums** give names to a fixed set of values, so that code says `Color.Green` instead of `1`. **Modules** put related code in its own file and its own namespace, so that two files can use the same name without a clash. A offers two ways to write a module: the plain `module` / `import` pair, and module files with `a_module` and `a_import`.

In this chapter:

- enums: members, reflection (`count`, `name`, `parse`, `has`) and base types
- `module` and `import`, `public` and `private`
- module files with `a_module` and `a_import`
- importing the library modules that are built into the compiler

## Enums

`enum Name { A, B, C }` declares a set of named integer constants. Values count up from 0; `= value` sets one explicitly and the next member continues from there. A trailing comma is allowed. Members can be written qualified (`Color.Blue`) or, when the name is unique, bare (`Blue`).

{{sample lang/enum_basic}}

What to notice:

- `Green = 5` makes `Blue` equal to 6. `Red` is 0.
- Members are `int` constants. They work as `case` labels, in array sizes (`Day.Sun + 1`) and in any other constant expression, and they do arithmetic like numbers.
- An enum variable is 8 bytes and behaves like an `int`; there is no check that a value is a valid member. `Color c = 99;` is accepted.
- `case Color.Red:` and `case Green:` are both fine.

### What an enum knows about itself

An enum can tell you about its members:

| Expression | Value |
|---|---|
| `Color.count` | the number of members |
| `Color.name(v)` | the name of the member with value `v`, or `"?"` if there is none |
| `Color.parse("Green")` | the value of a name, or -1 if the name is unknown |
| `Color.parse("Green", fallback)` | the value, or `fallback` instead of -1 |
| `Color.has(v)` | `true` if `v` is a member |

{{sample lang/enum_reflection}}

What to notice:

- `name` turns a number into text for printing, `parse` does the reverse: useful for configuration files and command lines.
- The values need not be consecutive: the loop tested 0 to 7 with `has` and found 0, 5 and 6.
- Asking for a member that does not exist, such as `Color.Purple`, is a compile error (`no such member 'Purple'`).

### Smaller enums

An enum can be stored in fewer bytes by giving it a base type: `enum Kind : uint8 { ... }`. This is handy in structures that are sent over a wire or written to a file.

{{sample lang/enum_base_type}}

What to notice:

- `sizeof(Kind)` is 1. In `Frame`, the fields are aligned like any other: a `Kind`, a `uint16` and another `Kind` take 8 bytes with padding.
- The value is cut to the base type when stored: `Kind k = 300;` holds 44.
- `Kind.name(Kind.Image)` and the other reflection functions work the same way.

## Modules in files

A source file can declare the module it belongs to with `module name;` as its first statement. Other files then `import name;` and use its names with the module as a prefix: `geometry.area(3, 4)`. Types are qualified in the same way (`geometry.Box*`).

The smallest example is a directory with two files: `main.a` imports `greeter`, and `greeter.a` starts with `module greeter;`.

{{sample lang/modules_demo}}

What to notice:

- `import greeter;` looked for `greeter.a` next to `main.a` and compiled it into the program.
- `greeter.hello(...)` calls the public function with the module name as a prefix.

A more complete module has constants, a private function and a class. The next sample is also a directory with two files: `main.a`, which imports, and `geometry.a`, which starts with `module geometry;`.

{{sample lang/module_geometry}}

What to notice:

- `import geometry;` found `geometry.a` in the directory of the importing file.
- Inside the module, names are used without the prefix: `describe` calls `secret()` and `area(...)`.
- `private` makes a top-level declaration (function, global, constant, class, enum) visible only inside its own file. Everything else is public; `public` may be written explicitly. A private name used from outside is the error `access to private declaration 'secret'`.
- Different modules can use the same names. `main.a` defines its own `area` and `geometry.area` is a different function.
- A file is compiled **once**, however many files import it, and several files may contribute to the same module name.
- The `module` line and the `import` line are the older and simpler form; the library itself is written with them.

### Where imports are found

`import name;` looks, in this order, in: the directory of the importing file, a `lib/` directory in the current directory, `/usr/lib/a/`, `/usr/local/lib/a/`, and a `lib/` next to the main source file. A dot in the name becomes a directory separator, and a quoted name is a file name.

The directory of this sample holds `main.a`, `plain.a`, `util/math.a` and `extras/tools.a`.

{{sample lang/module_paths}}

What to notice:

- `import util.math;` found `util/math.a`; the module is called `math`, as declared inside the file, not `util.math`.
- `import "extras/tools.a";` names the file explicitly; the module inside is `tools`.
- `plain.a` has no `module` line, so its names go into the **global** namespace: `shout()` is called without a prefix. Use this only for small helper files.
- The `max` in `util/math.a` takes three parameters and hides the prelude's two-parameter `max` inside the module. `::max` is the global function; outside the module, `max(4, 9)` is the prelude's `max` again.

## Module files: a_module and a_import

A module file has the extension `.am`. The module name and its content are written in one block, and `public` and `private` work as before. Both `.a` and `.am` files can import a module file with `a_import`.

This sample is a directory with `main.a` and the module file `shapes.am`, which holds `a_module shapes { ... }`.

{{sample lang/module_am}}

What to notice:

- `a_import('shapes.am');` makes `shapes.area(...)` available. The first argument is a file name, looked up like `import "file"`: next to the importing file, then `lib/`, `/usr/lib/a/` and `/usr/local/lib/a/`. Single or double quotes both work.
- The optional second argument lists the members to bring into your own namespace, separated by commas or blanks. `perimeter` and `Box` can then be used without the prefix, and `shapes.Box` still works.
- `secret()` stayed hidden but `reveal()` could call it.
- A name that is not a public member is an error (`the module has no public member called 'secret'`), and so is a name that is already declared in the importing file.
- A module file can itself contain `a_import` lines, before or inside the block. `a_module` blocks cannot be nested.

`'*'` imports every public member. The module file here is `wordtools.am`:

{{sample lang/module_am_all}}

What to notice:

- With `'*'` both `vowels` and `shout` are available without a prefix, and `wordtools.vowels` still works.
- Importing everything pollutes your namespace: a later `vowels` of your own would clash. Import by name when you can.

## Importing library modules

The library modules (`collections`, `sort`, `strings`, `json`, `math`, ...) are written in A and built into the compiler. `import name;` makes one available, and it adds code only to programs that import it. A file of the same name next to your source takes precedence.

{{sample lang/import_builtin}}

What to notice:

- Names are qualified: `collections.IntList`, `sort.sortInts`, `strings.padLeft`.
- Classes can be created with `new` (`list`), or live on the stack (`ages`).
- Every library module has its own page in the API reference, for example [collections](#api-collections), [sort](#api-sort) and [strings](#api-strings).
- Large programs made of several files can be built in two ways: with `import`, which compiles everything together, or by compiling the files separately and linking them (see [chapter 18](#chap-preprocessor-and-assembly)).

## Summary

- `enum E { A, B = 5, C }` declares `int` constants; `E.count`, `E.name(v)`, `E.parse(text)` and `E.has(v)` give reflection.
- `enum E : uint8 { ... }` stores the enum in the given integer type.
- `module name;` at the top of a file and `import name;` in another make `name.member` available; `import a.b;` finds `a/b.a`.
- `private` hides a top-level declaration from other files; files are compiled once.
- A file without a `module` line puts its names into the global namespace.
- `.am` module files use `a_module name { ... }` and `a_import('file.am', 'names')`; `'*'` imports all public members.
- Library modules are imported by name and used with their prefix.

## Where next

- [Preprocessor and assembly](#chap-preprocessor-and-assembly) shows how to compile files separately and link them.
- [Memory and pointers](#chap-memory-and-pointers) covers what `new` does.
- The [API reference](#api-collections) lists the library modules.
