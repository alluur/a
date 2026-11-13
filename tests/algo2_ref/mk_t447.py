"""Writes the reference table of tests/t447_stats_special.a: rows (x, ..., exact value) of the special functions computed in 70 digit decimals from the
exact binary values of the double arguments (refspecial.py). Run:  python3 tests/algo2_ref/mk_t447.py"""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from decimal import Decimal as D, getcontext
import refspecial as r
from tbl import table_text, patch
from statistics import NormalDist

here = os.path.dirname(os.path.abspath(__file__))
target = os.path.join(os.path.dirname(here), 't447_stats_special.a')

def d(x): return D(float(x))

tables = {}
def add(name, rows): tables[name] = rows

add('T_ERF', [[x, float(r.erf(d(x)))] for x in (-3, -1.5, -0.5, -1e-5, 1e-10, 0.1, 0.5, 1, 2, 3, 5, 6.5)])
add('T_ERFC', [[x, float(r.erfc(d(x)))] for x in (-5, -2, -0.5, 0, 0.5, 1, 2, 3, 5, 8, 10, 15, 26)])
add('T_LGAMMA', [[x, float(r.lgamma(d(x)))] for x in (0.01, 0.1, 0.5, 1.5, 2.5, 4.5, 10, 50.5, 100, 1000.25, 12345.5, 1e6)])
add('T_GAMMA', [[x, float(r.gamma_fn(d(x)))] for x in (0.01, 0.1, 0.5, 1.5, 3.5, 7.25, 20.5, 50, 100.5, 170)])
add('T_DIGAMMA', [[x, float(r.digamma(d(x)))] for x in (0.01, 0.1, 0.5, 1, 2.5, 10, 100, 1e5, -0.5, -1.5, -7.25)])
rows = []
for a in (0.5, 1, 2.5, 10, 50, 200):
    for f in (0.1, 0.5, 1, 1.5, 3, 10):
        x = a * f
        rows.append([a, x, float(r.inc_gamma_p(d(a), d(x))), float(r.inc_gamma_q(d(a), d(x)))])
add('T_INCGAMMA', rows)
rows = []
for a in (0.5, 2, 5.5, 30, 150):
    for b in (0.5, 2, 5.5, 30, 150):
        for x in (0.01, 0.2, 0.5, 0.8, 0.99):
            lo = r.inc_beta(d(x), d(a), d(b))
            rows.append([x, a, b, float(lo), float(r.inc_beta_upper(d(x), d(a), d(b)))])
add('T_INCBETA', rows)
rows = []
for a, b in ((0.5, 0.5), (1, 1), (2, 3.5), (10, 20), (100.5, 0.25), (0.001, 5)):
    v = r.lgamma(d(a)) + r.lgamma(d(b)) - r.lgamma(d(a) + d(b))
    rows.append([a, b, float(v) if abs(v) > D(10) ** -60 else 0.0])
add('T_LBETA', rows)

def erfinv_ref(y):
    y = d(y)
    x = D(NormalDist().inv_cdf((float(y) + 1) / 2) / math.sqrt(2)) if abs(float(y)) < 1 - 1e-12 else D(5.0)
    for _ in range(12):
        # erf(x) - y, written as (1 - y) - erfc(x) for large y so that the difference keeps its digits
        f = r.erf(x) - y if y < D('0.5') else (1 - y) - r.erfc(x)
        deriv = 2 / r.SQRT_PI * (-(x * x)).exp()
        x = x - f / deriv
    return x
rows = []
for y in (0.1, 0.3, 0.5, 0.9, 0.999, 1 - 1e-10):
    ref = erfinv_ref(y)
    rows.append([y, float(ref)])
    rows.append([-y, -float(ref)])
add('T_ERFINV', rows)

def normq_ref(p):
    p = d(p)
    x = D(NormalDist().inv_cdf(float(p))) if 1e-300 < float(p) < 1 - 1e-16 else D(-37)
    for _ in range(12):
        f = r.norm_cdf(x) - p
        x = x - f / r.norm_pdf(x)
    return x
rows = []
for p in (1e-300, 1e-100, 1e-20, 1e-10, 1e-5, 0.001, 0.025, 0.1, 0.3, 0.5, 0.7, 0.975, 0.999, 1 - 1e-10):
    rows.append([p, float(normq_ref(p))])
add('T_NORMQ', rows)

for name, rows in tables.items():
    pass
src = open(target).read()
for name, rows in tables.items():
    patch(target, name, table_text(name, rows))
print('patched', ', '.join('%s (%d rows)' % (n, len(r_)) for n, r_ in tables.items()))
