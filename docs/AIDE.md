# AIDE - the A IDE: the editor core libraries

AIDE is the integrated development environment of the A language. It will run as a terminal program (`aide`) and as a GUI
program (`aide-gui`), both on Linux and on AOS, and both are built on the same libraries. This document describes those
libraries (they are part of the A standard library, in `lib/`) and how the two front ends are meant to use them.

**State of the work.** The libraries described here are finished and tested (tests `t200` ... `t219`). The terminal front end exists: `user/aide.a` in the
AOS repository (`aide`, about 6000 lines, one file; manual `docs/AIDE.md` there) runs on the AOS terminals (serial console, `aterm`, `telnetd`) and on
Linux terminals, and uses everything below: `asys`, `acode`, `asyntax`, `atheme`, `aproject`, `afind` and the toolkit of [TUI.md](TUI.md). It has its own tests
(`tests/aide_tui_test.py` in the AOS repository: 90 tests in pseudo terminals, among them a random session of 500 keys, mouse events and resizes; and
the QEMU tests `aide` and `aide-gui`). The GUI front end (`user/gui/aide-gui.a`) does not exist yet. The libraries contain no user interface code: everything
that draws or reads the keyboard is the front end's job. The widgets of the GUI front end are the module `gcode` (section 13; tests `t240` ... `t267`),
and `examples/gui/codedemo.a` assembles them into a small working editor.

Contents

1. [Architecture](#1-architecture)
2. [asys - the system layer](#2-asys---the-system-layer)
3. [acode - buffer and editor](#3-acode---buffer-and-editor)
4. [asyntax - highlighting, symbols, completion](#4-asyntax---highlighting-symbols-completion)
5. [atheme - themes and settings](#5-atheme---themes-and-settings)
6. [aproject - project files, search and jobs](#6-aproject---project-files-search-and-jobs)
7. [afind - search and replace in a buffer](#7-afind---search-and-replace-in-a-buffer)
8. [regex](#8-regex)
9. [Writing a front end](#9-writing-a-front-end)
10. [AOS notes](#10-aos-notes)
11. [Tests and measurements](#11-tests-and-measurements)
12. [Known limitations](#12-known-limitations)
13. [The GUI widgets: gcode](#13-the-gui-widgets-gcode)

---

## 1. Architecture

```
                   aide (terminal)            aide-gui (GUI)               <- the front ends (aos repository)
                        |  draws cell grids        |  draws widgets
        +---------------+--------------------------+---------------+
        |                                                          |
      atheme (colours, settings)                                   |
        |                                                          |
      asyntax (tokens, symbols, completion) --+                    |
        |                                      |                   |
      afind (find / replace)  aproject (tree, find in files, jobs) |
        |                       |                                  |
      acode (Buffer, Editor)    |                                  |
        |                       |                                  |
        +----------- regex -----+---------- asys (memory, files, processes) ------ the kernel
```

* Every library is an ordinary embedded module: `import acode;` ... The embedded list is in `src/main.asm`.
* **No copying between layers.** A front end draws a line with `buffer.linePtr(i, &len)` (a pointer into the text, no copy) and
  `highlighter.tokens(i, ...)`; it learns about edits through a change listener (`Buffer.addListener`) and the buffer's
  `version`, so it only redraws what changed. Range queries (`lineStart`, `lineEnd`, `lineAt`, `copyRange`) are O(log n) or O(1).
* **Memory** comes from `asys.alloc` and goes back with `asys.free`; `dispose()` of every class frees everything it holds
  (the object itself is a few hundred bytes of `new` memory, which A never frees). Strings that the libraries return are asys
  memory; free them with `asys.free`.
* Objects with a constructor are declared with parentheses: `acode.Buffer b();` (a plain `acode.Buffer b;` is only zeroed).
* Errors are `-errno` numbers (`-asys.ENOENT` ...); `asys.errText(code)` makes text of them.

## 2. asys - the system layer

`import asys;` - a small layer that works on Linux (x86-64, ARM64, RISC-V 64, LoongArch64) **and on AOS**, using only system calls
that both have (see [section 10](#10-aos-notes)). On Windows memory, files, directories, time and random bytes work; child
processes, symbolic links, FIFOs and permission bits do not (those calls return `-ENOSYS`, `canSpawn()` and `hasLinks()` say so).

| Group | Functions |
|---|---|
| Memory | `alloc` (zeroed) `realloc` `free` `blockSize` `memInUse` `memBlocks` `memMapped` `memBadFrees` `keepsBigBlocks` `setKeepBigBlocks` (tests) `moveBytes` (memmove) `fillBytes` `bytesEqual` `strDup` `strDupN` `join` `concat3` |
| Files | `fileOpen(path, flags, mode)` `fileRead` `fileWrite` `fileClose` `fileSeek` `fileSync` `fileTruncate`; `readFile(path, &len, maxBytes, &err)` (regular files only: a FIFO, device or directory gives `-ENOTREG` and never blocks) `writeFile` `writeFileAtomic` class `AtomicFile` |
| Paths | `stat` `lstat` `fstat` (`Stat`: dev ino mode size mtime mtimeNs, `isFile()` `isDir()` `isLink()` `isFifo()` `perm()`) `exists` `isFile` `isDir` `mkdir` `mkdirs` `rmdir` `unlink` `rename` `readlink` `realpath` `getcwd` `chmod` `setMtime` `symlink` `mkfifo` `validName` `nameMax` |
| Directories | `listDir(path, DirList*)`: names and kinds from `getdents64` (no `stat` per entry), `DirList.sort(dirsFirst, ignoreCase)` |
| Time, random, environment | `nowMs` `monoMs` `sleepMs` `randomBytes` `getenv` `environment` |
| Processes | class `Process`: `start(argv, cwd, env, flags)` `read` `write` `closeIn` `tryWait` `wait` `signal` `signalGroup` `waitReadable` `dispose`; `pollFds` |
| Platform | `platform()` (`OS_LINUX`, `OS_AOS`, `OS_WINDOWS`; AOS is recognised through `uname`) `canSpawn()` `hasLinks()` |

**Memory.** Small blocks (up to 128 KiB) come from 2 MiB chunks in four size classes per doubling (at most 25 % waste) and are
reused through free lists; bigger blocks are `mmap`ed and, **on Linux**, go back to the system with `munmap` when freed; a big
block that shrinks moves to a smaller one; `realloc` of big blocks uses `mremap` on Linux. **On AOS and Windows freed big blocks
stay in the free lists** (`keepsBigBlocks()` is true) and the next request of the same size class, or of one or two classes below
(at most 50 % too big), takes one of them (zeroed again); if the system is full any bigger free block is used before `alloc` gives up.
The reason on AOS: its kernel hands out `mmap` addresses from a pointer that only moves up and `munmap` never lowers it (`doMmap` in
`kernel/sys.a`; the whole area is 0x10000000 - 0x3F000000, about 788 MB), so about 2600 cycles of `alloc(300000)` + `free` used up
the address space with nothing in use and `alloc` returned null (this crashed a long AIDE session: found in review, `t204` crashed
on AOS because of it). Windows has no `VirtualFree` in the compiler's import table. The price of keeping blocks is that the address
space used is the sum, over the size classes, of the most big blocks that were alive at the same time; it is not given back. Blocks
carry a header with a magic number, so a double free or a foreign pointer is detected, ignored and counted (`memBadFrees`).
`memInUse()` makes leaks visible: the tests compare it before and after a cycle. `setKeepBigBlocks(1)` switches a Linux process to
the AOS behaviour (tests do this: `t203`), `setKeepBigBlocks(0)` back.

**Atomic writing** (`AtomicFile`, `writeFileAtomic`, `Buffer.save`): a temp file `.NAME.tmp-<12 random hex digits>` is created next
to the target with `O_CREAT | O_EXCL | O_NOFOLLOW` and *the permissions of the existing file from its first byte*
(`fchmod` only repairs what the umask removed); data is written, flushed (`fsync`; `sync` on AOS), and renamed over the target.
A failing `fsync` (`EIO`, `ENOSPC` of a delayed allocation, a network file system) makes the save fail and removes the temp file; the
old file stays (`-EINVAL` / `-ENOSYS` only say that this kind of file cannot be synced and are ignored). A symbolic link as target
is resolved (the data goes where the link points; a loop of 32 links is `-ELOOP`); on any error the temp file is removed;
`W_BACKUP` keeps the old content as `NAME~`; `W_INPLACE_OK` allows overwriting in place when no temp file can be created (`EACCES`,
`EROFS`, `EPERM`, `ENAMETOOLONG`).
The temp name must fit the file system: if `.NAME.tmp-<12 hex>` would be longer than 250 bytes (Linux) or 55 bytes (AOS; there the
whole path must also stay within 255) the NAME part is cut, at a character boundary and never the random part (an earlier version cut
the end, so for a 255 byte name every save used the same temp name and one stale file of that name made all saves fail with `-EEXIST`,
and on AOS every name of 38 to 55 bytes failed with `-ENOSPC`).
**The identity of the file is kept** (Linux; `Stat` has `gid` for this): the temp file is given the owner and group of the old file
(`fchown`, then the permissions are put back, because `fchown` clears set-user-id bits). When the process may not give a file away
(a normal user saving a file of somebody else that it may write) or when the file has **several hard links**, the old file is
**overwritten in place** instead of replaced: the owner, the group and every hard link name keep working, but the save is not atomic
(a crash in the middle leaves a short file) and the permissions of the old file decide (`-EACCES` when it is not writable: then nothing
is changed and no temp file stays). A file with one link and the owner of the process is still replaced by rename. What stays as it
was: the **write permission bit does not protect** such a file (a 0444 file is replaced and stays 0444; a front end that wants to
protect read-only files must look at the mode itself). Extended attributes and ACLs are not copied. (Before this, a save changed the
owner and group to those of the process and broke hard links. Test `t270`.)

**Processes.** `Process.start` forks, sets up the pipes (all `O_CLOEXEC`, parent ends non-blocking, descriptors below 3 are moved
away before `dup2`), searches `PATH` itself, and reports a failing `exec` *synchronously* (`-ENOENT`, `-EACCES`) through a
close-on-exec error pipe. `P_GROUP` makes the child a process group leader, so `signalGroup` reaches grandchildren. The parent
ignores `SIGPIPE` (the child gets the default back), so `write` returns `-EPIPE` instead of killing the editor. After a signal
the status is that of `wait4`: `termSignal` or `exitCode`, never overwritten.

## 3. acode - buffer and editor

`import acode;` - see the header of `lib/acode.a` for the full list. The design in short:

**Buffer.** The text is a *gap buffer* (UTF-8 bytes; in text mode lines are separated by `\n` only). The line index is a second
gap array of line start offsets; entries behind the gap are stored relative to a running shift, so inserting or deleting lines near
the gap costs O(1) and moving the gap costs O(distance). Consequences, measured on one core (the table in section 11 has the numbers):
100 000 lines appended or prepended one by one take about 50 ms; edits close to each other are free; an edit far away from the
previous one costs the move of the two gaps over that distance, about 6 ms on average (17 ms for the longest jump) in a 120 MB
file. A rope or piece table would make that O(log n) at the price of everything else being slower.

* `linePtr(i, &len)` returns a pointer into the text when the line does not straddle the gap, else into a scratch copy - the
  front end cannot tell and does not need to (the pointer is valid until the next edit or the next `linePtr` call that needs
  the scratch copy). `flatten()` moves the gap to the end and returns the whole text contiguously.
* **Line endings, BOM, binary.** `load` detects LF / CRLF / CR (lone CR only when the file has no LF), the dominant style wins
  and `eolMixed` says that the file mixed them; the text in memory has `\n` only and `save` writes the detected style back.
  A UTF-8 BOM is removed and remembered. A file with NUL bytes in the first 8000 bytes, or a UTF-16 byte order mark, is *binary*:
  no conversion at all, byte for byte, not trimmed.
* **Undo.** An operation record is `(offset, bytes deleted, bytes inserted)` with the bytes in one arena; consecutive insertions
  (and forward deletions) are stored in one operation. `beginGroup(snapshot, n, key)` / `endGroup(snapshot, n)` make a step and record
  the cursors before and after it. Steps with the same non-zero `key` merge when the previous step ended with exactly the cursors
  the new one starts with (typing, backspace, delete). The history is capped (32 MiB by default, oldest steps dropped), and the
  *modified* flag compares state numbers: it is correct after undo, redo, new edits on a branch and after the save point was dropped.
  `setHistory(false)` forgets everything.
* **Listeners** get a `Change` (offset, bytes removed / inserted, first line, lines removed / inserted, version, kind) after each
  change - also for undo, redo and loading. There is no fixed number of listeners.
* **Files.** `load` opens with `O_NONBLOCK`, checks `fstat` (regular files only), reads straight into the buffer storage, scans
  once for the line index. `save` streams through `AtomicFile`. `checkExternal()` compares modification time (to the nanosecond)
  and size with what was seen at load / save (`EXT_CHANGED`, `EXT_DELETED`); `reload()`, `acknowledgeExternal()`.

**Editor.** A set of cursors `(anchor, pos, goal)`, kept sorted and merged (`normalize`), always on character boundaries. The
editor listens to its buffer and moves its cursors through every change, so several editors on one buffer stay consistent. Commands
work on all cursors from the last to the first, inside one undo group. Highlights:

* `typeChar` merges into word sized steps; `newline` copies the indentation, opens a level after `{ ( [` (and `:` for Python),
  splits `{|}` over three lines and empties a line that only holds indentation; typing `}` on a blank line aligns it with the line
  of its opening bracket (`matchBracket`, which skips strings, character literals and comments of the current language).
* `moveLines` moves the selection with its block (a selection that ends at column 0 of the next line moves that end too);
  `duplicateLines`, `joinLines`, `deleteLines`; `toggleLineComment` comments at the shallowest indentation and uncomments exactly;
  `copy` / `cut` / `paste` with a ring (`Clipboard`); with several cursors the pieces are remembered, so pasting into the same
  number of cursors puts one piece into each; copying without a selection copies whole lines and pastes above the caret line.
* `selectEnclosingBrackets` selects the content of the innermost bracket pair around the selection; called again it grows to the
  brackets themselves, then to the next pair outwards, and returns false when there is none.
* `tabWidth` / `indentWidth` below 1 mean 4 and above 64 mean 64; nothing divides by them unchecked.

## 4. asyntax - highlighting, symbols, completion

`import asyntax;`

* **Lexers** for A, C, C++, Python, shell, JSON, Markdown, INI, TOML, HTML, XML, Makefile and plain text. `lexLine(lang, state, text,
  len, tokens, max, &endState)` is a pure function: spans `(start, len, kind)` that cover the line without gaps, kinds from the fixed
  enum `Tok` (`Plain Keyword Type Builtin Constant Number String Char Escape Comment DocComment Preproc Operator Punct Function
  Variable Tag Attribute Heading Emphasis Link Code Quote Error`). The state is a small integer (in block comment, in a triple
  quoted string, in a here document - with a hash of its end word - in a Markdown fence, in an HTML script, ...).
* **Highlighter** (class): keeps the state at every line start. A buffer listener repairs the table *at once* after each edit: it
  lexes again from the changed line until the state at a following line start equals the state that was stored before (at most
  120 lines per edit; the rest is lexed when somebody asks). Typing in a line of code therefore costs one line. Bursts of edits
  (more than 64 between two requests) make the highlighter start over lazily. The tests compare the incremental result with a fresh
  lex after random edits (and undo / redo) in every language, 40 000 rounds in a one-off run.
* `detectLanguage(fileName, firstLine)` (extension, `Makefile`, `.bashrc`, `#!` lines, `<?xml`), `languageName`, `languageFromName`.
* `symbols(buffer, lang, SymbolList*)`: for A and C - modules, classes, structs, enums, unions, typedefs, constants (`const`,
  `#define`), functions and methods with their class; found from the token stream, so strings and comments never produce
  symbols. Python: classes, functions, methods, UPPER_CASE constants. Markdown: headings. Shell: functions. Makefile: targets.
* `Completer`: keywords of the language + symbols + words of the registered buffers, matched by prefix; exact-case matches
  come before case-insensitive ones, then symbols, keywords, words; shorter names first, then alphabetical. Its caches follow
  `Buffer.version`.

## 5. atheme - themes and settings

`import atheme;`

* **Theme**: 24 named colours (`Col`) and a colour + style (bold / italic / underline) for each of the 24 token kinds. Built-in:
  `dark light solarized-dark solarized-light monokai high-contrast gruvbox nord aos` (all nine pass their own validation; the
  Solarized themes are slightly adjusted where the originals are too faint to read). `toIni` / `save` / `loadTheme` /
  `parseTheme`: INI with `[theme] name base`, `[colors]`, `[tokens]`; a file only needs to name what it changes, the rest comes
  from `base`. Corrupt input (random bytes, NUL bytes, a 10000 byte line, a file over 1 MB, a BOM, bad values) gives warnings and
  the base theme, never a crash.
* `Theme.validate(Warnings*)` warns about unreadable contrast: text against its background must reach 4.5:1 (WCAG AA), line
  numbers, cursor, error / warning and syntax colours 3:1.
* **Colour helpers**: `rgb red green blue parseColor formatColor mix lighten darken to256 from256 to16 from16 luminance contrast
  readable`. `contrast` is the WCAG ratio times 100 (computed from a 256 entry linearisation table; checked against published values).
* **Settings** (`tabWidth insertSpaces lineNumbers wordWrap fontSize autoIndent trimOnSave finalNewline theme`, window geometry,
  recent files and projects (30 each, most recent first), key binding overrides `action = keys`): `$AIDE_HOME`, else `~/.aide`;
  numbers are clamped, unknown entries counted, `save` creates the directory and writes atomically.

## 6. aproject - project files, search and jobs

`import aproject;`

* **Globs** (`globMatch`, used by Ignore, the file tree and the file filter of find): `*` does not cross `/`, `**` does (`**/` may
  also match no directory), `?`, `[a-z]` `[!a]` `[^a]`, `\` quotes. The matcher is an automaton over the text, time O(pattern x
  text) and no recursion, so a hostile `.gitignore` line such as `*a*a*a*a*a*a*b` cannot freeze the tree (an earlier backtracking
  version needed 15 s for six stars against a 100 byte name and minutes for seven; the new one is compared with it on 400 000 random
  patterns, no difference).
* **Ignore**: `.gitignore` rules (`*  ?  [a-z]  **  !  /anchor  dir/`), rules from nested files carry their directory, plus a
  built-in list (`.git/ .hg/ .svn/ .bzr/ node_modules/ __pycache__/ *.pyc *.pyo *.o *.obj *.so *.dll *.dylib *.class .DS_Store
  Thumbs.db *.swp *.swo *~ #*#`; `.a` files are *not* ignored, and neither is `.gitignore`).
* **FileTree**: lazy; sorted folders first; ignore rules applied; symbolic links are entries of kind `K_LINK` and are **not
  followed** unless `followLinks` is set, then a directory whose (device, inode) equals an ancestor's is marked `loop` and not
  entered; `maxEntries` (200 000) and `maxDepth` (64) bound the walk (`truncated` says so); `create` / `rename` / `remove` validate
  names (`-EBADNAME` for "", ".", "..", `/`, `\`, control characters, more than `nameMax()` = 255 bytes, 55 on AOS) and refresh the tree.
* **Watcher**: polling: `watch(path)` / `unwatch(path)`, then `poll(events, max)` stats what is watched and reports created,
  modified and deleted entries (a watched directory reports its children).
* **FindJob**: plain / case-insensitive / whole word / regex search with context lines; `step(budgetMs)` does a bounded amount of
  work and `cancel()` stops it; only regular files are opened (a FIFO is skipped, never read), binary files and files over
  `maxFileSize` (5 MiB) are skipped, results are capped (`maxResults`, 10 000), symbolic links are not followed unless
  `FIND_FOLLOW` is given (then loops are detected by device and inode), the walk is at most 64 directories deep. When a regular
  expression hits its step limit in a file (a catastrophic pattern such as `(a+)+b`, or a huge line) the job sets `exceeded` and
  counts `filesExceeded`, and skips the rest of that file, so the results are known to be incomplete instead of silently empty.
* **QuickOpen**: `index(root, ign)` then `query(text, out, max)`: fuzzy file name search (`"fmain"` finds `src/main.a`;
  consecutive characters, component and word starts and file name hits score higher, ties go to the shorter path).
  **Recent**: an MRU list with `add`, `indexOf`, `save(path)` and `load(path)`.
* **Job / BuildJob / RunJob**: run a command with pipes *without ever blocking*: `poll()` reads what arrived (into a queue capped
  at 4 MB, oldest bytes dropped and counted - the pipe is always emptied, so a program that floods its output never stalls),
  feeds the input queue (`sendInput` never blocks, is capped at 1 MB, `closeInput` closes after the queue), notices the end,
  enforces `timeoutMs` (SIGTERM to the process group, SIGKILL after `graceMs`; `timedOut` is a flag, the exit status stays the real
  one), `kill()`, `killNow()`, `elapsedMs()`. `BuildJob` turns lines into `Problem`s (`path`, `line`, `col`, `severity`, `message`):
  the A compiler and GCC / Clang (`file:line[:col]: error: message`), `In file included from`, Visual C `file(line): error C1234`,
  Rust `error[E..]` + `--> file:line:col`, Python tracebacks; ANSI colours and Windows drive letters are handled.
  `startCompiler(source, output, target)` finds `ac` (`$AC`, `PATH`, `/usr/local/bin`, `/usr/bin`, `/bin`).

## 7. afind - search and replace in a buffer

`import afind;` - class `Finder`: `setPattern(pattern, OPT_REGEX | OPT_ICASE | OPT_WORD | OPT_NOWRAP)`, `findNext(from)`,
`findPrev(before)`, `count(limit)`, `matches(list, max)`, `replaceCurrent(editor, template)`, `replaceAll(editor, template)`,
`setRange(from, to)` (search in the selection). Search is per line (fast, uses `linePtr`); a pattern that contains a line break
searches the flattened text. Templates: `$0`..`$9`, `${n}`, `$$`, `\n \t \\` in regex mode, literal in plain mode.

Rules from earlier reviews, each with a test: `count` / `matches` do not disturb the current match; the groups used by
`replaceCurrent` belong to the match being replaced (it is matched again, anchored at its start, so `findPrev` makes no
difference); the current match becomes invalid when the buffer changes (`currentValid()`); `replaceAll` is one undo step and
handles empty matches like Python 3.7 (`re.sub`): an empty match is not allowed right after an empty match, so a pattern where the
empty match has priority (`a*?`, `x*|b`) finds `a` or `b` at the same place on the next round, and that match is re-matched under the
same rule for its groups (an earlier version lost the matched text: `a*?` on `aab` with `[$0]` gave `[][][][][]b[]` instead of
`[][a][][a][]b[]`). `exceeded` says that a regular expression hit its step limit (see section 8) during the last
`findNext` / `findPrev` / `count` / `matches` / `replaceAll`: the result is then incomplete (`replaceAll` replaces the matches found
before the search gave up), and a front end should say so.

## 8. regex

`import regex;` was rewritten for AIDE. The old four functions (`matches`, `search`, `test`, `replaceAll`) keep their old simple
dialect (`F_SIMPLE`, also usable with `compile(pattern, F_SIMPLE)`): `( ) | { }` are plain characters, a `^` that is not first and a `$`
that is not last are plain characters, `.` also matches a line break and `$` matches only at the very end of the text (not
before a final line break), everything else as before (`grep "main()"` of the AOS shell relies on this). Matching is UTF-8 aware
there too (`.` takes a whole character, `\w` includes non-ASCII letters), which the old functions were not. The new
syntax is for `compile()` and `replaceGroups`. The engine is a backtracking engine with Perl / Python
semantics: groups (up to 32) and non-capturing groups, named groups, alternation, greedy and lazy `* + ? {n,m}`, back
references, `^ $ \A \Z \b \B`, classes with ranges, POSIX classes and the shorthands, look-ahead `(?= )` `(?! )`, flags `(?i) (?s)
(?m)` also scoped, UTF-8 aware (`.` and negated classes take a whole character; `\w` includes non-ASCII letters; case folding is
ASCII only). A repeated group that matched the empty string ends its repetition (`(a*)*` on `b` matches once); this holds for
`* + {n,}` and for bounded `{m,n}`, where an empty iteration beyond the minimum ends the repetition like in Python (`(?:b?|xb){1,3}b`
on `xbbb` matches 4 bytes). One known difference to Python before 3.14 (Python 3.14 and Perl agree with this engine): `\B` matches
in an empty text. Errors are compile
errors with a message and a position (back reference to a missing or open group, unbalanced parentheses, bad ranges, "nothing to
repeat", "multiple repeat", a program over 400 000 instructions, nesting over 150). The matcher is a loop with an explicit stack
(no recursion per character: `.*Z` over a million characters works) and stops after 5 million steps (`exceeded`) so `(a+)+b` cannot
hang an editor. `tests/gen/gen_regex_test.py` runs 168 patterns through Python's `re` and compares search, group positions,
fullmatch and `sub`. In addition about 340 000 random patterns (groups, alternation, lazy and bounded quantifiers, back references,
look-ahead, flags, UTF-8; 3 texts each) were compared with Python 3.13 while reviewing this module and fixing the review findings:
the only differences are `\B` in an empty text and patterns where this engine's step limit is reached before Python
finishes (those are reported through `exceeded`, never silently). `afind.Finder.replaceAll` was compared with `re.sub` on about
200 000 of the same cases (single-line, non-empty texts) with no difference outside the step limit.

## 9. Writing a front end

Both front ends do the same things; only drawing and input differ.

1. `acode.Buffer b(); acode.Editor e(&b); asyntax.Highlighter* h = new asyntax.Highlighter(&b, lang); atheme.Theme* t =
   atheme.builtin("dark");` - open files with `b.load(path)`, language from `asyntax.detectLanguage(name, firstLine)`,
   `e.setLanguage(asyntax.languageName(lang))`, tabs from `e.detectIndent(true)`. Nothing is freed automatically (A has no
   destructors): call `dispose()` on everything you are done with.
2. Draw: for each visible line `i` get the text with `b.linePtr(i, &len)` and the spans with `h.tokens(i, tok, 256)`; colours
   from `t->tokenColor(kind)`. Selections and carets are `e.cur[k].anchor/.pos`; columns with `b.visualCol(i, offset, e.tabWidth)`
   (and `offsetAtCol` for mouse clicks). `visualCol` remembers the answer for the last offset of a line, so asking for the caret's column
   after every key stays O(1) at the end of a long line (and while typing in its middle); a scan from the line start is only needed after
   an edit before the remembered offset (test `t273`). Bracket highlight: `e.matchNearCaret(&at)`.
3. Keys call `Editor` commands (`typeChar`, `newline`, `backspace`, `moveLeft(shift)`, `undo`, ...). To know when to redraw compare
   `b.version` (or register a listener: the `Change` says which lines moved).
4. Files: `b.checkExternal()` on focus, `e.saveFile(path, flags, s.trimOnSave, s.finalNewline)`.
5. Project panel: `FileTree`; Ctrl+P: `QuickOpen`; Ctrl+Shift+F: `FindJob` stepped from the idle loop (`step(10)`); Ctrl+F:
   `afind.Finder`; build: `BuildJob.startCompiler`, call `poll()` from the idle loop, show `problems`, jump to `file:line`;
   run: `RunJob` with `sendInput` for a terminal pane.
6. Long running things (search, jobs, watcher) never block: everything is polled from the front end's own loop.

A terminal front end redraws a cell grid from the same data; the lines it needs are `linePtr`, `h.tokens`, `charWidth` (in
`acode`) and `visualCol`.

## 10. AOS notes

asys uses only calls that `kernel/sys.a` of AOS implements: `read write openat(257, directory descriptor ignored) close lseek
stat fstat lstat mmap munmap fcntl pipe2 dup2 fork execve wait4 kill poll rename mkdir rmdir unlink getdents64 getcwd chdir
clock_gettime nanosleep getrandom uname setpgid rt_sigaction`.

Missing in AOS, and what asys does:

* `fchmod`, `chmod`, `fsync`, `mremap`, `ftruncate`, `utimensat`, `link`, `symlink`: never called on AOS (asys asks `uname` once);
  `fsync` becomes `sync`, permissions are given when the file is created, `symlink` / `setMtime` return `-ENOSYS` and `hasLinks()` is false.
* `statx` and `clock_nanosleep` do not exist in the kernel; asys does not use them (it uses `stat` and `nanosleep`).
* File names are limited to 55 bytes and paths to 255 bytes by the AOS file system; `nameMax()` is 55 there and `validName` refuses
  longer names (the kernel reports a create with a too long name as `-ENOSPC`, which is misleading; `rename` says `-ENAMETOOLONG`).
  `AtomicFile` shortens its temp name to fit (see section 2).
* Freed big blocks stay in the allocator (the kernel never takes `mmap` address space back); see the Memory paragraph of section 2.
* `setMtime` is `-ENOSYS` and the AOS file system stores whole seconds: `Buffer.checkExternal` compares size and modification time,
  so a same-size rewrite within the same second as the load or save is not noticed. (`t207` waits a second on AOS for this reason.)
* The AOS shell and its tools (`user/sh.a`, `user/box.a`) are small, which matters for `Job.startShell`, `RunJob` and the tests
  that run shell commands: `sleep` takes whole seconds, `head` / `tail` have `-n` only (no `head -c`), `yes` never ends, `wc` pads
  its numbers to a width of 7 (`wc -c` exists but prints `" 588895"`), and `head`, `tail`, `wc`, `sort` and the other filters read at most
  1 MiB - 1 byte of their input first. The shell has no `$((..))` arithmetic, no `trap`, no `<&-`; it has `for ... in $(...)`,
  `while`, `if`, `case`, pipes and redirections. `t202` and `t213` are written with these limits in mind (see below).
* `execve` runs ELF files and `#!` scripts only (no fallback to the shell for a script without `#!`); `Job.startShell` needs
  `/bin/sh` to exist and to understand `-c`.
* `fork` on AOS is a full copy of the address space (the kernel says so in `sys.a`: "a full copy is fine"), so starting a job from
  a big editor is slower than on Linux.
* A process has at most 32 memory areas (`NVMA` in `kernel/proc.a`; the kernel never merges neighbours), and the image, the stack and
  every `mmap` use one each. asys therefore maps its small-block chunks 2, 4, 8, 16, 32 MiB (the sizes double, then stay at
  32 MiB) and carves blocks up to a quarter of a chunk (512 KiB growing to 8 MiB) from them; every live block that is bigger takes
  one area of its own and freed ones are kept (not unmapped), so about 25 different big blocks can exist over the lifetime of a process
  before `alloc` falls back to reusing a bigger free block or returns `null`. A front end that edits many huge files at once on AOS
  should keep the number of 8 MiB+ blocks low (one `Buffer` needs a few: text, line index, history).
* **What was run on AOS** (review round 2, QEMU without KVM, an image with the test programs and the compiler in it; the test
  programs are the ordinary Linux x86-64 executables, AOS runs them unchanged; `t213` and `t219` find the compiler as `build/ac` in the
  working directory, so the image had it as `/build/ac` and the tests were started from `/`): `t200` to `t219` all pass (`t202` and `t219` print one
  extra line on the console, the kernel's note about the unimplemented `fchmod` that the compiler `ac` calls, and `t202` the AOS
  shell's complaint about `exec 0<&-`; both are not part of the test's standard output, which equals the `.out` file), 20 000
  cycles of `alloc(300000)` + `free` fit in 2 MB, and file names of 38 to 55 bytes are saved atomically. At that time there was no front end; see
  the next paragraph for what was run with AIDE. The whole AOS image was also built
  with this compiler and its own boot tests `boot`, `shell`, `coreutils`, `processes` and `torture` pass (the `grep` of the AOS shell
  was checked by hand: `grep 'main()'` finds `main()` only, `grep 'a|b'` finds the text `a|b`, `^b$` and `ma.n` work).

* **AIDE on AOS** (stage "aidetui"; QEMU without KVM): `aide` runs on the serial console (read through a terminal emulator that also answers the
  size queries), in `aterm` (screenshot) and as the real thing for typing, saving, building with the in-OS compiler (`/bin/ac`, a fraction of a second), running the
  result, a compile error in the Problems list, Ctrl+F5 (the program on the real terminal and back), and quitting with the shell normal again. What AOS needed for it
  (a pty output queue that drops what does not fit, a kernel log line that tore the console screen) was fixed in the AOS repository, see its `docs/ARCHITECTURE.md`.
  The liveness mark of a running AIDE and the recovery copies need `/tmp` and `/home`; the lock is in `/tmp` on AOS so that nothing is written to the disk every few seconds.

## 11. Tests and measurements

| Test | What it checks |
|---|---|
| `t200_asys_mem` | allocator: zeroing, classes, big blocks, realloc, counters, double free, `moveBytes` |
| `t201_asys_files` | files, atomic writes (permissions, backup, streaming, links, loops), listing, FIFOs, names, time, random |
| `t202_asys_proc` | pipes, exit codes, environment, cwd, exec errors, 1 MB through `cat`, full pipes, `EPIPE`, floods, group kill |
| `t203_asys_fuzz` | 6000 random alloc / realloc / free operations (1 byte to 3 MB) checked against block patterns, zeroing, overlap and the counters, run twice (also with freed big blocks kept, as on AOS); 200 `alloc(300000)` + `free` cycles and 4 cycles of a 12 MB block map one block each (small on purpose: reuse zeroes the block, and qemu-user is slow) |
| `t204_acode_diff` | 10 000 random edits + grouped undo / redo with cursor snapshots against a reference model; line index; UTF-8 |
| `t205_acode_cursor` | exact cursor restoration (merged typing, backspace, delete, backwards selections, 4 cursors), motions, UTF-8, tab width 0 |
| `t206_acode_lineops` | move / duplicate / join / delete lines, indentation, comments, auto-indent, brackets, clipboard, clean-ups |
| `t207_acode_file` | LF / CRLF / CR / mixed / BOM / binary / UTF-16 round trips, external changes, FIFO, listeners, memory cycles of big texts |
| `t208_asyntax_lex` | token dumps of 13 languages, language detection |
| `t209_asyntax_inc` | incremental = fresh after random edits in 10 languages; work after an edit; symbols; completion |
| `t210_atheme` | colour conversions and WCAG values, 9 themes validated, theme / settings round trips, corrupt files |
| `t211_aproject_tree` | globs, ignore rules, tree (links, FIFOs, bounds, names), watcher, recent files, quick open |
| `t212_aproject_find` | find in files: modes, context, steps, cancel, limits, FIFO, link loops |
| `t213_aproject_job` | diagnostics (26 line formats and Rust's two line form), incremental output, input queue, timeout, kill, floods, the real `ac` |
| `t214_afind` | find / replace rules above, Python comparison of `replace all` (also patterns where an empty match has priority: `a*?`, `x*|b`) |
| `t215_regex_python` | 168 patterns compared with Python's `re` (generated by `tests/gen/gen_regex_test.py`), among them bounded repeats of groups that can be empty |
| `t216_regex_more` | flags, POSIX classes, 32 groups, errors, limits, big inputs, `quote` |
| `t217_acode_perf` | 100 000 lines inserted at the end / start / random places, 50 000 typed characters, 2000 cursors, a 3 MB file |
| `t218_regressions` | temp file permissions and names (also at the name limit), extreme tab widths, `dispose()` of every class, 24 MB cycles, bounded walks; exact undo / redo after the history was trimmed (model based), whole-line paste into several cursors, out-of-range line numbers, glob worst cases, find in files `exceeded`, the old regex dialect |
| `t219_aide_session` | a whole session through all modules: project, ignore rules, tree, quick open, find in files, buffer, editor, highlighter, symbols, completion, rename with undo, save, external change, watcher, settings, a real build with an error, the fix, the run |
| `t270_asys_identity` | `AtomicFile` keeps hard links together and the owner, group and set-user-id bits of the file it replaces; a second user (the test forks and calls `setuid`) overwrites a foreign file in place and gets `-EACCES` for one it may not write; a new file is made as before (needs root for the owner checks) |
| `t273_acode_visualcol` | `visualCol` against a plain scan after 4000 random edits (tabs, wide, combining, newlines, undo), set text, and typing 60000 characters into one line with a column query after every key |

All of them pass on the five targets (x86-64, ARM64, RISC-V 64, LoongArch64 under qemu-user, Windows under Wine) and, as
plain x86-64 executables, in an AOS image (see section 10; `t202` and `t213` use other shell commands there: `seq` instead of
`yes | head -c`, whole second sleeps, no `trap`, so a few numbers differ, the checks do not). On Windows
`t202` and `t213` print that processes are not supported (`.out.windows`), and `t218` skips its block about file names at the name
limit there (Windows has `MAX_PATH` instead; `.out.windows` has 92 checks instead of 103); the other tests run unchanged.

Measured natively on one core of the development machine (x86-64, a virtual machine; the numbers vary by 30 % from run to
run; the ARM64, RISC-V and LoongArch64 runs go through qemu-user and are 10 to 30 times slower, which the tests allow for):

| | |
|---|---|
| append / prepend 100 000 lines one by one | 50 ms / 55 ms |
| type 100 000 characters (one undo step, 100 KB of history) | 35 ms |
| a 120 MB file (125 821 440 bytes, 2.18 million lines): load | 0.85 s, 146 MB of memory |
| the same: 10 000 edits close together | 20 - 40 ms |
| the same: 1000 edits at random lines (each one moves the gaps) | 6 s, so 6 ms per edit; the longest jump (104 MB) 17 ms |
| the same: highlight line 1 000 000 for the first time (lexes 1 million lines) | 1.1 s |
| the same: search the whole file for a word that is not there | 0.33 s |
| the same: `setText("tiny")` afterwards (with highlighter attached) | 47 KB in use, 2 MB mapped |

These come from a throw-away measuring program, not from the tests (the tests only check that nothing is quadratic and that the
results are right). A previous version of the gap move copied backwards byte by byte when the distance was no multiple of 8:
a 100 MB jump took 250 ms; `asys.moveBytes` now copies in blocks and the same jump takes 17 ms (`t200` checks the results of all
distances).

## 12. Known limitations

* **Random edits in huge files** cost O(distance) because the text and the line index are gaps (6 ms per edit on average in a
  120 MB file when the edits jump around; local edits are free). A piece table or rope would change that. Highlighting a line
  far down a file that was never looked at lexes everything above it once (1.1 s for 2 million lines); the front end should keep
  asking for visible lines only, which are cheap afterwards.
* One cursor set per `Editor`; several views of one buffer are several `Editor`s (they stay consistent through the listener), but
  there is no shared selection history.
* Column selection is a set of cursors (`addCursorsInColumn`), not a rectangular selection object. No word wrap, no code folding,
  no bidirectional text: those belong to the front end (the engine gives display columns, not visual lines).
* Auto-indent knows `{ ( [` and `:`; there is no language specific smart indent beyond that, and no auto-closing of brackets.
* The lexers are line based: nested languages (JavaScript in HTML, code in Markdown fences) are not highlighted, only the
  container. Symbol extraction is heuristic (token patterns, no parser).
* `regex` has no look-behind, no possessive quantifiers, no Unicode classes or case folding beyond ASCII; matching is on bytes
  with UTF-8 aware `.` and sets.
* `afind` does not search across lines unless the pattern contains a line break; `^` and `$` are line anchors in the per-line mode.
* The watcher polls (no inotify), so it is only as fast as the caller's loop and costs one `stat` per watched entry.
* On Windows the allocator cannot give big blocks back (the compiler's import table has no `VirtualFree`): freed big blocks are
  kept in size-class free lists and reused. After a 24 MB text was edited and dropped, about 90 MB stayed mapped (in use: 0).
* Processes need `fork`/`execve`: not on Windows. `Job` merges standard error into standard output.
* Not tested here: files over 2 GiB (`maxLoad` defaults to 1 GiB), real ARM64 / RISC-V / LoongArch hardware (everything runs under qemu-user).

## 13. The GUI widgets: gcode

`import gcode;` puts the engine above on the screen as widgets of the A toolkit (`gui`, `guix`, `gfx`): the full description of every widget,
its keys and its callbacks is in [GUI.md](GUI.md#the-code-editor-widgets-gcode). Here is how the pieces fit together.

```
 CodeEditor ---- Doc ---- acode.Buffer + acode.Editor (cursors, undo)      Look: atheme.Theme, font, preferences
   draws only      |       asyntax.Highlighter (tokens of visible lines)       |  every widget registers with it:
   the visible     |       markers (diagnostics), bookmarks                    |  a theme change repaints them all
   lines           +--- asyntax.Completer (words of every open Doc)
 FindBar -- afind.Finder      Outline -- asyntax.symbols      EditorStatus -- Buffer fields (eol, bom, binary)
 FileTree -- aproject.FileTree + Ignore + Watcher             OutputPane -- aproject.Job / BuildJob + Problem
 Palette -- aproject.QuickOpen (files) or your own list       ThemeEditor / SettingsDialog -- atheme.Theme / Settings
```

The way a front end is written with them (this is `examples/gui/codedemo.a`):

1. One `Doc` per open file; the tab bar holds the `Doc*` as the user data of each tab, and the editor shows the selected one (`editor->setDoc`).
2. The editor tells the others through `editor->observe(f, user)` (events `EV_CHANGE`, `EV_CURSOR`, `EV_SCROLL`, `EV_DOC`): the status bar, the
   outline and the modified dot of the tab follow it without the editor knowing about them.
3. Files open from `FileTree.onOpen`, from the palette (`Palette.showFiles` on an `aproject.QuickOpen` index) or from a dialog. Saving is
   `doc->save(null)`; the Look decides whether trailing white space is trimmed and a final line break is added.
4. A build is an `aproject.BuildJob` that `OutputPane.attachBuild` follows from the event loop (a timer, never blocking); when it ends the problems
   become markers in the open documents (`doc->addMark`), and a click on a problem opens the file and calls `editor->gotoLine`.
5. Keys that belong to the whole window (Ctrl+S, Ctrl+Shift+P ...) are commands in a `Commands` registry that `install(window)` puts in front of the
   focused widget; the user's own bindings come from the `[keys]` section of `settings.ini`.
6. Settings and themes: `Look.applySettings` at start, `SettingsDialog` and `ThemeEditor` change the Look live, `Look.storeSettings` +
   `Settings.save` at exit; user themes are files in the theme directory.

Performance facts (checked by `t243`): drawing and lexing touch only the rows in view (`Highlighter.tokens` per visible line), an edit
repaints only the rows it changed (or the rows below when the lexer state at the start of the next line changed), the word highlight scans
the visible lines (no regular expression), the bracket match is looked up only when a bracket is next to the caret, and the completion popup
is computed after a 100 ms pause (it reads the whole document) and then filtered locally while the user types. Opening a 100 000 line file,
jumping to its end and typing at several places lexes each line once.

The tests: `t240` typing / selecting / undo / clipboard / multiple cursors, `t241` mouse, `t242` drawing (pixel checks of every highlight, wrap,
guides, two themes), `t243` 100 000 lines and a 100 000 character line, `t244` completion, `t245` the Look (nine themes, fonts, settings),
`t246` file tree on a temporary project, `t247` tab bar, `t248` find / replace / go to line, `t249` status bar and outline, `t250` output pane
and a real build job, `t251` terminal pane, `t252` colour picker, `t253` theme editor, `t254` settings dialog, `t255` dock, `t256` commands and
palette, `t257` the whole `codedemo` application driven like a user (open, edit, save, find, palette, build with errors, jump, close with a
question), `t258` random input with invariants and undo, `t259` columns of odd characters against `acode`, shared documents, CRLF saving. Added after the review: `t260` the find bar follows a tab
switch / a closed tab, `t261` fonts that cannot be used (no height, damaged) and odd fonts, `t262` completion in big files (linear time, the
rescan rule, duplicates, order), `t263` dialogs that are opened and closed leave nothing behind (documents, Look users, `onClosed`),
`t264` escape sequences and colour runs after UTF-8 in the output view, `t265` key values that are not text, the tab wheel, multi-letter
type-ahead, `t266` the terminal pane collects its programs (no zombies), `t267` small windows (the dock, the find bar, the demo).
All of them run the display server inside the test (Headless backend), type and click through it, and compare pixels and checksums; they pass on
the five targets (the ones that start processes print "processes can be started: 0" on Windows: `.out.windows`).

Known limitations of the GUI widgets (in addition to section 12): no code folding or minimap; word wrap breaks at a column; two editors on one
`Doc` share cursors; the font is the 13 pixel DejaVu (or the configured font file) and characters above Latin-1 are drawn as `?`; the menu bar
and the standard dialogs of `guix` are not themed; the completion candidates come from `asyntax.Completer` (words, symbols, keywords: no type
information); `FileTree` deletes files and empty folders only; the terminal pane needs a pseudo terminal (Linux and Android).

