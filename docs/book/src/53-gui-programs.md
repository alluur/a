# Four small applications, step by step

The last two chapters showed the parts. This chapter puts them together. Each application is built in two steps: a **first version** that does the one thing it is for, and a **finished version** with
the details that make it pleasant to use. Read the first version, run it, then look at what the second one adds and why.

The four programs are a counter, a to-do list, a drawing program and an analog clock. Together they use buttons and boxes, text input and lists, a canvas and the mouse, your own widgets,
timers, command line arguments, a file, and PNG output.

In this chapter:

* a pattern for keeping the state of an application in one place and updating the windows from it;
* a list that is rebuilt from data, and a file that keeps the data between runs;
* a drawing program: mouse strokes, a palette widget of your own, saving a picture;
* a clock: a custom widget drawn with polygons, a repeating timer and a module of its own.

All programs run against a display server as explained in [the chapter on windows and widgets](#chap-gui-basics). Each picture was taken by running the program against a headless display server and performing the clicks and keys written at the top of the sample (the first clock has none).

## A counter

The smallest application with state: a number, and buttons that change it.

### First version

{{sample gui/counter_basic src}}

{{shot gui/counter_basic}}

The state is the global `count`. `show()` is the **one** function that turns the state into what you see; the two callbacks only change the state and call it. The picture was taken after three clicks on "+".

* The two buttons have `flex = 1` in a row, so they share the width equally.
* `shown->font = gfx.sansBold()` and `align = 1` make the number bold and centred.
* The label is created with the text "0" and `show()` is not called at the start: the initial state and the initial text agree. Calling `show()` once at the start is safer in a larger program, as the next version does.

### The finished version

The finished counter has a step (a `SpinBox`), limits that disable the buttons, a Reset button, the keys +, - and 0, and a window title that shows the value.

{{sample gui/counter_app src}}

{{shot gui/counter_app}}

**What changed, and why**

* `show()` does more now: it also sets the title with `win->setTitle`, and enables or disables the two buttons with `setEnabled` at the limits. Everything that depends on `count` is in that one function, so no path can forget one of them.
* `add(delta)` changes `count` for the buttons and the keys `+` and `-`; it clamps the value to -20 .. 20. Reset sets `count` to 0 itself, and every path ends in `show()`.
* `win->onKey` gets the keys that no widget used. The focused widget gets a key first; a button has no use for `+`, so it falls through to the window. (A focused spin box would take the digit `0` for itself.) The picture shows the result of three clicks of step 2 and then the `+` key: 8.
* The callbacks use globals (`win`, `shown`, `less`, `more`, `step`). This program has one window with one set of widgets, and a global is the simplest way for a callback to reach them. With several windows, use the `userData` field that every widget and every window has.

## A to-do list

A list of tasks that you add, mark as done and remove, that remembers them between runs.

### First version

{{sample gui/todo_basic src}}

{{shot gui/todo_basic}}

The row at the top has a text field with `flex = 1` and an Add button; both call `addTask`. Below is a `ListBox` that grows with the window.

* `entry->setText("")` empties the field after adding, and `w->setFocus(entry)` means you can type at once.
* Typing a task and pressing Enter works because the field has `onEnter = addTask`. The three tasks in the picture were typed with the keyboard.
* The list box keeps its own copy of the strings: `list->addItem(text)` copies `entry->text()`.

### The finished version

A `ListBox` cannot change an item, mark one, or remove one. So the finished program keeps its **own data** in two arrays (`tasks` and `done`) and builds the list box from it each time: `refresh()` clears the list, adds one row for every task
(with `[x]` or `[ ]` in front), restores the selection, updates the summary label and saves the file. Every command changes the data and then calls `refresh()`.

{{sample gui/todo_app src}}

{{shot gui/todo_app}}

**What changed, and why**

* The data is the truth and the widgets are a view of it. That is why `refresh()` can be called after every change and never get out of step.
* `toggleTask` and `removeTask` work on `list->selected`, the index of the selected row. A row of the list is a task of the array with the same index, so no search is needed.
* `save()` writes `todo.txt` after every change, one line per task (`x text` for a done task, `- text` for an open one), and `load()` reads it at the start. Run the program, add tasks, close it and run it again in the same directory:
  the tasks are back. The picture shows the result of three tasks typed, the second one selected and **Done / not done** pressed: "2 of 3 tasks open".
* The helper `appendLine` builds a new string with `malloc`, `strcpy` and `strcat`. A has no built-in string type (a string is a `char*`), so text work is done with small functions like these; the `strings` module has a `StringBuilder` for the same job. The previous string is never freed, which is fine for a file of a few lines.

## A drawing program

A canvas that you draw on with the mouse, a palette, a brush size, Clear and Save.

### First version

{{sample gui/paint_basic src}}

{{shot gui/paint_basic}}

The picture is a house drawn with six mouse drags (the directive lines at the top of the sample). The canvas reports every mouse event, and the program joins the previous position to the new one with a line.

* `lastX` is -1 while the button is up. A press (`M_DOWN`) sets the start of a stroke, a move with the button down draws a line from the last position, a release (`M_UP`) ends the stroke.
* The canvas gets the events with the button down even when the pointer leaves it, so a stroke can run over the edge without breaking.
* After drawing into `c->surf` the program calls `c->invalidate()`, otherwise the window would not show the change.
* The size of the window is chosen to fit the canvas (320 x 220 plus the padding), and the canvas has `flex = 0` so that it keeps its surface size.

### The finished version

The finished program adds colours, a brush size, Clear and Save. The colours are a **widget of its own**, `Palette`: a row of eight cells that draws itself and stores the selected cell.
Moving the mouse quickly makes events that are far apart, so a thick brush must fill the gap: the program places a dab at every pixel of the way.

{{sample gui/paint_app src}}

{{shot gui/paint_app}}

**What changed, and why**

* `Palette` overrides `prefW`, `prefH`, `paint` and `onMouse`, as in [the custom widget of the basics chapter](#chap-gui-basics). A click on cell `mx / 32` selects it, and the selected cell has an accent outline.
* The slider sets the radius of the brush. `dab` draws a filled circle in the selected colour. `mouse` calls it once for every pixel between the old and the new position (`steps` is the larger of the two distances), so strokes are solid at any speed.
* The first version joined two points with `line`, which is always one pixel thick. The finished one replaces it with dabs, so the brush can have any radius from 1 to 12.
* **Clear** fills the canvas surface with white, **Save** writes it with `gimg.savePng(canvas->surf, "painting.png")` and reports it in a label. The canvas *is* the document: there is nothing else to save.
* The window is made with `fit()`, which resizes it to the preferred size of its content. The toolbar row asks for 530 pixels and a column gives every child the full width, so the canvas widget is 530 pixels wide. Its surface is 528 pixels, about the same; the two missing pixels show as a thin strip of background inside the right border.
* The picture was made with a click on the red cell and a drag, a click on blue and a drag, and so on: four strokes in four colours.

## An analog clock

A clock needs three things: a widget that draws a face for any time, a timer that asks for the time every second, and a way to test it with a time that does not change.

### First version: the clock face

The widget `ClockFace` has `hour`, `minute` and `second` and draws a dial with 60 ticks and three hands. A hand is a thin four-sided polygon from a short tail behind the centre to the tip, so `fillPolygon` draws it;
the corners come from `icos` and `isin`, as in the polygon sample of [the drawing chapter](#chap-graphics).

{{sample gui/clock_face src}}

{{shot gui/clock_face}}

**What to notice**

* Angles are measured clockwise from 3 o'clock, so 12 o'clock is -90 degrees: the hour hand is at `(hour % 12) * 30 + minute / 2 - 90` degrees. The minute hand moves a little with the seconds, the hour hand with the minutes.
* The widget paints relative to `ox`, `oy` and takes its size from `w` and `h`, so it works at any size the layout gives it.
* The picture shows 10:08:35: the hour hand just past 10, the minute hand between 1 and 2, the red second hand at 35.
* `hand` is a **private** method; it is only used inside the class.

### The finished version

The finished clock moves the widget into its own **module**, `clockface.a`, and the program in `main.a` imports it with `import clockface;`. It adds a digital readout, a check box that hides the second hand, a timer that updates the face once a second,
and a command line argument: `clock 10:08:35` shows that time and does not tick, which is also how the picture was made.

{{sample gui/clock_app src}}

{{shot gui/clock_app}}

**What changed, and why**

* The program is two files. `clockface.a` declares `module clockface;` after its imports and has `public class ClockFace`; `main.a` uses it as `clockface.ClockFace`. The widget can now be used by any program.
* `tick` reads the time with `datetime.now()` (UTC: the `datetime` module knows no time zones), shows it, and starts the next timer: a timer fires only once.
* `show` is the one function that turns a time into widgets, as `show` of the counter did. The command line decides where the time comes from: without an argument `tick(0)` starts the clock, with one `show` is called once.
* The check box has `onChange`; its callback sets the field and calls `invalidate()` on the face. The picture was taken after one click on it: the second hand is gone.

## Ideas to go further

* **Counter**: remember the value in a file as the to-do list does; add a menu bar with Quit and Reset (`guix`).
* **To-do list**: ask before removing (`guix.confirm`), edit a task with `guix.prompt`, keep a due date with `guix.chooseDate`.
* **Drawing program**: the white cell of the palette already works as an eraser; add a File menu with `guix.saveFile` and `guix.openFile` (`gimg.load` gives you the picture back), and an undo that keeps a copy of the surface.
* **Clock**: a time zone offset in a spin box, an alarm with `guix.notify`, a digital clock widget made with `textScaled`.

## Summary

* Keep the **state** of the application in variables and update the widgets from it in one function; callbacks change the state and call that function.
* A widget that cannot do what you need (a list that changes its items) is a view: keep the data yourself and rebuild the view.
* A canvas is a surface and a source of mouse events; the program draws into the surface and calls `invalidate()`.
* A widget of your own is a class with `paint`, `onMouse`, `prefW` and `prefH`; put it in a module when other programs can use it.
* Timers fire once: start the next one in the callback. Command line arguments (`main(int argc, char** argv)`) make a program easy to test.
* `gimg.savePng`, `readFile` and `writeFile` keep results between runs.

## Where next

* [Windows and widgets](#chap-gui-basics) and [more widgets, dialogs and charts](#chap-gui-more-widgets) for everything the applications could still use.
* [Drawing and images](#chap-graphics) for the functions behind the canvas and the clock.
* [Networking and the web inside a GUI](#chap-gui-net-and-web): fetch pages and talk to other programs without freezing a window.
* API references: [`gui`](#api-gui), [`guix`](#api-guix), [`gfx`](#api-gfx), [`gimg`](#api-gimg), [`datetime`](#api-datetime).
