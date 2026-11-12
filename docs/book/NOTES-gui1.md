# Notes of the graphics / GUI contributor (gui1)

Chapters: `src/50-graphics.md`, `51-gui-basics.md`, `52-gui-more-widgets.md`, `53-gui-programs.md`. Samples: `samples/gfx/` (drawing, images, charts:
everything that writes a PNG without a display server) and `samples/gui/` (programs with windows, plus `icons.a`, which draws offscreen).
Pictures: `shots/gfx-*.png`, `shots/gui-*.png`, made by `tools/shots.py` (see WRITING.md section 6).

## (a) Bugs and surprises in the compiler and libraries

### 1. `gfx.Surface.shadow` gets darker away from the rectangle

`shadow(x, y, w, h, spread, maxAlpha)` is documented as "a soft dark halo ... the darkness fades over spread pixels". The rings are drawn with
`alpha = maxAlpha * g / spread^2` where `g` is the distance from the rectangle, so the ring touching the rectangle is the *lightest* and the
outermost one the darkest (the window shadows of `wsrv` use it with spread 7, maxAlpha 90 and are therefore barely visible).

```a
gfx.Surface* s = new gfx.Surface(100, 40);
s->clear(gfx.WHITE);
s->shadow(40, 15, 20, 10, 8, 200);
for (int d = 1; d <= 8; d++) { printf("%d: %d\n", d, gfx.red(s->get(40 - d, 20))); }   // 252, 249, ... 230: darker with the distance
```

`samples/gfx/gradients_shadows` prints the effect (`0xffededf1` one pixel from the card, `0xffe4e4e8` eight pixels away).

### 2. `gchart.Gauge`: the caption is cut off at the preferred height

`Gauge.prefH()` is 100, but `paint()` draws the number at `cy + 8` and the caption one line below that, up to about y = 116 (for the default width 140).
`Widget.paintTree` clips a widget to its own rectangle, so a gauge that gets exactly its preferred height shows the number but not the caption.
A gauge painted straight into a surface (`samples/gfx/gauges`, with `g->h = 125`) is fine. In a window give the gauge extra height (a `Box` with `flex`,
or a subclass with a larger `prefH`); `samples/gui/charts_window` leaves the caption out for that reason.

### 3. `TextArea` has no selection and ignores Ctrl+A, Ctrl+C and Ctrl+X

`docs/GUI.md` says "the text widgets use Ctrl+A / C / X / V". `gui.TextBox` does (select all, copy, cut, paste), but `gui.TextArea.onKey` returns at once for
every Ctrl combination except Ctrl+V, and the class has no selection at all. Typing a character above U+07FF also does nothing (`isTextChar(uni) && uni < 2048`);
`TextBox` takes any code point. (`gcode.CodeEditor` is the editor with selections.)

### 4. A custom widget only gets the mouse wheel when it overrides `wantsScroll()`

`Window.handleMouse` offers `M_SCROLL` only to widgets whose `wantsScroll()` is true (and then walks up the parents). `docs/GUI.md` ("Your own widgets") lists
`paint`, `onMouse`, `onKey`, `prefW`, `prefH` and does not mention `wantsScroll`; a widget that handles `adp.M_SCROLL` in `onMouse` never sees it
(`samples/gui/custom_widget` has the one-line override).

### 5. Callbacks run during construction: order of creation matters

`RadioGroup.selectIndex`, `SpinBox.setValue`, `ComboBox.select` call `onChange` at once when it is already set. A callback that uses a label created later crashes
with a null pointer (SIGSEGV, exit code -11 and no message). Not a bug, but the first version of two samples crashed like this: create everything the callback uses
first, then set `onChange` and the start value.

### 6. Small points

* `gimg.savePng` writes uncompressed PNGs (a 120 x 60 picture is 28 928 bytes); `shots.py` recompresses them with Pillow for the book.
* `gui.messageBox` has a fixed window of 280 x 110: a long text is cut off.
* `Window.createWindow` returns `null` after 63 windows per connection, `Display.after` returns -1 when 32 timers are pending (no error message).
* `datetime` is UTC only (the clock sample says so in its title and label).
* The window placement of `wsrv` is a cascade: the first window with position -1,-1 gets its client area at 40,74 and each next one is 28 pixels further. `shots.py` relies on it
  only for the click coordinates in the samples.
* Pictures: the headless server draws the pointer into screenshots, and its shape and place are part of the picture; `shots.py` parks it in the bottom right corner.

## (b) Reference documentation that was wrong or incomplete

| File | Claim | What really happens |
|---|---|---|
| `docs/GUI.md`, Programs | "the text widgets use Ctrl+A / C / X / V" | only `TextBox`; `TextArea` takes Ctrl+V only (see 3) |
| `docs/GUI.md`, Programs | custom widgets override `paint onMouse onKey prefW prefH` | also `wantsScroll()` for the wheel (see 4) |
| `docs/GUI.md`, Drawing | `shadow` listed as "a soft dark halo" | the halo is darkest at the outer edge (see 1) |
| `docs/GUI.md`, Windows | `createWindow(title, w, h, flags)` | also the position: `createWindowAt` takes the top left corner of the *client area* (the title bar is above it) |
| `docs/GUI.md`, guix | `StatusBar: addSection(width) (0 stretches)` | right; but a section is exactly `width` wide and clips its text (a 70 pixel section cut "Ln 1, Col 1") |
| `docs/GUI.md`, Quick start | `adisplayd -vnc 5900 -control &` (127.0.0.1:7000) | right; `-p N` takes a display number *or a port* (`adp.portOf`: below 100 it is added to 7000, else it is the port) and `ADISPLAY=127.0.0.1:PORT` names it; two servers need two `-p` *and* two `-vnc` values |
| `docs/GUI.md`, gchart | "`Gauge g(0, 100); g->caption`" | see bug 2 |
| `WRITING.md` (older version) | "No floats" | corrected by the coordinator; the samples here use integers only where `gfx.isin` / `icos` are the point, and `gfx/plot_double` uses `double` and `dmath` |

## (c) What is not covered, and why

* `gterm`, `gcode`, `ghtml`, `gnet`, `wweb`, `wvnc`, `wfb`, `glock`, `dm`: not in my assignment (the guide `GUI.md` describes them; the chapters only point to the API references).
* The busy progress bar (`ProgressBar.start()`) is described but has no picture: it animates on a timer, so a screenshot would not be reproducible.
* Keyboard-only features of `guix` (Alt+letter menu opening, arrow keys in menus, type-ahead) are described in the text but only the accelerators have a sample.
* `guix.ScrollBar` on its own, `TabView.closable`, `Splitter` with `sideBySide = false`, `TreeView.lazy` / `onExpand`, `IconButton` outside a `Toolbar`: mentioned in tables, not run.
* Other targets: all samples were compiled for the eight targets with `samples.py --targets`; the drawing samples print checksums only where noted, and only the Linux x64 results were recorded
  (the books claims that gfx output is identical on every target; I did not run Windows, ARM or RISC-V binaries).
