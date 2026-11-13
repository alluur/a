"""Expected output of tests/t443_matrix_eig_svd.a: eigenvalues / singular values by a cyclic Jacobi iteration in 60 digit decimals (the sign free
quantities are printed: absolute values of eigen and singular vectors); the pseudo inverse and the minimum norm solutions in exact fractions."""
import sys
from fractions import Fraction as F
from decimal import Decimal as D, getcontext
getcontext().prec = 60

seed = 31415
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
def g3(v):
    return '%.3g' % float(v)

from refmat import jacobi, svd_dec

def solve_exact(A, b):
    n = len(A)
    M = [[F(x) for x in row] + [F(bb)] for row, bb in zip(A, b)]
    for k in range(n):
        p = next(i for i in range(k, n) if M[i][k] != 0)
        M[k], M[p] = M[p], M[k]
        for i in range(n):
            if i != k and M[i][k] != 0:
                f = M[i][k] / M[k][k]
                M[i] = [a - f * c for a, c in zip(M[i], M[k])]
    return [M[i][n] / M[i][i] for i in range(n)]

def matmul(A, B):
    return [[sum(F(A[i][k]) * B[k][j] for k in range(len(B))) for j in range(len(B[0]))] for i in range(len(A))]
def transpose(A):
    return [list(r) for r in zip(*A)]
def pinv_full_rank(A):
    m, n = len(A), len(A[0])
    At = transpose(A)
    if m >= n:      # (A^T A)^-1 A^T
        G = matmul(At, A)
        cols = [solve_exact(G, [At[i][c] for i in range(n)]) for c in range(m)]
        return [[cols[c][i] for c in range(m)] for i in range(n)]
    G = matmul(A, At)   # A^T (A A^T)^-1
    cols = [solve_exact(G, [1 if i == c else 0 for i in range(m)]) for c in range(m)]    # columns of (A A^T)^-1
    inv = [[cols[j][i] for j in range(m)] for i in range(m)]
    return matmul(At, inv)

def dump_abs(name, M):
    return '%s %d %d: %s' % (name, len(M), len(M[0]), ' '.join(g9(abs(M[i][j])) for i in range(len(M)) for j in range(len(M[0]))))
def dump_m(name, M):
    return '%s %d %d: %s' % (name, len(M), len(M[0]), ' '.join(g9(M[i][j]) for i in range(len(M)) for j in range(len(M[0]))))
def dump_v(name, v):
    return '%s %d: %s' % (name, len(v), ' '.join(g9(x) for x in v))

out = []
n = 6
A = [[0] * n for _ in range(n)]
for i in range(n):
    for j in range(n):
        A[i][j] = rnd()
for i in range(n):
    for j in range(i + 1, n):
        A[j][i] = A[i][j]
vals, vecs = jacobi(A)
out.append('6x6: status 0, sweeps below 15: 1')
out.append(dump_v('values', vals))
out.append(dump_abs('|vectors|', vecs))
out.append('residual below 1e-12: 1, orthonormal: 1')
out.append('trace = sum of eigenvalues: 1')
out.append('det = product of eigenvalues (relative 1e-10): 1')
out.append('V diag(w) V^T = A (1e-12): 1')
out.append('after dispose: status 8, ok 0')
out.append(dump_v('[[2,1],[1,2]] values', jacobi([[2, 1], [1, 2]])[0]))
vv = jacobi([[2, 1], [1, 2]])[1]
out.append(dump_abs('vectors', vv))
out.append(dump_v('diag(2,5,2) values', jacobi([[2, 0, 0], [0, 5, 0], [0, 0, 2]])[0]))
out.append('repeated eigenvalue: residual 1, orthonormal 1, sweeps 0')
out.append(dump_v('[[2,1,1],[1,2,1],[1,1,2]] values', jacobi([[2, 1, 1], [1, 2, 1], [1, 1, 2]])[0]))
out.append('residual 1, orthonormal 1')
out.append(dump_v('[[1,1],[1,1]] values (one is zero)', jacobi([[1, 1], [1, 1]])[0]))
out.append(dump_v('path graph values', jacobi([[0, 1, 0], [1, 0, 1], [0, 1, 0]])[0]))
out.append('1x1 1: -7.5')
out.append('zero matrix 3: 0 0 0')
# 20 x 20: draw the random numbers in the same order
for _ in range(20 * 20):
    rnd()
out.append('20x20: status 0, residual below 1e-11: 1, orthonormal 1, ascending 1')
out.append('all ascending: 1')
out.append('values only: status 0, same values 1, vectors empty 1')
out.append('not symmetric: status 9 (matrix is not symmetric)')
out.append('NaN: status 6')
out.append('2x3: status 1')
out.append('null: status 8')

# ---- SVD of the 5 x 3 matrix
A = [[rnd() for _ in range(3)] for _ in range(5)]
sig, U, V = svd_dec(A)
out.append('5x3: status 0, sweeps below 15: 1')
out.append(dump_v('singular values', sig))
out.append(dump_abs('|U|', U))
out.append(dump_abs('|V|', V))
out.append('U S V^T = A (1e-12): 1, U orthonormal 1, V orthonormal 1')
out.append('rank 3, cond %s, norm2 %s' % (g9(sig[0] / sig[-1]), g9(sig[0])))
out.append(dump_m('pinv', pinv_full_rank(A)))
b = [rnd() for _ in range(5)]
pi = pinv_full_rank(A)
x = [sum(pi[i][j] * b[j] for j in range(5)) for i in range(3)]
out.append('solve 0')
out.append(dump_v('least squares x', x))
out.append('convenience: rank 3, cond %s' % g9(sig[0] / sig[-1]))
# ---- the wide matrix
W = [[rnd() for _ in range(5)] for _ in range(3)]
sig, U, V = svd_dec(W)
out.append('3x5: status 0, U is 3 x 3, V is 5 x 3')
out.append(dump_v('singular values', sig))
out.append('U S V^T = A (1e-12): 1, U orthonormal 1, V orthonormal 1')
out.append(dump_m('pinv', pinv_full_rank(W)))
# ---- rank one u v^T
u = [1, 2, 3]; v = [1, -1, 2, 0]
uu = sum(t * t for t in u); vv_ = sum(t * t for t in v)
s1 = (D(uu) * D(vv_)).sqrt()
out.append(dump_v('rank one values', [s1, D(0), D(0)]))
out.append('rank 1, cond is infinite 1, U orthonormal 1, V orthonormal 1')
out.append('U S V^T = A (1e-12): 1')
pin = [[F(v[i] * u[j], uu * vv_) for j in range(3)] for i in range(4)]
out.append(dump_m('pinv', pin))
b = [1, 0, 2]
ub = sum(a * c for a, c in zip(u, b))
x = [F(t * ub, uu * vv_) for t in v]
out.append('solve 0')
out.append(dump_v('minimum norm x', x))
out.append('zero matrix: status 0, values 0 0, rank 0, cond is infinite 1, U orthonormal 1')
out.append('column (3, 0, 4, 0) 1: 5')
out.append('row (2, 3, 6) 1: 7')
H = [[float(1.0 / (i + j + 1)) for j in range(8)] for i in range(8)]
sig, _, _ = svd_dec(H)
out.append('hilbert(8) singular values (3 digits): ' + ' '.join(g3(s) for s in sig))
out.append('condition number %s, rank 8, rank with tolerance 1e-8 7' % ('%.3g' % float(sig[0] / sig[-1])))
out.append('1e150 / 1 columns: status 0, s0 1.41421356, s1 relative to 1: 1.41')
out.append('infinity: status 6, rank of it (convenience) -1')
out.append('null: status 8')
out.append('memory leaked: 0')
sys.stdout.write('\n'.join(out) + '\n')
