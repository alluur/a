"""Expected output of tests/t462_optim_seq.a: Fibonacci, Lucas, Catalan, harmonic and Bernoulli numbers, factorials and binomial coefficients as exact integers / fractions (Python
integers and fractions.Fraction), the orthogonal polynomials by their three term recurrences evaluated in exact fractions of the (binary) argument values."""
import math, sys
from fractions import Fraction as F

def line(name, v):
    if v != v: return '%s nan' % name
    if v == math.inf: return '%s inf' % name
    if v == -math.inf: return '%s -inf' % name
    return '%s %s' % (name, '%.12g' % v)

def tofloat(fr):
    try: return float(fr)
    except OverflowError: return math.inf

def fib(n):
    if n < 0: return (-1) ** (-n + 1) * fib(-n)
    a, b = 0, 1
    for _ in range(n): a, b = b, a + b
    return a
def lucas(n):
    if n < 0: return (-1) ** (-n) * lucas(-n)
    return 2 if n == 0 else fib(n - 1) + fib(n + 1)
def catalan(n): return math.comb(2 * n, n) // (n + 1)
def harmonic(n): return sum(F(1, k) for k in range(1, n + 1))
def bernoulli(n):                           # B(1) = -1/2
    B = [F(0)] * (n + 1)
    for m in range(n + 1):
        B[m] = F(1)
        for k in range(m): B[m] -= math.comb(m, k) * B[k] / (m - k + 1)
    return B[n]
out = []
out.append('Fibonacci 0 .. 20: ' + ' '.join(str(fib(i)) for i in range(21)))
for n in (30, 40, 50, 70, 78, 79, 90, 100):
    out.append(line('F(%d)' % n, float(fib(n))))
out.append(line('F(1476)', float(fib(1476))))
out.append(line('F(1477)', math.inf))
out.append(line('F(5000)', math.inf))
out.append('negative indexes F(-n) = (-1)^(n+1) F(n): ' + ' '.join(str(fib(-i)) for i in range(1, 9)))
out.append('exact up to F(78): 1, F(n+1) / F(n) -> phi: 1')
out.append('Lucas 0 .. 15: ' + ' '.join(str(lucas(i)) for i in range(16)))
out.append(line('L(60)', float(lucas(60))))
out.append(line('L(-5)', float(lucas(-5))))
out.append(line('L(1476)', math.inf))
out.append('L(n) = F(n - 1) + F(n + 1) for n = 1 .. 59: 1')
out.append('Catalan 0 .. 15: ' + ' '.join(str(catalan(i)) for i in range(16)))
for n in (30, 50, 100): out.append(line('C(%d)' % n, float(catalan(n))))
out.append(line('C(-1)', math.nan))
out.append('Harmonic 1 .. 10: ' + ' '.join('%.12g' % float(harmonic(i)) for i in range(1, 11)))
out.append(line('H(0)', 0.0))
for n in (100, 1000, 1001, 100000):
    out.append(line('H(%d)' % n, float(harmonic(n))))
# H(10000000) by the asymptotic series with exact constants (gamma to 40 digits)
from decimal import Decimal as D, getcontext
getcontext().prec = 50
gamma = D('0.57721566490153286060651209008240243104215933593992')
n = D(10000000)
h = n.ln() + gamma + 1 / (2 * n) - 1 / (12 * n * n) + 1 / (120 * n ** 4) - 1 / (252 * n ** 6)
out.append(line('H(10000000)', float(h)))
out.append(line('H(-3)', math.nan))
out.append('Factorials 0 .. 22: ' + ' '.join(str(math.factorial(i)) for i in range(23)))
out.append(line('170!', float(math.factorial(170))))
out.append(line('171!', math.inf))
out.append(line('(-1)!', math.nan))
row = 'binomial(n, k) for n = 0 .. 8:'
for n in range(9):
    for k in range(n + 1): row += ' %d' % math.comb(n, k)
    row += ' |'
out.append(row)
out.append(line('C(60, 30)', float(math.comb(60, 30))))
out.append(line('C(100, 50)', float(math.comb(100, 50))))
out.append(line('C(52, 5)', float(math.comb(52, 5))))
out.append(line('C(1000, 3)', float(math.comb(1000, 3))))
out.append(line('C(5, 7)', 0.0))
out.append(line('C(-1, 2)', math.nan))
out.append(line('C(5, -1)', math.nan))
out.append(line('C(10, 10)', 1.0))
def bern_list(upto):
    B = [F(0)] * (upto + 1)
    for m in range(upto + 1):
        B[m] = F(1)
        for k in range(m): B[m] -= math.comb(m, k) * B[k] / (m - k + 1)
    return B
BL = bern_list(200)
BL[1] = F(-1, 2)                            # the convention of the module: B(1) = -1/2
out.append('Bernoulli 0 .. 12: ' + ' '.join('%.12g' % float(BL[i]) for i in range(13)))
for n in (14, 20, 24, 30, 32, 40, 60, 100, 200):
    out.append('B(%d) %s' % (n, '%.9g' % float(BL[n])))
out.append(line('B(262)', math.inf))
out.append(line('B(261)', 0.0))
out.append(line('B(7)', 0.0))
out.append(line('B(-2)', math.nan))

def rec(kind, n, x):
    x = F(x)
    if n == 0: return F(1)
    if kind == 'P': p0, p1 = F(1), x
    if kind == 'T': p0, p1 = F(1), x
    if kind == 'U': p0, p1 = F(1), 2 * x
    if kind == 'H': p0, p1 = F(1), 2 * x
    if kind == 'L': p0, p1 = F(1), 1 - x
    for k in range(1, n):
        if kind == 'P': p2 = ((2 * k + 1) * x * p1 - k * p0) / (k + 1)
        if kind == 'T': p2 = 2 * x * p1 - p0
        if kind == 'U': p2 = 2 * x * p1 - p0
        if kind == 'H': p2 = 2 * x * p1 - 2 * k * p0
        if kind == 'L': p2 = ((2 * k + 1 - x) * p1 - k * p0) / (k + 1)
        p0, p1 = p1, p2
    return p1
xs = [-0.9, -0.3, 0.0, 0.45, 1.3]
degs = [0, 1, 2, 5, 12]
for kind, nm in (('P', 'Legendre P'), ('T', 'Chebyshev T'), ('U', 'Chebyshev U'), ('H', 'Hermite H'), ('L', 'Laguerre L')):
    for d in degs:
        out.append('%s_%d: %s' % (nm, d, ' '.join('%.9g' % float(rec(kind, d, x)) for x in xs)))
out.append('P_20(0.3) %.9g, T_20(0.3) %.9g, U_20(0.3) %.9g, H_20(0.3) %.9g, L_20(0.3) %.9g' % tuple(float(rec(k, 20, 0.3)) for k in 'PTUHL'))
out.append('negative degrees are NaN: 1 1 1 1 1')
out.append('T_n(cos t) = cos(n t) for n < 30: 1')
out.append('Legendre polynomials are orthogonal (1e-14): 1')
out.append('memory leaked: 0')
print('\n'.join(out))
