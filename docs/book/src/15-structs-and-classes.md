# Structs and classes

A struct groups several values under one name. A class is a struct that also owns functions (methods), hides its data, and can be extended by other classes. In A the two are the same construct with different defaults, so everything you learn about one applies to the other.

In this chapter:

- structs: fields, nesting, copying, pointers
- classes: constructors, methods, `this`, `new`
- access control: `public`, `private` and `protected`
- operator overloading
- inheritance, `super` and virtual methods

## Structs

A struct is declared with `struct Name { fields }`. A field can be any type, including another struct or an array. `.` reaches a field of a value; `->` reaches a field through a pointer, and `.` works on pointers too. A struct is **zeroed** when it is declared, and `=` copies all of its fields.

{{sample lang/struct_basic}}

What to notice:

- `Point q = p;` copied the struct: changing `q.x` did not change `p`.
- `r.bottomRight = (Point){6, 5};` assigns a whole struct from a compound literal. `strcpy(r.name, "window")` fills the `char` array field.
- Pointers use either spelling: `pp->x`, `(*pp).y` and `pp.x` mean the same.
- Fields are laid out in order, each at a multiple of its own size: `Point` is 16 bytes, `Rect` is 16 + 16 + 12 = 44 bytes, rounded up to 48. The size of every struct is a multiple of 8.
- `new Point` allocates a zeroed struct on the heap and returns a pointer; see [chapter 17](#chap-memory-and-pointers) for what that means.
- There is no automatic comparison: `a == b` on two struct values does not compare their fields. Write a function, or define `operator==` (see below).

## Classes

A class is declared with `class Name { members }`. Members are **private** unless marked `public`. A class has fields, methods (functions declared inside it) and optionally a constructor: a method with the name of the class and no result type.

{{sample lang/class_account}}

What to notice:

- `balance` is private. The compiler checks access: the commented line `a.balance = 1000;` gives `member is private to its class 'balance'`. Code in the methods of `Account` can use it freely.
- The modifier goes before the member: `private int balance;`, `public void deposit(...)`.
- Inside a method, `this` is a pointer to the object, and fields and methods can be used without a prefix. The constructor parameter `owner` hides the field `owner`, so `this.owner = owner;` is how you reach the field.
- `Account a("Ann", 100);` creates an object on the stack and runs the constructor. `new Account("Bob", 10)` creates it on the heap and returns a pointer.
- Call methods with `.` on an object and with `->` (or `.`) on a pointer.

### Access labels

Instead of a modifier on every member you can use C++ style labels. After `public:` or `private:` all following members have that access until the next label. A `struct` is public by default, a `class` is private by default.

{{sample lang/class_labels}}

What to notice:

- `Shape` has a public part (`id`, the constructor and `reveal`) and a private part (`secret` and `helper`). `reveal` can call `helper`; code outside the class cannot.
- `Open` is a struct: its fields are public unless a label says `private:`.

### Creating objects

How you declare an object decides whether the constructor runs:

| Declaration | What happens |
|---|---|
| `Counter c(10, 5);` | constructor runs, on the stack |
| `Counter c();` | constructor runs with its default arguments |
| `Counter* p = new Counter(100);` | constructor runs, on the heap |
| `Counter c;` | object is **zeroed**, the constructor does **not** run |

A class without a constructor is always just zeroed. Constructors may have default parameter values, like any function.

{{sample lang/class_objects}}

What to notice:

- `Counter c();` ran the constructor with `start = 1` and `step = 1`, so `tick()` made 2.
- `Counter zero;` has `step = 0`, so `tick()` left `value` at 0: the constructor never ran. When a class needs initialisation, declare it with parentheses or with `new`.
- `Plain` has no constructor, so all its fields start as 0 and `null`, with or without parentheses.

### Methods and global functions

Inside a class, its own methods and fields **hide** global functions of the same name. A method called `print` hides the global `print` within the class. Write `::print(...)` to reach the global function.

{{sample lang/class_shadow}}

What to notice:

- `print("starting")` inside `run` called `Logger.print`, which counted it. `::print` called the global function.
- Outside the class, `print` is the global function again.

## Operator overloading

A class (or struct) can define what the operators do by declaring methods named `operator` followed by the operator. The operators are `+ - * / % & | ^ << >> == != < > <= >= []` and the unary `-`. The left operand must be a class **value** (not a pointer); the right operand is whatever the method takes. `a != b` uses `operator==` when there is no `operator!=`, and `a += b` calls `operator+` and stores the result.

{{sample lang/operator_overload}}

What to notice:

- `operator-()` with no parameter is the unary minus; `operator-(Vec o)` would be the binary one.
- `operator*(int k)` multiplies by an `int`, not by a `Vec`: the right operand may have any type.
- A class has one method per operator: no overloading by parameter type. `&&`, `||`, `!`, `++`, `--` and `=` cannot be overloaded (`this operator cannot be overloaded`).
- Results that are classes are returned by value (see [functions](#chap-functions)).

## Inheritance

A class can extend one **base class**: `class Dog : Animal { ... }`. The base class must be defined first (`unknown type 'Animal'` otherwise). The derived object starts with the fields of the base class, so a `Dog*` can be used wherever an `Animal*` is expected: pointer types convert freely in A.

There are three levels of access: `public` (everyone), `protected` (the class and the classes derived from it) and `private` (only the class that declares the member, not even derived classes).

{{sample lang/inheritance}}

What to notice:

- `super(name, 2)` runs the base class constructor. Put it first in the constructor. A class without any constructor uses the base class constructor.
- `Bird.wings()` reads `legs`, which is `protected`. Reading `secret` (private to `Animal`) would be the error `member is private to its class 'secret'`.
- `Dog.kind()` has the same name as `Animal.kind()` and replaces it for calls on a `Dog`. `super.kind()` calls the base version.
- Through an `Animal*`, `a->kind()` still printed `animal`. The method `kind` is **not virtual**, so the type of the pointer decides which one runs.

### Virtual methods

To let the real class of an object decide, mark the base method `virtual`. A method with the same name in a derived class then overrides it (with or without the keyword; the signature is not compared).

{{sample lang/virtual_methods}}

What to notice:

- `describe()` is written once in `Animal` and calls `speak()`. Each object answered with its own `speak`: 1000 + 0 legs, 2000 + 4, and 12000 + 4 for `Puppy`, whose `speak` calls `super.speak()` and adds 10.
- `Puppy` has no constructor, so `new Puppy()` used `Dog`'s, which called `Animal(4)`.
- The object gets its vtable pointer when it is created with `new`, declared as a local, or declared as a global. Copying an object copies the pointer too: there is no protection against slicing, no destructor, no multiple inheritance and no abstract class.
- A virtual method must have a body; otherwise the program does not link (`undefined function`).

## A class that points to itself

A field may be a pointer to the class itself, which is how linked structures are built.

{{sample lang/linked_list}}

What to notice:

- `Stack` has private fields `top` and `size`. As a `new` object they start as `null` and 0, so no constructor is needed.
- `new Node(v)` runs the constructor; the new node's `next` is set to the old top, and `top` becomes the new node: a push onto the front of a singly linked list.
- Nodes are never freed (that is what `new` means in A); a long-running program that pushes and pops millions of times should use `malloc` and `free` instead (see [chapter 17](#chap-memory-and-pointers)).

## Summary

- `struct` and `class` are one construct: members are public in a struct and private in a class.
- Fields are laid out in order, naturally aligned, and the struct size is a multiple of 8; objects are zeroed.
- A constructor has the name of the class; `Class c(args);` and `new Class(args)` run it, `Class c;` does not.
- `this` is the pointer to the object; methods can use fields and other methods without a prefix, and they hide global functions of the same name (`::name` reaches the global one).
- `public`, `private` and `protected` are checked at compile time.
- Operator methods (`operator+`, `operator==`, `operator[]`, ...) give classes the usual operators.
- `class Dog : Animal` inherits; `super(...)` and `super.name(...)` reach the base class; `virtual` makes a method dispatch on the real class.

## Where next

- [Enums and modules](#chap-enums-and-modules) shows how to organise types into files.
- [Memory and pointers](#chap-memory-and-pointers) explains `new`, `alloc` and the heap.
- [The API reference of collections](#api-collections) shows ready-made classes: lists, maps, sets and queues.
