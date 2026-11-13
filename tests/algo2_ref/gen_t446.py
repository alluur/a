"""Expected output of tests/t446_stats_describe.a: exact rational arithmetic (fractions) and the Python statistics module. The nine quantile definitions of
Hyndman and Fan are written out as in R's documentation, with exact fractions (they were also compared with numpy.quantile's nine methods while writing this)."""
import math, statistics, sys
from fractions import Fraction as F
from decimal import Decimal as D, getcontext
getcontext().prec = 60

seed = 1234567
def lcg():
    global seed
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    return seed

g9 = lambda v: '%.9g' % float(v)
out = []
def pv(name, v): out.append('%s %s' % (name, g9(v)))
def dump(name, v): out.append('%s %d: %s' % (name, len(v), ' '.join(g9(a) for a in v)))
def chk(label, b): out.append('%s: %d' % (label, 1 if b else 0))

x = [(lcg() % 1000) / 10.0 for _ in range(23)]
y = [0.5 * x[i] + (lcg() % 400) / 10.0 - 20.0 for i in range(23)]
t = [float(lcg() % 9 + 1) for _ in range(17)]
u = [float(lcg() % 6) for _ in range(17)]
dump('x', x); dump('y', y); dump('t', t); dump('u', u)

def exact_mean(v): return sum((F(a) for a in v), F(0)) / len(v)
def exact_var(v, ddof):
    m = exact_mean(v)
    return sum(((F(a) - m) ** 2 for a in v), F(0)) / (len(v) - ddof)
def fsqrt(fr):
    return D(fr.numerator).sqrt() / D(fr.denominator).sqrt()

n = 23
pv('sum', math.fsum(x))
pv('mean', statistics.mean(x))
pv('variance (n - 1)', statistics.variance(x))
pv('variance (n)', statistics.pvariance(x))
pv('stddev (n - 1)', fsqrt(exact_var(x, 1)))
pv('stddev (n)', fsqrt(exact_var(x, 0)))
pv('sem', fsqrt(exact_var(x, 1) / n))
pv('minimum', min(x)); pv('maximum', max(x)); pv('range', max(x) - min(x))

def quantile(data, p, method):
    xs = sorted(F(a) for a in data)
    n = len(xs)
    p = F(p)
    def X(k):    # 1-based with clamping like R's padded vector
        return xs[min(max(k, 1), n) - 1]
    if method <= 3:
        nppm = n * p - F(1, 2) if method == 3 else n * p
        j = math.floor(nppm)
        if method == 1: h = 1 if nppm > j else 0
        elif method == 2: h = 1 if nppm > j else F(1, 2)
        else: h = 1 if (nppm != j or j % 2 == 1) else 0
    else:
        a, b = {4: (0, 1), 5: (F(1, 2), F(1, 2)), 6: (0, 0), 7: (1, 1), 8: (F(1, 3), F(1, 3)), 9: (F(3, 8), F(3, 8))}[method]
        nppm = a + p * (n + 1 - a - b)
        j = math.floor(nppm)
        h = nppm - j
    return (1 - h) * X(j) + h * X(j + 1)

pv('median', statistics.median(x))
pv('iqr', quantile(x, F(3, 4), 7) - quantile(x, F(1, 4), 7))
med = quantile(x, F(1, 2), 7)
pv('mad', quantile([abs(F(a) - med) for a in x], F(1, 2), 7))
ps = [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0]
for m in range(1, 10):
    out.append('quantile type %d 7: %s' % (m, ' '.join(g9(quantile(x, F(p), m)) for p in ps)))
ps2 = [0.333333333333, 0.05, 0.995]
dump('quantiles of t, type 6', [quantile(t, F(p), 6) for p in ps2])
dump('quantiles of t, type 8', [quantile(t, F(p), 8) for p in ps2])
modes = statistics.multimode(t)
pv('mode of t', min(modes))
out.append('multimode of t: %d modes: %s' % (len(modes), ' '.join('%g' % m for m in sorted(modes))))
out.append('multimode with room for 1: count %d, first %g' % (len(modes), min(modes)))
pv('mode of u', min(statistics.multimode(u)))

def moments(v):
    m = exact_mean(v)
    nn = len(v)
    m2 = sum(((F(a) - m) ** 2 for a in v), F(0)) / nn
    m3 = sum(((F(a) - m) ** 3 for a in v), F(0)) / nn
    m4 = sum(((F(a) - m) ** 4 for a in v), F(0)) / nn
    return m2, m3, m4
m2, m3, m4 = moments(x)
g1 = D(m3.numerator) / D(m3.denominator) / (D(m2.numerator) / D(m2.denominator)) ** D('1.5')
g2 = m4 / (m2 * m2) - 3
pv('skewness (biased)', g1)
pv('skewness (unbiased)', g1 * D(n * (n - 1)).sqrt() / (n - 2))
pv('excess kurtosis (biased)', g2)
pv('kurtosis (biased, Pearson)', g2 + 3)
pv('excess kurtosis (unbiased)', ((n + 1) * g2 + 6) * (n - 1) / ((n - 2) * (n - 3)))
pv('covariance (n - 1)', statistics.covariance(x, y))
pv('covariance (n)', statistics.covariance(x, y) * (n - 1) / n if False else (F(sum(F(a) * F(b) for a, b in zip(x, y))) - n * exact_mean(x) * exact_mean(y)) / n)
pv('pearson', statistics.correlation(x, y))

def ranks(v):
    order = sorted(range(len(v)), key=lambda i: v[i])
    r = [0.0] * len(v)
    i = 0
    while i < len(v):
        j = i
        while j < len(v) and v[order[j]] == v[order[i]]: j += 1
        for k in range(i, j): r[order[k]] = (i + 1 + j) / 2
        i = j
    return r
pv('spearman (x, y)', statistics.correlation(ranks(x), ranks(y)))
pv('spearman (t, u) with ties', statistics.correlation(ranks(t), ranks(u)))

def kendall(a, b):
    conc = disc = tx = ty = 0; pairs = 0
    for i in range(len(a)):
        for j in range(i + 1, len(a)):
            dx = a[i] - a[j]; dy = b[i] - b[j]
            pairs += 1
            if dx == 0 and dy == 0: tx += 1; ty += 1
            elif dx == 0: tx += 1
            elif dy == 0: ty += 1
            elif (dx > 0) == (dy > 0): conc += 1
            else: disc += 1
    return (conc - disc) / math.sqrt((pairs - tx) * (pairs - ty))
pv('kendall (x, y)', kendall(x, y))
pv('kendall (t, u) with ties', kendall(t, u))
out.append('ranks: 1')
dump('ranks of t', ranks(t))
out.append('zscores: 1')
pm = exact_mean(x); psd = fsqrt(exact_var(x, 0))
dump('z (first 6)', [(D(F(a).numerator) / D(F(a).denominator) - D(pm.numerator) / D(pm.denominator)) / psd for a in x[:6]])
pv('geometric mean of t', statistics.geometric_mean(t))
pv('harmonic mean of t', statistics.harmonic_mean(t))
w = [float(i + 1) for i in range(17)]
pv('weighted mean of t', sum(F(a) * F(b) for a, b in zip(t, w)) / sum(F(b) for b in w))
pv('geometric mean with a zero', 0.0)

# 3 x 12 data
cols = [[], [], []]
for i in range(12):
    a = (lcg() % 50) / 5.0
    b = (lcg() % 50) / 5.0 + a * 0.5
    c = float(lcg() % 20) - a
    cols[0].append(a); cols[1].append(b); cols[2].append(c)
out.append('covariance matrix: ' + ' '.join(g9(statistics.covariance(cols[i], cols[j])) for i in range(3) for j in range(3)))
out.append('correlation matrix: ' + ' '.join(g9(1.0 if i == j else statistics.correlation(cols[i], cols[j])) for i in range(3) for j in range(3)))
out += ['sortDoubles random: sorted 1, sum kept 1', 'sortDoubles sorted input stays sorted 1, reversed input becomes sorted 1',
        'sortDoubles with only 3 distinct values: 1, first 0 last 2', 'sortDoubles of equal values: 5', 'organ pipe: 1']
# edge cases
pv('mean of one value', 7.5)
chk('variance of one value (n - 1) is NaN', True)
pv('variance of one value (n)', 0.0)
pv('variance of two values', 2.0)
chk('mean of nothing is NaN', True); chk('mean of null is NaN', True)
pv('sum of nothing', 0.0)
pv('median of one value', 7.5)
pv('median of two values', 2.0)
for label in ('mean with NaN', 'variance with NaN', 'median with NaN', 'quantile with NaN', 'minimum with NaN', 'mode with NaN', 'spearman with NaN'):
    chk(label + ' is NaN', True)
out.append('ranks with NaN: 0, ranks of nothing: 0')
out.append('mean with infinity inf, max with infinity inf')
chk('mean of inf and -inf is NaN', True)
chk('variance with infinity is NaN', True)
pv('constant data: variance', 0.0)
chk('constant data: skewness is NaN', True); chk('constant data: kurtosis is NaN', True); chk('constant data: correlation is NaN', True)
chk('unbiased skewness needs 3 values (NaN otherwise)', True)
chk('unbiased kurtosis needs 4 values (NaN otherwise)', True)
for label in ('quantile p = -0.1', 'quantile p = 1.1', 'quantile p = NaN', 'quantile method 0', 'quantile method 10'):
    chk(label + ' is NaN', True)
pv('quantile of one value, every method', 22.5)
chk('geometric mean with a negative value is NaN', True)
chk('geometric mean of a negative value is NaN', True)
chk('negative weight is NaN', True)
out.append('zscores of constant data: 0')
out.append('covarianceMatrix of an empty matrix: ok 0 err 8')
out.append('covarianceMatrix with one observation (n - 1): ok 0 err 8')
out.append('compensated sum of 1e16 and 100000 ones: %s (a plain sum gives 1e16)' % ('%.17g' % math.fsum([1e16] + [1.0] * 100000)))
out.append('memory leaked: 0')
sys.stdout.write('\n'.join(out) + '\n')
