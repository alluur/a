"""Expected output of tests/t457_optim_ode.a: RK4 on the linear test equations is an exact polynomial in the step (fractions: the step 0.2 or 0.01 as the exact binary double that
the library uses); the adaptive solutions are compared with the closed forms (e^-2, cos / sin, the logistic and the stiff linear equation) in 60 digit decimals;
the other lines are the documented behaviour."""
import sys
sys.path.insert(0, '.')
from fractions import Fraction as F
from decimal import Decimal as D, getcontext
import refspecial as R
getcontext().prec = 60
g12 = lambda v: '%.12g' % float(v)
g9 = lambda v: '%.9g' % float(v)
g7 = lambda v: '%.7g' % float(v)
out = []
def rk4_decay(steps, t1=1.0):
    h = F((t1 - 0.0) / steps)          # the double (t1 - t0) / steps
    z = -h * (-1)                      # h * lambda with lambda = -1 ... y' = -y: k1 = -y -> factor 1 - h + h^2/2 - h^3/6 + h^4/24
    fac = 1 - h + h * h / 2 - h ** 3 / 6 + h ** 4 / 24
    return fac ** steps
for steps in (10, 20, 40):
    out.append("rk4 y' = -y, %d steps: y(1) = %s" % (steps, g12(rk4_decay(steps))))
out.append('RK4 is of order 4: error ratios between 15 and 17: 1 1')
h = F(2.0 / 10)
c = 1 - h * h / 2 + h ** 4 / 24; s = h - h ** 3 / 6
def mpow(n):
    M = [[F(1), F(0)], [F(0), F(1)]]
    step = [[c, s], [-s, c]]
    for _ in range(n):
        M = [[sum(M[i][k] * step[k][j] for k in range(2)) for j in range(2)] for i in range(2)]
    return M
M10 = mpow(10)
out.append('rk4 oscillator, 10 steps to t = 2: (%s, %s)' % (g12(M10[0][0]), g12(M10[1][0])))
M5 = mpow(5)
out.append('trajectory rows 0, 5 and 10: (1, 0) (%s, %s) (%s, %s)' % (g9(M5[0][0]), g9(M5[1][0]), g9(M10[0][0]), g9(M10[1][0])))
out.append('the last trajectory row is the result: 1, the start is kept: 1')
hb = F(-1.0 / 100)
facb = 1 + hb + hb * hb / 2 + hb ** 3 / 6 + hb ** 4 / 24      # y' = -y with step -0.01: k = -y; factor 1 - hb + ... with hb < 0
facb = 1 - hb + hb * hb / 2 - hb ** 3 / 6 + hb ** 4 / 24
out.append('rk4 backwards to t = -1: %s (e = 2.71828183)' % g9(facb ** 100))
out.append('rk4 with the same array for input and output: %s' % g12(rk4_decay(40)))
e2 = (-D(2)).exp()
out.append("rk45 y' = -y to t = 2: status 0, t = 2")
out.append('  y(2) = %s' % g7(e2))
out.append('  steps below 60: 1, rejected steps below 10: 1, function evaluations = 6 per step + 2 at the start (+ 6 per rejected step): 1')
out.append('  the error is within a few times the tolerance: 1')
out.append('after dispose: ok 0, step status 1')
out.append('rk45 oscillator at t = 10: (%s, %s)' % (g7(R.cos(D(10))), g7(-R.sin(D(10)))))
out.append('  energy conserved to 1e-8: 1')
out.append('rk45 logistic at t = 10: %s' % g7(1 / (1 + 9 * (-D(10)).exp())))
yst = (2500 * R.cos(D(3)) + 50 * R.sin(D(3))) / 2501 - D(2500) / 2501 * (-D(150)).exp()
out.append("rk45 on y' = -50 (y - cos t) (stiff, but solvable) at t = 3: status 0, y = %s" % g7(yst))
out.append('  steps below 800: 1')
out.append('rk45 backwards to t = -2: %s (e^2 = 7.3890561)' % g7(D(2).exp()))
out.append('solveAt: status 0, t = 3')
for t in ('0.5', '1', '2', '3'):
    out.append('  t = %s: (%s, %s)' % (t, g7(R.cos(D(t))), g7(-R.sin(D(t)))))
out.append("y' = cos t: y(1.5) = %s (sin 1.5 = 0.9974950)" % g7(R.sin(D('1.5'))))
out.append("y' = -2.5 y, y(0) = 3 at t = 1: %s, calls equal nfev 1" % g7(3 * (-D('2.5')).exp()))
out.append('with an initial step of 0.001: y(2) = %s, within 1e-8: 1' % g7(e2))
out += ['single steps: time increases every step 1, ends exactly at 1: 1, step() at the end does nothing: 0', 'a loose tolerance uses fewer steps than a tight one: 1',
        'Lotka-Volterra over 20 time units: the conserved quantity drifts by less than 1e-7: 1 (steps 1)', 'Lorenz to t = 1 agrees with RK4 with 20000 steps within 1e-8: 1',
        "y' = y^2 from 1 blows up at t = 1: status 3 (not OK: 1), the time reached is below 1.0000001: 1", 'right hand side returning NaN after t = 0.5: status 4 (ERR_NAN = 4)',
        'maxSteps 5: status 3 (ERR_NO_CONVERGE = 3), steps 5', 'invalid arguments: n = 0 1, null y0 1, rtol 0 1, atol < 0 1, NaN time 1, null function 1, NaN state 4, negative step 1',
        '  (ERR_ARG = 1, ERR_NAN = 4)', 'tEnd = NaN: 1; solveTo the current time: 0; solveAt with null: 1, with count 0: 1',
        'rk4 invalid: n = 0 1, steps 0 1, null 1, NaN time 1 (ERR_ARG = 1)', 'rk4 on a blow-up reports a non finite result: 4 (ERR_NAN = 4)', 'memory leaked: 0']
sys.stdout.write('\n'.join(out) + '\n')
