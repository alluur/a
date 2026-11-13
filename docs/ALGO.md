# Algorithms: data structures, strings, random numbers, statistics, matrices and numerical methods

Six modules for everyday programming and for numerical work, written in A and built into the compiler (`import ds;`, `import strx;`, `import rng;`, `import stats;`, `import matrix;`, `import optim;`):

| Module | What it is |
|---|---|
| [`ds`](#ds---data-structures) | deque, ring buffers, binary heap with handles, ordered map and set (AVL tree), hash maps for ints and texts, trie with wildcard search, union-find, bit set, Fenwick and segment trees with lazy updates, interval set, LRU cache, Bloom filter, count-min sketch |
| [`strx`](#strx---string-algorithms) | KMP, Horspool, Rabin-Karp, Aho-Corasick, edit distances and similarities, LCS, Myers diff with unified output, suffix array, Manacher, fuzzy matching (quick open), glob matching, Soundex, natural order |
| [`rng`](#rng---random-numbers) | SplitMix64, xoshiro256\*\*, PCG32, PCG64, MT19937, a ChaCha20 CSPRNG; unbiased bounded integers, 53 bit doubles, normal / exponential / gamma / beta / Poisson / binomial / geometric, shuffle, sampling, alias method, reservoir sampling, UUID v4 |
| [`stats`](#stats---statistics-distributions-and-tests) | descriptive statistics with the nine quantile definitions, streaming and windowed statistics, histograms with automatic bins, least squares regression (QR based) with standard errors and p values, accurate special functions and 11 distributions (pdf, cdf, upper tail, quantile), t / chi-square / F / Mann-Whitney tests, confidence intervals, bootstrap, autocorrelation, k-means, PCA |
| [`matrix`](#matrix---dense-and-sparse-linear-algebra) | dense and sparse double matrices: arithmetic, in place variants, LU with partial pivoting, Cholesky, Householder QR, least squares, symmetric eigenvalues (Jacobi), SVD (one sided Jacobi), rank, condition estimates, pseudo inverse, CSR matrices with conjugate gradient, complex matrices; singular matrices are reported, never solved into nonsense |
| [`optim`](#optim---numerical-methods) | root finding (bisection, Brent, Newton, secant, systems), minimisation (golden section, Brent, Nelder-Mead, BFGS, gradient descent), integration (trapezoid, Simpson, Romberg, adaptive Gauss-Kronrod, Gauss-Legendre), ODEs (RK4, adaptive RK45), interpolation (linear, cubic splines, Lagrange, Chebyshev), polynomials (roots, fit), FFT for any length and convolution, a simplex linear programming solver, special sequences |

They compose and extend [`algo`](LANGUAGE.md#12b-built-in-modules) (sorting, union-find, graphs, `editDistance`, `kmpFind`), `collections`, `random`, `math`, `dmath` and `bigint`, whose APIs are unchanged.
Everything works on all five targets and on AOS, uses only the `asys` layer for memory and the system random source, and gives the same results everywhere
(`double` arithmetic is soft float in A, so a seed or an input gives the same numbers on every CPU, and the results of algorithms that use only `+ - * /` and `sqrt` are bit for bit the results of a hardware double computation: t469 compares them with Python floats).

Contents: [conventions](#conventions) · [ds](#ds---data-structures) · [strx](#strx---string-algorithms) · [rng](#rng---random-numbers) · [stats](#stats---statistics-distributions-and-tests) · [matrix](#matrix---dense-and-sparse-linear-algebra) · [optim](#optim---numerical-methods) · [speed](#speed) · [tests](#tests) · [limitations](#limitations)

---

## Conventions

* **Declare objects with parentheses** (`ds.Deque d(16);`) when the class has constructor arguments; a constructor never runs for a plain `ds.Deque d;`.
  *Zeroed objects* (declared without parentheses) are valid in two ways. The classes **without a size or capacity** (`Deque`, `OrderedMap`, `OrderedSet`, `OrderedTextMap`, `OrderedTextSet`, `HashMap`, `HashSet`,
  `TextHashMap`, `TextHashSet`, `Trie`, `IntervalSet`, `BinaryHeap`, `PriorityQueue`, `DisjointSet`, `BitSet`, and in `strx` `AhoCorasick` and `LineDiff`) are empty containers that grow on first use.
  The classes **made with a size or capacity** (`RingBuffer`, `ByteRing`, `Fenwick`, `RangeFenwick`, `SegTree`, `LruCache`, `TextLruCache`, `BloomFilter`, `CountMinSketch`) must be declared with parentheses:
  zeroed, they have size 0 or capacity 0 and store nothing (`push`, `put` and `add` return `false`, queries find nothing), but they never crash. **A default argument is not applied to a zeroed object**:
  a zeroed `LruCache` has capacity 0, not 16, and a zeroed `BloomFilter` has no bits (`add` returns `false`, `mightContain` says no, `bitCount()` is 0). A zeroed `strx.Kmp`, `Horspool` or `RabinKarp` is an empty pattern.
* **`dispose()` frees every block** (also copies of text keys) and leaves an empty object that can be used again. `A` has no `delete`: an object made with `new` is never freed,
  so prefer objects on the stack. Collections of the standard library never free memory; these do. The tests check `asys.memInUse()` before and after.
* **Memory failures** do not crash: an operation that has to allocate returns `false`, `-1` or `null` and leaves the container as it was.
* **Bad indexes and empty containers** give `0`, `-1`, `false` or `null` (documented per method), never a crash (this includes `size 0`, never-sized, zeroed and disposed containers; t429 and t437 test it). Counts and sums wrap around on overflow.
* **Null pointers**: `strx` takes a `null` text as an empty text and `rng` takes a `null` array when the count is 0 (t429). **`ds` does not check its pointer arguments for `null`**: a text key, a byte buffer or an output
  array must be a real pointer. Measured crashes: `Trie.put`, `TextHashMap.put`, `TextHashSet.add`, `OrderedTextMap.put`, `OrderedTextSet.add`, `BloomFilter.addText / mightContainText / addBytes`, `CountMinSketch.addText / estimateText`,
  `TextLruCache.put`, `ByteRing.write / peek / read` with a length above 0, `Deque.copyTo(null)`, `Trie.collect` with a `null` array. A lookup in an empty container (`Trie.has(null)`, `TextHashMap.get(null)`) may happen to answer
  `false`; do not rely on it. Pass `""` for an empty text.
* **Texts** in `strx` are `char*` plus a length `(s, n)`; `n = -1` means "up to the terminating 0", and a `null` pointer is an empty text. Texts that are not 0 terminated are never read past `n`.
  A flag `utf8 = true` on the distance and similarity functions compares code points instead of bytes (invalid bytes count as one symbol each).
* **Not thread safe.**
* **Numeric modules** (`stats`, `matrix`, `optim`): numbers are `double`, arrays are `double*` plus a count, and a null pointer or a count below 1 is an invalid argument, never a crash: functions that return a number give NaN,
  functions that return a status give an error code (`matrix.ERR_...`, `optim.ERR_...`), builders return an empty object whose `ok()` is false. **NaN in the input** gives NaN (or a refusal with `ERR_NOT_FINITE` / `ERR_NAN` where an
  algorithm would turn it into nonsense), infinity follows IEEE arithmetic. Objects that own memory (`Matrix`, `LU`, `Spline`, `Regression`, `Histogram`, `FftPlan` ...) have `dispose()`, which is safe on a failed, a zeroed
  (declared without parentheses) and an already disposed object and leaves an empty one; `Type t = u;` copies the *handle*, not the numbers. Callbacks are `func` values with a context pointer (see [optim](#callbacks-and-how-to-pass-context)).
  t466 calls every public function and method with null pointers, zero and negative counts, NaN, infinity, 1e308 and one null among valid arguments, and checks that nothing crashes, hangs or leaks; t464 and t465 check the
  documented answers to hostile input.
* **A file called `stats.a`, `matrix.a` or `optim.a` next to your program shadows the module** (the directory of the importing file is searched first, see LANGUAGE.md section 10): the old example `examples/stats.a` is a program
  with a `main`, so a program in the `examples` folder cannot `import stats;`. The numeric examples are therefore in `examples/numeric/`.

---

## ds - data structures

All containers hold ints (texts and pointers fit in an int, and there are text variants for the maps and sets).

| Class | What | Main methods |
|---|---|---|
| `Deque` | double ended queue (growable ring) | `pushBack pushFront popBack popFront front back get set insertAt removeAt indexOf` |
| `RingBuffer` | fixed capacity FIFO, overwrites the oldest (or refuses) | `push pop peek get fromNewest`, counters `overwritten`, `rejected` |
| `ByteRing` | the same for bytes (network and serial buffers) | `write read peek skip available space`, counter `dropped` |
| `BinaryHeap`, `PriorityQueue` | priority queue with **handles**: `update(handle, newKey)` is decrease-key (and increase-key), `remove(handle)`, `merge(&other)` | `push(key, value) -> handle`, `pop popValue peek peekValue drain verify` |
| `OrderedMap`, `OrderedSet`, `OrderedTextMap`, `OrderedTextSet` | AVL tree (balanced, O(log n)); node numbers stay valid until that key is removed | `put get has remove` `floorNode ceilNode lowerNode higherNode` (and `...Key`) `rank select countRange range forEachRange forEach toArrays`, `foreach` works on the set |
| `HashMap`, `HashSet`, `TextHashMap`, `TextHashSet` | open addressing, linear probing, tombstones, resizing; entries in insertion order | `put get has remove add(key, delta) putIfAbsent first/next keyAt valueAt shrink` |
| `Trie` | map from texts, prefix and wildcard search (`?` one byte, `*` any run) | `put get has remove countPrefix collect walkPrefix longestPrefixOf countWildcard collectWildcard walkWildcard` |
| `DisjointSet` | union-find, path compression, union by size | `add find unite same sizeOf labels`, field `groups` |
| `BitSet` | packed bits | `set get flip setRange count countRange nextSet nextClear prevSet orWith andWith xorWith andNotWith isSubsetOf` |
| `Fenwick`, `RangeFenwick` | prefix / range sums; range add + range sum | `add prefix sum lowerBound build` |
| `SegTree` | sum, minimum or maximum over ranges, **lazy** range add and range assign | `SegTree t(n, ds.SEG_MAX); t.add(l, r, v); t.assign(l, r, v); t.query(l, r)` |
| `IntervalSet` | merged integer intervals | `add(lo, hi) remove(lo, hi) contains covers overlaps nextFree nextMember indexOf lowAt highAt length` |
| `LruCache`, `TextLruCache` | hash map + doubly linked list, eviction callback, counters `hits misses evictions` | `get put peek remove setCapacity setEvictHandler` |
| `BloomFilter` | "maybe in the set", integer arithmetic only | `BloomFilter f(expected, oneIn); add mightContain addText mightContainText merge falsePositivePpm` (`add` returns `false` when the filter has no bits: zeroed, out of memory, disposed) |
| `CountMinSketch` | approximate frequencies, optional conservative update | `add(key, n) estimate(key) merge` (`add` returns `false` when nothing was stored: no table, or `n <= 0`) |

Functions: `cmpAsc cmpDesc cmpText` (comparators for `BinaryHeap`, `OrderedMap`, `algo.sortBy`), `mix64 hashInt hashText hashBytes` (seeded), `randomSeed()` (a seed
from the system: pass it to the hash maps when the keys come from an attacker), `freeTexts(array, n)` (frees the texts `Trie.collect` hands out).

```c
import ds;

ds.BinaryHeap h;                                    // smallest key first; ds.BinaryHeap h(ds.cmpDesc) for the largest
int tok = h.push(40, 7);  h.push(10, 8);
h.update(tok, 5);                                   // decrease-key through the handle
int v = h.popValue();                               // 7: key 5 is the smallest now

ds.OrderedMap m;  m.put(10, 1);  m.put(20, 2);
int n = m.floorNode(15);  int k = m.keyAt(n);       // 10
int cnt = m.countRange(5, 25);  int r = m.rank(20); // 2, 1
int nth = m.select(0);                              // the node of the smallest key

ds.Trie t;  t.put("car", 1);  t.put("cat", 2);
int p = t.countPrefix("ca");  int w = t.countWildcard("c?t");   // 2, 1

ds.IntervalSet s;  s.add(1, 5);  s.add(6, 9);  s.remove(3, 4);   // [1,2] [5,9]
ds.LruCache c(100);  c.put(1, 10);  int got = c.get(1, -1);
```

Details that matter:

* **Ordered map**: the comparator is `int cmp(int a, int b)` (the default compares ints); keys can be text (`OrderedTextMap`, keys are copied) or your own type through a comparator. Entries live in
  arrays addressed by node numbers, so there are no per-node allocations; `rank`, `select` and range counts use subtree sizes kept by the tree.
* **Hash maps**: entries are kept in insertion order and the table only stores their numbers, so iteration is fast and in a fixed order and the table never gets more than half full.
  Removing leaves a tombstone that disappears when the entry array is compacted or grown. Removing while iterating is fine; inserting a new key invalidates entry numbers.
  The hash is a seeded 64 bit mixer (`ds.randomSeed()` for hostile keys).
* **Trie**: nodes are kept in arrays, the children of a node are a list sorted by byte, so keys come out in byte order. Wildcard search simulates the pattern with a bit-parallel automaton
  over the trie (one step per trie node that can still match; at most 62 items besides stars); a key of any length works (the walks are iterative).
* **Segment tree**: `SEG_SUM`, `SEG_MIN` or `SEG_MAX`; lazy propagation of add and assign, O(log n) for every operation; ranges are clipped to `0 .. size() - 1`; an empty range gives the identity.
* **Bloom filter / count-min sketch** use no floating point, so their bits are the same on every target.

---

## strx - string algorithms

### Searching

| | |
|---|---|
| `Kmp`, `Horspool`, `RabinKarp` | compile a pattern once, search many texts: `find(text, n, from)`, `count(text, n, overlap)`, `findAll(text, n, out, max, overlap)` (returns the total), `dispose()` |
| `prefixFunction`, `zFunction`, `period` | the KMP failure function, the Z array, the smallest period of a text |
| `indexOf(text, pattern, from)`, `countOf`, `findAll` | one-shot search with no setup: Horspool with a stack table that falls back to KMP when the text is nasty (worst case stays linear) |
| `AhoCorasick` | many patterns in one pass: `add(pattern) -> id`, `findAll(text, n, ids, ends, max)`, `count`, `first`, `each(text, n, callback, ctx)`, a state cursor `step / match / nextMatch / patternAt`, `ignoreCase` option |

An empty pattern matches at every position `0 .. n`. (`algo.kmpFind` and `algo.countOccurrences` rebuild their table for every call and restart after every match, so they are quadratic on texts like `aaaa...`; the classes above and `strx.countOf` are linear.) Horspool is usually sub-linear but O(n * m) in the worst case; Rabin-Karp uses two moduli below 2^31 with seeded bases and verifies every hit,
so the answer is always right. **That verification costs O(m) per hit, so Rabin-Karp (like Horspool) is quadratic when almost every window matches**: 2,000,000 times `a` searched for 1000 times `a` takes
about 15 ms with `Kmp.count` (and `strx.countOf`), 4.5 seconds with `Horspool.count` and 23 seconds with `RabinKarp.count` (measured natively). Use `Kmp` (always linear) or `strx.countOf` / `indexOf` (they fall back to KMP) when the text may be that repetitive, for example attacker supplied text. Aho-Corasick keeps children in sibling lists (compact for any alphabet) with a direct table for the root; a node limit (default 4 million) refuses further patterns.

```c
strx.AhoCorasick ac;  ac.add("he");  ac.add("she");  ac.add("hers");
int ids[16];  int ends[16];
int k = ac.findAll("ushers", -1, ids, ends, 16);    // 3 matches: "she" and "he" end at 4, "hers" at 6
ac.dispose();
```

### Distances and similarities

| | |
|---|---|
| `levenshtein(a, na, b, nb)` | edit distance, O(na * nb) time, **O(min) memory** |
| `levenshteinMax(a, na, b, nb, k)` | stops at `k` (returns `k + 1` when larger): banded, O(k * n) time, so two 1 MB texts with a few differences are instant |
| `osa`, `damerau` | optimal string alignment (swaps of neighbours, memory linear) and the true Damerau-Levenshtein distance (needs the whole table: refused with -1 above 2^23 cells) |
| `hamming(a, na, b, nb)`, `hammingBits` | differing symbols / bits, -1 when the lengths differ |
| `jaro`, `jaroWinkler`, `jaroWinklerEx` | 0.0 .. 1.0 (transpositions are half the out-of-order matches, rounded down, as in the original) |
| `diceBigrams`, `diceQgrams`, `jaccardQgrams`, `cosineQgrams`, `levenshteinSimilarity` | other similarities |
| `lcsLength`, `lcs` | longest common subsequence (Hirschberg: O(na * nb) time, linear memory) |
| `longestCommonSubstring(a, na, b, nb, &startA, &startB)` | O(na + nb) through the suffix array |
| `commonPrefix`, `commonSuffix` | lengths in bytes |

Pass `utf8 = true` as the last argument to count code points: `strx.levenshtein("caf\xc3\xa9", -1, "cafe", -1, true)` is 1 (bytes: 2).

### Diff of two line arrays

`LineDiff` computes a shortest edit script with **Myers' O((N + M) D) algorithm in linear space** (middle snake and divide and conquer). Lines are first replaced by integers; the common beginning
and end are cut off, and lines that occur in only one of the two files (they can only be changed) are left out of the search, which makes real files cheap.
`maxCost` (default 8000) bounds the work: a part that costs more is cut at the furthest point reached and the script is still correct but no longer shortest (`exact()` is `false`).

```c
int n1;  int n2;
char** a = strx.splitLines(textA, -1, &n1);          // one block: free it with strx.freeText((char*) a)
char** b = strx.splitLines(textB, -1, &n2);
strx.LineDiff d;
d.run(a, n1, b, n2);                                 // or d.runText(textA, textB)
char* patch = d.unified("a.txt", "b.txt", 3);        // "--- a.txt\n+++ b.txt\n@@ -1,3 +1,3 @@ ..." ("" when equal)
print(patch);  strx.freeText(patch);  d.dispose();
```

`d.distance()` is the number of deleted plus inserted lines; `opCount() opKind(i) opA(i) opB(i) opLen(i)` give the script as runs (equal / delete / insert).
The unified text is what `diff -u` prints (no timestamps; line breaks in the names are written as spaces, so a name cannot forge lines), including `\ No newline at end of file`; it was checked against GNU `diff` and `patch` (see [tests](#tests)).

### Suffix array and palindromes

`SuffixArray sa(text, n)` builds the suffix array (**SA-IS, linear time**) and the LCP array (Kasai) in about 24 bytes per input byte:
`at(i) rank(i) lcp(i) count(p, m) find(p, m) findAll(p, m, out, max) lcpOf(i, j)` (O(log n) after a one-time O(n) setup) `longestRepeat(&pos) distinctSubstrings()`
(`m` is the pattern length, -1 for "up to the 0"). `findAll` stores up to `max` positions in suffix order (not text order) and returns the total. An empty pattern occurs at every position `0 .. n`:
`count("")` and `findAll("", ...)` both return `n + 1` (it stores `n`, then the suffixes in order) and `find("")` returns 0.
`manacher(s, n, d1, d2)`, `longestPalindrome(s, n, &start)`, `countPalindromes`, `isPalindrome` run in O(n) (with `utf8` for code points).

### Matching names

* **`FuzzyMatcher`** (quick open): `FuzzyMatcher f("fb"); f.score("foo_bar", -1, positions)` gives a score (-1 when the letters are not a subsequence) and the byte offsets of the matched letters;
  `f.rank(items, n, outIndex, max, outScore)` sorts a list (ties: shorter first, then earlier). The score is a small dynamic program in the style of fzf: every match scores 16; matches
  at the start of the text or after a separator score more (white space 10, `/` 9, `_` `-` `.` 8), camel case humps and digits 7, runs of consecutive matches keep the bonus of their first letter, a
  gap costs 3 plus 1 per extra letter. **Smart case**: the match is case sensitive only when the pattern has a capital (`FUZZY_IGNORE_CASE`, `FUZZY_CASE`, `FUZZY_UTF8` flags).
  Case folding covers ASCII, Latin-1, Greek and Cyrillic. Candidates longer than 1024 symbols and patterns longer than 64 get a cheaper greedy score.
* **`globMatch(pattern, text, flags)`**: `*`, `?`, `[abc]`, `[a-z]`, `[!x]`, `\` escapes. `GLOB_PATHNAME`: `*` `?` and sets do not match `/`, a pattern segment that is exactly `**` matches any
  number of whole path segments (`src/**/*.a`); `GLOB_ICASE`, `GLOB_PERIOD` (a leading dot needs a literal dot), `GLOB_NOESCAPE`. Time is O(pattern * text) at worst, never exponential (checked
  against a brute-force matcher on 20000 random patterns).
* **`soundex(name, out)`** (American Soundex, `"Robert"` and `"Rupert"` give `R163`), `soundexEqual`.
* **`naturalCompare(a, b, ignoreCase)`** and `naturalSort(items, n)`: digit runs compare by value however long (`img2 < img10`), equal values with different numbers of leading zeros: fewer zeros first.

---

## rng - random numbers

### Generators

Every generator derives from `rng.Rng`. The sequences below are exact and identical on all targets; the tests compare them with independent Python implementations
(and with NumPy, Python's `random`, the RFC 8439 ChaCha20 vector, the PCG demo vector and the MT19937 reference vector).

| Class | Algorithm | Seeding | Output |
|---|---|---|---|
| `SplitMix64(seed)` | Vigna's splitmix64 | the state is the seed | `SplitMix64(1234567)`: 6457827717110365317, 3203168211198807973, 9817491932198370423 ... |
| `Xoshiro256(seed)` | xoshiro256\*\* 1.0 (period 2^256 - 1), `jump()` = 2^128 steps, `longJump()` = 2^192 steps (checked against matrix powers) | the 4 state words are the first 4 outputs of `SplitMix64(seed)`; `setState(a, b, c, d)` | `Xoshiro256(1)`: 12966619160104079557, 9600361134598540522 ... |
| `Pcg32(seed, stream)` | PCG XSH RR 64/32 of the PCG C library | `pcg32_srandom_r(seed, stream)`; the default is the pair of the PCG demo, 42 and 54 | `nextU32()`: 0xa15c02b7 0x7b47f409 0xba1d3330 ...; `nextU64()` = first word in the upper half |
| `Pcg64(seed, stream)` | PCG XSL RR 128/64 (`pcg64`) | `pcg_setseq_128_srandom_r(seed, stream)` with high halves 0, `seed128(hi, lo, hi, lo)`, or `setState(stateHi, stateLo, incHi, incLo)` like NumPy's state dictionary | identical to NumPy's `PCG64` in the same state |
| `Mt19937(seed)` | Mersenne Twister MT19937 | `init_genrand(seed)` (default 5489); `seedArray(key, n)` = `init_by_array`; `seedPython(seed)` = Python's `random.seed(int)` | `nextU32()`: 3499211612 581869302 3890346734 ... for 5489; `nextDouble()` is `genrand_res53`: **Python's `random.random()`** |
| `ChaCha20Rng(key32)` | ChaCha20 with fast key erasure (below) | 32 byte key, `seedUint64`, or **the system** when no key is given | bytes of the keystream as little endian 64 bit words |

Pcg32 and Mt19937 produce 32 bit words (`nextU32`); their `nextU64` puts the first word in the upper half. `fillBytes(buf, n)` writes little endian words of `nextU64`.

**ChaCha20Rng** keeps a 32 byte key. To refill, it computes 1024 bytes of ChaCha20 keystream (nonce 0, block counter 0 .. 15) with the key, takes the first 32 bytes as the *new key* (the old key is overwritten, so
earlier output cannot be recovered from a later memory dump) and hands out the other 992 bytes. Seeded from the system (`rng.ChaCha20Rng c;`) it mixes 32 fresh system bytes into the key after every 1 MiB of output;
`mixIn(data, n)`, `reseedFromSystem()` and `dispose()` (wipes the key) are available. If there is no memory it falls back to reading the system generator directly.
`rng.system()` is one shared system seeded generator, and a plain `rng.Rng r;` (no generator) uses it too, so `rng.Rng r; r.uuid4(buf);` is all you need for good random numbers.
`rng.systemSeed()` gives 64 bits from `getrandom` / `/dev/urandom` / the Windows generator, `rng.timeSeed()` a guessable seed from the clock (different on every call).

### Integers, doubles, booleans

* `below(n)`: an integer `0 .. n - 1` **without modulo bias** (Lemire's multiplication method, a division only when a retry is possible); `belowU64(n)` for the full 64 bit range; `uniformInt(lo, hi)` includes both ends and works over the whole int range.
* `nextDouble()`: a double in `[0, 1)` with 53 random bits, `(nextU64() >> 11) * 2^-53`; `nextDoubleOpen()` in `(0, 1]`; `uniform(a, b)`.
* `nextBool()`, `bernoulli(p)`, `nextInt()` (63 bits), `nextU32()`, `fillBytes`.

### Distributions

The algorithms and the way they consume random bits are those of **NumPy's `Generator`**: with a `Pcg64` in the same state the numbers are NumPy's numbers (printed to nine decimals and compared in test t432 for
`standard_normal`, `standard_exponential`, `standard_gamma`, `beta`, `chisquare`, `normal`, `lognormal`, `uniform`, `poisson`, `binomial` (inversion range) and `geometric`).

| Method | Algorithm |
|---|---|
| `normal()`, `normalAt(mu, sigma)`, `lognormal(mu, sigma)` | ziggurat with 256 layers (about 99 percent of the draws need one 64 bit word and one multiplication); the tables are computed on first use with the correctly rounded soft float functions, so they are the same everywhere |
| `exponential()`, `exponentialRate(rate)` | ziggurat with 256 layers |
| `gamma(shape)`, `gammaAt(shape, scale)` | Marsaglia-Tsang for shape > 1; an exponential for 1; the NumPy variant for < 1 |
| `beta(a, b)`, `chiSquared(k)` | Johnk's algorithm for `a, b <= 1`, else a ratio of two gammas; chi-squared is a gamma |
| `poisson(lambda)` | multiplication of uniforms below 10, PTRS (Hoermann's transformed rejection) from 10 on |
| `binomial(n, p)` | inversion for `n * p <= 30` (NumPy), above that the **exact order-statistic split** (a Beta draw cuts the problem in two); `n` up to 2^53 |
| `geometric(p)` | the number of trials up to and including the first success (1, 2, 3 ...): search for `p >= 1/3`, inversion below |

Doubles are soft float and `log`, `exp`, `pow` are correctly rounded and slow (about 45 microseconds), so the code avoids them where it can (the ziggurat only needs `exp` for about 1 percent of the draws; the Poisson and binomial constants
are cached for repeated calls with the same parameters). The speed table below shows what to expect.

### Arrays and sampling

* `shuffle(a, n)` (Fisher-Yates), `shuffleItems(base, n, itemSize)` for any fixed size items.
* `sample(n, k, out)`: `k` different integers from `0 .. n - 1` in random order (a partial shuffle when `n <= 4 k`, **Floyd's algorithm** with a hash set otherwise: O(k) time and memory however large `n` is);
  `sampleSorted` returns them in increasing order.
* `weighted(weights, n)`: an index with probability proportional to integer weights (exact, no floating point; -1 for negative weights, a zero sum, or a sum that does not fit in 63 bits).
* `AliasTable t(weights, n)` (doubles; `buildInts` for ints): Walker/Vose alias method, O(n) setup and one `below` plus one `nextDouble` per draw: `t.sample(&g)`. Zero weights are never drawn;
  negative, NaN, infinite or all-zero weights are refused (`ok()` is false).
* `ReservoirSampler r(k)`: `r.offer(&g, value)` for every item of a stream (Algorithm R); every item is in the reservoir with probability k / items seen.
* `uuid4(out)`: a random (version 4) UUID, 36 characters plus the terminating 0 (`out` needs 37 bytes).

```c
import rng;

rng.Xoshiro256 g(12345);                              // fixed seed: the same numbers on every run and every target
int roll = g.uniformInt(1, 6);
double iq = g.normalAt(100.0, 15.0);
int visits = g.poisson(4.5);

int deck[52];  for (int i = 0; i < 52; i++) { deck[i] = i; }
g.shuffle(deck, 52);

char id[40];  rng.uuid4(id);                          // from the system generator: "f47ac10b-58cc-4372-a567-0e02b2c3d479"
```

---

## stats - statistics, distributions and tests

`import stats;` (it uses the built-in `matrix` and `rng` modules). Data are `double*` plus a count; everything else is an ordinary `double` or `int`.

**Conventions.** An invalid argument (`n < 1`, a probability outside [0, 1], a negative scale, a null pointer) gives **NaN**, never a crash. **NaN in the data gives NaN**; the functions that sort
(`median`, `quantile`, `mode`, `ranks`, `spearman`, `kendall`, `mad`, `iqr` and the tests that use ranks) refuse data with NaN instead of sorting it into nonsense. Infinity follows IEEE arithmetic
(`mean` of data with +inf is +inf, `variance` is NaN). The empty sum is 0. Nothing allocates unless it says so; functions that need a sorted copy allocate it and free it before they return
(and give NaN when memory is short). `ddof` is the divisor `n - ddof` (1 = sample variance, 0 = population variance). Only the objects that are built (`Histogram`, `RollingStats`, `Regression`,
`KMeans`, `Pca`) have `dispose()`.

### Descriptive statistics

| Function | What |
|---|---|
| `sum` `mean` `variance(x, n, ddof = 1)` `stddev` `sem` | `sum` uses Neumaier's compensated summation (the error does not grow with `n`); `variance` is two-pass with the correction term of Chan, Golub and LeVeque, so data with a huge offset keep their digits |
| `median` `quantile(x, n, p, method = 7)` `quantiles(x, n, ps, k, out, method)` `quantileSorted` `iqr` `mad` | the nine quantile definitions of Hyndman and Fan: 1 to 3 are step functions, 4 to 9 interpolate; 7 is NumPy / Excel / R, 6 is Minitab and Python's `"exclusive"`, 5 Hazen, 8 median unbiased, 9 normal unbiased. `quantiles` sorts once for many probabilities |
| `mode` `multimode(x, n, out, max)` | the most frequent value (the smallest when tied) / all of them |
| `minimum` `maximum` `rangeOf` | NaN for empty data or NaN in the data |
| `skewness(x, n, bias = true)` `kurtosis(x, n, bias = true, excess = true)` | `bias = false` gives the sample statistics G1 and G2 (NaN below 3 / 4 values) |
| `covariance` `correlation` (Pearson) `spearman` `kendall` (tau-b, O(n^2)) `ranks` (ties get the average rank) `zscores` | a constant variable has no correlation: NaN |
| `geometricMean` `harmonicMean` `weightedMean` | NaN for negative values or negative weights; a zero gives 0 |
| `covarianceMatrix(&data)` `correlationMatrix(&data)` | a `matrix.Matrix` with one observation per row and one variable per column |

### Streaming statistics and windows

| Class / function | What |
|---|---|
| `Welford` | online mean, variance, skewness and kurtosis in O(1) memory (Welford and Pebay's update formulas), minimum and maximum, `merge(&other)` for parallel or chunked data; the sums are kept relative to the first value, so a million plus a spread of one keeps every digit |
| `Ema` | exponential moving average with `alpha` (`emaAlphaFromSpan`, `emaAlphaFromHalfLife` give pandas' conversions); `adjust = true` weights the history like pandas `ewm(adjust=True)` |
| `RollingStats(window)` | mean, sum, variance, minimum, maximum and median of the last `window` values. `add` is O(1) for the mean and variance (Welford with removal, on values shifted by the window mean of the last refresh), the extremes use monotone queues (O(1) amortised), the median a sorted copy (`add` shifts it: O(window) in the worst case); `mean variance stddev minimum maximum median` are O(1) (a NaN counter replaces the scan of the window), `sum` is an exact compensated sum, O(window). Removing a value from a running Welford state keeps the rounding error of that value's square, so a huge outlier would spoil the variance for up to `window` adds after it has left (a 1e12 outlier among values near 1: 7 digits). The state therefore carries a bound of its accumulated rounding error and is recomputed from the window (corrected two pass algorithm, compensated sums) as soon as the bound exceeds 1e-10 of the variance, or of the mean (relative to the larger of the absolute mean and the standard deviation), and anyway every `window` adds: ordinary data pays nothing, an outlier pays one O(window) pass (t470 compares every step of outlier, offset and growing-scale streams with a recomputation). A NaN poisons all results only while it is inside the window, an infinity gives mean = IEEE sum / n and variance NaN |
| `movingAverage` `weightedMovingAverage` `emaSeries` `cumsum` | whole-series versions (`cumsum` is compensated) |

### Histograms

`Histogram h(bins, lo, hi)` counts with equal width bins (the last bin includes `hi`, as in NumPy; values outside go to `below` / `above`, NaN to `nans`); `histogramAuto(x, n, rule)` chooses the range and
the number of bins with NumPy's rules `STURGES`, `SQRT_RULE`, `RICE`, `SCOTT`, `FD` (Freedman-Diaconis), `DOANE` and `AUTO_RULE` (the larger of Sturges and FD); `binWidth` and `binCount` give the rule's answer
without building anything. `count(i)`, `density(i)`, `edge(i)`, `binOf(x)`, `modeBin()`.

### Regression

`linearFit(x, y, n)`, `polyFit(x, y, n, degree)` and the general `olsFit(&X, y, addIntercept, weights)` return a `Regression`: coefficients, standard errors, t values and p values, `r2`, `adjR2`,
the residual standard error `sigma`, the F statistic and its p value, `fitted[]` and `residuals[]`; `predict(x)` for the one-variable fits. The fit is a **Householder QR** of the (column scaled) design matrix, never the
normal equations, so it stays accurate where the normal equations lose their digits (t451 fits a quadratic at x around 1000 and compares with the exact solution in fractions); a rank deficient design (a constant column next to the intercept, more coefficients than points) gives an error status (`matrix.ERR_RANK` or `matrix.ERR_ARG`). Rank deficiency is judged by the **condition of the whole triangle R** (`matrix.QR.rcond()`, a 1-norm estimate for R with unit columns, refused at or below `rows * eps`), not by its diagonal: an unpivoted QR does not show a rank deficiency in the diagonal of R alone, and a matrix that is rank 1 on paper (`u v^T` computed in doubles) often has `r22 / r11` of 1e-15, above `rows * eps`. Before this check, 18 of 1740 random rank deficient designs got coefficients of 1e14 and `err = 0` (t470 has the regression test).
`dispose()` frees the arrays. Weighted least squares takes non-negative case weights.

### Special functions and distributions

| Special functions | `erf erfc erfInv erfcInv gamma lgamma digamma beta lbeta incGammaP incGammaQ incGammaPInv incBeta incBetaInv stdNormalCdf stdNormalSf stdNormalPdf stdNormalQuantile` |
|---|---|

| Family | Functions (parameters follow the name) |
|---|---|
| normal | `normalPdf(x, mu, sigma)` `normalLogPdf` `normalCdf` `normalSf` `normalQuantile(p, mu, sigma)` |
| Student t | `tPdf(x, df)` `tCdf` `tSf` `tQuantile(p, df)` |
| chi-square | `chi2Pdf(x, k)` `chi2Cdf` `chi2Sf` `chi2Quantile` |
| F | `fPdf(x, d1, d2)` `fCdf` `fSf` `fQuantile` |
| gamma, beta | `gammaPdf(x, shape, scale)` ... `betaPdf(x, a, b)` ... (`Pdf Cdf Sf Quantile` each) |
| exponential, uniform, lognormal | `expPdf(x, rate)` ..., `uniformPdf(x, a, b)` ..., `lognormalPdf(x, mu, sigma)` ... |
| binomial, Poisson | `binomPmf(k, n, p)` `binomCdf` `binomSf` `binomQuantile` `poissonPmf(k, lambda)` `poissonCdf` `poissonSf` `poissonQuantile`; `k` and `n` are doubles that must hold whole numbers |

`...Sf` is the upper tail 1 - cdf computed directly, so a p value of 1e-300 is not rounded to 0: use `2 * tSf(|t|, df)` rather than `2 * (1 - tCdf(...))`. Quantiles are found by a safeguarded Newton iteration on the exact cdf (bisection whenever a step would leave the bracket), starting from an approximation (Cornish-Fisher for the t distribution; the normal quantile itself starts from Abramowitz and Stegun 26.2.23 and is polished by Halley steps). `tQuantile` has two special cases: `df = 1` (Cauchy) and `df = 2` use their closed forms (`cot(pi p)` written without cancellation, `(2p - 1) / sqrt(2 p (1 - p))`), which are right to the last digits for any p; for a tail below 1e-12 the iteration runs on the logarithmic scale (the tail is the power law `C x^-df` far out, an upper bound of the true tail, so Newton's method on `log(tail)` against `log x` is nearly a straight line and converges in a few steps even for `p = 1e-300`; the plain iteration needed about `ln(1/p)` steps and stopped at its limit of 400 far from the answer for `p` below about 1e-170). A quantile outside the range of a double (df below 1 and a tiny p) is `-inf` / `inf`; `tCdf` / `tSf` beyond |t| = 1e150 use the power law (accurate to about 1e-13: the exponent loses digits), they were NaN above 1e154. The t quantile in the tails is checked in t470 against 70 digit references (85 values, df 0.5 to 100, p from 1e-8 to 1e-300; worst relative error 2.5e-14).

**Accuracy** (checked in t447 to t449 against 70 digit decimal references computed independently in Python: series, continued fractions and Gauss-Legendre quadrature of the definitions): `erf`, `erfc`, `lgamma`
and `gamma` agree to 1e-15 relative error on the whole tested range (including arguments near 0: `erfc(1e-10)` is `1 - 1.1283791670955126e-10` to the last digit, and with it `stdNormalCdf` for |z| below 1e-7; the C library function `erfc` returned `1 - x` below 2^-27, 1.3e-10 relative error, until t470), `digamma` and `lbeta` to 1e-14, `erfInv` and the normal quantile to 1e-14, the incomplete gamma functions to 1e-13 and the incomplete beta function
to 1e-12; the upper tails `...Sf` and `incGammaQ` are computed directly, so they keep their relative accuracy where `1 - cdf` would be 0 (the normal quantile is tested down to p = 1e-300). The distribution functions are as accurate as the
special function behind them. The exact identities (`gamma(n + 1) = n!`, `I_x(1, 1) = x`, `P + Q = 1`, `erf + erfc = 1`, symmetry of the normal and t distributions) are tests of their own.
Invalid parameters (`sigma <= 0`, `df <= 0`, `p` outside [0, 1]) give NaN; the quantile of 0 and 1 is the end of the support (`-inf` / `+inf` for the normal).

**Large parameters.** The continued fractions and series behind the incomplete gamma and beta functions need about `sqrt(parameter)` terms and every term rounds, so the relative error grows like `1e-16 * sqrt(parameter)`:
the measured worst cases (a sweep of the upper tails against 70 digit references; the error depends on where the argument is, not only on the parameter) are 3e-14 for `tSf` with `df = 1e3`, 7e-14 at 1e4, 2.6e-13 at 1e5, and 1.6e-14, 2.9e-13 and **2.0e-12** for `fSf(f, 10, d2)` with `d2 = 1e3`, 1e4, 1e5, so expect 1e-12 to 1e-11 for parameters of 1e5 and more (not 1e-13). t465 compares single points up to 1e8 (`incBeta(0.4, 1e5, 1.5e5)`, `incGammaP(1e8, 1e8)`, `binomCdf(4900, 10000, 0.5)` and others, 2e-13 to 3e-13); there is no systematic sweep above 1e5, so for 1e8 the rule `1e-15 sqrt(parameter)` is an extrapolation, not a measurement.
Three measures keep this honest: (1) the binomial prefactor of the incomplete beta function takes the complement `n - x` as an exact input (without it `tCdf(1, 1e9)` was wrong in the ninth digit);
(2) the Student t distribution switches for `df >= 1e5` (and `t^2 < 2e-4 df`) to its expansion in `1 / df` (Cornish-Fisher polynomials to third order, 1e-14 relative, checked from `df = 1e5` to `1e17`); (3) when the
iteration needs more than 10^6 terms (a parameter above about 1e11) the function returns **NaN** instead of a wrong number (it took 0.5 s and answered 0.0126 for `incGammaP(1e15, 1e15)` before).

### Tests and confidence intervals

Every test returns `TestResult { stat, pvalue, df, df2, err }` (NaN everywhere and `err = matrix.ERR_ARG` for bad input: a null pointer, too few values, NaN in the data, a variance of 0, an unknown `tail`); `tail` is `TAIL_TWO`, `TAIL_LESS` or `TAIL_GREATER`. `Interval { lo, hi }` is NaN for bad input (a level outside (0, 1), `k > n`, an unknown method).

| Function | Test |
|---|---|
| `ttestOneSample(x, n, mu0, tail)` `ttestTwoSample(x, nx, y, ny, pooled, tail)` `ttestPaired` | Student t tests; the two-sample test is Welch's (Welch-Satterthwaite degrees of freedom) unless `pooled` |
| `chiSquareGof(observed, expected, k, ddof)` `chiSquareIndependence(table, rows, cols, yates)` | goodness of fit (`expected = null`: all categories equally likely) and independence of a contingency table (Yates' correction for 2 x 2) |
| `mannWhitney(x, nx, y, ny, tail)` | the U test; the p value is **exact** (dynamic programming over all arrangements) when there are no ties and both samples have at most 25 values, otherwise the normal approximation with tie and continuity corrections (SciPy's `"exact"` and `"asymptotic"`) |
| `anovaOneWay(data, sizes, k)` `varianceTest` `jarqueBera` | F tests and the Jarque-Bera normality test |
| `meanCI(x, n, level)` `meanDiffCI` `varianceCI` `proportionCI(k, n, level, method)` | Student t, Welch, chi-square intervals; proportions with `CI_WALD`, `CI_WILSON` (default) or `CI_CLOPPER_PEARSON` (exact, through the beta quantile) |
| `bootstrapCI(x, n, statFn, ctx, resamples, level, &rng)` | percentile bootstrap of **any** statistic: `statFn` is `double f(double* sample, int n, void* ctx)`; the resampling uses the generator you pass, so a seed gives the same interval on every target |

### Time series, clustering and PCA

`autocovariance`, `autocorrelation(x, n, maxLag, out)`, `partialAutocorrelation` (Levinson-Durbin) and `ljungBox(x, n, lags, modelDf)`. `kmeans(data, n, dim, k, &rng, maxIter, restarts)` is k-means++ seeding
and Lloyd's iterations with the best of several restarts (`KMeans`: `centers`, `labels`, `inertia`, `predict(point)`); the same generator state gives the same clusters on every target. `Pca(&data, keep, scale)` takes the
eigenvectors of the covariance matrix with the Jacobi solver of `matrix`: `components`, `variance`, `ratio` (share of the total variance), `transform` and `inverseTransform`; the sign of every axis is fixed (its largest
component is positive) so results do not flip between runs.

```c
import stats;

double x[8] = {2.1, 2.5, 3.1, 3.6, 4.0, 4.4, 5.2, 5.9};   double y[8] = {1.1, 1.7, 2.0, 2.8, 3.1, 3.9, 4.2, 5.0};
double m = stats.mean(x, 8),  sd = stats.stddev(x, 8, 1),  med = stats.median(x, 8);
double q1 = stats.quantile(x, 8, 0.25, 7);                         // NumPy's default definition
stats.Regression r = stats.linearFit(x, y, 8);                     // r.coef[0] + r.coef[1] x, r.r2, r.pvalue[1], r.residuals[i]
stats.TestResult t = stats.ttestTwoSample(x, 8, y, 8, false, stats.TAIL_TWO);   // Welch: t.stat, t.pvalue
double p = stats.tSf(2.5, 7.0);   double z = stats.normalQuantile(0.975, 0.0, 1.0);           // 1.959963984540054
stats.Interval ci = stats.meanCI(x, 8, 0.95);                      // ci.lo, ci.hi
r.dispose();
```

---


## matrix - dense and sparse linear algebra

`import matrix;`. Numbers are `double`, matrices are stored row by row (`m.d[i * m.cols + j]` is the fast access, `get(i, j)` / `set(i, j, v)` check their indexes), memory comes only from the `asys` layer, so it runs on all five
targets and on AOS.

```c
import matrix;

matrix.Matrix a(3, 3);                                         // 2 1 1 / 1 3 2 / 1 0 0
double v[9] = {2, 1, 1, 1, 3, 2, 1, 0, 0};   for (int i = 0; i < 9; i++) { a.d[i] = v[i]; }
matrix.LU f(&a);                                               // P A = L U with partial pivoting
double b[3] = {4, 5, 6};   double x[3];
if (f.solve(b, x) == matrix.OK) { /* x = 6, 15, -23 */ } else { printf("%s\n", matrix.errorText(f.err)); }
double d = f.det();  double rc = f.rcond();                    // 1-norm reciprocal condition estimate
f.dispose();  a.dispose();
```

### What is there

| Area | Classes and functions |
|---|---|
| construction | `Matrix(r, c)` (zero filled), `identity zeros ones diagonal fromArray outer hilbert`, `copy submatrix`, `getRow getCol setRow setCol swapRows swapCols setSubmatrix` |
| arithmetic | new matrices: `add sub mul transpose scaled hadamard` and the operators `+ - *`; **in place** (no allocation): `addInPlace subInPlace axpyInPlace scaleInPlace transposeInPlace mulInto(&b, &c)`, vectors: `mulVec mulVecT` |
| properties | `trace norm1 normInf normFro normMax isSymmetric isFinite det rank cond inverse solve`, vectors `vecDot vecNorm1 vecNorm2 vecNormInf vecAxpy vecScale vecCopy vecFill` (`vecNorm2` does not overflow or underflow) |
| `LU` | partial pivoting; `solve solveTranspose solveMatrix inverse det logAbsDet rcond cond1 lower upper permutation`; the loose function `luFactor` works in place on a plain array |
| `Cholesky` | `A = L L^T` for symmetric positive definite matrices; `solve det logDet inverse` |
| `QR` | Householder (LAPACK's storage); any shape; `q(full) r applyQ applyQt solveLS diagRatio rcond`; `solveLS` refuses (`ERR_RANK`) a matrix whose `rcond()` (condition estimate of R with unit columns) is at most `rows * eps`; `lstsq(&a, b, x, &resid, &rank)` solves least squares for **any** matrix (QR when it has full column rank in that sense, otherwise the SVD's minimum norm solution) |
| `SymEigen` | symmetric eigenvalues and orthonormal eigenvectors (cyclic Jacobi), ascending order |
| `SVD` | one sided Jacobi (Hestenes): `s u v rank cond pinv solve reconstruct norm2`, singular values descending, `U` and `V` thin (`m x k`, `n x k`) |
| sparse | `SparseVector` (sorted entries), `CsrMatrix` (built with `CooBuilder` or `fromDense`): `get mulVec mulVecT transpose addScaled mul scaled diagonal toDense`, and `cg(&a, b, x, maxIter, tol)` (Jacobi preconditioned conjugate gradient) |
| complex | `CMatrix` with parallel `re` / `im` arrays (A has no complex type): `add sub mul scaled conjTranspose trace normFro mulVec det solve` |

### Errors: no crash, no silent nonsense

Functions that can fail return a status: `matrix.OK` (0) or `ERR_DIM` (the shapes do not fit), `ERR_SINGULAR`, `ERR_NOT_SPD`, `ERR_NO_CONVERGE`, `ERR_MEMORY`, `ERR_NOT_FINITE` (NaN or infinity in the input or in the
result), `ERR_RANK`, `ERR_ARG` (null, empty or out of range argument), `ERR_NOT_SYMMETRIC`; `matrix.errorText(code)` names them. A method that returns a `Matrix` returns an **empty** one on failure (`ok()` is false,
`rows = 0`, `d = null`) whose `err` field says why; an empty matrix given to any operation fails with `ERR_ARG`. A *zeroed* object (declared without parentheses) or a disposed one is simply empty.

* **Singular matrices.** `solve()` and `inverse()` refuse a matrix with `ERR_SINGULAR` when a pivot is exactly 0 **or** when the estimated reciprocal condition number `rcond()` is below `matrix.EPS` (2.2e-16, the
  threshold at which MATLAB warns): such a system has no meaningful numeric answer. `LU f(&a, 0.0)` turns the rcond test off (only exact zero pivots are refused) when you know that you want an answer for an ill conditioned system;
  `f.rcond()` tells how much to trust it (about `log10(1 / rcond)` digits are lost). The determinant of an exactly singular matrix is 0. `rcond` is the 1-norm estimator of Hager and Higham (what LAPACK's `xGECON` does, within a small
  factor of the true value, checked in t441); `cond()` is the exact 2-norm condition number from the SVD.
* **Hilbert matrices** are the classic test: `hilbert(6)` solves with a visible loss of 7 digits (`rcond` about 1e-8), `hilbert(12)` is refused as singular to working precision, and with `minRcond = 0` it is solved and the answer is wrong
  in the fourth digit (t441 checks all three).
* **NaN and infinity.** The factorizations refuse input that contains them (`ERR_NOT_FINITE`) and results that overflow; `det()`, `cond()` and `norm...` of such a matrix give NaN; plain arithmetic (`add`, `mul`, norms) follows IEEE
  rules (NaN spreads). `vecNorm2` of a vector with infinity is infinity, with NaN NaN.
* **Not symmetric / not positive definite.** `Cholesky` and `SymEigen` check the symmetry (relative 1e-10: `ERR_NOT_SYMMETRIC`); `Cholesky` reports `ERR_NOT_SPD` for an indefinite **and** for a semi definite matrix (it has no unique factor).
* **Failed constructions still own memory.** When a factorization reports a numeric error (`Cholesky` with `ERR_NOT_SPD`, `LU` with `ERR_SINGULAR`) its parts are kept so that you can look at them (`LU.zeroAt`, `LU.det()`):
  call `dispose()` in every case; it is safe on a failed, a zeroed and an already disposed object.

### Memory

A `Matrix` is a **handle**: `Matrix b = a;` copies the handle, not the numbers (use `a.copy()`); `dispose()` frees the numbers and nothing is freed behind your back. Every operation is O(size) in memory: no operation copies a matrix inside a loop
(`mulInto`, the in place variants and `solve(b, x)` with `b` and `x` the same array allocate nothing, t468 counts the blocks). Sizes are limited to 2^28 numbers per matrix (`ERR_ARG` above, also when `rows * cols` would
overflow); a failed allocation gives `ERR_MEMORY`, never a crash. Blocks of several hundred KiB (a matrix of about 250 x 250 doubles) get a mapping of their own on AOS, and a process may hold only about 30 of them: reuse big matrices (`mulInto`, `copyFrom`, `solve(b, x)` with your own arrays), as the library does inside its loops; t468 checks that repeated work maps no new memory.

### Algorithms and cost

| | Algorithm | Cost | Notes |
|---|---|---|---|
| `LU` | Gaussian elimination, partial pivoting, row oriented | n^3 / 3 multiply-adds | `rcond` costs a few extra solves (O(n^2)) |
| `Cholesky` | row oriented | n^3 / 3 | half the work of LU, no pivoting needed |
| `QR` | Householder reflectors | 2 m n^2 | stable for ill conditioned least squares: the residual is minimised without squaring the condition number; `rcond()` is a Hager / Higham estimate on the column scaled R (O(n^2)), which is what recognises a rank deficient matrix (see Regression) |
| `SymEigen` | cyclic Jacobi with a threshold in the first sweeps | 6 to 10 sweeps of O(n^3) | slower than tridiagonal QL for big n, but accurate to the last digits for small eigenvalues and tiny code; `sweeps` tells how many were needed; up to 100 sweeps, then `ERR_NO_CONVERGE` |
| `SVD` | one sided Jacobi (Hestenes), `A` or `A^T` is rotated so that the columns are orthogonal | same order | high relative accuracy even for tiny singular values (the Hilbert matrix of order 8 in t443 keeps all its singular values, down to 1e-10); columns of `U` that belong to zero singular values are completed to an orthonormal set |
| `rank` / `pinv` / `lstsq` | from the SVD, threshold `max(m, n) * eps * s[0]` (NumPy's rule) | | pass `rtol` to change the threshold |
| `cg` | conjugate gradient, Jacobi preconditioner | O(nnz) per iteration | `ERR_NOT_SPD` when it meets a direction of non positive curvature, `ERR_NO_CONVERGE` after `maxIter` (x keeps the last iterate), `ERR_NOT_FINITE` for NaN |
| `CsrMatrix.mul` | Gustavson's algorithm with a dense accumulator row | O(flops + cols) | entries that cancel exactly are dropped |

---


## optim - numerical methods

`import optim;` (it uses `matrix` for the linear algebra inside). Roots, minima, integrals, differential equations, interpolation, polynomials, the FFT, linear programming and a few special sequences. All numbers are `double`.

### Callbacks and how to pass context

A has no closures, so a callback is an ordinary function whose name you pass as a `func` value, plus a **context pointer** (`void* ctx`) that is handed back to it on every call: a pointer to a struct of your own with the
parameters and counters the function needs, or `null`. The callbacks return a `double` (the library reads it back with `__dbl`); the signatures are

| Used by | Signature |
|---|---|
| scalar function: roots, 1-D minima, integrals, derivatives, `Chebyshev`, `findBracket` | `double f(double x, void* ctx)` |
| objective of `n` variables: `nelderMead bfgs gradientDescent gradientNum hessianNum`; also the statistic of `stats.bootstrapCI` (`double f(double* sample, int n, void* ctx)`) | `double f(double* x, int n, void* ctx)` |
| gradient (optional, `null` means central differences) | `void grad(double* x, int n, double* g, void* ctx)` |
| ODE right hand side `y' = rhs(t, y)` | `void rhs(double t, double* y, double* dydt, int n, void* ctx)` |
| `n` equations `F(x) = 0` for `newtonSystem` and `jacobianNum` | `void fvec(double* x, int n, double* out, void* ctx)` |

```c
import optim;
import dmath;

struct Decay { double k; int calls; }                              // the context: a parameter and a counter

double f(double x, void* c) { Decay* p = (Decay*) c;  p->calls++;  return dmath.exp(-p->k * x) - 0.5; }

Decay p;  p.k = 2.0;  p.calls = 0;
optim.Result r = optim.brent(f, &p, 0.0, 5.0, 1.0e-12, 100);      // the root of exp(-k x) = 1/2 in [0, 5]
if (r.status == optim.OK) { /* r.x = ln 2 / 2, r.fx, r.iterations, r.evals, p.calls */ }
```

A callback that returns NaN or infinity where a number is needed makes the call return `ERR_NAN`; it is never turned into a wrong answer. A **null** callback gives `ERR_ARG` (or NaN for the functions that return a number).
Every function that can fail returns a status (`optim.OK`, `ERR_ARG`, `ERR_BRACKET` (no sign change), `ERR_NO_CONVERGE`, `ERR_NAN`, `ERR_SINGULAR`, `ERR_MEMORY`, `LP_INFEASIBLE`, `LP_UNBOUNDED`) in its result or as its
return value; `optim.errorText(status)` names it. Bad arguments (NaN or infinite limits, `tol < 0`, a count below 1, reversed or empty intervals where that matters) are `ERR_ARG`; `ERR_NO_CONVERGE` still returns the best estimate.

### Roots and minima

| Function | Method and notes |
|---|---|
| `bisection(f, ctx, a, b, tol, maxIter)` | one binary digit per evaluation, always converges; `f(a)`, `f(b)` must have opposite signs (`ERR_BRACKET` otherwise) |
| `brent(f, ctx, a, b, tol, maxIter)` | Brent's method (inverse quadratic interpolation, secant, bisection fallback): superlinear for smooth functions with the guarantee of bisection; `tol` is absolute |
| `newton(f, df, ctx, x0, tol, maxIter)` | `df = null` uses a central difference; `ERR_SINGULAR` for a zero derivative, `ERR_NAN` when the iterate leaves the numbers |
| `secant(f, ctx, x0, x1, tol, maxIter)` | no derivative, no bracket guarantee |
| `findBracket(f, ctx, x0, step, &a, &b)` | walks away from `x0` with steps that grow by 1.6 until the sign changes (60 expansions at most) |
| `newtonSystem(fvec, ctx, x, n, tol, maxIter)` | Newton for `n` equations: numerical Jacobian, LU from `matrix`, the step is halved while the residual does not decrease; `ERR_SINGULAR` for a singular Jacobian |
| `goldenSection` `brentMin` `bracketMin` | one variable minimisation on `[a, b]` (the precision of the minimiser is about `sqrt(eps)`, because the function is flat there) and a downhill bracketing |
| `nelderMead(f, ctx, x, n, step, tol, maxEval)` | simplex method, no derivatives; `x` holds the start and receives the minimiser |
| `bfgs(f, grad, ctx, x, n, gtol, maxIter)` | quasi-Newton with a line search; `grad = null` uses central differences (2n evaluations, precision limited to about 1e-8) |
| `gradientDescent(f, grad, ctx, x, n, step0, gtol, maxIter)` | steepest descent with Armijo backtracking (robust, slow in narrow valleys) |
| `derivative derivative5 gradientNum jacobianNum hessianNum` | central differences with the step `cbrt(eps) * max(|x|, 1)` (about 1e-10 relative error), a five point formula, gradient, Jacobian (forward differences) and Hessian (about 6 digits) |

`Result { x, fx, err, iterations, evals, status }`: `err` is the half width of the final interval (roots), the final simplex size (`nelderMead`) or the gradient norm (`bfgs`).

### Integration and differential equations

| Function | Method and notes |
|---|---|
| `trapezoid simpson(f, ctx, a, b, n)` | composite rules, `n` panels (Simpson rounds up to even) |
| `romberg(f, ctx, a, b, tol, maxLevels)` | trapezoid rules with 1, 2, 4 ... 2^(maxLevels - 1) panels and Richardson extrapolation: excellent for smooth functions on finite intervals |
| `gaussKronrod(f, ctx, a, b, absTol, relTol, maxSub)` | **adaptive G7 / K15** (QUADPACK's `qag` rule): the subinterval with the largest error estimate is bisected until `max(absTol, relTol |I|)` is reached; **infinite limits** (`+-dmath.INFINITY`) are mapped to a finite interval; integrable endpoint singularities converge slowly but converge; `error`, `evals` and `intervals` are reported |
| `gaussLegendre(n, x, w)` `integrateGL` | the `n` point rule on `[-1, 1]` / `[a, b]` (exact for degree 2n - 1; nodes by Newton's method on `P_n`) |
| `integrateSamples simpsonSamples` | the trapezoid / Simpson rule for tabulated data |
| `rk4(rhs, ctx, n, t0, y0, t1, steps, yOut, traj)` | the classical fixed step Runge-Kutta; the whole trajectory on request |
| `Rk45 s(rhs, ctx, n, t0, y0, rtol, atol)` | Dormand-Prince 5(4) with adaptive step (error per step `atol + rtol max(|y|, |ynew|)`, automatic first step): `step(tEnd)`, `solveTo(tEnd, maxSteps)`, `solveAt(times, count, out, maxSteps)`; counters `nfev nsteps nrejected`; `ERR_NAN` for a right hand side that returns NaN, `ERR_NO_CONVERGE` when the step underflows or `maxSteps` is exceeded |

`Integral { value, error, evals, intervals, status }`.

### Interpolation and polynomials

| Function | Notes |
|---|---|
| `interpLinear(xs, ys, n, x)` | piecewise linear, end values outside the range (like `numpy.interp`) |
| `Spline(x, y, n, bc, d0, dn)` | cubic spline, `SPLINE_NATURAL` or `SPLINE_CLAMPED` (end slopes `d0`, `dn`); `value derivative(x, order) integral(a, b)` (exact); outside the range the end cubic continues; `err = ERR_ARG` for x not strictly increasing |
| `Barycentric(x, y, n)` | Lagrange interpolation in barycentric form: stable for any distinct nodes, O(n) per evaluation |
| `chebyshevNodes(n, a, b, out)` `Chebyshev(f, ctx, a, b, terms)` | nodes of the first kind and a Chebyshev series fitted to a function: `value` (Clenshaw), `derivative`, `integral`, `coefficient(j)` |
| `polyEval polyEvalDeriv polyDeriv polyIntegral polyAdd polyMul polyDivide polyFromRoots` | coefficients in **increasing** order (`coef[k]` belongs to `x^k`); Horner evaluation |
| `polyRoots(coef, degree, re, im)` | **Aberth-Ehrlich** iteration (all roots at once, cubic convergence for simple roots), Newton polishing on the original polynomial, zero roots taken out first; the roots come sorted by real part then imaginary part (conjugate pairs together); a multiple root has half the digits, as with every numerical method (t459 includes (x - 1)^4); returns the number of roots or `-ERR_...` |
| `polyFit(x, y, n, degree, coef)` | least squares through the QR decomposition of `matrix` (x is scaled to [-1, 1] internally for conditioning) |

### FFT and convolution

`fft(re, im, n, inverse)` transforms `n` complex numbers (separate `re` and `im` arrays) in place for **any** `n >= 1`: a radix-2 algorithm for powers of two and Bluestein's chirp-z algorithm for every other length (O(n log n)
always); the inverse includes the factor `1 / n`. `FftPlan plan(n)` computes the twiddle factors (and for other lengths the chirp and the transform of its kernel) once for many transforms of the same length: `plan.forward(re, im)`,
`plan.inverse(re, im)`. `rfft(x, n, outRe, outIm)` / `irfft` take real input (`n / 2 + 1` outputs), `convolve(a, na, b, nb, out)` is direct for short inputs and FFT based for long ones (`convolveDirect`, `convolveFft`
force one), `crossCorrelate`, `fftFrequencies(n, d, out)` (as `numpy.fft.fftfreq`) and `windowFunction(WIN_HANN ..., n, out)`. The twiddle factors come from `sincosTurns(k, n, &s, &c)`: exact integer octant reduction and a
Taylor series (about 1 ulp, ten times faster than `dmath.sin`), so a transform has the same bits on every target. The results match the O(n^2) definition to 1e-11 for lengths up to 100 and the round trips are exact to 1e-12 for
n = 1009, 1024, 2053, 3000, 4096 (t460); the FFT convolution of integer data is rounded back to exact integers in the tests.

### Linear programming

`linprog(c, n, A, m, b, kinds, maximize, x, &objective, &iterations)` solves `max (or min) c.x` subject to `m` rows `A x <= b` / `= b` / `>= b` (`kinds[i]` is `optim.LE`, `EQ` or `GE`; `null` means all `LE`) and `x >= 0`
with the **two phase simplex method** on a dense tableau (O(m (n + m)) memory). Dantzig's pricing is used, Bland's rule takes over when degenerate pivots repeat, so the method cannot cycle; the pivot count is bounded
(`ERR_NO_CONVERGE`). Returns `OK`, `LP_INFEASIBLE`, `LP_UNBOUNDED`, `ERR_NAN` (non-finite data), `ERR_ARG` or `ERR_MEMORY`; tolerance 1e-9 relative to the size of the data. t461 checks 60 random programs against the
exact optimum found by enumerating **all vertices** in fractions, and infeasible and unbounded programs by construction.

### Special sequences

`fibonacciD lucasD catalanD factorialD binomialD harmonicD bernoulliD` (as `double`: exact while below 2^53, `+inf` beyond the range of a double, NaN for negative arguments where there is no value) and the orthogonal polynomials
`legendreP chebyshevT chebyshevU hermiteH laguerreL` (three term recurrences, NaN for a negative degree); `fibonacciD(-n)` follows `F(-n) = (-1)^(n+1) F(n)`; `bernoulliD` uses the exact fractions up to n = 30 and the zeta
series above (relative error about 1e-13), `B(1) = -1/2`. The integer sequences up to 2^63 are in `math` and `arith`, the big ones in `bigint`.

---


## Speed

Measured by `examples/algo_bench.a` (`ds`, `strx`, `rng`) and `examples/numeric/algo2_bench.a` (`matrix`, `stats`, `optim`); native x86-64, one run on a shared 4 CPU machine: expect plus or minus 20 percent; everything is compiled by `ac`, doubles are soft float.

**ds**

| operation | per second |
|---|---:|
| Deque pushBack + popFront | 87 M |
| RingBuffer push (overwriting) | 172 M |
| BinaryHeap push + pop (200000 each) | 3.4 M |
| OrderedMap put (random keys) | 957 K |
| OrderedMap get | 2.2 M |
| OrderedMap floorNode | 2.0 M |
| OrderedMap rank | 2.2 M |
| OrderedMap remove (mostly absent keys) | 1.6 M |
| HashMap put (int keys, 500000 keys) | 8.8 M |
| HashMap get | 16 M |
| TextHashMap add (text keys) | 4.5 M |
| TextHashMap get | 10 M |
| Trie put (text keys) | 2.8 M |
| Trie countPrefix | 31 M |
| Trie countWildcard (100000 keys) | 29 K |
| DisjointSet unite (random pairs) | 7.4 M |
| DisjointSet find | 60 M |
| BitSet set (random bit) | 97 M |
| BitSet count (1000000 bits) | 13 K |
| Fenwick add / prefix (500000 each) | 14 M |
| SegTree range add / range sum (lazy) | 678 K |
| LruCache get / put (capacity 10000, 20000 keys) | 5.3 M |
| BloomFilter add + mightContain | 16 M |
| CountMinSketch add + estimate | 61 M |

**strx**

| operation | per second |
|---|---:|
| Kmp.count: bytes per second (4 MB, 12 letter pattern) | 108 M |
| Horspool.count: bytes per second | 133 M |
| RabinKarp.count: bytes per second | 65 M |
| AhoCorasick (500 patterns): bytes per second | 15 M |
| levenshtein of two 40 letter texts | 84 K |
| levenshteinMax(k = 3) of two 40 letter texts | 1.4 M |
| osa of two 40 letter texts | 74 K |
| jaroWinkler of two 40 letter texts | 185 K |
| lcsLength of two 40 letter texts | 130 K |
| SuffixArray build: letters per second (2 MB, 4 letters) | 2.5 M |
| SuffixArray.count of a 5 letter pattern | 1.2 M |
| longestPalindrome (Manacher): letters per second | 22 M |
| LineDiff.run: lines per second (100000 lines, 400 edits) | 6.7 M |
| FuzzyMatcher.rank: candidates per second | 3.6 M |
| globMatch src/**/*.a | 3.8 M |
| SplitMix64.nextU64 | 204 M |

**rng**

| operation | per second |
|---|---:|
| Xoshiro256.nextU64 | 71 M |
| Pcg32.nextU64 (two 32 bit outputs) | 67 M |
| Pcg64.nextU64 | 48 M |
| Mt19937.nextU64 (two 32 bit outputs) | 18 M |
| ChaCha20Rng.nextU64 (CSPRNG) | 2.6 M |
| below(1000) (Lemire, no bias) | 38 M |
| nextDouble (soft float) | 2.8 M |
| normal (ziggurat) | 1.0 M |
| exponential (ziggurat) | 965 K |
| gamma(2.5) | 99 K |
| poisson(4) | 735 K |
| poisson(100) (PTRS) | 20 K |
| binomial(100, 0.1) | 104 K |
| shuffle: elements per second | 14 M |
| sample(1000000, 1000): samples per second x 1000 | 8.3 M |
| AliasTable.sample (1000 categories) | 3.3 M |
| uuid4 | 685 K |

**matrix** (`examples/numeric/algo2_bench.a`; a "flop" is one multiply-add)

| operation | per second |
|---|---:|
| `Matrix.mulInto` 100 x 100 (flops) | 5.8 M |
| `LU` factorization of 150 x 150 (n^3 / 3 flops) | 5.0 M |
| `LU.solve` of one right hand side (150 x 150) | 254 |
| `Cholesky` 120 x 120 (n^3 / 3 flops) | 10.5 M |
| `QR` (Householder) 120 x 60 (2 m n^2 flops) | 13.8 M |
| `SymEigen` (Jacobi) of a 40 x 40 matrix | 3 |
| `SVD` (one sided Jacobi) of a 50 x 30 matrix | 4 |
| `CsrMatrix.mulVec` (60000 entries): entries | 7.0 M |
| `cg` on a 20000 x 20000 tridiagonal system: iterations | 32 |

**stats**

| operation | per second |
|---|---:|
| `mean` + `variance`: numbers | 2.1 M |
| `median` (sorts a copy): numbers | 3.2 M |
| `correlation` + `skewness` + `kurtosis`: numbers | 1.0 M |
| `spearman`: numbers | 510 K |
| `Welford.add` (four moments) | 360 K |
| `RollingStats(100)`: `add` + `mean` + `median` | 110 K (145 K before the rounding error bookkeeping of the review) |
| `normalCdf` | 6.5 K |
| `tCdf` (9 degrees of freedom) | 2.5 K |
| `tQuantile` | 214 |
| `gamma` + `lgamma` (per pair) | 7.1 K |
| `incBeta` | 2.1 K |
| `binomPmf` + `poissonCdf` (per pair) | 6.2 K |
| `olsFit` with 2000 observations and 4 variables: fits | 33 |
| `ttestTwoSample` of 2 x 20000 numbers: numbers | 1.0 M |
| `mannWhitney` of 2 x 5000 numbers: numbers | 1.0 M |
| `kmeans` (2000 points, k = 4, 2 restarts): points x restarts | 19 K |

**optim**

| operation | per second |
|---|---:|
| `brent`: roots of cos(x) - x to 1e-12 | 4.2 K |
| `gaussKronrod`: integrals of exp(-x^2) over [-4, 4] to 1e-12 | 122 |
| `romberg`: the same integral | 54 |
| `Rk45`: accepted steps (two equations, tolerance 1e-9) | 8.9 K |
| `bfgs` with a numerical gradient: Rosenbrock minimisations | 1.7 K |
| `nelderMead`: Rosenbrock minimisations | 2.5 K |
| `FftPlan` transforms of length 1024 (radix 2) | 238 |
| `FftPlan` transforms of length 4096 (radix 2) | 49 |
| `FftPlan` transforms of length 1000 (Bluestein) | 50 |
| `FftPlan` transforms of length 4099 (Bluestein) | 5 |
| `convolve` of two 2000 number arrays (FFT) | 13 |
| `polyRoots` of a polynomial of degree 20 | 98 |
| `linprog` with 30 variables and 30 constraints | 113 |

How to read it: the byte and letter rates are for the whole run of one search or build; the others are single operations. `Kmp`, `Horspool`, `RabinKarp` and `AhoCorasick` scan 4 MB of random text over four letters. Soft float makes the `double` based
functions much slower than the integer ones (`normal` needs about 1 microsecond, `gamma` 10, `poisson(100)` 50, because their rare branches call the 45 microsecond `log` and `exp`); the integer generators run at 15 to 200 million numbers per second.

The numeric modules pay for the soft float in every operation: about 5 million multiply-adds per second (a 100 x 100 matrix product takes 0.2 s, an LU solve of 150 unknowns 4 ms), a transcendental function about 45 microseconds. That is fine for the sizes
of everyday work (hundreds of unknowns, thousands of data points, FFTs of a few thousand points) and too slow for big ones: a Jacobi eigenvalue problem of order 200 takes minutes. The riscv64 target under `qemu-user` is about 16 times slower again.

---

## Tests

Tests t410 to t419 (`ds`), t420 to t428 (`strx`), t429 (null pointers and negative or absurd arguments in `strx` and `rng`, empty / zeroed / disposed containers in `ds`), t430 to t436 (`rng`) and t437 (every class zeroed, with size 0, 1, 2 and after `dispose()`; the examples of the module headers and of this file run as printed; the regression tests of the review findings) in `tests/`; they run on all five targets and, as the `algo` test of `tests/boot_test.py` of the AOS repository, inside AOS.

* **Differential tests** compare every structure with a plain model that is easy to get right (arrays, brute force, a full dynamic programming table) on thousands of random operations.
* **Expected outputs from independent implementations**: t430 (all generator sequences) was produced by Python implementations that were first checked against NumPy, Python's `random`, `cryptography`
  (ChaCha20), the RFC 8439 vector, the PCG demo output and the MT19937 reference output; t432 (distributions) by NumPy itself; t434 and t435 (shuffle, sampling, alias table, reservoir, UUID, the key
  erasure refill and `mixIn`) by Python mirrors of the documented algorithms. The `jump` polynomials of xoshiro were verified against 2^128 and 2^192 powers of its transition matrix.
* The unified diff text of t423 is identical to the output of GNU `diff -u`; 600 random file pairs were additionally applied with the real `patch(1)` and compared with `diff --minimal` for length (not part of the test suite).
* Statistical tests (t431, t433, t434) use fixed seeds, so their result never varies; thresholds are far in the tails.
* Big inputs (tens to hundreds of thousands of elements, lines or letters; t419 also 1.6 million bits) check that nothing is quadratic (the sizes are chosen so that the slowest tests take about 20 seconds or less on riscv64 under `qemu-user`, which is about 16 times slower than native for the soft float code; the limit of the test runner is 60 seconds); memory tests check that `dispose()` returns everything (`asys.memInUse()`), and that no block is freed twice.

---

**Numeric modules: tests t440 to t470.** t440 to t445 are `matrix` (basics, LU, Cholesky and QR, eigenvalues and SVD, sparse, complex), t446 to t453 `stats` (descriptive statistics, special functions, continuous and discrete distributions,
streaming and histograms, regression, tests and intervals, time series / k-means / PCA), t454 to t462 `optim` (roots, minima, integrals, ODEs, interpolation, polynomials, FFT, linear programming, sequences), and t463 to t469 the cross
cutting tests: the examples of the module headers and of this file run as printed (t463), hostile input to `matrix` (t464) and to `stats` and `optim` (t465), every public function and method called with hostile arguments and checked for
leaks (t466, generated by `tests/algo2_ref/mk_t466.py` from the signatures in `lib/*.a`), problems with a planted solution and cross checks between independent methods (t467), memory behaviour in the AOS allocator mode (t468) bit exact
results against hardware doubles (t469) and the regression tests of the findings of the independent review (t470: rank deficient least squares, t quantiles in the tails, `erfc` near 0, `RollingStats` after outliers, the sign of a zero determinant; the tables are made by `tests/algo2_ref/mk_t470.py`). They run on all five targets and, as the `algo2` test of `tests/boot_test.py` of the AOS repository, inside AOS.

* **The expected outputs come from Python** (`tests/algo2_ref/gen_t4NN.py`, regenerate with `python3 tests/algo2_ref/gen_all.py`), written independently of the library and using only the standard library: exact `fractions` (normal
  equations, Gaussian elimination, adjugates, splines, Mann-Whitney by dynamic programming), 60 and 70 digit `decimal` arithmetic (the special functions and distributions of `refspecial.py` from series, continued fractions and
  quadrature of the definitions; DFTs; eigenvalues and singular values by a cyclic Jacobi iteration; roots by Newton's method; roots of unity by their trigonometric form), and `statistics.NormalDist`. The printed values are rounded
  to 9 significant digits (or a tolerance is checked), so every target prints the same text. t469 is the exception that proves the arithmetic: its expected output is the bits of a hardware double computation, which the soft float
  must reproduce exactly.
* **Hard cases**: the Hilbert matrix (condition number 1.5e10 at order 8, singular to working precision at order 12), a polynomial fit at x around 1000, columns of size 1e150 and 1, rank one and rank deficient matrices,
  Wilkinson's polynomial and multiple roots, 60 random linear programs checked against the exact optimum by enumerating all vertices (t461) and 12 against their duals (t467), table rows of every continuous distribution with tail
  probabilities down to 1e-300, huge degrees of freedom and shape parameters (t465).
* **Planted solutions** (t467): random systems of 1 to 70 unknowns with a known integer solution, `Q diag(d) Q^T` with known eigenvalues, `U diag(s) V^T` with known singular values, data with a known covariance for PCA, three
  clusters for k-means, polynomials built from known roots; plus cross checks (Cholesky against LU, CG against LU, regression against the normal equations, three quadrature rules against each other, three minimisers, spline against
  Lagrange against the function, the FFT against the O(n^2) definition and the circular convolution theorem).
* **Robustness** (t464 to t466): null pointers, null callbacks, zero and negative counts, NaN, infinity, 1e308, absurd shapes (`Matrix(2^63 - 1, 2)`), singular and indefinite matrices, zeroed and disposed objects, aliased arguments.
  The generated test t466 makes about 2700 hostile calls and checks `asys.memInUse()` after each one. The first run of this idea found about 45 crashes (null callbacks, `luFactor(null)`,
  `SparseVector.dotDense(null)`, `Welford.addAll(null)`, `vecDot(null, ...)` ...), two practically endless loops (`catalanD` and `binomialD` with huge arguments), a silent wrong answer (`incGammaP(1e15, 1e15)`) and the loss of digits of
  every beta based distribution at large parameters; all are fixed and covered.
* **Memory** (t468): with `asys.setKeepBigBlocks(1)` (the behaviour of AOS and Windows) every workload is repeated and must not map new memory in the second round; everything is given back; the in place operations allocate nothing.
* Timing: every test takes at most 1.5 seconds natively (the slowest, t460, 1.2 s; riscv64 under `qemu-user` is about 16 times slower, the limit of the test runner is 60 seconds).

---

## Limitations

* **Not thread safe**; no containers of structs (ints only: store pointers or indexes).
* `ds` hash maps: entry numbers are invalidated by an insert of a new key. A `BinaryHeap` handle is valid until its element leaves; the number is reused afterwards.
* `strx.damerau` needs the full table and refuses inputs above 2^23 cells; `LineDiff` is not minimal when `maxCost` is exceeded (`exact()` tells); `FuzzyMatcher` scores long candidates (> 1024 symbols) and long patterns (> 64) greedily;
  `globMatch` has no brace expansion and, in path mode, no `/` inside `[...]`; case folding is ASCII, Latin-1, Greek and Cyrillic only; `LineDiff` compares whole lines (no ignore-whitespace options).
* `SuffixArray` takes about 24 bytes per input byte (SA-IS needs more while it builds); `AhoCorasick` about 48 bytes per trie node.
* `rng` distributions need `n` up to 2^53 for `binomial`; the large-`n` binomial is exact but not NumPy's BTPE, so its numbers differ from NumPy's there. `Pcg32` / `Mt19937` seed with 32 or 64 bits only.
  Gamma, beta, Poisson and binomial call the slow correctly rounded `log` / `exp` / `pow` and are therefore far slower than integer generators.
* ChaCha20Rng is as secure as ChaCha20 and the operating system random source; nothing else in `rng` is suitable for secrets. There is no fork detection.
* On AOS big blocks (above 128 KiB) come from a bump allocator that never reuses address space: code that must run there should reuse big buffers (the library does). The tests run on AOS with exactly the same
  inputs as on Linux (nothing is shrunk for AOS); the `algo` boot test checks that every one of them prints the same bytes there.
* **Numeric modules.** Soft float: everything numeric is 20 to 100 times slower than the same code on a CPU with a floating point unit (see Speed); `SymEigen` and `SVD` are Jacobi methods (O(n^3) per sweep, 6 to 10 sweeps): fine up to
  about 100 x 100, slow beyond. `matrix` holds at most 2^28 numbers per matrix, has no sparse direct solver (conjugate gradient only, for symmetric positive definite matrices), no complex eigenvalues or SVD, and no banded or triangular
  special cases. `Cholesky` and `SymEigen` check the symmetry to 1e-10 relative and use the upper triangle.
* **Accuracy limits**: the incomplete gamma and beta functions (and with them the gamma, beta, F, binomial and Poisson functions) lose accuracy with the size of the parameter: measured worst cases are 3e-14 (t, df = 1e3), 2.9e-13 (F, d2 = 1e4) and
  2e-12 (F, d2 = 1e5), unmeasured above that (extrapolated: 1e-11 near 1e8), NaN above about 1e11; Student t is accurate to 1e-14 for df >= 1e5 inside its expansion domain t^2 < 2e-4 df, and its tails beyond |t| = 1e150 to about 1e-13; `bernoulliD` is exact to n = 30 and 1e-13 relative above; `harmonicD` above 1000 uses the asymptotic series (1e-16); `Rk45` and `gaussKronrod` stop at the tolerance you
  give, not at the last digit; numerical derivatives are good to about 1e-10 (`derivative`) and 1e-6 (`hessianNum`); `polyRoots` finds a root of multiplicity m with about 16 / m digits; `bfgs` without a gradient stops at about 1e-8.
* `stats`: `mannWhitney` is exact only for samples of at most 25 values without ties (otherwise the normal approximation with corrections), `kendall` is O(n^2), no Fisher exact test and no Kolmogorov-Smirnov test, `bootstrapCI` is the
  percentile method. `kmeans` needs the data in memory as one array. Quantile and rank based functions allocate a sorted copy (and give NaN when memory is short).
* `optim`: `linprog` uses a dense tableau (O(m (n + m)) memory, at most 100000 variables and rows but the tableau must stay below 2^28 numbers), `polyFit` and `Spline` need their points sorted or distinct as documented, `interpLinear` checks only
  `xs[0] < xs[n - 1]`, `legendreP(n, x)` and the other recurrences take O(n) time for a huge degree `n`. A callback that returns NaN is reported (`ERR_NAN`); an infinity is an error for integrals and ODEs but an ordinary huge number for root finders
  (a pole looks like a sign change) and minimisers.
* On AOS the numeric tests run with exactly the same inputs as on Linux (the `algo2` boot test compares every output byte for byte); a matrix of several hundred KiB (about 250 x 250 doubles) gets a mapping of its own there and a process may hold only about 30 mappings: build big matrices once and reuse them, the library does the same inside its loops (t468).

