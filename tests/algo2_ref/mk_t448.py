"""Writes the reference tables of tests/t448_stats_dist.a: pdf, cdf and upper tail of the continuous distributions, and quantiles, in 70 digit decimals
computed from the exact binary values of the double parameters. The quantile of a double probability p_d is x_true + (p_d - cdf(x_true)) / pdf(x_true)
for a decimal x_true with cdf(x_true) = p (the error of the first order formula is below 1e-30). Run:  python3 tests/algo2_ref/mk_t448.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from decimal import Decimal as D
import refspecial as r
from tbl import table_text, patch

here = os.path.dirname(os.path.abspath(__file__))
target = os.path.join(os.path.dirname(here), 't448_stats_dist.a')
def d(x): return D(float(x))
def f(v): return float(v)

tables = {}
rows = []
for mu, sg in ((0.0, 1.0), (2.5, 0.7), (-10.0, 100.0)):
    for z in (-8, -3, -1, 0, 0.5, 2, 5, 10):
        x = mu + sg * z
        rows.append([mu, sg, x, f(r.norm_pdf(d(x), d(mu), d(sg))), f(r.norm_cdf(d(x), d(mu), d(sg))), f(r.norm_sf(d(x), d(mu), d(sg)))])
tables['T_NORMAL'] = rows

rows = []
for df in (1, 2, 3.5, 10, 30, 200.5):
    for x in (-6, -2, -0.3, 0, 0.5, 1.5, 4, 12):
        rows.append([df, x, f(r.t_pdf(d(x), d(df))), f(r.t_cdf(d(x), d(df))), f(r.t_sf(d(x), d(df)))])
tables['T_T'] = rows
rows = []
for df in (1e4, 1e5):
    for x in (-6, -2, -0.3, 0, 0.5, 1.5, 4, 12):
        rows.append([df, x, f(r.t_pdf(d(x), d(df))), f(r.t_cdf(d(x), d(df))), f(r.t_sf(d(x), d(df)))])
tables['T_TBIG'] = rows

rows = []
for k in (1, 2, 5, 10.5, 50, 300):
    for m in (0.05, 0.5, 1, 2, 4):
        x = k * m
        rows.append([k, x, f(r.chi2_pdf(d(x), d(k))), f(r.chi2_cdf(d(x), d(k))), f(r.chi2_sf(d(x), d(k)))])
tables['T_CHI2'] = rows

rows = []
for d1, d2 in ((1, 1), (2, 5), (5, 2), (10, 10), (3.5, 40), (100, 100)):
    for x in (0.1, 0.5, 1, 2, 5):
        rows.append([d1, d2, x, f(r.f_pdf(d(x), d(d1), d(d2))), f(r.f_cdf(d(x), d(d1), d(d2))), f(r.f_sf(d(x), d(d1), d(d2)))])
tables['T_F'] = rows

rows = []
for a, sc in ((0.5, 1), (1, 2), (2.5, 0.5), (10, 3), (100, 1)):
    for m in (0.2, 1, 2.5):
        x = a * sc * m
        rows.append([a, sc, x, f(r.gamma_pdf(d(x), d(a), d(sc))), f(r.gamma_cdf(d(x), d(a), d(sc))), f(r.gamma_sf(d(x), d(a), d(sc)))])
tables['T_GAMMA'] = rows

rows = []
for a, b in ((0.5, 0.5), (2, 5), (10, 3), (30, 30)):
    for x in (0.05, 0.3, 0.5, 0.9):
        rows.append([a, b, x, f(r.beta_pdf(d(x), d(a), d(b))), f(r.beta_cdf(d(x), d(a), d(b))), f(r.beta_sf(d(x), d(a), d(b)))])
tables['T_BETA'] = rows

rows = []
for rate in (0.1, 1, 25):
    for x in (0.01, 0.5, 3, 40):
        rows.append([rate, x, f(r.expon_pdf(d(x), d(rate))), f(r.expon_cdf(d(x), d(rate))), f(r.expon_sf(d(x), d(rate)))])
tables['T_EXP'] = rows

rows = []
for mu, sg in ((0, 1), (1.5, 0.4)):
    for x in (0.1, 1, 3, 20):
        rows.append([mu, sg, x, f(r.lognorm_pdf(d(x), d(mu), d(sg))), f(r.lognorm_cdf(d(x), d(mu), d(sg)))])
tables['T_LOGN'] = rows

# ---- quantiles
def qrow(cdf, pdf, xs, params):
    out = []
    for x in xs:
        x = D(x)
        p = cdf(x)
        pd = float(p)
        if not (1e-300 < pd < 1 - 1e-6):
            continue          # the quantile of a probability that is within 1e-6 of 1 is too sensitive to the rounding of p for the first order reference
        xq = x + (D(pd) - p) / pdf(x)
        out.append(params + [pd, float(xq)])
    return out

rows = []
for mu, sg in ((0.0, 1.0), (2.5, 0.7)):
    rows += qrow(lambda x: r.norm_cdf(x, d(mu), d(sg)), lambda x: r.norm_pdf(x, d(mu), d(sg)), [D(mu) + D(sg) * D(z) for z in ('-6.2', '-3', '-1.3', '0.25', '1', '2.5', '4.5')], [mu, sg])
tables['Q_NORMAL'] = rows
rows = []
for df in (1, 2.5, 10, 100):
    rows += qrow(lambda x: r.t_cdf(x, d(df)), lambda x: r.t_pdf(x, d(df)), ['-8', '-2.5', '-0.4', '0.7', '1.7', '6'], [df])
tables['Q_T'] = rows
rows = []
for k in (1, 4, 10.5, 60):
    rows += qrow(lambda x: r.chi2_cdf(x, d(k)), lambda x: r.chi2_pdf(x, d(k)), [D(k) * D(m) for m in ('0.02', '0.3', '0.9', '1.4', '2.3')], [k])
tables['Q_CHI2'] = rows
rows = []
for d1, d2 in ((2, 5), (10, 10), (3.5, 40)):
    rows += qrow(lambda x: r.f_cdf(x, d(d1), d(d2)), lambda x: r.f_pdf(x, d(d1), d(d2)), ['0.05', '0.4', '1', '2.2', '6'], [d1, d2])
tables['Q_F'] = rows
rows = []
for a, sc in ((0.5, 1), (2.5, 0.5), (30, 3)):
    rows += qrow(lambda x: r.gamma_cdf(x, d(a), d(sc)), lambda x: r.gamma_pdf(x, d(a), d(sc)), [D(a) * D(sc) * D(m) for m in ('0.01', '0.4', '1', '1.8', '3')], [a, sc])
tables['Q_GAMMA'] = rows
rows = []
for a, b in ((0.5, 0.5), (2, 5), (30, 30)):
    rows += qrow(lambda x: r.beta_cdf(x, d(a), d(b)), lambda x: r.beta_pdf(x, d(a), d(b)), ['0.02', '0.2', '0.5', '0.77', '0.97'], [a, b])
tables['Q_BETA'] = rows
rows = []
for rate in (0.1, 25):
    rows += qrow(lambda x: r.expon_cdf(x, d(rate)), lambda x: r.expon_pdf(x, d(rate)), [D('0.001') / D(rate) * D(m) for m in (1, 100, 1000, 2000, 20000, 400000)], [rate])
tables['Q_EXP'] = rows
rows = []
for mu, sg in ((0, 1), (1.5, 0.4)):
    rows += qrow(lambda x: r.lognorm_cdf(x, d(mu), d(sg)), lambda x: r.lognorm_pdf(x, d(mu), d(sg)), ['0.05', '0.5', '1', '3', '20'], [mu, sg])
tables['Q_LOGN'] = rows

for name, rows_ in tables.items():
    patch(target, name, table_text(name, rows_))
print('patched', ', '.join('%s (%d)' % (n, len(r_)) for n, r_ in tables.items()))
