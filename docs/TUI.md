# The terminal user interface toolkit

A toolkit for full screen programs in the terminal, written in A: keys and mouse, colours that adapt to the terminal, a screen buffer that
writes only what changed, and a set of widgets (menus, dialogs, lists, trees, tables, tabs, a file picker, a colour picker, a command
palette ...) with an application loop. It is meant for the terminal version of an IDE, and for any other program that wants a text user
interface. It works on Linux terminals and on the terminals of AOS (serial console, the GUI terminal `aterm` / `gterm`, `telnetd`).

```c
import tui;

tui.App* app;
int onQuit(int b) { app->quit(0); return 0; }

int main() {
    app = new tui.App();
    if (!app->start()) { println("this program needs a terminal"); return 1; }   // raw mode, alternate screen, mouse, paste ...
    tui.Box* col = tui.vbox(1, 1);
    col->add(new tui.Label("Hello from A"));
    tui.Button* b = new tui.Button("&Quit");
    b->onClick = onQuit;
    col->add(b);
    app->setRoot(col);
    return app->run();                                                           // until quit(); the terminal is restored
}
```

Compile it like any program (`ac hello.a -o hello`); the modules are built into the compiler. Examples: [`examples/tui/gallery.a`](../examples/tui/gallery.a)
(every widget), [`examples/tui/files.a`](../examples/tui/files.a) (a two panel file manager).

Contents: [the four modules](#the-four-modules) · [the terminal layer](#the-terminal-layer-term) · [input](#input-keys-mouse-paste) ·
[capabilities](#capabilities-and-fallbacks) · [the screen](#the-screen-tscreen) · [widgets](#widgets-tui) · [the application](#the-application-tuiapp) ·
[tuix](#bigger-widgets-and-dialogs-tuix) · [your own widgets](#writing-your-own-widget) · [testing](#testing) · [AOS](#aos-and-the-aos-terminals) ·
[limitations](#limitations)

---

## The four modules

| Module | What it is | Needs a terminal? |
|---|---|---|
| `term` | key / mouse / paste decoding (`Decoder`, `Event`), key names, terminal capabilities (`Caps`), the terminal itself (`Terminal`: raw mode, size, polling, suspend), child programs (`Process`) | only `Terminal` and `Process` |
| `tscreen` | cells, colours, character widths, drawing primitives, the diff renderer (`Screen`, `Out`) | no |
| `tui` | `Widget`, containers, basic widgets, menus, `Dialog`, `Theme` and the `App` loop | only `App.start()` |
| `tuix` | `TreeView`, `Table`, `TextPane`, message / prompt / file / colour dialogs, command palette, `DirList`, fuzzy matching | no |

`import tuix;` also loads `tui`, `tscreen` and `term`. The decoder, the screen, the widgets and the `App` run without a terminal
(`App.initHeadless`), which is how most of the tests drive them (see [Testing](#testing)).

Things to know about A when using it:

* An object with a constructor must be made with `tui.Label l("x");` or `new tui.Label("x")`. A plain `tui.Label l;` does **not** run the
  constructor.
* A constructor of your own widget class that derives from a widget must start with `super();` (the base constructor is not run otherwise).
* `new` never frees. Widgets, dialogs and strings live until the program ends; the list, tree, table and text pane widgets reuse their own buffers
  when you `clear()` them.
* Callbacks are plain functions in `func` fields: `button->onClick = f;` with `int f(int button)`. The widget comes back as an `int`; cast it:
  `tui.Button* b = (tui.Button*) arg;`. `userData` fields carry your own pointer.
* Do not name a global `input`, `list`... that the standard library already uses (`input()` is a function there).

---

## The terminal layer: `term`

```c
term.Terminal t;                       // or new term.Terminal()
if (!t.open()) { return 1; }           // looks at stdin / stdout (else /dev/tty), reads the capabilities and the window size
t.enter();                             // raw mode, alternate screen, hidden cursor, mouse, bracketed paste
term.Event e;
for (;;) {
    t.wait(250);                       // input, a watched descriptor, a resize or 250 ms
    while (t.next(&e)) { ... }
}
```

**Raw mode and its restore.** `enter()` saves the termios, clears ECHO, ICANON, ISIG, IEXTEN, IXON, ICRNL ..., and sets the modes that the
terminal supports and the program wants. `restore()` (also `leave()` and `close()`) undoes everything, once. It runs

* when you call `leave()` / `close()`, and from `App.stop()`,
* from the `exit()` hook, so `exit(3)` deep inside the program restores the terminal,
* from the signal handlers of SIGINT, SIGQUIT, SIGHUP, SIGTERM, SIGSEGV, SIGBUS, SIGFPE, SIGILL and SIGABRT: the terminal is restored, the
  signal is re-raised with the default action (so the shell sees the right exit status), and for crashes `fatal signal N` is printed,
* when the terminal goes away (hang up): `Terminal.eof` becomes true and an `EV_HUP` event arrives.

A stack overflow cannot run a handler (A does not use `sigaltstack`): after such a crash type `reset`.

**What `enter()` writes:** `CSI 22;0 t` (save the window title), `CSI ? 25 l` (hide the cursor), `CSI ? 7 l` (no auto wrap), `CSI ? 1049 h`
(alternate screen), `CSI ? 1002 h` / `1000 h` / `1006 h` (mouse), `CSI ? 2004 h` (bracketed paste), and clears the screen. Only what the terminal
supports (`Caps`); `useAlt`, `useMouse`, `usePaste` switch parts off, `caps.mouseMotion` asks for all mouse motion (1003), `caps.focusEvents`
for focus in / out reports (1004). `leave()` writes the inverse (and clears the screen when there is no alternate screen).

**Window size.** The order is: `ioctl(TIOCGWINSZ)`; when the system reports no size (zeros: a serial console on Linux, a pipe to `/dev/tty`) `App.start()` **asks the
terminal** with `CSI 18 t` and, when that gets no answer within 250 ms, with a cursor position report (`ESC 7 CSI 9999;9999 H CSI 6 n ESC 8`); when that fails too, `LINES` and
`COLUMNS`; then 80x24. `Terminal.updateSize()` does the first, third and fourth step (and sets `sizeFromIoctl`), `Terminal.probeSize(ms)` the second. Set `TUI_PROBE=1` (or
`App.probeSize = true`) to ask the terminal even when the system reports a size (AOS' serial console always says 24x80), `TUI_PROBE=0` never to ask. Changes arrive as
`EV_RESIZE` events: from SIGWINCH where it works, and by polling the size every 200 ms where it does not (AOS, see below).

**Waiting.** `wait(ms)` blocks for at most `ms` milliseconds (-1: for ever, 0: only look) and returns the number of queued events. It reads with
`ppoll`, never with a blocking `read`, so a time out or a signal always returns. A lone Esc is resolved by a timeout (`dec.escMs`, 40 ms by
default): until then the decoder waits for the rest of a possible escape sequence. **Several descriptors at once:** `watch(fd)` adds a
descriptor to the poll; when it is readable an `EV_FD` event (`key` = the descriptor, `x` = the `POLL_` bits) arrives between the key events.

**Child programs.**

```c
term.Process p;  p.startShell("make 2>&1");          // or p.start(argv): the program is searched in PATH
t.watch(p.fd);                                       // stdout and stderr of the child come through one pipe
...  on EV_FD:  n = p.read(buf, 1000);               // 0 at the end, then:  status = p.finish();
p.kill(15);                                          // to the child's whole process group (it is made the leader of one)
```

`Terminal.runProgram(argv)` / `runShell(cmd)` leave full screen mode, run the program in the foreground with the terminal in its normal mode, wait
for it and come back (raw mode again; the caller must redraw: `App.runShell` does that). While the child runs, Ctrl+C reaches the child and
not the toolkit's handler. `suspendSelf()` stops the program like Ctrl+Z in a shell (SIGSTOP) and redraws after `fg`.

---

## Input: keys, mouse, paste

`term.Decoder` turns bytes into `term.Event`s: `feed(byte)`, `feedText(s)`, `flush()` (the Esc timeout expired), `next(&e)`. It is pure code
(no system calls), so its tables are tested on every target (`tests/t220_term_keys.a`, `t221_term_mouse_paste.a`).

An `Event` has `kind`, `key`, `mods`, `x`, `y`, `button`, `action`, `text`, `len`:

| `kind` | meaning |
|---|---|
| `EV_KEY` | `key`, `mods` |
| `EV_MOUSE` | `x`, `y` (cells from 0), `button`, `action`, `mods` |
| `EV_PASTE` | `text`, `len` (bracketed paste, the text is a copy that stays valid) |
| `EV_RESIZE` | `x` columns, `y` rows |
| `EV_FOCUS` | `key` 1 gained, 0 lost (needs `caps.focusEvents`) |
| `EV_FD` | a watched descriptor is readable |
| `EV_HUP` | the terminal is gone |
| `EV_REPLY` | an answer to `CSI 6 n` (`key` 'R') or `CSI 18 t` (`key` 't') |
| `EV_RESUME` | the program was continued after a stop or a shell: redraw |

**Keys.** A character key is its Unicode code point; `Ctrl+S` is `'s'` with `MOD_CTRL`. Named keys start at `KEY_BASE`: `KEY_ENTER KEY_TAB KEY_BACKSPACE
KEY_ESC KEY_UP KEY_DOWN KEY_LEFT KEY_RIGHT KEY_HOME KEY_END KEY_PGUP KEY_PGDN KEY_INSERT KEY_DELETE KEY_BEGIN` and `fkey(n)` for F1 to F24.
Modifiers: `MOD_SHIFT` 1, `MOD_ALT` 2, `MOD_CTRL` 4, `MOD_META` 8 (the xterm numbers).

Understood: UTF-8; Ctrl+letters; Alt+key as an Esc prefix (`ESC ESC [ A` is Alt+Up); arrows, Home, End in the `CSI`, `SS3` (`ESC O`) and
`ESC [ 1 ~` forms; `Insert Delete PgUp PgDn`; F1 to F20 in the xterm, VT220, Linux console (`ESC [ [ A`) and rxvt forms; the modifier forms
`CSI 1 ; m A`, `CSI n ; m ~`; Shift+Tab (`CSI Z`); the keypad in application mode; the fixterms / kitty `CSI code ; m u` and xterm
`modifyOtherKeys` (`CSI 27 ; m ; code ~`) forms. Enter is CR; LF is reported as Enter with `MOD_CTRL` (`Event.isEnter()` is true for both);
a NUL right after CR (telnet) is dropped. A terminal cannot tell some keys apart: **Ctrl+H is Backspace, Ctrl+I is Tab, Ctrl+M is Enter, Ctrl+[ is Esc,
Ctrl+J is Enter, Ctrl+/ and Ctrl+_ are the same byte (reported as Ctrl+/)**. Do not give them different meanings.

`keyName(key, mods, buf, cap)` writes `"Ctrl+Alt+Up"`; `parseKey("Ctrl+S", &mods)` goes back; `keyIs(&e, "Alt+F")` and
`keyMatches(...)` compare (an upper case letter counts as Shift + the letter); `encodeKey(key, mods, buf)` makes the bytes a terminal would send (for tests).

**Mouse.** SGR reports (`CSI < b ; x ; y M/m`, mode 1006) and the old X10 reports (`CSI M` + 3 bytes). `button`: `MB_LEFT MB_MIDDLE MB_RIGHT
MB_WHEEL_UP MB_WHEEL_DOWN MB_WHEEL_LEFT MB_WHEEL_RIGHT`; `action`: `MA_PRESS MA_RELEASE MA_DRAG MA_MOVE MA_WHEEL`. Motion without a button only arrives
when `caps.mouseMotion` is set.

**Paste.** With bracketed paste on, pasted text arrives as one `EV_PASTE` event (a Ctrl+Q inside a paste does not quit). A paste that never ends
is delivered after 3 seconds without input.

---

## Capabilities and fallbacks

`term.Caps` (`colors`, `utf8`, `mouse`, `altScreen`, `bracketedPaste`, `title`, `italic`, `cursorShape`, `cursorAddr`, `mouseMotion`, `focusEvents`,
`syncOutput`, `aos`) is made by `capsFromEnv` from `TERM`, `COLORTERM`, `LC_ALL` / `LC_CTYPE` / `LANG` and `NO_COLOR` with a built-in table
(`capsFor` is the pure function behind it, used by the tests):

| `TERM` | colours | mouse, alt screen, paste, title |
|---|---|---|
| `dumb`, `unknown` | none, and no cursor addressing: `App.start()` refuses | no |
| `linux`, `vt*`, `ansi`, `cons*` | 16 (`vt*`: none, `ansi`: 8) | no |
| `xterm`, `screen`, `tmux`, `rxvt`, `st`, `putty`, `konsole`, `gnome`, `vte`, `cygwin` ... | 16, or 256 with `256color` in the name, `st`, `konsole`, `gnome`, `vte`, `putty`, `cygwin` | yes (no title for `screen` / `tmux`) |
| `alacritty`, `kitty`, `foot`, `wezterm`, `ghostty`, `contour`, `iterm`, `*-direct`, `*truecolor*` | 24 bit | yes |

`COLORTERM=truecolor` (or `24bit`) raises an xterm-like terminal to 24 bit; `NO_COLOR` (non empty) removes colours (attributes stay). A locale of `C` /
`POSIX` or a non UTF-8 charset turns the box drawing characters and symbols into ASCII (`+ - | # > <` ...). Overrides for people and for tests:

| Variable | Effect |
|---|---|
| `TUI_COLORS=0\|8\|16\|256\|truecolor` | the colour depth |
| `TUI_MOUSE=0\|1` | mouse reporting off / on |
| `TUI_ASCII=1` | ASCII instead of UTF-8 symbols (`0` forces UTF-8) |
| `TUI_SYNC=1` | wrap frames in synchronized output (`CSI ? 2026`) |
| `TUI_MOTION=1` | ask for all mouse motion (menus then follow the pointer) |
| `TUI_PROBE=1` | ask the terminal for its size at the start |

The fields of `caps` can be changed by hand after `open()`. Colours are always **downgraded to the nearest colour** the terminal has:
24 bit to the 256 colour palette (the 6x6x6 cube and the gray ramp, nearest by a perceptual distance), to the 16 ANSI colours, to 8 (bright colours
become bold), or dropped. Attributes the terminal lacks (italic) are removed. `App.start()` picks a theme: `Theme.useDark()` (24 bit palette) for 256+
colours, `useClassic()` (blue and cyan, the 16 ANSI colours) for 16 and 8, `useMono()` (reverse, bold, underline only) without colours.

---

## The screen: `tscreen`

A `Screen` is a grid of cells with two copies: the **back buffer** you draw into, and a record of what the terminal shows. `render(&out, &caps)`
appends to an `Out` buffer exactly the escape sequences that bring the terminal up to date, and nothing when nothing changed: moves only where
needed (`CSI n C` for small gaps, `CR`, `CUP`), SGR only when the style changes, wide characters as one unit. After a resize or `invalidate()` the
whole screen is sent again. With `caps.syncOutput` a frame is wrapped in `CSI ? 2026 h ... l`.

```c
tscreen.Screen s(80, 24);              // stack objects need the parentheses (they run the constructor)
tscreen.Out out();   term.Caps caps();
s.clear(0);
s.box(2, 1, 30, 5, tscreen.BOX_ROUND, tscreen.style(tscreen.CYAN, 0, 0));
s.text(4, 2, "Hello \xe4\xb8\x96\xe7\x95\x8c", tscreen.style(tscreen.rgb(255, 200, 0), 0, tscreen.A_BOLD));
s.render(&out, &caps);                 // out.b, out.n: the bytes to write to the terminal
println(s.dump());                     // the screen as plain text
```

**Styles are one int**: foreground colour (26 bits) | background colour << 26 | attributes << 52. Colours: `0` (the terminal's default),
`rgb(r, g, b)`, `hex(0xRRGGBB)`, `idx(n)` (palette entry n; 0 to 15 are the ANSI colours `BLACK RED GREEN YELLOW BLUE MAGENTA CYAN WHITE` and `GRAY`,
`BRIGHT_*`). `COL_KEEP` as a background keeps the background that is already there (text on a panel). Attributes: `A_BOLD A_DIM A_ITALIC
A_UNDERLINE A_REVERSE A_BLINK A_STRIKE`. Helpers: `style(fg, bg, attr)`, `fgOf bgOf attrOf`, `withFg withBg withAttr addAttr delAttr`, `downgrade(colour, depth)`,
`nearest16`, `nearest256`, `paletteRgb(n)`.

**Drawing** (all clipped to the clip rectangle, `pushClip` / `popClip`): `put`, `text` (returns the column after, so texts can follow each other),
`textMax`, `textEllipsis`, `fill`, `hline`, `vline`, `box` (`BOX_SINGLE DOUBLE ROUND HEAVY`), `panel`, `restyle`, `attrs`, `shadow`, `blit`,
`setCursor(x, y, shape)` / `hideCursor`. `rowText`, `dump`, `runeAt`, `styleAt` read the buffer back (tests).

**Characters.** `runeWidth(cp)`: 0 for controls and combining marks, 2 for East Asian wide and fullwidth characters and emoji, else 1 (ambiguous
width counts as 1). The tables are generated from Unicode 15.1 by `docs/gen_width.py` (357 + 120 ranges, binary search). A combining mark is attached to the cell
before it (up to three); a wide character that does not fit at the clip edge is replaced by a blank; overwriting half of a wide character blanks the other
half. `textWidth`, `textWidthN`, `fitBytes` measure UTF-8 text. Without UTF-8 the renderer replaces box drawing, block, arrow and a few other characters with
ASCII, and everything else with `?` (a wide character with `??`).

---

## Widgets: `tui`

Every widget is a class derived from `tui.Widget`: position and size relative to the parent (`x y w h`), `flex`, `fixedW / fixedH`, `halign / valign`,
`visible`, `enabled`, `focusable`, `name`, `userData`, `parent`, `app`, children (`add insert remove removeAll`), and virtual methods

| Method | Use |
|---|---|
| `prefW()`, `prefH()` | the size it wants (`fixedW`, `fixedH` override) |
| `layout()` | place the children (containers) |
| `paint(screen, ox, oy)` | draw; (ox, oy) is where the top left cell is on the screen; children are painted afterwards |
| `onKeyPress(event)` | a key for the focused widget (return true when used); parents get it next |
| `onMouse(event, lx, ly)` | a mouse event, with the position relative to the widget; return true when used. On a press a widget can set `app->capture = this` to receive all events until the release (drags) |
| `onFocus(gained)`, `onPaste(text, n)`, `mnemonicChar()`, `activate()`, `wantsText()`, `onOutside(event)`, `onResize(cols, rows)` | |

Common callback fields: `onKey` (a hook that sees keys first: `int f(int widget, int event)`, return 1 when used), `onFocusChange`, `onContext` (right click).
`invalidate()` asks for a repaint, `relayout()` for a new layout, `focusMe()`, `canFocus()`, `hasFocus()`, `containsFocus()`.

| Widget | Notes |
|---|---|
| `Box` (`vbox(spacing, padding)`, `hbox`) | row or column; children with `flex` share the free space; `halign` / `valign` for the cross axis; `themed` paints the theme's window colours |
| `Frame(title)` | border (`kind`) and title around its child; the border lights up when the focus is inside |
| `Splitter(sideBySide)` | two children and a divider that the mouse drags (`ratio`, `minFirst`, `minSecond`, `setFirstSize`, `onMove`) |
| `TabView` / `TabBar` | `addPage(widget, "&Title")`, Alt+1..9, Ctrl+PgUp/PgDn, click, `bar->closable` and `onClose`, `closePage` |
| `Label` | multi line, `align`, `setStyle`, `ellipsis` |
| `Button("&OK")` | `onClick`, `isDefault`, `flat`, mnemonic (Alt+letter), Enter / Space / click; a press that is released elsewhere does nothing |
| `CheckBox`, radio buttons | `radio = true` and the same `name` among siblings; `onChange` |
| `TextInput` | one line: arrows, Home / End, Ctrl+Left/Right and Alt+Left/Right by word, Backspace, Delete, Ctrl+Backspace / Ctrl+W / Ctrl+Delete, selection with Shift, Ctrl+A, Ctrl+K / Ctrl+U / Ctrl+Y kill ring, Ctrl+C / X / V (and Ctrl+Insert, Shift+Delete, Shift+Insert), history on Up / Down, `completer` on Tab (common prefix, then a menu), password mode, `maxLen`, `readOnly`, placeholder, mouse (click, drag, double click for a word), bracketed paste |
| `ListView` | `add(text, data, style)`, selection, scrolling, scroll bar, `filterable` (type to narrow), `matcher` hook, `onSelect`, `onActivate`, overridable `drawItem` |
| `ProgressBar` | value / max with the percentage, or `indeterminate` + `step()` |
| `Slider` | `max`, `step`, `onChange`, optional `trackColor` hook for a colour gradient track |
| `StatusBar` | segments left or right aligned, `message(text, ms)` replaces them for a while |
| `ScrollBar` | model `setRange(total, page, pos)`, `onScroll`; `drawVScroll` / `drawHScroll` / `scrollPosFor` are what the lists use |
| `MenuBar`, `Menu`, `MenuItem`, `PopupMenu` | see below |
| `Dialog` | modal window with a content widget and buttons (see the application section) |

**Menus.** `MenuBar* mb = new MenuBar(); Menu* f = mb->addMenu("&File"); f->add("&Open...", action, "Ctrl+O");` Items: `add`, `addCheck`
(flips `checked` before the action), `addSeparator`, `addSub` (submenu), `enabled`. `app->setMenuBar(mb)` makes F10 (`noF10` turns that off), Alt+letter
(the mnemonic of the title) and the **accelerators** work everywhere; the accelerator text on an item ("Ctrl+O") is also its shortcut. Keys in an open
menu: Up / Down / Home / End, Enter, Right (submenu, or the next menu), Left (back), Esc, a letter (mnemonic). Mouse: click a title, click or press-drag-release
an item, hover switches menus (with motion reporting), a click elsewhere closes; a second click on the same title closes. `app->popupMenu(menu, x, y)` makes a
context menu that is moved to fit the screen.

**Layout** is simple: sizes flow down (`layout()`), preferred sizes flow up. In a `vbox` children are stretched to the full width unless `halign` is set; `fixedW`
and `fixedH` force sizes; `flex` shares what is left. Overlays (dialogs, menus, toasts) have absolute positions.

**Themes.** `tui.theme` is the current `Theme`: about 35 styles (`window`, `text`, `selection`, `input`, `button`, `menu`, `status`, `error` ...) and the character
that fills the background. `useDark()`, `useLight()`, `useClassic()`, `useMono()` change it in place (the screen repaints).

---

## The application: `tui.App`

```c
tui.App* app = new tui.App();
app->start();                 // false: no terminal (a pipe, TERM=dumb); nothing was changed
app->setTitle("my IDE");      // window title (restored when the program ends)
app->setMenuBar(mb);  app->setRoot(w);
app->addShortcut("Ctrl+S", save, userData);      // int f(int userData)
app->addCommand("File: Save", "Ctrl+S", save);   // listed in the command palette; the key is registered as well
int code = app->run();        // until quit(code); the terminal is restored; returns the code
```

**The loop** (`pump(maxWaitMs)`, `run()` calls it for ever): paint if something changed and write the difference; wait (until the next timer, at most
`maxWaitMs`); decode and dispatch events; run due timers; call `onIdle`. `onResizeHook`, `onKeyHook`, `onSuspend`, `onResume` are further hooks.

**Keys go** to: the app key hook; the menu bar (F10, Alt+letter, accelerators; not while a dialog or menu is open); shortcuts with Ctrl, Alt or a function key; the
focused widget (its `onKey` hook, then `onKeyPress`), then its parents; Alt+letter mnemonics of buttons and check boxes; Tab / Shift+Tab (focus moves
in the focus scope: the top overlay or the whole tree); finally the plain key shortcuts, but only when the focused widget does not want text (so a shortcut
on `x` does not steal typing in a text field).

**Mouse** events go to the widget under the pointer, then its parents; a press focuses the nearest focusable widget; `app->clicks` is 1, 2, 3 for double
and triple clicks (450 ms); a widget that set `app->capture` gets the drag; a click outside an overlay closes popups, and a modal dialog swallows it.

**Overlays and dialogs.** `showOverlay(w, modal)` / `closeOverlay`; popups and toasts are overlays. A `Dialog(title, content)` gets buttons with
`addButton("&Yes", resultCode, isDefault)`; Esc closes it with `cancelResult`, Enter presses the default button, Alt+letter the mnemonic button, arrows move between
buttons, the title bar drags it. Two ways to run one: `int r = app->runDialog(d)` waits in a nested event loop and returns the result (simple
code); `app->showDialog(d)` returns at once and `d->onClose` is called later (event driven code). In a headless app `runDialog` returns (as cancelled)
when no input is left, so a test can never hang.

**Timers.** `int id = app->addTimer(ms, f, userData, repeat); app->cancelTimer(id);` (64 at most, `int f(int userData)`). `app->advanceClock(ms)` makes a
fake clock for tests. **Descriptors:** `app->watchFd(fd, f, userData)` calls `int f(int fd, int userData)` when `fd` has data (a child's pipe,
a socket; 16 at most). **Clipboard:** `setClipboard(text)` keeps it for `TextInput` paste and sends it to the terminal's clipboard (OSC 52) where the
terminal has a title (xterm family). **Toast:** `app->toast("saved", 2000)`. **Programs:** `runShell(null)` (an interactive shell, comes back and redraws) and
`runProgram(argv)`; `suspendProcess()` is Ctrl+Z.

**Running without a terminal.** `app->initHeadless(80, 24)` makes an app that reads from the decoder: `feed(bytes)`, `press("Ctrl+S")`, `type("text")`,
`click(x, y)`, `mouseDown / mouseDrag / mouseUp`, `wheel`, `paste`, `resizeTo`, `advanceClock`, `inject` (queue bytes without handling them yet), and `text()`
returns the screen as text. `app->screen` holds the cells (`styleAt` for colours).

---

## Bigger widgets and dialogs: `tuix`

| | |
|---|---|
| `TreeView` | `addNode(parent, text, data, lazy)`, node 0 is the invisible root. A lazy node shows an arrow and `onExpand(tree, node)` fills it the first time. Keys: arrows, Right / Left (expand, collapse, go to child / parent), Enter / Space, `+ - *`; `select(node)`, `removeChildren`, `clear`, `onSelect`, `onActivate` |
| `Table` | `addColumn(title, width, align)` (width 0: flexible), `addRow(...)` (up to 8 cells), click a header to sort (numbers as numbers, text without regard to case), `sortBy`, `selectedRow`, `onSelect`, `onActivate` |
| `TextPane` | program output: `append(text)` (partial lines stay open until the newline, `\r\n` is one newline), `appendLine`, `appendBytes`; ANSI colour sequences are shown as colours; follows the end until you scroll up; `onLineClick` / `onLineActivate` with `clickedLine`; `selectable`, a line limit (`maxLines`), sideways scrolling, a scroll bar |
| `messageBox(app, title, text, b1, b2, b3)` | returns the button number (1..3), 0 for Esc; the text is word wrapped |
| `askYesNo`, `askYesNoCancel`, `prompt(app, title, label, initial)` | `prompt` returns a copy of the text or null |
| `fileOpenDialog`, `fileSaveDialog`, `directoryDialog` | a path field, a list that filters as you type, directories first, `../`, Alt+. shows hidden files, a name field when saving (asks before replacing a file); return the full path or null. `newFileDialog` + `fileDialogResult` for the non-blocking form |
| `colorDialog(app, initial)` | the 256 colour palette (arrows, mouse) and R / G / B sliders with gradient tracks and a hex field; returns `idx(n)` for a palette colour, `rgb(...)` otherwise, `COL_DEFAULT` for the Default button, -1 when cancelled; `newColorDialog` + `colorDialogResult` |
| `commandPalette(app)` | text field and a list of the app's commands with fuzzy matching and the matched letters highlighted; runs the chosen command; `newCommandPalette` |
| `fuzzyScore(pattern, text, positions, max)` | subsequence match with a score (consecutive letters and word starts score higher; shorter texts win) |
| `DirList` | read a directory with `getdents`: `load(dir, hidden, withSizes)`, `sort()` (directories first, then by name), `name(i)`, `isDir(i)`, `sizeOf(i)`; `joinPath`, `parentPath`, `cleanPath`, `currentDir`, `fileSizeOf`; works on Linux, Android and AOS (Windows: `load` returns false) |

---

## Writing your own widget

```c
public class Meter : tui.Widget {
public:
    int value;
    Meter() { super(); focusable = true; }                       // do not forget super()
    virtual int prefW() { return 20; }
    virtual int prefH() { return 1; }
    virtual void paint(tscreen.Screen* s, int ox, int oy) {
        s->fill(ox, oy, w, 1, ' ', tui.theme->progressTrack);
        s->fill(ox, oy, w * value / 100, 1, ' ', hasFocus() ? tui.theme->selection : tui.theme->progressFill);
    }
    virtual bool onKeyPress(term.Event* e) {
        if (e->key == term.KEY_RIGHT) { value = value < 100 ? value + 5 : 100; invalidate(); return true; }
        return false;
    }
    virtual bool onMouse(term.Event* e, int lx, int ly) {
        if (e->button == term.MB_LEFT && e->action == term.MA_PRESS) { app->capture = this; value = lx * 100 / w; invalidate(); return true; }
        if (e->action == term.MA_DRAG) { value = lx * 100 / w; invalidate(); return true; }
        return e->action == term.MA_RELEASE;
    }
}
```

Use the theme styles instead of fixed colours so that the widget looks right at every colour depth. A text cursor is placed with `s->setCursor(x, y)` (only when
`app->cursorOk(this)`: no overlay covers the widget).

---

## Testing

| Test | What it covers |
|---|---|
| `tests/t220` .. `t221` | the decoder: every key sequence, modifiers, Esc handling, mouse, paste, focus, replies, the queue |
| `t222` .. `t225` | colours and their downgrade, capabilities by `TERM`, character widths, drawing primitives, the diff renderer (exact escape strings, and 720 random frames replayed through a tiny terminal emulator at every colour depth and without UTF-8) |
| `t226` | key names, `parseKey`, the key encoder and a round trip over 500 key combinations |
| `t227` .. `t235` | widgets, input, lists, tree and table, menus, dialogs, layout and splitter, text pane, the application loop (all through `initHeadless`) |
| `t236` | `DirList` and the file dialogs on a directory tree the test makes (Linux; `.out.windows` says so) |
| `t237` | the real terminal layer on a pseudo terminal the test creates (raw mode, the sequences written, keys and mouse read from a real pty, Esc timeout, SIGWINCH, restore) |
| `t238` | `Process`: a child with a pipe, exit status, kill of a process group, several children |
| `t239` | a random session of 2500 keys, clicks, drags, pastes and resizes against a UI with every widget; invariants after each step |

They are ordinary tests (`tests/run.sh t22`, `t23`) and run on all five targets with the same expected output (`t236`, `t237`, `t238` print one line on Windows).
**`tests/tui.sh`** is the second layer: it compiles `tests/tui/probe.a`, `examples/tui/gallery.a` and `examples/tui/files.a`, starts them in a
pseudo terminal of a given size, sends keystrokes, mouse events, pastes and signals, and checks the screen rebuilt by a terminal emulator written in
Python (`tests/tui/ptyterm.py`: CSI, SGR with 256 and 24 bit colours, the alternate screen, wide characters, modes, titles, OSC 52). It checks typing, menus, mouse,
resizing (`TIOCSWINSZ` + SIGWINCH), paste, suspend to a shell and back, the unusual Esc timing, the size fallbacks (`LINES` / `COLUMNS`, `CSI 18 t`), crashes and
signals (the terminal must be back to normal afterwards), `TERM=linux`, `TERM=dumb`, no terminal at all, the colour depths, `NO_COLOR`, ASCII mode and the
file manager working on real files. Run one test with `tests/tui.sh name`.

---

## AOS and the AOS terminals

The toolkit was run on AOS in QEMU (without KVM): the serial console with `TERM=linux` (the default there, 16 colours) and `TERM=xterm-256color` (the probe program: modes, raw
mode, keys, the lone Esc, the menu, Ctrl+Q and the shell working again afterwards), the widget gallery and the file manager (listing real AOS directories, `getdents` with file
types), and the pseudo terminal test `t237` (`tests/t237_term_pty.a`, which makes a pty with `/dev/ptmx`, forks a child that uses the toolkit on it and drives it) and the
process test `t238`: `t237` prints exactly the same on AOS as on Linux (also compiled with `-DNO_SIGWINCH`, which proves that the size polling alone notices a window size
change), `t238` differs only where AOS's own `sh` differs (exit status 126 for a missing program, no `${VAR:+x}`). No unknown system call was logged on the console.
To try it, build the programs with `ac` and put them into the RAM disk: `AC=ac tools/mkroot.sh --add /bin/gallery=gallery:755 --add /bin/files=files:755`, then pack the image
as the AOS `Makefile` does (`tools/mkimage.py ...`) and run them on the console (`export TERM=xterm-256color; gallery`).
Differences from Linux that the toolkit works around, from reading `kernel/tty.a`, `kernel/sys.a` and `kernel/devio.a`:

| AOS | What the toolkit does |
|---|---|
| `VMIN` / `VTIME` are ignored by the tty; a `read` with no data blocks | never reads without `ppoll` saying that data is there; timeouts come from `ppoll` |
| `SIGWINCH` is only sent by `TIOCSWINSZ` to the tty's process group; a process blocked in `ppoll` is restarted after the handler, so the signal does not wake it | the handler is installed, and on AOS (detected with `uname`: release or version contains "aos") the size is polled every 200 ms |
| the serial console reports 24x80 whatever the real terminal is | `TUI_PROBE=1` / `App.probeSize` asks the terminal with `CSI 18 t`, then with a cursor position report (only a terminal emulator at the other end can answer) |
| no `sigaltstack` | not used (it would be logged as an unknown system call); also on Linux |
| no job control: SIGSTOP / SIGTSTP / SIGCONT are ignored | `suspendProcess()` returns at once: use `runShell` (suspend to a shell) |
| `rt_sigprocmask` does nothing | no signal masks are used |
| `setpgid(pid, pgid)` ignores its first argument | only `setpgid(0, 0)` is called, in the child |
| the default `TERM` is `linux` on the console (`/etc/rc` exports `xterm`, `telnetd` too, `gterm` `xterm-256color` with `COLORTERM=truecolor`) | `linux`: 16 colours, no mouse, no alternate screen (the screen is cleared on exit); set `TERM` for more |
| poll time out granularity is 10 ms | the Esc timeout (40 ms) works in steps of 10 ms |

Everything else the toolkit uses exists on AOS: `ioctl` (TCGETS, TCSETSW, TIOCGWINSZ), `ppoll`, `rt_sigaction`, `uname`, `mmap`, `fork`, `execve`, `wait4`,
`pipe2`, `dup2`, `kill` (also to process groups), `getdents64` with the file type. The GUI terminal `gterm` (used by `aterm`) understands the sequences the toolkit
writes: colours (16, 256 and 24 bit), cursor movement, erasing, scroll regions, the alternate screen, bracketed paste, window titles, and **mouse reporting
(1000, 1002, 1003, 1006 and the old form, focus reports 1004, `CSI 18 t`)**, added for this toolkit (Shift + mouse still selects text). What `gterm` does not have:
double width cells for wide characters (CJK and emoji take one cell there, so the toolkit's layout is off by one cell per wide character: use `TUI_ASCII=1` or avoid them), OSC 52,
the `CSI 22 t` title stack (ignored) and colon separated SGR parameters.

---

## Limitations

* No multi line editor widget (the IDE brings its own); `TextPane` is read only.
* Width: East Asian ambiguous characters count as one cell; emoji sequences (ZWJ, flags, skin tones) are drawn as separate characters; no right to left or shaping.
* Windows consoles are not supported (`Terminal.open()` is false); the decoder, screen, widgets and headless `App` do compile and run there.
* The Linux console has no mouse (no `gpm` support).
* Scrolling a large area is done by redrawing the rows that changed (no `CSI S` / `T` or scroll regions), which is fine except on very slow links.
* Memory is never freed (A's `new`); dialogs created for every use leak a few kilobytes each: create them once and show them again.
* A stack overflow crash cannot restore the terminal (no `sigaltstack`).
* Mouse hover (menus following the pointer) needs a terminal that reports all motion (`TUI_MOTION=1`); by default only drags are reported, which keeps the link quiet.
