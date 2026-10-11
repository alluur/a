#!/usr/bin/env python3
"""Generates docs/CLIB.md: the reference of the C library modules, from the declarations and comments in lib/c*.a.
usage: python3 docs/gen_clib.py"""
import re, os
here = os.path.dirname(os.path.abspath(__file__))
lib = os.path.join(here, '..', 'lib')

MODULES = [
 ('cctype', '<ctype.h>', 'Character classification and conversion (ASCII).'),
 ('climits', '<limits.h> <stdint.h> <stddef.h>', 'Integer limits and `NULL`.'),
 ('cerrno', '<errno.h>', '`errno`, the error numbers, `strerror` and `perror`.'),
 ('cassert', '<assert.h>', '`assert`.'),
 ('cstring', '<string.h>', 'Memory and string functions.'),
 ('cstdlib', '<stdlib.h>', 'Memory allocation, number parsing, environment, processes, `qsort`.'),
 ('cstdio', '<stdio.h>', 'Streams, `printf` and `scanf` families, files, pipes.'),
 ('ctime', '<time.h>', 'Clocks, calendar time, time zones, `strftime`.'),
 ('cmath', '<math.h> <float.h> <fenv.h>', 'Floating point arithmetic and mathematical functions on software doubles.'),
 ('cfloat', '(`strtod`, `printf` conversions)', 'Text to double, double to text, `printf` with `%f %e %g %a`.'),
 ('cunistd', '<unistd.h> <sys/stat.h> <dirent.h> <fcntl.h> <signal.h> <fnmatch.h>', 'POSIX files, directories, processes, signals, `getopt`.'),
 ('ccomplex', '<complex.h>', 'Complex numbers: `Complex*`, `cmplx cadd cmul cabs csqrt cexp clog csin ...`.'),
 ('clocale', '<locale.h>', 'The "C" locale.'),
 ('cwchar', '<wchar.h> <wctype.h>', 'Wide characters and strings (Unicode code points in ints).'),
]

def fmt_hdr(h):
    return re.sub(r'<[^>]+>', lambda m: '`' + m.group(0) + '`', h)

def parse(path):
    lines = open(path).read().split('\n')
    items = []
    comment = []
    i = 0
    while i < len(lines):
        ln = lines[i]
        if ln.startswith('//'):
            comment.append(ln[2:].strip())
            i += 1
            continue
        m = re.match(r'^(struct|class)\s+(\w+)\s*\{', ln)
        if m and not m.group(2).startswith('__'):
            items.append(('struct', m.group(2), ln.strip(), comment))
        m = re.match(r'^const\s+(\w+)\s*=\s*(.+);\s*(//.*)?$', ln)
        if m and not m.group(1).startswith('__'):
            items.append(('const', m.group(1), m.group(2), comment[-1:] if False else []))
        m = re.match(r'^((?:int|char|bool|void|func|byte|long|\w+)\**)\s+(\w+)\s*\((.*)\)\s*\{\s*$', ln)
        if m and not m.group(2).startswith('__') and not ln.startswith(('if', 'for', 'while', 'return')):
            items.append(('func', m.group(2), ln.rstrip(' {').strip(), comment))
        if not ln.startswith('//'):
            comment = []
        i += 1
    return items

out = []
out.append(r'''# The C library of A

`import clib;` makes the whole C-style library available; the individual modules can also be imported one by one
(`import cstring;`). They are written in A, embedded in the compiler, and put their names into the **global
namespace** like the C headers do. Only the functions a program really uses end up in the executable.

| Module | C headers | Contents |
|---|---|---|''')
for name, hdr, desc in MODULES:
    out.append(f'| [`{name}`](#{name}) | {fmt_hdr(hdr)} | {desc} |')
out.append(r'''
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
* **Speed of the floating point functions.** Everything is done in software with integer instructions, bit-exact on every
  platform. On a current x86-64 machine: `dadd dsub dmul ddiv` about 0.1-0.3 microseconds, `sqrt` 0.4 microseconds,
  `sin cos exp log` 40-60 microseconds, `pow atan` 100-160 microseconds, `erf tgamma` 250-330 microseconds. That is fast enough
  for tools, simulations with thousands of steps and plots, but not for millions of calls.
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
''')
for name, hdr, desc in MODULES:
    path = os.path.join(lib, name + '.a')
    items = parse(path)
    out.append(f'### {name}')
    out.append(f'{fmt_hdr(hdr)} - {desc}  \n`import {name};`\n')
    # module header comment
    src = open(path).read().split('\n')
    head = []
    for ln in src[1:40]:
        if ln.startswith('//') and not ln.startswith('// ===='):
            head.append(ln[2:].rstrip())
        elif head:
            break
    text = '\n'.join(head).strip('\n')
    text = '\n'.join(l[2:] if l.startswith('  ') else l for l in text.split('\n'))
    out.append('```text\n' + text + '\n```\n')
    consts = [(n, v) for k, n, v, c in items if k == 'const']
    if consts:
        out.append('Constants: ' + ', '.join(f'`{n}`' for n, v in consts) + '\n')
    structs = [n for k, n, v, c in items if k == 'struct']
    if structs:
        out.append('Types: ' + ', '.join(f'`{n}`' for n in structs) + '\n')
    funcs = [(n, sig, c) for k, n, sig, c in items if k == 'func']
    if funcs:
        out.append('| Function | Description |\n|---|---|')
        for n, sig, c in funcs:
            d = ' '.join(c).replace('|', '\\|')
            out.append(f'| `{sig}` | {d} |')
        out.append('')
open(os.path.join(here, 'CLIB.md'), 'w').write('\n'.join(out) + '\n')
print('written docs/CLIB.md')
