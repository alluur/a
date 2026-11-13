"""Expected output of tests/t449_stats_discrete.a: verdicts of the table families (tables from mk_t449.py), identities, a few large parameter values computed in
100 digit decimals (the symmetric binomial median probability by lgamma, Poisson tails by the incomplete gamma function) and the limits of the discrete distributions."""
import math, sys
sys.path.insert(0, '.')
from decimal import Decimal as D, getcontext
import refspecial as r
getcontext().prec = 110
g = lambda v: '%.10g' % float(v)
out = ['binomial pmf, cdf, sf: all within 1e-12: 1', 'Poisson pmf, cdf, sf: all within 1e-12: 1', 'binomial quantile: all within exactly: 1', 'Poisson quantile: all within exactly: 1',
       'cdf(quantile(q)) >= q > cdf(quantile(q) - 1) for 39 levels: 0 violations', 'binomial pmf sums to 1 (1e-13): 1', 'Poisson pmf sums to 1 (1e-13): 1', 'cdf + sf = 1: 0 violations']
# large parameters
n = D(10) ** 9
lpmf = r.lgamma(n + 1) - 2 * r.lgamma(n / 2 + 1) - n * D(2).ln()
pm = lpmf.exp()
out.append('binomCdf(5e8, 1e9, 0.5) %s' % ('%.6g' % float(D('0.5') + pm / 2)))
out.append('binomPmf(5e8, 1e9, 0.5) * sqrt(pi n / 2) %s' % ('%.9g' % float(pm * (r.PI * n / 2).sqrt())))
lam = D(10) ** 8
out.append('poissonCdf(1e8, 1e8) %s' % ('%.6g' % float(r.inc_gamma_q(lam + 1, lam))))
out.append('binomQuantile(0.5, 1e9, 0.5) 500000000')
out.append('poissonQuantile(0.5, 1e6) 1000000')
# binomSf(10, 1e9, 1e-9) and poissonSf(10, 1)
p = D(1e-9); q = 1 - p; N = 10 ** 9
pmf = [q ** N]
for k in range(10):
    pmf.append(pmf[-1] * (N - k) / (k + 1) * p / q)
sf_b = 1 - sum(pmf)
pp = [(-D(1)).exp()]
for k in range(10):
    pp.append(pp[-1] / (k + 1))
sf_p = 1 - sum(pp)
out.append('binomSf(10, 1e9, 1e-9) is the Poisson(1) tail: %s vs %s' % ('%.6g' % float(sf_b), '%.6g' % float(sf_p)))
lines = [
 ('binomPmf(3, 10, 0.5)', g(math.comb(10, 3) / 1024)), ('binomPmf(3.5, 10, 0.5)', '0'), ('binomPmf(-1, 10, 0.5)', '0'), ('binomPmf(11, 10, 0.5)', '0'),
 ('binomPmf(0, 0, 0.5)', '1'), ('binomPmf(0, 5, 0)', '1'), ('binomPmf(5, 5, 1)', '1'), ('binomPmf(4, 5, 1)', '0'), ('binomPmf(1, 10.5, 0.5)', 'nan'),
 ('binomPmf(1, -1, 0.5)', 'nan'), ('binomPmf(1, 10, 1.5)', 'nan'), ('binomPmf(1, 10, nan)', 'nan'), ('binomPmf(nan, 10, 0.5)', 'nan'),
 ('binomCdf(-0.5, 10, 0.5)', '0'), ('binomCdf(10, 10, 0.5)', '1'), ('binomCdf(99, 10, 0.5)', '1'), ('binomCdf(3.9, 10, 0.5) = binomCdf(3)', '0'),
 ('binomCdf(inf, 10, 0.5)', '1'), ('binomCdf(-inf, 10, 0.5)', '0'), ('binomSf(-1, 10, 0.5)', '1'), ('binomSf(10, 10, 0.5)', '0'),
 ('binomQuantile(0, 10, 0.5)', '0'), ('binomQuantile(1, 10, 0.5)', '10'), ('binomQuantile(0.5, 10, 0)', '0'), ('binomQuantile(0.5, 10, 1)', '10'),
 ('binomQuantile(1.5, 10, 0.5)', 'nan'), ('binomQuantile(0.5, 10, 2)', 'nan'),
 ('poissonPmf(0, 0)', '1'), ('poissonPmf(1, 0)', '0'), ('poissonPmf(2.5, 3)', '0'), ('poissonPmf(-1, 3)', '0'), ('poissonPmf(2, -3)', 'nan'),
 ('poissonPmf(2, inf)', '0'), ('poissonPmf(2, nan)', 'nan'), ('poissonCdf(-1, 3)', '0'), ('poissonCdf(5, 0)', '1'), ('poissonCdf(inf, 3)', '1'),
 ('poissonSf(5, 0)', '0'), ('poissonSf(-1, 3)', '1'), ('poissonQuantile(0, 3)', '0'), ('poissonQuantile(1, 3)', 'inf'), ('poissonQuantile(0.5, 0)', '0'),
 ('poissonQuantile(0.5, -1)', 'nan'), ('poissonQuantile(2, 3)', 'nan'),
]
for label, v in lines:
    out.append('%s %s' % (label, v))
sys.stdout.write('\n'.join(out) + '\n')
