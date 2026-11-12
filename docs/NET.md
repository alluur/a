# Network protocols: WebSocket, wshub, SSE, httpx, JSON-RPC, MQTT, Redis and syslog

Five modules for programs that talk HTTP and WebSocket, written in A, running on every target (Linux x86-64, ARM64, RISC-V, LoongArch,
Windows and AOS) with the same code. They sit on `net`, `conn`, `tls` (TLS 1.3, [TLS.md](TLS.md)), `zlib` and `json`.

| Module | What it is |
|---|---|
| `websocket` | RFC 6455 and RFC 7692: client and server, `wss://`, strict frame checking, UTF-8 validation, close codes, fragments, permessage-deflate, keepalive, non-blocking use |
| `wshub` | a poll based server for thousands of WebSocket clients in one thread: rooms, send queues with limits, timeouts, TLS, plus an HTTP side and event streams |
| `sse` | Server-Sent Events: the wire format, a parser, a client that reconnects with `Last-Event-ID` |
| `httpx` | an HTTP toolkit: client (redirects, cookies, keep-alive, retries, streaming), request parser, router, middleware, static files, CORS, auth, multipart |
| `jsonrpc` | JSON-RPC 2.0: dispatcher and client over framed streams, HTTP and WebSocket |

A second group does messaging and logging (below, from the section "MQTT"): every protocol as a **client and as a small server**, both usable in tests and on AOS.

| Module | What it is |
|---|---|
| `mqtt` | an MQTT 3.1.1 client (QoS 0 / 1 / 2, sessions, will, TLS, keep-alive, reconnect with resubscribe; a poll based and a blocking API) and the packet codec |
| `mqttd` | an MQTT broker: many clients in one loop, topic tree with wildcards, retained messages, QoS 0 / 1 / 2 to subscribers, persistent sessions, wills, `$SYS` counters, queue caps |
| `redis` | a RESP2 client (all reply types, pipelining, MULTI / EXEC, AUTH, SELECT, pub/sub, TLS, time outs, reconnect) and the RESP codec |
| `redisd` | a small in-memory Redis server (strings, lists, hashes, sets, sorted sets, expiry, pub/sub, transactions, 16 databases) with limits |
| `syslog` | RFC 5424 and RFC 3164 messages (build and parse, structured data) and a sender over UDP, TCP and TLS |
| `syslogd` | a syslog collector (UDP, TCP, TLS) with filters, files with rotation, a bounded ring buffer and forwarding |
| `netio`, `netsrv` | the layers under them: a byte queue and a non-blocking client link (plain or TLS); a poll based TCP / TLS / UDP server core |

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

`net.setIdleHook(fn)` makes every blocking wait of `net` (receive, accept, wait for readability or for room to write, a send into a full socket buffer, `connectTimeout`, the TLS handshake) call `fn()` about every 2 ms while it waits.
(`waitWritable(h, ms)` with `ms != 0` runs the hook like `waitReadable` does; before, a `netio.Link` that had to wait for a full socket, and so the mqtt and redis clients and the TCP / TLS syslog `Sender`, did not run it: the in-process peer could not drain the socket
and the send stalled until its time out. This showed on AOS, whose loopback sockets hold only 64 KiB; `t390` checks it by filling the socket first, so it does not depend on the buffer sizes of the machine.) A program that is both
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

# MQTT, Redis and syslog

Three protocol families, each with a client and a server module (and a small server program each in `examples/`: `mqttd_demo.a`, `redisd_demo.a`, `syslogd_demo.a`). The servers are built to run for a long time: every queue has a limit, every limit is a setting, memory is
freed (a strict test per family compares the heap position before and after many operations), malformed input gets an error and a closed connection. **One thing grows with every TLS handshake: about 20 KB of never-freed heap each** (the cryptography of the earlier `tls` / `bn` modules, see Memory above;
measured +1.9 MB per 100 handshakes). A server with a TLS listener that anyone can reach can be made to grow by connecting and handshaking again and again (100,000 handshakes are about 2 GB), so such a server has to be restarted now and then or sit behind something that limits
connections (`maxPerIp`, a firewall, a TLS terminating proxy); plain listeners do not have the problem. The tests run on all five
targets (Linux x86-64, ARM64, RISC-V, LoongArch, Windows) and, since the review of this stage, inside AOS in QEMU (see Tests). The modules use only layers that AOS also has (`net`, `netio`, `tls`, `asys`, `datetime`, `os`); AOS queues only 16 unaccepted connections per listener and its sockets hold 64 KiB,
which the tests no longer assume anything about.

## The layers underneath: netio and netsrv

```c
import netio;
netio.Link* l = netio.newLink();
if (!l->open("broker.example.org", 8883, 5000, true, true)) println(l->error);     // TCP connect (blocks up to 5 s), then the TLS handshake
int n = l->send(data, len);                       // bytes taken (0: the socket is full right now), -1: the connection failed. Never blocks.
if (l->waitReadable(100)) { int got = l->recv(buf, 4096); }       // > 0 bytes, 0 closed, -2 nothing now, -1 failed
l->dispose();
netio.Queue q;  q.max = 65536;  q.add(bytes, n);  /* net.sendSome(fd, q.data(), q.pending()); q.consume(sent); */
```

`netio.Queue` is a first-in first-out byte buffer with an optional limit (`add` fails and sets `overflow` instead of growing). `netio.Link` drives the TLS session of the `tls` module as a state
machine, so a TLS connection is non-blocking too (`tls.wrap` is not: it installs blocking hooks). `net.setIdleHook` works with it: the waits of a link (connect, the TLS handshake, `sendAll` into a full socket, `waitReadable`) run the hook.

`netsrv.Server` is the core of the three servers (and of anything you write): one thread, `net.poll`, no blocking call in the loop, TLS handshakes included.

```c
int onOpen(netsrv.Server* s, netsrv.Conn* c)                      { c->user = (char*) newState();  return 0; }          // < 0 refuses the connection
int onData(netsrv.Server* s, netsrv.Conn* c, char* data, int n)  { c->out.add("+OK\r\n", 5);  return 0; }              // < 0 closes it after the output
int onClose(netsrv.Server* s, netsrv.Conn* c)                    { freeState(c->user);  return 0; }                    // c->closeReason says why
netsrv.Server* s = new netsrv.Server();  s->onOpen = onOpen;  s->onData = onData;  s->onClose = onClose;
s->listen(7777);  s->listenTls(7778, cfg);  s->addUdp(7779);  s->onDatagram = ...;   s->run();      // or  for (;;) s->poll(50);
```

| Setting | Default | Meaning |
|---|---|---|
| `maxConns` | 1000 (the most) | connections; more are closed at once (`stats->rejected`) |
| `maxPerIp` | 0 (off) | connections from one address |
| `maxOut` | 1 MiB | bytes queued for one connection (`c->out.max`): a client that does not read is cut off (`R_EVICTED`) instead of growing the queue |
| `handshakeTimeoutMs`, `idleTimeoutMs`, `lingerMs` | 5000, 0 (off), 1000 | TLS handshake time, silence (nothing received), the time a closing connection reads away what the peer still sends |
| `stallTimeoutMs` | 30000 (0: off) | a connection that has output waiting and has not been able to send one byte for this long is cut off (`R_EVICTED`): a peer that does not read, or a wedged TCP connection |

**Backpressure.** `s->pause(c, resumeBelow)` (call it from `onData`) stops reading from a connection (and delivering what TLS has decrypted already) until its output queue is down to `resumeBelow` bytes; then `s->onResume(server, conn)` runs, and it may pause again. `redisd` uses it so that a client
that pipelines commands with big replies is served as fast as it reads, instead of being cut off.
**Descriptors.** `maxConns` is not tied to the limit of file descriptors (`ulimit -n`): keep it below that limit minus what the program has open. When `accept()` fails for lack of descriptors or memory the listener rests for 50 ms and then tries again (`stats->acceptFailures`): before, it spun at 100% processor time as
long as the descriptors were gone. The server recovers when connections close (`tests/net2.sh` checks both with `ulimit -n 30`).

`close(c)` sends what is queued, says goodbye (TLS close_notify, FIN) and reads away the peer's remaining bytes for `lingerMs` (so the last bytes are not lost to a reset); `kill(c)` drops it at once. `onClose` runs
exactly once for every connection that `onOpen` saw. Conn objects, buffers and TLS sessions are reused. `killAll()` drops every connection, `shutdown()` everything.

## MQTT: `mqtt` and `mqttd`

```c
import mqtt;
mqtt.Client* c = mqtt.connect("mqtt://user:secret@broker.example.org:1883/");      // mqtts:// = TLS (certificate checked); null: mqtt.error()
c->subscribeWait("sensors/+/temp", 1, 3000);                                        // the granted QoS (0..2), 128 refused, -1 time out
c->publishWait("sensors/kitchen/temp", "21.5", 4, 1, false, 3000);                  // QoS 1: returns when the PUBACK is there
mqtt.Message* m = c->waitMessage(5000);  if (m != null) { println(m->topic); println(m->payload); m->dispose(); }
c->disconnect();  c->dispose();
```

**Client.** CONNECT with clean or persistent session, will (topic, payload, QoS, retain), user name and password, keep-alive (a PINGREQ after three quarters of the interval, a dead connection when the PINGRESP does not come), TLS.
PUBLISH with QoS 0, 1 and 2: the sender keeps every QoS 1 / 2 message until PUBACK / PUBCOMP, resends it with DUP (and the PUBREL of a message that reached PUBREC) after a reconnect with a persistent
session, and sends it again as a new message when the broker has no session (the messages that already reached PUBREC count as delivered); the receiver delivers a QoS 2 message once (it remembers the packet identifier until PUBREL).
SUBSCRIBE / UNSUBSCRIBE with the filters `+` and `#`, the SUBACK return codes (128: refused; the filter is then not remembered), invalid filters and topics are refused before anything is sent.
Subscriptions are repeated after a reconnect that did not keep the session. Two ways to use it:

* **blocking**: `publishWait`, `subscribeWait`, `unsubscribeWait`, `waitMessage`, `flushAll`;
* **non-blocking**: `publish` returns a token at once (the message waits in a queue while the client is offline or the window is full), `poll(ms)` serves the connection (reads, answers, pings, reconnects) for at most `ms`,
  `next()` takes a received message, or `c->onMessage = fn` (`fn(client, topic, payload, length, qos, retain)`, the payload is valid during the call and followed by a 0 byte), `onConnect`, `onDisconnect`, `onPublished(client, token)`.

`Options` (pass to `mqtt.newClient(host, port, options)` or `mqtt.connectWith(url, options)`; the client works on its own copy): `clientId` (empty: a random one, needs `cleanSession`), `cleanSession`, `keepAliveSec` (60), `username`, `password`, `willTopic`, `willPayload`, `willQos`,
`willRetain`, `useTls`, `verify`, `connectTimeoutMs` (5000: TCP, TLS and CONNACK each), `maxPacket` (1 MiB), `maxInflight` (20, at most 1024), `maxQueued` (1000 messages) and `maxQueuedBytes` (8 MiB) for what waits to be sent, `maxIncoming` (1000: more received
messages than that, when nobody calls `next()`, are dropped and counted in `dropped`), `maxOut` (4 MiB), `autoReconnect` (false), `reconnectMinMs` / `reconnectMaxMs` (500, 30000: the pause doubles). **Connecting blocks** for the TCP connection, the TLS handshake and the CONNACK
(each at most `connectTimeoutMs`), also when `poll` reconnects.

**The engine** (`begin(now)`, `feed(bytes, n)`, `outData()` / `outPending()` / `outConsumed(n)`, `tick(now)`, `lost(reason)`) has no sockets and no clock of its own: the tests drive it with a clock they set and with packets they lose on purpose.

**The codec** is usable alone: `Parser` (bytes in, `Packet` out, pointers into its buffer; limit `maxPacket` checked at the header; reserved types, wrong flags for every type, QoS 3, DUP on QoS 0, packet identifier 0, bad CONNECT flags,
strings that are not UTF-8 (overlong forms, surrogates, NUL), wildcards in topic names, invalid filters, lengths that lie: all are errors and the parser stays failed), `putConnect putConnack putPublish putAck putSubscribe putUnsubscribe putSuback putEmpty` (each writes a whole packet or nothing),
`topicMatches(filter, topic)` (`$`-topics are not matched by a filter that starts with `+` or `#`), `validTopicFilter`, `validTopicName`, `validUtf8`.

```c
import mqttd;
mqttd.Server* s = mqttd.newServer();
s->broker->addUser("alice", "secret");  s->broker->allowAnonymous = false;           // or s->broker->authHook / aclHook
if (!s->listen(1883)) { ... }                                                       // s->listenTls(8883, cfg); port 0 picks a free one (s->port)
s->run();                                                                           // or for (;;) { s->poll(50); }
```

**Broker.** One loop for all clients (`netsrv`). CONNACK codes 1 (protocol level other than 4: MQTT 3.1 and 5 are refused), 2 (empty client id with a persistent session), 3 (too many clients), 4, 5 (credentials); session present; a second connection with the same client id takes over
(its will is sent); persistent sessions keep subscriptions and the QoS 1 / 2 messages for an offline client (QoS 0 is not kept) and resend what is in flight with DUP; a topic tree with wildcards, one copy per client for overlapping subscriptions
(the highest QoS); QoS downgrade to the subscription's QoS; retained messages (an empty payload removes one; the retain flag is off for live deliveries and on for the ones sent at SUBSCRIBE); will messages (when the connection ends without DISCONNECT, on keep-alive time out
(1.5 times the interval), on a protocol violation, on takeover). **A will is held to the rules of a PUBLISH, checked at CONNECT**: a will topic that the ACL refuses (`aclHook` with op 1), that starts with `$`, is longer than `maxTopicLength` or deeper than `maxLevels` gets CONNACK 5
(and the connection that holds the client id is left alone); before, a will was a way round the ACL, round the ban on `$` topics (a client could overwrite the retained `$SYS/broker/version`) and round the topic limits (retained wills of 60,000 bytes). `$SYS/broker/clients/connected`, `clients/total`, `clients/disconnected` (published at once when they change), and every `sysIntervalMs` (10 s) messages received / sent / dropped, subscriptions, retained messages, uptime and version (all
retained; `sysIntervalMs = 0` turns `$SYS` off); clients cannot publish to `$` topics, neither with PUBLISH nor with a will.
**Retained messages at SUBSCRIBE** are all delivered, however many there are: they wait on a list (topics only, the message is looked up when it is sent, so a message that was replaced is sent in its new form and one that was removed is not sent) and go out as the client's window and output queue have room; this list is not
subject to `maxQueue` / `maxQueueBytes` (it was: a QoS 1 subscriber got 1020 of 3000 retained messages). It is bounded by `maxRetained` entries per client and by `maxQueuedTotal` for all clients together (what does not fit is dropped and counted). A client that disconnects loses what had not been sent yet (it subscribes again).
**Sessions belong to their user.** A stored session (online or offline) can only be resumed or taken over by a connection with the same user name (`bindSessions`, default on; both without a user name count as the same): another user gets CONNACK 5 and the session is left as it is. (Without this, a second user with valid credentials who knew a client id received
the first user's subscriptions and queued messages.) With `bindSessions = false` the MQTT 3.1.1 behaviour is back: whoever authenticates takes the session. A client that changes its user name needs a new client id. This is also a way to squat on a client id: with `allowAnonymous = true` an anonymous client can keep a
persistent session id from its owner: turn anonymous access off when it matters. When `maxSessions` is reached the offline session of the **same user** that has been gone longest is dropped first, and only if that user has none the one that has been gone longest of all: a user (or the anonymous ones together) cannot push out the sessions of the others by making many new ones, as long as it has sessions of its own; anonymous clients all
count as one user.

| Limit (setting of `broker`) | Default | What happens over it |
|---|---|---|
| `maxClients` | 1000 | CONNACK 3 |
| `maxPacket` | 1 MiB | the connection is closed at the header (nothing is buffered) |
| `maxInflight` | 20 (at most 256) | further QoS 1 / 2 messages wait in the client's queue |
| `maxQueue`, `maxQueueBytes` | 1000, 1 MiB | a message for a client (offline or slow) is dropped and counted (`stats->dropped`); `maxQueuedTotal` (32 MiB) for all clients together |
| `maxOut` | 4 MiB | bytes waiting for one socket: QoS 0 messages are dropped above half of it; a client that cannot take its acknowledgements is cut off |
| `maxSubsPerClient`, `maxSubscriptions` | 200, 20000 | SUBACK 128 |
| `maxRetained`, `maxRetainedBytes` | 10000, 16 MiB | a retained message is not stored (it is still delivered to the live subscribers; `stats->retainedRefused`); a retained value that would be replaced by a message that does not fit is **removed** (no retained message is better than an out of date one). The bytes count payload, topic and tree nodes (pessimistically); the broker's own `$` topics are exempt. Before this limit existed 300 retained messages of 1 MiB made 300 MB, and the count limit alone allowed 10 GB. |
| `maxSessions` | 1000 | the offline persistent session that has been gone longest (of the same user first, see above) is dropped (also `sessionExpirySec`) |
| `maxLevels`, `maxTopicLength`, `maxClientIdLength` | 64, 1024, 256 | refused subscription, dropped publish, CONNACK 2 |
| `connectTimeoutMs` | 10000 | a connection that sends no CONNECT is closed |

The broker core (`mqttd.Broker`) has no sockets either: `open(now)` makes a `Peer`, `feed(peer, bytes, n)` runs them, `peer->out` is what to send, `tick(now)` does the timers (`setClock` sets a fake clock), `closed(peer)` releases it.
Not supported: MQTT 5, the old 3.1 (answered with CONNACK 1), WebSocket transport, bridges, persistence on disk, shared subscriptions, message expiry.

## Redis: `redis` and `redisd`

```c
import redis;
redis.Client* c = redis.connect("redis://:password@localhost:6379/2");              // rediss:// = TLS; /2 = SELECT 2; null: redis.error()
c->set("greeting", "hello");  char* v = c->get("greeting");  println(v);  free(v);    // null when the key does not exist
redis.Reply* r = c->call("LRANGE", "mylist", "0", "-1");                           // any command, up to 6 arguments (callv for more and for binary data)
if (r->type == redis.T_ARRAY) for (int i = 0; i < r->count; i++) println(r->elems[i]->str);
r->dispose();                                                                      // every Reply you get is yours
```

**Client.** All RESP2 reply types (`T_STATUS T_ERROR T_INT T_BULK T_ARRAY T_NIL T_NILARRAY`; bulk strings are binary safe: `str`, `len`, and a 0 byte behind them). An error reply is a `Reply` of type `T_ERROR`; `call` returns null only
when the connection failed or timed out (`c->error`). Helpers: strings (`set setEx setBin get getBin incr decr incrBy append strLength del exists expire ttl keys mget mset dbsize flushAll info echo publish`), lists (`lpush rpush lpop rpop llen lrange`),
hashes (`hset hget hgetall hdel`), sets (`sadd srem smembers sismember`), sorted sets (`zadd zrange zscore zrem zcard`; scores as text). `redis.pipeline(c)` makes a `Pipeline`: `add(...)` as often as you like,
`run()` (one write, then all replies), `reply(i)`. `c->multi()`, `c->call(...)` (answers "QUEUED"), `c->exec()` (the array of the replies), `c->discard()`. `redis.pubsub(c)` makes a `PubSub` on a connection of its own (RESP2 allows nothing else on a subscribed connection):
`subscribe psubscribe unsubscribe punsubscribe ping`, `next(timeoutMs)` returns a `PubMessage` (channel, pattern, data) or null, and reconnects and subscribes again after a connection loss. AUTH (`redis://:pw@host`, or `redis://user:pw@host`) and SELECT are repeated after a reconnect.
`Options`: `timeoutMs` for every reply (5000; the connection is closed on a time out because the reply could still arrive), `connectTimeoutMs`, `autoReconnect` (true: the next call connects again), `maxBulk` (64 MiB), `maxOut` (64 MiB), `useTls`, `verify`, `db`, `password`, `username`.
**A command whose reply did not come is not sent again after a reconnect** (Redis commands are not idempotent in general).

**The codec.** `ReplyParser` (replies: nothing is buffered except the reply being built; a bulk string grows as its bytes arrive; `maxBulk` 64 MiB, `maxElements` 1,000,000, `maxDepth` 32, `maxTotal` 128 MiB, a line of 64 KiB; every length is checked before memory is taken; `maxReady` makes `feed`
stop so that a flood of messages is not buffered), `CmdParser` (requests as a server reads them: RESP arrays of bulk strings and inline commands with quotes; `maxBulk` 16 MiB, `maxArgs` 1024, `maxCommand` 32 MiB, `maxInline` 64 KiB), writers `putCommand putStatus putError putInt putBulk putNil putNilArray putArray`
(CR and LF in a status or error line become blanks: no reply injection). Malformed input is an error code and the parser stays failed.

```c
import redisd;
redisd.Server* s = redisd.newServer();  s->store->requirepass = "secret";  s->listen(6379);  s->run();
```

**Server.** `PING ECHO QUIT AUTH SELECT` (16 databases), `GET SET` (`EX PX NX XX KEEPTTL GET`) `SETNX SETEX PSETEX GETSET DEL EXISTS EXPIRE PEXPIRE` (`NX XX GT LT`) `TTL PTTL PERSIST INCR DECR INCRBY DECRBY APPEND STRLEN MGET MSET KEYS` (glob with `* ? [a-z] [^a] \x`, no exponential backtracking) `TYPE RENAME`,
`LPUSH RPUSH LPOP RPOP` (with a count) `LRANGE LLEN LINDEX`, `HSET HGET HGETALL HDEL HLEN HEXISTS HKEYS HVALS`, `SADD SREM SMEMBERS SISMEMBER SCARD`, `ZADD` (`NX XX CH`) `ZRANGE` (`WITHSCORES`) `ZSCORE ZREM ZCARD ZRANK` (scores are doubles: `-inf`, `1e+22`, `0.1`),
`PUBLISH SUBSCRIBE UNSUBSCRIBE PSUBSCRIBE PUNSUBSCRIBE` (subscribe mode as in Redis: only those, `PING` and `QUIT` are allowed), `MULTI EXEC DISCARD` (errors while queueing make `EXEC` answer `-EXECABORT`, errors inside `EXEC` are elements of the result),
`FLUSHALL FLUSHDB DBSIZE INFO COMMAND CLIENT`. Errors read like Redis' (`-WRONGTYPE ...`, `-ERR wrong number of arguments for 'get' command`, `-NOAUTH`, `-OOM`, ...). Keys expire lazily and by a sweep in the loop; a key that expired is still counted by `DBSIZE` until it is removed, as in Redis.

| Limit | Default | What happens over it |
|---|---|---|
| `maxBulk`, `maxArgs`, `maxCommand`, `maxInline` (of `store`) | 16 MiB, 1024, 32 MiB, 64 KiB | `-ERR Protocol error: ...` and the connection is closed (a bulk length is judged at its header: nothing is buffered) |
| `maxQueued` (commands after MULTI) | 1000 | `-ERR too many commands in the transaction`, then `EXEC` aborts |
| `maxSubs` (channels and patterns of a client) | 1000 | `-ERR too many subscriptions` |
| `maxMemory` | 64 MiB of data (see below) | write commands answer `-OOM`; reads and deletes still work |
| `net->maxConns`, `net->maxPerIp`, `net->idleTimeoutMs` | 1000, 0, 0 | closed at once / closed |
| `store->outHigh` | 1 MiB | **backpressure**: while this many bytes of replies are unsent, the client's next command (and the bytes behind it) wait; nothing more is read from the connection until half of it is sent (`0`: off) |
| `net->stallTimeoutMs` | 30 s | a client that has replies waiting and takes not one byte for this long is cut off |
| `net->maxOut` | 16 MiB | bytes waiting for a client because messages are **pushed** to it (pub/sub): a subscriber that does not read its messages is cut off. It does not limit replies |
| `store->maxReply` | 0 = automatic (`outHigh + maxMemory + maxBulk + 64 KiB`) | the most one command may put into a client's output queue: a command that goes beyond what the data could ever fill (`MGET` of the same 16 MiB key a thousand times) cuts the client off |

**Replies and clients that read slowly.** A reply is built whole, so one command can queue as many bytes as its reply has (a `GET` of a 16 MiB value, an `LRANGE` of a big list: up to `maxMemory`). A client that pipelines commands (4 `GET`s of a 10 MB value in one write) is not cut off: after each command the server looks at
`outHigh`, and while that much is unsent the commands wait in the server (at most one read of 16 KB) and the socket is not read. Before, the 16 MiB limit was applied to the replies of one burst, so clients that read normally were cut off (and a value of exactly `maxBulk` could be stored but not read). The worst case of memory
is `maxConns` times `maxCommand` for requests (a command is judged at its header, but a client can still send 32 MiB of arguments), and for replies `maxConns` times (`outHigh` plus the biggest reply a client can ask for, up to `maxReply`): 1000 clients that each `GET` a 16 MiB value and then do not read hold 16 GB until
`stallTimeoutMs` has passed. Lower `maxConns`, `maxBulk` and `maxMemory` for a small machine (AOS needs 128 MB of RAM at least).

**`maxMemory` counts heap blocks.** The allocator rounds every block up to a power of two (16 bytes at least) and adds 16 bytes, and the accounting does the same (a key, its value, an entry of a list, hash or set, the blocks of a sorted set, queued `MULTI` commands, plus a share of the hash tables). Measured with 64 MiB: the resident size of the process grows to between 64 and 80 MB
(the free lists keep the old, smaller blocks when a list or a table doubles); before, it reached 207 MB with the same limit because only the bytes of the data were counted. The output queues of the clients, the parser buffers and the connection objects are not counted (see above for the first). The limit is checked before a write command: one command can pass it (up to `maxCommand` bytes).
**Speed.** `APPEND` writes in place into the block of the string (it copies when the block is full, and then the next one is twice as big: n appends cost O(n); copying the whole value each time made 20,000 appends of 100 bytes take 8 s). Sorted sets keep their members in blocks of 256: an insert or a removal moves at most one block
(100,000 random `ZADD`s took 6.8 s with a plain sorted array and take well under a second now); `ZRANK` and `ZRANGE` add up the sizes of the blocks before the member (O(n / 256)).

**Where it differs from Redis 7.0.15** (checked with a real `redis-server` on the development machine: `tests/net2.sh` runs the redis client module against both and compares the output, and about 80,000 random commands (four runs of 20,000, differences that come from the two servers expiring a key at slightly different moments aside) and several hundred targeted cases were compared reply by reply). Scores are written as the shortest text that reads back (`1.5e-07`; Redis 7.0 writes 17 digits, `1.4999999999999999e-07`; Redis 7.2 and later write the short form, too).
The order of `KEYS`, `SMEMBERS`, `HKEYS`, `HGETALL` is the order of the hash table (unspecified in Redis as well). The expiry sweep looks at 20 keys per database every 100 ms (Redis: more, adaptive), so a key that has expired can be counted by `DBSIZE` a little longer. `INFO` has a few fields only. `COMMAND` and `CLIENT` answer an empty array / `OK`.
`SET ... GET` and `EXPIRE ... NX|XX|GT|LT` are supported as in Redis 7; `EXPIREAT`, `GETDEL`, `GETEX`, `SETRANGE`, `GETRANGE`, `SCAN`, `OBJECT` and the other commands that are not listed are not (`-ERR unknown command`). Numbers must be written canonically (`07`, `-0` and `+5` are not integers, as in Redis).
Not supported: persistence, replication, scripting, streams, `WATCH`, RESP3, blocking commands, cluster.
The core (`store->open()`, `c->feed(bytes, n)`, `c->out`, `store->setClock(ms)`) has no sockets: the tests check the bytes of the replies. A client with `c->paused` set has replies that nobody took: empty `c->out` (send it) and call `store->resume(c)`; `netsrv` does that through `onResume`.

## syslog: `syslog` and `syslogd`

```c
import syslog;
char buf[2048];
int n = syslog.build5424(&buf[0], 2048, syslog.FAC_AUTH, syslog.SEV_WARNING, datetime.now(), 0, "myhost", "sshd", "4711", "AUTHFAIL", "-", "login failed", 12);
//  <36>1 2026-10-11T22:14:15.000Z myhost sshd 4711 AUTHFAIL - login failed
syslog.Message m;  if (syslog.parse(&buf[0], n, &m, datetime.now()) == 0) { println(m.app); }          // RFC 5424, RFC 3164 or a text without <PRI>

syslog.Sender* s = syslog.newSender("tls://logs.example.org:6514");           // udp://host[:514]  tcp://host[:514]  tls://host[:6514]
s->setApp("myapp", "42");  s->facility = syslog.FAC_LOCAL0;
s->info("service started");  s->error("disk almost full");  s->flush(2000);  s->dispose();
```

**Messages.** Priority = facility * 8 + severity (`FAC_*`, `SEV_*`, `facilityName`, `parseFacility` ...). `build5424` and `build3164` write one message into a buffer (the length, or -1): header fields with blanks or control characters get `_`, empty ones become `-`, long ones are cut to the RFC's limits
(host 255, app 48, procid 128, msgid 32). `parse` reads either format and finds out which: RFC 5424 (timestamp with fraction and offset checked down to the calendar: February 30, hour 24 and offset 24:00 are errors; structured data checked element by element; the UTF-8 BOM) or RFC 3164
(`Mmm dd hh:mm:ss host tag[pid]: text`; the year is guessed from the clock you pass; a word that looks like a tag is not taken for a host) or a text without `<PRI>` (facility user, severity notice). It never reads beyond the length you give; the fields are copies and `msg`, `sd` point into your text. Errors: `E_PRI E_VERSION E_TIMESTAMP E_FIELD E_SD E_EMPTY E_TRUNCATED`.
`buildSd` writes structured data with the escaping of `"`, `\` and `]` and checks names; `sdParam` finds a parameter and unescapes it.

**Sender.** UDP: one datagram per message, cut at 2048 bytes. TCP and TLS: framing is octet counting (RFC 6587 and RFC 5425, the default) or newline (control characters in the text become blanks). The connection is made lazily (`connectTimeoutMs`, default 1000) and at most once per `retryIntervalMs` (2000): a collector that is down does not
slow the caller down. What cannot be sent yet is queued (`maxQueueBytes` 256 KiB, `maxQueueMessages` 1000; more is dropped and counted in `dropped`). A frame is only taken out of the queue when all of it is written: after a lost connection it is sent again completely (a frame that was cut in the middle is never continued on the new connection).
A collector that closed the connection is noticed at the next send. `sent`, `dropped`, `reconnects`, `errors` are counters; `s->now` fixes the clock of the timestamps.

```c
import syslogd;
syslogd.Server* s = syslogd.newServer();
s->listenUdp(514);  s->listenTcp(514);                                              // s->listenTls(6514, cfg); port 0 picks a free one (s->udpPort, s->tcpPort)
syslogd.Filter* f = syslogd.newFilter();  f->setSeverityUpTo(syslog.SEV_WARNING);  f->program = "sshd";  f->setPattern("Failed|refused");
s->collector->addFile(f, "/var/log/auth-problems.log", 1048576, 5);                // rotates at 1 MiB, keeps .1 ... .5
s->collector->addForward(null, "tls://central.example.org:6514");                   // everything goes on
s->run();                                                                           // or: for (;;) { s->poll(50); ... s->collector->ring->line(0) ... }
```

**Collector.** UDP: one message per datagram (a trailing line end is not part of it). TCP and TLS: octet counting and newline framing are told apart for every message (a digit starts an octet count, `<` or anything else a line; a line that starts with digits but has no blank after them is a line);
an octet count that is not a number, longer than 6 digits or over `maxMessage` (16 KiB), and a line that does not end within `maxMessage`, close the connection (`stats->framingErrors`). A message that cannot be parsed is counted and dropped (`keepMalformed` stores it as user.notice); a missing timestamp is replaced by the time of reception, a missing host by the address of the sender.
**Filters** (`Filter`): facilities and severities as bit masks (`addFacility`, `addSeverity`, `setSeverityUpTo(n)`: n and worse), `program` and `host` globs (`*`, `?`), a regular expression over the text (`setPattern`, the `regex` module; one search stops after `regexSteps` steps, 1,000,000 by default, so that a pattern like `(a+)+b` cannot be used to hang the collector with a line of a's: such a message counts as "does not match" and `regexExceeded` counts it), `invert`. `collector->dropFilter` drops what matches it.
**Routes**: `addFile` (a text file, size based rotation with kept files `path.1` ... `path.N`, a file that cannot be opened is counted and tried again after `retryMs`, lines are lost meanwhile), `addRing` (a bounded in-memory ring: lines and bytes), `addForward` (a `syslog.Sender`; the original text is passed on; forwarding a collector to itself loops: do not).
The default ring `collector->ring` takes everything that is not dropped; a message goes to every route whose filter matches.
**Lines** (`lineFormat`): `LINE_TRADITIONAL` "Oct 11 22:14:15 host app[pid]: text", `LINE_DETAIL` "2003-10-11T22:14:15Z host auth.warning app[pid]: text", `LINE_RAW`. Control characters in a message (line feed, carriage return, ESC, NUL ...) are written as `#ooo` (octal): a message cannot forge a log line or a terminal sequence.
File names are always yours: nothing from a message becomes part of a path. On AOS file names are limited to 55 characters: `path.N` must fit.
Not supported: reading `/dev/log` or the journal, RELP, TLS client certificates, file names built from message fields.

## Tests (MQTT, Redis, syslog)

`tests/t371` to `t393` run in the normal suite on every target (client and server in one thread from `net.setIdleHook`, ephemeral ports, nothing depends on time except small time outs; the tests wait for conditions and for quiet instead of counting polls and assume nothing about the size of socket buffers or how many connections a listener queues, because AOS has 64 KiB and 16). They are started from the root of the repository (`tests/run.sh` does that: `t388` and `t389` write files below `build/tests/`):

| Test | What |
|---|---|
| `t371` `t372` | MQTT codec byte for byte (every packet type; the remaining length table; the topic matching tables of the specification), malformed packets (every error code), a fuzz run |
| `t373` `t374` | client against broker: every QoS, wildcards, retained, overlapping subscriptions, QoS downgrade, ACL, order under a small window, callbacks; the QoS 1 and 2 state machines with a packet lost at every step (both directions, both sides reconnect) |
| `t375` `t376` | broker core: sessions, wills, takeover, keep-alive with a fake clock, queue caps, `$SYS`; the broker on sockets against garbage, announced sizes of 256 MB, silent connections, clients that never read, floods, 60 clients at once |
| `t377` `t378` `t379` | client resilience (URLs, reconnect and resubscribe, restart of the broker, misbehaving brokers, limits), MQTT over TLS, strict memory test |
| `t380` `t381` | RESP examples byte for byte, every malformed input, limits; every command of the server with the exact bytes of its reply (380 checks) |
| `t382` `t383` `t384` `t385` | client against server (all helpers, binary values of 1 MB, pipelines, transactions, pub/sub, AUTH, SELECT, reconnect, time outs, garbage replies), the server against hostile peers, TLS, strict memory test |
| `t386` `t387` | syslog formats (the RFC examples byte for byte, timestamps, structured data, every malformed message, a round trip with random fields, a fuzz run); sender against collector over UDP, TCP (both framings), TLS, reconnect, a frame cut in the middle, raw TCP framing cases |
| `t388` `t389` | filters, ring, files and rotation, forwarding, floods; strict memory test |
| `t390` | `net.waitWritable` and `netio.Link` run the idle hook while a socket is full (plain and TLS), the time limit of `sendAll`, `waitWritable(h, 0)` does not run the hook |
| `t391` | mqttd against the review findings: wills (ACL, `$`, topic limits), `maxRetainedBytes`, all retained messages of a SUBSCRIBE (3000 messages, 3 MB of them, a removed or replaced one), stored sessions and their owners, eviction order |
| `t392` | redisd against the review findings: the replies of the corrected and new commands (the bytes were taken from Redis 7.0.15), `HKEYS` / `HVALS`, memory accounting, `APPEND` and `ZADD` speed (compared with the time of plain `SET`s: no fixed time limits), sorted set blocks against a model, backpressure in the core, over a plain and a TLS socket |
| `t393` | the step limit of a regular expression in a syslogd filter (a catastrophic pattern on a line of a's is stopped, counted, and does not hold up the other messages; ordinary patterns on 16000 byte messages are not affected) |

**On AOS** the networking tests run in the boot test `net` of the AOS repository (the same programs, compiled by `/bin/ac` inside the system in QEMU, output compared with the `.out` files byte for byte). That test used to pick the tests by a file name pattern that stopped at `t370`; the branch `ws-net2-aos` of the AOS repository widens it to `t340` to `t399`, so `tests/boot_test.py net` includes `t371` to `t393`.
Before the fixes of the review, 5 of the first 19 of these tests failed there (`t376`, `t382`, `t383`, `t384`, `t387`: the idle hook, a connection backlog of 16 and a 64 KiB socket buffer); now **all 54 networking tests (`t340` to `t393`) print exactly what they print on Linux** (211 s in all in the boot test; the slowest are `t383` with 17 s and `t392` with 15 s). The three demo servers `examples/mqttd_demo.a`, `redisd_demo.a` and `syslogd_demo.a` are installed in `/usr/share/a/examples/net` of the system image, and the boot test `compiler` compiles them there (it compiles every installed example).
What was **not** run on AOS: the servers as programs that other machines talk to (the tests run client and server in one process over the loopback interface), TLS with a real certificate authority outside the tests, and anything for hours (the memory tests compare the heap before and after 10 operations, they do not run long).
What the strict memory tests do: they compare `__heap_pos` (what `new`, `alloc` and `strdup` use up and never give back) before and after 10 operations that followed a warm-up, and demand that it did not move at all. They found real leaks while the modules were written
(for example the score text of a sorted set came from `dtostr`, which takes 40 bytes of never-freed heap per call). What is **not** freed: the cryptography inside a TLS handshake (about 20 KB per handshake, see Memory above, and the warning at the top of this part: it applies to every TLS listener, `mqttd`, `redisd` and `syslogd` alike, and to a TLS client that connects again and again), objects made with `new` (the settings objects `Filter`, `Ring`, `FileSink`, `Options`, which are meant to live as long as the program).

## Limits: what these modules do not do

* **TLS speed.** As for `wshub`: a handshake costs about 150 ms of processor time and `netsrv` serves one thread; for many new TLS connections per second put a terminating proxy in front.
* **IPv4 only**, like `net`. **No IPv6, no proxies, no client certificates.**
* **Servers are for small installations and tests.** `mqttd`, `redisd` and `syslogd` keep everything in memory and have no persistence; they are not a replacement for Mosquitto, Redis or rsyslog under heavy load (the arithmetic is software, a request costs microseconds to milliseconds on the targets).
* **Connecting blocks.** `mqtt.connect`, a reconnect inside `poll`, `redis` commands on a closed connection and the first send of a TCP `syslog.Sender` block up to the connect time out (the TLS handshake counts again): a program with its own loop should connect where blocking is fine.
* **One thread.** The clients are not thread safe; one `netsrv.Server` serves all its sockets from the thread that calls `poll`.
* **Memory worst cases are products of limits** (clients times queue size): the defaults suit a normal machine; lower them for AOS (128 MB) as the tables above say.
* **Interoperability** was checked by hand during development, with independent programs where the machine had them: `redis-cli` against `redisd` (commands of every type, `--pipe`, `SUBSCRIBE` / `PUBLISH`, `--raw`, error replies), util-linux `logger` against `syslogd` (UDP and TCP, RFC 3164 and RFC 5424 with structured data), `nc` as the receiver of the `syslog` sender (the bytes of datagrams and of both TCP framings) and a hand written Python raw-socket MQTT client against `mqttd` (connect, subscribe, QoS 0 / 1 / 2, retained, will, ping, a malformed packet). `tests/net2.sh` repeats these checks (Linux; needs python3; `redis-cli`, `redis-server` and `logger` are used when they are installed; it is not part of `make test`; the raw MQTT client is `tests/net2_mqtt.py`) and adds: the `redis` client module run against a real `redis-server` and against `redisd` (the program `tests/net2_redis_client.a`; the two outputs must be identical; checked with Redis 7.0.15), the descriptor limit (`tests/net2_fdlimit.py`: with `ulimit -n 30` a server must not spin and must serve again afterwards) and the UDP sender with a name that does not resolve (`tests/net2_udpretry.a`). `redisd` was also compared with Redis 7.0.15 reply by reply with random commands over strings, lists, hashes, sets, sorted sets, expiry, `MULTI`, pub/sub (the reviewers' script is not part of the repository; the differences that remain are the ones listed under "Where it differs"). There is no MQTT client or broker from another vendor on the development machine, so MQTT was not checked against mosquitto or paho; the tests of the modules use them against each other and byte-exact examples from the specifications.
