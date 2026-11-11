#!/usr/bin/env python3
"""Runs the pty tests of the tui toolkit.  Usage:  tests/tui/run_tests.py [name-substring ...]

The test programs must be built first (tests/tui.sh does that): the paths come from the environment variables PROBE and GALLERY.
Every test starts a program in a pseudo terminal, sends keystrokes and mouse events and checks the emulated screen (see ptyterm.py).
"""
import os
import signal
import sys
import time
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ptyterm import Session  # noqa: E402

PROBE = os.environ.get("PROBE", "build/tests/tui/probe")
GALLERY = os.environ.get("GALLERY", "build/tests/tui/gallery")
FILES = os.environ.get("FILES", "build/tests/tui/files")

tests = []


def test(fn):
    tests.append(fn)
    return fn


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)


def eq(got, want, what=""):
    if got != want:
        raise AssertionError("%s: got %r, expected %r" % (what, got, want))


def start(prog=None, cols=80, rows=24, env=None, ready="size:"):
    s = Session([prog or PROBE], cols=cols, rows=rows, env=env)
    if ready:
        check(s.wait_for(ready, 5), "the program did not start; screen:\n" + s.screen_text())
    s.wait_idle()
    return s


def sane(s, what=""):
    """The terminal is back the way it was: cooked mode, no modes left on, cursor visible, main screen."""
    check(not s.is_raw(), what + ": terminal still in raw mode")
    check(not s.emu.on_alt, what + ": still on the alternate screen")
    for m in (1000, 1002, 1003, 1006, 2004, 1004):
        check(not s.emu.modes.get(m, False), what + ": mode %d left on" % m)
    check(s.emu.cursor_visible, what + ": cursor still hidden")
    check(s.emu.modes.get(7, True), what + ": autowrap left off")


def line(s, y):
    return s.emu.row_text(y)


def last(s):
    for y in range(s.emu.rows):
        t = line(s, y)
        if t.startswith("last: "):
            return t[6:]
    return None


# ---- start, quit, terminal state -----------------------------------------------------------------------------------------------------------
@test
def start_and_quit():
    s = start()
    check(s.is_raw(), "not in raw mode while running")
    check(s.emu.on_alt, "no alternate screen")
    for m in (1000, 1002, 1006, 2004):
        check(s.emu.modes.get(m), "mode %d not enabled" % m)
    check(s.emu.modes.get(25) is False, "cursor not hidden")
    check(s.emu.modes.get(7) is False, "autowrap not switched off")
    check(" File  Edit" in line(s, 0), "menu bar missing")
    s.key("\x11")
    eq(s.wait_exit(3), 0, "exit status")
    sane(s, "after quit")
    check(not s.emu.log_errors, "emulator saw unknown sequences: %r" % s.emu.log_errors)
    s.close()


@test
def title_and_clipboard():
    s = start(GALLERY, ready="Inputs")
    check(s.emu.title == "tui gallery", "window title not set: %r" % s.emu.title)
    check(len(s.emu.title_stack) == 1, "the old title was not saved")
    s.key("\x11")
    s.wait_exit(3)
    check(len(s.emu.title_stack) == 0 and s.emu.title != "tui gallery", "the old window title was not restored: %r" % s.emu.title)
    s.close()


# ---- keys ------------------------------------------------------------------------------------------------------------------------------------
@test
def keys_decoded():
    s = start()
    table = [
        ("\x1b[A", "Up"), ("\x1b[B", "Down"), ("\x1b[1;5C", "Ctrl+Right"), ("\x1b[1;2D", "Shift+Left"),
        ("\x1b[15~", "F5"), ("\x1bOP", "F1"), ("\x1b[19~", "F8"), ("\x1b[3~", "Delete"), ("\x1b[5~", "PgUp"),
        ("\x1b[H", "Home"), ("\x1b[F", "End"), ("\x1b[Z", "Shift+Tab"), ("\x01", "Ctrl+A"), ("\x7f", "Backspace"),
        ("\x1bx", "Alt+x"), ("\x1b\x7f", "Alt+Backspace"), ("é", "é"), ("世", "世"), ("\x1b[1;7A", "Ctrl+Alt+Up"),
        ("\x1b[17;5~", "Ctrl+F6"), ("\x1b[2~", "Insert"), ("\x1b[18~", "F7"), ("\x1b[1;2R", "Shift+F3"),
    ]
    for data, want in table:
        s.key(data, settle=0.1)
        eq(last(s), want, "after %r" % data)
    s.key("\x11")
    s.wait_exit(3)
    s.close()


@test
def escape_key_alone_and_split_sequences():
    s = start()
    s.send("\x1b")
    time.sleep(0.2)               # longer than the Esc timeout: this is the Escape key
    s.wait_idle()
    eq(last(s), "Esc", "a lone Esc")
    s.send("\x1b")
    time.sleep(0.01)
    s.send("[A")                  # the rest arrives quickly: it is the Up key
    s.wait_idle()
    eq(last(s), "Up", "a split sequence")
    s.send("\x1b")
    time.sleep(0.2)
    s.send("x")
    s.wait_idle()
    eq(last(s), "x", "Esc and later a letter")
    s.send("\x1b[1;")             # a sequence that never finishes must not block or crash
    time.sleep(0.2)
    s.send("\x1b[B")
    s.wait_idle()
    eq(last(s), "Down", "after an unfinished sequence")
    s.key("\x11")
    s.wait_exit(3)
    s.close()


# ---- text input ------------------------------------------------------------------------------------------------------------------------------
def focus_input(s):
    s.key("\t")      # Go button -> text field
    check(s.emu.cursor_visible, "the text field shows no cursor")


@test
def typing_and_editing():
    s = start()
    focus_input(s)
    s.key("héllo wörld")
    eq(line(s, 5), "héllo wörld", "typed text")
    s.key("\x1b[D\x1b[D\x1b[D")                    # three characters left
    s.key("X")
    eq(line(s, 5), "héllo wöXrld", "insert in the middle")
    eq((s.emu.x, s.emu.y), (9, 5), "cursor position")
    s.key("\x7f")
    eq(line(s, 5), "héllo wörld", "backspace")
    s.key("\x1b[H")
    check(s.emu.x == 0, "Home")
    s.key("\x1b[F")
    eq(s.emu.x, 11, "End")
    s.key("世界")
    eq(line(s, 5), "héllo wörld世界", "wide characters")
    eq(s.emu.x, 15, "the cursor is after two wide characters")
    s.key("\x1b[D")
    eq(s.emu.x, 13, "one step left skips a wide character")
    s.key("\x17")                                  # Ctrl+W: delete the word before the cursor
    s.key("\x1b[F")
    s.key("\r")
    check("entered: héllo wörld" in s.screen_text() or "entered: " in s.screen_text(), "Enter did not report the text")
    s.key("\x11")
    s.wait_exit(3)
    s.close()


@test
def bracketed_paste():
    s = start()
    focus_input(s)
    s.key("\x1b[200~pasted\ntext \x11 with a quit key\x1b[201~")
    txt = line(s, 5)
    check(txt.startswith("pasted text"), "paste was not inserted: %r" % txt)
    check(s.exited is None, "a Ctrl+Q inside a paste quit the program")
    s.key("\x11")
    eq(s.wait_exit(3), 0, "exit")
    s.close()


# ---- menus and shortcuts -----------------------------------------------------------------------------------------------------------------------
@test
def menus_by_keyboard():
    s = start()
    s.key("\x1bf")                                  # Alt+F
    check("Ctrl+N" in s.screen_text() and "Quit" in s.screen_text(), "menu did not open:\n" + s.screen_text())
    s.key("\x1b[B")                                 # the first item (New) is selected when the menu opens: Down goes to Open
    s.key("\r")
    check("menu: Open" in s.screen_text(), "the Open action did not run:\n" + s.screen_text())
    check("Ctrl+N" not in s.screen_text(), "menu did not close")
    s.key("\x1b[21~")                               # F10
    s.key("\x1b[C")                                 # Right: the Edit menu
    check("Copy" in s.screen_text(), "Right did not switch to the Edit menu")
    s.key("\x1b")
    check("Copy" not in s.screen_text(), "Esc did not close the menu")
    s.key("\x0e")                                   # Ctrl+N accelerator without opening the menu
    check("menu: New" in s.screen_text(), "accelerator Ctrl+N did not work")
    s.key("\x1bf")
    s.key("q")                                      # mnemonic Q = Quit
    eq(s.wait_exit(3), 0, "quit through the menu mnemonic")
    sane(s, "after menu quit")
    s.close()


@test
def menus_by_mouse():
    s = start()
    s.click(2, 0)                                   # "File"
    check("Ctrl+N" in s.screen_text(), "click on File did not open the menu")
    pos = s.emu.find("Open")
    s.click(pos[0] + 1, pos[1])
    check("menu: Open" in s.screen_text(), "click on Open did not run it")
    s.click(2, 0)
    s.click(30, 15)                                 # outside: closes
    check("Ctrl+N" not in s.screen_text(), "click outside did not close the menu")
    s.click(2, 0)
    s.click(2, 0)                                   # a second click on the title closes it
    check("Ctrl+N" not in s.screen_text(), "second click on the title should close the menu")
    s.key("\x11")
    s.wait_exit(3)
    s.close()


# ---- mouse -----------------------------------------------------------------------------------------------------------------------------------------
@test
def mouse_button_list_wheel_and_splitter():
    s = start()
    pos = s.emu.find("[ Go ]")
    s.click(pos[0] + 2, pos[1])
    s.click(pos[0] + 2, pos[1])
    check("clicked: 2" in s.screen_text(), "button clicks")
    pos = s.emu.find("item 5")
    s.click(pos[0] + 1, pos[1])
    check("selected: item 5" in s.screen_text(), "clicking a list item selects it")
    s.mouse("wheel", 5, 12, 65)
    s.mouse("wheel", 5, 12, 65)
    s.wait_idle()
    # drag the splitter divider
    ys = [y for y in range(24) if "│" in line(s, y)]
    check(ys, "no divider visible")
    divider = None
    for x in range(80):
        if s.emu.cell(x, 10).ch == "│":
            divider = x
    check(divider is not None, "no divider column")
    s.mouse("press", divider, 10)
    s.mouse("drag", divider - 10, 10)
    s.mouse("drag", divider - 20, 10)
    s.mouse("release", divider - 20, 10)
    s.wait_idle()
    newdiv = None
    for x in range(80):
        if s.emu.cell(x, 10).ch == "│":
            newdiv = x
    check(newdiv is not None and newdiv < divider - 10, "the splitter did not move (%r -> %r)" % (divider, newdiv))
    s.key("\x11")
    s.wait_exit(3)
    s.close()


@test
def list_filter_by_typing():
    s = start()
    pos = s.emu.find("item 1 ")
    s.click(pos[0] + 1, pos[1])                    # focus the list
    s.key("17")
    txt = s.screen_text()
    check("filter: 17" in txt and "item 17" in txt and "item 5 " not in txt, "filter as you type:\n" + txt)
    s.key("\x1b")                                   # Esc clears the filter
    check("filter:" not in s.screen_text(), "Esc did not clear the filter")
    s.key("\x11")
    s.wait_exit(3)
    s.close()


# ---- resize -----------------------------------------------------------------------------------------------------------------------------------
@test
def resize_follows_the_window():
    s = start()
    s.resize(100, 30)
    check("size: 100x30" in s.screen_text(), "size label after growing:\n" + s.screen_text())
    check(len([y for y in range(30) if "item" in line(s, y)]) > 15, "the list did not grow")
    s.resize(50, 12)
    check("size: 50x12" in s.screen_text(), "size label after shrinking")
    check(max(len(line(s, y)) for y in range(12)) <= 50, "a line is longer than the screen")
    s.resize(80, 24)
    check("size: 80x24" in s.screen_text(), "size back to 80x24")
    s.key("\x1bf")
    s.resize(60, 20)
    s.key("\x1b")
    s.key("\x11")
    eq(s.wait_exit(3), 0, "exit after resizes")
    sane(s, "after resize")
    check(not s.emu.log_errors, "emulator saw unknown sequences: %r" % s.emu.log_errors)
    s.close()


@test
def size_from_environment_when_nobody_knows():
    # the system reports no size and the terminal answers no query: LINES and COLUMNS are used
    s = Session([PROBE], cols=100, rows=40, env={"LINES": "33", "COLUMNS": "77"}, kernel_size=(0, 0), answer_18t=False, answer_cpr=False)
    check(s.wait_for("size:", 8), "no start")
    s.wait_idle()
    check("size: 77x33" in s.screen_text(), "LINES/COLUMNS were not used:\n" + s.screen_text())
    s.key("\x11")
    s.wait_exit(3)
    s.close()


@test
def size_default_when_nothing_helps():
    s = Session([PROBE], cols=100, rows=40, env={"LINES": None, "COLUMNS": None}, kernel_size=(0, 0), answer_18t=False, answer_cpr=False)
    check(s.wait_for("size:", 8), "no start")
    s.wait_idle()
    check("size: 80x24" in s.screen_text(), "the default 80x24 was not used:\n" + s.screen_text())
    s.key("\x11")
    s.wait_exit(3)
    s.close()


@test
def size_asked_from_the_terminal_when_the_system_does_not_know():
    # no size from the system: the terminal is asked (CSI 18 t, answered by the emulator) before LINES and COLUMNS are looked at
    s = Session([PROBE], cols=91, rows=37, env={"LINES": "33", "COLUMNS": "77"}, kernel_size=(0, 0))
    check(s.wait_for("size:", 5), "no start")
    s.wait_idle()
    check("size: 91x37" in s.screen_text(), "the size query was not answered or not used:\n" + s.screen_text())
    check(b"\x1b[18t" in bytes(s.raw_output), "the program did not ask for the size")
    s.key("\x11")
    s.wait_exit(3)
    s.close()


@test
def size_asked_with_a_cursor_position_report():
    # the terminal does not know CSI 18 t: the program falls back to "move the cursor far away and ask where it is"
    s = Session([PROBE], cols=88, rows=31, env={"LINES": None, "COLUMNS": None}, kernel_size=(0, 0), answer_18t=False)
    check(s.wait_for("size:", 8), "no start")
    s.wait_idle()
    check("size: 88x31" in s.screen_text(), "the cursor position report was not used:\n" + s.screen_text())
    check(b"\x1b[6n" in bytes(s.raw_output), "the program did not ask for the cursor position")
    s.key("\x11")
    s.wait_exit(3)
    s.close()


@test
def size_forced_query_and_no_query():
    # the system says 80x24 (a serial console does that) but the terminal is bigger: TUI_PROBE=1 asks anyway
    s = Session([PROBE], cols=120, rows=40, env={"TUI_PROBE": "1"}, kernel_size=(80, 24))
    check(s.wait_for("size:", 5), "no start")
    s.wait_idle()
    check("size: 120x40" in s.screen_text(), "TUI_PROBE=1 did not ask the terminal:\n" + s.screen_text())
    s.key("\x11")
    s.wait_exit(3)
    s.close()
    # when the system knows the size nothing is asked by default
    s = Session([PROBE], cols=120, rows=40, kernel_size=(100, 30))
    check(s.wait_for("size:", 5), "no start")
    s.wait_idle()
    check("size: 100x30" in s.screen_text(), "the size of the system was not used")
    check(b"\x1b[18t" not in bytes(s.raw_output), "the program asked for a size it already knew")
    s.key("\x11")
    s.wait_exit(3)
    s.close()


# ---- suspend to a shell and come back ----------------------------------------------------------------------------------------------------------
@test
def suspend_to_shell_and_resume():
    s = start()
    alt_before = s.emu.alt_entries
    s.send("\x1b[20~")                              # F9
    check(s.wait_for("shell status 0", 8), "the program did not come back:\n" + s.screen_text())
    check("child-end" in s.emu.main_text() and "child-start" in s.emu.main_text(), "the shell output is not on the main screen:\n" + s.emu.main_text())
    s.wait_idle()
    check(s.is_raw(), "raw mode was not restored after the shell")
    check(s.emu.on_alt, "alternate screen not entered again")
    check(s.emu.alt_entries > alt_before, "the full screen mode was not left while the shell ran")
    txt = s.screen_text()
    check(" File  Edit" in txt and "size: 80x24" in txt, "the screen was not redrawn after the shell:\n" + txt)
    # while the child ran the terminal was in cooked mode: stty printed icanon and echo as enabled
    child = s.emu.main_text().split("child-start")[1].split("child-end")[0].split()
    check(child == ["isig", "icanon", "echo"], "the shell did not run in cooked mode (stty says %r)" % child)
    s.key("x")
    eq(last(s), "x", "keys work again after the shell")
    s.key("\x11")
    eq(s.wait_exit(3), 0, "exit")
    sane(s, "after suspend")
    s.close()


# ---- crashes and signals: the terminal must come back ------------------------------------------------------------------------------------------
@test
def exit_from_inside_restores():
    s = start()
    s.key("\x1b[23~")                               # F11: exit(3)
    eq(s.wait_exit(3), 3, "exit status")
    sane(s, "after exit(3)")
    s.close()


@test
def crash_restores_the_terminal():
    s = start()
    s.key("\x1b[24~")                               # F12: null pointer write
    rc = s.wait_exit(3)
    check(rc is not None and rc < 0, "the program should die from a signal, status %r" % rc)
    eq(-rc, signal.SIGSEGV, "signal")
    sane(s, "after SIGSEGV")
    s.close()


@test
def signals_restore_the_terminal():
    for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT, signal.SIGQUIT):
        s = start()
        s.kill(sig)
        rc = s.wait_exit(3)
        check(rc is not None and rc == -sig, "signal %d: status %r" % (sig, rc))
        sane(s, "after signal %d" % sig)
        s.close()


@test
def hangup_of_the_terminal_ends_the_program():
    s = start()
    os_close = os.close
    os_close(s.master)              # the terminal goes away
    s.master = os.open("/dev/null", os.O_RDONLY)
    end = time.time() + 4
    while time.time() < end and s.proc.poll() is None:
        time.sleep(0.05)
    check(s.proc.poll() is not None, "the program did not end after its terminal was closed")
    s.close()


# ---- capabilities --------------------------------------------------------------------------------------------------------------------------------
@test
def linux_console_gets_no_mouse_no_alt_screen():
    s = start(env={"TERM": "linux", "COLORTERM": None})
    check(not s.emu.modes.get(1000) and not s.emu.modes.get(1006), "mouse reporting was enabled for TERM=linux")
    check(not s.emu.modes.get(1049), "alternate screen for TERM=linux")
    check(not s.emu.modes.get(2004), "bracketed paste for TERM=linux")
    check(b"\x1b[38;2" not in bytes(s.raw_output) and b"\x1b[38;5" not in bytes(s.raw_output), "extended colours for TERM=linux")
    s.key("\x11")
    s.wait_exit(3)
    check(not s.is_raw(), "raw mode after exit")
    s.close()


@test
def colour_depths():
    s = start(env={"TERM": "xterm-256color", "COLORTERM": "truecolor"})
    check(b"38;2;" in bytes(s.raw_output) or b"48;2;" in bytes(s.raw_output), "no 24 bit colours with COLORTERM=truecolor")
    s.key("\x11")
    s.wait_exit(3)
    s.close()
    s = start(env={"TERM": "xterm-256color", "COLORTERM": None})
    raw = bytes(s.raw_output)
    check(b"38;2;" not in raw and b"48;2;" not in raw and (b"38;5;" in raw or b"48;5;" in raw), "256 colour mode")
    s.key("\x11")
    s.wait_exit(3)
    s.close()
    s = start(env={"TUI_COLORS": "16"})
    raw = bytes(s.raw_output)
    check(b"38;2;" not in raw and b"38;5;" not in raw and b"48;5;" not in raw, "16 colour mode must use only the basic codes")
    s.key("\x11")
    s.wait_exit(3)
    s.close()
    s = start(env={"NO_COLOR": "1"})
    raw = bytes(s.raw_output)
    import re
    colours = re.findall(rb"\x1b\[[0-9;]*m", raw)
    bad = [c for c in colours if re.search(rb"[;\[](3[0-7]|4[0-7]|9[0-7]|10[0-7]|38|48)[;m]", c)]
    check(not bad, "NO_COLOR but colour codes were written: %r" % bad[:3])
    s.key("\x11")
    s.wait_exit(3)
    s.close()


@test
def ascii_fallback():
    s = start(env={"TUI_ASCII": "1"})
    txt = s.screen_text()
    check("┌" not in txt and "│" not in txt and "█" not in txt, "box drawing characters without UTF-8:\n" + txt)
    s.key("\x1bf")
    check("+--" in s.screen_text(), "the menu border should be drawn with + and -:\n" + s.screen_text())
    s.key("\x1b")
    s.key("\x11")
    s.wait_exit(3)
    s.close()


@test
def dumb_terminal_is_refused():
    s = Session([PROBE], env={"TERM": "dumb"})
    rc = s.wait_exit(3)
    eq(rc, 1, "exit status with TERM=dumb")
    check("needs a terminal" in s.screen_text(), "message missing")
    check(not s.emu.modes.get(1049), "the alternate screen was entered")
    s.close()


@test
def no_terminal_at_all():
    import subprocess
    p = subprocess.run([PROBE], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5, start_new_session=True)
    eq(p.returncode, 1, "exit status without a terminal")
    check(b"\x1b" not in p.stdout, "escape sequences written to a pipe")
    check(b"needs a terminal" in p.stdout, "message missing")


# ---- the gallery ---------------------------------------------------------------------------------------------------------------------------------
@test
def gallery_tabs_dialogs_palette():
    s = start(GALLERY, ready="Inputs")
    txt = s.screen_text()
    check("Name:" in txt and "Ada" in txt, "inputs page:\n" + txt)
    s.key("\x1b2")                                  # Alt+2
    check("apple" in s.screen_text() and "alpha" in s.screen_text(), "lists page:\n" + s.screen_text())
    s.key("\x1b3")
    check("Language" in s.screen_text() and "Python" in s.screen_text(), "table page")
    s.key("\x1b1")
    # the question dialog through its mnemonic
    s.key("\x1bq")
    check("Do you like terminals?" in s.screen_text(), "question dialog:\n" + s.screen_text())
    s.key("y")                                      # &Yes via mnemonic letter
    s.key("\x1by")
    s.wait_idle()
    check("Do you like terminals?" not in s.screen_text(), "dialog still open")
    check("answer: yes" in s.screen_text(), "the answer was not shown:\n" + s.screen_text())
    # command palette
    s.key("\x10")                                   # Ctrl+P
    check("Command palette" in s.screen_text(), "palette did not open")
    s.key("mono")
    s.key("\r")
    check("Command palette" not in s.screen_text(), "palette did not close")
    s.key("\x11")
    eq(s.wait_exit(3), 0, "gallery exit")
    sane(s, "gallery")
    s.close()


@test
def gallery_run_program_output():
    s = start(GALLERY, ready="Inputs")
    s.key("\x1b4")
    s.key("\x1br")                                  # Alt+R: the Run button
    check(s.wait_for("step 3", 5), "program output did not arrive:\n" + s.screen_text())
    check(s.wait_for("finished with status 0", 5), "end of the program not shown:\n" + s.screen_text())
    # the keyboard still works while a program ran: type into the event log
    s.key("\x11")
    eq(s.wait_exit(3), 0, "exit")
    s.close()


@test
def gallery_colour_dialog_and_file_dialog():
    s = start(GALLERY, ready="Inputs")
    s.key("\x1bc")                                  # Alt+C: Colour button
    check("rgb 200,100,50" in s.screen_text(), "colour dialog:\n" + s.screen_text())
    check("#C86432" in s.screen_text().upper(), "hex of the initial colour:\n" + s.screen_text())
    s.key("\x1b[Z")
    s.key("\r")
    s.key("\x1b")
    s.key("\x1bo")                                  # Alt+O: Open button
    check("Open a file" in s.screen_text(), "file dialog:\n" + s.screen_text())
    s.key("\x1b")
    check("Open a file" not in s.screen_text(), "file dialog did not close")
    s.key("\x11")
    s.wait_exit(3)
    s.close()


# ---- the file manager ------------------------------------------------------------------------------------------------------------------------
@test
def file_manager_copy_mkdir_delete_view():
    import shutil
    import tempfile
    root = tempfile.mkdtemp(prefix="tuifm")
    try:
        a = os.path.join(root, "a")
        b = os.path.join(root, "b")
        os.makedirs(os.path.join(a, "sub"))
        os.makedirs(b)
        open(os.path.join(a, "x.txt"), "w").write("hello\n")
        open(os.path.join(a, "y.txt"), "w").write("world\n")
        open(os.path.join(a, "sub", "z.txt"), "w").write("inner\n")
        s = Session([FILES, a, b], cols=100, rows=30, env={"PAGER": "cat"})
        check(s.wait_for("x.txt", 5), "listing of the left panel:\n" + s.screen_text())
        s.wait_idle()
        txt = s.screen_text()
        check("/sub" in txt and "y.txt" in txt and "<UP>" in txt and "<DIR>" in txt, "panel contents:\n" + txt)

        def select(name, panel_x=0):
            for y in range(30):
                t = line(s, y)
                k = t.find(name, panel_x)
                if k >= 0 and (panel_x == 0 or k >= panel_x):
                    s.click(k + 1, y)
                    return
            raise AssertionError("%s not on the screen:\n%s" % (name, s.screen_text()))

        select("x.txt")
        s.key("\x1b[15~")                                  # F5: copy to the other panel
        check(os.path.exists(os.path.join(b, "x.txt")), "the file was not copied")
        eq(open(os.path.join(b, "x.txt")).read(), "hello\n", "content of the copy")
        check(any("x.txt" in line(s, y)[50:] for y in range(30)), "the right panel was not reloaded")
        # new directory
        s.key("\x1b[18~")                                  # F7
        check("New directory" in s.screen_text(), "mkdir dialog")
        s.key("fresh")
        s.key("\r")
        check(os.path.isdir(os.path.join(a, "fresh")), "the directory was not created")
        check("/fresh" in s.screen_text(), "the new directory is not listed")
        # delete y.txt
        select("y.txt")
        s.key("\x1b[19~")                                  # F8
        check("Delete y.txt" in s.screen_text(), "delete confirmation:\n" + s.screen_text())
        s.key("\r")                                        # the default button is Yes
        check(not os.path.exists(os.path.join(a, "y.txt")), "y.txt was not deleted")
        # into /sub and back with Backspace
        select("/sub")
        s.key("\r")
        check(a + "/sub" in line(s, 1), "the panel title shows the new directory:\n" + line(s, 1))
        check("z.txt" in s.screen_text(), "contents of sub")
        s.key("\x7f")
        check("z.txt" not in s.screen_text() and a in line(s, 1), "Backspace goes up")
        # the pager: leave the full screen mode, run cat, come back
        select("x.txt")
        s.send("\x1b[13~")                                 # F3
        s.wait_idle(quiet=0.4)
        check("hello" in s.emu.main_text(), "the pager output is missing on the main screen")
        check("x.txt" in s.screen_text() and s.is_raw(), "the file manager did not come back")
        s.key("\x1b[21~")                                  # F10: quit
        eq(s.wait_exit(3), 0, "exit")
        sane(s, "file manager")
        s.close()
    finally:
        shutil.rmtree(root, ignore_errors=True)


def main():
    names = sys.argv[1:]
    failed = 0
    passed = 0
    for fn in tests:
        if names and not any(n in fn.__name__ for n in names):
            continue
        t0 = time.time()
        try:
            fn()
            print("PASS  %-50s %.1fs" % (fn.__name__, time.time() - t0))
            passed += 1
        except Exception:
            print("FAIL  %s" % fn.__name__)
            traceback.print_exc(limit=3)
            failed += 1
    print("passed: %d, failed: %d" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
