# =============================================================================
#  A language compiler - build system
#
#    make            build the compiler           -> build/ac
#    make test       run the test-suite natively  (Linux x86-64)
#    make test-all   test every target (needs wine64 and qemu-user, see docs/TARGETS.md)
#    make examples   compile every example for every target
#    make dist       release binary               -> dist/ac-<code>-<release>.elf
#    make deb        Debian package               -> dist/a-<code>-<release>.deb
#    make install    install to $(PREFIX) (default /usr/local)
#
#  Output files follow  {app_name}-{version-code}-{release-type}.{ext}
#  e.g.  a-1-release.deb   ac-1-release.elf   (RELEASE=debug|release)
# =============================================================================
NASM    ?= nasm
LD      ?= ld
PREFIX  ?= /usr/local
RELEASE ?= release

VERSION_NAME := $(shell sed -n 's/^%define VERSION_NAME *"\(.*\)"/\1/p' src/defs.inc)
VERSION_CODE := $(shell sed -n 's/^%define VERSION_CODE *\([0-9]*\).*/\1/p' src/defs.inc)
STEM         := $(VERSION_CODE)-$(RELEASE)
SRC           = $(wildcard src/*.asm) src/defs.inc $(wildcard lib/*.a)

all: build/ac

build/ac: $(SRC)
	@mkdir -p build
	$(NASM) -f elf64 -i src/ src/ac.asm -o build/ac.o
	$(LD) -o build/ac build/ac.o

test: build/ac
	tests/run.sh
	tests/link.sh
	tests/gui.sh

test-all: build/ac
	@for t in linux windows linux-arm64 android android-x64 linux-riscv64 android-riscv64 linux-loongarch64; do \
	    echo "== target: $$t"; TARGET=$$t tests/run.sh || exit 1; TARGET=$$t tests/link.sh || exit 1; done

examples: build/ac
	@mkdir -p build/examples
	@for t in linux windows linux-arm64 android android-x64 linux-riscv64 android-riscv64 linux-loongarch64; do \
	    for f in examples/*.a examples/gui/*.a; do \
	        ./build/ac -t $$t $$f -v $(VERSION_CODE) -r $(RELEASE) -o build/examples/$$(basename $$f .a)-$$t.out || exit 1; \
	    done; echo "examples compiled for $$t"; done

dist: build/ac
	@mkdir -p dist
	cp build/ac dist/ac-$(STEM).elf
	strip dist/ac-$(STEM).elf
	@ls -l dist/ac-$(STEM).elf

deb: build/ac
	@rm -rf build/deb && mkdir -p build/deb/DEBIAN build/deb/usr/bin build/deb/usr/lib/a \
	    build/deb/usr/share/doc/a-lang/examples build/deb/usr/share/man/man1
	install -m 0755 build/ac build/deb/usr/bin/ac
	strip build/deb/usr/bin/ac
	cp README.md docs/LANGUAGE.md docs/TARGETS.md docs/INTERNALS.md docs/CLIB.md build/deb/usr/share/doc/a-lang/
	cp -r examples/* build/deb/usr/share/doc/a-lang/examples/
	gzip -9n -c docs/ac.1 > build/deb/usr/share/man/man1/ac.1.gz
	printf 'Package: a-lang\nVersion: $(VERSION_NAME)\nSection: devel\nPriority: optional\nArchitecture: amd64\nMaintainer: Aytict (https://aytict.fi)\nHomepage: https://aytict.fi\nDescription: A - a small C-like systems language\n The "A" compiler is written in x86-64 assembly and produces native\n executables for Linux (x86-64, ARM64, RISC-V 64, LoongArch64), Windows (x86-64) and\n Android (ARM64, x86-64, RISC-V 64) without any external assembler, linker or libc.\n' > build/deb/DEBIAN/control
	@mkdir -p dist
	dpkg-deb --root-owner-group --build build/deb dist/a-$(STEM).deb
	@ls -l dist/a-$(STEM).deb

install: build/ac
	install -d $(DESTDIR)$(PREFIX)/bin $(DESTDIR)$(PREFIX)/lib/a $(DESTDIR)$(PREFIX)/share/man/man1
	install -m 0755 build/ac $(DESTDIR)$(PREFIX)/bin/ac
	gzip -9n -c docs/ac.1 > $(DESTDIR)$(PREFIX)/share/man/man1/ac.1.gz

clean:
	rm -rf build dist

.PHONY: all test test-all examples dist deb install clean
