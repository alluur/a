# Web protocols: WebSocket, wshub, SSE, httpx and JSON-RPC

Five modules for programs that talk HTTP and WebSocket, written in A, running on every target (Linux x86-64, ARM64, RISC-V, LoongArch,
Windows and AOS) with the same code. They sit on `net`, `conn`, `tls` (TLS 1.3, [TLS.md](TLS.md)), `zlib` and `json`.

| Module | What it is |
|---|---|
| `websocket` | RFC 6455 and RFC 7692: client and server, `wss://`, strict frame checking, UTF-8 validation, close codes, fragments, permessage-deflate, keepalive, non-blocking use |
| `wshub` | a poll based server for thousands of WebSocket clients in one thread: rooms, send queues with limits, timeouts, TLS, plus an HTTP side and event streams |
| `sse` | Server-Sent Events: the wire format, a parser, a client that reconnects with `Last-Event-ID` |
| `httpx` | an HTTP toolkit: client (redirects, cookies, keep-alive, retries, streaming), request parser, router, middleware, static files, CORS, auth, multipart |
| `jsonrpc` | JSON-RPC 2.0: dispatcher and client over framed streams, HTTP and WebSocket |

Also changed underneath: `net` got non-blocking calls and a cooperative waiting hook, `conn` frees its buffers, `tls` reuses finished sessions,
`zlib` got the calls permessage-deflate needs, `json` values can be freed.

## websocket

```c
import websocket;

websocket.WebSocket* ws = websocket.connect("wss://example.org/chat");      // ws:// or wss:// (certificate checked); null: websocket.error()
ws->sendText("hello");
websocket.Message* m = ws->receiveMessage();                                // null when the connection ended: ws->closeCode says why
println(m->data);  m->dispose();
ws->closeWith(1000, "bye");                                                 // closing handshake, then the socket is closed
ws->dispose();                                                              // frees everything; the pointer is invalid afterwards
```

Options (`websocket.Options`, pass to `connectWith(url, options)`): `verify` (check the server certificate; `websocket.setVerify(false)` changes
the default, like `http.setVerify`), `origin`, `protocols` ("chat, superchat"), `cookie`, `authorization`, `headers` (more request lines),
`deflate`, `maxMessage`, `maxFrame`, `connectTimeoutMs`, `handshakeTimeoutMs`. Values with CR, LF or other control characters are refused
before a connection is made (no header injection); the Sec-WebSocket-Key and every mask come from the operating system's random generator.
After the handshake `ws->protocol` is the subprotocol the server chose (`""` if none) and `ws->deflate` says whether compression is on.

A blocking server, one connection per call:

```c
conn.Connection* c = listener->accept(-1);
websocket.WebSocket* ws = websocket.accept(c, path, 256);            // reads the upgrade request, answers it; null if it was no valid upgrade
// websocket.acceptTls(c, tlsConfig, path, 256)                      // wss://: TLS handshake first
// websocket.acceptWith(c, serverOptions, info)                      // subprotocols, Origin policy, permessage-deflate, limits; info gets path, Origin, header(...)
// websocket.readUpgrade / completeUpgrade / rejectUpgrade           // look at the request (path, cookies) before you accept it, or refuse with 401, 403, 404
```

### What is checked (RFC 6455, strict)

Every violation sends a close frame with the right code and ends the connection (`ws->failed`, `ws->failReason`):

| Violation | Code |
|---|---|
| reserved bits RSV2, RSV3; RSV1 without permessage-deflate, on control frames or continuation frames | 1002 |
| unknown opcodes (3-7, 11-15) | 1002 |
| control frames longer than 125 bytes or fragmented | 1002 |
| an unmasked frame from a client, a masked frame from a server | 1002 |
| lengths that are not minimal (126 for 100 bytes, 127 for 1000 bytes), 64 bit lengths with the top bit | 1002 |
| a continuation without a message, a new message inside a fragmented one | 1002 |
| close frames with one payload byte or an invalid code (0-999, 1004-1006, 1015-2999, 5000+) | 1002 |
| text that is not UTF-8 (overlong forms, surrogates, above U+10FFFF, cut off at the end), also split over fragments, also a close reason | 1007 |
| a frame over `maxFrame`, a message over `maxMessage` (also inflated), a decompression bomb | 1009 |
| keepalive ping not answered | 1011 |

Text is checked as it arrives, so an invalid byte ends the connection before the message is complete. Pings are answered with pongs by the
module, but a pong is queued like any other frame: when the send queue is at `maxOutBuffer` the pong is skipped (RFC 6455 5.5.3 allows that) and `overflowed` is set, so a peer that pings
and never reads cannot make the queue grow (a `wshub` cuts such a client off). `closeWith(code, reason)` accepts the codes 1000-1003, 1007-1014 and 3000-4999 and a reason of at most 123 bytes of UTF-8. Text that you send is
checked too: `sendText` with invalid UTF-8 sends nothing and returns false.

### The server side of the handshake

`serverHandshake` judges the upgrade request as RFC 6455 4.2.1 says: method GET, HTTP/1.1, `Host`, `Upgrade`, `Connection`, a 16 byte base64 `Sec-WebSocket-Key`, and `Sec-WebSocket-Version` exactly `13` (otherwise 426 with the
supported version). **Origin:** with `ServerOptions.origins` set (a comma separated allow-list, `*` for any) an Origin that is not on the list is refused with 403, and so is a request without Origin if `requireOrigin` is on.
An `Origin` header that is *there* but empty, or 300 bytes or longer (a real origin is at most about 267: scheme, a 253 character host name, a port), is refused with 403 with or without a policy: it must not count as "no Origin"
(that let a browser past the allow-list in an earlier version) and it is never cut short (a prefix could match). Two Origin headers never match. The Origin that `onUpgrade` and `Client.origin` see is the whole header value.
Subprotocols and extensions that the client offers and the server does not know are ignored, as the RFC allows.

### Fragments, streaming, limits

```c
ws->beginMessage(websocket.OP_BINARY);  ws->sendFragment(data, n);  ...;  ws->endMessage();   // pieces are sent as they come (pings may go in between)
ws->setFragmentSize(4096);                       // split every message into frames of at most that size
ws->setStreamHandler(cb);                        // cb(ws, opcode, data, length, flags): pieces of a message as they arrive, nothing is collected
ws->setMaxMessage(1 << 20);  ws->maxQueue = 256; ws->maxOutBuffer = 1 << 20;
```

`maxMessage` and `maxFrame` default to 16 MiB. A message is assembled in a buffer that grows with the data (never beyond `maxMessage`) and is
given back after a big message. `maxOutBuffer` limits the bytes queued for sending (0: no limit): a send that would pass it returns false and sets
`ws->overflowed`.

### permessage-deflate (RFC 7692)

Turn it on with `Options.deflate` (client) or `ServerOptions.deflate` (server). Supported: the offer and the answer with every parameter
(`server_no_context_takeover`, `client_no_context_takeover`, `server_max_window_bits`, `client_max_window_bits`, quoted values, several offers in one header or in
several headers), strict validation of the answer (unknown or repeated parameters fail the handshake), compression of messages from `minCompress`
(default 64 bytes) up, the window limit for our compressor, and **context takeover when receiving** (a dictionary of the last 32 KB). Our own compressor never
uses context takeover (each message is independent, which every peer accepts); a server therefore always answers with `server_no_context_takeover` and, unless
`ServerOptions.allowTakeover`, `client_no_context_takeover`. With deflate on, messages sent in pieces are collected and sent compressed by `endMessage`. Every inflated
message is limited to `maxMessage` while it is inflated, so a few hundred bytes cannot become a gigabyte (close code 1009).

### Without sockets, and with a poller

`WebSocket` is a state machine that does no I/O of its own: `feed(bytes, n)` parses what arrived, `outData()` / `outPending()` / `outConsumed(n)` is what to send,
`takeMessage()` or a handler (`setHandler(cb)`: `cb(ws, event, opcode, data, length)`) delivers messages, `tick(now)` runs the keepalive
(`setKeepalive(intervalMs, timeoutMs)`: a ping after that much silence, 1011 when it stays unanswered). `wshub` is built on exactly that. For your own loop with
a `conn.Poller`: `ws->setNonBlocking(true)` (plain sockets only), put `ws->fd()` in the poller, call `ws->pump()` when it is readable (reads what is there, never waits,
answers pings), `ws->takeMessage()`, and `ws->flush()` while `outPending() > 0`.

## wshub

```c
import wshub;

int onOpen(wshub.Hub* h, wshub.Client* c)                      { h->join(c, "lobby"); return 0; }
int onMessage(wshub.Hub* h, wshub.Client* c, char* data, int n, int isText)
                                                               { h->publish("lobby", data, n, isText == 1, c->id); return 0; }
int onClose(wshub.Hub* h, wshub.Client* c, int code)           { return 0; }

wshub.Hub* hub = new wshub.Hub();
hub->onOpen = onOpen;  hub->onMessage = onMessage;  hub->onClose = onClose;
hub->staticDir = "www";                                        // GET / serves www/index.html; /healthz answers by itself
if (!hub->listen(8080)) { ... }                                // hub->listenTls(8443, tls.loadConfig(certPem, keyPem)) for wss and https
hub->run();                                                    // or: for (;;) { hub->poll(50); ... }   from your own loop
```

One thread serves every socket (`net.poll`): there is no blocking call in the loop (TLS handshakes are state machines too), no thread per client. `examples/hub_demo.a`
is a complete server (WebSocket, rooms, HTTP routes, uploads, SSE, JSON-RPC, static files, optional TLS).

| Setting | Default | Meaning |
|---|---|---|
| `maxClients` | 1000 (at most) | all connections; more get `503 Service Unavailable` |
| `maxMessage` | 1 MiB | largest WebSocket message, else 1009 |
| `maxQueued` | 1 MiB | bytes waiting to be sent to one client (messages and the pongs for its pings); over it the client is cut off (close code 1008 in `onClose`, `stats->evicted`) |
| `maxBody`, `maxHead` | 1 MiB, 16 KiB | HTTP request limits (413, 431) |
| `handshakeTimeoutMs` | 5000 | from accept to a complete request, TLS handshake included (slowloris) |
| `idleTimeoutMs` | 0 (off) | a WebSocket silent this long is closed with 1001 |
| `pingIntervalMs`, `pongTimeoutMs` | 0 (off), 10000 | ping silent clients; close the ones that do not answer (1011) |
| `keepAliveMs`, `closeTimeoutMs`, `sseKeepAliveMs` | 10000, 3000, 15000 | idle HTTP connections, the closing handshake, comment lines on event streams |
| `wsOptions` | | a `websocket.ServerOptions`: `protocols`, `origins`, `requireOrigin`, `deflate`, ... |
| `router`, `staticDir`, `onHttp`, `healthz` | | the HTTP side |

Callbacks are function pointers (every argument arrives as a number). `data` in `onMessage` is valid during the call and followed by a 0 byte. `c->user` is yours.
The `Client` pointer is valid until `onClose` returns; keep `c->id` (never reused while the hub runs) and use `hub->find(id)`, `sendTextTo(id, text)`, `closeId(id, ...)` later.
A closed client's socket stays open for up to a second while the other side reads the close frame (so unread data cannot turn the close into a connection reset);
such clients are not counted by `hub->count()`.

Sending: `sendText(c, text)`, `sendBinary(c, data, n)`, `broadcast(...)`, `publish(room, data, n, isText, exceptId)`. Rooms: `join(c, "name")`, `leave(c, "name")`, `roomSize`;
a client may be in 8 rooms, names have at most 63 bytes, `maxRooms` rooms exist (default 1000); a room disappears with its last member and a client leaves its rooms when it closes.
With permessage-deflate every recipient of a broadcast gets its own compression. `hub->shutdown(graceMs)` stops listening, sends close frames with 1001 and waits for the answers.
`hub->stats` counts connections, messages, bytes, evictions, timeouts and TLS failures; `GET /healthz` returns a part of it as JSON.

**HTTP side.** Requests that are no upgrades go to: `GET /healthz`; `hub->onHttp(hub, client, request, response)` (return 1 when you answered); `hub->router`
(an `httpx.Router`; a 404 from it falls through to the static files); `hub->staticDir` (GET and HEAD with ETag, Range, If-Modified-Since); 404. Keep-alive, chunked request
bodies, `Expect: 100-continue` and pipelining work; files are streamed in 16 KB pieces, never read whole. `hub->onUpgrade(hub, client, info)` may refuse an upgrade with an HTTP status after
looking at `info->path` and `info->headerInto("Cookie", buf, max)`.

**Event streams.** In `onHttp`: `sse.startResponse(res); return 1;`. The connection becomes a client of kind `KIND_SSE`: it is in `onOpen` / `onClose`, can join rooms, and receives the text of
`sendText`, `broadcast` and `publish` as events (`hub->sendEvent(c, name, data, id)` for names and ids). A comment line goes out every `sseKeepAliveMs`.

## sse

```c
import sse;
char* wire = sse.eventText("update", "line 1\nline 2", "7", 0);      // event: update / id: 7 / data: line 1 / data: line 2 / blank line (a heap string)
sse.begin(fd);  sse.send(fd, "tick", "now", "1");  sse.comment(fd, "keep-alive");     // on a plain socket (http.serve handlers)

sse.Client* c = sse.connect("http://localhost:8080/events");          // https works too; c->dispose() frees it
sse.Event* e = c->next(5000);                                        // waits at most 5 s; null: nothing yet (c->closed: given up)
println(e->event); println(e->data); println(e->id);  e->dispose();
```

`eventText` returns null when the event name or id contains CR or LF (stream injection). The parser (`sse.Parser`, usable alone) follows the specification: LF, CR and CRLF line ends, comments, one optional space after
the colon, data lines joined with LF, `id` with a NUL ignored, `retry` with digits only, a leading byte order mark skipped, an empty line at the start of the stream is fine, an event without an `event` field or with an empty one has the type `message`, an event is dispatched only if it has data. Limits: 64 KB per line, 1 MB per event, 1024
events waiting. The client sends `Last-Event-ID`, follows up to 3 redirects (also relative ones; other schemes are refused), reads header names in any letter case, understands chunked streams, honours the server's `retry` value, doubles its pause after each failure up to `maxRetryMs`, and gives up after
`maxRetries` failures in a row (default 5, -1 for never). A status other than 200, a content type other than `text/event-stream` and 204 end the client for good, as the specification says.

## httpx

**Client** (`httpx.Client`, blocking; https as in `http`):

| Feature | How |
|---|---|
| redirects 301 302 303 307 308 | `maxRedirects` (default 10). 303 becomes GET (HEAD stays); 301 and 302 turn POST into GET; 307, 308 and 301/302 of other methods keep method and body; `Authorization`, `Cookie` and `Proxy-Authorization` are dropped on a redirect to another origin (host, port or scheme: a downgrade from https to http counts) and stay dropped for the rest of that request, whether they came from the request's headers or from the client's default headers `client->headers`; relative, absolute and `//host` locations, dot segments. A Location with another scheme (`ftp:`, `file:`, `javascript:` ...) or a path over 2047 bytes fails the request ("a redirect to a URL that cannot be followed") |
| cookies | `client->cookies = httpx.newCookieJar()`: Set-Cookie after RFC 6265 (Domain, Path, Expires, Max-Age, Secure, HttpOnly, SameSite, `__Secure-` and `__Host-`), 50 per host and 256 in all |
| keep-alive | `keepAlive = true` reuses the connection; a kept connection that went stale is replaced without the caller noticing |
| retries | `retries`, `retryBackoffMs` (doubling, at most 5 s): connection errors and 502, 503, 504, 429 (`Retry-After` up to 5 s); only idempotent methods unless `retryAll` |
| timeouts | `connectTimeoutMs`, `sendTimeoutMs`, `headerTimeoutMs`, `bodyTimeoutMs`, `totalTimeoutMs` (https: the TLS layer reads with its own 10 s limit) |
| streaming | `stream(url, cb, user)` hands the body of a 2xx answer to `cb(user, data, n)` in pieces; `downloadTo(url, path, resume, &written)` writes a file without holding it in memory, with `Range` resume |
| Range | `getRange(url, from, to)` |
| bodies | `post put patch postForm postJson`, `postMultipart(url, multipart)`, `requestChunked(method, url, headers, reader, user)` for uploads of unknown length |
| answers | `Reply`: `status`, `header(name)`, `body` (+ 0 byte), `bodyLen`, `url`, `redirects`, `reused`; chunked, Content-Length and until-close bodies; 1xx skipped; gzip / deflate unpacked with `decompress = true`; `maxBody` (default 64 MiB) holds for the unpacked size too (a compressed bomb fails with "the answer body is too big") and a body that does not unpack is an error, not the raw bytes; at most 100 trailer lines, read within `bodyTimeoutMs` |

**Server pieces** (they work on bytes, so any transport can use them):

* `httpx.RequestParser`: HTTP/1.0 and 1.1; Content-Length and chunked bodies; limits (`maxHead`, `maxHeaders`, `maxBody`); refuses request smuggling shapes (Content-Length with chunked, conflicting
  Content-Length values, folded headers, bad tokens, NUL in paths) with 400, 413, 414, 431, 501 or 505.
* `httpx.Router`: `get post put del patch any(pattern, handler)`; patterns `/users/:id/posts/:post` and `/files/*`; `req->param("id")`, `req->queryValue("q", buf, n)`, `req->cookie(...)`; middleware
  `use(mw, data)` with `x->next()`; 404, 405 with `Allow`, OPTIONS, HEAD on GET routes; `onNotFound`. Handler signature: `int handler(httpx.Context* x)` with `x->req` and `x->res`.
* `httpx.Response`: `text json html bytes redirect error setHeader addHeader`; header values with CR/LF are refused; `Content-Length` and `Connection` are always ours.
* `httpx.serveFile(req, res, root, options)`: types, `ETag`, `Last-Modified`, `If-None-Match`, `If-Modified-Since`, `If-Match`, `If-Unmodified-Since`, `Range` (one range; `If-Range`; 416), index files, no dot files,
  no `..`, no symbolic links on the way (403).
* `httpx.Cors` with `corsMiddleware` (preflight, credentials, `Vary`), `checkBasic`, `bearerToken`, `unauthorized`, `constantTimeEquals`.
* `httpx.Multipart` builds forms (names and file names are escaped); `httpx.parseMultipart(contentType, body, n, parts, max)` reads them (boundary text inside data is data; limits on parts and part headers).

## jsonrpc

```c
json.Json* add(jsonrpc.Call* c) {
    json.Json* a = c->param(0, "a");  json.Json* b = c->param(1, "b");           // positional [1,2] or named {"a":1,"b":2}
    if (a == null || b == null) { c->fail(jsonrpc.INVALID_PARAMS, "need a and b", null); return null; }
    return json.newInt(a->asInt() + b->asInt());
}
jsonrpc.Dispatcher* d = new jsonrpc.Dispatcher();   d->add("add", add);
router->add("POST", "/rpc", jsonrpc.httpHandler, (char*) d);          // HTTP (httpx / wshub)
hub->onMessage = jsonrpc.hubMessage;  hub->user = (char*) d;          // WebSocket clients of a wshub
jsonrpc.serveStream(d, connection, jsonrpc.FRAME_LINES, 0);           // newline delimited, or FRAME_LENGTH: Content-Length headers

jsonrpc.Client* c = jsonrpc.connectWebSocket("ws://localhost:8080/");   // connectStream(connection, framing), connectHttp(url)
json.Json* r = c->call("add", json.parse("[1, 2]"));                    // null: c->errCode / errMessage / errData (an error answer) or c->transportError
c->notify("log", params);   jsonrpc.Batch* b = c->batch();  int i = b->add("add", p);  b->notify("log", p);  b->send();  b->result(i);
```

The dispatcher follows the specification: requests, notifications, batches (answers only for requests, nothing for a batch of notifications, an empty batch is an Invalid Request),
ids that are strings, numbers or null (anything else is an Invalid Request), `params` that are arrays or objects, the codes -32700 -32600 -32601 -32602 -32603, reserved `rpc.` names.
Limits: 100 requests per batch, 1 MiB per message, 200 levels of nesting (the JSON parser's limit). A text that is not UTF-8, or that has a NUL byte or a `\u0000` escape (a C string cannot hold it, and "ad\u0000d" would have run `ad`), is a Parse error. Results, error data and the whole request tree are freed by the module: a server runs in constant memory.
A handler returns a new value (never `params` or a part of it: the module frees the request tree and the result separately). Params that you pass to a client call stay yours. Not supported: calls from the server to the client over one connection (server notifications are delivered to `onNotification`).

## Waiting without threads: `net.setIdleHook`

`net.setIdleHook(fn)` makes every blocking wait of `net` (receive, accept, wait for readability, the TLS handshake) call `fn()` about every 2 ms while it waits. A program that is both
client and server of a connection can serve the other end from the hook (`hub->poll(0)`); a GUI program can run its event loop. The tests of these modules use it to run a client
and a server in one thread, which works the same on every target including Windows (where threads do not exist). It is not for production servers: use `hub->run()`.

## Memory

A long running program must not grow. Everything that lives long is freed: `WebSocket`, `Message`, `Headers`, `Request`, `Response`, `Reply`, cookies, multipart
parts, JSON values and the texts that `stringify` makes use the malloc heap and have `dispose()` (or are freed with `free`). The runtime's `new` and `alloc` never give memory back, so
the objects that a program creates again and again have **factory functions** whose `dispose()` frees the object completely:

| Make it with | Free it with |
|---|---|
| `websocket.connect(url)`, `websocket.accept(...)` | `ws->dispose()` (also the connection that `connect` made) |
| `httpx.newClient()`, `httpx.newCookieJar()`, `httpx.newMultipart()` | `client->dispose()`, `jar->dispose()`, `form->dispose()` |
| `sse.connect(url)` | `client->dispose()` |
| `jsonrpc.connectHttp(url)`, `connectWebSocket(url)`, `connectStream(c, framing)` | `client->dispose()` (a connection that you gave to `connectStream` stays yours) |
| `conn.create(handle)`, `listener->accept(ms)` | `connection->dispose()` |

`new httpx.Client()` and the other constructors still work, but their object stays in memory after `dispose()` (the contents are freed); use them for objects that live as long as the program.
A `wshub` reuses its client objects, buffers and TLS sessions (`tls.release`) and the HTTP side allocates nothing per request, so it runs in constant memory.
Two tests check this the strict way: `t365` (a hub, served from raw sockets, for every kind of connection) and `t366` (the client side and the toolkits) compare the heap position
before and after many operations and demand that it did not move at all. (An early version leaked 10 KB in every permessage-deflate message and 176 bytes in every WebSocket handshake;
a test with a loose limit had let that through.) What is **not** freed: the strings that `strdup` makes (a few bytes per request in some paths of the old `http` module) and the
cryptography inside a TLS handshake (big numbers in the `bn` module; measured about 20 KB per handshake on a server). A TLS server that handles millions of connections should be restarted now and then or sit
behind a TLS terminating proxy. On AOS blocks over 128 KiB are never reused address space: message and file buffers here are small (16 KB pieces) except when you send huge messages.

## Limits: what these modules do not do

* **TLS speed.** Public key arithmetic is done in A (no assembly, no hardware help). A TLS 1.3 handshake costs a server about 150 ms of processor time on x86-64 (measured with
  `tests/net.sh`-style clients against `hub_demo`), and a `wshub` is one thread: while it computes a handshake it serves nobody else. Plain `ws://` and `http://` ports are not affected;
  for many new `wss://` connections per second put a TLS terminating proxy in front.
* **permessage-deflate.** Receiving is complete (every parameter, context takeover, dynamic and fixed blocks). Our compressor writes fixed Huffman blocks with a hash chain match finder and never
  keeps its window between messages, so it compresses a little less than zlib (measured: English and source text of 13 to 126 KB came out at 30 to 55 percent of their size, zlib level 6 at 25 to 44 percent) but every peer accepts it.
* **HTTP.** HTTP/1.0 and 1.1 only (no HTTP/2, no h2c upgrade, no proxies, no `CONNECT`, no trailers in answers). The client does not keep a cache. `Expect` values other than `100-continue` are ignored.
  Method names are compared as they come (`get` is not `GET`).
* **JSON-RPC.** The server cannot call the client over the connection it came in on; messages that the server sends on its own arrive in `onNotification` of the client.
* **One thread.** All blocking calls of the client side block; the way to wait for several things is `conn.Poller`, `ws->setNonBlocking`, or a `wshub`. `net.setIdleHook` is for tests and GUI programs.
* **IPv4 only**, like the rest of `net`.
* **Defaults that are made for a trusted network.** For a server on the internet, set these yourself. `idleTimeoutMs` and `pingIntervalMs` are 0 (off): an upgraded socket that stays silent is kept for ever, so 1000 idle
  connections (`maxClients`, default 1000) lock every other client out with 503 until they go; set `idleTimeoutMs` (and `pingIntervalMs` so that dead peers are noticed). `maxQueued` is per client (1 MiB) and there is no
  limit for the hub as a whole: 1000 slow readers can hold 1000 MiB (AOS needs 128 MB of RAM at least): lower `maxQueued` and `maxMessage`, or `maxClients`, to what the machine has. A closing WebSocket lingers for one
  second and counts towards `maxClients` meanwhile. There is no limit per address; a firewall or a reverse proxy has to provide it. A TLS handshake blocks the thread for about 150 ms (see above), so a flood of `wss://`
  connection attempts is a flood of 150 ms stalls: with TLS, a terminating proxy in front is the safe setup. `handshakeTimeoutMs` (5 s) bounds how long a half open connection holds a slot.
* **Bare LF.** The request parser and the client accept a bare LF as a line end (RFC 9112 allows it for recipients). If a proxy of yours treats a bare LF differently, put it in front only with a configuration that rejects bare LF.
* **Memory.** Objects made with `new` (instead of the factory functions) keep their own few bytes after `dispose()`; TLS handshakes keep about 20 KB each (see Memory).

## Tests

`tests/t340` to `t370` run in the normal suite on every target (client and server in one thread, ephemeral ports): frames and strictness (`t340`-`t344`), permessage-deflate (`t345`), sockets, options, non-blocking and keepalive (`t346`-`t349`), the hub (`t350`-`t354`), SSE (`t355`, and from the plain `http` server `t367`), httpx (`t356`, `t357`), JSON-RPC (`t358`, `t359`), and the layers underneath: conn and net (`t360`), zlib (`t361`), json (`t362`), TLS session reuse (`t363`), memory (`t364` zlib and permessage-deflate, `t365` the hub, `t366` clients and toolkits), and regression tests for what independent reviewers found: `t368` (a recycled WebSocket object after a half message, pongs against `maxQueued`, the Origin policy, a finished `Connection: close` answer), `t369` (Locations of 8000 bytes and other schemes, default credentials across origins, compressed bombs, trailers, huge Range numbers), `t370` (an event stream that starts with an empty line, header names and long headers of the SSE client, NUL and bad UTF-8 in JSON-RPC). `tests/net.sh` (Linux x86-64; needs python3, curl, openssl; uses the python packages
`websockets` and `requests` when they are installed) checks the modules against independent implementations: python websockets as client and server (permessage-deflate, subprotocols, Origin, wss with a
verified certificate, 160 KB and 300 KB messages), raw frames with every RFC 6455 violation, curl (Range, ETag, chunked uploads, `Expect: 100-continue`, multipart, JSON-RPC, https) and a python SSE client.
