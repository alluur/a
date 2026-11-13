"""Expected output of tests/t451_stats_regress.a: ordinary and weighted least squares solved exactly with fractions (normal equations in rational arithmetic),
standard errors by exact matrix inversion, p values from the 70 digit decimal Student t and F distributions."""
import math, sys
sys.path.insert(0, '.')
from fractions import Fraction as F
from decimal import Decimal as D, getcontext
import refspecial as R
getcontext().prec = 60

seed = 5551212
def lcg():
    global seed
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    return seed

g9 = lambda v: '%.9g' % float(v)
out = []
def pv(name, v): out.append('%s %s' % (name, g9(v)))
def dump(name, v): out.append('%s %d: %s' % (name, len(v), ' '.join(g9(a) for a in v)))

def solve(A, b):
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

def inverse(A):
    n = len(A)
    cols = [solve(A, [1 if i == c else 0 for i in range(n)]) for c in range(n)]
    return [[cols[j][i] for j in range(n)] for i in range(n)]

def fsqrt(fr): return D(fr.numerator).sqrt() / D(fr.denominator).sqrt()
def fdec(fr): return D(fr.numerator) / D(fr.denominator)

def ols(rows, y, weights=None, intercept=True, title=''):
    n = len(y)
    X = [([F(1)] if intercept else []) + [F(v) for v in r] for r in rows]
    p = len(X[0])
    w = [F(1)] * n if weights is None else [F(v) for v in weights]
    XtWX = [[sum(w[i] * X[i][a] * X[i][b] for i in range(n)) for b in range(p)] for a in range(p)]
    XtWy = [sum(w[i] * X[i][a] * F(y[i]) for i in range(n)) for a in range(p)]
    c = solve(XtWX, XtWy)
    fitted = [sum(X[i][j] * c[j] for j in range(p)) for i in range(n)]
    res = [F(y[i]) - fitted[i] for i in range(n)]
    sse = sum(w[i] * res[i] ** 2 for i in range(n))
    sw = sum(w)
    if intercept:
        yb = sum(w[i] * F(y[i]) for i in range(n)) / sw
        sst = sum(w[i] * (F(y[i]) - yb) ** 2 for i in range(n))
    else:
        sst = sum(w[i] * F(y[i]) ** 2 for i in range(n))
    df = n - p
    r2 = 1 - sse / sst
    dftot = n - 1 if intercept else n
    adj = 1 - (1 - r2) * dftot / df
    sigma2 = sse / df
    inv = inverse(XtWX)
    se = [fsqrt(sigma2 * inv[j][j]) for j in range(p)]
    tv = [fdec(c[j]) / se[j] for j in range(p)]
    pvals = [2 * R.t_sf(abs(t), D(df)) for t in tv]
    out.append('%s: status 0, n %d, p %d, df %d' % (title, n, p, df))
    dump('  coef', c); dump('  stdErr', se); dump('  tvalue', tv); dump('  pvalue', pvals)
    pv('  r2', r2); pv('  adjR2', adj); pv('  sigma', fsqrt(sigma2)); pv('  sse', sse); pv('  sst', sst)
    if intercept and p > 1:
        fs = ((sst - sse) / (p - 1)) / (sse / df)
        pv('  fstat', fs); pv('  fpvalue', R.f_sf(fdec(fs), D(p - 1), D(df)))
    else:
        out.append('  fstat nan'); out.append('  fpvalue nan')
    return c, fitted, res

n = 15
x = [(lcg() % 1000) / 50.0 for _ in range(n)]
y = [3.5 - 0.8 * x[i] + 0.05 * x[i] * x[i] + (lcg() % 200 - 100) / 50.0 for i in range(n)]
dump('x', x); dump('y', y)
c, fit, res = ols([[a] for a in x], y, title='linear')
dump('  fitted (first 5)', fit[:5]); dump('  residuals (first 5)', res[:5])
out.append('  residuals sum to 0 and are orthogonal to x (1e-12): 1')
pv('  predict(10)', c[0] + c[1] * 10); pv('  predict(-3)', c[0] + c[1] * (-3))
out.append('after dispose: ok 0, predict is NaN 1')
c3, _, _ = ols([[a, a * a, a ** 3] for a in x], y, title='cubic')
c2, _, _ = ols([[a, a * a] for a in x], y, title='quadratic')
pv('  polyEval of the fit at 4', c2[0] + c2[1] * 4 + c2[2] * 16)
noise = [(lcg() % 64 - 32) / 64.0 for _ in range(21)]
xs = [1000.0 + i for i in range(21)]
ys = [2.0 + 0.5 * xs[i] - 0.001 * xs[i] * xs[i] + noise[i] for i in range(21)]
ols([[a, a * a] for a in xs], ys, title='quadratic at x = 1000 .. 1020')

m = 18
Xr = []; yy = []; wt = []
for i in range(m):
    a = (lcg() % 100) / 10.0
    b = (lcg() % 100) / 10.0 + a * 0.25
    cc = float(lcg() % 40) - a
    Xr.append([a, b, cc])
    yy.append(1.0 + 2.0 * a - 0.5 * b + 0.1 * cc + (lcg() % 100 - 50) / 20.0)
    wt.append(1.0 + (lcg() % 8) / 2.0)
ols(Xr, yy, title='multiple with intercept')
ols(Xr, yy, intercept=False, title='multiple without intercept')
ols(Xr, yy, weights=wt, title='multiple weighted')
out.append('weight 0 = row dropped (coefficients within 1e-12): 1')
out.append('negative weight: status 8, NaN weight: status 8 (ERR_ARG = 8)')
out.append('perfect fit: status 0, r2 above 1 - 1e-12 1, residuals below 1e-12 1, sigma below 1e-12 1')
out.append('  coefficients 4 -3')
out.append('two points: status 0, df 0, coef -1 3, r2 1')
out.append('  sigma is NaN 1, stdErr is NaN 1, pvalue is NaN 1, adjR2 is NaN 1, fstat is NaN 1')
out += ['one point: status 8 (ERR_ARG = 8)', 'constant x (collinear with the intercept): status 7 (ERR_RANK = 7), ok 0',
        'constant y: status 0, slope below 1e-12 1, r2 is NaN 1 (SST = 0)', 'degree 5 through 5 points: status 8 (ERR_ARG = 8)',
        'degree 4 through 5 points: status 0, df 0, interpolates (residuals below 1e-9) 1', 'NaN in x: status 6 (ERR_NOT_FINITE = 6)',
        'infinity in y: status 6', 'null: status 8', 'more coefficients than observations: status 1 (ERR_DIM = 1)', 'duplicate columns: status 7 (ERR_RANK = 7)',
        'zero column: status 7', 'memory leaked: 0']
sys.stdout.write('\n'.join(out) + '\n')
