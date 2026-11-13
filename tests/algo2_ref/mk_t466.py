#!/usr/bin/env python3
"""Generates tests/t466_numeric_hostile_calls.a: every public function and method of matrix, stats and optim called with hostile arguments (null pointers, null callbacks, zero and
negative counts, NaN, infinity, 1e308, one null among valid arguments, zeroed objects). The generated program checks two things only, the two that need no expected values: nothing
crashes or hangs (a crash fails the test run, the runner kills a hang) and nothing leaks (asys.memInUse() is the same after every call). The source is built from the signatures in lib/*.a,
so run this script again after adding public functions:   python3 tests/algo2_ref/mk_t466.py > tests/t466_numeric_hostile_calls.a
Functions with arguments this generator cannot invent (struct arguments ...) are listed in the comment at the top of the generated file."""
import os, re, sys

root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
mods = ['matrix', 'stats', 'optim']
DISPOSE = {'Matrix', 'CsrMatrix', 'CMatrix', 'SparseVector', 'Regression', 'Histogram', 'KMeans'}
PRIMS = ('int', 'double', 'bool', 'char', 'void')

def split_params(params):
    ps = []
    cur = ''
    for ch in params:
        if ch == ',':
            ps.append(cur.strip()); cur = ''
        else:
            cur += ch
    if cur.strip(): ps.append(cur.strip())
    out = []
    for p in ps:
        p = p.split('=')[0].strip()
        m = re.match(r'(.+?)\s*(\w+)$', p)
        out.append((m.group(1).strip().replace(' ', ''), m.group(2)))
    return out

funcs = []      # (module, ret, name, params)
classes = {}    # (module, cls) -> {'methods': [(ret, name, params)], 'ctors': [params]}
for m in mods:
    cur = None
    for line in open('%s/lib/%s.a' % (root, m)):
        line = line.rstrip('\n')
        mc = re.match(r'^public class (\w+)', line)
        if mc:
            cur = (m, mc.group(1)); classes[cur] = {'methods': [], 'ctors': []}; continue
        if line.startswith('}'):
            cur = None; continue
        if cur and line.startswith('    public ') and '(' in line and ' class ' not in line:
            mm = re.match(r'^    public\s+(?:virtual\s+)?(?:([A-Za-z_][\w\.\*]*)\s+)?(\w+)\((.*?)\)\s*(\{.*)?$', line)
            if not mm: continue
            ret, name, params, rest = mm.groups()
            if rest is None and not line.endswith('{'): continue
            plist = split_params(params)
            if name == cur[1] and ret is None: classes[cur]['ctors'].append(plist)
            elif ret is not None and name not in ('dispose', 'show'): classes[cur]['methods'].append((ret, name, plist))
        elif cur is None and line.startswith('public ') and '(' in line and not re.match(r'public (class|const|struct|enum)', line):
            mt = re.match(r'^public\s+([A-Za-z_][\w\.\*]*)\s+(\w+)\((.*)\)\s*(\{.*)?$', line)
            if mt and mt.group(2) not in ('show',): funcs.append((m, mt.group(1), mt.group(2), split_params(mt.group(3))))

# ---- argument values per profile
CB = {'grad': 'cbGrad', 'rhs': 'cbRhs', 'fvec': 'cbVec'}
OBJECTIVE = {'nelderMead', 'bfgs', 'gradientDescent', 'gradientNum', 'hessianNum', 'bootstrapCI'}
def callback(fname, pname):
    if pname in CB: return CB[pname]
    if fname in OBJECTIVE: return 'cbN'
    if fname in ('jacobianNum', 'newtonSystem'): return 'cbVec'
    return 'cb1'

def arg(profile, fname, pt, pn):
    """profile: 1 nulls, 2 zeros, 3 NaN and negative, 4 NaN data with small counts, 5 infinity, 6 huge values, 7 valid values (one parameter is made null by the caller)"""
    if pt == 'func': return 'null' if profile == 1 else callback(fname, pn)
    if pt == 'double*': return {1: 'null', 2: 'buf0', 3: 'bufN', 4: 'bufN', 5: 'bufI', 6: 'bufH', 7: 'bufS'}[profile]
    if pt == 'int*': return 'null' if profile == 1 else 'ibuf'
    if pt == 'void*': return 'null'
    if pt == 'char*': return 'null' if profile == 1 else '"abc"'
    if pt in ('Matrix*', 'matrix.Matrix*'): return {1: 'null', 2: '&mZero', 3: '&mNan', 4: '&mNan', 5: '&mInf', 6: '&mHuge', 7: '&mA'}[profile]
    if pt in ('CsrMatrix*', 'matrix.CsrMatrix*'): return 'null' if profile == 1 else '&cZero'
    if pt in ('SparseVector*', 'CMatrix*', 'Welford*', 'matrix.SparseVector*'): return 'null' if profile == 1 else '&obj'
    if pt == 'rng.Rng*': return 'null' if profile == 1 else 'grng'
    if pt == 'int': return {1: '3', 2: '0', 3: '-1', 4: '3', 5: '4', 6: '3', 7: '3'}[profile]
    if pt == 'double': return {1: '1.0', 2: '0.0', 3: 'dnan', 4: '1.0', 5: 'dinf', 6: '1.0e308', 7: '1.0'}[profile]
    if pt == 'bool': return {1: 'false', 2: 'true', 3: 'false', 4: 'true', 5: 'false', 6: 'true', 7: 'true'}[profile]
    return None

def variants(plist, profiles):
    for p in profiles:
        if p == 7:
            for i, (pt, pn) in enumerate(plist):
                if '*' in pt or pt == 'func': yield (7, i)
        else:
            yield (p, -1)

def qualified(m, ret):
    if ret in PRIMS or '.' in ret or '*' in ret: return ret
    return m + '.' + ret

CTOR = {
    ('matrix', 'Matrix'): 'matrix.Matrix obj(3, 3);',
    ('matrix', 'LU'): 'matrix.LU obj(&mA);',
    ('matrix', 'Cholesky'): 'matrix.Cholesky obj(&mA);',
    ('matrix', 'QR'): 'matrix.QR obj(&mA);',
    ('matrix', 'SymEigen'): 'matrix.SymEigen obj(&mA, true);',
    ('matrix', 'SVD'): 'matrix.SVD obj(&mA);',
    ('matrix', 'SparseVector'): 'matrix.SparseVector obj(5); obj.put(1, 2.0); obj.put(3, -1.0);',
    ('matrix', 'CsrMatrix'): 'matrix.CsrMatrix obj = matrix.fromDense(&mA, 0.0);',
    ('matrix', 'CooBuilder'): 'matrix.CooBuilder obj(3, 3); obj.add(1, 1, 2.0);',
    ('matrix', 'CMatrix'): 'matrix.CMatrix obj(2, 2); obj.set(0, 0, 1.0, 1.0); obj.set(1, 1, 2.0, 0.0);',
    ('stats', 'Welford'): 'stats.Welford obj; obj.add(1.0); obj.add(4.0);',
    ('stats', 'Ema'): 'stats.Ema obj(0.3, false); obj.add(1.0);',
    ('stats', 'RollingStats'): 'stats.RollingStats obj(4); obj.add(1.0); obj.add(3.0);',
    ('stats', 'Histogram'): 'stats.Histogram obj(5, 0.0, 10.0); obj.add(3.0);',
    ('stats', 'Regression'): 'stats.Regression obj = stats.linearFit(ax, ay, 4);',
    ('stats', 'KMeans'): 'stats.KMeans obj = stats.kmeans(dataM.d, 6, 2, 2, grng, 20, 2);',
    ('stats', 'Pca'): 'stats.Pca obj(&dataM, 0, false);',
    ('optim', 'Rk45'): 'optim.Rk45 obj(cbRhs, null, 2, 0.0, y0, 1.0e-6, 1.0e-9, 0.0);',
    ('optim', 'Spline'): 'optim.Spline obj(ax, ay, 4, 0, 0.0, 0.0);',
    ('optim', 'Barycentric'): 'optim.Barycentric obj(ax, ay, 4);',
    ('optim', 'Chebyshev'): 'optim.Chebyshev obj(cb1, null, 0.0, 1.0, 8);',
    ('optim', 'FftPlan'): 'optim.FftPlan obj(8);',
}
HAS_DISPOSE = {('stats', 'Ema'), ('stats', 'Welford')}      # classes without dispose()

PRE = '''import cstdio;
import asys;
import matrix;
import stats;
import optim;
import rng;
import dmath;

int calls = 0;
int leaks = 0;
double sink = 0.0;

double cb1(double x, void* c) { return x * x - 2.0; }
double cbN(double* x, int n, void* c) { double s = 0.0; for (int i = 0; i < n && i < 4; i++) { s += x[i] * x[i]; } return s; }
void cbGrad(double* x, int n, double* g, void* c) { for (int i = 0; i < n && i < 4; i++) { g[i] = 2.0 * x[i]; } }
void cbRhs(double t, double* y, double* dy, int n, void* c) { for (int i = 0; i < n && i < 4; i++) { dy[i] = -y[i]; } }
void cbVec(double* x, int n, double* out, void* c) { for (int i = 0; i < n && i < 4; i++) { out[i] = x[i] * x[i] - 1.0; } }

void leak(char* what, int bytes) {
    leaks++;
    printf("LEAK %s: %d bytes\\n", what, bytes);
}

// every group builds the shared test data itself: the arrays have 32 entries so that a count of 3 or 4 stays inside
'''

SETUP = '''
double dnan;
double dinf;
double buf0[32];
double bufN[32];
double bufI[32];
double bufH[32];
double bufS[32];
int ibuf[32];
matrix.Matrix mZero;
matrix.Matrix mNan;
matrix.Matrix mInf;
matrix.Matrix mHuge;
matrix.Matrix mA;
matrix.Matrix dataM;
matrix.CsrMatrix csr;
matrix.CsrMatrix cZero;
rng.Rng* grng;
double ax[4] = {0.0, 1.0, 2.0, 3.0};
double ay[4] = {1.0, 3.0, 2.0, 5.0};
double y0[2] = {1.0, 0.5};

void init() {
    dnan = dmath.nan();
    dinf = dmath.INFINITY;
    for (int i = 0; i < 32; i++) { buf0[i] = 0.0; bufN[i] = dnan; bufI[i] = dinf; bufH[i] = 1.0e308; bufS[i] = (double) (i - (i / 5) * 5) + 1.0; ibuf[i] = 0; }
    mNan = matrix.zeros(2, 2);
    mNan.d[0] = dnan;
    mInf = matrix.zeros(2, 2);
    mInf.d[0] = dinf;
    mInf.d[3] = 1.0;
    mHuge = matrix.zeros(2, 2);
    for (int i = 0; i < 4; i++) { mHuge.d[i] = 1.0e308; }
    mA = matrix.zeros(3, 3);
    double av[9] = {4.0, 1.0, 0.0, 1.0, 3.0, 1.0, 0.0, 1.0, 2.0};
    for (int i = 0; i < 9; i++) { mA.d[i] = av[i]; }
    dataM = matrix.zeros(6, 2);
    double dv[12] = {1.0, 2.0, 2.0, 1.0, 3.0, 5.0, 4.0, 3.0, 5.0, 8.0, 6.0, 6.5};
    for (int i = 0; i < 12; i++) { dataM.d[i] = dv[i]; }
    matrix.CooBuilder cooB(3, 3);
    cooB.add(0, 0, 4.0);
    cooB.add(1, 1, 3.0);
    cooB.add(2, 2, 2.0);
    cooB.add(0, 1, 1.0);
    cooB.add(1, 0, 1.0);
    csr = cooB.build();
    cooB.dispose();
}

void teardown() {
    mNan.dispose();
    mInf.dispose();
    mHuge.dispose();
    mA.dispose();
    dataM.dispose();
    csr.dispose();
}
'''
TEARDOWN = ''

groups = []      # (title, [lines])

def block(label, stmts, retcls=None):
    body = ' '.join(stmts)
    if retcls in DISPOSE: body += ' r.dispose();'
    if os.environ.get('T466_SLOW'):      # development aid: report the calls that take more than 20 ms
        return ['    { int m0 = asys.memInUse(); int t0 = millis(); %s if (millis() - t0 > 20) { printf("SLOW %%d ms: %s\\n", millis() - t0); } if (asys.memInUse() != m0) { leak("%s", asys.memInUse() - m0); } calls++; }' % (body, label.replace('"', "'").replace('%', '%%'), label.replace('"', "'"))]
    return ['    { int m0 = asys.memInUse(); %s if (asys.memInUse() != m0) { leak("%s", asys.memInUse() - m0); } calls++; }' % (body, label.replace('"', "'"))]

# ---- free functions: one group per module
FREE_PROFILES = [1, 2, 3, 4, 5, 6, 7]
for m in mods:
    lines = []
    for (fm, ret, name, plist) in funcs:
        if fm != m: continue
        for (profile, nullIdx) in variants(plist, [q for q in FREE_PROFILES if not (m == 'stats' and q == 6)]):     # incGammaP(1e308, 1e308) etc. take 0.5 s (the series gives up after 10^6 terms): tested in t465
            args = []
            for k, (pt, pn) in enumerate(plist):
                a = arg(profile, name, pt, pn)
                if a is None: args = None; break
                if profile == 7 and k == nullIdx: a = 'null'
                args.append(a)
            if args is None: continue
            call = '%s.%s(%s)' % (m, name, ', '.join(args))
            base = ret.split('.')[-1]
            q = qualified(m, ret)
            if ret == 'void': stmts = [call + ';']
            else: stmts = ['%s r = %s;' % (q, call)]
            lines += block('%s (profile %d%s)' % (call, profile, '' if profile != 7 else ', argument %d null' % (nullIdx + 1)), stmts, base if ret != 'void' else None)
    groups.append(('free functions of ' + m, lines))

# ---- methods: constructed objects and zeroed objects
METH_PROFILES = [1, 3, 4, 7]
for (m, c), info in classes.items():
    if (m, c) not in CTOR: continue
    lines = []
    for plist in info['ctors']:
        for (profile, nullIdx) in variants(plist, [1, 2, 3, 4, 5, 7]):
            args = []
            for k, (pt, pn) in enumerate(plist):
                a = arg(profile, c, pt, pn)
                if a is None: args = None; break
                if profile == 7 and k == nullIdx: a = 'null'
                args.append(a)
            if args is None: continue
            decl = '%s.%s obj(%s);' % (m, c, ', '.join(args))
            stmts = [decl]
            if (m, c) not in HAS_DISPOSE: stmts.append('obj.dispose();')
            lines += block('constructor %s' % decl, stmts)
    for (ret, name, plist) in info['methods']:
        for zeroed in (False, True):
            for (profile, nullIdx) in variants(plist, METH_PROFILES):
                if zeroed and profile == 7 and nullIdx > 0: continue
                args = []
                for k, (pt, pn) in enumerate(plist):
                    a = arg(profile, name, pt, pn)
                    if a is None: args = None; break
                    if profile == 7 and k == nullIdx: a = 'null'
                    args.append(a)
                if args is None: continue
                decl = ('%s.%s obj;' % (m, c)) if zeroed else CTOR[(m, c)]
                call = 'obj.%s(%s)' % (name, ', '.join(args))
                q = qualified(m, ret)
                base = ret.split('.')[-1]
                stmts = [decl, (call + ';') if ret == 'void' else ('%s r = %s;' % (q, call))]
                if (m, c) not in HAS_DISPOSE: stmts.append('obj.dispose();')
                lines += block('%s%s: %s' % (('zeroed ' if zeroed else ''), '%s.%s' % (m, c), call), stmts, base if ret != 'void' else None)
    groups.append(('methods of %s.%s' % (m, c), lines))

# ---- assemble: every group is a function of its own (the compiler handles them better than one huge main)
out = []
out.append('// matrix, stats, optim: every public function and method called with hostile arguments (generated by tests/algo2_ref/mk_t466.py from the signatures in lib/*.a).')
out.append('// Checks: nothing crashes or hangs, and asys.memInUse() is the same after every call (no leak on any error path). The expected output has no numbers: "0 leaks".')
out.append(PRE)
out.append(SETUP)
for gi, (title, lines) in enumerate(groups):
    out.append('// ---- %s' % title)
    out.append('void group%d() {' % gi)
    out += lines
    out.append('}\n')
out.append('int main() {')
out.append('    rng.Xoshiro256 gen(1);')
out.append('    int base = asys.memInUse();')
out.append('    init();')
out.append('    grng = &gen;')
for gi in range(len(groups)): out.append('    group%d();' % gi)
out.append('    teardown();')
out.append('    printf("%d calls, %d leaks\\n", calls, leaks);')
out.append('    printf("memory leaked: %d\\n", asys.memInUse() - base);')
out.append('    if (sink == 12345.678) { printf("never\\n"); }')
out.append('    return 0;')
out.append('}')
print('\n'.join(out))
