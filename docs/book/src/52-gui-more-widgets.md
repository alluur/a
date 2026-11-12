# More widgets: menus, tabs, tables, dialogs and charts

The module `gui` has the basic widgets. `guix` adds the ones that real applications need: menus with keyboard accelerators, combo boxes, radio buttons, tabs, scroll views, spin boxes,
splitters, tables, trees, toolbars with icons, a status bar, a calendar, tool tips and notifications, and **dialogs** that ask a question and call you back with the answer.
`gchart` adds data widgets: charts, gauges, switches and star ratings. All of them are ordinary `gui.Widget`s: you put them into a `Box`, give them `flex` or a size, and handle them with callbacks.

In this chapter:

* menus, accelerators and context menus;
* combo boxes, radio buttons, tabs, scroll views, spin boxes and splitters;
* tables, trees, toolbars, status bars, tool tips and text blocks;
* dialogs: confirm, prompt, open and save file, colour, date, and notifications;
* colour schemes and the 31 built-in icons;
* charts, gauges, switches and ratings.

Every sample starts as the ones in [the previous chapter](#chap-gui-basics) did: `gui.connect(null)`, a window, a root box, `d->run()`. Most pictures were taken after the program had been driven by a click or a key
(the `// book:` lines at the top of the sample).

## Menus

A `guix.MenuBar` goes at the top of the window, as the first child of a column with no padding. `bar->addMenu("&File")` adds a menu and returns it; the `&` marks the letter for Alt+F, which opens the menu.
`menu->add(text, f)` adds an item and returns it; `f` is a function `int f(int item)` and the argument is the `guix.MenuItem*` (cast it). `addSeparator()` draws a line.

{{sample gui/menu_bar src}}

{{shot gui/menu_bar}}

**What to notice**

* `->accel("Ctrl+N")` on an item sets the accelerator **and** shows it at the right edge. The accelerator works anywhere in the window while the bar is in it, with the menu closed.
  The names are `Ctrl+`, `Shift+`, `Alt+` and `Meta+` in front of a letter, `F1` to `F12`, `Enter`, `Esc`, `Del`, `Tab`, `Space`, `Backspace`, `Home`, `End`, `Up`, `Down`, `Left`, `Right`, `PgUp`, `PgDn` or `Ins`.
* `->disable()` greys out an item. `->setId(n)` gives it a number and `menu->byId(n)` finds it again.
* The pointer opens a menu with a click and switches menus when it moves over another title. The keyboard works too: F10 opens the first menu, Alt and a letter opens the menu with that letter after the `&`,
  the arrow keys, Enter and Esc move through open menus.
* The first line of the callback is the usual cast. `m->text` is the text of the item.

### Check items and submenus

`addCheck(text, checked, f)` adds an item with a check mark; `item->checked` changes by itself when it is chosen (so it is already new when your callback runs). `addSub(text, menu)` puts another `Menu` inside as a submenu.

{{sample gui/menu_checks src}}

{{shot gui/menu_checks}}

### Accelerators

{{sample gui/menu_accelerators src}}

{{shot gui/menu_accelerators}}

The three keys were Ctrl+N twice and F5: the label shows the last one and that three actions ran. A program that needs accelerators but no visible menu can still use a `MenuBar`; for keys in general there is `Window.onKey`.

### Context menus

Every widget has an `onContext` callback, called on a right click. In it, show a menu where the pointer is: `menu->popup(window, x, y)` with `window->lastMouseX` and `lastMouseY`.
A menu that does not fit moves inside the window.

{{sample gui/context_menu src}}

{{shot gui/context_menu}}

## Combo boxes and radio buttons

A `guix.ComboBox` is a drop-down list. `addItem(text)`, `select(i)`, `selected` (-1 for none), `text()` (the chosen text) and `onChange`. The list opens below the box (or above it when there is no room) and scrolls when it has more than eight rows.

{{sample gui/combo_box src}}

{{shot gui/combo_box}}

Radio buttons need a group: create the `guix.RadioGroup` first, then each `guix.RadioButton(text, group)`. Exactly one button of a group is chosen. `group->selectedIndex()`, `group->selectIndex(i)` and `group->onChange`
(a function `int f(int group)`) are what you use; the arrow keys move inside a group.

{{sample gui/radio_buttons src}}

{{shot gui/radio_buttons}}

::: warning

`selectIndex`, `select` and `setValue` call `onChange` **at once** if it is already set. If the callback uses a label that does not exist yet, the program crashes. Create everything the callback needs first,
then set `onChange` and the start value, as the sample does.

:::

## Tabs, scroll views and spin boxes

A `guix.TabView` shows one page at a time. `addTab("Title", page)` takes any widget as a page (usually a `Box`); `select(i)`, `selected` and `onChange` read and change the tab. With `closable = true` the tabs get close buttons
(`onTabClose`, `removeTab(i)`). Left and Right switch tabs when the tab bar has the focus.

{{sample gui/tab_view src}}

{{shot gui/tab_view}}

A `guix.ScrollView` shows part of a larger widget: `setContent(widget)`. Scroll bars appear when the content is bigger than the view; the content has its preferred size, or exactly the width of the view when
`fitWidth = true` (then it only scrolls up and down). The mouse wheel scrolls, with Shift sideways, and a widget inside that gets the keyboard focus is scrolled into view.

{{sample gui/scroll_view src}}

{{shot gui/scroll_view}}

The picture was taken after five steps of the wheel (40 pixels each, eight rows of 25 pixels in all): row 9 is the first one visible, and the scroll bar thumb is a short piece near the top of the track.

A `guix.SpinBox(min, max)` is a number field with two small arrows. Type digits, press Up and Down (`step`) or PageUp and PageDown (ten steps), click the arrows or turn the wheel. `value`, `setValue` and `onChange` as usual.

{{sample gui/spin_box src}}

{{shot gui/spin_box}}

## Splitters, tool tips and colour swatches

`guix.Splitter(sideBySide, firstSize)` shows two widgets with a divider you can drag: `true` puts them side by side (the first one `firstSize` pixels wide), `false` one above the other.
`add` the two widgets in order. `pos` is the size of the first pane and `minPane` the smallest size either pane can have.

{{sample gui/splitter src}}

{{shot gui/splitter}}

Every widget has a `tooltip` field. When the pointer rests on the widget for half a second, a small yellow card with the text appears next to it, and goes away when the pointer leaves the widget or a button is pressed.

{{sample gui/tooltips src}}

{{shot gui/tooltips}}

The picture needed a pointer that stays where it is (`pointer=keep`) and a pause: the tip only appears while the pointer rests.

`guix.Swatch(colour, w, h)` is a rectangle of one colour with a thin border; change `swatch->color` and call `invalidate()`.

{{sample gui/rgb_mixer src}}

{{shot gui/rgb_mixer}}

## Tables and trees

A `guix.TableView` has columns and rows of text. Add the columns first (`addColumn("Name", 150)`, title and width), then rows: `addRow("a\tb\tc")` with the cells separated by tabs, or `addEmptyRow()` and `setCell(row, col, text)`.
`setAlign(col, 1)` right-aligns a column. A click on a header sorts by that column (text without regard to case, numbers by their value; `sortBy(col, ascending)` does it from the program, `onSort` takes it over), the edge of a header can be dragged to resize
the column, `selected` is the chosen row, `onSelect` and `onActivate` (double click or Enter) tell you, `cell(row, col)` reads a cell and `clear()` empties the table.

{{sample gui/table_view src}}

{{shot gui/table_view}}

The picture was taken after a click on the header "Size": the rows are sorted by the numbers in that column, smallest first, and a small arrow marks the column. A second click would reverse the order.

A `guix.TreeView` shows nodes that can have children. `tree->addRoot("text")` adds a top level node and returns a `guix.TreeNode*`; `node->add("child")` adds a child. `tree->expand(node, true)` opens a node,
`select(node)` chooses one; `selected`, `onSelect` and `onActivate` work like the list's. A node has `userData`, `expanded` and `lazy` (it shows an arrow although it has no children yet: add them in `tree->onExpand`, the node is `tree->expandedNode`).
Click the arrow or press Right, Left and Enter to open and close; Up, Down, Home, End, PageUp and PageDown move.

{{sample gui/tree_view src}}

{{shot gui/tree_view}}

`examples/gui/afiles.a` is a file browser made of a tree of folders, a table of files and a splitter.

## Toolbars, icons and the status bar

A `guix.Toolbar` is a row of flat icon buttons. `addButton(icon, "Tip", f)` returns the `guix.IconButton`; the text is its tool tip. `addSeparator()` adds a gap. An icon button can be a toggle: `toggle = true` and `checked`.
A `guix.StatusBar` has sections: `addSection(width)` (0 stretches over what is left) and `setText(section, text)`.

{{sample gui/toolbar_status src}}

{{shot gui/toolbar_status}}

**What to notice**

* The click on the Save icon calls `tool`, and the status bar shows its tip. The star is a toggle that starts pressed.
* A section is exactly `width` pixels wide and cuts its text: the second section is 90 pixels so that "Ln 1, Col 1" fits.

There are 31 icons (`guix.ICON_NEW` is 1 to `ICON_PANEL`, 31). `guix.drawIcon(surface, icon, x, y, colour)` draws one, 16 x 16 pixels, on **any** surface in any colour, so it works outside toolbars too; the sample draws them without a window.

{{sample gui/icons}}

{{shot gui/icons}}

## Text blocks and calendars

A `guix.TextBlock(text)` is text that **wraps** at the width of the widget: `\n` starts a paragraph, `align` (0 left, 1 centre, 2 right), `color`, `wrapWidth`. A `gui.Label` is always one line.

{{sample gui/text_block src}}

{{shot gui/text_block}}

A `guix.Calendar` shows a month: `year`, `month`, `day`, `setDate(y, m, d)` and `onChange`. Click a day, use the arrows or the wheel to change the month, the arrow keys to move by day and week, PageUp and PageDown by month.

{{sample gui/calendar src}}

{{shot gui/calendar}}

## Dialogs

A dialog opens a window of its own, and when the user is done it calls **your** function with the result and closes. The call returns at once; the answer arrives later, in the event loop.

| Function | The callback `int f(int result)` receives |
|---|---|
| `guix.confirm(d, title, text, f)` | 1 for Yes, 0 for No or a closed window |
| `guix.prompt(d, title, label, initial, f)` | the text as a `char*` (cast to `int`), 0 when cancelled |
| `guix.openFile(d, title, startDir, f)` | the chosen path as a `char*`, 0 when cancelled |
| `guix.saveFile(d, title, startDir, name, f)` | the path; the dialog asks before it replaces a file |
| `guix.chooseColor(d, title, 0xFFRRGGBB, f)` | the colour as `0xFFRRGGBB`, 0 when cancelled |
| `guix.chooseDate(d, title, year, month, day, f)` | `year * 10000 + month * 100 + day`, 0 when cancelled |

Each of `confirm`, `prompt`, `openFile` and `saveFile` has an `...Arg` version that takes one more `int`; your function reads it from `guix.dialogArg`, which is handy when several dialogs share one callback. All dialogs return the window they opened.

{{sample gui/dialog_confirm src}}

{{shot gui/dialog_confirm}}

{{sample gui/dialog_prompt src}}

{{shot gui/dialog_prompt}}

**What to notice**

* In the picture of the prompt the main window is grey: it has lost the focus to the dialog. Both windows go on working, it is not a modal dialog box in the sense of other toolkits.
* A cancelled prompt gives 0, which is why `answered` tests `text == 0` before it casts the number back to a string.
* `initial` is the text the field starts with.

The file dialogs list a directory: folders first (entered with a double click, `..` goes up), a check box shows hidden files, and a text field holds the name. The sample makes a few files first so that there is something to see.

{{sample gui/dialog_open_file src}}

{{shot gui/dialog_open_file}}

{{sample gui/dialog_save_file src}}

{{shot gui/dialog_save_file}}

{{sample gui/dialog_color src}}

{{shot gui/dialog_color}}

{{sample gui/dialog_date src}}

{{shot gui/dialog_date}}

### Notifications

`guix.notify(d, title, text, kind, ms)` shows a card in the top right corner of the screen: `kind` 0 is information, 1 a warning, 2 an error. It disappears after `ms` milliseconds or on a click, and up to six cards are shown at a time.
It is for events that arrive while the user does something else: a download that finished, a message from a friend.

{{sample gui/notifications src}}

{{shot gui/notifications}}

## Colours and icons of your own program

The standard look is light. All widgets read a handful of **global variables** when they paint, so a program with another colour scheme sets them before it builds its windows:

| Module | Variables |
|---|---|
| `gui` | `cBack` (windows), `cText`, `cTextDim`, `cAccent`, `cAccentText`, `cField` (text fields, lists), `cBorder`, `cButton`, `cButtonHot`, `cButtonDown`, `cSelect`; tool tips: `cTipBack`, `cTipBorder`, `cTipText` |
| `guix` | `cPanel` (menu popups, notification cards), `cTabIdle`, `cTrack`, `cThumbOff` (scroll bars), `cHeadTop`, `cHeadBottom`, `cStripe` (tables) |
| per widget | `MenuBar.background`, `Toolbar.background`; the text boxes have `colBack`, `colText`, `colSel`, `colBorder`, `colAccent`, `colDim` |

{{sample gui/dark_theme src}}

{{shot gui/dark_theme}}

The title bar and the border belong to the display server and keep its look. The menu popups take their colour from `guix.cPanel` (set in the sample), and the bar itself from `MenuBar.background`.

## Charts, gauges, switches and ratings

`gchart` has four widgets for data. They paint like all widgets, so the first pictures here are made **without a window**: a widget has `w` and `h`, and `widget->paint(surface, x, y)` draws it into any surface.
In a program you would put them in a box and let the layout size them (the last sample of this section does).

### Chart

`gchart.Chart(kind)` with `gchart.BAR`, `LINE`, `AREA` or `PIE`. `addSeries(name, colour)` adds a data series and returns its number (up to 8; colour 0 takes the next colour of a built-in palette).
Give it data with `setValues(series, array, n)` or one point at a time with `push(series, value)`: the chart keeps the last `maxPoints` points (60 by default) and the oldest drop out, so a live chart scrolls by itself.
`setLabels(names, n)` gives names to the bars or slices, `setRange(lo, hi)` fixes the vertical axis (otherwise it is chosen from the data, in steps of 1, 2 or 5 times a power of ten), `title`, `legend`, `grid` and `stacked` change the look.
`seriesCount()`, `pointCount(s)`, `valueAt(s, i)` and `clearData()` read and reset the data.

{{sample gfx/chart_bar}}

{{shot gfx/chart_bar}}

{{sample gfx/chart_line}}

{{shot gfx/chart_line}}

{{sample gfx/chart_area}}

{{shot gfx/chart_area}}

**What to notice**

* In the bar chart with `stacked = true` the series are piled up instead of drawn side by side, and the axis grows to the sum.
* The line chart shows two series with different colours from the palette and a legend; `setRange(0, 100)` keeps the axis from moving.
* `maxPoints = 30` made the area chart keep 30 of the 100 values pushed; `valueAt(load, 0)` is the oldest one that is left.

{{sample gfx/chart_pie}}

{{shot gfx/chart_pie}}

A pie chart draws **one slice per value** of the first series and takes the slice names from `setLabels`.

### Gauge, switch and rating

A `gchart.Gauge(min, max)` is a dial with coloured zones: green, then yellow from `warn` percent of the range (60 by default) and red from `critical` (85); set both to 100 for one colour. `setValue(v)` clamps to the range, `caption` is a text below the value.
A `gchart.Switch(initial)` is an on/off toggle (`on`, `set(b)`, `onChange`; click or Space). A `gchart.Rating(stars, initial)` is a row of stars to click (`value`, `max`, `set(n)`, `onChange`).

{{sample gfx/gauges}}

{{shot gfx/gauges}}

{{sample gfx/switch_rating}}

{{shot gfx/switch_rating}}

::: note

A gauge draws its caption **below** its preferred height, so a gauge that gets exactly `prefH()` (100 pixels) in a window shows the number but not the caption. Give it more room (a taller box), or leave the caption out.

:::

### In a window

{{sample gui/charts_window src}}

{{shot gui/charts_window}}

**What to notice**

* The chart has `flex = 1` and fills the window; the gauge and the stars keep their preferred sizes. `push` calls `invalidate()` by itself, so the chart redraws.
* The picture shows the 12 starting values and five clicks on **Add sample**, which pushed 35, 52, 61, 48 and 73 from the table in the program. The gauge shows the last of them, 73.
* Real programs would call `push` from a timer (`d->after`): [the previous chapter](#chap-gui-basics) shows how timers work.

## Summary

* `guix.MenuBar`, `Menu`, `MenuItem`: titles with `&`, items with callbacks `int f(int item)`, `->accel("Ctrl+S")`, `addCheck`, `addSub`, `addSeparator`, `disable`; context menus with `onContext` and `popup`.
* `ComboBox`, `RadioGroup` + `RadioButton`, `TabView`, `ScrollView`, `SpinBox` and `Splitter` cover choices and structure. Callbacks fire as soon as `onChange` is set and the value changes: create what they use first.
* `TableView` (columns, rows, sorting), `TreeView`, `Toolbar` with `IconButton`, `StatusBar`, `TextBlock`, `Calendar` and `tooltip` finish the set; `drawIcon` draws any of the 31 icons anywhere.
* Dialogs (`confirm`, `prompt`, `openFile`, `saveFile`, `chooseColor`, `chooseDate`) call your function with the answer; `notify` shows a card.
* A colour scheme is a set of global variables (`gui.cBack` and friends) set before the windows are built.
* `gchart`: `Chart` (bar, line, area, pie), `Gauge`, `Switch`, `Rating`: ordinary widgets that can also paint into any surface.

## Where next

* [Four small applications built step by step](#chap-gui-programs) put widgets, dialogs and drawing together.
* [Drawing and images](#chap-graphics) for the functions behind `Canvas` and your own widgets.
* [The code editor widgets](#chap-code-editor-widgets): the themed editor, file tree, tabs, find bar and terminal pane of the AIDE editor.
* API references: [`guix`](#api-guix), [`gchart`](#api-gchart), [`gui`](#api-gui).
