# Data structures, string algorithms and random numbers

The [collections chapter](#chap-collections-and-algorithms) has the everyday containers. This chapter is about three bigger modules for the day when they are not enough: a deque, a priority queue whose entries you can change, an ordered map, a trie and a Bloom filter (`ds`); fast searching, edit distance, a text diff and a suffix array (`strx`); and random number generators with many distributions (`rng`). All three are written in A, come with the compiler, and give **the same results on every target**.

**In this chapter**

* `ds`: data structures: deque, ring buffers, heaps with handles, ordered maps and sets, hash maps, tries, union-find, bit sets, Fenwick and segment trees, interval sets, an LRU cache, a Bloom filter and a count-min sketch;
* `strx`: string algorithms: KMP and friends, Aho-Corasick, edit distances and similarities, longest common subsequence, a line diff, a suffix array, palindromes, fuzzy and glob matching, Soundex, natural order;
* `rng`: six generators, unbiased integers, doubles, a dozen distributions, shuffling, sampling and weighted choice, secure random numbers;
* the traps: what is checked, what is not, and what is slow.

## Rules that hold for all three modules

* **Declare objects with parentheses.** `ds.Deque d(16);` runs the constructor. `ds.Deque d;` does **not** (see [structs and classes](#chap-structs-and-classes)). The classes that have no size or capacity (`Deque`, `OrderedMap`, `HashMap`, `Trie`, `BinaryHeap` ...) still work when they were only zeroed: they are empty and grow on first use. The classes that are made with a size or capacity (`RingBuffer`, `Fenwick`, `LruCache`, `BloomFilter` ...) must be declared with parentheses: zeroed, they have size 0 and store nothing. A class that has no constructor at all, such as `strx.LineDiff`, is declared without parentheses (`strx.LineDiff d;`); the compiler says `this class has no constructor` otherwise.
* **`dispose()` gives the memory back.** `A` has no `delete`, so call `dispose()` on a container when you are done; it frees every block, also the copies of text keys, and leaves an empty object that can be used again. Objects made with `new` are never freed, so prefer objects on the stack.
* **No crashes on bad numbers.** A bad index, an empty container or a failed allocation gives `0`, `-1`, `false` or `null` (documented per method) and leaves the container as it was. Use `size()` or `isEmpty()` when 0 is a valid element.
* **`ds` does not check pointers.** A text key, a byte buffer or an output array must be a real pointer: `Trie.put(null, 1)` crashes. Pass `""` for an empty text. `strx` and `rng` take a `null` text as an empty text.
* **Not thread safe.** Give every thread its own objects.

::: note
Every sample in this chapter was compiled for all nine targets and run under emulation for ARM64, RISC-V and LoongArch: the output is the same bit for bit, also for the generators and for everything that uses `double`. The numbers that come from random generators are therefore printed in full, and you can compare them with your own run.
:::

## Data structures: `ds`

All containers hold ints. Texts and pointers fit in an int, and the maps, sets and caches have variants with text keys. `import ds;` gives you everything in this table.

| Class | What it is | Typical use |
|---|---|---|
| `Deque` | double ended queue | queues and stacks, work lists |
| `RingBuffer`, `ByteRing` | fixed size FIFO that overwrites (or refuses) | the last N readings, serial and network buffers |
| `BinaryHeap`, `PriorityQueue` | priority queue with handles | schedulers, Dijkstra, "k smallest" |
| `OrderedMap`, `OrderedSet`, `OrderedTextMap`, `OrderedTextSet` | balanced tree: keys in order | nearest key, k-th key, ranges, word indexes |
| `HashMap`, `HashSet`, `TextHashMap`, `TextHashSet` | hash tables that remember insertion order | counting, lookups, "seen before?" |
| `Trie` | map from texts with prefix and wildcard search | autocomplete, routing tables |
| `DisjointSet` | union-find | connected groups, minimum spanning tree |
| `BitSet` | packed bits | sieves, flags, sets of small numbers |
| `Fenwick`, `RangeFenwick` | running sums that change | counters per day, rankings |
| `SegTree` | sum, minimum or maximum over ranges, lazy updates | range queries with range updates |
| `IntervalSet` | merged integer intervals | calendars, address ranges |
| `LruCache`, `TextLruCache` | least recently used cache | caching computed results |
| `BloomFilter`, `CountMinSketch` | "probably in the set", approximate counts | huge streams in little memory |

### Sequences: `Deque`

A **deque** (say "deck") is a queue that you can fill and empty at both ends. `ds.Deque` keeps its elements in a ring that grows when it is full, so `pushBack`, `pushFront`, `popBack` and `popFront` take constant time.

{{sample algo/deque_basics}}

What to notice:

* `ds.Deque d(4);` is declared with parentheses. The capacity is rounded up to a power of two and is **at least 8**; it doubles when the ring is full. The queue at the end let 1000 numbers pass through and still has capacity 8, because the ring wraps around.
* `foreach` works on a deque because it has `size()` and `get(i)` (see [more language features](#chap-more-language-features)). `get(0)` is the front.
* `insertAt(i, v)` and `removeAt(i)` move the elements of the shorter side, and `indexOf` looks at every element: all three are O(n). `insertAt` returns `false` for an index outside `0 .. size()`.
* On an empty deque `popFront()` returns 0, `front()` returns 0 and `get(5)` returns 0. Test `isEmpty()` when 0 is a real element.

### Fixed size buffers: `RingBuffer` and `ByteRing`

A **ring buffer** has a fixed capacity and never allocates after it was made. When it is full, a new element either replaces the oldest one (a sliding window) or is refused. `ByteRing` is the same idea for bytes, for network and serial buffers.

{{sample algo/ring_buffers}}

What to notice:

* `RingBuffer(capacity, overwriteOldest = true)`: when the ring is full the oldest element is pushed out and `overwritten` counts it (10 readings into 4 slots: 6). With `false` a full ring refuses the new element: `push` returns `false` and `rejected` counts.
* `get(0)` and `peek()` are the oldest element, `fromNewest(0)` the newest, `pop()` removes the oldest. `foreach` works here too.
* **The two classes have opposite defaults.** `ByteRing(capacity, overwriteOldest = false)` refuses what does not fit: `write` returns how many bytes it took (2 of 5) and `dropped` counts the rest.
* `peek(out, n)` copies bytes without removing them, `read(out, n)` removes them, `skip(n)` throws them away. The bytes you read are not 0 terminated; the sample adds the 0 itself.

### Priority queues: `BinaryHeap`

A **heap** hands out the element with the smallest key first, in O(log n) per push and pop. The key says what comes first, the value is what you want back.

{{sample algo/heap_basics}}

What to notice:

* `push(key, value)` stores a pair (the value is optional). `peek()` is the smallest key, `peekValue()` its value; `pop()` returns the **key** and `popValue()` the **value** of the element it removes.
* Equal keys come out in no particular order (both 3s did). If the order of equals matters, put a counter into the key, as the next sample does.
* A comparator turns the order around: `ds.cmpDesc` is a max-heap, and your own function `int cmp(int a, int b)` (negative: `a` comes out first) can compare anything that fits in a key.
* `drain(keys, values)` pops everything into arrays (room for `size()` ints each; either may be `null`). `merge(&other)` moves all elements of another heap in and leaves it empty.

### A scheduler with handles

`push` returns a **handle**: a number that names the element for as long as it stays in the heap. With it you can change a key or remove the element without searching for it. `ds.PriorityQueue` is the same class with the names `enqueue(priority, value)`, `dequeue()` and `peekPriority()`.

{{sample algo/task_scheduler}}

What to notice:

* `update(handle, newKey)` works in both directions (decrease-key and increase-key) in O(log n). That is what Dijkstra's algorithm needs, and what `collections.PriorityQueue` cannot do.
* `remove(handle)` cancels a task from the middle of the queue. A second `remove` with the same handle returns `false`: the handle is stale. `contains(handle)` asks without changing anything.
* One number orders the queue: `priority * 1000 + arrival`, so equal priorities run first come first served (this assumes fewer than 1000 tasks).
* A handle is valid **until its element leaves the heap**. The number is reused afterwards, so never keep a handle of a popped element.

### Ordered maps and sets: `OrderedMap`

An **ordered map** keeps its keys in sorted order in a balanced tree (an AVL tree), so every operation costs O(log n), including the ones that a hash table cannot do: the nearest key, the k-th key, and "everything between a and b".

{{sample algo/ordered_map}}

What to notice:

* `floorKey(x)` is the largest key `<= x`, `lowerKey(x)` the largest `< x`, `ceilKey(x)` the smallest `>= x`, `higherKey(x)` the smallest `> x`. Each takes a fallback for "none" (`higherKey(500, -1)`). The `...Node` versions return a node number, -1 for none.
* `rank(key)` is how many keys are smaller (the key need not be there), `select(i)` the node of the i-th smallest, `countRange(lo, hi)` how many keys lie in `lo .. hi`, **both ends included**.
* A **node number** stays valid until that key is removed, whatever else is inserted or removed. `keyAt`, `valueAt` and `setValueAt` use it, and `firstNode()` with `nextNode(t)` walk the map in order.
* `forEachRange(lo, hi, callback, ctx)` calls `int callback(int key, int value, int ctx)` for every entry in the range, in order; a non-zero result stops the walk and is returned. The callback must not insert or remove entries. `range(lo, hi, keys, values, max)` and `toArrays` copy into arrays instead.
* `put` returns 1 for a new key and 0 when it replaced a value. `ds.OrderedMap reverse(ds.cmpDesc);` orders the keys with a comparator. `OrderedSet` is the same with keys only, and `foreach` works on it.

### With text keys: `OrderedTextMap`

`OrderedTextMap` and `OrderedTextSet` do the same for text keys. The keys are **copied**, compared like `strcmp` (byte order), and freed by `dispose()`.

{{sample algo/word_index}}

What to notice:

* `index.put(word, index.get(word, 0) + 1)` is the counting idiom. The buffer `word` is reused for every word, which is safe because the map keeps its own copy.
* `first()`, `last()`, `floor(key)`, `ceil(key)`, `lower(key)` and `higher(key)` return the key text, or `null` when there is none. The texts point into the map: they stay valid until that key is removed.
* `rank("fox")` is 6 (six words come before it), `select(4)` is the text at position 4, and `range("b", "e", keys, counts, max)` includes both ends. The order is byte order, so every capital letter would come before every lower case letter.
* `foreach (char* w in once)` walks an `OrderedTextSet` in alphabetical order.

### Hash maps and sets

A **hash map** finds a key in constant time on average. The maps of `ds` store their entries in insertion order and keep only their numbers in the hash table, so walking a map is fast and **the order is always the same**, on every run and every target.

{{sample algo/hash_maps}}

What to notice:

* `add(key, delta = 1)` adds to the value (a missing key counts as 0) and returns the new value: that is a counter in one call.
* `first()` and `next(e)` walk the entries; `keyAt(e)` and `valueAt(e)` read them. Removing the current entry while walking is fine. **Inserting a new key invalidates entry numbers.**
* `put` returns 1 for a new key and 0 when the key existed. `putIfAbsent` returns `true` only when it stored the value. `get(key, fallback)` gives the fallback for a missing key.
* `TextHashMap` and `TextHashSet` copy their keys. `HashSet.add` returns 1 for a new element and 0 for a repeat, which makes "have I seen this?" one call. Pass `ds.randomSeed()` to the constructor when the keys come from an attacker.
* The keys are in insertion order, not sorted. When you need sorted keys, use an `OrderedMap`.
* The seeded 64 bit hash functions of the tables are public: `ds.hashInt`, `hashText`, `hashBytes` and `mix64`. The comparators `ds.cmpAsc`, `cmpDesc` and `cmpText` work with `BinaryHeap`, `OrderedMap` and `algo.sortBy` alike.

### Prefixes and wildcards: `Trie`

A **trie** is a tree with one edge per byte of the key. Searching for a prefix costs time in the length of the prefix, however many keys there are. `ds.Trie` also finds keys with wildcards and the longest stored prefix of a text.

{{sample algo/trie_search}}

What to notice:

* `countPrefix("car")` counts the keys that begin with `car` (the key `car` itself included). `walkPrefix(prefix, callback, ctx)` calls `int callback(char* key, int value, int ctx)` in byte order; the key text is only valid during the call.
* `collect(prefix, out, max)` **copies** the keys: free them with `ds.freeTexts(out, n)`.
* In a wildcard pattern `?` is exactly one byte and `*` is any run of bytes, also none; `\` takes the next byte literally. A pattern may have at most 62 items besides stars: `countWildcard` returns -1 for a longer one.
* `longestPrefixOf(text, &value)` returns the length of the longest stored key that begins `text`, or -1; that is how a router picks `/api/users` over `/api`.

### Union-find: `DisjointSet`

A **disjoint set** (union-find) keeps track of which elements belong together while groups are merged. It uses path compression and union by size, so both `find` and `unite` are nearly constant time.

{{sample algo/disjoint_set}}

What to notice:

* `unite(a, b)` returns `true` when it joined two different groups. The field `groups` counts the groups that are left, `same(a, b)` asks, `sizeOf(x)` gives the size of the group, `find(x)` its representative (-1 for a number that is not an element).
* `labels(out)` numbers the groups `0 .. groups - 1` in the order of their first element, writes a label for every element and returns the number of groups.
* `add()` appends a new element in a group of its own, so the set can grow. That, `sizeOf` and `labels` are what `ds.DisjointSet` has more than `algo.UnionFind` of the [collections chapter](#chap-collections-and-algorithms).
* Kruskal's minimum spanning tree is a heap and a disjoint set: take the cheapest cable first, and lay it only when it joins two groups. 5 cables of the 7 were laid, 33 is the total price.

### Bit sets: `BitSet`

A `BitSet` is a set of the numbers `0 .. size - 1` stored as bits in 64 bit words: 64 numbers per word, and set operations that work on a whole word at a time.

{{sample algo/bitset_sieve}}

What to notice:

* `BitSet(count)` starts with all bits 0. `set(i)`, `unset(i)`, `flip(i)`, `get(i)`, `setAll()`, `count()` (the number of 1 bits). A bit outside `0 .. size - 1` is ignored: `set` does nothing there and `get` returns `false`.
* **`setRange(lo, hi)` and `countRange(lo, hi)` are half open**: they use the bits `lo .. hi - 1`. `Fenwick`, `SegTree` and `IntervalSet` (below) include both ends.
* `nextSet(i)` and `nextClear(i)` find the next 1 or 0 bit at or after `i` (-1 for none), `prevSet(i)` the last 1 bit at or before `i`. A loop over `nextSet` walks all members in order.
* `orWith`, `andWith`, `xorWith` and `andNotWith` change this set; `isSubsetOf`, `intersects` and `equals` only ask. `copyFrom(&other)` copies and resizes. `resize(n)` changes the size and sets new bits to 0.

### Running sums: `Fenwick` and `RangeFenwick`

A **Fenwick tree** (binary indexed tree) answers "what is the sum of elements `a` to `b`?" and takes changes to single elements, both in O(log n). Indexes are `0 .. size - 1`.

{{sample algo/fenwick_trees}}

What to notice:

* `prefix(i)` is the sum of elements `0 .. i` and `sum(l, r)` the sum of `l .. r`: **both ends are included**. `get(i)`, `set(i, v)` and `total()` are shortcuts.
* `build(values, count)` fills the tree in O(n); calling `add` for every element costs O(n log n).
* `lowerBound(target)` is the first index whose running total reaches `target`: the first day with 100 sales was day 5. It works only when no element is negative, and returns `size()` when even the total is smaller (`1000` gave 14).
* `RangeFenwick` turns it around: `add(l, r, v)` adds `v` to every element of a range, and `sum`, `prefix` and `get` ask. Sums wrap around on overflow like every `int`.

### Range queries with updates: `SegTree`

A **segment tree** answers sum, minimum or maximum over a range, and it can **add** a value to a whole range or **assign** one, all in O(log n), because it postpones the work ("lazy propagation").

{{sample algo/segment_tree}}

What to notice:

* `SegTree(count, operation)` with `ds.SEG_SUM`, `ds.SEG_MIN` or `ds.SEG_MAX`. `build(values, count)` fills it, `query(l, r)` asks (both ends included), `get(i)` and `total()` are shortcuts, `set(i, v)` assigns one element.
* `add(l, r, v)` adds to every element of the range, `assign(l, r, v)` replaces them all. After the `+3` the maximum rose from 22 to 25 and the minimum from 8 to 9, without visiting every element.
* A range is clipped to the tree. An **empty range** gives the neutral value: 0 for a sum, the largest `int` for a minimum, the smallest `int` for a maximum.
* For plain sums with point changes a Fenwick tree is smaller and faster. Use a `SegTree` for minimum and maximum, or when you need range assign.

### Integer intervals: `IntervalSet`

An `IntervalSet` is a set of integers stored as sorted, closed intervals `[lo, hi]`. Intervals that overlap **or touch** are merged.

{{sample algo/interval_set}}

What to notice:

* `add(540, 599)` is 60 minutes: both ends are in the set. `add(600, 629)` touches the first block (599 + 1 = 600), so the two became one block, `09:00-10:30`.
* `count()` is the number of blocks, `length()` the number of integers, `lowAt(i)` and `highAt(i)` the ends of block `i`.
* `contains(x)`, `covers(lo, hi)` (every integer of the range is in the set) and `overlaps(lo, hi)` (at least one is) ask; `indexOf(x)` is the block that holds `x`, or -1.
* `nextFree(x, &out)` and `nextMember(x, &out)` store the answer through the pointer and return `false` when there is none. `remove` can cut a block in two (the cancellation).

### A cache: `LruCache`

An **LRU cache** (least recently used) keeps the results of the last N requests. When it is full, the entry that was used longest ago makes room for the new one.

{{sample algo/lru_cache}}

What to notice:

* `get(key, fallback)` returns the fallback for a missing key, counts a hit or a miss, and makes the entry the newest. `peek` does not change the order and `has` only asks. The counters `hits`, `misses` and `evictions` are fields (on a `TextLruCache` they are methods).
* The eviction handler `int onEvict(int key, int value, int ctx)` is called whenever an entry **leaves**: when it is evicted, with `remove`, `clear`, `setCapacity` and `dispose` (the last line of the output). Replacing the value of a key is not a departure.
* `newest()`, `olderThan(t)` and `oldest()` walk the entries; `keyAt(t)` and `valueAt(t)` read them. `setCapacity` shrinks or grows the cache; shrinking evicts the oldest entries.
* Memory grows with the entries that are in the cache, not with its capacity: a cache with capacity 1,000,000 that holds 50,000 entries is fine.

### Approximate answers: `BloomFilter` and `CountMinSketch`

Two structures that trade exactness for memory. A **Bloom filter** says "possibly in the set" or "certainly not". A **count-min sketch** estimates how often a key occurred. Both use a fixed amount of memory however many keys you give them, and both use only integer arithmetic, so their bits are the same on every target.

{{sample algo/sketches}}

What to notice:

* `BloomFilter(expected, oneIn)` sizes the filter: 500 names with about 1 false alarm in 100 need 5056 bits (632 bytes) and 7 hash functions. **It never forgets a key it was given** ("forgotten 0"), but it may claim to know others: 67 false alarms in 10,000 tests, 0.67 percent. You cannot remove a key or list the keys.
* `fillPermille()` and `falsePositivePpm()` tell how full the filter is and what false alarm rate to expect right now. `merge` adds the keys of a filter with the same size and seed.
* `CountMinSketch(width, depth)`: an estimate is **never smaller** than the real count, and it is at most the real count plus about `e / width` times `total()` with a probability of `1 - e^-depth`. The hot keys were off by 0 to 5 in 5000 events, the worst cold key by 9.
* A key that never occurred can still get an estimate above 0 when others collide with it, but the sample's key got 0. `setConservative(true)` keeps estimates lower.
* Both classes have variants for text (`addText`, `mightContainText`, `estimateText`) and bytes (`addBytes`, ...).

### What costs what

| Structure | Main operations | Cost | Good to know |
|---|---|---|---|
| `Deque` | push, pop at both ends | O(1) | `insertAt`, `removeAt`, `indexOf`: O(n) |
| `RingBuffer`, `ByteRing` | push, pop, get | O(1) | fixed capacity, no allocation after the constructor |
| `BinaryHeap` | `push`, `pop`, `update`, `remove` | O(log n) | `peek`: O(1); equal keys in no order |
| `OrderedMap`, `OrderedSet` | everything | O(log n) | `range`: O(log n + count); no allocation per node |
| `HashMap`, `TextHashMap` | `put`, `get`, `remove` | O(1) on average | iteration in insertion order; the table is never more than half full |
| `Trie` | `put`, `get`, `countPrefix` | O(key length) | wildcard search: one step per trie node that can still match |
| `DisjointSet` | `find`, `unite` | nearly O(1) | |
| `BitSet` | `set`, `get` | O(1) | `count` and set operations: O(size / 64) |
| `Fenwick` | `add`, `prefix`, `sum`, `lowerBound` | O(log n) | `build`: O(n) |
| `SegTree` | `add`, `assign`, `query` | O(log n) | lazy propagation |
| `IntervalSet` | `add`, `remove`, queries | O(log n) plus the intervals merged or cut | |
| `LruCache` | `get`, `put` | O(1) | |
| `BloomFilter`, `CountMinSketch` | `add`, `mightContain`, `estimate` | a few hashes | fixed memory |

The module documentation, `docs/ALGO.md` in the source tree, lists measured speeds for every operation. They were taken natively on x86-64 by the authors of the module and not measured again for this book.

## String algorithms: `strx`

`strx` works on **texts as a pointer and a length**: every function takes `(char* s, int n)`, and `n = -1` means "up to the terminating 0". A `null` pointer is an empty text. Texts that are not 0 terminated are never read past `n`. Functions that return a text or an array allocate it; the sections say how to free it (`strx.freeText`). The distance, similarity and palindrome functions compare code points instead of bytes when you pass `utf8 = true`.

### Searching for one pattern: `Kmp`, `Horspool`, `RabinKarp`

Three classes compile a pattern once and search as many texts as you like. All three have the same methods, and the answer is always right; they differ in speed on different texts.

{{sample algo/search_patterns}}

What to notice:

* `find(text, n, from)` gives the index of the first match at or after `from`, or -1. `findAll(text, n, out, max, overlap)` stores up to `max` positions and returns the **total** number of matches. `count(text, n, overlap)` only counts. Overlapping matches are counted unless you pass `overlap = false` (`"aa"` in `"aaaaa"`: 4, or 2).
* An **empty pattern** matches at every position `0 .. n`.
* `strx.indexOf`, `countOf` and `findAll` need no setup. They use Horspool with a table on the stack and switch to KMP when the text turns out to be nasty, so they stay linear.
* `prefixFunction` (the KMP failure table), `zFunction` (the Z array; `z[0]` is the length) and `period` (the smallest period of a text) are the tools the searches are built from.
* `Kmp` is always linear. `Horspool` is usually faster than that but takes O(n * m) when almost every window matches, and `RabinKarp` has to verify every hit, so it does too: see [Limits and traps](#limits-and-traps).

### Many patterns at once: `AhoCorasick`

The Aho-Corasick automaton searches for **all patterns in one pass** over the text. The time is linear in the length of the text plus the number of matches, however many patterns there are.

{{sample algo/aho_corasick}}

What to notice:

* `add(pattern)` returns the id of the pattern, in the order of first appearance. Adding the same pattern again returns its old id, and an empty pattern is refused (-1).
* `findAll(text, n, ids, ends, max)` lists matches in text order and returns the total. `ends[i]` is the position **after** the last byte of the match, so `ends[i] - ac.patternLength(ids[i])` is where it starts. At one end position the longest pattern comes first.
* `each(text, n, callback, ctx)` calls `int callback(int id, int end, int ctx)` for every match; a non-zero result stops. `first` finds only the first match and `count` only counts.
* For a **stream**, `step(state, byte)` moves a cursor (an `int`, 0 at the start) one byte on, and `match(state)` with `nextMatch(t)` and `patternAt(t)` list the patterns that end there, longest first. You never need the whole text in memory.
* `AhoCorasick(true)` ignores ASCII case. The search builds the automaton by itself when patterns were added since the last search. A node limit (default 4,000,000) makes further patterns fail.

### Edit distances

The **edit distance** between two texts is the smallest number of changes that turns one into the other.

{{sample algo/edit_distance}}

What to notice:

* `levenshtein` counts insertions, deletions and replacements of one letter. `osa` and `damerau` also count swapping two neighbours as one change. `ca` to `abc` shows the difference: the optimal string alignment (`osa`) allows no edit inside a swapped pair (3), the true Damerau-Levenshtein distance finds 2.
* `levenshteinMax(a, na, b, nb, k)` stops early and returns `k + 1` when the distance is larger than `k`. It needs O(k * n) time, so comparing two megabyte texts with a few differences is instant.
* `hamming` counts the positions that differ and returns -1 for texts of different lengths; `hammingBits` counts differing bits. `levenshteinSimilarity` is a number from 0.0 to 1.0.
* The last argument `utf8 = true` compares whole characters: `café` is 5 bytes and 4 characters, so the distance to `cafe` is 2 by bytes and 1 by characters.
* Memory: `levenshtein` needs only O(min(na, nb)) memory and `osa` linear memory; `damerau` needs the whole table and returns -1 above 2^23 cells.

### Similarity and fuzzy suggestions

A **similarity** is a number from 0.0 to 1.0: 1.0 for equal texts, near 0.0 for texts with nothing in common. The functions return doubles, so print them with `doubleToFixed` (see [numbers](#chap-numbers)).

{{sample algo/spell_suggest}}

What to notice:

* `jaro` and `jaroWinkler` are made for names: the Winkler bonus rewards a common beginning (`martha` and `marhta` score 0.944 and 0.961, the classic example). `diceBigrams`, `jaccardQgrams` and `cosineQgrams` compare the pairs of neighbouring letters (bigrams, `q = 2`; `diceQgrams`, `jaccardQgrams` and `cosineQgrams` take another `q`) and care less about the order of the letters.
* The suggestion list is a pipeline: `levenshteinMax(..., 2)` rejects far words cheaply, and a `ds.BinaryHeap` with one key per candidate (`distance * 1000 + (1000 - score)`) hands out the best first.
* Which measure is "right" depends on the data: edit distance for typos, Jaro-Winkler for names, q-grams for longer texts where the order of words may change.

### What two texts have in common

{{sample algo/common_parts}}

What to notice:

* The **longest common subsequence** (`lcsLength`, `lcs`) keeps letters in order but allows gaps. `lcs(a, na, b, nb, &len)` returns the text as a **new block: free it with `strx.freeText`**. It needs linear memory (Hirschberg's method).
* The **longest common substring** is one unbroken run. `longestCommonSubstring(a, na, b, nb, &startA, &startB)` returns its length and where it starts in each text; it takes O(na + nb) time.
* `commonPrefix` and `commonSuffix` give lengths in bytes. The LCS is what a diff is made from: the letters you keep, and the rest you delete or insert.

### A text diff: `LineDiff`

`LineDiff` compares two arrays of lines with Myers' algorithm, which finds a **shortest** edit script in O((N + M) D) time and linear memory, where D is the number of changed lines.

{{sample algo/text_diff}}

What to notice:

* `runText(a, b)` splits the two texts into lines for you. `run(linesA, na, linesB, nb, maxCost, noEolA, noEolB)` takes line arrays made by `strx.splitLines`, which also tells whether the last line had no newline. Pass those two flags on (the 6th and 7th argument of `run`): without them a last line that lacks its newline is treated as equal to the same line with a newline, and the `\ No newline at end of file` marker is not written.
* `distance()` is the number of deleted plus inserted lines. `opCount()`, `opKind(i)`, `opA(i)`, `opB(i)` and `opLen(i)` give the script as runs: kind 0 is equal, 1 is delete, 2 is insert.
* `unified(nameA, nameB, context)` writes what `diff -u` writes (no timestamps; the default is 3 lines of context, the sample uses 1). It is `""` when the texts are equal. The result is a new block: free it with `strx.freeText`. A line array from `splitLines` is one block too: `strx.freeText((char*) lines)`.
* `maxCost` (default 8000) bounds the work. A part that costs more is cut off; the script is still correct but no longer the shortest, and `exact()` says so.

### A suffix array: `SuffixArray`

A **suffix array** lists the start positions of all suffixes of a text in sorted order. It answers "does this occur, and where?" for any pattern, in O(pattern length * log n) after a build in linear time.

{{sample algo/suffix_array}}

What to notice:

* `sa.at(i)` is the start of the i-th suffix in sorted order, `rank(p)` the sorted position of the suffix that starts at `p`, and `lcp(i)` the length of the common prefix of suffix `i` and the one above it.
* `count(p)`, `find(p)` and `findAll(p, m, out, max)` search for a pattern; the positions come in **suffix order, not text order**, and `findAll` returns the total. An empty pattern occurs at `n + 1` places.
* `lcpOf(i, j)` is the length of the common prefix of the suffixes at `i` and `j`. `longestRepeat(&pos)` is the longest substring that occurs twice (overlap allowed) and `distinctSubstrings()` the number of different substrings: `banana` has 15.
* The object keeps a copy of the text and needs about 24 bytes per input byte. Use it when you ask **many** questions about **one** text; for one question, `strx.indexOf` is cheaper.

### Palindromes

{{sample algo/palindromes}}

What to notice:

* `isPalindrome` compares the bytes as they are, with no case folding and no skipping of blanks or punctuation: `A man, a plan` is not one.
* `longestPalindrome(s, n, &start)` returns the length and start of the longest palindromic substring (the leftmost on a tie). `countPalindromes` counts all of them, every position separately. Both run in linear time (Manacher's algorithm).
* `manacher(s, n, d1, d2)` gives the raw radii: `d1[i]` odd palindromes centred on `i` (the longest has length `2 * d1[i] - 1`), `d2[i]` even ones centred between `i - 1` and `i` (length `2 * d2[i]`).
* With `utf8 = true` whole characters count: `été` is a palindrome of three characters and five bytes.

### Quick open and glob patterns

**Fuzzy matching** is what a "quick open" box does: you type a few letters and the best names rise to the top. **Glob patterns** are the `*.a` of the shell.

{{sample algo/quick_open}}

What to notice:

* `FuzzyMatcher("sma")` matches when the letters appear in the text **in order**, gaps allowed. `score(text, n, positions)` returns a score (bigger is better, -1 when the pattern is not a subsequence) and the byte offsets of the matched letters. `rank(items, count, outIndex, max, outScore)` sorts a list, best first; ties go to the shorter text, then the earlier one.
* The score rewards matches at the start of a text, after a separator (`/`, `_`, `-`, `.`, a blank) and at camel case humps, rewards runs of consecutive matches, and charges for gaps. The exact numbers belong to the matcher; compare them with each other, not with a fixed limit.
* **Smart case**: the match is case sensitive only when the pattern has a capital letter (`"MM"` does not match `main menu`, `"mm"` does). Flags `FUZZY_IGNORE_CASE`, `FUZZY_CASE` and `FUZZY_UTF8` change this.
* `globMatch(pattern, text, flags)`: `*`, `?`, `[abc]`, `[a-z]`, `[!x]` and `\` escapes. With `GLOB_PATHNAME`, `*` stops at a slash and a segment that is exactly `**` matches any number of path segments. `GLOB_ICASE`, `GLOB_PERIOD` and `GLOB_NOESCAPE` are the other flags. There is **no brace expansion**.

### Names that sound alike, and natural order

{{sample algo/names_and_order}}

What to notice:

* `soundex(name, out)` writes the four character code of American Soundex; `out` needs 5 bytes. `Robert` and `Rupert` share `R163`. It knows ASCII letters only, and returns `false` for a text with no letter.
* `naturalCompare(a, b, ignoreCase)` compares like `strcmp`, but runs of digits count by value however long they are: `img2` comes before `img10`. Equal values with different numbers of leading zeros: fewer zeros first (`img2` before `img02`).
* `naturalSort(items, n, ignoreCase)` is a stable merge sort. `sort.sortStrings` is an insertion sort in byte order, which is why `Img3.png` came first in the left column.

### Which tool do I use, and what does it cost?

| You need | Use | Time and memory (n = text length, m = pattern length) |
|---|---|---|
| one pattern in one text, once | `strx.indexOf`, `strx.countOf` | linear; `indexOf` switches to KMP when the text is nasty |
| one pattern in many texts, or very repetitive text | `strx.Kmp` | O(n + m), always |
| the same, usually faster | `strx.Horspool` | usually sub-linear, O(n * m) at worst |
| many patterns at once | `strx.AhoCorasick` | linear in the text plus the matches; about 48 bytes per trie node |
| many questions about one text | `strx.SuffixArray` | build O(n), about 24 bytes per byte; `count` and `find` O(m log n) |
| typo tolerance | `levenshtein`, `levenshteinMax`, `jaroWinkler` | O(na * nb) time and O(min) memory; with a limit `k`: O(k * n) |
| what two texts share | `lcs`, `longestCommonSubstring` | O(na * nb) with linear memory; O(na + nb) for the substring |
| what changed between two files | `strx.LineDiff` | O((N + M) D) time, linear memory (D = changed lines) |
| palindromes | `longestPalindrome`, `manacher` | O(n) |
| names typed into a box | `strx.FuzzyMatcher` | a small dynamic program per candidate |
| file name patterns | `strx.globMatch` | O(pattern * text) at worst, never exponential |
| names that sound alike | `strx.soundex` | O(n) |

## Random numbers: `rng`

A **pseudo random generator** is a formula that turns a number (the **seed**) into a long sequence that looks random. The same seed gives the same sequence, which is what you want for tests, simulations and games you want to replay. `rng` has six of them. Each is a class with its **own state**, so two generators never disturb each other, and each method (`below`, `normal`, `shuffle` ...) works with every generator.

### Generators and seeds

| Class | Algorithm | Seeding | Good for |
|---|---|---|---|
| `SplitMix64(seed)` | splitmix64, one 64 bit state | the state is the seed | the fastest (204 M numbers per second in the module documentation); seeding others |
| `Xoshiro256(seed)` | xoshiro256\*\*, period 2^256 - 1 | four outputs of `SplitMix64(seed)`, or `setState(a, b, c, d)` | the default choice: fast and good; `jump()` skips 2^128 numbers, `longJump()` 2^192 |
| `Pcg32(seed, stream)` | PCG XSH RR 64/32 | `Pcg32(42, 54)` is the default | native 32 bit output with `nextU32()`; the stream makes independent sequences |
| `Pcg64(seed, stream)` | PCG XSL RR 128/64 | `seed128(...)`, or `setState(...)` like NumPy's state | the same numbers as NumPy's `PCG64` in the same state |
| `Mt19937(seed)` | Mersenne Twister | `init_genrand`, `seedArray`, or `seedPython(seed)` | `Mt19937` with `seedPython` gives **Python's `random.random()`** |
| `ChaCha20Rng(key32)` | ChaCha20 with key erasure | a 32 byte key, `seedUint64`, or the system | **the only one for secrets** (2.6 M numbers per second) |

The speeds are from the module documentation (native x86-64, not measured again). Every sequence is exact: the tests of the module compare them with independent implementations, and the next sample shows the documented first values.

{{sample algo/rng_generators}}

What to notice:

* `rng.Xoshiro256 g(2024);` is a fixed seed: the numbers are the same on every run **and on every target**. `SplitMix64(1234567)` begins with 6457827717110365317, `Pcg32(42, 54)` with `0xa15c02b7`, and `Mt19937(5489)` with 3499211612, the values of the reference implementations.
* Every generator has `nextU64()`; `Pcg32` and `Mt19937` make 32 bit words with `nextU32()`, and their `nextU64()` puts the first word in the upper half. Use `%u` to print a `uint64`.
* `Mt19937` with `seedPython(12345)` returns 0.416619872545341 from `nextDouble()`, the number that Python's `random.seed(12345); random.random()` prints.
* Two generators with the same seed are in step (55 and 55), a different seed or `jump()` gives another stream. `getState(i)` and `setState(...)` copy a position so that a sequence can continue later.
* A generator declared without parentheses is zeroed and still works: it behaves like the one with the default seed (`Pcg32` like `Pcg32(42, 54)`, `Mt19937` like `Mt19937(5489)`, the others like seed 0). A plain `rng.Rng r;` uses the **system** generator instead.

### Integers, doubles and coins

{{sample algo/dice_and_pi}}

What to notice:

* `below(n)` is an integer `0 .. n - 1` **without modulo bias** (Lemire's multiplication method: `x % n` makes small numbers a little likelier unless `n` divides 2^64). `uniformInt(lo, hi)` includes both ends and works over the whole `int` range.
* `nextDouble()` is a double in `[0, 1)` with 53 random bits: every multiple of 2^-53 is possible and 1.0 never. `nextDoubleOpen()` is in `(0, 1]`, which is safe for a logarithm. `uniform(a, b)` is in `[a, b)`.
* `nextBool()` is a fair coin; `bernoulli(p)` is true with probability `p`; `nextInt()` gives 63 random bits; `fillBytes(buf, n)` fills a buffer.
* The Monte Carlo estimate of pi from 100,000 points is 3.1383: close, and exactly the same on every machine, because the doubles are soft float (see [numbers](#chap-numbers)).

### Distributions

Real data is rarely uniform. `rng` has the usual ones, with the algorithms of **NumPy's `Generator`**: with a `Pcg64` in the same state they give NumPy's numbers.

| Method | What it draws |
|---|---|
| `normal()`, `normalAt(mu, sigma)` | bell curve (ziggurat with 256 layers); mean 0 and spread 1, or your own |
| `lognormal(mu, sigma)` | the exponential of a normal number: always positive, skewed |
| `exponential()`, `exponentialRate(rate)` | waiting times between independent events |
| `gamma(shape)`, `gammaAt(shape, scale)` | sums of waiting times; the building block of beta and chi-squared |
| `beta(a, b)` | a number between 0 and 1 with a shape that you choose |
| `chiSquared(k)` | the sum of `k` squared normal numbers |
| `poisson(lambda)` | how many events happen in a time span: 0, 1, 2 ... |
| `binomial(n, p)` | how many of `n` tries succeed |
| `geometric(p)` | the number of the try of the first success: 1, 2, 3 ... |

{{sample algo/distributions}}

What to notice:

* Each row draws 2000 numbers from one `Pcg64`. The first three draws, the mean of all 2000 and the true mean are printed: the sample means are within a few percent of the true means, which is what a sample of this size gives. The numbers are the numbers that NumPy gives for the same state.
* The `...At` and `...Rate` forms are the plain ones shifted and scaled. `poisson`, `binomial` and `geometric` return whole numbers, which the sample converts to `double` to share one loop.
* The bins show the bell curve. The three middle bins cover -1.5 to 1.5, which holds 86.6 percent of a normal distribution; the sample has 17,414 of 20,000 draws there, 87 percent.
* **Speed**: integer generators run at tens of millions of numbers per second, but the distributions use soft float: `normal` and `exponential` about a million per second, `gamma` and `binomial(100, 0.1)` about a hundred thousand, `poisson(100)` twenty thousand (figures from the module documentation).

### Shuffling: a deck of cards

`shuffle(a, n)` puts `a[0 .. n - 1]` in a random order with the Fisher-Yates algorithm: every order is equally likely (if `below` is unbiased, which it is).

{{sample algo/shuffled_deck}}

What to notice:

* A deck is the numbers 0 to 51. `c % 13` is the rank and `c / 13` the suit; the helper `showCard` turns them into text.
* The top cards after the shuffle are the same on every run and every target, because the generator has a fixed seed. Change the seed (31415) and you get another deck; use `rng.systemSeed()` (see [below](#secure-random-numbers-and-uuids)) when it must differ on every run.
* Shuffling 2000 times and counting hands with a pair gives 965, 48.3 percent. The exact probability is 49.3 percent: a sample of 2000 is about 1 percentage point off.
* `shuffleItems(base, n, itemSize)` shuffles anything made of fixed size items, here four 4-byte words.

### Sampling without repeats

{{sample algo/sampling}}

What to notice:

* `sample(n, k, out)` writes `k` **different** numbers from `0 .. n - 1` in random order and returns `false` when `k > n`. `sampleSorted` returns them in increasing order.
* It takes O(k) time and memory however large `n` is: for `n` up to four times `k` it does a partial shuffle of a table of `n` numbers, for larger `n` it uses **Floyd's algorithm** with a small hash set. A sample of 5 from a trillion numbers needs no table of a trillion numbers.
* The check counts how often each of the 49 numbers was drawn in 20,000 draws of 6: about 2448 each, and the range 2299 to 2529 is what chance gives.
* A `ReservoirSampler` keeps `k` items chosen uniformly from a stream whose length you do not know. `offer(&g, value)` for every item, `get(i)` afterwards; every item of the stream has the same chance, `k / items seen`.

### Weighted choice

Sometimes the outcomes are not equally likely: loot drops, word frequencies, load balancing.

{{sample algo/weighted_pick}}

What to notice:

* `weighted(weights, n)` returns an index with probability proportional to **integer** weights. It is exact (no floating point) and returns -1 for a negative weight, a zero sum, or a sum that does not fit in 63 bits.
* `AliasTable` (Walker's alias method) takes weights as **doubles** that need not add up to 1 (`buildInts` takes ints). The setup is O(n), and every draw costs one `below` and one `nextDouble`, however many categories there are: use it when you draw many times from the same weights.
* The table needs the generator as an argument: `table.sample(&g)`. A zero weight is never drawn. A table with a negative, NaN, infinite or all-zero weight is **not ok** (`ok()` is `false`) and its `sample` returns -1.
* `probabilityOf(i)` gives the exact probability that the table has for category `i`.

### Secure random numbers and UUIDs

Everything above is **predictable**: from a few outputs an attacker can compute the rest. For passwords, session tokens and keys use `ChaCha20Rng`, the CSPRNG (cryptographically secure generator) of `rng`.

{{sample algo/secure_random}}

What to notice:

* Without a key, `ChaCha20Rng` is seeded from the operating system and reseeds itself, so it is different on every run. The sample therefore checks only the shape: the draws differ, the UUID has the right format.
* With a 32 byte key the sequence is **fixed**: that is for tests (and the key here is the bytes 0 to 31, which is no secret). The generator erases its key after every refill, so an earlier output cannot be recovered from a later memory dump. `dispose()` wipes the key.
* `rng.systemSeed()` gives 64 random bits from the operating system: a good seed for a fast generator, and the one to log if you want to replay a run. `rng.timeSeed()` is a guessable seed from the clock.
* `rng.uuid4(buf)` makes a random version 4 UUID from the system generator: 36 characters and a final 0, so `buf` needs **37 bytes**. `g.uuid4(buf)` does the same with the generator `g`, so a seeded generator makes UUIDs that repeat.
* A plain `rng.Rng r;` and `rng.system()` use the shared system generator. Nothing else in `rng` is suitable for secrets. There is no fork detection: a forked child continues with the same state, so reseed it.

## Limits and traps

A checklist of what the three modules do **not** do, or do differently from what you might expect.

**Declaring and freeing**

* `Class c;` without parentheses does not run the constructor. The classes made with a size or capacity (`RingBuffer`, `ByteRing`, `Fenwick`, `RangeFenwick`, `SegTree`, `LruCache`, `TextLruCache`, `BloomFilter`, `CountMinSketch`, and in `strx` `Kmp`, `Horspool`, `RabinKarp`, `SuffixArray`, `FuzzyMatcher`) must be declared with their arguments. A zeroed one has size 0: `push`, `put` and `add` return `false` and queries find nothing, but nothing crashes. **A default argument is not applied to a zeroed object**: a zeroed `LruCache` has capacity 0, not 16.
* The module documentation lists `BitSet` among the zeroed classes that "grow on first use", but a zeroed `BitSet` has size 0 and **ignores `set(5)`**. Call `resize(n)` first, or declare `BitSet(n)`. (A zeroed `DisjointSet` does grow: `add()` creates elements.)
* `strx.LineDiff d();` is a compile error because the class has no constructor. Declare it as `strx.LineDiff d;`.
* `dispose()` is the only way to free. `new` objects are never freed.

**Pointers**

* `ds` does not check pointer arguments: `Trie.put(null, 1)`, `TextHashMap.put`, `OrderedTextMap.put`, `BloomFilter.addText`, `CountMinSketch.addText`, `TextLruCache.put`, `ByteRing.write(null, n)`, `Deque.copyTo(null)` and `Trie.collect` with a `null` array crash. A lookup in an empty container may happen to answer `false`; do not rely on it. Pass `""` for an empty text.
* Output arrays are not checked either: `findAll`, `toArrays`, `copyTo` need room for what they write (for example `size()` ints).
* Text and arrays that the library returns (`strx.lcs`, `unified`, `splitLines`, `Trie.collect`) are yours to free: `strx.freeText` and `ds.freeTexts`.

**Handles and numbers**

* A `BinaryHeap` handle is valid until its element leaves; the number is reused afterwards, so a stale handle can name a different element.
* A `HashMap` entry number is invalidated by inserting a new key. An `OrderedMap` node number stays valid until its key is removed.
* Counts and sums wrap around on overflow, like every `int`. `Fenwick.lowerBound` needs non-negative elements.
* **Ranges differ**: `BitSet.setRange` and `countRange` are half open (`lo .. hi - 1`); `Fenwick.sum`, `SegTree.query`, `OrderedMap.countRange` and `IntervalSet` include both ends.
* Equal keys in a heap come out in no particular order. `ds.PriorityQueue` is not `collections.PriorityQueue`: it has handles.

**Speed**

* `Horspool` and `RabinKarp` take O(n * m) when almost every window matches, because they check every candidate. Measured for this chapter (native x86-64): 100,000 times `a` searched for 500 times `a` took 1 ms with `Kmp.count`, 117 ms with `Horspool.count` and 525 ms with `RabinKarp.count`; the module documentation gives 15 ms, 4.5 s and 23 s for 2,000,000 and 1000. Use `Kmp`, `strx.countOf` or `strx.indexOf` when the text may be that repetitive, for example text from outside.
* `algo.kmpFind` and `algo.countOccurrences` rebuild their table on every call and start again after every match, so they are quadratic on such texts (40,000 times `a` against 400: 222 ms, `strx.countOf` took less than a millisecond).
* `strx.damerau` needs the whole table and refuses inputs above 2^23 cells (-1). `LineDiff` is not minimal when `maxCost` is exceeded. `FuzzyMatcher` scores candidates longer than 1024 symbols and patterns longer than 64 with a cheaper greedy score.
* The distributions `gamma`, `beta`, `poisson` and `binomial` use the slow, correctly rounded `log`, `exp` and `pow` of the soft float library, and are far slower than the integer generators.

**What is not there**

* No containers of structs: store pointers or indexes. All containers hold ints.
* `globMatch` has no brace expansion, and in path mode no `/` inside `[...]`. Case folding covers ASCII, Latin-1, Greek and Cyrillic in `FuzzyMatcher`, ASCII only in the other functions.
* `SuffixArray` takes about 24 bytes per input byte (more while it is built), `AhoCorasick` about 48 bytes per trie node.
* **Distribution parameters are not validated.** Nothing crashes or hangs, but `gamma(-1)`, `chiSquared(-1)` and `normalAt(0, -1)` return numbers instead of failing, and `poisson(-1)`, `geometric(0)` and `binomial(-3, 0.5)` return 0 (checked by running). Keep shape, scale and probabilities in their valid ranges.
* `Pcg32` and `Mt19937` seed with 32 or 64 bits only. `binomial` with a large `n` (up to 2^53) is exact but not NumPy's algorithm, so its numbers differ from NumPy's there.
* `ChaCha20Rng` is as secure as ChaCha20 and the operating system's random source; nothing else in `rng` is suitable for secrets.

## Summary

* `ds`, `strx` and `rng` give you the structures and algorithms of a good textbook, in A, with the same results on every target. Declare objects with parentheses and call `dispose()` when you are done.
* `ds.Deque` and `RingBuffer` are queues and windows; `BinaryHeap` is a priority queue whose entries you can update and remove through handles; `OrderedMap` finds nearest keys, ranks and ranges in O(log n); the hash maps remember insertion order.
* `Trie`, `DisjointSet`, `BitSet`, `Fenwick`, `SegTree` and `IntervalSet` are the specialists for prefixes, groups, sets of small numbers, running sums, range queries and merged ranges; `LruCache`, `BloomFilter` and `CountMinSketch` save time or memory.
* `strx` searches (`Kmp`, `Horspool`, `RabinKarp`, `AhoCorasick`, `SuffixArray`), measures (`levenshtein`, `jaroWinkler`, `lcs`), compares files (`LineDiff`) and matches names (`FuzzyMatcher`, `globMatch`, `soundex`, `naturalCompare`). Prefer `Kmp` or `countOf` when the text may be repetitive.
* `rng` generators have their own state and an exact, documented sequence: a seed gives the same numbers everywhere. `below` is unbiased, `nextDouble` has 53 bits, and the distributions follow NumPy.
* `shuffle`, `sample`, `ReservoirSampler`, `weighted` and `AliasTable` cover shuffling, sampling and weighted choice. For secrets use `ChaCha20Rng` and nothing else.
* The traps: `ds` does not check null pointers, bit set ranges are half open, handles and entry numbers can go stale, and some searches are quadratic on repetitive text.

## Where next

* [Collections and algorithms](#chap-collections-and-algorithms) for the simpler containers (`IntList`, `StrMap`, `IntHeap`), sorting, graphs and `algo.UnionFind`.
* [Text and strings](#chap-text-and-strings) for `strings`, `utf8` and regular expressions, and [numbers](#chap-numbers) for `random`, `double` and `fixed`.
* [More language features](#chap-more-language-features) for `foreach` over the containers of this chapter.
* [Cryptography](#chap-cryptography) for the ChaCha20 cipher and the other primitives behind secure random numbers.
* API references: [`ds`](#api-ds), [`strx`](#api-strx), [`rng`](#api-rng).
