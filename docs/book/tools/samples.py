#!/usr/bin/env python3
"""Compile and run every code sample of the A book and compare the output with the recorded one.

  samples.py [--ac PATH] [--update] [--targets] [--jobs N] [-v] [SELECTOR ...]

A sample is  samples/GROUP/NAME.a  (one file)  or  samples/GROUP/NAME/main.a  (a directory with helper modules).
SELECTOR is GROUP, GROUP/NAME or a path; no selector = everything.

The first lines of a sample may carry directives in comments:
    // book: compile-only        compile (every target with --targets) but do not run: needs a display, a terminal, the network ...
    // book: gui                 a graphical program: compiled here, run and photographed by tools/shots.py
    // book: exit=3              the program is expected to end with exit code 3 (default 0)
    // book: timeout=60          seconds (default 20)
    // book: args=one two        command line arguments
    // book: sorted              compare the lines of the output in sorted order (threads)
    // book: linux-only          the program needs Linux (fork, signals, /proc ...): --targets builds only the Linux targets
Next to the program:  NAME.in is read as standard input, NAME.out is the expected standard output.
The program runs in a scratch copy of its directory, so it may create files.

--update writes the .out of samples that have none (and rewrites the ones that differ: check the diff before you commit!).
--targets compiles every sample for every target of the compiler as well (a build check, nothing is run).
Exit status 0 only when every selected sample passes.
"""
import argparse, concurrent.futures, difflib, os, re, shlex, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
BOOK = os.path.dirname(HERE)
SAMPLES = os.path.join(BOOK, "samples")
TARGETS = ["linux", "linux-arm64", "linux-riscv64", "linux-loongarch64", "windows", "android", "android-x64", "android-riscv64", "android-loongarch64"]


def find_samples(selectors):
    found = []
    for root, dirs, files in os.walk(SAMPLES):
        dirs.sort()
        rel = os.path.relpath(root, SAMPLES)
        if os.path.exists(os.path.join(root, "main.a")) and rel != ".":
            found.append(os.path.join(root, "main.a"))
            dirs[:] = []
            continue
        for f in sorted(files):
            if f.endswith(".a"):
                found.append(os.path.join(root, f))
    if selectors:
        keep = []
        for p in found:
            rel = os.path.relpath(p, SAMPLES)
            name = rel[:-2] if not rel.endswith("/main.a") else rel[:-7]
            for s in selectors:
                s = s.rstrip("/")
                if s.endswith(".a"):
                    s = s[:-2]
                if name == s or name.startswith(s + "/") or os.path.abspath(s) == os.path.abspath(p):
                    keep.append(p)
                    break
        found = keep
    return found


def directives(path):
    d = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for i, line in enumerate(f):
            if i > 12:
                break
            m = re.match(r"\s*//\s*book:\s*(.*)$", line)
            if not m:
                continue
            for item in re.findall(r"(args=.*|[\w-]+(?:=\S+)?)", m.group(1)):
                if item.startswith("args="):
                    d["args"] = item[5:]
                    break
                k, _, v = item.partition("=")
                d[k] = v or True
    return d


def sample_name(path):
    rel = os.path.relpath(path, SAMPLES)
    return rel[:-7] if rel.endswith("/main.a") else rel[:-2]


def out_path(path):
    return path[:-2] + ".out"


def run_one(path, ac, update, targets, verbose):
    name = sample_name(path)
    d = directives(path)
    srcdir = os.path.dirname(path)
    multi = os.path.basename(path) == "main.a"
    tmp = tempfile.mkdtemp(prefix="bk-")
    try:
        work = os.path.join(tmp, "w")
        if multi:
            shutil.copytree(srcdir, work)
        else:
            os.makedirs(work)
            shutil.copy(path, work)
            for ext in (".in",):
                if os.path.exists(path[:-2] + ext):
                    shutil.copy(path[:-2] + ext, work)
        prog = os.path.join(work, "main.a" if multi else os.path.basename(path))
        exe = os.path.join(work, "prog.elf")
        r = subprocess.run([ac, prog, "-o", exe], cwd=work, capture_output=True, text=True, timeout=120)
        if r.returncode != 0:
            return name, False, "compile error:\n" + (r.stderr or r.stdout)[:1500]
        if targets:
            for t in TARGETS[1:]:
                if d.get("linux-only") and not t.startswith("linux"):
                    continue
                r = subprocess.run([ac, "-t", t, prog, "-o", os.path.join(work, "x-" + t)], cwd=work, capture_output=True, text=True, timeout=120)
                if r.returncode != 0:
                    return name, False, "compile error for target %s:\n%s" % (t, (r.stderr or r.stdout)[:1500])
        if d.get("compile-only") or d.get("gui"):
            return name, True, "compiled" + (" (targets too)" if targets else "")
        stdin_path = path[:-2] + ".in" if not multi else os.path.join(srcdir, "main.in")
        stdin = open(stdin_path, "rb") if os.path.exists(stdin_path) else subprocess.DEVNULL
        timeout = int(d.get("timeout", 20) if d.get("timeout") is not True else 20)
        want_exit = int(d.get("exit", 0) if d.get("exit") is not True else 0)
        argv = [exe] + shlex.split(d.get("args", ""))
        env = {"PATH": "/usr/bin:/bin", "HOME": work, "LANG": "C", "TERM": "dumb"}
        try:
            r = subprocess.run(argv, cwd=work, stdin=stdin, capture_output=True, timeout=timeout, env=env)
        except subprocess.TimeoutExpired:
            return name, False, "timeout after %d s" % timeout
        got = r.stdout.decode("utf-8", "replace")
        if r.returncode != want_exit:
            return name, False, "exit code %d (expected %d)\nstderr: %s\nstdout: %s" % (r.returncode, want_exit, r.stderr.decode("utf-8", "replace")[:600], got[:600])
        op = out_path(path) if not multi else os.path.join(srcdir, "main.out")
        norm = (lambda s: "\n".join(sorted(s.splitlines())) + "\n") if d.get("sorted") else (lambda s: s)
        if os.path.exists(op):
            want = open(op, encoding="utf-8", errors="replace", newline="").read()
            if norm(want) == norm(got):
                return name, True, "ok"
            if update:
                open(op, "w", encoding="utf-8", newline="").write(got)
                return name, True, "output rewritten"
            diff = "".join(difflib.unified_diff(want.splitlines(True), got.splitlines(True), "expected", "got", n=2))
            return name, False, "output differs:\n" + diff[:1500]
        if update:
            open(op, "w", encoding="utf-8", newline="").write(got)
            return name, True, "output recorded (%d bytes)" % len(got)
        return name, False, "no .out file (run with --update, then read the output and commit it)"
    except Exception as e:  # keep going with the other samples
        return name, False, "harness error: %r" % (e,)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ac", default=os.environ.get("AC") or os.path.join(BOOK, "..", "..", "build", "ac"))
    ap.add_argument("--update", action="store_true")
    ap.add_argument("--targets", action="store_true")
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("selectors", nargs="*")
    a = ap.parse_args()
    ac = os.path.abspath(a.ac)
    if not os.path.exists(ac):
        sys.exit("no compiler at %s (run make, or pass --ac)" % ac)
    files = find_samples(a.selectors)
    if not files:
        sys.exit("no samples selected")
    bad = 0
    with concurrent.futures.ThreadPoolExecutor(a.jobs) as ex:
        futs = [ex.submit(run_one, p, ac, a.update, a.targets, a.verbose) for p in files]
        for f in futs:
            name, ok, msg = f.result()
            if not ok:
                bad += 1
                print("FAIL %s: %s" % (name, msg))
            elif a.verbose or "recorded" in msg or "rewritten" in msg:
                print("ok   %s (%s)" % (name, msg))
    print("%d samples, %d failed" % (len(files), bad))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
