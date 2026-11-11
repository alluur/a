"""ptyterm - a pseudo terminal session with a small terminal emulator, for testing full screen programs.

    s = Session(["./probe"], cols=80, rows=24, env={"TERM": "xterm-256color"})
    s.wait_for("size: 80x24")
    s.send("\x1b[A")                 # keystrokes (bytes or str)
    s.click(10, 3)                   # mouse press + release at a cell (0 based), SGR encoding
    s.resize(100, 30)                # TIOCSWINSZ + SIGWINCH
    print(s.screen_text())           # rows joined by newlines, trailing blanks removed
    s.close()

The emulator (Emu) understands what the toolkit writes: cursor movement, SGR (16, 256 and 24 bit colours, attributes), erasing, the
alternate screen, wide characters, combining marks, mode switches (cursor, autowrap, mouse, bracketed paste, focus), titles and OSC 52. It also
answers the size and cursor position queries like a real terminal. Nothing here depends on the toolkit itself.
"""
import fcntl
import os
import pty
import select
import signal
import struct
import subprocess
import termios
import time
import unicodedata


def char_width(ch):
    if unicodedata.category(ch) in ("Mn", "Me", "Cf") and ch != "­":
        return 0
    if unicodedata.east_asian_width(ch) in ("W", "F"):
        return 2
    return 1


class Cell:
    __slots__ = ("ch", "fg", "bg", "attr", "extra")

    def __init__(self):
        self.ch = " "
        self.fg = None
        self.bg = None
        self.attr = 0
        self.extra = ""

    def copy_from(self, o):
        self.ch, self.fg, self.bg, self.attr, self.extra = o.ch, o.fg, o.bg, o.attr, o.extra

    def key(self):
        return (self.ch, self.fg, self.bg, self.attr, self.extra)


ATTR = {1: "bold", 2: "dim", 3: "italic", 4: "underline", 5: "blink", 7: "reverse", 9: "strike"}


class Emu:
    def __init__(self, cols, rows):
        self.cols = cols
        self.rows = rows
        self.main = self._grid(cols, rows)
        self.alt = self._grid(cols, rows)
        self.grid = self.main
        self.on_alt = False
        self.x = 0
        self.y = 0
        self.saved = (0, 0)
        self.fg = None
        self.bg = None
        self.attr = 0
        self.cursor_visible = True
        self.autowrap = True
        self.wrap_pending = False
        self.modes = {}              # private mode number -> bool (what the program switched on)
        self.title = None
        self.title_stack = []
        self.clipboard = None        # decoded OSC 52 payload (bytes)
        self.cursor_shape = 0
        self.replies = bytearray()   # what the terminal answers to queries
        self.bell = 0
        self.alt_entries = 0
        self.state = 0
        self.buf = ""
        self.pending = b""
        self.log_errors = []

    def _grid(self, cols, rows):
        return [[Cell() for _ in range(cols)] for _ in range(rows)]

    def resize(self, cols, rows):
        # a simple resize: keep what fits (real terminals differ; the toolkit redraws everything anyway)
        def fit(g):
            ng = self._grid(cols, rows)
            for y in range(min(rows, len(g))):
                for x in range(min(cols, len(g[0]))):
                    ng[y][x].copy_from(g[y][x])
            return ng
        self.main = fit(self.main)
        self.alt = fit(self.alt)
        self.grid = self.alt if self.on_alt else self.main
        self.cols, self.rows = cols, rows
        self.x = min(self.x, cols - 1)
        self.y = min(self.y, rows - 1)

    # ---- output -----------------------------------------------------------------------------------------------------------------------
    def feed(self, data):
        data = self.pending + data
        self.pending = b""
        # keep an incomplete UTF-8 sequence for the next call
        i = len(data)
        k = 0
        while k < 4 and i - 1 - k >= 0:
            b = data[i - 1 - k]
            if b & 0xC0 == 0x80:
                k += 1
                continue
            if b >= 0xC0:
                need = 2 if b < 0xE0 else 3 if b < 0xF0 else 4
                if k + 1 < need:
                    self.pending = data[i - 1 - k:]
                    data = data[:i - 1 - k]
            break
        for ch in data.decode("utf-8", "replace"):
            self._char(ch)

    def _char(self, ch):
        st = self.state
        if st == 0:
            if ch == "\x1b":
                self.state = 1
            elif ch == "\r":
                self.x = 0
                self.wrap_pending = False
            elif ch == "\n":
                self._linefeed()
            elif ch == "\b":
                self.x = max(0, self.x - 1)
            elif ch == "\t":
                self.x = min(self.cols - 1, (self.x // 8 + 1) * 8)
            elif ch == "\x07":
                self.bell += 1
            elif ch >= " " and ch != "\x7f":
                self._put(ch)
        elif st == 1:
            if ch == "[":
                self.state = 2
                self.buf = ""
            elif ch == "]":
                self.state = 3
                self.buf = ""
            elif ch == "7":
                self.saved = (self.x, self.y)
                self.state = 0
            elif ch == "8":
                self.x, self.y = self.saved
                self.state = 0
            elif ch == "c":
                self.state = 0
            elif ch in "()*+":
                self.state = 4
            else:
                self.state = 0
        elif st == 2:
            if "\x40" <= ch <= "\x7e":
                self.state = 0
                self._csi(self.buf, ch)
            else:
                self.buf += ch
        elif st == 3:
            if ch == "\x07":
                self.state = 0
                self._osc(self.buf)
            elif ch == "\x1b":
                self.state = 5
            else:
                self.buf += ch
        elif st == 5:
            self.state = 0
            self._osc(self.buf)
        elif st == 4:
            self.state = 0

    def _osc(self, text):
        code, _, rest = text.partition(";")
        if code in ("0", "2"):
            self.title = rest
        elif code == "52":
            import base64
            _, _, data = rest.partition(";")
            try:
                self.clipboard = base64.b64decode(data)
            except Exception:
                self.log_errors.append("bad OSC 52: " + data)

    def _linefeed(self):
        if self.y == self.rows - 1:
            self.grid.pop(0)
            self.grid.append([Cell() for _ in range(self.cols)])
        else:
            self.y += 1

    def _put(self, ch):
        w = char_width(ch)
        if w == 0:
            # a combining mark joins the previous cell
            px = self.x - 1
            if self.wrap_pending:
                px = self.x
            if px >= 0 and self.grid[self.y][px].ch == "":
                px -= 1
            if px >= 0:
                self.grid[self.y][px].extra += ch
            return
        if self.wrap_pending and self.autowrap:
            self.x = 0
            self._linefeed()
        self.wrap_pending = False
        if self.x + w > self.cols:
            if self.autowrap:
                self.x = 0
                self._linefeed()
            else:
                self.x = self.cols - w
        c = self.grid[self.y][self.x]
        c.ch, c.fg, c.bg, c.attr, c.extra = ch, self.fg, self.bg, self.attr, ""
        if w == 2:
            t = self.grid[self.y][self.x + 1]
            t.ch, t.fg, t.bg, t.attr, t.extra = "", self.fg, self.bg, self.attr, ""
        self.x += w
        if self.x >= self.cols:
            self.x = self.cols - 1
            self.wrap_pending = True

    def _params(self, s):
        out = []
        for part in s.lstrip("?<>=").split(";"):
            if part == "":
                out.append(0)
            else:
                try:
                    out.append(int(part.split(":")[0]))
                except ValueError:
                    out.append(0)
        return out

    def _erase(self, y, x0, x1):
        for x in range(x0, x1):
            c = self.grid[y][x]
            c.ch, c.fg, c.bg, c.attr, c.extra = " ", None, self.bg, 0, ""

    def _csi(self, s, f):
        priv = s.startswith("?")
        p = self._params(s)
        n = p[0] if p and p[0] > 0 else 1
        self.wrap_pending = False if f in "ABCDEFGHdf" else self.wrap_pending
        if priv and f in "hl":
            for m in p:
                self._mode(m, f == "h")
            return
        if s and s[0] in "<>=":
            return
        if f == "A":
            self.y = max(0, self.y - n)
        elif f == "B":
            self.y = min(self.rows - 1, self.y + n)
        elif f == "C":
            self.x = min(self.cols - 1, self.x + n)
        elif f == "D":
            self.x = max(0, self.x - n)
        elif f == "E":
            self.y = min(self.rows - 1, self.y + n)
            self.x = 0
        elif f == "F":
            self.y = max(0, self.y - n)
            self.x = 0
        elif f == "G":
            self.x = min(self.cols - 1, n - 1)
        elif f == "d":
            self.y = min(self.rows - 1, n - 1)
        elif f in "Hf":
            self.y = min(self.rows - 1, (p[0] if p[0] > 0 else 1) - 1)
            self.x = min(self.cols - 1, ((p[1] if len(p) > 1 and p[1] > 0 else 1)) - 1)
        elif f == "J":
            mode = p[0]
            if mode == 0:
                self._erase(self.y, self.x, self.cols)
                for yy in range(self.y + 1, self.rows):
                    self._erase(yy, 0, self.cols)
            elif mode == 1:
                for yy in range(0, self.y):
                    self._erase(yy, 0, self.cols)
                self._erase(self.y, 0, self.x + 1)
            else:
                for yy in range(self.rows):
                    self._erase(yy, 0, self.cols)
        elif f == "K":
            mode = p[0]
            if mode == 0:
                self._erase(self.y, self.x, self.cols)
            elif mode == 1:
                self._erase(self.y, 0, self.x + 1)
            else:
                self._erase(self.y, 0, self.cols)
        elif f == "X":
            self._erase(self.y, self.x, min(self.cols, self.x + n))
        elif f == "m":
            self._sgr(p)
        elif f == "q" and s.endswith(" "):
            self.cursor_shape = p[0]
        elif f == "n":
            if p[0] == 6:
                self.replies += ("\x1b[%d;%dR" % (self.y + 1, self.x + 1)).encode()
            elif p[0] == 5:
                self.replies += b"\x1b[0n"
        elif f == "t":
            if p[0] == 18:
                self.replies += ("\x1b[8;%d;%dt" % (self.rows, self.cols)).encode()
            elif p[0] == 22:
                self.title_stack.append(self.title)
            elif p[0] == 23 and self.title_stack:
                self.title = self.title_stack.pop()
        elif f == "s":
            self.saved = (self.x, self.y)
        elif f == "u":
            self.x, self.y = self.saved
        else:
            self.log_errors.append("unhandled CSI %r %r" % (s, f))

    def _mode(self, m, on):
        self.modes[m] = on
        if m == 25:
            self.cursor_visible = on
        elif m == 7:
            self.autowrap = on
        elif m == 1049:
            if on and not self.on_alt:
                self.saved = (self.x, self.y)
                self.on_alt = True
                self.alt_entries += 1
                self.grid = self.alt
                for yy in range(self.rows):
                    self._erase(yy, 0, self.cols)
            elif not on and self.on_alt:
                self.on_alt = False
                self.grid = self.main
                self.x, self.y = self.saved

    def _sgr(self, p):
        i = 0
        while i < len(p):
            v = p[i]
            if v == 0:
                self.fg = self.bg = None
                self.attr = 0
            elif v in ATTR:
                self.attr |= 1 << list(ATTR).index(v)
            elif v == 22:
                self.attr &= ~3
            elif v == 23:
                self.attr &= ~(1 << 2)
            elif v == 24:
                self.attr &= ~(1 << 3)
            elif v == 27:
                self.attr &= ~(1 << 5)
            elif 30 <= v <= 37:
                self.fg = ("i", v - 30)
            elif 90 <= v <= 97:
                self.fg = ("i", v - 90 + 8)
            elif 40 <= v <= 47:
                self.bg = ("i", v - 40)
            elif 100 <= v <= 107:
                self.bg = ("i", v - 100 + 8)
            elif v == 39:
                self.fg = None
            elif v == 49:
                self.bg = None
            elif v in (38, 48):
                if i + 2 < len(p) and p[i + 1] == 5:
                    col = ("i", p[i + 2])
                    i += 2
                elif i + 4 < len(p) and p[i + 1] == 2:
                    col = ("rgb", p[i + 2], p[i + 3], p[i + 4])
                    i += 4
                else:
                    col = None
                if v == 38:
                    self.fg = col
                else:
                    self.bg = col
            else:
                self.log_errors.append("unhandled SGR %d" % v)
            i += 1

    # ---- reading the screen -------------------------------------------------------------------------------------------------------------
    def row_text(self, y):
        out = ""
        for c in self.grid[y]:
            out += c.ch + c.extra
        return out.rstrip()

    def text(self):
        return "\n".join(self.row_text(y) for y in range(self.rows)).rstrip("\n")

    def main_text(self):
        """The text of the main screen (what is there while the alternate screen is shown, or the scroll back of a shell)."""
        return "\n".join("".join(c.ch + c.extra for c in row).rstrip() for row in self.main).rstrip("\n")

    def cell(self, x, y):
        return self.grid[y][x]

    def find(self, text):
        """(x, y) of the first occurrence of text in a row, or None."""
        for y in range(self.rows):
            line = ""
            starts = []
            for x, c in enumerate(self.grid[y]):
                if c.ch == "":
                    continue
                starts.append(x)
                line += c.ch + c.extra
            i = line.find(text)
            if i >= 0:
                return (starts[i], y)
        return None


class Session:
    def __init__(self, argv, cols=80, rows=24, env=None, cwd=None, kernel_size=None):
        """kernel_size: what the system reports as the window size, (0, 0) for "unknown" (like a serial console); default: cols x rows."""
        self.cols, self.rows = cols, rows
        self.emu = Emu(cols, rows)
        self.raw_output = bytearray()
        master, slave = pty.openpty()
        kc, kr = kernel_size if kernel_size is not None else (cols, rows)
        self._set_size(slave, kc, kr)
        e = dict(os.environ)
        for k in ("TERM", "COLORTERM", "LANG", "LC_ALL", "LC_CTYPE", "NO_COLOR", "TUI_COLORS", "TUI_MOUSE", "TUI_ASCII", "TUI_PROBE", "TUI_MOTION", "TUI_SYNC", "LINES", "COLUMNS"):
            e.pop(k, None)
        e["TERM"] = "xterm-256color"
        e["COLORTERM"] = "truecolor"
        e["LANG"] = "C.UTF-8"
        e["PS1"] = "$ "
        if env:
            for k, v in env.items():
                if v is None:
                    e.pop(k, None)
                else:
                    e[k] = v

        def child_setup():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)

        self.proc = subprocess.Popen(argv, stdin=slave, stdout=slave, stderr=slave, close_fds=True, env=e, cwd=cwd, preexec_fn=child_setup)
        os.close(slave)
        self.master = master
        self.exited = None

    @staticmethod
    def _set_size(fd, cols, rows):
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

    # ---- io -------------------------------------------------------------------------------------------------------------------------------
    def pump(self, timeout=0.05):
        """Reads what the program wrote (waiting up to timeout seconds for the first bytes) and feeds the emulator."""
        end = time.time() + timeout
        got = False
        while True:
            left = max(0.0, end - time.time())
            r, _, _ = select.select([self.master], [], [], left)
            if not r:
                break
            try:
                data = os.read(self.master, 65536)
            except OSError:
                data = b""
            if not data:
                break
            got = True
            self.raw_output += data
            self.emu.feed(data)
            if self.emu.replies:
                os.write(self.master, bytes(self.emu.replies))
                self.emu.replies = bytearray()
            end = time.time() + 0.02
        if self.exited is None:
            rc = self.proc.poll()
            if rc is not None:
                self.exited = rc
        return got

    def wait_for(self, text, timeout=5.0, absent=False):
        """Waits until text is on the screen (or, with absent=True, no longer)."""
        end = time.time() + timeout
        while True:
            self.pump(0.05)
            present = self.emu.find(text) is not None
            if present != absent:
                return True
            if time.time() > end:
                return False

    def wait_idle(self, quiet=0.15, timeout=3.0):
        """Waits until the program has not written anything for a while."""
        end = time.time() + timeout
        last = time.time()
        while time.time() < end:
            if self.pump(0.03):
                last = time.time()
            elif time.time() - last > quiet:
                return

    def wait_exit(self, timeout=5.0):
        end = time.time() + timeout
        while time.time() < end:
            self.pump(0.05)
            if self.exited is not None:
                return self.exited
        return None

    def send(self, data):
        if isinstance(data, str):
            data = data.encode("utf-8")
        os.write(self.master, data)

    def key(self, data, settle=0.15):
        self.send(data)
        self.wait_idle(quiet=settle)

    def mouse(self, kind, x, y, button=0, mods=0):
        """kind: 'press', 'release', 'drag', 'wheel'. button: 0 left, 1 middle, 2 right; wheel: 64 up, 65 down."""
        b = button + mods
        if kind == "drag":
            b += 32
        final = "m" if kind == "release" else "M"
        self.send("\x1b[<%d;%d;%d%s" % (b, x + 1, y + 1, final))

    def click(self, x, y, button=0, settle=0.15):
        self.mouse("press", x, y, button)
        self.mouse("release", x, y, button)
        self.wait_idle(quiet=settle)

    def resize(self, cols, rows, settle=0.2):
        self.cols, self.rows = cols, rows
        self._set_size(self.master, cols, rows)
        self.emu.resize(cols, rows)
        try:
            os.killpg(os.getpgid(self.proc.pid), signal.SIGWINCH)
        except ProcessLookupError:
            pass
        self.wait_idle(quiet=settle)

    # ---- state ----------------------------------------------------------------------------------------------------------------------------
    def screen_text(self):
        return self.emu.text()

    def termios_flags(self):
        """(iflag, oflag, cflag, lflag) of the pty as the program sees it."""
        a = termios.tcgetattr(self.master)
        return a[0], a[1], a[2], a[3]

    def is_raw(self):
        l = self.termios_flags()[3]
        return (l & (termios.ICANON | termios.ECHO)) == 0

    def kill(self, sig):
        os.kill(self.proc.pid, sig)

    def close(self):
        try:
            if self.proc.poll() is None:
                self.proc.kill()
            self.proc.wait(timeout=2)
        except Exception:
            pass
        try:
            os.close(self.master)
        except OSError:
            pass
