#!/usr/bin/env python3
"""Real processes: adisplayd (display server with VNC and control), hello and calc (clients), driven through the VNC
backend (pointer, keyboard, screen grabs) and through actl (screenshot / input injection)."""
import os, subprocess, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rfbclient import Rfb

bindir = sys.argv[1]
port_vnc = 5909
env = dict(os.environ, ADISPLAY="9")
procs = []

def start(name, *args):
    p = subprocess.Popen([os.path.join(bindir, name)] + list(args), env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    procs.append(p)
    return p

def fail(msg):
    print("FAIL:", msg)
    for p in procs:
        p.kill()
    sys.exit(1)

try:
    start("adisplayd", "-p", "9", "-vnc", str(port_vnc), "-control", "-size", "800x600")
    c = None
    for _ in range(50):
        try:
            c = Rfb(port=port_vnc)
            break
        except OSError:
            time.sleep(0.1)
    if c is None:
        fail("cannot connect to the VNC server")
    if (c.w, c.h) != (800, 600):
        fail("screen size %dx%d" % (c.w, c.h))
    c.grab()
    top, bottom = c.pixel(100, 5), c.pixel(100, 590)
    if not (top[2] > bottom[2] and top[1] > bottom[1]):
        fail("the background is not a gradient: %s %s" % (top, bottom))
    print("vnc connected, background ok")

    # hello: click the button through VNC
    start("hello")
    time.sleep(0.6)
    c.grab()
    box = c.find_color((60, 120, 216))
    if not box:
        fail("the primary button of hello was not found")
    cx, cy = (box[0] + box[2]) // 2, (box[1] + box[3]) // 2
    def label_area():
        out = b""
        for y in range(box[1] - 28, box[1] - 10):
            out += bytes(c.fb[(y * c.w + box[0]) * 4:(y * c.w + box[0] + 200) * 4])
        return out
    label_before = label_area()
    c.click(cx, cy)
    time.sleep(0.4)
    c.grab()
    label_after = label_area()
    if label_before == label_after:
        fail("the label did not change after the click")
    print("button click through VNC ok")

    # drag the window by its title bar (the title bar is dark blue while focused)
    tb = c.find_color((82, 124, 214), tol=40)
    if not tb:
        fail("title bar not found")
    c.pointer(tb[0] + 20, tb[1] + 6, 0)
    c.pointer(tb[0] + 20, tb[1] + 6, 1)
    c.pointer(tb[0] + 120, tb[1] + 66, 1)
    c.pointer(tb[0] + 120, tb[1] + 66, 0)
    time.sleep(0.3)
    c.grab()
    tb2 = c.find_color((82, 124, 214), tol=40)
    if not tb2 or abs((tb2[0] - tb[0]) - 100) > 3 or abs((tb2[1] - tb[1]) - 60) > 3:
        fail("window did not move by (100, 60): %s -> %s" % (tb, tb2))
    print("window drag ok")

    # calc: the keyboard through VNC
    start("calc")
    time.sleep(0.6)
    c.type_text("12*7+5=")
    time.sleep(0.5)
    c.grab()
    vnc_png = bytes(c.fb)

    # actl takes the same screenshot through the display protocol
    shot = os.path.join(bindir, "shot.ppm")
    r = subprocess.run([os.path.join(bindir, "actl"), "-d", "9", "shot", shot], env=env, capture_output=True, text=True, timeout=20)
    if r.returncode != 0:
        fail("actl shot: " + r.stdout + r.stderr)
    data = open(shot, "rb").read()
    hdr_end = data.index(b"255\n") + 4
    pix = data[hdr_end:]
    same = 0
    total = 0
    for i in range(0, c.w * c.h, 7):
        total += 1
        if pix[i * 3:i * 3 + 3] == bytes((vnc_png[i * 4 + 2], vnc_png[i * 4 + 1], vnc_png[i * 4])):
            same += 1
    # the clock-less desktop is static, so the two screenshots are the same (the pointer is drawn into both)
    if same != total:
        fail("actl screenshot differs from the VNC screen (%d of %d samples)" % (same, total))
    print("actl screenshot matches the VNC screen")

    # actl injects input: type into calc and compare with a typing session through VNC
    r = subprocess.run([os.path.join(bindir, "actl"), "-d", "9", "type", "9"], env=env, capture_output=True, text=True, timeout=20)
    if r.returncode != 0:
        fail("actl type: " + r.stdout + r.stderr)
    time.sleep(0.4)
    c.grab()
    if bytes(c.fb) == vnc_png:
        fail("typing with actl changed nothing")
    print("actl input ok")

    # apanel: a taskbar at the bottom of the screen, with a button for every window; clicking the focused window's button minimizes it
    start("apanel")
    time.sleep(1.0)
    c.grab()
    panel_color = c.pixel(400, 595)
    if abs(panel_color[0] - 226) > 3 or abs(panel_color[2] - 236) > 3:
        fail("the taskbar was not found at the bottom: %s" % (panel_color,))
    print("taskbar ok")
    start("calc")
    time.sleep(1.0)
    c.grab()
    # the button of the newest (focused) window is blue: click it and the window goes away (the screen changes)
    btn = None
    for x in range(0, 700, 4):
        p = c.pixel(x, 582)
        if abs(p[0] - 60) < 8 and abs(p[1] - 120) < 8 and abs(p[2] - 216) < 8:
            btn = x
            break
    if btn is None:
        fail("the task button of the focused window was not found")
    before = bytes(c.fb)
    c.click(btn + 10, 582)
    time.sleep(0.8)
    c.grab()
    if bytes(c.fb) == before:
        fail("clicking the task button changed nothing")
    c.click(btn + 10, 582)
    time.sleep(0.8)
    c.grab()
    print("task button ok")

    # aterm: a shell on a pseudo terminal. Keys typed through VNC reach the shell, and when it ends the window and the program go away
    term = start("aterm")
    time.sleep(1.2)
    c.grab()
    if not c.find_color((20, 24, 28), tol=2):
        fail("the terminal window (dark background) was not found")
    c.type_text("exit")
    c.key(0xff0d, 1)
    c.key(0xff0d, 0)
    for _ in range(50):
        if term.poll() is not None:
            break
        time.sleep(0.1)
    if term.poll() != 0:
        fail("aterm did not end after exit was typed (%s)" % term.poll())
    print("terminal shell ok")
    term2 = start("aterm", "exit", "0")
    for _ in range(50):
        if term2.poll() is not None:
            break
        time.sleep(0.1)
    if term2.poll() != 0:
        fail("aterm with a command did not end (%s)" % term2.poll())
    print("terminal command ok")

    # a second display with the screen locker: a wrong password keeps it locked, the right one removes it
    env2 = dict(os.environ, ADISPLAY="10")
    def start2(name, *args):
        p = subprocess.Popen([os.path.join(bindir, name)] + list(args), env=env2, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        procs.append(p)
        return p
    users = os.path.join(bindir, "users.txt")
    h = subprocess.run(["openssl", "passwd", "-6", "-salt", "abcdefgh", "hunter2"], capture_output=True, text=True).stdout.strip()
    open(users, "w").write("aleksi:%s:1000:1000:/home/aleksi:/bin/sh\n" % h)
    start2("adisplayd", "-p", "10", "-vnc", "5910", "-control", "-size", "800x600")
    c2 = None
    for _ in range(50):
        try:
            c2 = Rfb(port=5910)
            break
        except OSError:
            time.sleep(0.1)
    if c2 is None:
        fail("cannot connect to the second VNC server")
    start2("hello")
    time.sleep(0.6)
    c2.grab()
    card_spot = (260, 300)
    before = c2.pixel(*card_spot)
    box2 = c2.find_color((60, 120, 216))
    if not box2:
        fail("hello button not found on display 10")
    lock = start2("alock", "-d", "10", "-u", users, "aleksi")
    time.sleep(1.0)
    c2.grab()
    after = c2.pixel(*card_spot)
    if after == before or abs(after[0] - 238) > 3:
        fail("the lock screen card is not there: %s -> %s" % (before, after))
    print("screen locked")
    c2.click((box2[0] + box2[2]) // 2, (box2[1] + box2[3]) // 2)
    time.sleep(0.3)
    c2.type_text("wrongpw")
    c2.key(0xff0d, 1)
    c2.key(0xff0d, 0)
    time.sleep(0.5)
    if lock.poll() is not None:
        fail("the locker quit after a wrong password")
    print("wrong password rejected")
    time.sleep(1.2)
    c2.type_text("hunter2")
    c2.key(0xff0d, 1)
    c2.key(0xff0d, 0)
    for _ in range(40):
        if lock.poll() is not None:
            break
        time.sleep(0.1)
    if lock.poll() != 0:
        fail("the locker did not end after the right password (%s)" % lock.poll())
    time.sleep(0.4)
    c2.grab()
    if c2.pixel(*card_spot) != before:
        fail("the screen is not back after unlocking")
    print("unlocked")
    print("ok")
finally:
    for p in procs:
        p.kill()
