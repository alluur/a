#!/usr/bin/env python3
"""Run the terminal samples of the A book in a pseudo terminal and record what they show.

  tuishot.py [--ac PATH] [--update] [--keep] [-v] [SELECTOR ...]

A terminal sample is  samples/GROUP/NAME.a  with the directive  `// book: tui`  in its first lines (the sample checker only compiles
it).  Next to it:

  NAME.keys     what to do, one token per line (the vocabulary is in WRITING.md, section 7)
  NAME.screen   the result: the final 80x24 screen as plain text (trailing blanks trimmed, no escape sequences)

Without --update the screen is compared with NAME.screen (exit status 1 when it differs or is missing).  With --update the sample is
run TWICE and NAME.screen is written only when both runs show the same screen: a sample that is not deterministic is an error.
SELECTOR is GROUP, GROUP/NAME or a path; no selector = every terminal sample.

How it works: the sample is compiled with ac and run in the empty directory /tmp/tuishot/run (made again for every run; TUISHOT_DIR changes /tmp/tuishot); ptyterm.Session (tests/tui/ptyterm.py: a small terminal
emulator behind a pty of 80x24, TERM=xterm-256color, LANG=C.UTF-8, no other environment) starts it; the tokens of NAME.keys are sent
one by one, and after every token the tool waits until the program has been quiet for 250 ms; the screen of the emulator at the end is
the result.
"""
import argparse, fcntl, os, re, shutil, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
BOOK = os.path.dirname(HERE)
ROOT = os.path.dirname(os.path.dirname(BOOK))
SAMPLES = os.path.join(BOOK, "samples")
sys.path.insert(0, os.path.join(ROOT, "tests", "tui"))
import ptyterm  # noqa: E402  (the terminal emulator of the tui tests)

COLS, ROWS = 80, 24
# The sample runs in this directory (made empty for every run) so that the paths a program shows are the same on every machine.
WORKDIR = os.environ.get("TUISHOT_DIR", "/tmp/tuishot")
QUIET = 0.25           # seconds without output = the program has finished reacting
START_TIMEOUT = 8.0

NAMED = {
    "enter": "\r", "return": "\r", "tab": "\t", "esc": "\x1b", "escape": "\x1b", "backspace": "\x7f", "space": " ", "minus": "-",
}
CURSOR = {"up": "A", "down": "B", "right": "C", "left": "D", "home": "H", "end": "F"}
TILDE = {"insert": 2, "delete": 3, "pgup": 5, "pageup": 5, "pgdn": 6, "pagedown": 6}
FKEYS = {1: "P", 2: "Q", 3: "R", 4: "S"}
FTILDE = {5: 15, 6: 17, 7: 18, 8: 19, 9: 20, 10: 21, 11: 23, 12: 24}


class SampleError(Exception):
    pass


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


def find_samples(selectors):
    found = []
    for root, dirs, files in os.walk(SAMPLES):
        dirs.sort()
        for f in sorted(files):
            if f.endswith(".a") and directives(os.path.join(root, f)).get("tui"):
                found.append(os.path.join(root, f))
    if selectors:
        keep = []
        for p in found:
            name = os.path.relpath(p, SAMPLES)[:-2]
            for s in selectors:
                s = s.rstrip("/")
                if s.endswith(".a"):
                    s = s[:-2]
                if name == s or name.startswith(s + "/") or os.path.abspath(s) == os.path.abspath(p)[:-2] or os.path.abspath(s) == os.path.abspath(p):
                    keep.append(p)
                    break
        found = keep
    return found


# ---- the key vocabulary -----------------------------------------------------------------------------------------------------------------
def encode_key(name):
    """'ctrl-x', 'alt-f', 'shift-tab', 'ctrl-alt-up', 'f10', 'enter' ... -> the bytes a terminal sends."""
    parts = name.lower().split("-")
    key = parts[-1]
    mods = set(parts[:-1])
    for m in mods:
        if m not in ("ctrl", "alt", "shift"):
            raise SampleError("unknown modifier %r in key:%s" % (m, name))
    code = 1 + (1 if "shift" in mods else 0) + (2 if "alt" in mods else 0) + (4 if "ctrl" in mods else 0)
    if key in CURSOR:
        return ("\x1b[%s%s" % ("1;%d" % code if code > 1 else "", CURSOR[key])).encode()
    if key in TILDE:
        return ("\x1b[%d%s~" % (TILDE[key], ";%d" % code if code > 1 else "")).encode()
    m = re.fullmatch(r"f(\d+)", key)
    if m:
        n = int(m.group(1))
        if n in FKEYS:
            return ("\x1b[1;%d%s" % (code, FKEYS[n]) if code > 1 else "\x1bO" + FKEYS[n]).encode()
        if n in FTILDE:
            return ("\x1b[%d%s~" % (FTILDE[n], ";%d" % code if code > 1 else "")).encode()
        raise SampleError("unknown function key %r" % key)
    if key == "tab" and "shift" in mods and mods == {"shift"}:
        return b"\x1b[Z"
    if key in NAMED:
        base = NAMED[key]
    elif len(key) == 1 or (len(key) > 1 and all(ord(c) > 127 for c in key)):
        base = key
    else:
        raise SampleError("unknown key %r" % key)
    out = base
    if "ctrl" in mods:
        c = base.lower()
        if "a" <= c <= "z":
            out = chr(ord(c) - 96)
        elif c in "[\\]^_":
            out = chr(ord(c) - 64)
        elif c == " ":
            out = "\x00"
        elif c == "/":
            out = "\x1f"
        else:
            raise SampleError("Ctrl+%s cannot be sent as one byte" % base)
    elif "shift" in mods and len(base) == 1:
        out = base.upper()
    if "alt" in mods:
        out = "\x1b" + out
    return out.encode("utf-8")


def parse_keys(path):
    """-> (env dict, list of (token, argument))"""
    env = {}
    toks = []
    with open(path, encoding="utf-8") as f:
        for n, raw in enumerate(f, 1):
            line = raw.rstrip("\n")
            if line.strip() == "" or line.lstrip().startswith("#"):
                continue
            kind, sep, arg = line.partition(":")
            kind = kind.strip().lower()
            if not sep:
                raise SampleError("%s:%d: no colon in %r" % (os.path.basename(path), n, line))
            if kind == "env":
                k, _, v = arg.partition("=")
                env[k.strip()] = v
                continue
            if kind not in ("text", "key", "wait", "click", "rclick", "press", "release", "drag", "wheel-up", "wheel-down", "paste", "resize", "expect", "gone"):
                raise SampleError("%s:%d: unknown token %r" % (os.path.basename(path), n, kind))
            toks.append((kind, arg, n))
    return env, toks


def xy(arg, where):
    m = re.fullmatch(r"\s*(\d+)\s*,\s*(\d+)\s*", arg)
    if not m:
        raise SampleError("%s: expected X,Y (cells from 0), got %r" % (where, arg))
    return int(m.group(1)), int(m.group(2))


def play(sess, toks):
    for kind, arg, n in toks:
        where = "line %d" % n
        if kind == "text":
            sess.send(arg)
        elif kind == "key":
            sess.send(encode_key(arg.strip()))
        elif kind == "wait":
            time.sleep(int(arg) / 1000.0)
        elif kind == "click":
            x, y = xy(arg, where)
            sess.mouse("press", x, y)
            sess.mouse("release", x, y)
        elif kind == "rclick":
            x, y = xy(arg, where)
            sess.mouse("press", x, y, 2)
            sess.mouse("release", x, y, 2)
        elif kind == "press":
            x, y = xy(arg, where)
            sess.mouse("press", x, y)
        elif kind == "release":
            x, y = xy(arg, where)
            sess.mouse("release", x, y)
        elif kind == "drag":
            x, y = xy(arg, where)
            sess.mouse("drag", x, y)
        elif kind == "wheel-up":
            x, y = xy(arg, where)
            sess.mouse("wheel", x, y, 64)
        elif kind == "wheel-down":
            x, y = xy(arg, where)
            sess.mouse("wheel", x, y, 65)
        elif kind == "paste":
            sess.send(b"\x1b[200~" + arg.encode("utf-8") + b"\x1b[201~")
        elif kind == "resize":
            c, r = xy(arg, where)
            sess.resize(c, r, settle=QUIET)
            continue
        elif kind == "expect":
            if not sess.wait_for(arg, timeout=6.0):
                raise SampleError("%s: %r never appeared on the screen:\n%s" % (where, arg, sess.screen_text()))
        elif kind == "gone":
            if not sess.wait_for(arg, timeout=6.0, absent=True):
                raise SampleError("%s: %r is still on the screen:\n%s" % (where, arg, sess.screen_text()))
        sess.wait_idle(quiet=QUIET, timeout=6.0)


def run_once(ac, path, keep, verbose):
    keys_path = path[:-2] + ".keys"
    if not os.path.exists(keys_path):
        raise SampleError("no %s" % os.path.basename(keys_path))
    env, toks = parse_keys(keys_path)
    # one run at a time: the work directory has a fixed name
    lock = open(WORKDIR + ".lock", "w")
    fcntl.flock(lock, fcntl.LOCK_EX)
    tmp = WORKDIR
    shutil.rmtree(tmp, ignore_errors=True)
    try:
        build = os.path.join(tmp, "build")          # the program is built here ...
        work = os.path.join(tmp, "run")             # ... and runs here, in an empty directory: /tmp/tuishot/run
        os.makedirs(build)
        os.makedirs(work)
        shutil.copy(path, build)
        exe = os.path.join(build, "prog.elf")
        r = subprocess.run([ac, os.path.join(build, os.path.basename(path)), "-o", exe], cwd=build, capture_output=True, text=True, timeout=120)
        if r.returncode != 0:
            raise SampleError("compile error:\n" + (r.stderr or r.stdout)[:1500])
        e = {"HOME": work, "PATH": "/usr/bin:/bin", "PS1": "$ ", "LC_ALL": "C.UTF-8"}
        e.update(env)
        sess = ptyterm.Session([exe], cols=COLS, rows=ROWS, env=e, cwd=work)
        try:
            sess.wait_idle(quiet=0.4, timeout=START_TIMEOUT)
            play(sess, toks)
            sess.wait_idle(quiet=QUIET, timeout=4.0)
            lines = [l.rstrip() for l in sess.emu.text().split("\n")]
            status = sess.exited
            if verbose:
                sys.stderr.write("   exit status: %r, emulator complaints: %r\n" % (status, sess.emu.log_errors[:3]))
        finally:
            sess.close()
        while lines and lines[-1] == "":
            lines.pop()
        return "\n".join(lines) + "\n"
    finally:
        if keep:
            sys.stderr.write("   kept %s\n" % tmp)
        else:
            shutil.rmtree(tmp, ignore_errors=True)
        lock.close()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("selectors", nargs="*")
    ap.add_argument("--ac", default=os.path.join(ROOT, "build", "ac"))
    ap.add_argument("--update", action="store_true", help="record NAME.screen (two runs must agree)")
    ap.add_argument("--keep", action="store_true", help="keep the scratch directory")
    ap.add_argument("-v", "--verbose", action="store_true")
    a = ap.parse_args()
    samples = find_samples(a.selectors)
    if not samples:
        print("no terminal samples found")
        return 0
    bad = 0
    for p in samples:
        name = os.path.relpath(p, SAMPLES)[:-2]
        want_path = p[:-2] + ".screen"
        try:
            got = run_once(a.ac, p, a.keep, a.verbose)
            if a.update:
                again = run_once(a.ac, p, False, False)
                if again != got:
                    raise SampleError("not deterministic: two runs show different screens\n--- first\n%s--- second\n%s" % (got, again))
                with open(want_path, "w", encoding="utf-8") as f:
                    f.write(got)
                print("ok    %s (recorded, %d lines)" % (name, got.count("\n")))
                continue
            if not os.path.exists(want_path):
                raise SampleError("no .screen file (run with --update, then look at it)")
            want = open(want_path, encoding="utf-8").read()
            if want != got:
                import difflib
                diff = "".join(difflib.unified_diff(want.splitlines(True), got.splitlines(True), "recorded", "now", n=1))
                raise SampleError("screen differs:\n" + diff[:1500])
            print("ok    %s" % name)
        except SampleError as e:
            bad += 1
            print("FAIL  %s: %s" % (name, e))
        except Exception as e:  # keep going
            bad += 1
            print("FAIL  %s: harness error %r" % (name, e))
    print("%d terminal sample(s), %d failed" % (len(samples), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
