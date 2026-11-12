# HTTP, WebSocket and TLS

The protocols of the web are all in the standard library, written in A: `http` for requests and responses (client and server),
`websocket` for two-way messages, and `tls` for encryption, which makes `https://` work. They are built on the sockets of
[the networking chapter](#chap-networking), so the same ideas apply: handles, time limits, checking every result.

This chapter teaches the basics: the plain `http` module, and the handshake and the frames of `websocket` down to the bytes. The next
chapter, [WebSocket, server-sent events, an HTTP toolkit and JSON-RPC](#chap-web-services), builds on it with the rest of
`websocket` (compression, close codes, streaming, `wss://`), a server for many clients (`wshub`), event streams (`sse`), a bigger HTTP
toolkit (`httpx`) and `jsonrpc`.

In this chapter:

* an HTTP client and server: requests, headers, forms, redirects, compressed bodies, files;
* WebSocket: the handshake, the frame format, messages, ping and close;
* TLS 1.3: certificates, trust, and how to encrypt a socket;
* what each module does **not** do.

## Which module do I use?

| I want to ... | Use |
|---|---|
| download a page or call a web API, `http://` or `https://` | `http.get`, `http.post`, `http.request` |
| save a download to a file | `http.download` |
| answer HTTP requests | `http.serve` (fixed port) or your own accept loop with `http.readRequest` / `http.respond` |
| serve a directory of files | `http.serveStatic`, `http.serveFile` |
| exchange messages with a browser or a peer, in both directions, over one connection | `websocket` (`ws://` and `wss://`) |
| encrypt a connection of my own protocol | `tls.wrap` (client) and `tls.wrapServer` (server) |
| serve over https | `http.serveTls`, `http.serveStaticTls` |
| check or inspect a certificate | `x509` |
| drive TLS from an event loop, with no sockets inside | `tls.client` / `tls.accept` and `feed` / `outData` |
| serve many WebSocket clients from one thread, push events to browsers, call functions over JSON, or get cookies, retries, a router and middleware | `wshub`, `sse`, `jsonrpc`, `httpx`: [the next chapter](#chap-web-services) |

## HTTP

HTTP is a request and a response, both made of text lines. A request is a line with a method and a path, some header lines, an empty
line, and an optional body. A response is a status line, header lines, an empty line and a body. The `http` module speaks HTTP/1.1,
with one request per connection (it always sends `Connection: close`).

### What it looks like on the wire

Everything else in this chapter is easier to follow when you have seen the bytes once. The sample uses the first half of the client
(`http.sendRequest`) and reads the request with plain `net` calls, with the line ends made visible:

{{sample http/wire_format}}

**What to notice.**

* The request line (`POST /items?id=7 HTTP/1.1`), then `Host`, `Connection`, `User-Agent` and your own header, then `Content-Length`
  and an empty line, then the body. Lines end in `\r\n`.
* The response has `Content-Length`, which tells the client where the body ends. Other ways to end a body are shown below.
* `http.sendRequest` and `http.readResponse` are the two halves of `http.request`. Use them when you made the connection yourself,
  for example to talk to a server on a socket you already have.

### URLs

`http.parseUrl` splits `scheme://host:port/path?query`. The port defaults to 80 for `http` and 443 for `https`, an empty path becomes
`/`, and the query stays in the path. The scheme is turned to lower case. Characters that have a meaning in a URL must be escaped: `encoding.urlEncode` and
`encoding.urlDecode` ([API reference of encoding](#api-encoding)) do that (a `+` in a form value means a space).

{{sample http/url_parse}}

**What to notice.** Only absolute `http://` and `https://` URLs are accepted; anything else gives `false`. A host name is kept as
typed (case included). **IPv6 literals such as `http://[::1]/` are not supported** (sockets are IPv4 only): `parseUrl` splits such a URL wrongly, so a request to it fails with `cannot connect`.

### A client and a server

`http.get(url)`, `http.post(url, body, contentType)` and `http.request(method, url, extraHeaders, body, bodyLength)` return an
`http.Response` (`status`, `headers`, `body`, `bodyLen`, `header(name)`) or `null`. The server side is `http.readRequest(client, q)`
to parse a request from an accepted socket into an `http.Request` and `http.respond(client, status, contentType, body)` to answer it.

`http.serve(port, handler, count)` is the accept loop for you, but it listens on a port you name and cannot tell you a port the
system picked. The samples therefore write the same loop themselves, on a listening socket made with port `0`, in a child process.

{{sample http/get_post}}

**What to notice.**

* The handler `void handler(http.Request* q, int client)` is exactly the kind of function `http.serve` calls. `q->method`, `q->path`,
  `q->query` (still URL-encoded), `q->body` and `q->bodyLen` describe the request.
* The server accepts a request, answers it and closes the connection; there is no keep-alive. Each `http.get` is a new connection.
* `http.post` sends the body with `Content-Length`; `http.request` also lets you choose the method (`PUT` here) and add headers.

`http.download(url, path)` (not used in the sample) is a `GET` that writes the body to a file. It returns `200` when the file was
written, the HTTP status when that was not 200 (and then writes nothing), and `-1` when the request or the writing failed; the reason
is in `http.error()`.

### Routing and status codes

A handler decides by method and path. The status code is the first thing a client looks at: 2xx success, 3xx redirect, 4xx the
request was wrong, 5xx the server failed. `http.statusText(code)` gives the standard reason phrase.

{{sample http/server_router}}

**What to notice.**

* Always test the result of a request for `null` before you read `->status`; `http.error()` says what went wrong.
* The server keeps `count` in a global variable of its own process, so the `GET /items` after two posts reports `2 items`.
* `http.queryValue(q, "name", buf, max)` returns the URL-decoded value of a query parameter (`%20` became a space).
* `respond` writes `Content-Type`, `Content-Length`, `Connection` and `Server` headers. Headers beyond those, such as `Location`
  or `Cache-Control`, mean writing the response with `net.sendText` yourself (see the redirect sample).

### Query strings and forms

Parameters arrive either in the URL (`/who?name=Ada`) or in the body of a `POST` (`name=Ada&city=Zurich`, the format of an HTML
form). `queryValue` reads `q->query`; for a form body, copy the body there first, as the handler does.

{{sample http/forms}}

**What to notice.** `http.postForm(url, "a=1&b=2")` sends `application/x-www-form-urlencoded`; it expects the fields already
encoded. A parameter that is not there makes `queryValue` return `false`, so give every parameter a default. `q->query` holds 1024
bytes, so the handler copies a form body into it only when `q->bodyLen` is below 1000; a longer body would overflow it.

### Headers

Header names are not case sensitive. `q->header("name")` and `r->header("name")` return a copy of the value, or `null`. The
extra headers of `http.request` are raw text, one `Name: value\r\n` per header.

{{sample http/headers}}

**What to notice.** The server sees the client's `User-Agent` (`A-http/1.0`) and the `X-Token` we added. `respond` has no way to add
headers, so the handler builds the response head itself. `http.headerOf(raw, name, buf, max)` reads one value out of the raw header
block, which is what `->header()` does internally.

### Redirects

A `3xx` answer with a `Location` header sends the client elsewhere. `http.get` follows `301`, `302`, `303`, `307` and `308` (as a new
`GET`) up to five times, for absolute URLs and for paths that start with `/`. `http.request` follows nothing, which is what you want
when you need to see the redirect itself.

{{sample http/redirects}}

**What to notice.** A loop gives up with the error text `too many redirects`. A redirect to a relative path that does not start with
`/` (such as `next.html`) is returned to you as it is.

### How a response body ends

The client has to know where the body stops. `http.readResponse` understands the three ways a response can say it:

{{sample http/chunked}}

**What to notice.**

* With `Content-Length` the body is that many bytes; extra bytes after it are not read.
* With `Transfer-Encoding: chunked` the body comes in pieces, each preceded by its size in hexadecimal and ended by a zero-size chunk.
  A server uses it when it does not know the total length in advance. The client joins the pieces.
* With neither, the body runs until the server closes the connection (the HTTP/1.0 way).
* A `204 No Content` has no body. The client does not treat it specially: it reads "until the connection closes", which a server that
  honours `Connection: close` does at once.
* On the **server** side `readRequest` reads a body only when `Content-Length` is given; chunked request bodies are not decoded.

### Authentication

HTTP Basic authentication sends `user:password` in base64 in an `Authorization` header. It is not encryption: anyone who can see the
connection can read it, so use it only over https.

{{sample http/basic_auth}}

**What to notice.** `http.basicAuth(user, password)` returns the finished header line (with its `\r\n`), ready to pass as the
`extra` argument of `http.request`. The server answers `401` with `WWW-Authenticate` when the credentials are missing or wrong.

### Compression

`http.setCompression(true)` adds `Accept-Encoding: gzip, deflate` to every request. A `gzip` or `deflate` response is **always** unpacked by
the client, whether you asked for compression or not, so `r->body` is the plain text. On the server, `http.respondGzip` sends a body
compressed.

{{sample http/gzip}}

**What to notice.** The `Content-Length` header is the size on the wire (102 bytes), while `bodyLen` is the size after unpacking
(4500 bytes). The server must decide by the client's `Accept-Encoding` header whether it may compress.

### Serving files

`http.serveFile(client, rootDirectory, request)` answers a `GET` or `HEAD` with a file below a directory, and `http.serveStatic(port,
dir, count)` is a complete web server for a directory. `http.mimeType(path)` picks the `Content-Type` from the file extension.

{{sample http/static_files}}

**What to notice.**

* A path that ends in `/` gets `index.html`. A missing file is `404`, a method other than `GET` or `HEAD` is `405`.
* A path that tries to climb out of the directory (`..`, also when escaped as `%2e%2e`, and backslashes) is refused with `403`.
  The file outside the web root is never read.
* The `HEAD` answer has the headers of the file but no body. The client does not know the request was a `HEAD`, so `readResponse`
  waits for `Content-Length` bytes and gets none: with `HEAD`, read only the headers.
* The whole file is read into memory before it is sent, so this is a server for small sites, not for large downloads.

### When things go wrong

{{sample http/errors}}

**What to notice.** All failures return `null` and `http.error()` has a short text, for example `not an http:// URL`, `cannot connect`,
`not an HTTP response`, `connection closed before the response`, `too many redirects`, or the TLS problem for https. A server that
answers with `500` is **not** a failure of the call: you get a `Response` with `status` 500.

### A real server

`http.serve(port, handler, count)` answers `count` requests (`0` means for ever) and returns when it cannot listen. It serves **one
request at a time**: while a handler runs, other clients wait in the backlog. The sample only compiles, because it needs a fixed
port; start it and try `curl "http://localhost:8080/hello?name=World"`.

{{sample http/serve_forever}}

**What to notice.**

* Every request costs about 6 KB of memory that is never freed (`new` and `alloc` never free, and `readRequest` allocates). That is
  fine for tools and tests; for a service that runs for weeks, restart it now and then, or `fork` a child for each connection and let
  it exit. A `wshub` with an `httpx.Router` ([the next chapter](#chap-web-services)) serves HTTP for many clients at once and runs in
  constant memory.
* Limits of the `http` module: methods up to 15 characters, paths and queries up to 1023, header lines up to 4095 (a longer line is read as
  two), request bodies up to 64 MiB (a larger `Content-Length` gets `400`), a 15-second time limit on every read and write of a
  client (a client that sends nothing holds up the others for that long), one request per connection, no keep-alive, no cookies, no multipart forms, no proxies, no HTTP/2. (`httpx`
  in the next chapter has keep-alive, cookies and multipart forms; proxies and HTTP/2 are not supported by either.) Handlers must answer
  with `respond` (or write the response themselves) before they return.
* `examples/http_server.a` is a small web server and `examples/http_get.a` a command-line client with an `--insecure` switch.

## WebSocket

A WebSocket starts as an ordinary HTTP request that asks to *upgrade* the connection. After the upgrade both sides can send messages
at any time, over the same TCP connection, until one of them closes it. Browsers speak WebSocket, which is what makes it useful for
live pages: a chat, a dashboard, a game.

The API: `websocket.connect("ws://host:port/path")` for a client (`wss://` works too, see the end of this chapter),
`websocket.accept(connection, path, max)` for a server (it takes a `conn.Connection`), then `sendText`, `sendBinary`, `ping`, `receive`
and `close` on the returned `websocket.WebSocket`. The samples of this chapter use these short names. The module has more:
`receiveMessage` and `closeWith(code, reason)`, fragments, compression, non-blocking use, strict checks of everything the standard
demands, and a server for many clients; [the next chapter](#chap-web-services) covers them.

### The handshake

The client sends `Upgrade: websocket` and a `Sec-WebSocket-Key` made of 16 random bytes (from the operating system's random generator,
so it differs on every run). The server proves that it understood by answering `101
Switching Protocols` with `Sec-WebSocket-Accept`: the SHA-1 of the key plus a fixed GUID, in base64. `acceptKey` computes it, and
the sample checks it with the example key from the RFC.

{{sample http/ws_handshake}}

**What to notice.**

* `clientSend` and `clientFinish` are the two halves of `websocket.connect`, so a client and a server can live in one thread (the
  server's `accept` runs between the halves). `websocket.connect` itself blocks until the server has answered, so it needs a server in
  another process or machine, or one that runs from `net.setIdleHook` (see [the next chapter](#chap-web-services)).
* The server learns the requested path (`/chat`). A request that is not a WebSocket upgrade is answered with `400 Bad Request`
  and `accept` returns `null`.

### Frames

Messages travel in frames: a header of 2 to 14 bytes, then the payload. The first byte has the FIN bit (last frame of a message) and
the opcode (text, binary, close, ping, pong, continuation). The second byte has the mask bit and a 7-bit length; lengths of 126 and
above use two more bytes, and above 65535 eight more. **Frames from a client are masked** with a 4-byte key; frames from a server
are not.

{{sample http/ws_frames}}

**What to notice.** The first two frames are the examples of RFC 6455 section 5.7, so you can compare them with the standard; the three lengths at the end show where the length field changes size. `buildFrame`
writes a frame and `parseHeader` reads one: it returns the header length, `0` when it needs more bytes, `-1` for an invalid
header (reserved bits set). The same `unmask` call masks and unmasks. You only need these functions to write a proxy or a test: the
`WebSocket` methods use them for you.

### An echo server and a client

{{sample http/ws_echo}}

**What to notice.**

* The server process loops on `receive` until it returns `-1` (the connection closed) and answers every message. The opcode in the
  last argument tells text (`1`) from binary (`2`).
* `ws->close(1000)` starts the closing handshake with the status code 1000 ("normal"). `examples/ws_echo.a` is this server as a
  stand-alone program on port 8081, which a browser can connect to with `new WebSocket("ws://localhost:8081/")`.
* The client masks its frames with a random 4-byte key per frame, and the handshake key is random too; both come from the operating
  system's random generator, so there is nothing to seed and the bytes on the wire differ from run to run.
* The same server and client in **one** thread, with no `fork`, is the first sample of [the next chapter](#chap-web-services).

### Messages

{{sample http/ws_messages}}

**What to notice.**

* `receive(buf, max, &opcode)` returns one complete message: fragments are joined for you. It returns the length, and `-1` when the
  connection closed.
* A message longer than `max` is cut to `max` bytes and the rest is dropped. For a text message that fills the buffer exactly there
  is no room for the terminating zero, so use the returned length. (`receiveMessage()` of [the next chapter](#chap-web-services)
  has neither problem: it gives you a `Message` whose `data` always ends in a 0 byte.)
* A 70000-byte message is one call; the 8-byte length field is chosen by the library.
* The receiver does not trust the length that a frame announces. A frame over `maxFrame` or a message over `maxMessage` (16 MiB each by
  default; `setMaxMessage(n)` lowers them) ends the connection with the close code 1009, and nothing is allocated for the announced
  size. A server that faces strangers should still set the limits to what it needs.
* Text messages **are** checked for valid UTF-8: an invalid byte ends the connection with the close code 1007 (the check runs while the
  bytes arrive), and `sendText` refuses text that is not UTF-8. Compression (permessage-deflate) and sub-protocol negotiation exist too;
  see [the next chapter](#chap-web-services).

### Ping, pong and close

A *ping* asks "are you still there?" and the other side must answer with a *pong* that has the same payload. `receive` answers pings
by itself and hides pongs, so the sample below, which wants to see one, reads the raw connection (`ws->c` is the `conn.Connection`). A
program that wants pings and pongs as events sets a handler (`setHandler`); `ws->rttMs` has the round trip of the last ping that was
answered, and `setKeepalive` sends pings by itself ([the next chapter](#chap-web-services)).

Closing is a handshake as well: one side sends a close frame with a 2-byte status code (and, with `closeWith`, an optional reason), the
other answers with its own. Codes: 1000 normal, 1001 going away, 1002 protocol error, 1003 unsupported data, 1007 text that is not
UTF-8, 1009 message too big, 4000 to 4999 for your own use. The next chapter has the whole table.

{{sample http/ws_ping_close}}

**What to notice.**

* After `ping()` and `sendText()`, the server's single `receive` call answered the ping and returned the text; the pong (`8a 00`:
  opcode 10, length 0) is already waiting in the client's connection.
* On the receiving side `receive` returns `-1` for a close frame, `closeCode` has the code the peer sent (`4001` here), and `closed`
  is true. The library answers the close frame automatically, so there is nothing more to do but stop.
* `close(code)` waits up to one second for the peer's close frame (here nobody answers, which is why this sample takes a second to
  end); it sends **no reason text**, only the code. `closeWith(code, reason)` also sends a reason of up to 123 bytes.

::: note

`websocket.connect` accepts `ws://` and `wss://`. A secure WebSocket takes two layers, TLS and then the WebSocket handshake on top of
it; `connect` does both, and the TLS section below shows the same thing by hand, which is also how you would do it for a connection
that you opened yourself. [The next chapter](#chap-web-services) uses `wss://` directly.

:::

## TLS and HTTPS

TLS is the encryption under `https://`. A client checks the server's **certificate** (is it for the name I typed? is it signed by an
authority I trust? is it valid today?) and then both sides agree on secret keys that nobody listening can learn. A has TLS 1.3 written
from scratch, with no C library or OpenSSL behind it:

* a **client** with certificate checking, and a **server**;
* cipher suites `TLS_AES_128_GCM_SHA256`, `TLS_CHACHA20_POLY1305_SHA256` and `TLS_AES_256_GCM_SHA384`; X25519 is the only key exchange;
* server signatures RSA-PSS, ECDSA P-256 and ECDSA P-384; certificates and keys in PEM (RSA or EC);
* **not** supported: TLS 1.2 and older, session resumption, 0-RTT, client certificates, ALPN, revocation checks. A server that only
  speaks TLS 1.2 makes the handshake fail with `the peer sent alert 70` ("protocol version"). `docs/TLS.md` in the repository lists
  the details.

::: warning

The cryptography is not constant time (it uses table lookups and data-dependent branches). That is fine for fetching pages, checking
certificates and servers whose clients are not on the same machine; do not use it to protect long-lived secrets against someone who
can measure timings on your computer.

:::

The simplest use is invisible: `http.get("https://...")` does TLS, and so do `http.post` and `http.download`. This section shows the
layers underneath. The samples need a certificate; they share a throw-away one, in the module `testcert.a` next to each program: a
self-signed EC P-256 certificate for `localhost` and `127.0.0.1`, valid until 2100, with its private key. **Everybody who reads this
book has that key**, so it protects nothing; it is there so that the samples run. For a real one use a certificate authority, or for
tests:

```sh
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 30 \
    -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" -keyout key.pem -out cert.pem
```

### Looking at a certificate

A certificate says who it is for (a subject and a list of alternative names), who vouches for it (the issuer's signature), and
when it is valid. `x509.verifyChain(chain, count, host, now)` returns `null` when the chain is good and otherwise a sentence that
says why not. It is what every TLS client runs, and with a fixed `now` it is deterministic:

{{sample http/cert_check}}

**What to notice.**

* The certificate fits `localhost` and `127.0.0.1` because both are in its alternative names; the match for a host name is not case
  sensitive, and a `*.` wildcard stands for exactly one label.
* **Trust** comes from the store of root certificates. The system's roots are loaded on the first check: the file named by
  `SSL_CERT_FILE`, or else the usual bundle such as `/etc/ssl/certs/ca-certificates.crt` (on Windows the system's certificate store). `x509.addRootPem(text)` adds one of your own, and `x509.clearRoots()` removes
  them all, the system's included (and stops them from being loaded).
* The messages tell the problems apart: no trusted root at all, a different host name, a date before or after the validity, an unknown
  authority. A self-signed certificate is accepted only when you added it as a root.

### TLS without a network

The `tls` module's core is a state machine that does no I/O: you give it the bytes that arrived, and it gives you the bytes to send.
That is how the GUI's `gnet.Fetch` fetches `https://` pages inside an event loop, and it allows a test that needs neither sockets nor processes.

{{sample http/tls_inmemory}}

**What to notice.**

* `tls.client(host, verify)` and `tls.accept(config)` make the two sides. `outData` / `outLength` / `outConsumed` is the output queue,
  `feed` takes input. The `pump` function is the "network": it moves bytes both ways until nothing moves.
* After the handshake `write` encrypts into the output queue and `readApp` decrypts what was fed in. Twelve bytes of text became 34 on
  the wire: a 5-byte record header, the data, one byte of record type and a 16-byte authentication tag.
* `client->suiteName` is the negotiated cipher suite. `shutdown` sends `close_notify`, the polite goodbye that lets the peer tell a
  finished stream from a cut one.

### TLS over a socket

For ordinary programs there is a shortcut: `tls.wrap(fd, hostName, verify)` runs the client handshake on a connected socket, and
`tls.wrapServer(fd, config)` the server handshake on an accepted one. From then on **the same `net.send`, `net.recv`, `net.recvLine`
and `net.close` calls on that handle are encrypted**, so a protocol written for plain sockets works on TLS unchanged.

{{sample http/tls_loopback}}

**What to notice.**

* `tls.loadConfig(certPem, keyPem)` reads the certificate chain (the server's certificate first) and the private key (RSA as PKCS#1
  or PKCS#8, EC P-256 or P-384 as SEC1 or PKCS#8) and returns `null` if either is unusable.
* `tls.wrap` returns `false` on failure and `tls.lastError()` says why. The socket stays open either way; close it.
* The name you pass to `wrap` is the one checked against the certificate. It is **not** looked up: the socket is already
  connected, so connect to the address you mean and pass the name you expect.
* `net.close` first sends `close_notify`. `net.rawSend`, `net.rawRecv` and `net.rawClose` bypass TLS when you need the bytes below.

### Trust: who accepts what

The same server, six clients:

{{sample http/tls_trust}}

**What to notice.**

* `verify = false` accepts anything: encryption without authentication protects against eavesdroppers but not against someone who
  *is* the server. Use it only for a server you know, and never as the default.
* A self-signed certificate is refused until you trust it explicitly. The message for a certificate that no trusted root vouches for
  depends on what is in the store: with no roots at all it says so; with an unrelated root it says `self signed (not trusted)` for a self-signed certificate like this one, and `issued by an unknown authority` for any other.
* The host name check is separate from the trust check. The right certificate for the wrong name is refused.
* A host given as an IP address (`127.0.0.1`) is matched only against the IP entries in the certificate's alternative names, and a
  host name only against its DNS entries. Only a certificate with no alternative names at all falls back to its common name, and then for host names only.

### https in `http`

`http.get`, `http.post`, `http.request` and `http.download` do the TLS handshake themselves for `https://` URLs, with the
certificate check turned on. `http.setVerify(false)` turns it off. The server side is `http.serveTls(port, config, handler, count)`
and `http.serveStaticTls`.

{{sample http/https_loopback}}

**What to notice.** The first request fails with the reason in `http.error()`, because nothing is trusted yet. After
`x509.addRootPem`, `https://` works exactly like `http://`. The server process does what `http.serveTls` does: handshake first, then
the usual HTTP on the same handle.

Against the real Internet and with files for the certificate, the two ends look like this. Both only compile here:

{{sample http/https_client}}

{{sample http/https_server}}

Start the second one with a `cert.pem` and `key.pem` (the `openssl` command above makes them) and try
`curl --cacert cert.pem https://localhost:8443/`. `examples/httpsd.a` is a complete HTTPS web
server for a directory, with the certificate and key on the command line.

### One piece of code for plain and for TLS: `conn`

`conn.Connection(handle)` wraps *any* socket handle, including one that `tls.wrap` made secure, because the connection only uses
`net.send` and `net.recv`. A protocol written for a `conn.Connection` therefore does not know whether the line it reads was
encrypted.

{{sample http/conn_tls}}

**What to notice.** The same two functions serve and ask over a plain socket and over TLS. The only difference is the line that makes
the connection: `new conn.Connection(fd)` after `tls.wrapServer(fd, cfg)` or `tls.wrap(fd, name, true)`.

### A secure WebSocket by hand

Because `websocket.accept`, `clientSend` and `clientFinish` take a `conn.Connection`, a `wss://` connection is one more layer of the
same idea: TLS first, then the WebSocket handshake on the encrypted connection.

{{sample http/wss_by_hand}}

**What to notice.** The WebSocket calls (`accept`, `clientSend`, `clientFinish`, `receive`, `sendText`) are the same as in the plain
version; what is new is the TLS step before them. `websocket.connect("wss://...")` does the client's half of this for you; doing it by
hand shows the layers and works for a connection that you made yourself.

## Summary

* `http.get`, `http.post` and `http.request` return a `Response` or `null`; always check for `null`, and read `http.error()`.
* A server is a loop of `accept`, `http.readRequest`, a handler that calls `http.respond`, and `close`. `http.serve` is that loop on a
  fixed port. It handles one request at a time and uses memory that is never freed, so it suits tools and small services.
* A response body ends by `Content-Length`, by chunks, or by the end of the connection; the client handles all three, and unpacks
  gzip and deflate.
* A WebSocket is an HTTP upgrade followed by frames; `receive` joins fragments and answers pings, and a close frame ends the
  conversation with a status code. `websocket.connect` takes `ws://` and `wss://`; the module checks frames, UTF-8 and close codes
  strictly (more in [the next chapter](#chap-web-services)).
* TLS 1.3 is built in. `tls.wrap` and `tls.wrapServer` make an ordinary socket secure; the `net` calls on it are then encrypted.
* A certificate must match the host name, be valid today and lead to a trusted root; `x509.addRootPem` adds your own, `x509.verifyChain`
  tells you why a chain fails, and `http.setVerify(false)` skips the check (do not make that a habit).
* `conn.Connection` works the same on a plain and on a secure socket, which is how `wss` is built by hand.

## Where next

* [Networking](#chap-networking): the sockets, addresses and packets under all of this.
* [WebSocket, server-sent events, an HTTP toolkit and JSON-RPC](#chap-web-services): the rest of `websocket` (close codes,
  fragments, compression, `wss://`), a server for many clients, event streams, `httpx` and `jsonrpc`.
* API references: [http](#api-http), [websocket](#api-websocket), [tls](#api-tls), [x509](#api-x509), [conn](#api-conn).
* Bigger programs in `examples/`: `http_server.a`, `http_get.a`, `httpsd.a` (HTTPS server for a directory), `ws_echo.a`,
  `chat_server.a` (a plain TCP chat server built on `conn`).
* `docs/TLS.md` in the repository: the whole list of supported suites, the trust store, and how TLS is tested.
