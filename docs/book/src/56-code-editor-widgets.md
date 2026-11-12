# The code editor widgets and the libraries behind AIDE

AIDE, the integrated development environment of A, is built from libraries that you can use too. Underneath is an **engine** with no user interface: a system layer, a text buffer with undo, a syntax
highlighter, themes, project files, searching and build jobs. On top of it sit the **widgets** of `gcode`: a code editor, tabs, a file explorer, find bars, an output panel, a terminal panel, a command
palette and dialogs. The last section of this chapter assembles them into a small IDE and shows how the real `aide` and `aide-gui` are put together.

In this chapter:

* the layers, and what each module is for;
* the engine: `asys`, `acode`, `asyntax`, `atheme`, `aproject`, `afind` and `aidecore`, each with a program you can run;
* the widgets of `gcode` and its eight parts, each shown in a picture;
* **building your own IDE** from these parts.

The widgets use windows, boxes and menus from [GUI basics](#chap-gui-basics) and [more widgets](#chap-gui-more-widgets). Pictures here are taken the way [the display server chapter](#chap-display-server)
describes: a server and a client in one program. The documents behind this chapter are [the GUI reference](#chap-gui-reference) (the code editor widgets) and [the AIDE notes](#chap-aide) (the engine).

## The layers

```text
   aide (terminal)            aide-gui (GUI)               front ends: they draw and read the keyboard
        |                          |
        |                    gcode widgets  <-- Look (theme, font, preferences)
        |                          |
        +---- aidecore: project file, build plans, snippets, templates, recovery, session
        |
   atheme  asyntax  afind  aproject  acode  ----  regex
                         |
                       asys: memory, files, processes
```

| Module | What it is for |
|---|---|
| `asys` | memory that can be freed, files, atomic writes, directories, time, child processes with pipes; works on Linux and on AOS |
| `acode` | `Buffer` (the text, lines, undo, files) and `Editor` (cursors and every editing command) |
| `asyntax` | lexers for 12 languages and plain text, the `Highlighter`, symbols and completion |
| `atheme` | themes (checked for contrast), colour helpers and the user's settings |
| `aproject` | ignore rules, the file tree, find in files, quick open, jobs and build diagnostics |
| `afind` | search and replace in a buffer, including regular expressions |
| `aidecore` | what an IDE needs besides these: `.aide` project file, build plans, snippets, templates, recovery copies, sessions |
| `gcode` (and `gcode_core`, `gcode_doc`, `gcode_editor`, `gcode_bars`, `gcode_panes`, `gcode_dock`, `gcode_dialogs`, `gcode_ide`) | the widgets |

The engine contains **no user interface**. A front end draws a line with `buffer.linePtr(i, &len)` (a pointer into the text, no copy) and `highlighter.tokens(i, ...)`, and learns about edits through a
change listener, so it only redraws what changed. Long running things (search, jobs, the file watcher) never block: the front end polls them from its own loop.

::: note

Objects with a constructor are declared with parentheses (`acode.Buffer b();`) or made with `new`. A plain `acode.Buffer b;` is only zeroed. Strings that the libraries return are `asys` memory:
free them with `asys.free`. Errors are `-errno` numbers (`-asys.ENOENT`); `asys.errText(code)` turns one into words.

:::

## asys: the system layer

`asys` is deliberately small: only system calls that Linux and AOS both have. Functions return a value of 0 or more, or `-ERRNO`; functions that return pointers return `null` and may store the error through an `int*`.

{{sample gcode/asys_files}}

**What to notice**

* `writeFileAtomic` writes a temporary file next to the target, flushes it and renames it over the target, so a crash never leaves a half written file. The permissions of an existing file are kept, a symbolic link is
  resolved, and `W_BACKUP` keeps the old content as `NAME~`. `writeFile` is the plain overwrite.
* `readFile(path, &length, limit, &error)` reads **regular files only**: a directory or a FIFO is refused at once with "not a regular file" and never blocks. A size limit gives "file too large".
* `listDir` reads names and kinds with `getdents64`, without a `stat` per entry; `sort(dirsFirst, ignoreCase)` orders them. `mkdirs` is `mkdir -p`; `validName` refuses `""`, `.`, `..`, names with `/` or control characters, and names
  longer than `nameMax()` (255 bytes; 55 on AOS).
* Memory from `asys.alloc` is zeroed and counted (`memInUse()`), so a test can compare it before and after a cycle and find a leak.

Processes use the same conventions:

{{sample gcode/asys_process}}

**What to notice**

* `asys.Process p();` is declared with parentheses. `start(argv, cwd, env, flags)` forks, sets up the pipes (all close-on-exec, parent ends non-blocking), searches `PATH` itself and reports a failing `exec` **at once** (`no such file or directory`),
  not later.
* `read(1, ...)` is standard output, `read(2, ...)` standard error; a result of 0 means closed, less than 0 means nothing yet. `P_MERGE` puts both in one pipe. The extra environment replaces entries of the same name.
* `waitReadable(ms)` is the wait; there is no blocking call anywhere. The parent ignores `SIGPIPE`, so writing to a closed pipe is an error and not a death. `P_GROUP` makes the child a process group leader, and `signalGroup` reaches its children.
* On Windows memory, files, directories and time work; processes return `-ENOSYS` (`canSpawn()` says so).

## acode: buffer and editor

The text of a document is a **gap buffer** (UTF-8 bytes, `\n` between lines) with a line index that is a second gap array. Edits near the previous edit cost almost nothing: 100,000 lines appended one at a time take about 50 ms,
and a 120 MB file loads in under a second. An edit far from the last one costs the move of the gaps (about 6 ms in a 120 MB file).

{{sample gcode/buffer}}

**What to notice**

* A text that ends with a newline has one more, empty, line: `"alpha\nbeta\ngamma\n"` is 4 lines. Positions are **byte offsets**; `lineStart(i)`, `lineEnd(i)`, `lineAt(offset)` convert, and `visualCol` / `offsetAtCol` handle tabs, wide characters and combining marks.
* `linePtr(i, &len)` returns a pointer into the text without a copy (valid until the next edit), which is how a front end draws a line.
* Every change goes through `edit(offset, deleteLength, text, length)`, and every change calls the listeners (`addListener`), also undo, redo and loading. The listener gets a `Change` with offset, sizes, the first line and the number of lines affected.
* `modified()` compares state numbers, not a flag: after two undos the buffer is back at the saved state and no longer modified, and it stays correct after new edits on a branch.
* `load` detects LF, CRLF and CR line ends, a byte order mark and binary files (kept byte for byte), reads straight into the buffer storage and checks `fstat`; `save` writes through `AtomicFile` and keeps the
  detected style. `checkExternal()` notices that someone else changed the file.

An `Editor` adds cursors and every command an editor has. Every command is **one undo step**, and undo restores the cursors exactly.

{{sample gcode/editor}}

**What to notice**

* `newline` copies the indentation and opens a level after `{`, `(` or `[`. `toggleLineComment` comments at the shallowest indentation and uncomments exactly; `setLanguage("a")` tells it the comment syntax.
* An editor has **any number of cursors**: `addCursor(anchor, position)` made three, one typed string went into all of them, and one `undo` took all three back. Commands work on the cursors from the last to the first so that offsets stay valid.
* The commands are the ones the keys of an editor map to: `moveWordLeft`, `selectLine`, `moveLines`, `duplicateLines`, `joinLines`, `deleteLines`, `changeCase`, `indentLines`, clipboard `copy` / `cut` / `paste` with a ring, `matchBracket`, `selectEnclosingBrackets`, `addNextOccurrence`.
* Several editors on one buffer stay consistent: each listens to the buffer and moves its cursors through every change.

## asyntax: highlighting, symbols, completion

Lexers are **line based** with a small integer state per line. `lexLine(language, state, text, length, out, max, &endState)` is a pure function: it gives spans (start, length, kind) that cover the line without gaps,
and the state the next line starts in.

{{sample gcode/syntax_tokens}}

**What to notice**

* The kinds are the fixed enum `Tok`: `Plain Keyword Type Builtin Constant Number String Char Escape Comment DocComment Preproc Operator Punct Function Variable Tag Attribute Heading Emphasis Link Code Quote Error`. A theme gives each one a colour and a style.
* The block comment changed the state to 1 on its first line, and the state was still 1 on the second, so `int x;` there is a comment; the third line closes it and the rest is code again.
* The languages are A, C, C++, Python, shell, JSON, Markdown, INI, TOML, HTML, XML and Makefiles. `detectLanguage(fileName, firstLine)` uses the extension, special names (`Makefile`, `.bashrc`) and `#!` lines.
* A `Highlighter` listens to a buffer and keeps the state at the start of every line. After an edit it lexes again from the changed line until the state at a line start equals the one it had, so typing in a line of code costs one line, and opening a
  block comment re-lexes down to the closing `*/`.

Symbols and completion come from the same token stream:

{{sample gcode/symbols}}

**What to notice**

* `symbols(buffer, language, &list)` finds modules, constants, classes (with their methods: `Circle.area`), structs, enums, typedefs and functions of A and C, classes and functions of Python, headings of Markdown, functions of shell scripts and
  targets of Makefiles. A string or a comment never produces a symbol: `hidden` in the last line is ignored. It is heuristic (token patterns, no parser).
* `Completer` offers the keywords and builtins of the language, the symbols and the words of the registered buffers, matched by prefix; exact-case matches come first, then symbols, keywords and words, shorter names first.
  The work is linear in the number of words that start with the prefix, so a big file does not make a key press slow.
* `Candidate.kind` is 0 for a symbol, 1 for a keyword and 2 for a word.

## atheme: themes and settings

A `Theme` has 24 named colours (`Col`: `Background`, `Foreground`, `LineNumber`, `Selection`, `StatusBar`, `Border`, `Error`, `FindMatch` ...) and a colour and style (bold, italic, underline) for each of the 24 token kinds.
Nine are built in: `dark light solarized-dark solarized-light monokai high-contrast gruvbox nord aos`.

{{sample gcode/theme}}

**What to notice**

* A theme file is INI with `[theme]`, `[colors]` and `[tokens]`. It only names what it changes; the rest comes from `base`. Unknown keys and bad colours give warnings and leave the base value; random bytes or a file over 1 MB give the base theme and warnings, never a crash.
* `validate` warns about unreadable contrast: text against its background must reach 4.5:1 (WCAG AA), line numbers, the cursor and syntax colours 3:1. `contrast(a, b)` is the ratio times 100 (13.17:1 is 1317), computed from a linearisation table.
* The colour helpers: `rgb`, `parseColor` (`#fa0`, `#ffaa00`, `ffaa00`, `0xffaa00` or a name), `formatColor`, `mix`, `lighten`, `darken`, `to256` / `from256`, `to16` / `from16`, `luminance`, `readable`.

The user's settings are a small INI file:

{{sample gcode/settings}}

**What to notice**

* The file lives in `$AIDE_HOME` or `~/.aide` (`configDir()`); `save` makes the folder and writes atomically. Themes of the user are `NAME.ini` files in `themes/` next to it.
* Recent files and projects are kept most recent first (30 of each), without duplicates. Key bindings are `action = keys` lines.
* Values are **checked and clamped** (`tabWidth = 5000` became 16), lines that mean nothing are counted in `unknown`, and a missing file leaves the settings as they were.

## aproject: files, search and jobs

An IDE works on a folder. `aproject` has the pieces: ignore rules, a lazy file tree, a watcher, find in files, quick open and jobs.

{{sample gcode/project_tree}}

**What to notice**

* `Ignore` knows `.gitignore` rules (`*`, `?`, `[a-z]`, `**`, `!`, a leading `/`, a trailing `/`) and a built-in list (`.git`, `node_modules`, `__pycache__`, `*.o`, `*.so`, `*~` ...). `.a` files are not ignored, neither is `.gitignore`.
* `FileTree` is **lazy**: a folder is read when you open it (`load(node)`), sorted with folders first, and symbolic links are not followed unless asked for (a link to an ancestor is marked as a loop and not entered). Bounds stop runaway trees: 200,000 entries and depth 64.
* `globMatch` is an automaton over the text: time proportional to pattern times text, no recursion, so a hostile `.gitignore` line such as `*a*a*a*a*a*a*b` cannot freeze the tree. `*` stays inside a name, `**` crosses folders.
* `Watcher` polls (no inotify), so it is only as fast as the caller's loop and costs one `stat` per watched entry.

Search:

{{sample gcode/project_find}}

**What to notice**

* `FindJob.start(root, text, flags, ignore, contextLines)` returns at once; `step(budgetMs)` does at most that much work, so a front end keeps drawing. Flags: `FIND_REGEX`, `FIND_ICASE`, `FIND_WORD`, `FIND_FOLLOW`; `fileFilter` is a glob.
* Only regular files are opened (a FIFO is skipped), binary files and files over `maxFileSize` (5 MiB) are skipped, results are capped (10,000). A regular expression that hits its step limit sets `exceeded`, so incomplete results are known to be incomplete.
* Lines count from 0 and columns are byte offsets in the results, so the sample adds 1 for display.
* `QuickOpen` is the Ctrl+P search: the characters of the query must appear in the path in order; consecutive characters, component and word starts and file name hits score higher, and ties go to the shorter path.

Jobs run commands without blocking:

{{sample gcode/build_job}}

**What to notice**

* `Job` collects output into a queue capped at 4 MB (the pipe is always emptied, so a program that floods its output never stalls), has a `timeoutMs` (SIGTERM to the process group, SIGKILL after `graceMs`), `kill()` and `sendInput`.
* `BuildJob` turns lines into `Problem`s: the A compiler and GCC / Clang (`file:line[:col]: error: message`), `In file included from`, Visual C (`file(line): error C1234`), Rust (`error[E..]` plus `--> file:line:col`) and Python tracebacks. ANSI colours and Windows drive letters are handled.
  A column of 0 means the tool did not say.
* A real build is `startCompiler(source, output, target)`: it finds `ac` in `$AC`, `PATH` and the usual places and returns `-ENOENT` when there is none. This sample uses a shell script as the "compiler" so that it needs no compiler installed.
* Processes need `fork`: not on Windows.

## afind: search and replace in a buffer

{{sample gcode/find_replace}}

**What to notice**

* `setPattern(pattern, options)` with `OPT_REGEX`, `OPT_ICASE`, `OPT_WORD` (for a regular expression `\b` is put around it) and `OPT_NOWRAP`. A pattern that does not compile gives `ok == false` and a message (`missing )`) with the position.
* `findNext(offset)` finds the first match at or after the offset and wraps around unless `OPT_NOWRAP` is set; `curStart` and `curEnd` are the match. `count` and `matches` do not disturb the current match.
* Replacement templates in a regular expression use `$0` to `$9`, `${n}`, `$$` and `\n \t \\`; a plain replacement is used as it is. The groups always belong to the match that is replaced.
* `replaceAll` is **one undo step**. Empty matches are handled like Python's `re.sub`.
* The regular expression engine (`regex`) is a backtracking matcher with Perl / Python semantics, groups, named groups, back references, look-ahead, lazy quantifiers and flags. It uses an explicit stack, so `.*Z` over a million characters works, and
  it stops after 5 million steps (`exceeded`), so `(a+)+b` cannot hang an editor. There is no look-behind.

## aidecore: the logic of a front end

`aidecore` is what an IDE front end needs besides the editor libraries, with no user interface, so the GUI and the terminal front ends can share it.

{{sample gcode/aidecore_project}}

**What to notice**

* `newProject(template, folder, name, &mainPath)` makes `main.a`, `README.md` and the project file `.aide` from a template (`TPL_HELLO`, `TPL_CONSOLE`, `TPL_GUI`, `TPL_SERVER`).
* The file `.aide` is shared with the terminal AIDE: a `[project]` section (name, main, build, run, ignore, flags, output, target, version) and any number of `[run NAME]` sections (program, arguments, working folder, environment). `save` **keeps every section it does not know**,
  so a file written by a newer AIDE loses nothing, and line breaks in values become blanks, so a value cannot add entries.
* `makeBuildPlan` makes the command line: `$ ac main.a -r debug -v 3 -DTRACE`. `-r` is the kind of build (`debug` or `release`), `-v` the version number, and the project's flags are split like a shell would and none is dropped. The program is called `NAME-VERSION-RELEASE.elf` (`main-3-debug.elf`).
* `Words` splits a command line the way a shell would (quotes group, no escapes, any number of words); `shellQuote` is the other direction.

Snippets expand to code that fits the line:

{{sample gcode/snippets}}

**What to notice**

* The built-in snippets (`main`, `for`, `class`, `println`, `guimain` ...) plus the user's `snippets.ini`. `expandWord` replaces the word before the caret (Tab does this in an editor); the caret goes where `$0` was.
* The expansion keeps the indentation of the line and uses the document's indent unit; the output is sized exactly, so any depth works, and a snippet that would grow beyond 8 MB is refused.
* `Recovery` (copies of unsaved documents in `CONFIG/recovery`, found again after a crash) and `Session` (the open files and carets of a project) are in this module too; they were not run for this chapter.

## The widgets of gcode

`import gcode;` brings all the parts of the widget library. They share one `Look`: a theme, a font and the preferences (`tabWidth`, `insertSpaces`, `lineNumbers`, `wordWrap`, `autoIndent`, `showWhitespace`, `indentGuides` ...). Every widget registers with it,
so `gcode.theLook()->setThemeName("monokai")` repaints all of them at once.

| Part | What is in it |
|---|---|
| `gcode_core` | `Look`, `LineEdit` (a text box in the theme's colours), key name helpers |
| `gcode_doc` | `Doc`: a buffer, its editor, highlighter, language, markers and bookmarks (one per tab) |
| `gcode_editor` | `CodeEditor` |
| `gcode_bars` | `TabBar`, `FindBar`, `GotoBar`, `StatusBar`, `EditorStatus`, `Outline`, and the themed building blocks `FlatButton`, `BarBox`, `BarLabel`, `RowList` |
| `gcode_panes` | `FileTree`, `OutputPane` (output and problems), `TerminalPane` |
| `gcode_dock` | `Dock`, `PanelTabs`, `Commands`, `Palette` |
| `gcode_dialogs` | `ColorPicker`, `ThemeEditor`, `SettingsDialog` |
| `gcode_ide` | `SearchPane`, `RunPane`, `DocView` |

### The editor

A `CodeEditor` is a `gui.Widget` that draws a gutter with line numbers, bookmark and error markers, syntax colours from the theme, a caret, selections, the current line, other uses of the word at the caret, the matching bracket, find matches, squiggles under
markers, indentation guides and white space marks. **Only the visible lines are drawn and lexed**, and an edit repaints only the rows that changed, so a file of 100,000 lines scrolls and takes input like a small one.

{{sample gcode/editor_view}}

{{shot gcode/editor_view}}

**What to notice**

* A `CodeEditor` has a `Doc` of its own; `setDoc(doc)` shows another one and keeps the scroll position in the old one. `open(path)` reads a file and detects the language and the indentation. Documents are what tabs hold.
* `addMark(line, column, length, severity, text)` draws a marker in the gutter and a squiggle: the red dot and the wavy line under `totl`, the yellow dot and the squiggle under `total`. `markMessage(line, column)` gives the text for a tool tip. Markers and bookmarks follow
  their lines when text is inserted or deleted above them.
* The selection runs over the loop (lines 4 to 6): `select(anchor, position)` takes byte offsets, `gotoLine(line, column)` counts from 0.
* The editor draws on a grid of cells (the width of the widest glyph of the font); wide characters take two cells and combining marks none. Characters above Latin-1 show as `?` because the font has only Latin-1. Bold is drawn by striking the text twice; italic is not drawn.
* The keys are the ones of a code editor: Shift extends, Ctrl moves by word, Tab and Shift+Tab indent selected lines, Ctrl+Z / Y undo and redo, Ctrl+D adds the next occurrence, Alt+Up / Down moves lines, Ctrl+Alt+Up / Down adds a cursor, Ctrl+Space completes, Ctrl+/ comments, F2 jumps between bookmarks.
  Keys the editor does not use (Ctrl+S, Ctrl+F ...) go on to the window: see `Commands` below.

Themes change the look of every widget that uses the same `Look`, or of one editor if you give it a `Look` of its own:

{{sample gcode/editor_themes}}

{{shot gcode/editor_themes}}

**What to notice**

* `setLook(look)` replaces the shared `theLook()` for this editor, which is how a preview or a split of different themes works. `look->setFontIndex(gcode.FONT_SANS)` or `setFontFile(path)` changes the font; `setLineGap(n)` the line spacing.
* The built-in fonts are 13 pixel DejaVu; a font file is loaded with `gfx.loadFont` and refused when it cannot be used (missing, damaged, or without a line height).
* A theme change repaints every registered widget at once; `look->changed()` tells editors to copy the preferences after you changed them.

### Tabs, find bar, outline and status bar

{{sample gcode/editor_panels}}

{{shot gcode/editor_panels}}

**What to notice**

* `TabBar.addTab(title, userData)`: the user data is the `Doc`. Tabs have a modified dot (`setModified`), close buttons (`onClose` can veto), middle click closes, tabs can be dragged to reorder, and an overflow gets arrows and a list.
* `FindBar` is built on `afind`: incremental, Enter and Shift+Enter, "3 of 12", toggles for case, whole word and regular expression, Replace and Replace All (one undo step). It **follows the document the editor shows**: after a tab switch the count and Replace work on the new
  text at once. The matches are highlighted in the editor; `GotoBar` understands `12`, `12:5`, `+10` and `-3`.
* `Outline` lists the symbols of the document (`asyntax.symbols`) with kind badges and a filter, follows the caret and refreshes after edits (up to 2 s later for documents over 500 KB). The sample shows two symbols: the two functions.
* `EditorStatus` is a `StatusBar` that knows the editor: position, selection or cursor count, tabs or spaces (a click toggles), encoding, line ends (a click cycles) and language. The editor tells the others through `editor->observe(f, user)` with the events
  `EV_CHANGE`, `EV_CURSOR`, `EV_SCROLL` and `EV_DOC`; that is how these widgets follow it without the editor knowing them.

### Explorer and output

{{sample gcode/tree_output}}

{{shot gcode/tree_output}}

**What to notice**

* `FileTree.setRoot(folder)` opens a project on `aproject.FileTree` with `.gitignore` rules (the `docs/` folder is hidden). Folders open lazily, files have icons by type, and there is a keyboard interface: type-ahead (letters typed within one second form a name prefix), F2 renames, Delete asks before deleting (non-empty folders are refused),
  F5 refreshes. `revealRel("src/lib/money.a")` opens the folders above a file and selects it. The disk is polled every 1.5 s (`pollNow()` by hand).
* `OutputPane.attachBuild(job)` follows a running `BuildJob` from a timer, with ANSI colours (16, 256 and 24 bit), carriage returns and a line limit. The **Problems** tab lists what the job found; a click or Enter on a problem calls `onJump(pane)` with `jumpPath`, `jumpLine` and `jumpCol`
  (1 based), which is what an IDE uses to open the file at that line.
* `TerminalPane` is a `gterm.Terminal` in the colours of the theme:

{{sample gcode/terminal_pane}}

{{shot gcode/terminal_pane}}

**What to notice**

* `start(display, command)`, `feed`, `send`, `stop`, `onExit`. The process is collected when the panel ends (SIGHUP, 300 ms to leave, then SIGKILL), so there are no zombies. Linux and Android only.
* The colours of the panel are those of the `nord` theme the sample set on the shared `Look`.

### Commands and the palette

Keys that belong to the whole window are **commands** in a registry. `install(window)` puts the registry in front of the focused widget, so Ctrl+S reaches it before the editor sees the key (a menu bar keeps working behind it).

{{sample gcode/palette}}

{{shot gcode/palette}}

**What to notice**

* `add(id, title, keys, function, userData)`. Keys are written like `ctrl+shift+p` or `f5`. `setKeys` refuses a key that another command has (the sample's attempt to give `file.save` the key `f5` returned 0), and `applySettings` / `storeSettings` read and write the `[keys]` section of the user's settings.
* `Palette` is an overlay with fuzzy matching: `showCommands(window, commands)`, `showFiles(window, quickOpen)` for Ctrl+P, or your own list with `addItem(label, detail, userData)` and `show`. Typing `wra` left one command; Enter ran it.
* The palette closes itself and gives the focus back to the widget that had it.

`Dock` is the layout of an IDE: a sidebar, the centre, and a bottom panel with dividers you drag. It keeps minimum sizes (a panel that would leave the centre too small is left out until the window is big enough), remembers what the user chose (`sideW`, `bottomH`) and has
`showSidebar`, `showBottom` and `onLayout`. `PanelTabs` is tabs over pages, used for "Files | Outline" and "Output | Terminal".

### Dialogs

{{sample gcode/color_picker}}

{{shot gcode/color_picker}}

**What to notice**

* `ColorPicker` has a hue bar, a saturation / value square, R G B H S V sliders, a hex field (`#rrggbb`, `0x...` or names), swatches and an old / new preview. `gcode.pickColor(display, title, rgb, callback)` is the dialog; the callback gets `0xFFRRGGBB`, or 0 when cancelled, and Enter presses OK.
* The window is `F_FIXED` and sizes itself with `fit()`. In this version the preview swatch and the hex field at the top right run up to the right edge of the window, without the margin the left side has (noted in the notes file of this chapter).

The theme editor edits a whole theme while you watch:

{{sample gcode/theme_editor}}

{{shot gcode/theme_editor}}

**What to notice**

* The list shows every theme colour (entries 0 to 23) and syntax style (24 to 47) with a swatch; the picker edits the chosen one, and a live preview editor shows the result. With "Apply to all editors while editing" (`live`) the changes reach every editor at once.
* `setEntry(index, rgb, style)` is what the picker calls. The contrast checker (`Theme.validate`) explains what is wrong: the comment colour `#303030` on the dark background is 1.26:1 (minimum 3:1), so the list at the bottom has one warning.
* It loads, saves, duplicates and deletes user themes (built-in ones are protected), reverts, and its window can be opened again and again: the preview editor, document and Looks are freed when it closes. `SettingsDialog` does the same for the preferences:
  tab width, spaces or tabs, line numbers, wrap, trailing white space, guides, highlights, font, theme, line spacing, every control applying at once to the Look and the open documents.

### Search, run and documentation

{{sample gcode/ide_panes}}

{{shot gcode/ide_panes}}

**What to notice**

* `SearchPane` is find in files on `aproject.FindJob`: a query field, toggles, a file name pattern, Search and Stop. The results are lines `path:line:col: text` and one click calls `onJump(pane)`. The search runs in steps from a timer; `step()` does it by hand, as the sample does.
* `RunPane.start(job, name)` follows a started `aproject.Job` and has an input line: Enter sends a line to the program's standard input and shows it, Ctrl+D ends the input, Ctrl+C in the empty line stops the program. The picture was taken while the program waits for its name; when it
  ends, the pane shows the exit code and the run time (which is why the sample takes the picture before that: the time would change the picture).
* `DocView` is a list of pages and a `ghtml.HtmlView`: `openDocs()` lists the Markdown files of the documentation folder (`$AIDE_DOCS`, `/usr/share/a/docs`, `/usr/local/share/a/docs`, `./docs`), with links between pages, anchors and `back()`.
  `onOpenFile` is called for a link to a source file.

## Building your own IDE

An IDE is these parts, wired together in a small number of ways. The program below is a complete little IDE of about 100 lines. It is a real GUI program (`import gui;`, `gui.connect(null)`, `d->run()`); the book photographed it with
the screenshot tool against a headless display server, after pressing Ctrl+F and typing `total`.

{{sample gcode/mini_ide}}

{{shot gcode/mini_ide}}

**What to notice**

* **One `Doc` per open file.** The tab bar holds the `Doc*` as the user data of each tab, and the editor shows the selected one with `setDoc`. `openFile` first looks for an existing tab with that path, so opening a file twice shows the same tab.
* **The editor tells the others.** `EditorStatus`, `Outline` and `FindBar` are given the editor when they are made and follow it through `observe`; the program never copies state between them. The modified dot of the tab is updated from `editor->onChange`.
* **Files open from the explorer.** `FileTree.onOpen` has `openedPath`. A click on a problem does the reverse: `OutputPane.onJump` opens `jumpPath` and calls `gotoLine`.
* **A build is a `BuildJob` that the `OutputPane` follows.** `startCompiler` returns `-ENOENT` when `ac` is not found; the sample prints that instead of crashing. This is the one part of the program the picture does not show: no compiler is installed where the picture is taken.
* **Layout is a `Dock`** with a sidebar of two pages (`PanelTabs`), the centre (tabs, editor, find bar) and the bottom panel. The menu bar and the status bar are above and below it.
* A global variable named `find` would clash with a function of the standard library (`std` has a `find(char*, char*)`), which is why the find bar is called `findBar`.

### What codedemo adds

`examples/gui/codedemo.a` (662 lines; compiled for this chapter, and driven like a user by the toolkit's test `t257`) is the same program done thoroughly, and the base of the real AIDE GUI. On top of the little IDE it has:

1. **Commands, menus and the palette from one table.** `addCommands()` registers every action once (`file.save`, `edit.find`, `view.sidebar`, `run.build` ...) with its keys; the menu items are made from the registry (`item(menu, text, id)` reads the accelerator text from the command), and the palette lists the same commands. `commands->install(win)` makes the keys work everywhere.
2. **Settings and themes.** `look->applySettings(settings)` at start, the `SettingsDialog` and the `ThemeEditor` change the `Look` live, and `look->storeSettings` plus `Settings.save` run at exit. The user's keys come from the `[keys]` section.
3. **More panels.** A go to line bar, quick open (`Palette.showFiles` on an `aproject.QuickOpen` index), go to symbol, a terminal tab, and the bottom panel as `PanelTabs`.
4. **Build and run.** F7 builds the current file with the A compiler through a `BuildJob`; when it ends the problems become markers in the open documents (`doc->addMark`); F5 builds and runs the program in the terminal.
5. **Closing with a question.** A window `onClose` that asks about unsaved documents (a dialog), and `Doc.isModified()` for the tabs.

### aide and aide-gui

The two front ends of AIDE are in the AOS repository, not in this one, so what follows comes from `docs/AIDE.md` and was **not** run or read for this book:

* **`aide-gui`** (`user/gui/aide-gui.a`) is the codedemo idea carried further: a window with menus, a tool bar, two editor panes, a real terminal, run, problems and search panels (`RunPane`, `SearchPane`), themes that reach the menus and dialogs, project templates and run configurations
  (`aidecore`), the documentation (`DocView`), recovery of unsaved work and a session that reopens the files. It adds `gfx.scaleFont`, `setFontScales` and `setUiFont` (interface fonts at other sizes) and colour globals for a dark look of menus, tables and tool tips (`guix.cPanel`, `gui.cTipBack` ...).
* **`aide`** (`user/aide.a`, about 6000 lines in one file) is the terminal front end. It draws a cell grid from the same data (`linePtr`, `tokens`, `charWidth`, `visualCol`), uses the terminal toolkit of [the previous chapter](#chap-terminal-ui) for menus and dialogs, and runs on Linux terminals and on
  the AOS terminals (serial console, `aterm`, `telnetd`). It uses `asys`, `acode`, `asyntax`, `atheme`, `aproject` and `afind`.
* Both share `aidecore`: the same `.aide` project file, the same recovery records and the same session file format. The engine has no user interface code, so everything that draws or reads the keyboard is the front end's job.

A front end, in short, does the same steps whatever it draws on: make a `Buffer`, an `Editor` and a `Highlighter` per document; draw the visible lines from `linePtr` and `tokens` with the colours of a `Theme`; turn keys into `Editor` commands; redraw when `version` changes or a listener fires;
check `checkExternal()` when the window gets the focus; poll `FindJob`, `Watcher` and `Job` from the idle loop; and save with `saveFile` (trim, final newline, atomic).

## Limits

* No code folding, no minimap, no bidirectional text. Word wrap breaks at a column, not at a word. Two editors on one `Doc` share their cursors.
* The font is the 13 pixel DejaVu (or the configured font file); characters above Latin-1 are drawn as `?`; the menu bar and the standard dialogs of `guix` are not themed; completion offers words, symbols and keywords but has no type information.
* `FileTree` deletes files and empty folders only. The terminal panel needs a pseudo terminal (Linux and Android).
* Random edits far apart in a huge file cost the move of the gap (6 ms per edit in 120 MB); highlighting a line far down a file that was never looked at lexes everything above it once (1.1 s for 2 million lines), so a front end must ask for visible lines only.
* The lexers are line based: nested languages (JavaScript in HTML, code in Markdown fences) show only the container. `regex` has no look-behind.
* `FindJob` and `Watcher` are polled; `Watcher` has no inotify.
* The widgets were exercised through a headless display server in one process with real key presses and mouse clicks, not on a real display or with a real user. The performance numbers in this chapter are from the documentation of the libraries, not measured again here.

## Summary

* The editor is a stack: `asys` (system), `acode` (buffer, editor, undo), `asyntax` (tokens, symbols, completion), `atheme` (themes, settings), `aproject` (tree, search, jobs), `afind` (search and replace), `aidecore` (project file, plans, snippets), then the widgets of `gcode`.
* The engine has no user interface and never blocks: searches and jobs run in steps, polled from the front end's loop.
* Every command of the editor is one undo step; several cursors work as one; a buffer can have several editors that stay consistent.
* All `gcode` widgets take their colours from a `Look`; one theme change repaints them all. The editor tells the other widgets through `observe`.
* `Doc` per tab, `Commands` for window-wide keys, `Palette` for commands and files, `Dock` for the layout, `OutputPane` and `RunPane` for jobs, `FileTree` for the project.
* An IDE is these widgets wired together; `mini_ide` is a hundred lines, `codedemo` a few hundred, and the real front ends add settings, sessions, recovery and polish.

## Where next

* [The GUI reference](#chap-gui-reference) lists every key and callback of the widgets; [the AIDE notes](#chap-aide) describe the engine, the tests and the AOS notes.
* [Terminal programs](#chap-terminal-ui) for the terminal front end's toolkit, and [networking, web pages and terminals in windows](#chap-gui-net-and-web) for `gterm` and `ghtml`, which `TerminalPane` and `DocView` use.
* [System programming](#chap-system-programming) for processes and files in general.
* API references: [asys](#api-asys), [acode](#api-acode), [asyntax](#api-asyntax), [atheme](#api-atheme), [aproject](#api-aproject), [afind](#api-afind), [aidecore](#api-aidecore), [gcode](#api-gcode), [gcode_core](#api-gcode_core), [gcode_doc](#api-gcode_doc),
  [gcode_editor](#api-gcode_editor), [gcode_bars](#api-gcode_bars), [gcode_panes](#api-gcode_panes), [gcode_dock](#api-gcode_dock), [gcode_dialogs](#api-gcode_dialogs), [gcode_ide](#api-gcode_ide).
