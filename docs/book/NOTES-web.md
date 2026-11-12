# Notes from the web services chapter (`42-web-services.md`, and the edits to `41-http-websocket-tls.md`)

Compiler: `build/ac` of this worktree (the branch with the merged `ws-net1` work: `websocket`, `wshub`, `sse`, `httpx`, `jsonrpc`).
Everything below was run unless it says "not run". The reproductions are short programs; each one was compiled and run here.

## (0) Status of the older findings about `websocket` (docs/book/FINDINGS.md, section "Library: networking")

| Older finding | Now | Evidence |
|---|---|---|
| `websocket` takes the handshake key and the masks from an unseeded `rand()` (same on every run) | **fixed**: both come from the operating system's random generator (`secure`), a fresh mask for every frame | run below |
| `websocket.receive` leaves no terminating zero when a message fills the buffer | **fixed for the new API, still true for the old call**: `Message.data` (from `receiveMessage` / `takeMessage`) always has a 0 byte after the data; `receive(buf, max, &op)` still writes the zero only when `n < max` | run below, and sample `web/ws_messages` |
| `websocket` allocates whatever frame length the peer announces | **fixed**: `maxFrame` / `maxMessage` (16 MiB each by default) are checked from the header, 1009 is the answer, a message buffer grows with the data that really arrived | run below |
| `http.Request.query` holds 1,024 bytes, so the documented `strcpy(q->query, q->body)` overflows | **still true** for the `http` module (`lib/http.a` was not touched by the merge). `httpx.Request.query` is a heap string; `httpx` limits the request target instead (2048 bytes in all, the path under 1099, else 414) | run below |
| "the strict wss / UTF-8 / permessage-deflate WebSocket, wshub, sse, httpx and jsonrpc are not on the branch yet" | obsolete: they are on the branch; chapter 42 describes them and chapter 41 was corrected | (the FINDINGS.md rows are for the coordinator to update: I may not edit that file) |

```c
// 1. key and masks: three runs of this program print three different keys; two objects send "hello" with different masks
import websocket; import conn; import encoding;
int main() {
    conn.Listener* l = new conn.Listener(0);
    conn.Connection* c = conn.open("127.0.0.1", l->port(), 1000);
    char key[40];
    websocket.clientSend(c, "localhost", l->port(), "/", key);
    println(key);                                          // rBkKsnoaZpBBI3xBPMyMUQ==, h/sykCqAtsMZrM4whaVb6w==, KYgr4Dr0cFtEc68ukJRVoA==
    websocket.WebSocket* a = websocket.create(null, true);
    a->sendText("hello");
    println(encoding.hexEncode(a->outData(), a->outPending()));     // 81 85 <a different 4 byte mask every time> ...
    return 0;
}
```

```c
// 2. receive() without a terminating zero, and a frame that announces 1 TiB
import websocket; import encoding;
int main() {
    websocket.WebSocket* s = websocket.create(null, false);
    websocket.WebSocket* c = websocket.create(null, true);
    s->sendText("12345678");
    c->feed(s->outData(), s->outPending());
    char buf[16];
    memset(&buf[0], 'X', 16);
    int op;
    int n = c->receive(&buf[0], 8, &op);
    printf("%d bytes, buf[8] = %d\n", n, buf[8]);           // 8 bytes, buf[8] = 88: still 'X', no terminating zero
    websocket.WebSocket* srv = websocket.create(null, false);
    char bytes[16];
    int k = encoding.hexDecode("82ff000001000000000000000000", &bytes[0]);   // binary, masked, length 2^40
    int h0 = __heap_pos;
    int r = srv->feed(&bytes[0], k);
    printf("feed %d, closed %d, heap +%d\n", r, srv->closed, __heap_pos - h0);   // feed -1, closed 1, heap +528 (the close frame)
    return 0;
}
```

```c
// 3. http.Request.query (module http): the neighbour of query in memory is overwritten
import http;
int main() {
    http.Request* q = new http.Request();
    strcpy(&q->version[0], "HTTP/1.1");
    char* big = alloc(1100);
    memset(big, 'x', 1030);
    strcpy(&q->query[0], big);               // what the form handler of chapter 41 would do with a 1030 byte body
    printf("version: \"%s\"\n", &q->version[0]);   // version: "xxxxxx"
    return 0;
}
```

## (a) Compiler and library bugs, and sharp edges

### 1. `wshub`: `hub->close(c, ...)` on an event stream in the same turn as `sendEvent` delivers nothing, not even the response head

`Hub.close` marks an event stream client dead (`c->dead = true`) and the hub drops its queue. If the events were queued in the same
callback (`onOpen`), the client receives **no answer at all** ("no HTTP answer"; `sse.Client` retries and gives up). Closing a few turns
later works. `docs/NET.md` and the header only say "an event stream is simply ended".

```c
import wshub; import httpx; import sse; import net;
wshub.Hub* hub;
int serve() { hub->poll(0); return 0; }
int onHttp(wshub.Hub* h, wshub.Client* c, httpx.Request* req, httpx.Response* res) { sse.startResponse(res); return 1; }
int onOpen(wshub.Hub* h, wshub.Client* c) {
    h->sendEvent(c, "hello", "world", "1");
    h->close(c, 1000, null);                 // expected: the event arrives, then the stream ends
    return 0;
}
int main() {
    hub = new wshub.Hub();  hub->onHttp = onHttp;  hub->onOpen = onOpen;
    hub->listenOn("127.0.0.1", 0, null);  net.setIdleHook(serve);
    char url[80];  format(&url[0], 80, "http://127.0.0.1:%d/", hub->port);
    sse.Client* c = sse.connect(&url[0]);  c->maxRetries = 0;
    sse.Event* e = c->next(1000);
    printf("event: %s, status %d, error: %s\n", e == null ? "none" : e->data, c->status, sse.error());
}   // prints: event: none, status 0, error: no HTTP answer
```

The chapter warns about it and the sample `web/sse_stream` closes the streams from the main loop.

### 2. `net.accept` on a non-blocking listener waits for ever when an idle hook is set (a trap inside the hook)

With a hook installed `net.accept(server)` first does `rawWaitReadable(server, -1)` and only then `acceptSome`, whatever the mode of the
listener. In a normal program that is the point of the hook. **Inside the hook** (where the sample's server lives) the wait cannot be
served any more (the hook is not re-entrant), so the first call that finds no client pending hangs the program. The tests avoid it by
using `listener->accept(0)` or `acceptSome`. My first version of `web/ws_echo` worked by luck (a client was always pending) and
`web/rpc_transports` hung. `docs/NET.md` ("Waiting without threads") does not warn about it; `net.acceptSome` has the right comment.

```c
import net;
int listener;  int calls = 0;
int hook() { calls++; net.accept(listener); return 0; }    // expected: a negative number at once when nobody is pending
int main() {
    listener = net.listenOn("127.0.0.1", 0, 4);
    net.setNonBlocking(listener, true);
    net.setIdleHook(hook);
    int c = net.connect("127.0.0.1", net.localPort(listener));    // one connection is pending: the first hook call accepts it
    char buf[10];  net.setTimeout(c, 500);
    net.recv(c, &buf[0], 10);                                      // the second hook call never returns
    printf("calls %d\n", calls);                                   // never printed (timeout 124 under `timeout 5`)
}
```

### 3. `jsonrpc.Client.dispose()` (and `close()`) close a connection that was given to `connectStream`, although the docs say it "stays yours"

`lib/jsonrpc.a` ("A connection that was given to connectStream stays yours") and `docs/NET.md` ("a connection that you gave to
`connectStream` stays yours") suggest the socket is left alone. `close()` calls `link->close()` and `dispose()` calls `close()`. What
stays yours is the `conn.Connection` **object** (it is not freed). Chapter 42 says that.

```c
import jsonrpc; import conn; import net;
int main() {
    int l = net.listenOn("127.0.0.1", 0, 4);
    conn.Connection* c = conn.open("127.0.0.1", net.localPort(l), 1000);
    jsonrpc.Client* cl = jsonrpc.connectStream(c, jsonrpc.FRAME_LINES);
    printf("%d\n", c->isOpen());      // 1
    cl->dispose();
    printf("%d\n", c->isOpen());      // 0
    return 0;
}
```

### 4. `sse.Client.reconnects` counts the first connection too

The comment says "how many times the stream was opened again"; after the first successful connection it is already 1.

```c
// (a hub with an event stream on / as in repro 1, but without the close in onOpen)
sse.Client* c = sse.connect(&url[0]);
sse.Event* e = c->next(1000);
printf("reconnects = %d\n", c->reconnects);      // 1, before any reconnect
```

### 5. Smaller things

* **Listening on every interface by default.** `hub->listen(port)`, `hub->listenTls(port, cfg)` and `conn.Listener(port)` bind `0.0.0.0` (checked in
  `/proc/net/tcp`: `00000000:<port>`). The comment in `lib/wshub.a` says so; `docs/NET.md` shows `hub->listen(8080)` without a word, and
  `lib/conn.a` has no word either. `hub->listenOn("127.0.0.1", port, cfg)` and `net.listenOn` are the local-only forms; **`conn.Listener` has no
  host parameter at all**, so a sample that must stay on loopback cannot use it (my samples use `net.listenOn` + `conn.create`).
* **A new limit, undocumented:** `net.secureAttach` has 512 slots (it had 32 and dropped the 33rd silently); now `tls.wrap` / `tls.wrapServer` fail with
  "too many secure sockets at the same time". It applies to `https://` and `wss://` clients and `websocket.acceptTls`, not to the TLS clients of
  a hub. From the source; not tried with 513 connections.
* **`httpx.statusText(418)` is "Unknown"** (RFC 9110 lists 418 as unused: fine, but `res->error(418)` then has the body `Unknown`).
* **`char* long = ...` gives "expected a variable name"**: `long` is a reserved word; the message does not say so. (Compiler diagnostic; hit it once.)
* **`hub.stats` / `/healthz` count the connection that asks**: `"clients":1` in the answer to the very first request. Not a bug; surprising.
* **Middleware of an `httpx.Router` in a hub runs only for the router's routes**, not for `/healthz`, `onHttp` or static files (and a 404 of the router that falls through
  to the files has lost its middleware headers). Documented implicitly ("hub->router ... 404 from it falls through").
* **Samples from chapter 41 take a second each now**: `ws->close(code)` waits up to one second for the answer (it was 200 ms), and the samples
  `http/ws_ping_close` and `http/ws_handshake` close without a server running. They still pass (well under the limit); I could not touch them.

## (b) Places where the reference documentation is wrong or incomplete

| File | Claim | What really happens |
|---|---|---|
| `docs/NET.md` ("Waiting without threads"), `lib/net.a` header of `setIdleHook` | every blocking wait calls the hook; nothing about `accept` inside the hook | `net.accept` waits for readability even on a non-blocking listener, which hangs inside the hook; use `acceptSome` or `waitReadable(h, 0)` first (bug 2) |
| `lib/jsonrpc.a` header and `docs/NET.md` (Memory table) | a connection given to `connectStream` "stays yours" | `close()` / `dispose()` close it; only the `Connection` object is yours to free (bug 3) |
| `lib/sse.a` `Client.reconnects` | "opened again" | counts the first connection too (bug 4) |
| `lib/httpx.a` header comment (line 21) | "`httpx.cors`, `httpx.checkBasic / checkBearer`" | the names are `httpx.Cors` with `corsMiddleware`, `checkBasic` and `bearerToken`; `cors` and `checkBearer` do not exist |
| `docs/NET.md` httpx section | limits of the request parser: `maxHead`, `maxHeaders`, `maxBody` | there are two more that nothing mentions: the request target may be 2048 bytes in all, and the path 1098 (414 for more). Tried: path of 1098 bytes 200, 1099 bytes 414; target of 2048 bytes 200, 2049 bytes 414 |
| `docs/NET.md` hub section | "an event stream is simply ended" (header) | queued bytes are dropped, also the response head (bug 1) |
| `docs/NET.md` "Defaults that are made for a trusted network" | lists timeouts and sizes | does not say that `listen` binds every interface and that `conn.Listener` cannot be bound to one |
| `docs/NET.md` (websocket) | describes `receiveMessage` | does not mention the older `receive(buf, max, &op)` still exists with its two quirks (cuts a longer message; no terminating zero when the message fills the buffer) |
| `lib/websocket.a` (comment of `closeWith`) vs the chapter text before my edit | `close(code)` "waits up to 200 ms" (old chapter 41) | `closeWith` / `close` wait up to **1 second** in blocking mode (`waitClose(1000)`); chapter 41 corrected |
| `docs/book/FINDINGS.md` | the rows quoted at the top of this file | see table (0); for the coordinator |

Statements of chapter 41 that the new library made wrong, all corrected: the key and masks from `rand()` (and the advice to call `srand`); the
receiver "allocates whatever length a frame announces"; "text frames are not checked for valid UTF-8, no extensions, no sub-protocol
negotiation"; "`close(code)` waits 200 ms"; "`websocket.connect` accepts `ws://` only" (three places: a note, the section on wss by hand, the summary);
"a server in another process" for the handshake sample (now also "from `net.setIdleHook`"). Cross-links to chapter 42 were added (intro, the
which-module table, the HTTP limits, the WebSocket section, Summary, Where next). `http` statements (no keep-alive, no cookies, 6 KB per request,
HEAD, `query[1024]`) are still true: `lib/http.a` did not change, and the 27 samples of the `http` group still pass.

## (c) What I could not cover, and why

* **Windows, AOS, Android, riscv64 and loongarch64 runs.** The 25 samples compile for all nine targets (`samples.py --targets web`), and run correctly
  under `qemu-user` for **linux-arm64** (the run the assignment asks for). Nothing was run on Windows or AOS. The idle hook is what makes the samples
  portable; I did not test `thread` there.
* **Interoperability** with other implementations (`tests/net.sh`: python `websockets`, curl, openssl) and with a real browser: not run (no network
  tools set up, and not allowed to install anything). Everything in the chapter is verified between these modules and against hand-made bytes.
* **Features described in the chapter but not run in a sample:** `Cors` / `corsMiddleware`, `httpx.Client.stream`, `requestChunked`, `serveStream` with
  `FRAME_LENGTH`, the plain-`http` event stream helpers (`sse.begin`, `sse.send`, `sse.comment`: described, covered by `tests/t367_sse_http.a`),
  `websocket.acceptTls` / `acceptTlsWith` (blocking wss server), `readUpgrade` + `completeUpgrade` / `rejectUpgrade` (only through the hub's `onUpgrade`),
  `ServerOptions.requireOrigin` / `requireProtocol`, the parameters of the deflate negotiation (`tests/t345`), `maxQueued` eviction of a slow reader
  (depends on socket buffer sizes, so not deterministic), `pingIntervalMs` / `pongTimeoutMs` of a hub (the keepalive sample uses the plain `websocket`
  with a fake clock), `hub->shutdown`, `retryAll`, `Options.headers` / `authorization`. I checked `idleTimeoutMs`, `shutdown`, `retries`, `headerTimeoutMs`,
  a stale kept-alive connection, the 100 request batch limit and the `closeWith` code ranges in throw-away programs (all as documented), not in samples.
* **Speed and memory claims of `docs/NET.md`** (150 ms per TLS handshake, constant memory, compression ratios of 30 to 55 percent): quoted from the
  document and marked as such in the chapter; not measured. (`web/wss_loopback` does one failing and two complete handshakes in about 0.15 s on this
  machine, client and server both in the process.)
* **The 512 secure sockets limit**, see above.
* `docs/NET.md` itself is not part of `chapters.txt`. The chapter cites it as a file of the repository. If the coordinator adds it as a reference
  chapter, the three mentions can become links.

## Practical notes for the coordinator

* Add `chapter src/42-web-services.md` after the line of `src/41-http-websocket-tls.md` in `chapters.txt`. The chapter's slug is `web-services`
  (`#chap-web-services`, which chapter 41 links to). Until the line is added, `build.py --lint` does not see the chapter; I linted a private copy of
  the book tree with the line added: 0 errors, 0 warnings for chapters 41 and 42 (the 12 warnings that remain come from `31-collections-and-algorithms.md`
  and its link to the chapter of another contributor).
* The group `web` has 25 samples, none compile-only, all with recorded output. Total run time of the group on this machine: about 1.5 s with three jobs.
* `samples/web/wss_loopback/testcert.a` is a copy of the throw-away certificate module of `samples/http/*/testcert.a`; the book listing of the sample
  shows it after `main.a` (about 2 KB of PEM text).
