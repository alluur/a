"""Expected output of tests/t463_numeric_examples.a: the examples of the module headers and of docs/ALGO.md. The statistics are exact fractions (mean, variance, the regression through
the exact normal equations), the p values come from the 70 digit decimal distributions of refspecial.py, the matrix example is solved exactly (the inverse by the adjugate: det -1,
solution 6, 15, -23, 1-norm condition number 4 * 9 = 36), the root of exp(-2 x) = 1/2 is ln(2) / 2."""
import math, sys
sys.path.insert(0, '.')
from fractions import Fraction as F
from decimal import Decimal as D, getcontext
import refspecial as R
getcontext().prec = 60
g9 = lambda v: '%.9g' % float(v)
x = [F(s) for s in ('2.1', '2.5', '3.1', '3.6', '4.0', '4.4', '5.2', '5.9')]
y = [F(s) for s in ('1.1', '1.7', '2.0', '2.8', '3.1', '3.9', '4.2', '5.0')]
# the data are decimal literals: the double nearest to each is what the program sees
x = [F(float(v)) for v in x]; y = [F(float(v)) for v in y]
n = len(x)
emean = lambda v: sum(v, F(0)) / len(v)
evar = lambda v: sum(((a - emean(v)) ** 2 for a in v), F(0)) / (len(v) - 1)
fsqrt = lambda fr: D(fr.numerator).sqrt() / D(fr.denominator).sqrt()
out = []
out.append('mean ' + g9(emean(x)))
out.append('stddev ' + g9(fsqrt(evar(x))))
xs = sorted(x)
out.append('median ' + g9((xs[3] + xs[4]) / 2))
# quantile method 7: h = (n - 1) p, linear interpolation between neighbours
h = F(n - 1) * F(1, 4)
lo = int(h)
out.append('quantile 0.25 ' + g9(xs[lo] + (h - lo) * (xs[lo + 1] - xs[lo])))
mx, my = emean(x), emean(y)
sxx = sum(((a - mx) ** 2 for a in x), F(0)); sxy = sum(((a - mx) * (b - my) for a, b in zip(x, y)), F(0)); syy = sum(((b - my) ** 2 for b in y), F(0))
slope = sxy / sxx; icpt = my - slope * mx
sse = syy - slope * sxy
df = n - 2
out.append('regression status 0, n %d, p 2, df %d' % (n, df))
out.append('intercept ' + g9(icpt))
out.append('slope ' + g9(slope))
out.append('r2 ' + g9(1 - sse / syy))
se_slope2 = (sse / df) / sxx
tval = D(slope.numerator) / D(slope.denominator) / fsqrt(se_slope2)
out.append('slope p value ' + g9(min(D(1), 2 * R.t_sf(abs(tval), df))))
res = [b - (icpt + slope * a) for a, b in zip(x, y)]
out.append('residual 0 ' + g9(res[0]))
out.append('residual 7 ' + g9(res[7]))
out.append('predict(4.2) ' + g9(icpt + slope * F(float(4.2))))
# Welch
vx, vy = evar(x), evar(y)
sx, sy = vx / n, vy / n
tstat = (D((mx - my).numerator) / D((mx - my).denominator)) / fsqrt(sx + sy)
wdf = (sx + sy) ** 2 / (sx ** 2 / (n - 1) + sy ** 2 / (n - 1))
out.append('t ' + g9(tstat))
out.append('df ' + g9(wdf))
out.append('p value ' + g9(min(D(1), 2 * R.t_sf(abs(tstat), D(wdf.numerator) / D(wdf.denominator)))))
out.append('tSf(2.5, 7) ' + g9(R.t_sf(D(2.5), 7)))
out.append('normalQuantile(0.975) 1.95996398454005')
# 95 percent confidence interval of the mean: mean -+ t_{0.975, 7} s / sqrt(n); the quantile solved in decimals
tq = R.quantile(lambda t: R.t_cdf(t, 7), D('0.975'), D(0), D(10))
half = tq * fsqrt(evar(x) / n)
m = D(mx.numerator) / D(mx.denominator)
out.append('ci lo ' + g9(m - half))
out.append('ci hi ' + g9(m + half))
out.append('x = 6 15 -23')
out.append('det -1')
out.append('rcond within a factor 3 of the exact value 1/36: 1')
out.append('root ' + g9(D(2).ln() / 2))
out.append('calls counted by the context equal evals: 1, iterations below 30: 1')
out.append('residual below 1e-12: 1')
out.append('memory leaked: 0')
print('\n'.join(out))
