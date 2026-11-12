# The C library tour

A comes with the C library, written in A. If you know C, you already know most of it: `printf` and `scanf`, `fopen` and `fgets`, `strtok`, `qsort`, `malloc`, `strftime`, `getopt`, `sqrt`. The names, the arguments and the results are those of C, with a few changes that come from the language (a 64 bit `int`, no variable argument lists, doubles that travel as bit patterns). This chapter is a hands-on tour: one idea per sample, run it, read the output. The last part ports a small C program to A, step by step.

The complete list of functions is in the reference chapter on the C library (it is generated from the modules). Read this tour to learn how the parts fit, and the reference to look things up.

In this chapter:

* the modules and what they replace;
* characters, limits, errors and assertions;
* strings, memory and number parsing;
* streams, formatted output and input;
* files, directories, `getopt` and wildcards;
* dates and time zones;
* floating point: the `double` type and the C functions, and complex numbers;
* wide characters;
* porting a C program.

## The modules

`import clib;` makes the whole library available. You can also import the modules one by one, which keeps small programs small: only the functions that a program uses end up in the executable. The names go into the global namespace, like the C headers do, so you write `fopen(...)`, not `cstdio.fopen(...)`.

| Module | C headers | Contents |
|---|---|---|
| `cctype` | `<ctype.h>` | `isalpha`, `isdigit`, `toupper` ... (ASCII) |
| `climits` | `<limits.h>` `<stdint.h>` `<stddef.h>` | `INT_MAX`, `UINT32_MAX`, `PATH_MAX`, `NULL` |
| `cerrno` | `<errno.h>` | `errno`, `ENOENT` ..., `strerror`, `perror` |
| `cassert` | `<assert.h>` | `assert`, `assertMsg` |
| `cstring` | `<string.h>` | `memmove`, `strchr`, `strstr`, `strtok`, `strlcpy` ... |
| `cstdlib` | `<stdlib.h>` | `malloc`, `free`, `strtol`, `qsort`, `getenv`, `system`, `div`, `atexit` |
| `cstdio` | `<stdio.h>` | `FILE*`, `fopen`, `fgets`, `fprintf`, `sscanf`, `popen` |
| `ctime` | `<time.h>` | `time`, `gmtime`, `localtime`, `mktime`, `strftime`, `strptime` |
| `cmath` | `<math.h>` `<float.h>` | `sqrt`, `sin`, `pow`, `floor` ... on the bits of a double |
| `cfloat` | (`strtod`, `printf` conversions) | `strtod`, `dtostr`, `printfd` with `%f %e %g %a` |
| `cunistd` | `<unistd.h>` `<sys/stat.h>` `<dirent.h>` `<fcntl.h>` `<signal.h>` `<fnmatch.h>` | `open`, `stat`, `opendir`, `fork`, `signal`, `getopt` |
| `ccomplex` | `<complex.h>` | `cmplx`, `cadd`, `cmul`, `cabs`, `cexp` ... |
| `clocale` | `<locale.h>` | `setlocale`, `localeconv` (only the "C" locale) |
| `cwchar` | `<wchar.h>` `<wctype.h>` | wide characters and strings |

Some C functions are not in a module because every program already has them: `printf`, `exit`, `rand`, `strlen`, `strcmp`, `strcpy`, `strcat`, `memcpy`, `memset`, `atoi`, `abs`. `setjmp` and `longjmp` are built into the language, and `bool` is a type, so there is no `stdbool`.

### A first tour

{{sample clib/clib_tour}}

**What to notice.**

* One `import clib;` gives you files, `scanf`, `qsort`, dates, math, `malloc`, the environment and `system`.
* `qsort` takes a function pointer: the type is `func`, and the comparison receives pointers to two elements as `char*`. Inside, you cast to the real type.
* `fscanf` and friends take the *addresses* of the variables, as in C: `&amount`. Text goes in a `char` array, with no `&`.
* The math line uses `dlit("2")` and `printfd` for a number with a fraction. The part "Floating point" below explains why.

### What is different from C

| In C | In A |
|---|---|
| `int` is 32 bits, `long` 64 | `int` and `long` are the same 64 bit type; `int32`, `uint32` ... when the width matters. `%d` prints a whole 64 bit value |
| `char` is signed (usually) | `char` is an unsigned byte |
| `printf` takes any number of arguments | `printf` and its relatives take up to **eight** values after the format; the `v...` versions (`vprintf`, `vsnprintf`) take an array of values and their count instead of a `va_list`. Your own functions can use `...` with `va_arg(i)` and `va_count()` |
| `scanf` stores through pointers of the right size | every pointer target is 64 bits unless you say `%hhd` (1 byte) or `%hd` (2 bytes) |
| `FILE*`, `stdin`, `stdout`, `stderr` | the same; the standard streams are constants. File output is buffered (4 KiB) and written at `fclose`, `fflush` and exit. `stdout` and `stderr` are not buffered |
| `errno` is a thread local macro | `errno` is a plain global variable with the Linux numbers on every platform |
| `assert(cond)` prints the text of the condition | `assert` is a function and cannot; use `assertMsg` or a macro of your own |
| `const char*`, `const void*` | `char*` and `void*`: the compiler does not accept `const` inside a type |
| octal literals `0755` | there are none: `0755` is the decimal number 755. Write `493`, `0x1ED` or `0b111101101` |
| `malloc` returns uninitialised memory | `malloc` returns zeroed memory |
| the locale changes `printf` and `isalpha` | there is only the "C" locale; text is UTF-8 |
| `double` is hardware | `double` is a type of the language, calculated in software, the same bits on every platform |

Functions that fail return `-1`, `null` or `EOF` and set `errno`, as in C. `fork`, `kill`, `link`, `symlink`, `signal` and `alarm` exist on Linux and Android only; on Windows they fail with `ENOSYS`. `time` zones follow the POSIX `TZ` rules.

## Characters, limits, errors

### Classifying characters

`cctype` has the tests and conversions of `<ctype.h>`. They take an `int` and work on ASCII only.

{{sample clib/ctype_classify}}

**What to notice.**

* Each function gives 0 or 1. `ispunct` is true for printable characters that are neither letters, digits nor the space. `isxdigit` accepts `0-9`, `a-f` and `A-F`.
* The space and the tab are `isspace`, not `isalpha`.

{{sample clib/ctype_convert}}

**What to notice.**

* `toupper` and `tolower` change letters only.
* `digitValue(c, base)` is not in C; it gives the value of a digit in any base up to 36, or `-1` when `c` is not a digit of that base. It is the building block of number parsers.
* The functions know only ASCII. A byte of a UTF-8 text above 127 is not a letter here. For Unicode letters use `iswalpha` of `cwchar` (below) or the `utf8` module.

### Integer limits

{{sample clib/limits_table}}

**What to notice.**

* `INT_MAX`, `LONG_MAX` and `LLONG_MAX` are all 2^63 - 1, because `int` is 64 bits. `INT32_MAX` and the other fixed width names are there for code that cares about exact sizes.
* The unsigned 64 bit values print with `%u`. With `%d` they would show as negative numbers.
* Arithmetic on two `uint32` values wraps at 32 bits, arithmetic on `int` at 64 bits (the last two lines).

### Errors: errno, strerror, perror

{{sample clib/errno_basic}}

**What to notice.**

* A failed call sets `errno` and returns a marker (`null` for `fopen`). `errno` is only meaningful right after a failure; successful calls do not reset it to 0, so set it yourself before a call if you need to tell.
* `strerror(n)` gives the message. The numbers are those of Linux, also on Windows.
* `perror("config")` writes `config: Permission denied` to standard error (the sample does that; the recorded output shows only standard output).

### Assertions

`assert(cond)` stops the program when the condition is false. It writes a message to standard error and ends with exit code 134, the code that a C program gets from `abort`.

{{sample clib/assert_ok}}

{{sample clib/assert_fail}}

**What to notice.**

* `assert` is a function, so it cannot print the text of the condition the way the C macro does. `assertMsg(cond, "what was expected")` lets you say it.
* A has a C style preprocessor, so the `CHECK` macro in the second sample builds the message from the condition: `#cond` makes it a string. The message on standard error is `assertion failed: check failed: x + 1 == 7`.
* Use assertions for conditions that are bugs when false. For errors that can happen in normal use (a missing file, bad input), return an error code.

### The locale

{{sample clib/locale_c}}

**What to notice.**

* There is exactly one locale, "C". `setlocale` accepts `""`, `"C"`, `"POSIX"` and names that end in `.UTF-8`, and always reports "C". Unknown names give `null`.
* Numbers are formatted with a `.` and without digit grouping, whatever the environment says. Text is UTF-8.

## Strings and memory

The prelude has `strlen`, `strcmp`, `strcpy`, `strcat`, `strdup`, `memcpy` and `memset`. `cstring` adds the rest of `<string.h>`.

### Memory functions

{{sample clib/string_memory}}

**What to notice.**

* `memmove` copies correctly when the areas overlap, `memcpy` does not promise that. When in doubt, use `memmove`.
* The memory functions take `char*` and a byte count. `memchr` and `memrchr` search from the front and from the back and return the address, or `null`.
* `memccpy` copies up to and including a stop character and returns the address after it.

### Searching

{{sample clib/string_search}}

**What to notice.**

* `strrchr(path, '/') + 1` is the usual way to get the file name from a path. The functions return an *address* into the original text, so subtract the start to get an index.
* `strspn` and `strcspn` count the characters at the start that are in (or not in) a set. `strpbrk` finds the first of several characters.
* `strchr(s, 0)` finds the terminating zero: it counts as part of the string.

### Splitting

{{sample clib/string_tokens}}

**What to notice.**

* `strtok` writes zero bytes into your text, so give it a copy, and it remembers its place between calls in a hidden variable: you cannot split two texts at the same time. `strtok_r` keeps the place in a variable of yours.
* Runs of delimiters give no empty tokens in `strtok`. `strsep` does return empty fields (`name,,42,` has four), which is what you want for CSV-like data.

### Copying without overflow

{{sample clib/string_copy}}

**What to notice.**

* `strncpy(dst, src, n)` does not add a zero when the source has `n` or more characters, so the result may not be a string. The sample finds no zero byte in `small`.
* `strlcpy` and `strlcat` (from BSD) always terminate and return the length the full result would have had. `wanted >= size` means that the text was cut. They are the better habit.
* `stpcpy` returns the end of what it wrote, so a chain of copies needs no second pass.

## Memory, numbers, sorting

### malloc and free

The language's own `new` and `alloc` never free memory, which suits short programs. A program that runs for a long time uses `malloc` and `free`, which reuse memory.

{{sample clib/stdlib_malloc}}

**What to notice.**

* `calloc(count, size)` and `malloc(size)` return zeroed memory. In A, even a block that was used and freed before is cleared when it is handed out again.
* `realloc` keeps the old content in front of a bigger block. Always use the returned pointer; the block may have moved.
* A freed block is reused: the second `malloc(100)` returns the same address. That is a reason for `free` to be your last use of the pointer.
* `free(null)` does nothing. Only pointers from `malloc`, `calloc` and `realloc` may be freed, not those of `alloc` or `new`.

### Text to numbers

{{sample clib/stdlib_strtol}}

**What to notice.**

* `strtol(text, &end, base)` converts as much as it can and sets `end` to the first character it did not use. `end == text` means that no digits were found, `*end != 0` means that something was left over: that is how you check a whole text.
* Base 0 reads the prefix: `0x` for hexadecimal, a leading `0` for octal.
* A value that is too large gives the limit (here `INT_MAX`) and sets `errno` to `ERANGE`. Set `errno = 0` before the call to be able to tell.
* `strtoul` gives the bit pattern of an unsigned number. Print it with `%u`.

### qsort and bsearch

{{sample clib/stdlib_qsort}}

**What to notice.**

* The arguments are the array, the number of elements, the size of one element (`sizeof(Person)`, or 8 for an `int`) and the comparison.
* The comparison receives two pointers as `char*` and returns a negative number, 0 or a positive number. Cast them to the element type, as in `((Person*) a)->age`.
* Do not subtract for numbers that can be large (`x - y` can overflow); compare and return -1, 0 or 1, as `cmpInt` does.
* `bsearch` needs a sorted array and returns the address of an element, or `null`.

### Division, exit handlers

{{sample clib/stdlib_div_exit}}

**What to notice.**

* `div(a, b)` returns a pointer to a static `div_t` with `quot` and `rem`. The next call to `div` overwrites it.
* Division truncates toward zero, so `-17 / 5` is -3 with remainder -2: the remainder has the sign of the dividend.
* Functions registered with `atexit` run when the program ends, the last registered first. `exit` runs them. In this implementation so do `_Exit`, `quick_exit` and `abort`, which in C skip them; only `_exit` of `cunistd` leaves at once.

### Random numbers

{{sample clib/stdlib_random}}

**What to notice.**

* `srand48`, `lrand48`, `mrand48` and `drand48` give the same sequences as the C library of Linux (glibc): `srand48(2026)` starts with 894009023 there as well. That is useful when you must reproduce a sequence.
* `drand48` returns a double as a bit pattern; print it with `printfd`.
* `erand48` keeps its state in an array of three ints that you pass, so several generators can run next to each other.
* None of these is for security. For keys use `secure.bytes` (see [Cryptography](#chap-cryptography)).

## Streams: stdio

### Formatted output

{{sample clib/stdio_printf}}

**What to notice.**

* The formats are those of C: flags `- 0 + space #`, width and precision (also `*`), the conversions `d i u x X o b c s p %` (`%b` is binary, which C does not have) and the length modifiers `h hh l ll z`.
* At most eight values follow the format. A longer list goes through an array and `vprintf`, `vsnprintf` and their relatives.
* `snprintf` never writes more than `size` bytes, including the zero, and returns the length of the full text. `asprintf` allocates the buffer for you (free it with `free`). `dprintf` writes to a file descriptor.
* `printf` knows integers and text only. `%f` is for `printfd` (below).

### Reading and writing files

{{sample clib/stdio_files}}

**What to notice.**

* The modes are `"r"`, `"w"` (create or empty), `"a"` (append), and `"+"` for both directions. `"b"` is accepted and ignored.
* `fgets` keeps the newline and returns `null` at the end of the file. `feof` is true only after a read has hit the end.
* `ftell`, `fseek` (with `SEEK_SET`, `SEEK_CUR`, `SEEK_END`) and `rewind` move around. `ungetc` pushes one character back.
* `rename` replaces an existing target; `remove` deletes a file or an empty directory.

### Lines of any length

{{sample clib/stdio_getline}}

**What to notice.**

* `getline(&line, &cap, f)` allocates and grows the buffer, returns the length including the newline, and returns -1 at the end. Start with `line = null` and `cap = 0`, and `free` the buffer when you are done.
* The last line has no newline in this file, and `getline` returns it all the same.

### Binary data

{{sample clib/stdio_binary}}

**What to notice.**

* `fwrite(ptr, size, count, f)` and `fread` take the size of an item and a count, and return the number of *complete items* that were transferred.
* A record file allows direct access: `fseek(f, 2 * sizeof(Point), SEEK_SET)` jumps to record 2.
* The data is written as it is in memory: 8 bytes per `int`. A file made on one platform is read back correctly on another only when both agree on size and byte order.

### Buffering

{{sample clib/stdio_buffering}}

**What to notice.**

* A file stream collects output in a 4 KiB buffer. After `fputs` the file on disk is still empty; `fflush` and `fclose` write it. A program that crashes loses what is in the buffer.
* `setvbuf(f, null, _IONBF, 0)` turns buffering off for one stream (`_IOLBF` is line buffered, `_IOFBF` full). The buffer argument is ignored; the module uses its own.
* `stdout` and `stderr` are not buffered, so ordinary `printf` output appears at once.

### Parsing text with sscanf

{{sample clib/stdio_sscanf}}

**What to notice.**

* The return value is the number of items assigned, and `EOF` (-1) if the input ended before the first. Always check it.
* `%d` stores a whole 64 bit `int`. Use `%hhd` for a `uint8` or `char` target and `%hd` for 16 bits.
* White space in the format matches any amount of white space. `%[^=]` reads up to a character, `%*d` reads and discards, `%n` stores the number of characters used so far.

### Standard input

{{sample clib/stdio_filter}}

**What to notice.**

* `scanf` stops at the first text that does not fit; the rest stays in the input for the next call. The sample then copies the rest, one character at a time, with `getchar` and `putchar`.
* The book's build gives this sample its input from a file with the same name and the extension `.in`.

## Files and directories: unistd

`cunistd` has the POSIX file system functions. They work on Linux and Android and, apart from links and processes, on Windows. Descriptors are plain numbers.

### Descriptors

{{sample clib/unistd_fd}}

**What to notice.**

* `open(path, flags, mode)`: `O_RDONLY`, `O_WRONLY` or `O_RDWR`, combined with `O_CREAT`, `O_TRUNC`, `O_APPEND`, `O_EXCL`. The mode matters only when the file is created. Octal 644 is `420` here, since A has no octal literals.
* `read` returns the count, 0 at the end, -1 on an error; it does not add a zero byte. `write` returns the count written.
* `O_EXCL` with `O_CREAT` fails with `EEXIST` when the file exists: a safe way to create a file that nobody else may have created first.
* The first descriptors are 0 (input), 1 (output) and 2 (error). `STDIN_FILENO`, `STDOUT_FILENO` and `STDERR_FILENO` name them.

### File information

{{sample clib/unistd_stat}}

**What to notice.**

* `stat` fills a `Stat` with `st_size`, `st_mode`, the times, `st_nlink`, `st_uid`, `st_gid` and `st_ino`. `S_ISREG`, `S_ISDIR` and `S_ISLNK` test the kind. The size of a *directory* depends on the file system, so the sample prints sizes of files only.
* `access(path, mode)` returns 0 when the file exists (`F_OK`) and can be read, written or executed (`R_OK`, `W_OK`, `X_OK`, or-ed together).
* `lstat` does not follow a symbolic link, `stat` does. `readlink` gives the text of the link without a terminating zero.
* The permission bits are written with binary literals: `0b110100100` is 644 in octal.

### Directories

{{sample clib/unistd_dirs}}

**What to notice.**

* `readdir` returns every entry, including `.` and `..`, in no defined order. Skip the two, and sort if the order matters.
* The `d_type` of an entry says what it is (4 directory, 8 file, 10 link), saving a `stat`.
* `realpath` resolves `..` and links into an absolute path; the file must exist.
* `rmdir` only removes empty directories (`ENOTEMPTY` otherwise).
* The `os` module of [System programming](#chap-system-programming) has `listDir`, which collects the names for you.

### getopt

`getopt` is the classic C option parser: it returns one option letter per call.

{{sample clib/unistd_getopt}}

**What to notice.**

* The option string `":vo:n:"`: each letter is an option, a letter followed by `:` takes an argument (in `optarg`). The leading `:` makes a missing argument return `':'` instead of `'?'`.
* `-n5` and `-n 5` both work, and `-x` is unknown: `getopt` returns `'?'` and puts the letter in `optopt`. It also prints a message on standard error unless you set `opterr = 0`.
* When the options are used up `getopt` returns `-1`, and `optind` is the index of the first argument that is not an option.
* The `cli` module of [System programming](#chap-system-programming) does the same with long options, defaults and a help text.

### Wildcards

{{sample clib/unistd_fnmatch}}

**What to notice.**

* `fnmatch(pattern, name, flags)` returns 0 for a match. `*`, `?`, `[a-c]`, `[!a-c]` and backslash escapes work like in the shell.
* `FNM_PATHNAME` makes wildcards stop at `/`, `FNM_PERIOD` makes a leading dot need an explicit dot, `FNM_CASEFOLD` ignores case.

## Dates and time: ctime

Times are `int` seconds since 1970-01-01 00:00:00 UTC. Functions that take a `time_t*` in C take an `int*`. `gmtime` and `localtime` return a pointer to a static `tm` that the next call overwrites; `gmtime_r` and `localtime_r` fill your own.

### Breaking a time into fields

{{sample clib/time_gmtime}}

**What to notice.**

* The fields of `tm` count from 1900 for the year, from 0 for the month and from 0 for the day of the year; `tm_wday` is 0 for Sunday.
* Negative times are before 1970: `-1` is one second before the epoch.
* `asctime` and `ctime` give the fixed text `Tue Nov 14 22:13:20 2023` with a newline. `ctime` uses local time, so the sample sets the zone first.
* `timegm` is the inverse of `gmtime`.

### Formatting

{{sample clib/time_strftime}}

**What to notice.**

* The conversions are those of C: `%A %a` day names, `%B %b` month names, `%F` (`%Y-%m-%d`), `%T`, `%I %p` for the 12 hour clock, `%j` day of the year, `%U` and `%V` week numbers, `%s` seconds since 1970, `%z` and `%Z` the zone.
* `strftime` returns the number of characters it stored, and `0` when the result does not fit in the buffer.

### Date arithmetic

{{sample clib/time_calendar}}

**What to notice.**

* `timegm` (UTC) and `mktime` (local time) normalise the fields first. Month 13 is January of the next year, day 0 is the last day of the previous month, February 31 becomes March 3. To add a month or 100 days, change the field and convert.
* The difference of two times is a number of seconds; divide by 86400 for days. `difftime(a, b)` is `a - b`.

### Reading a date

{{sample clib/time_strptime}}

**What to notice.**

* `strptime(text, format, &tm)` returns a pointer to the first character it did not use, or `null` when the text does not fit the format. The rest of the text is in your hands.
* It understands `%Y %m %d %H %M %S %y %b %B %p %I` and more (see the reference).
* Fields the format does not mention keep their old values. Clear the `tm` first if that matters.

### Time zones

{{sample clib/time_zones}}

**What to notice.**

* The zone comes from the `TZ` variable in the POSIX form: `EST5EDT` (name, offset, daylight name), or with explicit rules `EET-2EEST,M3.5.0/3,M10.5.0/4`. The sign counts hours *west* of Greenwich, so `CET-1` is UTC+1.
* Call `tzset()` after you change `TZ`. Without a `TZ` variable the rule at the end of `/etc/localtime` is used (Linux and Android), and without that, UTC.
* **Historical rule changes are not known**: today's rule is applied to every year. A date in 1985 gets today's daylight saving dates.
* `mktime(&p)` with `tm_isdst = -1` finds out by itself whether daylight saving applies and fills in `tm_isdst` and `tm_gmtoff`.

## Floating point

A has a `double` type (and `float` is an alias for it): a real IEEE 754 binary64 number that you can use in expressions, compare, store in structs and print with `printlnDouble`. It is calculated in software, so the results are the same on every platform. The chapter on numbers ([Numbers](#chap-numbers)) describes the type and the `dmath` module, which has the mathematical functions for `double` values.

The C library works with the **same 64 bits**, but it passes them as an `int`: a "bit pattern". An `int` is accepted everywhere, including by `printf` style functions with a list of values. So the C style functions of `cmath`, `cfloat` and `ccomplex` take and return `int`:

```a
int x = dlit("2.5");               // text to a double, as bits
int r = sqrt(dmul(x, x));          // functions on bit patterns: dadd dsub dmul ddiv dneg, sqrt sin pow ...
printfd("%.3f\n", r);              // printf with %f %e %g %a
```

The two styles meet in two compiler functions: `__bits(d)` gives the 64 bits of a `double` as an `int`, and `__dbl(i)` makes a `double` from 64 bits.

| You want to | With the `double` type | With bit patterns (C library) |
|---|---|---|
| write a number | `2.5` | `dlit("2.5")`, `itod(3)` |
| calculate | `a * b + 1` | `dadd(dmul(a, b), itod(1))` |
| compare | `a < b` | `dlt(a, b)`, `deq(a, b)` |
| square root, sine, power | `dmath.sqrt(x)`, `dmath.sin(x)`, `dmath.pow(x, y)` | `sqrt(x)`, `sin(x)`, `pow(x, y)` |
| convert to an `int` | `(int) d` | `dtoi(x)` |
| print | `printlnDouble(d)`, `doubleToFixed(d, 3)` | `printfd("%.3f", x)` |
| read from text | `parseDouble(text)` | `strtod`, `atof`, `dlit`, `sscanf` with `%lf` |

::: warning

The conversion is where mistakes happen. A `double` that you pass where an `int` is expected is *converted to an integer*, not reinterpreted: `printf("%d", 3.99)` prints 3, and `printfd("%.2f", 3.99)` prints `0.00` because it reads the integer 3 as the bits of a tiny number. Pass `__bits(d)`. The other way round, `double x = M_PI;` converts the integer that holds the bits of pi and gives 4.6e18. Write `__dbl(M_PI)`, or use `dmath.PI`.

:::

The next sample shows the bridge in both directions, and the mistakes.

{{sample clib/math_double}}

**What to notice.**

* The wrappers `sqrtd` and `powd` are one line each: bits out, C function, bits back. If you use the C functions with typed doubles a lot, write such wrappers, or use `dmath`, which has them.
* `printfd` takes `__bits(...)` for each `%f`. Integers, like the `3` in `3 items of`, are passed as they are.
* `sscanf("%lf", &v)` stores through a pointer to a `double` variable: the pointer is just an address.
* `(3 + 4) * 0.5` and `dmul(dadd(itod(3), itod(4)), dlit("0.5"))` produce the same 64 bits. The two styles are two ways to write the same arithmetic.

The samples below use the bit pattern style, because that is the style of the C library and of the C programs that you port. When a C program says `double x = sqrt(y) * 2`, you can write the same with the `double` type and `dmath`, as the port at the end of this chapter does.

### Reading and printing numbers: cfloat

{{sample clib/float_parse}}

**What to notice.**

* `strtod(text, &end)` converts what it can (decimal, hexadecimal, `inf`, `nan`) and sets `end` like `strtol`. Nothing converted: `end` is the start of the text and the result is 0.
* `dtostr(x)` is the shortest text that reads back as exactly `x`: `0.1`, `-2500.0`, `inf`.
* `atof` has no way to report an error. Use `strtod` when the text is not yours.

{{sample clib/float_printf}}

**What to notice.**

* `printfd`, `sprintfd`, `snprintfd` and `fprintfd` understand `%f %F %e %E %g %G %a %A` with the usual flags, width and precision. All other conversions work as in `printf`.
* The digits are exact: `%.30f` of 0.1 shows `0.100000000000000005551115123126`, and `%.0f` of 1e22 shows all 23 digits.
* `%g` chooses the shorter of `%f` and `%e` and drops trailing zeros. `%a` is the exact hexadecimal form.
* The eight value limit applies: the format of `printfd` and its values must fit.

### Mathematical functions: cmath

`cmath` has the functions of `<math.h>`, on bit patterns: `sqrt cbrt pow exp exp2 expm1 log log2 log10 log1p hypot`, the trigonometric and hyperbolic functions and their inverses, `floor ceil round rint trunc fmod remainder`, `erf tgamma lgamma`, classification (`isnan`, `isinf`, `fpclassify`) and the constants `M_PI`, `M_E`, `INFINITY`, `NAN`, `DBL_EPSILON` and the rest of `<float.h>`. `sqrt` and the basic operations are exact; the others are computed with about 100 bits and rounded once, so they are within one unit in the last place, and nearly always correctly rounded.

{{sample clib/math_basic}}

**What to notice.**

* `%.17g` shows the 17 significant digits that tell any two doubles apart: `sqrt(2)` is `1.4142135623730951`.
* `log10(0.001)` is exactly -3 and `cbrt(27)` exactly 3: results that are mathematically exact come out exact.
* `1 / 3` with 20 digits shows the error that is already in the stored number: `0.33333333333333331483`.

{{sample clib/math_trig}}

**What to notice.**

* Angles are in radians. Degrees to radians is `deg * pi / 180`.
* `tan(pi / 2)` is not infinity but 1.6e16: the double nearest to pi / 2 is not exactly pi / 2.
* `atan(1) * 4` gives pi to all digits of a double.

{{sample clib/math_rounding}}

**What to notice.**

* `floor` goes down, `ceil` up, `trunc` toward zero. `round` rounds halves away from zero (2.5 becomes 3), `rint` rounds halves to the even number (2.5 becomes 2, 3.5 becomes 4).
* `-0.4` rounds to `-0`: negative zero is a real value, and `%g` prints it.
* `dtoi` cuts toward zero, `lround` rounds. `fmod` has the sign of the first argument, `remainder` can be negative for a positive first argument.

{{sample clib/math_special}}

**What to notice.**

* Division by zero, `sqrt(-1)` and `log(0)` do not stop the program: they give `inf`, `nan` and `-inf`. Test with `isnan`, `isinf` and `isfinite`.
* A NaN is not equal to anything, not even to itself. `dcmp` returns 2 for "unordered".
* `1e-320` is a subnormal number: smaller than the smallest normal number and with less precision. `-0` equals `+0` in a comparison, but `signbit` tells them apart.

{{sample clib/math_exact}}

**What to notice.**

* `0.1 + 0.2` is `0.30000000000000004`, not `0.3`: the same in every language, on every machine. Here you also get it on every platform of A, because the arithmetic is done in software.
* `0.1` is stored as `0.1000000000000000055...`. Ten additions of 0.1 do not make 1.
* Compare with a tolerance, not with `==`: `fabs(a - b) < 1e-12`.
* `DBL_EPSILON` is the gap between 1 and the next number. Adding half of it to 1 changes nothing.

### Complex numbers: ccomplex

A complex number is a pointer to a `Complex` with two doubles (as bit patterns). Functions that make a number return a new one on the heap, so expressions nest.

{{sample clib/complex_basic}}

**What to notice.**

* `cmplx(re, im)` makes a number; `cadd`, `csub`, `cmul`, `cdiv`, `conj`, `cneg` work on two (or one). `creal`, `cimag`, `cabs` (the modulus) and `carg` (the angle) take them apart.
* `cstr(z)` gives the shortest exact text of both parts: `3.0+4.0i`.
* `cpolar(r, theta)` builds a number from radius and angle.

{{sample clib/complex_functions}}

**What to notice.**

* `csqrt`, `cexp`, `clog` and the trigonometric functions take complex arguments. `csqrt(-4)` is `2i`, and `clog(-1)` is `i pi`.
* `e^(i pi)` is `-1` plus a tiny imaginary part, 1.2e-16: the pi of a double is not exactly pi.
* The quadratic formula works with a negative discriminant: the roots of x^2 + 2x + 5 are `-1+2i` and `-1-2i`.

## Wide characters: cwchar

A *wide character* is a Unicode code point stored in an `int`, and a wide string is an `int` array that ends with 0. `cwchar` has `wcslen`, `wcscpy`, `wcscmp`, `wcsstr`, `wcstok`, `towupper`, `iswalpha`, `wcwidth` and the other names of `<wchar.h>` and `<wctype.h>`. Conversion to and from UTF-8 is `mbstowcs` and `wcstombs` of `cstdlib` (`cwchar` imports them).

There are no wide string literals (`L"..."`): you write a UTF-8 literal and convert it.

{{sample clib/wchar_convert}}

**What to notice.**

* The text has 35 bytes and 22 characters. Indexing a wide string gives characters; indexing the UTF-8 text gives bytes.
* `towupper` and `iswalpha` know Latin, Greek, Cyrillic and the common scripts: `ï` becomes `Ï` and `έ` becomes `Έ`. CJK characters are letters but have no case.
* `wcswidth` gives the columns a text takes in a terminal: CJK characters take two, so 22 characters need 25 columns.
* `mbtowc` and `wctomb` convert one character at a time and return the number of bytes.

{{sample clib/wchar_strings}}

**What to notice.**

* The `wcs...` functions work like their `str...` relatives on `int*`. `hit - buf` is the index in characters.
* `wcstok` keeps its place in a variable that you pass (`&save`), like `strtok_r`.
* The helper `wide()` is the place where UTF-8 text becomes a wide string.

## Porting a C program

Porting a C program to A is mostly renaming. The sections above showed the differences one by one; here they are in a real program.

### Step 1: a word counter

This C program reads text on standard input, counts how often each word occurs, and prints the five most frequent ones with their share. It uses `ctype`, `string`, `stdlib` (`qsort`), `stdio` and a `double`.

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define MAXWORDS 1000

struct entry {
    char word[32];
    int count;
};

static struct entry table[MAXWORDS];
static int used = 0;

static void add(const char *w) {
    for (int i = 0; i < used; i++) {
        if (strcmp(table[i].word, w) == 0) {
            table[i].count++;
            return;
        }
    }
    if (used < MAXWORDS) {
        strncpy(table[used].word, w, 31);
        table[used].count = 1;
        used++;
    }
}

/* most frequent first, then alphabetical */
static int compare(const void *a, const void *b) {
    const struct entry *x = a, *y = b;
    if (x->count != y->count) return y->count - x->count;
    return strcmp(x->word, y->word);
}

int main(void) {
    char word[32];
    int len = 0, c, total = 0;

    while ((c = getchar()) != EOF) {
        if (isalpha(c)) {
            if (len < 31) word[len++] = tolower(c);
        } else if (len > 0) {
            word[len] = 0;
            add(word);
            total++;
            len = 0;
        }
    }
    if (len > 0) {
        word[len] = 0;
        add(word);
        total++;
    }

    qsort(table, used, sizeof table[0], compare);
    printf("%d words, %d different\n", total, used);
    for (int i = 0; i < used && i < 5; i++) {
        printf("%-10s %3d  %5.1f%%\n", table[i].word, table[i].count,
               100.0 * table[i].count / total);
    }
    return 0;
}
```

I compiled this program with `gcc` and ran it on the input below. The A version has to print the same lines.

```text
The quick brown fox jumps over the lazy dog.
The dog barks; the fox runs away!
A quick brown dog? No: the quick fox.
```

{{sample clib/port_wordfreq}}

The output is character for character what `gcc` prints for the C version. These are all the changes that were needed:

| In the C program | In the A port | Why |
|---|---|---|
| `#include <stdio.h>` and four more | `import cstdio;` and four more (or one `import clib;`) | modules instead of headers |
| `#define MAXWORDS 1000` | `const MAXWORDS = 1000;` | a constant is better than a macro here (`#define` works too) |
| `struct entry { ... };` and `struct entry table[N]` | `struct Entry { ... }` and `Entry table[MAXWORDS]` | the `struct` keyword in a declaration is optional (`struct entry table[N]` also works), and so is the `;` after the brace |
| `static int used` | `int used` | `static` also works (it is the same as `private`); in a program that is one unit it makes no difference |
| `const void *a` in `compare` | `char* a`, then `Entry* x = (Entry*) a;` | `qsort` passes `char*` pointers; the cast moves into the function |
| `qsort(table, used, sizeof table[0], compare)` | `qsort((char*) table, used, sizeof(Entry), compare)` | the array is passed as `char*` |
| `100.0 * count / total` printed with `%5.1f` | `double percent = ...;` and `printfd(..., __bits(percent))` | the `double` type works as in C, but `printfd` takes bits |

What did *not* have to change: the declarations with several names (`int len = 0, c, total = 0;`), `word[len++] = tolower(c)`, the `for (int i = 0; ...)` loops, `strncpy`, `strcmp`, `getchar`, the `printf` formats `%-10s %3d`.

### Step 2: a program with options and error messages

`head` prints the first lines of files. It uses `getopt`, `strtol` with error checking, `fopen`, `fgets`, `strerror`, `fprintf(stderr, ...)` and exit codes. The A version is a sample directory (`main.a` and a data file `poem.txt` that the book's build copies next to it), and it is run with the arguments `-n 2 poem.txt missing.txt poem.txt`. The C original is the same text apart from its `#include` lines; compiled with `gcc` it gives the same output and the same exit status.

{{sample clib/port_head}}

**What to notice.**

* Apart from the lines at the top, the program is the C source character for character: the `#include` lines became `import` lines (`climits` is for `NULL`). The `switch` on the option letter with a block in a `case`, `static`, `sizeof line`, `strtol(optarg, &end, 10)`, `fprintf(stderr, ...)` and `strerror(errno)` are all C as it was.
* The missing file gives a message on standard error, which is not part of the recorded output, and the exit status 1 (the sample says `exit=1`). The output of the two good files is there.

### Step 3: floating point

The third program reads numbers and prints their mean and standard deviation. In C it declares `double v[MAXN], x, sum = 0, ...`, reads with `scanf("%lf", &x)` and calls `sqrt` from `<math.h>`.

{{sample clib/port_stats}}

**What to notice.**

* The declarations and the loops are the C text. `sum += x`, `(v[i] - mean) * (v[i] - mean)` and `v[i] < lo` work on real `double` values.
* `scanf("%lf", &x)` stores the 64 bits through the pointer, and `x` is a valid `double` afterwards.
* The two places that changed are the output (`__bits(mean)` for `printfd`) and `sqrt`, which is `dmath.sqrt` for a `double`. The C library `sqrt` would take bits.
* Again the output equals that of the C program compiled with `gcc`.

### Step 4: the traps

{{sample clib/port_pitfalls}}

**What to notice.**

* `sizeof(int)` and `sizeof(long)` are both 8. `char` is unsigned: `char c = 200` stays 200.
* `sscanf("%d")` stores 8 bytes. The `%hhd` conversion stores one.
* `010` is ten, not eight. Reading code that uses octal permissions (`0755`, `0644`) is the most dangerous: the program compiles and gets the wrong mode.
* `uint32` wraps at 32 bits, `int` does not.
* A `double` handed to `printf` is truncated to an integer.
* A function pointer (`func`) has no signature and no check. A call returns an `int`.
* `malloc` returns zeroed memory, and string literals are writable.

### A checklist for porting

1. Replace each `#include` by the `import` of the module in the table at the top of the chapter, or write `import clib;`.
2. Change `const char*` and `const void*` to `char*`, and `NULL` to `null` (`NULL` also exists in `climits`).
3. Cast the arguments of `qsort` and `bsearch`; read the elements through casts inside the comparison.
4. Check every `printf` with more than eight values, and every `va_list`.
5. Replace octal numbers by decimal or binary ones.
6. Check sizes: `%d` for 64 bit `int`, `%hhd` in `scanf` for bytes, `uint32` where 32 bit wrap matters.
7. Print doubles with `printfd(..., __bits(x))`, and pass `__bits(x)` to the C math functions or use `dmath`.
8. Run the original and the port on the same input, and compare the output.

## Summary

* `import clib;` gives all of the C library; the individual modules (`cstdio`, `cstring`, ...) keep programs small. The names are the C names, in the global namespace.
* `int` is 64 bits, `char` is an unsigned byte, there are no octal literals, and `printf`-style functions take up to eight values (arrays go through the `v...` functions).
* `strtol`, `strtod` and `sscanf` tell you how much of the text they used; check it. `snprintf`, `strlcpy` and `getline` avoid overflowing buffers.
* `qsort`, `bsearch`, `atexit` and `signal` take `func` pointers; the arguments are `char*` or `int`, and you cast inside.
* `cunistd` has descriptors, `stat`, directories, `getopt`, `fnmatch`, `fork` and `signal`; `ctime` has `gmtime`, `mktime`, `strftime`, `strptime` and POSIX time zones.
* `double` is a type of the language; the C math and print functions take it as a bit pattern: `__bits(d)` and `__dbl(i)` connect the two. A `double` passed to an `int` is converted, not reinterpreted.
* Porting is mostly renaming: headers become imports, `const` and `void*` become `char*`, and the output of `printf("%f")` becomes `printfd`.

## Where next

* [Numbers](#chap-numbers) for the `double` type, `dmath`, `bigint`, `decimal` and `fixed`.
* [System programming](#chap-system-programming) for `os`, `thread`, `cli`, `log` and `testing`, which use these functions at a higher level.
* [Cryptography](#chap-cryptography) for `secure`, which you should use instead of `rand` for secrets.
* API references: [cstdio](#api-cstdio), [cstdlib](#api-cstdlib), [cstring](#api-cstring), [ctime](#api-ctime), [cunistd](#api-cunistd), [cmath](#api-cmath), [cfloat](#api-cfloat), [ccomplex](#api-ccomplex), [cwchar](#api-cwchar), [cctype](#api-cctype), [cerrno](#api-cerrno), [cassert](#api-cassert), [climits](#api-climits), [clocale](#api-clocale) and [clib](#api-clib).
