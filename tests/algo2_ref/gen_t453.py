"""Expected output of tests/t453_stats_series_cluster.a: autocovariances in exact fractions, the partial autocorrelation as the last coefficient of the exactly solved
Yule-Walker system, Ljung-Box with the 70 digit chi-square tail, k-means on blobs whose optimum follows from their construction (blob means; for k = 2 the cheapest merge
of two blobs, checked here against all three possibilities), PCA by the Jacobi eigen decomposition of the exact covariance matrix in 60 digit decimals."""
import math, sys
sys.path.insert(0, '.')
from fractions import Fraction as F
from decimal import Decimal as D, getcontext
import refspecial as R
from refmat import jacobi
getcontext().prec = 60

seed = 1618033
def lcg():
    global seed
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    return seed

g9 = lambda v: '%.9g' % float(v)
out = []
def pv(name, v): out.append('%s %s' % (name, g9(v)))
def dump(name, v): out.append('%s %d: %s' % (name, len(v), ' '.join(g9(a) for a in v)))
def fdec(fr): return D(fr.numerator) / D(fr.denominator)
def emean(v): return sum((F(a) for a in v), F(0)) / len(v)

n = 60
x = []; prev = 0.0
for _ in range(n):
    prev = 0.75 * prev + (lcg() % 200 - 100) / 64.0
    x.append(prev)
dump('series (first 8)', x[:8])
m = emean(x)
def acov(k): return sum((F(x[i]) - m) * (F(x[i - k]) - m) for i in range(k, n)) / n
pv('autocovariance lag 0', acov(0)); pv('autocovariance lag 1', acov(1)); pv('autocovariance lag 5', acov(5)); pv('autocovariance lag 59', acov(59))
out.append('autocovariance lag 60 is NaN 1, lag -1 is NaN 1')
acf = [acov(k) / acov(0) for k in range(11)]
out.append('acf: 1'); dump('acf lags 0..10', acf)
def solve(A, b):
    nn = len(A)
    M = [[F(v) for v in row] + [F(bb)] for row, bb in zip(A, b)]
    for k in range(nn):
        p = next(i for i in range(k, nn) if M[i][k] != 0)
        M[k], M[p] = M[p], M[k]
        for i in range(nn):
            if i != k and M[i][k] != 0:
                f = M[i][k] / M[k][k]
                M[i] = [a - f * c for a, c in zip(M[i], M[k])]
    return [M[i][nn] / M[i][i] for i in range(nn)]
def pacf(k):
    if k == 0: return F(1)
    R_ = [[acf[abs(i - j)] for j in range(k)] for i in range(k)]
    return solve(R_, [acf[i + 1] for i in range(k)])[k - 1]
out.append('pacf: 1'); dump('pacf lags 0..8', [pacf(k) for k in range(9)])
def ljung(lags, df):
    q = sum(acf[k] ** 2 / (n - k) for k in range(1, lags + 1)) * n * (n + 2)
    return q, R.chi2_sf(fdec(q), D(df))
q, p = ljung(10, 10); out.append('Ljung-Box lags 10: err 0 stat %s df 10 p %s' % (g9(q), g9(p)))
q, p = ljung(10, 8); out.append('Ljung-Box lags 10, 2 fitted parameters: err 0 stat %s df 8 p %s' % (g9(q), g9(p)))
for _ in range(200): lcg()
out += ['white noise: all of acf 1..5 below 0.2 in absolute value: 1', 'constant series: acf 0, pacf 0, Ljung-Box err 8', 'maxLag >= n: 0, maxLag -1: 0, n = 1: 0, null: 0',
        'Ljung-Box with lags = n: err 8; with more fitted parameters than lags: err 8', 'series with NaN: acf 0']

# ---- k-means
per = 20
blobs = []
cx = [0.0, 10.0, 5.0]; cy = [0.0, 0.0, 9.0]
for c in range(3):
    pts = []
    for i in range(per):
        a = cx[c] + (lcg() % 128 - 64) / 64.0
        b = cy[c] + (lcg() % 128 - 64) / 64.0
        pts.append((a, b))
    blobs.append(pts)
def mean2(pts): return (sum(F(p[0]) for p in pts) / len(pts), sum(F(p[1]) for p in pts) / len(pts))
def ss(pts):
    mx, my = mean2(pts)
    return sum((F(p[0]) - mx) ** 2 + (F(p[1]) - my) ** 2 for p in pts)
means = sorted(mean2(b) for b in blobs)
out.append('kmeans k = 3: ok 1, err 0, k 3, dim 2, n 60')
out.append('centers sorted by x: ' + ' '.join('(%s, %s)' % (g9(a), g9(b)) for a, b in means))
pv('inertia', sum(ss(b) for b in blobs))
out.append('every blob is one cluster: 1, three different labels: 1')
out.append('cluster sizes 20 20 20')
out.append('iterations between 1 and 300: 1')
out.append('predict (9, 1) gives the blob around x = 10: center (%s, %s)' % tuple(g9(v) for v in mean2(blobs[1])))
out.append('predict (4, 8): center (%s, %s)' % tuple(g9(v) for v in mean2(blobs[2])))
out.append('same seed, same result: 1')
out.append('after dispose: ok 0, predict -1')
allp = [p for b in blobs for p in b]
mx, my = mean2(allp)
out.append('k = 1: center (%s, %s), inertia %s' % (g9(mx), g9(my), g9(ss(allp))))
out.append('k = n: err 0, inertia 0, all labels different 1')
merges = [ss(blobs[0] + blobs[1]) + ss(blobs[2]), ss(blobs[0] + blobs[2]) + ss(blobs[1]), ss(blobs[1] + blobs[2]) + ss(blobs[0])]
best = min(range(3), key=lambda i: merges[i])
assert best == 0
out.append('k = 2: cluster sizes 20 and 40')
pv('k = 2 inertia', merges[best])
out.append('duplicate points, k = 3: err 0, inertia 0')
out.append('k > n: 8, k = 0: 8, null data: 8, null generator: 8, n = 0: 8, dim = 0: 8')
out.append('NaN in the data: 6 (ERR_ARG = 8, ERR_NOT_FINITE = 6)')

# ---- PCA
mrows = 25
rows = []
for _ in range(mrows):
    t = (lcg() % 400 - 200) / 16.0
    a = t + (lcg() % 64 - 32) / 32.0
    b = 0.5 * t + (lcg() % 64 - 32) / 16.0 + 3.0
    c = (lcg() % 64 - 32) / 8.0 - 0.25 * t
    rows.append([a, b, c])
cols = [[r[j] for r in rows] for j in range(3)]
means3 = [emean(cl) for cl in cols]
def cov_matrix(cols_):
    mm = [emean(cl) for cl in cols_]
    return [[sum((F(a) - mm[i]) * (F(b) - mm[j]) for a, b in zip(cols_[i], cols_[j])) / (mrows - 1) for j in range(3)] for i in range(3)]
def pca(cols_):
    cov = cov_matrix(cols_)
    vals, vecs = jacobi([[fdec(v) for v in row] for row in cov])
    order = list(range(3))[::-1]
    comps = []
    for i in order:
        v = [vecs[r][i] for r in range(3)]
        big = max(range(3), key=lambda j: abs(v[j]))
        if v[big] < 0: v = [-t for t in v]
        comps.append(v)
    return [vals[i] for i in order], comps
vals, comps = pca(cols)
total = sum(vals)
out.append('pca: ok 1, err 0, n 25, dim 3, k 3')
dump('mean', means3)
dump('variance', vals)
dump('ratio', [v / total for v in vals])
out.append('components 3 x 3: ' + ' '.join(g9(comps[i][j]) for i in range(3) for j in range(3)))
scores = [[sum((D(F(rows[r][j]).numerator) / D(F(rows[r][j]).denominator) - fdec(means3[j])) * comps[c][j] for j in range(3)) for c in range(3)] for r in range(2)]
out.append('scores 25 x 3, first two rows: ' + ' '.join(g9(scores[r][c]) for r in range(2) for c in range(3)))
out += ['inverse transform reproduces the data (1e-10): 1', 'scores have mean 0: 1, variance equals the explained variance (1e-9): 1',
        'two components: k 2, reconstruction loss equals (n - 1) times the dropped variance (1e-9): 1', 'scores of two components: 25 x 2']
# standardized: correlation matrix eigenvalues
sds = [(sum(((F(a) - emean(cl)) ** 2 for a in cl), F(0)) / (mrows - 1)) for cl in cols]
corr = [[fdec(cov_matrix(cols)[i][j]) / (fdec(sds[i]).sqrt() * fdec(sds[j]).sqrt()) for j in range(3)] for i in range(3)]
cv, _ = jacobi(corr)
dump('standardized: variance', sorted(cv, reverse=True))
out += ['standardized variances add up to 3 (the number of variables): 1', 'one observation: err 1 (ERR_DIM = 1), NaN: err 6, null: err 8',
        'transform of a matrix with a different number of columns: err 1', 'after dispose: ok 0', 'memory leaked: 0']
sys.stdout.write('\n'.join(out) + '\n')
