"""Expected output of tests/t459_optim_poly.a: polynomial arithmetic and the least squares fit in exact fractions; the roots are known by construction (integers, roots of unity
by their trigonometric form in 60 digit decimals) and sorted with the rule documented for polyRoots."""
import math, sys
sys.path.insert(0, '.')
from fractions import Fraction as F
from decimal import Decimal as D, getcontext
import refspecial as R
getcontext().prec = 60
g9 = lambda v: '%.9g' % float(v)
g12 = lambda v: '%.12g' % float(v)
clean = lambda v: 0.0 if abs(float(v)) < 1e-9 else float(v)
out = []
def dump(name, c): out.append('%s (%d): %s' % (name, len(c), ' '.join(g9(clean(v)) for v in c)))
def horner(c, x):
    r = F(0)
    for a in reversed(c): r = r * x + a
    return r
p = [F(-7), F(2), F(0), F(-3), F(0), F(1)]
q = [F(2), F(-1), F(1)]
out.append('polyEval at 2: %s, at -1.5: %s, at 0: %s' % (g12(horner(p, F(2))), g12(horner(p, F(-3, 2))), g12(horner(p, F(0)))))
dp = [k * p[k] for k in range(1, 6)]
out.append('polyEvalDeriv at 2: value %s derivative %s' % (g12(horner(p, F(2))), g12(horner(dp, F(2)))))
out.append('polyDeriv: degree 4'); dump('  derivative', dp)
ip = [F(4)] + [p[k] / (k + 1) for k in range(6)]
out.append('polyIntegral with constant 4: degree 6'); dump('  antiderivative', ip)
out.append('derivative of a constant: degree 0, value 0')
out.append('polyAdd: degree 5'); dump('  sum', [p[k] + (q[k] if k < 3 else 0) for k in range(6)])
prod = [F(0)] * 8
for i in range(6):
    for j in range(3): prod[i + j] += p[i] * q[j]
out.append('polyMul: degree 7'); dump('  product', prod)
def divide(num, den):
    r = list(num); dq = len(num) - len(den); quo = [F(0)] * (dq + 1)
    for k in range(dq, -1, -1):
        c = r[k + len(den) - 1] / den[-1]; quo[k] = c
        for j in range(len(den)): r[k + j] -= c * den[j]
    return quo, r[:len(den) - 1]
qu, re_ = divide(p, q)
out.append('polyDivide by x^2 - x + 2: quotient degree 3'); dump('  quotient', qu); dump('  remainder', re_)
qb, rb = divide(prod, q)
dump('  product divided by the factor', qb); dump('  remainder', rb)
out.append('dividing a polynomial of lower degree: quotient degree 0, value 0'); dump('  remainder (the numerator)', [F(1), F(1)])
out.append('division by a polynomial with a zero leading coefficient: -1, by null: -1')
out.append('polyFromRoots: 0')
fr = [F(1)]
for r_ in (1, 2, 3, 4):
    fr = [F(0)] + fr
    for k in range(len(fr) - 1): fr[k] -= r_ * fr[k + 1]
dump('  (x-1)(x-2)(x-3)(x-4)', fr)
out.append('no roots: the constant polynomial 1')
out.append('invalid: negative degree evaluates to NaN 1, null 1, deriv of null -1')

def after(a, b):
    m = max(abs(a[0]), abs(b[0]))
    if abs(a[0] - b[0]) > 1e-10 * (1 + m): return a[0] > b[0]
    return a[1] > b[1]
def sort_roots(rs):
    rs = list(rs); n = len(rs)
    for i in range(1, n):
        v = rs[i]; j = i - 1
        while j >= 0 and after(rs[j], v):
            rs[j + 1] = rs[j]; j -= 1
        rs[j + 1] = v
    return rs
def roots_line(name, rs, count=None):
    rs = sort_roots([(clean(a), clean(b)) for a, b in rs])
    out.append('%s: %d roots:%s' % (name, len(rs), ''.join(' (%s, %s)' % (g9(a), g9(b)) for a, b in rs)))
roots_line('(x-1)(x-2)(x-3)(x-4)', [(1, 0), (2, 0), (3, 0), (4, 0)])
s2 = D(2).sqrt() / 2
roots_line('x^4 + 1', [(sa * s2, sb * s2) for sa in (1, -1) for sb in (1, -1)])
roots_line('x^3 - 1', [(1, 0), (D('-0.5'), R.PI.__class__(3).sqrt() / 2), (D('-0.5'), -D(3).sqrt() / 2)])
def unity(n): return [(R.cos(2 * R.PI * k / n), R.sin(2 * R.PI * k / n)) for k in range(n)]
roots_line('x^5 - 1', unity(5))
roots_line('x^3 (three zero roots)', [(0, 0)] * 3)
roots_line('x^3 (x - 2)', [(0, 0)] * 3 + [(2, 0)])
roots_line('x^2 + x - 6 with leading zeros', [(-3, 0), (2, 0)])
roots_line('-6 x + 3', [(F(1, 2), 0)])
out.append('the constant 7: 0 roots:')
dump('  (x - 2)(x + 7) (x^2 + 2x + 5)', [-70, -3, 1, 7, 1])
roots_line('real and complex roots', [(2, 0), (-7, 0), (-1, 2), (-1, -2)])
roots_line('x^2 - 1e20', [(-1e10, 0), (1e10, 0)])
out += ['roots of very different size, relative error below 1e-9: 1',
        '(x - 1)^3: 3 roots, all within 1e-4 of 1: 1, imaginary parts below 1e-4: 1', 'Wilkinson degree 10: 10 roots, error below 1e-6: 1',
        'x^30 - 1: 30 roots, all on the unit circle (1e-12): 1, residual below 1e-12: 1', 'random polynomial of degree 25: 25 roots, residual below 1e-11: 1',
        'the zero polynomial: -1, NaN coefficient: -1, infinite coefficient: -1, null: -1, negative degree: -1 (-ERR_ARG = -1)', 'the coefficients are not changed: 1']

def solve(A, b):
    n = len(A)
    M = [[F(x) for x in row] + [F(bb)] for row, bb in zip(A, b)]
    for k in range(n):
        piv = next(i for i in range(k, n) if M[i][k] != 0); M[k], M[piv] = M[piv], M[k]
        for i in range(n):
            if i != k and M[i][k] != 0:
                f = M[i][k] / M[k][k]; M[i] = [a - f * c for a, c in zip(M[i], M[k])]
    return [M[i][n] / M[i][i] for i in range(n)]
def fit(x, y, deg):
    V = [[F(xi) ** k for k in range(deg + 1)] for xi in x]
    A = [[sum(V[i][a] * V[i][b] for i in range(len(x))) for b in range(deg + 1)] for a in range(deg + 1)]
    b = [sum(V[i][a] * F(y[i]) for i in range(len(x))) for a in range(deg + 1)]
    return solve(A, b)
x = [F(i) for i in range(8)]
y = [F(3, 2), F(-1, 4), F(2), F(15, 2), F(15), F(121, 4), F(49), F(157, 2)]
out.append('polyFit degree 3: status 0'); dump('  coefficients', fit(x, y, 3))
out.append('degree 0 (the mean): status 0'); dump('  coefficient', fit(x, y, 0))
out.append('degree 7 interpolates 8 points: status 0, residuals below 1e-7: 1')
bx = [F(1000 + i) for i in range(21)]
by = [3 + 2 * F(1000 + i) - F(0.001) * F(1000 + i) ** 2 + F((i % 5 - 2), 8) for i in range(21)]
out.append('quadratic at x around 1000: status 0'); dump('  coefficients', fit(bx, by, 2))
out.append('invalid: too few points 1, NaN 4, null 1, negative degree 1 (ERR_ARG = 1, ERR_NAN = 4)')
out.append('memory leaked: 0')
sys.stdout.write('\n'.join(out) + '\n')
