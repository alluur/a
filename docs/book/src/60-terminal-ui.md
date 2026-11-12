# Terminal programs with the tui toolkit

Some programs belong in a terminal: an editor you use over SSH, a file manager, a monitor, an installer. The toolkit in this chapter builds
**full screen terminal programs** in A: it reads keys and the mouse, adapts to the colours the terminal has, writes only what changed on the
screen, and brings menus, dialogs, lists, trees, tables, tabs and a command palette. It is written for Linux terminals; the source also has code for AOS.

Every program in this chapter was run in a **pseudo terminal**: a software terminal that a test program can type into and read the screen of. It behaves like an `xterm-256color` terminal. The book did not try the programs in real terminal programs of other kinds, so where the text says what a terminal "can do", it means what the toolkit assumes from its tables.

In this chapter:

* the four modules and how they fit together;
* a first program, and how to try programs without a terminal;
* keys, the mouse and what terminals can do;
* the screen buffer: cells, colours, wide characters and the diff renderer;
* widgets, layout, menus, dialogs, lists, trees, tables and text panes;
* timers, child processes and the application loop;
* writing your own widget, and testing a terminal program.

The graphical counterpart of this toolkit is described in the [GUI chapters](#chap-gui-basics). The complete reference is
[the tui reference](#chap-tui-reference); the API of each module is generated: [term](#api-term), [tscreen](#api-tscreen), [tui](#api-tui), [tuix](#api-tuix).

## The four modules

| Module | What it is | Needs a terminal? |
|---|---|---|
| `term` | decoding of keys, mouse and paste (`Decoder`, `Event`), key names, terminal capabilities (`Caps`), the terminal itself (`Terminal`: raw mode, size, waiting for input), child programs (`Process`) | only `Terminal` |
| `tscreen` | cells, colours, character widths, drawing, and the diff renderer (`Screen`, `Out`) | no |
| `tui` | `Widget`, boxes, buttons, text fields, lists, menus, `Dialog`, `Theme` and the `App` loop | only `App.start()` |
| `tuix` | the bigger parts: `TreeView`, `Table`, `TextPane`, ready-made dialogs (`messageBox`, `askYesNo`, `prompt`, file and colour dialogs), the command palette, `DirList` | no |

`import tuix;` also loads `tui`, `tscreen` and `term`. All modules are built into the compiler, so `ac program.a -o program` is all you need.
Only `Terminal.open()` and `App.start()` (which calls it) touch a real terminal. Everything else, including a whole `App`, runs without one (`App.initHeadless`),
which is how many examples in this chapter can print the screen of a "terminal program".

::: warning

A class that has a constructor must be made with parentheses or with `new`: `term.Terminal t();`, `tui.Label l("x");` or `new tui.Label("x")`. A declaration without parentheses (`term.Terminal t;`, `tui.Label l;`) only fills the object with zeroes and does **not** run the constructor; [chapter 15](#chap-structs-and-classes) has the rules. For this toolkit that is a trap, not just untidiness:

* `term.Decoder d;` and `term.Terminal t;` crash with `SIGFPE` (a division by zero). This is the form shown in the header comment of `lib/term.a` and in `docs/TUI.md`. The decoder keeps its events in a queue whose size the constructor sets, so in a zeroed decoder the size is 0: the first call that decodes bytes (`d.feedText(...)`), or the first key that reaches a `Terminal`, divides by zero. The program is killed by signal 8 (a program that is in raw mode prints "fatal signal 8" first, and the terminal is put back). Write `term.Decoder d();` and `term.Terminal t();`, or use `new`.
* A zeroed `term.Terminal` also has `useAlt`, `useMouse` and `usePaste` off, because the constructor is what turns them on.
* A zeroed widget (`tui.Label l;`) has `visible`, `enabled`, `w` and `h` all zero or false, so nothing is drawn.
* The constructor of your own widget class must start with `super();`. Without it the base class constructor does not run, with the same result as above.

:::

## A first program

A terminal program makes an `App`, calls `start()`, builds a tree of widgets, hands it to `setRoot` and calls `run()`.

{{sample tui/hello}}

{{screen tui/hello}}

**What to notice**

* `start()` switches the terminal to **raw mode** (every key arrives at once and is not echoed, and there are no line editing keys), to the **alternate screen** (a second screen, so that the text of your shell is back when the program ends) and to mouse reporting, as far as the terminal has them (see [what the terminal can do](#what-the-terminal-can-do)). It returns `false` when it has no terminal to use: the program has no controlling terminal at all (started by `cron`, for example), or `TERM` is `dumb`. Redirecting input or output is not a reason: with `./prog > file` the toolkit opens `/dev/tty` and the program still works. Nothing has been changed when `start()` returns `false`, so you can print a message and exit. `run()` returns when
  something calls `quit()`; the terminal is put back, also when the program ends through `exit()` or a fatal signal.
* The `&` in `"&Greet"` marks the mnemonic: Alt+G presses the button. Tab moves the focus, Enter or Space presses the focused button.
* `isDefault` on a button means "Enter in a **dialog** presses it". On a plain screen Enter goes to the focused widget, so the text field
  has its own `onEnter` callback. The screen above is what the program shows after typing `Ada` and pressing Enter.
* Callbacks are plain functions that take `int` arguments and return `int`. For a button or a text field the argument is the widget itself: `int f(int widget)`; cast it back (`(tui.Button*) arg`) when you need it. Other hooks pass something else (a menu item, the data you gave a timer, a file descriptor); each is described where it is introduced below.
* In raw mode the keyboard does not send signals: **Ctrl+C is an ordinary key**. A program that should quit on Ctrl+C says so with
  `app->addShortcut("Ctrl+C", doQuit)`.

The screen above was recorded by running the program in a pseudo terminal of 80 x 24 and feeding it the keys listed in a file next to the
sample (`tools/tuishot.py`, see [the last section](#terminal-programs-in-the-book)). Colours and the cursor are not in the text; the program draws them.

## Trying programs without a terminal

`app->initHeadless(columns, rows)` makes an `App` that reads its events from a decoder you feed yourself and whose screen you can read as text.
`type("text")`, `press("Ctrl+S")`, `click(x, y)` and `text()` are the calls you use most (there are also `paste`, `wheel`, `mouseDown`, `mouseDrag`, `mouseUp`, `inject` and `advanceClock`). A third argument of `initHeadless` sets the colour depth of the pretend terminal (24 bit by default). This is how the tests of the toolkit work, and how most samples in the rest of this
chapter show screens in the book.

{{sample tui/headless}}

**What to notice**

* `pump(0)` lays out the widgets and paints one frame. `press`, `type` and `click` do it themselves afterwards.
* `type("Ada")` goes to the focused widget, `press("Alt+S")` is the mnemonic of `&Shout`, `click(3, 4)` is a mouse click on a cell (column first, rows count from 0).
* The checkbox was unchecked by the click and a click in the text field gave it the focus again. `app->focus` tells which widget has it.
* A headless `App` has a fake clock (see [Timers](#timers-and-the-application-loop)), so nothing in it depends on the speed of the machine.

## Keys, the mouse and paste

A terminal sends bytes, and the bytes of a key are not always the same: `ESC [ A`, `ESC O A` and `ESC [ 1 ; 1 A` all mean "Up" on some terminal, and the decoder accepts all three. `term.Decoder` turns the bytes into
`term.Event` values. It is pure code, with no system calls, so you can feed it a string. (Make a decoder with `new term.Decoder()` or `term.Decoder d();`, never `term.Decoder d;`: see the warning above.)

{{sample tui/decoder}}

**What to notice**

* An `Event` has a `kind` (`EV_KEY`, `EV_MOUSE`, `EV_PASTE`, `EV_RESIZE`, `EV_FOCUS`, `EV_FD`, `EV_HUP` ...). Mouse positions are cells counted from 0: the report `10;5` of the
  terminal, which counts from 1, became `(9,4)`.
* A character key is its Unicode code point, `Ctrl+S` is `'s'` with the modifier bit `MOD_CTRL`. Named keys start at `KEY_BASE`: `KEY_UP`, `KEY_ENTER`, `fkey(5)` ...
* A lone Esc is ambiguous: it could be the start of a sequence. The decoder waits for 40 ms (`dec.escMs`); `flush()` is what happens when the wait is over.
* A bracketed paste (`ESC [ 200 ~ ... ESC [ 201 ~`) arrives as **one** `EV_PASTE` event, not as 11 key presses, and a control character such as `Ctrl+Q` inside a paste does not become a key event, so it cannot quit the program. (A terminal only wraps a paste in these sequences after the program has switched bracketed paste on, which `App.start()` and `Terminal.enter()` do.)
* A terminal cannot tell some keys apart: Ctrl+H is Backspace, Ctrl+I is Tab, Ctrl+M is Enter, Ctrl+[ is Esc. Do not give them different meanings.

Keys have names, which is what menus, shortcuts and `keyIs` use.

{{sample tui/keynames}}

**What to notice**

* `parseKey` and `keyName` go back and forth between `"Ctrl+Alt+Up"` and a key code plus modifiers (`ctrl-alt-up` and `Ctrl+Alt+Up` are the same).
* `encodeKey` produces the bytes a terminal would send; `App.press` uses it to drive a headless program. `Alt+Enter` is `ESC` followed by Enter.
* `keyIs(&event, "Alt+Shift+F")` compares an event with a name. An upper case letter counts as Shift plus the letter.

## What the terminal can do

Terminals differ: some show 24 bit colours, some only 8 or none, some report the mouse, some have an alternate screen. The toolkit does not read a terminfo database. `term.Caps` records what the toolkit **assumes** the terminal can do, and works it out from the name in `TERM`
with a small built-in table (read `capsFor` in `lib/term.a` for the complete rules), from `COLORTERM`, from the locale (`LC_ALL`, `LC_CTYPE`, `LANG`) and from `NO_COLOR`. `capsFor` is the pure function behind it, so you can try any name without a terminal.
The sample below only runs names through that function; it does not talk to terminals of these kinds.

{{sample tui/caps}}

**What to notice**

* `dumb` (and `unknown`) have no cursor addressing, so `App.start()` returns `false`. Any name that starts with `vt` (`vt100`) gets no colours and no mouse, `ansi` gets 8 colours, and `linux` gets 16 colours but no mouse and no alternate screen. A `TERM` that is not set is treated as `ansi`.
* Every other name is treated like an xterm: mouse, alternate screen, bracketed paste and a window title, with 16 colours (`xterm-color` gets 8). A name with `256color` in it, or one starting with `st`, `konsole` or `gnome`, gets 256 colours; `xterm-direct`, `kitty`, `alacritty` and a few more get 24 bit. A name the table does not know (`foobar`) gets the xterm defaults.
* `COLORTERM=truecolor` (or `24bit`) lifts such a terminal to 24 bit colours, `NO_COLOR` removes all colours (bold and underline stay), and a locale that is not UTF-8 (`C`, `POSIX`) turns box drawing characters into ASCII. An unset or empty locale counts as UTF-8.
* Programs never test for these themselves: colours are downgraded to the nearest colour the terminal has, symbols fall back to ASCII, and `App.start()` picks a theme
  (dark for 256 and more colours, classic blue and cyan for 8 and 16, a monochrome one without colours).

You can force a setting for a test or for yourself: `TUI_COLORS=0|8|16|256|truecolor`, `TUI_MOUSE=0|1`, `TUI_ASCII=1`, `TUI_SYNC=0|1` (synchronized output) and `TUI_MOTION=1` (all mouse motion). The next program shows its own capabilities. Its key file sets `TERM=linux` and `TUI_ASCII=1` with `env:` lines, so the toolkit
assumes 16 colours, no mouse and ASCII drawing. (It is still the same pseudo terminal: only the toolkit's assumptions change.)

{{sample tui/fallback}}

{{screen tui/fallback}}

**What to notice**

* The box is drawn with `+`, `-` and `|` instead of line drawing characters, and the program is the same program.
* The progress bar is a bar of coloured blanks with its percentage on top; a screen shown as text has no colours, so only the `60%` is visible. (The check box looks the same with and without Unicode: its `[x]` is always plain ASCII.)
* `app->caps` is the capability record the toolkit uses. A program can look at it (here: colours, `utf8`, `mouse`) but normally does not need to.

## The terminal layer

The widgets are built on `term.Terminal`. You can use it directly for a small program that does not need widgets: open it, `enter()` the full screen mode, wait for events. Remember the parentheses: `term.Terminal t();`.

{{sample tui/events}}

{{screen tui/events}}

**What to notice**

* `t.open()` checks that there is a terminal and reads its capabilities and size; it returns `false` when there is none. `t.enter()` writes the sequences that switch to raw mode, the alternate screen, the mouse and bracketed paste (as far as the capabilities allow), and installs the handlers that restore everything. `leave()` (or `exit()`, or a fatal signal) undoes it.
* `t.wait(250)` returns after input, a resize or 250 ms. It uses `ppoll`, never a blocking read, so a timeout or a signal always returns. `watch(fd)` adds a file descriptor: an `EV_FD` event arrives when it is readable.
* The screen above is what the program drew with `writeStr` and cursor positioning escape sequences. The mouse click, the wheel and the paste are all events that arrived through the same loop.
* A window resize arrives as `EV_RESIZE`; a hang up as `EV_HUP`. `Terminal.softExit(true)` turns a `SIGHUP`, `SIGTERM` or `SIGINT` sent from outside into an `EV_HUP` event (its `key` is the signal number) so that a program can save its work before it ends.

::: note

The terminal layer does not remember what is on the screen: it only moves a cursor and writes text. The next section is about the part that
remembers it.

:::

## The screen buffer

A `tscreen.Screen` is a grid of cells with two copies: the **back buffer** you draw into, and a record of what the terminal shows. `render` writes the escape sequences that bring
the terminal up to date. You can draw into a screen and look at it as text without any terminal. Make one with `tscreen.Screen s(34, 7);` or `new tscreen.Screen(34, 7)`: it needs the parentheses too.

{{sample tui/screen}}

**What to notice**

* A style is **one `int`**: the foreground colour, the background colour and the attributes (`A_BOLD`, `A_UNDERLINE`, `A_REVERSE` ...). `style(fg, bg, attr)` builds one.
* Everything is clipped to the clip rectangle (`pushClip`, `popClip`): the long text in the sample stops at ten cells. `textEllipsis` shortens text with `…`.
* `text` returns the column after the text, so pieces of text can follow each other. The wide characters `世界` take two cells each.
* `rowText`, `dump` and `styleAt` read the buffer back: they are how the tests and this chapter look at screens.

### Colours

A colour is `0` (the terminal's default), `rgb(r, g, b)` or `idx(n)` (an entry of the 256 colour palette; 0 to 15 are the ANSI colours `RED`, `BRIGHT_RED` ...). When the terminal
has fewer colours than you used, the colour is replaced by the **nearest** one it has.

{{sample tui/colors}}

**What to notice**

* Orange (255, 128, 0) becomes palette entry 208 on a 256 colour terminal and plain yellow (3) on a 16 or 8 colour one: the nearest colour by the "redmean" distance, a cheap approximation of how different two colours look.
* An 8 colour terminal has no bright colours, so `BRIGHT_RED` (9) becomes red (1), which the renderer shows in bold.
* The default colour is never changed, and with no colours at all everything becomes the default colour.

### Character widths

{{sample tui/widths}}

**What to notice**

* East Asian wide characters and emoji take two cells, a combining accent takes none: `textWidth` counts cells, not bytes or characters. `fitBytes` tells how many bytes fit into a number of cells without cutting a character.
* A wide character that does not fit at the edge is replaced by a blank, and overwriting half of one blanks the other half.
* Ambiguous characters (some Greek and Cyrillic letters, box drawing) count as one cell. Emoji sequences (flags, skin tones) are drawn as separate characters.

### The diff renderer

The renderer sends only what changed. After a resize or `invalidate()` it sends everything.

{{sample tui/render}}

**What to notice**

* The first frame is 27 bytes, the same frame again is **0 bytes**, and changing one word costs a cursor move, one colour change and the five new characters.
* The same orange in three colour depths: `38;2;255;128;0` (24 bit), `38;5;208` (256 colours) and `33` (16 colours): the downgrade happens in the renderer, so widgets never think about it.
* With `caps.syncOutput` a frame is wrapped in "synchronized output" sequences, so a terminal that knows them shows it without flicker.

## Widgets and layout

Every widget derives from `tui.Widget`: a position and size inside its parent (`x y w h`), a `flex` share, `visible`, `enabled`, `focusable` and callbacks. Layout is simple: sizes flow
down, preferred sizes flow up. In a `vbox`, children are stretched to the full width; children with a `flex` share what is left.

{{sample tui/layout}}

**What to notice**

* `Frame` draws a border and a title; `Splitter(true)` puts two children side by side with a divider the mouse can drag; `TabView` shows one page at a time, with Alt+1 to Alt+9 and Ctrl+PgUp / Ctrl+PgDn to switch.
* The splitter's `ratio` (400 of 1000) gave the first pane 40 per cent of the 43 columns that are left after the one column of the divider: `firstSize()` says 17 cells. `flex = 1` made the splitter take all the height that the label and the status bar did not need.
* Overlays (dialogs, menus, toasts) have absolute positions and live outside the tree of widgets.

### Lists

A `ListView` holds text items, each with a number for your own data. With `filterable` set, typing narrows the list.

{{sample tui/list}}

**What to notice**

* The list has 10 items and 7 rows, so it shows a scroll bar (the `█` and `░` on the right). The filter text is shown at the bottom, and takes one of the rows. A substring match with no regard to case is the default; `matcher` replaces it.
* `onActivate` runs on Enter or a double click, `onSelect` when the selection moves. `selectedText()` and `selectedData()` read the choice.
* Typed characters go to the filter, Backspace edits it and Esc clears it, so a list in a dialog needs no extra text field. Up, Down, PgUp, PgDn, Home and End move the selection.

### Trees and tables

{{sample tui/tree}}

**What to notice**

* A tree node can be **lazy**: it shows an arrow, and `onExpand` fills it the first time it opens. The hook ran once, although the node was opened twice.
* Node 0 is the invisible root. Keys: Right expands (or goes to the first child), Left collapses (or goes to the parent), Enter and Space toggle.
* A node has a text (the tree keeps its own copy of it) and an `int` of user data (an index, or a pointer cast to `int` ...), which `addNode` takes as its third argument and `nodeData(node)` gives back.

{{sample tui/table}}

**What to notice**

* `addColumn(title, width, align)`: width 0 takes the space that is left, align 0 is left, 1 centred and 2 right. A table has at most 8 columns, and `addRow` takes up to 8 cells. A click on a header sorts by that column, again reverses; the arrow shows which way.
* Numbers sort as numbers (`98`, `412`, `1204`, `3500`), text without regard to case; a column sorts as numbers only when both cells being compared are numbers. The sort is stable and fast (a test with 40,000 rows took well under a second).
* `selectedRow()` is the number `addRow` returned for that row, **not** its place on the screen: sorting does not change it. Use it with `cell(row, column)`. It is -1 when nothing is selected.

### Text output

A `TextPane` is read only: it shows the output of a program. Text arrives in any pieces, ANSI colour codes become colours, and the pane follows the end until the user scrolls up.

{{sample tui/textpane}}

**What to notice**

* `done` was appended without a newline and is already on the screen: an unfinished line is shown.
* `\e[31m` made `error` red: the colour is in the cell's style, so `styleAt` can check it. `\r\n` counts as one newline.
* The pane has 5 rows and the sample added 9 lines in all (the three above and six more), so the first lines scrolled away and the scroll bar appeared. It keeps 5000 lines by default (`maxLines`; you may lower it, but not raise it, because the pane allocates room for 5000 lines when it is made). When the lines or its 1 MiB of text are used up, the oldest quarter of the lines is dropped.

## Menus

A `MenuBar` holds `Menu` objects, each with items. An item text with `&` has a mnemonic; the accelerator text (`"Ctrl+O"`) is also the shortcut.

{{sample tui/menus}}

**What to notice**

* `addSeparator`, `addCheck` (the item shows a check mark and flips `checked` before the action runs), `addSub` (a submenu with the arrow `►`).
* `setMenuBar(bar)` makes F10, Alt+letter and every accelerator work everywhere, also when a text field has the focus.
* The action receives the item: `int f(int item)`; its `text` still contains the `&`, which the sample removes for printing.
* In an open menu: Up and Down skip separators, Right opens a submenu (or the next menu), Left goes back, Esc closes, a letter chooses the item with that mnemonic.

The same in a real terminal, with a menu that is open:

{{sample tui/menuapp}}

{{screen tui/menuapp}}

**What to notice**

* `addShortcut("Ctrl+C", doQuit)` is needed because Ctrl+C arrives as an ordinary key in raw mode.
* The key file pressed Alt+E: the Edit menu dropped over the label. A menu opens as an overlay, above everything, and moves to fit the screen.
* The status bar message of `doNew` goes away after the time you give (`message(text, ms)`).

## Dialogs and pickers

A `Dialog` is a modal window with a content widget and buttons. Esc closes it with `cancelResult`, Enter presses the default button, Alt+letter the mnemonic button, and the title bar
can be dragged. There are two ways to run one: `showDialog(d)` returns at once and `d->onClose` is called later; `runDialog(d)` runs a nested event loop and returns the result.

{{sample tui/dialogs}}

**What to notice**

* `addButton("&Reload", 1, true)`: the label, the result code and whether it is the default button.
* `messageBox`, `askYesNo`, `askYesNoCancel` and `prompt` are ready-made dialogs that block until the user answered. `prompt` returns a copy of the text, or `null` when cancelled.
* A headless `App` cannot wait for a person, so the sample queues the keys first with `inject()`. A real program just calls the function. In a headless app `runDialog` returns (as cancelled) when no input is left,
  so a test can never hang.
* Dialogs are never freed (A's `new` does not free): create a dialog once and show it again if the program opens it often.

### The file picker

`fileOpenDialog`, `fileSaveDialog` and `directoryDialog` show a path field and a list that filters as you type, directories first, `../` to go up. They return the full path, or `null`.

{{sample tui/openfile}}

{{screen tui/openfile}}

**What to notice**

* The program made a few files first, so the dialog has something to list. The start directory must be an **absolute path** (a relative one is taken from `/`): the sample joins `currentDir()` and `docs`.
* The list is a `ListView`: typing filters it, Enter opens a directory or picks a file, Alt+. shows hidden files. A save dialog has a name field and asks before replacing a file.
* The dialog is built on `DirList`, which you can use yourself:

{{sample tui/dirlist}}

**What to notice**

* `load(dir, hidden, withSizes)` reads a directory with `getdents`, without a `stat` per entry (sizes are only asked for when you want them). `sort()` puts directories first, then names without regard to case.
* `joinPath`, `parentPath` and `cleanPath` work on text only and never touch the disk.
* A link to a directory counts as a directory; `isLink(i)` tells that it is a link. Nothing is ever opened, so a FIFO cannot make the dialog wait. (Windows has no `DirList`: `load` returns `false`.)

### The command palette

`app->addCommand("File: Save", "Ctrl+S", save)` adds a command to a list and registers its key as a shortcut. `commandPalette(app)` shows the list with fuzzy matching.

{{sample tui/palette}}

**What to notice**

* `fuzzyScore(pattern, text, positions, max)` returns -1 when the letters of the pattern do not appear in order, else a score: consecutive letters and word starts score higher, shorter texts win. `positions` gets the matched positions, which the palette highlights.
* The palette is a dialog (`newCommandPalette` + `showDialog`, or the blocking `commandPalette(app)`). Typing `sb` found "Toggle **s**idebar" only, Enter ran it.
* Pressing `Ctrl+O` ran the second command: a command's key works everywhere, not only in the palette.

There is also a colour dialog, `colorDialog(app, initial)`, with the 256 colour palette, red / green / blue sliders and a hex field; it returns `idx(n)` for a palette colour, `rgb(...)` for any other, and -1 when cancelled.

## Timers and the application loop

`App.run()` calls `pump(maxWaitMs)` for ever. Each turn it paints if something changed and writes the difference, waits for input (but not longer than the next timer), dispatches the events, runs due timers and calls
`onIdle`. Events go to the widget under the pointer (mouse) or the focused widget (keys), then to its parents; shortcuts and menus see keys first.

{{sample tui/timers}}

**What to notice**

* `addTimer(ms, function, data, repeat)` returns an id for `cancelTimer`; up to 64 timers. A repeating timer that is late runs once, not once for every missed interval.
* A headless `App` has a **fake clock** (`advanceClock(ms)`): the timers above ran exactly when the program said, and the output does not depend on how fast the machine is.
* A real program uses the same calls. A progress bar updated by a timer is a few lines, as the widget gallery of the toolkit shows (`examples/tui/gallery.a`).

### Following the size of the window

{{sample tui/resize}}

{{screen tui/resize}}

**What to notice**

* A resize arrives as `EV_RESIZE` (from `SIGWINCH`, or by polling the size every 200 ms on AOS). The toolkit makes a new screen, lays the widgets out again and calls `onResizeHook`.
* The window of this sample was resized to 60 x 10 by the key file (`resize:60,10`); the screen above is the result.
* The size comes from the system. A serial console that reports nothing is asked with `CSI 18 t` and a cursor position report; the limit is `term.MAX_COLS` x `term.MAX_ROWS` (1000 x 500).

### The mouse

{{sample tui/splitter}}

{{screen tui/splitter}}

**What to notice**

* The key file pressed on the divider (column 39), dragged to column 30 and 20 and released: the divider is now at column 20. Only drags are reported by default, which keeps the link quiet; `TUI_MOTION=1` asks for all motion.
* `app->clicks` is 1, 2 or 3 for double and triple clicks. A widget that sets `app->capture = this` on a press gets all mouse events until the release (that is how drags work).

### Child programs and descriptors

A program that starts another one (a build, a search) must not block while it runs. `term.Process` starts a child whose standard output and error come through one pipe; `app->watchFd(fd, function, data)`
calls your function when the pipe has data.

{{sample tui/build}}

{{screen tui/build}}

**What to notice**

* `startShell` runs a command line through `/bin/sh`; the child gets its own process group, so `kill` stops the whole job. `read` returns 0 at the end; `finish()` waits and gives the exit status.
* The pane shows the output while the child runs, and `\033[31m` in the output is a colour in the pane: `TextPane` understands ANSI sequences. Colour codes you add yourself work the same.
* `runShell` / `runProgram` of the `App` instead leave full screen mode, run a program in the foreground with the normal terminal, wait for it and come back, redrawing the screen.

### Putting it together

{{sample tui/notebook}}

{{screen tui/notebook}}

**What to notice**

* `TabView.addPage(widget, "&Title")` and Alt+1 to Alt+3 switch pages. The key file pressed Alt+2 and moved down the table: the status bar shows the callback's text.
* A tree, a table and a form, none of them aware of the others: each page is an ordinary widget, and `TabView` only decides which one is visible.
* The selected row is shown by colour, which the text of a screen cannot show; everything in this toolkit that "highlights" something does it with styles.

## Writing your own widget

Derive from `tui.Widget`, start the constructor with `super();`, and override `prefW`, `prefH`, `paint`, `onKeyPress` and `onMouse`.

{{sample tui/widget}}

**What to notice**

* `paint(screen, ox, oy)` gets the screen position of the widget's top left cell. Use the **theme styles** (`tui.theme->progressFill`, `selection` ...) instead of fixed colours, so that the widget looks right at every colour depth.
* A key handler returns `true` when it used the key; the parents see it otherwise. In `onMouse`, setting `app->capture = this` on a press makes the widget receive the drag and the release.
* Text is drawn with the cell's background kept (`COL_KEEP`), so a label can lie on top of a bar.
* A text cursor is placed with `screen->setCursor(x, y)`, but only when `app->cursorOk(this)` says that no overlay covers the widget.

## Terminal programs in the book

The programs of this chapter that start with `App.start()` need a real terminal, so the book's checker only compiles them. Their screens come from `tools/tuishot.py`: it compiles the program,
starts it in a pseudo terminal of 80 x 24, sends the keys of the `.keys` file next to it (typed text, named keys, mouse clicks, drags, pastes, resizes, environment variables), waits until the program is quiet and
records the final screen as plain text. The vocabulary is in the writing guide of the book. You can use the same approach for your own programs: the screen emulator it uses is `tests/tui/ptyterm.py`,
and the toolkit's own `tests/tui.sh` drives the widget gallery and the file manager with it.

For tests that run everywhere without a pseudo terminal, use `initHeadless` as in this chapter. Two things it cannot test are the raw mode and signals; the toolkit's test
`t237` runs the real terminal layer in a pseudo terminal it creates itself.

## Limits

* There is no multi line editor widget (the AIDE terminal editor brings its own); `TextPane` is read only.
* Wide characters work as described above, but emoji sequences and right-to-left text do not. The GUI terminal `gterm` draws a wide character in one cell (see [the GUI terminal](#chap-gui-net-and-web)): use `TUI_ASCII=1` there.
* Windows consoles are not supported (`Terminal.open()` is false); the decoder, the screen, the widgets and the headless `App` do compile and run there.
* The Linux console has no mouse. Scrolling is done by redrawing the changed rows (no scroll regions), which is fine except on very slow links.
* Memory is not freed: `new` widgets and dialogs live until the program ends. Create them once.

## Summary

* `term` decodes keys, mouse and paste into events, knows the capabilities of the terminal and owns raw mode; `tscreen` draws into a buffer and writes only the difference; `tui` and `tuix` are the widgets and the `App` loop.
* `App.start()` takes over the terminal and returns `false` when there is none; `initHeadless` runs the same widgets without one, with a fake clock and a screen you can read as text.
* A style is one `int`; colours are downgraded to the nearest colour the terminal has, and symbols fall back to ASCII.
* Callbacks are functions `int f(int widget)`; objects with a constructor need parentheses or `new`, and your own widgets start with `super();`.
* Menus, dialogs, lists, trees, tables, text panes, the file picker and the command palette are ready made; `Dialog` can run nested (`runDialog`) or event driven (`showDialog`).
* Children and descriptors are watched by the loop (`watchFd`), so a build never freezes the screen.
* In raw mode Ctrl+C is an ordinary key; say what it does with `addShortcut`.

## Where next

* [The tui reference](#chap-tui-reference) for every key, option and limit, and AOS notes.
* [The GUI chapters](#chap-gui-basics) for the graphical counterpart of the widgets, and [the code editor widgets](#chap-code-editor-widgets), which end in the terminal and GUI IDE.
* [System programming](#chap-system-programming) for processes, signals and files.
* API references: [term](#api-term), [tscreen](#api-tscreen), [tui](#api-tui), [tuix](#api-tuix).
