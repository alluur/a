# Targets: Linux, Windows and Android

The compiler (`ac`) runs on **Linux x86-64** and writes executables for every target below,
so it doubles as a cross compiler. Pick the target with `-t`:

| `-t` value | Operating system | CPU | Default output name (`hello.a`) | Format |
|---|---|---|---|---|
| `linux` (default), `linux-x64` | Linux | x86-64 | `hello-1-debug.elf` | ELF64, static |
| `linux-arm64` | Linux | AArch64 | `hello-1-debug.arm64.elf` | ELF64, static |
| `windows`, `win`, `win64` | Windows 7+ | x86-64 | `hello-1-debug.exe` | PE32+, console |
| `android`, `android-arm64` | Android | AArch64 | `hello-1-debug.bin` | ELF64, static |
| `android-x64` | Android | x86-64 | `hello-1-debug.x64.bin` | ELF64, static |
| `linux-riscv64`, `linux-rv64` | Linux | RISC-V 64 (RV64GC) | `hello-1-debug.riscv64.elf` | ELF64, static |
| `android-riscv64`, `android-rv64` | Android | RISC-V 64 | `hello-1-debug.riscv64.bin` | ELF64, static |
| `linux-loongarch64`, `linux-la64` | Linux | LoongArch64 | `hello-1-debug.loongarch64.elf` | ELF64, static |

The default name is `{app_name}-{version-code}-{release-type}.{ext}`; change it with `-v CODE`,
`-r TYPE`, or take full control with `-o FILE`:

```sh
ac -t windows -v 12 -r release app.a        # app-12-release.exe
```

The source code is the same for every target. The runtime differences (system calls, command line,
file handles) are hidden behind the standard library and the `__…` built-in functions.

## Linux

Static executables that talk to the kernel directly (no libc, no dynamic loader). They run on any
Linux distribution of the matching CPU, in containers and in minimal environments such as
`FROM scratch`.

```sh
ac -o hello hello.a && ./hello
ac -t linux-arm64 -o hello-arm hello.a      # Raspberry Pi, AWS Graviton, Apple silicon VMs …
```

An ARM64 file can be tried on an x86-64 machine with QEMU user mode emulation
(`sudo apt install qemu-user`, then `qemu-aarch64 ./hello-arm`).

## RISC-V 64 and LoongArch64

Two more CPU families with the same source, the same standard library and the same ABI idea as AArch64
(arguments on the stack in 16 byte slots, `__ARCH` tells the code which CPU it is built for):

| CPU | `__ARCH` | `-t` | Notes |
|---|---|---|---|
| x86-64 | 0 | `linux`, `windows`, `android-x64` | |
| AArch64 (ARM64) | 1 | `linux-arm64`, `android` | phones, tablets, Raspberry Pi, Apple silicon VMs |
| RISC-V 64 | 2 | `linux-riscv64`, `android-riscv64` | needs the base integer set and the M extension (every RV64GC chip); no floating point or compressed instructions are used |
| LoongArch64 | 3 | `linux-loongarch64` | Loongson 3A5000 and later |

Both are static Linux ELF files without libc, using the generic Linux system call numbers (the ones of AArch64);
differences such as `renameat2`, `statx` (LoongArch has no `stat`) and the `O_DIRECTORY` flag value are handled by the
standard library. They run on real hardware or under QEMU user mode:

```sh
ac -t linux-riscv64 -o hello.rv hello.a && qemu-riscv64 ./hello.rv
ac -t linux-loongarch64 -o hello.la hello.a && qemu-loongarch64 ./hello.la
```

The complete test-suite passes on all of them (`TARGET=linux-riscv64 tests/run.sh`, `TARGET=linux-loongarch64 tests/run.sh`).
Not supported (yet): 32-bit CPUs (A's `int` is 64 bits), macOS / iOS (Mach-O, code signing) and the BSDs.

## Windows

PE32+ console executables importing only `kernel32.dll` (`GetStdHandle`, `ReadFile`, `WriteFile`,
`CreateFileA`, `CloseHandle`, `ExitProcess`, `GetCommandLineA` and about 40 more for time, files, directories, processes,
pipes, memory, environment) and `ws2_32.dll` (Winsock, for the `net` family of modules: sockets, UDP, time limits, polling, host name lookup) and `iphlpapi.dll` (adapter, ARP, route and connection tables, ICMP echo). The other functions are reached through the
`__winapi` / `__winapix` built-ins by import-table slot. The C library (`import clib;`) runs on Windows too: `system`,
`popen`, `fopen`, `stat`, `opendir`, `getenv` ... are implemented with these imports. Not available: `fork`, `kill`, `link`,
`symlink` and signals (they fail with `ENOSYS`). The image is linked at
`0x140000000` without ASLR; it reserves an 8 MiB stack and probes the stack for large frames the
way `__chkstk` does. Command line arguments are parsed with the standard Windows rules, so
`argv` works as expected.

```sh
ac -t windows -o hello.exe hello.a
```

* Output is raw bytes. If you print non-ASCII text, run the console in UTF-8 mode (`chcp 65001`).
* On Linux you can test the result with Wine: `sudo apt install wine64`, then
  `WINEDEBUG=-all wine64 hello.exe` (on Debian/Ubuntu the binary is `/usr/lib/wine/wine64`).

## Android

Android is Linux underneath, so A produces **static native executables with raw system calls**.
Modern phones and tablets are ARM64, hence `-t android` means AArch64; `-t android-x64` is for
x86-64 devices, emulators and Chromebooks.

Run a program from a computer with `adb`:

```sh
ac -t android -o hello.bin hello.a
adb push hello.bin /data/local/tmp/hello
adb shell chmod 755 /data/local/tmp/hello
adb shell /data/local/tmp/hello
```

Or directly on the phone inside [Termux](https://termux.dev) (copy the file, `chmod +x`, run it).

Notes

* ELF segments are aligned to 16 KiB, so the files also load on devices with 16 KiB pages
  (Android 15+) as well as on 4 KiB devices.
* Executables must be started from a location that allows execution (`/data/local/tmp`, Termux's
  home). Android blocks execution from shared storage (`/sdcard`) and from app data directories of
  other apps.
* These are command line programs. **Building an installable `.apk` is not supported yet**; it
  requires a shared library output with an Android entry point, a binary manifest and
  signing. That is on the roadmap.
* The executables were verified under QEMU user mode emulation of AArch64 and natively for x86-64.
  If you run them on a real device and see a difference, please report it.

## Testing every target

The repository's test-suite is target-aware:

```sh
make test                                   # native
TARGET=windows       tests/run.sh           # through Wine
TARGET=linux-arm64   tests/run.sh           # through qemu-aarch64
TARGET=android       tests/run.sh           # through qemu-aarch64
TARGET=android-x64   tests/run.sh           # native
make test-all                               # all of them
```

Install the helpers on Debian/Ubuntu with `sudo apt install nasm qemu-user wine64`.
