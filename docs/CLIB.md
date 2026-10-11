# The C library of A

`import clib;` makes the whole C-style library available; the individual modules can also be imported one by one
(`import cstring;`). They are written in A, embedded in the compiler, and put their names into the **global
namespace** like the C headers do. Only the functions a program really uses end up in the executable.

| Module | C headers | Contents |
|---|---|---|
| [`cctype`](#cctype) | `<ctype.h>` | Character classification and conversion (ASCII). |
| [`climits`](#climits) | `<limits.h>` `<stdint.h>` `<stddef.h>` | Integer limits and `NULL`. |
| [`cerrno`](#cerrno) | `<errno.h>` | `errno`, the error numbers, `strerror` and `perror`. |
| [`cassert`](#cassert) | `<assert.h>` | `assert`. |
| [`cstring`](#cstring) | `<string.h>` | Memory and string functions. |
| [`cstdlib`](#cstdlib) | `<stdlib.h>` | Memory allocation, number parsing, environment, processes, `qsort`. |
| [`cstdio`](#cstdio) | `<stdio.h>` | Streams, `printf` and `scanf` families, files, pipes. |
| [`ctime`](#ctime) | `<time.h>` | Clocks, calendar time, time zones, `strftime`. |
| [`cmath`](#cmath) | `<math.h>` `<float.h>` | Floating point arithmetic and mathematical functions on software doubles. |
| [`cfloat`](#cfloat) | (`strtod`, `printf` conversions) | Text to double, double to text, `printf` with `%f %e %g %a`. |
| [`cunistd`](#cunistd) | `<unistd.h>` `<sys/stat.h>` `<dirent.h>` `<fcntl.h>` `<signal.h>` `<fnmatch.h>` | POSIX files, directories, processes, signals, `getopt`. |
| [`clocale`](#clocale) | `<locale.h>` | The "C" locale. |
| [`cwchar`](#cwchar) | `<wchar.h>` `<wctype.h>` | Wide characters and strings (Unicode code points in ints). |

Not modules because they are part of the language or the standard library that every program has:
`setjmp` / `longjmp` (built-in, see the language reference), `printf` / `exit` / `rand` / `strlen` / `strcmp` / `strcpy` /
`strcat` / `memcpy` / `memset` / `atoi` / `abs` (the prelude `lib/std.a`), `stdbool` (`bool` is a type).

## How A differs from C, for people who port C code

* **`int` is 64 bits**, `long` is the same type, `char` is an unsigned byte. `%d` prints a 64-bit value, `scanf("%d")`
  stores 8 bytes (use `%hhd` / `%hd` for 1 or 2 bytes). `INT_MAX` is 2^63-1; `INT32_MAX`, `UINT32_MAX` ... exist as well.
* **There are no variable argument lists.** The `printf` family takes up to **eight** values after the format (default
  parameter values fill the rest), and the `v...` versions (`vsnprintf`, `vfprintf` ...) take an array of values
  (an `int*`) and their count instead of a `va_list`. Text and pointers are passed as they are.
* **There is no `float` / `double` type.** A double is an `int` holding the 64-bit IEEE 754 pattern; arithmetic is done by
  functions (`dadd dsub dmul ddiv`, compare with `dlt dle deq ...`) in software, exactly rounded. Literals come from text:
  `dlit("3.14")`, `itod(3)`. The `printf` family of the standard library prints integers; **`printfd`, `sprintfd`,
  `snprintfd`, `fprintfd`, `vformatd`** (module `cfloat`) understand `%f %e %g %a` as well.
* **Function pointers** are values of the type `func`: `func f = compare; f(a, b);`. `qsort`, `bsearch`, `atexit` and `signal`
  use them. A function called through a `func` returns an `int` and its arguments are not checked.
* **Structs cannot be passed or returned by value.** `div` / `ldiv` return a pointer to a static `div_t`; `gmtime` /
  `localtime` return a pointer to a static `tm`, as in C.
* **`FILE*`**: `stdin`, `stdout` and `stderr` are constants; pass them wherever a `FILE*` is expected. Output to files is
  buffered and written at `fclose`, `fflush` and when the program ends; `stdout` and `stderr` are not buffered.
* **Macros do not exist**: `assert(cond)` cannot print the expression (use `assertMsg`), `offsetof` is missing (use
  `sizeof` and field addresses), `errno` is a plain global variable.
* **Memory**: `malloc`/`free` is a real allocator (`import cstdlib;`). The language's own `new` and `alloc` never free.
* **Locale and wide characters**: always the "C" locale and UTF-8 text; wide characters are code points stored in ints.
* **Time zones** follow the POSIX rules of the `TZ` variable, or the rule stored in `/etc/localtime`. Historical rule
  changes are not known: today's rule is applied to every year.
* **Windows and Android**: the same source runs everywhere. Where a feature does not exist on a platform the function
  fails with `ENOSYS` (`fork`, `kill`, `link`, `symlink`, `signal` and `alarm` on Windows).


## A quick tour

```c
import clib;

int byLength(char* a, char* b) {                       // compare function for qsort: gets pointers to two elements
    return strlen(((char**) a)[0]) - strlen(((char**) b)[0]);
}

int main(int argc, char** argv) {
    // files and formatted output
    FILE* f = fopen("report.txt", "w");
    fprintf(f, "%-8s|%6d|\n", "total", 1600);
    fclose(f);

    // reading it back with scanf: the pointers are passed as they are
    char word[32];
    int amount;
    f = fopen("report.txt", "r");
    fscanf(f, "%s | %d", word, &amount);
    fclose(f);
    printf("%s %d\n", word, amount);

    // sorting strings with a function pointer
    char* names[3];
    names[0] = "ccc"; names[1] = "a"; names[2] = "bb";
    qsort((char*) names, 3, 8, byLength);
    printf("%s %s %s\n", names[0], names[1], names[2]);

    // dates
    int now = time(null);
    char text[64];
    strftime(text, 64, "%A, %d %B %Y", gmtime(&now));
    println(text);

    // mathematics: doubles are ints holding the IEEE bit pattern
    int r = sqrt(dlit("2"));
    printfd("sqrt(2) = %.15f, sin(1) = %g\n", r, sin(itod(1)));

    // malloc/free, getenv, system
    char* buf = malloc(100);
    strcpy(buf, "hello");
    free(buf);
    char* home = getenv("HOME");
    if (home != null) { println(home); }
    return system("exit 3");                            // the exit code of the command is returned
}
```

Error handling follows C: functions return `-1`, `null` or `EOF` and set `errno`:

```c
FILE* f = fopen("/nonexistent/file", "r");
if (f == null) {
    perror("fopen");                                    // fopen: No such file or directory
    return errno;                                       // 2
}
```

Use `setjmp` / `longjmp` for exceptions, and `atexit` for cleanup:

```c
int env[4];
void fail() { longjmp(env, 1); }
int main() {
    if (setjmp(env) == 0) { fail(); } else { println("caught"); }
    return 0;
}
```

## Reference

### cctype
`<ctype.h>` - Character classification and conversion (ASCII).  
`import cctype;`

```text
cctype - C <ctype.h>                                       import cctype;

Character classification and conversion with the C names. The functions take an int
(a character code) and are ASCII only; see the utf8 module for Unicode.
The names go into the global namespace, like the C header.
(The standard library itself has the same tests under camelCase names: isDigit, isAlpha ...)
```

| Function | Description |
|---|---|
| `bool isalpha(int c)` |  |
| `bool isdigit(int c)` |  |
| `bool isalnum(int c)` |  |
| `bool isupper(int c)` |  |
| `bool islower(int c)` |  |
| `bool isspace(int c)` | space, \t \n \v \f \r |
| `bool isblank(int c)` | space or tab |
| `bool iscntrl(int c)` |  |
| `bool isgraph(int c)` | printable, but not the space |
| `bool isprint(int c)` | printable including the space |
| `bool ispunct(int c)` | printable and neither a letter, a digit nor the space |
| `bool isxdigit(int c)` |  |
| `bool isascii(int c)` |  |
| `int toupper(int c)` |  |
| `int tolower(int c)` |  |
| `int toascii(int c)` |  |
| `int digitValue(int c, int base = 36)` | value of a digit in the given base (0-9, a-z, A-Z), -1 if c is not a digit of that base |

### climits
`<limits.h>` `<stdint.h>` `<stddef.h>` - Integer limits and `NULL`.  
`import climits;`

```text
climits - C <limits.h>, <stdint.h>, <stddef.h>, <stdbool.h> constants   import climits;

In A `int` and `long` are both 64-bit, `char` is an unsigned byte and `bool` a byte, so the
limits of INT_*, LONG_* and LLONG_* are the 64-bit ones. The fixed-width names (INT8_MAX ...
UINT32_MAX) are there for code that cares about exact sizes. UINT64_MAX / ULLONG_MAX do not
exist because A has no unsigned 64-bit type (the bit pattern is -1).
```

Constants: `CHAR_BIT`, `CHAR_MIN`, `CHAR_MAX`, `SCHAR_MIN`, `SCHAR_MAX`, `UCHAR_MAX`, `SHRT_MIN`, `SHRT_MAX`, `USHRT_MAX`, `INT_MIN`, `INT_MAX`, `LONG_MIN`, `LONG_MAX`, `LLONG_MIN`, `LLONG_MAX`, `INT8_MIN`, `INT8_MAX`, `UINT8_MAX`, `INT16_MIN`, `INT16_MAX`, `UINT16_MAX`, `INT32_MIN`, `INT32_MAX`, `UINT32_MAX`, `INT64_MIN`, `INT64_MAX`, `INTPTR_MIN`, `INTPTR_MAX`, `INTMAX_MIN`, `INTMAX_MAX`, `PTRDIFF_MIN`, `PTRDIFF_MAX`, `SIZE_MAX`, `SSIZE_MAX`, `MB_LEN_MAX`, `PATH_MAX`, `NAME_MAX`, `NULL`

### cerrno
`<errno.h>` - `errno`, the error numbers, `strerror` and `perror`.  
`import cerrno;`

```text
cerrno - C <errno.h> and strerror                          import cerrno;

`errno` is a global variable. The functions of the C modules (cstdio, cstdlib, cunistd ...) set it
when they fail, using the Linux error numbers on every platform.
```

Constants: `EPERM`, `ENOENT`, `ESRCH`, `EINTR`, `EIO`, `ENXIO`, `E2BIG`, `ENOEXEC`, `EBADF`, `ECHILD`, `EAGAIN`, `ENOMEM`, `EACCES`, `EFAULT`, `EBUSY`, `EEXIST`, `EXDEV`, `ENODEV`, `ENOTDIR`, `EISDIR`, `EINVAL`, `ENFILE`, `EMFILE`, `ENOTTY`, `EFBIG`, `ENOSPC`, `ESPIPE`, `EROFS`, `EMLINK`, `EPIPE`, `EDOM`, `ERANGE`, `ENAMETOOLONG`, `ENOSYS`, `ENOTEMPTY`, `EILSEQ`, `ECONNREFUSED`, `EWOULDBLOCK`

| Function | Description |
|---|---|
| `char* strerror(int e)` | message text for an error number, like C's strerror |
| `void perror(char* prefix)` | prints "prefix: message" for the current errno on standard error (C's perror) |

### cassert
`<assert.h>` - `assert`.  
`import cassert;`

```text
cassert - C <assert.h>                                     import cassert;

A has no macros, so `assert` cannot print the text of the expression. It reports the failure on
standard error and ends the program with exit code 134 (the code a C program gets from abort).
assertMsg lets you say what was expected.
```

| Function | Description |
|---|---|
| `void assert(bool ok)` |  |
| `void assertMsg(bool ok, char* message)` |  |

### cstring
`<string.h>` - Memory and string functions.  
`import cstring;`

```text
cstring - C <string.h>                                     import cstring;

The functions of the C header that the standard library (strlen, strcmp, strcpy, strcat, strdup,
memcpy, memset) does not already have, with the C names and arguments. Texts are NUL-terminated
`char*`, "memory" functions take `char*` and a byte count. It also imports cerrno, for `strerror`.
```

| Function | Description |
|---|---|
| `char* memmove(char* dst, char* src, int n)` | ---- memory ----------------------------------------------------------------------------------------------- copies n bytes, also when the areas overlap; returns dst |
| `int memcmp(char* a, char* b, int n)` | <0, 0, >0 like strcmp, for n bytes |
| `char* memchr(char* s, int c, int n)` | address of the first byte equal to c in the first n bytes, null if there is none |
| `char* memrchr(char* s, int c, int n)` | like memchr, but the last match |
| `char* memccpy(char* dst, char* src, int c, int n)` | copies up to n bytes and stops after the first byte equal to c; returns the address after it, null if c was not found |
| `char* strncpy(char* dst, char* src, int n)` | ---- copying and joining -------------------------------------------------------------------------------- copies at most n characters and fills the rest of dst (up to n) with zero bytes; returns dst |
| `char* strncat(char* dst, char* src, int n)` | appends at most n characters of src, always adds the terminating zero; returns dst |
| `char* stpcpy(char* dst, char* src)` | copies and returns the address of the terminating zero in dst |
| `int strlcpy(char* dst, char* src, int size)` | BSD safe copy: at most size-1 characters plus the zero; returns the length of src |
| `int strlcat(char* dst, char* src, int size)` | BSD safe append: the result has at most size-1 characters; returns the length it would have had |
| `char* strndup(char* s, int n)` | a heap copy of at most n characters of s |
| `int strncmp(char* a, char* b, int n)` | ---- comparing --------------------------------------------------------------------------------------------- |
| `int strcasecmp(char* a, char* b)` | comparison that ignores the case of ASCII letters |
| `int strncasecmp(char* a, char* b, int n)` |  |
| `int strcoll(char* a, char* b)` | locale comparison (the "C" locale: same as strcmp) |
| `int strxfrm(char* dst, char* src, int n)` | locale transformation (the "C" locale: a copy); returns the length of src |
| `int strnlen(char* s, int max)` | ---- searching --------------------------------------------------------------------------------------------- length of s, but looks at no more than max characters |
| `char* strchr(char* s, int c)` | address of the first c (searching includes the terminating zero), null if there is none |
| `char* strrchr(char* s, int c)` | address of the last c, null if there is none |
| `char* strstr(char* hay, char* needle)` | address of the first occurrence of needle in hay, null if there is none |
| `char* strcasestr(char* hay, char* needle)` | case-insensitive strstr |
| `int strspn(char* s, char* accept)` | number of leading characters of s that all appear in accept |
| `int strcspn(char* s, char* reject)` | number of leading characters of s that do not appear in reject |
| `char* strpbrk(char* s, char* accept)` | address of the first character of s that appears in accept, null if there is none |
| `char* strtok(char* s, char* delim)` | ---- splitting ----------------------------------------------------------------------------------------------- splits s into tokens separated by any character of delim. The first call passes the text (it is modified: delimiters become zero bytes), the next calls pass null. Returns null after the last token. |
| `char* strtok_r(char* s, char* delim, char** save)` | like strtok, with the position kept in *save so that several splits can run at once |
| `char* strsep(char** sp, char* delim)` | like strtok_r but empty tokens are returned too; *sp is the position, null when the text is used up |

### cstdlib
`<stdlib.h>` - Memory allocation, number parsing, environment, processes, `qsort`.  
`import cstdlib;`

```text
cstdlib - C <stdlib.h>                                     import cstdlib;

  malloc calloc realloc free   a real allocator: freed memory is reused (std `alloc`/`new` never free)
  strtol strtoul strtoll strtoull strtoimax strtoumax atol atoll   number parsing with any base 2-36
  abs labs llabs imaxabs div ldiv lldiv
  getenv setenv putenv unsetenv clearenv environ
  system abort _Exit quick_exit
  mblen mbtowc wctomb mbstowcs wcstombs     (UTF-8; wide characters are ints)

  qsort bsearch atexit        (take function pointers: the type `func`, see the language reference)
  random srandom  srand48 lrand48 mrand48 drand48 erand48 seed48   (the POSIX random number generators)
`exit`, `rand` and `srand` are in the standard library already.
```

Constants: `EXIT_SUCCESS`, `EXIT_FAILURE`, `RAND_MAX`, `MB_CUR_MAX`

Types: `div_t`

| Function | Description |
|---|---|
| `char* malloc(int size)` |  |
| `char* calloc(int count, int size)` |  |
| `void free(char* p)` | gives a block back for reuse; free(null) does nothing. Only pointers from malloc/calloc/realloc may be freed. |
| `int malloc_usable_size(char* p)` | capacity in bytes of a block from malloc |
| `char* realloc(char* p, int size)` |  |
| `int abs64(int x)` | ---- numbers ------------------------------------------------------------------------------------------------- |
| `int labs(int x)` |  |
| `int llabs(int x)` |  |
| `int imaxabs(int x)` |  |
| `div_t* div(int a, int b)` | quotient and remainder at once. The result is a pointer to a static div_t:  div_t* d = div(7, 2); |
| `div_t* ldiv(int a, int b)` |  |
| `div_t* lldiv(int a, int b)` |  |
| `int strtol(char* s, char** end, int base = 10)` | converts text to a number: leading white space, optional sign, base 2-36 (0 = from the prefix: 0x hex, 0 octal, otherwise decimal). *end (when not null) is set to the first character that was not used. Out of range values give the limit and set errno to ERANGE. |
| `int strtoll(char* s, char** end, int base = 10)` |  |
| `int strtoimax(char* s, char** end, int base = 10)` |  |
| `int strtoul(char* s, char** end, int base = 10)` | unsigned version: the result is the bit pattern, values above 2^63 come out negative |
| `int strtoull(char* s, char** end, int base = 10)` |  |
| `int strtoumax(char* s, char** end, int base = 10)` |  |
| `int atol(char* s)` |  |
| `int atoll(char* s)` |  |
| `char** environ()` | the environment as a null-terminated array of "NAME=value" strings (changes made by setenv are included) |
| `char* getenv(char* name)` |  |
| `int setenv(char* name, char* value, bool overwrite = true)` | sets NAME=value; an existing variable is only replaced when overwrite is true. Returns 0, or -1 with errno set |
| `int putenv(char* assignment)` | "NAME=value" |
| `int unsetenv(char* name)` |  |
| `int system(char* command)` | ---- processes ----------------------------------------------------------------------------------------------- Runs a command through the shell (/bin/sh -c on Linux, /system/bin/sh on Android, cmd.exe /c on Windows) and waits for it. Returns the exit code of the command (128 + signal number if it was killed), -1 if it could not be started. system(null) returns 1: a shell is available. |
| `int random()` | ---- random numbers (POSIX) --------------------------------------------------------------------------------------------- random() / srandom() use the generator of rand() / srand() of the standard library |
| `void srandom(int seed)` |  |
| `void srand48(int seed)` |  |
| `int seed48(int* seed16v)` | sets the whole 48-bit state from three 16-bit values (seed16v[0] is the lowest); returns nothing useful |
| `int lrand48()` | 0 ... 2^31-1 |
| `int mrand48()` | -2^31 ... 2^31-1 |
| `int drand48()` |  |
| `int erand48(int* xsubi)` | like drand48 / lrand48 with the state given as three 16-bit values in xsubi[0..2], which are updated |
| `int atexit(func f)` | ---- function pointer functions -------------------------------------------------------------------------- registers a function (no arguments) that exit calls when the program ends, last registered first. Returns 0, or -1 when 32 functions are registered already. |
| `void qsort(char* base, int n, int size, func cmp)` |  |
| `char* bsearch(char* key, char* base, int n, int size, func cmp)` | binary search in a sorted array: returns the address of an element equal to key, null if there is none |
| `void abort()` | ends the program abnormally (exit code 134, as after SIGABRT) |
| `void _Exit(int code)` |  |
| `void quick_exit(int code)` |  |
| `int mblen(char* s, int n)` | ---- multibyte characters (UTF-8) ---------------------------------------------------------------------------- number of bytes of the character at s (0 for the end of the text, -1 for an invalid sequence) |
| `int mbtowc(int* wc, char* s, int n)` | decodes one character into *wc; returns the bytes used (0 at the end of the text, -1 if invalid) |
| `int wctomb(char* s, int wc)` | encodes the character wc; returns the number of bytes (-1 if it cannot be encoded) |
| `int mbstowcs(int* dst, char* src, int n)` | converts a UTF-8 text into at most n wide characters (ints); returns how many were stored (-1 if invalid) |
| `int wcstombs(char* dst, int* src, int n)` | converts wide characters (0-terminated) into at most n bytes of UTF-8; returns the bytes stored |

### cstdio
`<stdio.h>` - Streams, `printf` and `scanf` families, files, pipes.  
`import cstdio;`

```text
cstdio - C <stdio.h>                                       import cstdio;

Streams (`FILE*`) with the C names: fopen fclose fread fwrite fgetc fputc fgets fputs fseek ftell
rewind feof ferror fflush setvbuf ungetc getline popen pclose tmpfile remove rename ...
and the printf / scanf families: fprintf sprintf snprintf vfprintf vsnprintf dprintf,
scanf fscanf sscanf vsscanf.

  stdin  stdout  stderr   the standard streams (they are constants, pass them wherever a FILE* is expected)
  printf                   is in the standard library; it prints to stdout like in C

Differences from C that come from the language:
  * there are no variable argument lists: the printf family takes up to eight values
    (text and pointers are passed as they are), the v... functions take an array of them (an `int*`),
    scanf takes up to eight pointers. Values are 64-bit, so %d / %i / %u / %x read and write a whole `int`;
    hh, h and l ... modifiers choose 1, 2 or 8 bytes in scanf.
  * output to files is buffered (4 KiB) and written out at fclose / fflush / exit; stdout and stderr
    are not buffered.
  * floating point (see cmath / cfloat): a double is the int that holds its bit pattern. scanf reads %f %lf %e %g into an int
    (8 bytes, also without the l); fprintfd / vfprintfd write %f %e %g %a. printf / fprintf / sprintf keep to the integer
    conversions (use printfd, sprintfd, snprintfd of cfloat for text on the screen or in buffers).
```

Constants: `EOF`, `SEEK_SET`, `SEEK_CUR`, `SEEK_END`, `BUFSIZ`, `FILENAME_MAX`, `FOPEN_MAX`, `TMP_MAX`, `L_tmpnam`, `_IOFBF`, `_IOLBF`, `_IONBF`, `stdin`, `stdout`, `stderr`

Types: `FILE`

| Function | Description |
|---|---|
| `FILE* fopen(char* path, char* mode)` | opens a file. mode: "r" read, "w" write (create / empty), "a" append, "+" adds the other direction, "x" fails if the file exists (with w), "b" is ignored. Returns null with errno set on failure. |
| `FILE* fdopen(int fd, char* mode)` | wraps an existing file descriptor / handle (mode as for fopen, without creation flags) |
| `int fileno(FILE* f)` |  |
| `int fflush(FILE* f)` |  |
| `int fclose(FILE* f)` |  |
| `FILE* freopen(char* path, char* mode, FILE* f)` | reopens a stream on another file (the old one is closed). stdin / stdout / stderr can be redirected as well? No: they keep their handles, so the standard streams cannot be reopened. |
| `int setvbuf(FILE* f, char* buf, int mode, int size = 4096)` | ---- buffering --------------------------------------------------------------------------------------------- mode: _IOFBF full buffering, _IOLBF line buffering, _IONBF none. The buffer argument is ignored (an internal one is used). |
| `void setbuf(FILE* f, char* buf)` |  |
| `int fseek(FILE* f, int offset, int whence)` |  |
| `int ftell(FILE* f)` |  |
| `int fseeko(FILE* f, int offset, int whence)` |  |
| `int ftello(FILE* f)` |  |
| `void rewind(FILE* f)` |  |
| `int fgetpos(FILE* f, int* pos)` |  |
| `int fsetpos(FILE* f, int* pos)` |  |
| `int feof(FILE* f)` |  |
| `int ferror(FILE* f)` |  |
| `void clearerr(FILE* f)` |  |
| `int fgetc(FILE* f)` | ---- character input ------------------------------------------------------------------------------------------ next byte (0-255) or EOF |
| `int getc(FILE* f)` |  |
| `int getchar()` |  |
| `int ungetc(int c, FILE* f)` | pushes one character back; the next read returns it. Returns c, or EOF if there is no room / c is EOF |
| `char* fgets(char* buf, int n, FILE* f)` | reads a line of at most n-1 characters (the newline is kept) and ends it with a zero. Returns buf, null at the end / on error |
| `int fread(char* ptr, int size, int count, FILE* f)` | reads `count` items of `size` bytes; returns how many complete items were read |
| `int getdelim(char** line, int* cap, int delim, FILE* f)` | POSIX getline: reads a whole line (with the newline) into a malloc'ed buffer *line of size *cap (both are updated; start with *line = null, *cap = 0). Returns the length, -1 at the end. |
| `int getline(char** line, int* cap, FILE* f)` |  |
| `int fputc(int c, FILE* f)` |  |
| `int putc(int c, FILE* f)` |  |
| `int putchar(int c)` |  |
| `int fputs(char* s, FILE* f)` | writes the text without a newline; returns 0, or EOF on failure |
| `int puts(char* s)` | writes the text and a newline to stdout |
| `int fwrite(char* ptr, int size, int count, FILE* f)` | writes count items of size bytes; returns how many complete items were written |
| `int vfprintf(FILE* f, char* fmt, int* args, int n)` | ---- formatted output ------------------------------------------------------------------------------------------ vfprintf: the values are an array (see vformat in the standard library for the formats) |
| `int vprintf(char* fmt, int* args, int n)` |  |
| `int fprintf(FILE* f, char* fmt, int a = 0, int b = 0, int c = 0, int d = 0, int e = 0, int g = 0, int h = 0, int i = 0)` |  |
| `int vfprintfd(FILE* f, char* fmt, int* args, int n)` | like vfprintf, with %f %e %g %a for doubles |
| `int fprintfd(FILE* f, char* fmt, int a = 0, int b = 0, int c = 0, int d = 0, int e = 0, int g = 0, int h = 0, int i = 0)` |  |
| `int vsprintf(char* out, char* fmt, int* args, int n)` | the buffer must be large enough for the result |
| `int vsnprintf(char* out, int size, char* fmt, int* args, int n)` | writes at most size-1 characters and a zero; returns the length the full result has |
| `int sprintf(char* out, char* fmt, int a = 0, int b = 0, int c = 0, int d = 0, int e = 0, int f = 0, int g = 0, int h = 0)` |  |
| `int snprintf(char* out, int size, char* fmt, int a = 0, int b = 0, int c = 0, int d = 0, int e = 0, int f = 0, int g = 0, int h = 0)` |  |
| `int dprintf(int fd, char* fmt, int a = 0, int b = 0, int c = 0, int d = 0, int e = 0, int f = 0, int g = 0, int h = 0)` | printf to a raw file descriptor |
| `int remove(char* path)` | deletes a file or an empty directory; 0 on success, -1 with errno set |
| `int rename(char* from, char* to)` | renames or moves a file or directory (an existing destination is replaced); 0 on success, -1 with errno set |
| `char* tmpnam(char* buf)` | makes up a name for a temporary file ("/tmp/tmpXXXXXX", or in %TEMP% on Windows); buf must hold 260 characters. Returns buf (or a static buffer when buf is null). |
| `FILE* tmpfile()` | an anonymous temporary file opened "w+"; it disappears when it is closed |
| `FILE* popen(char* command, char* mode)` | starts a shell command and returns a stream connected to its output ("r") or input ("w") |
| `int pclose(FILE* f)` | closes a popen stream and returns the exit code of the command |
| `int vsscanf(char* text, char* fmt, int* ptrs, int n)` |  |
| `int vfscanf(FILE* f, char* fmt, int* ptrs, int n)` |  |
| `int vscanf(char* fmt, int* ptrs, int n)` |  |
| `int sscanf(char* text, char* fmt, int a = 0, int b = 0, int c = 0, int d = 0, int e = 0, int f = 0, int g = 0, int h = 0)` |  |
| `int fscanf(FILE* fl, char* fmt, int a = 0, int b = 0, int c = 0, int d = 0, int e = 0, int f = 0, int g = 0, int h = 0)` |  |
| `int scanf(char* fmt, int a = 0, int b = 0, int c = 0, int d = 0, int e = 0, int f = 0, int g = 0, int h = 0)` |  |

### ctime
`<time.h>` - Clocks, calendar time, time zones, `strftime`.  
`import ctime;`

```text
ctime - C <time.h>                                         import ctime;

time clock difftime clock_gettime gettimeofday
struct tm:  gmtime localtime gmtime_r localtime_r mktime timegm
text:       strftime strptime asctime ctime
zones:      tzset (reads the TZ variable, or /etc/localtime on Linux, or UTC); `timezone_name()`

Times are `int` seconds since 1970-01-01 00:00:00 UTC. Functions that take a `time_t*` in C take an
`int*` here:  int t = time(null);  tm* p = localtime(&t);
Local time follows the POSIX rules of the TZ variable ("EET-2EEST,M3.5.0/3,M10.5.0/4", "UTC", "EST5EDT"),
or the rule at the end of /etc/localtime when TZ is not set (Linux/Android). Without either, local time is UTC.
```

Constants: `CLOCKS_PER_SEC`, `CLOCK_REALTIME`, `CLOCK_MONOTONIC`, `CLOCK_PROCESS_CPUTIME_ID`, `TIME_UTC`

Types: `tm`, `timespec`, `timeval`

| Function | Description |
|---|---|
| `int clock_gettime(int id, timespec* ts)` | ---- clocks ------------------------------------------------------------------------------------------------------- reads a clock: id CLOCK_REALTIME (seconds since 1970), CLOCK_MONOTONIC, or CLOCK_PROCESS_CPUTIME_ID. Returns 0 or -1 |
| `int timespec_get(timespec* ts, int base)` |  |
| `int gettimeofday(timeval* tv)` |  |
| `int time(int* t = null)` | seconds since 1970; also stored in *t when t is not null |
| `int clock()` | processor time used by the program in CLOCKS_PER_SEC (1,000,000) units. On Windows this is the time since the first call. |
| `int nanosleep(timespec* req, timespec* rem = null)` | sleeps for the given time (rounded up to milliseconds); returns 0 |
| `int difftime(int a, int b)` | a - b in seconds |
| `int timegm(tm* p)` | seconds since 1970 for the date fields of p, which are normalized first (month 13 = January of next year, day 0 = last of the previous month, 70 seconds = 1 minute 10 seconds ...). Treats the fields as UTC. |
| `void tzset()` | (re)reads the time zone from the TZ variable or /etc/localtime |
| `char* timezone_name()` | the name of the zone that is in effect now |
| `tm* gmtime_r(int* t, tm* out)` | ---- conversions --------------------------------------------------------------------------------------------------- breaks a time into UTC calendar fields; fills out and returns it |
| `tm* localtime_r(int* t, tm* out)` |  |
| `tm* gmtime(int* t)` | the result of gmtime / localtime is a static record that the next call overwrites |
| `tm* localtime(int* t)` |  |
| `int mktime(tm* p)` | seconds since 1970 for local time fields (normalized, and tm_isdst / tm_gmtoff / tm_wday / tm_yday filled in) |
| `int strftime(char* out, int max, char* fmt, tm* p)` | formats p according to fmt (like C): %a %A day name  %b %h %B month name  %c date and time  %C century  %d day  %D %m/%d/%y  %e day, space padded %F %Y-%m-%d  %g %G ISO year  %H hour 00-23  %I hour 01-12  %j day of year  %k %l hour, space padded  %m month %M minute  %n newline  %p AM/PM  %P am/pm  %r %I:%M:%S %p  %R %H:%M  %s seconds since 1970  %S second  %t tab %T %H:%M:%S  %u weekday 1-7  %U %W %V week numbers  %w weekday 0-6  %x date  %X time  %y %Y year  %z +hhmm  %Z zone  %% Returns the number of characters stored (0 if they do not fit in max). |
| `char* asctime(tm* p)` | "Sun Sep 16 01:03:52 1973\n" (in a static buffer) |
| `char* ctime(int* t)` |  |
| `char* strptime(char* s, char* fmt, tm* p)` | reads a date / time from s according to fmt into p (POSIX strptime). Supports %Y %y %m %d %e %H %M %S %I %p %j %b %B %h %a %A %T %R %D %F %y %z %Z %n %t %% and white space. Returns the address after the used text, null on a mismatch. |
| `bool strncasecmp_(char* a, char* b, int n)` |  |

### cmath
`<math.h>` `<float.h>` - Floating point arithmetic and mathematical functions on software doubles.  
`import cmath;`

```text
cmath - C <math.h> and <float.h> for A                      import cmath;

A has no floating point types, so a `double` is an `int` that holds the 64-bit IEEE 754 bit pattern
of the number. Every operation is done in software, exactly rounded like on a CPU (round to nearest even),
and works the same on every platform. Names are the C names: sqrt, sin, pow, floor, fmod ...

   int x = dlit("2.5");               // a double from text (or itod(3) from an int)
   int y = sqrt(dmul(x, x));          // arithmetic by function: dadd dsub dmul ddiv dneg
   printfd("%.3f\n", y);              // printing: printfd / sprintfd (import cfloat;)

Constants M_PI, M_E ... INFINITY, NAN, DBL_MAX ... are bit patterns too.
sqrt and the basic operations are exact (error 0); exp, log, sin, pow ... are computed with ~100 bits
and rounded once, so they are within 1 ulp (nearly always correctly rounded).
```

Constants: `INFINITY`, `HUGE_VAL`, `NAN`, `NEG_INFINITY`, `M_E`, `M_LOG2E`, `M_LOG10E`, `M_LN2`, `M_LN10`, `M_PI`, `M_PI_2`, `M_PI_4`, `M_1_PI`, `M_2_PI`, `M_2_SQRTPI`, `M_SQRT2`, `M_SQRT1_2`, `DBL_MANT_DIG`, `DBL_DIG`, `DBL_DECIMAL_DIG`, `DBL_MIN_EXP`, `DBL_MAX_EXP`, `DBL_MIN_10_EXP`, `DBL_MAX_10_EXP`, `DBL_MAX`, `DBL_MIN`, `DBL_TRUE_MIN`, `DBL_EPSILON`, `FLT_RADIX`, `FP_NAN`, `FP_INFINITE`, `FP_ZERO`, `FP_SUBNORMAL`, `FP_NORMAL`, `DD_LN2_H`, `DD_LN2_L`, `DD_LN10_H`, `DD_LN10_L`, `DD_PI_H`, `DD_PI_L`, `DD_PI2_H`, `DD_PI2_L`, `DD_PI4_H`, `DD_PI4_L`, `DD_3PI4_H`, `DD_3PI4_L`, `DD_E_H`, `DD_E_L`, `DD_SQRTPI_H`, `DD_SQRTPI_L`, `DD_2_SQRTPI_H`, `DD_2_SQRTPI_L`, `DD_HLN2PI_H`, `DD_HLN2PI_L`, `DD_SQRT2_H`, `DD_SQRT2_L`, `DD_INVLN2_H`, `DD_INVLN2_L`, `STIR1_H`, `STIR1_L`, `STIR2_H`, `STIR2_L`, `STIR3_H`, `STIR3_L`, `STIR4_H`, `STIR4_L`, `STIR5_H`, `STIR5_L`, `STIR6_H`, `STIR6_L`, `STIR7_H`, `STIR7_L`, `STIR8_H`, `STIR8_L`, `STIR9_H`, `STIR9_L`, `STIR10_H`, `STIR10_L`, `STIR11_H`, `STIR11_L`, `STIR12_H`, `STIR12_L`, `STIR13_H`, `STIR13_L`, `STIR14_H`, `STIR14_L`, `STIR15_H`, `STIR15_L`, `STIR16_H`, `STIR16_L`, `STIR17_H`, `STIR17_L`, `STIR18_H`, `STIR18_L`, `STIR19_H`, `STIR19_L`, `STIR20_H`, `STIR20_L`, `DD_EULER_H`, `DD_EULER_L`, `DD_ZETA2_H`, `DD_ZETA2_L`, `DD_ZETA3_H`, `DD_ZETA3_L`, `DD_ZETA4_H`, `DD_ZETA4_L`, `DD_ZETA5_H`, `DD_ZETA5_L`, `DD_ZETA6_H`, `DD_ZETA6_L`, `DD_ZETA7_H`, `DD_ZETA7_L`, `DD_ZETA8_H`, `DD_ZETA8_L`, `DD_ZETA9_H`, `DD_ZETA9_L`, `DD_ZETA10_H`, `DD_ZETA10_L`, `DD_ZETA11_H`, `DD_ZETA11_L`, `DD_ZETA12_H`, `DD_ZETA12_L`, `DD_ZETA13_H`, `DD_ZETA13_L`

| Function | Description |
|---|---|
| `bool isnan(int x)` | ---- classification ---------------------------------------------------------------------------------------------- |
| `bool isinf(int x)` |  |
| `bool isfinite(int x)` |  |
| `bool isnormal(int x)` |  |
| `bool signbit(int x)` |  |
| `int fpclassify(int x)` | FP_NAN, FP_INFINITE, FP_ZERO, FP_SUBNORMAL or FP_NORMAL |
| `int fabs(int x)` |  |
| `int dneg(int x)` |  |
| `int copysign(int x, int y)` |  |
| `int dcmp(int a, int b)` | ---- comparison ------------------------------------------------------------------------------------------------------- -1, 0, 1, or 2 when the numbers are unordered (a NaN is involved). -0 equals +0. |
| `int dadd(int a, int b)` | ---- arithmetic (exactly rounded) ------------------------------------------------------------------------------------- |
| `int dsub(int a, int b)` |  |
| `int dmul(int a, int b)` |  |
| `int ddiv(int a, int b)` |  |
| `int sqrt(int a)` |  |
| `int itod(int n)` | ---- conversion from and to integers --------------------------------------------------------------------------------- the double closest to the integer n |
| `int dtoi(int x)` | the integer part of x (cut towards zero); too large values give the largest / smallest int, NaN gives 0 |
| `int trunc(int x)` | ---- rounding to integers ------------------------------------------------------------------------------------------------ cuts off the fraction (towards zero) |
| `int floor(int x)` |  |
| `int ceil(int x)` |  |
| `int round(int x)` | nearest integer, halves away from zero |
| `int rint(int x)` | nearest integer, halves to the even one (the usual rounding mode) |
| `int nearbyint(int x)` |  |
| `int lround(int x)` |  |
| `int llround(int x)` |  |
| `int lrint(int x)` |  |
| `int llrint(int x)` |  |
| `int scalbn(int x, int n)` | ---- exponent handling ------------------------------------------------------------------------------------------------------ x * 2^n, correctly rounded |
| `int ldexp(int x, int n)` |  |
| `int scalbln(int x, int n)` |  |
| `int frexp(int x, int* e)` | splits x into m * 2^e with 0.5 <= \|m\| < 1; stores e in *e |
| `int modf(int x, int* ip)` | splits x into integer part (stored in *ip) and fraction (returned), both with the sign of x |
| `int logb(int x)` | the exponent of x as a double (floor(log2(\|x\|))) |
| `int ilogb(int x)` | the exponent of x as an int (-2147483648 for 0 and NaN) |
| `int nan(char* tag)` |  |
| `int nextafter(int x, int y)` | the next representable number after x in the direction of y |
| `int nexttoward(int x, int y)` |  |
| `int fmax(int a, int b)` | ---- min, max, remainder ----------------------------------------------------------------------------------------------------- |
| `int fmin(int a, int b)` |  |
| `int fdim(int x, int y)` | positive difference: x - y if x > y, otherwise 0 |
| `int fmod(int x, int y)` |  |
| `int remainder(int x, int y)` | IEEE remainder: x - n*y where n is x/y rounded to nearest (halves to even) |
| `int remquo(int x, int y, int* quo)` | like remainder; the low bits of the quotient go to *quo (with the sign of x/y) |
| `int exp(int x)` |  |
| `int exp2(int x)` |  |
| `int expm1(int x)` |  |
| `int log(int x)` |  |
| `int log2(int x)` |  |
| `int log10(int x)` |  |
| `int log1p(int x)` |  |
| `int pow(int x, int y)` |  |
| `int cbrt(int x)` | cube root |
| `int hypot(int x, int y)` | sqrt(x*x + y*y) without overflow |
| `int fma(int x, int y, int z)` | x * y + z with a single rounding |
| `int sin(int x)` |  |
| `int cos(int x)` |  |
| `int tan(int x)` |  |
| `int atan(int x)` |  |
| `int atan2(int y, int x)` |  |
| `int asin(int x)` |  |
| `int acos(int x)` |  |
| `int cosh(int x)` |  |
| `int sinh(int x)` |  |
| `int tanh(int x)` |  |
| `int asinh(int x)` |  |
| `int acosh(int x)` |  |
| `int atanh(int x)` |  |
| `int erf(int x)` |  |
| `int erfc(int x)` | erfc(x) = 1 - erf(x) without losing the small result for large x |
| `int lgamma(int x)` |  |
| `int tgamma(int x)` |  |

### cfloat
(`strtod`, `printf` conversions) - Text to double, double to text, `printf` with `%f %e %g %a`.  
`import cfloat;`

```text
cfloat - text <-> double, printf with floating point       import cfloat;   (needs cmath, which it imports)

  strtod atof            text to double (decimal, hexadecimal, inf, nan; correctly rounded)
  dtostr(x)              shortest text that reads back as exactly x (like Python's repr: "0.1", "1e+22", "1.5")
  printfd sprintfd snprintfd eprintfd vformatd formatd
                         printf family that understands %f %F %e %E %g %G %a %A besides everything vformat knows.
                         A double is passed like any other value: its bit pattern (see cmath).

   printfd("%d squared is %.3f\n", 2, dmul(dlit("1.5"), dlit("1.5")));

The results are exactly rounded (the digits are computed with big integers), also for %.40f or 1e300.
```

| Function | Description |
|---|---|
| `int strtod(char* s, char** end)` | converts the start of s to a double: white space, sign, then a decimal number (123, 1.5, .5e-3), a hexadecimal one (0x1.8p3), inf / infinity or nan. *end (if not null) is set to the first unused character; if nothing could be converted it is s itself and the result is 0. |
| `bool isalnum_(int c)` |  |
| `int atof(char* s)` |  |
| `int dlit(char* s)` | the double that the text means ("2.5", "1e-3", "0x1p4", "inf") |
| `char* dtostr(int x)` | the shortest text that reads back as exactly x, in the style of Python's repr: 0.1  1.5  100.0  1e+22  1.5e-07  nan  inf |
| `int vformatd(char* out, int max, char* fmt, int* args, int nargs)` | like vformat (see the standard library) and also %f %F %e %E %g %G %a %A: the matching value is the bit pattern of a double |
| `int formatd(char* out, int max, char* fmt, int a = 0, int b = 0, int c = 0, int d = 0, int e = 0, int f = 0, int g = 0, int h = 0)` |  |
| `int sprintfd(char* out, char* fmt, int a = 0, int b = 0, int c = 0, int d = 0, int e = 0, int f = 0, int g = 0, int h = 0)` |  |
| `int snprintfd(char* out, int size, char* fmt, int a = 0, int b = 0, int c = 0, int d = 0, int e = 0, int f = 0, int g = 0, int h = 0)` |  |
| `int printfd(char* fmt, int a = 0, int b = 0, int c = 0, int d = 0, int e = 0, int f = 0, int g = 0, int h = 0)` | printf to stdout with floating point support |
| `int eprintfd(char* fmt, int a = 0, int b = 0, int c = 0, int d = 0, int e = 0, int f = 0, int g = 0, int h = 0)` | the same for standard error |

### cunistd
`<unistd.h>` `<sys/stat.h>` `<dirent.h>` `<fcntl.h>` `<signal.h>` `<fnmatch.h>` - POSIX files, directories, processes, signals, `getopt`.  
`import cunistd;`

```text
cunistd - POSIX <unistd.h>, <sys/stat.h>, <dirent.h>, <fcntl.h>, getopt     import cunistd;

Process, file system and directory functions with the C/POSIX names, working on Linux, Android and Windows:
  getpid getppid getuid getgid gethostname getcwd chdir mkdir rmdir unlink link symlink readlink realpath
  access chmod stat lstat fstat (Stat) S_ISDIR S_ISREG S_ISLNK  truncate ftruncate fsync
  open read write close lseek dup dup2 pipe isatty
  sleep usleep fork waitpid execv execvp kill raise _exit       (fork, kill ... : Linux and Android only)
  opendir readdir closedir (DIR, Dirent)         getopt (optarg optind opterr optopt)
  mkstemp mkdtemp  fnmatch  signal alarm pause (signals: Linux and Android)
File descriptors are the plain numbers of the operating system (handles on Windows).
Failing calls return -1 (or null) and set errno (see cerrno).
```

Constants: `F_OK`, `X_OK`, `W_OK`, `R_OK`, `O_RDONLY`, `O_WRONLY`, `O_RDWR`, `O_CREAT`, `O_EXCL`, `O_TRUNC`, `O_APPEND`, `S_IFMT`, `S_IFDIR`, `S_IFREG`, `S_IFLNK`, `SIGHUP`, `SIGINT`, `SIGQUIT`, `SIGABRT`, `SIGKILL`, `SIGUSR1`, `SIGSEGV`, `SIGUSR2`, `SIGPIPE`, `SIGALRM`, `SIGTERM`, `STDIN_FILENO`, `STDOUT_FILENO`, `STDERR_FILENO`, `FNM_PATHNAME`, `FNM_NOESCAPE`, `FNM_PERIOD`, `FNM_CASEFOLD`, `FNM_NOMATCH`, `SIG_DFL`, `SIG_IGN`, `SIG_ERR`

Types: `Stat`, `Dirent`, `DIR`

| Function | Description |
|---|---|
| `int getpid()` | ---- process information ---------------------------------------------------------------------------------------- |
| `int getppid()` |  |
| `int getuid()` |  |
| `int getgid()` |  |
| `int geteuid()` |  |
| `int getegid()` |  |
| `int getpagesize()` |  |
| `int gethostname(char* name, int size)` | copies the host name into name (at most size bytes); 0 on success |
| `char* getcwd(char* buf, int size)` | the current directory copied into buf; returns buf, null on failure |
| `int chdir(char* path)` |  |
| `int mkdir(char* path, int mode = 493)` |  |
| `int rmdir(char* path)` |  |
| `int unlink(char* path)` |  |
| `int link(char* existing, char* newpath)` | hard link (Linux and Android) |
| `int symlink(char* target, char* linkpath)` | symbolic link (Linux and Android) |
| `int readlink(char* path, char* buf, int size)` | reads the target of a symbolic link into buf (no zero is added); returns its length, -1 on failure |
| `int access(char* path, int mode)` | checks whether a file exists (F_OK) and can be read / written / executed (R_OK, W_OK, X_OK; or-ed together) |
| `int chmod(char* path, int mode)` |  |
| `char* realpath(char* path, char* buf)` | the absolute path of a file with symbolic links resolved (the file must exist). buf needs PATH_MAX (4096) bytes. Returns buf, null on failure. |
| `bool S_ISDIR(int mode)` |  |
| `bool S_ISREG(int mode)` |  |
| `bool S_ISLNK(int mode)` |  |
| `int stat(char* path, Stat* st)` | information about a file: size, kind, times. 0 on success, -1 if the file does not exist |
| `int lstat(char* path, Stat* st)` | like stat, but a symbolic link is not followed |
| `int fstat(int fd, Stat* st)` |  |
| `int ftruncate(int fd, int len)` |  |
| `int truncate(char* path, int len)` |  |
| `int fsync(int fd)` |  |
| `int open(char* path, int flags, int mode = 420)` | ---- file descriptors -------------------------------------------------------------------------------------------------- opens a file with the O_* flags (O_RDONLY / O_WRONLY / O_RDWR, or-ed with O_CREAT, O_EXCL, O_TRUNC, O_APPEND) |
| `int read(int fd, char* buf, int n)` | reads up to n bytes; returns the count, 0 at the end, -1 on failure |
| `int write(int fd, char* buf, int n)` |  |
| `int close(int fd)` |  |
| `int lseek(int fd, int offset, int whence)` |  |
| `int dup(int fd)` |  |
| `int dup2(int old, int nw)` |  |
| `int pipe(int* fds)` | creates a pipe: fds[0] is the read end, fds[1] the write end (an array of two ints). 0 on success |
| `bool isatty(int fd)` |  |
| `int sleep(int seconds)` | ---- time --------------------------------------------------------------------------------------------------------------- waits for the given number of seconds; returns 0 |
| `int usleep(int microseconds)` |  |
| `void _exit(int code)` | ---- processes --------------------------------------------------------------------------------------------------------- |
| `int fork()` | creates a copy of the program: returns 0 in the child and the child's process id in the parent (Linux and Android) |
| `int waitpid(int pid, int* status, int options = 0)` | waits for the child `pid` (-1 = any); the status is stored in *status (exit code in bits 8-15). Returns the pid, -1 on failure |
| `int execv(char* path, char** argv)` | replaces the program with another one: argv is a null-terminated array of strings |
| `int execvp(char* file, char** argv)` | like execv, but a name without '/' is searched in the directories of PATH |
| `int kill(int pid, int sig)` | sends a signal to a process (Linux and Android) |
| `int raise(int sig)` |  |
| `DIR* opendir(char* path)` | starts reading a directory; null (with errno set) if it cannot be opened |
| `Dirent* readdir(DIR* d)` | the next entry (a static record inside the DIR), null at the end |
| `int closedir(DIR* d)` |  |
| `int getopt(int argc, char** argv, char* optstring)` | POSIX option parsing:  while ((c = getopt(argc, argv, "ab:c")) != -1) ... Letters followed by ':' take an argument (in optarg). Returns the option letter, '?' for an unknown option, ':' for a missing argument if optstring starts with ':', -1 when the options are used up (optind = first other argument). |
| `int mkstemp(char* tmpl)` | creates and opens a new file whose name is the template with its XXXXXX replaced; returns the descriptor, -1 on failure |
| `char* mkdtemp(char* tmpl)` | creates a new directory from the template; returns the template, null on failure |
| `int fnmatch(char* pattern, char* name, int flags = 0)` | shell style wildcard matching:  * ? [abc] [a-z] [!x]  with backslash escapes. Returns 0 when the name matches, FNM_NOMATCH otherwise. flags: FNM_PATHNAME (wildcards do not match '/'), FNM_PERIOD (a leading '.' needs an explicit '.'), FNM_NOESCAPE, FNM_CASEFOLD. |
| `func signal(int sig, func handler)` | installs a signal handler: a function void handler(int sig), or SIG_DFL (the default action) or SIG_IGN (ignore the signal). Returns the previous handler, or SIG_ERR (with errno set) on failure. Signals are available on Linux and Android only. |
| `int alarm(int seconds)` | delivers a SIGALRM to the program after the given number of seconds (0 cancels); returns the seconds that were left |
| `int pause()` | waits until a signal arrives; returns -1 with errno EINTR |

### clocale
`<locale.h>` - The "C" locale.  
`import clocale;`

```text
clocale - C <locale.h>                                     import clocale;

A programs always run in the "C" locale (ASCII rules, decimal point '.', no digit grouping). setlocale accepts
"", "C", "POSIX" and names that end in ".UTF-8" / ".utf8" (text is UTF-8 anyway) and reports the locale as "C".
```

Constants: `LC_CTYPE`, `LC_NUMERIC`, `LC_TIME`, `LC_COLLATE`, `LC_MONETARY`, `LC_MESSAGES`, `LC_ALL`

Types: `lconv`

| Function | Description |
|---|---|
| `char* setlocale(int category, char* locale)` | the locale of category `category`; with a name it "sets" it. Returns "C", or null when the name is not known |
| `lconv* localeconv()` | number formatting conventions of the locale (the "C" ones) |

### cwchar
`<wchar.h>` `<wctype.h>` - Wide characters and strings (Unicode code points in ints).  
`import cwchar;`

```text
cwchar - C <wchar.h> and <wctype.h>                        import cwchar;

Wide characters are Unicode code points stored in ints; a wide string is an `int*` ended by a 0.
The functions have the C names: wcslen wcscpy wcsncpy wcscat wcsncat wcscmp wcsncmp wcschr wcsrchr wcsstr
wcsspn wcscspn wcspbrk wcstok wcsdup  wmemcpy wmemmove wmemset wmemcmp wmemchr  wcstol wcstoul  btowc wctob
wcwidth wcswidth  and the classification iswalpha iswdigit iswalnum iswspace iswupper iswlower iswpunct iswprint
iswgraph iswcntrl iswxdigit iswblank  towupper towlower.
Conversions to and from UTF-8 text are mbstowcs / wcstombs (cstdlib) - this module imports cstdlib so they come along.
Letters and case mapping cover ASCII, Latin-1, Latin Extended-A, Greek, Cyrillic and the common scripts
(Hebrew, Arabic, Devanagari, Thai, Hiragana, Katakana, CJK, Hangul) for classification.
```

Constants: `WEOF`

| Function | Description |
|---|---|
| `int wcslen(int* s)` | ---- strings --------------------------------------------------------------------------------------------------- |
| `int* wcscpy(int* dst, int* src)` |  |
| `int* wcsncpy(int* dst, int* src, int n)` |  |
| `int* wcscat(int* dst, int* src)` |  |
| `int* wcsncat(int* dst, int* src, int n)` |  |
| `int wcscmp(int* a, int* b)` |  |
| `int wcsncmp(int* a, int* b, int n)` |  |
| `int* wcschr(int* s, int c)` |  |
| `int* wcsrchr(int* s, int c)` |  |
| `int* wcsstr(int* hay, int* needle)` |  |
| `int wcsspn(int* s, int* accept)` |  |
| `int wcscspn(int* s, int* reject)` |  |
| `int* wcspbrk(int* s, int* accept)` |  |
| `int* wcstok(int* s, int* delim, int** save)` | like strtok: the position is kept in *save |
| `int* wcsdup(int* s)` |  |
| `int* wmemcpy(int* dst, int* src, int n)` |  |
| `int* wmemmove(int* dst, int* src, int n)` |  |
| `int* wmemset(int* dst, int c, int n)` |  |
| `int wmemcmp(int* a, int* b, int n)` |  |
| `int* wmemchr(int* s, int c, int n)` |  |
| `int wcstol(int* s, int** end, int base = 10)` | number conversion (digits are ASCII): the same rules as strtol |
| `int wcstoul(int* s, int** end, int base = 10)` |  |
| `int btowc(int c)` | single byte <-> wide character (ASCII only: other bytes give WEOF / -1) |
| `int wctob(int c)` |  |
| `bool iswupper(int c)` | ---- classification ---------------------------------------------------------------------------------------------- |
| `bool iswlower(int c)` |  |
| `bool iswalpha(int c)` |  |
| `bool iswdigit(int c)` |  |
| `bool iswxdigit(int c)` |  |
| `bool iswalnum(int c)` |  |
| `bool iswspace(int c)` |  |
| `bool iswblank(int c)` |  |
| `bool iswcntrl(int c)` |  |
| `bool iswprint(int c)` |  |
| `bool iswgraph(int c)` |  |
| `bool iswpunct(int c)` |  |
| `int towupper(int c)` | ---- case mapping ----------------------------------------------------------------------------------------------------- |
| `int towlower(int c)` |  |
| `int wcwidth(int c)` | ---- display width (columns in a terminal) ------------------------------------------------------------------------------- -1 for control characters, 0 for combining marks, 2 for wide (CJK, emoji) characters, otherwise 1 |
| `int wcswidth(int* s, int n)` | columns used by the first n characters of s (-1 if one of them is a control character) |

