# Collections and algorithms

Arrays in A have a fixed size and no operations of their own. When a program needs a list that grows, a table that finds a value by name, a queue or a sorted order, it imports a module. This chapter covers the nine collection classes of `collections`, sorting and searching with `sort` and `algo`, and the two modules for working at the level of bits and bytes: `bits` and `bytebuf`.

**In this chapter**

* `collections`: lists, hash maps, sets, a queue, a heap and a priority queue;
* `sort`: sorting numbers and strings, binary search;
* `algo`: sorting with your own order, searching, dynamic programming, union-find and graphs;
* `bits`: counting, rotating and extracting bits;
* `bytebuf`: reading and writing integers in a chosen byte order, building binary messages, hex dumps and sizes.

## The collection classes

All collections live in the module `collections`. Objects can be created on the stack (`collections.IntList list;`) or on the heap (`new collections.IntList()`); the samples use whichever reads better.

| Class | Holds | Typical use |
|---|---|---|
| `IntList` | a growable array of `int` | results, stacks |
| `StrList` | a growable array of strings | lines, words |
| `StrMap` | string to `int` | counting words, settings |
| `IntMap` | `int` to `int` | caches, lookups by number |
| `IntSet`, `StrSet` | a set of ints or strings | "have I seen this?" |
| `IntQueue` | first in, first out | work lists, breadth-first search |
| `IntHeap` | min-heap of `int` | the smallest element first, heap sort |
| `PriorityQueue` | values with a priority | schedulers, Dijkstra, A* |

Three rules hold for all of them:

* **No errors, only defaults.** Reading outside a list or from an empty queue does not crash: it returns 0 (or `null` for strings) and changes nothing. Use `size()` (or `isEmpty()`, which the lists of ints, the queue, the heap and the priority queue have) when 0 is a valid value.
* **Memory is never freed** (see [memory and pointers](#chap-memory-and-pointers)). When a collection grows it leaves the old storage behind, which is fine for programs that finish and worth knowing for programs that run for days.
* **They store `int` and `char*` only.** To keep a struct, store a pointer to it as an `int`, or keep the structs in an array and store the index.

### Lists: `IntList` and `StrList`

{{sample collections/intlist}}

What to notice:

* `push` and `pop` work at the end, so an `IntList` is also a stack. `insert(i, v)` and `removeAt(i)` shift the elements after `i`, which costs time proportional to the length.
* `get(100)` on a short list returns 0, and `set` with a bad index does nothing. `insert` and `removeAt` with a bad index do nothing either (`removeAt` returns 0).
* `items()` returns the raw array. That is how you hand a list to `sort.sortInts`. The pointer is only valid until the next `push` or `insert`, because the storage may move.

{{sample collections/strlist}}

What to notice:

* A `StrList` keeps the **pointers** you give it. It does not copy the text, so the strings must stay alive and unchanged while they are in the list.
* `get` and `pop` return `null` for a bad index or an empty list.
* A `StrList` can do less than an `IntList`: `push`, `pop`, `get`, `size`, `indexOf`, `clear` and `items`. There is no `set`, `insert` or `removeAt`.
* `items()` is a `char**`, which is exactly what `sort.sortStrings` wants.

### Maps: `StrMap` and `IntMap`

A map finds a value by its key in constant time on average. `StrMap` maps strings to ints, `IntMap` maps ints to ints.

{{sample collections/strmap}}

What to notice:

* `get(key, fallback)` returns the fallback for a missing key. Together with `put`, that gives you a counter in one line: `counts.put(w, counts.get(w, 0) + 1)`.
* A `StrMap` **copies its keys**, so the buffer you passed can be reused.
* The map has no ordered iteration. You walk its *slots*: `for (int s = 0; s < m.capacity(); s++)` and use the slots where `keyAt(s)` is not `null`. The order is that of the hash table, not of insertion. The sample collects the keys and sorts them to get a stable listing.
* `remove` returns true when the key was there.

{{sample collections/intmap}}

What to notice:

* A global `collections.IntMap memo;` works as a cache that every call of `chain` can see: the classic *memoization*.
* For an `IntMap` the slot test is `usedAt(s)`, because every `int`, including 0, can be a key. `keyAt(s)` and `valueAt(s)` read the slot.

### Sets: `IntSet` and `StrSet`

{{sample collections/sets}}

What to notice:

* `add` twice keeps one element. `has` and `remove` work like the map functions, and `remove` returns true when the element was there.
* A `StrSet` copies the text; the sample reuses one buffer for all five words.
* To walk a set use `capacity()` and the slot functions: `usedAt(s)` and `valueAt(s)` for an `IntSet`, `valueAt(s) != null` for a `StrSet`.

### Queue, heap and priority queue

{{sample collections/queue_heap}}

What to notice:

* `IntQueue` is a ring buffer: `push` adds at the end, `pop` removes from the front, `peek` looks at the front. On an empty queue `pop` returns 0.
* `IntHeap` always hands out the **smallest** element first, whatever the push order. Pushing all numbers and popping them all is a heap sort. For a max-heap push the negated values and negate what you pop.
* Equal numbers (the two 3s) both come out.

{{sample collections/priority_queue}}

What to notice:

* `push(priority, value)` stores a value with a priority and `pop()` returns the value with the **smallest** priority. Here the values are job numbers, which index the array of names.
* `peekPriority()` shows the priority of the next element, before you pop it.
* Elements with equal priority come out in no particular order.

See the [API reference of `collections`](#api-collections).

## Sorting: `sort`

`sort` is the small module for numbers and strings in their natural order.

| Function | What it does |
|---|---|
| `sortInts(a, n)` | ascending, in place (a quicksort that finishes small ranges with insertion sort) |
| `reverseInts(a, n)` | reverses the array |
| `isSorted(a, n)` | true when the array is in ascending order (equal neighbours are fine) |
| `binarySearch(a, n, key)` | the index of `key` in a sorted array, or -1 |
| `sortStrings(a, n)` | alphabetical by byte value, in place; the strings are not copied |

{{sample collections/sort_ints}}

What to notice:

* `binarySearch` needs a sorted array. With duplicates it finds *an* element that is equal, not necessarily the first; `algo.lowerBound` gives the first.
* The last lines sort 5000 numbers and verify the result with `isSorted`. A test like that is cheap and catches mistakes early.

{{sample collections/sort_strings}}

What to notice:

* The order is by byte value, so all capital letters come before all lower case letters.
* `sortStrings` is an insertion sort: fine for hundreds of strings, slow for tens of thousands.
* For a case-blind order, sort lower-case copies, as the sample does, or sort an array of indexes with `algo.sortBy` and a comparator that looks the strings up by index.

See the [API reference of `sort`](#api-sort).

## Algorithms: `algo`

`algo` collects the algorithms that you would otherwise write again and again: sorting with your own order, binary search, permutations, string distance, primes, shortest paths. Arrays are `int*` plus a length. A **comparator** is a function `int cmp(int a, int b)` that returns a negative number, 0 or a positive number.

### Arrays

{{sample collections/algo_arrays}}

What to notice:

* `sortBy(a, n, cmp)` is a **stable** merge sort: elements that compare equal keep their order (31 before 91, 12 before 22). The comparator is passed as a function name.
* `lowerBound(a, n, key)` is the first index whose element is `>= key` and `upperBound` the first that is `> key`; the difference is the number of equal elements (`countEqual`). Both need a sorted array and return `n` when there is no such element.
* `unique` removes repeated neighbours of a sorted array and returns the new length.
* `sortDesc(a, n)` is the same stable sort in descending order.
* `rotate(a, n, k)` moves every element `k` places to the left. `kthSmallest(a, n, k)` returns the element that would be at index `k` (counting from 0) after sorting; it is a quickselect, so it does not sort everything. `partition` (the elements below a pivot first, no other order promised) and `nextPermutation` change the array in place (`kthSmallest` rearranges it). `nextPermutation` returns false after the last arrangement and leaves the array sorted again, so a `do ... while` loop visits all permutations once.

### Sequences and strings

{{sample collections/algo_sequences}}

What to notice:

* `maxSubarray` (the largest sum of consecutive elements), `lis` (the length of the longest strictly increasing subsequence), `knapsack` (the 0/1 version: every item is taken once or not at all) and `lcsLength` (the longest common subsequence) are the classic dynamic programming problems.
* `editDistance` is the Levenshtein distance: the fewest insertions, deletions and replacements that turn one text into the other.
* `kmpFind(text, pattern)` searches in linear time and returns the index of the first match or -1. `countOccurrences` counts matches that overlap, and `isSubsequence(small, big)` asks whether the letters of `small` appear in `big` in order, with gaps allowed.
* `sieve(limit, flags)` fills `flags[0..limit]` with 1 for primes and returns how many there are. `flags` is a `char` array of `limit + 1` bytes.

### Union-find

A **union-find** structure keeps track of which elements belong to the same group while groups are being merged.

{{sample collections/algo_union_find}}

What to notice:

* `unite(a, b)` returns true when it joined two different groups and false when they were already connected. The field `groups` counts the groups that are left.
* `same(a, b)` asks whether two elements are in the same group; `find(a)` returns the representative of its group.

### Graphs

{{sample collections/algo_graph}}

What to notice:

* `edge(from, to, weight)` adds a directed edge, `undirected(a, b, w)` adds two. Nodes are numbered from 0.
* `bfs` and `dfs` fill an array (it needs room for all the nodes) with the visiting order and return how many nodes they reached. Neighbours are visited in the order in which the edges were added.
* `dijkstra(start, dist)` fills `dist` with the shortest distances (-1 for unreachable nodes). The weights must not be negative.
* `topological(order)` returns false when the graph has a cycle: a build order does not exist then.
* `components()` counts the connected components and follows every edge in both directions. `hasPath(a, b)` follows the edges in their own direction.

## Bits: `bits`

The `bits` module is for code that cares about single bits: flags, hashes, protocols, bitboards. The functions whose name ends in a bit width (`clz32`, `rotl32`, `bswap16`, `rev8`, ...) work on exactly that many bits and ignore the bits above. The others (`popcount`, `log2`, `isPow2`, `get`, `field`, ...) work on a whole 64 bit `int`.

### Counting

{{sample collections/bits_counting}}

What to notice:

* `popcount` counts the 1 bits, `parity` tells whether that number is odd, `clz` and `ctz` count leading and trailing zeros. `clz(0)` and `ctz(0)` are 64 (the full width), `log2(0)` is -1.
* `log2(x)` is the position of the highest 1 bit, the integer part of the binary logarithm: `log2(1000)` is 9.
* `isPow2`, `nextPow2` (the smallest power of two that is not smaller than `x`) and `mask(n)` (the `n` lowest bits set) are the usual helpers for buffer sizes and masks.
* The `32`-suffixed versions (`clz32`, `ctz32`) work on 32 bits, so `clz32(0)` and `ctz32(0)` are 32.

### Rotating, swapping and reversing

{{sample collections/bits_rotate_swap}}

What to notice:

* A **rotation** moves bits out at one end and back in at the other. `rotl32(x, 32)` is `x` again. The 32 bit versions take and return `uint32`, the 64 bit versions `uint64`.
* `bswap16/32/64` reverse the order of the **bytes**: that converts between little endian and big endian.
* `rev8/16/32/64` reverse the order of the **bits**.

### Single bits and fields

{{sample collections/bits_fields}}

What to notice:

* `set`, `clear`, `flip` and `get` work on bit number `i` (0 is the lowest) of an `int`. `set`, `clear` and `flip` return the new value; they do not change a variable. `get` returns 0 or 1.
* `field(x, lo, n)` extracts `n` bits starting at bit `lo`, `insert(x, lo, n, v)` replaces them. The RGB565 colour in the sample shows why: 5 + 6 + 5 bits in one 16 bit number.
* `signExtend(x, n)` reads the low `n` bits as a signed number: the sensor value `0xFF6` is -10 in 12 bits. `fitsSigned` and `fitsUnsigned` tell whether a value fits into `n` bits.
* `udiv`, `umod` and `ucmp` treat plain `int` values as unsigned 64 bit numbers. (A `uint64` variable does this by itself.)

See the [API reference of `bits`](#api-bits).

## Bytes: `bytebuf`

Files and network protocols are made of bytes in a fixed order. `bytebuf` reads and writes integers in either byte order, builds messages with a growing buffer, and reads them back with range checks. The names tell the width and the order: `U32be` is an unsigned 32 bit number with the most significant byte first (**big endian**), `U16le` has the least significant byte first (**little endian**).

### Reading and writing integers

{{sample collections/bytebuf_endian}}

What to notice:

* The same four bytes read as `0xCAFEBABE` one way and `0xBEBAFECA` the other. Always check which order a format uses.
* `getI8`, `getI16be`, `getI32be` and friends return **signed** values; `getU...` return unsigned ones. 64 bit values are `uint64`.
* These plain functions do not check ranges. They read and write exactly what you point them at.

### A growing buffer and a checked reader

{{sample collections/bytebuf_buf_reader}}

What to notice:

* `Buf` appends: `u8`, `u16be`, `u32le`, `u64be`, `text` (bytes without a terminator), `cstr` (with the terminating zero), `bytes(p, n)`, `fill`, `align`.
* `varint(v)` writes a number in 7 bit groups: 300 takes two bytes (`ac 02`), small numbers one. `svarint` maps negative numbers to small positive ones first (-5 becomes 9), so they stay short.
* Write a placeholder (`u32be(0)`), remember `size()` and fill it in later with `patch32be(at, value)`. That is the standard way to write a length that is not known in advance.
* `Reader` checks every read. A read past the end returns 0 and sets `bad`; you can check once at the end instead of after every field.
* `b->data` is always zero terminated, so a buffer that holds text can be printed.

### Sizes and hex dumps

{{sample collections/bytebuf_sizes}}

What to notice:

* `humanSize` uses powers of 1024 (`KiB`, `MiB`), `humanSizeSI` powers of 1000 (`kB`, `MB`).
* `parseSize` understands what people type: `10MB` is 10,000,000, `10M` and `10MiB` are 10,485,760, a blank and a decimal point are fine (`1.5G`), a plain number is a number of bytes, and -1 means "not a size".
* `hex` and `fromHex` convert bytes to hexadecimal text and back; `fromHex` gives the byte count through a pointer, skips blanks, and returns `null` for a bad digit or an odd number of digits. `hexdump` produces the classic listing with offsets, bytes and printable characters, which is what you want in a debugging session.

See the [API reference of `bytebuf`](#api-bytebuf).

## Summary

* The nine collection classes cover lists, maps, sets, a queue, a heap and a priority queue. They return defaults instead of failing and never free memory.
* Maps and sets are walked slot by slot (`capacity`, `keyAt`, `usedAt`) in hash order. Sort the keys when you need a stable listing.
* `sort` sorts ints and strings in place; `algo.sortBy` takes a comparator and is stable.
* `algo` has binary search helpers, permutations, dynamic programming, string distance, a prime sieve, union-find and a graph class with BFS, DFS, Dijkstra and topological order.
* `bits` counts, rotates, swaps and extracts bits; a bit width at the end of a function's name (`rotl32`, `bswap16`) is the exact width it works on, the other functions use the whole 64 bit `int`.
* `bytebuf` reads and writes integers in big or little endian, builds messages with `Buf` and parses them with the range-checked `Reader`.

## Where next

* [Numbers](#chap-numbers): the number types beyond `int`.
* [Data formats](#chap-data-formats): JSON, CSV, tar archives and zlib, which work with the same kind of byte data.
* [Text and strings](#chap-text-and-strings): splitting and searching the text that goes into these collections.
* API references: [`collections`](#api-collections), [`sort`](#api-sort), [`algo`](#api-algo), [`bits`](#api-bits), [`bytebuf`](#api-bytebuf).
