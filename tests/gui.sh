#!/bin/bash
# The graphical stack with real processes (Linux x86-64 only, needs python3): the display server with a VNC backend,
# a few clients, input through VNC and through actl. Usage: tests/gui.sh
cd "$(dirname "$0")/.."
AC=./build/ac
OUT=build/guitest
mkdir -p $OUT
for prog in adisplayd actl hello calc paint notes asession adm vnc_demo alock showcase aterm aview afiles apanel anet; do
    if ! $AC examples/gui/$prog.a -o $OUT/$prog 2> $OUT/$prog.err; then
        echo "FAIL  gui/$prog (compile error: $(head -1 $OUT/$prog.err))"; exit 1
    fi
done
if ! command -v python3 >/dev/null; then echo "gui tests skipped (no python3)"; exit 0; fi
if timeout 120 python3 tests/gui/session_test.py $OUT > $OUT/session.log 2>&1; then
    echo "gui tests passed"
else
    echo "FAIL  gui/session"; cat $OUT/session.log; exit 1
fi
