# Text and strings

Text in A is a plain `char*`: a pointer to bytes that end with a zero byte, and the bytes are UTF-8. There is no string class and no hidden length, so a few small modules do the work that other languages build in. This chapter shows how to build, search and cut text, how to count characters instead of bytes, how to turn binary data into text and back, and how to match patterns with regular expressions.

**In this chapter**

* `strings`: a `StringBuilder`, search and replace, padding, splitting and joining;
* `utf8`: characters (code points) instead of bytes;
* `encoding`: Base64, hexadecimal and URL escapes;
* `codec`: text, binary digits and small pictures converted into each other;
* `regex`: a full regular expression engine with groups, look-ahead, lazy quantifiers and a step limit.

## Text in A on one page

Four facts explain almost everything in this chapter.

* A string is a pointer to bytes and ends at the first zero byte. `strlen(s)` counts **bytes**, not characters.
* String literals are stored in writable memory, so functions such as `trim` and `strUpper` can change them in place. Work on a copy (`strdup`) when you need the original.
* Functions that **return** text (`strings.concat`, `utf8.reverse`, `encoding.hexEncode` ...) make a new string on the heap. The heap is never freed (see [memory and pointers](#chap-memory-and-pointers)), which is fine for programs that finish, and something to keep in mind in a loop that runs a million times.
* Binary data can contain zero bytes, so functions that handle it (`encoding`, `hash`, `zlib`) take a pointer **and a length**. Do not use `strlen` on such data.

## Building and changing strings: `strings`

The `strings` module is the toolbox for everyday text work. Everything it returns is a new string; the arguments stay as they are.

### StringBuilder

Joining many small pieces with `concat` copies the text each time. A `StringBuilder` keeps one buffer that grows as needed, so it is the right tool when you assemble a line, a report or a file piece by piece.

{{sample text/strings_builder}}

What to notice:

* `strings.StringBuilder sb;` lives on the stack, only the text lives on the heap.
* `view()` returns a pointer into the builder. It stays valid until you append again, because the buffer may move. `toString()` returns an independent copy.
* `length()` is in bytes, `clear()` empties the builder and keeps its buffer.

### Searching, replacing and padding

| Function | What it does |
|---|---|
| `concat(a, b)` | `a` followed by `b` |
| `repeat(s, n)` | `s` written `n` times |
| `reverse(s)` | the bytes in the opposite order (use `utf8.reverse` for text with accents) |
| `count(s, sub)` | how many times `sub` occurs, without overlaps |
| `lastIndexOf(s, c)` | the index of the last character `c`, or -1 |
| `replace(s, from, to)` | every occurrence of `from` replaced by `to` |
| `padLeft(s, width, fill)`, `padRight(...)` | fill up to `width` characters with the character `fill` |
| `capitalize(s)`, `upper(s)`, `lower(s)` | letter case (ASCII letters only) |
| `isBlank(s)` | true when the text is empty or only white space |

{{sample text/strings_functions}}

What to notice:

* `count("aaaa", "aa")` is 2: matches never overlap, and `replace` works the same way.
* `padLeft` and `padRight` never cut: a text that is already too long comes back as it is.
* Replacing with an empty text deletes the matches.
* The case functions know only the letters A to Z. For accented letters you need your own code with `utf8`.

### Splitting and joining

`split` cuts a text at every occurrence of one separator character and stores the pieces in an array you provide. `join` is the opposite.

{{sample text/strings_split_join}}

What to notice:

* The third piece is empty: two commas in a row give an empty field, they are not skipped.
* `max` limits how many pieces are stored. The return value is the number of pieces stored, and the rest of the text is dropped.
* The separator is one character. For a longer separator or a pattern use `regex` (below).

### What every program already has

Some string functions are part of the standard prelude, so they work without any `import`: `strlen`, `streq`, `strcmp`, `strcpy`, `strdup`, `find`, `contains`, `indexOf`, `startsWith`, `endsWith`, `substr`, `trim`, `strUpper`, `strLower` and `streqi`.

{{sample text/strings_std}}

What to notice:

* `trim` and `strUpper` change the text **in place**. The sample copies the string first with `strdup`.
* `trim` returns a pointer that may be a little further into the same text, because it removes the leading blanks by moving the pointer.
* `find` and `indexOf` give the position or -1; `contains`, `startsWith`, `endsWith` give a truth value.
* `substr(s, start, length)` makes a new string. It does not check that the range is inside `s`.

See the [API reference of `strings`](#api-strings).

## UTF-8: `utf8`

A **code point** is the number that Unicode gives to a character: 65 for `A`, 233 for `é`, 128512 for the smiley. UTF-8 stores a code point in one to four bytes. `strlen` counts bytes, so `"é"` has length 2. The `utf8` module works with code points, which are plain `int` values. Strings stay ordinary `char*`.

{{sample text/utf8_length}}

What to notice:

* `strlen` says 29 and `utf8.length` says 18 for the same text.
* `utf8.decode(s, pos, &cp)` reads one code point at byte offset `pos` and returns how many bytes it used. That is the loop you write to walk through a text.
* `utf8.byteOffset(s, index)` converts a character index into a byte offset.
* `utf8.reverse` keeps multi-byte characters intact. It handles at most 1024 code points; a longer text is cut off.
* A code point is not always what a reader sees as one character: an accent can be a separate code point, and `utf8.length` counts it as one.

Converting between text and arrays of code points:

{{sample text/utf8_codepoints}}

What to notice:

* `toCodepoints(s, out, max)` stores at most `max` numbers and returns how many. `fromCodepoints(cps, n)` builds a new string.
* `utf8.encode(cp, buf)` writes up to 4 bytes, does **not** add a zero byte and returns the byte count. Add the terminator yourself, as the sample does.

Real data is not always valid UTF-8.

{{sample text/utf8_validate}}

What to notice:

* A byte that cannot start or continue a character decodes as U+FFFD (the replacement character) and uses exactly one byte. A loop over broken text therefore always makes progress.
* `isValid` checks the structure: lead bytes and continuation bytes, and it rejects the bytes C0, C1 and F5 to FF.

::: warning
`isValid` does **not** reject overlong three and four byte forms, surrogate halves (U+D800 to U+DFFF) or code points above U+10FFFF. If you must be strict with untrusted input, add your own check.
:::

See the [API reference of `utf8`](#api-utf8).

## Base64, hexadecimal and URLs: `encoding`

Binary data cannot go into a JSON string, a URL or an e-mail as it is. The `encoding` module turns bytes into safe text and back. Functions that produce text return new strings; the decoding functions write into a buffer you provide and return the number of bytes, or -1 when the input is not valid.

{{sample text/encoding_base64}}

What to notice:

* The inputs are the Base64 test vectors of RFC 4648. The `=` padding grows as the input shortens.
* You pass the **length** of binary data: `base64Encode(data, n)`. That is why bytes that are 0 or 255 work.
* The output buffer of `base64Decode` needs about `strlen(text) * 3 / 4` bytes. The decoder skips white space and accepts text with or without the `=` padding.
* The decoder returns -1 for characters that are not part of the alphabet.

{{sample text/encoding_hex_url}}

What to notice:

* `hexEncode` writes lowercase digits; `hexDecode` accepts both cases and returns -1 for an odd number of digits or a non-hex character.
* `urlEncode` leaves letters, digits and `- _ . ~` alone and writes every other **byte** as `%XX`. A UTF-8 character therefore becomes several escapes.
* `urlDecode` turns `+` into a space and keeps a broken escape such as `%zz` as text.

See the [API reference of `encoding`](#api-encoding).

## Converters: `codec`

`codec` converts between text, binary digits and small greyscale pictures. It was made to feed neural networks (see [the `nn` section of the data formats chapter](#chap-data-formats)), but it is also a handy way to look at bits.

### Text and binary digits

{{sample text/codec_binary}}

What to notice:

* `textToBinary(text, sep)` writes 8 binary digits per byte with `sep` between the bytes. `binaryToText` reads them back and ignores separators.
* `intToBinary(n, width)` and `binaryToInt` work on numbers.
* `bytesToBits` writes one byte (0 or 1) per bit, which is the form a network wants as input. `bitsToBytes` packs them again.

### Pictures

A `codec.Image` has a width `w`, a height `h` and one byte per pixel in `px`: 0 is black and 255 is white. `binaryToImage` reads rows of `0` and `1` where **1 is a dark pixel**.

{{sample text/codec_image}}

What to notice:

* `get(x, y)` outside the picture returns 255 (white); it does not crash.
* `scaleUp(k)` turns every pixel into a `k` by `k` block. `invert()` swaps dark and light in place.
* `toAscii(img, step)` draws the picture with characters, so you can look at it in a terminal: ten shades from `@` (black) to a blank (white), taken from every `step`-th pixel, so a bigger `step` gives a smaller drawing.

### Text as a picture and back

`textToImage` draws text with a built-in 5 by 7 pixel font. `imageToText` reads such a picture back, even when a few pixels are wrong.

{{sample text/codec_text_image}}

What to notice:

* Every character takes 6 columns (5 plus one blank) and every line 9 rows, and the picture has a margin of one pixel, all multiplied by the scale: `n` characters on one line give a picture `(6n + 1) * scale` wide and `10 * scale` high.
* `imageToText(img, 0)` detects the scale; pass the scale when you know it.
* After flipping six pixels the reader still finds the right text, because it picks the closest glyph. `imageToTextWith(img, scale, recogniser)` lets your own neural network do that choice.
* The font has the characters 32 to 126 (ASCII). Other characters come out as `?`.

### Image files

{{sample text/codec_files}}

What to notice:

* `writePgm` / `readPgm` (8 bit grey), `writePbm` / `readPbm` (1 bit, binary or plain text form) and `writeBmp` / `readBmp` (reads 1, 8, 24 and 32 bit) cover the formats that any image viewer opens.
* The binary PBM is the smallest file (229 bytes: one bit per pixel); PGM stores a byte per pixel, the plain text PBM a character per pixel, and the BMP is the largest.
* A reader returns `null` for a file that is missing or is not in that format.

`codec` has more helpers for networks (`textToVector`, `oneHot`, `fontSet` ...); the [API reference of `codec`](#api-codec) lists them all.

## Regular expressions: `regex`

A regular expression is a short pattern that describes a set of texts: `\d+` means "one or more digits". The `regex` module is a backtracking engine with Perl and Python rules: the leftmost match wins, alternatives are tried in order and quantifiers are greedy unless you add `?`.

### The syntax

| Pattern | Meaning |
|---|---|
| `abc`, `\.`, `\n`, `\t`, `\xHH` | literal characters; a backslash makes a special character literal |
| `.` | any character except a line break (a whole UTF-8 character, not one byte) |
| `[abc]` `[a-z]` `[^0-9]` `[[:alpha:]]` | character classes, ranges, negation, POSIX names |
| `\d` `\w` `\s` and `\D` `\W` `\S` | digits, "word" characters and white space (`\d` and `\s` are ASCII only; `\w` also matches every non-ASCII character) |
| `^` `$` `\A` `\Z` `\b` `\B` | start and end of the text (of each line with `(?m)`), start and end always, word boundary and its opposite |
| `*` `+` `?` `{n}` `{n,}` `{n,m}` `{,m}` | repetition (greedy) |
| `*?` `+?` `??` `{n,m}?` | the lazy versions: as few as possible |
| `a\|b` | alternatives |
| `(...)` `(?:...)` `(?P<name>...)` `(?<name>...)` | a numbered group, a group that does not capture, a named group |
| `\1` ... `\9`, `(?P=name)` | back references to what a group matched |
| `(?=...)` `(?!...)` | look-ahead, positive and negative |
| `(?i)` `(?s)` `(?m)` `(?i:...)` | flags: ignore case, `.` matches a line break, `^` and `$` per line; the flags can also be given as the second argument of `compile` |

Not supported: look-behind (`(?<=...)`), possessive quantifiers (`a++`), atomic groups (`(?>...)`) and Unicode properties (`\p{L}`). `compile` reports them as errors. Case folding with `(?i)` is for the ASCII letters only.

### Compiling and searching

`regex.compile(pattern, flags)` returns a `Regex*`. Check its `ok` field: a bad pattern sets `ok` to false and puts the reason into `error` and the position into `errorPos`. The main methods take the text, its length and an array for the results:

| Method | Result |
|---|---|
| `search(text, n, from, caps)` | the start of the first match at or after `from`, or -1 |
| `matchAt(text, n, pos, caps)` | the end of a match that starts exactly at `pos`, or -1 |
| `matchFull(text, n, caps)` | true when the **whole** text matches |
| `groupIndex("name")` | the number of a named group (0 when there is no such name) |
| `dispose()` | frees the memory the compiled pattern uses |

`caps` is an `int` array with room for `2 * (groups + 1)` numbers (66 is always enough): `caps[2*g]` and `caps[2*g+1]` are the start and end offsets of group `g`, and group 0 is the whole match. A group that did not take part has -1 in both places. Pass `null` when you only want to know whether there is a match.

{{sample text/regex_search}}

What to notice:

* The results are **offsets** into the text, not copies. To print a group, the sample uses `%.*s` with the length and the address `&text[caps[2*g]]`.
* `matchFull` fails for `"mail bob@example.com"` because the pattern must cover the whole text, while `search` would find the address inside it.
* `matchAt` is anchored: it is how you write a tokenizer that reads the next token at the current position.

### Finding every match

There is no "find all" call. You write a loop with `search` and move `from` to the end of the last match.

{{sample text/regex_find_all}}

What to notice:

* `pos = caps[1] > at ? caps[1] : at + 1;` continues after the match and steps one byte forward after an empty match. Without this a pattern such as `x*` would loop for ever.
* Groups give you the parts: the sample turns groups 1 and 2 into numbers with `atoi`.

### Replacing

`replaceGroups(pattern, text, replacement)` replaces every match. In the replacement `$0` is the whole match, `$1` to `$9` and `${n}` are groups, and `$$` is a dollar sign. The result is a new string.

{{sample text/regex_replace}}

What to notice:

* `$1` takes **one** digit, so `$10` is group 1 followed by a 0. Use `${10}` for groups from 10 on; `${2}` is the same as `$2`. A group number that does not exist gives an empty text, and a `$` that is not followed by a digit, `{` or `$` stays as it is.
* An empty match is replaced as well: `x*` on `abc` puts a dash before and after every letter, like Python 3.7 and newer.
* A group that did not take part in the match contributes nothing.
* `replaceAll` uses the replacement literally and the *simple dialect* described at the end of this section.

### Anchors and boundaries

{{sample text/regex_anchors}}

What to notice:

* `^` and `$` mean the start and the end of the **text**. With `(?m)` they match at every line.
* `$` also matches just before a final line break, so `cat$` matches the text `"cat\n"`. `\Z` does not: it is the very end.
* `\b` is a word boundary, `\B` the opposite. `\bcat\b` finds the word, `\Bcat\B` finds it inside `concatenate`.

### Classes and quantifiers

{{sample text/regex_classes}}

What to notice:

* `<.+>` is greedy and swallows `<a><b>` as one match. The lazy `<.+?>` finds `<a>` and `<b>` separately.
* In `Z|x|cd` the matches come in text order. At each position the first alternative that fits wins.
* A dot must be written `\.` to mean a dot: `\d+\.\d+` finds `4.50` and nothing else.

### Named groups, back references and non-capturing groups

{{sample text/regex_named_groups}}

What to notice:

* A named group is still numbered: `year` is group 1. `groupIndex("year")` gives you the number, and 0 means "no such name".
* `\1` repeats what group 1 matched. That finds doubled words.
* `(?:...)` groups for repetition without taking a group number, so `groups` stays small.
* A group that did not take part (the `(a)` in `(a)|(b)` matching `b`) has -1 in both offsets.

### Flags and look-ahead

{{sample text/regex_flags}}

What to notice:

* `(?i)` can stand at the start of the pattern or in front of a part of it, `(?i:...)` limits it to the parentheses. The `flags` argument of `compile` (`regex.F_ICASE`, `F_DOTALL`, `F_MULTILINE`) has the same effect on the whole pattern.
* `(?=px)` looks ahead without using up the text. The match for `\d+(?=px)` is `24`, not `24px`.
* The negative look-ahead has to exclude digits too (`(?!\d|px)`), otherwise `\d+` can simply stop one digit earlier.

### Unicode

{{sample text/regex_utf8}}

What to notice:

* `.` and `[^...]` use up one whole UTF-8 character, so `Gr.{3}` matches `Grüße` (5 characters, 7 bytes).
* `\w` matches every non-ASCII character, so words in any script are found.
* A class can contain a range of code points, here `[ぁ-ヶ]` for hiragana and katakana.
* `(?i)` ignores the case of ASCII letters only: `ü` does not match `Ü`.

### Errors and limits

{{sample text/regex_limits}}

What to notice:

* A pattern that does not compile sets `ok` to false. Using such a `Regex` is safe: searches simply find nothing.
* A pattern can have at most 32 capturing groups (`regex.MAXGROUPS`).
* The engine stops after **5 million steps**: `search` returns -1 and `exceeded` is true. You can change the limit per pattern with `stepLimit`.

::: warning
Nested quantifiers such as `(a+)+b` can take exponential time on text that does not match, and someone who controls the pattern or the text can use that to freeze a program. The step limit keeps your program running. Look at `exceeded` when a search finds nothing, because "no match" and "gave up" both return -1.
:::

### The simple functions

For a quick test in a tool, four functions compile and cache the pattern for you: `matches` (the whole text), `test` (anywhere), `search` (the position and length) and `quote` (escape a text so that it matches itself). The last eight patterns are cached.

{{sample text/regex_simple}}

What to notice:

* `matches`, `test`, `search` and `replaceAll` use the **simple dialect**: `( ) | { }` are ordinary characters, a `^` that is not first and a `$` that is not last are ordinary characters, `.` also matches a line break. That is why `regex.test("main()", line)` finds a function call and behaves like `grep`.
* `compile(pattern, 0)` and `replaceGroups` use the full syntax. `compile(pattern, regex.F_SIMPLE)` gives the simple dialect as an object.
* `quote` is for user input: build a pattern from `quote(userText)` and it matches exactly that text.

See the [API reference of `regex`](#api-regex).

## Summary

* A string is a `char*` of UTF-8 bytes ending in a zero byte; `strlen` counts bytes.
* `strings` returns new strings and leaves its arguments alone; use a `StringBuilder` to build text piece by piece.
* `utf8` counts and walks code points; invalid bytes decode as U+FFFD, one byte at a time.
* `encoding` converts bytes to Base64, hexadecimal and URL escapes and back; binary data always travels with its length.
* `codec` converts text to binary digits and to small pictures, and reads and writes PGM, PBM and BMP files.
* `regex` has groups, named groups, back references, look-ahead, lazy quantifiers and flags. It returns offsets into your text, has no built-in "find all" and stops runaway patterns after 5 million steps.
* The four simple functions (`matches`, `test`, `search`, `replaceAll`) use an older, simpler dialect.

## Where next

* [Collections and algorithms](#chap-collections-and-algorithms): lists, maps, sorting and searching.
* [Data formats](#chap-data-formats): JSON, CSV and INI are text formats you will parse with the tools of this chapter.
* [Memory and pointers](#chap-memory-and-pointers): why returned strings are never freed.
* API references: [`strings`](#api-strings), [`utf8`](#api-utf8), [`encoding`](#api-encoding), [`codec`](#api-codec), [`regex`](#api-regex).
