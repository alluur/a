"""Expected output of tests/t450_stats_stream.a: the streaming statistics are computed exactly with fractions; the histogram bin rules are NumPy's formulas
(numpy.histogram_bin_edges) written out with the math module, and the counts use exact edges."""
import math, statistics, sys
from fractions import Fraction as F
from decimal import Decimal as D, getcontext
getcontext().prec = 60

seed = 8675309
def lcg():
    global seed
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    return seed

g9 = lambda v: '%.9g' % float(v)
out = []
def pv(name, v): out.append('%s %s' % (name, g9(v)))
def dump(name, v): out.append('%s %d: %s' % (name, len(v), ' '.join(g9(a) for a in v)))
def chk(label, b): out.append('%s: %d' % (label, 1 if b else 0))
def emean(v): return sum((F(a) for a in v), F(0)) / len(v)
def evar(v, ddof):
    m = emean(v)
    return sum(((F(a) - m) ** 2 for a in v), F(0)) / (len(v) - ddof)
def fsqrt(fr): return D(fr.numerator).sqrt() / D(fr.denominator).sqrt()
def fdec(fr): return D(fr.numerator) / D(fr.denominator)

v = [(lcg() % 20000) / 37.0 - 100.0 for _ in range(300)]
out.append('Welford count 300')
pv('mean', emean(v)); pv('variance (n - 1)', evar(v, 1)); pv('variance (n)', evar(v, 0)); pv('stddev', fsqrt(evar(v, 1)))
pv('sem', fsqrt(evar(v, 1) / 300)); pv('minimum', min(v)); pv('maximum', max(v))
m = emean(v); m2 = sum(((F(a) - m) ** 2 for a in v), F(0)) / 300; m3 = sum(((F(a) - m) ** 3 for a in v), F(0)) / 300; m4 = sum(((F(a) - m) ** 4 for a in v), F(0)) / 300
skew = fdec(m3) / fdec(m2) ** D('1.5'); kurt = m4 / (m2 * m2) - 3
pv('skewness', skew); pv('excess kurtosis', kurt)
chk('equals the batch functions (1e-12 relative)', True)
out.append('merged: count 300')
pv('merged mean', emean(v)); pv('merged variance', evar(v, 1)); pv('merged skewness', skew); pv('merged kurtosis', kurt)
out.append('merged min and max equal: 1, merge into an empty accumulator: count 300 mean equal 1')
chk('30 merged parts of 10: variance', True)
big = [1e9 + (i % 7) for i in range(1000)]
pv('variance of 1e9 + (i mod 7)', evar(big, 1))
out.append('after reset: count 0, mean is NaN 1, variance is NaN 1')
out.append('one value: mean 5, variance(1) is NaN 1, variance(0) 0')
out.append('a NaN poisons the accumulator: mean 1 min 1 var 1')
out.append('constant data: variance 0, skewness is NaN 1')

s = [(lcg() % 100) / 4.0 for _ in range(12)]
dump('series', s)
a = F(0.3)
e = []
for i, x in enumerate(s):
    e.append(F(x) if i == 0 else a * F(x) + (1 - a) * e[-1])
dump('ema alpha 0.3', e)
num = den = F(0); e = []
for x in s:
    num = F(x) + (1 - a) * num; den = 1 + (1 - a) * den
    e.append(num / den)
dump('ema alpha 0.3, adjust', e)
pv('alpha for span 9', 2 / 10)
pv('alpha for half life 3', 1 - 2 ** (-1 / 3))
pv('alpha 1 follows the input', 8.0)
out.append('alpha 0 gives NaN: 1, emaSeries refuses alpha 2: 0')
out.append('current of an empty Ema is NaN: 1')
out.append('after reset: 1 count 0')

d = [(lcg() % 5000) / 13.0 - 150.0 for _ in range(40)]
out.append('window 5, ok 1')
for i in (2, 4, 11, 19, 32, 39):
    k = min(i + 1, 5)
    win = d[i + 1 - k:i + 1]
    out.append('after %d values: size %d full %d' % (i + 1, k, 1 if k == 5 else 0))
    out.append('  mean %s sum %s variance %s stddev %s min %s max %s median %s' % (g9(emean(win)), g9(sum(F(a) for a in win)), g9(evar(win, 1)), g9(fsqrt(evar(win, 1))), g9(min(win)), g9(max(win)), g9(statistics.median(win))))
chk('all 40 steps equal the batch statistics of the window', True)
out.append('window 1: mean 9 min 9 max 9 median 9 variance(1) is NaN 1 variance(0) 0')
out.append('window 0: ok 0 size 0; window 2^26 + 1: ok 0; mean of nothing is NaN 1')
out.append('NaN window: 0 0 0 1 1 1 0 0')
out.append('after the NaN left: mean 7 min 6 max 8 median 7')
last = []
for i in range(200000):
    last.append(1e8 + (lcg() % 100000) / 100.0)
win = last[-100:]
out.append('long run: mean %s variance %s min %s max %s median %s' % (g9(emean(win)), g9(evar(win, 1)), g9(min(win)), g9(max(win)), g9(statistics.median(win))))
out.append('long run: memory flat 1, added 200000')

d = [(lcg() % 1000) / 7.0 for _ in range(30)]
out.append('movingAverage window 7: 24 values')
dump('ma', [emean(d[i:i + 7]) for i in range(24)])
out.append('weightedMovingAverage window 4: 27 values')
dump('wma', [sum(F(k + 1) * F(d[i + k]) for k in range(4)) / 10 for i in range(27)])
out.append('window larger than the data: 0, window 0: 0, window equal to n: 1')
pv('single average', emean(d))
dump('cumsum', [math.fsum(d[:i + 1]) for i in range(30)])
for _ in range(5000): lcg()
out.append('long moving average: 4951 values, worst deviation from the exact mean below 1e-9: 1')

out += ['bins 5 total 14 below 1 above 1 nans 1', 'counts: 3 3 2 3 3', 'edges: 0 2 4 6 8 10', 'density: ' + ' '.join(g9(F(c, 28)) for c in (3, 3, 2, 3, 3)),
        'density integrates to 1: 1, fullest bin 0', 'binOf: -1 0 0 1 4 5 -2', 'out of range accessors: count(-1) 0 count(5) 0, edge(6) is NaN 1, density(7) is NaN 1',
        'after dispose: ok 0, count(0) 0, bins 0', 'invalid histograms: ok 0 0 0 0']

# ---- automatic bins
n = 200
d = [(lcg() % 100000) / 997.0 for _ in range(n)]
lo, hi = min(d), max(d)
ptp = hi - lo
pv('data minimum', lo); pv('data maximum', hi)

def q7(v, p):
    xs = sorted(F(a) for a in v); nn = len(xs); pos = (nn - 1) * F(p)
    j = math.floor(pos); h = pos - j
    return float((1 - h) * xs[j] + h * xs[min(j + 1, nn - 1)])
sd0 = float(fsqrt(evar(d, 0)))
def width(rule):
    if rule == 'sturges': return ptp / (math.log2(n) + 1.0)
    if rule == 'sqrt': return ptp / math.sqrt(n)
    if rule == 'rice': return ptp / (2.0 * n ** (1.0 / 3))
    if rule == 'scott': return (24.0 * math.pi ** 0.5 / n) ** (1.0 / 3.0) * sd0
    fd = 2.0 * (q7(d, 0.75) - q7(d, 0.25)) * n ** (-1.0 / 3)
    if rule == 'fd': return fd
    if rule == 'doane':
        sg1 = math.sqrt(6.0 * (n - 2) / ((n + 1.0) * (n + 3)))
        g1 = float(fdec(F(sum((F(a) - emean(d)) ** 3 for a in d)) / n) / fdec(evar(d, 0)) ** D('1.5'))
        return ptp / (1.0 + math.log2(n) + math.log2(1.0 + abs(g1) / sg1))
    st = ptp / (math.log2(n) + 1.0)           # auto
    return min(fd, st) if fd else st

def counts(bins):
    c = [0] * bins
    L, H = F(lo), F(hi)
    for x in d:
        if F(x) == H: c[bins - 1] += 1; continue
        pos = (F(x) - L) / (H - L) * bins
        b = math.floor(pos)
        assert abs(pos - round(pos)) > F(1, 10 ** 9) or True
        c[min(b, bins - 1)] += 1
    return c

for rule in ('sturges', 'sqrt', 'rice', 'scott', 'fd', 'doane', 'auto'):
    w = width(rule)
    r = ptp / w
    assert abs(r - round(r)) > 1e-9, rule
    bins = int(math.ceil(r))
    # no data value may sit within 1e-9 of an edge (the test would depend on rounding)
    for x in d:
        pos = (x - lo) / ptp * bins
        assert abs(pos - round(pos)) > 1e-9 or x in (lo, hi), (rule, x)
    c = counts(bins)
    out.append('%s: width %s bins %d counts %s total %d' % (rule, g9(w), bins, ' '.join(str(k) for k in c), sum(c)))
c = counts(7)
out.append('fixed 7 bins: ' + ' '.join(str(k) for k in c))
out.append('constant data: bins 1, range 2.5 .. 3.5, counts 5')
out.append('data with NaN: ok 0, binWidth is zero 1, binCount 0')
out.append('one value: binWidth is zero 1, binCount 1')
out.append('unknown rule: binWidth is zero 1')
out.append('memory leaked: 0')
sys.stdout.write('\n'.join(out) + '\n')
