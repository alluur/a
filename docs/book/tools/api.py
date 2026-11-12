#!/usr/bin/env python3
"""Generate the library reference of the book (Markdown) from the sources in lib/*.a.

  api.py [--lib DIR] [-o FILE]

For every module: the header comment of the file, then every `public` declaration with the comment that precedes it (or follows it on the
same line): functions, constants, variables, enums, structs and classes with their public members. The output has one `## name {#api-name}`
section per module, so chapters can link to `#api-name`.  Nothing is invented: the text is what the source says.
"""
import argparse, glob, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(HERE, "..", "..", "..", "lib")


def strip_code(line, in_block):
    """Return (code part of the line without comments, strings emptied; trailing // comment; still inside a /* block)."""
    out, i, n, comment = [], 0, len(line), ""
    while i < n:
        if in_block:
            j = line.find("*/", i)
            if j < 0:
                return "".join(out), comment, True
            i, in_block = j + 2, False
            continue
        c = line[i]
        if c == "/" and line[i:i + 2] == "//":
            comment = line[i + 2:].strip()
            break
        if c == "/" and line[i:i + 2] == "/*":
            in_block = True
            i += 2
            continue
        if c in "\"'":
            q, j = c, i + 1
            while j < n and line[j] != q:
                j += 2 if line[j] == "\\" else 1
            out.append(q + q)
            i = j + 1
            continue
        out.append(c)
        i += 1
    return "".join(out), comment, in_block


def header_text(lines):
    """The leading comment block of the file as (summary, markdown body)."""
    block = []
    for ln in lines:
        s = ln.strip()
        if not s.startswith("//"):
            if s == "" and not block:
                continue
            break
        block.append(ln.rstrip("\n")[ln.index("//") + 2:])
    block = [b for b in block if not re.fullmatch(r"\s*=+\s*", b)]
    if not block:
        return "", ""
    first = block[0].strip()
    m = re.match(r"(\S+)\s+-+\s+(.*?)(\s{2,}(?:import|#include)\b.*)?$", first)
    summary = (m.group(2).strip() if m else first)
    if m is None:
        m2 = re.match(r"(.*?)(\s{2,}(?:import)\b.*)$", first)
        summary = m2.group(1).strip() if m2 else first
    body = block[1:]
    out, code, par = [], [], []

    def flush_par():
        if par:
            out.append(md_text(" ".join(p.strip() for p in par)))
            out.append("")
            par.clear()

    def flush_code():
        if code:
            pad = min(len(c) - len(c.lstrip()) for c in code if c.strip())
            out.append("```a")
            out.extend(c[pad:].rstrip() for c in code)
            out.append("```")
            out.append("")
            code.clear()

    for b in body:
        if b.strip() == "":
            if code:
                code.append("")
            else:
                flush_par()
            continue
        indent = len(b) - len(b.lstrip())
        if indent >= 4:
            flush_par()
            code.append(b)
        else:
            while code and code[-1] == "":
                code.pop()
            flush_code()
            par.append(b)
    while code and code[-1] == "":
        code.pop()
    flush_code()
    flush_par()
    return summary, "\n".join(out).strip()


DECL = re.compile(r"^\s*public\b(.*)$")


def parse(path):
    lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
    summary, body = header_text(lines)
    items, depth, in_block = [], 0, False
    pending = []              # comment lines directly above
    cls = None                # (name, depth at which the class body is)
    i = 0
    while i < len(lines):
        raw = lines[i]
        code, trailing, in_block_next = strip_code(raw, in_block)
        stripped = raw.strip()
        if not in_block and stripped.startswith("//"):
            pending.append(stripped[2:].strip())
            i += 1
            continue
        if not in_block and stripped == "":
            pending = []
            i += 1
            continue
        m = DECL.match(code) if not in_block else None
        take = False
        if m and (depth == 0 or (cls and depth == cls[1])):
            take = True
        if take:
            # gather the whole signature: up to the first { or ; (or = for variables) at paren depth 0
            sig, j, par, done, cm, tr = "", i, 0, False, in_block, trailing
            while j < len(lines) and not done:
                c, t, cm = strip_code(lines[j], cm if j > i else in_block)
                if j > i and t and not tr:
                    tr = t
                for k, ch in enumerate(c):
                    if ch == "(":
                        par += 1
                    elif ch == ")":
                        par -= 1
                    if par == 0 and ch in "{;":
                        sig += c[:k]
                        done = True
                        break
                else:
                    sig += c + " "
                if done:
                    break
                j += 1
                if j - i > 12:
                    break
            sig = re.sub(r"\s+", " ", sig).strip()
            sig = re.sub(r"^public\s+", "", sig)
            desc = " ".join(pending).strip() or tr
            kind = "var"
            head = sig.split("=")[0].strip() if "(" not in sig.split("=")[0] else sig
            if re.match(r"(abstract\s+|final\s+)?class\b", sig):
                kind = "class"
            elif re.match(r"struct\b", sig):
                kind = "struct"
            elif re.match(r"enum\b", sig):
                kind = "enum"
            elif re.match(r"typedef\b", sig):
                kind = "typedef"
            elif re.match(r"const\b", sig):
                kind = "const"
            elif "(" in head and not head.startswith("func"):
                kind = "func"
            if kind == "func" or kind == "typedef":
                sig = sig.split("{")[0].strip()
            if kind in ("var", "const") and "=" in sig:
                left, _, right = sig.partition("=")
                sig = left.strip() + " = " + (right.strip() if len(right.strip()) <= 70 else right.strip()[:67] + "...")
            entry = {"kind": kind, "sig": sig, "desc": desc, "member": bool(cls and depth == cls[1]), "cls": cls[0] if cls else None}
            if kind == "enum":
                # the constants: the text between { and }
                body_txt, k, cm2, d2 = "", i, in_block, 0
                while k < len(lines):
                    c, t, cm2 = strip_code(lines[k], cm2)
                    body_txt += c + " "
                    d2 += c.count("{") - c.count("}")
                    if d2 <= 0 and "{" in body_txt:
                        break
                    k += 1
                mm = re.search(r"\{(.*)\}", body_txt)
                entry["values"] = re.sub(r"\s+", " ", mm.group(1)).strip() if mm else ""
            items.append(entry)
            if kind in ("class", "struct") and "{" in (code + "".join(lines[i + 1:i + 2])) or kind in ("class", "struct"):
                nm = re.match(r"(?:abstract\s+|final\s+)?(?:class|struct)\s+(\w+)", sig)
                cls = (nm.group(1) if nm else "?", depth + 1)
        pending = []
        # braces
        for ch in code:
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if cls and depth < cls[1]:
                    cls = None
        in_block = in_block_next
        i += 1
    return summary, body, items


def md_escape_inline(s):
    return s.replace("|", "\\|")


def md_text(s):
    """Comment text from the source is plain text, not Markdown: escape what Markdown would act on."""
    for ch in ("\\", "<", ">", "*", "_", "[", "]", "`", "|", "#"):
        s = s.replace(ch, "\\" + ch)
    return s


def render(modname, summary, body, items):
    out = ["## %s {#api-%s}" % (modname, modname), ""]
    if summary:
        out += ["*%s*" % md_text(summary.rstrip(".")) + ".", ""]
    out += ["`import %s;`" % modname, ""]
    if body:
        out += [body, ""]
    groups = [("Constants and variables", ("const", "var"), False), ("Types", ("enum", "typedef"), False),
              ("Functions", ("func",), False)]
    top = [e for e in items if not e["member"]]
    n_shown = 0
    for title, kinds, _ in groups:
        sel = [e for e in top if e["kind"] in kinds]
        if not sel:
            continue
        out += ["### %s" % title, ""]
        out += entries_md(sel)
        n_shown += len(sel)
    classes = [e for e in top if e["kind"] in ("class", "struct")]
    for c in classes:
        n_shown += 1
        out += ["### %s %s" % (c["kind"], re.sub(r"^(?:abstract |final )?(?:class|struct) ", "", c["sig"]).replace(" ", " ")), ""]
        if c["desc"]:
            out += [md_text(c["desc"]), ""]
        cname = re.match(r"(?:abstract\s+|final\s+)?(?:class|struct)\s+(\w+)", c["sig"]).group(1)
        mem = [e for e in items if e["member"] and e["cls"] == cname]
        out += entries_md(mem)
        n_shown += len(mem)
    return "\n".join(out), n_shown


def entry_md(e):
    """Described entries become a definition (term + text); undescribed ones are gathered by the caller into a code block."""
    s = "`%s`" % e["sig"].replace("`", "'")
    if e["kind"] == "enum" and e.get("values"):
        s += " — `{ %s }`" % e["values"].replace("`", "'")
    return [s, ":   " + md_text(e["desc"]), ""]


def sig_line(e):
    t = e["sig"]
    if e["kind"] == "enum" and e.get("values"):
        t += " { %s }" % e["values"]
    return t + ";"


def entries_md(entries):
    out, bare = [], []

    def flush():
        if bare:
            out.extend(["```a"] + bare + ["```", ""])
            bare.clear()

    for e in entries:
        if e["desc"]:
            flush()
            out.extend(entry_md(e))
        else:
            bare.append(sig_line(e))
    flush()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lib", default=LIB)
    ap.add_argument("-o", "--output")
    a = ap.parse_args()
    parts, index, total = [], [], 0
    for path in sorted(glob.glob(os.path.join(a.lib, "*.a"))):
        name = os.path.basename(path)[:-2]
        summary, body, items = parse(path)
        md, n = render(name, summary, body, items)
        total += n
        parts.append(md)
        index.append((name, summary))
    head = ["# Library reference {#chap-api}", "",
            "Every module of the standard library, generated from the source files in `lib/`: the header comment of each file, and every `public` "
            "function, constant, type and class member with the comment the author wrote next to it. %d modules, %d declarations. "
            "A declaration that says *(no description in the source)* has none yet; the name and the signature are still exact." % (len(parts), total), "",
            "| Module | Purpose |", "|---|---|"]
    for name, summary in index:
        head.append("| [`%s`](#api-%s) | %s |" % (name, name, md_escape_inline(summary.rstrip(".")) if summary else ""))
    head.append("")
    text = "\n".join(head) + "\n\n" + "\n\n".join(parts) + "\n"
    if a.output:
        os.makedirs(os.path.dirname(os.path.abspath(a.output)), exist_ok=True)
        open(a.output, "w", encoding="utf-8").write(text)
    else:
        sys.stdout.write(text)
    sys.stderr.write("api: %d modules, %d declarations\n" % (len(parts), total))


if __name__ == "__main__":
    main()
