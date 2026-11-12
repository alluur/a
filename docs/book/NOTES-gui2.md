# Notes of the contributor "gui2" (terminal UI, display server, GUI net / web / terminal widgets, code editor widgets)

Chapters: `src/60-terminal-ui.md`, `src/54-display-server.md`, `src/55-gui-net-and-web.md`, `src/56-code-editor-widgets.md`.
Samples: `samples/tui` (28 programs, 9 of them real terminal programs with `.keys` and `.screen`), `samples/guisrv` (14), `samples/guinet` (14), `samples/gcode` (24).
Tool: `tools/tuishot.py` (terminal samples); section 7 "Terminal samples" of `WRITING.md` has its vocabulary.

Everything below was found by running the code on this branch (`build/ac`).

## (a) Compiler and library bugs, surprises

### a1. `term.Terminal t;` and `term.Decoder d;` crash with SIGFPE (constructor not run)

`lib/term.a` (header comment: `term.Terminal t;`, `Decoder d; d.feedText(...)`) and `docs/TUI.md` ("The terminal layer": `term.Terminal t; // or new term.Terminal()`) show a plain
declaration. A plain declaration does **not** run the constructor, so the object is zeroed (`dec` of the terminal is null, a `Decoder` has no queue), and the program dies with `fatal signal 8`
or `Floating point exception` as soon as it uses it.

```c
import term;
int main() {
    term.Decoder d;             // wrong: no constructor
    term.Event e;
    d.feedText("a");
    printf("next: %d\n", d.next(&e));     // Floating point exception (exit 136)
    return 0;
}
```

With `term.Terminal t;` the same happens on the first key (`while (t.next(&e))` after `t.wait(250)`). `term.Decoder d();`, `term.Terminal t();` or `new` work. The rule is stated in `docs/TUI.md`
("A plain `tui.Label l;` does not run the constructor") but its own examples break it.

### a2. `tuix.fileOpenDialog(app, title, "docs", "")`: a relative start directory is taken from `/`

`fpMake` calls `cleanPath("/", start)`, so a relative `startDir` means `/docs`, not `./docs`; the dialog then says "cannot read /docs". `docs/TUI.md` does not say that the start directory must be
absolute (an empty string means `currentDir()`). Workaround used in `samples/tui/openfile.a`: `tuix.joinPath(tuix.currentDir(), "docs")`.

### a3. `Button.isDefault` does nothing outside a `Dialog`

Documented as "Enter in a dialog presses it", so not a bug, but a reader who makes a default button on a plain screen and presses Enter in a `TextInput` gets nothing. Use `TextInput.onEnter`
there (`samples/tui/hello.a`). The chapter says so.

### a4. A global named `find` gives a compile error that points into the standard library

```c
int find;
int main() { return find; }
```

```text
<std>:574: error: name is already declared as something else: 'sub'
  int find(char* s, char* sub) {
```

The prelude (`std`) has a function `find(char*, char*)`, so a global (variable) with that name is refused, but the message names a line of `<std>` and the parameter `sub`, not the user's declaration. `docs/TUI.md`
warns about `input` and `list`; `find` bit me in `samples/gcode/mini_ide.a` (a global `gcode.FindBar* find;`), and it is a likely name for a find bar. The sample uses `findBar`.

### a5. A class object with a constructor at file scope: misleading error

```c
import acode;
acode.Buffer b();                                   // at file scope
int main() { b.setText("x", 1); return 0; }
```

```text
error: member access on a value that is not a struct, class or pointer to one
```

`acode.Buffer b();` inside a function is the documented form; at file scope the declaration is not accepted as an object (the error comes at the first use, not at the declaration). Use a pointer and `new`
for globals (`samples/gcode/editor.a`). `docs/AIDE.md` section 1 says "Objects with a constructor are declared with parentheses" without the file scope limit.

### a6. Embedding a server and a client in one process needs a ping, not a fixed number of turns

Not a bug, but the first version of `samples/guisrv/protocol.a` sent a 28 KB `Q_PRESENT` and then called `srv->step(0)` ten times; sometimes the pixels had not been read yet and the screen still
showed the old picture. Waiting for `E_PONG` of a `Q_PING` is the reliable way (what `Display.sync()` and the harness of the gcode tests do). The chapter explains it.

### a7. No way to learn the port of a `wsrv.Server` / `wvnc.Vnc` / `wweb.Web` that was given port 0

`Server(backend, 0)` listens on an ephemeral port, but `listenFd` is private and `Server` has no `port` field (`Vnc.port` keeps the requested 0), so an embedding program cannot say where to connect.
The book's samples ask the system for a free port first (`net.listen(0, ...)`, `net.localPort`, close it) and pass that number, which has a small race; a `Server.port()` accessor would remove it. For the same reason
the `wvnc` and `wweb` samples connect to the port they chose themselves. Not a bug.

### a8. `RunPane` prints the run time at the end of a program's output

`[the program ended with exit code 0 after 0.06 s]`. That makes a picture of a finished run different every time. `samples/gcode/ide_panes.a` photographs the pane while the program still waits for input.

### a9. `ThemeEditor.setEntry(i, rgb, style)` does not update the picker

After `te->setEntry(24 + Tok.Keyword, 0xFF8800, bold)` the list and the preview show `#FF8800` but the colour picker and its hex field still show the old colour (`#569CD6`, see the picture of
`gcode/theme_editor`) until the entry is selected again. Probably intended (the picker is the input), but a program that drives the editor sees a mixed state.

### a10. `gcode.pickColor`: the right edge of the dialog

The window is 354 pixels wide after `fit()`; the preview swatch and the hex field at the top right run up to the right border without the margin that the left side has (see `shots/gcode-color_picker.png`).
Cosmetic.

### a11. `Table` column width includes the sort arrow

`addColumn("Size", 7, 2)`: the header shows `Siz ▲` when sorted (the arrow takes the cell width). A column needs the title width plus 3 or 4 to show both. Cosmetic.

### a12. `wfb.keyFor` with AltGr on the `us` layout returns the plain character

`keyFor(8, false, true, &uni)` after `useLayout("us")` sets `uni` to `'7'` (AltGr changes nothing). Nothing in the docs says what AltGr does on `us`; `samples/guisrv/framebuffer.a` shows it.

## (b) Documentation errors and gaps

* `docs/TUI.md`, "The terminal layer: term": `term.Terminal t;` must be `term.Terminal t();` (a1). `lib/term.a` header: the same for `Terminal t;` and `Decoder d;`.
* `docs/TUI.md`, "Bigger widgets" (file dialogs): the start directory must be absolute (a2).
* `docs/GUI.md`, "A web browser: ghtml and abrowse": "It does not do CSS, forms, frames or scripts (they are skipped)" contradicts the paragraph "**Forms**: ..." a few lines further down, and the real behaviour:
  forms **do** work (`samples/guinet/html_form.a` submits one: `POST http://example.org/join`, `name=Grace+%26+co&size=l&colour=g&note=...`). The first sentence is out of date.
* `lib/gcode.a` (header): "gcode_core: Look, RowList, FlatButton, LineEdit, small helpers". `RowList`, `FlatButton`, `BarBox` and `BarLabel` are in `lib/gcode_bars.a`; `gcode_core` has `Look`, `LineEdit` and helpers.
  `docs/GUI.md` ("The code editor widgets") says `RowList`, `FlatButton`, `LineEdit`, `BarBox`, `BarLabel` are "themed building blocks" without naming a file, which is fine.
* `docs/GUI.md`, `adp` section: `E_WELCOME` is documented with its fields only in the header of `lib/adp.a`; the byte offsets (version at 8, client number at 12, width at 16, height at 20) are what a hand written client needs
  (`samples/guisrv/protocol.a`). The header lists them in order, which is enough, but a reader has to add the 8 byte message header.
* `docs/GUI.md`, display server: `new wsrv.Server(b, 7000)` is shown, and `7000` is the only port the text mentions; nothing says how to run a second server in the same machine (use another port: `adisplayd -p 24612`,
  `ADISPLAY=127.0.0.1:24612`). The sentence "`ADISPLAY=N` = port 7000+N" only holds below 100: a number of 100 or more is the port itself (`adp.portOf`).
* `docs/AIDE.md`, section 1 and 3: "Objects with a constructor are declared with parentheses: `acode.Buffer b();`" is right inside functions only (a5).

## (c) Not covered, not verified, and why

* **Real terminals.** Everything in the TUI chapter ran in `tests/tui/ptyterm.py`, a pseudo terminal with a small emulator, never in a real xterm, the Linux console, tmux, a serial line or on AOS. Mouse reports were
  injected as SGR sequences; X10 mouse reports, the Linux console's key forms and `TERM=linux` behaviour beyond the `fallback` sample were not run. `softExit` (SIGHUP / SIGTERM to events), `suspendProcess`, `runShell` and
  the crash handlers were not run (the toolkit's own test `t237` covers them).
* **Colours and the cursor are not in `.screen` files.** The plain text of a screen cannot show a selection, a highlighted menu item, the palette of the colour dialog or the filled part of a progress bar; the chapter says so
  where it matters. The colour dialog sample was dropped for that reason.
* **Real framebuffer, real VNC viewer, real browser.** `wfb` was tested through `handleEvent` and `keyFor` only (no `/dev/fb0`, no `takeConsole`). `wvnc` was tested with a hand written RFB client (3.8, None security, Raw
  encoding, 32 bit): no VNC password, no 8 or 16 bit formats, no input events, no second viewer. `wweb` was tested with plain HTTP requests (page, token, wrong token, lock-out); the WebSocket was not opened.
* **`dm` sessions.** Starting a session (`fork`, `setuid`, `ADISPLAY`) was not run (needs a real user and root). Users, passwords, the configuration file and the login window were.
* **`gnet` over the Internet, `https://`.** All HTTP samples talk to a server inside the process on loopback. TLS, certificate refusal and `abrowse` were not run (`abrowse`, `aterm`, `achat`, `codedemo` and `adisplayd` were
  compiled; `adisplayd`, `hello` and `actl` were also run once on high ports for the shell session in chapter 54).
* **`aide` and `aide-gui`** are in the AOS repository, not here. The chapter describes them from `docs/AIDE.md` and says so. `aidecore.Recovery` and `aidecore.Session` were not run. `asys` on AOS and Windows was not run;
  the samples compile for all eight targets.
* **Interactive behaviour of the code widgets** beyond what the samples do (drag selection, completion popup, column selection, word wrap, `FileTree` rename and delete, `Dock` dividers, `DocView` links, `SettingsDialog`)
  was not driven by me; the toolkit's tests t240 to t267 and t281 to t283 cover them and were not run again.
* **Performance numbers** in chapter 56 (100,000 lines in 50 ms, a 120 MB file in under a second ...) are quoted from `docs/AIDE.md` and `docs/GUI.md`, not measured again.
* **Targets.** All 80 samples of the four groups compile for the eight targets (`samples.py --targets`). They were *run* only on Linux x86-64. Samples that need processes or pseudo terminals are marked `linux-only`;
  `tui/dirlist` and the file picker rely on `DirList`, which returns false on Windows (the sample would print different output there; it was not run there).
* **Not recorded:** the `.out` of the graphical samples contains only what they print; the pictures (20 of them, taken with `tools/shots.py` from the in-process programs and from `gcode/mini_ide` against a headless
  `adisplayd`) were taken twice and are byte for byte identical.
