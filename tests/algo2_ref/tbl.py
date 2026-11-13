"""Helpers for the table driven tests: rows of doubles written as A source text between  // BEGIN TABLE name  and  // END TABLE name  markers."""
import re

def lit(v):
    v = float(v)
    s = '%.17g' % v
    if 'e' not in s and '.' not in s and 'n' not in s:
        s += '.0'
    return s

def table_text(name, rows):
    """a global array  double name[N] = { ... };  with one row of numbers per line"""
    n = sum(len(r) for r in rows)
    lines = ['double %s[%d] = {' % (name, max(n, 1))]
    for r in rows:
        lines.append('    ' + ', '.join(lit(v) for v in r) + ',')
    lines.append('};')
    return '\n'.join(lines)

def patch(path, name, text):
    src = open(path).read()
    b = '// BEGIN TABLE %s\n' % name
    e = '// END TABLE %s\n' % name
    i = src.index(b) + len(b)
    j = src.index(e)
    src = src[:i] + text + '\n' + src[j:]
    open(path, 'w').write(src)
