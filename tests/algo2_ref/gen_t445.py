"""Expected output of tests/t445_matrix_complex.a: exact Gaussian rational arithmetic (a complex number is a pair of fractions)."""
import sys
from fractions import Fraction as F

seed = 2718
def lcg():
    global seed
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    return seed

class C:
    def __init__(self, re=0, im=0): self.re, self.im = F(re), F(im)
    def __add__(s, o): return C(s.re + o.re, s.im + o.im)
    def __sub__(s, o): return C(s.re - o.re, s.im - o.im)
    def __mul__(s, o): return C(s.re * o.re - s.im * o.im, s.re * o.im + s.im * o.re)
    def __truediv__(s, o):
        d = o.re * o.re + o.im * o.im
        return C((s.re * o.re + s.im * o.im) / d, (s.im * o.re - s.re * o.im) / d)
    def zero(s): return s.re == 0 and s.im == 0

def clean(v):
    return 0.0 if (v < 1e-11 and v > -1e-11) else v
def g9(v): return '%.9g' % clean(float(v))
def gg(v): return '%g' % float(v)

def rand_mat(n):
    m = [[None] * n for _ in range(n)]
    for i in range(n):
        for j in range(n):
            re = lcg() % 11 - 5
            im = lcg() % 11 - 5
            m[i][j] = C(re, im)
    return m

def dump(name, m):
    return '%s %d %d: %s' % (name, len(m), len(m[0]), ' '.join('(%s, %s)' % (g9(z.re), g9(z.im)) for r in m for z in r))

def matmul(A, B):
    n, k, m = len(A), len(B), len(B[0])
    out = [[C() for _ in range(m)] for _ in range(n)]
    for i in range(n):
        for j in range(m):
            s = C()
            for t in range(k):
                s = s + A[i][t] * B[t][j]
            out[i][j] = s
    return out

def solve(A, b):
    n = len(A)
    M = [[A[i][j] for j in range(n)] + [b[i]] for i in range(n)]
    det = C(1)
    for k in range(n):
        p = next(i for i in range(k, n) if not M[i][k].zero())
        if p != k:
            M[k], M[p] = M[p], M[k]
            det = C(0) - det
        det = det * M[k][k]
        for i in range(n):
            if i != k and not M[i][k].zero():
                f = M[i][k] / M[k][k]
                M[i] = [a - f * c for a, c in zip(M[i], M[k])]
    return [M[i][n] / M[i][i] for i in range(n)], det

out = []
A = rand_mat(3); B = rand_mat(3)
out.append(dump('A', A)); out.append(dump('B', B))
out.append(dump('A+B', [[A[i][j] + B[i][j] for j in range(3)] for i in range(3)]))
out.append(dump('A-B', [[A[i][j] - B[i][j] for j in range(3)] for i in range(3)]))
out.append(dump('A*B', matmul(A, B)))
out.append(dump('A^H', [[C(A[j][i].re, -A[j][i].im) for j in range(3)] for i in range(3)]))
out.append(dump('i A', [[A[i][j] * C(0, 1) for j in range(3)] for i in range(3)]))
tr = A[0][0] + A[1][1] + A[2][2]
out.append('trace (%s, %s)' % (gg(tr.re), gg(tr.im)))
nf = sum(z.re * z.re + z.im * z.im for r in A for z in r)
from decimal import Decimal as D, getcontext
getcontext().prec = 50
out.append('normFro %s' % '%.9g' % float(D(nf.numerator).sqrt() / D(nf.denominator).sqrt()))
out.append('mulVec 0')
x = [C(1, F(1, 2)), C(-1, 2), C(2, -1)]
y = [sum((A[i][j] * x[j] for j in range(3)), C()) for i in range(3)]
out.append('A x = ' + ' '.join('(%s, %s)' % (gg(z.re), gg(z.im)) for z in y))
b = [C(3, 1), C(-2, 4), C(1, -2)]
sol, det = solve(A, b)
out.append('det status 0')
out.append('det (%s, %s)' % (g9(det.re), g9(det.im)))
out.append('solve status 0')
out.append('x = ' + ' '.join('(%s, %s)' % (g9(z.re), g9(z.im)) for z in sol))
out.append('A x = b (1e-12): 1')
out.append('in place gives the same: 1')
out.append('mulVec aliasing: 8')
out.append('errors: add(null) 8, mul(null) 8, add of other shape 1 (ERR_ARG = 8, ERR_DIM = 1)')
out.append('det of the identity: (1, 0)')
out.append('singular solve: 2 (ERR_SINGULAR = 2)')
out.append('singular det (0, 0)')
out.append('NaN: solve 6, det 6')
out.append('2x3: det 1, solve 1 (ERR_DIM = 1)')
out.append('empty: ok 0 err 8')
out.append('set out of range 0, getRe NaN 1')
out.append('copy: 1')
out.append('memory leaked: 0')
sys.stdout.write('\n'.join(out) + '\n')
