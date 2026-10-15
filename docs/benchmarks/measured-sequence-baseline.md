# Alicorn #50 baseline and History prototype

Historical first-phase capture. The [real-patch follow-up](history-real-patch-projection.md) validates references and simultaneous folds, removes the blocked/tree storage mismatch, and finds that a compact binary block directory approaches tree latency. Its decision supersedes this report's suggested implementation order; the measurements below are retained as the original evidence.

Captured 2026-10-14 on Windows 10 build 19045 with Odin `dev-2026-09-nightly:a2fb372`. The runtime height-index source matches the reviewed `94b7034`; the working baseline revision was `9b5eaf571f13b7fcc6826a18c5ecf5bafaec0038`. The CPU model could not be queried in this restricted environment.

The Alicorn results compare simpler height-index alternatives before tree work. The History section below adds a local-splice B+ tree performance prototype; it is not a reusable core and neither consumer has been integrated. The Alicorn executable is [the baseline harness](../../experimental/measured_sequence_baseline/main.odin); its raw output from five sequential fresh-process runs is in [the raw capture](raw/measured-sequence-baseline-windows-2026-10-14.txt).

## Real Alicorn viewport profile

The existing headless text-layout benchmark produced 20,000 logical rows and 317 measured heights after its scroll and reflow phases. In the latest run, the full frame averaged 3.158 ms during scroll and 3.290 ms during wrapped-width reflow. The final index was profiled separately over 120 viewport offsets:

| Geometry path | p50 per call | p95 per call |
| --- | ---: | ---: |
| Existing `virtual_list_variable_metrics` | 0.5 µs | 0.5 µs |
| Direct sparse Y lookup candidate | 0.1 µs | 0.2 µs |

The candidate matched the existing first/last rows and leading offset on all 120 offsets. It saves roughly 0.3–0.4 µs from a 3 ms frame, so viewport seeking is not a meaningful frame-time bottleneck. The separate full-frame output is in [the text-layout capture](raw/text-layout-baseline-windows-2026-10-14.txt).

## Sparse lookup and update baselines

The table reports medians across five sequential processes. Lookup values are nanoseconds per query for 50,000 deterministic queries. Update p95 values are the median of each process's p95 across 180 transactions; each transaction changes 32 existing measured rows and performs two viewport seeks. Bracketed figures show the range across those five process-level p95 values.

| Rows / overrides | Pattern | Current f32 lookup | Direct f32 | Direct f64 | Chunked f64 | Update p95: current / direct f32 / direct f64 / chunked |
| ---: | --- | ---: | ---: | ---: | ---: | --- |
| 20k / 317 | Scattered | 171 ns | 17 ns | 14 ns | 20 ns | 1.1 [1.1–1.4] / 0.7 [0.6–0.9] / 1.0 [1.0–1.2] / 1.1 [1.0–1.2] µs |
| 20k / 317 | Clustered | 168 ns | 16 ns | 14 ns | 21 ns | 1.3 [1.2–1.6] / 0.8 [0.6–1.0] / 1.1 [0.9–1.2] / 1.1 [1.0–1.4] µs |
| 100k / 1k | Scattered | 248 ns | 27 ns | 23 ns | 33 ns | 2.1 [1.9–2.3] / 1.4 [1.3–1.6] / 1.9 [1.6–2.0] / 2.9 [2.0–3.0] µs |
| 100k / 1k | Clustered | 241 ns | 24 ns | 22 ns | 29 ns | 2.0 [1.9–2.5] / 1.3 [1.3–1.6] / 1.7 [1.6–2.0] / 2.1 [2.0–3.0] µs |

Direct Y search over the existing f32 entries reduces isolated lookup cost by about 9–10× without changing storage. It matched the existing nested search across the randomized query samples, near-measurement boundaries, and an exact integer-height boundary fixture. The f64 alternatives were checked against an expanded f64 oracle; small differences from the current f32 result occur near rounded boundaries and are a precision distinction, not evidence that the f64 answers are wrong.

The chunked representation groups measurements in 32-entry blocks and caches each block's cumulative height delta. It is slower than direct sparse search for lookups and existing-height updates. Its estimated storage is 8.0 KiB for 317 overrides and 25.6 KiB for 1,000 overrides, compared with 5.1 KiB / 16.0 KiB for the current f32 entry payload and 7.6 KiB / 24.0 KiB for f64 sparse entries. These are index payload estimates, not process allocation totals; allocator headers and dynamic-array slack for the flat arrays are excluded.

## Front insertion trace

A second synthetic trace inserted one estimated row at logical position zero in each of 180 transactions, then performed two viewport seeks. At 100k rows and 1,000 overrides, the median p95 was 2.2 µs for the current f32 index, 1.8 µs for direct f32, 1.2 µs for direct f64, and 0.2 µs for the chunked candidate. The clustered case had similar results. The chunked fixture uses a per-block logical-index bias so a front insertion changes a small block directory instead of rewriting every stored index.

This is a synthetic pressure case, not a captured application editing trace. The chunked fixture does not yet implement removal, arbitrary splice, block split/merge, or a complete lifecycle policy, so its result justifies further baseline work rather than adoption. The other measurements show that a general tree is not warranted for ordinary scrolling. Before considering Alicorn tree work, capture a real source-edit trace and see whether it makes this front-insert cost material to the user.

## Decision

The Alicorn viewport path does not pass the tree gate: its complete geometry calculation is below one microsecond, and direct sparse search already removes most of its cost. Keep the tree experiment out of the Alicorn runtime for this workload. A separate direct-Y runtime optimization can be reviewed on its own merits; this benchmark only keeps it as a candidate.

## History local-collapse experiment

This is a deterministic synthetic projection fixture, not a captured History patch or an existing History feature. Each case starts with 50,000 adapter records and performs 180 identical transactions: replace four contiguous same-hunk context records with one collapsed placeholder, checksum a 100-row viewport, restore the four records, then checksum another 100-row viewport. The four representations produce identical checksums. Five sequential fresh-process runs are in [the comparison capture](raw/history-projection-comparison-final-windows-2026-10-14.txt); Odin and OS versions match the Alicorn section.

| Representation | 50k compressible runs p95 | 50k alternating rows p95 | Payload: compressible / alternating |
| --- | ---: | ---: | ---: |
| Expanded display-row references (current-style direct index) | 1,141.3 µs | 250.9 µs | 3.57 MB / 780 KB |
| Flat records + per-record prefix summaries | 1,162.4 µs | 1,160.0 µs | 5.60 MB / 5.60 MB |
| Fixed 32-record blocks + block-prefix summaries | 29.5 µs | 30.4 µs | 4.11 MB / 4.11 MB |
| B+ tree, 32-item leaves and 16-way branches | 3.3 µs | 4.9 µs | 361 KB / 361 KB |

The expanded representation keeps direct random display-row access. Its read-only 100-row p95 was 0.9 µs in both 50k cases; the tree measured 0.7 µs for compressible runs and 1.4 µs for alternating rows. That is a 0.5 µs absolute difference in the slower case. This is an index microbenchmark, not a full History frame measurement.

The tree was about 8.9× faster than the block-prefix alternative for compressible spans and 6.2× faster for alternating rows. Its node payload was 53.7% below the expanded row-reference payload in the alternating fixture and 89.9% below it in the compressible fixture. The tree stores 32-bit indices into a shared, immutable source-record table; payload totals exclude that source table and allocator overhead. This is only a fair incremental-memory comparison if the eventual History adapter can reference existing parsed patch storage without first creating a similarly large projection-record table. Validate that against the real `Patch_Display_Line` and patch model before relying on the memory result.

The prototype only supports a local splice that stays inside one leaf and has spare capacity. It does not split or merge leaves, handle arbitrary hunk-body folds across leaves, inject allocation failures, or establish cursor invalidation semantics. Its rejected-range and over-capacity checks confirm those requests leave the local tree summary and revision unchanged. The adapter validates initial display-row, hunk, and source lookup results against the flat representation, and the timed traces match exact viewport checksums.

This made the tree promising for further History research, without authorizing integration. The subsequent real-patch milestone passed the reference and multi-fold checks and added an equal-storage hierarchical-block alternative. Its results justify establishing an actual application requirement or remaining performance advantage before investing in arbitrary balanced-tree splices. Full native frames and growing-splice memory remain unmeasured.
