#!/usr/bin/env python3
# A raw-socket MQTT 3.1.1 client written from the specification (no library): checks mqttd on the given port. Exit status 0 if every check passed.
import socket, struct, sys, time

port = int(sys.argv[1])
fails = 0

def check(name, ok):
    global fails
    print(("ok   " if ok else "FAIL ") + name)
    if not ok:
        fails += 1

def enc_len(n):
    out = b''
    while True:
        b = n % 128; n //= 128
        if n: b |= 128
        out += bytes([b])
        if not n: return out

def s(x): return struct.pack('>H', len(x)) + x
def pkt(t, flags, body): return bytes([(t << 4) | flags]) + enc_len(len(body)) + body

def connect_pkt(cid, clean=True, ka=30, will=None):
    fl = 2 if clean else 0
    pl = s(cid.encode())
    if will:
        fl |= 4 | (will[2] << 3)
        pl += s(will[0].encode()) + s(will[1])
    return pkt(1, 0, s(b'MQTT') + bytes([4, fl]) + struct.pack('>H', ka) + pl)

def read_pkt(sock):
    h = sock.recv(1)
    if not h: return None
    mult = 1; ln = 0
    while True:
        b = sock.recv(1)[0]; ln += (b & 127) * mult; mult *= 128
        if not b & 128: break
    body = b''
    while len(body) < ln: body += sock.recv(ln - len(body))
    return h[0] >> 4, h[0] & 15, body

def mk(cid, **kw):
    c = socket.create_connection(('127.0.0.1', port)); c.settimeout(3)
    c.sendall(connect_pkt(cid, **kw))
    return c, read_pkt(c)

a, r = mk('pyA');                         check('CONNACK accepted', r == (2, 0, b'\x00\x00'))
b, r = mk('pyB', will=('will/b', b'gone', 1))
check('second client', r == (2, 0, b'\x00\x00'))
a.sendall(pkt(8, 2, struct.pack('>H', 1) + s(b'sensor/#') + bytes([2]) + s(b'will/+') + bytes([1])))
check('SUBACK grants 2 and 1', read_pkt(a) == (9, 0, b'\x00\x01\x02\x01'))
b.sendall(pkt(3, 0, s(b'sensor/1/temp') + b'21.5'))
check('QoS 0 message delivered', read_pkt(a) == (3, 0, s(b'sensor/1/temp') + b'21.5'))
b.sendall(pkt(3, 2, s(b'sensor/2') + struct.pack('>H', 7) + b'qos1'))
check('PUBACK for QoS 1', read_pkt(b) == (4, 0, b'\x00\x07'))
r = read_pkt(a)
check('QoS 1 message delivered with QoS 1', r[0] == 3 and r[1] & 6 == 2 and r[2].startswith(s(b'sensor/2')) and r[2].endswith(b'qos1'))
b.sendall(pkt(3, 4, s(b'sensor/3') + struct.pack('>H', 8) + b'qos2'))
check('PUBREC for QoS 2', read_pkt(b) == (5, 0, b'\x00\x08'))
b.sendall(pkt(6, 2, struct.pack('>H', 8)))
check('PUBCOMP after PUBREL', read_pkt(b) == (7, 0, b'\x00\x08'))
r = read_pkt(a)
check('QoS 2 message delivered', r[0] == 3 and r[1] & 6 == 4)
pid = struct.unpack('>H', r[2][2 + len(b'sensor/3'):4 + len(b'sensor/3')])[0]
a.sendall(pkt(5, 0, struct.pack('>H', pid)))
check('PUBREL from the broker', read_pkt(a) == (6, 2, struct.pack('>H', pid)))
a.sendall(pkt(7, 0, struct.pack('>H', pid)))
b.sendall(pkt(3, 1, s(b'ret/x') + b'kept'))
time.sleep(0.1)
c, r = mk('pyC')
c.sendall(pkt(8, 2, struct.pack('>H', 2) + s(b'ret/+') + bytes([0])))
check('SUBACK', read_pkt(c) == (9, 0, b'\x00\x02\x00'))
check('retained message with the retain flag', read_pkt(c) == (3, 1, s(b'ret/x') + b'kept'))
c.sendall(pkt(12, 0, b''))
check('PINGRESP', read_pkt(c) == (13, 0, b''))
b.close(); time.sleep(0.2)
r = read_pkt(a)
check('will message of a vanished client', r[0] == 3 and r[2].startswith(s(b'will/b')) and r[2].endswith(b'gone'))
c.sendall(pkt(8, 2, struct.pack('>H', 3) + s(b'$SYS/broker/clients/connected') + bytes([0])))
read_pkt(c)
r = read_pkt(c)
check('$SYS counter of connected clients', r is not None and r[0] == 3 and r[2][2:2 + len(b'$SYS/broker/clients/connected')] == b'$SYS/broker/clients/connected' and r[2].endswith(b'2'))
d, r = mk('pyD')
d.sendall(b'\x00\x00')
time.sleep(0.2)
check('a malformed packet closes the connection', d.recv(10) == b'')
e = socket.create_connection(('127.0.0.1', port)); e.settimeout(3)
e.sendall(pkt(1, 0, s(b'MQIsdp') + bytes([3, 2]) + struct.pack('>H', 30) + s(b'old')))
check('MQTT 3.1 is answered with CONNACK 1', read_pkt(e) == (2, 0, b'\x00\x01'))
sys.exit(1 if fails else 0)
