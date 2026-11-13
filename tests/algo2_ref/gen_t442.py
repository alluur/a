"""Expected output of tests/t442_matrix_chol_qr.a: Cholesky factor, determinant, log determinant, |diag R| of the QR decomposition and the least squares
results are computed with 60 digit decimals / exact fractions (normal equations in exact arithmetic, pseudo inverse of rank one and wide matrices)."""
import sys
from fractions import Fraction as F
from decimal import Decimal as D, getcontext
getcontext().prec = 60

seed = 777
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
        p = next(i for i in range(k, n) if M[i][k] != 0)
        if p != k:
            M[k], M[p] = M[p], M[k]
            det = -det
        det *= M[k][k]
        for i in range(n):
            if i != k and M[i][k] != 0:
                f = M[i][k] / M[k][k]
                M[i] = [a - f * c for a, c in zip(M[i], M[k])]
    return [M[i][n] / M[i][i] for i in range(n)], det

def matmul(A, B):
    return [[sum(F(A[i][k]) * B[k][j] for k in range(len(B))) for j in range(len(B[0]))] for i in range(len(A))]
def transpose(A):
    return [list(r) for r in zip(*A)]

out = []
# ---- Cholesky
n = 5
Mx = [[rnd() for _ in range(n)] for _ in range(n)]
S = [[sum(Mx[i][k] * Mx[j][k] for k in range(n)) + (1 if i == j else 0) for j in range(n)] for i in range(n)]
b = [rnd() for _ in range(n)]
L = [[D(0)] * n for _ in range(n)]
for j in range(n):
    s = D(S[j][j]) - sum(L[j][k] ** 2 for k in range(j))
    L[j][j] = s.sqrt()
    for i in range(j + 1, n):
        L[i][j] = (D(S[i][j]) - sum(L[i][k] * L[j][k] for k in range(j))) / L[j][j]
x, det = solve_exact(S, b)
out.append('cholesky status 0')
out.append('L %d %d: %s' % (n, n, ' '.join(g9(L[i][j]) for i in range(n) for j in range(n))))
out.append('solve 0')
out.append('x %d: %s' % (n, ' '.join(g9(v) for v in x)))
out.append('det %s' % '%.9g' % float(det))
out.append('logDet %s' % '%.9g' % float(D(det.numerator).ln() - D(det.denominator).ln()))
inv_cols = [solve_exact(S, [1 if i == c else 0 for i in range(n)])[0] for c in range(n)]
out.append('inverse %d %d: %s' % (n, n, ' '.join(g9(inv_cols[j][i]) for i in range(n) for j in range(n))))
out.append('L L^T = S: 1')
out.append('in place: 1')
out.append('[[1,2],[2,1]]: status 3 (matrix is not symmetric positive definite)')
out.append('semi definite [[1,1],[1,1]]: status 3')
out.append('not symmetric: status 9 (matrix is not symmetric)')
out.append('NaN: status 6')
out.append('2x3: status 1')
out.append('solve on a failed factorization: 3')

# ---- QR of 7 x 4
A = [[rnd() for _ in range(4)] for _ in range(7)]
b = [rnd() for _ in range(7)]
# Gram-Schmidt in 60 digits for |r_ii|
cols = [[D(A[i][j]) for i in range(7)] for j in range(4)]
qs = []
rdiag = []
for j in range(4):
    v = cols[j][:]
    for q in qs:
        dot = sum(a * c for a, c in zip(v, q))
        v = [a - dot * c for a, c in zip(v, q)]
    nr = sum(a * a for a in v).sqrt()
    rdiag.append(nr)
    qs.append([a / nr for a in v])
out.append('qr status 0')
out.append('Q is 7 x 4, R is 4 x 4')
out.append('Q R = A (1e-12): 1')
out.append('Q^T Q = I (1e-14): 1')
out.append('R is upper triangular: 1')
out.append('|diag R| 4: %s' % ' '.join(g9(v) for v in rdiag))
out.append('full Q is 7 x 7')
out.append('full Q^T Q = I (1e-14): 1')
AtA = matmul(transpose(A), A)
Atb = [sum(F(A[i][j]) * b[i] for i in range(7)) for j in range(4)]
x, _ = solve_exact(AtA, Atb)
res2 = sum((b[i] - sum(F(A[i][j]) * x[j] for j in range(4))) ** 2 for i in range(7))
resn = D(res2.numerator).sqrt() / D(res2.denominator).sqrt()
out.append('least squares status 0')
out.append('x 4: %s' % ' '.join(g9(v) for v in x))
out.append('residual norm %s' % '%.9g' % float(resn))
out.append('|A x - b| recomputed %s' % '%.9g' % float(resn))
out.append('lstsq: status 0, rank 4, same solution 1')

# ---- quadratic fit
noise = [F(1, 2), F(-1, 4), F(1, 8), F(-1, 2), F(1, 4), F(-1, 8)]
V = [[1, i, i * i] for i in range(6)]
y = [1 + 2 * i + 3 * i * i + noise[i] for i in range(6)]
c, _ = solve_exact(matmul(transpose(V), V), [sum(F(V[i][j]) * y[i] for i in range(6)) for j in range(3)])
r2 = sum((y[i] - sum(F(V[i][j]) * c[j] for j in range(3))) ** 2 for i in range(6))
out.append('quadratic fit status 0')
out.append('coefficients 3: %s' % ' '.join(g9(v) for v in c))
out.append('residual %s' % '%.9g' % float(D(r2.numerator).sqrt() / D(r2.denominator).sqrt()))

# ---- rank deficient: A = u v^T with u = (1, 2, 3), v = (1, 2)
u = [1, 2, 3]; v = [1, 2]; bb = [1, 0, 2]
uu = sum(t * t for t in u); vv = sum(t * t for t in v); ub = sum(a * c for a, c in zip(u, bb))
x = [F(t * ub, uu * vv) for t in v]
res2 = sum((bb[i] - u[i] * (v[0] * x[0] + v[1] * x[1])) ** 2 for i in range(3))
out.append('rank deficient: status 0, rank 1')
out.append('x 2: %s' % ' '.join(g9(t) for t in x))
out.append('residual %s' % '%.9g' % float(D(res2.numerator).sqrt() / D(res2.denominator).sqrt()))
out.append('QR of it: diagRatio below 1e-14 1, solveLS status 7 (ERR_RANK = 7)')
# ---- wide 2 x 4: x = A^T (A A^T)^-1 b
Aw = [[1, 2, 0, 1], [0, 1, 3, 1]]; bw = [3, 5]
AAt = matmul(Aw, transpose(Aw))
z, _ = solve_exact(AAt, bw)
xw = [sum(F(Aw[i][j]) * z[i] for i in range(2)) for j in range(4)]
out.append('wide 2x4: status 0, rank 2')
out.append('minimum norm x 4: %s' % ' '.join(g9(t) for t in xw))
out.append('residual 0')
out.append('QR of a wide matrix: status 0, R is 2 x 4, solveLS status 1 (ERR_DIM = 1)')
out.append('zero matrix: status 0, rank 0, x 0 0, residual 3.74166')
out.append('QR with infinity: status 6, lstsq 6')
out.append('lstsq with NaN in b: 6')
out.append('lstsq with null: 8')
out.append('memory leaked: 0')
sys.stdout.write('\n'.join(out) + '\n')
