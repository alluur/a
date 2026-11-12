#!/bin/sh
# Builds the Debian package of the A compiler.
#   packaging/deb/mkdeb.sh OUTFILE VERSION_NAME VERSION_CODE
# Run from the repository root. Needs build/ac. Packs the book (build/book/html and build/book/*.epub) when it has been built.
set -eu
OUT=$1; VNAME=$2; VCODE=$3
STAGE=build/deb
PKG=a-lang
VERSION="$VNAME-$VCODE"
DATE=$(LC_ALL=C date -R -u ${SOURCE_DATE_EPOCH:+-d "@$SOURCE_DATE_EPOCH"})
MAINTAINER=${MAINTAINER:-"Aytict (https://aytict.fi)"}
[ -x build/ac ] || { echo "mkdeb: build/ac is missing (run make)" >&2; exit 1; }

rm -rf "$STAGE"
D=$STAGE/usr/share/doc/$PKG
mkdir -p "$STAGE/DEBIAN" "$STAGE/usr/bin" "$STAGE/usr/lib/a" "$STAGE/usr/share/man/man1" \
         "$STAGE/usr/share/bash-completion/completions" "$STAGE/usr/share/vim/vimfiles" "$STAGE/usr/share/nano" \
         "$D/reference" "$D/examples"

install -m 0755 build/ac "$STAGE/usr/bin/ac"
strip "$STAGE/usr/bin/ac"
gzip -9n -c docs/ac.1 > "$STAGE/usr/share/man/man1/ac.1.gz"
install -m 0644 packaging/deb/ac.bash-completion "$STAGE/usr/share/bash-completion/completions/ac"
cp -r editors/vim/* "$STAGE/usr/share/vim/vimfiles/"
install -m 0644 editors/nano/a.nanorc "$STAGE/usr/share/nano/a.nanorc"

install -m 0644 README.md "$D/README.md"
install -m 0644 packaging/deb/copyright "$D/copyright"
sed -e "s/@VERSION@/$VERSION/; s/@VERSION_NAME@/$VNAME/; s/@VERSION_CODE@/$VCODE/; s/@DATE@/$DATE/" packaging/deb/changelog | gzip -9n > "$D/changelog.gz"
for f in docs/*.md; do install -m 0644 "$f" "$D/reference/"; done
cp -r examples/. "$D/examples/"
if [ -d build/book/html ]; then
    mkdir -p "$D/html"
    cp -r build/book/html/. "$D/html/"
fi
for e in build/book/a-book-*.epub; do
    [ -f "$e" ] && install -m 0644 "$e" "$D/$(basename "$e")"
done

# permissions: directories 755, files 644 (the binary was installed 755)
find "$STAGE" -type d -exec chmod 0755 {} +
find "$STAGE" -type f ! -path "$STAGE/usr/bin/*" -exec chmod 0644 {} +
# md5sums for dpkg --verify
( cd "$STAGE" && find usr -type f -exec md5sum {} + | sort -k2 ) > "$STAGE/DEBIAN/md5sums"
SIZE=$(du -sk --exclude=DEBIAN "$STAGE" | cut -f1)

cat > "$STAGE/DEBIAN/control" <<CTRL
Package: $PKG
Version: $VERSION
Section: devel
Priority: optional
Architecture: amd64
Installed-Size: $SIZE
Maintainer: $MAINTAINER
Homepage: https://aytict.fi
Suggests: qemu-user
Description: A - a small C-like systems language and its compiler
 A is a small, C-like systems programming language. Its compiler, ac, is
 written in x86-64 assembly and needs no assembler, linker or C library: it
 writes finished static executables for Linux (x86-64, ARM64, RISC-V 64,
 LoongArch64), Windows (x86-64) and Android (ARM64, x86-64, RISC-V 64).
 .
 The standard library is written in A and compiled into your program: text,
 collections, numbers, data formats, cryptography and TLS 1.3, networking, the
 C library, a GUI toolkit, a terminal UI toolkit and the editor libraries of
 AIDE. This package also contains the book "The A Programming Language" (HTML
 and EPUB), the examples, the manual page and syntax files for Vim and nano.
 .
 Suggested: qemu-user, to run the ARM64, RISC-V and LoongArch programs on an
 x86-64 machine.
CTRL
chmod 0644 "$STAGE/DEBIAN/control" "$STAGE/DEBIAN/md5sums"
mkdir -p "$(dirname "$OUT")"
dpkg-deb --root-owner-group -Zxz --build "$STAGE" "$OUT"
