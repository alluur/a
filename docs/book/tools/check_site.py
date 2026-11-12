#!/usr/bin/env python3
"""Check the HTML site of the book: every internal link (file and #anchor), every image, every script and stylesheet must exist.

  check_site.py SITE_DIR
Exit status 0 when nothing is broken."""
import html.parser, os, re, sys, urllib.parse


class P(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.links, self.ids, self.assets = [], set(), []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if a.get("id"):
            self.ids.add(a["id"])
        if tag == "a" and a.get("href"):
            self.links.append(a["href"])
        for k in ("src", "href"):
            if tag in ("img", "script", "link") and a.get(k):
                self.assets.append(a[k])


def main(site):
    pages, bad = {}, []
    for f in sorted(os.listdir(site)):
        if f.endswith(".html"):
            p = P()
            p.feed(open(os.path.join(site, f), encoding="utf-8").read())
            pages[f] = p
    nlinks = 0
    for f, p in pages.items():
        for href in p.links:
            if re.match(r"^[a-z]+:", href) or href.startswith("//"):
                continue
            nlinks += 1
            path, _, frag = href.partition("#")
            tgt = path or f
            if tgt.endswith(".html"):
                if tgt not in pages:
                    bad.append("%s: link to missing page %s" % (f, href))
                elif frag and urllib.parse.unquote(frag) not in pages[tgt].ids:
                    bad.append("%s: link to missing anchor %s" % (f, href))
            elif not os.path.exists(os.path.join(site, urllib.parse.unquote(path))):
                bad.append("%s: link to missing file %s" % (f, href))
        for a in p.assets:
            if re.match(r"^[a-z]+:", a):
                continue
            if not os.path.exists(os.path.join(site, a.split("#")[0])):
                bad.append("%s: missing asset %s" % (f, a))
    print("%d pages, %d internal links checked" % (len(pages), nlinks))
    for b in bad[:60]:
        print("BROKEN:", b)
    print("OK: nothing broken" if not bad else "%d broken" % len(bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
