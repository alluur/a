# Installing A

This chapter gets `ac`, the A compiler, onto your machine, compiles a first program and sets up your editor. It takes about five minutes.

**In this chapter**

* installing from the Debian package, or building from source;
* compiling and running your first program;
* syntax highlighting for Vim and nano;
* what to do on Windows, macOS and Android.

## What you need

The compiler is a static program for **Linux on x86-64**. It needs nothing else: no libraries, no other compilers. Any Linux distribution works, and so does a container, WSL 2 or a virtual machine.

To **build the compiler from source** you need `nasm` (version 2.14 or newer), `ld` from binutils and `make`. The Debian package needs nothing.

## Option 1: the Debian package

The package is named `a-lang` and the file follows the naming scheme of this book, `{app_name}-{version-code}-{release-type}.deb`:

```sh
sudo dpkg -i a-1-release.deb
```

```text
Selecting previously unselected package a-lang.
Preparing to unpack a-1-release.deb ...
Unpacking a-lang (0.1.0-1) ...
Setting up a-lang (0.1.0-1) ...
```

Check that it works:

```sh
ac --version
```

```text
ac 0.1.0
```

The package puts these files on your system:

| Path | Content |
|---|---|
| `/usr/bin/ac` | the compiler |
| `/usr/share/man/man1/ac.1.gz` | the manual page: `man ac` |
| `/usr/share/bash-completion/completions/ac` | tab completion for `ac` options, targets and file names |
| `/usr/share/doc/a-lang/html/` | this book as a web site: open `index.html` in a browser |
| `/usr/share/doc/a-lang/a-book-1-release.epub` | this book as an e-book |
| `/usr/share/doc/a-lang/reference/` | the reference documents as Markdown |
| `/usr/share/doc/a-lang/examples/` | example programs, from "Hello" to a web server and a GUI |
| `/usr/share/vim/vimfiles/` | Vim syntax, file type detection and a colour scheme for A |
| `/usr/share/nano/a.nanorc` | nano syntax highlighting |
| `/usr/lib/a/` | an empty directory: the compiler also looks for your own module files here (see [the compiler](#chap-compiler)) |

The package has no dependencies. It *suggests* `qemu-user`, which lets you run the programs you compile for ARM64, RISC-V or LoongArch on an x86-64 machine. To remove everything again: `sudo dpkg -r a-lang`.

::: note
Some minimal container images (and the images of some cloud tools) tell `dpkg` not to install documentation and man pages. If `/usr/share/doc/a-lang` is missing after the installation, that is the reason, not a broken package. Install with `sudo dpkg -i --path-include='/usr/share/doc/*' --path-include='/usr/share/man/*' a-1-release.deb` to get them.
:::

## Option 2: build from source

Get the source tree of A, then:

```sh
make
```

```text
nasm -f elf64 -i src/ src/ac.asm -o build/ac.o
ld -o build/ac build/ac.o
```

That is all: two commands and about two seconds later `build/ac` is your compiler. To install it:

```sh
sudo make install                   # /usr/local/bin/ac and the man page
make install PREFIX=$HOME/.local    # without root
```

Other targets of the `Makefile`:

| Command | What it does |
|---|---|
| `make test` | runs the compiler's regression tests on this machine |
| `make dist` | writes the release binary `dist/ac-1-release.elf` |
| `make deb` | builds `dist/a-1-release.deb` |
| `make book` | builds this book: the HTML site and `dist/a-book-1-release.epub` (needs `python3` and `pandoc`) |
| `make book-samples` | compiles and runs every code sample of this book and compares the output |

## Your first program

Create a file `hello.a`:

{{sample start/hello}}

Compile it and run the result:

```sh
ac hello.a
./hello-1-debug.elf
```

```text
Hello from A!
```

The compiler wrote a file called `hello-1-debug.elf` into the current directory. The name is made of the source name, a *version code* (`1` by default) and a *release type* (`debug` by default); [the compiler chapter](#chap-compiler) explains how to change each part. To pick a name yourself, use `-o`:

```sh
ac -o hello hello.a
./hello
```

You compiled a real, self-contained program. It does not depend on any library, so you can copy it to another Linux machine and it runs there. (The next chapter even runs one inside an empty directory with `chroot` to prove it.)

## Compile for another system

Add `-t` and a target name. The same source, a different executable:

```sh
ac -t windows hello.a        # hello-1-debug.exe
ac -t linux-arm64 hello.a    # hello-1-debug.arm64.elf
ac -t android hello.a        # hello-1-debug.bin
```

You cannot run those on your Linux x86-64 machine directly. How to test them (QEMU, Wine, `adb`, Termux) is in [the compiler chapter](#chap-compiler) and in [Targets](#chap-targets).

## Set up your editor

**Vim and Neovim.** If you installed the Debian package, Vim already knows A: files that end in `.a` get syntax highlighting, `//` comments and 4-space indent. Without the package:

```sh
mkdir -p ~/.vim && cp -r editors/vim/* ~/.vim/        # Neovim: ~/.config/nvim/
```

Add `syntax on` to `~/.vimrc`. There is also an optional dark colour scheme made for A: `colorscheme a-dark` (it needs a true-colour terminal).

**nano.** The package installs `/usr/share/nano/a.nanorc`; on a system where nano reads that directory nothing else is needed. Otherwise:

```sh
mkdir -p ~/.nanorc.d && cp editors/nano/a.nanorc ~/.nanorc.d/
echo 'include "~/.nanorc.d/a.nanorc"' >> ~/.nanorc
```

**AIDE.** A has its own IDE, with a file tree, line numbers, colour themes and a key that builds and runs your program. It runs in a terminal and in a window; see [the AIDE chapter](#chap-aide).

## On Windows, macOS and Android

* **Windows:** install WSL 2 (a real Linux kernel inside Windows), install the Debian package in it, and compile. With `-t windows` you get a `.exe` that runs on Windows itself. The compiler has not been tested on WSL by the authors of this book; it is a plain static Linux program and should work.
* **macOS:** use a Linux virtual machine or a container (Docker, Podman, Lima, UTM).
* **Android:** compile on Linux with `-t android` (ARM64 phones and tablets) or `-t android-x64` (emulators), copy the file with `adb push` and run it from `adb shell` or from Termux. Packaging an `.apk` is not supported.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `ac: command not found` | Open a new shell, or run `build/ac` by its path. With `make install PREFIX=$HOME/.local` add `$HOME/.local/bin` to your `PATH`. |
| `Exec format error` when you run the program | The file was compiled for another target. Compile without `-t`, or with `-t linux`, for this machine. |
| `./hello: Permission denied` | Run `chmod +x` on the file; the compiler sets the flag itself, but copying through some file systems drops it. |
| `make: nasm: No such file or directory` | Install `nasm` (`sudo apt install nasm binutils make`). |
| An error like `prog.a:3: error: expected ';'` | That is a mistake in your program; the line and a caret show where. See [compile errors](#chap-compiler). |

## Summary

* Install the compiler with `sudo dpkg -i a-1-release.deb`, or build it with `make` in two seconds.
* `ac hello.a` writes `hello-1-debug.elf`; `-o` chooses the name; `-t` chooses the target system.
* The Debian package also contains this book, the examples, the manual page, shell completion and editor syntax files.
* The compiler runs on Linux x86-64; the programs it makes run on the systems of the target you choose.

## Where next

* [The compiler `ac`](#chap-compiler): every option, targets, separate compilation, error messages.
* [Your first programs](#chap-first-programs): printing, reading input, command line arguments.
