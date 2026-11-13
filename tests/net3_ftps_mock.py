#!/usr/bin/env python3
# A small FTPS server in the order that vsftpd, ProFTPD and FileZilla Server use, for tests/net3.sh (the A client module ftp against a server that is not ftpd):
# the data connection is taken when the transfer command arrives, "150" is sent FIRST and the TLS handshake of the data connection happens after it.
# (The first version of the A modules handshook first and sent 150 after it: it only worked with itself.) Usage: net3_ftps_mock.py PORTFILE CERT KEY
# Commands: AUTH TLS, USER, PASS, PBSZ, PROT, TYPE, FEAT, EPSV, PASV, EPRT, PORT, RETR, STOR, LIST, NLST, NOOP, QUIT. RETR hello.txt gives 16 bytes; every other name is 550.
import socket, ssl, threading, sys, re

portfile, certfile, keyfile = sys.argv[1], sys.argv[2], sys.argv[3]
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(certfile, keyfile)
ls = socket.socket()
ls.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
ls.bind(("127.0.0.1", 0))
ls.listen(5)
open(portfile, "w").write(str(ls.getsockname()[1]))
stored = {}


def serve(c):
    f = c.makefile("rb")

    def send(s):
        c.sendall(s.encode() + b"\r\n")

    send("220 mock FTPS")
    pasv = None
    active = None
    while True:
        line = f.readline()
        if not line:
            return
        cmd = line.decode().strip()
        verb, _, arg = cmd.partition(" ")
        verb = verb.upper()
        if verb == "AUTH":
            send("234 go")
            c = ctx.wrap_socket(c, server_side=True)
            f = c.makefile("rb")
        elif verb == "USER":
            send("331 password please")
        elif verb == "PASS":
            send("230 ok")
        elif verb in ("PBSZ", "PROT", "TYPE", "OPTS"):
            send("200 ok")
        elif verb == "FEAT":
            send("211-features\r\n AUTH TLS\r\n SIZE\r\n211 End")
        elif verb in ("EPSV", "PASV"):
            if pasv:
                pasv.close()
            pasv = socket.socket()
            pasv.bind(("127.0.0.1", 0))
            pasv.listen(1)
            active = None
            p = pasv.getsockname()[1]
            send("229 Entering Extended Passive Mode (|||%d|)" % p if verb == "EPSV" else "227 Entering Passive Mode (127,0,0,1,%d,%d)" % (p >> 8, p & 255))
        elif verb == "EPRT":
            m = re.match(r"\|1\|([\d.]+)\|(\d+)\|", arg)
            active = (m.group(1), int(m.group(2)))
            send("200 ok")
        elif verb == "PORT":
            n = [int(x) for x in arg.split(",")]
            active = ("%d.%d.%d.%d" % tuple(n[:4]), n[4] * 256 + n[5])
            send("200 ok")
        elif verb in ("RETR", "STOR", "LIST", "NLST"):
            if verb == "RETR" and arg != "hello.txt":
                send("550 no such file")
                if pasv:
                    pasv.close()
                    pasv = None
                continue
            if active:
                d = socket.create_connection(active)
            else:
                d, _ = pasv.accept()
                pasv.close()
                pasv = None
            send("150 here we go")
            d = ctx.wrap_socket(d, server_side=True)        # the handshake AFTER the 150
            if verb == "STOR":
                buf = b""
                while True:
                    x = d.recv(65536)
                    if not x:
                        break
                    buf += x
                stored[arg] = buf
                d.close()
                send("226 stored %d bytes" % len(buf))
            else:
                d.sendall({"RETR": b"hello from mock\n", "LIST": b"-rw-r--r--   1 ftp ftp 16 Jan  1  2020 hello.txt\r\n", "NLST": b"hello.txt\r\n"}[verb])
                d.close()
                send("226 done")
        elif verb == "SIZE":
            send("213 16" if arg == "hello.txt" else "550 no")
        elif verb == "NOOP":
            send("200 ok")
        elif verb == "QUIT":
            send("221 bye")
            return
        else:
            send("502 no")


while True:
    c, _ = ls.accept()
    threading.Thread(target=serve, args=(c,), daemon=True).start()
