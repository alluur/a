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

    # a protected display: cookie authentication for clients and a VNC password
    from rfbclient import AuthFailed
    cookie_file = os.path.join(bindir, "cookie.txt")
    pass_file = os.path.join(bindir, "vncpass.txt")
    if os.path.exists(cookie_file):
        os.remove(cookie_file)
    open(pass_file, "w").write("s3cret99\n")
    env3 = dict(os.environ, ADISPLAY="11")
    p3 = subprocess.Popen([os.path.join(bindir, "adisplayd"), "-p", "11", "-vnc", "5911", "-control", "-size", "640x400",
                           "-cookie", cookie_file, "-newcookie", "-vncpass", pass_file], env=env3, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    procs.append(p3)
    time.sleep(0.8)
    if oct(os.stat(cookie_file).st_mode & 0o777) != "0o600":
        fail("the cookie file is not mode 600")
    # VNC: no password and a wrong password are refused, the right one works
    try:
        Rfb(port=5911)
        fail("the VNC server accepted a viewer without a password")
    except (AssertionError, OSError):
        pass
    time.sleep(1.2)
    try:
        Rfb(port=5911, password="wrongpw")
        fail("the VNC server accepted a wrong password")
    except AuthFailed:
        pass
    time.sleep(1.3)
    v = Rfb(port=5911, password="s3cret99")
    if (v.w, v.h) != (640, 400):
        fail("protected VNC screen size")
    print("vnc password ok")
    # display clients: no cookie and a wrong cookie are refused; the right cookie lets hello and actl in
    def run3(prog, extra, *args, timeout=10):
        e = dict(env3)
        e.update(extra)
        return subprocess.run([os.path.join(bindir, prog)] + list(args), env=e, capture_output=True, text=True, timeout=timeout)
    r = run3("actl", {"HOME": "/nonexistent"}, "-d", "11", "shot", os.path.join(bindir, "p3.ppm"))
    if r.returncode == 0 or "cookie" not in r.stdout:
        fail("actl without a cookie: " + r.stdout)
    r = run3("actl", {"ADISPLAY_COOKIE": "00112233445566778899aabbccddeeff"}, "-d", "11", "shot", os.path.join(bindir, "p3.ppm"))
    if r.returncode == 0:
        fail("actl with a wrong cookie got in")
    r = run3("hello", {"HOME": "/nonexistent"})
    if r.returncode == 0:
        fail("hello without a cookie got in")
    r = run3("actl", {"ADISPLAY_COOKIE_FILE": cookie_file}, "-d", "11", "shot", os.path.join(bindir, "p3.ppm"))
    if r.returncode != 0:
        fail("actl with the cookie: " + r.stdout + r.stderr)
    hp = subprocess.Popen([os.path.join(bindir, "hello")], env=dict(env3, ADISPLAY_COOKIE_FILE=cookie_file), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    procs.append(hp)
    time.sleep(0.8)
    if hp.poll() is not None:
        fail("hello with the cookie ended")
    v.grab()
    if not v.find_color((60, 120, 216)):
        fail("hello with the cookie did not show its button")
    print("cookie authentication ok")
    # listening on all interfaces is only allowed with a cookie
    r = subprocess.run([os.path.join(bindir, "adisplayd"), "-p", "12", "-vnc", "5912", "-listen", "0.0.0.0"], capture_output=True, text=True, timeout=10)
    if r.returncode == 0 or "cookie" not in r.stderr:
        fail("adisplayd -listen without a cookie: " + r.stdout + r.stderr)
    print("listen needs a cookie ok")

    # the web backend: a browser-style client (HTTP + WebSocket) sees the same screen as VNC and controls it
    from webclient import WebDisplay
    import urllib.request, urllib.error
    env4 = dict(os.environ, ADISPLAY="13")
    p4 = subprocess.Popen([os.path.join(bindir, "adisplayd"), "-p", "13", "-vnc", "5913", "-web", "8093", "-webtoken", "webtok12345", "-control", "-size", "640x400"],
                          env=env4, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    procs.append(p4)
    time.sleep(0.8)
    page = urllib.request.urlopen("http://127.0.0.1:8093/?t=webtok12345", timeout=5).read().decode()
    if "<canvas" not in page or "webtok12345" not in page or "@TOKEN@" in page:
        fail("the web page is wrong")
    try:
        urllib.request.urlopen("http://127.0.0.1:8093/", timeout=5)
        fail("the page was served without the token")
    except urllib.error.HTTPError as e:
        if e.code != 403:
            fail("page without token: %s" % e.code)
    time.sleep(1.2)
    for token, origin, label in (("wrongtoken", "same", "wrong token"), ("webtok12345", "http://evil.example", "foreign origin")):
        try:
            WebDisplay(8093, token, origin=origin)
            fail("the web display accepted a " + label)
        except ConnectionRefusedError as e:
            if e.args[0] != 403:
                fail("%s: status %s" % (label, e.args[0]))
        time.sleep(1.5)
    hp4 = subprocess.Popen([os.path.join(bindir, "hello")], env=env4, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    procs.append(hp4)
    time.sleep(0.8)
    web = WebDisplay(8093, "webtok12345")
    web.pump(1.0)
    if (web.w, web.h) != (640, 400):
        fail("web display size %dx%d" % (web.w, web.h))
    vnc4 = Rfb(port=5913)
    vnc4.grab()
    same = total = 0
    for yy in range(0, 400, 7):
        for xx in range(0, 640, 5):
            total += 1
            if web.pixel(xx, yy) == vnc4.pixel(xx, yy):
                same += 1
    if same != total:
        fail("web and VNC show different screens (%d of %d samples)" % (same, total))
    print("web screen equals the VNC screen")
    box = web.find_color((60, 120, 216))
    if not box:
        fail("hello's button is not on the web screen")
    def label_area():
        return bytes(web.fb[((box[1] - 28) * web.w + box[0]) * 3:((box[1] - 10) * web.w + box[0]) * 3 + 600])
    before = label_area()
    web.click((box[0] + box[2]) // 2, (box[1] + box[3]) // 2)
    web.pump(1.0)
    if label_area() == before:
        fail("a click through the web display did nothing")
    print("web click ok")
    cp = subprocess.Popen([os.path.join(bindir, "calc")], env=env4, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    procs.append(cp)
    time.sleep(0.8)
    web.pump(0.5)
    snap = bytes(web.fb)
    web.type_text("12*7+5=")
    web.pump(1.0)
    if bytes(web.fb) == snap:
        fail("typing through the web display did nothing")
    vnc4.grab()
    same = total = 0
    for yy in range(0, 400, 7):
        for xx in range(0, 640, 5):
            total += 1
            if web.pixel(xx, yy) == vnc4.pixel(xx, yy):
                same += 1
    if same != total:
        fail("after typing, web and VNC differ (%d of %d)" % (same, total))
    print("web keyboard ok")
    web.s.close()

    # abrowse: loads a page over HTTP without freezing, loads its picture in the background, follows a link, and goes back
    import tempfile, http.server, threading, functools
    from PIL import Image
    site = tempfile.mkdtemp()
    os.makedirs(os.path.join(site, "sub"))
    Image.new("RGB", (200, 80), (200, 30, 30)).save(os.path.join(site, "red.png"))
    open(os.path.join(site, "index.html"), "w").write("<title>Index</title><h1>Index page</h1><p>A picture: <img src='red.png' alt='red'> and <a href='sub/two.html'>the second page</a>.</p>")
    open(os.path.join(site, "sub", "two.html"), "w").write("<title>Two</title><h1>Second</h1><p><a href='../index.html'>back to the index</a></p>")
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=site)
    handler.log_message = lambda *a, **k: None
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 8097), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    env5 = dict(os.environ, ADISPLAY="14")
    p5 = subprocess.Popen([os.path.join(bindir, "adisplayd"), "-p", "14", "-vnc", "5914", "-control", "-size", "800x600"], env=env5, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    procs.append(p5)
    time.sleep(0.8)
    v5 = Rfb(port=5914)
    bp = subprocess.Popen([os.path.join(bindir, "abrowse"), "http://127.0.0.1:8097/index.html"], env=env5, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    procs.append(bp)
    time.sleep(1.5)
    v5.grab()
    red = v5.find_color((200, 30, 30), tol=4)
    if not red or red[2] - red[0] < 150 or red[3] - red[1] < 60:
        fail("the picture of the page did not load: %s" % (red,))
    print("browser page and picture ok")
    # the link: find the blue link text, click it
    link = v5.find_color((26, 95, 200), tol=10)
    if not link:
        fail("no link on the page")
    v5.click((link[0] + link[2]) // 2, (link[1] + link[3]) // 2)
    time.sleep(1.0)
    v5.grab()
    if v5.find_color((200, 30, 30), tol=4):
        fail("the picture is still there after following the link")
    print("browser link ok")
    # Alt+Left goes back (the picture comes again)
    v5.key(0xffe9, 1)                     # Alt_L
    v5.key(0xff51, 1)                     # Left
    v5.key(0xff51, 0)
    v5.key(0xffe9, 0)
    time.sleep(1.5)
    v5.grab()
    if not v5.find_color((200, 30, 30), tol=4):
        fail("back did not show the index page again")
    print("browser back ok")

    # https: a site whose certificate is signed by a CA the browser is told to trust (SSL_CERT_FILE) shows its page and picture over TLS;
    # without that trust the browser shows the "not private" page, and "Proceed" opens the site anyway
    import ssl, datetime, ipaddress
    from cryptography import x509 as cx
    from cryptography.x509.oid import NameOID
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec as cec
    def cname(cn): return cx.Name([cx.NameAttribute(NameOID.COMMON_NAME, cn)])
    def cbuild(sub, key, iss, ikey, ca, sans=None):
        b = cx.CertificateBuilder().subject_name(cname(sub)).issuer_name(cname(iss)).public_key(key.public_key()).serial_number(cx.random_serial_number())
        b = b.not_valid_before(datetime.datetime(2020, 1, 1)).not_valid_after(datetime.datetime(2100, 1, 1))
        b = b.add_extension(cx.BasicConstraints(ca=ca, path_length=None), critical=True)
        if sans: b = b.add_extension(cx.SubjectAlternativeName(sans), critical=False)
        return b.sign(ikey, hashes.SHA256())
    cakey = cec.generate_private_key(cec.SECP256R1()); cacert = cbuild("Session Test CA", cakey, "Session Test CA", cakey, True)
    lkey = cec.generate_private_key(cec.SECP256R1())
    lcert = cbuild("localhost", lkey, "Session Test CA", cakey, False, [cx.DNSName("localhost"), cx.IPAddress(ipaddress.ip_address("127.0.0.1"))])
    cadir = tempfile.mkdtemp()
    capath = os.path.join(cadir, "ca.pem"); certpath = os.path.join(cadir, "leaf.pem"); keypath = os.path.join(cadir, "leaf.key")
    open(capath, "wb").write(cacert.public_bytes(serialization.Encoding.PEM))
    open(certpath, "wb").write(lcert.public_bytes(serialization.Encoding.PEM))
    open(keypath, "wb").write(lkey.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    sctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); sctx.minimum_version = ssl.TLSVersion.TLSv1_3; sctx.load_cert_chain(certpath, keypath)
    httpsd = http.server.ThreadingHTTPServer(("127.0.0.1", 8098), handler)
    httpsd.socket = sctx.wrap_socket(httpsd.socket, server_side=True)
    threading.Thread(target=httpsd.serve_forever, daemon=True).start()
    env6 = dict(os.environ, ADISPLAY="15", SSL_CERT_FILE=capath)
    p6 = subprocess.Popen([os.path.join(bindir, "adisplayd"), "-p", "15", "-vnc", "5915", "-control", "-size", "800x600"], env=env6, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    procs.append(p6)
    env7 = dict(os.environ, ADISPLAY="16")
    env7.pop("SSL_CERT_FILE", None)
    p7 = subprocess.Popen([os.path.join(bindir, "adisplayd"), "-p", "16", "-vnc", "5916", "-control", "-size", "800x600"], env=env7, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    procs.append(p7)
    time.sleep(0.8)
    v6 = Rfb(port=5915)
    b6 = subprocess.Popen([os.path.join(bindir, "abrowse"), "https://localhost:8098/index.html"], env=env6, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    procs.append(b6)
    time.sleep(2.0)
    v6.grab()
    red = v6.find_color((200, 30, 30), tol=4)
    if not red or red[2] - red[0] < 150 or red[3] - red[1] < 60:
        fail("the https page or its picture did not load: %s" % (red,))
    print("browser https page and picture ok")
    v7 = Rfb(port=5916)
    b7 = subprocess.Popen([os.path.join(bindir, "abrowse"), "https://localhost:8098/index.html"], env=env7, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    procs.append(b7)
    time.sleep(2.0)
    v7.grab()
    if v7.find_color((200, 30, 30), tol=4):
        fail("the page of an untrusted https site was shown without asking")
    if not v7.find_color((26, 95, 200), tol=10):
        fail("no links on the not-private page")
    print("browser untrusted https refused ok")
    # the links of the page are "Back to safety" and, below it, "Proceed ... anyway": click the lowest one
    lowest = v7.find_color_lowest((26, 95, 200), tol=10)
    if not lowest:
        fail("no Proceed link")
    v7.click((lowest[0] + lowest[2]) // 2, (lowest[1] + lowest[3]) // 2)
    time.sleep(2.0)
    v7.grab()
    red = v7.find_color((200, 30, 30), tol=4)
    if not red:
        fail("Proceed did not open the https page")
    print("browser proceed anyway ok")
    httpsd.shutdown()
    httpd.shutdown()

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
