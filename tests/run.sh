#!/bin/bash
# Runs every tests/*.a program and compares stdout (.out) and exit code (.exit, default 0).
# Usage: tests/run.sh [pattern]            (Linux x86-64 native)
#        TARGET=windows tests/run.sh       (PE executables, run through Wine)
#        TARGET=linux-arm64 tests/run.sh   (AArch64 ELF, run through qemu-aarch64)
#        TARGET=android tests/run.sh       (Android ARM64 ELF, run through qemu-aarch64)
#        TARGET=android-x64 tests/run.sh   (Android x86-64 ELF, run natively)
#        TARGET=linux-riscv64 | android-riscv64 | linux-loongarch64   (run through qemu-riscv64 / qemu-loongarch64)
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
mkdir -p build/tests
for src in tests/${1:-t}*.a; do
    name=$(basename "$src" .a)
    exe=build/tests/$name.$EXT
    if ! $AC -t $TARGET "$src" -o "$exe" 2> build/tests/$name.err; then
        if [ -f tests/$name.err ]; then
            if grep -qF "$(cat tests/$name.err)" build/tests/$name.err; then pass=$((pass+1)); continue; fi
        fi
        echo "FAIL  $name (compile error: $(head -1 build/tests/$name.err))"; fail=$((fail+1)); continue
    fi
    if [ -f tests/$name.err ]; then echo "FAIL  $name (expected a compile error)"; fail=$((fail+1)); continue; fi
    want_exit=0; [ -f tests/$name.exit ] && want_exit=$(cat tests/$name.exit)
    if [ -f tests/$name.in ]; then
        timeout 60 $RUN "$exe" < tests/$name.in > build/tests/$name.got 2>/dev/null
    else
        timeout 60 $RUN "$exe" > build/tests/$name.got 2>/dev/null < /dev/null
    fi
    got_exit=$?
    if [ "$got_exit" != "$want_exit" ]; then
        echo "FAIL  $name (exit code $got_exit, expected $want_exit)"; fail=$((fail+1)); continue
    fi
    if [ -f tests/$name.out ] && ! diff -q tests/$name.out build/tests/$name.got >/dev/null; then
        echo "FAIL  $name (output differs)"; diff tests/$name.out build/tests/$name.got | head -5; fail=$((fail+1)); continue
    fi
    pass=$((pass+1))
done
echo "passed: $pass, failed: $fail"
[ $fail -eq 0 ]
