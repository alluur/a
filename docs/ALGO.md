# Data structures, string algorithms and random numbers

Three modules for everyday programming, written in A and built into the compiler (`import ds;`, `import strx;`, `import rng;`):

| Module | What it is |
|---|---|
| [`ds`](#ds---data-structures) | deque, ring buffers, binary heap with handles, ordered map and set (AVL tree), hash maps for ints and texts, trie with wildcard search, union-find, bit set, Fenwick and segment trees with lazy updates, interval set, LRU cache, Bloom filter, count-min sketch |
| [`strx`](#strx---string-algorithms) | KMP, Horspool, Rabin-Karp, Aho-Corasick, edit distances and similarities, LCS, Myers diff with unified output, suffix array, Manacher, fuzzy matching (quick open), glob matching, Soundex, natural order |
| [`rng`](#rng---random-numbers) | SplitMix64, xoshiro256\*\*, PCG32, PCG64, MT19937, a ChaCha20 CSPRNG; unbiased bounded integers, 53 bit doubles, normal / exponential / gamma / beta / Poisson / binomial / geometric, shuffle, sampling, alias method, reservoir sampling, UUID v4 |

They compose and extend [`algo`](LANGUAGE.md#12b-built-in-modules) (sorting, union-find, graphs, `editDistance`, `kmpFind`), `collections` and `random`, whose APIs are unchanged.
Everything works on all five targets and on AOS, uses only the `asys` layer for memory and the system random source, and gives the same results everywhere
(`rng` doubles are soft float, so a seed gives the same numbers on every CPU).

Contents: [conventions](#conventions) · [ds](#ds---data-structures) · [strx](#strx---string-algorithms) · [rng](#rng---random-numbers) · [speed](#speed) · [tests](#tests) · [limitations](#limitations)

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

## Speed

Measured by `examples/algo_bench.a` (native x86-64, one run on a shared 4 CPU machine: expect plus or minus 20 percent; everything is compiled by `ac`, doubles are soft float).

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

How to read it: the byte and letter rates are for the whole run of one search or build; the others are single operations. `Kmp`, `Horspool`, `RabinKarp` and `AhoCorasick` scan 4 MB of random text over four letters. Soft float makes the `double` based
functions much slower than the integer ones (`normal` needs about 1 microsecond, `gamma` 10, `poisson(100)` 50, because their rare branches call the 45 microsecond `log` and `exp`); the integer generators run at 15 to 200 million numbers per second.

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
