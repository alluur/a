# Notes of the contributor "gui2" (terminal UI, display server, GUI net / web / terminal widgets, code editor widgets)

Chapters: `src/60-terminal-ui.md`, `src/54-display-server.md`, `src/55-gui-net-and-web.md`, `src/56-code-editor-widgets.md`.
Samples: `samples/tui`, `samples/guisrv`, `samples/guinet`, `samples/gcode`. Tool: `tools/tuishot.py` (terminal samples).

## (a) Compiler and library bugs, surprises

### a1. `term.Terminal t;` crashes with SIGFPE on the first event (constructor not run)

`lib/term.a` (header comment) and `docs/TUI.md` ("The terminal layer") both show `term.Terminal t;`. A plain declaration does **not** run
the constructor (`dec` stays null), so the program dies as soon as it reads an event: `fatal signal 8`.

```c
import term;
int main() {
    term.Terminal t;            // wrong: no constructor
    if (!t.open()) { return 1; }
    t.enter();
    term.Event e;
    t.wait(250);                // fine
    while (t.next(&e)) { }      // crashes when a key arrives (type any key): fatal signal 8
    return 0;
}
```

Run it in a pseudo terminal and send one key. `term.Terminal t();` or `new term.Terminal()` works. The same applies to `term.Decoder`
(`Decoder d; d.feedText(...)` in the header comment of `lib/term.a` has the same problem). The language rule is in `docs/TUI.md`
("The four modules": "A plain `tui.Label l;` does not run the constructor"), but its own examples break it.

### a2. `tuix.fileOpenDialog(app, title, "docs", "")`: a relative start directory is taken from `/`

`fpMake` calls `cleanPath("/", start)`, so a relative `startDir` means `/docs`, not `./docs`. The dialog then shows
"cannot read /docs". `docs/TUI.md` does not say that the start directory must be absolute (an empty string means `currentDir()`).
Workaround: `tuix.joinPath(tuix.currentDir(), "docs")`.

### a3. `Button.isDefault` has no effect outside a `Dialog`

Documented as "Enter in a dialog presses it", so not a bug, but a reader who puts a default button in a plain screen and presses Enter in a
`TextInput` gets nothing. Use `TextInput.onEnter` there.

## (b) Documentation errors

* `docs/TUI.md`, "The terminal layer: term": `term.Terminal t;` must be `term.Terminal t();` (see a1).
* `docs/TUI.md`, "Bigger widgets": the file dialogs' start directory must be absolute (see a2).

## (c) Not covered / not verified

(filled in at the end)
