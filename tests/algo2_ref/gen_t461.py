"""Expected output of tests/t461_optim_lp.a: the optimum of every bounded program is found by enumerating all vertices (every choice of n of the constraint planes and
non-negativity bounds, solved exactly with fractions), so the expected objective and the infeasible programs are exact; unbounded programs are known by construction."""
import itertools, sys
from fractions import Fraction as F
seed = 3141592
def lcg():
    global seed
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    return seed
g9 = lambda v: '%.9g' % float(v)
LE, EQ, GE = -1, 0, 1

def solve_square(M, rhs):
    n = len(M)
    A = [[F(v) for v in row] + [F(r)] for row, r in zip(M, rhs)]
    for k in range(n):
        p = next((i for i in range(k, n) if A[i][k] != 0), None)
        if p is None: return None
        A[k], A[p] = A[p], A[k]
        for i in range(n):
            if i != k and A[i][k] != 0:
                f = A[i][k] / A[k][k]
                A[i] = [a - f * c for a, c in zip(A[i], A[k])]
    return [A[i][n] / A[i][i] for i in range(n)]

def enumerate_lp(c, A, b, kinds, maximize):
    """returns (status, objective, solution) for a bounded program (None = infeasible)"""
    n = len(c); m = len(A)
    planes = [(list(map(F, A[i])), F(b[i])) for i in range(m)] + [([F(1) if j == k else F(0) for j in range(n)], F(0)) for k in range(n)]
    best = None
    for subset in itertools.combinations(range(len(planes)), n):
        x = solve_square([planes[i][0] for i in subset], [planes[i][1] for i in subset])
        if x is None: continue
        if any(v < 0 for v in x): continue
        ok = True
        for i in range(m):
            r = sum(planes[i][0][j] * x[j] for j in range(n))
            k = kinds[i] if kinds else LE
            if (k == LE and r > planes[i][1]) or (k == GE and r < planes[i][1]) or (k == EQ and r != planes[i][1]): ok = False; break
        if not ok: continue
        obj = sum(F(c[j]) * x[j] for j in range(n))
        if best is None or (obj > best[0] if maximize else obj < best[0]): best = (obj, x)
    return best

def show(name, res, extra=True):
    if res is None:
        out.append('%s: status 7' % name)
    else:
        out.append('%s: status 0 objective %s, feasible and objective = c.x: 1, pivots at most 100: 1' % (name, g9(res[0])))
out = []
c = [-3, -5]; A = [[1, 0], [0, 2], [3, 2]]; b = [4, 12, 18]
r = enumerate_lp(c, A, b, None, False)
show('min -3x - 5y, x <= 4, 2y <= 12, 3x + 2y <= 18', r); out.append('  solution (%s, %s)' % (g9(r[1][0]), g9(r[1][1])))
show('max 3x + 5y with the same constraints', enumerate_lp([3, 5], A, b, None, True))
r = enumerate_lp([4, 2, 1], [[1, 0, 0], [4, 1, 0], [8, 4, 1]], [5, 25, 125], None, True)
show('Klee-Minty 3: max 4 x1 + 2 x2 + x3', r); out.append('  solution (%s, %s, %s)' % tuple(g9(v) for v in r[1]))
show('min x + 2y, x + y >= 3', enumerate_lp([1, 2], [[1, 1]], [3], [GE], False))
show('min x + 2y, -x - y <= -3 (negative right hand side)', enumerate_lp([1, 2], [[-1, -1]], [-3], [LE], False))
show('min 2x + y, x + y = 5', enumerate_lp([2, 1], [[1, 1]], [5], [EQ], False))
show('redundant equations x + y = 2, 2x + 2y = 4, min x', enumerate_lp([1, 0], [[1, 1], [2, 2]], [2, 4], [EQ, EQ], False))
show('contradicting equations x + y = 2, 2x + 2y = 5', enumerate_lp([1, 0], [[1, 1], [2, 2]], [2, 5], [EQ, EQ], False))
show('x + y >= 4 and x + y <= 4 together, min x + 3y', enumerate_lp([1, 3], [[1, 1], [1, 1]], [4, 4], [GE, LE], False))
out.append('x >= 5 and x <= 3: status 7')
out.append('min -x, x - y <= 1 (unbounded): status 8')
out.append('min x + y with no constraint: status 0 objective 0, feasible and objective = c.x: 1, pivots at most 100: 1')
out.append('min -x + y with no constraint (unbounded): 8')
out.append('zero objective (a feasibility problem): status 0 objective 0, feasible and objective = c.x: 1, pivots at most 100: 1')
out.append('0 x <= -1 (an empty row): status 7')
out.append('0 x <= 5 (an empty row that always holds): status 0 objective 0, feasible and objective = c.x: 1, pivots at most 100: 1')
out.append('one variable: min -2x, x <= 7: status 0 objective -14, feasible and objective = c.x: 1, pivots at most 100: 1')
r = enumerate_lp([F(-3, 4), 150, F(-1, 50), 6], [[F(1, 4), -60, F(-1, 25), 9], [F(1, 2), -90, F(-1, 50), 3], [0, 0, 1, 0]], [0, 0, 1], None, False) if False else None
# Beale's example with the exact decimals as the doubles used by the test
cb = [F(-0.75), F(150), F(-0.02), F(6)]
Ab = [[F(0.25), F(-60), F(-0.04), F(9)], [F(0.5), F(-90), F(-0.02), F(3)], [F(0), F(0), F(1), F(0)]]
rb = enumerate_lp(cb, Ab, [0, 0, 1], None, False)
show("Beale's cycling example", rb)
out.append('  solution (%s, %s, %s, %s)' % tuple(g9(v) for v in rb[1]))
cost = [8, 6, 10, 9, 12, 13, 14, 9, 16]
At = [[0] * 9 for _ in range(6)]
for s in range(3):
    for t in range(3):
        At[s][s * 3 + t] = 1; At[3 + t][s * 3 + t] = 1
show('transportation problem 3 x 3', enumerate_lp(cost, At, [20, 30, 25, 15, 35, 25], [EQ] * 6, False))
price = [F(0.18), F(0.23), F(0.05), F(0.30), F(0.12), F(0.20)]
nut = [[110, 205, 160, 160, 420, 260], [4, 14, 13, 8, 4, 14], [2, 12, 54, 285, 22, 80], [30, 20, 8, 9, 15, 22]]
show('diet problem', enumerate_lp(price, nut, [2000, 55, 800, 100], [GE] * 4, False))
for t in range(60):
    n = 2 + lcg() % 3; m = 3 + lcg() % 4
    cc = [lcg() % 11 - 5 for _ in range(n)]
    AA = []; bb = []; kk = []
    for i in range(m):
        AA.append([lcg() % 9 - 3 for _ in range(n)])
        bb.append(lcg() % 20 - 3)
        r_ = lcg() % 10
        kk.append(LE if r_ < 6 else (GE if r_ < 9 else EQ))
    AA.append([1] * n); bb.append(30); kk.append(LE)
    mx = (lcg() % 2) == 1
    show('random program %d (n %d, m %d, %s)' % (t, n, m + 1, 'max' if mx else 'min'), enumerate_lp(cc, AA, bb, kk, mx))
out += ['NaN in c: 4, in b: 4, infinity in A: 4 (ERR_NAN = 4)', 'n = 0: 1, m < 0: 1, null c: 1, null x: 1, unknown row kind: 1 (ERR_ARG = 1)',
        'errorText of the program statuses: the linear program is infeasible | the linear program is unbounded', 'memory leaked: 0']
sys.stdout.write('\n'.join(out) + '\n')
