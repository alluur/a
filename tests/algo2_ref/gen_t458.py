"""Expected output of tests/t458_optim_interp.a: cubic splines (natural and clamped) are solved exactly with fractions (the data are exactly representable binary numbers),
as are the Lagrange polynomial and the Chebyshev coefficients of a quintic; e^x cos(3x) and its derivative, integral and Chebyshev coefficients (modified Bessel functions of the
complex argument 1 + 3i, by their power series) in 60 digit decimals."""
import math, sys
sys.path.insert(0, '.')
from fractions import Fraction as F
from decimal import Decimal as D, getcontext
import refspecial as R
getcontext().prec = 60
g12 = lambda v: '%.12g' % float(v)
g10 = lambda v: '%.10g' % float(v)
g9 = lambda v: '%.9g' % float(v)
out = []
xs = [F(0), F(1), F(5, 2), F(3), F(9, 2), F(6)]
ys = [F(1), F(3), F(2), F(5), F(4), F(1, 2)]
qs = [F(-1), F(0), F(2, 5), F(1), F(17, 10), F(11, 4), F(9, 2), F(59, 10), F(7)]
qs = [F(float(q)) for q in qs]           # the doubles (0.4, 1.7, 5.9 are not exact)

def interp_linear(x):
    if x <= xs[0]: return ys[0]
    if x >= xs[-1]: return ys[-1]
    i = max(k for k in range(len(xs) - 1) if xs[k] <= x)
    return ys[i] + (x - xs[i]) / (xs[i + 1] - xs[i]) * (ys[i + 1] - ys[i])
out.append('linear interpolation: ' + ' '.join(g12(interp_linear(q)) for q in qs))
out.append('one point: 1, empty: 1, NaN query: 1')

def spline(xs, ys, natural=True, d0=0, dn=0):
    n = len(xs)
    h = [xs[i + 1] - xs[i] for i in range(n - 1)]
    A = [[F(0)] * n for _ in range(n)]; b = [F(0)] * n
    for i in range(1, n - 1):
        A[i][i - 1] = h[i - 1]; A[i][i] = 2 * (h[i - 1] + h[i]); A[i][i + 1] = h[i]
        b[i] = 6 * ((ys[i + 1] - ys[i]) / h[i] - (ys[i] - ys[i - 1]) / h[i - 1])
    if natural:
        A[0][0] = F(1); A[n - 1][n - 1] = F(1)
    else:
        A[0][0] = 2 * h[0]; A[0][1] = h[0]; b[0] = 6 * ((ys[1] - ys[0]) / h[0] - F(d0))
        A[n - 1][n - 2] = h[-1]; A[n - 1][n - 1] = 2 * h[-1]; b[n - 1] = 6 * (F(dn) - (ys[-1] - ys[-2]) / h[-1])
    M = [[A[i][j] for j in range(n)] + [b[i]] for i in range(n)]
    for k in range(n):
        p = next(i for i in range(k, n) if M[i][k] != 0); M[k], M[p] = M[p], M[k]
        for i in range(n):
            if i != k and M[i][k] != 0:
                f = M[i][k] / M[k][k]; M[i] = [a - f * c for a, c in zip(M[i], M[k])]
    m2 = [M[i][n] / M[i][i] for i in range(n)]
    segs = []
    for i in range(n - 1):
        segs.append((ys[i], (ys[i + 1] - ys[i]) / h[i] - h[i] * (2 * m2[i] + m2[i + 1]) / 6, m2[i] / 2, (m2[i + 1] - m2[i]) / (6 * h[i])))
    return segs
def seg_of(xs, x):
    return max([k for k in range(len(xs) - 1) if xs[k] <= x] or [0])
def sval(segs, xs, x, order=0):
    i = seg_of(xs, x); a, b, c, d = segs[i]; dx = x - xs[i]
    return [a + b * dx + c * dx * dx + d * dx ** 3, b + 2 * c * dx + 3 * d * dx * dx, 2 * c + 6 * d * dx, 6 * d][order]
def sint(segs, xs, lo, hi):
    if lo > hi: return -sint(segs, xs, hi, lo)
    i0 = seg_of(xs, lo); i1 = seg_of(xs, hi); tot = F(0)
    for i in range(i0, i1 + 1):
        a, b, c, d = segs[i]
        L = lo if i == i0 else xs[i]; H = hi if i == i1 else xs[i + 1]
        anti = lambda t: a * t + b * t ** 2 / 2 + c * t ** 3 / 3 + d * t ** 4 / 4
        tot += anti(H - xs[i]) - anti(L - xs[i])
    return tot
nat = spline(xs, ys)
out.append('natural spline: ok 1, n 6')
out.append('values: ' + ' '.join(g12(sval(nat, xs, q)) for q in qs))
out.append('first derivatives: ' + ' '.join(g12(sval(nat, xs, q, 1)) for q in qs))
out.append('second derivatives: ' + ' '.join(g12(sval(nat, xs, q, 2)) for q in qs))
out.append('third derivatives: ' + ' '.join(g12(sval(nat, xs, q, 3)) for q in qs))
out.append('passes through the data: 1, natural ends (second derivative 0): 1')
out.append('first and second derivative are continuous at the knots: 1')
def pv(name, v): out.append('%s %s' % (name, g12(v)))
pv('integral 0 .. 6', sint(nat, xs, F(0), F(6)))
pv('integral 1.2 .. 4', sint(nat, xs, F(1.2), F(4)))
pv('integral 4 .. 1.2 (reversed)', sint(nat, xs, F(4), F(1.2)))
pv('integral -1 .. 7 (with extrapolation)', sint(nat, xs, F(-1), F(7)))
out += ['additivity: 1', 'derivative order 0 and 4 are NaN: 1 1', 'after dispose: ok 0, value is NaN 1']
cl = spline(xs, ys, False, F(3, 2), F(-2))
out.append('clamped spline values: ' + ' '.join(g12(sval(cl, xs, q)) for q in qs))
out.append('end slopes: 1.5 -2')
pv('clamped integral 0 .. 6', sint(cl, xs, F(0), F(6)))
out.append('natural spline through 2 points is the line: 2 5 14')
out.append('clamped spline through 2 points with zero slopes: 2 5 8')
out.append('  and its integral 10')
out.append('clamped spline with the exact end slopes reproduces a cubic (1e-13): 1')
out.append('not increasing: 1, duplicate x: 1, one point: 1, NaN y: 1, null: 1, unknown boundary: 1 (ERR_ARG = 1)')
def lagrange(x):
    if x in xs: return ys[xs.index(x)]
    s = F(0)
    for j in range(6):
        t = ys[j]
        for k in range(6):
            if k != j: t *= (x - xs[k]) / (xs[j] - xs[k])
        s += t
    return s
out.append('lagrange: ' + ' '.join(g12(lagrange(q)) for q in qs))
out += ['exact at the nodes: 1', "Runge's function, degree 20: equispaced error above 1 1, Chebyshev nodes error below 0.1 1",
        'duplicate nodes: 1, NaN node: 1, null: 1, n = 0: 1 (ERR_ARG = 1); a single node is constant: 1', 'NaN query: 1']
clean0 = lambda v: 0.0 if abs(v) < 1e-15 else v          # cos(pi / 2) is 6e-17 in floating point, exactly 0 as a quarter turn
out.append('chebyshevNodes(5) on -1 .. 1: ' + ' '.join(g12(clean0(-math.cos(math.pi * (2 * k + 1) / 10))) for k in range(5)))
out.append('three nodes on 2 .. 10: ' + ' '.join(g12(6 - 4 * math.cos(math.pi * (2 * k + 1) / 6)) for k in range(3)))
out.append('invalid: n = 0 1, null 1, a >= b is not tested here')
out.append('e^x cos(3x) on 0 .. 2 with 24 terms: ok 1')
f = lambda x: D(x).exp() * R.cos(3 * D(x))
fp = lambda x: D(x).exp() * (R.cos(3 * D(x)) - 3 * R.sin(3 * D(x)))
pts = ['0', '0.1', '0.7', '1.3', '1.9', '2']
out.append('values: ' + ' '.join(g12(f(D(float(p)))) for p in pts))
out.append('derivatives: ' + ' '.join(g10(fp(D(float(p)))) for p in pts))
pv('integral over 0 .. 2', (D(2).exp() * (R.cos(D(6)) + 3 * R.sin(D(6))) - 1) / 10)
out.append('outside the interval the polynomial continues: value at 2.1 is finite 1, at 2.1 within 1e-3 of the function: 1')
# Chebyshev coefficients via complex modified Bessel functions: c_k = 2 Re[e^{1+3i} I_k(1 + 3i)]
class Cx:
    def __init__(s, r, i=D(0)): s.r, s.i = D(r), D(i)
    def __add__(s, o): return Cx(s.r + o.r, s.i + o.i)
    def __mul__(s, o): return Cx(s.r * o.r - s.i * o.i, s.r * o.i + s.i * o.r)
def cscale(z, k): return Cx(z.r * k, z.i * k)
def bessel_i(k, z):
    half = cscale(z, D('0.5')); half2 = half * half
    term = Cx(1)
    for _ in range(k): term = term * half
    term = cscale(term, D(1) / D(math.factorial(k)))
    s = Cx(0)
    for m in range(0, 80):
        s = s + term
        term = cscale(term * half2, D(1) / D((m + 1) * (m + 1 + k)))
    return s
z = Cx(1, 3)
e1 = Cx(D(1).exp() * R.cos(D(3)), D(1).exp() * R.sin(D(3)))
ck = lambda k: 2 * (e1 * bessel_i(k, z)).r
pv('coefficient 0', ck(0))
out.append('coefficient 30 is NaN: 1')
out.append('3x^5 - 2x^2 + 1 with 6 terms: ' + ' '.join(g9(v) for v in (0, F(15, 8), -1, F(15, 16), 0, F(3, 16))))
pv('  integral over -1 .. 1', F(2, 3))
out.append('  value at 0.37 within 1e-14 of the polynomial: 1')
x37 = F(37, 100)
out.append('  derivative at 0.37 (exact 15 x^4 - 4 x): %s' % g10(15 * x37 ** 4 - 4 * x37))
out.append('one term: derivative 0, value 1, half of coefficient 0 is 1')
out.append('|x| with 40 terms: error at 0.5 below 1e-3 1, error at 0 above 1e-3 (kink): 1')
out.append('NaN function: 4 (ERR_NAN = 4), a > b: 1, zero terms: 1, infinite interval: 1 (ERR_ARG = 1)')
out.append('memory leaked: 0')
sys.stdout.write('\n'.join(out) + '\n')
