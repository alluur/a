#!/bin/sh
# Builds the Debian packages of the A language.
#   packaging/deb/mkdeb.sh OUT_COMPILER OUT_COMMON VERSION_NAME VERSION_CODE
# Run from the repository root. Needs build/ac. Packs the book (build/book/html and build/book/*.epub)
# into OUT_COMMON when it has been built.
#
# Two packages come out of this:
#   a-lang         (Architecture: amd64) the ac binary, its man pages and bash completion - the
#                  only part that is tied to the host CPU, since ac is itself x86-64 code.
#   a-lang-common  (Architecture: all)   the language reference, standard library docs, the book,
#                  the examples and the Vim/nano syntax files - installable on any architecture,
#                  with or without a-lang, e.g. to read the docs on a machine ac cannot run on.
set -eu
OUT_AC=$1; OUT_COMMON=$2; VNAME=$3; VCODE=$4
VERSION="$VNAME-$VCODE"
DATE=$(LC_ALL=C date -R -u ${SOURCE_DATE_EPOCH:+-d "@$SOURCE_DATE_EPOCH"})
MAINTAINER=${MAINTAINER:-"Aytict (https://aytict.fi)"}
[ -x build/ac ] || { echo "mkdeb: build/ac is missing (run make)" >&2; exit 1; }

# Staged outside the repository: a repo checked out over NFS (or similar) can have directories
# whose setgid bit the build user cannot chmod away, which dpkg-deb then refuses as "bad
# permissions" on DEBIAN/. A plain tmpdir never has that problem.
STAGE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/a-deb-build.XXXXXX")
trap 'rm -rf "$STAGE_ROOT"' EXIT

# -----------------------------------------------------------------------------------------------
# a-lang: the compiler (Architecture: amd64)
# -----------------------------------------------------------------------------------------------
STAGE_AC=$STAGE_ROOT/deb
PKG_AC=a-lang
D_AC=$STAGE_AC/usr/share/doc/$PKG_AC

rm -rf "$STAGE_AC"
mkdir -p "$STAGE_AC/DEBIAN" "$STAGE_AC/usr/bin" "$STAGE_AC/usr/share/man/man1" "$STAGE_AC/usr/share/man/man7" \
         "$STAGE_AC/usr/share/bash-completion/completions" "$D_AC"

install -m 0755 build/ac "$STAGE_AC/usr/bin/ac"
strip "$STAGE_AC/usr/bin/ac"
gzip -9n -c docs/ac.1 > "$STAGE_AC/usr/share/man/man1/ac.1.gz"
gzip -9n -c docs/a.7 > "$STAGE_AC/usr/share/man/man7/a.7.gz"
install -m 0644 packaging/deb/ac.bash-completion "$STAGE_AC/usr/share/bash-completion/completions/ac"

install -m 0644 packaging/deb/copyright "$D_AC/copyright"
sed -e "s/@PKG@/$PKG_AC/; s/@VERSION@/$VERSION/; s/@VERSION_NAME@/$VNAME/; s/@VERSION_CODE@/$VCODE/; s/@DATE@/$DATE/" \
    packaging/deb/changelog | gzip -9n > "$D_AC/changelog.gz"

find "$STAGE_AC" -type d -exec chmod 0755 {} +
find "$STAGE_AC" -type f ! -path "$STAGE_AC/usr/bin/*" -exec chmod 0644 {} +
( cd "$STAGE_AC" && find usr -type f -exec md5sum {} + | sort -k2 ) > "$STAGE_AC/DEBIAN/md5sums"
SIZE_AC=$(du -sk --exclude=DEBIAN "$STAGE_AC" | cut -f1)

cat > "$STAGE_AC/DEBIAN/control" <<CTRL
Package: $PKG_AC
Version: $VERSION
Section: devel
Priority: optional
Architecture: amd64
Installed-Size: $SIZE_AC
Maintainer: $MAINTAINER
Homepage: https://aytict.fi
Recommends: a-lang-common (= $VERSION)
Suggests: qemu-user
Description: A - compiler for the A programming language
 The A compiler, ac, compiles A source code directly to native executables.
 It is written in x86-64 assembly and needs no external assembler, linker or
 C library: it writes finished static executables for Linux (x86-64, ARM64,
 RISC-V 64, LoongArch64), Windows (x86-64) and Android (ARM64, x86-64,
 RISC-V 64). This is why the package itself is amd64 only, even though its
 output is not: ac is a cross compiler, but it only runs on an x86-64 host.
 .
 This package contains the ac binary, its manual pages (ac(1) for the
 compiler's options, a(7) for the language) and bash completion.
 .
 The language reference, standard library documentation, the book, the
 examples and the Vim/nano syntax files are in a-lang-common, which installs
 on any architecture.
 .
 Suggested: qemu-user, to run the ARM64, RISC-V and LoongArch programs on an
 x86-64 machine.
CTRL
chmod 0644 "$STAGE_AC/DEBIAN/control" "$STAGE_AC/DEBIAN/md5sums"
mkdir -p "$(dirname "$OUT_AC")"
dpkg-deb --root-owner-group -Zxz --build "$STAGE_AC" "$OUT_AC"

# -----------------------------------------------------------------------------------------------
# a-lang-common: language reference, standard library docs, the book, examples, editor syntax
# (Architecture: all)
# -----------------------------------------------------------------------------------------------
STAGE_CM=$STAGE_ROOT/deb-common
PKG_CM=a-lang-common
D_CM=$STAGE_CM/usr/share/doc/$PKG_CM

rm -rf "$STAGE_CM"
mkdir -p "$STAGE_CM/DEBIAN" "$STAGE_CM/usr/share/vim/vimfiles" "$STAGE_CM/usr/share/nano" \
         "$D_CM/reference" "$D_CM/examples"

cp -r editors/vim/* "$STAGE_CM/usr/share/vim/vimfiles/"
install -m 0644 editors/nano/a.nanorc "$STAGE_CM/usr/share/nano/a.nanorc"

install -m 0644 README.md "$D_CM/README.md"
install -m 0644 packaging/deb/copyright "$D_CM/copyright"
sed -e "s/@PKG@/$PKG_CM/; s/@VERSION@/$VERSION/; s/@VERSION_NAME@/$VNAME/; s/@VERSION_CODE@/$VCODE/; s/@DATE@/$DATE/" \
    packaging/deb/changelog | gzip -9n > "$D_CM/changelog.gz"
for f in docs/*.md; do install -m 0644 "$f" "$D_CM/reference/"; done
cp -r examples/. "$D_CM/examples/"
if [ -d build/book/html ]; then
    mkdir -p "$D_CM/html"
    cp -r build/book/html/. "$D_CM/html/"
fi
for e in build/book/a-book-*.epub; do
    [ -f "$e" ] && install -m 0644 "$e" "$D_CM/$(basename "$e")"
done

find "$STAGE_CM" -type d -exec chmod 0755 {} +
find "$STAGE_CM" -type f -exec chmod 0644 {} +
( cd "$STAGE_CM" && find usr -type f -exec md5sum {} + | sort -k2 ) > "$STAGE_CM/DEBIAN/md5sums"
SIZE_CM=$(du -sk --exclude=DEBIAN "$STAGE_CM" | cut -f1)

cat > "$STAGE_CM/DEBIAN/control" <<CTRL
Package: $PKG_CM
Version: $VERSION
Section: doc
Priority: optional
Architecture: all
Installed-Size: $SIZE_CM
Maintainer: $MAINTAINER
Homepage: https://aytict.fi
Suggests: a-lang (= $VERSION)
Description: A - language reference, standard library docs and editor support
 Architecture-independent material for the A programming language: the book
 "The A Programming Language" (HTML and EPUB, with compiled and run code
 samples), the language and standard library reference (docs/*.md), the
 example programs, and syntax files for Vim and nano.
 .
 Install alongside a-lang to compile and run the examples, or on its own
 to read the documentation and browse the examples on an architecture ac
 does not run on (ac is x86-64 only; see a-lang's description).
CTRL
chmod 0644 "$STAGE_CM/DEBIAN/control" "$STAGE_CM/DEBIAN/md5sums"
mkdir -p "$(dirname "$OUT_COMMON")"
dpkg-deb --root-owner-group -Zxz --build "$STAGE_CM" "$OUT_COMMON"
