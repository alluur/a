#!/usr/bin/env python3
"""redisd against the findings of the second review, with a client that is not written in A: usage  net2_redisd_limits.py PORT PID
 1. 300 connections that announce a bulk string of 16 MiB and send nothing must not make the server allocate memory (resident size, /proc/PID/status)
 2. 4000 keys with a life of 100 ms, written in one pipeline, are swept away by the server within 3 seconds (DBSIZE 0)
(The keys that collide in the hash of the first version are made and checked by t394, which does not need a second program.)
Exit status 0 if every check passed."""
import os, socket, sys, time

port, pid = int(sys.argv[1]), int(sys.argv[2])
fails = 0

def check(name, ok, extra=''):
    global fails
    print(('ok   ' if ok else 'FAIL ') + name, extra)
    if not ok: fails += 1

def rss():
    for l in open('/proc/%d/status' % pid):
        if l.startswith('VmRSS'):
            return int(l.split()[1])         # KB
    return -1

def cmd(s, *args):
    out = b'*%d\r\n' % len(args)
    for a in args:
        a = a if isinstance(a, bytes) else str(a).encode()
        out += b'$%d\r\n%s\r\n' % (len(a), a)
    s.sendall(out)

def readline(s):
    buf = b''
    while not buf.endswith(b'\r\n'):
        d = s.recv(1)
        if not d: return None
        buf += d
    return buf

c = socket.create_connection(('127.0.0.1', port), timeout=10)
before = rss()
socks = []
for i in range(300):
    x = socket.create_connection(('127.0.0.1', port), timeout=5)
    x.sendall(b'*1\r\n$16777216\r\n')
    socks.append(x)
time.sleep(1.0)
after = rss()
check('300 connections that announce 16 MiB each: the resident size grows by %d KB (was 9.6 GB)' % (after - before), after - before < 20000)
for x in socks: x.close()
time.sleep(0.5)
cmd(c, 'PING'); check('the server still answers', readline(c) == b'+PONG\r\n')

# 2. a pile of keys with a short life
batch = b''.join(b'*5\r\n$3\r\nSET\r\n$%d\r\nex%d\r\n$1\r\nv\r\n$2\r\nPX\r\n$3\r\n100\r\n' % (len(b'ex%d' % i), i) for i in range(4000))
c.sendall(batch)
n = 0
while n < 4000:
    l = readline(c)
    if l is None: break
    n += 1
cmd(c, 'DBSIZE'); first = readline(c)
t0 = time.time(); left = None
while time.time() - t0 < 3.0:
    cmd(c, 'DBSIZE'); left = int(readline(c)[1:])
    if left == 0: break
    time.sleep(0.1)
check('4000 keys with PX 100: DBSIZE %s right after, %s after %.1f s (the old sweep needed minutes)' % (first.strip().decode(), left, time.time() - t0), left == 0)

cmd(c, 'FLUSHALL'); readline(c)
sys.exit(1 if fails else 0)
