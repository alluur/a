"""Writes the reference tables of tests/t470_numeric_review.a (regression tests for the review of stage algo2) in 70 digit decimals computed from the exact
binary values of the double arguments (refspecial.py):
  T_ERFC   erfc(x) for tiny x (the library returned 1 - x below 2^-27)
  T_NCDF   the standard normal cdf for tiny |z|
  T_TQ     the quantile of Student's t for tiny tails (rows: df, p, quantile)
Run:  python3 tests/algo2_ref/mk_t470.py"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from decimal import Decimal as D, getcontext, localcontext
import refspecial as r
from tbl import table_text, patch

here = os.path.dirname(os.path.abspath(__file__))
target = os.path.join(os.path.dirname(here), 't470_numeric_review.a')

def d(x): return D(float(x))

tables = {}
tables['T_ERFC'] = [[x, float(r.erfc(d(x)))] for x in (1e-15, 1e-12, 1e-10, 1e-9, 5e-9, 7.4e-9, 7.5e-9, 1e-8, 3e-8, -1e-9, -1e-10, -2e-8, 1e-5)]
tables['T_NCDF'] = [[z, float(r.norm_cdf(d(z)))] for z in (1e-12, 1e-10, 1e-9, 1e-8, 2e-8, -1e-9, -3e-9, 5e-9, -1e-8)]

def t_quantile(df, p):
    """the exact quantile of the double p (70 digits): Newton's method on the upper tail with the decimal t distribution; p > 1/2 by symmetry"""
    p = d(p); df = d(df)
    if p > D('0.5'):
        return -t_quantile(float(df), float(1 - p))
    # start: the power law  sf(x) = C x^-df,  C = df^((df - 2) / 2) / B(df / 2, 1 / 2)
    with localcontext() as c:
        c.prec = 90
        lc = (df - 2) / 2 * df.ln() - (r.lgamma(df / 2) + r.lgamma(D('0.5')) - r.lgamma(df / 2 + D('0.5')))
        x = ((lc - p.ln()) / df).exp()
        # the power law overshoots when x is not large: walk down by Newton on log(sf)
        for _ in range(200):
            sf = r.t_sf(x, df)
            if sf == 0:
                x = x * 2; continue
            pdf = r.t_pdf(x, df)
            step = (sf.ln() - p.ln()) * sf / (pdf * x)       # Newton step in log x
            xn = x * (step).exp()
            if abs(xn - x) <= abs(x) * D(10) ** -40:
                x = xn
                break
            x = xn
        return -x                                    # the lower tail quantile (p < 1/2) is negative

rows = []
for df in (0.5, 1, 1.5, 2, 3, 5, 7.5, 30, 100):
    for p in (1e-8, 1e-11, 1e-12, 1e-14, 1e-20, 1e-50, 1e-100, 1e-200, 1e-300):
        q = t_quantile(df, p)
        if abs(q) > D('1e300'):
            continue                                  # not a double: the library answers -infinity (tested separately)
        rows.append([df, p, float(q)])
for df in (3, 7.5):
    for p in (1 - 2.0 ** -50, 1 - 2.0 ** -40, 0.999999):
        rows.append([df, p, float(t_quantile(df, p))])
tables['T_TQ'] = rows

for name, rows in tables.items():
    patch(target, name, table_text(name, rows))
print('patched', ', '.join('%s (%d rows)' % (n, len(r_)) for n, r_ in tables.items()))
