# System programming

A program rarely lives alone. It reads files, looks at its environment, starts other programs, waits for signals, runs on several processor cores and answers to a command line. This chapter shows the parts of the standard library that talk to the operating system and the processor, and the two small helpers that every tool needs: a logger and a test harness.

Most samples in this chapter run on Linux. Where a function exists on Linux and Android only, the text says so.

In this chapter:

* files and directories with `os` and the standard library;
* environment variables, child processes, pipes and signals;
* measuring time;
* threads (`thread`) and the processor (`cpu`): atomic operations, locks, CPU identification;
* command lines (`cli`), logging (`log`) and unit tests (`testing`).

::: note

The samples use the module names `os`, `thread`, `cpu`, `cli`, `log` and `testing`, which are written in A and compiled into your program when you import them. Functions with C names (`fork`, `getenv`, `signal`, `open`) come from the C library modules; they are described in more detail in [the C library tour](#chap-c-library-tour).

:::

## Files and directories

The standard library, which every program has without an import, can read and write whole files (`readFile`, `writeFile`), test whether a file exists (`fileExists`), delete one (`fileDelete`) and create a directory (`makeDir`). The `os` module adds what is missing: the working directory, the size of a file, renaming, and listing a directory.

| Function | What it does |
|---|---|
| `os.getCwd()` | the working directory as a new heap string, `null` on error |
| `os.fileSize(path)` | the size in bytes; `-1` if the file cannot be opened, and (on ordinary file systems) for a directory |
| `os.rename(from, to)` | renames or moves a file or directory; `true` on success |
| `os.listDir(path, names, max)` | stores the names of the entries (without `.` and `..`) in `names`; returns how many, `-1` on error |

### The working directory

`os.getCwd()` returns the directory your program was started in, or the one you changed to. Changing it is a C library function: `chdir`.

{{sample sys/os_cwd}}

**What to notice.**

* The sample prints only the last name of the path. A full path is different on every machine, and a program whose output depends on it cannot be checked.
* The returned string is a copy that you own. `os.getCwd()` before and after a `chdir` gives two different strings.

### Size, rename and delete

{{sample sys/os_files}}

**What to notice.**

* `os.fileSize` has no way to say "this is a directory", so on ordinary file systems it returns `-1` for one, just like for a file that does not exist. Special directories can behave differently: on Linux `os.fileSize("/proc")` is `0`. When you must tell the two apart, use `stat` and `S_ISDIR` from `cunistd` (see [the C library tour](#chap-c-library-tour)).
* On Linux, `os.rename` replaces an existing destination. On Windows it refuses. If your program must run on both, delete the destination first.
* `fileDelete` returns `false` for a file that is already gone, so deleting twice is safe.

### Listing a directory

{{sample sys/os_listdir}}

**What to notice.**

* You provide the array and the number of slots. `os.listDir` never writes more than `max` names. When the directory has more entries, the rest is silently left out, so give it a generous array.
* Each name is a new heap string.
* The order is whatever the file system returns. Sort the names (the `sort` module has `sortStrings`) before you print them or compare them.

### Walking a tree

Combine `listDir` and `fileSize` and you have a recursive walk: an entry with a size of `-1` is treated as a directory. (A file that you are not allowed to open also gives `-1`; the walk then tries to list it, `listDir` fails with `-1`, and nothing is printed below it.)

{{sample sys/os_walk}}

### Handles for large files

`readFile` reads everything into memory. For big files or for appending, open a handle with `fileOpen` and read or write in pieces.

{{sample sys/file_handles}}

**What to notice.**

* The three modes are `FILE_READ`, `FILE_WRITE` (creates or truncates) and `FILE_APPEND`.
* `fileRead` returns `0` at the end of the file. A negative handle means the open failed.
* A does not buffer the handle functions: each `fileWrite` is a system call, and the data is in the file as soon as it returns. If you write many small pieces, collect them in a buffer first, or use `FILE*` from the C library, which buffers (see [the C library tour](#chap-c-library-tour)).

## The environment

Every program receives a set of `NAME=value` strings from the program that started it. `getenv` reads one, `setenv` changes it for your program and for the children it starts later, and `environ()` gives you the whole list.

{{sample sys/env_vars}}

**What to notice.**

* `getenv` returns `null` for a variable that is not set, and a pointer to the value otherwise. The text belongs to the library: do not change or free it, and copy it (`strdup`) if you need your own version.
* `setenv(name, value, false)` keeps an existing value. The default `true` replaces it.
* `getEnv(argc, argv, name)` is the older function of the standard library. It needs `argc` and `argv` to find the environment of the process, returns a new copy of the value, and does not see changes made by `setenv`. Prefer `getenv`.
* Your program can set at most 64 different names with `setenv`; after that `setenv` returns `-1`.
* A change affects your own process and the children you start afterwards. It never changes the parent's environment, or the shell you started from.

## Child processes

On Linux and Android a program can start other programs. The classic way has three steps: `fork` makes a copy of the running program, the copy replaces itself with another program (`exec`), and the parent waits for the end (`waitpid`). The functions come from the `cunistd` module.

### fork and waitpid

`fork` returns twice. In the child it returns `0`, in the parent it returns the process id of the child.

{{sample sys/proc_fork}}

**What to notice.**

* The child ends with `_exit`, which leaves at once. `exit` also runs the exit handlers that the program registered with `atexit` and flushes buffered files, which you rarely want in a copy.
* `waitpid` stores a status word. The exit code is in bits 8 to 15. The low 7 bits are the number of the signal that killed the process, or 0.
* A parent that never waits leaves a zombie behind: a finished child whose exit status nobody has collected. It stays in the process table until the parent ends.

### Talking through a pipe

A pipe is a one-way channel in the kernel: `pipe` gives you two descriptors (a descriptor is the small number that the system uses for an open file or pipe), one to read and one to write. After a `fork`, both processes have both ends. Each side closes the end it does not use.

{{sample sys/proc_pipe}}

**What to notice.**

* The parent closes its copy of the write end *before* it reads. A pipe ends only when every write end is closed. If the parent kept its own, `read` would wait forever.
* `read` returns `0` at the end of the pipe, and `-1` on an error.
* Data is a stream of bytes, with no message boundaries. Read in a loop until `0`, as the sample does.

### Replacing the program: exec

{{sample sys/proc_exec}}

**What to notice.**

* `execvp` searches the directories of `PATH`. `execv` wants a path with a `/` in it (`execv("echo", ...)` fails, `execv("/bin/echo", ...)` works). Both take a list of strings that ends with `null`, and the first entry is the program name.
* They only return when they fail. The code after `execvp` is the error path; `127` is the exit code that shells use for "command not found".
* The output of the child goes to the same standard output as yours. `print` and `println` do not buffer, so the order of lines is the order of events.

### The easy way: system and popen

When you want to run a shell command and do not care about the details, use `system` (runs the command and returns its exit code) or `popen` (gives you a stream that reads the output of the command, or writes to its input).

{{sample sys/proc_system_popen}}

**What to notice.**

* `system` returns the exit code of the command, `128 + signal` if it was killed and `-1` if it could not be started.
* `pclose` waits for the command and returns its exit code.
* The commands go through the shell (`/bin/sh -c` on Linux), so quoting rules of the shell apply. Never put text from an untrusted source into a command line: it can run anything.

::: warning

On this branch a stream opened with `popen(command, "w")` has a problem: the command also inherits the write end of its own input pipe (the pipe is not marked close-on-exec, which would make the system close it when the new program starts). A command that reads until the end of its input (`sort`, `cat`, `tr`) therefore never sees the end, and `pclose` waits forever; `popen("tr a-z A-Z", "w")` is an example. A command that stops reading by itself is fine: the sample uses a shell `read`, and `head -n 1` also works. When you need to feed a program that reads to the end, use `pipe`, `fork`, `dup2` and `execvp` as in the earlier samples: in the child, `dup2` the read end onto descriptor 0, close both pipe ends, and in the parent close the write end after you have written.

:::

## Signals

A signal is a small message that the kernel delivers to a process: "the user pressed Ctrl-C" (`SIGINT`), "please end" (`SIGTERM`), "a timer ran out" (`SIGALRM`), or one that another process sent with `kill` (`SIGUSR1`, `SIGUSR2`). `signal` installs a function that runs when the signal arrives, or `SIG_IGN` to ignore it, or `SIG_DFL` for the default action.

{{sample sys/proc_signals}}

**What to notice.**

* The handler takes the signal number. Do very little in it: set a flag, return, and look at the flag in your main loop. A handler can run in the middle of anything, including in the middle of `alloc`.
* `raise(sig)` sends a signal to yourself. `kill(pid, sig)` sends one to any process you may signal; `getpid()` is your own id.
* The default action of `SIGUSR1` ends the process. The parent sees this in the status that `waitpid` returns: the low bits hold the signal number (10 for `SIGUSR1` on Linux).
* `SIGKILL` cannot be caught or ignored.
* Signals do not exist on Windows. There `signal`, `kill` and `alarm` fail with `ENOSYS`.

## Time

`millis()` counts milliseconds from an arbitrary starting point. Only the difference of two readings means something, which makes it the right tool for measuring how long something took. `sleepMs(n)` waits.

{{sample sys/time_elapsed}}

**What to notice.**

* The sample checks `elapsed >= 50` rather than printing the time. A program that prints how long it took has a different output every run. For examples and tests, check a bound instead.
* `cpu.cycles()` reads the processor's own counter. It is finer than `millis()` but its unit is not seconds: on x86-64 it reads the time stamp counter (the `rdtsc` instruction), on other processors a counter that ticks at a fixed rate. Compare two readings; do not turn one into seconds without knowing the rate of your machine.
* Calendar time (dates, time zones, `strftime`) is in `ctime`: see [the C library tour](#chap-c-library-tour). The `datetime` module has a date and time class: see its [API reference](#api-datetime).

## Threads

A thread is a second flow of control inside your program. All threads share the same memory, so they can work on one array at the same time. They also share all the problems of shared memory.

The `thread` module starts real operating system threads on Linux and Android. A thread runs a function that takes one `int` and returns an `int`.

| Function | What it does |
|---|---|
| `thread.spawn(fn, arg)` | starts `fn(arg)` in a new thread; returns a `Thread*`, `null` if it could not be started |
| `thread.join(t)` | waits for the end and returns the function's result (joining twice is fine) |
| `thread.finished(t)` | `true` if the thread has ended |
| `thread.parallelFor(n, body, workers)` | calls `body(i)` for `i` from 0 to `n - 1` on `workers` threads (0 = one per processor; at most 64, and never more than `n`) |
| `thread.cpuCount()` | the number of processors the program may use |
| `thread.currentId()`, `thread.yield()` | the id of the calling thread; give the processor away |
| `thread.supported()` | `true` where threads are real |

::: warning

The runtime of A is not thread safe. Do not call `alloc`, `new`, `print`, `printf` or the file functions from several threads at the same time. Let the threads compute into arrays and counters, and print from the main thread. When a thread must print, guard the call with a lock (a sample below does that).

:::

### Starting threads

{{sample sys/thread_basic}}

**What to notice.**

* The function is passed as a value: `thread.spawn(sumTo, 100)`. To pass more than one number, put them in a struct and pass its address as the `int`.
* Each thread has its own stack of 1 MiB (1,048,576 bytes). The main thread has the stack that the system gives every program, 8 MiB with the usual settings (`ulimit -s`). A thread that uses more than its 1 MiB, by recursing deeply or by having big local arrays, crashes the program: a test with a function that has a 1,000 byte local array stopped at about 1,000 calls in a thread, and at about 8,000 in the main thread. Keep large arrays out of the local variables of thread functions.
* On Windows `thread.supported()` is `false` and `spawn` runs the function to its end before it returns. Programs that only compute and join give the same result there.

### Atomic operations

If four threads each do `hits = hits + 1`, updates get lost: two threads read the same old value, and both write the same new one. An atomic operation reads, changes and writes in one indivisible step. The `cpu` functions work on an `int` (64 bits wide in A).

{{sample sys/thread_atomic}}

**What to notice.**

* `cpu.atomicAdd(&n, 1)` returns the value *before* the addition. That makes it a ticket machine: every caller gets a different number.
* `cpu.atomicCas(&n, expected, desired)` ("compare and swap") stores `desired` only if `n` still holds `expected`. It returns the old value either way, so you can see whether it worked.
* The other operations are `atomicSub`, `atomicInc`, `atomicDec`, `atomicSwap`, `atomicLoad` and `atomicStore`. All of them are full memory barriers.

### Locks

When several fields must change together, one atomic number is not enough. A lock lets one thread at a time into a piece of code. The `cpu` module has a spin lock: a plain `int` that is `0` when free and `1` when taken.

{{sample sys/thread_lock}}

**What to notice.**

* `cpu.lock(&flag)` waits (spins) until it gets the lock. `cpu.tryLock(&flag)` returns `false` at once if the lock is taken. `cpu.unlock(&flag)` releases it.
* A spin lock wastes processor time while it waits, so hold it for a few instructions only. The library has no mutex that puts a thread to sleep and no condition variable: for waiting you have the spin lock, `cpu.pause()` and `thread.join`.
* Nothing connects the lock to the data. The rule that every access to `account` takes `guard` first is a rule of your program.

### Splitting a loop

{{sample sys/thread_parallel_for}}

**What to notice.**

* The body must not depend on the order of the iterations. Each `i` writes its own array element here, so nothing needs a lock.
* `thread.cpuCount()` depends on the machine, so the sample prints only a fact that is always true.
* The call returns when every iteration is done.

### A producer and a consumer

A queue between two threads is a classic. This one is a ring of four slots protected by a spin lock. The producer waits when it is full, the consumer waits when it is empty.

{{sample sys/thread_producer_consumer}}

**What to notice.**

* Both sides wait by calling `cpu.pause()` in a loop. It tells the processor that this is a spin loop.
* `pop()` returns `-1` for "empty", so `0` can be the "no more items" marker.
* Only the main thread calls `printf`, as the warning above demands.
* Because of the single producer and single consumer, the order of the output is always the same. This sample needs real threads: on Windows, where `spawn` runs the function first, the producer would wait forever for a consumer that does not run yet.

### Output from several threads

When threads must print, a lock keeps each line in one piece. The order of the lines still depends on timing, so the sample says `// book: sorted`, which tells the checker to compare the lines in sorted order.

{{sample sys/thread_print_sorted}}

**What to notice.**

* The sleeps make worker 3 finish first. Run it again and the order may change, but never the content of a line.
* The sum of the results is the same every time, because it is computed in `main` in a fixed order from the values that `join` returns.

## The processor

The `cpu` module is written with the `asm` feature of the language: small pieces of machine code for x86-64, ARM64, RISC-V 64 and LoongArch64. You have already used its atomic operations and locks. It also tells you what you are running on.

| Function | What it does |
|---|---|
| `cpu.arch()`, `cpu.archName()` | the CPU the program was built for (`cpu.ARCH_X64`, `ARCH_ARM64`, `ARCH_RISCV64`, `ARCH_LOONGARCH64`) and its name |
| `cpu.cycles()` | a monotonic counter |
| `cpu.pause()`, `cpu.fence()` | spin loop hint; full memory barrier |
| `cpu.cpuid(leaf, sub, reg)` | x86-64 CPUID instruction (`reg` 0 to 3 is eax, ebx, ecx, edx); `0` on other CPUs |
| `cpu.vendor()`, `cpu.brand()` | x86-64: the vendor string and the marketing name; `""` elsewhere |
| `cpu.hwcap()`, `cpu.hwcap2()` | Linux and Android: the capability bits that the kernel reports |

### Which CPU?

{{sample sys/cpu_arch}}

**What to notice.**

* `cpu.arch()` is the architecture of the *build*, not of the machine you run on. A program built for x86-64 and run under an emulator still says x86-64.
* `static if (__ARCH == 0) { ... } else { ... }` decides while compiling. The branch that is not chosen is never compiled, so it may use things that exist on one CPU only. The output shown is that of the x86-64 build.
* The meaning of the `hwcap` bits differs on each CPU; read the kernel's documentation before you test one.

### CPUID

{{sample sys/cpu_cpuid}}

**What to notice.**

* The vendor and brand strings are machine specific, so the sample checks their shape (12 characters, not empty) and does not print them. Print them yourself to see what your machine says.
* Leaf 1, register `edx` holds the classic feature bits. Bit 26 is SSE2, which every x86-64 CPU has.
* On other processors the program prints one line and stops. Wrap CPUID code in a check of `cpu.arch()`, as the sample does.

### Memory barriers

Compilers and processors may reorder memory accesses. When one thread hands data to another, a barrier makes sure that the data is written before the flag that announces it.

{{sample sys/cpu_fence}}

**What to notice.**

* Three steps: write the data, `cpu.fence()`, raise the flag. The reader waits for the flag and then reads the data.
* `cpu.atomicStore` and `cpu.atomicLoad` for the flag make sure that the access itself is not torn or optimised away.
* The `spins > 0` check shows that the main thread really had to wait.

## Command lines

A command line program gets its arguments in `main(int argc, char** argv)`: `argc` is the number of words, and `argv[0]` is the program name. For a single flag, the standard library has `hasArg(argc, argv, "-v")` and `argValue(argc, argv, "-o", fallback)`. For anything bigger, use `cli.ArgParser`, which understands

* flags and options with several names: `-v,--verbose`;
* combined short flags: `-ac` means `-a -c`;
* `--name=value` and `-o value`;
* `--` to end the options, and a lone `-` as an ordinary argument;
* `-h` and `--help`, for which it prints the usage itself.

You declare what is allowed with `addFlag(names, help)` and `addOption(names, help, default)`, call `parse(argc, argv)` and then ask: `flag(name)`, `option(name)`, `optionInt(name, fallback)`, `positionalCount()` and `positional(i)`. Any of the names of an option can be used to ask for it.

{{sample sys/cli_basic}}

**What to notice.**

* The `args=` line in the sample tells the build how to run it. The same flags work on a terminal.
* `parse` returns `false` after an error or after `--help`. Return from `main` right away then; the parser has printed what is needed.
* The sample gives three options (`-v`, `--output=report.txt`, `-n 5`) and then two file names. The parser also accepts options after the file names or between them: only `--` stops it.
* `optionInt` turns the text of the option into a number. When the option was not given, the text is the default you declared ("10" for `-n`). Only when the text is not a number do you get your fallback.

### Short flags and the end of options

{{sample sys/cli_short_flags}}

**What to notice.**

* `-ac` is the two flags `-a` and `-c`. A short option that takes a value (`-o`) cannot be part of a combination; it needs its own word.
* After `--` every word is an argument, even when it begins with a dash. That is how users pass a file called `-b`.
* A lone `-` is an argument. By convention programs read standard input for it.

### The help text

{{sample sys/cli_help}}

**What to notice.**

* `--help` prints the usage to standard output and `parse` returns `false`, so the program exits with the code you choose; here it is 1 (`exit=1` in the sample tells the checker).
* The text is built from your declarations: the names, the help strings and the defaults. An empty default is not shown.
* The last line, `-h,--help`, is added by the parser.
* The parser has room for 32 declarations (each `addFlag` or `addOption` counts once, however many names it has) and 64 arguments. It does not tell you when you go over: further declarations are ignored, so using such an option later gives `unknown option`, and further arguments are dropped without a message.

### Mistakes

Errors are reported on standard error, and `parse` returns `false`:

{{sample sys/cli_errors}}

Standard error is not part of the recorded output of a sample. This is what the program writes there:

```text
true : -v file
tool: unknown option -x
false : -x
tool: option needs a value: -o
false : -o
tool: unknown option -v=3
false : -v=3
```

(The first, third, fifth and seventh lines are the standard output of the sample, and the others are the messages of the parser. I merged both streams to show the order.)

**What to notice.**

* The program name that you gave to `ArgParser` starts every message.
* `-v=3` is an error because `=value` only works with long names (`--name=value`).
* For C style option parsing with `getopt`, see [the C library tour](#chap-c-library-tour).

## Logging

The `log` module writes lines with a level to standard error (so that your real output, on standard output, stays clean). The levels from low to high are `DEBUG`, `INFO`, `WARN`, `ERROR` and `OFF`. The default level is `INFO`, so `debug` lines are hidden.

| Function | What it does |
|---|---|
| `log.debug(msg)`, `info`, `warn`, `error` | write one line |
| `log.debugf(fmt, a, b, c, d)`, `infof`, `warnf`, `errorf` | the same with `printf` formatting; exactly four values (pass `0` for the unused ones) |
| `log.setLevel(level)` | hide everything below `level` |
| `log.setFd(fd)` | write to another descriptor or file handle |
| `log.setTimestamps(on)`, `log.setColors(on)` | switch the time stamp and the colours off or on (colours are only used when the output is a terminal) |

### Levels

{{sample sys/log_levels}}

**What to notice.**

* The sample sends the log to standard output with `setFd(1)` and removes the time stamp, so that its output can be recorded. In a real program you would leave both alone.
* The tag has a fixed width (`[INFO ]`, `[WARN ]`), so messages line up.
* `log.setLevel(log.OFF)` silences the log completely.
* Keep messages short. A message of about 2,000 characters is the limit for the plain functions (a longer one is cut and loses its line break), and the `f` functions cut the formatted text at 1,023 characters.

### Formatted messages

{{sample sys/log_format}}

**What to notice.**

* The `f` functions take a format and exactly four values. Text is passed as `(int) text`, like all values of `printf`.
* A message that is not shown costs very little: the formatting is skipped when the level is too low.
* For a message that you build yourself, with more than four values, use `format` and the plain functions.

::: note

A program cannot import both `log` and the C library modules `cstdio` or `cmath`: the C function `log` (the logarithm) has the same name as the module, and the compiler reports `name is already declared as something else: 'log'`. Use the standard library's `printf` and `fileOpen` in programs that use the `log` module.

:::

### A log file and the time stamp

{{sample sys/log_sink}}

**What to notice.**

* `setFd` accepts any open handle, so a file works as a sink. The module does not rotate or close the file; you do.
* A time stamp is 19 characters (`YYYY-MM-DD HH:MM:SS`) followed by a space. The sample checks the shape and not the value, because the value is different every time.

## Unit tests

`testing` is a tiny harness: a few assertions that count what passed, print what failed, and a summary whose result you return from `main`.

| Function | What it does |
|---|---|
| `testing.assertEq(expected, actual, name)` | two numbers are equal |
| `testing.assertStrEq(expected, actual, name)` | two strings are equal (an `actual` of `null` counts as a failure) |
| `testing.check(condition, name)` | any condition |
| `testing.passedCount()`, `testing.failedCount()` | the counters so far |
| `testing.summary()` | prints `N passed, M failed` and returns M |
| `testing.reset()` | sets both counters to 0 |

### A passing test

{{sample sys/testing_basic}}

**What to notice.**

* `assertEq` takes the *expected* value first. A message that reads "expected 4 but got 6" is only right when you keep to that order.
* A test that passes prints nothing. Only the summary line is printed.
* `return testing.summary();` makes the exit code the number of failures, so a script can see that tests failed. An exit code is a byte: 256 failures would look like success. If that can happen to you, return `failed > 0 ? 1 : 0` instead.

### What a failure looks like

{{sample sys/testing_failures}}

**What to notice.**

* Each failure is one line that starts with `FAIL`, then the name you gave, then the two values. `check` has no values to show, so its line has only the name.
* A string that is `null` is shown as `(null)`. The sample also prints its own line with `passedCount()` and `failedCount()` before `summary()`.
* The run goes on after a failure; you see every broken test at once. The summary then says `2 passed, 4 failed` and the exit code is 4 (`exit=4` in the sample).
* Give every assertion a name that says what is *true*: "last in, first out", not "test 3". It is what you will read when it fails.

## Putting it together

A small tool that uses three of the modules: `cli` for the options, `os` for the files and `log` for the messages.

{{sample sys/tool_du}}

**What to notice.**

* The log level follows the `-v` flag: with `-v` the skipped files are mentioned as `DEBUG` lines, without it they are silent.
* The `-m` option is read as a number with a default, `optionInt("--min", 0)`.
* Not giving exactly one directory is reported on standard error and returns 2, a failure to read the directory is a log line and returns 1, success returns 0: three different outcomes with three different exit codes. This is the convention that other programs expect: `0` for success, `1` for a failure, `2` for wrong use. (The sample is not perfect: a mistake that `parse` reports, such as an unknown option, returns 1.)

## Summary

* `os` has four functions: `getCwd`, `fileSize`, `rename` and `listDir`. The rest of file handling is in the standard library (`readFile`, `fileOpen`, ...) and in `cunistd`.
* `getenv`, `setenv` and `environ()` work with the environment. A change only reaches your own process and the processes you start later.
* `fork`, `execvp`, `waitpid` and `pipe` start and connect programs on Linux and Android. `system` and `popen` go through the shell; `popen(cmd, "w")` has a known problem on this branch.
* `signal` installs handlers; keep them short. Signals do not exist on Windows.
* Threads share memory: use `cpu.atomicAdd` and friends for counters and `cpu.lock` for larger pieces of data, and never call `alloc` or `print` from two threads at once.
* `cpu` tells you the architecture of the build and, on x86-64, the CPU vendor and features. Its output is machine specific, so test shapes, not values.
* `cli.ArgParser` handles flags, options, combined short flags and `--help`; `log` writes leveled lines; `testing` counts assertions and gives you an exit code.

## Where next

* [The C library tour](#chap-c-library-tour) covers `cunistd` (files, directories, `getopt`), `cstdio`, `cstdlib` and `ctime` in depth.
* [API reference of os](#api-os), [thread](#api-thread), [cpu](#api-cpu), [cli](#api-cli), [log](#api-log) and [testing](#api-testing).
* [API reference of asys](#api-asys): a lower level system layer with freeable memory, atomic file writing and child processes with pipes.
* [Cryptography](#chap-cryptography) uses `secure` and `hash`, which also talk to the operating system.
