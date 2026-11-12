#!/usr/bin/env python3
"""Syntax highlighting for the A book: A (and the C-like fences used in the old docs), shell, JSON, plain.

highlight(lang, text) -> html string for the inside of <code>...</code>.  Class names (see brand/aytict.css):
  k keyword   t type   c constant (true false null this)   n number   s string / char   cm comment
  pp preprocessor   f function call   d name being defined   b standard library function   o operator-ish (not coloured)
No dependencies; the same function highlights the HTML site and the EPUB.
"""
import html, re

KEYWORDS = set("""if else switch case default while do for foreach in break continue return struct class enum const static typedef
union asm defer goto extern public private protected virtual override final abstract super module import a_module a_import new sizeof
is as var interface static_assert operator""".split())
TYPES = set("""int long char byte bool void func int8 int16 int32 int64 uint8 uint16 uint32 uint64 size_t uintptr_t ssize_t intptr_t
ptrdiff_t short signed unsigned double float""".split())
CONSTS = set("true false null this NULL EOF stdin stdout stderr errno".split())
BUILTIN = set("""print println printInt printlnInt printChar printBool printHex eprint eprintln readChar readLine atoi strlen streq
strcmp strcpy strcat strdup memcpy memset indexOf startsWith intToStr isDigit isAlpha isUpper isLower isSpace toUpper toLower abs
min max srand rand exit alloc fileOpen fileRead fileWrite fileClose readFile writeFile input askInt confirm readAll parseInt format
printf printRepeat printColor clearScreen cursorTo isTerminal ansiInit argIndex hasArg argValue millis sleepMs getEnv fileExists
fileDelete makeDir endsWith find contains substr trim strUpper strLower streqi hexToStr malloc calloc realloc free qsort bsearch
setjmp longjmp va_arg va_count dadd dsub dmul ddiv itod dtoi dlit dtostr printfd sprintfd""".split())

TOKEN = re.compile(r"""
  (?P<cm>//[^\n]*|/\*.*?\*/)
 |(?P<pp>^[ \t]*\#[ \t]*[a-z]+[^\n]*)
 |(?P<s>"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')
 |(?P<n>0[xX][0-9a-fA-F_]+|0[bB][01_]+|\d[\d_]*)
 |(?P<id>[A-Za-z_][A-Za-z_0-9]*)
""", re.S | re.M | re.X)


def esc(t):
    return html.escape(t, quote=False)


def span(cls, t):
    return '<span class="%s">%s</span>' % (cls, esc(t))


def hl_a(text):
    out, pos, prev_kw = [], 0, ""
    for m in TOKEN.finditer(text):
        if m.start() > pos:
            out.append(esc(text[pos:m.start()]))
        kind, t = m.lastgroup, m.group()
        pos = m.end()
        if kind == "id":
            nxt = text[pos:pos + 1]
            rest = text[pos:].lstrip(" \t")
            if t in KEYWORDS:
                out.append(span("k", t)); prev_kw = t; continue
            if t in TYPES:
                out.append(span("t", t)); prev_kw = ""; continue
            if t in CONSTS:
                out.append(span("c", t)); prev_kw = ""; continue
            if prev_kw in ("class", "struct", "enum", "union", "module", "interface"):
                out.append(span("d", t)); prev_kw = ""; continue
            if t in BUILTIN and rest.startswith("("):
                out.append(span("b", t)); prev_kw = ""; continue
            if rest.startswith("("):
                out.append(span("f", t)); prev_kw = ""; continue
            out.append(esc(t)); prev_kw = ""
        else:
            out.append(span(kind, t))
            if kind != "cm":
                prev_kw = ""
    out.append(esc(text[pos:]))
    return "".join(out)


SH_TOKEN = re.compile(r"""
  (?P<cm>(?<![\w$])\#[^\n]*)
 |(?P<s>"(?:\\.|[^"\\])*"|'[^']*')
 |(?P<c>\$\{?[A-Za-z_][A-Za-z_0-9]*\}?|\$\(|\$[0-9?#@*])
 |(?P<t>(?<![\w-])--?[A-Za-z][\w-]*(?:=[^\s]*)?)
 |(?P<id>[A-Za-z_./~][\w./~+-]*)
""", re.X)


def hl_sh(text):
    out, pos, cmd = [], 0, True
    for m in SH_TOKEN.finditer(text):
        gap = text[pos:m.start()]
        if "\n" in gap or "|" in gap or ";" in gap or "&&" in gap or "||" in gap or "(" in gap:
            cmd = True
        if gap.strip() == "$" and gap.endswith(" ") and pos == 0:
            cmd = True
        out.append(esc(gap))
        kind, t = m.lastgroup, m.group()
        pos = m.end()
        if kind == "id":
            if cmd and "=" not in t:
                out.append(span("f", t)); cmd = False
            else:
                out.append(esc(t))
        else:
            out.append(span(kind, t))
            if kind != "cm":
                cmd = False
    out.append(esc(text[pos:]))
    # a leading "$ " prompt: grey, not part of the command
    return re.sub(r'(^|\n)\$ ', r'\1<span class="cm">$ </span>', "".join(out))


JSON_TOKEN = re.compile(r'(?P<s>"(?:\\.|[^"\\])*")|(?P<n>-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)|(?P<c>\b(?:true|false|null)\b)')


def hl_json(text):
    out, pos = [], 0
    for m in JSON_TOKEN.finditer(text):
        out.append(esc(text[pos:m.start()]))
        out.append(span(m.lastgroup, m.group()))
        pos = m.end()
    out.append(esc(text[pos:]))
    return "".join(out)


def highlight(lang, text):
    lang = (lang or "").lower()
    if lang in ("a", "c", "cpp", "h"):
        return hl_a(text)
    if lang in ("sh", "bash", "shell", "console", "zsh"):
        return hl_sh(text)
    if lang == "json":
        return hl_json(text)
    return esc(text)


if __name__ == "__main__":
    import sys
    print(highlight(sys.argv[1], sys.stdin.read()))
