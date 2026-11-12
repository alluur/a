"""Expected output of tests/t460_optim_fft.a: DFT values from the definition in 60 digit decimals, exact integer convolutions (Python integers), NumPy's fftfreq and
window formulas, sin / cos of rational turns in decimals; the property checks (round trips, Parseval ...) are verdict lines, and the random numbers replay the test's generator."""
import math, sys
sys.path.insert(0, '.')
from decimal import Decimal as D, getcontext
import refspecial as R
getcontext().prec = 60
seed = 987654321
def lcg():
    global seed
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    return seed
g9 = lambda v: '%.9g' % float(v)
clean = lambda v: 0.0 if abs(float(v)) < 1e-9 else float(v)
out = []
for n in (8, 5, 7, 12):
    out.append('fft of 1 .. %d: status 0' % n)
    for k in range(n):
        re = sum(D(j + 1) * R.cos(2 * R.PI * ((j * k) % n) / n) for j in range(n))
        im = -sum(D(j + 1) * R.sin(2 * R.PI * ((j * k) % n) / n) for j in range(n))
        out.append('  X[%d] = (%s, %s)' % (k, g9(clean(re)), g9(clean(im))))
out.append('20 lengths from 1 to 100 against the definition (1e-11): 0 wrong; round trips (1e-12): 0 wrong')
for n in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 15, 16, 17, 20, 31, 64, 100):
    for _ in range(2 * n): lcg()
for n in (1024, 4096, 1009, 3000, 2053):
    for _ in range(n): lcg()
    out.append('n = %d: round trip error below 1e-12: 1, Parseval (sum |X|^2 = n sum |x|^2) within 1e-10: 1, imaginary parts back to 0 (1e-12): 1' % n)
out += ['an impulse transforms to a constant: 1', 'a constant transforms to an impulse of height n: 1', 'a cosine with 3 periods has two peaks of height n / 2 at bins 3 and 9: 1']
for _ in range(12): lcg()
out += ['shift theorem: 1', 'real input: X[n - k] = conj X[k]: 1, imaginary part of X[0] and X[n / 2] vanish: 1']
for _ in range(20): lcg()
out.append('linearity (length 10): 1')
for n in (16, 15, 10):
    for _ in range(n): lcg()
    out.append('rfft n = %d: status 0, equals the first n / 2 + 1 bins of fft (1e-12): 1, irfft restores the input (1e-12): 1' % n)
na, nb = 30, 40
a = [lcg() % 21 - 10 for _ in range(na)]
b = [lcg() % 21 - 10 for _ in range(nb)]
conv = [0] * (na + nb - 1)
for i in range(na):
    for j in range(nb): conv[i + j] += a[i] * b[j]
out += ['convolve (small, direct): 0', 'convolveFft: 0', 'out[0] %d, out[1] %d, out[68] %d, weighted checksum %d' % (conv[0], conv[1], conv[68], sum(v * (k + 1) for k, v in enumerate(conv))),
        'the FFT result equals the direct sums to 1e-10: 1 (rounded they are identical: 1)']
n1, n2 = 3000, 2500
x = [lcg() % 21 - 10 for _ in range(n1)]
y = [lcg() % 21 - 10 for _ in range(n2)]
z2999 = sum(x[i] * y[2999 - i] for i in range(n1) if 0 <= 2999 - i < n2)
out += ['convolve of 3000 and 2500 values: 0', 'six entries equal the direct sums (1e-7): 1, z[2999] = %d' % z2999, 'the sum of the convolution is the product of the sums: 1', 'crossCorrelate: 0']
c1 = [1.0, 2.0, 3.0, 4.0]; c2 = [0.0, 1.0, 0.5]
cc = [sum(c1[i + k - 2] * c2[i] for i in range(3) if 0 <= i + k - 2 < 4) for k in range(6)]
out.append('  values: ' + ' '.join(g9(v) for v in cc))
out += ['convolution with a single value: 0, 25', 'invalid: null 1, na = 0 1, nb = -1 1', 'fftFrequencies(8, 0.5): 0']
fq = [(k if k < 4 else k - 8) / (8 * 0.5) for k in range(8)]
out.append('   ' + ' '.join(g9(v) for v in fq))
out.append('fftFrequencies(5, 1): ' + ' '.join(g9((k if k < 3 else k - 5) / 5.0) for k in range(5)))
out.append('invalid: n = 0 1, d = 0 1, null 1')
N = 9
for name, f in (('rectangular', lambda k: 1.0), ('hann', lambda k: 0.5 - 0.5 * math.cos(2 * math.pi * k / (N - 1))),
                ('hamming', lambda k: 0.54 - 0.46 * math.cos(2 * math.pi * k / (N - 1))),
                ('blackman', lambda k: 0.42 - 0.5 * math.cos(2 * math.pi * k / (N - 1)) + 0.08 * math.cos(4 * math.pi * k / (N - 1)))):
    out.append('%s window of 9: %s' % (name, ' '.join(g9(clean(f(k))) for k in range(N))))
out.append('window of 1 point: 1, hann of 2 points: 0 0, invalid kind 1, n = 0 1')
ks = [0, 1, 3, 5, 7, 11, 13, 17, 23, 31]; ns = [1, 12, 8, 7, 16, 9, 100, 33, 40, 64]
parts = []
for k, n in zip(ks, ns):
    ang = 2 * R.PI * k / n
    parts.append('(%s, %s)' % ('%.14g' % clean(R.sin(ang)), '%.14g' % clean(R.cos(ang))))
out.append('sincosTurns: ' + ' '.join(parts))
out += ['quarter turn: 1 0; half turn: 0 -1; negative and large k: same angle 1; 1000000 / 8 turns is 0: 1', 'n = 0 gives NaN: 1',
        'plan of 0, -5, 2^29 + 1 points: err 1 1 1 (ERR_ARG = 1)', 'a failed plan refuses to run: 1', 'null arrays: 1 1', 'fft with n = 0: 1, n = -3: 1, null: 1',
        'a disposed plan refuses to run: 1', 'a plan for one point: 0 0, value 7', 'a plan can be reused: every run gives bit for bit the same result: 1', 'memory leaked: 0']
sys.stdout.write('\n'.join(out) + '\n')
