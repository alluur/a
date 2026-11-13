#!/usr/bin/env python3
"""A server that is out of file descriptors must not spin on accept(): usage  net2_fdlimit.py PORT PID PROTO
Opens 100 connections to a server whose descriptor limit is about 30, lets it run for a second and measures the CPU time it used (/proc/PID/stat),
then closes them and checks that the server serves a new connection (PROTO redis: PING, mqtt: CONNECT)."""
import os, socket, sys, time

port, pid, proto = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
hz = os.sysconf('SC_CLK_TCK')

def cpu():
    f = open('/proc/%d/stat' % pid).read().rsplit(')', 1)[1].split()
    return (int(f[11]) + int(f[12])) / hz           # utime + stime

socks = []
for i in range(100):
    s = socket.socket()
    s.setblocking(False)
    try:
        s.connect(('127.0.0.1', port))
    except BlockingIOError:
        pass
    except OSError:
        pass
    socks.append(s)
time.sleep(0.5)
c0, t0 = cpu(), time.time()
time.sleep(1.5)
used = (cpu() - c0) / (time.time() - t0)
for s in socks:
    s.close()
time.sleep(0.5)
ok = used < 0.4
print('cpu while at the descriptor limit: %.0f%% (%s)' % (used * 100, 'ok' if ok else 'too much: the listener spins'))
# the server recovers: a new connection is served
s = socket.create_connection(('127.0.0.1', port), timeout=3)
if proto == 'redis':
    s.sendall(b'PING\r\n')
    served = s.recv(100) == b'+PONG\r\n'
else:
    s.sendall(bytes([0x10, 0x0e, 0, 4]) + b'MQTT' + bytes([4, 2, 0, 60, 0, 2]) + b'fd')
    served = s.recv(100)[:4] == bytes([0x20, 2, 0, 0])
print('served again after the connections were closed: %s' % ('ok' if served else 'NO'))
sys.exit(0 if ok and served else 1)
