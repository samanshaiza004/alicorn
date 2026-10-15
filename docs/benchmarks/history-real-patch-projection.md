# Alicorn #50: real History projection research

The next milestone is complete: a headless adapter uses History's actual parser and immutable hunk storage, supports independently identified simultaneous folds, and accelerates source-coordinate seeking with cached summaries. All implementations remain experimental. The results favor testing a compact block directory further before investing in a general B+ tree.

The experiment now lives on `codex/measured-sequence`, based on master `94b7034286146839144948e2083275dd29ebb0c9`. The original experiment commit was replayed as `9c298fc`; no static-SDL branch commits were carried along. The Alicorn variable-height decision is complete: retain its sparse index. Direct-Y optimization remains an optional independent change.

## Evidence and method

The [headless package](../../experimental/history_patch_projection/README.md) snapshots unchanged patch/parser routines from History `ce3276cf2fb425013df013bcb49e211ca234473a`. Its provenance checker passed against those Git objects and three real patches: the adaptive toolbar, scroll changes, and initial patch parser. Four additional fixtures cover mixed old/new origins, gaps, blank/meta lines, zero-count hunks, binary and empty files, and complete-file deletion.

The adapter stores identical **16-byte span references** in every index: record kind, parsed hunk or fold-catalog slot, first line, and line count. There is no shared full `Projection_Record` table. Parsed text is borrowed. The application freezes a separate fold catalog with stable IDs and original spans. Creating a second fold cannot redirect the first placeholder. The earlier synthetic harness's shared sentinel was also replaced with independent application-owned fold references and a coexistence regression check.

Source lookup descends old/new subtree measures while accumulating the display measure. Explicit gaps connect hunk origins; zero-count starts use unified diff's preceding-line convention. Additions and deletions consume only the applicable source axis, while headers and metadata consume only display rows. Tests compare exact text, kinds, source gutters, hunk/line identities, and borrowed text addresses against History's expanded display values. Both source axes are checked exhaustively on the small fixtures. All available fold plans coexist, expand in non-LIFO order, and preserve each line's logical selection/scroll anchor. Different patch epochs are rejected.

The [raw capture](raw/history-real-patch-projection-windows-2026-10-14.txt) contains five sequential fresh processes on Windows 10 build 19045, Odin `dev-2026-09-nightly:a2fb372`, compiled with `-o:speed -thread-count:1`. All backend checksums match, queries/local folds allocate nothing, and index destruction releases all tracked index allocations. Compilation and execution are headless; no GUI/GPU fixture was launched.

Each transaction folds and unfolds one planned region while another independent fold remains active, reconstructs two actual viewports of up to 100 rows, and seeks once along each source axis. Timing excludes checksum calculation, parsing, data generation, and fixture validation. Read-only timing measures viewport reconstruction alone. Numbers below are the median of the five process-level p95 values; sub-microsecond differences on small fixtures are near timer resolution. These are complete **row-descriptor** reconstructions, not shaped or rendered History frames.

## Equal-representation comparisons

| Fixture | Rows / compact spans | Block prefixes: transaction p95 | Binary block directory | Fanout-16 tree directory |
| --- | ---: | ---: | ---: | ---: |
| Actual toolbar patch | 110 / 15 | 1.1 µs | 1.1 µs | 1.1 µs |
| Actual scroll patch | 128 / 68 | 2.1 µs | 2.1 µs | 2.1 µs |
| Actual parser-addition patch | 237 / 3 | 1.0 µs | 1.0 µs | 1.0 µs |
| Hand-authored edge cases | 22 / 19 | 0.8 µs | 0.7 µs | 0.7 µs |
| Amplified scroll bodies, 256 repeats | 32,768 / 17,408 | 4.9 µs | 2.8 µs | 2.9 µs |

The amplified fixture renumbers and repeats actual hunk bodies, then passes them through the same parser. It has 544 leaves and 128 fold plans spread throughout the projection. It is a scale test, not a captured large History workload. Both hierarchical variants reach approximately 1.7× the flat-prefix directory's transaction speed. Their 0.1 µs difference does not meet the proposed 2× gate against the best simple alternative.

Read-only p95 is identical across the three candidates at 0.8 µs for the actual scroll patch and 1.1 µs for the amplified case. The old synthetic run stored full records in its blocked baseline and compact references in the tree. Its latency result remains useful for that trace, but its memory figures do not isolate the tree topology's benefit. This new run removes that representation difference. It also uses explicit optimized compilation; do not compare its absolute timings directly with the earlier capture.

## Memory and construction

Index measurements use Odin's tracking allocator and include allocated capacity, directory storage, and transient directory-build arrays. They report **requested heap bytes**, excluding allocator bookkeeping/headers, process memory, stack buffers, and shared patch/fold data. Mutation peak is reset after construction so it does not inherit the temporary build peak. This is more complete than node payload alone, but is not an OS memory measurement. Build timings include tracking-allocator instrumentation.

| Amplified case | Index live | Index peak build | Build time, median | Peak during local folds |
| --- | ---: | ---: | ---: | ---: |
| Block prefix directory | 317,728 B | 317,728 B | 172.4 µs | 317,728 B |
| Binary block directory | 365,824 B | 365,824 B | 179.5 µs | 365,824 B |
| Fanout-16 tree directory | 311,328 B | 315,952 B | 179.6 µs | 311,328 B |

The fanout-16 directory uses about 15% less settled index memory than the binary directory. Its advantage over block prefixes is about 2%. Fixed leaves dominate this storage, and the binary directory reserves a power-of-two leaf tier. These results do not establish the memory cost of a fully mutable balanced tree.

In the actual 128-row scroll patch, History's expanded display index requests 7,224 B. The compact indexes request 1,784 B (prefix), 1,912 B (binary), or 1,856 B (tree), plus the same 1,696 B fold catalog. The shared parsed patch payload is approximately 22,812 B, counting source-string lengths and allocated hunk/line-array capacities. This reduction comes mainly from referencing runs rather than duplicating full display rows, and it benefits all three candidates. The existing History feature has no folds, so this is an index/storage comparison rather than an adoption claim about equivalent application features.

The amplified driver's common parser/adapter preparation peaks at 8,046,721 requested bytes, including the parser's temporary expanded display array, span seed, and fold plans. After releasing that expanded array it retains 6,203,465 B, including a 524,288 B construction seed that can be released after building a selected index. Serialized fixture input and generation buffers are outside that common tracking scope. The raw capture reports these separately from the index allocator. Growing/cross-leaf splice peak remains unmeasured because neither candidate implements that operation.

## Decision and remaining gates

The real reference model and multi-fold semantics are demonstrated. The equal-storage block hierarchy removes most of the apparent tree advantage for these traces, so there is still no justification for integrating a B+ tree or extracting a generic package.

The next valuable evidence is an actual History folding interaction trace and a full native viewport profile. Small real patches favor simple representations; the amplified case only establishes bounded directory behavior. If dynamic cross-leaf folds are required, first compare the simplest compact-block implementation that can perform that same operation. Balanced tree split/merge and failure-atomic allocation work is justified only by a remaining measured benefit or a requirement the simpler representation cannot meet.

Current mutations stay within one leaf and existing capacity. Rejected ranges/references, overflow of leaf capacity, repeated folds, aliased insertion input, exact cached summaries, and round trips are tested. Arbitrary partial-run folding, cross-leaf mutation, balance/reclamation, allocation-failure injection during growth, stale cursors, native selection/scroll interaction, and full frame latency remain acceptance gates. Logical anchor checks here do not substitute for live History dogfooding.
