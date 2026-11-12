# The compiler: ac

`ac` is the whole toolchain in one program: preprocessor, compiler, code generators for four CPU families, linker, and the writers for ELF and PE executables. This chapter explains every option, how output files are named, how to compile for other systems and run the result, how to split a program into several files, and how to read the compiler's error messages.

**In this chapter**

* the command line and every option;
* output names: `{app_name}-{version-code}-{release-type}.{ext}`;
* targets, and how to run programs built for them;
* modules, separate compilation, the preprocessor;
* error messages and exit codes;
* using `ac` from a Makefile.

## The command line

`ac -h` prints a summary:

```text
A compiler 0.1.0 (version code 1)  -  Aytict, https://aytict.fi
Usage: ac [options] source.a          compile a program
       ac -c [options] source.a       compile to an object file (.ao)
       ac [options] a.ao b.ao ...     link object files into a program

Options:
  -o FILE     output file (default: NAME-VERSION-RELEASE.EXT)
  -t TARGET   linux (default) | windows | android | linux-arm64 | android-x64 |
              linux-riscv64 | android-riscv64 | linux-loongarch64 | android-loongarch64
              linux = linux-x64, android = android-arm64, windows = windows x64
  -c          compile to an object file instead of a program
  -D NAME[=V] define a preprocessor macro (may be repeated)
  -E          print the preprocessed source and stop
  -v CODE     version code used in the default output name (default 1)
  -r TYPE     release type used in the default output name (default debug)
  -h          show this help
  --version   show the compiler version
```

There are three ways to use it, and the compiler picks the right one from the file names you give it:

| You write | The compiler |
|---|---|
| `ac prog.a` | compiles `prog.a` (and every file it imports) into an executable |
| `ac -c unit.a` | compiles one unit into an object file `unit-1-debug.ao` |
| `ac a.ao b.ao -o prog` | links object files into an executable |

The compiler reads **no environment variables** and no configuration file. Everything it does is decided by the command line and the source.

## Compile and run

{{sample start/hello}}

```sh
ac hello.a
./hello-1-debug.elf
```

```text
Hello from A!
```

The executable is written into the **current directory**, not next to the source file: `ac sub/hello.a` writes `hello-1-debug.elf` here. A successful compilation prints nothing and exits with status 0.

## Output names

The default name of the output file is

```text
{app_name}-{version-code}-{release-type}.{ext}
```

* **app_name** is the name of the source file without `.a`;
* **version-code** is the number you give with `-v` (default `1`): the build number of your application;
* **release-type** is the word you give with `-r` (default `debug`), normally `debug` or `release`;
* **ext** depends on the target: `.elf`, `.exe`, `.bin`, ...

`-v` and `-r` change nothing in the generated code: they only name the file. That makes it easy for build scripts to produce files like `shop-42-release.exe` that say what they are:

```sh
ac -t windows -v 12 -r release hello.a        # hello-12-release.exe
```

With `-o` you choose the whole name yourself and `-v`/`-r` are ignored:

```sh
ac -o /tmp/hello hello.a                      # exactly /tmp/hello
```

## Targets

`-t` chooses the operating system and the CPU. These are the real names that the compiler wrote when `hello.a` was compiled for every target (the file `hello-1-debug.*` in each case):

| `-t` | System and CPU | Output file |
|---|---|---|
| `linux` (default), `linux-x64` | Linux, x86-64 | `hello-1-debug.elf` |
| `linux-arm64` | Linux, ARM64 (AArch64) | `hello-1-debug.arm64.elf` |
| `linux-riscv64`, `linux-rv64` | Linux, RISC-V 64 | `hello-1-debug.riscv64.elf` |
| `linux-loongarch64`, `linux-la64` | Linux, LoongArch64 | `hello-1-debug.loongarch64.elf` |
| `windows`, `win`, `win64` | Windows, x86-64 | `hello-1-debug.exe` |
| `android`, `android-arm64` | Android, ARM64 | `hello-1-debug.bin` |
| `android-x64` | Android, x86-64 | `hello-1-debug.x64.bin` |
| `android-riscv64`, `android-rv64` | Android, RISC-V 64 | `hello-1-debug.riscv64.bin` |
| `android-loongarch64` | Android, LoongArch64 | `hello-1-debug.loongarch64.bin` |

::: note
`android-loongarch64` is accepted by the compiler and by its test runner, but it is not part of the target guide (see [Targets](#chap-targets)), so treat it as experimental. An unknown name gives `ac: error: unknown target, use linux, windows, android, linux-arm64, android-x64, linux-riscv64, android-riscv64 or linux-loongarch64`.
:::

Every executable is **static**: it talks to the operating system directly and needs no libc and no dynamic loader. The program below is the same Linux executable as above, copied into an otherwise empty directory and started with `chroot`, so nothing but the file itself is visible to it:

```sh
mkdir root && cp hello-1-debug.elf root/hello
sudo chroot root /hello
```

```text
Hello from A!
```

### Running programs for other targets

You can compile for every target on your Linux x86-64 machine, but you can only run a result where it belongs. The usual helpers:

| Target | How to try it on an x86-64 Linux machine |
|---|---|
| ARM64, RISC-V 64, LoongArch64 Linux | QEMU user mode: `qemu-aarch64`, `qemu-riscv64`, `qemu-loongarch64` (Debian package `qemu-user`) |
| Windows | Wine: `wine64 hello-1-debug.exe` |
| Android | Copy to a device or emulator: `adb push`, then `adb shell` (or Termux) |

Here are three programs compiled with `-t linux-arm64`, `-t linux-riscv64` and `-t linux-loongarch64`, each started through its QEMU emulator, and the Windows program under Wine. Same source, same output:

```sh
ac -t linux-arm64 -o hello.arm64 hello.a && qemu-aarch64 ./hello.arm64
ac -t linux-riscv64 -o hello.rv hello.a && qemu-riscv64 ./hello.rv
ac -t linux-loongarch64 -o hello.la hello.a && qemu-loongarch64 ./hello.la
ac -t windows -o hello.exe hello.a && wine64 hello.exe
```

```text
Hello from A!
Hello from A!
Hello from A!
Hello from A!
```

(The first start of Wine in a new user account prints a few lines about creating its configuration; the program output is the last line.)

The details of every platform are in [Targets](#chap-targets). To branch on the target inside a program, use the predefined constants `__OS` and `__ARCH` (see [the preprocessor and assembly chapter](#chap-preprocessor-and-assembly)).

## Modules and where the compiler looks for them

`import json;` makes a module of the standard library available. Those modules are **inside the compiler**: no file is read, so a program never breaks because a library file is missing.

For your own modules the compiler looks, in this order, in

1. the directory of the file that has the `import`,
2. `lib/` (relative to where you run `ac`),
3. `/usr/lib/a/`,
4. `/usr/local/lib/a/`.

A program that is split over two files in one directory needs no special command:

{{sample lang/modules_demo}}

`ac main.a` finds `greeter.a` next to it and compiles both. The `lib/` directory is looked up relative to the directory where you **run** `ac`, not relative to the source file. A module that is nowhere to be found stops the compilation with `main.a:1: error: cannot find the imported file 'mymod.a'`. (The Debian package creates the empty directory `/usr/lib/a/` as a place for your own system-wide modules.) The module language features, including `.am` module files and `a_import`, are covered in [Enums and modules](#chap-enums-and-modules).

## Separate compilation: objects and the linker

Large projects can be compiled one unit at a time and linked at the end, like in a C toolchain. The units share their declarations through a header file that every unit includes:

```c
// util.h
int add(int a, int b);
extern int counter;
```

```c
// util.a
#include "util.h"
int counter = 100;
int add(int a, int b) { return a + b; }
```

```c
// main.a
#include "util.h"
int main() {
    printlnInt(add(20, 22));
    return counter - 100;
}
```

```sh
ac -c util.a -o util.ao
ac -c main.a -o main.ao
ac main.ao util.ao -o prog
./prog
```

```text
42
```

The objects are tiny (here 184 and 332 bytes) because the standard library is **not** part of an object: the link step compiles the parts of it that the objects use, so there is only one copy and library state such as the heap is shared.

::: warning
Do not `import` a user module from two units that you compile separately: each unit would contain its own copy, and the link step fails with `ac: error: duplicate definition of 'util.square'`. Put shared declarations in a header, and put the definitions in exactly one unit. All objects must be made for the same target (`-t`) by the same compiler version; the object records both. The order of the objects on the command line does not matter, and `main` must be defined in exactly one of them.
:::

## The preprocessor from the command line

A C-style preprocessor is built in (`#define`, `#include`, `#if`, `#ifdef`, `#else`, `#endif` ...; see [the preprocessor chapter](#chap-preprocessor-and-assembly)). Two options talk to it:

* `-D NAME` or `-D NAME=VALUE` defines a macro before the first line is read. `-D NAME` alone gives it the value 1. You can repeat it.
* `-E` prints the preprocessed source and stops: the quickest way to see what a macro or an `#if` did.

Take this program:

```c
#define GREETING "hi"
#ifdef DEBUG
int level() { return 2; }
#else
int level() { return 1; }
#endif
int main() { println(GREETING); printlnInt(level()); return 0; }
```

```sh
ac -E -D DEBUG pp.a
```

```text


int level() { return 2; }



int main() { println("hi"); printlnInt(level()); return 0; }
```

The lines of the directives became empty lines, so line numbers in error messages still match your file. Without `-E`, `ac -D DEBUG pp.a -o pp && ./pp` prints `hi` and `2`.

## Error messages and exit status

The compiler **stops at the first error** and prints the file, the line, the message, the source line and a caret under the place where it noticed the problem:

```text
bad.a:2: error: expected an expression
      int x = ;
              ^
```

```text
bad2.a:2: error: undeclared identifier 'undefinedName'
      printlnInt(undefinedName);
                 ^
```

Mistakes that are not in a source line have no file name:

```text
ac: error: cannot read the input file
ac: error: no input file (try: ac -h)
```

The exit status of `ac` is **0** on success and **1** on any error, so `make` and shell scripts can rely on `ac file.a && ./run`. Typical messages are `expected ';'`, `undeclared identifier 'x'`, `wrong number of arguments in call`, `member is private to its class 'balance'`, `undefined function 'f'` and `left side of assignment is not assignable`; [the language chapters](#chap-language-reference) mention the errors that belong to each feature.

## The exit status of your program

`main` returns the exit status of the program to the operating system. The shell sees it in `$?`:

```c
int main() { return 7; }
```

```sh
ac ex.a -o ex
./ex; echo "exit=$?"
```

```text
exit=7
```

## Using ac in a Makefile

Because `ac` is a plain command that reads one file and exits with a status, it fits a Makefile directly. This pattern rule builds every `NAME.a` into a program `NAME`:

```make
AC ?= ac

%: %.a
	$(AC) -o $@ $<

all: hello ex
clean:
	rm -f hello ex
```

```text
ac -o hello hello.a
ac -o ex ex.a
```

Run `make` a second time and it says `Nothing to be done for 'all'`. For programs that import their own modules, list the module files as extra prerequisites so that `make` rebuilds when they change: `app: app.a greeter.a`.

To produce release builds for several targets, loop over the target names and let the default name tell the files apart:

```sh
for t in linux windows linux-arm64 android; do ac -t $t -v 12 -r release app.a; done
# app-12-release.elf  app-12-release.exe  app-12-release.arm64.elf  app-12-release.bin
```

## How fast is it?

The compiler is a single native program without any start-up cost. On the machine that built this book (a 2.1 GHz Xeon, one core used) these were typical times:

| Program | Time |
|---|---|
| `hello.a`, 4 lines | 3 to 4 ms (output: 4,170 bytes) |
| `examples/http_server.a`, an HTTP server | 40 ms (162,450 bytes) |
| `examples/gui/showcase.a`, 248 lines with the GUI toolkit | 123 ms (330,931 bytes) |

These are measurements from one machine, not promises; they show the order of magnitude. The executables are small because the compiler removes every function a program does not use.

## Summary

* `ac prog.a` compiles, `ac -c unit.a` makes an object, `ac a.ao b.ao -o prog` links.
* Output files are named `{app}-{version-code}-{release-type}.{ext}` unless you pass `-o`; `-v` and `-r` only change the name.
* `-t` selects one of nine targets; results are static executables that need no libc.
* Imported standard modules live inside the compiler; your own modules are found next to the importing file, then in `lib/`, `/usr/lib/a/` and `/usr/local/lib/a/`.
* For separate compilation share declarations through a header; never import one user module from two units.
* `-D` defines a macro and `-E` shows the preprocessed source.
* The compiler stops at the first error, prints a caret under it and exits with 1.

## Where next

* [Your first programs](#chap-first-programs) begin the language guide.
* [Targets](#chap-targets) has the details for Linux, Windows and Android.
* [How the compiler works](#chap-internals) describes the passes and the code generators.
