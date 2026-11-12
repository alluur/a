# Writing the A book

The book "The A Programming Language" (Aytict) is built from this directory:

```
docs/book/
  chapters.txt          the order of the chapters and parts
  src/NN-slug.md        chapters (Markdown; one `# Title` per file)
  samples/GROUP/NAME.a  verified code samples (+ NAME.out = the recorded output)
  shots/GROUP-NAME.png  screenshots of graphical samples
  brand/                Aytict look: CSS, logo, cover
  tools/                build.py (HTML site + EPUB), samples.py (checker), shots.py (screenshots), api.py (API reference), hl.py
```

Everything printed in the book is either prose, or a listing that **the build takes from a sample file that was compiled and run**.
Code is never pasted into a chapter by hand. That is the rule that keeps the book true.

## 1. Samples

A sample is `samples/GROUP/NAME.a` (one file), or a directory `samples/GROUP/NAME/` with `main.a` and helper modules
(`import helper;` finds `helper.a` next to the importing file). The recorded standard output is `NAME.out` (`main.out` for a directory),
standard input comes from `NAME.in`.

* The **first line** is a comment with the title of the listing in sentence case, no full stop: `// Reading a file line by line`.
  The book shows it as the caption of the listing.
* **One idea per sample**, 10 to 60 lines (module samples up to about 80). Comments in the code say *why*, not *what*.
* The program must **print what it demonstrates**, so that the output block teaches too. Print results, not "done".
* **Deterministic**: no addresses, time of day, pids, host names, user names, random numbers (seed `srand` or use fixed data), sorting by
  pointer, or thread timing in the output. A sample runs in a scratch directory, so it may create and delete files there.
* **No network except loopback**, and then with an ephemeral port: `net.listen(0, ...)` and read the port back (`net.localPort`).
  Never hard code a port. Prefer one process: `thread`, or `net` with non-blocking sockets, or a fork, so the sample is self-contained.
* **Floating point**: `double` (and `float`, its alias) is a real type, implemented in software (module `dfloat`, loaded when a program uses it; `dmath` has `sqrt sin pow log ...`), so results are identical on every target. Read `docs/LANGUAGE.md` section 7 ("static if, :: and floating point") and `tests/t92_double.a`. Print doubles with `printlnDouble` / `doubleToFixed`; the `printfd` family of the C library takes raw bit patterns (`__bits(d)`), not `double` values. Note: `docs/CLIB.md` and `README.md` still claim that A has no `float` / `double`; they are out of date.
* Use only what the **compiler on this branch** does (`build/ac`). If a feature in the docs does not work, do not hide it:
  work around it in the sample and write the problem into `docs/book/NOTES-<yourname>.md` (see section 5).
* Compiles for **every target**: `python3 docs/book/tools/samples.py --targets NAME`. Needs Linux only (fork, signals, `/proc`)?
  Say so with `// book: linux-only`.

Directives (in `//` comments within the first 12 lines):

| Directive | Meaning |
|---|---|
| `// book: compile-only` | built (and checked for every target) but not run: needs a terminal, the network, root, a display ... |
| `// book: gui` | a graphical program: built here, run and photographed by `tools/shots.py` against a headless display server |
| `// book: exit=3` | expected exit code (default 0) |
| `// book: timeout=60` | seconds (default 20) |
| `// book: args=one two` | command line arguments |
| `// book: sorted` | compare the output lines sorted (threads) |
| `// book: linux-only` | `--targets` only builds the Linux targets |

Check your samples (the compiler is `build/ac` in the worktree root; build it with `make`):

```sh
python3 docs/book/tools/samples.py --update GROUP/NAME     # compile, run, record NAME.out the first time
python3 docs/book/tools/samples.py GROUP                   # compare with the recorded output
python3 docs/book/tools/samples.py --targets GROUP         # also compile for all 9 targets
```

**Read every `.out` file after recording it.** `--update` accepts whatever the program printed; you are the one who decides whether
that is correct.

## 2. Chapters

`src/NN-slug.md`: one `# Title` (chapter), then `##` sections, `###` subsections. Markdown is CommonMark with tables, fenced divs
and raw attributes (pandoc `commonmark_x`). Keep a line length of any length; blank line before and after lists, tables and code.

Directives, each alone on a line:

| Directive | Result |
|---|---|
| `{{sample group/name}}` | the source of the sample, then its recorded output |
| `{{sample group/name src}}` | the source only (programs without output, or when the output is shown in your prose) |
| `{{shot group/name}}` | the screenshot `shots/group-name.png` of a graphical sample |

Other conventions:

* Callouts: `::: note`, `::: tip` or `::: warning`, a blank line, the text, a blank line, `:::`.
* Shell sessions: a fenced block with `sh`; the commands you show must be ones you ran. Text output: a fenced block with `text`.
  Code that is **not** a runnable sample (a fragment, a signature, a snippet of a configuration file): a fenced block with `a` (syntax
  highlighted) is fine, but keep fragments small and make sure they are correct; anything with a `main` goes into a sample.
* Cross links: `[API reference of json](#api-json)` links to the generated API reference of a module (every file of `lib/` has one);
  `[the networking chapter](#chap-networking)` links to a chapter (`chap-` + the slug of the file name without its number).
* Name modules, functions and keywords in backticks: `json`, `json.parse()`, `foreach`.

Structure of a chapter (this is for readers who skim, so keep it regular):

1. `# Title`
2. A short intro (2 to 4 sentences: what the chapter is about and why you would want it). A bullet list "In this chapter" is welcome.
3. Sections in the order a reader needs them, small ones: a short explanation (what / why), then the sample, then **what to notice**
   (2 to 4 sentences or bullets on the output, edge cases, pitfalls). Tables for options and comparisons.
4. `## Summary`: 4 to 8 bullets.
5. `## Where next`: links to related chapters / API references.

Tone: friendly, plain English, second person ("you"), short sentences, no jokes at the reader's expense, no filler, no marketing.
Define a term when it first appears. Be exact with numbers and limits and say when something is **not** supported.

## 3. Facts come from the sources, not from memory

* The reference documentation is in `docs/*.md` (`LANGUAGE.md`, `CLIB.md`, `GUI.md`, `TUI.md`, `AIDE.md`, `TLS.md`, `TARGETS.md`,
  `INTERNALS.md`). The truth is the compiler: **run the code** before you describe it.
* For a module read its header comment and its public declarations (`grep -n '^public\|^    public' lib/NAME.a`), and look at how
  `tests/*.a` and `examples/` use it; the tests are verified programs. You do not need to read whole big files.
* If the docs and the compiler disagree, the compiler wins; write the discrepancy into your notes file.

## 4. Ground rules for contributors working in parallel

* Write only your own chapter files and your own `samples/` groups (see your assignment). Do not edit `lib/`, `src/`, `tests/`,
  other people's files, `chapters.txt`, `tools/` (except where your assignment says so), and do not run `git commit`/`push`/`stash`.
* The machine has 4 CPUs shared with other work: run things with `nice`, never start long loops, do not run the big test suites
  (`tests/run.sh`) and do not start QEMU.
* Graphical samples use a headless display server; use high, free ports (see the GUI section in `tools/shots.py`), never 7000-7999 or
  5900-5999.
* Time limit of a sample: it must finish in well under 20 seconds.

## 5. Notes file and final report

Write `docs/book/NOTES-<yourname>.md` with: (a) compiler / library bugs you hit, each with a 5 to 15 line reproduction; (b) places where
the reference docs were wrong or incomplete (file, claim, what really happens); (c) modules or features you could not cover and why.
Your final message to the coordinator lists: chapter files, number of samples per group, modules covered (and which have only a
compile-only sample), and a link to the notes file. Be factual about what you tested and what you did not.

## 6. Graphical samples

A sample that draws or has windows is photographed by `tools/shots.py`; the picture goes to `shots/GROUP-NAME.png` and a chapter shows it
with `{{shot group/name}}` (after the `{{sample group/name}}` that shows the code). Two kinds, chosen by a directive in the first 12 lines:

| Directive | Kind |
|---|---|
| `// book: shot=out.png` | **a drawing program** (no window, no display server): it draws into a `gfx.Surface` and writes the PNG with `gimg.savePng(s, "out.png")`. It is an ordinary run-and-record sample (it needs a `.out` like any other: print what it did), and `shots.py` runs it in a scratch directory and copies `out.png` to `shots/GROUP-NAME.png`. |
| `// book: gui` | **a program with windows** (`import gui;`): the sample checker only compiles it; `shots.py` starts a headless display server, runs the program as a client, drives it, takes a screenshot and cuts the window out. It has no `.out`. |

```sh
python3 docs/book/tools/shots.py                      # every graphical sample of every group (also the ones of the other contributors: pass your GROUP instead)
python3 docs/book/tools/shots.py gui/hello_window     # one sample (GROUP or GROUP/NAME, like samples.py)
python3 docs/book/tools/shots.py --list               # which samples are graphical
nice -n 10 python3 docs/book/tools/shots.py -v --keep gui   # keep the scratch directories (with the program's output in client.log)
```

What the tool does for a `gui` sample (details in the docstring at the top of `tools/shots.py`): it compiles `examples/gui/adisplayd.a` and the
sample, starts `adisplayd -vnc P1 -p P2 -control -size WxH` on two free ports between 21000 and 31999 (never 5900-5999 or 7000-7999), photographs the
empty desktop, starts the program with `ADISPLAY=127.0.0.1:P2`, waits, performs the actions of the directives, waits until the screen has
stopped changing, and writes the part of the screen that differs from the empty desktop (+ 8 pixels of margin) as a PNG. Every process it
started is killed afterwards, also after an error. A sample must therefore:

* **set `gui.caretBlinks = false;`** when it has a text field (the caret blinks on a timer and the picture would differ from run to run), and
  must not show the time of day, random numbers, or anything else that changes: the picture has to be the same every time;
* **connect with `gui.connect(null)`** (that reads `ADISPLAY`) and **run until the window is closed** (`d->run()`); a program that ends by itself
  fails ("the program ended ... before the picture was taken");
* keep its windows small: the screen is 800x600 by default (`// book: window=WxH` changes it), the first window is placed at 40,74 and the next ones
  cascade by 28 pixels, and a window that does not fit is cut off (the tool warns when the picture touches the edge of the screen).

Directives for the picture, one or more per `// book:` line, all within the first 12 lines (the **actions** run in the order written):

| Directive | Meaning |
|---|---|
| `window=WxH` | size of the screen (default 800x600) |
| `wait=MS` | time for the program to paint before the first action (default 1500) |
| `click=X,Y`, `rclick=X,Y`, `dclick=X,Y` | click with the left or right button, or double click; X, Y are **screen** coordinates (the first window's client area starts at 40,74: a widget at (10, 20) inside it is at 50,94) |
| `move=X,Y` | move the pointer (hover); with `pointer=keep` and `pause=1200` this shows a tool tip |
| `drag=X0,Y0,X1,Y1` | press, move in five steps, release (sliders, paint programs, splitters) |
| `scroll=X,Y,N` | mouse wheel at X,Y, N steps (N > 0 up, N < 0 down) |
| `type=TEXT` | type text (the rest of the line, blanks included, so put it last on its line) |
| `key=NAME` | one key: `enter tab esc backspace delete space left right up down home end pgup pgdn insert f1`..`f12`, a character, or with modifiers `ctrl+a`, `alt+f`, `ctrl+shift+z` |
| `pause=MS` | wait a while (every action is already followed by 200 ms) |
| `pointer=keep` / `pointer=X,Y` | by default the pointer is moved into the bottom right corner before the picture so that it is not on it; `keep` leaves it where the last action put it, `X,Y` puts it there |
| `full` | the picture is the whole screen, not the part that changed |

Example (a button that is clicked, then some text typed into the text field that has the focus):

```a
// A text field and a button
// book: gui
// book: click=110,127
// book: type=Hello
```

Work out the coordinates from the layout (window at 40,74 + padding + spacing + preferred sizes), or take a first picture with `full`, look at
it and read the pixels off. **Look at every picture** (the Read tool shows images): empty windows, clipped text and a window that is too
small are all possible, and the tool cannot tell. Tell the build nothing else: `build.py` takes `shots/GROUP-NAME.png` where a chapter says
`{{shot group/name}}`.

## 7. Terminal samples

A full screen program (the terminal UI toolkit, `import tui;` / `import term;`) cannot run in the plain checker: it needs a terminal. Mark it
`// book: tui` (add `compile-only` on the same line, `// book: tui compile-only`, so that every version of `samples.py` only compiles it) and
write two files next to it:

* `NAME.keys` - what the "user" does, one token per line (the vocabulary below);
* `NAME.screen` - the result, written by `tools/tuishot.py`: the final screen of an **80 x 24** terminal as plain text (trailing blanks
  trimmed, no escape sequences, so colours and the cursor are not part of it). A chapter shows it with the line `{{screen tui/name}}`
  after the listing.

```sh
python3 docs/book/tools/tuishot.py --update tui/hello      # build, run in a pseudo terminal, feed NAME.keys, record NAME.screen (twice: both runs must agree)
python3 docs/book/tools/tuishot.py tui                     # compare with the recorded screens (exit status 1 when one differs)
```

`tuishot.py` compiles the sample, starts it in a pseudo terminal of 80 x 24 (the terminal emulator of `tests/tui/ptyterm.py`, `TERM=xterm-256color`,
`LANG=C.UTF-8`, `HOME` and the working directory = the empty directory `/tmp/tuishot/run`, so a file dialog shows the same path everywhere),
waits until the program has been quiet for 250 ms after every token, and records the screen at the end. Look at the `.screen` file after you
recorded it, like a `.out` file. Things that change from run to run (a clock, a progress bar driven by a timer) must not be on the screen.
A program that is not a terminal program of the toolkit but still wants a plain screen can use `App.initHeadless` instead: it runs in the
normal checker and prints `app->text()` (no `tui` directive).

Tokens of a `.keys` file (`#` starts a comment line, blank lines are ignored; everything after the first colon is the argument, blanks included):

| Token | Meaning |
|---|---|
| `text:hello world` | type the text (UTF-8 is fine) |
| `key:enter` | one key: `enter tab esc backspace space delete insert home end pgup pgdn up down left right f1`..`f12`, `minus`, or one character |
| `key:ctrl-x`, `key:alt-f`, `key:shift-tab`, `key:ctrl-alt-up` | a key with modifiers (`ctrl`, `alt`, `shift`, joined with `-`; `ctrl` works with letters, `[ \ ] ^ _ / space`) |
| `wait:200` | wait this many milliseconds (then the usual quiet wait follows) |
| `click:10,5` / `rclick:10,5` | click with the left / right button at column 10, row 5 (cells counted from 0, SGR mouse reports) |
| `press:X,Y`, `drag:X,Y`, `release:X,Y` | the three parts of a drag with the left button |
| `wheel-up:X,Y` / `wheel-down:X,Y` | one wheel step |
| `paste:text` | a bracketed paste (the program must have switched bracketed paste on, which `App.start()` does) |
| `resize:100,30` | change the window size (`TIOCSWINSZ` + `SIGWINCH`); the recorded screen has the new size |
| `expect:text` / `gone:text` | wait (at most 6 s) until the text is on the screen / no longer there; an error otherwise. Use it where a program needs real time (a child process that ends) |
| `env:NAME=value` | set an environment variable for the program (before it starts), for example `env:TERM=linux`, `env:TUI_ASCII=1`, `env:NO_COLOR=1` |
