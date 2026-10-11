#!/usr/bin/env python3
"""Line-level delta debugging for a failing A/C pair produced by difffuzz.py.
   ddmin.py file.a file.c [target]   -> /tmp/min.a /tmp/min.c   (the A and C files must be line aligned)"""
import sys, subprocess, os, tempfile
fa, fc = sys.argv[1], sys.argv[2]
target = sys.argv[3] if len(sys.argv) > 3 else "linux"
RUN = ["qemu-aarch64"] if target in ("linux-arm64", "android") else []
AC = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "build", "ac")
A = open(fa).read().split("\n"); C = open(fc).read().split("\n")
A = [""] * (len(C) - len(A)) + A
assert len(A) == len(C), (len(A), len(C))
tmp = tempfile.mkdtemp()
def sh(cmd):
    try: return subprocess.run(cmd, capture_output=True, timeout=20)
    except subprocess.TimeoutExpired: return None
def bad(keep):
    a = "\n".join(A[i] for i in keep) + "\n"; c = "\n".join(C[i] for i in keep) + "\n"
    open(tmp + "/p.a", "w").write(a); open(tmp + "/p.c", "w").write(c)
    r = sh(["gcc", "-w", "-O0", "-fwrapv", tmp + "/p.c", "-o", tmp + "/pc"])
    if not r or r.returncode: return False
    r = sh([AC, "-t", target, tmp + "/p.a", "-o", tmp + "/pa"])
    if not r or r.returncode: return False
    w = sh([tmp + "/pc"]); g = sh(RUN + [tmp + "/pa"])
    return bool(w and g and w.stdout != g.stdout)
keep = list(range(len(A)))
assert bad(keep), "no mismatch"
n = 2
while len(keep) >= 2:
    size = max(1, len(keep) // n); changed = False
    for s in range(0, len(keep), size):
        cand = keep[:s] + keep[s + size:]
        if cand and bad(cand): keep = cand; n = max(n - 1, 2); changed = True; break
    if not changed:
        if size == 1: break
        n = min(len(keep), n * 2)
open("/tmp/min.a", "w").write("\n".join(A[i] for i in keep) + "\n")
open("/tmp/min.c", "w").write("\n".join(C[i] for i in keep) + "\n")
print(open("/tmp/min.a").read())
