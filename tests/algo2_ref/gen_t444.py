"""Expected output of tests/t444_matrix_sparse.a: sparse structures as Python dictionaries of exact integers (all values are small integers or halves)."""
import sys

seed = 99
def lcg():
    global seed
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    return seed

def g(v): return '%.10g' % v
def gg(v): return '%g' % v

out = []
class Csr:
    def __init__(self, rows, cols, entries):      # entries: dict (i, j) -> value (zero values dropped)
        self.rows, self.cols = rows, cols
        self.e = {k: float(v) for k, v in entries.items() if v != 0}
    def row_items(self, i):
        return sorted((j, v) for (ii, j), v in self.e.items() if ii == i)
    def nnz(self): return len(self.e)
    def dump(self, name):
        ptr = [0]; cols = []; vals = []
        for i in range(self.rows):
            for j, v in self.row_items(i):
                cols.append(j); vals.append(v)
            ptr.append(len(cols))
        out.append('%s %d x %d nnz %d' % (name, self.rows, self.cols, self.nnz()))
        out.append('  rowPtr: ' + ' '.join(str(p) for p in ptr))
        out.append('  cols: ' + ' '.join(str(c) for c in cols))
        out.append('  vals: ' + ' '.join(g(v) for v in vals))
    def dense(self):
        return [[self.e.get((i, j), 0.0) for j in range(self.cols)] for i in range(self.rows)]
    def transpose(self): return Csr(self.cols, self.rows, {(j, i): v for (i, j), v in self.e.items()})
    def scaled(self, k): return Csr(self.rows, self.cols, {k_: v * k for k_, v in self.e.items()})
    def add_scaled(self, alpha, o):
        d = dict(self.e)
        for k_, v in o.e.items():
            d[k_] = d.get(k_, 0.0) + alpha * v
        return Csr(self.rows, self.cols, d)
    def mul(self, o):
        d = {}
        for (i, k), a in self.e.items():
            for (k2, j), b in o.e.items():
                if k == k2:
                    d[(i, j)] = d.get((i, j), 0.0) + a * b
        return Csr(self.rows, o.cols, d)

def random_csr(rows, cols, entries):
    d = {}
    for _ in range(entries):
        i = lcg() % rows; j = lcg() % cols; v = lcg() % 9 - 4
        d[(i, j)] = d.get((i, j), 0.0) + v
    return Csr(rows, cols, d)

# ---- sparse vectors
out.append('nnz 3, indexes 2 7 9, values 3 2.5 4')
out.append('get(7) 2.5, get(3) 0, get(10) is NaN 1, put(10) 0')
out.append('after removing 7: nnz 2')
v = {2: 3.0, 7: 2.5, 9: 4.0}; w = {2: 2.0, 3: 7.0, 9: -1.0}
dot = sum(v[i] * w[i] for i in v if i in w)
norm = (sum(x * x for x in v.values())) ** 0.5
out.append('dot %s, norm %s' % (gg(dot), gg(norm)))
out.append('dotDense %s' % gg(sum(v[i] * (i + 1) for i in v)))
s = [0.0] * 10
for i in range(10):
    s[i] = v.get(i, 0.0) - 2.0 * w.get(i, 0.0)
out.append('v - 2 w 10: ' + ' '.join(g(x) for x in s))
out.append('nnz of the sum %d' % sum(1 for x in s if x != 0))
y = [1.0 + 3.0 * w.get(i, 0.0) for i in range(10)]
out.append('y + 3 w 10: ' + ' '.join(g(x) for x in y))
out.append('dot with a different dimension is NaN 1, addScaled gives null 1')

# ---- builder
d = {(2, 3): 5.0, (0, 4): 3.0, (2, 0): -2.0, (3, 1): 7.0, (1, 2): 0.0, (0, 0): 4.0}
out.append('builder out of range: 0 0 0, NaN 0')
out.append('count 8')
m = Csr(4, 5, d)
m.dump('A')
out.append('get(0,4) 3, get(1,2) 0, get(3,3) 0, get(9,9) is NaN 1')
dn = m.dense()
out.append('dense: ' + ' '.join(gg(dn[i][j]) for i in range(4) for j in range(5)))
m.dump('fromDense')
x = [1, 2, 3, 4, 5]
out.append('mulVec 0')
out.append('A x 4: ' + ' '.join(g(sum(dn[i][j] * x[j] for j in range(5))) for i in range(4)))
xt = [1, -1, 2, 0.5]
out.append('A^T x 5: ' + ' '.join(g(sum(dn[i][j] * xt[i] for i in range(4))) for j in range(5)))
out.append('diagonal 4: ' + ' '.join(g(dn[i][i]) for i in range(4)))
out.append('mulVec aliasing: 8 (ERR_ARG = 8)')
m.transpose().dump('A^T')
m.scaled(-0.5).dump('-0.5 A')
out.append('normFro %s' % gg(sum(v_ * v_ for v_ in m.e.values()) ** 0.5))
out.append('after dispose: ok 0, build of an empty builder: nnz 0 rowPtr 0 0 0')
out.append('0 rows: ok 0 err 8')

# ---- random matrices
a = random_csr(12, 9, 30)
b = random_csr(9, 7, 25)
c = random_csr(12, 9, 20)
out.append('A nnz %d, B nnz %d, C nnz %d' % (a.nnz(), b.nnz(), c.nnz()))
p = a.mul(b)
out.append('A * B equals the dense product: 1, nnz %d' % p.nnz())
p.dump('A * B')
sm = a.add_scaled(2.0, c)
out.append('A + 2 C equals the dense sum: 1, nnz %d' % sm.nnz())
sm.dump('A + 2 C')
out.append('A - A has 0 entries')
out.append('A * A (12x9 times 12x9): ok 0 err 1')
out.append('A + B (different shapes): ok 0 err 1')
out.append('(A^T)^T = A: 1')
for _ in range(9): lcg()      # x
for _ in range(12): lcg()     # z
out.append('A x sparse = dense: 1')
out.append('A^T z sparse = dense: 1')
random_csr(3, 4, 5)           # the matrix of the "non square" check uses 11 more numbers (not needed: the generator stops here)

# ---- conjugate gradients
out.append('cg: status 0, iterations at most 62: 1, error below 1e-8: 1')
out.append('cg with 5 iterations: status 4 (ERR_NO_CONVERGE = 4), iterations 5')
out.append('cg started at the solution: status 0, iterations 0')
out.append('cg with b = 0: status 0, x is zero 1')
out.append('negative definite: status 3 (ERR_NOT_SPD = 3)')
out.append('non square: 1 (ERR_DIM = 1), null: 8')

# ---- large matrix, exact integers: x <- A x ten times from the ones vector
n = 20000
x = [1] * n
for _ in range(10):
    y = [0] * n
    for i in range(n):
        s_ = 4 * x[i]
        if i > 0: s_ -= x[i - 1]
        if i + 1 < n: s_ -= x[i + 1]
        y[i] = s_
    x = y
out.append('nnz %d, A^10 times ones: x[0] = %d, x[1] = %d, x[10000] = %d, sum %d' % (3 * n - 2, x[0], x[1], x[10000], sum(x)))
out.append('memory leaked: 0')
sys.stdout.write('\n'.join(out) + '\n')
