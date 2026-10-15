"""A client of the web display backend (wweb) written independently of the A code: HTTP, WebSocket framing, the run-length
pixel format, and input messages. It keeps a frame buffer like the browser page does."""
import base64, os, socket, struct, time


class WebDisplay:
    def __init__(self, port, token="", host="127.0.0.1", origin="same", timeout=5):
        self.s = socket.create_connection((host, port), timeout=timeout)
        key = base64.b64encode(os.urandom(16)).decode()
        hosthdr = "%s:%d" % (host, port)
        req = "GET /ws?t=%s HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n" % (token, hosthdr, key)
        if origin == "same":
            req += "Origin: http://%s\r\n" % hosthdr
        elif origin:
            req += "Origin: %s\r\n" % origin
        self.s.sendall((req + "\r\n").encode())
        head = b""
        while b"\r\n\r\n" not in head:
            chunk = self.s.recv(1)
            if not chunk:
                raise ConnectionError("closed")
            head += chunk
        self.status = int(head.split(b" ")[1])
        self.head = head.decode()
        if self.status != 101:
            raise ConnectionRefusedError(self.status)
        import hashlib
        want = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
        assert want in self.head, self.head
        self.w = self.h = 0
        self.fb = None
        self.buf = b""
        self.updates = 0

    def _need(self, n):
        while len(self.buf) < n:
            chunk = self.s.recv(65536)
            if not chunk:
                raise ConnectionError("closed")
            self.buf += chunk

    def _frame(self):
        self._need(2)
        b0, b1 = self.buf[0], self.buf[1]
        ln = b1 & 0x7F
        off = 2
        if ln == 126:
            self._need(4); ln = struct.unpack(">H", self.buf[2:4])[0]; off = 4
        elif ln == 127:
            self._need(10); ln = struct.unpack(">Q", self.buf[2:10])[0]; off = 10
        assert not (b1 & 0x80), "server frames are not masked"
        self._need(off + ln)
        payload = self.buf[off:off + ln]
        self.buf = self.buf[off + ln:]
        return b0 & 15, payload

    def _message(self, data):
        t = data[0]
        if t == 1:
            self.w, self.h = struct.unpack(">HH", data[1:5])
            self.fb = bytearray(self.w * self.h * 3)
        elif t == 2:
            x, y, w, h = struct.unpack(">HHHH", data[1:9])
            p, i, n = 9, 0, w * h
            while i < n and p < len(data):
                c = data[p]; p += 1
                if c < 128:
                    for _ in range(c + 1):
                        self._put(x, y, w, i, data[p:p + 3]); p += 3; i += 1
                else:
                    px = data[p:p + 3]; p += 3
                    for _ in range(c - 125):
                        self._put(x, y, w, i, px); i += 1
            assert i == n, (i, n)
            self.updates += 1

    def _put(self, x, y, w, i, px):
        o = ((y + i // w) * self.w + x + i % w) * 3
        self.fb[o:o + 3] = px

    def pump(self, seconds=0.5):
        """reads messages for a while"""
        end = time.time() + seconds
        self.s.settimeout(0.1)
        while time.time() < end:
            try:
                op, payload = self._frame()
            except socket.timeout:
                continue
            if op == 2:
                self._message(payload)
            elif op == 8:
                raise ConnectionError("closed by the server")
        self.s.settimeout(5)

    def pixel(self, x, y):
        o = (y * self.w + x) * 3
        return tuple(self.fb[o:o + 3])

    def find_color(self, rgb, tol=6):
        x0 = y0 = 10**9; x1 = y1 = -1
        for y in range(self.h):
            for x in range(self.w):
                p = self.pixel(x, y)
                if all(abs(p[i] - rgb[i]) <= tol for i in range(3)):
                    x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x); y1 = max(y1, y)
        return (x0, y0, x1, y1) if x1 >= 0 else None

    # ---- input (the browser's messages) ----
    def _send(self, payload):
        mask = os.urandom(4)
        n = len(payload)
        hdr = bytes([0x82, 0x80 | n]) if n < 126 else bytes([0x82, 0x80 | 126]) + struct.pack(">H", n)
        self.s.sendall(hdr + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))

    def move(self, x, y): self._send(bytes([1]) + struct.pack(">HH", x, y))
    def down(self, b=1): self._send(bytes([2, b]))
    def up(self, b=1): self._send(bytes([3, b]))
    def wheel(self, d): self._send(bytes([4, d & 255]))
    def click(self, x, y):
        self.move(x, y); self.down(); self.up()
    def key(self, code, uni=0, down=True):
        self._send(bytes([5]) + struct.pack(">HI", code, uni) if down else bytes([6]) + struct.pack(">H", code))
    def type_text(self, text):
        for ch in text:
            self.key(ord(ch.lower()) if ch.isalpha() else ord(ch), ord(ch), True)
            self.key(ord(ch.lower()) if ch.isalpha() else ord(ch), 0, False)
