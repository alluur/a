# =============================================================================
#  A language compiler - build system
#
#    make            build the compiler           -> build/ac
#    make test       run the test-suite natively  (Linux x86-64)
#    make test-all   test every target (needs wine64 and qemu-user, see docs/TARGETS.md)
#    make examples   compile every example for every target
#    make dist       release binary               -> dist/ac-<code>-<release>.elf
#    make book       the book (HTML + EPUB)       -> build/book/html, dist/a-book-<code>-<release>.epub
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
	tests/https.sh
	tests/tui.sh

test-all: build/ac
	@for t in linux windows linux-arm64 android android-x64 linux-riscv64 android-riscv64 linux-loongarch64; do \
	    echo "== target: $$t"; TARGET=$$t tests/run.sh || exit 1; TARGET=$$t tests/link.sh || exit 1; done

examples: build/ac
	@mkdir -p build/examples
	@for t in linux windows linux-arm64 android android-x64 linux-riscv64 android-riscv64 linux-loongarch64; do \
	    for f in examples/*.a examples/gui/*.a examples/tui/*.a; do \
	        ./build/ac -t $$t $$f -v $(VERSION_CODE) -r $(RELEASE) -o build/examples/$$(basename $$f .a)-$$t.out || exit 1; \
	    done; echo "examples compiled for $$t"; done

dist: build/ac
	@mkdir -p dist
	cp build/ac dist/ac-$(STEM).elf
	strip dist/ac-$(STEM).elf
	@ls -l dist/ac-$(STEM).elf

deb: build/ac
	@mkdir -p dist
	packaging/deb/mkdeb.sh dist/a-$(STEM).deb $(VERSION_NAME) $(VERSION_CODE)
	@ls -l dist/a-$(STEM).deb

# the book "The A Programming Language": HTML site and EPUB (docs/book/, needs python3 and pandoc)
book: build/ac
	python3 docs/book/tools/build.py --out build/book --code $(VERSION_CODE) --release $(RELEASE)
	@mkdir -p dist
	cp build/book/a-book-$(STEM).epub dist/a-book-$(STEM).epub
	@ls -l dist/a-book-$(STEM).epub

# compile and run every code sample of the book and compare the output with the recorded one
book-samples: build/ac
	python3 docs/book/tools/samples.py --ac build/ac

install: build/ac
	install -d $(DESTDIR)$(PREFIX)/bin $(DESTDIR)$(PREFIX)/lib/a $(DESTDIR)$(PREFIX)/share/man/man1
	install -m 0755 build/ac $(DESTDIR)$(PREFIX)/bin/ac
	gzip -9n -c docs/ac.1 > $(DESTDIR)$(PREFIX)/share/man/man1/ac.1.gz

clean:
	rm -rf build dist

.PHONY: all test test-all examples dist deb book book-samples install clean
