# TLS and the cryptography behind it

A has TLS 1.3, written from scratch in A (no libc, no OpenSSL): a **client** with certificate checking and a **server**. It is
what makes `https://` work in `http`, `gnet.Fetch` and the `abrowse` browser, and what `examples/httpsd.a` serves with.

```c
import http;
http.Response* r = http.get("https://example.org/");        // checked against the system's trusted roots
println(r->body);
```

## What is there

| Module | What it does |
|--------|--------------|
| `tls` | the TLS 1.3 protocol: a session state machine, blocking sockets, `net` integration, server configuration |
| `x509` | certificates (DER and PEM), signature and chain checks, host names, validity, the trust store |
| `rsa` | RSA signature verification (PKCS#1 v1.5, PSS) and PSS signing |
| `ec` | ECDSA on P-256 and P-384: verification and signing |
| `x25519` | X25519 key exchange (RFC 7748) |
| `aes` | AES-128 / AES-256 and GCM |
| `chacha` | ChaCha20 and Poly1305 (RFC 8439) |
| `bn` | big numbers with Montgomery arithmetic (30 bit limbs): the engine of `rsa`, `ec` and `x25519` |
| `hash` | SHA-1/256/384/512, HMAC (`hash.digest(bits, ...)`, `hash.hmac(bits, ...)`) |
| `secure` | random bytes from the operating system (`getrandom`, `/dev/urandom`, `RtlGenRandom` in ADVAPI32.DLL on Windows) |

Cipher suites: `TLS_AES_128_GCM_SHA256`, `TLS_CHACHA20_POLY1305_SHA256`, `TLS_AES_256_GCM_SHA384`. Key exchange: X25519.
Server signatures accepted: RSA-PSS (`rsa_pss_rsae_sha256/384/512`), ECDSA P-256/SHA-256 and P-384/SHA-384. Certificate
signatures: RSA PKCS#1 v1.5 or PSS and ECDSA with SHA-1 (RSA only), SHA-256, SHA-384, SHA-512.
Not there: TLS 1.2 and older, session tickets / resumption, 0-RTT, client certificates, HelloRetryRequest (so a peer that
does not take X25519 fails with a message), revocation checks (OCSP, CRL), name constraints, ALPN, Ed25519, IPv6 literals.

## Using it

**Through `http` and `net`** (the easy way). `http.get`, `http.post`, `http.request` and `http.download` take `https://` addresses.
`http.setVerify(false)` turns the certificate check off (do not, unless you know the server). To make your own socket secure,

```c
int fd = net.connect("example.org", 443);
if (!tls.wrap(fd, "example.org", true)) { println(tls.lastError()); }
net.sendText(fd, "GET / HTTP/1.0\r\n\r\n");      // net.send / net.recv / net.recvLine / net.close now go through TLS
```

`tls.wrap` does the handshake; after that every `net` call on that handle encrypts or decrypts, `net.close` sends the goodbye
(`close_notify`) first, and `net.waitReadable` knows about data that TLS has already decrypted. `net.rawSend`, `rawRecv` and
`rawClose` bypass TLS. `tls.sessionOf(fd)` returns the session (`->suiteName`, `->leaf` the certificate of the peer).

**A server.**

```c
tls.Config* cfg = tls.loadConfig(readFile("cert.pem"), readFile("key.pem"));    // chain, server certificate first; RSA or EC key
http.serveTls(8443, cfg, handler, 0);               // or  http.serveStaticTls(8443, "www", 0, cfg)
// by hand:  int c = net.accept(s);  if (tls.wrapServer(c, cfg)) { ...net.recv / net.send as usual... }
```

Private keys can be PKCS#1 (`BEGIN RSA PRIVATE KEY`), SEC1 (`BEGIN EC PRIVATE KEY`) or PKCS#8 (`BEGIN PRIVATE KEY`). Make a test
certificate with `openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -subj /CN=localhost -addext
subjectAltName=DNS:localhost,IP:127.0.0.1 -keyout key.pem -out cert.pem`; `examples/httpsd.a cert.pem key.pem 8443 .` serves a
directory, and `curl --cacert cert.pem https://localhost:8443/` reads it.

**In an event loop.** `gnet.Fetch` handles `https://` itself (`f->verifyCerts`, then `f->secure`, `f->cipher`, `f->certError`
tell what happened). The session underneath does no I/O of its own, so it fits any loop:

```c
tls.Tls* t = tls.client("example.org", true);       // true: verify
// send what tls.outData(t) / tls.outLength(t) offer, then tls.outConsumed(t, n)
// when bytes arrive:   tls.feed(t, bytes, n);   then send again (the handshake answers are in the output)
// when tls.ready(t):   tls.write(t, request, n);   tls.readApp(t, buf, max) / tls.available(t) give the decrypted data
// tls.closed(t): the peer said goodbye;  tls.failed(t): t->error says why;  tls.keyUpdate(t, true) rotates the keys
```

`tls.accept(cfg)` makes the server side of a session the same way. `tls.clientOnly(host, verify, suite)` offers just one suite
(0x1301, 0x1302 or 0x1303), useful for tests.

## Certificates and trust

`x509.loadSystemRoots()` runs on the first verification. On Linux and Android it reads `$SSL_CERT_FILE`, else
`/etc/ssl/certs/ca-certificates.crt`, `/etc/pki/tls/certs/ca-bundle.crt`, `/etc/ssl/cert.pem`, ... (the usual places). On **Windows** it
takes the certificates of the system's `ROOT` store (`CertOpenSystemStore` in CRYPT32.DLL, so roots that an administrator added are
there too), plus `$SSL_CERT_FILE` if set. Without any roots a verified connection fails with "no trusted root certificates are
installed". To trust one more certificate: `x509.addRootPem(text)` or `x509.addRootFile(path)`; `x509.clearRoots()` empties the
store (and stops the system roots from being loaded).

A chain is accepted when the first certificate is valid today and fits the host name (a DNS name in `subjectAltName` with a
leading `*.` wildcard for exactly one label, an IP address SAN, or the common name when there is no SAN), every certificate is
inside its validity dates, and the chain leads, by signatures, to a trusted root (or the certificate itself is one) through
intermediates that are CA certificates (`basicConstraints`). `x509.verifyChain` returns `null` or a sentence such as
"the certificate has expired", "the certificate is for a different host name", "the certificate was issued by an unknown
authority", "the certificate is self signed (not trusted)".

## Security notes

* **Not constant time.** The big number, AES and curve code uses table lookups and data-dependent branches. That is fine for
  verifying certificates, for browsing, and for servers whose clients are not co-located attackers; it is not a basis for
  protecting long-lived secrets against a local attacker who can measure timings. Keys and nonces are fresh per connection.
* Every random value comes from the operating system (`secure.bytes`); if there is none, the session fails (it never falls
  back to a weaker source).
* Certificates are checked by default everywhere (`gnet.Fetch`, `http`, `tls.client(host, true)`). A refused certificate fails
  the request; `abrowse` shows a "Your connection is not private" page and offers "Proceed anyway" per host for the session.
* A TLS 1.3 session that receives a record that does not authenticate, a wrong `Finished`, a wrong `CertificateVerify`, or
  something that is not TLS at all ends with a fatal alert and `t->error`.
* Speed (x86-64): about 3 MB/s with AES-GCM and 8 MB/s with ChaCha20-Poly1305; an RSA-2048 handshake takes about 0.1 s,
  an ECDSA P-256 one less. Ten times slower on the emulated targets.

## How it is tested

* `tests/t127_crypto.a` (generated by `tests/gen/gen_crypto_test.py`) compares hashes, HMAC, RSA PKCS#1/PSS (2048 and 3072 bit),
  ECDSA P-256/P-384, X25519, AES-GCM, ChaCha20-Poly1305 and 21 certificate chain cases (wildcards, IP SANs, expired, wrong host,
  unknown authority, forged signature, a non-CA intermediate, ...) with values from Python's `cryptography` and `hashlib`, on
  all eight targets.
* `tests/t128_tls.a` runs a client and a server session against each other in memory with every suite, RSA and both EC key
  types and formats, 50 KB and 40 KB transfers, key updates in both directions, close_notify, a damaged record, wrong host,
  unknown authority and garbage input.
* `tests/t129_gui_https.a`: `gnet.Fetch` over https (GET, POST, redirect, a 200 KB body, 404, untrusted server, `verifyCerts=false`).
* `tests/https.sh` (Linux x86-64; needs `openssl`, `curl`, `python3`): the A server `httpsd` is fetched by curl, `openssl s_client`
  with each suite, and Python's `ssl`; the A client talks to `openssl s_server` with RSA, P-256 and P-384 certificates and every
  suite, and refuses an untrusted one. `tests/gui.sh` includes `abrowse` over https with a Python server.
