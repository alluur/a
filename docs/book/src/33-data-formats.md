# Data formats

Programs read and write data in formats that other programs understand: JSON from a web service, CSV from a spreadsheet, INI files for settings, `.tar.gz` archives, file names, dates and checksums. This chapter covers the modules for these formats, and ends with `nn`, a small neural network library that you can use to learn patterns from data.

**In this chapter**

* `json`: parse, navigate, build and write JSON;
* `csv` and `ini`: the two simplest text formats for tables and settings;
* `tar` and `zlib`: archives, and compression that other tools can read;
* `path`: taking file names apart;
* `datetime`: calendar arithmetic in UTC, and time zones;
* `hash`: checksums, cryptographic digests and HMAC;
* `nn`: perceptrons, a back-propagation network and a Hopfield memory.

## JSON: `json`

JSON is the format of web services and configuration files. The `json` module turns text into a tree of `Json` values and a tree back into text. A `Json*` can be an object, an array, a string, a number, a boolean or null, and you ask which with `isObject()`, `isArray()`, `isString()`, `isNumber()`, `isBool()` and `isNull()`.

### Parsing and navigating

{{sample data/json_parse}}

What to notice:

* `json.parse(text)` returns `null` for invalid text, and `json.errorMessage()` says why.
* `get("key")` finds a member of an object and `at(i)` an element of an array; `size()` counts members or elements. `asString()`, `asInt()` and `asBool()` read a value.
* A missing member gives `null`, so `doc->get("a")->get("b")` crashes (a segmentation fault) when `a` is missing. Test with `has` or for `null` first.
* The `*Or` helpers (`intOr`, `stringOr`, `boolOr`) return your fallback when the member is missing **or has the wrong kind**. They are the short way to read optional settings.
* `asString()` of something that is not a string is `""`, and `asInt()` of something that is neither a number nor a boolean is 0.

### Walking a document of unknown shape

{{sample data/json_walk}}

What to notice:

* `keyAt(i)` gives the name of member `i` of an object and `at(i)` its value, so a `for` loop visits every member **in the order of the text**.
* The function calls itself for nested objects and arrays. That is the whole trick for working with any JSON document.

### Building and writing

{{sample data/json_build}}

What to notice:

* `newObject()`, `newArray()`, `newInt(n)`, `newString(s)`, `newBool(b)` and `newNull()` create values. `set(key, value)` adds a member (or replaces it, keeping its place) and `push(value)` appends to an array. Strings are copied.
* `stringify` writes compact text, `pretty` indents by two spaces. Both return a new string.
* Quotes, backslashes and control characters in strings are escaped for you.
* There is no `newDouble`: a number with a fraction can only come from parsing (see below).

### Changing a document

{{sample data/json_modify}}

What to notice:

* Whole numbers are exact 64-bit integers. A number with a fraction or an exponent keeps its **original text**, and `stringify` writes it back unchanged. A round trip does not lose digits.
* `asInt()` of such a number does not round: `0.75` gives 0, and `1e3` gives 1, because the exponent is not applied. Do not use `asInt()` on numbers written with an exponent.
* Integers beyond 64 bits do not fit: `99999999999999999999` wraps around silently.
* A parsed document can be edited with `set` and `push` and written again.

### Strings and Unicode

{{sample data/json_strings}}

What to notice:

* `\n`, `\t`, `\r`, `\b`, `\f`, `\"`, `\\`, `\/` and `\uXXXX` are decoded, including surrogate pairs such as `\ud83d\ude00` for a character outside the first 65536. The result is ordinary UTF-8.
* Two escapes do not survive the trip into a C string. `\u0000` is dropped, because text in A ends at the first zero byte. A single surrogate without its partner (`\ud83d` alone) is not an error, but it becomes three bytes that are not valid UTF-8; a high surrogate followed by an escape that is not a low surrogate is the error `bad surrogate pair`.
* The writer escapes only what JSON requires (quote, backslash, control characters) and leaves UTF-8 as it is.
* A raw control character, such as a real tab inside a string, is an error when parsing (`control character in string`). Write it as `\t`.

### Errors

{{sample data/json_errors}}

What to notice:

* The messages are short and do not give a position. Show them to the user together with the input.
* A bare value such as `42` is a valid document, and blanks around it are fine.
* The parser is a little more tolerant than the JSON standard: for example it accepts a number with leading zeros (`007`) as 7, and a repeated key is not an error (the last value wins, and the member keeps the place of the first). Arrays and objects may be nested 201 levels deep; one more gives the error `nested too deeply`.

See the [API reference of `json`](#api-json).

## CSV: `csv`

CSV stores a table as lines of fields separated by commas. The difficulty is a field that contains a comma or a quote: it is written in double quotes, and a quote inside it is doubled. `csv` handles one **line** at a time.

{{sample data/csv_parse}}

What to notice:

* `csv.parseLine(line, sep, out, max)` fills `out` with new strings and returns how many fields it stored. The separator is a character, so `';'` and tab (`9`) work too.
* Empty fields count: `a,,c,` has four fields.
* An empty line is one empty field. `max` limits how many fields are stored: with `max` 2, the line `x,y,z,w` gives 2.
* A quoted field may contain the separator, and `""` inside quotes is one quote.

{{sample data/csv_write}}

What to notice:

* `quote(field, sep)` adds quotes only when the field contains the separator, a quote or a line break.
* `joinLine(fields, n, sep)` builds one line (up to 64 fields).
* What `joinLine` writes, `parseLine` reads back.

A small report shows the usual work: split each line, convert numbers, add up.

{{sample data/csv_table}}

What to notice:

* The first line is a header, so the loop starts at 1.
* The price `2.90` is converted to cents with `atoi` on both sides of the dot, to stay in integers. This only works when every price has exactly two digits after the dot (`2.5` would read as 205 cents). For real money code use [`decimal`](#chap-numbers).
* Fields that contain line breaks are not supported, because `parseLine` sees one line. Read the file line by line. `parseLine` does not remove a carriage return, so with a file that has Windows line endings (CRLF) the last field of each line ends in `\r` unless you strip it first.

See the [API reference of `csv`](#api-csv).

## INI files: `ini`

INI files are settings in `[sections]` with `key = value` lines. Lines that start with `;` or `#` are comments, and so is the rest of a value line after ` ;` or ` #`. Values may be put in double quotes to keep ` ;` and ` #` (a `;` or `#` that follows a non-blank character is part of the value anyway). Blanks inside a value are always kept, and blanks at the very start or end are trimmed, even inside the quotes. Keys before the first section belong to the section `""`.

{{sample data/ini_parse}}

What to notice:

* `get(section, key, fallback)` returns the fallback for a missing key. `getInt` and `getBool` convert, and also return the fallback when the value is not a number (it has to start with digits, after an optional `-`) or not one of the boolean words below.
* The booleans are `true`, `yes`, `on`, `1` and `false`, `no`, `off`, `0`, in **lower case**.
* Names are case-sensitive: `[Server]` is not `[server]`.
* The fields `count`, `sections`, `keys` and `values` are public, so you can list every setting.

{{sample data/ini_write}}

What to notice:

* `set` adds or replaces, `remove` deletes (and returns whether the key was there), `toString()` writes INI text.
* A section that has no keys left is not written.
* `ini.load(path)` reads a file and returns `null` when it cannot be read.
* `getBool("x", "c", true)` returns the fallback for `Yes`, because only lower case is recognised.

See the [API reference of `ini`](#api-ini).

## Archives: `tar`

A tar archive is a sequence of 512-byte blocks: a header for each file, the file data padded to 512 bytes, and two empty blocks at the end. The `tar` module builds and reads archives **in memory** (POSIX ustar format). Use `zlib` to compress the result, and ordinary file functions to put it on disk.

{{sample data/tar_archive}}

What to notice:

* `Writer.add(name, data, n)` adds a file, `addDir(name)` a directory, and `finish(&n)` returns the archive bytes and their length. The archive above is 4096 bytes: four entries need 512 bytes each for their headers (2048), the two non-empty files 512 each for their data (1024), plus 1024 for the end.
* `Reader.next()` moves to the next entry and sets `name`, `size`, `isDir`, `mode` and `data`. `data` points **into the archive buffer**; it is not a copy and has no terminating zero, so the sample copies with `substr`.
* `next()` returns false at the end and also when a header is damaged. Then `bad` is true.
* Files get mode 644 and directories 755. The modification time and the owner are 0.

{{sample data/tar_file}}

What to notice:

* A name of up to 100 characters goes into the header as it is. A longer name is split at a `/` into the ustar prefix field (at most 155 characters) and the name field (at most 100), so 256 characters is the longest possible. `add` returns false when a name cannot be split that way.
* Writing the archive to disk and reading it back are ordinary file calls (`fileOpen`, `fileWrite`, `fileRead`). The archive is binary, so it needs a length and not `strlen`.
* Plain files and directories are read. Links and device nodes are skipped, and GNU long names are understood.

See the [API reference of `tar`](#api-tar).

## Compression: `zlib`

`zlib` compresses with DEFLATE (RFC 1951) and reads and writes both containers that wrap it: **zlib** (RFC 1950, used by PNG and HTTP) and **gzip** (RFC 1952, the `.gz` files).

| Function | Output |
|---|---|
| `compress` / `decompress` | the zlib container: a 2-byte header, the data and an Adler-32 checksum |
| `gzip` / `gunzip` | the gzip container: header, data, CRC-32 and length |
| `deflate` / `inflate` | the raw stream with no container |
| `deflateLevel(data, n, level, &out)` | like `deflate`, with an effort from 1 (fastest) to 9 (best); other values are clamped to that range, and `deflate`, `compress` and `gzip` use 6 |

All of them except `deflateLevel` take `(data, length, &outLength)` and return a new buffer, or `null` when the data is damaged or memory is short. Every result has a hidden terminating zero byte after its length, so decompressed text can be used as a string.

{{sample data/zlib_roundtrip}}

What to notice:

* Each pair gives back exactly the original text. The containers add a few bytes (zlib 6, gzip 18) around the raw stream.
* The container checksums are the CRC-32 and Adler-32 of the `hash` module (see below). `gunzip` and `decompress` verify them.
* The gzip output starts with `1F 8B`, the signature of every `.gz` file.

{{sample data/zlib_levels}}

What to notice:

* Repetitive data collapses (10000 bytes to 85) and random data grows by a few bytes (10000 to 10011). Compressing twice, or compressing encrypted data, does not help.
* The compressor looks for repeats in the last 32 KB and writes them with the fixed Huffman code (one ready-made table of bit codes that is the same for every input, so the savings come from the repeats, not from the codes), or as stored blocks when that is smaller. Real text shrinks to between a quarter and a half (the source of `lib/json.a` to 26%, the file `docs/LANGUAGE.md` to 49%). A full gzip, which also uses dynamic Huffman codes, does better: `gzip -9` needs 1489 bytes for the word soup of this sample (`zlib.gzip` writes 1852 bytes for it). Every program can read what `zlib` writes.
* A higher level searches longer: here 2652 bytes at level 1 and 1812 at level 9 for the same data.

{{sample data/zlib_damage}}

What to notice:

* A flipped bit in the checksum, a wrong header, a cut-off stream and plain text given to `decompress` all give `null`. A decompressor that checks its input is a safety feature.
* After the damage is undone the data is accepted again: the check is exact.

`tar` and `zlib` together make a `.tar.gz`:

{{sample data/zlib_tgz}}

The file is a normal archive. The system tools read it:

```sh
tar tzvf logs.tar.gz
```

```text
-rw-r--r-- 0/0              78 1970-01-01 00:00 logs/day1.txt
-rw-r--r-- 0/0              78 1970-01-01 00:00 logs/day2.txt
-rw-r--r-- 0/0              78 1970-01-01 00:00 logs/day3.txt
```

What to notice:

* Three copies of the same text take 4096 bytes in the tar and 155 bytes after gzip, because the repeats are found.
* The listing shows the fixed owner 0/0 and the time 0 (1970-01-01) that `tar.Writer` puts into every header.

See the [API reference of `zlib`](#api-zlib).

## File names: `path`

`path` works on file names as text. It does not touch the disk. Both `/` and `\` count as separators when it takes a name apart. The separators that `join` adds and the names that `normalize` returns use `/`, which Windows accepts as well.

{{sample data/path_parts}}

What to notice:

* `dirname` is everything before the last component, `basename` the last component, `extension` the part from the last dot (with the dot), and `stem` the name without the extension.
* The edge cases are worked out: `dirname("file.txt")` is `.`, a leading dot does not make an extension (`.bashrc`), and a trailing slash is ignored.
* `stem("a.tar.gz")` is `a.tar`: only the last extension counts.
* `isAbsolute` knows `/dir`, `C:\dir` and `C:/dir`.

{{sample data/path_build}}

What to notice:

* `join(a, b)` puts exactly one separator between the parts and lets an **absolute second part win**.
* `normalize` removes `.`, `..` and doubled separators without looking at the disk. A relative path keeps the `..` that it cannot resolve, an absolute one cannot go above the root, and an empty result is `.`.
* `withExtension(path, ".bak")` replaces or adds an extension (write the dot yourself), and an empty extension removes it.

See the [API reference of `path`](#api-path).

## Dates and times: `datetime`

`datetime` works in **UTC**. A timestamp is the number of seconds since 1970-01-01 00:00:00 UTC (the Unix epoch), and a `DateTime` object holds the calendar fields of one: `year`, `month`, `day`, `hour`, `minute`, `second`, `weekday` (0 is Sunday) and `yearDay` (1 to 366).

`datetime.now()` and `nowMillis()` read the clock. Their results change on every run, so the samples in this book use fixed timestamps.

{{sample data/datetime_convert}}

What to notice:

* `new datetime.DateTime(unix)` fills the fields. `set(unix)` reuses the object and `toUnix()` goes back. `toString()`, `dateString()` and `timeString()` give `2001-09-09 01:46:40`, `2001-09-09` and `01:46:40`.
* `datetime.toUnix(y, m, d, h, mi, s)` turns calendar fields into a timestamp.
* Negative timestamps work: -1 is one second before the epoch.
* `weekdayName(w)` and `monthName(m)` give English names.

{{sample data/datetime_calendar}}

What to notice:

* `isLeapYear` follows the full rule: 1900 and 2100 are not leap years, 2000 is.
* `daysFromCivil(y, m, d)` is the number of days since the epoch, so the **difference of two day numbers** is the number of days between two dates.
* `dayOfWeek(y, m, d)` and `daysInMonth(y, m)` are all you need to draw a calendar.

### Time zones

`datetime` has no zones, so the simplest way to show a local time is to add the offset to the timestamp before you build the `DateTime`.

{{sample data/datetime_zones}}

What to notice:

* The same moment is already 2025 in Helsinki and still 2024 in Honolulu.
* Offsets are not always whole hours: India (Kolkata) is +5:30 and Newfoundland (St John's) is -3:30 in winter.
* This method knows nothing about daylight saving time. For that, use the C library.

{{sample data/datetime_posix_zones}}

What to notice:

* The C library reads the zone from the `TZ` variable. A POSIX rule gives the standard name, the offset (**positive west of Greenwich**, so Helsinki is `-2`), the daylight name and the rules for the switch: `M3.5.0/3` means "month 3, last (5th) week, Sunday, at 03:00". The library does not look up region names: `TZ=Europe/Helsinki` is read as a zone called `Europe` with no offset, so you get UTC times. When `TZ` is not set, Linux programs use the rule at the end of `/etc/localtime`.
* `localtime` and `strftime` then show winter time (`EET`, UTC+2) and summer time (`EEST`, UTC+3) correctly. `mktime` converts a local date back to a timestamp.
* Only today's rule is known: the rule is applied to every year, even where history differed.
* The program sets `TZ` itself, so the output does not depend on the computer. The [C library tour](#chap-c-library-tour) has more on `ctime`.

See the [API reference of `datetime`](#api-datetime).

## Checksums and hashes: `hash`

A **hash function** turns any amount of data into a short fixed-size value. The same input always gives the same value, and any small change gives a completely different one. Checksums find accidental damage; cryptographic hashes also resist deliberate tampering. Every function takes a pointer and a **byte count**, so `strlen(s)` for text.

| Function | Result | Use |
|---|---|---|
| `crc32`, `crc32Update` | 32 bits | gzip, zip, PNG, detecting damage |
| `adler32` | 32 bits | zlib |
| `fnv1a`, `djb2` | 32 bits | hash tables |
| `md5`, `sha1` | 128, 160 bits | old formats and checksums; **broken** as security hashes |
| `sha256`, `sha384`, `sha512` | 256, 384, 512 bits | signatures, integrity checks |
| `hmacSha256`, `hmac` | MAC (message authentication code) | authenticating a message with a secret key |

The checksums return an `int`. The digests return lowercase hex text (`md5`, `sha1`, `sha256`, `sha512`), or write the raw bytes into a buffer (`md5Raw`, `sha1Raw`, `sha256Raw`, `sha384Raw`, `sha512Raw`).

{{sample data/hash_checksums}}

What to notice:

* The CRC-32 of `"123456789"` is `CBF43926`, the standard check value, and the Adler-32 of `"Wikipedia"` is `11E60398`, the example value that is quoted everywhere for Adler-32.
* The checksum of an empty text is not always 0: it is 0 for CRC-32, but Adler-32 starts at 1, FNV-1a at its offset basis (`811C9DC5`) and djb2 at 5381 (`1505` in hex).
* `crc32Update(crc, data, n)` continues a checksum, so a large file can be read in chunks. Start with 0.
* Changing one letter changes the whole checksum.

{{sample data/hash_digests}}

What to notice:

* These are the published test vectors for `"abc"`. If your own implementation prints something different, it is wrong, not the vector.
* `md5`, `sha1`, `sha256` and `sha512` return text. SHA-384 only exists as raw bytes (`sha384Raw`), which the sample converts with `encoding.hexEncode`.
* `digest(bits, data, n, out)` picks the hash by its size (128, 160, 256, 384, 512) and returns the length of the result in bytes, 0 for an unknown size.

{{sample data/hash_empty_and_long}}

What to notice:

* Even nothing has a hash. `e3b0c442...` is the best known SHA-256 value.
* SHA-1 and SHA-256 pad the data to a multiple of 64 bytes, so the lengths 55, 56, 63 and 64 are the classic places for a mistake.
* One million `a` is the NIST long-message test: SHA-256 `cdc76e5c...` and SHA-1 `34aa973c...`.
* A message with zero bytes must be passed with its length: `strlen` would stop at the first zero.

{{sample data/hash_hmac}}

What to notice:

* An **HMAC** mixes a secret key into the hash so that only someone with the key can compute it. The first line is the test vector 2 of RFC 4231.
* `hmac(bits, key, klen, data, dlen, out)` works with the hashes of `digest` (128, 160, 256, 384 or 512 bits) and returns the length of the MAC in bytes.
* To check a MAC compare it with `equalConstantTime`, which looks at every byte so that its running time does not tell an attacker where the first difference is.

::: warning
Do not store passwords as a plain `sha256` of the password. Fast hashes can be tried very many times per second. [The cryptography chapter](#chap-cryptography) shows how to do it properly.
:::

See the [API reference of `hash`](#api-hash).

## Neural networks: `nn`

A neural network learns a function from examples: it has numbers called **weights**, and training nudges them until the answers come out right. The `nn` module is small, works entirely in [`fixed` point numbers](#chap-numbers) (so the results are exactly the same on every CPU) and needs no floating point. Vectors and matrices are plain `int` arrays holding fixed-point values, where `fixed.ONE` is 1.0.

| Class | What it is |
|---|---|
| `Perceptron(n)` | one neuron with a step output: `fit`, `predict` |
| `Network(count, sizes, hidden, out)` | a multi-layer network trained by back-propagation (it works out how much each weight added to the error and corrects it): `forward`, `train`, `fit`, `predict`, `save`, `load` |
| `Autoencoder` | squeezes data into a short code and rebuilds it |
| `Hopfield(n)` | an associative memory for patterns of +1 and -1: `store`, `recall`, `energy` |
| `SOM`, `Elman`, `LSTM`, `ConvNet` | a self-organizing map, two recurrent networks and a small convolutional network |

The activation functions are `ACT_LINEAR`, `ACT_SIGMOID`, `ACT_TANH`, `ACT_RELU`, `ACT_LEAKY` and `ACT_SOFTMAX`.

### One neuron

A perceptron draws a straight line through the input space. It can learn every problem that a line can solve.

{{sample data/nn_perceptron}}

What to notice:

* `fit(x, targets, count, epochs, rate)` runs whole passes over the examples (one pass is an **epoch**) and returns the number of epochs used; it stops early when a pass has no mistake. The targets and the answers of `predict` are plain 0 and 1.
* AND and OR are learned in a few epochs. XOR is not: no straight line separates `(0,1)` and `(1,0)` from `(0,0)` and `(1,1)`, so the 100 epochs run out and at least one answer stays wrong (here two of the four).
* The inputs and the learning rate are fixed-point numbers (`fixed.fromInt(1)`, `fixed.fromText("0.25")`).

### A network that learns XOR

Add a hidden layer and XOR becomes learnable. The sample creates a network with 2 inputs, 4 hidden neurons and 1 output, and trains it with fixed data and a fixed seed, so the numbers are the same on every run and on every target.

{{sample data/nn_xor}}

What to notice:

* `fixed.seed(7)` comes **before** the network is created: the start weights and the order of the examples come from that generator. A different seed gives different numbers and nearly the same result.
* `new nn.Network(3, sizes, nn.ACT_TANH, nn.ACT_SIGMOID)`: three layers, `tanh` in the hidden layer and a `sigmoid` output between 0 and 1.
* `fit(inputs, targets, count, epochs, rate, stopBelow)` trains and returns the final mean loss (0.000052). `stopBelow` stops early when the loss falls below it; 0 means never.
* Before training the four outputs (0.500, 0.389, 0.270 and 0.233) say nothing about XOR. After training, the outputs are within about 0.013 of the right answer.
* `net->forward(x)` returns a pointer to the output vector.
* `Network.accuracy` compares the strongest output with the strongest target, so it is always 100% for a network with a **single** output. That is why the sample counts the answers itself.

### An associative memory

A **Hopfield network** stores patterns and repairs damaged ones: give it a corrupted version and it usually settles into the closest stored pattern.

{{sample data/nn_hopfield}}

What to notice:

* The patterns are arrays of +1 and -1 (`#` and `.` in the picture). `store` adds a pattern with the Hebb rule (cells that have the same value in a pattern get a stronger link).
* `energy` measures how stable a state is; lower is more stable. Damaging five of the 25 cells raises the energy from -312 to -128, and `recall` brings it back to -312.
* `recall(state, maxSweeps)` changes the state in place and returns the number of sweeps it needed (`maxSweeps` when it has not settled by then). A sweep visits every cell once; the last sweep is the one in which nothing changed, so 2 sweeps here means one that repaired the pattern and one that confirmed it.
* A Hopfield network of `n` neurons holds only a few patterns (about 0.14 n). Similar patterns interfere with each other.

The `codec` module (see [text and strings](#chap-text-and-strings)) turns text and pictures into the vectors these networks want, and the example program `examples/ocr.a` combines them into a character recogniser. See the [API reference of `nn`](#api-nn).

## Summary

* `json` parses to a tree you navigate with `get` and `at`, and builds one with `newObject` and friends. Numbers with a fraction keep their text, and integers beyond 64 bits wrap.
* `csv` reads and writes one line at a time with correct quoting; `ini` reads and writes sections and keys with defaults.
* `tar` and `zlib` make archives and compressed data that other programs can read; damaged input gives `null`, not garbage.
* `path` takes file names apart and joins them, with no disk access.
* `datetime` is UTC arithmetic on timestamps and calendar fields. Local times are an offset away, and the C library knows the daylight saving rules.
* `hash` has checksums for damage, SHA-2 for integrity and HMAC for authentication. MD5 and SHA-1 are for old formats only.
* `nn` trains small networks in fixed-point arithmetic, so the training is exactly reproducible.

## Where next

* [Cryptography](#chap-cryptography): AES, RSA, signatures and how to use hashes safely.
* [Text and strings](#chap-text-and-strings): regular expressions for the text formats that have no module.
* [Numbers](#chap-numbers): `fixed`, which the neural networks are built on.
* [System programming](#chap-system-programming): files, directories and processes.
* API references: [`json`](#api-json), [`csv`](#api-csv), [`ini`](#api-ini), [`tar`](#api-tar), [`zlib`](#api-zlib), [`path`](#api-path), [`datetime`](#api-datetime), [`hash`](#api-hash), [`nn`](#api-nn).
