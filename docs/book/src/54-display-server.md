# The display server

Every window of an A graphical program is drawn by a **display server**, itself a program written in A. It owns the screen, composes the windows of its
clients, draws their title bars, moves and resizes them, and routes the keyboard and the mouse. The server needs no X11, no Wayland and no C library. A
program that uses `import gui;` is a **client**: it talks to the server over TCP in a small binary protocol.

This chapter looks at the server from the inside. You will see how to embed a server and a client in one program (which is how this book takes its screenshots),
what the window manager does, how the output reaches a VNC viewer, a browser or a Linux framebuffer, how access is protected, and how a screen locker and a
login screen are built on top of it.

In this chapter:

* the pieces of the stack and a server with a client in the same process;
* the display protocol (`adp`) spoken by hand;
* input injection, the window manager and layers;
* the backends: headless, VNC (`wvnc`), framebuffer (`wfb`) and web (`wweb`, `wwebpage`);
* cookies and passwords, the screen locker (`glock`), the display manager (`dm`).

Writing programs with windows and widgets is the subject of [the GUI chapters](#chap-gui-basics); this chapter is about what is behind them.

## The stack

```text
  your programs         import gui;  (windows, widgets, events)
        |                TCP, the display protocol (adp)
  +-----------------+
  |    wsrv.Server  |   windows, window manager, input routing
  +---+-------+-----+
      |       |   \        backends: where the pixels go and the input comes from
  Headless   Vnc   Framebuffer   Web         (wsrv.Headless, wvnc, wfb, wweb)
  glock: a locker program          dm: login screen and sessions
```

| Module | Role |
|---|---|
| `adp` | the display protocol: opcodes, key codes, flags, message buffers |
| `wsrv` | the server: `Server`, the window manager, and the `Headless` backend |
| `wvnc` | a VNC (RFB) backend: any VNC viewer shows and controls the display |
| `wfb` | the Linux framebuffer and evdev backend (keyboard, mouse, touch) |
| `wweb`, `wwebpage` | a web browser backend: the display on a canvas, input back over a WebSocket; `wwebpage` holds the page |
| `glock` | a screen locker that works with the server's lock windows |
| `dm` | the display manager: users, passwords, the login window and sessions |

A server has one **primary backend** (it decides the size of the screen) and any number of further backends that show the same screen: a framebuffer, a VNC server and a web page at the same time.

## A server and a client in one program

The simplest server is `wsrv.Headless`: a "monitor" without output. `new wsrv.Server(backend, port)` listens on `127.0.0.1:port`; `server->step(ms)` does everything that is due
(accept clients, read their requests, read input, draw what changed). A client in the **same process** connects to it like to any other server, as long as the server gets turns while the client waits.
`gui.idleHook` is the function the client library calls while it waits.

{{sample guisrv/embed}}

{{shot guisrv/embed}}

**What to notice**

* The server needs a port number. The sample asks the system for a free one (`net.listen(0, ...)`, `net.localPort`) and closes that socket again; programs in this book never use a fixed port.
* `gui.connectAs("127.0.0.1:port", "demo")` is the `ADISPLAY` form `host:port`. A single number below 100 means port 7000 plus the number (`ADISPLAY=0` is `127.0.0.1:7000`).
* `settle()` is the pattern for all programs like this: `d->sync()` sends everything the client wrote, then both sides get turns (`srv->step(0)` and `d->pump(0)`) until nothing is pending.
* `srv->screen` is the screen as a `gfx.Surface`: the picture shows the title bar with its three buttons, the window border, the grip at the bottom right and the pointer, all drawn by the **server**. The client
  only draws the inside of the window. The pointer was moved to a corner first, because the server draws it.
* `srv->windowCount()`, `windowAt(i)` and `clientCount()` let an embedding program look at the state of the server.

The pattern is how most tests of the GUI libraries work, and how the pictures of this chapter and the two after it are made: the program saves `srv->screen` with `gimg.savePng`.

## The display protocol

A message is `int32 length, int32 opcode, payload`, all numbers little endian 32-bit integers; pixels are four bytes: blue, green, red, alpha. A client sends
requests (`Q_HELLO`, `Q_CREATE`, `Q_PRESENT`, `Q_MOVE`, `Q_PING` ...) and receives events (`E_WELCOME`, `E_EXPOSE`, `E_MOUSE`, `E_KEY`, `E_CLOSE` ...). The header of `lib/adp.a` lists all of them
with the fields of each. Any program in any language that speaks this protocol is a client. Here is one written with nothing but `net` and `adp`:

{{sample guisrv/protocol}}

{{shot guisrv/protocol}}

**What to notice**

* `Q_HELLO` carries the protocol version and the client's name; the answer `E_WELCOME` has the version, the client number and the **size of the screen**. `Q_CREATE` gives the id you chose for the window, its position and size, flags and title.
* `Q_PRESENT` sends pixels for a rectangle of the window. The **first** present is what shows the window.
* `Q_PING` is answered by `E_PONG` after the server has handled everything the client sent before it. It is how `sync()` works, and the only reliable way to wait: a first version of this sample
  looked at the screen right after sending and sometimes saw the old picture, because the server had not read the pixels yet.
* The window is drawn without a client library: gradient pixels went over a socket. The `gui` library adds widgets, layout, text and event handling on top of exactly these messages.

## Injecting input

The headless backend has no keyboard or mouse: a program injects events with `moveTo`, `click`, `buttonDown`, `buttonUp`, `scroll`, `keyDown`, `keyUp`, `tap` and `typeText`. They go through the same routing as real input.

{{sample guisrv/input}}

{{shot guisrv/input}}

**What to notice**

* Pointer events go to the window under the pointer (or to the one that was pressed while a button is down); keys go to the **focused** window. A click on the text box gave the window and the widget the focus.
* Positions are screen positions. The sample adds the window's position (`findWindow` gives the server's window), the widget's `absX()` / `absY()` and half its size.
* `tap(key, character)` is one key press and release; `typeText` types each character. Key codes are the constants of `adp` (`KEY_BACKSPACE`, `KEY_ENTER`, `KEY_LEFT` ...).
* `gui.caretBlinks = false` keeps the caret solid so that the picture does not depend on the time.

With `allowInject` and `allowScreenshots` a server also lets *clients* inject input and take screenshots; `actl` and the tool that took the graphical screenshots of this book use that.

## The window manager

The server is also the window manager. Windows have a title bar (close, maximize, minimize), a border and, unless the client asked for `F_FIXED`, a grip at the bottom right. A press on the title
bar drags the window, a double click maximizes it, a click raises it and gives it the focus, `Alt+Tab` switches and `Alt+F4` asks the window to close.

{{sample guisrv/windows}}

{{shot guisrv/windows}}

**What to notice**

* The title bar is 26 pixels high and sits *above* the client area (`win->y - 13` is the middle of it), the border is 2 pixels. `srv->windowAt(i)` is ordered from the back to the front.
* A click on A brought it to the front (`stacking order: B A`) and gave it the focus: the focused window has the blue title bar, the other one is gray.
* **The window decides.** The close button only sends `E_CLOSE`; the client's `onClose` returned 1, so the window stayed. The server never kills a program.
* `toggleMaximize` changed the server's window and told the client its new size (`E_RESIZE`): `b->w` and `wb->w` agree, and the window came back to 150 x 70.

### Layers

Windows can ask for a layer with flags. `F_BELOW` stays under everything (a wallpaper), `F_ABOVE` over everything (a panel), `F_NODECOR` has no frame, `F_NOFOCUS` never takes the keyboard focus.

{{sample guisrv/layers}}

{{shot guisrv/layers}}

**What to notice**

* A desktop is made of such windows: the wallpaper and the panel in this sample are ordinary clients, and a taskbar like `apanel` is a client too.
* The normal window was dragged up under the panel: the server limits the title bar to the top of the screen (`ny >= 26`), and the panel, being `F_ABOVE`, stays in front.
* The order in the list is the stacking order: wallpaper, normal window, panel.

## Backends

A `Backend` has a size, receives the changed rectangles of the screen in `present`, and produces input events with `push`. The server asks it which file descriptors it wants watched (`pollFds`) and tells it when
they are ready (`service`). You add more than one with `srv->addBackend`.

### VNC

`wvnc.Vnc` serves the screen as an RFB server (versions 3.3, 3.7 and 3.8, the Raw encoding, 8, 16 and 32 bit true colour). Several viewers can be connected, together with other backends. The mouse, the wheel and the keyboard
come back. The sample below is a tiny viewer written by hand, to show the protocol; a real viewer is `vncviewer host:display`.

{{sample guisrv/vnc}}

**What to notice**

* The server speaks first: `RFB 003.008`. The viewer answers with its version, chooses a security type (1 is none), says that the display may be shared, and gets the size, the pixel format and the name.
* The first pixel is the top of the background gradient. VNC sends blue, green and red, which is why `126 84 52` is the server's colour 52, 84, 126.
* **There is no encryption.** `setPassword("...")` asks for the standard VNC password (DES challenge; only 8 characters count and a wrong try makes the next one wait). The default host is `127.0.0.1`: on a network you do not trust,
  tunnel the port with `ssh -L 5900:localhost:5900 host`.

### Framebuffer

`wfb.Framebuffer("/dev/fb0", "us")` draws on a Linux framebuffer and reads the keyboard, mouse and touch screens from `/dev/input` (32 and 16 bits per pixel; layouts `us` and `fi` with AltGr). It needs
root or the `video` and `input` groups, so the sample below uses only its pure parts: the translation of evdev events and the key layouts.

{{sample guisrv/framebuffer}}

**What to notice**

* Without a device the backend says why (`ok()` is false and `error()` has the text). The programs of this book never need a framebuffer.
* A relative mouse moves the pointer (`EV_REL` events add to its position); the wheel and the buttons become `IE_SCROLL`, `IE_DOWN` and `IE_UP`.
* `keyFor(code, shift, altgr, &character)` is the layout: key 40 of a Finnish keyboard is `ä`, with Shift `Ä`, and AltGr on key 8 gives `{`. On the `us` layout AltGr changes nothing.
* With `takeConsole = true` the text console is put in graphics mode and its keyboard is silenced until `shutdown()`. That part was not run for this chapter: there is no framebuffer here.

### Web browser

`wweb.Web` serves the display to a browser: a page with a canvas, the changed rectangles run-length coded over a WebSocket, and the mouse and keyboard back. The page is a string inside the module `wwebpage`.

{{sample guisrv/web}}

**What to notice**

* The token is a shared secret in the address (`/?t=secret123`), at least 8 letters and digits. A backend with an invalid token does not start (`ok()` is false), and any host but `127.0.0.1` needs one.
* A wrong token gets `403 Forbidden`, and the next try **waits**: the right token right after it was refused too.
* The WebSocket (`/ws`) also needs the token and refuses an `Origin` that is not the page's own host, so a page on another site cannot take the display over from your browser (this is from the
  documentation; the sample does not open a WebSocket). It is plain HTTP: tunnel it on networks you do not trust.
* Browser shortcuts such as Ctrl+W cannot be captured by a page.

{{sample guisrv/webpage}}

**What to notice**

* The page is generated from `docs/web/index.html` by a script and compiled into the program, so a server needs no files. The token replaces the placeholder `@TOKEN@`.
* The protocol of the WebSocket is documented at the top of `lib/wweb.a`: binary messages, with the size, rectangles of pixels, and pointer, button, wheel and key events.

### A server program

`adisplayd` (`examples/gui/adisplayd.a`) is the display server as a program, with options for all of this. Its core is short:

{{sample guisrv/server}}

**What to notice**

* The first backend decides the size of the screen; `addBackend` adds a second view of the same screen.
* Listening on another address than `127.0.0.1` is refused unless a cookie is set (next section).

Run the real program, with a client, from a shell. The numbers are ports on loopback; use `ADISPLAY=0` (port 7000) in everyday life:

```sh
ac examples/gui/adisplayd.a -o adisplayd
ac examples/gui/hello.a -o hello
ac examples/gui/actl.a -o actl
./adisplayd -p 24612 -vnc 24611 -control -size 640x400 &
ADISPLAY=127.0.0.1:24612 ./hello &
./actl -d 127.0.0.1:24612 shot shot.ppm
```

```text
display on 127.0.0.1:24612, 640x400, VNC on 127.0.0.1:24611
640x400 saved to shot.ppm
```

Point a VNC viewer at port 24611 to look at it. On a Linux console without a desktop, `./adisplayd -fb /dev/fb0 -layout fi` draws on the screen instead.

## Who may connect

By default the server listens on `127.0.0.1` only and every local user can connect. To use it from another computer, or to keep other local users out, give it a **cookie**, a shared secret of at least 16 bytes
as hex text.

{{sample guisrv/cookie}}

**What to notice**

* After `Q_HELLO` a server with a cookie sends a 16 byte nonce; the client answers with `HMAC-SHA256(cookie, nonce)`. **The cookie itself never travels.** A wrong answer closes the connection, nothing else is accepted
  before the answer, and a client has 5 seconds to give it.
* `connectWith(spec, name, cookie)` passes the cookie; `gui.connect` looks in `ADISPLAY_COOKIE`, then the file named by `ADISPLAY_COOKIE_FILE`, then `~/.adisplay-cookie`.
* `listenOn("0.0.0.0", port)` is refused without a cookie. `adisplayd -newcookie -cookie FILE` makes a cookie file with 32 random bytes and mode 600.
* The protocol is **not encrypted**: windows and keystrokes travel in the clear. The cookie proves who may connect; on networks you do not trust also use an SSH tunnel.

## Locking the screen

A window with the flag `F_LOCK` covers the screen and gets **all** input: the server draws no other window, ignores `Alt+Tab` and `Alt+F4`, and does not let anything else take the focus until the lock window is gone.
`glock.Locker` is a ready-made locker; you give it a function that checks the password.

{{sample guisrv/lock}}

**What to notice**

* `srv->locked()` and `lockWindow()` tell an embedding program whether a lock is showing. The click on the button while locked went to the locker, not to the app.
* After a wrong password the next try has to wait 1 s, then 2 s and so on, to at most 30 s. The right password given at once was not even checked (`checked 1 times`).
* The locker also shows the time of day, so it is not photographed in this book. `alock` (`examples/gui/alock.a`) is the ready program: it checks the password against `/etc/shadow` (run it as root, or give the display manager's users file with `-u`).
* This stops the keyboard and pointer of the display from reaching other windows. It does not stop a local user who connects to the display port, so on a shared machine also lock the console or session of the system.

## The display manager

`dm` is a small display manager: it runs the display server, shows a login window, checks the password, starts the session of the user and shows the login window again when the session ends. The pieces can be used apart.
First the users and the configuration file:

{{sample guisrv/dm_users}}

**What to notice**

* A users file has lines `name:hash:uid:gid:home:session`. `makeUserLine` makes a line with a `$6$` SHA-512 hash (the same format as `/etc/shadow`; `openssl passwd -6` works too). `users = system` reads `/etc/passwd` and `/etc/shadow` instead (needs root).
* `authenticate` refuses a wrong password, an unknown user, locked accounts (`!`, `*`) and users with a uid below `minUid` (1000 by default), and root unless `allowRoot` is set. An unknown name takes as long as a wrong password, so the time does not tell whether a name exists.
* The configuration file is `key = value` with `#` comments; keys: `port`, `vnc`, `vnchost`, `fb`, `layout`, `width`, `height`, `users`, `session`, `greeting`, `shutdown`, `reboot`, `minuid`, `allowroot`, `takeconsole`. Unknown keys are ignored.

The login window is a `gui` client like any other, here shown on the headless backend:

{{sample guisrv/dm_login}}

{{shot guisrv/dm_login}}

**What to notice**

* `dm.Manager(server, config)` connects to the server as a client (`displayPort` is the port the server listens on) and builds the login window in the middle of the screen. `step(ms)` runs one turn of both.
* A failed login shows "Wrong user name or password" and makes the next attempt wait 1, 2, 3 ... seconds (at most 8).
* A good login starts the `session` command through `/bin/sh` in its own session, as the user (`setgroups`, `setgid`, `setuid`, `chdir`) when `adm` runs as root, with `ADISPLAY`, `HOME`, `USER` and `LOGNAME` set. When it ends, all
  clients that are still connected are disconnected and the login window comes back. This was not run here: starting a session needs `fork`, root and a real user.
* The complete program is `examples/gui/adm.a`; `asession` is a small desktop to start from it. A fuller display manager lives in its own repository (see [the GUI reference](#chap-gui-reference)).

## Limits

* No hardware acceleration; one font family at one size in the built-in fonts; no input methods; the clipboard is plain text.
* The server and the clients are single threaded and talk TCP over loopback.
* On Windows the server (with VNC), the toolkit and the programs work; the framebuffer backend does not exist and the display manager cannot start sessions (no `fork`).
* The framebuffer backend was not run on a real framebuffer for this book; the VNC and web backends were exercised with clients written in A over loopback, not with a real viewer or browser.

## Summary

* The display server (`wsrv`) composes the windows of its clients, draws the frames, moves, resizes and focuses windows and routes input. The window decides about closing; the server never kills a program.
* A server and a client can live in one process: give the server turns while the client waits (`gui.idleHook`), and use a ping (`sync`) to wait for it.
* The protocol (`adp`) is small: hello, create, present pixels, input events. Any program that speaks it is a client.
* The screen can be shown by several backends at once: `Headless`, `wvnc.Vnc`, `wfb.Framebuffer`, `wweb.Web`.
* Access is controlled by a cookie (HMAC challenge), a VNC password and a web token; none of the transports is encrypted, so tunnel them on untrusted networks.
* `F_LOCK` windows implement screen lockers (`glock`); `dm` implements users, `$6$` passwords, the login window and sessions.

## Where next

* [The GUI basics](#chap-gui-basics), [more widgets](#chap-gui-more-widgets) and [GUI programs](#chap-gui-programs): the client side.
* [Networking from a GUI program](#chap-gui-net-and-web), the HTML view and the terminal widget.
* [The GUI reference](#chap-gui-reference) for every flag, key code and option, and [the TLS notes](#chap-tls-notes).
* API references: [wsrv](#api-wsrv), [adp](#api-adp), [wvnc](#api-wvnc), [wfb](#api-wfb), [wweb](#api-wweb), [wwebpage](#api-wwebpage), [glock](#api-glock), [dm](#api-dm).
