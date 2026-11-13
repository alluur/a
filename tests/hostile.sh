#!/bin/bash
# Hostile source text must not make the compiler slow or crash (the AIDE editors compile text that anybody can write):
# deeply nested parentheses, tuples and lambdas, very long lists. Every program is compiled with a time limit; the result
# has to be a normal exit (0 = compiled, 1 = a compile error with a message), never a timeout or a crash.
# Usage: tests/hostile.sh        (needs python3 to generate the sources; ~1 second)
cd "$(dirname "$0")/.."
AC=./build/ac
dir=$(mktemp -d /tmp/hostile.XXXXXX)
trap 'rm -rf "$dir"' EXIT
python3 - "$dir" <<'PY'
import sys
d = sys.argv[1]
def w(name, text):
    open('%s/%s.a' % (d, name), 'w').write(text)
n = 12000
w('nested_tuple_expr',   'int main() { int a = 1; int r = ' + '(a, ' * n + 'a' + ')' * n + '; return r; }\n')
w('nested_tuple_stmt',   'int main() { int a = 1; ' + '(a, ' * n + 'a' + ')' * n + '; return 0; }\n')
w('nested_pattern',      'int main() { int a = 1; ' + '(a, ' * 3000 + 'a' + ')' * 3000 + ' = 5; return 0; }\n')
w('nested_tuple_type',   'int main() { ' + '(int, ' * 3000 + 'int' + ')' * 3000 + ' t; return 0; }\n')
w('nested_casts',        'int main() { int a = 1; return ' + '(int)(char)' * 20000 + 'a; }\n')
w('nested_lambdas',      'int main() { int r = ' + '(x => ' * 3000 + '1' + ')' * 3000 + '; return 0; }\n')
w('nested_lambdas2',     'int main() { int r = ' + '((a, b) => ' * 2000 + '1' + ')' * 2000 + '; return 0; }\n')
w('deep_parens',         'int main() { return ' + '(' * 200000 + '1' + ')' * 200000 + '; }\n')
w('long_params',         'int main() { int r = (' + ', '.join('a%d' % i for i in range(30000)) + ') => 1; return 0; }\n')
w('many_tuples',         'int main() { int a = 1; int b = 2; int r = 0; ' + 'r = (a, b); ' * 20000 + 'return r; }\n')
w('many_lambdas',        'int main() { func f = (a, b) => a; ' + 'f = (a, b) => b; ' * 20000 + 'return 0; }\n')
w('many_values',         'int main() { int x = 1; char* s = $"' + '{x}' * 5000 + '"; return 0; }\n')
w('long_interp_text',    'int main() { int x = 1; char* s = $"' + 'ab {x} ' * 20000 + '"; return 0; }\n')
w('many_brace_lists',    'struct P { int x; int y; }\nint main() { P a[20000] = {' + '{1, 2}, ' * 20000 + '}; return 0; }\n')
PY
fail=0
for f in "$dir"/*.a; do
    name=$(basename "$f" .a)
    s=$(date +%s.%N)
    timeout 10 $AC "$f" -o "$dir/$name.out" > "$dir/$name.err" 2>&1
    rc=$?
    e=$(date +%s.%N)
    t=$(echo "$e - $s" | bc)
    if [ $rc -gt 1 ]; then
        echo "FAIL  $name (exit code $rc after ${t}s)"; fail=$((fail+1))
    elif [ "$(echo "$t > 5" | bc)" = 1 ]; then
        echo "FAIL  $name (too slow: ${t}s)"; fail=$((fail+1))
    else
        printf 'ok    %-20s rc=%s %.2fs\n' "$name" $rc "$t"
    fi
done
[ $fail -eq 0 ] && echo "hostile: all ok"
[ $fail -eq 0 ]
