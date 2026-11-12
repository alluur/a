# Notes of the contributor for chapters 34, 35 and 36 (system programming, cryptography, C library tour)

Everything below was found while writing and running the samples in `samples/sys`, `samples/crypto` and `samples/clib` with the
compiler of this branch (`build/ac`, x86-64 Linux). The samples compile for all 8 targets (`samples.py --targets`) but were **run** only on
x86-64 Linux.

## (a) Compiler and library bugs

### 1. `popen(cmd, "w")` hangs when the command reads until end of input

`lib/cstdio.a` makes the pipe with `pipe2(fds, 0)` (no `O_CLOEXEC`). `__spawn_shell` (lib/cstdlib.a) dup2s one end onto standard input
and leaves the original descriptors open, so the child also holds the *write* end of its own input pipe. `pclose` closes the parent's
write end and waits, but the command never sees the end of its input.

```c
import cstdio;
int main() {
    FILE* f = popen("cat", "w");      // or sort, tr ...
    fputs("x\n", f);
    pclose(f);                        // never returns
    return 0;
}
```

Observed: `x` is printed, then the program hangs (the test killed it after 3 s). In `"r"` mode the extra descriptor is harmless. Count of
pipe descriptors seen by `ls -l /proc/self/fd` in the child: 5 for `"w"`, 4 for `"r"`. Fix: create the parent's end with `O_CLOEXEC`
(or close it in the child). The chapter documents the problem in a warning; the sample uses `read word` in the shell, which ends by itself.

### 2. `_Exit`, `quick_exit` and `abort` run the `atexit` handlers

```c
import clib;
void bye() { println("handler ran"); }
int main() { atexit(bye); println("main"); _Exit(0); }    // prints "handler ran" too
```

Same for `quick_exit(0)` and `abort()` (the handler runs, then exit code 134). In C only `exit` runs the handlers. Only `_exit` of
`cunistd` leaves at once. The chapter says so ("in this implementation").

### 3. `log.infof` and friends need exactly four values

`log.infof("hello %d", 1)` gives `error: wrong number of arguments in call`, because `debugf infof warnf errorf` have no default values, while
`printf` accepts one to eight. The header of `lib/log.a` says "up to four values, like printf". Suggestion: default parameters `= 0`.

### 4. `const` is not accepted in a type

`int f(const char* s)` gives `error: unknown type` (pointing at `const`). The message is no help for people who port C code; LANGUAGE.md
does not say that `const` is only for constants. Related: `byte` (alias of `char`) cannot be used as a variable name (`uint8 byte = 0;` gives
`expected a variable name`).

### 5. Octal literals do not exist, and `0755` is silently decimal

`mkdir("d", 0755)` creates a directory with mode 1363 octal; `0o755` is a syntax error. This is a trap for everyone who ports C code that
sets permissions. LANGUAGE.md section 3 lists the literal forms but does not warn. The samples use `0b111101101` (underscores are ignored, so
`0b111_101_101` also works) or the decimal value, and chapter 36 has a warning.

## (b) Documentation that is wrong or incomplete

| File | Claim | What really happens |
|---|---|---|
| `docs/CLIB.md` (intro) | "There is no `float` / `double` type" | `double` is a real type (LANGUAGE.md section 7, `tests/t92_double.a`). The C library takes and returns doubles as `int` bit patterns; a `double` passed where an `int` is expected is converted to an integer, not reinterpreted (`printf("%d", 3.99)` prints 3, `printfd("%.2f", 3.99)` prints `0.00`, `double x = M_PI;` gives 4.6e18). Chapter 36 explains the relation and the `__bits` / `__dbl` bridge. Also `cmath.a`'s own header says "A has no floating point types". |
| `docs/CLIB.md` | "Structs cannot be passed or returned by value" | They can (LANGUAGE.md section 7, `tests/t57_struct_value.a`). Only `div`, `gmtime` ... return pointers to static records, which is true. |
| `docs/CLIB.md` | "Macros do not exist" | A has a C style preprocessor (LANGUAGE.md section 7). `#define CHECK(c) assertMsg(c, "check failed: " #c)` works and prints the expression (sample `clib/assert_fail`). The library's `assert` is a function, so it still cannot print the condition. |
| `docs/CLIB.md` (climits) | "UINT64_MAX / ULLONG_MAX do not exist" | `lib/climits.a` defines `UINT64_MAX`, `ULLONG_MAX`, `ULONG_MAX` as `uint64` constants (sample `clib/limits_table` prints `UINT64_MAX 18446744073709551615` with `%u`). |
| `docs/CLIB.md` | reference tables contain `abs64` (cstdlib), `isalnum_` (cfloat), `dmax_` (ccomplex), `strncasecmp_` (ctime) | internal helpers that leaked into the generated tables. |
| `docs/CLIB.md` (cstdio, `freopen`) | description ends "stdin / stdout / stderr can be redirected as well? No: ..." | an unfinished sentence in the generated text. |
| `lib/x509.a` header | `x509.verifyChain(chain, count, "example.com")` | the function has a fourth parameter, `now` (seconds since 1970): `verifyChain(chain, count, host, now)`. A good thing for tests (sample `crypto/x509_chain` uses a fixed date). |
| `lib/rsa.a`, `lib/ec.a` headers | "Verification only: no signing" | `rsa.signPss` and `ec.sign` exist (TLS.md lists them correctly). `ec.sign` returns a DER signature, takes a random nonce from `secure.bytes`. |
| `lib/aes.a` header | "16 or 32 byte key" | a 24 byte key (AES-192) also works: `aes.gcm(key, 24)` gave the same cipher text and tag as OpenSSL for a test vector (not shown in the book, not documented). |
| `lib/x509.a` | `loadSystemRoots()` "once" | `verifyChain` calls it itself unless `x509.clearRoots()` was called before (clearRoots sets the "loaded" flag). Needed for reproducible samples. |
| task description | "os (processes, environment, files, directories, time)" | the `os` module has only `getCwd`, `rename`, `fileSize`, `listDir`. Processes, environment and time are `cunistd`, `cstdlib`, `ctime` and the prelude (`millis`, `sleepMs`, `getEnv`). Chapter 34 covers them from those modules. |
| task description | "thread (... mutexes ...)" | there are no mutexes or condition variables; `cpu.lock` is a spin lock, `cpu.atomic*` are the atomics. The module header says the runtime is not thread safe (no `alloc`, `print` from several threads). On Windows `spawn` runs the function to its end first, so the producer/consumer sample would never finish there (marked `linux-only`). |
| `std` `getEnv(argc, argv, name)` | not documented in detail | it does not see changes made with `setenv` (checked: `setenv("XX","1",true)` then `getEnv` gives `null`, `getenv` gives the value). |
| `testing.summary()` | "exit code = number of failures" | true, but an exit code is a byte: 256 failures exit with 0. (`return 256 + 3;` from `main` exits with 3.) |
| `lib/cli.a` | `printHelp` | writes the usage to standard output, error messages go to standard error; at most 32 declared options and 64 positional arguments (further ones are silently ignored). |

## (c) Not covered, or only partly

* **Not run on other targets.** All 112 samples compile for the 8 targets; they were run on x86-64 Linux only. Windows, Android and ARM64 behaviour
  (the synchronous `spawn`, `ENOSYS` for `fork`, `symlink`, `signal`) is taken from the module headers and CLIB.md, not tested.
* **`tls` against a real server** (`crypto/tls_fetch`) is compile-only. TLS is shown in memory (`tls_memory`, `tls_checks`) and over a real
  loopback socket with a forked server (`tls_socket`, Linux only). The TLS chapter itself belongs to the networking contributor.
* **Not in the book** (no samples): `bn` (the big number engine; linked from the crypto chapter), `bigint`, `asys` (only linked), `datetime`,
  `random` (chapter 32), `hash` beyond SHA-2 and HMAC (SHA-1, MD5, CRC are not shown), `setjmp` / `longjmp` (built in, not a module), the
  `dm`, `adp` and other modules that are not on the list.
* **Not available in the library, so not shown:** key derivation (PBKDF2, HKDF, scrypt, argon2), RSA encryption, ECDH on NIST curves,
  AES modes other than GCM, Ed25519, SHA-3. The crypto chapter says so.
* `ctime` was shown with `gmtime`, `mktime` and `TZ` rules; `clock_gettime`, `nanosleep`, `gettimeofday` were tested while writing but the sample
  was cut to keep the number of samples down (it printed only checks like "slept at least 30 ms").

## Checks that the samples rely on (so you can judge the numbers)

* Crypto vectors were recomputed independently with Python's `cryptography` package (OpenSSL 3.0): AES-GCM test cases 2, 4 and 16, RFC 8439
  ChaCha20-Poly1305 and ChaCha20, RFC 7748 X25519, RFC 6979 ECDSA P-256 and P-384 (public keys derived from the private keys and the
  signatures verified), DES with `openssl enc -des-ecb` (legacy provider), the VNC answer, SHA-512 crypt with `openssl passwd -6`
  (including `rounds=10000`), and the book's test certificates with `openssl verify`. Signatures that A produced (`rsa.signPss`, `ec.sign`)
  were verified by OpenSSL once.
* The three ported C programs (`port_wordfreq`, `port_head`, `port_stats`) were compiled with `gcc` and give identical output (and exit status).
* `drand48` / `lrand48` / `mrand48` after `srand48(2026)` match glibc's numbers.
* Floating point output (`math_*`, `float_*`, `complex_*`) was compared with Python's `math` and `cmath`. One difference is on the Python side:
  `math.cbrt(27)` gives `3.0000000000000004`, A gives exactly `3`.
* Speeds quoted in chapter 35 (SHA-256 about 200 MB/s, ChaCha20-Poly1305 about 12 MB/s, AES-GCM about 2 MB/s, SHA-512 crypt with 5000 rounds
  5 ms) are single runs on one machine.

## Samples that depend on the machine in a way worth knowing

* `sys/cpu_arch` prints which branch `static if (__ARCH == 0)` compiled: the recorded output is for the x86-64 build.
* `sys/thread_print_sorted` uses `// book: sorted`; the recorded line order is the order of that run.
* `crypto/*` samples with random keys print only facts that do not depend on them (accepted / rejected, lengths).
* `clib/unistd_stat` and `sys/thread_producer_consumer` and `sys/cpu_fence` are marked `linux-only` because they need symbolic links or real threads.
