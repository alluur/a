# Cryptography

A has a small set of cryptographic building blocks written in A itself: hashes and HMAC, two authenticated ciphers (AES-GCM and ChaCha20-Poly1305), X25519 key agreement, RSA and ECDSA signatures, X.509 certificates, TLS 1.3, and the password hashes of `/etc/shadow`. They are what `http` and `gnet` use for `https://`, and you can use them directly.

This chapter shows each module with a sample that uses a published test vector where one exists, and explains which tool is for which job. Choosing the right tool, and using it in the right order, matters more than any single call.

In this chapter:

* a map of the primitives: what each one is for, and what is *not* there;
* random numbers, hashes and HMAC;
* encryption with AES-GCM and ChaCha20-Poly1305, and the nonce rule;
* key agreement with X25519, signatures with RSA and ECDSA, certificates;
* TLS in memory and over a socket, and password hashes.

::: warning

**This is a from-scratch implementation that has not had an independent security audit.** It was written for A, in A, and its tests compare its answers with published test vectors and with other implementations (Python's `cryptography` package, which uses OpenSSL, and `openssl`, `curl` and Python's `ssl` module for TLS), so it computes the right results. That is not the same as being safe against an attacker. In particular the code is **not constant time**: table lookups and branches that depend on secret data can leak the secret to someone who can measure timings, for example from another process on the same machine. Use it to learn, to talk to servers and to protect data where a loss is acceptable. For anything whose loss would hurt (money, health, other people's data), use a library that has been audited and has years of use, and treat what is in this chapter as a way to understand how that library works.

:::

## Which primitive for which job

Start from what you want to achieve, not from the algorithm.

| You want to | Use | Module and call |
|---|---|---|
| get a fingerprint of data, to detect accidents | a hash: SHA-256, SHA-384, SHA-512 | `hash.sha256Raw`, `hash.digest(bits, ...)` |
| prove that a message came from someone who knows a shared secret, and was not changed | HMAC | `hash.hmacSha256`, `hash.hmac(bits, ...)` |
| keep data secret **and** detect changes | an AEAD cipher: AES-GCM or ChaCha20-Poly1305 | `aes.seal` / `aes.open`, `chacha.seal` / `chacha.open` |
| agree on a key with someone over a channel that others can read | X25519 | `x25519.base`, `x25519.scalarmult` |
| prove that *you* wrote something, so that anyone can check it | a signature: ECDSA (P-256, P-384) or RSA (PSS, PKCS#1 v1.5) | `ec.sign` / `ec.verify`, `rsa.signPss` / `rsa.verifyPss` / `rsa.verifyPkcs1` |
| know that a public key belongs to a named server | a certificate chain | `x509.parsePem`, `x509.verifyChain` |
| protect a whole connection | TLS 1.3 | `tls`, or `https://` through `http` |
| store a password so that a stolen database does not give the passwords away | a salted, slow password hash | `syscrypt.sha512crypt`, `syscrypt.verify` |
| get unpredictable bytes for keys and nonces | the operating system's generator | `secure.bytes` |
| talk to a VNC server | DES, nothing else | `des.vncResponse` |

Three facts that the table cannot show:

* **A hash alone does not authenticate.** Anyone can compute SHA-256 of any data, including an attacker who changed it. Use HMAC when both sides share a secret, and a signature when they do not.
* **Encryption alone does not protect against changes.** `chacha.xorStream` encrypts and nothing else; a changed byte decrypts to a changed byte, silently. Use the AEAD functions, which check a tag before they give you any plain text.
* **Key agreement alone does not tell you who you agreed with.** X25519 gives two parties a shared secret; it does not tell either of them whom they share it with. Combine it with a signature, a certificate, or a secret that you shared in advance, or an attacker in the middle can run two agreements and read everything.

What is **not** there (checked in the sources of `lib/`): encryption with RSA or key exchange with ECDH on the NIST curves (`rsa` and `ec` only sign and verify; `rsa` cannot make PKCS#1 v1.5 signatures, only check them); the classic block cipher modes ECB, CBC and CTR for AES (the only public AES calls are the GCM ones); Ed25519; SHA-3; and key derivation functions such as PBKDF2, HKDF, scrypt or argon2. (The `tls` module has an HKDF inside, but it is private to it.) `hash.sha1` and `hash.md5` exist for old formats (`hash.digest` also takes 160 for SHA-1 and 128 for MD5); do not use them where an attacker can choose the data.

## Random bytes and hex text

Keys and nonces must be unpredictable. `secure.bytes(buf, n)` fills a buffer from the operating system's generator (`getrandom` or `/dev/urandom` on Linux, `RtlGenRandom` on Windows) and returns `false` if the system has none. `secure.unique(out)` gives 16 bytes that do not repeat: normally random bytes from the same source, but when there is no secure generator it falls back to a hash of a counter, the clock and an address. Such a value does not repeat, but it can be guessed, so use `secure.bytes` for keys.

{{sample crypto/secure_random}}

**What to notice.**

* Always look at the result of `secure.bytes` when the bytes are a key. The signing and TLS code of the library stops with an error when `secure.bytes` fails instead of using a weaker source, and your program should do the same.
* `rand()` of the standard library is a simple xorshift generator for games and tests. After `srand(1)` it gives the same numbers every time, and its state can be worked out from a few outputs. Never use it for a key, a nonce or a password salt.

Test vectors and keys are easier to read as hex text. `secure.toHex(data, n)` makes lower case hex, and `secure.fromHex(text, out, max)` decodes it. The decoder returns the number of bytes, and `-1` for an odd number of digits, for a character that is not a hex digit, and for a result that would not fit in `max` bytes. It accepts upper and lower case, and ignores trailing spaces, carriage returns and newlines. Every sample below uses these two functions to write keys and results.

## Hashes and HMAC

A hash turns any amount of data into a fixed size fingerprint. A good hash makes two things impossible in practice: finding other data with the same fingerprint, and working backwards from a fingerprint to the data. `hash.sha256(data, n)` returns the fingerprint as 64 hex characters; `hash.sha256Raw` writes the 32 bytes. `hash.digest(bits, data, n, out)` chooses 256, 384 or 512 at run time, writes the raw digest and returns its size in bytes (32, 48 or 64; it returns 0 for a size it does not know).

{{sample crypto/hash_sha2}}

**What to notice.**

* Every function takes a pointer and a byte count: `hash.sha256(abc, 3)`. A string is passed with `strlen(s)`.
* The SHA-256 and SHA-512 digests of `abc` are the published values from FIPS 180, and so is the start of the SHA-384 digest. One different letter (`abd`) changes the whole digest.
* The empty input has a hash, too (`e3b0c442...`).

An HMAC mixes a secret key into the hash. Whoever knows the key can compute the tag; whoever does not know it cannot. It is the simplest way to protect messages between two programs that share a secret.

{{sample crypto/hash_hmac}}

**What to notice.**

* The sample is test case 2 of RFC 4231.
* The receiver computes the tag again and compares it with the one that came with the message. **Compare with `hash.equalConstantTime`**. A normal comparison stops at the first different byte, and the time it takes tells an attacker how many bytes were right, one byte at a time.
* `hash.hmac(bits, ...)` returns the length of the tag, like `digest`.

For speed, here is what was measured on a 2.1 GHz Intel Xeon virtual machine (x86-64 Linux, one core in use, the best of five runs): SHA-256 hashed about 200 MB per second and SHA-512 about 300 MB per second (16 MB of data), ChaCha20-Poly1305 sealed about 14 MB per second and AES-128-GCM about 3 MB per second (1 MB of data). Your numbers will differ with the machine, but the order should not: hashes are fast, ChaCha20-Poly1305 is slower, and AES-GCM is the slowest. All of them are plain A code with no processor instructions for cryptography, so they are fine for small messages and short connections, and slow for bulk data.

## Authenticated encryption

An AEAD cipher ("authenticated encryption with associated data") does three things with one call: it encrypts, it computes a tag over the cipher text, and it lets you add *associated data* that is not encrypted but is covered by the tag, such as a header or a message number. When you open the message, the tag is checked first. If a single bit of the cipher text, of the tag or of the associated data is wrong, you get `false` and no plain text at all.

Both ciphers in A have the same shape:

```a
aes.Gcm* g = aes.gcm(key, 16);                                   // or 32 bytes for AES-256
aes.seal(g, nonce12, aad, aadLen, plain, n, out);                // out: n bytes cipher text, then 16 bytes tag
bool ok = aes.open(g, nonce12, aad, aadLen, in, n + 16, out);

chacha.seal(key32, nonce12, aad, aadLen, plain, n, out);
bool ok = chacha.open(key32, nonce12, aad, aadLen, in, n + 16, out);
```

| | AES-GCM | ChaCha20-Poly1305 |
|---|---|---|
| key | 16 or 32 bytes | 32 bytes |
| nonce | 12 bytes | 12 bytes |
| tag | 16 bytes | 16 bytes |
| speed here | slower (about 3 MB/s) | faster (about 14 MB/s) |
| standard | NIST SP 800-38D | RFC 8439 |

Pick either. Use ChaCha20-Poly1305 when speed matters in this implementation, and AES-GCM when something else in the system insists on it. TLS in A offers both (and AES-256-GCM).

### AES-GCM against a published vector

{{sample crypto/aes_gcm_vector}}

**What to notice.**

* This is test case 4 of the GCM specification (McGrew and Viega). The tag was recomputed with OpenSSL through Python's `cryptography` package, and it is the same.
* `out` holds the cipher text (as long as the plain text) and then the 16 byte tag. You need `n + 16` bytes.
* `aes.gcm(key, 16)` does the key schedule once. Keep the `Gcm*` and use it for many messages.

{{sample crypto/aes_gcm_256}}

**What to notice.**

* Only the key length changes. A 32 byte key gives AES-256. The sample is test case 16 of the GCM specification.
* `aes.open` decrypts into a buffer of your own. It writes nothing when the tag is wrong, and it returns `false` for an input shorter than the 16 byte tag.

### Changes are noticed

{{sample crypto/aes_gcm_roundtrip}}

**What to notice.**

* The three attacks (a flipped bit, other associated data, a cut message) are all refused by the same `false`.
* The associated data `msg-id=42` was not encrypted, but it is protected: with `msg-id=43` the tag does not fit.
* The key and the nonce come from `secure.bytes`. The nonce has to be passed to the receiver (it is not secret), the key must not.

### The nonce rule

A *nonce* ("number used once") makes every message encrypt differently. The rule has no exceptions: **never use the same nonce twice with the same key.** The sample shows why.

{{sample crypto/aes_nonce_reuse}}

**What to notice.**

* Both ciphers (the sample shows AES-GCM) are stream ciphers inside: the plain text is combined with a key stream that depends only on the key and the nonce. Two messages with the same nonce use the same stream.
* Then `cipher1 XOR cipher2` equals `plain1 XOR plain2`. The key has dropped out, and anyone who guesses one text gets the other.
* With GCM, repeating a nonce also leaks material that lets an attacker forge messages.

Two safe ways to choose nonces: a random 12 byte nonce for each message (fine for up to about four billion messages per key), or a counter that you never reset. The counter is also useful for something else.

{{sample crypto/aead_counter_nonce}}

**What to notice.**

* The nonce is a message counter. Sender and receiver count in step, so the nonce does not need to be sent.
* The receiver derives the nonce from *its* counter. A replayed message (number 0 again) and a message that arrives too early (number 2 before 1) do not open, so replay and reordering are noticed without more code.
* The counter only moves on after a good message. An attacker who sends garbage cannot push the receiver out of step.
* This channel goes one way. If both sides send with the same key, give each direction its own key, or its own fixed byte in the nonce, or the two counters will produce the same nonce.

### ChaCha20-Poly1305

{{sample crypto/chacha_aead}}

**What to notice.**

* The vector is section 2.8.2 of RFC 8439. The tag `1ae10b59...` is the one printed in the RFC.
* The key is the bytes `0x80` to `0x9f`, written with a loop because it is a counting pattern. The sample prints the first 32 bytes of the cipher text and the tag.

The module also exposes the plain ChaCha20 stream cipher, `chacha.xorStream`, without any authentication. Protocols can be built on it, and on its own it is dangerous.

{{sample crypto/chacha_stream}}

**What to notice.**

* The same call encrypts and decrypts. The third line shows the danger: a flipped bit in the cipher text flips the same bit of the plain text, and nothing notices. `Ladies` became `Madies`.
* The `counter` argument is the block counter, 1 here as in RFC 8439 section 2.4.2 (the AEAD uses block 0 for the Poly1305 key).

### A file that can be trusted

{{sample crypto/file_encrypt}}

**What to notice.**

* The file layout is `nonce | cipher text | tag`. The nonce is new and random for each file, so one key can protect many files.
* A damaged byte, and a wrong key, both give `null`. There is no way to get half of the text.
* The associated data `v1` is not stored in the file. The reader has to supply the same value, so the cipher text is bound to a context: the same bytes would be refused by code that expects `v2`.
* A real program needs a place to keep the key. This sample only generates one. How the key reaches the program (a prompt, a key file with strict permissions, an operating system store) is the hard part, and a key derivation function from a password is not in the library.

## Key agreement with X25519

Two people who have never met can compute the same secret by sending each other public numbers. In X25519 the numbers are 32 bytes. `x25519.base(pub, priv)` makes a public key from a private key (32 random bytes). `x25519.scalarmult(shared, myPriv, theirPub)` computes the shared secret. Keys and results are 32 bytes in the little-endian order of RFC 7748.

{{sample crypto/x25519_rfc7748}}

**What to notice.**

* The numbers are the Alice and Bob of RFC 7748 section 6.1.
* Both sides get the same 32 bytes, and only the public keys crossed the network.

The shared secret is a good random-looking value, but it is not a key yet. Hash it first, and in a real protocol put anything else that both sides know (the two public keys, a protocol name) into the hash. The sample below keeps it short and hashes only the secret.

{{sample crypto/x25519_hybrid}}

**What to notice.**

* Alice and Bob each hash the shared secret with SHA-256 into the same 32 byte key, and use it with ChaCha20-Poly1305.
* The direction is part of the associated data (`alice->bob`). Without it, an attacker could send Alice's own message back to her.
* Nothing here proves who is on the other end. Run this over a network and a man in the middle can do one agreement with each side. Authenticate the public keys: sign them, put them in certificates, or compare them out of band.

`x25519.scalarmult` returns `false` when the result is all zeros.

{{sample crypto/x25519_bad_key}}

**What to notice.**

* A peer can send a public key of tiny order (such as all zeros) to force a known "secret". The function refuses it. Check its result, and stop the connection when it is `false`.

## Signatures

A signature proves that the holder of a private key approved some data, and anyone who has the public key can check it. You sign the *hash* of the message, not the message: `hash.sha256Raw` first, then the signature function.

### RSA

The `rsa` module takes the numbers of a public key as big-endian bytes, the way they stand in a certificate:

```a
rsa.verifyPkcs1(modulus, modLen, exponent, expLen, hashBits, digest, signature, sigLen)
rsa.verifyPss(modulus, modLen, exponent, expLen, hashBits, digest, signature, sigLen)
rsa.signPss(modulus, modLen, privateExponent, dLen, hashBits, digest, out)
```

`hashBits` is 256, 384 or 512 (and 160 for the SHA-1 signatures of old certificates, for verification only). The modulus has 512 to 8192 bits for verification. PSS here uses MGF1 with the same hash and a salt as long as the hash, which is what TLS 1.3 uses.

{{sample crypto/rsa_verify}}

**What to notice.**

* The signatures were made by OpenSSL (through Python's `cryptography` package) with a throw-away 2048 bit key. `PKCS#1 v1.5` and `PSS` are the two RSA signature schemes; the message is the text `The A Programming Language`, hashed with SHA-256 (`256` in the calls).
* A PSS signature does not verify as PKCS#1, and a different message does not verify at all.
* New designs should use PSS. PKCS#1 v1.5 is here because many certificates still use it.

{{sample crypto/rsa_sign}}

**What to notice.**

* `signPss` needs the private exponent `d` as well as the modulus. The key in the sample is public in this book, so it protects nothing. **Never put a real private key into source code.**
* Two signatures of the same message differ, because each uses a fresh random salt. Both verify.
* A signature made here was also checked with OpenSSL.
* There is no key generation in the library. Make keys with a tool such as `openssl genpkey`.

### ECDSA

ECDSA signatures are much shorter than RSA ones (two 32 byte numbers for P-256, against 256 bytes for RSA-2048). Checking one is not faster in this library, though: on the machine described above a P-256 check took about 5 ms and an RSA-2048 check about 3.5 ms. `ec.verify(bits, pub, publen, digest, dlen, r, rlen, s, slen)` takes the curve (256 or 384), the public key as an uncompressed point `04 || X || Y`, the digest, and the two numbers of the signature as big-endian bytes.

{{sample crypto/ecdsa_verify}}

**What to notice.**

* The key and the signature are the P-256 example of RFC 6979 appendix A.2.5: the message is `sample` and the hash is SHA-256.
* The public key is checked: a point that is not on the curve is rejected before the signature is looked at.
* A damaged signature or another message gives `false`, never a crash.

{{sample crypto/ecdsa_p384}}

**What to notice.**

* P-384 pairs with SHA-384 here (`hash.digest(384, ...)`). The digest may be any length; the left bytes are used.
* The same data checked as P-256 is rejected: the point has the wrong size for the curve.

`ec.sign(bits, privateKey, digest, dlen, out)` returns a signature in DER format, the form that certificates and TLS use: `30 len 02 len r 02 len s`. The nonce comes from the system's random generator.

{{sample crypto/ecdsa_sign}}

**What to notice.**

* `verifyDer` in the sample takes the DER apart (it is only a few lines for P-256) and passes `r` and `s` on. A leading zero byte in a DER integer is fine.
* Two signatures of the same data differ, because ECDSA signs with a random number each time. If that number ever repeats or is predictable, the private key can be computed from two signatures. The library takes it from `secure.bytes`.
* The key pair is a published test key from RFC 6979. The signature was also checked with OpenSSL.

## Certificates

A certificate is a signed statement: "this public key belongs to this name". `x509` reads them (PEM or DER), checks signatures, and decides whether a chain of certificates leads to a root that you trust.

{{sample crypto/x509_parse}}

**What to notice.**

* `x509.parsePem(text, out, max)` reads every `CERTIFICATE` block of a PEM text and returns how many it found. `x509.parse(der, len)` takes the DER bytes of one certificate.
* The fields of `Cert` that you will use are `cn` (common name), `san` and `sanIp` (the subject alternative names, `sanCount` of them), `notBefore` and `notAfter` (seconds since 1970), `isCA`, `keyKind` (1 RSA, 2 EC), `curve`, `sigKind` and `sigHash`.
* The certificate is a test certificate made for this book. It is valid until 2100.

A client has to check that the certificate is for the host it wanted to talk to. The rules are in `x509.matchesHost`:

{{sample crypto/x509_hostnames}}

**What to notice.**

* A wildcard `*.cdn.example.test` covers exactly one label: `static.cdn.example.test`, but not `a.b.cdn.example.test` and not `cdn.example.test`. A wildcard needs at least two labels after the star, so `*.test` never matches.
* Names are compared without regard to case.
* An IP address (four dotted numbers, so IPv4 only) is only accepted when the certificate lists it as an IP address. A certificate with a list of alternative names is never matched against its common name; the common name is only used for old certificates that have no list.

`x509.verifyChain(chain, count, host, now)` does the whole check and returns `null` when the chain is trusted, or a sentence that says what is wrong. The caller supplies `now`: the clock is a parameter, which is also what makes the sample repeatable.

{{sample crypto/x509_chain}}

**What to notice.**

* The trust store is a list of root certificates. `x509.addRootPem(text)` trusts more. The first verification loads the system's roots (the file named by the environment variable `SSL_CERT_FILE`, else `/etc/ssl/certs/ca-certificates.crt` or one of four other usual places on Linux; Windows uses its root store), unless you call `x509.clearRoots()` first, which empties the store and stops that. The sample does so, so that the result is the same on every machine.
* The answers are plain sentences: wrong host name, unknown authority, not valid yet, expired.
* What is **not** checked: revocation (no OCSP, no CRL), name constraints, certificate policies and key usage. A certificate that was revoked yesterday is still good here.
* A valid certificate says that someone with the key for `www.example.test` was known to a root. It says nothing about whether that someone is honest.

## TLS

TLS 1.3 is the protocol that puts all of the above to work: a handshake (key agreement, a signature, a certificate check) followed by encrypted records. The `tls` module does this for you. The networking chapters show how to use it with HTTP: see [HTTP, WebSocket and TLS](#chap-http-websocket-tls). Here it is shown from the cryptography side, without any network.

A session is a state machine that does no input or output itself. It has a buffer of bytes it wants to send (`tls.outLength` and `tls.outData`, then `tls.outConsumed`) and a function to feed it the bytes that arrived (`tls.feed`). That makes it work with blocking sockets, with event loops and in tests. In the first sample the "network" is a function that copies bytes from one session to the other.

{{sample crypto/tls_memory}}

**What to notice.**

* `tls.clientOnly(host, verify, 0x1303)` offers one cipher suite only (0x1301 AES-128-GCM, 0x1302 AES-256-GCM, 0x1303 ChaCha20-Poly1305). `tls.client(host, verify)` offers all three and lets the server choose.
* The key exchange is X25519, the certificate signature is checked with `rsa` or `ec`, the certificate chain with `x509`, and the records are sealed with `aes` or `chacha`. Nothing else is involved.
* `tls.shutdown` sends a `close_notify`, so that the other side knows the end of the data was not cut by an attacker.
* The certificate and the key in the helper module `pki.a` are test material. The private key is public.

What a client does when something is wrong:

{{sample crypto/tls_checks}}

**What to notice.**

* The first attempt has everything right and connects. With `verify` set, each of the next three attempts fails during the handshake, with the same messages that `x509.verifyChain` gives. The last attempt has verification off: the connection is encrypted, but you have no idea whom you are talking to. Never switch verification off in a real program.
* `client->error` holds the reason. `tls.failed(client)` says whether a session has failed.

The same handshake over a real socket, on the loopback interface. The server is a child process (so that the two sides do not share a heap), the port is chosen by the system and read back with `net.localPort`:

{{sample crypto/tls_socket}}

**What to notice.**

* After `tls.wrap(fd, host, true)` (client) or `tls.wrapServer(fd, cfg)` (server), the ordinary `net.sendText`, `net.recvLine` and `net.close` encrypt and decrypt by themselves.
* `tls.sessionOf(fd)` gives the session: the cipher suite name and the peer's certificate.
* The sample needs `fork`, so it is Linux only.

To talk to a real server, `tls.connect(host, port, true)` does the name lookup, the TCP connection and the handshake in one call. The next sample is only compiled, not run, because it needs the Internet.

{{sample crypto/tls_fetch src}}

What TLS in A does not have: TLS 1.2 and older, session resumption, 0-RTT, client certificates, and the `HelloRetryRequest` message (a server that does not accept X25519 fails with an error). This is the list in the header comment of `lib/tls.a`; the key exchange is X25519 only, and the signatures are RSA-PSS and ECDSA on P-256 and P-384.

## Passwords

A system that stores passwords must assume that its database will leak. Then the damage is limited by how expensive it is to try guesses. The right tool is a *slow, salted* password hash: slow, so that each guess costs time; salted, so that two users with the same password have different hashes and a table of precomputed hashes is useless.

`syscrypt` implements the SHA-512 crypt of `/etc/shadow` (the `$6$` format). Its hashes are the same as those of `crypt(3)`, `mkpasswd -m sha-512` and `openssl passwd -6`.

{{sample crypto/syscrypt_vector}}

**What to notice.**

* The first line is the test vector of Ulrich Drepper's specification of SHA-crypt. The last hash in the sample was made with `openssl passwd -6` and checks here.
* The result is `$6$`, the salt, `$` and 86 characters of the hash, so it is a text you can store in a file or a database column as it is.
* `syscrypt.verify(password, stored)` takes the whole stored text, reads the salt (and the number of rounds) out of it, hashes again and compares without stopping at the first difference.

{{sample crypto/syscrypt_rounds}}

**What to notice.**

* The default is 5000 rounds. `$6$rounds=N$salt` asks for another count: 1000 to 999999999, and a number outside that range is moved to the nearest limit. On the 2.1 GHz virtual machine described above (best of several runs) 5000 rounds took about 5 ms and 100000 rounds about 100 ms; a login can afford the second.
* The rounds are part of the stored text, so you can raise the count for new passwords while old ones keep working. A hash made with the default count has no `rounds=` part.
* A salt has at most 16 characters (the rest is cut) and ends at the next `$`, as the two `$6$ab` lines show. The `rounds=10000` hash in the sample is the published vector.
* Other formats are not supported. `sha512crypt` returns `null` for `$5$`, and `verify` returns `false` for `$1$` (MD5 crypt), `$y$` and plain text.

A complete small registration and login, with a random salt for each user:

{{sample crypto/password_store}}

**What to notice.**

* `newSalt()` takes 16 random bytes from `secure.bytes` and turns each into a character of the alphabet that crypt uses. Never use a name or a counter as a salt.
* Two users with the same password get two different hashes. Bob's hash also accepts Ann's password, as it should: the same password under another salt.
* The check is the call `login(password, stored)`: nothing but the stored text is needed.

SHA-512 crypt is slow but it is not *memory hard*; a modern password hash like scrypt or argon2 is harder to attack with special hardware. They are not in the library. Make passwords long, let users choose pass phrases, and raise the rounds.

## DES, for VNC only

DES is a block cipher from 1977 with a 56 bit key, which can be found by searching. It is in the library for one reason: the VNC remote screen protocol uses it to prove that a client knows the password. Do not use it for anything new.

{{sample crypto/des_block}}

**What to notice.**

* `des.encryptBlock(key8, in8, out8)` takes exactly 8 bytes and gives 8 bytes. The key is 8 bytes of which 56 bits count: the lowest bit of every byte is a parity bit that is ignored.
* The key and block are the classic worked example (`133457799bbcdff1`, `0123456789abcdef` gives `85e813540f0ab405`), and the result was checked with OpenSSL.
* The same block always encrypts to the same bytes (this is the mode called ECB). That leaks patterns in the data, so a block cipher on its own is not a way to encrypt a message.

{{sample crypto/des_vnc}}

**What to notice.**

* The VNC server sends 16 random bytes. The client encrypts them with the password as the DES key (the bits of every byte reversed, which is a quirk of VNC) and sends the result.
* Only the first 8 characters of the password count, so a longer password adds no security.
* The answer in the sample was computed with OpenSSL as well.

## Checklist

* Use `secure.bytes` for every key, nonce and salt.
* Use an AEAD (`aes.seal`, `chacha.seal`) for secrecy, with a nonce that is new for every message under the same key.
* Authenticate every key exchange, with a signature, a certificate or a shared secret.
* Compare tags, hashes and password hashes in constant time (`hash.equalConstantTime`, `syscrypt.verify`).
* Check the result of everything that can fail: `secure.bytes`, `x25519.scalarmult`, `aes.open`, `x509.verifyChain`.
* Keep keys out of source code, logs and error messages.
* Remember what these modules are: not constant time, not audited.

## Summary

* Choose the primitive by the job: hash for fingerprints, HMAC for shared-secret authenticity, AEAD for secrecy with integrity, X25519 for key agreement, ECDSA or RSA-PSS for signatures, `x509` and `tls` for identity and channels, `syscrypt` for passwords.
* A hash is not a signature, encryption is not authentication, and key agreement is not identity.
* AES-GCM and ChaCha20-Poly1305 have the same calls; both need a unique 12 byte nonce for every message under a key. Reusing one is a disaster.
* The samples check the code against published vectors (NIST, RFC 8439, RFC 7748, RFC 6979, Drepper) and against OpenSSL.
* TLS 1.3 in A is a state machine that you feed with bytes; `net` and `http` wrap it for you.
* What is missing: RSA encryption, ECDH on the NIST curves, CBC/CTR modes, Ed25519, SHA-3, key derivation functions and password hashes beyond SHA-512 crypt.
* **The implementation is from scratch, not constant time, and has not been independently audited.**

## Where next

* [HTTP, WebSocket and TLS](#chap-http-websocket-tls) for TLS in use.
* [API reference of hash](#api-hash), [secure](#api-secure), [aes](#api-aes), [chacha](#api-chacha), [x25519](#api-x25519), [rsa](#api-rsa), [ec](#api-ec), [x509](#api-x509), [tls](#api-tls), [syscrypt](#api-syscrypt) and [des](#api-des).
* [API reference of bn](#api-bn): the big number code with Montgomery multiplication that `rsa`, `ec` and `x25519` are built on.
