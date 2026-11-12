# WebSocket, server-sent events, an HTTP toolkit and JSON-RPC

[The previous chapter](#chap-http-websocket-tls) showed the basics: an HTTP client and server, a WebSocket handshake, TLS. This chapter
is about five modules for programs that talk to browsers and to other services. They are written in A, run the same on every
target, and sit on `net`, `conn`, `tls`, `zlib` and `json`:

* `websocket`: WebSocket (RFC 6455) and compression (RFC 7692), complete and strict, `ws://` and `wss://`;
* `wshub`: a server for many WebSocket clients in one thread, with rooms, an HTTP side and event streams;
* `sse`: server-sent events, the one-way stream of text that browsers call `EventSource`;
* `httpx`: an HTTP client (redirects, cookies, retries, downloads) and the pieces of a server (router, middleware, files, multipart);
* `jsonrpc`: JSON-RPC 2.0 over a stream, HTTP or WebSocket.

In this chapter:

* a WebSocket echo server and client, text and binary messages, close codes and what a peer sees;
* fragments, streaming and compression, and a peer that breaks the rules;
* `wss://` over loopback, a hub with rooms, its HTTP side, access control and limits;
* an event stream with a client that reconnects;
* an HTTP client and a router, tested against each other;
* JSON-RPC over three transports;
* waiting without threads, and a list of what these modules do **not** do.

## Which module do I use?

| I want to ... | Use |
|---|---|
| talk to one WebSocket peer, `ws://` or `wss://` | `websocket.connect`, `websocket.accept` |
| serve many WebSocket clients from one thread, with rooms | `wshub` |
| push events from a server to browsers (one way) | `sse` with a `wshub`, or `sse.begin` / `sse.send` in an `http` handler |
| read an event stream | `sse.connect` |
| call a web API with cookies, redirect rules, retries, big downloads | `httpx.Client` |
| answer HTTP requests with routes, middleware, static files | `httpx.Router` inside a `wshub` |
| call functions in another program, with JSON | `jsonrpc` |
| serve a client and its server in one thread | `net.setIdleHook`, `conn.Poller`, `wshub.poll` |

The older `http` module of [the previous chapter](#chap-http-websocket-tls) still works and is the shortest way to fetch one page.
`httpx` is what you reach for when you need more than that.

::: note

**How the samples run.** Every sample in this chapter is one program with one thread: the client and its server live in the same
process, so that a sample is self-contained and needs no second terminal. The trick is `net.setIdleHook`: while a blocking call of the
client waits for the network, `net` calls a function of yours every few milliseconds, and that function serves the other end. The
section [Waiting without threads](#waiting-without-threads) explains it; `ws_echo` below is the first example. In a real program the
server is a separate program and you simply run it (`hub->run()`). All servers here listen on `127.0.0.1` with port `0`, so the system
picks a free port.

:::

## WebSocket basics

### An echo server and a client

A WebSocket starts as an HTTP request that asks to *upgrade* the connection; afterwards both sides send **messages** whenever they want.
The client calls `websocket.connect(url)`. The server accepts a connection from a listening socket and calls `websocket.accept`.
Both get a `websocket.WebSocket`.

{{sample web/ws_echo}}

**What to notice.**

* `websocket.connect` returns `null` when it fails; `websocket.error()` says why and `websocket.status()` is the HTTP status of the
  answer (101 means the upgrade worked).
* `receiveMessage()` waits for one **whole** message and gives you a `websocket.Message`: `isText()`, `data`, `length`. `data` always has
  a 0 byte after the data, so a text message is a string. Free a message with `dispose()`.
* The server half runs inside `serve()`. It is non-blocking: `setNonBlocking(true)` and `pump()` read what has arrived and never
  wait, `takeMessage()` hands out what `pump()` collected, and `acceptSome` does not wait for a client.
* `closeWith(1000, "done")` is the closing handshake: it sends a close frame and waits (at most one second) for the answer. After it,
  `closed` is true and `closeCode` is the code of the **answer**.
* `dispose()` frees the object and closes the socket. Call it when you are done with a connection.

Everything a client can say about itself goes into `websocket.Options` for `websocket.connectWith(url, options)`:

| Field | Meaning |
|---|---|
| `origin`, `cookie`, `authorization` | the headers of that name (a value with CR, LF or another control character is refused: no header injection) |
| `protocols` | the subprotocols you offer, `"chat, superchat"`; after the handshake `ws->protocol` is the one the server chose |
| `headers` | more request lines, `"X-One: 1\r\nX-Two: 2\r\n"` |
| `deflate` | offer compression (see below) |
| `verify` | `wss://`: check the server certificate (default: on) |
| `maxMessage`, `maxFrame` | largest message and frame you accept, default 16 MiB each |
| `connectTimeoutMs`, `handshakeTimeoutMs` | 5000 and 10000 ms |

### Text and binary messages

A message is **text** (it must be UTF-8) or **binary** (anything). The module checks text on the way in and on the way out. A
`WebSocket` is also a plain state machine: `websocket.create(null, isClient)` makes one without a socket, `feed` takes the bytes that
arrived, `outData` / `outPending` / `outConsumed` are the bytes to send. That makes the frame sizes visible, so this sample uses two
objects and carries the bytes from one to the other.

{{sample web/ws_messages}}

**What to notice.**

* `sendText` with an invalid UTF-8 byte returns `false` and sends **nothing**. An empty message is a message.
* A frame has a header of 2 bytes (payload up to 125), 4 bytes (up to 65535) or 10 bytes (more). A **client** adds 4 bytes of mask.
  So 5 bytes cost 11 bytes from a client and 7 from a server, and 70000 bytes cost 70014 and 70010.
* The older `receive(buf, max, &opcode)` still works, but it cuts a message that is longer than `max`, and a message that fills the buffer
  exactly gets **no terminating zero**: see the `#` in the last line. `receiveMessage` has neither problem.
* The `Sec-WebSocket-Key` of the handshake and every mask come from the operating system's random generator, so there is nothing to seed.

## Closing, and what each side sees

### Close codes

A connection ends with a **close frame**: a status code of two bytes and, optionally, a reason of up to 123 bytes of UTF-8. The other
side answers with its own close frame, and then the TCP connection is closed. Codes are numbers:

| Code | Name | Meaning |
|---|---|---|
| 1000 | `CLOSE_NORMAL` | done |
| 1001 | `CLOSE_GOING_AWAY` | a server shutting down, a page that was left; a hub uses it for a client that was silent too long |
| 1002 | `CLOSE_PROTOCOL` | the peer broke the protocol |
| 1003 | `CLOSE_UNSUPPORTED` | data of a kind the peer cannot take |
| 1005 | `CLOSE_NO_STATUS` | **never sent**: what `closeCode` says when a close frame had no code |
| 1006 | `CLOSE_ABNORMAL` | **never sent**: what `closeCode` says when the connection ended without a close frame |
| 1007 | `CLOSE_BAD_DATA` | text that is not UTF-8 |
| 1008 | `CLOSE_POLICY` | a hub uses it for a client that was cut off because its send queue was full |
| 1009 | `CLOSE_TOO_BIG` | a message or frame over the limit |
| 1010 to 1014 | | extension missing, internal error (1011: a keepalive ping was not answered), service restart, try later, bad gateway |
| 3000 to 3999 | | for libraries and frameworks |
| 4000 to 4999 | | **yours**: use them for application meanings such as "kicked" |

`closeWith(code, reason)` accepts 1000 to 1003, 1007 to 1014 and 3000 to 4999 and returns `false` for anything else.

{{sample web/ws_close}}

**What to notice.**

* The side that starts the close sees the **answer**: the client's `closeReason` is empty because an answer carries only the code. The
  server, which received the first frame, has both the code and the reason (`"all done"`).
* When the server closes, the client's `receiveMessage` returns `null`; `closeCode` and `closeReason` say why. A program that reads
  until `null` needs nothing else.
* A connection that is cut without a close frame gets the code **1006** from the library, and the reason is empty. Treat 1006 as
  "something broke", not as something the peer said.
* `closeWith` refuses 1006, 999, 5000 and a reason of 124 bytes, and sends nothing. After a close frame has been sent, `sendText`
  returns `false`.
* In blocking mode `closeWith` waits for the answer for up to **one second**. In non-blocking mode and in a hub it only queues the
  frame: keep reading until `closed`.

### A peer that breaks the rules

The module is strict. When a peer sends something RFC 6455 forbids, the module sends a close frame with the right code and ends the
connection. `ws->failed` is true and `failReason` says what was wrong. The sample feeds hand-made bytes to a server-side object, as if
a hostile client had sent them:

{{sample web/ws_strict}}

**What to notice.**

* **1002** is a broken protocol: an unmasked frame from a client (and a masked one from a server), reserved bits, unknown opcodes, control
  frames that are fragmented or longer than 125 bytes, a length that is not in its shortest form, a continuation with nothing to
  continue, bad close frames.
* **1007** is invalid text. The check runs **while the bytes arrive**, so a bad byte ends the connection before the message is
  complete. Overlong forms (`c1 61` is an overlong "a"), surrogates and values over U+10FFFF are refused too, also when the text is split
  over several frames.
* **1009** is a size limit. A frame that announces a gigantic length (the last line announces 1 TiB) is refused from its header:
  nothing is allocated for it.
* A keepalive that is not answered gives 1011 (see [Keepalive](#keepalive) below).

## Messages in pieces, and compression

### Fragments and streaming

A big message does not have to be in memory in one piece. You can send it in **fragments**, and receive it **piece by piece**. A
frame with FIN clear says "more follows"; control frames such as pings may be sent in between.

{{sample web/ws_fragments}}

**What to notice.**

* `beginMessage`, any number of `sendFragment`, then `endMessage`: each piece goes out as it comes, and a ping can be sent in between.
  `endMessage` sends an **empty** last frame with FIN set.
* `setFragmentSize(4)` cuts every message into frames of at most 4 bytes (the sample uses 4 to keep the output short).
* The receiver of a fragmented message gets **one** message with `takeMessage` (the pieces are joined).
* `setStreamHandler(f)` hands you each piece (`flags`: 1 first, 2 last, 0 in between) and collects nothing: `takeMessage` returns
  `null`. The last piece may be empty, as here. Use it for messages that are bigger than you want to hold.
* With compression switched on (next section) the pieces are collected and sent compressed by `endMessage`.
* Limits: `maxMessage` and `maxFrame` are 16 MiB by default; a message is built in a buffer that grows with the data. `maxOutBuffer` limits
  the bytes queued for sending; a send that would pass it returns `false` and sets `overflowed`.

### permessage-deflate

Text compresses well. **permessage-deflate** (RFC 7692) is an extension that the client *offers* in the handshake and the server
*accepts*; then every message of 64 bytes or more is deflated. You turn it on with `Options.deflate` (client) and
`ServerOptions.deflate` (server); `ws->deflate` says whether it was agreed.

{{sample web/ws_deflate}}

**What to notice.**

* The same 2150 bytes of JSON-like text cost 2158 bytes on the wire without compression and **377** with it. A short text (5 bytes) is
  sent as it is: `minCompress` is 64 bytes.
* Compression only happens if **both** sides agree. A server without `deflate` ignores the offer, and nothing breaks.
* The limit that matters is on the **inflated** size. The last line is a decompression bomb: 400000 equal bytes shrink to 2540 bytes,
  but the server's `maxMessage` is 100000, so it ends the connection with **1009** while it is still inflating.
* Our compressor writes fixed Huffman blocks and never keeps its window between messages, so it compresses a little less than zlib
  (`docs/NET.md` measured 30 to 55 percent of the original size on text of 13 to 126 KB, against 25 to 44 percent for zlib at level 6).
  Every peer accepts it. When **receiving**, everything in the RFC is supported, including context takeover.

## A secure WebSocket: wss://

`websocket.connect("wss://...")` does the TLS handshake first (TLS 1.3, [the previous chapter](#chap-http-websocket-tls)) and then the
WebSocket handshake on the encrypted connection. The server certificate is checked like for `https://`: it must lead to a trusted
root, be valid today and match the host name (an IP address needs an IP entry in the certificate). The sample uses the throw-away
certificate of the previous chapter, in the module `testcert` that is listed after the program, and a `wshub` as the server.

{{sample web/wss_loopback}}

**What to notice.**

* Without a trusted certificate `connect` returns `null` and `websocket.error()` says why (here: no roots at all, because the sample
  called `x509.clearRoots()`). `x509.addRootPem(text)` trusts a certificate of your own.
* `Options.verify = false` encrypts but does not check who is at the other end, as in the previous chapter. `websocket.setVerify(false)`
  changes the default for the whole program. Neither is a habit to start.
* The hub does the TLS handshake as part of its poll loop: `hub->listenOn(host, port, tls.loadConfig(cert, key))` or
  `hub->listenTls(port, config)`. The refused first client shows up in `stats->tlsFailures`.
* For a single connection without a hub: `websocket.acceptTls(connection, config, path, max)` (blocking). A `wss` socket cannot be put
  into non-blocking mode (`setNonBlocking` returns `false`): use a hub for many connections.
* A TLS handshake costs a server about 150 ms of processor time (`docs/NET.md`, x86-64, not measured for this chapter), and a hub is
  one thread. For many new `wss://` connections per second, put a TLS terminating proxy in front.

## wshub: many clients, one thread

One thread per client does not scale, and a blocking `receive` does not mix with several connections. A `wshub.Hub` is a loop built on
`net.poll`: it accepts connections, reads, writes and times out all of them without ever waiting for one client, and calls **your
functions** when something happens. Clients are WebSockets, event streams (below) and plain HTTP requests, all on one port.

You give the hub callbacks; every argument is a number or a pointer:

| Callback | Called when |
|---|---|
| `onOpen(hub, client)` | a WebSocket (or event stream) is ready |
| `onMessage(hub, client, data, n, isText)` | a message arrived; `data` is valid **during the call** and followed by a 0 byte |
| `onClose(hub, client, code)` | the client is gone; `code` is its close code (1006 for a dropped connection) |
| `onHttp(hub, client, request, response)` | a plain HTTP request; return 1 if you answered |
| `onUpgrade(hub, client, info)` | an upgrade request that passed the Origin check; return 0 to accept or an HTTP status to refuse |

A `Client` has an `id` (never reused while the hub runs), a `path`, and a `user` pointer that is yours. The `Client*` is valid until
`onClose` returns; to find a client later keep its `id` and use `hub->find(id)`, `hub->sendTextTo(id, text)` or `hub->closeId(id, ...)`.

### Rooms and broadcast

A **room** is a named group of clients. `publish(room, data, n, isText, exceptId)` sends a message to every member, except one client
if you give its id. `broadcast` goes to everybody.

{{sample web/hub_rooms}}

**What to notice.**

* `onMessage` copies `data` with `strdup`, because the pointer is only valid during the call.
* `join` creates a room when its first member arrives; a room disappears with its last member; a client leaves its rooms when it closes
  (the last line: bob left, so red and blue each have one member). A client may be in 8 rooms, a name has at most 63 bytes, a hub has
  at most 1000 rooms by default.
* `publish` skipped the sender (`c->id`). `broadcastText` reached every client in every room.
* `hub->listen(port)` listens on **every** network interface; `hub->listenOn("127.0.0.1", port, null)` only on this machine. The samples
  use the second form.
* The clients wait with `receiveMessage()` for messages that must come. A message that must **not** come can only be checked by waiting
  a while (`waitMessage(40)` is what the sample does), which is why "(nothing)" is the one place where time plays a part.

### The HTTP side

Requests that are not WebSocket upgrades go to the hub's HTTP side, in this order: `GET /healthz`, your `onHttp`, the `httpx.Router`
in `hub->router`, the files of `hub->staticDir`, then `404`. Keep-alive, chunked request bodies and `Expect: 100-continue` work, and
files are streamed in 16 KB pieces.

{{sample web/hub_http}}

**What to notice.**

* `/healthz` answers by itself with JSON. Note `"clients":1`: the connection that asks is counted too.
* `onHttp` returned 0 for everything but `/hello`, so the hub went on with the router, then the files. A router that has no route for a
  path answers 404 and the hub falls through to the static files, which is why `/` gives `index.html` and `/nothing` gives 404.
* The middleware `stamp` ran around the two routes and its header is on both. It did **not** run for `/healthz`, `onHttp` or the
  files: middleware belongs to the router.
* `x->req->param("id")` is the `:id` of the pattern, already percent-decoded; `queryValue` reads `?shout=yes`. The next sections
  explain the router.
* A WebSocket client of the same port works at the same time: one hub, two protocols.

### Who may connect

A WebSocket server that browsers can reach has a problem that HTTP servers have too: any web page can open a connection to it. The
browser sends an **`Origin`** header with the page's address, and the server decides. `ServerOptions` (in `hub->wsOptions`, or for
`websocket.acceptWith`) has `origins`, a comma separated allow-list, and `protocols`, the subprotocols the server speaks.
`onUpgrade` gets the request (`info->path`, `info->headerInto("Cookie", ...)`) and can refuse with 401, 403, 404...

{{sample web/hub_upgrade}}

**What to notice.**

* The order of checks: the Origin list first (`another Origin:` never reached `onUpgrade`), then `onUpgrade`. A refusal is a normal HTTP
  answer: `connect` returns `null` and `websocket.status()` has the status.
* `ServerOptions.protocols` lists what the server speaks, best first; the server picks the first one the client also offered
  (`chat`, not the client's own favourite). `ws->protocol` is `""` when nothing was agreed.
* The last line is a trap. An `Origin` check protects **browsers**. A client that sends no `Origin` at all (a script, a command-line
  tool) gets in unless you set `requireOrigin`. The check cannot replace a login.
* An `Origin` header that is empty, or 300 bytes or longer, is refused with 403 whether you have a list or not.
* Every refused upgrade is counted in `stats->rejected`.

### Limits and timeouts

The defaults of a hub are made for a trusted network. Change them for anything that faces strangers:

| Setting | Default | Meaning |
|---|---|---|
| `maxClients` | 1000 (also the highest value) | all connections; more get `503 Service Unavailable` |
| `maxMessage` | 1 MiB | largest WebSocket message, else close code 1009 |
| `maxQueued` | 1 MiB | bytes waiting for **one** client that reads slowly; over it the client is cut off (1008, `stats->evicted`) |
| `maxBody`, `maxHead` | 1 MiB, 16 KiB | HTTP request limits (413, 431) |
| `handshakeTimeoutMs` | 5000 | from accept to a complete request, TLS included |
| `idleTimeoutMs` | **0 (off)** | a WebSocket silent this long is closed with 1001 |
| `pingIntervalMs`, `pongTimeoutMs` | **0 (off)**, 10000 | ping silent clients; close the ones that do not answer (1011) |
| `keepAliveMs`, `closeTimeoutMs`, `sseKeepAliveMs` | 10000, 3000, 15000 | idle HTTP connections, the closing handshake, comment lines on event streams |

{{sample web/hub_limits}}

**What to notice.**

* The third client got `503` before any WebSocket handshake; `stats->rejected` counts it.
* A message over `maxMessage` ends that connection with **1009**; the other clients are not affected.
* With `idleTimeoutMs` at its default, a client that connects and says nothing stays for ever. A thousand such clients lock everybody
  else out with 503. Set `idleTimeoutMs` and `pingIntervalMs` on a server that is reachable from outside.
* `maxQueued` limits **one** client; there is no limit for the hub as a whole, so 1000 slow readers can hold 1000 MiB. Lower
  `maxQueued`, `maxMessage` or `maxClients` to what the machine has.
* `hub->stats` counts connections, messages, bytes, evictions, timeouts and TLS failures. `hub->shutdown(graceMs)` stops listening, sends
  1001 to every WebSocket and waits for the answers.

## Server-sent events

**Server-sent events** (SSE) are the simple cousin of WebSocket: one direction, server to client, plain text over an ordinary HTTP
response that never ends. Browsers read it with `EventSource` and reconnect by themselves, and send `Last-Event-ID` so that the server
can go on where it stopped. Choose SSE when only the server talks (a log, a progress bar, a ticker); choose WebSocket when both do.

### The wire format

An event is a few lines of `field: value`, ended by an empty line. `event:` names it, `data:` is its text (one line per line of text),
`id:` is the id that a reconnecting client sends back, `retry:` is the pause before a reconnect in milliseconds, and a line that starts
with a colon is a comment that keeps the connection alive.

{{sample web/sse_wire}}

**What to notice.**

* `sse.eventText(event, data, id, retryMs)` builds the text of one event. It returns `null` if the event name or the id contains a line
  break: otherwise a client's text could add fields (stream injection).
* The parser takes bytes in **any** pieces (here 5 at a time) and understands LF, CR and CRLF as line ends. A comment gives nothing;
  `event: nodata` followed by an empty line gives nothing either, because an event is only dispatched when it has data.
* An event without a name has the type `message`. The `id` **persists**: the second event has no `id:` line and still reports `1`.
* `retry:` takes digits only. Limits of the parser: 64 KB per line, 1 MB per event, 1024 events waiting.

### A stream and a client that reconnects

In a hub an HTTP handler turns its response into a stream with `sse.startResponse(res)`; the connection then becomes a client of the hub
that is in `onOpen` and `onClose`, can join rooms, and receives `sendText`, `broadcast` and `publish` as events
(`hub->sendEvent(c, name, data, id)` adds a name and an id). The client is `sse.connect(url)`, and `next(ms)` waits for the next event.

In the sample the server sends two events per connection and then "restarts". The client has to find out where it was.

{{sample web/sse_stream}}

**What to notice.**

* After the stream ended, the client came back **by itself** and sent `Last-Event-ID: 2`; the server went on with event 3. The first
  request had no such header.
* **204** means "do not reconnect". After the last event the server answered the third reconnect with 204, and the client gave up
  (`closed` is true). A status other than 200, or a content type other than `text/event-stream`, ends the client for good as well.
* The client waits `retryMs` (the server's `retry:` field replaces it; the default is 3000, the sample uses 20), doubles the pause after
  each failure up to `maxRetryMs`, and gives up after `maxRetries` failures in a row (default 5).
* `c->reconnects` counts every time the stream was opened, the first time included: 3 here.
* **A trap:** `hub->close(c, ...)` on an event stream ends it at once and drops what is still queued for it. If you call it in the same
  callback that queued the events (for example in `onOpen`), the client gets no answer at all, not even the response head. The sample
  closes the streams from the main loop, after the client has read the events.
* On the plain `http` server, a handler can write a stream with `sse.begin(client)`, `sse.send(client, name, data, id)` and
  `sse.comment(client, text)`; `sse.lastEventId(request)` reads the header. That is one blocking handler per stream, so use a hub
  for more than a few clients. `tests/t367_sse_http.a` is a verified program that does it.

## httpx: an HTTP toolkit

The `http` module of the previous chapter does one request per connection and has no cookies, no keep-alive, no retries and no
router. `httpx` is its bigger sibling. It has two halves, and they were written to work together:

| Client (`httpx.Client`) | Server pieces (work on bytes, so any transport can use them) |
|---|---|
| redirects with the rules of the RFC, cookies, keep-alive, retries, time limits, gzip, streaming, resumable downloads, Range, multipart uploads, chunked uploads | `RequestParser`, `Router` with patterns and middleware, `Response`, static files with `ETag` / `Range`, CORS, Basic and Bearer authentication, multipart forms |

The samples use a `wshub` as the server, because it already serves an `httpx.Router`.

### The client

You make a client with `httpx.newClient()` and call `get`, `head`, `del`, `post`, `put`, `patch`, `postForm`, `postJson`,
`postMultipart`, or `request(method, url, headers, body, n)` for the general case. You get a `httpx.Reply`: `status`, `header(name)`,
`body` (followed by a 0 byte), `bodyLen`, `url` (after redirects), `redirects`, `reused`.

{{sample web/httpx_client}}

**What to notice.**

* **No reply** (`null`) and **an error reply** are different things. A 403 or 404 is an answer from the server and arrives as a `Reply`.
  `null` means that no answer came at all (nothing listening, a wrong URL, a time out): `httpx.error()` says why.
* `c->headers` holds headers that go with **every** request (`X-Client` here). `c->keepAlive = true` reuses the connection for the next
  request to the same server (`reused=1`); a kept connection that went stale is replaced without you noticing.
* `postJson` sets `Content-Type: application/json`; the body of a reply is a string, so `json.parse(r->body)` works directly
  ([the data formats chapter](#chap-data-formats) shows `json`).
* Free a `Reply` with `dispose()`. A client made by `newClient()` is freed by `c->dispose()`.

### Redirects

A `3xx` answer with a `Location` header sends the client elsewhere. What must happen to the method and the body is a matter of rules
that have a history, and `httpx` follows them.

{{sample web/httpx_redirects}}

**What to notice.**

* **301 and 302** turn a `POST` into a `GET` without a body, **303** always does, **307 and 308** keep the method and the body (the 7 bytes
  of JSON arrived again). Relative, absolute and `//host` locations, and dot segments, are resolved.
* `maxRedirects` is 10 by default. `0` switches following off: you get the 302 itself with its `Location`. A loop ends with the
  error `too many redirects`.
* A `Location` with another scheme (`ftp:`, `file:`, `javascript:`...) fails the request: "a redirect to a URL that cannot be followed".
* `Authorization`, `Cookie` and `Proxy-Authorization` are **dropped** when a redirect leaves the origin (another host, port or scheme;
  https to http counts). The last two lines show it: the same `Authorization` header from `c->headers` arrived at the server we
  asked and not at the one we were sent to. It stays dropped for the rest of that request.

### Cookies

A **cookie** is a small value that a server asks the client to remember (`Set-Cookie`) and to send back (`Cookie`). Give the client a jar
with `c->cookies = httpx.newCookieJar()` and it follows RFC 6265: `Domain`, `Path`, `Expires`, `Max-Age`, `Secure`, `HttpOnly`,
`SameSite`, the `__Secure-` and `__Host-` prefixes, at most 50 cookies per host and 256 in all.

{{sample web/httpx_cookies}}

**What to notice.**

* Without a jar nothing is remembered. With one, the cookies set by `/login` were already in the jar when the client followed the
  redirect to `/echo`.
* The cookie `theme` has `Path=/prefs`: it is sent to `/prefs/echo` and not to `/echo`. When several cookies match, the one with the
  longer path comes first (`theme=dark; sid=abc123`).
* `Max-Age=0` deletes a cookie: after `/logout` the jar has one cookie left.
* `HttpOnly` is stored (`sid->httpOnly`), but it is a hint for **browsers**; it does not stop your own program from reading the jar.

### Retries and time limits

Networks fail, and some failures are worth another try. With `retries` set, the client tries again after a connection error and after
`502`, `503`, `504` and `429`, for requests that are safe to repeat (not `POST` and `PATCH` unless `retryAll`). It waits
`retryBackoffMs` first and doubles the pause each time (5 seconds at most), and it honours `Retry-After` up to 5 seconds.

{{sample web/httpx_retries}}

**What to notice.**

* Without retries the first answer is the answer: the `503` came back. With three retries the client tried three times and got the 200.
  The `Retry-After: 0` of the server made the pauses zero.
* Time limits are separate, all in milliseconds: `connectTimeoutMs` (5000), `sendTimeoutMs` (15000), `headerTimeoutMs` (15000),
  `bodyTimeoutMs` (15000, for each piece of the body) and `totalTimeoutMs` (0 = none, the whole request with its redirects).
  A server that says nothing ends with `timed out waiting for the answer`.
* For `https://` the TLS layer reads with its own 10 second limit.

### A router, middleware and authentication

A router matches the **method** and the **path** of a request to a function. Patterns have `:name` parts and a final `*` that takes the
rest of the path. **Middleware** is a function that runs before the route and decides whether the request goes on (`x->next()`).
Because these pieces work on bytes, you can test a whole server **without a network**: feed a request as text to the `RequestParser`,
give the parsed request to `router->handle`, and look at the response.

{{sample web/httpx_router}}

**What to notice.**

* A handler is `int handler(httpx.Context* x)`; it fills `x->res` (`text`, `json`, `html`, `bytes`, `redirect`, `error`, `setHeader`)
  and reads `x->req` (`param`, `queryValue`, `header`, `cookie`, `body`).
* The router adds what a good server adds: `404` for an unknown path, **`405` with an `Allow` header** for a known path and a wrong method,
  `OPTIONS` answered from the routes, and `HEAD` for every `GET` route (no body is sent, the length is).
* `guard` is middleware: it ends the request with `httpx.unauthorized(...)` (a `401` and `WWW-Authenticate`) or calls `x->next()` and,
  afterwards, adds a header to the finished answer. It ran for the 404 and the 405 too.
* `httpx.checkBasic(req, user, umax, pass, pmax)` decodes a Basic `Authorization` header; compare secrets with
  `httpx.constantTimeEquals`, which does not stop at the first difference. `httpx.bearerToken(req)` reads `Authorization: Bearer`.
  Basic and Bearer tokens are not encrypted: use them over `https` (`wss`, a hub with TLS).
* The parser refuses what is used for **request smuggling**: `Content-Length` together with `Transfer-Encoding` (last line),
  conflicting `Content-Length` values, folded headers, bad tokens and NUL bytes in paths. The status is 400, 413, 414, 431, 501 or 505.
  The request target may be 2048 bytes at most, the path under 1099.
* CORS has its own piece: `httpx.Cors` with `corsMiddleware` (preflight, credentials, `Vary`). It is not in a sample here.

### Forms and uploads

An HTML form with files is sent as `multipart/form-data`: parts separated by a boundary text. `httpx.newMultipart()` builds one
(`addField`, `addFile`, `addFilePath`), `c->postMultipart(url, form)` sends it, and `httpx.parseMultipart` splits one on the server.

{{sample web/httpx_upload}}

**What to notice.**

* Field names and file names are escaped for you: the quote marks in `Holiday "photos"` survived. The field `note` has a line break
  and still came out whole; a boundary text that appears inside the data is data.
* A part with a `filename` is a file: its `contentType` and `length` are there, and the bytes (all 300, zero bytes included) in `data`.
* `parseMultipart` returns `-1` for a body that is not multipart (the second request: `400`). It has limits on the number of parts and
  on part headers. Free the parts with `httpx.freeParts`.
* The other body forms of the client: `postForm(url, "a=1&b=2")` (the fields must already be encoded) and
  `requestChunked(method, url, headers, reader, user)` for an upload of unknown length. The second is not in a sample.

### Files, ranges and downloads

A hub with `staticDir` (or `httpx.serveFile(req, res, root, options)` in your own route) serves files with `Content-Type`, `ETag`,
`Last-Modified`, `Range` and conditional requests, index files, and no dot files, no `..`, no symbolic links on the way. The client
side is `getRange`, conditional headers, `downloadTo` and `decompress`.

{{sample web/httpx_files}}

**What to notice.**

* `Range: bytes=995-` gave **206** with `Content-Range: bytes 995-999/1000`. A start past the end gave **416**.
* `If-None-Match` with the `ETag` of the first answer gave **304 and no body**: "you already have it".
* `downloadTo(url, path, resume, &written)` writes to a file and never holds the body in memory. With `resume` it continues at the
  end of an existing file: the file had 400 bytes, 600 were fetched (status 206), and it ended with 1000. It returns the status, or
  `-1` on failure.
* `c->decompress = true` asks for gzip and unpacks the answer; the reply says 59 bytes where 35 travelled. A body that does not unpack is
  an **error**, not the raw bytes, and `maxBody` (64 MiB) holds for the unpacked size too, so that a compressed bomb is refused
  (`docs/NET.md`; this part was not run for the chapter). `stream(url, callback, user)` hands a body to a function in pieces; it is not in a sample.

## JSON-RPC 2.0

**JSON-RPC** is a small protocol for calling functions in another program: a request is a JSON object with a `method`, `params` and an
`id`; the answer has the same `id` and either a `result` or an `error`. A request **without** an `id` is a *notification*: no answer is
sent. Several requests can travel in one array, a *batch*. The module follows the specification, including its error codes:
`-32700` parse error, `-32600` invalid request, `-32601` method not found, `-32602` invalid params, `-32603` internal error, and
`-32000` to `-32099` for yours.

### The dispatcher alone

A `jsonrpc.Dispatcher` is a table of method names and functions. `handleText(request, n, &outLength)` takes a request as text and returns
the answer as text (or `null` when no answer is due). It has no transport, so it is easy to test:

{{sample web/rpc_dispatch}}

**What to notice.**

* A handler is `json.Json* f(jsonrpc.Call* c)`. `c->param(0, "a")` reads a parameter by position (`[1,2]`) **or** by name
  (`{"a":1,"b":2}`). To fail, call `c->fail(code, message, data)` and return `null`.
* **Return a new value, never `params` or a part of it:** the module frees the request and the result separately.
* A notification (no `id`) ran the handler (`logged` is 1) and produced no answer. A batch gives an array of answers; the notification
  in it has none, the invalid entry (`42`) has an Invalid Request with `id` `null`, and a batch of notifications alone has no answer at all.
* The checks of the specification are there: an empty batch, an `id` that is an object, text that is not JSON (-32700). `id`s may be
  strings, numbers or `null`. Limits: 100 requests per batch, 1 MiB per message, 200 levels of nesting. A text that is not UTF-8, or has a
  NUL byte or a `\u0000`, is a parse error.

### Three transports

The same dispatcher serves three transports:

| Transport | Server | Client |
|---|---|---|
| a stream, one JSON text per line (or `Content-Length` headers like the Language Server Protocol) | `jsonrpc.serveStream(d, connection, framing, limit)` | `jsonrpc.connectStream(connection, framing)` |
| HTTP `POST` | `router->add("POST", "/rpc", jsonrpc.httpHandler, (char*) d)` | `jsonrpc.connectHttp(url)` |
| WebSocket | `hub->onMessage = jsonrpc.hubMessage; hub->user = (char*) d` | `jsonrpc.connectWebSocket(url)` |

{{sample web/rpc_transports}}

**What to notice.**

* The function `exercise` is the same for all three, and so is its output. A client has `call(method, params)`, `notify(method, params)`
  and `batch()`; the calls look alike whatever carries them.
* `call` returns the result (free it with `dispose()`), or `null`. Then either `c->errCode`, `c->errMessage` and `c->errData` describe an
  **error answer** from the server, or `c->transportError` describes a problem below JSON-RPC: a lost connection, a time out
  (`timeoutMs`, default 10000), an answer that is not valid.
* A batch: `b->add(method, params)` returns an index, `b->notify` adds a notification, `send()` sends the lot, and `b->result(i)`,
  `b->errorCode(i)`, `b->answered(i)` read the answers by index.
* Params you pass to the client stay yours: dispose them yourself. `c->dispose()` closes the connection and frees the client (a connection
  you gave to `connectStream` stays yours).
* **Not supported:** the server cannot call the client over the connection the request came in on. Messages that the server sends on
  its own arrive in the client's `onNotification`.

## Waiting without threads

Several things may have to happen at once: a client waits for an answer while a server must answer, a program serves ten
connections, a GUI must stay alive. The usual answer is threads. These modules offer three others, in the order of how much of the
loop you write yourself:

| Tool | You write | Use it for |
|---|---|---|
| `wshub` with `hub->run()` or `hub->poll(ms)` | callbacks | a server |
| `ws->setNonBlocking(true)`, `pump()`, `takeMessage()`, `flush()` with a `conn.Poller` | the loop | your own protocol or a few connections |
| `net.setIdleHook(fn)` | the other end of **one** connection | tests, samples, a GUI that must not freeze |

### The idle hook

`net.setIdleHook(fn)` makes every blocking wait of `net` (receive, accept, wait for readability, the TLS handshake) call `fn()` about every
2 ms while it waits. If a program is **both** the client and the server of a connection, the server can live in `fn`. It is how every
sample in this chapter works, how the tests of these modules run on every target, and the way it stays portable on Windows, where
`thread` runs a function at once in the calling thread instead of starting one.

{{sample web/idle_hook}}

**What to notice.**

* The client's `recvLine` blocks. While it waits, `serve()` accepts the connection and answers. Nothing else is needed.
* The hook must **never wait**. The client is waiting for the hook, so a blocking call inside it stops both. Use calls that do not wait:
  `net.waitReadable(h, 0)` (0 ms), `net.acceptSome`, `net.recvSome`, `net.sendSome`, `hub->poll(0)`, `ws->pump()`.
* **A trap:** `net.accept(listener)` waits until the listener is readable **even on a non-blocking listener** when a hook is set. Inside
  the hook that waits for ever, as soon as no client is pending. Use `net.acceptSome` on a non-blocking listener, or test
  `net.waitReadable(listener, 0)` first.
* While the hook runs, `net` does not call it again. A blocking call inside the hook therefore really blocks.
* It is not for production servers: use a hub there. `net.setIdleHook(null)` removes it.

### Your own loop with a poller

A `conn.Poller` waits for many sockets at once. With `ws->setNonBlocking(true)` a `WebSocket` never waits: `fd()` is the socket to give to the
poller, `pump()` reads what has arrived (answering pings, noticing close frames), `takeMessage()` hands out the messages and
sends are queued and flushed as the socket allows.

{{sample web/ws_poller}}

**What to notice.**

* `step()` looks and never waits: `poller->wait(0)` returns how many sockets are ready, `readyTag(k)` says which (the tag is the slot we
  gave to `add`; the listener has the tag 100). Only the ready peers are pumped.
* The tags are **copied before** the sockets are served, because `poller->remove` reorders the poller's lists and would make the
  later `readyTag(k)` point at the wrong entry.
* When a peer's `closed` turns true, take it out of the poller and `dispose()` it. The server saw the code of client 2 (1000).
* A `wss` socket cannot be switched to non-blocking mode. For TLS use a hub.

### Keepalive

A silent connection may be an idle one or a dead one (a cable pulled, a phone out of range): TCP can take minutes to say so. A
**keepalive** pings after some silence and gives up when no answer comes. `ws->setKeepalive(intervalMs, timeoutMs)` does it for one
connection (a blocking `waitMessage` serves it by itself); a hub does it with `pingIntervalMs` and `pongTimeoutMs`. The clock is a
parameter (`tick(now)`), so a sample can run time at its own speed:

{{sample web/ws_keepalive}}

**What to notice.**

* Any sign of life counts: a pong, but also a message. The interval starts again from the last one.
* The ping at 2100 ms was not answered, and 500 ms later the library sent a close frame with **1011** and ended the connection
  (`failReason` has the text). After that, sending fails.
* `ws->rttMs` is the round trip of the last ping that was answered (here 40 ms), `-1` before the first one.

## Limits and traps

A list of the places where these modules can surprise you. Most of them are in the samples above.

* **Listening on every interface.** `hub->listen(port)`, `hub->listenTls(port, cfg)` and `conn.Listener(port)` listen on `0.0.0.0`.
  For a server that is only for this machine use `hub->listenOn("127.0.0.1", port, cfg)` or `net.listenOn`.
* **The defaults are made for a trusted network.** No idle timeout, no ping, 1000 clients of 1 MiB each. See the table in
  [Limits and timeouts](#limits-and-timeouts).
* **Pointers have a lifetime.** `data` in `onMessage` is valid during the call; a `Client*` until `onClose` returns. Keep ids, not
  pointers. A `Message` from `receiveMessage` or `takeMessage` is yours: call `dispose()`.
* **Free what you make.** `WebSocket`, `Message`, `Reply`, `Response`, `Request`, cookie jars, multipart forms, JSON values and the texts
  of `stringify` use the malloc heap and have `dispose()`. The runtime's `new` and `alloc` never give memory back, so objects that a
  program creates again and again have **factory functions** (`httpx.newClient()`, `httpx.newCookieJar()`, `httpx.newMultipart()`,
  `websocket.connect`, `sse.connect`, `jsonrpc.connectHttp`, `conn.create`) whose `dispose()` frees the whole object. A `new httpx.Client()`
  still works and still leaks its few bytes. A hub itself runs in constant memory.
* **Closing in the same callback.** `hub->close` on an **event stream** drops what is still queued (see above).
* **`closeWith` can wait.** In blocking mode up to one second for the peer's answer.
* **`receive(buf, max, &op)` is the old API:** cuts long messages, leaves no zero at exactly `max` bytes. Use `receiveMessage`.
* **`net.accept` with an idle hook waits** (see above); `net.acceptSome` does not.
* **Request targets.** `httpx` refuses a request target over 2048 bytes and a path of 1099 bytes or more with 414. The older `http.Request`
  has fixed buffers: `query` holds 1024 bytes, so copying a longer form body into it overflows (the previous chapter guards for it).
* **IPv4 only.** Like the rest of `net`.
* **Bare LF.** The request parser and the client accept a bare LF as a line end, as RFC 9112 allows for recipients. If a proxy in front
  of your server treats a bare LF differently, configure it to reject bare LF.

## What the modules do not do

From `docs/NET.md` and from the limits found while writing this chapter:

* **No HTTP/2**, no h2c upgrade, no proxies, no `CONNECT`, no trailers in answers, no cache in the client. HTTP/1.0 and 1.1 only.
  `Expect` values other than `100-continue` are ignored. Method names are compared as they come (`get` is not `GET`).
* **No WebSocket compression with a window that is kept between messages when sending.** Receiving supports it; our compressor writes
  fixed Huffman blocks and starts afresh for every message, so a server always answers with `server_no_context_takeover`.
* **TLS is slow.** Public key arithmetic is done in A, with no assembly or hardware help: about 150 ms of processor time per handshake
  on a server (x86-64, according to `docs/NET.md`), and a hub does it in its only thread. TLS 1.3 only: no TLS 1.2, no session
  resumption, no client certificates, no ALPN ([the previous chapter](#chap-http-websocket-tls)).
* **No server-to-client calls in JSON-RPC** over the connection of the request.
* **One thread.** Every blocking call of the client side blocks. To wait for several things use `conn.Poller`, `ws->setNonBlocking`, a
  hub or the idle hook. The idle hook is for tests and GUI programs.
* **No limit per address and none for the hub as a whole.** A firewall or a reverse proxy has to provide it. A closing WebSocket lingers
  for one second and counts towards `maxClients` meanwhile.
* **No IPv6.**
* **Not run for this chapter:** Windows and AOS, a real browser (the interoperability tests in `tests/net.sh` use python `websockets`,
  curl and openssl: I did not run them), `Cors`, `Client.stream`, `requestChunked`, a `Last-Event-ID` against a browser, the speed of
  TLS, and hubs with hundreds of clients. The samples compile for all nine targets; they were run on x86-64 and, under `qemu-user`, on
  ARM64.

## Summary

* `websocket` is complete and strict: `ws://` and `wss://`, UTF-8 checking, close codes with reasons, fragments and streaming,
  permessage-deflate with a bomb limit, keepalive, and a state machine without I/O for your own loop.
* A peer that breaks the rules gets a close frame (1002 protocol, 1007 bad text, 1009 too big, 1011 keepalive) and loses the connection.
  Frames announcing a huge length are refused from the header.
* `receiveMessage()` gives a `Message` that always ends in a 0 byte. `closeCode` 1006 means "no close frame arrived", 1005 "no code".
* `wshub` serves WebSockets, event streams and HTTP from one thread on one port: callbacks, rooms, limits, timeouts, TLS. Its defaults
  are for a trusted network.
* `sse` writes and parses event streams; the client reconnects with `Last-Event-ID`, and 204 means "stop".
* `httpx` is an HTTP client (redirect rules, cookies, retries, time limits, downloads) and a server kit (parser, router, middleware, files,
  multipart) that can be tested without a network.
* `jsonrpc` serves one dispatcher over streams, HTTP and WebSocket, with batches, notifications and the error codes of the specification.
* `net.setIdleHook` lets one thread play both ends of a connection; for a server use a hub, for your own protocol a `conn.Poller`.

## Where next

* [HTTP, WebSocket and TLS](#chap-http-websocket-tls): the basics under all of this, and the older `http` module.
* [Networking](#chap-networking): the sockets, `conn` and the poller.
* [Data formats](#chap-data-formats): `json`, which `jsonrpc` and the samples above use.
* API references: [websocket](#api-websocket), [wshub](#api-wshub), [sse](#api-sse), [httpx](#api-httpx), [jsonrpc](#api-jsonrpc),
  [net](#api-net), [conn](#api-conn), [zlib](#api-zlib), [json](#api-json).
* `docs/NET.md` in the repository: the reference for these five modules, with all options and limits; `tests/t340` to `t370` are
  verified programs for every feature, and `examples/hub_demo.a` is a complete server (WebSocket, rooms, HTTP routes, uploads, SSE,
  JSON-RPC, static files, optional TLS).
