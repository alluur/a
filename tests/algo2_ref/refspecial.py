"""High precision reference implementations (Python standard library only: decimal, fractions, math).

Used by the generators of the expected outputs of the tests t440 .. t469 of the A repository: special functions
(erf, erfc, gamma, incomplete gamma and beta), the distributions (cdf, sf, pdf, quantile) with 60 significant digits,
so that the doubles computed by the A library are checked against values that are exact to far more digits than a
double has.  Nothing here depends on the A implementation.
"""
from decimal import Decimal as D, getcontext, localcontext
import math

PREC = 70
getcontext().prec = PREC

def dpi():
    # Machin / Chudnovsky is overkill: use the Gauss-Legendre algorithm
    with localcontext() as c:
        c.prec = PREC + 10
        a = D(1); b = 1 / D(2).sqrt(); t = D(1) / 4; p = D(1)
        for _ in range(12):
            an = (a + b) / 2
            b = (a * b).sqrt()
            t -= p * (a - an) ** 2
            a = an
            p *= 2
        return (a + b) ** 2 / (4 * t)

PI = dpi()
SQRT_PI = PI.sqrt()
LN2PI = (2 * PI).ln()

def erf(x):
    x = D(x)
    # Taylor series  2/sqrt(pi) * sum (-1)^n x^(2n+1) / (n! (2n+1)); use the e^(-x^2) form that has no cancellation
    #  erf(x) = 2/sqrt(pi) * exp(-x^2) * sum 2^n x^(2n+1) / (1*3*5*...*(2n+1))
    with localcontext() as c:
        c.prec = PREC + 20
        s = D(0); term = x
        n = 0
        while True:
            s += term
            n += 1
            term = term * 2 * x * x / (2 * n + 1)
            if abs(term) < abs(s) * D(10) ** (-(PREC + 15)) and n > 5:
                break
        return 2 / SQRT_PI * (-(x * x)).exp() * s

def erfc(x):
    x = D(x)
    with localcontext() as c:
        # erfc(x) = 1 - erf(x); extra precision for the cancellation (erfc(10) ~ 2e-45)
        extra = int(float(x) ** 2 / 2.3) + 10 if x > 0 else 10
        c.prec = PREC + extra
        return 1 - erf(x) if x < 0 else (1 - erf_hp(x, extra))

def erf_hp(x, extra):
    with localcontext() as c:
        c.prec = PREC + extra + 20
        s = D(0); term = x; n = 0
        while True:
            s += term
            n += 1
            term = term * 2 * x * x / (2 * n + 1)
            if abs(term) < abs(s) * D(10) ** (-(PREC + extra + 15)) and n > 5:
                break
        return 2 / SQRT_PI * (-(x * x)).exp() * s

BERN = [D(1), D(-1) / 2, D(1) / 6, D(0), D(-1) / 30, D(0), D(1) / 42, D(0), D(-1) / 30, D(0), D(5) / 66, D(0), D(-691) / 2730,
        D(0), D(7) / 6, D(0), D(-3617) / 510, D(0), D(43867) / 798, D(0), D(-174611) / 330, D(0), D(854513) / 138,
        D(0), D(-236364091) / 2730, D(0), D(8553103) / 6]

def lgamma(x):
    x = D(x)
    with localcontext() as c:
        c.prec = PREC + 20
        shift = D(0)
        while x < 60:
            shift += x.ln()
            x += 1
        # Stirling series
        s = (x - D('0.5')) * x.ln() - x + LN2PI / 2
        xp = x
        for k in range(1, 14):
            b = BERN[2 * k]
            s += b / (2 * k * (2 * k - 1) * xp)
            xp *= x * x
        return s - shift

def gamma_fn(x):
    return lgamma(x).exp()

def inc_gamma_p(a, x):
    """regularized lower incomplete gamma P(a, x)"""
    a = D(a); x = D(x)
    if x == 0: return D(0)
    with localcontext() as c:
        c.prec = PREC + 30
        # series: x^a e^-x / Gamma(a+1) * sum x^n / ((a+1)...(a+n))
        s = D(1); term = D(1); n = 0
        while True:
            n += 1
            term = term * x / (a + n)
            s += term
            if term < s * D(10) ** (-(PREC + 20)):
                break
        return (a * x.ln() - x - lgamma(a + 1)).exp() * s

def inc_gamma_q(a, x):
    a = D(a); x = D(x)
    with localcontext() as c:
        c.prec = PREC + 60
        return 1 - inc_gamma_p(a, x)

def inc_beta(x, a, b):
    """regularized incomplete beta I_x(a, b) by the hypergeometric series (x < 1)"""
    x = D(x); a = D(a); b = D(b)
    if x <= 0: return D(0)
    if x >= 1: return D(1)
    with localcontext() as c:
        c.prec = PREC + 40
        if x > (a + 1) / (a + b + 2):
            return 1 - inc_beta(1 - x, b, a)
        lb = lgamma(a + b) - lgamma(a) - lgamma(b)
        pre = (lb + a * x.ln() + b * (1 - x).ln()).exp() / a
        # 2F1(a+b, 1; a+1; x) = sum (a+b)_n / (a+1)_n x^n
        s = D(1); term = D(1); n = 0
        while True:
            term = term * (a + b + n) / (a + 1 + n) * x
            n += 1
            s += term
            if term < s * D(10) ** (-(PREC + 20)) or n > 200000:
                break
        return pre * s

def inc_beta_upper(x, a, b):
    x = D(x)
    with localcontext() as c:
        c.prec = PREC + 60
        return 1 - inc_beta(x, a, b) if x <= (D(a) + 1) / (D(a) + D(b) + 2) else inc_beta(1 - x, b, a)

# ---- distributions -----------------------------------------------------------------------------------------------------------
def norm_cdf(x, mu=0, sigma=1):
    z = (D(x) - D(mu)) / D(sigma)
    return erfc(-z / D(2).sqrt()) / 2

def norm_sf(x, mu=0, sigma=1):
    z = (D(x) - D(mu)) / D(sigma)
    return erfc(z / D(2).sqrt()) / 2

def norm_pdf(x, mu=0, sigma=1):
    z = (D(x) - D(mu)) / D(sigma)
    return (-(z * z) / 2).exp() / (D(sigma) * (2 * PI).sqrt())

def t_sf(x, df):
    x = D(x); df = D(df)
    with localcontext() as c:
        c.prec = PREC + 20
        ib = inc_beta(df / (df + x * x), df / 2, D('0.5'))      # P(|T| > |x|)
        tail = ib / 2
        return tail if x >= 0 else 1 - tail

def t_cdf(x, df):
    x = D(x)
    return 1 - t_sf(x, df) if x >= 0 else t_sf(-x, df)

def t_pdf(x, df):
    x = D(x); df = D(df)
    return (lgamma((df + 1) / 2) - lgamma(df / 2)).exp() / (df * PI).sqrt() * (1 + x * x / df) ** (-(df + 1) / 2)

def chi2_cdf(x, k):
    return inc_gamma_p(D(k) / 2, D(x) / 2)

def chi2_sf(x, k):
    return inc_gamma_q(D(k) / 2, D(x) / 2)

def chi2_pdf(x, k):
    x = D(x); k = D(k)
    return ((k / 2 - 1) * x.ln() - x / 2 - k / 2 * D(2).ln() - lgamma(k / 2)).exp()

def gamma_cdf(x, a, scale=1):
    return inc_gamma_p(a, D(x) / D(scale))

def gamma_pdf(x, a, scale=1):
    x = D(x); a = D(a); s = D(scale)
    return ((a - 1) * x.ln() - x / s - a * s.ln() - lgamma(a)).exp()

def f_cdf(x, d1, d2):
    x = D(x); d1 = D(d1); d2 = D(d2)
    return inc_beta(d1 * x / (d1 * x + d2), d1 / 2, d2 / 2)

def f_sf(x, d1, d2):
    x = D(x); d1 = D(d1); d2 = D(d2)
    return inc_beta_upper(d1 * x / (d1 * x + d2), d1 / 2, d2 / 2)

def f_pdf(x, d1, d2):
    x = D(x); d1 = D(d1); d2 = D(d2)
    lb = lgamma(d1 / 2) + lgamma(d2 / 2) - lgamma((d1 + d2) / 2)
    return (d1 / 2 * d1.ln() + d2 / 2 * d2.ln() + (d1 / 2 - 1) * x.ln() - (d1 + d2) / 2 * (d2 + d1 * x).ln() - lb).exp()

def beta_cdf(x, a, b):
    return inc_beta(x, a, b)

def beta_pdf(x, a, b):
    x = D(x); a = D(a); b = D(b)
    return ((a - 1) * x.ln() + (b - 1) * (1 - x).ln() - (lgamma(a) + lgamma(b) - lgamma(a + b))).exp()

def binom_pmf(k, n, p):
    from fractions import Fraction
    p = Fraction(str(p)) if not isinstance(p, Fraction) else p
    return D(math.comb(n, k)) * D(p.numerator) / D(p.denominator) if False else _binom_pmf(k, n, p)

def _binom_pmf(k, n, p):
    from fractions import Fraction
    p = Fraction(p) if isinstance(p, Fraction) else Fraction(float(p))
    v = math.comb(n, k) * p ** k * (1 - p) ** (n - k)
    return D(v.numerator) / D(v.denominator)

def binom_cdf(k, n, p):
    return sum((_binom_pmf(i, n, p) for i in range(0, k + 1)), D(0))

def binom_sf(k, n, p):
    return sum((_binom_pmf(i, n, p) for i in range(k + 1, n + 1)), D(0))

def pois_pmf(k, lam):
    lam = D(lam)
    return (k * lam.ln() - lam - lgamma(D(k) + 1)).exp() if lam > 0 else (D(1) if k == 0 else D(0))

def pois_cdf(k, lam):
    return inc_gamma_q(D(k + 1), D(lam))

def pois_sf(k, lam):
    return inc_gamma_p(D(k + 1), D(lam))

def quantile(cdf, p, lo, hi, iters=400):
    """bisection on a decimal cdf"""
    p = D(p); lo = D(lo); hi = D(hi)
    for _ in range(iters):
        mid = (lo + hi) / 2
        if cdf(mid) < p:
            lo = mid
        else:
            hi = mid
        if hi - lo < D(10) ** (-30) * max(abs(hi), D(1)):
            break
    return (lo + hi) / 2

def fmt(v, digits=9):
    """the text an A program prints with doubleToSci(v, digits - 1): digits significant digits, e.g. 1.23456789e+00"""
    v = float(v)
    return ('%.' + str(digits - 1) + 'e') % v
