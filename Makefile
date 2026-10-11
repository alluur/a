# A language compiler - build system
NASM  ?= nasm
LD    ?= ld
SRC    = $(wildcard src/*.asm) src/defs.inc lib/std.a

all: build/ac

build/ac: $(SRC)
	@mkdir -p build
	$(NASM) -f elf64 -i src/ src/ac.asm -o build/ac.o
	$(LD) -o build/ac build/ac.o

clean:
	rm -rf build

.PHONY: all clean
