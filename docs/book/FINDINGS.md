# What writing the book found

Every module and language feature of the book was run, so the book also became a test of the compiler and the library. This is the index of what turned up. Every item was reproduced on this branch; the reproductions (3 to 15 lines each) are in the `NOTES-*.md` file named in the last column. The chapters describe the **real** behaviour and warn the reader where it is a trap.

Nothing here was fixed by the book work: `lib/` and `src/` were left alone on purpose (the tier-2 work changes them). Items that the tier-2 work has since fixed are struck through.

## Compiler and language

| Finding | Where |
|---|---|
| `Class c;` (no parentheses) does **not** run the constructor; only `Class c();`, `Class c(args);` and `new` do. `docs/LANGUAGE.md`, `docs/TUI.md`, `lib/term.a` and `docs/AIDE.md` show the form without parentheses; for `term.Terminal t;` this crashes with SIGFPE | NOTES-lang 1, NOTES-gui2 a1 |
| `==` on two struct values compiles and silently does not compare the fields | NOTES-lang 4 |
| A bare `sqrt(2.0)` after `import dmath;` calls the C-library bit-pattern function and gives 2.19e+18 with no diagnostic (use `dmath.sqrt`); likewise `double x = M_PI;` and `printfd("%f", d)` with a double variable | NOTES-lang 2, 3; NOTES-stdlib2 |
| A `void` function used as a value compiles and crashes at run time (`char* u = strUpper(line);`) | NOTES-net 1 |
| ~~Duplicate `case` labels are not diagnosed~~ **fixed** by the language work that landed after the first book version (`duplicate case label`, also for ranges and texts); a `switch` on text now compares the text | NOTES-lang 5 |
| Structs, constants and enums may be used before their declaration inside function bodies (the reference says they may not); a base class must still come first | NOTES-lang 5, chapter 10 |
| A top-level function cannot reuse a prelude name (`max`, `min`, `find`); a global named `find` gives an error that points into `<std>` | NOTES-lang 5, NOTES-gui2 a4 |
| `const char*` gives "unknown type"; octal literals do not exist (`0755` is decimal 755) | NOTES-stdlib2 4, 5 |
| In `#if`, a letter inside a character constant is replaced by 0 (`#if 'a' == 'b'` is true) | src/pp.asm, found by the chapter 18 review |
| A global class object with a constructor gives a misleading error | NOTES-gui2 a5 |
| `android-loongarch64` is accepted by the compiler and the test runner but is not in `docs/TARGETS.md` | chapter 3 |

## Library: data, text and numbers

| Finding | Where |
|---|---|
| `utf8.isValid` accepts overlong sequences, surrogate halves and code points above U+10FFFF; `utf8.reverse` silently cuts at 1024 code points | NOTES-stdlib1 1, 2 |
| `json` wraps integers beyond 64 bits without an error, accepts leading zeros (`007`); `asInt()` of `1e3` is 1 | NOTES-stdlib1 3 |
| `nn.Network.accuracy` is always 100 for a single-output network | NOTES-stdlib1 4 |
| `ini.toString()` writes a value that contains a quote so that `parse` cannot read it back | NOTES-stdlib1 5 |
| `regex` accepts `(?x)` and ignores it; `groupIndex` of an unknown name returns 0 | NOTES-stdlib1 6, 7 |
| `docs/LANGUAGE.md` lists a hex `sha384` in `hash`; only `sha384Raw` exists; the `lib/nn.a` header shows `fit` with 5 arguments, it takes 6 | NOTES-stdlib1 (b) |

## Library: system, crypto and C library

| Finding | Where |
|---|---|
| `popen(cmd, "w")` hangs in `pclose` for commands that read to end of input (the pipe is not close-on-exec) | NOTES-stdlib2 1 |
| `_Exit`, `quick_exit` and `abort` run the `atexit` handlers; only `_exit` skips them | NOTES-stdlib2 2 |
| `log.infof` and friends need exactly four values; `import cstdio; import log;` (or `cmath` + `log`) fails because `cmath` declares `log`; `log.info` truncates messages above about 2,190 characters and loses the newline | NOTES-stdlib2 3, chapter 34 review |
| `os.fileSize("/proc")` is 0, not -1 (the "directory gives -1" rule holds on ordinary file systems only) | chapter 34 review |
| `cunistd.getopt` prints the wrong letter in the "option requires an argument" message | chapter 36 review |
| Stale header comments: `cpu.a` says all atomics are full memory barriers (`atomicLoad` is an ordinary load on x86-64); `rsa.a` and `ec.a` say "verification only" but `rsa.signPss` and `ec.sign` exist; `x509.verifyChain` has a fourth parameter `now`; `cmath.a` says A has no floating point; `cassert.a` says A has no macros | chapters 34, 35, 36 reviews |
| `docs/CLIB.md` says there is no `double`, no structs by value, no varargs, and lists leaked helper names; `README.md` repeats the "no float/double" claim and has old size figures (compiler 470 KB, 9,000 lines; now about 3 MB and 20,000 lines) | NOTES-stdlib2 (b), NOTES-lang (b) |

## Library: networking

| Finding | Where |
|---|---|
| `netif` silently drops sockets beyond 512; its count and search functions overwrite what `parse*` loaded | NOTES-net 2, 3 |
| `http.parseUrl` returns `true` with garbage for an IPv6 literal | NOTES-net 4 |
| ~~`websocket` uses an unseeded `rand()` for the handshake key and the masks~~ **fixed**: key and masks now come from the OS random generator (fresh mask per frame). ~~Allocates whatever frame length the peer announces~~ **fixed** (1009 close). `websocket.receive(buf, max, &op)` still leaves no terminating zero when a message fills the buffer (the new `Message.data` does) | NOTES-net 5, 6; NOTES-web |
| `dns.buildQuery` writes into the buffer before it validates the name | NOTES-net 7 |
| `net.recvLine` splits a line longer than the buffer into several lines; `conn.Connection.readLine` drops the rest instead; `readLine` cannot tell a time out from the end of the connection | NOTES-net 8, 9 |
| `http.Request.query` holds 1,024 bytes but a form body can be 64 MiB: the documented `strcpy(q->query, q->body)` overflows | chapter 41 review |
| The strict `wss://` / UTF-8 / permessage-deflate WebSocket, `wshub`, `sse`, `httpx` and `jsonrpc` are now on the branch and described in chapter 42 | NOTES-web |

## Library: GUI, display server, terminal and editor widgets

| Finding | Where |
|---|---|
| `gfx.Surface.shadow` fades the wrong way: the ring next to the rectangle is the lightest, the shadow ends in a hard edge, and window shadows (`spread 4, maxAlpha 50`) are nearly invisible. Suggested fix in the notes | NOTES-gui1 1, chapter 50 review |
| `gchart.Gauge`: the caption is cut off at the preferred height | NOTES-gui1 2 |
| `TextArea` has no selection and ignores Ctrl+A/C/X, although `docs/GUI.md` says text widgets support them | NOTES-gui1 3 |
| A custom widget only gets the mouse wheel when it overrides `wantsScroll()`; callbacks run while widgets are still being created (two sample crashes) | NOTES-gui1 4, 5 |
| `tuix.fileOpenDialog` resolves a relative start directory from `/`; `Button.isDefault` does nothing outside a `Dialog` | NOTES-gui2 a2, a3 |
| There is no way to read the port of a `wsrv.Server` / `wvnc.Vnc` / `wweb.Web` that was given port 0 | NOTES-gui2 a7 |
| `RunPane` prints the elapsed time, `ThemeEditor.setEntry` leaves the colour picker on the old colour, `gcode.pickColor` clips at the right edge, `Table` column width includes the sort arrow, `wfb.keyFor` with AltGr on the `us` layout returns the plain character | NOTES-gui2 a8 to a12 |
| `docs/GUI.md` says `ghtml` does not do forms (it does); `ADISPLAY=N` only means port 7000+N below 100; the `lib/gcode.a` header misplaces `RowList` and `FlatButton` | NOTES-gui2 (b) |

## Found while writing the chapters of the second round

| Finding | Where |
|---|---|
| `net.accept` on a non-blocking listener inside the idle hook hangs forever (use `net.acceptSome`); `docs/NET.md` does not warn about it | NOTES-web |
| `wshub`: `hub->close(c, ...)` on an SSE client in the same callback as `sendEvent` delivers nothing, not even the response head | NOTES-web |
| `jsonrpc.Client.dispose()` closes a connection given to `connectStream`, although the documentation says it stays yours; `sse.Client.reconnects` counts the first connection too | NOTES-web |
| `hub->listen` and `conn.Listener` bind 0.0.0.0 (`conn.Listener` has no host parameter); `net.secureAttach` has 512 slots (a new, undocumented limit) | NOTES-web |
| `lib/httpx.a` header names `httpx.cors` and `checkBearer`, which do not exist; `char* long = ...` says "expected a variable name" with no hint that `long` is reserved | NOTES-web |
| `ds.BitSet`: a zeroed `BitSet` ignores `set()` out of range although `docs/ALGO.md` says it grows; `strx.LineDiff d();` says "this class has no constructor"; `LruCache.dispose()` also calls the eviction handler | NOTES-algo |
| `static_assert(sizeof(ThisClass) ...)` placed before the class's last field gives contradictory answers (both `==` 16 and `!= 16` fail for a 16-byte class); put it after the last field | NOTES-lang2 |
| A function (not only a variable or field) named `rev` turns `foreach (x in rev a)` into the error `foreach needs an array, a range ...`; "does not implement the abstract method" points at the token after the class and does not name the class | NOTES-lang2 |
| `httpx.Router`: a `:param` or `*` value of 128 bytes or more is silently dropped but the route still runs with `param()` null (a handler that does `strlen` or `strcpy` on it crashes on a long URL); `wshub`: raising `maxClients` after `listen()` is ignored; a zeroed `websocket.Options o;` means `verify` false and all time-outs 0 | NOTES-web 6 to 8 |
| `ds` containers passed or assigned **by value** share their buffers, and when the copy grows it frees the original's buffer; `strx.levenshtein` and `lcsLength` are documented as O(min) memory but decode both texts first (about 8 bytes per input byte) | NOTES-algo |
| `docs/ALGO.md`: the `splitLines` + `run` example drops the no-newline flags (its patch differs from `diff -u`); `lib/strx.a` mentions `LineDiff.EQUAL` constants that do not exist; the "five targets" claim is stale; no callback signatures are given | NOTES-algo |

## What the book work verified and found *correct*

* 551 samples pass on x86-64; all compile for nine targets; all run with identical output under QEMU on ARM64, RISC-V 64 and LoongArch64 (five CPU-name samples excluded); 13 drawing samples give byte-identical PNGs on x86-64, ARM64 and RISC-V.
* Crypto test vectors (AES-GCM, ChaCha20-Poly1305, X25519, ECDSA P-256/P-384 per RFC 6979, DES, SHA-512 crypt) agree with OpenSSL and Python's `cryptography`; signatures made by A verify in OpenSSL. `srand48` / `lrand48` / `drand48` give glibc's numbers. The C ports in chapter 36 give the same output as the gcc-compiled originals.
* TLS 1.3 handshakes work over loopback in both directions; the A https client worked against `openssl s_server -tls1_3` and failed against `-tls1_2` (TLS 1.2 is not supported, as `docs/TLS.md` says).
* VNC (RFB 3.3, 3.7, 3.8, password, 16 and 32 bit pixels) and the web backend (token, origin check, lock-out) answered a throwaway Python client as the chapter 54 text says.
