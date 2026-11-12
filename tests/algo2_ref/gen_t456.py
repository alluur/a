"""Expected output of tests/t456_optim_integrate.a: the integrals are closed forms in 60 digit decimals (e, pi, sin(100) / 100 ...); the Gauss-Legendre nodes come from
Newton's method on the Legendre polynomials in decimals; the fixed trapezoid and Simpson sums replay the rules in Python floats (same order of operations)."""
import math, sys
sys.path.insert(0, '.')
from decimal import Decimal as D, getcontext
import refspecial as R
getcontext().prec = 60
g11 = lambda v: '%.11g' % float(v)
g12 = lambda v: '%.12g' % float(v)
out = []
def line(name, v, status=0, ok='1', limit='1e-9'):
    out.append('%s: status %d value %s error estimate below %s: %s' % (name, status, g11(v), limit, ok))
pi = R.PI
e = D(1).exp()
line('sin on 0 .. pi', D(2))
line('x^10 on 0 .. 2', D(2) ** 11 / 11)
line('exp on 0 .. 1', e - 1)
line('4 / (1 + x^2) on 0 .. 1 (pi)', pi)
line('x exp(x) on 0 .. 1', D(1))
line('exp(-x^2) on the whole line (sqrt pi)', pi.sqrt())
line('1 / (1 + x^2) on 0 .. infinity (pi / 2)', pi / 2)
line('x^3 exp(-x) on 0 .. infinity (6)', D(6))
line('exp(x) on -infinity .. 0 (1)', D(1))
line('exp(x) on 0 .. -infinity (-inf reversed: the same with a minus)', D(-1))
line('ln(x) on 0 .. 1 (an integrable singularity at 0)', D(-1))
line('1 / sqrt(x) on 0 .. 1', D(2))
line('sqrt(1 - x^2) on -1 .. 1 (pi / 2)', pi / 2)
line('cos(100 x) on 0 .. 1 (oscillating)', R.sin(D(100)) / 100)
line('|x - 0.3| on 0 .. 1 (a kink)', D('0.29'))
line('sin on pi .. 0 (reversed limits)', D(-2))
out += ['empty range: status 0 value 0 evals 0', 'smooth function: evaluations 15 (one Kronrod rule of 15 points), intervals 1',
        'oscillating function: more evaluations (above 15 and below 2000): 1, intervals 32 at most 40: 1']
ctx = D(2) * (1 - R.cos(D(6))) / 3
out.append('2 sin(3x) on 0 .. 2 with a context: status 0 value %s calls equal evals 1' % g11(ctx))
out += ['1 / x on 0 .. 1 diverges: status 3 (ERR_NO_CONVERGE = 3), the error estimate is large: 1', 'NaN values: status 4 (ERR_NAN = 4)',
        'too few subdivisions: status 3, still a finite estimate 1',
        'invalid arguments: NaN limit 1, negative tolerance 1, maxSub 0 1, maxSub too large 1 (ERR_ARG = 1)', 'a loose tolerance needs only one rule: evaluations 15']
line('Romberg sin on 0 .. pi', D(2)); line('Romberg exp on 0 .. 1', e - 1); line('Romberg x^10 on 0 .. 2', D(2) ** 11 / 11)
out += ['Romberg needs few levels (at most 8) for a smooth function: 1', 'Romberg on 1 / sqrt(x) (not smooth at 0, 12 levels): status 4',
        'Romberg with 1 level: 1 (ERR_ARG = 1), 31 levels: 1']
def trap(f, a, b, n):
    h = (b - a) / n
    s = 0.5 * (f(a) + f(b))
    for i in range(1, n): s += f(a + i * h)
    return s * h
def simp(f, a, b, n):
    if n % 2 == 1: n += 1
    h = (b - a) / n
    s = f(a) + f(b)
    for i in range(1, n): s += (4.0 if i % 2 == 1 else 2.0) * f(a + i * h)
    return s * h / 3.0, n
out.append('trapezoid sin, 100 panels: %s (evals 101)' % g12(trap(math.sin, 0.0, math.pi, 100)))
out.append('simpson sin, 100 panels: %s' % g12(simp(math.sin, 0.0, math.pi, 100)[0]))
v, nn = simp(math.sin, 0.0, math.pi, 7)
out.append('simpson sin, 7 panels (rounded up to 8): %s evals %d' % (g12(v), nn + 1))
out.append('simpson is exact for cubics: x^3 on 0 .. 1 with 2 panels 0.25')
out.append('the trapezoid rule is not: x^3 on 0 .. 1 with 2 panels %s' % g12(trap(lambda x: x ** 3, 0.0, 1.0, 2)))
out += ['invalid: trapezoid n = 0: 1, simpson with NaN limit: 1, trapezoid of a NaN function: 4',
        'error ratios: trapezoid between 3.9 and 4.1: 1, Simpson between 15 and 17: 1', 'gaussLegendre(8): 0']

def legendre(n, x):
    p0, p1 = D(1), x
    for k in range(1, n):
        p0, p1 = p1, ((2 * k + 1) * x * p1 - k * p0) / (k + 1)
    return p1 if n > 0 else p0
def gl(n):
    xs = []
    for i in range(n):
        x = D(math.cos(math.pi * (i + 0.75) / (n + 0.5)))
        for _ in range(8):
            p = legendre(n, x); dp = n * (x * p - legendre(n - 1, x)) / (x * x - 1)
            x = x - p / dp
        xs.append(x)
    xs.sort()
    ws = []
    for x in xs:
        dp = n * (x * legendre(n, x) - legendre(n - 1, x)) / (x * x - 1)
        ws.append(2 / ((1 - x * x) * dp * dp))
    return xs, ws
xs, ws = gl(8)
out.append('nodes: ' + ' '.join(g12(v) for v in xs))
out.append('weights: ' + ' '.join(g12(v) for v in ws))
x5, w5 = gl(5)
out.append('n = 5: node 0 %s, middle node 0, weight sum %s' % (g12(x5[0]), g12(sum(w5))))
out.append('invalid: n = 0 1, n = 2001 1, null 1')
out.append('8 point rule on x^15 on 0 .. 1 (exact 1/16): 0.0625, on x^16 (degree 16 is not exact): error between 1e-15 and 1e-9: 1')
line('20 point rule on exp, 0 .. 1', e - 1, limit='1e-6')
out += ['integrateGL with n = 0: status 1', 'trapezoid for samples at uneven spacing: 5.05',
        'Simpson for x^3 samples, 7 samples on 0 .. 3: 20.25 (exact 20.25); 6 samples on 0 .. 2.5 (3/8 rule at the end): 9.765625 (exact 9.765625)',
        'two samples: 2, three samples (one Simpson panel pair): 0.25', 'invalid: n = 1 is NaN 1, null is NaN 1', 'memory leaked: 0']
sys.stdout.write('\n'.join(out) + '\n')
