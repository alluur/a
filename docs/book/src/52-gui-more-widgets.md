# More widgets: menus, tabs, tables, dialogs and charts

The module `gui` has the basic widgets. `guix` adds the ones that real applications need: menus with keyboard accelerators, combo boxes, radio buttons, tabs, scroll views, spin boxes,
splitters, tables, trees, toolbars with icons, a status bar, text blocks and a calendar, and **dialogs** that ask a question and call you back with the answer. (Tool tips are part of `gui` itself: every widget has a `tooltip` field.)
`gchart` adds data widgets: charts, gauges, switches and star ratings. All of them are ordinary `gui.Widget`s: you put them into a `Box`, give them `flex` or a size, and handle them with callbacks.

In this chapter:

* menus, accelerators and context menus;
* combo boxes, radio buttons, tabs, scroll views, spin boxes, splitters, tool tips and colour swatches;
* tables, trees, toolbars, status bars, text blocks and calendars;
* dialogs: confirm, prompt, open and save file, colour, date, and notifications;
* colour schemes and the 31 built-in icons;
* charts, gauges, switches and ratings.

The window samples start as the ones in [the previous chapter](#chap-gui-basics) did: `gui.connect(null)`, a window, a root box, `d->run()`. Most pictures were taken after the program had been driven by a click or a key
(the `// book:` lines at the top of the sample). The samples of the chart section that draw into a picture do not open a window at all.

## Menus

A `guix.MenuBar` goes at the top of the window, as the first child of a column with no spacing and no padding (`gui.vbox(0, 0)`). `bar->addMenu("&File")` adds a menu and returns it (a bar holds up to 16 menus); the `&` marks the letter for Alt+F, which opens the menu.
`menu->add(text, f)` adds an item and returns it; `f` is a function `int f(int item)` and the argument is the `guix.MenuItem*` (cast it). `addSeparator()` draws a line.

{{sample gui/menu_bar src}}

{{shot gui/menu_bar}}

**What to notice**

* `->accel("Ctrl+N")` on an item sets the accelerator **and** shows it at the right edge. The accelerator works anywhere in the window while the bar is in it, with the menu closed.
  Write the name exactly like this (the case matters): any of `Ctrl+`, `Shift+`, `Alt+` and `Meta+` in front of a single character, `F1` to `F12`, `Enter`, `Esc`, `Del`, `Tab`, `Space`, `Backspace`, `Home`, `End`, `Up`, `Down`, `Left`, `Right`, `PgUp`, `PgDn` or `Ins`.
* `->disable()` greys out an item: it does nothing when clicked, and its accelerator does nothing either. `->setId(n)` gives it a number and `menu->byId(n)` finds it again (also inside submenus).
* The pointer opens a menu with a click and switches menus when it moves over another title.
* The keyboard works without the pointer. F10 opens the first menu, and Alt and a letter opens the menu whose title has that letter after the `&`; in both cases the first item is already highlighted.
  Up and Down move through the items (and wrap around), Home jumps to the first item, Enter or Space runs the highlighted item, and Esc closes the menu (or only the submenu, when one is open).
  Right opens a submenu; when the highlighted item has no submenu, Right and Left go to the next and the previous menu of the bar, with nothing highlighted yet (press Down first). Left inside a submenu closes it.
  While a menu is open, Alt and a letter does not switch to another menu: close it first.
* The first line of the callback is the usual cast. `m->text` is the text of the item.

### Check items and submenus

`addCheck(text, checked, f)` adds an item with a check mark; `item->checked` changes by itself when it is chosen (so it is already new when your callback runs). `addSub(text, menu)` puts another `Menu` inside as a submenu.

{{sample gui/menu_checks src}}

{{shot gui/menu_checks}}

### Accelerators

{{sample gui/menu_accelerators src}}

{{shot gui/menu_accelerators}}

The program was driven with three keys: Ctrl+N twice, then F5. The label shows the last action, "Refresh", and the counter says that three actions ran. The menu was never opened: the keys alone ran the items.
A program that needs accelerators but no visible menu can still use a `MenuBar`: put it in the window and set `bar->visible = false`, and the accelerators keep working. For keys in general there is `Window.onKey`, which receives the keys that no widget wanted.

### Context menus

Every widget has an `onContext` callback, `int f(int widget)`, called on a right click. In it, show a menu where the pointer is: `menu->popup(window, x, y)` with `window->lastMouseX` and `lastMouseY`.
A menu that does not fit below the point opens above it, and one that is too wide is moved to the left, so that it stays inside the window. The keyboard and mouse work in it as in a menu of a bar.

{{sample gui/context_menu src}}

{{shot gui/context_menu}}

## Combo boxes and radio buttons

A `guix.ComboBox` is a drop-down list. `addItem(text)`, `select(i)`, `selected` (the number of the chosen row), `text()` (the chosen text) and `onChange`. The first item you add is chosen at once, so `selected` is -1 only while the box is empty;
`select` ignores a number that is out of range, so it cannot clear the choice. The list opens below the box (or above it when there is no room) and scrolls when it has more than eight rows. With the focus on a closed box, Up and Down change the choice and Enter or Space opens the list.

{{sample gui/combo_box src}}

{{shot gui/combo_box}}

Radio buttons need a group: create the `guix.RadioGroup` first, then each `guix.RadioButton(text, group)`. At most one button of a group is chosen: at the start none is, so call `selectIndex(0)` (or whichever you want), and from then on a click can only move the choice, never clear it.
`group->selectedIndex()` (-1 while nothing is chosen), `group->selectIndex(i)` and `group->onChange` (a function `int f(int group)`) are what you use. The arrow keys move the choice inside a group, and wrap around at the ends.

{{sample gui/radio_buttons src}}

{{shot gui/radio_buttons}}

::: warning

`selectIndex`, `select` and `setValue` call `onChange` **at once** when `onChange` is already set and the value really changes (setting the value a widget already has calls nothing). If the callback uses a label that does not exist yet, the program crashes.
Create everything the callback needs first, then set `onChange` and the start value, as the radio sample does. (The combo box sample sets its start value before `onChange`, so it starts without calling the callback.)

:::

## Tabs, scroll views and spin boxes

A `guix.TabView` shows one page at a time. `addTab("Title", page)` takes any widget as a page (usually a `Box`); `select(i)`, `selected` and `onChange` read and change the tab (the first tab you add is selected at once).
Left, Right, Home and End switch tabs when the tab view has the focus (click a tab title to give it the focus).

With `closable = true` every tab gets a small cross on its right. A click on it removes the tab. To take part, set `onTabClose`, a function `int f(int tabview)`: `tabview->closedIndex` holds the number of the tab, the tab is still there when your function runs,
and if you return 0 the tab is then removed; return 1 to keep it (to ask "Save changes?" first, for example). `removeTab(i)` removes a tab from your own code and does not call `onTabClose`.
No sample shows closable tabs; this paragraph comes from the library source and from a small test program that clicked the crosses.

{{sample gui/tab_view src}}

{{shot gui/tab_view}}

A `guix.ScrollView` shows part of a larger widget: `setContent(widget)`. Scroll bars appear when the content is bigger than the view; the content has its preferred size (but never less than the size of the view), or exactly the width of the view when
`fitWidth = true` (then it only scrolls up and down). The mouse wheel scrolls 40 pixels a step, with Shift sideways, and a widget inside that gets the keyboard focus is scrolled into view. `scrollTo(x, y)` scrolls from your code, and `offX` and `offY` tell where the view is now.
A `ScrollView` is a flexible widget (`flex = 1`) from the start.

The scroll bars are `guix.ScrollBar` widgets, which you can also use alone: `new guix.ScrollBar(vertical)`, then `configure(totalSize, pageSize)` and `setValue(v)`. The value always stays between 0 and `total - page`, `onChange` (`int f(int scrollbar)`)
runs when it changes, a click on the track beside the thumb moves it by one page, and the thumb can be dragged. This was tried with a small test program; no sample shows a lone `ScrollBar`.

{{sample gui/scroll_view src}}

{{shot gui/scroll_view}}

The picture was taken after five steps of the wheel: 5 x 40 = 200 pixels, which is exactly eight rows (a label is 21 pixels high and the box puts 4 pixels between rows, so a row takes 25). Row 9 is the first one visible, and the scroll bar thumb is a short piece near the top of the track.

A `guix.SpinBox(min, max)` is a number field with two small arrows. Type digits (and a minus sign when `min` is negative), press Up and Down (`step`, 1 unless you change it) or PageUp and PageDown (ten steps), Home and End (`min` and `max`), click the arrows or turn the wheel.
`value`, `setValue` and `onChange` as usual; `setValue` cuts the number to the range. The picture was taken after the start value 5, a click into the field, Up twice and PageUp once: 5 + 2 + 10 = 17.

{{sample gui/spin_box src}}

{{shot gui/spin_box}}

## Splitters, tool tips and colour swatches

`guix.Splitter(sideBySide, firstSize)` shows two widgets with a divider you can drag: `true` puts them side by side (the first one `firstSize` pixels wide), `false` one above the other (the first one `firstSize` pixels high).
`add` the two widgets in order; a splitter holds exactly two. `pos` is the size of the first pane (its width, or its height when the panes are stacked) and `minPane` the smallest size either pane can have (40 pixels unless you change it). The divider between the panes is 6 pixels wide.
A splitter is a flexible widget (`flex = 1`) from the start.

{{sample gui/splitter src}}

{{shot gui/splitter}}

The picture was taken after the divider had been dragged to the right, so the list is wider than the 120 pixels it started with. The stacked form works the same with the mouse moving up and down; this was tried with a small test program (a splitter of height 300 and `firstSize` 100:
dragging down 80 pixels gave `pos` 180, and dragging far down stopped at 254, leaving the second pane its 40 pixels), but no sample shows it.

Every widget has a `tooltip` field. When the pointer rests on the widget for half a second, a small pale yellow card with the text appears just below and to the right of the pointer, and goes away when the pointer leaves the widget or a button is pressed.

{{sample gui/tooltips src}}

{{shot gui/tooltips}}

The picture needed a pointer that stays where it is (`pointer=keep`) and a pause: the tip only appears while the pointer rests.

`guix.Swatch(colour, w, h)` is a rectangle of one colour with a thin border; change `swatch->color` and call `invalidate()`. A colour with an alpha below 255 shows the checkerboard behind it.
In the sample below the sliders mix a colour; the picture was taken after the three sliders had been dragged, and the label shows the result as `#C854FF`.

{{sample gui/rgb_mixer src}}

{{shot gui/rgb_mixer}}

## Tables and trees

A `guix.TableView` has columns and rows of text. Add the columns first (`addColumn("Name", 150)`, title and width; a table has up to 16 columns), then rows: `addRow("a\tb\tc")` with the cells separated by tabs, or `addEmptyRow()` and `setCell(row, col, text)`.
Both row functions return the number of the new row. `setAlign(col, 1)` right-aligns a column.

A click on a header sorts by that column: the first click ascending, the next one descending (cells that are both whole numbers are compared by their value, all others as text without regard to case; equal rows keep their order).
`sortBy(col, ascending)` sorts from the program. If you set `onSort` (`int f(int table)`), a click only sets `sortColumn` and `sortAscending` and calls you, and you sort yourself, usually with `table->sortBy(table->sortColumn, table->sortAscending)`; set `sortable = false` to turn header clicks off.
The edge of a header can be dragged to resize the column. `selected` is the chosen row (its position in the current order, -1 for none), `onSelect` and `onActivate` (double click or Enter) tell you, `cell(row, col)` reads a cell, `rowCount()` and `columnCount()` count, and `clear()` empties the table.

{{sample gui/table_view src}}

{{shot gui/table_view}}

The picture was taken after a click on the header "Size": the rows are sorted by the numbers in that column, smallest first (96, 310, 1204, 5120, 88411, 2048000), and a small arrow marks the column. A second click would reverse the order.
The `Size` cells are right-aligned because of `setAlign(1, 1)`.

A `guix.TreeView` shows nodes that can have children. `tree->addRoot("text")` adds a top level node and returns a `guix.TreeNode*`; `node->add("child")` adds a child. `tree->expand(node, true)` opens a node (or closes it with `false`),
`select(node)` chooses one; `selected` (a `TreeNode*`, null for none), `onSelect` and `onActivate` work like the list's. A node has `text`, `userData`, `expanded`, `parent`, `count` and `lazy`.
With the mouse, click the arrow to open or close a node, or double-click the node (which also calls `onActivate`). With the keyboard: Right opens a closed node, or moves to the first child of an open one; Left closes an open node, or moves to its parent;
Enter opens or closes the node and calls `onActivate`; Up, Down, Home, End, PageUp and PageDown move.

{{sample gui/tree_view src}}

{{shot gui/tree_view}}

In the picture, `tree->select(src)` made the label read "Selected: src": `select` calls `onSelect` at once, like the other widgets, and here `onSelect` had been set first.

### Loading children on demand

A tree of a whole disk cannot be built before the window opens. Set `node->lazy = true` on a folder that has no children yet: it gets the open arrow anyway. When the node is opened, the tree calls `tree->onExpand` (`int f(int tree)`), and `tree->expandedNode` is the node:
add its children there. `onExpand` runs **every time** the node is opened (also after a close and an open), not only the first time, so check `node->count == 0` before you add children again. `lazy` stays on: a lazy node always shows its arrow, even when it ended up with no children.
No sample shows this; it was checked with a small test program in which a lazy node got "child A" and "child B" in `onExpand`, a second open called `onExpand` again (with `count` already 2), and Right on an empty lazy node opened it and left the arrow in place.

`examples/gui/afiles.a` is a file browser made of a tree of folders, a table of files and a splitter.

## Toolbars, icons and the status bar

A `guix.Toolbar` is a row of flat icon buttons. `addButton(icon, "Tip", f)` returns the `guix.IconButton`; the text is its tool tip, and `f` is a function `int f(int button)`. `addSeparator()` adds a gap. An icon button can be a toggle: `toggle = true` and `checked`.
A `guix.StatusBar` has up to eight sections: `addSection(width)` returns its number (a width of 0 stretches over what is left; several such sections share it) and `setText(section, text)` sets the text.

{{sample gui/toolbar_status src}}

{{shot gui/toolbar_status}}

**What to notice**

* The click on the Save icon calls `tool`, and the status bar shows its tip, "Save". The star is a toggle that starts pressed.
* A section is exactly `width` pixels wide and cuts its text: the second section is 90 pixels so that "Ln 1, Col 1" fits.
* The status bar paints a fixed light grey and ignores the colour variables of the section "Colours and icons of your own program" below; the toolbar has its own `background` field.

There are 31 icons, numbered from `guix.ICON_NEW` (1) to `guix.ICON_PANEL` (31). `guix.drawIcon(surface, icon, x, y, colour)` draws one, 16 x 16 pixels with its top left corner at `x, y`, on **any** surface in any colour, so it works outside toolbars too; the sample draws them without a window,
and the output shows three of the numbers: `ICON_NEW` is 1, `ICON_SETTINGS` is 20 and `ICON_PANEL` is 31. The picture names all of them.

{{sample gui/icons}}

{{shot gui/icons}}

## Text blocks and calendars

A `guix.TextBlock(text)` is text that **wraps** at the width of the widget: `\n` starts a paragraph, `align` (0 left, 1 centre, 2 right), `color`, `font`, and `wrapWidth` (when above 0, the lines wrap at that width instead of at the width of the widget).
`setText` changes the text. A `gui.Label` is always one line. In the picture the long paragraph wraps into four lines, the second paragraph starts on its own line, and the last block is centred and grey.

{{sample gui/text_block src}}

{{shot gui/text_block}}

A `guix.Calendar` shows a month, with the week starting on Monday: `year`, `month`, `day` (the chosen date; it starts as today), `setDate(y, m, d)`, `packed()` (`year * 10000 + month * 100 + day`) and `onChange`.
Click a day (also one of the grey days of the next or the previous month) or use the keys to choose a date: Left and Right move by a day, Up and Down by a week, PageUp and PageDown by a month. Each of these calls `onChange`.
The two arrows in the header and the mouse wheel only turn the page to another month: they change nothing that you can read from `year`, `month` and `day`, and they do not call `onChange`. `setDate` does not call it either.
The picture shows the date after a click on the 21st of March 2025 (the sample started on the 14th).

{{sample gui/calendar src}}

{{shot gui/calendar}}

## Dialogs

A dialog opens a window of its own, and when the user is done it calls **your** function with the result and closes the window. The call returns at once; the answer arrives later, in the event loop.
The dialogs are not modal: the user can still click in the other windows of your program while one is open.

| Function | The callback `int f(int result)` receives |
|---|---|
| `guix.confirm(d, title, text, f)` | 1 for Yes, 0 for No or a closed window |
| `guix.prompt(d, title, label, initial, f)` | the text as a `char*` (cast to `int`), 0 when cancelled or closed |
| `guix.openFile(d, title, startDir, f)` | the chosen path as a `char*`, 0 when cancelled or closed; only a file that exists is accepted |
| `guix.saveFile(d, title, startDir, name, f)` | the path as a `char*`; the dialog asks before it replaces a file that exists |
| `guix.chooseColor(d, title, 0xFFRRGGBB, f)` | the colour as `0xFFRRGGBB`, 0 when cancelled |
| `guix.chooseDate(d, title, year, month, day, f)` | `year * 10000 + month * 100 + day`, 0 when cancelled |

Each of `confirm`, `prompt`, `openFile` and `saveFile` has an `...Arg` version (`confirmArg`, `promptArg`, `openFileArg`, `saveFileArg`) that takes **one more `int` as its last argument**; your function reads it from `guix.dialogArg`, which is handy when several dialogs share one callback.
For example, `guix.confirmArg(d, "Delete", "Sure?", answered, 42)` calls `answered(1)` with `guix.dialogArg` equal to 42 when the user presses Yes. `dialogArg` is only meaningful inside the callback; it is 0 for the plain versions.
`chooseColor` and `chooseDate` have no `...Arg` version, so do not read `dialogArg` in their callbacks. No sample shows the `...Arg` functions; they were tried with a small test program (a Yes, a No and a text answer each arrived with the number that had been passed in).
All dialogs return the window they opened.

{{sample gui/dialog_confirm src}}

{{shot gui/dialog_confirm}}

{{sample gui/dialog_prompt src}}

{{shot gui/dialog_prompt}}

**What to notice**

* In the pictures of the confirm and the prompt dialogs the main window has a grey title bar: it has lost the focus to the dialog. Both windows go on working; it is not a modal dialog box in the sense of other toolkits.
* A cancelled prompt gives 0, which is why `answered` tests `text == 0` before it casts the number back to a string. Enter in the field has the same effect as the OK button.
* `initial` is the text the field starts with ("Ada" in the picture).

The file dialogs list a directory: `..` first (it goes up), then the folders (shown with a `/` after the name; a double click enters one), then the files, each group sorted without regard to case. A check box shows hidden files (names that start with a dot), and a text field holds the name.
A single click on a file puts its name into the field, a double click on a file accepts it, and so do the Open or Save button and Enter. The open dialog refuses a name that does not exist ("That file does not exist"). The sample makes a few files first so that there is something to see;
the list in the picture also holds the sample's own source file, because the program ran in a copy of its directory.

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
