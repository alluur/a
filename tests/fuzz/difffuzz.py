#!/usr/bin/env python3
"""Differential fuzzer: random programs are generated in A and in C, built with `ac` and
gcc, executed, and their outputs compared.

    tests/fuzz/difffuzz.py [count] [seed] [target]

target: linux (default) | linux-arm64 | windows | android | android-x64
"""
import random, subprocess, sys, os, tempfile, shutil

COUNT = int(sys.argv[1]) if len(sys.argv) > 1 else 100
SEED = int(sys.argv[2]) if len(sys.argv) > 2 else 1
TARGET = sys.argv[3] if len(sys.argv) > 3 else "linux"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AC = os.path.join(ROOT, "build", "ac")

RUN = []
if TARGET in ("linux-arm64", "android"):
    RUN = ["qemu-aarch64"]
elif TARGET == "windows":
    RUN = ["/usr/lib/wine/wine64"]
    os.environ.setdefault("WINEDEBUG", "-all")
    os.environ.setdefault("WINEPREFIX", "/tmp/wineprefix")


class Gen:
    def __init__(self, rng):
        self.r = rng
        self.ints = ["v%d" % i for i in range(6)]
        self.chars = ["c0", "c1"]
        self.bools = ["b0"]
        self.globs = ["g0", "g1"]
        self.nfuncs = rng.randint(1, 3)
        self.maxf = 0
        self.loopdepth = 0
        self.uid = 0

    # ---- expressions: return (a_text, c_text)
    def const(self):
        r = self.r
        k = r.random()
        if k < 0.6:
            v = r.randint(-20, 100)
        elif k < 0.85:
            v = r.randint(-100000, 100000)
        else:
            v = r.randint(-(1 << 40), 1 << 40)
        return ("(%d)" % v if v < 0 else str(v)), ("(%dL)" % v if v < 0 else "%dL" % v)

    def var(self):
        r = self.r
        k = r.random()
        if k < 0.55:
            n = r.choice(self.ints); return n, n
        if k < 0.7:
            n = r.choice(self.chars); return n, "((long)%s)" % n
        if k < 0.78:
            n = r.choice(self.bools); return n, "((long)%s)" % n
        if k < 0.9:
            n = r.choice(self.globs); return n, n
        i = self.expr(0)
        return "arr[(%s) & 7]" % i[0], "arr[(%s) & 7]" % i[1]

    def expr(self, depth):
        r = self.r
        if depth <= 0 or r.random() < 0.18:
            return self.const() if r.random() < 0.35 else self.var()
        k = r.random()
        a = self.expr(depth - 1)
        if k < 0.50:
            b = self.expr(depth - 1)
            op = r.choice(["+", "-", "*", "&", "|", "^"])
            return "(%s %s %s)" % (a[0], op, b[0]), "(%s %s %s)" % (a[1], op, b[1])
        if k < 0.58:
            b = self.expr(depth - 1)
            op = r.choice(["/", "%"])
            return ("(%s %s ((%s & 255) | 1))" % (a[0], op, b[0]),
                    "(%s %s ((%s & 255) | 1))" % (a[1], op, b[1]))
        if k < 0.66:
            b = self.expr(depth - 1)
            op = r.choice(["<<", ">>"])
            return ("(%s %s (%s & 31))" % (a[0], op, b[0]),
                    "(%s %s (%s & 31))" % (a[1], op, b[1]))
        if k < 0.78:
            b = self.expr(depth - 1)
            op = r.choice(["<", ">", "<=", ">=", "==", "!="])
            return "(%s %s %s)" % (a[0], op, b[0]), "((long)(%s %s %s))" % (a[1], op, b[1])
        if k < 0.86:
            b = self.expr(depth - 1)
            op = r.choice(["&&", "||"])
            return "(%s %s %s)" % (a[0], op, b[0]), "((long)(%s %s %s))" % (a[1], op, b[1])
        if k < 0.92:
            op = r.choice(["!", "~", "-"])
            return "(%s%s)" % (op, a[0]), "((long)(%s%s))" % (op, a[1])
        if k < 0.96 and self.maxf:
            b = self.expr(depth - 1)
            f = "f%d" % r.randrange(self.maxf)
            return "%s(%s, %s)" % (f, a[0], b[0]), "%s(%s, %s)" % (f, a[1], b[1])
        b = self.expr(depth - 1)
        c = self.expr(depth - 1)
        return ("(%s ? %s : %s)" % (a[0], b[0], c[0]), "(%s ? %s : %s)" % (a[1], b[1], c[1]))

    # ---- statements: return (a_text, c_text) lists of lines
    def lvalue(self):
        r = self.r
        k = r.random()
        if k < 0.55:
            n = r.choice(self.ints); return n, n
        if k < 0.7:
            n = r.choice(self.chars); return n, n
        if k < 0.78:
            n = r.choice(self.bools); return n, n
        if k < 0.88:
            n = r.choice(self.globs); return n, n
        i = self.expr(1)
        t = "arr[(%s) & 7]" % i[0]
        return t, "arr[(%s) & 7]" % i[1]

    def stmt(self, depth, ind):
        r = self.r
        pad = "    " * ind
        k = r.random()
        if depth <= 0 or k < 0.45:
            la, lc = self.lvalue()
            e = self.expr(3)
            kind = r.random()
            if kind < 0.45:
                return [pad + "%s = %s;" % (la, e[0])], [pad + "%s = %s;" % (lc, e[1])]
            if kind < 0.8:
                op = r.choice(["+=", "-=", "*=", "&=", "|=", "^="])
                if la.startswith("b"):
                    op = "="
                return [pad + "%s %s %s;" % (la, op, e[0])], [pad + "%s %s %s;" % (lc, op, e[1])]
            if la.startswith("b"):
                return [pad + "%s = %s;" % (la, e[0])], [pad + "%s = %s;" % (lc, e[1])]
            op = r.choice(["++", "--"])
            if r.random() < 0.5:
                return [pad + "%s%s;" % (la, op)], [pad + "%s%s;" % (lc, op)]
            return [pad + "%s%s;" % (op, la)], [pad + "%s%s;" % (op, lc)]
        if k < 0.62:
            c = self.expr(2)
            a1, c1 = self.block(depth - 1, ind + 1)
            if r.random() < 0.5:
                a2, c2 = self.block(depth - 1, ind + 1)
                return ([pad + "if (%s) {" % c[0]] + a1 + [pad + "} else {"] + a2 + [pad + "}"],
                        [pad + "if (%s) {" % c[1]] + c1 + [pad + "} else {"] + c2 + [pad + "}"])
            return ([pad + "if (%s) {" % c[0]] + a1 + [pad + "}"],
                    [pad + "if (%s) {" % c[1]] + c1 + [pad + "}"])
        if k < 0.80 and self.loopdepth < 2:
            self.loopdepth += 1
            self.uid += 1
            iv = "i%d" % self.uid
            n = r.randint(1, 6)
            a1, c1 = self.block(depth - 1, ind + 1)
            self.loopdepth -= 1
            return ([pad + "for (int %s = 0; %s < %d; %s++) {" % (iv, iv, n, iv)] + a1 + [pad + "}"],
                    [pad + "for (long %s = 0; %s < %d; %s++) {" % (iv, iv, n, iv)] + c1 + [pad + "}"])
        if k < 0.90 and self.loopdepth < 2:
            self.loopdepth += 1
            self.uid += 1
            wv = "w%d" % self.uid
            n = r.randint(1, 5)
            a1, c1 = self.block(depth - 1, ind + 1)
            self.loopdepth -= 1
            return ([pad + "int %s = 0;" % wv, pad + "while (%s < %d) {" % (wv, n)] + a1 + [pad + "    %s++;" % wv, pad + "}"],
                    [pad + "long %s = 0;" % wv, pad + "while (%s < %d) {" % (wv, n)] + c1 + [pad + "    %s++;" % wv, pad + "}"])
        # switch on a small value
        self.uid += 1
        e = self.expr(2)
        cases_a, cases_c = [], []
        for v in sorted(r.sample(range(0, 6), r.randint(1, 4))):
            sa, sc = self.stmt(0, ind + 2)
            brk = r.random() < 0.7
            cases_a += [pad + "    case %d:" % v] + sa + ([pad + "        break;"] if brk else [])
            cases_c += [pad + "    case %d:" % v] + sc + ([pad + "        break;"] if brk else [])
        da, dc = self.stmt(0, ind + 2)
        return ([pad + "switch ((%s) & 7) {" % e[0]] + cases_a + [pad + "    default:"] + da + [pad + "}"],
                [pad + "switch ((%s) & 7) {" % e[1]] + cases_c + [pad + "    default:"] + dc + [pad + "}"])

    def block(self, depth, ind):
        a, c = [], []
        for _ in range(self.r.randint(1, 3)):
            sa, sc = self.stmt(depth, ind)
            a += sa
            c += sc
        return a, c

    def program(self):
        r = self.r
        A = ["int g0 = %d;" % r.randint(-9, 9), "int g1 = %d;" % r.randint(-9, 9), "int arr[8];", ""]
        C = ["#include <stdio.h>", "#include <stdbool.h>",
             "long g0 = %s;" % A[0].split("=")[1].strip().rstrip(";"),
             "long g1 = %s;" % A[1].split("=")[1].strip().rstrip(";"), "long arr[8];", ""]
        for i in range(self.nfuncs):
            self.maxf = i
            e = self.expr(3)
            e = (e[0].replace("v", "p").replace("c0", "p").replace("c1", "q").replace("b0", "q").replace("arr[", "arr["),
                 e[1].replace("v", "p").replace("c0", "p").replace("c1", "q").replace("b0", "q"))
            A += ["int f%d(int p, int q) {" % i,
                  "    return %s;" % self.fix_func_expr(e[0], "a"), "}", ""]
            C += ["long f%d(long p, long q) {" % i,
                  "    return %s;" % self.fix_func_expr(e[1], "c"), "}", ""]
        self.maxf = self.nfuncs
        A += ["int main() {"]
        C += ["int main() {"]
        for i in range(6):
            v = r.randint(-50, 50)
            A.append("    int v%d = %d;" % (i, v))
            C.append("    long v%d = %d;" % (i, v))
        A += ["    char c0 = %d;" % r.randint(0, 255), "    char c1 = %d;" % r.randint(0, 255), "    bool b0 = true;"]
        C += ["    unsigned char c0 = %s;" % A[-3].split("=")[1].strip().rstrip(";"),
              "    unsigned char c1 = %s;" % A[-2].split("=")[1].strip().rstrip(";"), "    _Bool b0 = 1;"]
        self.main_pairs = []
        for _ in range(r.randint(4, 9)):
            sa, sc = self.stmt(3, 1)
            self.main_pairs.append((sa, sc))
        self.head = (A, C)
        for sa, sc in self.main_pairs:
            A += sa
            C += sc
        for n in self.ints + self.chars + self.bools + self.globs:
            A.append("    printlnInt(%s);" % n)
            C.append('    printf("%%ld\\n", (long)%s);' % n)
        A += ["    for (int z = 0; z < 8; z++) printlnInt(arr[z]);", "    return 0;", "}"]
        C += ['    for (int z = 0; z < 8; z++) printf("%ld\\n", arr[z]);', "    return 0;", "}"]
        nprint = len(self.ints + self.chars + self.bools + self.globs) + 3
        self.tail_a = A[-nprint:]
        self.tail_c = C[-nprint:]
        return "\n".join(A) + "\n", "\n".join(C) + "\n"

    def fix_func_expr(self, text, lang):
        # inside f(): only p, q, globals and arr are valid names (variables were renamed)
        import re
        text = re.sub(r"\bp[0-9]\b", "p", text)
        text = re.sub(r"\bc[0-9]\b", "q", text)
        return text


def render(g, keep):
    """Rebuild the program keeping only the main() statements listed in keep."""
    A = list(g.head[0]); C = list(g.head[1])
    # drop the statements that were appended after the head
    nA = len(A) - sum(len(sa) for sa, sc in g.main_pairs) - len(g.tail_a)
    nC = len(C) - sum(len(sc) for sa, sc in g.main_pairs) - len(g.tail_c)
    A = A[:nA]; C = C[:nC]
    for i, (sa, sc) in enumerate(g.main_pairs):
        if i in keep:
            A += sa; C += sc
    return "\n".join(A + g.tail_a) + "\n", "\n".join(C + g.tail_c) + "\n"


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, timeout=60, **kw)


def main():
    tmp = tempfile.mkdtemp(prefix="difffuzz")
    bad = 0
    try:
        for n in range(COUNT):
            rng = random.Random(SEED * 100003 + n)
            a_src, c_src = Gen(rng).program()
            pa, pc = os.path.join(tmp, "p.a"), os.path.join(tmp, "p.c")
            open(pa, "w").write(a_src)
            open(pc, "w").write(c_src)
            exe_a = os.path.join(tmp, "p.exe" if TARGET == "windows" else "p.out")
            exe_c = os.path.join(tmp, "p_c")
            r = run(["gcc", "-w", "-O0", "-fwrapv", pc, "-o", exe_c])
            if r.returncode != 0:
                print("gcc rejected seed", SEED, n, r.stderr.decode()[:300])
                continue
            r = run([AC, "-t", TARGET, pa, "-o", exe_a])
            if r.returncode != 0:
                bad += 1
                print("COMPILE FAIL seed=%d n=%d: %s" % (SEED, n, r.stderr.decode().splitlines()[0]))
                shutil.copy(pa, "/tmp/difffuzz_fail_%d_%d.a" % (SEED, n))
                continue
            want = run([exe_c]).stdout
            try:
                got = run(RUN + [exe_a]).stdout
            except subprocess.TimeoutExpired:
                got = b"<timeout>"
            if want != got:
                bad += 1
                shutil.copy(pa, "/tmp/difffuzz_fail_%d_%d.a" % (SEED, n))
                shutil.copy(pc, "/tmp/difffuzz_fail_%d_%d.c" % (SEED, n))
                print("MISMATCH seed=%d n=%d (saved /tmp/difffuzz_fail_%d_%d.[ac])" % (SEED, n, SEED, n))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("target=%s programs=%d mismatches=%d" % (TARGET, COUNT, bad))
    sys.exit(1 if bad else 0)

main()
