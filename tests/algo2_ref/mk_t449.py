"""Writes the reference tables of tests/t449_stats_discrete.a: binomial and Poisson pmf, cdf, upper tail and quantiles in 100 digit decimals built from the exact
doubles (recurrences of the probabilities, so nothing is approximated). The quantile is the smallest k with cdf(k) >= q for the double q. Run:  python3 tests/algo2_ref/mk_t449.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from decimal import Decimal as D, getcontext
from tbl import table_text, patch
getcontext().prec = 110

here = os.path.dirname(os.path.abspath(__file__))
target = os.path.join(os.path.dirname(here), 't449_stats_discrete.a')

def binom_probs(n, p):
    p = D(float(p)); q = 1 - p
    pm = [q ** n]
    for k in range(n):
        pm.append(pm[-1] * (n - k) / (k + 1) * p / q)
    return pm

def pois_probs(lam, kmax):
    lam = D(float(lam))
    pm = [(-lam).exp()]
    for k in range(kmax):
        pm.append(pm[-1] * lam / (k + 1))
    return pm

def cdf_sf(pm, k):
    c = sum(pm[:k + 1], D(0))
    s = sum(pm[k + 1:], D(0))
    return c, s

tables = {}
rows = []
for n, p, ks in ((1, 0.5, (0, 1)), (10, 0.3, (0, 1, 3, 5, 10)), (50, 0.01, (0, 1, 3, 10, 50)), (200, 0.5, (0, 60, 100, 130, 200)), (1000, 0.9, (700, 850, 900, 920, 1000))):
    pm = binom_probs(n, p)
    for k in ks:
        c, s = cdf_sf(pm, k)
        rows.append([n, p, k, float(pm[k]), float(c), float(s)])
tables['T_BINOM'] = rows

rows = []
for lam, ks in ((0.1, (0, 1, 3)), (2.5, (0, 1, 2, 5, 12)), (30, (5, 20, 30, 45, 80)), (400, (300, 380, 400, 440, 520)), (5000, (4700, 4950, 5000, 5100, 5400))):
    kmax = max(ks) + 400
    pm = pois_probs(lam, kmax)
    # the tail beyond kmax is negligible (< 1e-100) for these parameters
    total = sum(pm, D(0))
    for k in ks:
        c = sum(pm[:k + 1], D(0))
        rows.append([lam, k, float(pm[k]), float(c), float(1 - c)])
tables['T_POISSON'] = rows

def quantile_rows_binom():
    rows = []
    for n, p in ((10, 0.3), (50, 0.01), (200, 0.5), (1000, 0.9), (1000000, 1e-5)):
        if n > 100000:
            # a large n with a tiny p: the exact pmf by the same recurrence up to the tail
            pm = binom_probs(0, 0.5)    # placeholder, replaced below
        pm = binom_probs(n, p) if n <= 100000 else None
        if pm is None:
            p_ = D(float(p)); q_ = 1 - p_
            pm = [q_ ** n]
            for k in range(60):
                pm.append(pm[-1] * (n - k) / (k + 1) * p_ / q_)
        cum = []
        s = D(0)
        for v in pm:
            s += v
            cum.append(s)
        # q values: the middle of cdf steps, plus fixed levels
        targets = [0.001, 0.05, 0.5, 0.9, 0.99, 0.999999]
        for t in targets:
            td = D(float(t))
            k = next(i for i, c in enumerate(cum) if c >= td)
            # the distance to the neighbouring steps must be large against the 1e-13 error of the double computation
            lo = cum[k - 1] if k > 0 else D(-1)
            assert td - lo > D('1e-9') and cum[k] - td > D('1e-9'), (n, p, t, k)
            rows.append([n, p, float(t), k])
    return rows
tables['Q_BINOM'] = quantile_rows_binom()

rows = []
for lam in (0.1, 2.5, 30, 400, 5000):
    pm = pois_probs(lam, int(lam * 2 + 200))
    cum = []
    s = D(0)
    for v in pm:
        s += v
        cum.append(s)
    for t in (0.001, 0.05, 0.5, 0.9, 0.99, 0.999999):
        td = D(float(t))
        k = next(i for i, c in enumerate(cum) if c >= td)
        lo = cum[k - 1] if k > 0 else D(-1)
        assert td - lo > D('1e-9') and cum[k] - td > D('1e-9'), (lam, t, k)
        rows.append([lam, float(t), k])
tables['Q_POISSON'] = rows

for name, rows_ in tables.items():
    patch(target, name, table_text(name, rows_))
print('patched', ', '.join('%s (%d)' % (n, len(r_)) for n, r_ in tables.items()))
