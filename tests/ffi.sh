#!/bin/bash
# Calling C libraries (extern "library"): every tests/ffi/*.a program is compiled and run, its output compared with the .out
# file. Linux programs are dynamically linked against glibc; the other CPUs run under QEMU with the cross glibc as sysroot
# (/usr/<triple>, packages libc6-arm64-cross, libc6-riscv64-cross, libc6-loong64-cross), windows.a under Wine.
# Usage: tests/ffi.sh            (TARGET=linux-arm64 | linux-riscv64 | linux-loongarch64 | windows, like tests/run.sh)
cd "$(dirname "$0")/.."
AC=./build/ac
TARGET=${TARGET:-linux}
RUN=""
EXT=elf
case "$TARGET" in
linux) PROGS="libc dlopen" ;;
linux-arm64) PROGS="libc dlopen"; SYS=/usr/aarch64-linux-gnu; RUN=$(command -v qemu-aarch64) ;;
linux-riscv64) PROGS="libc dlopen"; SYS=/usr/riscv64-linux-gnu; RUN=$(command -v qemu-riscv64) ;;
linux-loongarch64) PROGS="libc dlopen"; SYS=/usr/loongarch64-linux-gnu; RUN=$(command -v qemu-loongarch64) ;;
windows) PROGS="windows"; EXT=exe
    export WINEDEBUG=-all WINEPREFIX=${WINEPREFIX:-/tmp/wineprefix}
    RUN=$(command -v wine64 || echo /usr/lib/wine/wine64) ;;
*) echo "ffi tests: no dynamic linking for $TARGET yet (skipped)"; exit 0 ;;
esac
if [ -n "$SYS" ] && [ ! -d "$SYS" ]; then echo "ffi tests skipped ($SYS not installed)"; exit 0; fi
[ -n "$SYS" ] && export QEMU_LD_PREFIX=$SYS
pass=0; fail=0
mkdir -p build/ffitests
for name in $PROGS; do
    exe=build/ffitests/$name.$TARGET.$EXT
    if ! $AC -t $TARGET tests/ffi/$name.a -o $exe 2> build/ffitests/$name.err; then
        echo "FAIL  ffi/$name (compile error: $(head -1 build/ffitests/$name.err))"; fail=$((fail+1)); continue
    fi
    timeout 60 $RUN $exe 2>/dev/null | tr -d '\r' > build/ffitests/$name.got
    if ! diff -q tests/ffi/$name.out build/ffitests/$name.got > /dev/null; then
        echo "FAIL  ffi/$name (output differs)"; diff tests/ffi/$name.out build/ffitests/$name.got | head -5; fail=$((fail+1)); continue
    fi
    pass=$((pass+1))
done
echo "ffi tests passed: $pass, failed: $fail"
[ $fail -eq 0 ]
