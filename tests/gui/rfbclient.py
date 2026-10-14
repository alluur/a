#!/usr/bin/env python3
"""A minimal RFB (VNC) client for testing the VNC backend: connects, grabs the screen, sends mouse and key events."""
import socket, struct, time

class Rfb:
    def __init__(self, host="127.0.0.1", port=5900, timeout=5):
        self.s = socket.create_connection((host, port), timeout=timeout)
        ver = self.recvn(12)
        assert ver.startswith(b"RFB 003.00"), ver
        self.s.sendall(b"RFB 003.008\n")
        n = self.recvn(1)[0]
        types = self.recvn(n)
        assert 1 in types, types
        self.s.sendall(bytes([1]))
        res = struct.unpack(">I", self.recvn(4))[0]
        assert res == 0, res
        self.s.sendall(bytes([1]))                       # shared
        self.w, self.h = struct.unpack(">HH", self.recvn(4))
        self.pf = self.recvn(16)
        nl = struct.unpack(">I", self.recvn(4))[0]
        self.name = self.recvn(nl).decode()
        self.fb = bytearray(self.w * self.h * 4)

    def recvn(self, n):
        buf = b""
        while len(buf) < n:
            c = self.s.recv(n - len(buf))
            if not c:
                raise EOFError("connection closed")
            buf += c
        return buf

    def request(self, incremental=0, x=0, y=0, w=None, h=None):
        w = self.w if w is None else w
        h = self.h if h is None else h
        self.s.sendall(struct.pack(">BBHHHH", 3, incremental, x, y, w, h))

    def read_update(self):
        hdr = self.recvn(4)
        assert hdr[0] == 0, hdr
        n = struct.unpack(">H", hdr[2:4])[0]
        for _ in range(n):
            x, y, w, h, enc = struct.unpack(">HHHHi", self.recvn(12))
            assert enc == 0, enc
            data = self.recvn(w * h * 4)
            for row in range(h):
                o = ((y + row) * self.w + x) * 4
                self.fb[o:o + w * 4] = data[row * w * 4:(row + 1) * w * 4]

    def grab(self, incremental=0):
        self.request(incremental)
        self.read_update()

    def pixel(self, x, y):
        o = (y * self.w + x) * 4
        return (self.fb[o + 2], self.fb[o + 1], self.fb[o])      # r, g, b

    def pointer(self, x, y, mask=0):
        self.s.sendall(struct.pack(">BBHH", 5, mask, x, y))

    def click(self, x, y):
        self.pointer(x, y, 0)
        self.pointer(x, y, 1)
        self.pointer(x, y, 0)

    def key(self, sym, down):
        self.s.sendall(struct.pack(">BBHI", 4, down, 0, sym))

    def type_text(self, text):
        for ch in text:
            self.key(ord(ch), 1)
            self.key(ord(ch), 0)

    def find_color(self, rgb, tol=6):
        """bounding box of all pixels with this colour"""
        x0 = y0 = 10**9; x1 = y1 = -1
        for y in range(self.h):
            for x in range(self.w):
                p = self.pixel(x, y)
                if all(abs(p[i] - rgb[i]) <= tol for i in range(3)):
                    x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x); y1 = max(y1, y)
        return (x0, y0, x1, y1) if x1 >= 0 else None

    def save_ppm(self, path):
        with open(path, "wb") as f:
            f.write(b"P6\n%d %d\n255\n" % (self.w, self.h))
            for i in range(self.w * self.h):
                f.write(bytes((self.fb[i * 4 + 2], self.fb[i * 4 + 1], self.fb[i * 4])))
