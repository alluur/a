"""Expected output of tests/t455_optim_minimize.a: the minimizers are known in closed form (parabola, quartic x^4 - 3x^3 + 2 at 9/4, cosh(x) - 2x at asinh 2, Booth (1, 3),
Beale (3, 1/2), Rosenbrock (1, 1), shifted sphere) or computed by Newton's method on the gradient in 60 digit decimals (Himmelblau); statuses are the documented behaviour."""
import sys
from decimal import Decimal as D, getcontext
getcontext().prec = 60
g6 = lambda v: '%.6g' % float(v)
g5 = lambda v: '%.5g' % float(v)

def himmel_min(x, y):
    x = D(x); y = D(y)
    for _ in range(40):
        a = x * x + y - 11; b = x + y * y - 7
        fx = 4 * x * a + 2 * b; fy = 2 * a + 4 * y * b
        fxx = 4 * a + 8 * x * x + 2; fxy = 4 * x + 4 * y; fyy = 2 + 4 * b + 8 * y * y
        det = fxx * fyy - fxy * fxy
        x, y = x - (fyy * fx - fxy * fy) / det, y - (fxx * fy - fxy * fx) / det
    return x, y
asinh2 = (D(2) + D(5).sqrt()).ln()
out = []
f2 = lambda x: x ** 4 - 3 * x ** 3 + 2
for name in ('golden', 'brentMin'):
    out.append('%s (x - 1.5)^2 + 2: status 0 x 1.5 f 2' % name)
    out.append('%s x^4 - 3x^3 + 2: status 0 x 2.25 f %s' % (name, g6(f2(D('2.25')))))
    out.append('%s cosh(x) - 2x: status 0 x %s f %s' % (name, g6(asinh2), g6(D(5).sqrt() - 2 * asinh2)))
    out.append('%s |x - 2| + 1 (not smooth): status 0 x 2 f 1' % name)
out = out[:0] + [out[0], out[4], out[1], out[5], out[2], out[6], out[3], out[7]]
out += ['brentMin (x - 1)^4 (a flat minimum): status 0, within 1e-3 of 1: 1', 'golden with the end points swapped: status 0 x 1.5 f 2',
        'brentMin 3 (x + 2.25)^2 with a context: status 0 x -2.25 f 0', 'a parabola needs few evaluations (at most 12): 1 (calls 6, evals 6)',
        'golden iterations between 45 and 55: 1, evaluations equal iterations + 2: 1',
        'minimum outside the interval (the end point wins): status 0, x within 1e-6 of 2: 1',
        'bracketMin of (x - 3)^2 from 0, 1: status 0, lo < mid < hi 1, the minimum is inside 1, f(mid) is the smallest of the three 1', 'brentMin inside it: status 0 x 3 f 0',
        'bracketMin of a function without a minimum (-x): status 2 (ERR_BRACKET = 2)', 'function returning NaN: golden 4, brentMin 4',
        'too few iterations: golden 3, brentMin 3 (ERR_NO_CONVERGE = 3)', 'tolerance 0: golden 1, brentMin 1; NaN end point: 1 (ERR_ARG = 1)',
        'Nelder-Mead Rosenbrock: status 0 x 1 1 f below 1e-8 1', '  evaluations below 600: 1',
        'Nelder-Mead shifted sphere in 5 dimensions: status 0 x 0 1 2 3 4 f below 1e-8 1']
for label, start in (('(3, 1.5)', (3, 1.5)), ('(-3, 3)', (-3, 3)), ('(-3.5, -3)', (-3.5, -3)), ('(3.5, -1.5)', (3.5, -1.5))):
    x, y = himmel_min(*start)
    out.append('Himmelblau from %s: status 0 x %s %s f below 1e-8 1' % (label, g5(x), g5(y)))
out += ['Booth from (0, 0) with the default simplex: status 0 x 1 3 f below 1e-8 1', 'Beale from (1, 1): status 0 x 3 0.5 f below 1e-8 1',
        'with a context: status 0, x 1.5, y -1.5', '  calls equal evals 1', 'n = 0: status 1 (ERR_ARG = 1), 30 evaluations: status 3 (ERR_NO_CONVERGE = 3)',
        'a NaN value inside the search: status 4 (ERR_NAN = 4)', 'zero start with the default simplex (0.00025): status 0',
        'BFGS Rosenbrock, analytic gradient: status 0 x 1 1 f below 1e-8 1', '  iterations below 60: 1, gradient norm below 1e-8: 1',
        'BFGS Rosenbrock, numerical gradient: status 0 x 1 1 f below 1e-8 1', 'BFGS shifted sphere: status 0 x 0 1 2 3 4 f below 1e-8 1',
        '  a quadratic needs few iterations (at most 8): 1', 'BFGS x^2 + 10000 y^2: status 0 x 0 0 f below 1e-8 1']
x, y = himmel_min(3, 2)
out.append('BFGS Himmelblau from (0, 0): status 0 x %s %s f below 1e-8 1' % (g5(x), g5(y)))
out += ['BFGS Beale from (1, 1): status 0 x 3 0.5 f below 1e-8 1', 'a function without a minimum (-x): status 3 (not converged: 1)',
        'a NaN value at the start: status 4 (ERR_NAN = 4)', 'a function that is NaN far away (it never gets there): status 0',
        '2 iterations only: status 3 (ERR_NO_CONVERGE = 3)', 'start at the minimum: status 0, iterations 0', 'null x: 1, n = 0: 1, gtol 0: 1',
        'with a context and numerical gradients: status 0, x 2, y -2', '  calls equal evals 1',
        'gradient descent, shifted sphere: status 0 x 0 1 2 f below 1e-8 1', 'gradient descent on Rosenbrock (slow in the valley): status 0, within 0.01 of (1, 1): 1',
        'gradient descent, x^2 + 10000 y^2 (a narrow valley, condition number 10000): status 3 (not converged within 10000 iterations: 1), f still above 1e-8: 1',
        'gradient descent with numerical gradients, Booth: status 0 x 1 3 f below 1e-8 1', '3 iterations only: status 3 (ERR_NO_CONVERGE = 3)',
        'negative step: status 1 (ERR_ARG = 1), null x: status 1', 'memory leaked: 0']
sys.stdout.write('\n'.join(out) + '\n')
