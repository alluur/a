# Graphical programs in A: display server, toolkit and display manager

A has a complete graphics stack written in A itself: a **software graphics library**, a **display server** (compositor and
window manager), a **widget toolkit** for programs, and a **display manager** (login screen and session launcher). Nothing
outside the compiler is needed: no X11, no Wayland, no libc.

```
  hello  calc  paint  notes  ...          programs, written with  import gui;
        \    |    |     /                 (windows, widgets, events)
         \   |    |    /   TCP, the display protocol (adp)
          +--------------+
          |  adisplayd   |                the display server  (import wsrv;)
          |  windows, WM |
          +---+------+---+
              |      |      \             backends
         Framebuffer VNC   Headless       (import wfb;  import wvnc;  wsrv.Headless)
         /dev/fb0   viewer  tests
  adm  ----> shows the login screen, starts sessions as the user  (import dm;)
```

| Module | What it is |
|--------|------------|
| `gfx` | surfaces, drawing, alpha blending, antialiased fonts, image output, checksums |
| `adp` | the display protocol: opcodes, key codes, message buffers |
| `wsrv` | the display server: compositor, window manager, input routing; the `Headless` backend |
| `wvnc` | a VNC (RFB) backend: view and control the display with any VNC viewer |
| `wfb` | the Linux framebuffer + evdev (keyboard, mouse, touch) backend |
| `gui` | the client library and the basic widgets, popups, tooltips |
| `guix` | more widgets: menus, combo box, radio buttons, tabs, scroll view, spin box, splitter; dialogs (confirm, prompt, file, colour) |
| `gchart` | data widgets: `Chart` (bar, line, area and pie charts with rolling data), `Gauge`, `Switch`, `Rating` |
| `glock` | a screen locker (works with the server's `F_LOCK` windows) |
| `wweb` | a web browser backend: the display in a canvas, mouse and keyboard back over a WebSocket |
| `ghtml` | shows HTML and Markdown: parser, layout, links, images, scrolling (`HtmlView`) |
| `gnet` | non-blocking HTTP fetches, a port scanner, TCP connections and listeners, UDP announcements and a peer-to-peer chat, all inside the event loop |
| `secure` | secure random bytes, unique nonces, hex; (`hash` has `hmacSha256`, `des` the DES cipher for VNC passwords) |
| `tls`, `x509` | TLS 1.3 client and server and certificate checking, for `https://` in `gnet.Fetch` and `abrowse` (see [TLS.md](TLS.md)) |
| `gimg` | colour images: load PNG, BMP and PPM, save PNG, smooth scaling |
| `gterm` | a terminal emulator widget (pseudo terminal, ANSI/xterm escape sequences) |
| `gcode` | the widgets of the AIDE code editor: `CodeEditor`, `FileTree`, `TabBar`, `FindBar`, `GotoBar`, `StatusBar`, `OutputPane`, `TerminalPane`, `SearchPane`, `RunPane`, `DocView`, `Outline`, `ColorPicker`, `ThemeEditor`, `SettingsDialog`, `Dock`, `Commands`, `Palette` (see [below](#the-code-editor-widgets-gcode)) |
| `dm` | the display manager: users, passwords, login screen, sessions |
| `syscrypt` | `$6$` SHA-512 password hashes (as in `/etc/shadow`) |

The programs are in `examples/gui/`; tests in `tests/t110`-`t129`, `t240`-`t267` and `t281`-`t282` (gcode, fonts, panels), `tests/gui.sh`, `tests/https.sh`.

## Quick start

```sh
ac examples/gui/adisplayd.a -o adisplayd       # the display server
ac examples/gui/hello.a -o hello
ac examples/gui/calc.a -o calc
./adisplayd -vnc 5900 -control &               # 127.0.0.1:7000 (ADISPLAY=0), VNC on 127.0.0.1:5900
ADISPLAY=0 ./hello &
ADISPLAY=0 ./calc &
ac examples/gui/aterm.a -o aterm && ADISPLAY=0 ./aterm &     # a terminal (also: showcase, notes, paint, alock)
vncviewer localhost:5900                       # look at it (any VNC viewer; tunnel the port for remote use)
```

* **On a Linux console** (no desktop running): `./adisplayd -fb /dev/fb0 -layout fi` draws on the screen and reads the
  keyboard and mouse from `/dev/input` (needs root or the `video` and `input` groups).
* **Without any screen**: `adisplayd` with `-vnc` only (the default) is a headless display; `actl shot file.ppm` takes
  screenshots and `actl click|type|key ...` injects input (start the server with `-control`).
* **ADISPLAY** names the display for clients: `0` = 127.0.0.1:7000, `N` = port 7000+N, or `host:port`.

## Drawing: `gfx`

```c
import gfx;
gfx.Surface* s = new gfx.Surface(320, 200);          // pixels are ints 0xAARRGGBB
s->clear(gfx.rgb(30, 30, 40));
s->fillRoundRect(10, 10, 100, 40, 8, gfx.rgb(200, 80, 60));
s->text(gfx.sans(), 20, 22, "Hello, Ä Ö Å", gfx.WHITE);     // UTF-8, Latin-1 glyphs
s->savePPM("out.ppm");                                       // or saveBMP
```

* Shapes: `fill rect hline vline line circle fillCircle roundRect fillRoundRect gradientV shadow`, and `fillPolygon(xs, ys, n, c)`,
  `fillPie(cx, cy, r, a0, a1, c)`, `thickArc(cx, cy, r0, r1, a0, a1, c)` and `arc(...)` (angles in degrees, clockwise from the right;
  `gfx.isin` / `gfx.icos` give sine and cosine times 1024); every function clips to the
  surface and to the clip rectangle (`setClip`, `resetClip`). A colour with alpha < 255 blends with what is there.
* Images: `blit` (copy), `blitBlend` (alpha compositing), `pack` / `unpack` (4 bytes per pixel: blue, green, red, alpha).
* Text: `text(font, x, y, utf8, colour)`, `textCentered`, `gfx.textWidth(font, s)`; fonts `gfx.sans()`, `gfx.sansBold()`,
  `gfx.mono()` are 13-pixel antialiased DejaVu fonts (generated by `docs/gen_font.py` into `lib/gfxfont.a`).
  Other fonts load from files: `gfx.loadFont(path)` returns a font (or null for a missing or damaged file, or one without line height). The file is
  binary: byte ascent, byte line height, then for each code 32..255 the bytes advance, left bearing (signed), top (signed),
  width, height, followed by width*height 4-bit coverage values (two per byte, the first pixel in the high nibble).
  `gfx.sans()`, `sansBold()` and `mono()` use the files that the font configuration names: the file in `$AFONT_CONF`, else
  `/etc/fonts.conf`, with lines `sans=/path/font.afont`, `sansbold=...`, `mono=...` (`builtin` keeps DejaVu; a missing or
  damaged file also falls back to DejaVu). The AOS project makes such fonts with a generator written in A (`fonts/fontgen.a`).
* **Other sizes** (`t281`): `gfx.scaleFont(font, percent)` makes a copy of a font at 20 to 400 percent (every glyph sampled again with an area average, integer arithmetic: the same pixels on every
  target). `gfx.setFontScales(uiPercent, monoPercent)` scales the shared fonts **in place** (`sans()` and `sansBold()` by the first number, `mono()` by the second; `Font.assign` swaps the glyph data of the
  object, so every widget that holds a pointer to `gfx.sans()` has the new size after its next layout; the terminal calls `remeasure()`), `gfx.setUiFont("mono" | "sans" | "/path/font.afont")` chooses
  the font of sans and sansbold (false for a file that cannot be used), `uiFontScale()` / `monoFontScale()` read the sizes. 100 gives back the exact original fonts.
* `checksum()` gives one number for the whole picture: the same program draws the same pixels on every target, which is how
  the tests compare Linux x64, ARM64, RISC-V, LoongArch and Windows.

## Charts and gauges: `gchart`

```c
import gchart;
gchart.Chart* c = new gchart.Chart(gchart.LINE);        // BAR, LINE, AREA or PIE
int cpu = c->addSeries("CPU", 0);                       // colour 0 = the next colour of the palette
c->setRange(0, 100);
c->push(cpu, 42);                                       // one point per tick; the chart scrolls after c->maxPoints (60)
gchart.Gauge* g = new gchart.Gauge(0, 100);   g->setValue(73);   g->caption = "CPU %";
gchart.Switch* sw = new gchart.Switch(true);  sw->onChange = changed;       // int changed(int widget)
gchart.Rating* r = new gchart.Rating(5, 3);
```

A `Chart` scales its y axis to 1, 2 or 5 times a power of ten unless `setRange` fixes it, draws a grid with labels, a title and a
legend (`title`, `grid`, `legend`), stacks bars with `stacked = true`, and takes names for the x axis or the pie slices from
`setLabels`. All of them are ordinary `gui.Widget`s: put them in a `Box`, give them `flex` or a size.

## Programs: `gui`

```c
import gui;

int clicked(int self) { println("clicked"); return 0; }

int main() {
    gui.Display* d = gui.connect(null);                 // uses ADISPLAY
    gui.Window* w = d->createWindow("Hello", 280, 120, 0);
    gui.Box* col = gui.vbox(10, 14);                    // spacing 10, padding 14
    col->add(new gui.Label("Press the button"));
    gui.Button* b = new gui.Button("Click me");
    b->primary = true;
    b->onClick = clicked;
    col->add(b);
    w->setRoot(col);
    w->fit();
    d->run();                                            // until the last window is closed
    return 0;
}
```

**Widgets**: `Label`, `Button`, `CheckBox`, `TextBox` (single line, selection, clipboard, password), `TextArea` (multi-line
editor), `ListBox`, `Slider`, `ProgressBar`, `ImageView`, `Canvas` (a picture you draw into), `Separator`, `Spacer`, and
`Box` for layout. A `Box` arranges its children in a row (`hbox`) or column (`vbox`); a child with `flex > 0` takes its
share of the free space, the others get their preferred size (`prefW()` / `prefH()`).

**Callbacks** are functions `int f(int widget)`; the widget arrives as an int: `gui.Button* b = (gui.Button*) widget;`.
Fields: `onClick` (Button), `onChange` (CheckBox, TextBox, TextArea, Slider), `onEnter` (TextBox), `onSelect` /
`onActivate` (ListBox), `onMouseEvent` (Canvas). Every widget has `userData` for your own use.

**Windows**: `createWindow(title, w, h, flags)` or `createWindowAt(title, x, y, w, h, flags)`. Flags (from `adp`):
`F_NODECOR` (no title bar), `F_BELOW` (wallpaper), `F_ABOVE` (panels), `F_NOFOCUS`, `F_FIXED` (not resizable).
Window methods: `setRoot setTitle move resize fit show hide raise close invalidate update`, `setFocus`, `defaultButton`
(Enter presses it), `onClose` (return nonzero to keep the window open), `onKey` (keys no widget wanted), `onResize`,
`noClear` (the program paints everything itself into `w->surf`).

**Timers**: `d->after(ms, f, arg)` calls `int f(int arg)` once; `d->cancel(id)`.  **Clipboard**: `d->setClipboard(text)`; the
text widgets use Ctrl+A / C / X / V. `gui.messageBox(d, title, text)` shows a small dialog.

**Your own widgets**: derive from `gui.Widget` (call `super();` first) and override `paint(surface, ox, oy)`, `onMouse`,
`onKey`, `prefW`, `prefH`; see `Swatch` in `examples/gui/paint.a`.

**Your own loop**: instead of `d->run()` call `d->pump(ms)` (handles events for up to `ms`) in a loop.

**Small extras**: `d->ping(n)` asks the server to answer with the same number (`d->lastPong`): when it arrives the server has handled everything
the client sent before (the gcode tests use it to wait for big windows); a `TextBox` has optional colours (`colBack colText colSel colBorder
colAccent colDim`, 0 = the standard theme) and inserts any Unicode code point. The caret of a `TextBox` / `TextArea` blinks
every 500 ms; set `gui.caretBlinks = false` to keep it solid (no timer: the gcode tests do this so that window checksums do not depend on the
speed of the machine).

## More widgets: `guix`

```c
import gui;
import guix;

guix.MenuBar* bar = new guix.MenuBar();
guix.Menu* file = bar->addMenu("&File");                  // & marks the Alt key: Alt+F opens the menu
file->add("Open...", doOpen)->accel("Ctrl+O");             // int doOpen(int item) { ... return 0; }
file->add("Save", doSave)->accel("Ctrl+S");
file->addSeparator();
file->add("Quit", doQuit)->accel("Ctrl+Q");
guix.Menu* view = bar->addMenu("&View");
view->addCheck("Word wrap", true, wrapChanged);            // item->checked changes by itself
guix.Menu* more = new guix.Menu();
more->add("Alpha", pickAlpha);
view->addSub("More", more);                                // a submenu
col->add(bar);                                             // the bar goes at the top of the window
```

* **Menus**: a `MenuBar` shows menus from its titles; accelerators (`"Ctrl+S"`, `"Ctrl+Shift+Z"`, `"F5"`, `"Alt+Enter"`,
  `"Del"`, ...) work anywhere in the window while the bar is in it; `F10` opens the first menu; Alt+letter opens the
  menu whose title has that letter after an `&`. Arrow keys, Enter and Esc move through open menus, the pointer opens a
  menu on a click and switches menus when it moves over another title. Items can be disabled (`->disable()`), checkable
  (`addCheck`), have a submenu (`addSub`) and an `id` (`->setId(n)`, `menu->byId(n)`). A callback is
  `int f(int item)`; cast the item: `(guix.MenuItem*) item`.
* **Context menus**: give any widget `onContext = f;` (called on a right click). In `f` show a menu where the pointer is:
  `menu->popup(widget->win, widget->win->lastMouseX, widget->win->lastMouseY);`. A menu that does not fit moves
  inside the window.
* **ComboBox** (`addItem`, `select`, `text()`, `selected`, `onChange`): a drop-down list that opens below (or above)
  and scrolls when it has more than eight rows. **RadioButton** + **RadioGroup**: create the group, then buttons with
  `new guix.RadioButton("text", group)`; `group->selectedIndex()`, `group->selectIndex(i)`, `group->onChange`;
  the arrow keys move inside a group.
* **TabView**: `addTab("Title", page)` where the page is any widget (usually a `Box`); `select(i)`, `onChange`,
  `closable = true` gives the tabs close buttons (`onTabClose`, `removeTab(i)`). Left/Right switch tabs.
* **ScrollView**: `setContent(widget)`; scrollbars appear when the content is larger (the content has its preferred
  size, or exactly the width of the view with `fitWidth = true`). The mouse wheel scrolls (Shift for sideways), and a
  widget inside that gets the keyboard focus is scrolled into view. **ScrollBar** can be used on its own.
* **SpinBox** (`min`, `max`, `step`, `value`, `onChange`): type digits, use Up/Down/PageUp/PageDown, click the arrows
  or turn the wheel. **Splitter**: `new guix.Splitter(true, 120)` puts two widgets side by side (false: one above the
  other) with a divider you drag. **Swatch** shows a colour.
* **TableView**: `addColumn("Name", 120)` first, then rows with `addRow("a\tb\tc")` (cells separated by tabs) or
  `addEmptyRow()` + `setCell(row, col, text)`; `setAlign(col, 1)` right-aligns a column. Click a header to sort (text
  without regard to case, numbers by value; `sortBy(col, ascending)`, or your own `onSort`), drag the edge of a header to
  resize the column, `selected`, `onSelect`, `onActivate` (double click or Enter), `cell(row, col)`, `clear()`.
* **TreeView**: `TreeNode* n = tree->addRoot("text"); n->add("child");` Nodes have `userData`, `expanded` and `lazy` (an
  arrow although there are no children yet: add them in `tree->onExpand`, the node is `tree->expandedNode`). Click the
  arrow or press Right/Left/Enter to open and close, Up/Down/Home/End/PageUp/PageDown to move, `selected`, `onSelect`,
  `onActivate`. `examples/gui/afiles.a` (a file browser: a tree of folders, a table of files, a splitter) uses all three.
* **Toolbar and icons**: `tb = new guix.Toolbar(); tb->addButton(guix.ICON_SAVE, "Save", f); tb->addSeparator();`. An
  `IconButton` is flat, has a tooltip and can be a toggle (`toggle = true`, `checked`). There are 27 icons
  (`ICON_NEW OPEN SAVE CUT COPY PASTE UNDO REDO PLUS MINUS CLOSE CHECK LEFT RIGHT UP DOWN REFRESH SEARCH HOME SETTINGS TRASH
  PLAY PAUSE STOP STAR INFO WARNING`); `guix.drawIcon(surface, icon, x, y, colour)` draws one (16 x 16) anywhere.
* **StatusBar**: `addSection(width)` (0 stretches) and `setText(section, text)`. **TextBlock**: text that wraps at the width
  of the widget (`\n` starts a paragraph, `align`, `wrapWidth`). **Calendar**: `year month day`, `onChange`, click a day,
  the arrows or the wheel change the month, arrow keys move by day and week, PageUp/PageDown by month; `guix.chooseDate(d,
  title, year, month, day, f)` is a dialog (the result is `year * 10000 + month * 100 + day`, 0 when cancelled).
* **Notifications**: `guix.notify(d, "Title", "text", kind, ms)` shows a card in the top right corner (kind 0 information,
  1 warning, 2 error); it closes after `ms` or on a click, up to six at a time.
* **Busy bar**: `progressBar->start()` / `stop()` animate a `gui.ProgressBar` for work of unknown length.
* **Tooltips**: `widget->tooltip = "text";` (a field of every widget) shows the text when the pointer rests on it.

* **Colours of a dark program**: the standard look is light. A program with a colour scheme sets the globals the widgets read when they paint: `gui.cBack cText cTextDim cAccent cAccentText cField cBorder cButton
  cButtonHot cButtonDown cSelect`, the tool tips (`gui.cTipBack cTipBorder cTipText`), and for the widgets of `guix` `guix.cPanel` (menu popups), `cTabIdle`, `cTrack`, `cThumbOff` (scroll bars), `cHeadTop`,
  `cHeadBottom`, `cStripe` (tables); `MenuBar.background` and `Toolbar.background` colour the bars. AIDE does this for every theme (`AideApp.applyChrome` in the AOS repository). More icons: `ICON_BUILD` (a hammer), `ICON_BUG`,
  `ICON_FOLDER`, `ICON_PANEL`.

**Dialogs** open a window, and when the user is done they call your function `int f(int result)` and close:

| Function | Result |
|----------|--------|
| `guix.confirm(d, title, text, f)` | 1 for Yes, 0 for No or when the window was closed |
| `guix.prompt(d, title, label, initial, f)` | the text as a `char*` (cast to int), 0 when cancelled |
| `guix.openFile(d, title, startDir, f)` | the path as a `char*`, 0 when cancelled; folders can be entered, `..` goes up, hidden files can be shown |
| `guix.saveFile(d, title, startDir, name, f)` | the path; asks before an existing file is replaced |
| `guix.chooseColor(d, title, 0xFFRRGGBB, f)` | the colour as `0xFFRRGGBB`, 0 when cancelled |

The `...Arg` versions (`confirmArg`, `promptArg`, `openFileArg`, `saveFileArg`) take one more int that your function reads
from `guix.dialogArg`. `examples/gui/showcase.a` shows every widget and dialog; `examples/gui/notes.a` is an editor with
menus, accelerators, a context menu and the file dialogs.

**Popups** (`gui.Window`): `w->showPopup(widget)` puts a widget that covers the window above everything; it receives all
mouse and key events until `w->closePopup()` (Esc also closes it, and then `widget->onDismiss()` is called). Menus and the
combo box's list are built on this, so you can make your own.

## Locking the screen: `glock` and `alock`

A window with the flag `adp.F_LOCK` covers the screen, stays above everything and gets **all** input; the server does not
draw the other windows, ignores `Alt+Tab` and `Alt+F4`, and does not let anything else take the focus until the window is
destroyed. `glock.Locker` is a ready-made locker (clock, user name, password field):

```c
glock.Locker* l = new glock.Locker(display, "aleksi", checkPassword);   // int checkPassword(int password) -> 1 if right
l->run();                                                               // returns when it was unlocked
```

After a wrong password the next try has to wait one second more each time (at most 30 s). `alock [-d display]
[-u usersfile] [user]` (`examples/gui/alock.a`) is the program: it checks the password against `/etc/shadow` (it must be
allowed to read it, so run it as root, or give the display manager's users file with `-u`) with the same `$6$` code as the
display manager. `wsrv.Server.locked()` and `lockWindow()` tell an embedding program whether a lock is showing.

## Remote display and authentication

By default the display server listens on `127.0.0.1` only, and every local user can connect. To use it from another computer
(or to keep other local users out) give it a **cookie**, a shared secret, and let it listen on more addresses:

```sh
adisplayd -newcookie -cookie ~/.adisplay-cookie -listen 0.0.0.0 -vnc 5900 -vncpass ~/.vncpass &
scp ~/.adisplay-cookie other:~/                       # a safe way to copy it
ADISPLAY=server:7000 ./hello                          # on the other computer; reads ~/.adisplay-cookie
```

* **Cookie authentication**: the cookie file holds 16 or more bytes as hex text (`-newcookie` makes one with 32 random bytes and
  mode 600 when the file does not exist, also on Windows, where the random bytes come from `RtlGenRandom`). After `Q_HELLO` a server with a cookie sends a 16 byte nonce (`E_AUTH`); the client answers with
  `HMAC-SHA256(cookie, nonce)` (`Q_AUTH`). The cookie itself never travels; a wrong answer closes the connection (`E_DENIED`),
  nothing else is accepted before the answer, and a client has 5 seconds to give it.
* **Clients** find the cookie in `ADISPLAY_COOKIE` (hex text), or the file named by `ADISPLAY_COOKIE_FILE`, or
  `~/.adisplay-cookie`; or in a program: `gui.connectWith("host:7000", "name", cookieHex)`. `actl` does the same.
  Embedding programs call `server->setCookie(hex)` and `server->listenOn("0.0.0.0", port)`; listening on anything but
  127.0.0.1 is refused unless a cookie is set.
* **VNC password**: `adisplayd -vncpass FILE` (the first line is the password; only 8 characters count, that is how VNC works) or
  `vnc->setPassword("...")`. It speaks the standard VNC authentication (DES challenge); a wrong password makes the next try
  wait 1 s longer each time (at most 10 s).
* **No encryption**: the display protocol and VNC send windows and keystrokes in the clear. The cookie proves who may connect;
  on a network you do not trust, also use an SSH tunnel (`ssh -L 7000:localhost:7000 server`).

## The display in a web browser: `wweb`

```sh
adisplayd -web 8080 -webtoken mysecret1 &       # open  http://127.0.0.1:8080/?t=mysecret1  in any browser
```

Nothing has to be installed on the viewing side: the page draws the display on a canvas and sends the mouse (move, buttons,
wheel) and the keyboard back over a WebSocket. Several browsers can watch at once, together with VNC viewers and a framebuffer.
Only the changed parts of the screen are sent, run-length coded. `-webhost 0.0.0.0` serves other computers (a token is then
required; one is made and printed when you do not give one). In a program: `srv->addBackend(new wweb.Web(w, h, port, host, token))`.

* **Safety**: the page and the WebSocket need the token (in the address), a wrong token makes the next try wait, and the
  WebSocket refuses an `Origin` that is not the page's own host (so a page on another web site cannot take the display over
  from your browser). It is plain http: the token and the screen are readable on the network path; use an SSH tunnel
  (`ssh -L 8080:localhost:8080 server`) on networks you do not trust.
* **Protocol**: documented at the top of `lib/wweb.a`; `docs/web/index.html` is the page (`docs/gen_wweb_page.py` turns it
  into `lib/wwebpage.a`), and `tests/gui/webclient.py` is an independent client that the tests use.
* **Keys**: the page sends the browser's keys as `adp` key codes with the typed character; browser shortcuts such as Ctrl+W
  or Ctrl+T cannot be captured by a page.

## TCP, UDP and a chat: `gnet`

`gnet.Conn` is a TCP connection that lives in the event loop (`onLine` for text protocols or `onData` for raw bytes, `onClose`,
`sendLine`, `close`), `gnet.Listener` accepts them (`onAccept`, the new connection is `l->accepted`), and `gnet.Beacon` sends and
receives UDP datagrams (`broadcast`, `send`, `onPacket`). None of them blocks the window; they use `d->watch` (up to 64
descriptors per display connection).

`gnet.Chat` is a peer-to-peer chat made from them: every program listens, announces its name by UDP every 3 seconds, and
connects to the others it hears (of two peers the one whose `name@port` sorts higher connects, so there is one connection per
pair; duplicate names are refused). `chat->say("text")` reaches everybody, `onEvent` reports joins, leaves and messages.
`examples/gui/achat.a` is a chat program with a peer list, a log, notifications for messages that arrive while the window is in
the background, and Chat > Connect for an address by hand. There is no encryption or login: use it on a network you trust.

## Networking from a GUI program: `gnet` and `anet`

```c
gnet.Fetch* f = new gnet.Fetch();
f->onDone = finished;                                  // int finished(int fetch) { ... f->status, f->body ... }
f->onProgress = progress;                              // f->received of f->contentLength bytes
f->start(display, "http://example.org/", null);        // returns at once; the window stays responsive
f->cancel();
```

`Fetch` is an HTTP/1.1 request inside the event loop (`f->post("a=1&b=2", null)` makes it a POST with a body; a form POST answered
with a redirect is followed with GET, like a browser does; **cookies**: `Set-Cookie` headers go into `gnet.cookies()`, a `CookieJar`
by host name, and are sent back to the same host, so logins work; `f->useCookies = false` skips this; Path, Domain and expiry are
not used, `Max-Age=0` or an empty value deletes a cookie) (`d->watch`): redirects (up to 5), chunked bodies, `Content-Length`, a
check that the body is complete, and **`https://`** (TLS 1.3, see [TLS.md](TLS.md): the certificate is checked against the system's
roots unless `f->verifyCerts = false`; afterwards `f->secure`, `f->cipher`, and for a refused certificate `f->certError`). Connecting and
name lookup still wait (4 s at most). `gnet.Scan` tests the ports of a host one per turn of the event loop (`onFound`, `onProgress`, `onDone`, `stop()`).
`examples/gui/anet.a` is a network tool made of them and of `netif`, `dns` and `netutil`: interfaces, connections, ARP table,
routes, DNS lookups (A, AAAA, MX, NS, TXT, CNAME), an HTTP fetch with headers and body, a port scanner, TCP connect timing.

## A web browser: `ghtml` and `abrowse`

```c
import ghtml;
ghtml.HtmlView* v = new ghtml.HtmlView();
v->onLink = clicked;                       // int clicked(int view): v->linkHref (already absolute)
v->onHover = hovering;                     // v->hoverHref, null off a link
v->setHtml("<h1>Hello</h1><p>A <a href='x.html'>link</a>.</p>", "http://example.org/");
v->setMarkdown(text, "file:///home/me/notes.md");
v->setPlain(text, "x");                    // plain text in a <pre> block
// pictures: v->imageCount(), v->imageSource(i) are the wanted ones; v->setImage(address, surface) supplies one
```

`HtmlView` draws headings (h1 to h6, the big ones scaled), paragraphs, lists (nested, ordered or not), preformatted text, block
quotes, rules, tables (cells side by side), links, bold, code, underline and images (with their alt text until they are
loaded). It does not do CSS, forms, frames or scripts (they are skipped), italics or colours. The view scrolls (wheel, keys,
scroll bar), shows the hand cursor over links and relays out when its width changes. `ghtml.parseHtml`, `markdownToHtml`
(headings, paragraphs, lists, code blocks, quotes, tables, rules, links, images, **bold**, *italic*, `code`), `plainText`,
`decodeEntities` and `resolveUrl(base, ref)` (relative, absolute, `..`, `#fragment`, `//host`) work on their own.

`examples/gui/abrowse.a` is a browser made of `HtmlView`, `gnet.Fetch` (pages load without freezing the window), `gimg` (the
pictures of a page load four at a time in the background) and the toolbar widgets: address bar, back/forward/reload/home, history
that remembers the scroll position, files and Markdown (`abrowse docs/GUI.md`), images and plain text, view source. There is
`https://` pages are fetched over TLS and the status bar shows `Secure: TLS_AES_128_GCM_SHA256` (or `Not secure (plain http)`);
a site whose certificate is refused shows a "Your connection is not private" page with the reason, **Back to safety** and
**Proceed anyway (unsafe)**, which opens that host without checking its certificate until the browser is closed.

**Forms**: `<form action method>` with `input` (text, password, search, email, number ... as text fields; checkbox; radio;
submit, button, image; hidden), `textarea`, `select` with `option` and `button` become real widgets inside the view (they
scroll with the page, Tab moves between them and brings them into view). A click on a submit button, or Enter in a text field,
collects the fields in order as `name=value` pairs (URL-encoded, `+` for spaces, `%0D%0A` for newlines; unchecked boxes and
radios are left out, and only the submit button that was used is sent) and calls `view->onSubmit`: `submitMethod` (`GET` or
`POST`), `submitUrl` (for GET the query is added to the action address) and `submitBody`. `abrowse` sends them with
`gnet.Fetch`; the back button repeats the address with GET.
**Anchors**: `<h2 id=x>` and `<a name=x>` can be linked to with `#x`: `view->scrollToAnchor("x")`, `view->anchorY("x")`;
`abrowse` scrolls on a click and for addresses with a fragment.

Text at other sizes: `surface->textScaled(font, x, y, text, colour, percent)` (and `scaledWidth`) draws text larger or smaller
with bilinear sampling.

## Images: `gimg`

```c
import gimg;
gfx.Surface* s = gimg.load("photo.png");            // PNG, BMP or PPM/PGM (by content); null if it cannot be read
gfx.Surface* t = gimg.fit(s, 300, 200);              // smooth, keeps the proportions; gimg.scale(s, w, h) for any size
gimg.savePng(s, "copy.png");                         // 8-bit RGBA, stored without compression
col->add(new gui.ImageView(t));
```

PNG: every colour type and bit depth (not interlaced), palettes with transparency; BMP: 1, 4, 8, 24 and 32 bits without
compression; the decoder contains its own inflate. `gimg.decode(bytes, n)` and `gimg.encodePng(surface, &n)` work in memory.
`examples/gui/aview.a` is an image viewer (open, save as PNG, zoom, fit to the window).

## A taskbar and minimizing

Windows have a minimize button next to maximize. The display server can list the normal windows of all clients and control
them (`adp.Q_LISTWIN` / `Q_WINCMD`); in `gui` that is `d->requestWindowList()` (the answer calls `d->onWinList`, the data is in
`d->winList[i]->gid / state / title`, `nWinList`) and `d->windowCommand(gid, adp.WC_ACTIVATE | WC_MINIMIZE | WC_CLOSE |
WC_MAXIMIZE)`. `examples/gui/apanel.a` is a taskbar made of it: a button for every window (click: show or minimize),
launchers (`apanel Terminal=aterm Files=afiles`) and a clock. Panels, wallpapers, undecorated and no-focus windows are not
listed.

## A terminal: `gterm` and `aterm`

```c
import gterm;
gterm.Terminal* t = new gterm.Terminal();
t->flex = 1;
col->add(t);
window->setRoot(col);
t->onExit = shellEnded;              // int shellEnded(int terminal) { ... }
t->start(display, null);             // runs $SHELL; start(display, "ls -l") runs a command through /bin/sh -c
```

`aterm` (`examples/gui/aterm.a`) is a terminal program made of it: `ADISPLAY=0 ./aterm` opens your shell, `./aterm htop`
runs a command and closes when it ends. Ctrl+Shift+N opens another window, Ctrl+Shift+W closes one.

* **What it understands**: UTF-8 (Latin-1 characters are drawn with the built-in font, the box-drawing and block characters
  are drawn as lines and rectangles, arrows and triangles (`▸ ▾ ◂ ▴ ▶ → ...`) as small solid shapes, a few punctuation and symbol characters
  by plain ASCII stand-ins (`…` is `.`, `–` is `-`, `✓` is `*`; test `t272`), other characters show as `?`), colours with 16, 256 and 24-bit values, bold, dim,
  underline, reverse; cursor movement, erasing, inserting and deleting characters and lines, scroll regions, tabs; the
  alternate screen (vim, less, top, nano, mc work); application cursor keys, bracketed paste, cursor reports and device
  attributes, the size report (`CSI 18 t`), window titles (`OSC 0` and `OSC 2`; the window title follows unless `onTitle` is set),
  and **mouse reporting for programs** (modes 1000, 1002, 1003 with the SGR form 1006 or the old form, wheel, drags; hold Shift to
  select text instead) and focus reports (1004): what the [terminal toolkit](TUI.md) needs. `TERM` is `xterm-256color`.
* **Keys**: arrows, Home/End, PageUp/Down, Insert/Delete, F1-F12 with the Shift/Alt/Ctrl variants, Ctrl+letters, Alt+key
  (sends Esc first), Shift+Tab. **History**: 2000 lines; mouse wheel or Shift+PageUp/PageDown. **Mouse**: select by dragging
  (a double click selects a word); a selection is copied to the clipboard when it is made, the middle button and
  Ctrl+Shift+V paste, Ctrl+Shift+C copies. The size of the pseudo terminal follows the widget (the program gets `SIGWINCH`).
* **Without a program**: `t->feed("text\r\n")` writes to the screen as if a program had printed it, and what the user types
  is collected for `t->takeSent()`; `lineText(row)`, `cursorRow`, `cursorCol`, `selectedText()` read the screen back.
* **Limits**: Linux and Android only (Windows has no pseudo terminals here: `start` returns false); no wide (CJK) characters
  (they take one cell), no italics, no clipboard sequence (`OSC 52`), one font size.

Two small additions to `gui` made it possible: `d->watch(fd, f, arg)` calls `int f(int arg)` whenever a file descriptor
(a pipe, a pseudo terminal, a socket) is readable inside the event loop (`d->unwatch(fd)`), and `d->requestPasteTo(widget)`
asks the clipboard and calls `widget->onPaste(text)`.

## The code editor widgets: `gcode`

`import gcode;` - the widgets of the AIDE code editor (see [AIDE.md](AIDE.md) for the engine they sit on: `acode` buffers and editors,
`asyntax` highlighting, `atheme` themes, `aproject` project tree and build jobs, `afind` search). `examples/gui/codedemo.a` assembles all of
them into a small editor window (menu bar, sidebar with files and outline, tabs, editor, find / go to line bars, build output, terminal, status
bar, command palette, theme editor and settings); it is the base of the real AIDE GUI.

```c
import gui;  import gcode;
gui.Display* d = gui.connect(null);
gui.Window* w = d->createWindow("Editor", 800, 500, 0);
gcode.CodeEditor* e = new gcode.CodeEditor();       // has an empty document of its own
e->open("main.a");                                  // 0 or -errno; language and indentation are detected
gui.Box* col = gui.vbox(0, 0);   col->add(e);   w->setRoot(col);   w->setFocus(e);
gcode.theLook()->setThemeName("monokai");           // every gcode widget changes its colours at once
d->run();
```

All widgets take their colours (and the editors their font) from a `gcode.Look`; `gcode.theLook()` is the shared one. A theme change
(`look->setThemeName("nord")`, `look->setTheme(t)`, or edit `look->theme` and call `look->refresh()`) repaints every registered widget at once;
`look->setFontIndex(gcode.FONT_SANS)` or `setFontFile(path)` changes the font, `look->setLineGap(n)` the line spacing. Preferences (`tabWidth
insertSpaces lineNumbers wordWrap autoIndent trimOnSave finalNewline showWhitespace indentGuides highlightLine highlightWord matchBrackets blink
autoComplete`) are fields of the Look; `look->changed()` tells the editors to copy them. `look->applySettings(settings)` / `storeSettings` convert
to and from `atheme.Settings` (which has a `font` entry for this: `mono`, `sans`, `sansbold` or the path of a font file).
User themes are `NAME.ini` files in `gcode.themeDirectory()` (`<config dir>/themes`, or the directory given to `setThemeDirectory`).

### Documents and the editor

* **`Doc`**: a buffer, its `acode.Editor` (cursors, undo), an `asyntax.Highlighter`, the language, diagnostics and bookmarks. `doc->open(path)`,
  `save(path or null)` (atomic; trims / adds the final newline according to the Look), `setText`, `setLanguage`, `isModified()`,
  `addMark(line, col, len, SEV_ERROR, "text")` (gutter marker + squiggle), `toggleBookmark(line)`. Markers and bookmarks follow the lines when
  text is inserted or deleted above them. The tabs of an IDE are Docs: `editor->setDoc(doc)` shows another one and keeps the scroll position of the
  old one in it. All Docs share one `gcode.completer()`.
* **`CodeEditor`** (a `gui.Widget`, flex 1): gutter with line numbers (current line lit), bookmark and error / warning markers; syntax colours from
  the theme; blinking caret; selections, current line, find matches, other uses of the word at the caret and the matching bracket drawn behind
  the text; inline squiggles; indentation guides and white space marks (options); horizontal scroll or word wrap (`setWordWrap`); scroll bars
  and wheel; a completion popup; a context menu (`editor->menu`, add your own items); read-only mode (`setReadOnly`). Only the visible lines are
  drawn and lexed, and an edit repaints only the rows that changed: a 100 000 line file scrolls and takes input like a small one (the
  exceptions are listed under "Notes and limits"). `editor->setLook(look)` gives an editor a Look of its own (a preview); `editor->dispose()`
  lets go of the Look, the document, the timers and the highlight when the editor is not needed any more (the Doc is freed by its owner).
* **Keys**: arrows, Shift extends, Ctrl = by word, Home / End (smart), Ctrl+Home / End, PgUp / PgDn, Tab / Shift+Tab (indent / outdent a
  selection of lines), Enter (auto indent), Backspace / Delete (Ctrl: by word), Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z, Ctrl+C / X / V (the display
  server's clipboard), Ctrl+A, Ctrl+D (next occurrence), Ctrl+L (line), Ctrl+/ and Ctrl+Shift+/ (comments), Ctrl+] / [ (indent), Ctrl+Shift+D
  (duplicate), Ctrl+Shift+K (delete line), Ctrl+J (join), Alt+Up / Down (move lines), Alt+Shift+Up / Down (copy lines), Ctrl+Alt+Up / Down (more
  cursors), Ctrl+Up / Down (scroll), Ctrl+Space (completion), Ctrl+F2 / F2 / Shift+F2 (bookmarks), Esc (extra cursors, selection, popup). UTF-8 text
  of any code point can be typed. Keys the editor does not use (Ctrl+S, Ctrl+F ...) go on to the window: see `Commands` below.
* **Mouse**: click, double click (word), triple click (line), drag (a double or triple click then drag selects by words or lines), Shift+click,
  Ctrl+click (another cursor), Alt+drag (rectangular selection), wheel (Shift: sideways), scroll bar thumbs and tracks, gutter (left strip:
  bookmark; numbers: select line, drag for several), right click (context menu), dragging outside scrolls. `doubleClickMs` is the click interval.
* **Callbacks and observers**: `onChange`, `onCursor`, `onScroll`, `onGutter`, `onContextMenu` (`int f(int editor)`); several widgets can listen
  at once through `editor->observe(f, user)` with `f(user, editor, event)` and `EV_CHANGE | EV_CURSOR | EV_SCROLL | EV_DOC`.
* **Completion**: Ctrl+Space, or by itself (`autoComplete`, after `completeDelayMs` = 100 ms of silence, two letters). Candidates are the keywords of the
  language, the symbols and the words of every open Doc; Up / Down / PgUp / PgDn / Tab / Enter / Esc, a click on a row; typing narrows the list.
  The work is linear in the number of words that share the typed prefix (40 000 words: 60 ms; it was quadratic and took 45 s), and a buffer of
  1 MB or more is scanned for words again only after 25 edits (or a change of 2000 bytes, or a new language), so the newest words of a huge file
  show up a little late.
* **Programmatic use**: `gotoLine(line, col)`, `select(a, b)`, `revealCaret()`, `centerLine`, `setFindHighlight(pattern, afind options)`, `scrollRows`,
  `setFirstLine`, `cmdCopy / cmdPaste / cmdUndo ...`, `getText()`, `getSelectedText()`, `pointOfOffset(off, &x, &y)` and `offsetAtPoint(x, y)`
  (used by the tests), `touch()` after you changed the buffer or the cursors yourself.

### Panels and bars

| Widget | What it does |
|---|---|
| `FileTree` | project explorer on `aproject.FileTree`: lazy folders, `.gitignore` rules, icons by file type drawn with gfx primitives, keyboard (arrows, Right / Left, Enter, Home / End, type-ahead: letters typed within `typeAheadMs` = 1 s form a name prefix, so `file59` lands on `file59.txt`, one letter again and again cycles through the names that start with it; F2 rename, Del delete, F5), filter box (also searches folders that were never opened), inline name field for new file / new folder / rename, delete with a confirmation dialog (non-empty folders are refused), context menu, refresh by polling (`pollNow()`; a timer calls it every 1.5 s), `onOpen(tree)` with `tree->openedPath`, `revealRel("src/main.a")` |
| `TabBar` | tabs (`addTab(title, userData)`), modified dot, close buttons, middle click closes, `onClose` can veto, neighbour selection after a close, drag to reorder (`onMove`), overflow arrows + list of all tabs, the mouse wheel scrolls the tabs when they overflow, right click (`onTabContext`) |
| `FindBar` | find / replace panel on `afind`: incremental, Enter / Shift+Enter, "3 of 12" count, case / whole word / regular expression / in selection toggles (Alt+C / W / R), invalid expression shown, Replace, Replace All (one undo step), highlights in the editor, Esc closes; follows the document the editor shows (after a tab switch the count, Enter, Replace and Replace All work on the new text at once, the pattern is applied to it again; the "in selection" range is forgotten); in a narrow window the count and then the option buttons give way so that the find field keeps room |
| `GotoBar` | `12`, `12:5`, `+10`, `-3` (`gcode.parseGoto`) |
| `StatusBar` + `EditorStatus` | sections with clicks; the editor status shows position, selection / cursors, tabs or spaces (click toggles), encoding, line ends (click cycles), language, read-only |
| `Outline` | the symbols of the document (`asyntax.symbols`): kind badges, filter box, click jumps, follows the caret, refreshes after edits and when the document or its language changes |
| `OutputPane` | build output with ANSI colours (16, 256 and 24-bit, also the colon forms `38:2:r:g:b`; background colours are skipped, window titles / hyperlinks / character set selections are swallowed), carriage returns, a line limit (and a line that never ends is cut after 4000 bytes), follow-the-end; diagnostics are recognised and coloured; **Problems** list; click or Enter on a problem (or a `file:line:col:` line) calls `onJump(pane)` with `jumpPath / jumpLine / jumpCol` (1 based); `attachBuild(aproject.BuildJob*)` follows a running job (Stop, Clear, exit code) |
| `TerminalPane` | a `gterm.Terminal` in the colours of the theme: `start(display, command)`, `feed`, `send`, `stop`, `onExit` (Linux and Android; the program is collected: SIGHUP, 300 ms to leave, then SIGKILL, so no zombies) |
| `PanelTabs`, `Dock` | tabs over pages; the docking layout sidebar \| centre / bottom panel with draggable dividers (minimum sizes, `showSidebar`, `showBottom`, `onLayout`); a panel that would leave the centre smaller than `minCenter` x `minCenterH` is left out until the window is big enough, and `sideW` / `bottomH` keep what the user chose |
| `Commands`, `Palette` | a registry of commands (`add(id, title, "ctrl+shift+p", f, user)`, `setKeys` with conflict check, `applySettings` / `storeSettings` for the user's `[keys]`), `install(window)` makes the window offer keys to the registry first (a menu bar keeps working behind it); `Palette` is the overlay for commands, files (`showFiles(window, aproject.QuickOpen*)`) or your own list, with fuzzy matching |
| `ColorPicker` | hue bar, saturation / value square, R G B H S V sliders, hex field (`#rrggbb`, `0x`, names), swatches, old / new preview; `gcode.pickColor(display, title, rgb, f)` is a dialog |
| `ThemeEditor` | a window that lists every theme colour and syntax style, edits them with the picker, shows a live preview editor and the contrast warnings of `Theme.validate`, loads / saves / duplicates / deletes user themes (built-in ones are protected), reverts, and applies every change to all open editors at once (`live`); the window can be opened again and again: its preview editor, document and Looks are freed when it closes |
| `SettingsDialog` | tab width, spaces or tabs, line numbers, wrap, auto indent, trim on save, final newline, white space, guides, highlights, blink, completion, font, theme, line spacing: every control applies at once to the Look and the open documents, and updates the `atheme.Settings` |
| `SearchPane` (gcode_ide) | find in files: a query field, options (case, whole word, regular expression), a file name pattern, Search / Stop; the results are lines `path:line:col: text` in a list where **one click** calls `onJump(pane)` with `jumpPath` (as listed, relative to the root) / `jumpLine` / `jumpCol` (1 based); the search runs in steps from a timer (`step()` by hand in tests), `stepMs`, `matches`, `files` |
| `RunPane` (gcode_ide) | the output of a program (`start(job, name)` follows a started `aproject.Job`) and an input line: Enter sends the line to the program's standard input (and shows it), Ctrl+D ends the input, Ctrl+C in the empty line stops the program; header with Stop and Clear; `onFinished(pane)` with `exitCode` / `signal` (`signalName`), a diagnostic-like line is clickable (`onJump`) |
| `DocView` (gcode_ide) | a list of pages and a `ghtml.HtmlView`: `openDocs()` lists the Markdown files of the documentation folder (`$AIDE_DOCS`, `/usr/share/a/docs`, `/usr/local/share/a/docs`, `./docs`) and the AIDE manual (`/usr/share/aide/aide.md`); links between pages, anchors, `back()`, `onOpenFile` for links to source files (test `t282`) |
| `RowList`, `FlatButton`, `LineEdit`, `BarBox`, `BarLabel` | the themed building blocks (a list with scroll bar, a flat / toggle button, a `gui.TextBox` with theme colours and `onSpecial` for Esc / Up / Down / Tab / Alt+letter) |

### Notes and limits

* The editor draws on a grid of cells (the font's widest glyph); with `mono` (the default) every glyph fits, with `sans` the glyphs are centred
  in their cells. Wide (CJK) characters take two cells, combining marks none; characters above Latin-1 show as `?` (the font has only Latin-1).
  Bold is drawn by striking the text twice, italic is not drawn (the colour is).
* Word wrap breaks at a column, not at a word. Code folding, a minimap, split views with separate cursors (two editors on one `Doc` share
  its cursors) and bidirectional text are not there.
* `guix.MenuBar` and the dialogs of `guix` keep the standard (light) look; the `gcode` widgets are themed.
* Windows that are closed take their widgets out of the Looks (`Look.prune`, run before every notification); `gui.Window.onClosed` tells
  you when a window is gone (also when the program closed it) and the window's pixels are freed then. Dialogs that make documents or
  Looks of their own (the theme editor) release them there.
* A font file that cannot be used (missing, damaged, or without line height: an all-zero file) is refused by `gfx.loadFont` / `look->setFontFile`;
  `look->setFontName(name)` then uses the mono font and returns false. The editors never divide by the font size: the line height is at least 1.
* Key values that are not text (surrogates, above 0x10FFFF, control characters; a VNC client can send any 32 bit value) are ignored by
  `CodeEditor` and `gui.TextBox` (`gui.isTextChar`), so the text stays valid UTF-8.
* Performance that is worse than "like a small file": the first completion in a 5 MB file scans it (about 0.35 s); typing in a 3 MB file that is
  one single line costs about 150 ms per key; the Outline of a 100 000 line file (25 000 symbols) is rebuilt in about 230 ms after a pause in the typing (250 ms; up to
  2 s for documents over 500 KB, so that it happens less often); with `completeDelayMs = 0` every key of a 5 MB file waits for a scan.
* Small windows: from about 320 x 240 on the demo is usable (the panels give way); below that nothing breaks (checked from 40 x 30 to 2400 x 1600)
  but there is no room left for text.
* The test pattern: `tests/gcode_harness.inc` runs the display server in the test process (`Headless`), moves the pointer, types and takes
  window checksums; `settle()` sends a ping behind everything the client wrote, so big windows are finished before the test looks.

## The display server: `wsrv`

```c
wsrv.Headless* b = new wsrv.Headless(800, 600);      // or wvnc.Vnc / wfb.Framebuffer
wsrv.Server* srv = new wsrv.Server(b, 7000);         // listens on 127.0.0.1:7000
srv->addBackend(otherBackend);                        // several outputs at once
srv->run();                                           // or: while (...) { srv->step(20); }
```

* **Window manager**: title bars with close, maximize and minimize buttons (a double click on the title also maximizes; windows
  with `F_FIXED` do not maximize; `srv->toggleMaximize(win)`), move by dragging the title, resize with the grip at the bottom right,
  focus follows the click, windows come to the front; `Alt+Tab` switches, `Alt+F4` asks the window to close. The
  window decides (`E_CLOSE`), the server never kills a program.
* **Layers**: `F_BELOW` windows stay under everything, `F_ABOVE` windows over everything; `F_NODECOR` windows have no frame;
  `F_LOCK` windows are screen lockers (see below).
* **Input**: pointer events go to the window under the pointer (to the window that was pressed while a button is down),
  keys go to the focused window. The cursor is drawn by the server (arrow, text beam, hand, two resize arrows:
  `CURSOR_SIZE_H`, `CURSOR_SIZE_V`).
* **Embedding**: `srv->screen` is the screen surface (take screenshots with `savePPM`), `srv->windowCount()`, `windowAt(i)`,
  `clientCount()`, `disconnectAllExcept(clientNumber)`, `setBackground(top, bottom)`.
  `allowScreenshots` and `allowInject` (default off) let clients take screenshots and inject input (used by `actl` and tests).
* **Headless backend** for tests: `moveTo click buttonDown buttonUp scroll keyDown keyUp tap typeText`.
  In one process, `gui.idleHook = f` (a function that calls `srv->step(0)`) lets a client library connect to a server that
  runs in the same program; see `tests/t111_gui_server.a`.

### VNC (`wvnc`)

`new wvnc.Vnc(1024, 768, 5900, "127.0.0.1")` serves RFB 3.3 / 3.7 / 3.8 with the Raw encoding for 8, 16 and 32 bit true colour
formats; several viewers at once. There is **no password and no encryption**: the default host is 127.0.0.1; for remote use
tunnel it (`ssh -L 5900:localhost:5900 host`).

### Framebuffer (`wfb`)

`new wfb.Framebuffer("/dev/fb0", "us")` (layout `us` or `fi` with AltGr). 32 and 16 bits per pixel; relative mice, wheel,
absolute devices and touch screens; `takeConsole = true` puts the text console in graphics mode and silences its keyboard
while the display runs (`shutdown()` restores it). Untested without a framebuffer device: the key mapping and pixel
conversion are covered by `tests/t114_gui_input.a`.

## The display protocol (`adp`)

Messages are `int32 length, int32 opcode, payload` with little-endian 32-bit integers; pixels are blue, green, red, alpha.
Requests: `Q_HELLO Q_CREATE Q_DESTROY Q_TITLE Q_MOVE Q_RESIZE Q_PRESENT Q_VISIBLE Q_RAISE Q_FOCUS Q_CLIPSET Q_CLIPGET Q_CURSOR
Q_PING`; events: `E_WELCOME E_EXPOSE E_MOUSE E_KEY E_FOCUS E_CLOSE E_RESIZE E_CROSS E_CLIP E_PONG`. The full description with
the fields of each message is in the header of `lib/adp.a`. Any program (in any language) that speaks this protocol is a
client.

## The display manager: `dm` and `adm`

(A fuller display manager and display server for Linux and AOS lives in its own repository, https://github.com/alluur/adm: sessions chosen at login, a secret per session, automatic login, `$5$` hashes, `admctl`, a systemd unit and a Debian package. It is built on the same `wsrv`, `wfb` and `gui` modules. The `dm` module and `examples/gui/adm.a` described here stay as the small version.)

```sh
ac examples/gui/adm.a -o adm
ac examples/gui/asession.a -o asession    # a small desktop: wallpaper, panel with launchers and a clock
./adm /etc/adm/adm.conf
```

`adm` runs the display server, shows a login window, checks the password, starts the session and shows the login window again
when the session ends (all programs that are still connected are disconnected).

```
# /etc/adm/adm.conf
port = 0                     # display 0 = port 7000
fb = /dev/fb0                # "none" = no framebuffer
layout = fi
vnc = 0                      # VNC port (0 = off; numbers below 100 mean 5900 + n)
users = system               # /etc/passwd + /etc/shadow, or the name of a users file
session = /usr/local/bin/asession Calc=/usr/local/bin/calc Notes=/usr/local/bin/notes
greeting = Welcome
shutdown = /sbin/poweroff
reboot = /sbin/reboot
minuid = 1000                # system accounts below this uid cannot log in
allowroot = 0
takeconsole = 1
```

* **Users**: `users = system` needs root (to read `/etc/shadow`) and `$6$` (SHA-512) password hashes; other formats (`$y$`
  yescrypt, `$5$`, `$1$`) are refused. Or use a users file with lines `name:hash:uid:gid:home:session` (`session` empty = the
  default `session`); make a line with `dm.makeUserLine(name, password, salt, uid, gid, home, session)` (or `openssl passwd -6`).
  Locked accounts (`!`, `*`), root (unless `allowroot`) and uids below `minuid` cannot log in.
* **Sessions**: the command runs through `/bin/sh -c` in its own session, as the user (`setgroups`, `setgid`, `setuid`, `chdir` to
  the home directory) when `adm` runs as root, with `ADISPLAY`, `HOME`, `USER`, `LOGNAME` set.
* **Failed logins** make the next attempt wait 1, 2, 3 ... seconds (at most 8); a wrong user name takes as long as a wrong
  password.
* **Security notes**: the display port listens on 127.0.0.1 only, and every local user can connect to it; the display is
  therefore for the programs of one session. VNC has no authentication. The screen locker (`alock`) stops the keyboard
  and pointer of the display from reaching other windows; it is not protection against a local user who connects to the
  display port (such a client can create windows, and with `allowInject` send input), so on a shared machine also lock the
  console or session of the operating system.

## Limits

No hardware acceleration; one font family at one size (Latin-1); no input methods; the server and the clients are single
threaded and talk TCP over loopback; the clipboard is plain text. On Windows the server (with VNC), the toolkit and the
programs work; the framebuffer backend does not exist there and the display manager cannot start sessions (no `fork`).
