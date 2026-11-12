"""Expected output of tests/t440_matrix_basic.a: exact integer arithmetic in plain Python floats (all entries are small integers or halves)."""
import math, sys

seed = 4711
def lcg():
    global seed
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    return seed

def g(v):
    return '%.10g' % v

class M:
    def __init__(self, r, c, d=None):
        self.r, self.c = r, c
        self.d = d if d is not None else [0.0] * (r * c)
    def at(self, i, j): return self.d[i * self.c + j]
    def T(self):
        return M(self.c, self.r, [self.at(i, j) for j in range(self.c) for i in range(self.r)])
    def __add__(self, o): return M(self.r, self.c, [a + b for a, b in zip(self.d, o.d)])
    def __sub__(self, o): return M(self.r, self.c, [a - b for a, b in zip(self.d, o.d)])
    def __mul__(self, o):
        out = M(self.r, o.c)
        for i in range(self.r):
            for k in range(self.c):
                for j in range(o.c):
                    out.d[i * o.c + j] += self.at(i, k) * o.at(k, j)
        return out

out = []
def dumpM(name, m):
    out.append('%s %d %d: %s' % (name, m.r, m.c, ' '.join(g(v) for v in m.d)))
def dumpV(name, v):
    out.append('%s %d: %s' % (name, len(v), ' '.join(g(x) for x in v)))
def pv(name, v):
    out.append('%s %s' % (name, g(v)))

def fillRandom(m):
    for i in range(m.r * m.c):
        m.d[i] = float(lcg() % 19 - 9)

a = M(3, 4); b = M(4, 2); c = M(3, 4)
fillRandom(a); fillRandom(b); fillRandom(c)
dumpM('A', a); dumpM('B', b); dumpM('C', c)
dumpM('A+C', a + c)
dumpM('A-C', a - c)
dumpM('A*B', a * b)
dumpM('A^T', a.T())
dumpM('2.5A', M(3, 4, [2.5 * v for v in a.d]))
dumpM('A.C', M(3, 4, [x * y for x, y in zip(a.d, c.d)]))
dumpM('A*B op', a * b)
dumpM('A+C op', a + c)
dumpM('A-C op', a - c)
pv('trace A', sum(a.at(i, i) for i in range(3)))
pv('norm1 A', max(sum(abs(a.at(i, j)) for i in range(3)) for j in range(4)))
pv('normInf A', max(sum(abs(a.at(i, j)) for j in range(4)) for i in range(3)))
pv('normFro A', math.sqrt(sum(v * v for v in a.d)))
pv('normMax A', max(abs(v) for v in a.d))
x4 = [1, -2, 3, 0.5]
dumpV('A x', [sum(a.at(i, j) * x4[j] for j in range(4)) for i in range(3)])
x3 = [2, 0, -1]
dumpV('A^T x', [sum(a.at(i, j) * x3[i] for i in range(3)) for j in range(4)])
sub = M(2, 3, [a.at(1 + i, 1 + j) for i in range(2) for j in range(3)])
dumpM('sub(1,1,2,3)', sub)
big = M(4, 5)
for i in range(2):
    for j in range(3):
        big.d[(1 + i) * 5 + 2 + j] = sub.at(i, j)
dumpM('setSubmatrix', big)
dumpV('row 1', [a.at(1, j) for j in range(4)])
dumpV('col 2', [a.at(i, 2) for i in range(3)])
# swapRows(0,2), swapCols(1,3)
rows = [[a.at(i, j) for j in range(4)] for i in range(3)]
rows[0], rows[2] = rows[2], rows[0]
a = M(3, 4, [v for r_ in rows for v in r_])
dumpM('swapRows(0,2)', a)
rows = [[a.at(i, j) for j in range(4)] for i in range(3)]
for r_ in rows:
    r_[1], r_[3] = r_[3], r_[1]
a = M(3, 4, [v for r_ in rows for v in r_])
dumpM('swapCols(1,3)', a)
pv('get(2,3)', a.at(2, 3))
out.append('set out of range: 0 0')
out.append('get out of range is NaN: 1')
dumpM('identity(3)', M(3, 3, [1.0 if i == j else 0.0 for i in range(3) for j in range(3)]))
dumpM('diagonal', M(3, 3, [[2.0, 3.0, 5.0][i] if i == j else 0.0 for i in range(3) for j in range(3)]))
u = [1, 2, 3]; v = [4, 5]
dumpM('outer', M(3, 2, [float(x * y) for x in u for y in v]))
dumpM('hilbert(3)', M(3, 3, [1.0 / (i + j + 1) for i in range(3) for j in range(3)]))
dumpM('ones(2,3)', M(2, 3, [1.0] * 6))
dumpM('zeros(2,2)', M(2, 2))
dumpM('fromArray', M(2, 3, [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]))
# in place ops (c is the original C)
q = M(3, 4, list(c.d))
q = q + c
dumpM('C+=C', q)
q = q - a
dumpM('-= A', q)
q = M(3, 4, [-0.5 * x for x in q.d])
dumpM('*= -0.5', q)
q = M(3, 4, [x + 2.0 * y for x, y in zip(q.d, c.d)])
dumpM('axpy 2C', q)
sq = M(3, 3)
fillRandom(sq)
dumpM('sq', sq)
out.append('transposeInPlace: 0')
dumpM('sq^T', sq.T())
out.append('transposeInPlace of 3x4: 1 (ERR_DIM = 1)')
out.append('mulInto: 0')
dumpM('A*B into', a * b)
out.append('mulInto alias: 8 (ERR_ARG = 8)')
out.append('mulInto wrong shape: 1')
out.append('add 3x4 + 4x2: ok 0 err 1 (dimension mismatch)')
out.append('mul 4x2 * 4x2: ok 0 err 1')
out.append('Matrix(0, 5): ok 0 err 8')
out.append('Matrix(-1, 2): ok 0 err 8')
out.append('Matrix(1e9, 1e9): ok 0 err 8')
out.append('transpose of an empty matrix: ok 0 err 8')
out.append('add(null): ok 0 err 8')
out.append('submatrix out of range: ok 0 err 8')
out.append('setRow bad index: 8')
out.append('zeroed matrix: ok 0 rows 0 trace is NaN 1 det is NaN 1')
out.append('errorText(0) ok | errorText(99) unknown error')
out.append('NaN spreads: 1 1 0 1, isFinite 0')
out.append('normMax with NaN is NaN: 1, normFro: 1')
out.append('isSymmetric exact 0, tol 1e-6 1, non square 0')
pv('normFro of 3e200, 4e200', 5.0)
pv('normFro of 3e-200, 4e-200', 5.0)
out.append('memory leaked: 0')
out.append('memory at the middle was above the base: 1')
sys.stdout.write('\n'.join(out) + '\n')
