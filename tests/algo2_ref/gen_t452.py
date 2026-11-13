"""Expected output of tests/t452_stats_tests.a: t, chi-square, F and normal p values and quantiles from the 70 digit decimal distributions of refspecial.py,
statistics in exact fractions, the exact Mann-Whitney distribution by dynamic programming over integers, and a Python replay of xoshiro256** for the bootstrap."""
import math, sys
sys.path.insert(0, '.')
from fractions import Fraction as F
from decimal import Decimal as D, getcontext
from statistics import NormalDist
import refspecial as R
getcontext().prec = 60

seed = 424242
def lcg():
    global seed
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    return seed

g9 = lambda v: '%.9g' % float(v)
out = []
def dump(name, v): out.append('%s %d: %s' % (name, len(v), ' '.join(g9(a) for a in v)))
def fdec(fr): return D(fr.numerator) / D(fr.denominator)
def fsqrt(fr): return D(fr.numerator).sqrt() / D(fr.denominator).sqrt()
def emean(v): return sum((F(a) for a in v), F(0)) / len(v)
def evar(v, ddof=1):
    m = emean(v)
    return sum(((F(a) - m) ** 2 for a in v), F(0)) / (len(v) - ddof)
def show(label, stat, df, p, err=0):
    out.append('%s: err %d stat %s df %s p %s' % (label, err, g9(stat), g9(df), g9(p)))
def tails_t(t, df):
    t = D(t)
    two = min(D(1), 2 * R.t_sf(abs(t), df))
    return two, R.t_cdf(t, df), R.t_sf(t, df)       # two sided, less, greater

a = [(lcg() % 1000) / 10.0 + 20.0 for _ in range(12)]
b = [(lcg() % 800) / 10.0 + 35.0 for _ in range(15)]
p1 = [(lcg() % 500) / 10.0 for _ in range(10)]
p2 = [p1[i] + 2.0 + (lcg() % 100 - 50) / 20.0 for i in range(10)]
dump('a', a); dump('b', b); dump('p1', p1); dump('p2', p2)

for which, name in (('two', 'two sided'), ('less', 'less'), ('greater', 'greater')):
    n = 12
    t = fdec(emean(a) - 60) / (fsqrt(evar(a)) / D(n).sqrt())
    two, lo, up = tails_t(t, D(n - 1))
    show('one sample, mu0 = 60, ' + name, t, 11, {'two': two, 'less': lo, 'greater': up}[which])
t = fdec(emean(a)) / (fsqrt(evar(a)) / D(12).sqrt())
show('one sample, mu0 = 0 (tiny p)', t, 11, tails_t(t, D(11))[0])

def welch(x, y):
    nx, ny = len(x), len(y)
    A = evar(x) / nx; B = evar(y) / ny
    t = fdec(emean(x) - emean(y)) / fsqrt(A + B)
    df = (A + B) ** 2 / (A * A / (nx - 1) + B * B / (ny - 1))
    return t, df
def pooled(x, y):
    nx, ny = len(x), len(y)
    sp = ((nx - 1) * evar(x) + (ny - 1) * evar(y)) / (nx + ny - 2)
    t = fdec(emean(x) - emean(y)) / fsqrt(sp * (F(1, nx) + F(1, ny)))
    return t, F(nx + ny - 2)
t, df = welch(a, b)
two, lo, up = tails_t(t, fdec(df))
show('Welch, two sided', t, df, two); show('Welch, less', t, df, lo); show('Welch, greater', t, df, up)
t, df = pooled(a, b)
two, lo, up = tails_t(t, fdec(df))
show('pooled, two sided', t, df, two); show('pooled, less', t, df, lo)
d = [F(p1[i]) - F(p2[i]) for i in range(10)]
t = fdec(emean(d)) / (fsqrt(evar(d)) / D(10).sqrt())
two, lo, up = tails_t(t, D(9))
show('paired, two sided', t, 9, two); show('paired, less', t, 9, lo); show('paired, greater', t, 9, up)

def chi2(label, obs, exp, df):
    stat = sum((F(o) - F(e)) ** 2 / F(e) for o, e in zip(obs, exp))
    show(label, stat, df, R.chi2_sf(fdec(stat), D(df)))
obs = [18, 22, 31, 12, 17]
chi2('goodness of fit, uniform', obs, [20] * 5, 4)
chi2('goodness of fit, given expected', obs, [25, 25, 20, 15, 15], 4)
chi2('goodness of fit, one estimated parameter', obs, [25, 25, 20, 15, 15], 3)
def indep(label, tab, yates=False):
    r = len(tab); c = len(tab[0]); tot = F(sum(sum(row) for row in tab))
    rs = [sum(row) for row in tab]; cs = [sum(tab[i][j] for i in range(r)) for j in range(c)]
    stat = F(0)
    for i in range(r):
        for j in range(c):
            e = F(rs[i] * cs[j]) / tot
            dd = abs(F(tab[i][j]) - e)
            if yates and r == 2 and c == 2:
                dd = max(dd - F(1, 2), F(0))
            stat += dd * dd / e
    df = (r - 1) * (c - 1)
    show(label, stat, df, R.chi2_sf(fdec(stat), D(df)))
indep('independence 3x3', [[12, 8, 20], [15, 9, 7], [6, 14, 11]])
indep('independence 2x2', [[30, 10], [18, 22]])
indep('independence 2x2 with Yates', [[30, 10], [18, 22]], True)
indep('independence 2x3, proportional rows', [[10, 20, 30], [40, 50, 60]])

# ---- Mann-Whitney
def ranks(v):
    order = sorted(range(len(v)), key=lambda i: v[i]); r = [F(0)] * len(v); i = 0
    while i < len(v):
        j = i
        while j < len(v) and v[order[j]] == v[order[i]]: j += 1
        for k in range(i, j): r[order[k]] = F(i + 1 + j, 2)
        i = j
    return r
def u_stat(x, y):
    rk = ranks(list(x) + list(y))
    return sum(rk[:len(x)]) - F(len(x) * (len(x) + 1), 2)
def exact_cdf(n1, n2):
    """distribution of U (counts) by choosing which ranks belong to the first sample"""
    N = n1 + n2
    ways = {(0, 0): 1}
    for rank in range(1, N + 1):
        new = dict(ways)
        for (j, s), c in ways.items():
            if j < n1:
                new[(j + 1, s + rank)] = new.get((j + 1, s + rank), 0) + c
        ways = new
    dist = {}
    for (j, s), c in ways.items():
        if j == n1:
            dist[s - n1 * (n1 + 1) // 2] = dist.get(s - n1 * (n1 + 1) // 2, 0) + c
    return dist, sum(dist.values())
def mw_exact(label, x, y):
    u = u_stat(x, y)
    dist, tot = exact_cdf(len(x), len(y))
    le = F(sum(c for k, c in dist.items() if k <= u), tot); ge = F(sum(c for k, c in dist.items() if k >= u), tot)
    two = min(F(1), 2 * min(le, ge))
    return u, two, le, ge
x7 = [10.0 * i + (lcg() % 10) / 10.0 for i in range(7)]
y9 = [10.0 * i + 5.0 + (lcg() % 10) / 10.0 for i in range(9)]
u, two, le, ge = mw_exact('', x7, y9)
for lab, pp in (('two sided', two), ('less', le), ('greater', ge)):
    show('Mann-Whitney exact 7 and 9, ' + lab, u, 0, pp)
u2, two2, _, _ = mw_exact('', y9, x7)
show('Mann-Whitney exact 9 and 7, two sided', u2, 0, two2)
def mw_asym(x, y):
    n1, n2 = len(x), len(y); n = n1 + n2
    u = u_stat(x, y)
    allv = sorted(list(x) + list(y)); tie = 0; i = 0
    while i < n:
        j = i
        while j < n and allv[j] == allv[i]: j += 1
        tie += (j - i) ** 3 - (j - i); i = j
    mu = F(n1 * n2, 2)
    s2 = F(n1 * n2, 12) * ((n + 1) - F(tie, n * (n - 1)))
    if s2 == 0:
        return u, None, None, None
    s = fsqrt(s2)
    z_two = (fdec(abs(u - mu)) - D('0.5')) / s
    two = min(D(1), 2 * R.norm_sf(z_two))
    up = R.norm_sf((fdec(u - mu) - D('0.5')) / s)
    lo = R.norm_cdf((fdec(u - mu) + D('0.5')) / s)
    return u, two, lo, up
ta = [float(lcg() % 10) for _ in range(12)]
tb = [float(lcg() % 10) + 1.0 for _ in range(15)]
u, two, lo, up = mw_asym(ta, tb)
show('Mann-Whitney with ties, two sided', u, 0, two); show('Mann-Whitney with ties, less', u, 0, lo); show('Mann-Whitney with ties, greater', u, 0, up)
xl = [(lcg() % 100000) / 997.0 for _ in range(30)]
yl = [(lcg() % 100000) / 997.0 + 6.0 for _ in range(35)]
assert len(set(xl + yl)) == 65
u, two, lo, up = mw_asym(xl, yl)
show('Mann-Whitney 30 and 35 (normal approximation), two sided', u, 0, two); show('Mann-Whitney 30 and 35, less', u, 0, lo)
u, two, lo, up = mw_asym([1.0, 2.0, 3.0, 4.0], [1.0, 2.0, 3.0, 4.0])
show('Mann-Whitney of identical samples', u, 0, two)
u, two, _, _ = mw_exact('', [5.0], [1.0, 2.0, 3.0])
show('Mann-Whitney 1 and 3, exact', u, 0, two)
out.append('Mann-Whitney of constant samples (no variance): err 0 stat 4.5 df 0 p nan')

# ---- ANOVA, variance test, Jarque-Bera
groups = [[(lcg() % 500) / 10.0 for _ in range(6)], [(lcg() % 500) / 10.0 + 8.0 for _ in range(8)], [(lcg() % 500) / 10.0 + 3.0 for _ in range(7)]]
dump('groups', [v for g in groups for v in g])
alld = [v for g in groups for v in g]; N = len(alld); k = 3
grand = emean(alld)
ssb = sum(len(g) * (emean(g) - grand) ** 2 for g in groups)
ssw = sum(sum((F(v) - emean(g)) ** 2 for v in g) for g in groups)
Fs = (ssb / (k - 1)) / (ssw / (N - k))
out.append('ANOVA: err 0 F %s df 2 df2 18 p %s' % (g9(Fs), g9(R.f_sf(fdec(Fs), D(2), D(18)))))
Fv = evar(a) / evar(b)
lo = R.f_cdf(fdec(Fv), D(11), D(14)); up = R.f_sf(fdec(Fv), D(11), D(14))
show('variance ratio a / b, two sided', Fv, 11, min(D(1), 2 * min(lo, up))); show('variance ratio a / b, less', Fv, 11, lo); show('variance ratio a / b, greater', Fv, 11, up)
def jb(label, z):
    n = len(z); m = emean(z)
    m2 = sum(((F(v) - m) ** 2 for v in z), F(0)) / n; m3 = sum(((F(v) - m) ** 3 for v in z), F(0)) / n; m4 = sum(((F(v) - m) ** 4 for v in z), F(0)) / n
    S = fdec(m3) / fdec(m2) ** D('1.5'); K = fdec(m4 / (m2 * m2)) - 3
    stat = D(n) / 6 * (S * S + K * K / 4)
    out.append('%s: err 0 stat %s df 2 p %s' % (label, g9(stat), g9((-stat / 2).exp())))
z = []
for _ in range(40):
    s = 0.0
    for _ in range(6):
        s += (lcg() % 1000) / 1000.0
    z.append(s - 3.0)
jb('Jarque-Bera of 40 near normal values', z)
sk = []
for _ in range(30):
    u = (lcg() % 1000) / 1000.0
    sk.append(-math.log(1.0 - u * 0.999))
jb('Jarque-Bera of 30 exponential values', sk)

# ---- confidence intervals
def newton_q(cdf, pdf, p, x0, iters=12):
    x = D(x0)
    for _ in range(iters):
        x = x - (cdf(x) - D(p)) / pdf(x)
    return x
def tq(p, df):
    z = NormalDist().inv_cdf(p)
    return newton_q(lambda x: R.t_cdf(x, D(df)), lambda x: R.t_pdf(x, D(df)), p, z * (1 + 1 / (4.0 * float(df))))
def zq(p): return newton_q(R.norm_cdf, R.norm_pdf, p, NormalDist().inv_cdf(p))
def chi2q(p, k):
    z = NormalDist().inv_cdf(p); w = 2 / (9 * k)
    return newton_q(lambda x: R.chi2_cdf(x, D(k)), lambda x: R.chi2_pdf(x, D(k)), p, k * (1 - w + z * math.sqrt(w)) ** 3)
def bq(p, a, b):
    lo, hi = D(0), D(1)
    for _ in range(110):
        mid = (lo + hi) / 2
        if R.beta_cdf(mid, D(a), D(b)) < D(p): lo = mid
        else: hi = mid
    return (lo + hi) / 2
def interval(label, lo, hi): out.append('%s: [%s, %s]' % (label, g9(lo), g9(hi)))
def mean_ci(x, level):
    n = len(x); h = tq(0.5 + 0.5 * level, n - 1) * fsqrt(evar(x) / n); m = fdec(emean(x))
    return m - h, m + h
interval('mean of a, 95 percent', *mean_ci(a, 0.95)); interval('mean of a, 99 percent', *mean_ci(a, 0.99)); interval('mean of a, 50 percent', *mean_ci(a, 0.5))
A_ = evar(a) / 12; B_ = evar(b) / 15
dfw = (A_ + B_) ** 2 / (A_ * A_ / 11 + B_ * B_ / 14)
h = tq(0.975, fdec(dfw)) * fsqrt(A_ + B_); dm = fdec(emean(a) - emean(b))
interval('a - b, 95 percent (Welch)', dm - h, dm + h)
def var_ci(x, level):
    n = len(x); ss = fdec(evar(x) * (n - 1)); al = 0.5 * (1 - level)
    return ss / chi2q(1 - al, n - 1), ss / chi2q(al, n - 1)
interval('variance of a, 90 percent', *var_ci(a, 0.9)); interval('variance of b, 95 percent', *var_ci(b, 0.95))
def prop(k, n, level, method):
    al = 0.5 * (1 - level); ph = D(k) / D(n)
    if method == 'cp':
        lo = D(0) if k == 0 else bq(al, k, n - k + 1)
        hi = D(1) if k == n else bq(1 - al, k + 1, n - k)
        return lo, hi
    z = zq(1 - al)
    if method == 'wald':
        hh = z * (ph * (1 - ph) / n).sqrt()
        return max(D(0), ph - hh), min(D(1), ph + hh)
    z2 = z * z; den = 1 + z2 / n; c = (ph + z2 / (2 * n)) / den
    hh = z * (ph * (1 - ph) / n + z2 / (4 * n * n)).sqrt() / den
    lo = D(0) if k == 0 else max(D(0), c - hh); hi = D(1) if k == n else min(D(1), c + hh)
    return lo, hi
interval('proportion 7 of 20, Wald', *prop(7, 20, 0.95, 'wald')); interval('proportion 7 of 20, Wilson', *prop(7, 20, 0.95, 'wilson'))
interval('proportion 7 of 20, Clopper-Pearson', *prop(7, 20, 0.95, 'cp'))
interval('proportion 0 of 15, Wilson', *prop(0, 15, 0.95, 'wilson')); interval('proportion 0 of 15, Clopper-Pearson', *prop(0, 15, 0.95, 'cp'))
interval('proportion 15 of 15, Clopper-Pearson', *prop(15, 15, 0.95, 'cp'))
interval('proportion 1 of 200, Wald (clipped at 0)', *prop(1, 200, 0.99, 'wald')); interval('proportion 1 of 200, Clopper-Pearson', *prop(1, 200, 0.99, 'cp'))

# ---- bootstrap: replay xoshiro256** seeded through splitmix64
M64 = (1 << 64) - 1
class Xo:
    def __init__(self, seed):
        s = seed & M64
        st = []
        for _ in range(4):
            s = (s + 0x9E3779B97F4A7C15) & M64
            z = s
            z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & M64
            z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & M64
            st.append(z ^ (z >> 31))
        self.s = st
    def next(self):
        s0, s1, s2, s3 = self.s
        rotl = lambda x, k: ((x << k) | (x >> (64 - k))) & M64
        res = (rotl((s1 * 5) & M64, 7) * 9) & M64
        t = (s1 << 17) & M64
        s2 ^= s0; s3 ^= s1; s1 ^= s2; s0 ^= s3; s2 ^= t; s3 = rotl(s3, 45)
        self.s = [s0, s1, s2, s3]
        return res
    def below(self, n):
        x = self.next(); m = x * n; lo = m & M64; hi = m >> 64
        if lo < n:
            t = ((1 << 64) - n) % n
            while lo < t:
                x = self.next(); m = x * n; lo = m & M64; hi = m >> 64
        return hi
def lerp(a_, b_, t_):
    if a_ == b_: return a_
    return b_ - (b_ - a_) * (1.0 - t_) if t_ >= 0.5 else a_ + (b_ - a_) * t_
def q7(xs, p):
    n = len(xs); nppm = 1.0 + p * (n + 1 - 1.0 - 1.0)
    j = math.floor(nppm + 4 * 2.220446049250313e-16); h = nppm - j
    if abs(h) < 4 * 2.220446049250313e-16: h = 0.0
    i0 = min(max(j - 1, 0), n - 1); i1 = min(max(j, 0), n - 1)
    if h == 0.0: return xs[i0]
    if h == 1.0: return xs[i1]
    return lerp(xs[i0], xs[i1], h)
def boot(x, k, seed, B, level):
    g = Xo(seed); n = len(x); sts = []
    for _ in range(B):
        buf = [x[g.below(n)] for _ in range(n)]
        sts.append(math.fsum(buf) / n * k)
    sts.sort()
    al = 0.5 * (1 - level)
    return q7(sts, al), q7(sts, 1.0 - al)
f = boot(a, 2.5, 2024, 400, 0.9); s_ = boot(a, 1.0, 2024, 400, 0.9)
interval('bootstrap mean of a x 2.5, 90 percent, 400 resamples', *f)
interval('the same without the factor', *s_)
out.append('same seed, same interval: 1')
out.append('the factor scales the interval: 1')
out += ['t test with n = 1: err 8, stat is NaN 1, p is NaN 1', 't test with NaN: err 8; with null: err 8; second sample of size 1: err 8',
        'chi-square with 1 category: err 8; negative count: err 8; zero expected count: err 8; no degrees of freedom left: err 8',
        'independence with an empty column: err 8; with 1 row: err 8', 'Mann-Whitney with NaN: err 8; with null: err 8',
        'ANOVA with an empty group: err 8; with one group: err 8; no residual degrees of freedom: err 8',
        'level 1: NaN 1; level 0: NaN 1; n = 1: NaN 1; k > n: NaN 1; k < 0: NaN 1', 'bootstrap with 5 resamples: NaN 1; without a statistic: NaN 1',
        'Jarque-Bera with 1 value: err 8; with constant data: err 8', 'memory leaked: 0']
sys.stdout.write('\n'.join(out) + '\n')
