# Notes of the standard library 1 contributor (text, collections, numbers, data formats)

Chapters: `src/30-text-and-strings.md`, `src/31-collections-and-algorithms.md`, `src/32-numbers.md`, `src/33-data-formats.md`.
Samples: `samples/text`, `samples/collections`, `samples/numbers`, `samples/data` (94 samples, all with recorded output).
Everything below was checked with `build/ac` of this branch on Linux x86-64.

## (a) Compiler and library bugs, quirks and limits

Each item was reproduced. The chapters describe the behaviour as it is and, where it matters, warn the reader.

### 1. `utf8.isValid` accepts some invalid UTF-8

Overlong three and four byte forms, surrogate halves and code points above U+10FFFF are reported as valid. Only C0, C1 and F5 to FF are rejected, and broken continuation bytes.

```c
import utf8;
int main() {
    printlnInt(utf8.isValid("\xE0\x80\x80"));       // 1 (overlong U+0000), should be 0
    printlnInt(utf8.isValid("\xED\xA0\x80"));       // 1 (surrogate U+D800), should be 0
    printlnInt(utf8.isValid("\xF0\x80\x80\x80"));   // 1 (overlong)
    printlnInt(utf8.isValid("\xF4\x90\x80\x80"));   // 1 (> U+10FFFF)
    printlnInt(utf8.isValid("\xC0\x80"));           // 0 (correct)
    return 0;
}
```

The chapter says so in the section on `utf8`.

### 2. `utf8.reverse` silently cuts texts longer than 1024 code points

```c
import utf8;
int main() {
    char* big = alloc(3000);
    for (int i = 0; i < 2000; i++) { big[i] = 'a' + i % 26; }
    printlnInt(strlen(utf8.reverse(big)));          // 1024, not 2000
    return 0;
}
```

(The function uses a local array `int cps[1024]` and `toCodepoints(s, cps, 1024)`.)

### 3. `json`: integers beyond 64 bits wrap, leading zeros are accepted, `asInt()` of an exponent number

```c
import json;
int main() {
    json.Json* v = json.parse("[99999999999999999999, 007, 1e3, 0.75]");
    println(json.stringify(v));                     // [7766279631452241919,7,1e3,0.75]
    printlnInt(v->at(2)->asInt());                  // 1 (the exponent is not applied)
    printlnInt(v->at(3)->asInt());                  // 0
    return 0;
}
```

* `99999999999999999999` becomes 7766279631452241919 without an error (and `stringify` writes the wrapped number, not the original text, so data is lost silently).
* `007` is accepted as 7 (the standard forbids leading zeros).
* The header comment of `lib/json.a` says numbers with a fraction or an exponent keep their text and "asInt() truncates them". For `1e3` that gives 1, not 1000. This is probably unintended; the book describes the actual behaviour and tells readers not to use `asInt()` on exponent numbers.
* There is no `newDouble` / `newNumber(text)`: a number with a fraction can only come from `parse`.
* Nesting is limited to about 200 levels; errors have no position (`json.errorMessage()` returns only a short text).
* `doc->get("a")->get("b")` when `a` is missing dereferences `null` and crashes with a segmentation fault (expected for A, mentioned in the chapter).

### 4. `nn.Network.accuracy` is always 100 for a network with one output

`accuracy` compares `argmax(prediction)` with `argmax(target)`; with a single output both are index 0.

```c
import nn;
import fixed;
int main() {
    int sizes[3] = {2, 4, 1};
    fixed.seed(1);
    nn.Network* net = new nn.Network(3, sizes, nn.ACT_TANH, nn.ACT_SIGMOID);
    int x[4] = {0, 0, 0, 0};
    int t[2] = {fixed.ONE, 0};
    printlnInt(net->accuracy(x, t, 1));             // 100 (untrained network)
    int t2[2] = {0, 0};
    printlnInt(net->accuracy(x, t2, 1));            // 100 (wrong target too)
    return 0;
}
```

The XOR sample therefore counts the answers itself. The chapter has a warning.

### 5. `ini`: a value that contains a double quote does not survive `toString()` and `parse()`

```c
import ini;
int main() {
    ini.Ini* c = new ini.Ini();
    c->set("s", "k", "say \"hi\"");
    char* t = c->toString();                        // k = "say "hi""
    ini.Ini* d = ini.parse(t);
    println(d->get("s", "k", "?"));                 // say
    return 0;
}
```

`toString()` puts the value in quotes when it contains `;`, `#` or `"` but does not escape an inner quote, and the parser ends the value at the next quote. Also: `getBool` only knows the **lower case** words (`Yes`, `TRUE` give the fallback), and the header says only that *names* are case-sensitive.

### 6. `regex`: the flag `(?x)` is accepted but does nothing

```c
import regex;
int main() {
    regex.Regex* re = regex.compile("(?x) a b", 0);
    printlnInt(re->ok);                             // 1: no error
    printlnInt(re->search(" a b", 4, 0, null));     // 0: the blanks are literal
    printlnInt(re->search("ab", 2, 0, null));       // -1: verbose mode is not implemented
    return 0;
}
```

An unknown flag letter should be an error, as `(?>...)` ("unknown extension") and `(?<=...)` ("look-behind is not supported") are. Also: `groupIndex("unknown")` returns 0, which is also the number of the whole match; the header does not say so.

### 7. Smaller points

* `sort.sortStrings` is an insertion sort (O(n^2)); `sort.binarySearch` with duplicates returns an arbitrary equal element.
* `csv.joinLine` silently handles at most 64 fields. `csv.parseLine` works on one line, so quoted fields with line breaks cannot be read; there is no multi-line API.
* `tar.Writer` writes mode 644 / 755, owner 0 and modification time 0 for every entry; there is no way to set them.
* `fixed.mul` overflows silently when the raw product exceeds 2^63: `fixed.mul(fixed.fromInt(3000), fixed.fromInt(3000))` prints -7777216.0.
* `decimal.parse` returns 0 for text that is not a number, which cannot be told from a real 0 (call `decimal.isValid` first).
* `arith.rat(1, 0)` is 0/1, not an error.

## (b) Places where the reference documents are wrong or incomplete

1. **`double` does exist.** `docs/book/WRITING.md` ("No floats: A has no float / double type"), `src/01-welcome.md` ("There is no float or double type") and `docs/CLIB.md` describe doubles only as ints holding bit patterns. The compiler on this branch has a real `double` type (and `float` as an alias): `double x = 2.5; double y = x * 3 + 0.25;`, casts `(int) d`, comparisons, `printlnDouble`, `doubleToFixed`, `parseDouble`, and the module `dmath` (typed `sqrt sin pow ...`). `docs/LANGUAGE.md` section 7 ("`static if`, `::` and floating point") describes it correctly, and `tests/t92_double.a` tests it. The samples `numbers/dfloat_basics`, `dfloat_bits`, `dmath_functions` and `dmath_simulation` use the type; chapter 32 documents it and says that the C library shows the same numbers as `int` bit patterns. **The Welcome chapter and `WRITING.md` should be corrected by the coordinator.**
2. `docs/CLIB.md` ("How A differs from C"): "Structs cannot be passed or returned by value". They can (`docs/LANGUAGE.md` section 7); `arith.Rational`, a struct with operators, is passed and returned by value in `numbers/arith_rational`.
3. `docs/LANGUAGE.md` section 12b lists `sha384` among the hex functions of `hash`. There is only `sha384Raw` (and `digest(384, ...)`); `md5`, `sha1`, `sha256` and `sha512` return hex text.
4. `lib/nn.a` header: the XOR example calls `net->fit(inputs, targets, 4, 3000, fixed.fromText("0.5"))` with five arguments. `fit` takes six (the last is `stopBelow`): the compiler says "wrong number of arguments in call". `docs/LANGUAGE.md` has the correct call.
5. `lib/regex.a` documents `groupIndex(name)` without saying what an unknown name gives (0), and does not say that `(?x)` is ignored.
6. `lib/utf8.a`: "true if the whole text is well formed UTF-8" is stronger than what `isValid` checks (see 1 above).
7. `lib/json.a`: "asInt() truncates them" is wrong for numbers with an exponent (see 3 above).

## (c) Not covered, and why

All 28 assigned modules have at least one sample that runs. None is compile-only.

Features that are only mentioned in the text, or not shown at all:

* `nn`: `Autoencoder`, `SOM`, `Elman`, `LSTM` and `ConvNet`, and `Network.save` / `load` (only listed in a table). The samples show `Perceptron`, `Network` (XOR) and `Hopfield`.
* `codec`: the helpers that build vectors for networks (`textToVector`, `oneHot`, `fontSet`, `glyphVector` ...), `imageToTextWith`, `crop`, `resize`, `bitsToImage` and the byte forms `imageToBytes` / `bytesToImage`. A combined codec + nn character recogniser would be a good sample for a later edition (`examples/ocr.a` does it).
* `bn`: `mulInto`, `toMont` / `fromMont`, `addMod` / `subMod` and `invMont` (the curve arithmetic helpers).
* `regex`: `searchAdv`, `replaceAll` on its own, `(?P=name)` and `\10`..`\32` back references are listed in the syntax table but not demonstrated.
* `bytebuf`: `Reader.seek`, `take`, `i8` / `i16` / `i32`, `Buf.align`, `fill` and the 16 bit `patch` functions.
* `hash`: the `Sha512` class (incremental hashing) is not shown; `hash` is used on complete buffers only.
* `zlib`: the returned buffers are `malloc` memory that should be `free`d; the samples do not free them.
* `random.clockSeed()` and `datetime.now()` / `nowMillis()` are described but not run, because their output cannot be recorded.

## What was and was not verified

Verified: every sample compiles and runs on Linux x86-64, the recorded output was read and every number that has an independent reference was checked against it: hash test vectors (MD5, SHA-1, SHA-256, SHA-384, SHA-512, HMAC RFC 4231 case 2 and RFC 2202), the CRC-32 check value, Adler-32 of "Wikipedia", `2^255 - 19` Fermat test, the RSA round trip, factorials, Fibonacci numbers, the number of digits of 2^1000 (Python), `1000000000` as 2001-09-09 01:46:40 UTC, the timestamp of 2024-02-29 12:30:15 UTC, the `.tar.gz` of `data/zlib_tgz` and the tar of `data/tar_file` with the system `tar` and `gzip -t`, and the size of the same data with `gzip -9`.
Every sample also compiles for all eight targets (`samples.py --targets`).

Not verified: the programs were **not run** on ARM64, RISC-V, LoongArch, Windows or Android (no emulator was started, as the rules say). The software floating point, fixed point and hash code is integer-only and should print the same everywhere, but that is an expectation, not a test. The `datetime_posix_zones` sample depends on the C library's handling of `TZ` rules, which is the part most likely to differ on Windows. Performance claims were not measured. The HTML build of the chapters was checked with `tools/build.py --lint` (0 errors; the only warnings of my chapters are links to chapters that do not exist yet: `chap-memory-and-pointers`, `chap-cryptography`, `chap-c-library-tour`, `chap-system-programming`).
