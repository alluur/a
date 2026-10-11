#!/usr/bin/env python3
"""Reduce a failing difffuzz program: reduce.py seed n [target]  -> /tmp/reduced.a /tmp/reduced.c"""
import sys, random, tempfile, os
seed, n = int(sys.argv[1]), int(sys.argv[2])
target = sys.argv[3] if len(sys.argv) > 3 else "linux"
sys.argv = ["x", "0", "1", target]
here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, "difffuzz.py")).read().replace("\nmain()\n", "\n")
g_ns = {"__file__": os.path.join(here, "difffuzz.py"), "__name__": "difffuzz"}
exec(compile(src, "difffuzz", "exec"), g_ns)
Gen, render, run, AC, RUN = g_ns["Gen"], g_ns["render"], g_ns["run"], g_ns["AC"], g_ns["RUN"]
g = Gen(random.Random(seed * 100003 + n)); g.program()
tmp = tempfile.mkdtemp()
def mism(keep):
    a, c = render(g, keep)
    open(tmp + "/p.a", "w").write(a); open(tmp + "/p.c", "w").write(c)
    if run(["gcc", "-w", "-O0", "-fwrapv", tmp + "/p.c", "-o", tmp + "/pc"]).returncode: return False
    exe = tmp + ("/pa.exe" if target == "windows" else "/pa")
    if run([AC, "-t", target, tmp + "/p.a", "-o", exe]).returncode: return False
    return run([tmp + "/pc"]).stdout != run(RUN + [exe]).stdout
keep = set(range(len(g.main_pairs)))
if not mism(keep):
    print("no mismatch for this seed"); sys.exit(0)
for i in sorted(keep):
    t = keep - {i}
    if mism(t): keep = t
a, c = render(g, keep)
open("/tmp/reduced.a", "w").write(a); open("/tmp/reduced.c", "w").write(c)
print("kept statements:", sorted(keep)); print(a)
