#!/usr/bin/env python3
"""Build "The A Programming Language": an Aytict-branded HTML site and an EPUB 3 book from docs/book/.

  build.py [--out DIR] [--epub FILE] [--html DIR] [--only html|epub|all] [--code N] [--release TYPE] [--lint]

Pipeline: chapters.txt -> text of every chapter (hand written src/*.md, the reference docs of the repository, the API reference that
tools/api.py generates from lib/*.a) -> {{sample}} / {{shot}} / {{screen}} directives become listings taken from files that were
compiled and run (samples/) -> pandoc (commonmark_x) to its JSON syntax tree -> this script: unique ids, links between chapters,
syntax highlighting (tools/hl.py), heading numbers -> pandoc writes the HTML pages (wrapped in the Aytict template) and the EPUB.
Needs: python3, pandoc 3.x.  Nothing else (no network).
"""
import argparse, datetime, html, json, os, re, shutil, subprocess, sys, uuid

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import hl  # noqa: E402

BOOK = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(BOOK))
SAMPLES = os.path.join(BOOK, "samples")
SHOTS = os.path.join(BOOK, "shots")
BRAND = os.path.join(BOOK, "brand")
READER = "commonmark_x-smart-tex_math_dollars"

TITLE = "The A Programming Language"
SUBTITLE = "Language guide, compiler, standard library and GUI programming"
SITE = "https://aytict.fi"
TAGLINE = "Modern digital solutions, built on Finnish reliability."

errors, warnings = [], []


def err(msg):
    errors.append(msg)
    sys.stderr.write("ERROR: %s\n" % msg)


def warn(msg):
    warnings.append(msg)
    sys.stderr.write("warning: %s\n" % msg)


# ---------------------------------------------------------------------------------------------------------------- version
def version_info():
    t = open(os.path.join(REPO, "src", "defs.inc"), encoding="utf-8").read()
    name = re.search(r'%define\s+VERSION_NAME\s+"([^"]*)"', t).group(1)
    code = re.search(r"%define\s+VERSION_CODE\s+(\d+)", t).group(1)
    return name, code


# ---------------------------------------------------------------------------------------------------------------- chapters
class Chapter:
    def __init__(self, kind, path, slug, number, part):
        self.kind, self.path, self.slug, self.number, self.part = kind, path, slug, number, part
        self.title = ""
        self.ast = []          # list of blocks
        self.ids = {}          # original id -> final id
        self.headings = []     # (level, final id, text)
        self.text = ""
        self.html = ""
        self.fname = slug + ".html"


def read_chapters():
    chapters, part, n, letter = [], None, 0, 0
    parts = []
    for raw in open(os.path.join(BOOK, "chapters.txt"), encoding="utf-8"):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        kw, _, rest = line.partition(" ")
        rest = rest.strip()
        if kw == "part":
            part = {"title": rest, "chapters": []}
            parts.append(part)
        elif kw in ("chapter", "appendix"):
            path = rest.split()[0]
            m = re.search(r"slug=(\S+)", rest)
            if kw == "chapter":
                n += 1
                num = str(n)
            else:
                letter += 1
                num = chr(64 + letter)
            stem = os.path.splitext(os.path.basename(path.replace("gen:", "")))[0]
            slug = m.group(1) if m else re.sub(r"^\d+-", "", stem).lower()
            if part is None:
                part = {"title": "", "chapters": []}
                parts.append(part)
            c = Chapter(kw, path, slug, num, part)
            part["chapters"].append(c)
            chapters.append(c)
        else:
            err("chapters.txt: unknown line: " + line)
    return chapters, parts


def chapter_source(c, gen_dir):
    if c.path.startswith("gen:"):
        return os.path.join(gen_dir, c.path[4:] + ".md")
    return os.path.normpath(os.path.join(BOOK, c.path))


# ---------------------------------------------------------------------------------------------------------------- directives
DIRECTIVE = re.compile(r"^\{\{\s*(sample|shot|screen)\s+([A-Za-z0-9_./-]+)(?:\s+(src))?\s*\}\}\s*$")


def fence_for(text):
    n = 3
    for m in re.finditer(r"`{3,}", text):
        n = max(n, len(m.group()) + 1)
    return "`" * n


def sample_files(name):
    d = os.path.join(SAMPLES, name)
    if os.path.isdir(d):
        main = os.path.join(d, "main.a")
        others = sorted(f for f in os.listdir(d) if f.endswith(".a") and f != "main.a")
        return main, [os.path.join(d, f) for f in others], os.path.join(d, "main.out")
    p = os.path.join(SAMPLES, name + ".a")
    return p, [], os.path.join(SAMPLES, name + ".out")


def sample_meta(path):
    meta, title = {}, ""
    with open(path, encoding="utf-8", errors="replace") as f:
        for i, line in enumerate(f):
            if i == 0 and line.startswith("//") and "book:" not in line:
                title = line[2:].strip()
            m = re.match(r"\s*//\s*book:\s*(.*)$", line)
            if m:
                for item in m.group(1).split():
                    k, _, v = item.partition("=")
                    meta[k] = v or True
            if i > 12:
                break
    return meta, title


def listing(title, relname, code, lang="a"):
    f = fence_for(code)
    cap = html.escape(title) if title else ""
    out = [":::: listing", "::: ltitle", "%s[%s]{.lfile}" % (cap + " " if cap else "", relname), ":::", "", f + lang, code.rstrip("\n"), f, "::::", ""]
    return out


def expand_directives(text, chapter_name):
    out = []
    for line in text.split("\n"):
        m = DIRECTIVE.match(line.strip())
        if not m:
            out.append(line)
            continue
        kind, name, flag = m.group(1), m.group(2), m.group(3)
        if kind == "sample":
            main, others, outp = sample_files(name)
            if not os.path.exists(main):
                err("%s: sample %s does not exist" % (chapter_name, name))
                out.append("**MISSING SAMPLE %s**" % name)
                continue
            meta, title = sample_meta(main)
            code = open(main, encoding="utf-8", errors="replace").read()
            out += [""] + listing(title, name + (".a" if not os.path.isdir(os.path.join(SAMPLES, name)) else "/main.a"), code)
            for o in others:
                out += listing("", os.path.relpath(o, SAMPLES), open(o, encoding="utf-8", errors="replace").read())
            if flag != "src" and not meta.get("compile-only") and not meta.get("gui"):
                if os.path.exists(outp):
                    got = open(outp, encoding="utf-8", errors="replace", newline="").read().replace("\r\n", "\n").replace("\r", "")
                    if got.strip():
                        f = fence_for(got)
                        out += [":::: output", "::: ltitle", "Output", ":::", "", f + "text", got.rstrip("\n"), f, "::::", ""]
                else:
                    err("%s: sample %s has no recorded output (%s)" % (chapter_name, name, os.path.relpath(outp, SAMPLES)))
        elif kind == "shot":
            png = os.path.join(SHOTS, name.replace("/", "-") + ".png")
            if not os.path.exists(png):
                err("%s: screenshot %s does not exist" % (chapter_name, os.path.relpath(png, BOOK)))
                continue
            main = sample_files(name)[0]
            title = sample_meta(main)[1] if os.path.exists(main) else name
            out += ["", "::: shot", "![%s](%s)" % (title or name, png), "", "*%s*" % (title or name), ":::", ""]
        elif kind == "screen":
            scr = os.path.join(SAMPLES, name + ".screen")
            if not os.path.exists(scr):
                err("%s: terminal screen %s does not exist" % (chapter_name, name))
                continue
            got = open(scr, encoding="utf-8", errors="replace").read()
            f = fence_for(got)
            out += ["", ":::: screen", "::: ltitle", "Screen (80 x 24 terminal)", ":::", "", f + "text", got.rstrip("\n"), f, "::::", ""]
    return "\n".join(out)


# ---------------------------------------------------------------------------------------------------------------- sample index
def all_samples():
    """[(name, main file)] of every sample under samples/."""
    out = []
    for root, dirs, files in os.walk(SAMPLES):
        dirs.sort()
        rel = os.path.relpath(root, SAMPLES)
        if rel != "." and os.path.exists(os.path.join(root, "main.a")):
            out.append((rel, os.path.join(root, "main.a")))
            dirs[:] = []
            continue
        for f in sorted(files):
            if f.endswith(".a"):
                out.append((os.path.join(rel, f[:-2]) if rel != "." else f[:-2], os.path.join(root, f)))
    return out


def gen_samples_index(chapters_all, gen_dir):
    """Appendix: every sample, the chapter that shows it, and for every library module the samples that import it (a coverage report)."""
    used = {}                                        # sample name -> chapter
    for c in chapters_all:
        src = os.path.join(BOOK, c.path) if not c.path.startswith("gen:") else None
        if not src or not os.path.exists(src):
            continue
        for line in open(src, encoding="utf-8"):
            m = DIRECTIVE.match(line.strip())
            if m and m.group(1) == "sample":
                used.setdefault(m.group(2), c)
    libdir = os.path.join(REPO, "lib")
    modules = sorted(f[:-2] for f in os.listdir(libdir) if f.endswith(".a"))
    clib_members = set(re.findall(r"^\s*import\s+(\w+)\s*;", open(os.path.join(libdir, "clib.a"), encoding="utf-8").read(), re.M)) if os.path.exists(os.path.join(libdir, "clib.a")) else set()
    by_module = {m: [] for m in modules}
    rows = []
    for name, main in all_samples():
        meta, title = sample_meta(main)
        text = open(main, encoding="utf-8", errors="replace").read()
        imports = set(re.findall(r"^\s*import\s+([A-Za-z0-9_]+)\s*;", text, re.M))
        if "clib" in imports:
            imports |= clib_members
        for d in os.path.dirname(main), :
            for f in os.listdir(d) if os.path.isfile(os.path.join(d, "main.a")) and d != SAMPLES else []:
                if f.endswith(".a") and f != "main.a":
                    imports |= set(re.findall(r"^\s*import\s+([A-Za-z0-9_]+)\s*;", open(os.path.join(d, f), encoding="utf-8", errors="replace").read(), re.M))
        kind = "window" if meta.get("gui") else ("terminal" if meta.get("tui") else ("compiled" if meta.get("compile-only") else "run"))
        ch = used.get(name)
        rows.append((name, title or name, kind, ch))
        for m in imports:
            if m in by_module:
                by_module[m].append((name, ch))
    nsamples = len(rows)
    lines = ["# Code sample index {#chap-samples}", "",
             "The book contains **%d code samples**. Each one was compiled for all targets and (except the programs that need a window, a terminal or a network) run when the book was built; "
             "the output shown under a listing is what it printed. *run* means compiled and executed, *window* a graphical program that was photographed, "
             "*terminal* a program that was run in a pseudo terminal, *compiled* a program that was built and checked for every target but not run." % nsamples, "",
             "## Which samples use which module", "", "| Module | Samples |", "|---|---|"]
    missing = []
    for m in modules:
        lst = by_module[m]
        if not lst and m == "std":
            lines.insert(lines.index("| Module | Samples |"), "(`std`, the prelude with `print`, `strlen`, `rand` ..., is imported by every program, so it is not listed.)\n")
            continue
        if not lst:
            missing.append(m)
            continue
        names = []
        for n, ch in sorted(lst)[:8]:
            names.append("[`%s`](#chap-%s)" % (n, ch.slug) if ch else "`%s`" % n)
        more = " and %d more" % (len(lst) - 8) if len(lst) > 8 else ""
        lines.append("| [`%s`](#api-%s) | %s%s |" % (m, m, ", ".join(names), more))
    if missing:
        lines += ["", "Modules without a sample of their own in this book (they are used through the modules above, or are internal parts of bigger ones): " + ", ".join("`%s`" % m for m in missing) + ".", ""]
    lines += ["", "## All samples", "", "| Sample | What it shows | Kind | Where |", "|---|---|---|---|"]
    for name, title, kind, ch in rows:
        lines.append("| `%s` | %s | %s | %s |" % (name, title.replace("|", "\\|"), kind, "[%s](#chap-%s)" % (ch.title.replace("|", "\\|"), ch.slug) if ch else "(not in a chapter)"))
    lines.append("")
    orphans = [n for n, t, k, c in rows if c is None]
    sys.stderr.write("samples: %d, modules without a sample: %d, samples not in any chapter: %d\n" % (nsamples, len(missing), len(orphans)))
    if missing:
        sys.stderr.write("  no sample for: %s\n" % " ".join(missing))
    open(os.path.join(gen_dir, "samples.md"), "w", encoding="utf-8").write("\n".join(lines))


# ---------------------------------------------------------------------------------------------------------------- pandoc / AST
def pandoc_json(markdown_text, name):
    r = subprocess.run(["pandoc", "-f", READER, "-t", "json"], input=markdown_text.encode("utf-8"), capture_output=True)
    if r.returncode != 0:
        err("pandoc failed on %s: %s" % (name, r.stderr.decode()[:500]))
        return {"blocks": []}
    return json.loads(r.stdout)


def plain(node):
    """Plain text of an inline / block structure."""
    if isinstance(node, list):
        return "".join(plain(x) for x in node)
    if not isinstance(node, dict):
        return ""
    t, c = node.get("t"), node.get("c")
    if t == "Str":
        return c
    if t in ("Space", "SoftBreak", "LineBreak"):
        return " "
    if t == "Code":
        return c[1]
    if t in ("Link", "Image", "Span", "Div", "Quoted", "OrderedList"):
        return plain(c[1])
    if t in ("CodeBlock", "RawBlock", "RawInline", "Math", "Table", "Note"):
        return ""
    return plain(c)


def inl(text):
    """A plain string as a list of pandoc inlines."""
    out = []
    for i, w in enumerate(text.split()):
        if i:
            out.append({"t": "Space"})
        out.append({"t": "Str", "c": w})
    return out


def slugify(s):
    s = re.sub(r"[^\w\s-]", "", s.lower(), flags=re.U)
    return re.sub(r"[\s_]+", "-", s.strip()).strip("-")


def walk_blocks(blocks, fn):
    """Call fn on every node (dict) in the tree, depth first, allowing in-place modification."""
    if isinstance(blocks, list):
        for b in blocks:
            walk_blocks(b, fn)
    elif isinstance(blocks, dict):
        fn(blocks)
        walk_blocks(blocks.get("c"), fn)


def transform(node, fn):
    """Rebuild the tree; fn(dict) may return a replacement dict (or None to keep it)."""
    if isinstance(node, list):
        return [transform(x, fn) for x in node]
    if isinstance(node, dict):
        if "t" in node:
            r = fn(node)
            if r is not None:
                node = r
        if "c" in node:
            node = dict(node)
            node["c"] = transform(node["c"], fn)
        return node
    return node


GLOBAL_PREFIXES = ("api-", "chap-")


SAFE_TAGS = {"code", "kbd", "br", "sup", "sub", "span", "b", "i", "em", "strong", "a", "img", "hr", "details", "summary", "p", "div", "small", "mark", "var", "samp"}


def neutralise_raw_html(blocks, chapter):
    """A stray "<name>" in the text is read as an HTML tag by Markdown and is never closed: that breaks XHTML. Keep only known tags."""
    def fn(node):
        if node["t"] == "RawInline" and node["c"][0] == "html":
            m = re.match(r"</?\s*([A-Za-z][A-Za-z0-9-]*)", node["c"][1])
            if m and m.group(1).lower() not in SAFE_TAGS:
                warn("%s: %s is not a known HTML tag, shown as text" % (chapter, node["c"][1][:40]))
                return {"t": "Str", "c": node["c"][1]}
        return None
    return transform(blocks, fn)


def prepare_chapter(c, text, shot_dir_note):
    ast = pandoc_json(text, c.path)
    blocks = neutralise_raw_html(ast["blocks"], c.path)
    # the chapter title: the first level 1 heading; extra level 1 headings become level 2
    seen_h1 = False
    for b in blocks:
        if b["t"] == "Header" and b["c"][0] == 1:
            if not seen_h1:
                seen_h1 = True
                c.title = plain(b["c"][2]).strip()
                if not b["c"][1][0]:
                    b["c"][1][0] = "chap-" + c.slug
                elif not b["c"][1][0].startswith("chap-"):
                    b["c"][1][0] = "chap-" + c.slug
            else:
                b["c"][0] = 2
    if not seen_h1:
        err("%s has no level 1 heading" % c.path)
    c.ast = blocks
    # ids: every id becomes unique over the whole book (slug-id), except the global ones (api-*, chap-*)
    def idmap(node):
        if node["t"] in ("Header", "Div", "Span", "CodeBlock"):
            attr = node["c"][1] if node["t"] == "Header" else node["c"][0]
            old = attr[0]
            if old:
                new = old if old.startswith(GLOBAL_PREFIXES) else "%s-%s" % (c.slug, old)
                c.ids[old] = new
                attr[0] = new
    walk_blocks(blocks, idmap)
    # headings for the table of contents and the search index
    for b in blocks:
        pass
    def collect(node):
        if node["t"] == "Header":
            lvl, attr, inl = node["c"]
            c.headings.append((lvl, attr[0], plain(inl).strip()))
    walk_blocks(blocks, collect)


def highlight_blocks(c):
    def fn(node):
        if node["t"] == "CodeBlock":
            attr, code = node["c"]
            lang = attr[1][0] if attr[1] else ""
            body = hl.highlight(lang, code.rstrip("\n"))
            cls = "language-%s" % lang if lang else "plain"
            return {"t": "RawBlock", "c": ["html", '<pre class="%s"><code>%s\n</code></pre>' % (cls, body)]}
        return None
    c.ast = transform(c.ast, fn)


def number_headings(c, shift):
    """Put the chapter number in front of the level 1 heading (a span, so styles can treat it) and shift levels for the EPUB.
    The EPUB (shift 1) gets a short label ("3." / "Appendix A.") because it ends up in the table of contents; the web page "Chapter 3"."""
    first = True
    for b in c.ast:
        if b["t"] == "Header":
            if b["c"][0] == 1 and first:
                first = False
                if shift:
                    label = ("%s." % c.number) if c.kind == "chapter" else ("Appendix %s." % c.number)
                else:
                    label = ("Chapter %s" % c.number) if c.kind == "chapter" else ("Appendix %s" % c.number)
                b["c"][2] = [{"t": "Span", "c": [["", ["chno"], []], [{"t": "Str", "c": label}]]}, {"t": "Space"}] + b["c"][2]
            b["c"][0] += shift
    return None


def doc_slug_map(chapters):
    m = {}
    for c in chapters:
        if c.path.endswith(".md") and not c.path.startswith("gen:"):
            m[os.path.basename(c.path)] = c
    return m


def resolve_links(c, chapters, docmap, mode, id_owner):
    cur = {orig: final for orig, final in c.ids.items()}

    def target_page(other):
        return "" if (mode == "epub" or other is c) else other.fname

    def fn(node):
        if node["t"] != "Link":
            return None
        attr, inl, (url, title) = node["c"]
        new = None
        if url.startswith("#"):
            frag = url[1:]
            if frag in cur:
                new = "#" + cur[frag]
            elif frag.startswith(GLOBAL_PREFIXES) and frag in id_owner:
                new = target_page(id_owner[frag]) + "#" + frag
            elif frag in id_owner:
                new = target_page(id_owner[frag]) + "#" + frag
            else:
                warn("%s: link to #%s has no target" % (c.path, frag))
                new = ""
        elif re.match(r"^[a-z]+:", url):
            return None
        else:
            base, _, frag = url.partition("#")
            other = docmap.get(os.path.basename(base)) if base.endswith(".md") else None
            if other is not None:
                if frag:
                    final = other.ids.get(frag) or (frag if frag in id_owner else None)
                    if final is None:
                        warn("%s: link to %s#%s has no target" % (c.path, base, frag))
                        new = target_page(other) + "#chap-" + other.slug
                    else:
                        new = target_page(other) + "#" + final
                else:
                    new = target_page(other) + "#chap-" + other.slug
            else:
                new = ""      # a file of the repository: keep the words, drop the link
        if new == "":
            return {"t": "Span", "c": [["", ["repo"], []], inl]}
        node = dict(node)
        node["c"] = [attr, inl, [new, title]]
        return node

    c.ast = transform(c.ast, fn)


def absolutize_images(c):
    def fn(node):
        if node["t"] == "Image":
            attr, inl, (url, title) = node["c"]
            if not os.path.isabs(url):
                url = os.path.normpath(os.path.join(BOOK, url))
            if not os.path.exists(url):
                err("%s: image %s not found" % (c.path, url))
            node = dict(node)
            node["c"] = [attr, inl, [url, title]]
            return node
        return None
    c.ast = transform(c.ast, fn)


# ---------------------------------------------------------------------------------------------------------------- html
def pandoc_html(blocks):
    doc = {"pandoc-api-version": [1, 23, 1], "meta": {}, "blocks": blocks}
    r = subprocess.run(["pandoc", "-f", "json", "-t", "html5", "--no-highlight", "--wrap=none"], input=json.dumps(doc).encode(), capture_output=True)
    if r.returncode != 0:
        err("pandoc html failed: " + r.stderr.decode()[:300])
    return r.stdout.decode("utf-8")


def post_html(h):
    # headings get a permalink anchor
    def anchor(m):
        return '<h%s id="%s"%s>%s<a class="hl" href="#%s" aria-label="Link to this section">#</a></h%s>' % (m.group(1), m.group(2), m.group(3), m.group(4), m.group(2), m.group(1))
    h = re.sub(r'<h([2-4]) id="([^"]+)"([^>]*)>(.*?)</h\1>', anchor, h, flags=re.S)
    # wide tables scroll on their own
    h = h.replace("<table", '<div class="tablewrap"><table').replace("</table>", "</table></div>")
    return h


PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>%(title)s · %(book)s · Aytict</title>
<meta name="description" content="%(desc)s">
<meta name="theme-color" content="#0b1b3a">
<link rel="icon" href="%(root)simg/logo.svg" type="image/svg+xml">
<link rel="stylesheet" href="%(root)scss/aytict.css">
<script>try{var t=localStorage.getItem("ayt-theme");if(t)document.documentElement.setAttribute("data-theme",t)}catch(e){}</script>
</head>
<body class="%(bodyclass)s">
<a class="skip" href="#main">Skip to the content</a>
<header class="top">
  <button class="menu-btn" id="menu" aria-label="Chapters" aria-expanded="false" aria-controls="side"><span></span></button>
  <a class="brand" href="%(root)sindex.html"><img src="%(root)simg/logo.svg" alt="" width="34" height="34"><span class="brand-name">Aytict<span class="fi">.fi</span></span><span class="brand-sep" aria-hidden="true"></span><span class="brand-doc">The A Programming Language</span></a>
  <div class="search"><input type="search" id="q" placeholder="Search the book" autocomplete="off" aria-label="Search the book"><ul id="results" hidden></ul></div>
  <button class="theme-btn" id="theme" aria-label="Switch between light and dark colours" title="Light / dark"><svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true"><path d="M12 3a9 9 0 1 0 9 9 7 7 0 0 1-9-9z" fill="currentColor"/></svg></button>
</header>
<div class="shell">
<nav class="side" id="side" aria-label="Chapters">%(nav)s</nav>
<main id="main">
<article class="chapter">
%(body)s
</article>
%(pager)s
</main>
<aside class="toc" aria-label="On this page">%(toc)s</aside>
</div>
<footer class="foot">
  <div><img src="%(root)simg/logo.svg" alt="" width="26" height="26"> <strong>Aytict</strong> · <a href="%(site)s">aytict.fi</a> · %(tagline)s</div>
  <div>A language %(ver)s (version code %(code)s) · built %(date)s</div>
</footer>
<script src="%(root)sjs/search-data.js"></script>
<script src="%(root)sjs/book.js"></script>
</body>
</html>
"""


def nav_html(parts, current, root=""):
    out = []
    for p in parts:
        is_cur = any(ch is current for ch in p["chapters"])
        out.append('<details class="part"%s><summary>%s</summary><ol>' % (" open" if is_cur or not p["title"] else "", html.escape(p["title"] or "Book")))
        for ch in p["chapters"]:
            label = ("%s" % ch.number) if ch.kind == "chapter" else ch.number
            out.append('<li%s><a href="%s%s"%s><span class="no">%s</span>%s</a></li>' % (
                ' class="cur"' if ch is current else "", root, ch.fname, ' aria-current="page"' if ch is current else "", html.escape(label), html.escape(ch.title)))
        out.append("</ol></details>")
    return "\n".join(out)


def toc_html(c):
    items = [(l, i, t) for (l, i, t) in c.headings if l in (2, 3)]
    if not items:
        return ""
    out = ['<div class="toc-title">On this page</div><ul>']
    for l, i, t in items:
        out.append('<li class="l%d"><a href="#%s">%s</a></li>' % (l, i, html.escape(re.sub(r"^class |^struct ", "", t))))
    out.append("</ul>")
    return "\n".join(out)


def pager_html(chapters, i):
    prev = chapters[i - 1] if i > 0 else None
    nxt = chapters[i + 1] if i + 1 < len(chapters) else None
    out = ['<nav class="pager" aria-label="Previous and next chapter">']
    out.append('<a class="prev" href="%s"><small>Previous</small>%s</a>' % (prev.fname, html.escape(prev.title)) if prev else "<span></span>")
    out.append('<a class="next" href="%s"><small>Next</small>%s</a>' % (nxt.fname, html.escape(nxt.title)) if nxt else "<span></span>")
    out.append("</nav>")
    return "\n".join(out)


def index_html(parts, chapters, ver, code, date, downloads):
    cards = []
    for p in parts:
        lis = "".join('<li><a href="%s"><span class="no">%s</span>%s</a></li>' % (ch.fname, ch.number, html.escape(ch.title)) for ch in p["chapters"])
        cards.append('<section class="card"><h2>%s</h2><ol>%s</ol></section>' % (html.escape(p["title"] or "Book"), lis))
    dl = "".join('<a class="btn %s" href="%s" download>%s</a>' % (cls, href, label) for (label, href, cls) in downloads)
    return """
<div class="hero">
  <img class="hero-logo" src="img/logo.svg" alt="Aytict" width="120" height="120">
  <div>
    <p class="eyebrow">Aytict · aytict.fi</p>
    <h1 class="hero-title">The A Programming Language</h1>
    <p class="hero-sub">%(sub)s. One small compiler, no C toolchain, native programs for Linux, Windows and Android on x86-64, ARM64, RISC-V and LoongArch.</p>
    <p class="hero-actions"><a class="btn primary" href="%(first)s">Start reading</a><a class="btn" href="%(ref)s">Library reference</a>%(dl)s</p>
    <p class="hero-meta">A compiler %(ver)s · version code %(code)s · %(date)s</p>
  </div>
</div>
<div class="cards">%(cards)s</div>
""" % {"sub": SUBTITLE, "first": chapters[0].fname, "ref": next((c.fname for c in chapters if c.slug == "api"), chapters[0].fname),
       "dl": dl, "ver": ver, "code": code, "date": date, "cards": "".join(cards)}


def search_entries(chapters):
    entries = []
    for c in chapters:
        sect_title, sect_id, buf = c.title, "chap-" + c.slug, []

        def flush():
            txt = re.sub(r"\s+", " ", " ".join(buf)).strip()
            entries.append({"t": sect_title, "c": c.title, "u": "%s#%s" % (c.fname, sect_id), "x": txt[:500]})
            buf.clear()
        for b in c.ast_plain:
            if b[0] == "h":
                flush()
                sect_title, sect_id = b[1], b[2]
            else:
                buf.append(b[1])
        flush()
    return entries


def plain_blocks(ast):
    """(kind, text[, id]) per top level block of the chapter, for the search index."""
    out = []
    for b in ast:
        if b["t"] == "Header":
            out.append(("h", plain(b["c"][2]).strip(), b["c"][1][0]))
        elif b["t"] in ("Para", "Plain"):
            out.append(("p", plain(b["c"])))
        elif b["t"] in ("BulletList", "OrderedList", "Div", "DefinitionList", "Table"):
            out.append(("p", plain(b["c"]) if b["t"] != "Table" else ""))
    return out


# ---------------------------------------------------------------------------------------------------------------- epub
def epub_metadata(ver, code, date):
    ident = "urn:uuid:" + str(uuid.uuid5(uuid.NAMESPACE_URL, "https://aytict.fi/a-lang/book/" + ver))
    return {"title": [{"type": "main", "text": TITLE}, {"type": "subtitle", "text": SUBTITLE}], "author": "Aytict", "publisher": "Aytict",
            "lang": "en", "date": date, "rights": "© 2026 Aytict. https://aytict.fi", "identifier": ident,
            "description": "The complete guide to the A programming language, its compiler (version %s, code %s), its standard library, networking and GUI programming. %s" % (ver, code, TAGLINE),
            "subject": ["programming languages", "compilers", "GUI programming"]}


def build_epub(chapters, parts, out_file, ver, code, date, workdir):
    blocks = []
    for p in parts:
        if p["title"]:
            blocks.append({"t": "Header", "c": [1, ["part-" + slugify(p["title"]), ["part"], []], inl(p["title"])]})
        for c in p["chapters"]:
            blocks.extend(c.epub_ast)
    doc = {"pandoc-api-version": [1, 23, 1], "meta": {}, "blocks": blocks}
    jpath = os.path.join(workdir, "book.json")
    json.dump(doc, open(jpath, "w"))
    meta = os.path.join(workdir, "epub-meta.yaml")
    with open(meta, "w", encoding="utf-8") as f:
        f.write("---\n" + json.dumps(epub_metadata(ver, code, date), ensure_ascii=False) + "\n---\n")
    cmd = ["pandoc", "-f", "json", "-t", "epub3", "--toc", "--toc-depth=3", "--split-level=2", "--css", os.path.join(BRAND, "epub.css"),
           "--metadata-file", meta, "--wrap=none"]
    cover = os.path.join(BRAND, "cover.png")
    if os.path.exists(cover):
        cmd += ["--epub-cover-image", cover]
    else:
        warn("no brand/cover.png: the EPUB has no cover image")
    cmd += ["-o", out_file, jpath]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        err("pandoc epub failed: " + r.stderr[:800])
    elif r.stderr.strip():
        for ln in r.stderr.strip().splitlines()[:8]:
            warn("pandoc: " + ln)


# ---------------------------------------------------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(REPO, "build", "book"))
    ap.add_argument("--html", help="directory of the HTML site (default OUT/html)")
    ap.add_argument("--epub", help="EPUB file (default OUT/a-book-CODE-RELEASE.epub)")
    ap.add_argument("--only", default="all", choices=["all", "html", "epub"])
    ap.add_argument("--code")
    ap.add_argument("--release", default="release")
    ap.add_argument("--lint", action="store_true", help="read everything and report problems, write nothing")
    ap.add_argument("--downloads", nargs="*", default=[], help="LABEL=FILE pairs offered on the title page (the files are copied into the site)")
    ap.add_argument("--link", nargs="*", default=[], help="LABEL=HREF pairs offered on the title page (a relative link, nothing is copied)")
    a = ap.parse_args()
    ver, code = version_info()
    code = a.code or code
    date = os.environ.get("BOOK_DATE") or datetime.date.today().isoformat()
    out = os.path.abspath(a.out)
    gen = os.path.join(out, "gen")
    os.makedirs(gen, exist_ok=True)
    work = os.path.join(out, "work")
    os.makedirs(work, exist_ok=True)

    # generated chapters
    r = subprocess.run([sys.executable, os.path.join(HERE, "api.py"), "-o", os.path.join(gen, "api.md")], capture_output=True, text=True)
    if r.returncode != 0:
        err("api.py failed: " + r.stderr[-500:])

    chapters, parts = read_chapters()
    gen_samples_index(chapters, gen)
    ok_chapters = []
    for c in chapters:
        src = chapter_source(c, gen)
        if not os.path.exists(src):
            warn("chapter file %s does not exist yet: skipped" % c.path)
            continue
        text = open(src, encoding="utf-8").read()
        text = expand_directives(text, c.path)
        prepare_chapter(c, text, None)
        ok_chapters.append(c)
    for p in parts:
        p["chapters"] = [c for c in p["chapters"] if c in ok_chapters]
    parts = [p for p in parts if p["chapters"]]
    chapters = ok_chapters
    # renumber after skipping missing ones
    n = l = 0
    for c in chapters:
        if c.kind == "chapter":
            n += 1
            c.number = str(n)
        else:
            l += 1
            c.number = chr(64 + l)
    id_owner = {}
    for c in chapters:
        for orig, final in c.ids.items():
            id_owner.setdefault(orig, c)
            id_owner.setdefault(final, c)
    docmap = doc_slug_map(chapters)
    for c in chapters:
        highlight_blocks(c)
        absolutize_images(c)
    # two variants of the tree: html (links to other pages) and epub (links inside one document, deeper headings)
    import copy
    base = {c.slug: copy.deepcopy(c.ast) for c in chapters}
    for c in chapters:
        c.ast = copy.deepcopy(base[c.slug])
        resolve_links(c, chapters, docmap, "epub", id_owner)
        number_headings(c, 1)
        c.epub_ast = c.ast
        c.ast = copy.deepcopy(base[c.slug])
        resolve_links(c, chapters, docmap, "html", id_owner)
        number_headings(c, 0)
        c.ast_plain = plain_blocks(c.ast)
    if a.lint:
        sys.stderr.write("lint: %d chapters, %d errors, %d warnings\n" % (len(chapters), len(errors), len(warnings)))
        return 1 if errors else 0

    epub_file = os.path.abspath(a.epub or os.path.join(out, "a-book-%s-%s.epub" % (code, a.release)))
    if a.only in ("all", "epub"):
        build_epub(chapters, parts, epub_file, ver, code, date, work)
    if a.only in ("all", "html"):
        site = os.path.abspath(a.html or os.path.join(out, "html"))
        if os.path.isdir(site):
            shutil.rmtree(site)
        for d in ("css", "js", "img", "shots"):
            os.makedirs(os.path.join(site, d))
        shutil.copy(os.path.join(BRAND, "aytict.css"), os.path.join(site, "css", "aytict.css"))
        shutil.copy(os.path.join(BRAND, "book.js"), os.path.join(site, "js", "book.js"))
        shutil.copy(os.path.join(BRAND, "logo.svg"), os.path.join(site, "img", "logo.svg"))
        downloads = []
        for item in a.downloads:
            label, _, f = item.partition("=")
            if os.path.exists(f):
                os.makedirs(os.path.join(site, "downloads"), exist_ok=True)
                shutil.copy(f, os.path.join(site, "downloads", os.path.basename(f)))
                downloads.append((label, "downloads/" + os.path.basename(f), ""))
        for item in a.link:
            label, _, href = item.partition("=")
            downloads.append((label, href, ""))
        # screenshots: rewrite the absolute image paths of the html tree
        shotnames = set()
        for i, c in enumerate(chapters):
            def fix(node):
                if node["t"] == "Image":
                    attr, inl, (url, title) = node["c"]
                    base_name = os.path.basename(url)
                    shotnames.add(url)
                    node = dict(node)
                    node["c"] = [attr, inl, ["shots/" + base_name, title]]
                    return node
                return None
            c.ast = transform(c.ast, fix)
        for u in shotnames:
            shutil.copy(u, os.path.join(site, "shots", os.path.basename(u)))
        for i, c in enumerate(chapters):
            body = post_html(pandoc_html(c.ast))
            page = PAGE % {"title": html.escape(c.title), "book": TITLE, "desc": html.escape(SUBTITLE), "root": "", "nav": nav_html(parts, c),
                           "body": body, "pager": pager_html(chapters, i), "toc": toc_html(c), "site": SITE, "tagline": TAGLINE,
                           "ver": ver, "code": code, "date": date, "bodyclass": "page"}
            open(os.path.join(site, c.fname), "w", encoding="utf-8").write(page)
        body = index_html(parts, chapters, ver, code, date, downloads)
        page = PAGE % {"title": "Home", "book": TITLE, "desc": html.escape(SUBTITLE), "root": "", "nav": nav_html(parts, None),
                       "body": body, "pager": "", "toc": "", "site": SITE, "tagline": TAGLINE, "ver": ver, "code": code, "date": date, "bodyclass": "home"}
        open(os.path.join(site, "index.html"), "w", encoding="utf-8").write(page)
        entries = search_entries(chapters)
        open(os.path.join(site, "js", "search-data.js"), "w", encoding="utf-8").write("window.BOOK_INDEX=" + json.dumps(entries, ensure_ascii=False) + ";\n")
        sys.stderr.write("html: %d pages in %s\n" % (len(chapters) + 1, site))
    sys.stderr.write("build: %d chapters, %d errors, %d warnings\n" % (len(chapters), len(errors), len(warnings)))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
