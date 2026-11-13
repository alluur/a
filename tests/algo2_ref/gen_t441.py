"""Expected output of tests/t441_matrix_lu.a: exact rational arithmetic (fractions) for determinants, solutions and inverses of the integer matrices;
the pivot bookkeeping of the last section is Gaussian elimination with partial pivoting written out in Python floats."""
import sys
from fractions import Fraction as F

seed = 20240229
def lcg():
    global seed
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    return seed
def rnd():
    return lcg() % 19 - 9

def clean(v):
    return 0.0 if (v < 1e-11 and v > -1e-11) else v
def g9(v):
    return '%.9g' % clean(float(v))

def solve_exact(A, b):
    n = len(A)
    M = [[F(x) for x in row] + [F(bb)] for row, bb in zip(A, b)]
    det = F(1)
    for k in range(n):
        p = next((i for i in range(k, n) if M[i][k] != 0), None)
        if p is None:
            return None, F(0)
        if p != k:
            M[k], M[p] = M[p], M[k]
            det = -det
        det *= M[k][k]
        for i in range(n):
            if i != k and M[i][k] != 0:
                f = M[i][k] / M[k][k]
                M[i] = [a - f * c for a, c in zip(M[i], M[k])]
    x = [M[i][n] / M[i][i] for i in range(n)]
    return x, det

def inverse_exact(A):
    n = len(A)
    cols = []
    for c in range(n):
        e = [1 if i == c else 0 for i in range(n)]
        x, _ = solve_exact(A, e)
        cols.append(x)
    return [[cols[j][i] for j in range(n)] for i in range(n)]

out = []
for rnd_ in range(3):
    n = 3 + rnd_ * 2
    A = [[rnd() for _ in range(n)] for _ in range(n)]
    b = [rnd() for _ in range(n)]
    x, det = solve_exact(A, b)
    assert det != 0
    out.append('n=%d status 0' % n)
    out.append('det ' + '%.9g' % float(det))
    out.append('solve status 0')
    out.append('x %d: %s' % (n, ' '.join(g9(v) for v in x)))
    inv = inverse_exact(A)
    out.append('inverse %d %d: %s' % (n, n, ' '.join(g9(inv[i][j]) for i in range(n) for j in range(n))))
    out.append('A * inverse is the identity (1e-12): 1')
    out.append('rcond estimate: not below the exact value 1, within a factor 3 1, cond1 = 1/rcond 1')
    out.append('P A = L U (1e-12): 1')
    out.append('solveTranspose residual small: 1')
    for _ in range(2 * n):      # the right hand sides B of solveMatrix
        rnd()
    out.append('solveMatrix: A X = B (1e-10): 1')
    out.append('logAbsDet matches det: 1, sign %d' % (1 if det > 0 else -1))
    out.append('convenience det 1, inverse ok 1, solve ok 1')

for _ in range(144):
    rnd()
out.append('known solution: status 0, max error below 1e-12: 1, rcond above 0.01: 1')
out.append('in place solve gives the same: 1')
out.append('1..9: status 2 (singular matrix), solve 2, rcond below 1e-16: 1, cond1 above 1e16: 1, det below 1e-12: 1')
out.append('inverse: ok 0 err 2')
out.append('Matrix.inverse: ok 0 err 2')
out.append('Matrix.solve: ok 0 err 2')
out.append('rcond check off: status 0')

def lu_pivots(a, n):
    a = [row[:] for row in a]
    piv = list(range(n)); sign = 1; zero = -1
    for k in range(n):
        p = max(range(k, n), key=lambda i: (abs(a[i][k]), -i))
        # the first row with the largest absolute value (strictly greater replaces: first maximum wins)
        best = k; mx = abs(a[k][k])
        for i in range(k + 1, n):
            if abs(a[i][k]) > mx:
                mx = abs(a[i][k]); best = i
        p = best
        if p != k:
            a[k], a[p] = a[p], a[k]
            piv[k], piv[p] = piv[p], piv[k]
            sign = -sign
        if a[k][k] == 0:
            if zero < 0: zero = k
            continue
        for i in range(k + 1, n):
            l = a[i][k] / a[k][k]
            a[i][k] = l
            if l != 0:
                for j in range(k + 1, n):
                    a[i][j] -= l * a[k][j]
    return a, piv, sign, zero

_, _, _, zero = lu_pivots([[2.0, 4.0, 6.0], [1.0, 2.0, 3.0], [5.0, 1.0, 0.0]], 3)
out.append('equal rows: status 2, det 0, zeroAt %d, rcond 0' % zero)
out.append('Matrix.det of it: 0')
out.append('with minRcond 0: status 2 (still singular: exact zero pivot)')
out.append('zero matrix: status 2 det 0 rcond 0')
out.append('1x1: status 0, x 2.5, det 4, rcond 1')
out.append('1x1 zero: status 2 det 0')
out.append('hilbert(6): status 0, error below 1e-6: 1, error above 1e-14 (it is ill conditioned): 1, rcond between 1e-9 and 1e-6: 1')
# det H6 = 1/186313420339200000 exactly (product formula for the Hilbert determinant)
from math import comb, factorial
def hilbert_det(n):
    # the Cauchy determinant: prod_{i=1}^{n-1} i!^4 / prod_{i=1}^{2n-1} i!
    num = 1
    for i in range(1, n):
        num *= factorial(i) ** 4
    den = 1
    for i in range(1, 2 * n):
        den *= factorial(i)
    return F(num, den)
assert hilbert_det(6) == F(1, 186313420339200000), hilbert_det(6)
out.append('det relative error below 1e-8: 1')
out.append('hilbert(12): status 2 (singular to working precision), rcond below 1e-15: 1')
out.append('hilbert(12) with minRcond 0: status 0, the answer is wrong by more than 1e-4: 1')
for _ in range(16):
    rnd()
out.append('row scaled system: status 0, error below 1e-9: 1')
out.append('NaN in the matrix: status 6 (NaN or infinity), det is NaN 1, solve 6')
out.append('infinity in the matrix: status 6')
out.append('NaN in the right hand side: status 6')
out.append('overflow: status 1')
out.append('2x3: status 1 (ERR_DIM = 1)')
out.append('empty: status 8')
out.append('null: status 8')
out.append('solve after dispose: 8')
_, piv, sign, zero = lu_pivots([[0.0, 2.0, 1.0], [1.0, 1.0, 1.0], [2.0, 1.0, 3.0]], 3)
out.append('luFactor: status 0, pivots %d %d %d, sign %d, zeroAt %d' % (piv[0], piv[1], piv[2], sign, zero))
# det = sign * product of the pivots on the diagonal of U; compute exactly
x_, det = solve_exact([[0, 2, 1], [1, 1, 1], [2, 1, 3]], [0, 0, 0])
out.append('det from the diagonal: %g' % float(det))
out.append('memory leaked: 0')
sys.stdout.write('\n'.join(out) + '\n')
