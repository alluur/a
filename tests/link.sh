#!/bin/bash
# Separate compilation tests: every directory in tests/link is a program of several .a files (and headers).
# Each .a file is compiled with -c to an object, the objects are linked (in alphabetical order) and run.
#   expected.out   the output of the program     expected.err   a substring of the expected link error
# Usage: tests/link.sh      (TARGET=windows | linux-arm64 | ... like tests/run.sh)
cd "$(dirname "$0")/.."
AC=./build/ac
TARGET=${TARGET:-linux}
RUN=""
EXT=elf
case "$TARGET" in
windows)
    EXT=exe
    export WINEDEBUG=-all WINEPREFIX=${WINEPREFIX:-/tmp/wineprefix}
    RUN=$(command -v wine64 || echo /usr/lib/wine/wine64) ;;
linux-arm64|android|android-arm64)
    RUN=$(command -v qemu-aarch64) ;;
linux-riscv64|android-riscv64|linux-rv64|android-rv64)
    RUN=$(command -v qemu-riscv64) ;;
linux-loongarch64|linux-la64|android-loongarch64)
    RUN=$(command -v qemu-loongarch64) ;;
esac
pass=0; fail=0
for dir in tests/link/*/; do
    name=$(basename "$dir")
    out=build/linktests/$name
    rm -rf "$out"; mkdir -p "$out"
    objs=()
    ok=1
    for src in "$dir"*.a; do
        o="$out/$(basename "$src" .a).ao"
        if ! $AC -t $TARGET -c "$src" -o "$o" 2> "$out/compile.err"; then
            echo "FAIL  link/$name (compile error in $src: $(head -1 "$out/compile.err"))"; ok=0; break
        fi
        objs+=("$o")
    done
    [ $ok = 1 ] || { fail=$((fail+1)); continue; }
    exe="$out/prog.$EXT"
    if $AC -t $TARGET "${objs[@]}" -o "$exe" 2> "$out/link.err"; then
        if [ -f "$dir/expected.err" ]; then
            echo "FAIL  link/$name (expected a link error)"; fail=$((fail+1)); continue
        fi
        timeout 60 $RUN "$exe" > "$out/got" 2>/dev/null
        if cmp -s "$out/got" "$dir/expected.out"; then pass=$((pass+1)); else echo "FAIL  link/$name (output differs)"; fail=$((fail+1)); fi
    else
        if [ -f "$dir/expected.err" ] && grep -qF "$(cat "$dir/expected.err")" "$out/link.err"; then pass=$((pass+1))
        else echo "FAIL  link/$name (link error: $(head -1 "$out/link.err"))"; fail=$((fail+1)); fi
    fi
done
echo "link tests passed: $pass, failed: $fail"
[ $fail = 0 ]
