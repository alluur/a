# Notes of the contributor for chapter 37 (data structures, string algorithms and random numbers)

Chapter: `src/37-data-structures-strings-random.md`, samples: `samples/algo/` (32 samples). Everything below was found while writing and
running them with the compiler of this branch (`build/ac`). All samples compile for all nine targets (`samples.py --targets algo`) and
were **run** on x86-64 Linux and under `qemu-user` on linux-arm64, linux-riscv64 and linux-loongarch64 (`--run-target`): the output is
identical on all four. Windows and the four Android targets were compiled only.

## (a) Compiler and library bugs

I found **no compiler bug** and no library function that returns a wrong result. All outputs that could be checked independently were
(see "What I verified" at the end). The surprises are API traps, listed under (b) because the documentation is where they belong.
No generator or distribution differed between targets.

### 1. A zeroed `ds.BitSet` ignores `set()` (docs say it "grows on first use")

`docs/ALGO.md` ("Conventions") puts `BitSet` in the list of classes that "are empty containers that grow on first use" when they were only
zeroed. They do not grow on `set`:

```c
import ds;
int main() {
    ds.BitSet bs;                       // also ds.BitSet bs();
    bs.set(5);
    printf("size %d get %d\n", bs.size(), bs.get(5));     // size 0 get 0: set() out of range is ignored
    bs.resize(10);
    bs.set(5);
    printf("size %d get %d\n", bs.size(), bs.get(5));     // size 10 get 1
    return 0;
}
```

This is the documented rule "out of range is ignored" (the source comment of `set` says so), so it is the doc list that is wrong, not
the code. (`DisjointSet` really does grow: `add()`.) The chapter says so under "Limits and traps".

### 2. `strx.LineDiff d();` does not compile

```c
import strx;
int main() { strx.LineDiff d(); return 0; }
```

```text
error: this class has no constructor
```

`LineDiff` has no constructor, so it can only be declared `strx.LineDiff d;`. `docs/ALGO.md` ("Conventions") says "Declare objects with
parentheses ... when the class has constructor arguments", which is true, but the first sentence of the same file's `ds` header comment
("Declare an object on the stack WITH parentheses") invites the error for every class. `Trie` and `IntervalSet` have an empty constructor
and accept both forms; `LineDiff` does not.

### 3. `LineDiff.run` after `splitLines`: the example of the docs loses the "no newline" information

`docs/ALGO.md` ("Diff of two line arrays") shows `strx.splitLines(textA, -1, &n1)` and `d.run(a, n1, b, n2)`. `splitLines` reports through
its fourth argument whether the last line had no newline, and `run` takes that as its 6th and 7th argument (`eolMissingA`, `eolMissingB`).
Without them the patch is wrong for texts without a final newline:

```c
import strx;
int main() {
    int na = 0; int nb = 0;
    char** a = strx.splitLines("one\ntwo\nthree", -1, &na);       // no newline at the end
    char** b = strx.splitLines("one\nthree\nfour\n", -1, &nb);
    strx.LineDiff d;
    d.run(a, na, b, nb);
    print(d.unified("a.txt", "b.txt"));
    return 0;
}
```

Output: `three` is shown as an unchanged context line. `diff -u a.txt b.txt` shows `-three`, `\ No newline at end of file`, `+three`. With
`bool eolA; splitLines(..., &eolA)` and `d.run(a, na, b, nb, 8000, eolA, eolB)` (or with `runText`) the output equals `diff -u` (checked
against GNU diff for the diffs in `samples/algo/text_diff.a`). This is an API trap, not a bug: the chapter's sample passes the flags.

### 4. `LruCache.dispose()` calls the eviction handler

`setEvictHandler(f, ctx)`: `f` is called for every entry that leaves the cache: when it is evicted, with `remove`, `clear`,
`setCapacity` (shrinking) **and `dispose()`** (checked by running; the module header and `docs/ALGO.md` do not say when the handler is
called, `t417` tests `clear`). Replacing the value of an existing key does not call it. Probably intended; the chapter documents it
(and `samples/algo/lru_cache.a` shows it in its last line).

## (b) Where the reference docs are wrong or incomplete

| File | Claim or gap | What really happens |
|---|---|---|
| `docs/ALGO.md` intro | "Everything works on all five targets and on AOS" | The compiler has nine targets (x86-64, ARM64, RISC-V and LoongArch Linux, Windows, four Android). Every sample of this chapter compiles for all nine and gives the same output on three of them under qemu-user. Windows and Android were not run. |
| `docs/ALGO.md` "Conventions" | `BitSet` "grows on first use" | see (a) 1: `set` out of range is ignored; call `resize(n)`. |
| `docs/ALGO.md` ds table | `setRange` / `countRange` of `BitSet` listed without their meaning | Both are **half open**: `setRange(lo, hi)` sets the bits `lo .. hi - 1`, `countRange(lo, hi)` counts them. `Fenwick.sum(l, r)`, `SegTree.query(l, r)`, `OrderedMap.countRange(lo, hi)` and `IntervalSet` include both ends. Only a comment in the source says it. |
| `docs/ALGO.md` ds table | `RingBuffer` and `ByteRing` both "overwrite the oldest (or refuse)" | The defaults are opposite: `RingBuffer(capacity, overwriteOldest = true)`, `ByteRing(capacity, overwriteOldest = false)`. |
| `docs/ALGO.md` ds table | no callback signatures | `OrderedMap.forEach(f, ctx)` and `forEachRange(lo, hi, f, ctx)`: `int f(int key, int value, int ctx)`; `Trie.walkPrefix`, `walkWildcard`, `forEach`: `int f(char* key, int value, int ctx)` (the key text is only valid during the call); `AhoCorasick.each`: `int cb(int id, int end, int ctx)`; `LruCache.setEvictHandler`: `int f(int key, int value, int ctx)`. A non-zero result stops the walk and is returned (not documented for `LruCache`: the result is ignored). |
| `docs/ALGO.md` ds table | `BinaryHeap`: it does not say what `peek` / `pop` return | `peek()` and `pop()` return the **key**, `peekValue()` and `popValue()` the value; `PriorityQueue.dequeue()` returns the value and `peekPriority()` the key. Equal keys come out in no particular order (only in the source comment). |
| `docs/ALGO.md` ds table | `Deque d(capacity)` | The capacity is rounded up to a power of two and is **at least 8**: `Deque(4)` has capacity 8 (the sample's first version said "grows to 8"). |
| `docs/ALGO.md` ds table | `LruCache`, `TextLruCache` counters | On `LruCache` `hits`, `misses`, `evictions` are fields, on `TextLruCache` they are methods (`hits()` ...). |
| `lib/strx.a` line 2001 | comment "DIFF kind of run i: LineDiff.EQUAL (0), DELETE (1) or INSERT (2)" | There are no such constants; the kinds are the plain numbers 0, 1 and 2 (the tests compare with literals). |
| `docs/ALGO.md` "Diff of two line arrays" | example without `eolMissingA / B` | see (a) 3. |
| `docs/ALGO.md` rng | "Distributions" table, no word on bad parameters | Parameters are **not validated**, nothing hangs or crashes: `gamma(-1)` returned 1.072, `chiSquared(-1)` 2.2042542677802404, `normalAt(0, -1)` -1.019 (all just numbers); `poisson(-1)`, `geometric(0)`, `geometric(-1)`, `binomial(-3, 0.5)`, `poisson(0)` return 0, `exponentialRate(0)` is `inf`, `binomial(10, 2.0)` is 10 (p >= 1), `sample(5, -1, a)` and `sample(5, 6, a)` return `false`. NumPy would raise an error. (Checked by running; not in the chapter's samples.) |
| `docs/ALGO.md` "Conventions" | "A default argument is NOT applied to a zeroed object" | True for `ds`, but the generators of `rng` do not follow it: a zeroed `rng.Pcg32` behaves like `Pcg32(42, 54)`, a zeroed `Mt19937` like `Mt19937(5489)`, `Xoshiro256`, `SplitMix64` and `Pcg64` like seed 0 (checked; the t430 test relies on it). A zeroed `AliasTable` / `ReservoirSampler` is not ok (`ok()` false, `sample` returns -1). |
| `docs/ALGO.md` Speed | all figures native x86-64 | Not measured again for the book. The chapter repeats a few (generator speeds) and labels them. The two measurements the chapter states itself (Horspool / Rabin-Karp / `algo.countOccurrences` against `Kmp`, and `sortStrings` against `algo.sortBy`) were taken here, natively. |

Measured here, native x86-64, one run (also in the chapter):

* 100,000 letters `a` searched for 500 letters `a`: `Kmp.count` 1 ms, `Horspool.count` 117 ms, `RabinKarp.count` 525 ms, `strx.countOf` 0 ms.
  The docs measured 15 ms, 4.5 s and 23 s for 2,000,000 and 1000, the same shape.
* `algo.countOccurrences` of 400 `a` in 40,000 `a`: 222 ms; `strx.countOf` less than 1 ms (the quadratic behaviour that the docs
  claim for `algo.kmpFind` / `countOccurrences`). The text of chapter 31 now says so.
* 20,000 random eight letter strings: `sort.sortStrings` (insertion sort) 866 ms, `algo.sortBy((int*) items, n, ds.cmpText)` 9 ms, same order.

## (c) What I could not cover, and what I did not test

* **Windows and Android were only compiled**, never run (no emulator allowed here). The three Linux targets other than x86-64 ran under
  `qemu-user`.
* The tests `t410` to `t437` and their `.out` files were used to learn the API, not re-run (the coordinator said never to run the test
  suites). Their claims of correctness (differential tests, comparisons with NumPy, Python, RFC 8439) were not re-checked, except for the
  numbers that appear in the samples (next section).
* Public members **without a runnable use** in a sample (they are described in prose or only in the API reference): `ds.mix64`, `hashInt`,
  `hashText`, `hashBytes`, `cmpAsc`, `cmpText`, `RingBuffer.isFull`, `ByteRing.byteAt` / `clear`, `BinaryHeap.keyOf` / `valueOf` /
  `setValue` / `peekHandle`, `OrderedMap.removeFirst` / `removeLast` / `lastNode` / `prevNode` / `rankUpTo` / `forEach` / `isNode`,
  `OrderedTextMap.valueOfRank`, the `Ordered...Set` `removeFirst`, `HashMap.shrink` / `isEntry` / `toArrays`, `Trie.hasPrefix` /
  `forEach` / `walkWildcard`, `BitSet.clearAll` / `clearRange`, `BloomFilter.mightContainBytes` / `addBytes`, `CountMinSketch.widthOf` /
  `depthOf` / `estimateBytes` / `merge` / `setConservative`, `strx.jaroWinklerEx`, `diceQgrams` with another `q`, the `utf8` variants of
  `lcs` and `longestCommonSubstring`, `FuzzyMatcher` with `FUZZY_UTF8`, `GLOB_PERIOD` and `GLOB_NOESCAPE`, `rng.mulhi64`, `belowU64`,
  `Xoshiro256.longJump`, `Pcg64.seed128` / `setState`, `Mt19937.seedArray`, `ChaCha20Rng.seedBytes` / `mixIn` / `reseedFromSystem`,
  `ReservoirSampler.clear`, `AliasTable.buildInts`. Every public data structure, every string algorithm family and every generator and
  distribution has at least one runnable sample.
* The **system-seeded** parts (`rng.systemSeed`, `rng.uuid4`, `ChaCha20Rng` without a key, `rng.Rng` without a generator) cannot print
  their values; `samples/algo/secure_random.a` checks the shape only (UUID format, two draws differ).
* Memory failures (`asys.alloc` returning `null`) and the node limit of `AhoCorasick` were not provoked; the docs and the tests describe them.
* No performance claim about AOS (the operating system of the same team) was checked; the chapter does not mention it.
* 32 samples is above the "20 to 28" that the assignment aimed at: every data structure family wanted its own sample, and each is
  short (30 to 59 lines). Pairs that could be merged if the book needs fewer: `fenwick_trees` + `segment_tree`, `quick_open` +
  `names_and_order`, `heap_basics` + `task_scheduler`, `shuffled_deck` + `sampling`.

## What I verified independently (besides reading the `.out` files)

* **Generators**: `SplitMix64`, `Xoshiro256`, the Lemire `below` / `uniformInt`, `shuffle`, `sample` (both branches, Floyd's with its
  hash set), `ReservoirSampler`, `weighted` and the `AliasTable` (Vose, same stack order) were re-implemented in Python; every number in
  `rng_generators`, `dice_and_pi`, `shuffled_deck`, `sampling` and `weighted_pick` matched, including the 100,000 point Monte Carlo
  (78457 inside) and 20,000 draws of `sample(49, 6)`.
* `Pcg64(42, 54)` and all twelve distribution rows of `distributions.a` (also the histogram) match **NumPy 2.5.3** (`Generator` over
  `PCG64` with the state set from `pcg_setseq_128_srandom_r`); `Mt19937.seedPython(12345)` gives Python's `random.random()`
  0.416619872545341; `Pcg32(42, 54)` and `Mt19937(5489)` give the first values of their reference code.
* `ChaCha20Rng` with the key 0..31: the first three words were computed with a Python ChaCha20 block function (fast key erasure
  construction: block counter 0..15, first 32 bytes are the new key); the UUID of `Xoshiro256(1)` too.
* **Strings**: Levenshtein and OSA tables, LCS lengths, the longest common substring, the suffix array of `banana`, the occurrence counts and
  the longest repeat of the poem, the palindrome counts, Jaro-Winkler of MARTHA/DIXON (0.961, 0.813), Soundex codes were checked with Python or
  the standard references. The unified diffs equal `diff -u` of GNU diffutils (minus timestamps).
* **ds**: Kruskal's result (33), the Collatz lengths and the LRU order of `lru_cache.a`, the sieve and the set operations of
  `bitset_sieve.a`, the sums of `fenwick_trees.a` and `segment_tree.a`, the word counts of `word_index.a` were recomputed by hand or in
  Python. The Bloom filter and count-min figures (5056 bits, 67 false alarms, estimates) come from the module itself; their exact values
  depend on its hash functions, which are integer code and therefore identical everywhere (the same on four targets).

## Second pass by an independent reviewer (fresh eyes)

Everything below was run with `build/ac` of this worktree. **No library function that returns a wrong result was found.** Differential checks that agree:
`Kmp`, `Horspool`, `RabinKarp` and `strx.countOf` against a naive search on 20,000 random small cases (overlap on and off), `SegTree` (sum, min,
max, add and assign mixed), `IntervalSet` and `OrderedMap` (`rank`, `floorKey`, `verify`) against plain arrays, the twelve rows of `distributions.a`
(first three draws and the mean of 2000) against NumPy 2.5.3 with the PCG64 state copied from `Pcg64(2024, 7).getState(0..3)`, and
`Mt19937.seedPython(12345)` against Python's `random.random()`. All 32 samples give the recorded output on x86-64 and under `qemu-user` on
linux-arm64, linux-riscv64 and linux-loongarch64, and compile for all nine targets.

Where the reference text was wrong, and the chapter was corrected:

| Where | Claim | What really happens |
|---|---|---|
| `lib/strx.a` (comments of `levenshtein`, `lcsLength`), `docs/ALGO.md` (table of costs) | `levenshtein` needs O(min(na, nb)) memory | the DP rows are O(min), but `symPair` first decodes **both** texts into arrays of ints: 8 bytes per input byte. Two 1 MB texts: `levenshteinMax(a, n, b, n, 5)` peaked at 33 MB resident (`resource.getrusage` of the child), 130 ms |
| `docs/ALGO.md` (search section) | `strx.countOf` / `indexOf` "fall back to KMP" | only `indexOf` is Horspool with a fallback; `countOf` and `findAll` (the one-shot ones) run `Kmp` from the start |
| `docs/ALGO.md` "Conventions" | the classes made from a size or capacity store nothing when zeroed | true for `ds`; a zeroed `strx.Kmp`, `Horspool`, `RabinKarp` is an **empty pattern**, which matches everywhere (`find("abc")` is 0, `count("abc")` is 4) and a zeroed `FuzzyMatcher` scores every text 0 (the ALGO.md sentence "is an empty pattern" is right; the chapter had said "finds nothing") |
| `Trie` header ("O(length of the prefix)") | `countPrefix` costs the length of the prefix | each step scans a sorted sibling list (up to 255 entries), so O(length x fan-out); fine for text, but not a flat O(length) |

Other traps that were not in the notes above and are now in the chapter: `Mt19937` and `ChaCha20Rng` are the only generators that allocate and have
`dispose()`; `ChaCha20Rng.seedUint64` has only 64 bits of entropy; `rng.Pcg64(42)` is not NumPy's `default_rng(42)` (NumPy seeds PCG64 through a
`SeedSequence`, so only a copied state gives the same numbers); `OrderedMap.nextNode` is an O(log n) search, so a walk with `firstNode` / `nextNode`
costs O(n log n); the set operations of `BitSet` keep the size of the receiver.

### A trap found by the reviewer: a `ds` container passed or assigned **by value** shares its buffers

The compiler accepts `void f(ds.Deque d)` and `ds.Deque b = a;` and copies the fields, which are pointers. When the copy grows, `grow()` frees the buffer that the original still points to:

```c
import ds; import asys;
void grow(ds.Deque d) { for (int i = 0; i < 20; i++) d.pushBack(i); }     // by value: a copy of the object
int main() {
    ds.Deque a(4);
    grow(a);                                      // the copy outgrew the buffer of a and freed it
    int* other = (int*) asys.alloc(64);           // the allocator hands out the freed block again
    for (int i = 0; i < 8; i++) other[i] = 1000 + i;
    a.pushBack(7);                                // a still writes into that block
    printf("other[0] = %d\n", other[0]);          // 7, not 1000
    return 0;
}
```

This is the usual rule for classes with owned memory (pass a pointer), not a compiler bug, but nothing in `docs/ALGO.md` says it. The chapter's rules and traps now say so; its samples pass `ds.Deque* d`.
