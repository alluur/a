# Welcome to A

A is a small, C-like systems programming language with a compiler written in x86-64 assembly. You write a program, run one command, and get a finished native executable: no C compiler, no assembler, no linker and no C library are involved, neither to build the compiler nor to use it.

This book is the complete guide to the language, the compiler and everything that ships with them: the standard library, networking, graphical programs, terminal programs and the AIDE editor. It is written by [Aytict](https://aytict.fi), the company that makes A.

**In this chapter**

* what you get when you install A, and what you do not get (yet);
* a first look at the language on one page;
* how the book is organised and how to read it.

## What you get

| Piece | What it is |
|---|---|
| **`ac`** | The compiler: one static program of about 3 MB. It reads A source and writes executables (ELF for Linux and Android, PE for Windows) by itself, with a built-in preprocessor and a built-in linker. Compiling "Hello, world" takes a few milliseconds. |
| **Eight documented targets** | Linux on x86-64, ARM64, RISC-V 64 and LoongArch64; Windows on x86-64; Android on ARM64, x86-64 and RISC-V 64. The same source compiles for all of them. |
| **The standard library** | More than 100 modules written in A and compiled into your program: text, collections, numbers, JSON, regular expressions, cryptography, TLS 1.3, TCP/UDP/HTTP/WebSocket, the C library and more. Only what a program really uses ends up in its executable. |
| **GUI programming** | A 2D graphics library, a widget toolkit, a display server with a window manager, and a code editor widget set, all written in A. |
| **Terminal programs** | A toolkit for full screen text programs with mouse, colours and widgets. |
| **AIDE** | An IDE for A in two versions, in the terminal and in a window, with file tree, line numbers, colour themes and one key to build and run. |
| **Editor support** | Syntax files for Vim and nano, and a bash completion for `ac`. |

## A first look

Here is a whole program that uses most of the basic ideas. Read it once; every part is explained later in the book.

{{sample start/tour}}

What to notice:

* The program starts in `main`, like C. The statements look like C too: `for`, `if`, `else if`, `switch`, `continue`, `return`.
* `int` is a **64-bit** integer. `bool` is a real type. Everything starts as zero, locals and heap memory included.
* A `struct` has public members, a `class` has private members unless you say `public`.
* `Color.Blue` is the third value of the enum: `Green = 5` restarts the counting, so `Blue` is 6.
* Objects can live on the stack (`Stack s;`) or on the heap (`new Point`).
* Functions can be used before they are defined; there are no prototypes to maintain.
* `print`, `println`, `printInt` and `printlnInt` come with every program.

## What A is not (yet)

An honest list helps you decide whether A fits your project.

* **There is no `float` or `double` type.** Floating point numbers are 64-bit patterns stored in an `int`, and arithmetic is done by functions (`dadd`, `dmul`, `sqrt` ...) in software. The results are exact and identical on every target, but slower than hardware floating point. See [the C library tour](#chap-c-library-tour).
* **There is no garbage collector.** Memory from `new` and `alloc` is never freed; programs that run for a long time use `malloc` and `free`. See [Memory and pointers](#chap-memory-and-pointers).
* **There is no bounds checking.** Pointers are plain addresses, as in C. The type checking is light: pointer types convert freely.
* **The compiler runs on Linux x86-64.** It produces programs for the other systems, but to compile on Windows or macOS you use WSL, a container or a virtual machine.
* **Android programs are plain executables** (for `adb shell` or Termux). Packaging as an `.apk` is not implemented.
* **TLS and the cryptography are written from scratch** in A and have not had an independent security audit. Use them for learning, tools and internal services; for high-stakes systems, add your own review.

## How the book is organised

| Part | What is in it |
|---|---|
| **Welcome** | This chapter, [installing A](#chap-install) and [the compiler `ac`](#chap-compiler). |
| **The A language** | A guided tour of every feature, from [your first programs](#chap-first-programs) to [memory](#chap-memory-and-pointers) and [the preprocessor](#chap-preprocessor-and-assembly), then the complete [language reference](#chap-language-reference). |
| **The standard library** | [Text](#chap-text-and-strings), [collections](#chap-collections-and-algorithms), [numbers](#chap-numbers), [data formats](#chap-data-formats), [system programming](#chap-system-programming), [cryptography](#chap-cryptography) and [the C library](#chap-c-library-tour). |
| **Networking** | [Sockets, addresses and packets](#chap-networking), then [HTTP, WebSocket and TLS](#chap-http-websocket-tls). |
| **Graphics and GUI programming** | [Drawing](#chap-graphics), [your first windows](#chap-gui-basics), [more widgets](#chap-gui-more-widgets), [complete applications](#chap-gui-programs), [the display server](#chap-display-server), [network and web widgets](#chap-gui-net-and-web), [code editor widgets](#chap-code-editor-widgets) and the [GUI reference](#chap-gui-reference). |
| **Terminal programs** | [Full screen programs in the terminal](#chap-terminal-ui) and the [TUI reference](#chap-tui-reference). |
| **The AIDE editor** | How to use the IDE and how it is built. |
| **Targets and internals** | [Every target in detail](#chap-targets) and [how the compiler works](#chap-internals). |
| **Appendices** | A [quick reference card](#chap-quick-reference) and the generated [library reference](#chap-api): every public function of every module. |

You do not have to read in order. If you know C, skim the first language chapters and go to the part you need. If you are new to programming, read chapters 4 to 10 in order and type in the examples.

## How to read the listings

Every code listing in this book comes from a file that was **compiled and run when the book was built**, and the output under it is what the program really printed. The first line of a listing is its title; the name of the sample file is on the right.

{{sample start/hello}}

You can type this into a file `hello.a`, compile it with `ac hello.a` and run the result. Three kinds of boxes appear in the text:

::: note
A **note** adds background that is good to know.
:::

::: tip
A **tip** shows a shortcut or a good habit.
:::

::: warning
A **careful** box marks something that can go wrong: limits, traps, differences from C.
:::

Programs that need a window, a terminal or a network are shown with a screenshot or a screen capture of what they did when the book was built.

## What was tested

* Every sample in this book was compiled with `ac` and its output was checked against the recorded output; every sample was also compiled for all eight targets.
* The samples were run on Linux x86-64. The compiler's own regression suite (several hundred programs) runs on Linux x86-64, ARM64, RISC-V 64 and LoongArch64 under QEMU, and on Windows under Wine.
* The compiler has **not** been tested on real Windows, Android, RISC-V or LoongArch hardware in the course of writing this book. Reports from real devices are welcome.

## About Aytict

Aytict (https://aytict.fi) is a company from Rauma, Finland that builds software as a service and provides cybersecurity, DevOps and ICT services. A and its operating system AOS are written by the same team. The company's motto is *Modern digital solutions, built on Finnish reliability*, and the compiler tries to live up to it: small, predictable, and with no hidden machinery.

## Summary

* A is a C-like language; its compiler `ac` writes native executables for eight targets on its own.
* The standard library, the GUI toolkit and the editor are written in A and ship with the compiler.
* There is no floating point type, no garbage collector and no bounds checking; know the limits before you start.
* Every listing in this book was compiled and run.

## Where next

* [Installing A](#chap-install) takes five minutes.
* [The compiler `ac`](#chap-compiler) explains every option.
* [Your first programs](#chap-first-programs) start the language guide.
