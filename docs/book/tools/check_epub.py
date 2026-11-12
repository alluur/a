#!/usr/bin/env python3
"""Structural checks of an EPUB 3 file (a stand-in for EPUBCheck, which needs Java):

  check_epub.py BOOK.epub

* the container: `mimetype` first and stored, container.xml, the package document
* metadata: title, language, identifier, modified date, cover image
* the manifest: every item exists, every file of the archive is in the manifest, media types fit the extensions
* the spine: every itemref names a manifest item; the navigation document is there and lists existing files
* every XHTML file is well-formed XML, has a title and unique ids
* every internal link (href) and every image (src) resolves, including #fragments
Exit status 0 when nothing is wrong.
"""
import os, posixpath, sys, zipfile
import xml.etree.ElementTree as ET

NS = {"c": "urn:oasis:names:tc:opendocument:xmlns:container", "o": "http://www.idpf.org/2007/opf", "dc": "http://purl.org/dc/elements/1.1/",
      "h": "http://www.w3.org/1999/xhtml", "e": "http://www.idpf.org/2007/ops", "n": "http://www.daisy.org/z3986/2005/ncx/"}
TYPES = {".xhtml": "application/xhtml+xml", ".css": "text/css", ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".svg": "image/svg+xml",
         ".gif": "image/gif", ".ncx": "application/x-dtbncx+xml", ".ttf": "font/ttf", ".otf": "font/otf", ".woff": "font/woff", ".woff2": "font/woff2"}


def main(path):
    problems, notes = [], []
    z = zipfile.ZipFile(path)
    names = z.namelist()
    infos = z.infolist()
    if not infos or infos[0].filename != "mimetype":
        problems.append("the first entry must be `mimetype`")
    else:
        if infos[0].compress_type != 0:
            problems.append("`mimetype` must be stored without compression")
        if z.read("mimetype") != b"application/epub+zip":
            problems.append("`mimetype` has the wrong content")
    try:
        cont = ET.fromstring(z.read("META-INF/container.xml"))
        opf_path = cont.find(".//c:rootfile", NS).get("full-path")
    except Exception as e:
        print("FATAL: container.xml: %r" % e)
        return 1
    base = posixpath.dirname(opf_path)
    opf = ET.fromstring(z.read(opf_path))
    md = opf.find("o:metadata", NS)
    for tag in ("dc:title", "dc:language", "dc:identifier", "dc:creator"):
        if md.find(tag, NS) is None or not (md.find(tag, NS).text or "").strip():
            problems.append("metadata: %s is missing" % tag)
    if not any(m.get("property") == "dcterms:modified" for m in md.findall("o:meta", NS)):
        problems.append("metadata: dcterms:modified is missing")
    items = {}
    for it in opf.findall("o:manifest/o:item", NS):
        href = posixpath.normpath(posixpath.join(base, it.get("href")))
        items[it.get("id")] = (href, it.get("media-type"), it.get("properties") or "")
        if href not in names:
            problems.append("manifest: %s is not in the archive" % href)
        ext = posixpath.splitext(href)[1].lower()
        if ext in TYPES and it.get("media-type") != TYPES[ext]:
            problems.append("manifest: %s has media type %s, expected %s" % (href, it.get("media-type"), TYPES[ext]))
    listed = {v[0] for v in items.values()}
    for n in names:
        if n == "mimetype" or n.startswith("META-INF/") or n == opf_path or n.endswith("/"):
            continue
        if n not in listed:
            problems.append("archive: %s is not in the manifest" % n)
    if not any("cover-image" in v[2] for v in items.values()):
        notes.append("no cover image declared")
    navs = [v[0] for v in items.values() if "nav" in v[2].split()]
    if len(navs) != 1:
        problems.append("there must be exactly one navigation document (found %d)" % len(navs))
    spine = [i.get("idref") for i in opf.findall("o:spine/o:itemref", NS)]
    for idref in spine:
        if idref not in items:
            problems.append("spine: %s is not in the manifest" % idref)
    # XHTML files
    docs, ids = {}, {}
    for id_, (href, mt, props) in items.items():
        if mt != "application/xhtml+xml":
            continue
        try:
            root = ET.fromstring(z.read(href))
        except ET.ParseError as e:
            problems.append("%s: not well-formed XML: %s" % (href, e))
            continue
        docs[href] = root
        seen = set()
        for el in root.iter():
            i = el.get("id")
            if i:
                if i in seen:
                    problems.append("%s: duplicate id %r" % (href, i))
                seen.add(i)
            tag = el.tag.split("}")[-1]
            if tag == "script" and "scripted" not in props:
                problems.append("%s: <script> in a document that is not declared scripted" % href)
        ids[href] = seen
        t = root.find(".//h:head/h:title", NS)
        if t is None or not (t.text or "").strip():
            problems.append("%s: no <title>" % href)
    # links and images
    nlinks = nimgs = 0
    for href, root in docs.items():
        d = posixpath.dirname(href)
        for el in root.iter():
            tag = el.tag.split("}")[-1]
            if tag == "a" and el.get("href"):
                target = el.get("href")
                if target.startswith(("http:", "https:", "mailto:")):
                    continue
                nlinks += 1
                f, _, frag = target.partition("#")
                tf = posixpath.normpath(posixpath.join(d, f)) if f else href
                if tf not in names:
                    problems.append("%s: link to missing file %s" % (href, target))
                elif frag and tf in ids and frag not in ids[tf]:
                    problems.append("%s: link to missing anchor %s" % (href, target))
            if tag == "img" and el.get("src"):
                nimgs += 1
                s = el.get("src")
                if s.startswith(("http:", "https:", "data:")):
                    problems.append("%s: remote or data image %s" % (href, s[:40]))
                elif posixpath.normpath(posixpath.join(d, s)) not in names:
                    problems.append("%s: missing image %s" % (href, s))
    # navigation document
    if navs and navs[0] in docs:
        navdoc = docs[navs[0]]
        toc = [n for n in navdoc.iter("{%s}nav" % NS["h"]) if n.get("{%s}type" % NS["e"]) == "toc"]
        if not toc:
            problems.append("the navigation document has no nav epub:type=toc")
        else:
            entries = [a for a in toc[0].iter("{%s}a" % NS["h"])]
            if not entries:
                problems.append("the table of contents is empty")
            notes.append("table of contents: %d entries" % len(entries))
    ncx = [v[0] for v in items.values() if v[1] == "application/x-dtbncx+xml"]
    for n in ncx:
        try:
            ET.fromstring(z.read(n))
        except ET.ParseError as e:
            problems.append("%s: not well-formed: %s" % (n, e))
    print("%s: %d files, %d XHTML documents in the spine, %d internal links and %d images checked, %.1f MB" % (
        os.path.basename(path), len(names), len(spine), nlinks, nimgs, os.path.getsize(path) / 1e6))
    for n in notes:
        print("note:", n)
    for p in problems[:60]:
        print("PROBLEM:", p)
    if len(problems) > 60:
        print("... and %d more" % (len(problems) - 60))
    print("OK: no problems found" if not problems else "%d problems" % len(problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
