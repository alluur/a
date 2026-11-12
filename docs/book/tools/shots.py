#!/usr/bin/env python3
"""Photograph the graphical samples of the A book.

  shots.py [--ac PATH] [-v] [--keep] [--list] [SELECTOR ...]

SELECTOR is GROUP, GROUP/NAME or a path; no selector = every graphical sample.  The result of  samples/GROUP/NAME.a  is
shots/GROUP-NAME.png.  A sample is graphical when one of its first 12 lines holds a directive comment:

  // book: gui              a program with windows: it needs the display server (see "How it works")
  // book: shot=out.png     a pure drawing program (gfx, gimg, gchart): no display; the tool runs it in a scratch directory and copies
                            the file it wrote (out.png, a PNG made with gimg.savePng) to shots/GROUP-NAME.png

Directives of a  gui  sample (each on a `// book:` line within the first 12 lines; several per line are fine; the ACTIONS run in the order
in which they are written):

  window=WxH       size of the (headless) screen, default 800x600. The windows of the program appear at 40,74 and cascade by 28 pixels, so
                   the screen has to be bigger than the windows. The picture is cut out of the screen (see below), so a large screen costs nothing.
  args=a b         command line arguments of the program (like the sample checker)
  wait=MS          the time the program gets to paint before the first action, default 1500
  click=X,Y        move the pointer to X,Y (screen coordinates) and click the left button     rclick=X,Y   right button     dclick=X,Y   double click
  move=X,Y         move the pointer (hover effects, tool tips: follow it with pause=1500)
  drag=X0,Y0,X1,Y1 press at X0,Y0, move to X1,Y1 in five steps, release
  scroll=X,Y,N     the mouse wheel at X,Y; N > 0 scrolls up, N < 0 down (|N| steps)
  type=TEXT        type text (the rest of the line; use it last on its line); Unicode is fine
  key=NAME         one key: enter tab esc backspace delete space left right up down home end pgup pgdn insert f1..f12 or a single
                   character; with modifiers: ctrl+a  alt+f  ctrl+shift+z  shift+tab
  pause=MS         wait (the screen needs 200 ms after every action anyway)
  pointer=keep     leave the pointer where the last action put it (default: it is moved to the bottom right corner before the
                   picture is taken, so that it is not on the picture); pointer=X,Y puts it there
  full             do not cut the picture to the windows: the whole screen is the picture

How it works: the tool compiles examples/gui/adisplayd.a once and every sample with `ac`; for each sample it starts adisplayd headless
(`-vnc PORT -p PORT2 -control -size WxH`, two free ports between 21000 and 31999, never 5900-5999 or 7000-7999) and talks to it itself
in the display protocol (adp), like `actl` does: it takes a screenshot of the empty desktop (with the pointer in the corner), starts the
program as a client (ADISPLAY=127.0.0.1:PORT2) in a scratch copy of the sample's directory (the executable is in another directory, so
a file dialog sees only the sample's own files), waits `wait` ms, performs the actions (injecting pointer and keys), waits until two
screenshots in a row are equal (at most 5 s), compares with the empty desktop, cuts out the bounding box of everything that changed
(8 pixels of margin: the window shadow is part of the margin) and writes it as a PNG with Pillow.  Both servers and the client are killed in
every case (also on errors and on Ctrl+C).  Use  nice -n 10  on a shared machine.
Programs should set `gui.caretBlinks = false` (the caret of a text field blinks on a timer) and must not draw the time of day.
"""
import argparse, atexit, os, random, re, shutil, signal, socket, struct, subprocess, sys, tempfile, time

try:
    from PIL import Image, ImageChops
except ImportError:
    sys.exit("shots.py needs Pillow (python3 -m pip install pillow)")

HERE = os.path.dirname(os.path.abspath(__file__))
BOOK = os.path.dirname(HERE)
ROOT = os.path.dirname(os.path.dirname(BOOK))
SAMPLES = os.path.join(BOOK, "samples")
SHOTS = os.path.join(BOOK, "shots")
sys.path.insert(0, HERE)
from samples import find_samples, sample_name  # noqa: E402  (selectors work like in the sample checker)

MARGIN = 8
DEFAULT_SCREEN = (800, 600)
DEFAULT_WAIT = 1500
AFTER_ACTION = 0.2          # seconds the server and the program get after every injected event
THRESHOLD = 12              # a pixel counts as changed when a channel differs by more than this (the shadow is below it)

# display protocol (lib/adp.a, lib/wsrv.a)
Q_HELLO, E_WELCOME, Q_SHOT, E_SHOT, Q_INJECT = 1, 101, 15, 112, 16
IE_MOVE, IE_DOWN, IE_UP, IE_SCROLL, IE_KEYDOWN, IE_KEYUP = 1, 2, 3, 4, 5, 6
KEYS = {
    "backspace": 8, "tab": 9, "enter": 13, "return": 13, "esc": 27, "escape": 27, "space": 32, "delete": 127, "del": 127,
    "left": 300, "right": 301, "up": 302, "down": 303, "home": 304, "end": 305, "pgup": 306, "pageup": 306, "pgdn": 307,
    "pagedown": 307, "insert": 308, "shift": 340, "ctrl": 341, "alt": 342, "meta": 343,
}
for _i in range(1, 13):
    KEYS["f%d" % _i] = 320 + _i - 1
MODS = ("ctrl", "shift", "alt", "meta")


class ShotError(Exception):
    pass


# ---- the processes we started: every one of them is killed, whatever happens -----------------------------------------------------
PROCS = []


def spawn(argv, **kw):
    p = subprocess.Popen(argv, start_new_session=True, **kw)
    PROCS.append(p)
    return p


def kill(p):
    if p.poll() is None:
        for sig in (signal.SIGTERM, signal.SIGKILL):
            try:
                os.killpg(p.pid, sig)
            except (ProcessLookupError, PermissionError):
                break
            try:
                p.wait(timeout=1.5)
                break
            except subprocess.TimeoutExpired:
                continue
    try:
        p.wait(timeout=1)
    except subprocess.TimeoutExpired:
        pass
    if p in PROCS:
        PROCS.remove(p)


def kill_all(*_):
    for p in list(PROCS):
        kill(p)


atexit.register(kill_all)


def on_signal(signum, frame):
    kill_all()
    sys.exit(130)


signal.signal(signal.SIGINT, on_signal)
signal.signal(signal.SIGTERM, on_signal)


# ---- directives ---------------------------------------------------------------------------------------------------------------------
ACTION_KEYS = ("click", "rclick", "dclick", "move", "drag", "scroll", "type", "key", "pause")


def read_directives(path):
    """(flags, actions): flags is a dict (gui, shot, window, wait, args, pointer, full), actions a list of (name, value) in order."""
    flags, actions = {}, []
    with open(path, encoding="utf-8", errors="replace") as f:
        for i, line in enumerate(f):
            if i > 12:
                break
            m = re.match(r"\s*//\s*book:\s*(.*?)\s*$", line)
            if not m:
                continue
            rest = m.group(1)
            while rest:
                rest = rest.lstrip()
                if not rest:
                    break
                m2 = re.match(r"([\w-]+)(?:=(.*))?", rest)
                if not m2:
                    break
                key, val = m2.group(1), m2.group(2)
                if key in ("args", "type"):               # the rest of the line, blanks included
                    value = val if val is not None else ""
                    rest = ""
                else:
                    m3 = re.match(r"([\w-]+)(?:=(\S*))?", rest)
                    key, value = m3.group(1), m3.group(2)
                    rest = rest[m3.end():]
                if key in ACTION_KEYS:
                    actions.append((key, value))
                else:
                    flags[key] = value if value is not None else True
    return flags, actions


def pair(text, n, what):
    try:
        v = [int(x) for x in text.split(",")]
    except ValueError:
        v = []
    if len(v) != n:
        raise ShotError("%s needs %d numbers separated by commas, got %r" % (what, n, text))
    return v


# ---- talking to the display server ------------------------------------------------------------------------------------------------
class Ctl:
    def __init__(self, port):
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=10)
        self.buf = b""
        self.send(Q_HELLO, struct.pack("<i", 1) + b"shots")
        self.wait_for(E_WELCOME)

    def send(self, op, payload=b""):
        self.sock.sendall(struct.pack("<ii", len(payload), op) + payload)

    def message(self):
        while True:
            if len(self.buf) >= 8:
                n, op = struct.unpack_from("<ii", self.buf)
                if len(self.buf) >= 8 + n:
                    payload = self.buf[8:8 + n]
                    self.buf = self.buf[8 + n:]
                    return op, payload
            data = self.sock.recv(1 << 20)
            if not data:
                raise ShotError("the display server closed the connection")
            self.buf += data

    def wait_for(self, want):
        while True:
            op, payload = self.message()
            if op == want:
                return payload

    def screenshot(self):
        self.send(Q_SHOT)
        p = self.wait_for(E_SHOT)
        w, h = struct.unpack_from("<ii", p)
        return Image.frombuffer("RGBA", (w, h), p[8:8 + w * h * 4], "raw", "BGRA", 0, 1).convert("RGB")

    def inject(self, kind, x=0, y=0, button=0, key=0, uni=0):
        self.send(Q_INJECT, struct.pack("<6i", kind, x, y, button, key, uni))

    def move(self, x, y):
        self.inject(IE_MOVE, x, y)

    def click(self, x, y, button=1):
        self.move(x, y)
        time.sleep(0.05)
        self.inject(IE_DOWN, button=button)
        time.sleep(0.05)
        self.inject(IE_UP, button=button)

    def key(self, combo):
        parts = combo.lower().split("+") if len(combo) > 1 else [combo]
        if combo.endswith("++"):                                   # "ctrl++"
            parts = combo[:-2].lower().split("+") + ["+"]
        mods = [m for m in parts[:-1]]
        name = parts[-1]
        for m in mods:
            if m not in MODS:
                raise ShotError("unknown modifier %r in key=%s" % (m, combo))
        if name in KEYS:
            code, uni = KEYS[name], 0
        elif len(name) == 1:
            code, uni = ord(name), ord(name)
        else:
            raise ShotError("unknown key %r in key=%s" % (name, combo))
        if mods and uni and ("ctrl" in mods or "alt" in mods):
            uni = 0                                                  # Ctrl+A is not the character "a"
        for m in mods:
            self.inject(IE_KEYDOWN, key=KEYS[m])
        self.inject(IE_KEYDOWN, key=code, uni=uni)
        self.inject(IE_KEYUP, key=code)
        for m in reversed(mods):
            self.inject(IE_KEYUP, key=KEYS[m])

    def type(self, text):
        for ch in text:
            if ch.isupper() and ch.isascii():
                self.inject(IE_KEYDOWN, key=KEYS["shift"])
                self.inject(IE_KEYDOWN, key=ord(ch.lower()), uni=ord(ch))
                self.inject(IE_KEYUP, key=ord(ch.lower()))
                self.inject(IE_KEYUP, key=KEYS["shift"])
            else:
                self.inject(IE_KEYDOWN, key=ord(ch), uni=ord(ch))
                self.inject(IE_KEYUP, key=ord(ch))
            time.sleep(0.01)

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


def stable_screenshot(ctl, limit=5.0):
    """Screenshots until two in a row are the same (the server draws a moment after the program or the input)."""
    time.sleep(AFTER_ACTION)
    prev = ctl.screenshot()
    end = time.time() + limit
    while time.time() < end:
        time.sleep(0.2)
        img = ctl.screenshot()
        if img.tobytes() == prev.tobytes():
            return img
        prev = img
    return prev


def free_port(taken):
    for _ in range(200):
        p = random.randint(21000, 31999)
        if p in taken or 5900 <= p <= 5999 or 7000 <= p <= 7999:
            continue
        s = socket.socket()
        try:
            s.bind(("127.0.0.1", p))
        except OSError:
            continue
        finally:
            s.close()
        return p
    raise ShotError("no free port")


# ---- building ---------------------------------------------------------------------------------------------------------------------
def build(ac, src, exe, cwd):
    r = subprocess.run([ac, src, "-o", exe], cwd=cwd, capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        raise ShotError("compile error:\n" + (r.stderr or r.stdout)[:1500])


def scratch_copy(path, tmp):
    """The sample's own files in tmp/w; returns (the main source in it, tmp/w)."""
    work = os.path.join(tmp, "w")
    if os.path.basename(path) == "main.a":
        shutil.copytree(os.path.dirname(path), work, ignore=shutil.ignore_patterns("*.out", "*.png"))
        return os.path.join(work, "main.a"), work
    os.makedirs(work)
    shutil.copy(path, work)
    return os.path.join(work, os.path.basename(path)), work


# ---- one sample ---------------------------------------------------------------------------------------------------------------------
def crop_box(base, img):
    diff = ImageChops.difference(base, img)
    r, g, b = diff.split()
    mask = ImageChops.lighter(ImageChops.lighter(r, g), b).point(lambda v: 255 if v > THRESHOLD else 0)
    # the pointer waits in the bottom right corner of the empty desktop: when a sample moved it away, that is a difference too
    mask.paste(0, (img.width - 40, img.height - 40, img.width, img.height))
    return mask.getbbox()


def run_actions(ctl, actions):
    for name, value in actions:
        if name == "click":
            ctl.click(*pair(value, 2, "click"))
        elif name == "rclick":
            ctl.click(*pair(value, 2, "rclick"), button=3)
        elif name == "dclick":
            x, y = pair(value, 2, "dclick")
            ctl.click(x, y)
            time.sleep(0.05)
            ctl.click(x, y)
        elif name == "move":
            ctl.move(*pair(value, 2, "move"))
        elif name == "drag":
            x0, y0, x1, y1 = pair(value, 4, "drag")
            ctl.move(x0, y0)
            time.sleep(0.05)
            ctl.inject(IE_DOWN, button=1)
            for i in range(1, 6):
                time.sleep(0.03)
                ctl.move(x0 + (x1 - x0) * i // 5, y0 + (y1 - y0) * i // 5)
            time.sleep(0.05)
            ctl.inject(IE_UP, button=1)
        elif name == "scroll":
            x, y, n = pair(value, 3, "scroll")
            ctl.move(x, y)
            time.sleep(0.05)
            for _ in range(abs(n)):
                ctl.inject(IE_SCROLL, button=1 if n > 0 else -1)
                time.sleep(0.05)
        elif name == "type":
            ctl.type(value)
        elif name == "key":
            ctl.key(value)
        elif name == "pause":
            time.sleep(int(value) / 1000.0)
        time.sleep(AFTER_ACTION)


def shot_gui(path, name, ac, tools, flags, actions, verbose, keep):
    sw, sh = DEFAULT_SCREEN
    if flags.get("window") not in (None, True):
        sw, sh = pair(flags["window"].lower().replace("x", ","), 2, "window")
    wait = int(flags["wait"]) if flags.get("wait") not in (None, True) else DEFAULT_WAIT
    tmp = tempfile.mkdtemp(prefix="shot-")
    ctl = server = client = None
    try:
        src, work = scratch_copy(path, tmp)
        exe = os.path.join(tmp, "bin", "prog")
        os.makedirs(os.path.dirname(exe))
        build(ac, src, exe, work)
        vnc = free_port(set())
        port = free_port({vnc})
        corner = (sw - 1, sh - 1)
        server = spawn([tools["adisplayd"], "-p", str(port), "-vnc", str(vnc), "-control", "-size", "%dx%d" % (sw, sh)],
                       stdout=open(os.path.join(tmp, "server.log"), "w"), stderr=subprocess.STDOUT, cwd=tmp)
        for _ in range(100):
            if server.poll() is not None:
                raise ShotError("the display server stopped: " + open(os.path.join(tmp, "server.log")).read()[:500])
            try:
                ctl = Ctl(port)
                break
            except (OSError, ShotError):
                time.sleep(0.05)
        if ctl is None:
            raise ShotError("cannot connect to the display server on port %d" % port)
        ctl.move(*corner)
        base = stable_screenshot(ctl)

        env = {"PATH": "/usr/bin:/bin", "HOME": work, "LANG": "C", "TERM": "dumb", "ADISPLAY": "127.0.0.1:%d" % port}
        log = open(os.path.join(tmp, "client.log"), "w")
        argv = [exe] + (flags["args"].split() if isinstance(flags.get("args"), str) else [])
        client = spawn(argv, cwd=work, env=env, stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
        end = time.time() + wait / 1000.0
        while time.time() < end:
            if client.poll() is not None:
                break
            time.sleep(0.05)

        def check_alive():
            if client.poll() is not None:
                raise ShotError("the program ended with exit code %d before the picture was taken:\n%s"
                                % (client.returncode, open(os.path.join(tmp, "client.log")).read()[:600]))

        check_alive()
        run_actions(ctl, actions)
        check_alive()
        pointer = flags.get("pointer")
        if pointer is None:
            ctl.move(*corner)
        elif pointer not in ("keep", True):
            ctl.move(*pair(pointer, 2, "pointer"))
        img = stable_screenshot(ctl)
        check_alive()
        if flags.get("full"):
            box = (0, 0, sw, sh)
        else:
            box = crop_box(base, img)
            if box is None:
                raise ShotError("nothing changed on the screen: the program drew no window (log: %s)" % open(os.path.join(tmp, "client.log")).read()[:300])
            if box[0] <= 0 or box[1] <= 0 or box[2] >= sw or box[3] >= sh:
                print("warning %s: the window touches the edge of the %dx%d screen; make it bigger with // book: window=WxH" % (name, sw, sh))
            box = (max(0, box[0] - MARGIN), max(0, box[1] - MARGIN), min(sw, box[2] + MARGIN), min(sh, box[3] + MARGIN))
        out = os.path.join(SHOTS, name.replace("/", "-") + ".png")
        os.makedirs(SHOTS, exist_ok=True)
        img.crop(box).save(out, optimize=True)
        return out, (box[2] - box[0], box[3] - box[1])
    finally:
        if ctl:
            ctl.close()
        for p in (client, server):
            if p:
                kill(p)
        if keep:
            print("kept %s" % tmp)
        else:
            shutil.rmtree(tmp, ignore_errors=True)


def shot_file(path, name, ac, flags, verbose, keep):
    """A drawing program: run it, copy the PNG it wrote."""
    want = flags["shot"]
    if want is True or not want.endswith(".png"):
        raise ShotError("shot=FILE.png needs the name of a PNG file")
    tmp = tempfile.mkdtemp(prefix="shot-")
    try:
        src, work = scratch_copy(path, tmp)
        exe = os.path.join(tmp, "bin", "prog")
        os.makedirs(os.path.dirname(exe))
        build(ac, src, exe, work)
        timeout = int(flags["timeout"]) if flags.get("timeout") not in (None, True) else 20
        env = {"PATH": "/usr/bin:/bin", "HOME": work, "LANG": "C", "TERM": "dumb"}
        argv = [exe] + (flags["args"].split() if isinstance(flags.get("args"), str) else [])
        p = spawn(argv, cwd=work, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            so, se = p.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            kill(p)
            raise ShotError("timeout after %d s" % timeout)
        finally:
            if p in PROCS:
                PROCS.remove(p)
        if p.returncode != 0:
            raise ShotError("exit code %d\n%s" % (p.returncode, (se or so).decode("utf-8", "replace")[:600]))
        produced = os.path.join(work, want)
        if not os.path.exists(produced):
            raise ShotError("the program did not write %s" % want)
        out = os.path.join(SHOTS, name.replace("/", "-") + ".png")
        os.makedirs(SHOTS, exist_ok=True)
        im = Image.open(produced)
        im.load()
        im.save(out, optimize=True)                                  # the same pixels, smaller file
        return out, im.size
    finally:
        if keep:
            print("kept %s" % tmp)
        else:
            shutil.rmtree(tmp, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser(description="photograph the graphical samples of the A book")
    ap.add_argument("--ac", default=os.environ.get("AC") or os.path.join(ROOT, "build", "ac"))
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--keep", action="store_true", help="keep the scratch directories (the program log is in them)")
    ap.add_argument("--list", action="store_true", help="only list the graphical samples")
    ap.add_argument("selectors", nargs="*")
    a = ap.parse_args()
    ac = os.path.abspath(a.ac)
    if not os.path.exists(ac):
        sys.exit("no compiler at %s (run make, or pass --ac)" % ac)
    todo = []
    for path in find_samples(a.selectors):
        flags, actions = read_directives(path)
        if flags.get("gui") or flags.get("shot"):
            todo.append((path, flags, actions))
    if a.list:
        for path, flags, actions in todo:
            print(sample_name(path), "gui" if flags.get("gui") else "file")
        return
    if not todo:
        sys.exit("no graphical samples selected (a sample needs  // book: gui  or  // book: shot=out.png)")
    tools = {}
    if any(f.get("gui") for _, f, _ in todo):
        tdir = tempfile.mkdtemp(prefix="shot-tools-")
        atexit.register(shutil.rmtree, tdir, True)
        try:
            tools["adisplayd"] = os.path.join(tdir, "adisplayd")
            build(ac, os.path.join(ROOT, "examples", "gui", "adisplayd.a"), tools["adisplayd"], tdir)
        except ShotError as e:
            sys.exit("cannot build the display server: %s" % e)
    bad = 0
    for path, flags, actions in todo:
        name = sample_name(path)
        t0 = time.time()
        try:
            if flags.get("gui"):
                out, size = shot_gui(path, name, ac, tools, flags, actions, a.verbose, a.keep)
            else:
                out, size = shot_file(path, name, ac, flags, a.verbose, a.keep)
            print("ok   %s -> %s (%dx%d, %.1f s)" % (name, os.path.relpath(out, ROOT), size[0], size[1], time.time() - t0))
        except ShotError as e:
            bad += 1
            print("FAIL %s: %s" % (name, e))
        except Exception as e:                      # keep going with the other samples
            bad += 1
            print("FAIL %s: %r" % (name, e))
        finally:
            kill_all()
    print("%d pictures, %d failed" % (len(todo), bad))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
