#!/bin/bash
# Runs the terminal user interface tests: builds the test programs (tests/tui/probe.a, examples/tui/*.a) and drives them in a pseudo
# terminal with a Python terminal emulator (tests/tui/ptyterm.py): typing, menus, mouse, paste, resize, suspend to a shell, signals,
# capabilities, and that the terminal is restored at the end.
# Usage: tests/tui.sh [test-name-substring ...]      needs python3 and a built compiler (make)
cd "$(dirname "$0")/.."
AC=./build/ac
OUT=build/tests/tui
mkdir -p $OUT
for prog in tests/tui/probe.a examples/tui/gallery.a examples/tui/files.a; do
    [ -f $prog ] || continue
    name=$(basename $prog .a)
    if ! $AC $prog -o $OUT/$name; then echo "cannot compile $prog"; exit 1; fi
done
export PROBE=$OUT/probe GALLERY=$OUT/gallery FILES=$OUT/files
exec python3 tests/tui/run_tests.py "$@"
