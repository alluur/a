#!/usr/bin/env python3
"""Generates tests/t215_regex_python.a and its expected output from Python's `re` module.

Every case is run by Python (search, fullmatch and sub with a replacement that shows groups 0 and 1) and the
results are written in a canonical text form; the A test prints the same form using lib/regex.a. The two must agree
byte for byte. Positions are UTF-8 byte offsets. Usage: tests/gen/gen_regex_test.py   (from the repository root)
"""
import re, sys, os

CASES = [
    # literals, classes, anchors
    ("abc", "xxabcxx"), ("^abc$", "abc"), ("^abc$", "abcd"), ("a.c", "xa-cx"), ("[a-c]+", "xxabcabcdd"),
    ("[^a-c]+", "abcxyzabc"), (r"\d+", "ab123cd45"), (r"\w+@\w+\.\w+", "mail bob@site.com now"), (r"\s+", "a \t b"),
    (r"[\d-]+", "tel 12-34-5"), (r"[]a]+", "x]a]y"), (r"[a\]]+", "x]a]y"), (r"[\w.]+", "foo.bar baz"), (r"\.txt$", "a.txt"),
    ("a$", "a\n"), ("a$", "a\nb"), (r"(?m)a$", "a\nb"), (r"(?m)^b", "a\nb"), (r"\Aa", "a"), (r"a\Z", "a\n"), (r"a\Z", "a"),
    # groups and alternation
    ("(a|b)+c", "xababcx"), ("(foo|foobar)baz", "foobarbaz"), ("(a)(b)?(c)", "ac"), ("(?:ab)+", "xababab"),
    ("a|ab", "abc"), ("(a|ab)(c|bcd)(d*)", "abcd"), ("(a+)(a+)", "aaaa"), ("^(a+)+$", "aaaa"), ("(a)|b", "b"),
    ("((a)|(b))+", "ab"), ("(a(b(c)))", "abc"), ("x(?:a|b)(c)", "xbc"), ("(|a)+", "aaa"), ("a||b", "b"),
    # quantifiers
    ("a{2,3}", "aaaaa"), ("a{2,}", "aaaaa"), ("a{,2}", "aaaaa"), ("a{3}", "aa"), ("x{0}y", "xy"), ("a{2}b", "caab"),
    ("(ab){2,3}", "abababab"), ("(ab){2}", "ababab"), ("a{,}", "a{,}"), ("a{x}", "a{x}"), ("a{1,2}{", "a{"), ("{", "a{"),
    # lazy
    ("a.*?b", "aXbXb"), ("<.+?>", "<a><b>"), ("a+?", "aaa"), ("(ab)*?c", "ababc"), ("a??b", "ab"), ("a{2,4}?", "aaaa"),
    ("(a+?)(a*)", "aaa"), ("(.*?)(\\d+)", "abc123"),
    # back references
    (r"(a+)\1", "aaaaa"), (r"(\w)\1", "hello"), (r"(a)|b\1", "b"), (r"(?P<x>a)(?P=x)", "aa"), (r"(.)(.)\2\1", "xabbay"),
    (r"(a*)\1b", "aab"), (r"(?i)(a)\1", "aA"), (r"(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)\10", "abcdefghijj"),
    # empty iterations (Perl / Python semantics)
    ("(a*)*", "b"), ("(a*)+", "b"), ("(a*)*", "aab"), ("(a|)+", "b"), ("(a?)*b", "aab"), ("(a*?)*", "aa"), ("(a*){2,3}", "aa"),
    ("(?:a*)*", "aaa"), ("(a*)*?b", "aab"), ("(a*)+?b", "aab"), ("(|a)+", "aa"), ("(a*|b)*", "abab"), ("(a|b*)*c", "abbc"),
    ("(?:(a)|b)*", "ab"), ("(a?)+", "aa"), ("(a?){3}", "a"), ("(a*)*$", "aa"), ("((a*)b?)*", "aabab"),
    # word boundaries, lookahead, flags
    (r"\bfoo\b", "a foo b"), (r"\Boo", "foo"), (r"\bfoo\b", "foobar"), ("foo(?=bar)", "foobar foobaz"), ("foo(?!bar)", "foobar foobaz"),
    (r"(?=(a+))a*b\1", "baaabac"), (r"(?i)abc", "xABCx"), (r"(?i:a)b", "Ab"), (r"(?i:a)b", "AB"), (r"(?s)a.b", "a\nb"), ("a.b", "a\nb"),
    ("(?=a)*b", "b"), (r"(?!a)\w", "ab"), ("^(?:a|ab)(?=c)", "abc"),
    # classes and escapes
    (r"[a-z]+\d{2}", "xx abc12 de3"), (r"\x41+", "xAAy"), (r"a\.b", "a.b axb"), (r"[\x41-\x43]+", "xABCDx"), (r"\t", "a\tb"), (r"[\t ]+", "a \t b"),
    (r"\S+\s\S+", "ab  cd ef"), (r"\W+", "ab, cd"), (r"\D+", "12ab34"),
    # non-ASCII (positions are bytes)
    ("é+", "caféé!"), (".", "é"), ("^.$", "€"), ("[é€]+", "a€éb"), ("[^a]", "é"), (r"\w+", "naïve café"), ("(.)(.)", "éa"), ("a.c", "aéc"),
    # unmatched / empty
    ("x", ""), ("", ""), ("", "abc"), ("^$", ""), ("a*", ""), (".*", "abc"), (".*?", "abc"), ("(a)?", "b"), ("(a)?b", "b"),
]

ERRORS = ["(a", "a)", "[a", "[z-a]", "*a", "+a", "a**", "(a)\\2", "\\1(a)", "(a\\1)", "a{2,1}", "(?P<n>a)(?P<n>b)", "x{1}{2}", "^*",
          "\\b*", "a|*", "(?P<1>a)", "(?P=zz)", "\\", "[\\", "(?", "(?x", "a{1,2}{3}"]

def boff(text, i):
    return len(text[:i].encode("utf-8"))

def esc(s):
    return s.replace("\\", "\\\\").replace("\n", "\\n").replace("\t", "\\t")

def aliteral(s):
    out = []
    for b in s.encode("utf-8"):
        c = chr(b)
        if c == '"' or c == '\\':
            out.append("\\" + c)
        elif 32 <= b < 127:
            out.append(c)
        else:
            out.append("\\x%02x" % b)
    # "\xNN" followed by a hex digit would run on: the A lexer reads exactly two digits, so this is safe
    return '"' + "".join(out) + '"'

def result_line(i, pat, text):
    try:
        rx = re.compile(pat)
    except re.error:
        return "%d ERR" % i
    m = rx.search(text)
    if m is None:
        s = "-"
    else:
        parts = ["%d,%d" % (boff(text, m.start()), boff(text, m.end()))]
        for g in range(1, rx.groups + 1):
            if m.start(g) < 0:
                parts.append("-")
            else:
                parts.append("%d,%d" % (boff(text, m.start(g)), boff(text, m.end(g))))
        s = ";".join(parts)
    f = 1 if rx.fullmatch(text) else 0
    def rep(mm):
        g1 = ""
        if rx.groups >= 1 and mm.group(1) is not None:
            g1 = mm.group(1)
        return "[" + mm.group(0) + "|" + g1 + "]"
    r = rx.sub(rep, text)
    return "%d %s F%d R<%s>" % (i, s, f, esc(r))

def main():
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    lines = []
    src = []
    src.append("// Generated by tests/gen/gen_regex_test.py from Python's re module: every case is run by lib/regex.a and the\n")
    src.append("// result (search positions in bytes with groups, fullmatch, sub) must equal what Python printed. Do not edit by hand.\n")
    src.append("import regex;\n\n")
    src.append("void esc(char* s) {\n    for (int i = 0; s[i] != 0; i++) {\n        if (s[i] == 10) { print(\"\\\\n\"); }\n        else if (s[i] == 9) { print(\"\\\\t\"); }\n        else if (s[i] == 92) { print(\"\\\\\\\\\"); }\n        else { printChar(s[i]); }\n    }\n}\n\n")
    src.append("void runCase(int i, char* pat, char* text) {\n")
    src.append("    regex.Regex* re = regex.compile(pat, 0);\n")
    src.append("    if (!re->ok) { printf(\"%d ERR\\n\", i); return; }\n")
    src.append("    int n = strlen(text);\n    int caps[66];\n")
    src.append("    int at = re->search(text, n, 0, &caps[0]);\n")
    src.append("    printf(\"%d \", i);\n")
    src.append("    if (at < 0) { print(\"-\"); }\n")
    src.append("    else {\n        for (int g = 0; g <= re->groups; g++) {\n            if (g > 0) { print(\";\"); }\n            if (caps[2 * g] < 0) { print(\"-\"); } else { printf(\"%d,%d\", caps[2 * g], caps[2 * g + 1]); }\n        }\n    }\n")
    src.append("    int caps2[66];\n    printf(\" F%d R<\", re->matchFull(text, n, &caps2[0]) ? 1 : 0);\n")
    src.append("    char* r = regex.replaceGroups(pat, text, \"[$0|$1]\");\n    esc(r);\n    print(\">\\n\");\n    re->dispose();\n}\n\n")
    src.append("int main() {\n")
    for i, (pat, text) in enumerate(CASES):
        src.append("    runCase(%d, %s, %s);\n" % (i, aliteral(pat), aliteral(text)))
        lines.append(result_line(i, pat, text))
    base = len(CASES)
    for j, pat in enumerate(ERRORS):
        i = base + j
        src.append("    runCase(%d, %s, \"abc\");\n" % (i, aliteral(pat)))
        lines.append(result_line(i, pat, "abc"))
    src.append("    return 0;\n}\n")
    open(os.path.join(root, "tests", "t215_regex_python.a"), "w").write("".join(src))
    open(os.path.join(root, "tests", "t215_regex_python.out"), "w").write("\n".join(lines) + "\n")
    print("cases:", len(CASES), "errors:", len(ERRORS))

main()
