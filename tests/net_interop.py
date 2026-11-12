#!/usr/bin/env python3
"""Interoperability checks for the A networking modules against independent implementations: the Python
websockets package (client and server, permessage-deflate, wss), curl (HTTP, Range, chunked, 100-continue, multipart, JSON-RPC),
requests (Server-Sent Events) and raw sockets (RFC 6455 violations). Started by tests/net.sh with the paths of the built programs."""
import asyncio, os, socket, ssl, struct, subprocess, sys, time, json, tempfile, hashlib, base64

hub_demo, ws_cat, wss_echo, workdir, cert, key = sys.argv[1:7]
results = []

def ok(name, cond, extra=""):
    results.append(bool(cond))
    print(("ok    " if cond else "FAIL  ") + name + ((" -- " + str(extra)) if (not cond and extra) else ""))

def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); return p

def start(args, wait_line="listening", env=None):
    p = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)
    t0 = time.time()
    while time.time() - t0 < 10:
        line = p.stdout.readline()
        if wait_line in line: return p
    p.kill(); raise RuntimeError("did not start: " + " ".join(args))

def raw_handshake(port, extra=""):
    s = socket.create_connection(("127.0.0.1", port), timeout=5)
    key = base64.b64encode(os.urandom(16)).decode()
    s.sendall(("GET / HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n%s\r\n" % (key, extra)).encode())
    buf = b""
    while b"\r\n\r\n" not in buf: buf += s.recv(4096)
    return s, buf

def frame(op, payload, fin=True, mask=True, rsv=0):
    b0 = (0x80 if fin else 0) | (rsv << 4) | op
    n = len(payload); m = 0x80 if mask else 0
    h = bytes([b0])
    if n < 126: h += bytes([m | n])
    elif n < 65536: h += bytes([m | 126]) + struct.pack(">H", n)
    else: h += bytes([m | 127]) + struct.pack(">Q", n)
    if mask:
        k = os.urandom(4); h += k
        payload = bytes(c ^ k[i % 4] for i, c in enumerate(payload))
    return h + payload

def read_close(s):
    """reads frames until a close frame; returns its code (or None when the connection ended)"""
    s.settimeout(5); data = b""
    try:
        while True:
            c = s.recv(4096)
            if not c: return None if len(data) < 2 else parse_close(data)
            data += c
            r = parse_close(data)
            if r is not None: return r
    except socket.timeout:
        return None

def parse_close(data):
    i = 0
    while i + 2 <= len(data):
        op = data[i] & 15; n = data[i + 1] & 127; i += 2
        if n == 126: n = struct.unpack(">H", data[i:i+2])[0]; i += 2
        if len(data) < i + n: return None
        if op == 8: return struct.unpack(">H", data[i:i+2])[0] if n >= 2 else 1005
        i += n
    return None

async def main():
    try:
        import websockets
    except ImportError:
        websockets = None
    www = os.path.join(workdir, "www"); os.makedirs(www, exist_ok=True)
    open(os.path.join(www, "index.html"), "w").write("<h1>hi</h1>")
    big = bytes((i * 7) % 251 for i in range(100000))
    open(os.path.join(www, "big.bin"), "wb").write(big)
    open(os.path.join(www, "a.txt"), "w").write("0123456789abcdefghij")
    port = free_port(); tport = free_port()
    hub = start([hub_demo, str(port), www])
    thub = start([hub_demo, str(tport), www, cert, key])
    env = dict(os.environ, SSL_CERT_FILE=cert)
    try:
        # ---- websockets (Python) -> the A hub
        if websockets:
            async with websockets.connect("ws://127.0.0.1:%d/" % port, subprotocols=["echo"]) as ws:
                await ws.send("hello"); ok("python client -> hub: text echo", await ws.recv() == "hello")
                ok("subprotocol negotiated", ws.subprotocol == "echo")
                ok("permessage-deflate negotiated", any(e.name == "permessage-deflate" for e in ws.protocol.extensions))
                t = "abc def " * 20000
                await ws.send(t); ok("160 KB compressible text (compressed both ways)", await ws.recv() == t)
                b = os.urandom(300000)
                await ws.send(b); ok("300 KB random binary", await ws.recv() == b)
                await ws.send("é€𝄞 UTF-8"); ok("UTF-8", await ws.recv() == "é€𝄞 UTF-8")
                async def frags():
                    yield "frag"; yield "ment"; yield "ed"
                await ws.send(frags()); ok("a fragmented message", await ws.recv() == "fragmented")
                pong = await ws.ping(); await asyncio.wait_for(pong, 5); ok("ping answered", True)
                await ws.close(1001, "going"); ok("close handshake", ws.close_code == 1001)
            async with websockets.connect("ws://127.0.0.1:%d/" % port, subprotocols=["nope"]) as ws:
                ok("an unknown subprotocol: connected without one", ws.subprotocol is None)
            async with websockets.connect("ws://127.0.0.1:%d/" % port, compression=None) as ws:
                await ws.send("plain"); ok("without compression", await ws.recv() == "plain" and not ws.protocol.extensions)
            # rooms and a second client
            async with websockets.connect("ws://127.0.0.1:%d/" % port) as a, websockets.connect("ws://127.0.0.1:%d/" % port) as b:
                await a.send("join r1"); await b.send("join r1"); await asyncio.sleep(0.2)
                await a.send("pub r1 news!"); ok("rooms: publish reaches the other client", await asyncio.wait_for(b.recv(), 5) == "news!")
            # wss
            ctx = ssl.create_default_context(cafile=cert)
            async with websockets.connect("wss://localhost:%d/" % tport, ssl=ctx) as ws:
                await ws.send("secure"); ok("python wss client -> TLS hub (certificate verified)", await ws.recv() == "secure")
                big2 = os.urandom(200000); await ws.send(big2); ok("200 KB over wss", await ws.recv() == big2)
            # A client -> Python server
            async def handler(ws):
                async for m in ws: await ws.send("py:" + m if isinstance(m, str) else m)
            srv = await websockets.serve(handler, "127.0.0.1", 0, subprotocols=["chat"], origins=["https://good.example", None])
            sp = srv.sockets[0].getsockname()[1]
            async def run(args, e=None):
                # not subprocess.run: the python servers live in this event loop and must keep running meanwhile
                p = await asyncio.create_subprocess_exec(*args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT, env=e or os.environ)
                out, _ = await asyncio.wait_for(p.communicate(), 30)
                return out.decode()
            out = await run([ws_cat, "ws://127.0.0.1:%d/" % sp, "--protocol", "chat", "--deflate", "hello", "wörld"])
            ok("A client -> python server: echo, subprotocol, deflate", "py:hello" in out and "py:wörld" in out and "protocol=[chat] deflate=1" in out and "closed 1000" in out, out)
            out = await run([ws_cat, "ws://127.0.0.1:%d/" % sp, "--origin", "https://evil.example", "x"])
            ok("A client: a refused Origin (403) is reported", "connect failed" in out and "403" in out, out)
            out = await run([ws_cat, "ws://127.0.0.1:%d/" % sp, "--origin", "https://good.example", "x"])
            ok("A client: an allowed Origin", "py:x" in out, out)
            srv.close(); await srv.wait_closed()
            ssrv = await websockets.serve(handler, "localhost", 0, ssl=ssl.create_default_context(ssl.Purpose.CLIENT_AUTH))
            ssrv.close(); await ssrv.wait_closed()
            sctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); sctx.load_cert_chain(cert, key); sctx.minimum_version = ssl.TLSVersion.TLSv1_3
            ssrv = await websockets.serve(handler, "127.0.0.1", 0, ssl=sctx)
            sp = ssrv.sockets[0].getsockname()[1]
            out = await run([ws_cat, "wss://127.0.0.1:%d/" % sp, "secure"], env)
            ok("A client -> python wss server, certificate trusted through SSL_CERT_FILE", "py:secure" in out, out)
            out = await run([ws_cat, "wss://127.0.0.1:%d/" % sp, "secure"], dict(os.environ, SSL_CERT_FILE="/nonexistent"))
            ok("A client refuses the same server without that trust", "connect failed" in out, out)
            out = await run([ws_cat, "wss://127.0.0.1:%d/" % sp, "--insecure", "secure"], dict(os.environ, SSL_CERT_FILE="/nonexistent"))
            ok("... and talks to it with --insecure", "py:secure" in out, out)
            ssrv.close(); await ssrv.wait_closed()
            # A blocking wss server (acceptTls) <- python client
            wp = free_port()
            wproc = start([wss_echo, str(wp), cert, key], "echo server")
            try:
                async with websockets.connect("wss://localhost:%d/" % wp, ssl=ssl.create_default_context(cafile=cert)) as ws:
                    await ws.send("blocking"); ok("python client -> A blocking wss server (acceptTls)", await ws.recv() == "blocking")
            finally:
                wproc.kill()
        else:
            print("skip  the python websockets package is not installed: no client/server interop checks")

        # ---- raw frames against the hub: every violation is answered with the right close code
        def violate(name, data, want, extra=""):
            s, resp = raw_handshake(port, extra)
            try: s.sendall(data)
            except OSError: pass
            code = read_close(s); s.close()
            ok("raw: " + name + " -> " + str(want), code == want, code)
        violate("reserved bit RSV2", frame(1, b"x", rsv=2), 1002)
        violate("RSV1 without the extension", frame(1, b"x", rsv=4), 1002)
        violate("unknown opcode 3", frame(3, b"x"), 1002)
        violate("an unmasked client frame", frame(1, b"x", mask=False), 1002)
        violate("a fragmented ping", frame(9, b"x", fin=False), 1002)
        violate("a ping of 126 bytes", frame(9, b"x" * 126), 1002)
        violate("a continuation without a message", frame(0, b"x"), 1002)
        violate("a new message inside a fragmented one", frame(1, b"a", fin=False) + frame(1, b"b"), 1002)
        violate("invalid UTF-8", frame(1, b"\xc3\x28"), 1007)
        violate("a surrogate", frame(1, b"\xed\xa0\x80"), 1007)
        violate("invalid UTF-8 split over fragments", frame(1, b"ab\xe2\x82", fin=False) + frame(0, b"\x28"), 1007)
        violate("close code 1005 on the wire", frame(8, struct.pack(">H", 1005)), 1002)
        violate("close code 999", frame(8, struct.pack(">H", 999)), 1002)
        violate("a one byte close payload", frame(8, b"x"), 1002)
        violate("an invalid close reason", frame(8, struct.pack(">H", 1000) + b"\xff"), 1007)
        violate("1 MB + 1 message (maxMessage)", frame(2, b"x" * (1048577)), 1009)
        # a valid close is echoed
        s, _ = raw_handshake(port); s.sendall(frame(8, struct.pack(">H", 1000) + b"bye")); ok("raw: a valid close is echoed with the code", read_close(s) == 1000); s.close()
        # pipelined HTTP requests on one connection
        s = socket.create_connection(("127.0.0.1", port), timeout=5)
        s.sendall(b"GET /api/hello?name=A HTTP/1.1\r\nHost: x\r\n\r\nGET /api/hello?name=B HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
        data = b""
        while True:
            c = s.recv(4096)
            if not c: break
            data += c
        ok("pipelined requests are answered in order", data.find(b"hello, A") != -1 and data.find(b"hello, A") < data.find(b"hello, B"), data)

        # ---- curl against the hub
        def curl(*args):
            return subprocess.run(["curl", "-s", "-S", "--max-time", "20"] + list(args), capture_output=True, text=False, timeout=30)
        base = "http://127.0.0.1:%d" % port
        r = curl(base + "/healthz"); ok("curl /healthz", b'"status":"ok"' in r.stdout, r.stdout)
        r = curl(base + "/api/hello?name=Ada%20L"); ok("curl a route with a query", r.stdout == b"hello, Ada L", r.stdout)
        r = curl(base + "/big.bin"); ok("curl a 100 KB file (streamed)", r.stdout == big)
        r = curl("-r", "5-9", base + "/a.txt"); ok("curl a range", r.stdout == b"56789", r.stdout)
        r = curl("-r", "-4", base + "/a.txt"); ok("curl a suffix range", r.stdout == b"ghij", r.stdout)
        r = curl("-D", "-", "-o", "/dev/null", base + "/a.txt"); hdr = r.stdout.decode()
        etag = [l.split(": ", 1)[1].strip() for l in hdr.split("\r\n") if l.lower().startswith("etag")][0]
        r = curl("-s", "-o", "/dev/null", "-w", "%{http_code}", "-H", "If-None-Match: " + etag, base + "/a.txt"); ok("curl If-None-Match -> 304", r.stdout == b"304", r.stdout)
        lm = [l.split(": ", 1)[1].strip() for l in hdr.split("\r\n") if l.lower().startswith("last-modified")][0]
        r = curl("-s", "-o", "/dev/null", "-w", "%{http_code}", "-H", "If-Modified-Since: " + lm, base + "/a.txt"); ok("curl If-Modified-Since -> 304", r.stdout == b"304", r.stdout)
        r = curl("-s", "-o", "/dev/null", "-w", "%{http_code}", base + "/../../etc/passwd", "--path-as-is"); ok("curl path traversal is refused", r.stdout in (b"403", b"404"), r.stdout)
        rpc = '{"jsonrpc":"2.0","method":"add","params":[40,2],"id":1}'
        r = curl("-H", "Content-Type: application/json", "-d", rpc, base + "/rpc"); ok("curl JSON-RPC over HTTP", json.loads(r.stdout) == {"jsonrpc": "2.0", "result": 42, "id": 1}, r.stdout)
        p = subprocess.run(["curl", "-s", "-H", "Transfer-Encoding: chunked", "-H", "Content-Type: application/json", "--data-binary", "@-", base + "/rpc"], input=rpc.encode(), capture_output=True, timeout=30)
        ok("curl with a chunked request body", json.loads(p.stdout)["result"] == 42, p.stdout)
        r = curl("-H", "Expect: 100-continue", "-d", rpc, "-D", "-", base + "/rpc"); ok("curl Expect: 100-continue", b"100 Continue" in r.stdout and b'"result":42' in r.stdout, r.stdout)
        batch = '[{"jsonrpc":"2.0","method":"add","params":{"a":1,"b":2},"id":"a"},{"jsonrpc":"2.0","method":"nope","id":2},{"jsonrpc":"2.0","method":"time"}]'
        r = curl("-d", batch, base + "/rpc"); res = json.loads(r.stdout)
        ok("curl a JSON-RPC batch", len(res) == 2 and res[0]["result"] == 3 and res[1]["error"]["code"] == -32601, r.stdout)
        open(os.path.join(workdir, "up.txt"), "w").write("uploaded text")
        r = curl("-F", "name=Ada", "-F", "doc=@" + os.path.join(workdir, "up.txt") + ";type=text/plain", base + "/upload")
        ok("curl -F: multipart form with a file", b"field name=Ada" in r.stdout and b"file doc=up.txt:13" in r.stdout, r.stdout)
        r = curl("-k", "https://127.0.0.1:%d/healthz" % tport); ok("curl https (-k) against the TLS hub", b'"status":"ok"' in r.stdout, r.stdout)
        r = curl("--cacert", cert, "--tlsv1.3", "https://localhost:%d/api/hello" % tport); ok("curl https with the certificate checked", r.stdout == b"hello, world", r.stdout)

        # ---- Server-Sent Events
        try:
            import requests
            resp = requests.get(base + "/events", stream=True, timeout=10)
            ok("SSE: text/event-stream", resp.headers.get("Content-Type", "").startswith("text/event-stream"))
            lines = []
            t0 = time.time()
            for line in resp.iter_lines(chunk_size=1, decode_unicode=True):
                lines.append(line)
                if any(l.startswith("data: tick") for l in lines) or time.time() - t0 > 6: break
            resp.close()
            ok("SSE: the greeting event and a tick (python requests)", "event: hello" in lines and "data: welcome" in lines and any(l.startswith("data: tick") for l in lines), lines)
        except ImportError:
            print("skip  python requests is not installed: no SSE check")
    finally:
        hub.kill(); thub.kill()
    print("%d of %d checks passed" % (sum(results), len(results)))
    return all(results)

sys.exit(0 if asyncio.run(main()) else 1)
