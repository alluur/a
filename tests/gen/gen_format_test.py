#!/usr/bin/env python3
"""Generates tests/t326_format_python.a and its expected output from Python's % operator.

Python's float formatting is correctly rounded (David Gay's algorithm), so every line of the expected output is a reference
for the exact algorithm of vformat in lib/std.a. The A test calls format() with the same format text and the bits of the
same double (the A language passes a double as its 64 bit pattern through ... ), prints the result and a '|'.

Usage:  tests/gen/gen_format_test.py                     (from the repository root: rewrites t326_format_python.a / .out)
        tests/gen/gen_format_test.py --stress N SEED PREFIX    (N random cases into PREFIX.a / PREFIX.out: for bug hunting)
"""
import math, os, random, struct, sys

def bits_of(x):
    return struct.unpack('<q', struct.pack('<d', x))[0]

def from_bits(b):
    return struct.unpack('<d', struct.pack('<Q', b & 0xFFFFFFFFFFFFFFFF))[0]

def hexlit(b):
    # an A integer literal for a signed 64 bit pattern
    return hex(b & 0xFFFFFFFFFFFFFFFF)

SPECIAL = [
    0.0, -0.0, 1.0, -1.0, 0.5, -0.5, 1.5, 2.5, 3.5, 0.125, 0.375, 0.1, 0.2, 0.3, 1 / 3, 2 / 3, 10 / 3, 1e22, 1e23, 1e15, 1e16, 1e17,
    123456789.123456789, 9.999999e22, 0.000123456, 1e-5, 1e-4, 99999.5, 999999.5, 0.9999995, 9.5, 99.5, 0.05, 0.95, 0.995,
    1e300, 1e-300, 1.7976931348623157e308, 2.2250738585072014e-308, 2.225073858507201e-308, 5e-324, 1e-310, 4.9406564584124654e-324,
    2.0 ** 52, 2.0 ** 53, 2.0 ** 53 + 2, 2.0 ** 63, 2.0 ** 64, 2.0 ** 100, 2.0 ** -1074, 2.0 ** -1022, 2.0 ** -10, 3.141592653589793,
    2.718281828459045, 1234567.0, 12345678.0, 0.000001, 0.0000001, 100.0, 1000000.0, 1e6 - 0.5, 5e-5, 0.00005, 4.35, 2.675, 1.005,
    float('inf'), float('-inf'), float('nan'),
]

# float formats: flags, width, precision, conversion
def float_formats(rng, n):
    out = []
    convs = 'eEfFgGvv'
    for _ in range(n):
        flags = ''.join(rng.sample('-+ 0#', rng.choice([0, 0, 1, 1, 2, 3])))
        width = rng.choice(['', '', '', '5', '10', '12', '20', '30', '40'])
        prec = rng.choice(['', '', '.0', '.1', '.2', '.3', '.6', '.10', '.15', '.17', '.20', '.30', '.50', '.100'])
        out.append('%' + flags + width + prec + rng.choice(convs))
    return out

BASIC = ['%v', '%+v', '%12v', '%-12v|', '%020v', '%f', '%e', '%g', '%E', '%G', '%F', '%.0f', '%.1f', '%.2f', '%.3e', '%.10g', '%.17g', '%.0e', '%#.0f', '%#g', '%#.3g', '%+f',
         '% e', '%010.3f', '%-12.4e|', '%12.4G', '%.3g', '%.1g', '%g', '%.20f', '%.40e']

INT_FORMATS = ['%d', '%i', '%5d', '%-5d|', '%05d', '%+d', '% d', '%.5d', '%8.5d', '%-8.5d|', '%+.3d', '%x', '%X', '%#x', '%#X', '%08x',
               '%#010x', '%o', '%#o', '%u', '%10u', '%-10u|', '%.0d', '%5.0d', '%#.0o', '%ld', '%lld', '%zd', '%lu', '%hd', '%hhd']

INT_VALUES = [0, 1, -1, 7, 8, 9, 10, 15, 16, 255, 256, 1000, -1000, 12345, -12345, 65535, 65536, 2147483647, -2147483648, 4294967295,
              4294967296, 1 << 40, (1 << 62), (1 << 63) - 1, -(1 << 63)]

def c_ints(cases):
    """The expected text of integer cases: glibc's printf (gcc is only needed to generate the test, not to run it). Python's % differs from
    C for  %#x  of 0,  %#o  and  %.0d  of 0, and prints negative numbers with %x / %o / %u with a sign; the A formatter follows C with
    64 bit values, so a conversion without a length gets  ll."""
    import subprocess, tempfile
    src = ['#include <stdio.h>', 'int main() {']
    for fmt, v in cases:
        f = fmt.rstrip('|')
        has_len = any(c in f for c in 'hlzjt')
        if not has_len:
            f = f[:-1] + 'll' + f[-1]
        if f[-1] in 'di' and 'hh' not in f and 'h' not in f and 'l' not in f and 'z' not in f:
            f = f[:-1] + 'll' + f[-1]
        arg = '(long long)%dLL' % v if v != -(1 << 63) else '(long long)(-9223372036854775807LL - 1)'
        if f[-1] in 'uxXo':
            arg = '(unsigned long long)' + arg
        elif 'h' in f:
            arg = '(int)' + arg
        src.append('    printf("%s%s\\n", %s);' % (f.replace('"', '\\"'), '|' if fmt.endswith('|') else '', arg))
    src.append('    return 0;\n}')
    with tempfile.TemporaryDirectory() as d:
        open(d + '/i.c', 'w').write('\n'.join(src).replace('\\\\n', '\\n'))
        r = subprocess.run(['gcc', '-w', '-O0', d + '/i.c', '-o', d + '/i'], capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit('gcc failed: ' + r.stderr[:500])
        out = subprocess.run([d + '/i'], capture_output=True, text=True).stdout
    return out.split('\n')[:len(cases)]

def py_v(fmt, x):
    """%v: the shortest text that reads back (Python's repr, without a forced .0), with the usual sign, width and flags."""
    base = fmt.rstrip('|')
    left = False; zero = False; plus = False; space = False
    i = 1
    while base[i] in '-+ 0#':
        c = base[i]
        left = left or c == '-'; zero = zero or c == '0'; plus = plus or c == '+'; space = space or c == ' '
        i += 1
    j = i
    while base[j].isdigit():
        j += 1
    width = int(base[i:j]) if j > i else 0
    r = repr(x)
    neg = r.startswith('-')
    body = r.lstrip('-')
    if math.isnan(x):
        neg = False
        body = 'nan'
    if body.endswith('.0'):
        body = body[:-2]
    sign = '-' if neg else '+' if plus else ' ' if space else ''
    special = math.isinf(x) or math.isnan(x)
    pad = max(0, width - len(sign) - len(body))
    if left:
        text = sign + body + ' ' * pad
    elif zero and not special:
        text = sign + '0' * pad + body
    else:
        text = ' ' * pad + sign + body
    return text + ('|' if fmt.endswith('|') else '')

def py_float(fmt, x):
    if fmt.rstrip('|').endswith('v'):
        return py_v(fmt, x)
    if math.isinf(x) or math.isnan(x):
        # C pads inf and nan with spaces even when the 0 flag is given; Python pads them with zeros. The A formatter follows C,
        # so the flag is taken out of the reference format.
        i = 1
        while i < len(fmt) and fmt[i] in '-+ 0#':
            i += 1
        fmt = '%' + fmt[1:i].replace('0', '') + fmt[i:]
    return fmt.rstrip('|') % x + ('|' if fmt.endswith('|') else '')

def build(cases_f, cases_i, cases_star):
    lines = []
    exp = []
    for fmt, b in cases_f:
        x = from_bits(b)
        lines.append('    chk("%s", %s);' % (fmt.replace('%', '%%') if False else fmt, hexlit(b)))
        exp.append(py_float(fmt, x) if not math.isnan(x) else py_float(fmt, float('nan')))
    ints = c_ints(cases_i) if cases_i else []
    for (fmt, v), text in zip(cases_i, ints):
        lines.append('    chki("%s", %d);' % (fmt, v) if v > -(1 << 63) else '    chki("%s", -9223372036854775807 - 1);' % fmt)
        exp.append(text)
    for fmt, w, p, b in cases_star:
        x = from_bits(b)
        lines.append('    chks("%s", %d, %d, %s);' % (fmt, w, p, hexlit(b)))
        exp.append(fmt.rstrip('|') % (w, p, x) + ('|' if fmt.endswith('|') else ''))
    return lines, exp

HEADER = '''// Generated by tests/gen/gen_format_test.py from Python's % operator. Do not edit.
// Every line is  format(fmt, value)  of lib/std.a compared (by the expected output) with  fmt %% value  in Python.
// A double goes through format(...) as its 64 bit pattern.
void chk(char* fmt, int bits) {
    char b[2300];
    format(&b[0], 2300, fmt, bits);
    printf("%s\\n", &b[0]);
}
void chki(char* fmt, int v) {
    char b[200];
    format(&b[0], 200, fmt, v);
    printf("%s\\n", &b[0]);
}
void chks(char* fmt, int w, int p, int bits) {
    char b[2300];
    format(&b[0], 2300, fmt, w, p, bits);
    printf("%s\\n", &b[0]);
}
int main() {
'''

def make_cases(rng, nrand):
    cf = []
    # every special value with the basic formats
    for x in SPECIAL:
        for fmt in BASIC:
            cf.append((fmt, bits_of(x)))
    # random bit patterns (normal numbers over the whole range), denormals, decimal looking values, exact ties
    for i in range(nrand):
        kind = i % 5
        if kind == 0:
            b = rng.getrandbits(63)
            if (b >> 52) == 0x7FF:
                b ^= 1 << 52
            x = from_bits(b | (rng.getrandbits(1) << 63))
        elif kind == 1:
            x = from_bits(rng.getrandbits(52) | (rng.getrandbits(1) << 63))          # denormals
        elif kind == 2:
            if i % 10 == 2:
                # a power of two or its neighbour: the interval of the numbers that read back as it is not symmetric there
                b = bits_of(2.0 ** rng.randint(-1074, 1023))
                x = from_bits(b + rng.choice([-1, 0, 0, 1]))
            else:
                x = round(rng.uniform(-1000, 1000), rng.randint(0, 8))
        elif kind == 3:
            x = rng.randint(-10 ** 6, 10 ** 6) / 2 ** rng.randint(0, 12)               # exact binary fractions: ties
        else:
            x = rng.uniform(-1, 1) * 10.0 ** rng.randint(-30, 30)
        cf.append((rng.choice(float_formats(rng, 40)), bits_of(x)))
    return cf

def main():
    args = sys.argv[1:]
    stress = None
    if args and args[0] == '--stress':
        stress = (int(args[1]), int(args[2]), args[3])
    rng = random.Random(326 if stress is None else stress[1])
    if stress is None:
        cf = make_cases(rng, 400)
        ci = [(f, v) for f in INT_FORMATS for v in INT_VALUES if not (f.endswith('hd') and False)]
        star = []
        for x in [3.14159, -2.5, 1e10, 0.1, 1234.5678]:
            for w, p in [(10, 2), (-10, 2), (8, 0), (0, 5), (-6, 3), (20, 10)]:
                star.append(('%*.*f', w, p, bits_of(x)))
                star.append(('%*.*e', w, p, bits_of(x)))
                star.append(('%-*.*g|', w, p, bits_of(x)))
        out_a = os.path.join(os.path.dirname(__file__), '..', 't326_format_python.a')
        out_o = os.path.join(os.path.dirname(__file__), '..', 't326_format_python.out')
    else:
        cf = make_cases(rng, stress[0])
        ci = []
        star = []
        out_a = stress[2] + '.a'
        out_o = stress[2] + '.out'
    lines, exp = build(cf, ci, star)
    with open(out_a, 'w') as f:
        f.write(HEADER)
        f.write('\n'.join(l for l in lines if l))
        f.write('\n    return 0;\n}\n')
    with open(out_o, 'w') as f:
        f.write('\n'.join(exp) + '\n')
    print('wrote %d cases' % len(exp))

main()
