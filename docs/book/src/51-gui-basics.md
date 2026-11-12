# Graphical programs: windows and widgets

A has a whole graphical stack written in A: a **display server** that owns the screen and the windows, and a **toolkit**, the module `gui`, that your programs use to
open windows and fill them with buttons, text fields and lists. This chapter shows how to run a graphical program, and then walks through the basic widgets, layout, callbacks,
timers, windows and the event loop, with a picture of every program. You can even write your own widget.

In this chapter:

* how a graphical program finds the display server, and how to run and watch one;
* your first window, and the widgets `Label`, `Button`, `CheckBox`, `TextBox`, `TextArea`, `ListBox`, `Slider`, `ProgressBar`, `ImageView`, `Canvas`, `Separator` and `Spacer`;
* layout with `Box` and `flex`, callbacks, timers, the clipboard and message boxes;
* windows and their flags, your own widget class, and your own event loop with `pump`.

The drawing functions of the previous chapter ([Drawing and images](#chap-graphics)) are what every widget uses to paint itself.

## The display server and your program

A graphical program does not draw on the screen itself. It connects over TCP (to the loopback address) to a **display server**, `adisplayd`, and creates windows there. It draws each window
into a surface of its own, sends the pixels to the server, and receives mouse and keyboard events back. The server is the window manager as well: it draws the title bars, moves and
resizes windows, and decides which window has the keyboard focus.

```text
  your program          your program
  (import gui)          (import gui)
        \                    /          TCP, the display protocol (adp)
         +------------------+
         |    adisplayd     |           windows, title bars, focus, mouse, keys
         +---+----------+---+
             |          |
        VNC viewer   Linux framebuffer   (or no output at all: a headless display)
```

A program finds the server through the environment variable `ADISPLAY`: `0` (the default) means port 7000 on this computer, `N` means port 7000 + N, and `host:port` names any address.
`gui.connect(null)` reads it. The display server comes with the compiler as `examples/gui/adisplayd.a`, and `examples/gui/actl.a` is a small remote control that takes screenshots and
injects mouse and keyboard events (the server must be started with `-control` to allow that). Here is a complete session, on a free high port so that it cannot collide with anything:

```sh
ac examples/gui/adisplayd.a -o adisplayd
ac examples/gui/actl.a -o actl
ac hello_window.a -o hello_window
./adisplayd -p 24680 -vnc 24681 -control -size 640x480 &
```

```text
display on 127.0.0.1:24680, 640x480, VNC on 127.0.0.1:24681
```

```sh
ADISPLAY=127.0.0.1:24680 ./hello_window &
./actl -d 127.0.0.1:24680 click 170 133        # press the button of the program
./actl -d 127.0.0.1:24680 shot hello.ppm       # a screenshot of the whole screen
```

```text
640x480 saved to hello.ppm
```

* The server has no screen of its own. `-vnc PORT` serves the display as a VNC (RFB) server, so any VNC viewer on `127.0.0.1:24681` shows the windows and sends the mouse and the keys.
  Without a viewer the display is a headless display: nothing is shown, but programs run and `actl shot` works.
* `-p` sets the display: a number below 100 is added to 7000, a larger number is the port itself. Two servers need two different `-p` values and two different `-vnc` values.
* `-size WxH` is the size of the screen (default 1024 x 768). `-fb /dev/fb0` draws on a Linux framebuffer instead, and reads the keyboard and mouse from `/dev/input`.
* `actl` takes `shot FILE.ppm`, `move X Y`, `click X Y`, `down B` / `up B`, `type TEXT` and `key NAME`.
* **The pictures in this chapter are made like this.** `tools/shots.py` starts a headless display server, runs each sample as a client, injects the clicks and keys that are written
  in the comment lines at the top of the sample (`// book: click=170,133`), takes a screenshot and cuts the windows out of it. The samples that have such a line are the ones with a picture.

::: note

The listings in this book are the programs as you would write them. The `// book:` comment lines at the top are instructions for the picture-maker and mean nothing to the compiler.

:::

## Your first window

{{sample gui/hello_window src}}

{{shot gui/hello_window}}

The program connects, creates a window, puts a **column** (`vbox`) with a label and a button into it, and runs the event loop. The picture was taken after the button had been clicked once.

* `gui.connect(null)` returns a `gui.Display*`, or `null` when there is no display server (nothing listens, or `ADISPLAY` is wrong). Always check.
* `d->createWindow(title, w, h, flags)` makes a window whose **client area** (the part you draw in) is `w` x `h`. The title bar and the border are added around it by the server.
  The server places the first window at 40, 74 on the screen and each next one 28 pixels further.
* `w->setRoot(widget)` sets the widget that fills the window. It is nearly always a `Box`.
* `d->run()` handles events until the last window is closed. A button's `onClick` is a function `int f(int widget)`: the widget arrives as an `int`, and you cast it back.
* `label->setText(...)` copies the text, so a local buffer is fine. It also asks for a layout and a repaint; you never paint by hand.

## Labels, buttons and check boxes

{{sample gui/labels_buttons src}}

{{shot gui/labels_buttons}}

| Widget | Fields and methods |
|---|---|
| `Label(text)` | `text`, `setText(t)`, `color`, `align` (0 left, 1 centre, 2 right), `font` |
| `Button(text)` | `text`, `setText(t)`, `onClick`, `primary` (accent colour), `click()` (as if clicked) |
| `CheckBox(text)` | `text`, `checked`, `setChecked(b)`, `onChange` |

Every widget also has `x y w h` (set by the layout), `visible`, `enabled` (`setEnabled(b)` greys it out and makes it ignore input), `focusable`, `flex`, `userData`, `tooltip` and `parent`.

* `w->fit()` resizes the window to the preferred size of its content: `prefW()` and `prefH()` of the root, which for a `Box` are the sums of its children plus spacing and padding.
* A button takes the keyboard focus when clicked or when you press Tab; Enter and Space then press it. A focused button has an accent coloured outline.
* The colours come from globals of the module: `gui.cAccent`, `gui.cText`, `gui.cTextDim`, `gui.cBack` and others. Changing them gives a different look (see the next chapter).

## Layout with boxes

A `gui.Box` arranges its children in a **column** (`gui.vbox(spacing, padding)`) or a **row** (`gui.hbox(spacing, padding)`). `spacing` is the gap between children, `padding` the margin inside the box.
Boxes go inside boxes, as deep as you like. A box draws nothing unless you set `background` or `border` to a colour, which is a good way to see what the layout does.

{{sample gui/box_layout src}}

{{shot gui/box_layout}}

The layout rules are short:

1. **Along** the box (down in a column, right in a row) every child gets its preferred size (`prefW()` or `prefH()`), unless it has `flex`.
2. **Across** the box every child is **stretched** to the full width (column) or height (row), minus the padding. That is why the text field and the label boxes in the picture are as wide as the window.
3. What is left over along the box is divided among the children with `flex > 0`, in proportion to their `flex`.
4. A box without flexible children leaves the extra room empty at the end (right or bottom).

{{sample gui/flex_layout src}}

{{shot gui/flex_layout}}

**What to notice**

* The search field has `flex = 1`, so it takes all the width the label and the button do not need. In the second row the three buttons share the width 1 : 2 : 1.
* The list box has `flex = 1` in a column, so it grows downwards to the bottom of the window. The window keeps its 380 x 220 because the program never calls `fit()`.
* Resize the window (drag the grip in the corner) and the layout is done again; the widgets with `flex` follow.

### Separators and spacers

`gui.Separator` draws a thin line: horizontal in a column, vertical in a row. `gui.Spacer(size)` is an empty widget of `size` x `size` pixels; give it `flex` and it becomes elastic, which pushes the widgets after it to the end of the row.

{{sample gui/separators src}}

{{shot gui/separators}}

## Callbacks

Everything that happens in a window reaches your program as a **callback**: a function `int f(int widget)` that you store in a field such as `onClick`. The argument is the widget that fired it, as an `int`.
Cast it to the right class to read its fields. Every widget has a `userData` field that belongs to you: one function can serve many widgets.

{{sample gui/callbacks_userdata src}}

{{shot gui/callbacks_userdata}}

| Field | Class | When |
|---|---|---|
| `onClick` | `Button` | pressed and released over the button, or Enter / Space |
| `onChange` | `CheckBox`, `TextBox`, `TextArea`, `Slider` | the state or the text changed |
| `onEnter` | `TextBox` | Enter was pressed in the field |
| `onSelect`, `onActivate` | `ListBox` | another row was chosen; double click or Enter |
| `onMouseEvent` | `Canvas` | any mouse event on the canvas |
| `onContext` | every widget | right click (see the next chapter) |

A callback runs inside the event loop: **do not block in it** (no waiting for input, no long calculation), or the windows stop responding. Use a timer or `pump` for long work.

## Text fields and text areas

A `gui.TextBox` is one line of editable text. `text()` returns the current text, `setText(t)` replaces it. It has `placeholder` (grey text while empty), `password` (shows dots), `onChange` and `onEnter`.
Inside it works as you expect: arrow keys, Home, End, Shift for selecting, Backspace and Delete, the mouse for placing the caret and selecting, and Ctrl+A, C, X, V for select all, copy, cut and paste.
Any Unicode character can be typed.

{{sample gui/text_input src}}

{{shot gui/text_input}}

**What to notice**

* `gui.caretBlinks = false;` keeps the caret solid. By default a focused text field blinks its caret every 500 ms with a timer; the book's pictures need a program that looks the same every time.
* `w->setFocus(widget)` gives the keyboard to a widget when the window opens. Tab moves the focus to the next focusable widget, Shift+Tab to the previous one.
* The status line is greyed with `gui.cTextDim`. The `text()` pointer is valid until the next change of the field: copy it (`strdup`) if you keep it.

A `gui.TextArea` is the multi-line version: `text()`, `setText(t)`, `lineCount()`, `onChange`, and `readOnly` for a viewer. It scrolls and has a caret, arrow keys, Home, End, PageUp, PageDown, Backspace, Delete and Enter.

{{sample gui/text_area src}}

{{shot gui/text_area}}

::: warning

`TextArea` is a simple editor: it has **no selection** and handles only Ctrl+V of the clipboard keys. For a real editor with selections, undo, syntax colours and many more features
see the `gcode` module and `examples/gui/codedemo.a`.

:::

### The clipboard

The display server keeps one plain text clipboard for all programs. `d->setClipboard(text)` puts text there; the text widgets use Ctrl+C, Ctrl+X and Ctrl+V for the same clipboard.
`d->requestPasteTo(widget)` asks for the clipboard text and calls `widget->onPaste(text)` when it arrives.

{{sample gui/clipboard src}}

{{shot gui/clipboard}}

## Lists, sliders and progress bars

A `gui.ListBox` shows rows of text. `addItem(text)` adds one, `item(i)` reads one, `size()` counts them, `clear()` empties the list; `selected` is the chosen row (-1 for none) and `select(i)` chooses one.
Rows are 23 pixels high. The list scrolls with the mouse wheel and the keys Up, Down, PageUp, PageDown, Home and End. `onSelect` is called for every change of the selection, `onActivate` for a double click or Enter.

{{sample gui/list_select src}}

{{shot gui/list_select}}

A `gui.Slider(min, max)` has `value`, `setValue(v)` and `onChange`. A `gui.ProgressBar` shows `value` from 0 to 100 (`setValue`).

{{sample gui/slider_progress src}}

{{shot gui/slider_progress}}

**What to notice**

* The slider is moved by clicking or dragging, and with Left and Right (one twentieth of the range at a time). `setValue` clamps to the range and only calls `onChange` when the value really changed.
* For work of unknown length `bar->start()` animates the bar (a block that moves back and forth) and `bar->stop()` ends it. It runs on a timer, so the program must be in the event loop.

## Pictures and canvases

`gui.ImageView(surface)` shows a `gfx.Surface`: a loaded file, a thumbnail, or something you drew. It paints with `blitBlend`, so transparent parts show the window background.

{{sample gui/image_view src}}

{{shot gui/image_view}}

A `gui.Canvas(w, h)` is a surface of its own (`canvas->surf`, white at first) that you draw into with all the functions of the previous chapter. It reports mouse events through `onMouseEvent`:
`lastKind` is `adp.M_DOWN`, `M_UP`, `M_MOVE` or `M_SCROLL`, `lastButton` is 1 (left), 2 (middle) or 3 (right), and `lastX`, `lastY` are the position **inside the canvas**.
After drawing you call `invalidate()` so that the canvas is painted again.

{{sample gui/canvas_clicks src}}

{{shot gui/canvas_clicks}}

**What to notice**

* A canvas has `flex = 1` by default and would stretch with the window; `canvas->flex = 0` keeps it at the size of its surface.
* The three clicks were at screen positions (80, 110), (150, 140) and (210, 100); the label shows the last one inside the canvas: 158, 14.
* Mouse events with the button down keep going to the canvas even when the pointer leaves it, which makes dragging work. A drawing program is in [the programs chapter](#chap-gui-programs).

## Timers

`d->after(ms, f, arg)` calls `int f(int arg)` once, `ms` milliseconds later, from the event loop. It returns a number for `d->cancel(id)`, or -1 when 32 timers are already waiting.
A timer fires **once**: to repeat, start the next one inside the callback.

{{sample gui/timer_ticks src}}

{{shot gui/timer_ticks}}

**What to notice**

* The chain runs `tick(1)` after 300 ms and then every 150 ms; the picture was taken after it ended, so it is the same every time.
* The second timer (`never`) is cancelled before it can fire. After `cancel` the number is no longer valid.
* A timer is only as exact as the event loop: callbacks and drawing delay it a little.

## Windows

`createWindowAt(title, x, y, w, h, flags)` places the client area at a position (the title bar is above it). The flags come from the module `adp`:

| Flag | Meaning |
|---|---|
| `adp.F_NODECOR` | no title bar and no border: the window is only its client area (panels, popups, splash screens) |
| `adp.F_FIXED` | the user cannot resize or maximize it |
| `adp.F_BELOW` | stays under all other windows (a wallpaper) |
| `adp.F_ABOVE` | stays above the others (a panel) |
| `adp.F_NOFOCUS` | never takes the keyboard focus |

{{sample gui/window_flags src}}

{{shot gui/window_flags}}

The methods of a `gui.Window`: `setRoot`, `setTitle`, `move(x, y)`, `resize(w, h)`, `fit()`, `show()`, `hide()`, `raise()`, `close()`, `setFocus(widget)` and `invalidate(x, y, w, h)`.
Properties and callbacks: `defaultButton` (a button that Enter presses), `onClose`, `onClosed`, `onKey`, `onResize`, and `noClear` (the program paints everything itself into `w->surf`).

{{sample gui/window_events src}}

{{shot gui/window_events}}

* `onKey(window, key, uni)` receives the keys that **no widget wanted**: here nothing has the focus, so the key `x` (code 120) comes to the window. Key codes of letters and digits are the lower case character; the other keys have the constants `adp.KEY_*`.
* `onResize` is called after the server resized the window; `w->w` and `w->h` hold the new size, and the root widget has already been laid out again.
* `onClose` runs when the user presses the close button: return non-zero to keep the window open (to ask "save changes?"), zero to let it close. `onClosed` runs afterwards, once.
* `d->quit = true` ends `d->run()` from anywhere, for a Quit menu item for example.

### Message boxes

`gui.messageBox(d, title, text)` shows a small window with a text and an OK button, and closes itself. It is a good example of a window made by a function that returns at once: the program goes on, and the dialog is just another window in the event loop.

{{sample gui/message_box src}}

{{shot gui/message_box}}

The text is a single `Label` (no wrapping) and the window is as wide as it needs to be, so keep the message short: it cannot be resized (`F_FIXED`). The next chapter has dialogs that ask a question and call you back with the answer.

## Your own widget

When the standard widgets do not fit, make a class that extends `gui.Widget`. Call `super();` first in the constructor and override what you need:

| Method | Purpose |
|---|---|
| `prefW()`, `prefH()` | the size you want; the layout asks for it |
| `paint(surface, ox, oy)` | draw the widget. `ox`, `oy` is the position of its top left corner **on the surface**: draw relative to them. Drawing outside `w` x `h` is clipped |
| `onMouse(kind, button, mx, my, mods)` | mouse events, with `mx`, `my` relative to the widget. Return `true` when you used the event |
| `onKey(down, key, uni, mods)` | key events (`down` is 1 for a press, 0 for a release) when the widget has the focus |
| `wantsScroll()` | return `true` to receive the mouse wheel (`kind == adp.M_SCROLL`, `button` is +1 up or -1 down) |

Set `focusable = true` in the constructor if the widget should take the keyboard focus. A click then gives it the focus by itself. When the widget's state changes call `invalidate()`, which asks for a repaint of just that widget.

{{sample gui/custom_widget src}}

{{shot gui/custom_widget}}

**What to notice**

* The picture was made by two clicks (+10 each) and four steps of the wheel (+5 each): 40. The outline shows the keyboard focus.
* `win` is the window the widget belongs to (`null` until it is put into one); `win->focusWidget == this` tells whether it has the focus.
* Without `wantsScroll()` returning `true` the wheel never reaches a custom widget.
* The knob draws with `thickArc` and `textCentered` from the previous chapter. Everything in the toolkit is made like this.

## The event loop and `pump`

`d->run()` is the loop `while (!d->quit && connected) { d->pump(50); }`. `d->pump(ms)` does one round: it paints the windows that changed, sends the pixels, waits up to `ms` milliseconds for
events or for the next timer, handles what arrived (events, timers, watched file descriptors), and paints again. It returns earlier when there was something to do.
When you have work of your own, write the loop yourself: one step of work, then `pump`.

{{sample gui/own_loop src}}

{{shot gui/own_loop}}

**What to notice**

* Each round does one of the 100 steps and then `pump(5)`, so the window stays responsive (it can be moved, resized and closed) while the "work" runs.
* When the last window closes `d->quit` becomes true and the loop ends; the program continues after it and prints a line.
* A callback that calls `pump` itself would run events inside a callback; keep the loop in `main`.
* `d->watch(fd, f, arg)` adds a file descriptor (a socket or a pipe) to the loop: `f(arg)` is called whenever it is readable. This is how network and terminal widgets work without threads.

## Summary

* A graphical program connects to a display server (`adisplayd`) named by `ADISPLAY`, creates windows, and draws into them with `gfx`. `actl` and `-vnc` let you control and watch a headless display.
* `gui.connect(null)`, `createWindow`, `setRoot`, `d->run()` are the skeleton of every program.
* Layout is done by `Box`: preferred sizes along the box, stretching across it, `flex` for the rest, `fit()` for the window.
* Widgets call you back with `int f(int widget)`; `userData` is yours.
* `TextBox`, `TextArea`, `ListBox`, `Slider`, `ProgressBar`, `ImageView` and `Canvas` cover the basic needs; `after` runs timers; `setClipboard` and `messageBox` talk to the rest of the system.
* A window has flags, and the callbacks `onClose`, `onKey` and `onResize`.
* Your own widget extends `gui.Widget` and overrides `paint`, `onMouse`, `onKey`, `prefW`, `prefH` (and `wantsScroll`).
* `d->pump(ms)` lets you write your own loop.

## Where next

* [More widgets: menus, tabs, tables, dialogs, charts](#chap-gui-more-widgets)
* [Four small applications, built step by step](#chap-gui-programs)
* [The display server](#chap-display-server): windows, layers, input and the protocol behind everything in this chapter
* API references: [`gui`](#api-gui), [`adp`](#api-adp), [`gfx`](#api-gfx)
