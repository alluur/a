# Notes from the networking chapters (`40-networking.md`, `41-http-websocket-tls.md`)

Compiler: `build/ac` of this worktree. Everything below was run unless it says "not run".

## (a) Compiler and library bugs, and sharp edges

### 1. A `void` function can be used as a value; no diagnostic, crash at run time

`strUpper` / `strLower` are `void` functions that change the string in place (`lib/std.a`). Using the "result" compiles without a warning
and the program crashes (or prints garbage). I wrote this by mistake while preparing `net/tcp_fork_server`.

```c
void shout(char* s) { strUpper(s); }
int main() {
    char line[16];
    strcpy(line, "hello");
    char* r = shout(line);      // compiles; r is whatever was in the result register
    char* u = strUpper(line);   // compiles
    println(u);                 // segmentation fault
    return 0;
}
```

Expected: a compile error such as `function 'strUpper' does not return a value`.

### 2. `netif`: the socket table silently stops at 512 entries

`netif.connectionCount()` / `connectionAt()` keep at most 512 sockets (`socks[512]` in `lib/netif.a`). On a machine with more open
sockets (a busy server, or many connections in `TIME_WAIT`, which a test run produces quickly) the rest is dropped without any
indication. A first version of my sample `netif_loopback` looked for its own listening socket in the table and failed about one run in
three while other samples ran in parallel (`/proc/net/tcp` had 2283 lines). I removed the dependency on the table from the sample.

Reproduction: open more than 512 connections, list `netif.connectionAt(i)`; entries after 512 are missing. (Reading `/proc/net/tcp`
while sockets change can also skip or duplicate entries; that is the kernel's behaviour, but the header comment does not mention it.)

### 3. `netif`: `parse*` replaces the table, but the counting/searching functions re-read the system

`parseRoutes(text)` fills the module's table with the text, but `routeCount()`, `defaultGateway()`, `arpCount()`, `arpLookup()`,
`connectionCount()` and `interfaceCount()` call `refresh*()` first and overwrite it with the live data. Only `routeAt(i)` / `arpAt(i)` /
`connectionAt(i)` read the table as it is.

```c
import netif;
int main() {
    netif.parseRoutes("Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT\n"
                      "eth0\t00000000\t0101A8C0\t0003\t0\t0\t100\t00000000\t0\t0\t0\n");
    printlnInt(netif.defaultGateway());     // the machine's real gateway (here 0xC0000201), not 0xC0A80101
    return 0;
}
```

Not a bug as such (the parsers are meant for tests), but it makes "test with fixed text" surprising and the header does not say it.
The book chapter documents it.

### 4. `http.parseUrl` accepts an IPv6 literal and returns garbage

```c
import http;
int main() {
    http.Url* u = new http.Url();
    printlnInt(http.parseUrl("http://[::1]:80/", u));   // 1 (true)
    println(u->host);                                    // [
    printlnInt(u->port);                                 // 0
    println(u->path);                                    // /:1]:80/
    return 0;
}
```

Expected: `false` (IPv6 is not supported) or a correct split. The chapter only says that IPv6 literals are not supported.

### 5. `websocket`: handshake key and mask keys come from an unseeded `rand()`

`clientSend` takes the 16 random bytes of `Sec-WebSocket-Key`, and `sendFrame` the 4-byte mask, from `rand()`. A program that does not
call `srand` therefore sends the **same** key and masks on every run:

```c
import websocket;
import conn;
int main() {
    conn.Listener* l = new conn.Listener(0);
    conn.Connection* c = conn.open("127.0.0.1", l->port(), 1000);
    char key[40];
    websocket.clientSend(c, "localhost", l->port(), "/", key);
    println(key);      // FcWai4cGw3w/WghLHPKpPw==  on every run
    return 0;
}
```

RFC 6455 wants the masking key to be unpredictable (it protects against cache poisoning by intermediaries). Suggestion: seed from
`secure.bytes` inside the module. The chapter tells readers to call `srand(random.clockSeed())`.

### 6. `websocket.receive`: no terminating zero when the message fills the buffer; unbounded allocation per frame

`if (total < max) buf[total] = 0;`, so a text message of exactly `max` bytes (or a longer one that was cut) has no NUL. And
`alloc(f->length + 1)` is done for whatever length a frame announces (up to 2^63), before any data has arrived. Both are mentioned in the
chapter; the second one is a way for a stranger to exhaust a server's memory.

### 7. `dns.buildQuery` writes into the buffer before it validates the name

A call that returns `-1` for `"bad..name"` has already written the header (with the id) into `buf`. If the caller reuses the buffer
for the next query without noticing the `-1`, the old id is there. (I fell into it: my first `net/dns_message` copied a "query"
that had been overwritten.) The chapter tells readers to use a fresh buffer. Minor.

### 8. `net.recvLine` splits a long line

A line longer than `max - 1` characters is returned in pieces: the rest comes out as the next "line" (`"0123456789ABCDEF\n"` with
`max = 8` gives `0123456`, `789ABCD`, `EF`). This is a legitimate design but dangerous for protocols; the header comment only says
"one line". The chapter and `net/tcp_protocol` show it.

### 9. `conn.Connection.readLine` cannot tell a time out from the end of the connection

Both return `-1`, and `isOpen()` stays `true` after either. To tell them apart one must call `net.waitReadable(c->handle(), ms)` before
reading. Documented in the chapter.

### 10. `http`: things that are easy to trip over (all are documented in the chapter)

* `http.serve(port, ...)` listens on a port you name and never tells you which port the system picked; a loopback sample has to
  copy the 8-line accept loop (the chapter does).
* `http.respond` / `respondBytes` cannot add headers (`Location`, `Cache-Control`, `WWW-Authenticate` need a hand-written response).
* `readRequest` reads a body only with `Content-Length`; a chunked request body is silently not read.
* `readResponse` does not know about `HEAD`, `204` or `304`: it reads `Content-Length` bytes or until the connection closes.
* A request costs about 6 KB of heap that is never freed (measured with `__heap_pos`: 6256 bytes on the server side per request,
  14.6 KB for client + server): `http.serve(..., 0)` grows for ever. The chapter says so.
* `Response.header(name)` / `Request.header(name)` return a fresh copy every call (`strdup`), so the heap grows with every call too.

### 11. Tooling: `tools/samples.py` cannot compare output that contains `\r`

`samples.py` reads the recorded `.out` in text mode (universal newlines turns `\r\n` into `\n`) but compares it with the bytes the
program printed, so a sample that prints a carriage return can never pass. `http.basicAuth` returns a line that ends in `\r\n`, which
is how I found it. The samples avoid printing `\r`. A fix in `samples.py` is to open the `.out` with `newline=""`.

## (b) Places where the reference documentation is wrong or incomplete

| File | Claim | What really happens |
|---|---|---|
| `docs/LANGUAGE.md` 12a (after the `net` table) | "calls block (use `setTimeout`, there is no `select`)" | The table above it documents `net.poll`, `waitReadable`, `waitWritable`, `connectTimeout`. Only the sentence is out of date. There is still no non-blocking mode switch. |
| `lib/tls.a` header comment | `tls.Stream* s = tls.accept(clientFd, cfg);` | `tls.accept(cfg)` returns a `tls.Tls*` session; the blocking server call is `tls.acceptStream(fd, cfg)` (returns a `tls.Stream*`); the socket shortcut is `tls.wrapServer(fd, cfg)`. |
| `docs/LANGUAGE.md` 12 ("Strings and characters") | lists `strUpper(s)`, `strLower(s)` next to functions that return strings | They are `void` and change the string in place (see bug 1). |
| `lib/netif.a` header | does not say that `routeCount()`, `defaultGateway()`, `arpLookup()` ... refresh from the system and replace what `parse*` loaded | see bug 3; also the 512 socket limit (bug 2). |
| `lib/websocket.a` header | "`ws->receive(buf, 1024, &op)`; n < 0: the connection was closed" | Correct, but it should say that a message that fills the buffer has no terminating zero, and that `ws->closeCode` holds the code of the peer's close frame. |
| `docs/LANGUAGE.md` 12a | `http.serve(8080, hello, 100)` shown as the way to run a server | Works, but nothing says that the port cannot be 0 in practice (the caller can never learn the port). |
| `lib/netaddr.a` | `serviceName` "= `"https"`" | Returns `null` for ports that are not in its table of about 40 services (the header comment of the function says so, LANGUAGE.md 12e does not). |

## (c) Modules or features I could not cover fully, and why

* **`rawnet`**: only a compile-only sample (`net/rawnet_capture`). Opening a packet socket needs root or `CAP_NET_RAW` and a real
  interface; the output would depend on the machine. (I did run the sandbox as root and did not try to capture, so the code path
  `rawnet.open("lo")` is **not verified** by me; `tests/t83_netutil.a` covers it.)
* **`netutil.ping` / `ntpTime`**: compile-only (`net/util_ping`): they need a network. The packet builders (`wolPacket`,
  `ntpBuildRequest`, `ntpParse`, `ntpStart` / `ntpFinish`) are run against fake peers.
* **Real DNS** (`dns.query` against a real server, `dns.reverse`, `net.resolve` of a real name): compile-only
  (`net/dns_lookup`, `net/internet_client`). The message encoding and decoding, `dns.query` and `net.resolve` against a DNS server of
  our own are run.
* **`netif`** live data (ARP cache, routes, gateway, DNS servers): compile-only `net/netif_live`; the parsers are run with fixed
  text, the loopback interface and its packet counter are run.
* **UDP broadcast and multicast**: compile-only (`net/udp_broadcast`); they depend on the network the computer is on.
* **`http.serve` and `http.serveTls` / `serveStaticTls`**: compile-only (`http/serve_forever`, `http/https_server`) because they need a
  fixed port. I started both by hand once, on ports 8080 and 8443, and fetched with `curl` (and `curl --cacert` with a certificate made by
  the `openssl` command from the chapter); that is **not** part of the automated samples.
* **`https://` against the Internet** (`http.get("https://example.org/")`) and the **system trust store**: compile-only
  (`http/https_client`). Not run: the sandbox has no direct Internet. The TLS handshake itself is run over loopback with a test
  certificate (`tls_loopback`, `tls_inmemory`, `tls_trust`, `https_loopback`, `wss_by_hand`, `conn_tls`).
* **TLS interoperability with other implementations** is not tested by the samples. By hand I checked: the A https server against
  `curl`; the A client against `openssl s_server -tls1_3` (works) and `-tls1_2` (fails with `the peer sent alert 70`).
* **TLS 1.3 features that the documentation lists as unsupported** (resumption, 0-RTT, client certificates, ALPN, revocation checks,
  HelloRetryRequest, TLS 1.2): taken from `docs/TLS.md`; only "TLS 1.2 fails" was tried.
* **Threads as the "other side"** of a loopback sample: not used, because `thread.spawn` on Windows runs the function in the calling
  thread (a server in a thread would hang there) and A's allocator is not thread safe. The samples use `fork`
  (`// book: linux-only`, 17 of them) or the single-process backlog trick. They compile for the Linux targets only.
* **IPv6 sockets**: not supported by `net` (parsing and printing of IPv6 addresses works); not covered beyond that.
* **Windows and Android behaviour**: nothing was run there. The samples that do not use `fork` compile for all 8 targets
  (`samples.py --targets`); whether they behave identically on Windows is not verified (for example `listenOn` sets `SO_REUSEADDR`
  only on Linux).
* **`examples/`** programs (`chat_server`, `httpsd`, `ws_echo`, `dnslookup`, `ping`, `netinfo`, `packets`, `arping`, `http_get`,
  `http_server`, `net_client`, `net_server`) are referenced by name in the chapters but I did not run them.

## Other remarks

* The number of samples is 66 (39 in `net`, 27 in `http`). 9 are compile-only (`udp_broadcast`, `internet_client`, `dns_lookup`,
  `netif_live`, `util_ping`, `rawnet_capture`, `serve_forever`, `https_client`, `https_server`), 17 are `linux-only` (they use `fork`),
  the other 40 run everywhere the compiler targets. Seven of the `http` samples are directories with a helper module `testcert.a`
  (a throw-away EC P-256 certificate for `localhost`, valid 2020-01-01 to 2100-01-01, generated with Python's `cryptography` package;
  the key is public and the file says so). The build shows `main.a` of a directory sample; the helper is described in the chapter text
  only.
* `samples.py` runs 3 samples at a time. I ran the two groups 8 times in parallel, three rounds (24 x 66 runs) after fixing
  `netif_loopback`: no failures. Before that fix the socket-table dependency (bug 2) failed intermittently.
* A has no two-dimensional arrays (`char said[2][64];` is `expected ';'`); I used `char* said[2]` with `alloc`. Not documented in
  `LANGUAGE.md`'s section on arrays.
