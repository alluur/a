# "The A Programming Language": the book

The book is written in Markdown and built into an Aytict-branded **HTML site** and an **EPUB 3** e-book. Every code listing in it comes from a sample program that is compiled and run by the build tools, so the book cannot show code that does not work.

## Build it

Needs `python3` and `pandoc` (3.x). Nothing else, no network.

```sh
make                 # the compiler, build/ac
make book            # the book:
                     #   build/book/html/                  the site (links to the EPUB next to it; goes into the Debian package)
                     #   dist/a-docs-1-release.zip         the same site as one file, with the EPUB as a download
                     #   dist/a-book-1-release.epub        the e-book
make book-samples    # compile and run every sample, compare with the recorded output
make deb             # dist/a-1-release.deb, with the book inside
```

Output names follow `{app_name}-{version-code}-{release-type}.{ext}`; `make book VERSION_CODE=2 RELEASE=debug` changes the middle and last part.

## Where things are

| Path | What |
|---|---|
| `chapters.txt` | the order of the chapters; a missing chapter file is skipped |
| `src/NN-name.md` | the chapters (the number is only for ordering, the book number is computed) |
| `../*.md` | the reference documents of the repository (`LANGUAGE.md`, `GUI.md` ...), included as reference chapters |
| `samples/GROUP/NAME.a` (+ `.out`, `.in`) | the verified code samples; a directory with `main.a` is a multi-file sample |
| `shots/` | screenshots of graphical samples, made by `tools/shots.py` |
| `brand/` | the Aytict look: `aytict.css`, `epub.css`, `logo.svg`, `cover.html` / `cover.png` |
| `tools/` | `build.py` (the build), `samples.py` (checker), `shots.py` (GUI screenshots), `tuishot.py` (terminal screens), `api.py` (library reference from `lib/*.a`), `check_site.py` and `check_epub.py` (validators), `hl.py` (syntax highlighting) |
| `NOTES-*.md` | what the authors found while writing: bugs of the compiler and library, errors in the older docs |
| `WRITING.md` | **the guide for authors**: sample format, directives, chapter structure, tone |

## Everyday commands

```sh
python3 docs/book/tools/samples.py --ac build/ac                 # all samples: compile, run, compare
python3 docs/book/tools/samples.py --ac build/ac --targets       # ... and compile each for all nine targets
python3 docs/book/tools/samples.py --ac build/ac --update lang/hello   # record the output of a new sample (read it afterwards!)
python3 docs/book/tools/build.py --lint                          # check chapters, directives and links, write nothing
python3 docs/book/tools/shots.py --ac build/ac gui/hello_window  # photograph a graphical sample
python3 docs/book/tools/check_site.py build/book/site            # every link of the site resolves
python3 docs/book/tools/check_epub.py dist/a-book-1-release.epub # structure of the EPUB
```

## Changing the look

All colours are variables at the top of `brand/aytict.css`; the logo is `brand/logo.svg`. To change the cover edit `brand/cover.html` and run `node docs/book/tools/cover.js` (needs the `playwright` package); the resulting `cover.png` is committed so the normal build needs no browser.

## After the language or the library changes

* The **library reference** (appendix) is generated from `lib/*.a` on every build: new public functions appear by themselves, the comment next to a declaration is its documentation.
* **Chapters** and **samples** are written by hand: add a sample under `samples/`, include it with `{{sample group/name}}` in the right chapter, run `make book-samples`.
* The **code sample index** (appendix) lists the modules that have no sample yet.
