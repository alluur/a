"""Reference linear algebra in 60 digit decimals (Python standard library only): cyclic Jacobi eigen decomposition of symmetric matrices and the SVD through it."""
from decimal import Decimal as D, getcontext
getcontext().prec = 60

def jacobi(A):
    """eigenvalues (ascending) and eigenvectors (columns) of a symmetric matrix of Decimals by cyclic Jacobi sweeps"""
    n = len(A)
    A = [[D(x) for x in row] for row in A]
    V = [[D(1) if i == j else D(0) for j in range(n)] for i in range(n)]
    for sweep in range(60):
        off = sum(A[i][j] ** 2 for i in range(n) for j in range(i + 1, n))
        if off < D(10) ** -110:
            break
        for p in range(n - 1):
            for q in range(p + 1, n):
                if A[p][q] == 0:
                    continue
                theta = (A[q][q] - A[p][p]) / (2 * A[p][q])
                t = (1 if theta >= 0 else -1) / (abs(theta) + (theta * theta + 1).sqrt())
                c = 1 / (t * t + 1).sqrt(); s = t * c
                for k in range(n):
                    akp, akq = A[k][p], A[k][q]
                    A[k][p] = c * akp - s * akq
                    A[k][q] = s * akp + c * akq
                for k in range(n):
                    apk, aqk = A[p][k], A[q][k]
                    A[p][k] = c * apk - s * aqk
                    A[q][k] = s * apk + c * aqk
                for k in range(n):
                    vkp, vkq = V[k][p], V[k][q]
                    V[k][p] = c * vkp - s * vkq
                    V[k][q] = s * vkp + c * vkq
    order = sorted(range(n), key=lambda i: A[i][i])
    vals = [A[i][i] for i in order]
    vecs = [[V[r][i] for i in order] for r in range(n)]
    return vals, vecs

def svd_dec(A):
    """singular values (descending), U, V (columns) of a tall or wide matrix of numbers via the eigen decomposition of A^T A in 60 digits"""
    m, n = len(A), len(A[0])
    wide = m < n
    if wide:
        A = [list(r) for r in zip(*A)]
        m, n = n, m
    G = [[sum(D(A[k][i]) * D(A[k][j]) for k in range(m)) for j in range(n)] for i in range(n)]
    vals, vecs = jacobi(G)
    order = list(range(n))[::-1]
    sig = [vals[i].sqrt() if vals[i] > 0 else D(0) for i in order]
    V = [[vecs[r][i] for i in order] for r in range(n)]
    U = [[(sum(D(A[r][k]) * V[k][j] for k in range(n)) / sig[j]) if sig[j] > D(10) ** -40 else D(0) for j in range(n)] for r in range(m)]
    if wide:
        return sig, V, U      # A^T = U S V^T  =>  A = V S U^T: u = V, v = U
    return sig, U, V

