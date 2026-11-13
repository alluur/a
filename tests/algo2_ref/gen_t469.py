"""Expected output of tests/t469_numeric_bitexact.a: the same algorithms in the same order of operations, run with plain Python floats (IEEE 754 doubles on the hardware of the machine
that generates the file). Python never fuses a multiply with an add and math.sqrt is correctly rounded, exactly as in the soft float of A, so every bit must agree. Only + - * / and
the square root are used, so no library function (exp, sin ...) is involved."""
import math, struct

def bits(v): return struct.unpack('<Q', struct.pack('<d', v))[0]
seed = 31415926
def lcg():
    global seed
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    return seed
def rnd(): return (lcg() % 2001 - 1000) / 64.0
out = []
def show(label, vs):
    if isinstance(vs, float): out.append('%s: %d' % (label, bits(vs)))
    else: out.append('%s: %s' % (label, ' '.join(str(bits(v)) for v in vs)))

def neumaier(x):
    s = 0.0; c = 0.0
    for v in x:
        t = s + v
        if abs(s) >= abs(v): c += (s - t) + v
        else: c += (v - t) + s
        s = t
    return s + c
def mean(x): return neumaier(x) / float(len(x))
def variance(x, ddof):
    n = len(x); m = mean(x); s = 0.0; c = 0.0
    for v in x:
        d = v - m; s += d * d; c += d
    v = (s - c * c / float(n)) / float(n - ddof)
    return 0.0 if v < 0.0 else v

x = [rnd() * 0.37 for _ in range(500)]
show('sum', neumaier(x))
show('mean', mean(x))
show('variance', variance(x, 1))
show('variance ddof 0', variance(x, 0))
y = [rnd() * 0.11 for _ in range(500)]
s = 0.0
for a, b in zip(x, y): s += a * b
show('dot', s)
mx = max(abs(v) for v in x)
s = 0.0
for v in x: s += v * v
show('norm2', math.sqrt(s))
s = 0.0
for v in x: s += abs(v)
show('norm1', s)
show('normInf', mx)
cs = []
s = 0.0; c = 0.0
for v in x[:40]:
    t = s + v
    if abs(s) >= abs(v): c += (s - t) + v
    else: c += (v - t) + s
    s = t
    cs.append(s + c)
show('cumsum (first 40)', cs)

A = [[0.0] * 9 for _ in range(12)]
B = [[0.0] * 7 for _ in range(9)]
for i in range(12):
    for j in range(9): A[i][j] = rnd()
for i in range(9):
    for j in range(7): B[i][j] = rnd()
def matmul(A, B):
    R = []
    for i in range(len(A)):
        row = []
        for j in range(len(B[0])):
            s = 0.0
            for k in range(len(B)): s += A[i][k] * B[k][j]
            row.append(s)
        R.append(row)
    return R
C = matmul(A, B)
show('product 12 x 7', [v for row in C for v in row])
v9 = [rnd() for _ in range(9)]
w = []
for i in range(12):
    s = 0.0
    for j in range(9): s += A[i][j] * v9[j]
    w.append(s)
show('A v', w)

n = 10
M = [[rnd() for _ in range(n)] for _ in range(n)]
rhs = [rnd() for _ in range(n)]
# luFactor
a = [row[:] for row in M]
piv = list(range(n)); sign = 1; ok = True
for k in range(n):
    p = k; mxv = abs(a[k][k])
    for i in range(k + 1, n):
        v = abs(a[i][k])
        if v > mxv: mxv = v; p = i
    if p != k:
        a[k], a[p] = a[p], a[k]
        piv[k], piv[p] = piv[p], piv[k]
        sign = -sign
    pivot = a[k][k]
    if pivot == 0.0: ok = False; continue
    rk = a[k]
    for i in range(k + 1, n):
        ri = a[i]
        l = ri[k] / pivot
        ri[k] = l
        if l != 0.0:
            for j in range(k + 1, n): ri[j] -= l * rk[j]
assert ok
def lu_solve(b):
    wv = [b[piv[i]] for i in range(n)]
    for i in range(n):
        s = wv[i]
        for j in range(i): s -= a[i][j] * wv[j]
        wv[i] = s
    for i in range(n - 1, -1, -1):
        s = wv[i]
        for j in range(i + 1, n): s -= a[i][j] * wv[j]
        wv[i] = s / a[i][i]
    return wv
show('LU solve', lu_solve(rhs))
d = float(sign)
for i in range(n): d *= a[i][i]
show('LU det', d)
show('LU factors (row 0 and row 9)', a[0])
show('LU row 9', a[9])
out.append('LU pivots: ' + ' '.join(str(p) for p in piv))
wv = rhs[:]
for i in range(n):
    s = wv[i] / a[i][i]
    wv[i] = s
    for j in range(i + 1, n): wv[j] -= a[i][j] * s
for i in range(n - 1, -1, -1):
    s = wv[i]
    for j in range(i + 1, n): s -= a[j][i] * wv[j]
    wv[i] = s
xt = [0.0] * n
for i in range(n): xt[piv[i]] = wv[i]
show('LU solveTranspose', xt)

BB = [[rnd() / 16.0 for _ in range(8)] for _ in range(8)]
BT = [[BB[j][i] for j in range(8)] for i in range(8)]
S = matmul(BT, BB)
for i in range(8): S[i][i] += 8.0
L = [row[:] for row in S]
for j in range(8):
    rj = L[j]
    s = rj[j]
    for k in range(j): s -= rj[k] * rj[k]
    assert s > 0
    ljj = math.sqrt(s)
    rj[j] = ljj
    for i in range(j + 1, 8):
        ri = L[i]
        t = ri[j]
        for k in range(j): t -= ri[k] * rj[k]
        ri[j] = t / ljj
for i in range(8):
    for j in range(i + 1, 8): L[i][j] = 0.0
show('Cholesky L (row 7)', L[7])
r8 = [rnd() for _ in range(8)]
wv = [0.0] * 8
for i in range(8):
    s = r8[i]
    for j in range(i): s -= L[i][j] * wv[j]
    wv[i] = s / L[i][i]
x8 = [0.0] * 8
for i in range(7, -1, -1):
    s = wv[i]
    for j in range(i + 1, 8): s -= L[j][i] * x8[j]
    x8[i] = s / L[i][i]
show('Cholesky solve', x8)

def rhs_damped(t, y):
    return [y[1], -y[0] - 0.1 * y[1] + 0.25 * t]
y = [1.0, 0.0]; t0 = 0.0; t1 = 8.0; steps = 200
h = (t1 - t0) / float(steps)
for s_ in range(steps):
    t = t0 + float(s_) * h
    k1 = rhs_damped(t, y)
    tmp = [y[i] + 0.5 * h * k1[i] for i in range(2)]
    k2 = rhs_damped(t + 0.5 * h, tmp)
    tmp = [y[i] + 0.5 * h * k2[i] for i in range(2)]
    k3 = rhs_damped(t + 0.5 * h, tmp)
    tmp = [y[i] + h * k3[i] for i in range(2)]
    k4 = rhs_damped(t + h, tmp)
    for i in range(2): y[i] += h / 6.0 * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i])
show('rk4 final state', y)
f = lambda x: x * x * x - 2.0 * x + 1.0
nn = 100; aa = 0.0; bb_ = 3.0
h = (bb_ - aa) / float(nn)
s = 0.5 * (f(aa) + f(bb_))
for i in range(1, nn): s += f(aa + float(i) * h)
show('trapezoid', s * h)
s = f(aa) + f(bb_)
for i in range(1, nn):
    wgt = 4.0 if i % 2 == 1 else 2.0
    s += wgt * f(aa + float(i) * h)
show('simpson', s * h / 3.0)
p = [rnd() / 8.0 for _ in range(6)]
q = [rnd() / 8.0 for _ in range(4)]
pq = [0.0] * 9
for i in range(6):
    for j in range(4): pq[i + j] += p[i] * q[j]
show('polyMul', pq)
r = 0.0
for k in range(8, -1, -1): r = r * 0.7 + pq[k]
show('polyEval at 0.7', r)
show('polyDeriv', [pq[k] * float(k) for k in range(1, 9)])
show('polyIntegral', [1.5] + [pq[k] / float(k + 1) for k in range(9)])
rr = pq[:]; dq = 8 - 3; qt = [0.0] * (dq + 1)
for k in range(dq, -1, -1):
    qq = rr[k + 3] / q[3]
    qt[k] = qq
    for j in range(4): rr[k + j] -= qq * q[j]
show('polyDivide quotient', qt)
show('polyDivide remainder', rr[:3])
out.append('memory leaked: 0')
print('\n'.join(out))
