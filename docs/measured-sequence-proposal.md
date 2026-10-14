# Measured sequence experiment — Alicorn #50

Status: Alicorn baseline and a synthetic History local-splice B+ tree prototype measured on 2026-10-14. No reusable measured-sequence core or consumer integration has been implemented. Tree integration into Alicorn or History is not approved.

## Recommendation

Proceed with an independent, headless Odin prototype and two workload adapters. Decide whether to integrate each adapter from measured results. Treat a result favoring the existing arrays as a successful experiment too.

The proposed primitive is an ordered sequence of application records with cached subtree summaries. Applications determine record boundaries, summaries, source identities, measurement validity, and invalidation. The package owns storage, balancing, traversal, and summary recomputation.

Start by profiling the existing height index and comparing simpler alternatives. Only if those results leave a measured need should the experiment proceed to a mutable B+ tree with explicit allocator ownership. Persistent snapshots, reference counting, text editing, stable anchors, and GUI policies would add requirements that these first two workloads do not establish.

## What the existing implementations actually do

The audit used Alicorn master `94b7034286146839144948e2083275dd29ebb0c9` and History master `e0eb3d4f8f59760d7a1c0d5071f60f080adc1b01`.

| Consumer | Current representation | Strength | Cost to investigate |
| --- | --- | --- | --- |
| Alicorn variable-height lists | Sorted sparse height overrides with lazily rebuilt prefix deltas | Storage proportional to deviations from a common estimate; cheap batched updates to existing entries | Prefix rebuild is O(M); inserting an override and shifting measurements after a source edit can move O(M) entries; current Y lookup performs nested binary searches |
| History patch display | Flat `Patch_Display_Line` array borrowing strings from parsed patch storage | O(1) display-row lookup and contiguous traversal; text is not duplicated | Building the display index is O(N); hunk-to-display lookup scans earlier hunks; changing a flattened projection would require updating or rebuilding its suffix |

Here N means logical rows and M means measured overrides. For the proposed tree, R means stored records, which can be much smaller than N. Complexity claims must use the appropriate quantity.

Alicorn's current `item_top` is O(log M) after pending prefix work. `item_at` and viewport range calculation search logical rows while calling that lookup, making the query phase approximately O(log N * log(M+1)). The sparse prefix rebuild and array edits are likely more consequential than that search alone.

History currently has hunk navigation and fixed-height diff virtualization. The inspected patch-display implementation does not implement collapsed-region projection. Collapse/expand benchmarks therefore describe an experimental extension, not an existing feature that is already slow. Commit-DAG indexing is a separate structure and is outside this first comparison.

Relevant sources:

- [Alicorn height index and variable metrics](https://github.com/samanshaiza004/alicorn/blob/94b7034286146839144948e2083275dd29ebb0c9/runtime/virtual_list.odin)
- [Alicorn existing height-index tests](https://github.com/samanshaiza004/alicorn/blob/94b7034286146839144948e2083275dd29ebb0c9/tests/main.odin)
- [Alicorn wrapped-text benchmark](https://github.com/samanshaiza004/alicorn/blob/94b7034286146839144948e2083275dd29ebb0c9/benchmarks/text_layout/main.odin)
- [History owned display index and borrowed text](https://github.com/samanshaiza004/alicorn-history/blob/e0eb3d4f8f59760d7a1c0d5071f60f080adc1b01/model.odin)
- [History display-row access and hunk lookup](https://github.com/samanshaiza004/alicorn-history/blob/e0eb3d4f8f59760d7a1c0d5071f60f080adc1b01/history_view.odin)

## Baseline gate before a tree

The first implementation work was a baseline harness, not a reusable B+ tree. The Alicorn run compares the current sparse index with direct Y search and a chunked sparse array, and profiles a real scroll/reflow transaction. Direct Y search is much cheaper in isolation, but index geometry is below one microsecond in a roughly 3 ms frame, so Alicorn's viewport workload does not justify a tree.

Use the same numeric precision for the improved sparse and chunked baselines as the eventual tree. Also retain the current f32 implementation as a compatibility reference, so any accuracy improvement is not incorrectly credited to the data structure. The first useful outcome may be that direct sparse search removes the nested lookup cost and there is no remaining reason for Alicorn to use a tree.

The chunked candidate stores sorted measurements in bounded-capacity blocks and caches each block's measured-height delta. It is slower than direct sparse search for ordinary measured-height updates and viewport seeking. A synthetic front-insertion trace favors its per-block index bias, but the candidate lacks removal and general splice support; a real source-edit trace is required before extending Alicorn's index.

Before building a tree, require evidence that the best simple candidate still spends meaningful time or memory in the index on representative traces. Freeze those traces and record index-only and full-transaction timings. Do not use a synthetic worst case alone to pass this gate. The current Alicorn scroll/reflow profile does not pass this gate; revisit only if a captured source-edit trace shows that the simpler alternatives are material to users. The baseline details and History comparison are in [the benchmark report](benchmarks/measured-sequence-baseline.md).

## Core representation and contract

Incubate under `experimental/measured_sequence/`, with separate tests, benchmark drivers, and application adapters. The package must import only Odin's base/core packages. Its independent tests and an external collection-import fixture must run without Alicorn, SDL, AccessKit, fonts, or a native window.

Use polymorphic `Item` and `Summary` types. The policy supplies an explicit summary identity, `summarize(item)`, and ordered `combine(left, right)`. Summary identity is the value for the empty sequence; it is separate from an optional application record identity, which the core does not require. Summaries require an associative combination with an identity; they need not be commutative or support subtraction. Callback policies must remain stable for a sequence's lifetime, must not allocate during queries, and must not read mutable global geometry. A changing measurement parameter can instead be applied to a stable summary during a query.

The first language spike should establish a small typed policy interface, including whether constant procedure parameters give useful inlining on the pinned Odin compiler. Measure any function-pointer overhead before freezing the public API. Avoid type erasure and a new trait or macro system. [Odin documents generic records, constant parameters, and allocator-based memory ownership](https://odin-lang.org/docs/overview/).

Use bounded inline leaf arrays and internal arrays of child references, record counts, and summaries. Start with fanout 16 and leaf capacity 32; compare one alternative configuration before selecting defaults. Keep leaf and branch allocation sizes separate so a large internal summary does not inflate every leaf.

Initially store aggregate leaf summaries and summarize individual records while scanning a bounded leaf. This avoids duplicating an entire Summary beside every Item. If measurement callbacks are expensive, benchmark per-record summary caching as a targeted alternative. Fixed capacities bound local shifting and recomputation; they do not promise a fixed total cost for arbitrary-length splices.

Store the allocator in the sequence. Reuse released nodes with a simple freelist; count unused capacity in memory reports. Queries and traversal must not allocate. Ordinary value replacement should recompute its leaf and ancestor path without allocation. Growing edits may allocate a bounded number of nodes per affected path plus storage for inserted records. Avoid an arena that retains every removed node indefinitely.

Use bottom-up bulk construction and subtree-aware splice operations. Do not implement a long insertion by calling single-item insertion repeatedly. The prototype's records are plain copied values; they have no implicit ownership or destructor behavior. Target these costs, with B as fixed node capacity:

| Operation | Target cost |
| --- | --- |
| Bulk build | O(R) time and storage |
| Whole summary / physical record count | O(1) |
| Record lookup, prefix seek, prefix or range summary | O(B log R) |
| Replace one record / change its measurement | O(B log R) |
| Splice | Boundary-path work plus inserted records and retired nodes |
| Forward cursor traversal | O(R) total; amortized bounded work per record |

A removed subtree still has to release its nodes. Do not describe a large deletion as constant-time or hide reclamation in a later UI frame.

### Small public surface

Conceptual operations, rather than final Odin signatures:

```text
init / destroy
build_from_slice
record_count / summary / get
replace / splice
prefix_summary / range_summary
seek_prefix
cursor_at / next / previous
```

`splice(first, end, inserted)` uses physical-record boundaries and a half-open range. Adapters split compressed records when a logical-row boundary falls inside one. Run splitting and coalescing stay in the adapters; the generic tree does not need a run trait.

Define `P(k)` as the summary of records `[0, k)`. `seek_prefix(predicate)` finds the smallest boundary k in `[0, R]` for which the predicate is true, or returns an explicit no-match/end result. The result exposes the accumulated summary and positions a cursor. An identity match at k=0 is valid. The predicate must change from false to true monotonically along prefixes; an arbitrary predicate cannot use logarithmic subtree skipping.

Adapters express exact ties with strict or non-strict comparisons. For a positive-height list, seeking the first prefix whose Y extent is greater than y identifies the row containing y. An exact row bottom belongs to the next row. The tree does not clamp out-of-range coordinates; the UI adapter preserves Alicorn's existing clamping behavior. Zero-width dimensions in diff records and multiple equal prefixes require explicit adapter boundary policies.

`range_summary` combines covered subtrees in sequence order. It must work for a summary that cannot be subtracted from another summary. Cursor paths retain sufficient prefix state for reverse traversal without assuming an inverse combination.

Items and summaries are copied values; referenced payloads remain application-owned. No mutable item pointer escapes the package: replacement must pass through the summary-maintaining API. Borrowed strings or source slices must outlive the tree and its cursors. The owning sequence must not be shallow-copied; consumers pass its pointer and call `destroy` exactly once.

Every successful mutation invalidates cursors with a sequence revision. Check that revision before dereferencing a cursor's saved path and return a stale-cursor result. The revision and internal node references are transient, not application anchors. The first version is single-owner and not concurrently mutable.

Invalid ranges and allocation failure must leave contents, summaries, revision, and existing cursors unchanged. Reserve required mutation storage before modifying live paths. Test failure at each allocation point in insert and multi-level splice, compare against a reference array after every injected failure, and verify the old tree remains queryable. Only a committed mutation advances the revision and invalidates cursors. Generic summary policies must provide valid arithmetic; adapters reject invalid heights and checked count overflows. These rules belong in the contract rather than being inferred from happy-path tests.

## Workload A: variable-height list

Store compressed estimated and measured geometry without requiring one record for every alternating estimated gap and measured row. Compare at least two encodings. A run encoding has separate estimated and measured runs and exposes its fragmentation cost. A gap-plus-override encoding stores the estimated-row count before a measured row and an optional measured height, followed by a trailing estimated gap; scattered overrides then need roughly one record per override plus a final gap. One estimated gap can represent a million unmeasured rows. An update matching the adapter's baseline policy removes the override and coalesces neighbors. Avoid one tree item per logical row in the sparse case, and report the selected record count as well as logical rows and overrides.

Use a stable summary containing:

```text
logical_rows: i64
estimated_rows: i64
measured_height: f64
```

For a query using estimate e, the Y extent is `measured_height + estimated_rows * e`. This allows the estimate dimension to change without rewriting every estimated run. Measurements dependent on width, font, or scale still need application-owned invalidation; changing e does not validate old measured heights.

Row-count seek finds the containing run. Y seek skips subtrees using the evaluated extent and resolves the position within a uniform run arithmetically. Source insertions and removals splice relative run lengths, avoiding rewriting every later absolute measured-row index. Storage remains O(R), with R bounded by the number of distinct runs rather than document length.

Use f64 accumulation internally and convert to existing UI geometry at the adapter boundary. Floating-point addition is not exactly associative: balancing can change rounding. Make that an explicit experiment: first test the summary algebra with integer heights and exact expected results, then test the production-oriented f64 implementation against a higher-precision/reference calculation and record accumulated error across different tree shapes. Compare the improved sparse and chunked baselines at the same f64 precision. This separates a precision change from an indexing change; the current f32 implementation remains a compatibility reference. Reject NaN, infinity, nonpositive heights, and overflowing extents. Do not claim bitwise equivalence to the existing f32 index.

Compare against four baselines:

1. The exact existing sparse override array, including its batching and lazy rebuild.
2. The same sparse array with direct Y binary search over measured-row bottoms and arithmetic within intervening estimated gaps. This should remove the nested logical-row search without introducing a tree.
3. A chunked sparse array that groups measurements in fixed-capacity blocks and caches block height deltas. This retains bounded local shifts while avoiding one global flat entry array; report block-directory storage and slack.
4. A dense Fenwick height index for update-heavy dense measurements. It is a legitimate competitor when logical positions remain mostly fixed; sequence edits require additional work.

Fixed-height virtualization retains its direct arithmetic path. The tree should have no cost there.

## Workload B: History diff projection

Keep parsed patch strings and hunk lines authoritative. Tree items borrow spans of those arrays rather than copying text or storing a full display record for every projected row. Use records for headers, contiguous context/addition/deletion spans, collapsed spans, and explicit omitted source gaps where source-coordinate mapping needs them.

Summaries carry independent old-source, new-source, display-row, and hunk-header measures. Additions consume no old-source rows; deletions consume no new-source rows; headers consume display rows without consuming source rows. Source positions in separate hunks are not contiguous: preserve the parsed hunk origins and represent intervening gaps instead of equating accumulated patch-line counts with absolute file line numbers.

A source lookup inside an omitted or collapsed span returns an explicit gap/collapsed result with its source range. The application chooses whether to expand, highlight a placeholder, or navigate to a neighboring visible row. Do not silently select an unrelated visible row at a zero-measure boundary.

A viewport query seeks once by display-row measure and advances a cursor through runs, indexing directly into each backing span. Hunk navigation seeks by header count and obtains the display prefix in the same traversal. Collapse/expand replaces a local span's projection and updates ancestor summaries; the raw patch remains owned by History. Restoring scroll anchors and deciding selected hunk identity remain History responsibilities.

Initial collapse traces replace a hunk body or a context span while keeping hunk headers explicit. Cross-hunk folds would introduce extra navigation semantics and are outside the first adapter. Source-mapping tests must include unified-diff zero-count hunk conventions, rather than assuming every hunk starts at a represented line on both sides.

The first synthetic comparison is complete for localized four-record context folds. It compares expanded display-row references, flat records with per-record prefixes, fixed blocks with block prefixes, and a B+ prototype. All four produce identical checksums; the tree is much faster than the other measured projection forms and has a smaller node payload than the expanded row references. The result only covers splices wholly inside one leaf with spare capacity. The tree stores 32-bit references into a shared immutable source-record slice, so its memory result depends on the real adapter being able to reference parsed patch storage directly. See the [benchmark report](benchmarks/measured-sequence-baseline.md) and [raw five-process capture](benchmarks/raw/history-projection-comparison-final-windows-2026-10-14.txt). This is evidence to complete the History experiment, not approval to integrate the prototype.

Implement collapse/expand semantics once, then benchmark equivalent traces on a flat run/block-prefix projection and the tree. Keep the exact current flat display array as the no-collapse baseline. Current O(1) random display-row access is a real advantage: report any regression there. A tree win requires better complete viewport transactions, index memory, or actual projection-changing interactions under identical semantics. Replacing one O(H) hunk scan alone would not justify a tree; a small hunk-prefix table is another baseline improvement. Prefer source references such as `(hunk_index, first_line, count)` over pointers into dynamic arrays that may reallocate; if pointers are used, make and enforce the immutable-storage lifetime rule.

## Measurements and correctness

Record N, M, and R separately. Use 10k, 100k, and 1M logical rows where practical. For heights, include zero overrides, 0.1%, 1%, 10%, and dense overrides; use both clustered and scattered changes. For diffs, include long context spans, many small hunks, alternating additions/deletions that resist compression, binary patches, metadata-only patches, and source gaps. Use sanitized real patch fixtures plus explicitly labeled generated extensions.

Measure bulk construction; random and localized insertion/removal; prefix/range queries; batches of 1/32/256 height updates followed by a viewport query; one seek followed by 30/100 visible-row reads; and collapse/expand or splice transactions near the beginning, middle, and end. Include stable read-mostly sessions and update/query alternation so batching benefits are visible.

Freeze seeds, operation traces, compiler, optimization mode, and baseline revisions. Exclude Git subprocesses, parsing, text generation, shaping, and fixture construction from index microbenchmarks. Report them separately in application-level tests. Both representations share equivalent backing payloads; report incremental index bytes, total live bytes, peak bytes during construction and splices, reserved capacity, unused block/node slots, and allocation counts. Release/destruction cost is a measured phase too.

Use checksums so queries cannot be optimized away. Separate operation timing from oracle verification. Report throughput and latency distributions for complete interaction transactions across at least five fresh process runs, with raw output. Do not infer application responsiveness from a microbenchmark speedup when shaping dominates the frame.

The existing 20k-row Alicorn text-layout benchmark supplies an application-level scroll/reflow trace and per-frame measurements. Its published results predate this proposal and are context, not SumTree evidence. History's current parser/display tests supply correctness fixtures; collapsed projection operations require new headless fixtures before any product feature is integrated.

Use an integer-height fixture first to establish exact associativity, prefix/range summaries, and boundary seeking. Then compare f64 aggregation with a higher-precision oracle under different mutation/tree shapes. Tests should compare random edit streams against a flat-vector oracle after every successful mutation. Cover empty/root-leaf trees; leaf/branch splits and merges; repeated equal summaries; zero-measure items; exact boundaries; end insertion; full removal; growth/shrink cycles; stale cursors; injected allocation failures; checked count overflow; invalid height values; and noncommutative summaries. Range tests must include a noninvertible summary so prefix subtraction cannot accidentally pass as a generic implementation.

For the adapters, test compressed runs against fully expanded small fixtures; edits that split a run twice; updates returning to an estimate; fractional Y; source gaps; consecutive additions or deletions; collapsed ranges; and bidirectional source/display mappings with explicit missing-position outcomes. Repeated splices must not cause unbounded fragmentation: coalescing belongs in the tests and memory traces.

Run headless correctness checks on Windows, macOS, and Linux. Keep performance runs manual, one bounded process at a time, with the 1M case opt-in. No native or parallel compilation is necessary for the initial package experiment.

## Adoption gates

Predeclare the target traces before tuning the tree. The following are proposed thresholds, not observed results:

- Alicorn: first pass the baseline gate: after the direct-Y and chunked alternatives, index work must remain a material part of a representative scroll/reflow transaction. If it is insignificant, stop Alicorn tree work. If it remains material, require at least a 2x p95 improvement on a profiled expensive update-plus-viewport interaction at 100k/1M rows against the best applicable baseline. Normal sparse viewport work must add less than 0.1 ms, and full normal-frame p95 must not regress more than 5%.
- History: compare identical collapse/expand behavior against both the expanded `Patch_Display_Line` baseline and the best simple block/run alternative. The synthetic local-fold prototype already exceeds the 2x p95 target, but its reference-storage assumption and local-only splice make that result provisional. Before integration, validate total index memory on actual parsed patches, keep alternating uncompressible cases within 20% of the expanded baseline, measure a full normal viewport/frame, and implement atomic cross-leaf splices with allocation-failure coverage. Arbitrary hunk-body folds must be represented in the agreed trace.
- Sparse memory: a million estimated rows must occupy bounded gap/run records plus index storage. With at most 1,000 overrides, additional index storage versus the best sparse baseline should remain below 256 KiB. Report compressed record count, block/node slack, peak construction/splice memory, and dense overhead rather than obscuring them behind this sparse test.
- Allocation: queries allocate zero bytes; ordinary replacement of an existing record allocates zero bytes; removed nodes are reclaimed or reused. No allocator activity grows merely from repeated reads.
- Maintainability: both adapters remain small and explain their source/run boundary rules. New GUI policies must not enter the generic API. If an adapter becomes harder to audit than the specialized alternative, reconsider the abstraction even if it is faster.

Passing one consumer's gate permits that consumer's integration. It does not establish that the other consumer should switch. Extraction into a separate repository waits for two real integrations, an independently usable API, reproducible evidence, and an external Odin fixture.

## Implementation sequence

1. Freeze baseline traces and profile existing implementations before tree work. **Completed for Alicorn viewport geometry and a synthetic History local-fold trace.** Do not add a tree to Alicorn's runtime viewport path. The synthetic History trace shows a promising tree speedup, but it does not prove the memory assumption or arbitrary splice behavior.
2. Validate the History item reference against real parsed patch storage, and extend the prototype to cross-leaf collapse/expand. Include split/merge, transactional reservation, allocation-failure injection, random differential tests, and peak memory. If the actual item storage or safety machinery erases the advantage, stop and retain the simpler representation.
3. Implement the generic headless core only after that gate: bulk build, ordered summaries, record lookup, prefix/range queries, and cursors first; then replacement, balanced insertion/removal, subtree-aware splice, and allocator-failure guarantees.
4. Build independent, application-facing adapters and differential tests. Run manual release-mode benchmarks and publish raw results, including losing cases and full viewport measurements.
5. Integrate a winning adapter only after the per-consumer gates pass, in a separate change behind a temporary experiment switch. Re-run end-to-end behavior, geometry, lifecycle, and allocation checks using the same traces.
6. Consider standalone extraction only after both consumer decisions and real use establish the public contract. Keep the existing structures when they win.

Scratchpad source/fold/wrap projections are a later validation opportunity. Scope's arbitrary overlapping-span queries are not automatically solved by prefix seeking; they may need ordered starts, subtree maximum ends, and filtered traversal. Add that pressure only if the first experiment succeeds.

## Research basis

[Issue #50](https://github.com/samanshaiza004/alicorn/issues/50) frames this as incubation and extraction rather than an immediate runtime replacement.

[Zed's explanation](https://zed.dev/blog/zed-decoded-rope-sumtree) and [current SumTree source](https://github.com/zed-industries/zed/blob/main/crates/sum_tree/src/sum_tree.rs) demonstrate the central idea: an ordered B+ tree whose summaries support multiple dimensions. Its implementation also includes reference-counted persistence and a larger surrounding API. The proposed Odin experiment borrows the measurement model, while its initial ownership contract follows the needs of these two consumers.

[Zed's cursor implementation](https://github.com/zed-industries/zed/blob/main/crates/sum_tree/src/cursor.rs) is useful for examining prefix accumulation, boundary bias, and traversal. Derive and test the Odin contract independently instead of mechanically porting Rust traits, lifetime rules, or its node capacities.

The [Odin language overview](https://odin-lang.org/docs/overview/) provides the language basis for generic records, compile-time parameters, explicit allocation, and tracking allocators. All proposed performance and integration benefits remain hypotheses until the experiment runs.
