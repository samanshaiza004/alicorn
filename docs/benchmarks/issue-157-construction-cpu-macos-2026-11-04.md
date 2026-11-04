# Issue #157: construction CPU audit on macOS

Date: 2026-11-04

- Current Alicorn source: `fe8967f08fed8b29e7cd27d5989f52b7a85f405c`
- Structured candidate: current source plus `issue-157-structured-invalidation-trace.patch` (SHA-256 `866b4200a6612fd8bc3cdaefc05aff101f17d3f6608a3936b926c52b5a0f7522`)
- Historical baseline: `96461223cdbf43080acb957276c045ad704f4606`
- Issue: [#157 — Attribute and reduce initial retained-tree construction overhead](https://github.com/samanshaiza004/alicorn/issues/157)

## Verdict

The initial-construction slowdown is reproducible on this Mac and is primarily CPU work inside `end_frame`. A behavior-preserving structured-trace candidate now defers formatting the five layout invalidation explanations until trace inspection. It preserves the exact historical strings and event order, and reduces optimized `end_frame` CPU by 15.6–24.6% across three synthetic workloads in an 11-process rerun. The full regression is not yet attributed to one behavior-preserving change, nor fully bisected to individual features.

A prior trace-literal experiment reduced allocator traffic but had overlapping timing ranges. The generic-reason experiment established a cost bound while losing diagnostics. The structured candidate retains those details, adds 32 bytes per `Trace_Event`, and keeps `Trace_Event.reason` ring-owned with the existing snapshot lifetime. The native Scratchpad smoke proves that a current Alicorn build can publish a frame and shut down, but it is one instrumented run from a temporary source snapshot, not a representative startup/high-water study.

**Recommendation: keep #157 open.** The cost is now better characterized, but the issue's representative Scratchpad measurement and deliberate acceptance of the remaining cost are still outstanding.

## Method

- Host: Apple M1 MacBook Air (`MacBookAir10,1`), arm64, macOS 27.2 build 26B123.
- Compiler: Odin `dev-2026-11-nightly:9a69916`, identical for both source revisions and profiles.
- The benchmark tool made disposable `git archive` snapshots and built the same low-level Odin probe against each. Each observation was a fresh process; the original audit used five alternating samples per workload and profile. The structured-trace comparison used seven samples, then an 11-sample repeat, with labels alternating order.
- Both ordinary and `-o:speed` profiles were measured separately. The reported CPU time is Darwin process CPU time; the probe's `total` is description plus `end_frame`, excluding runtime initialization and destruction.
- Workloads were 10,000 plain containers, 10,000 short text nodes, 10,000 requested wrapped-text nodes, and a 100-panel form (601 retained nodes). Retained-node counts and geometry checks matched across revisions.
- The synthetic probe does not load a font. `prepare_text_run_node` returns early when the font role is unavailable, so the short/wrapped cases do **not** measure real glyph shaping or native font fallback. In the probe, `shape_requests` stayed at zero. The native Scratchpad smoke is reported separately.

The harness and fixture are [`tools/bench_construction.py`](../../tools/bench_construction.py) and [`benchmarks/diagnostics/construction_cpu_probe.odin`](../../benchmarks/diagnostics/construction_cpu_probe.odin). Sanitized per-process samples are in [`raw/issue-157-construction-macos-m1-2026-11-04.json`](raw/issue-157-construction-macos-m1-2026-11-04.json). The earlier source-history audit is [`issue-157-construction-history.md`](../research/issue-157-construction-history.md).

Reproduction, from the repository root:

```sh
ODIN=/path/to/odin-dev-2026-11/odin
python3 tools/bench_construction.py \
  --odin "$ODIN" \
  --ref baseline=96461223cdbf43080acb957276c045ad704f4606 \
  --ref current=fe8967f08fed8b29e7cd27d5989f52b7a85f405c \
  --runs 5 --output out/issue157/repro-default
python3 tools/bench_construction.py \
  --odin "$ODIN" \
  --ref baseline=96461223cdbf43080acb957276c045ad704f4606 \
  --ref current=fe8967f08fed8b29e7cd27d5989f52b7a85f405c \
  --runs 5 --speed --output out/issue157/repro-speed
```

## Matched CPU results

Values are median milliseconds, with the five-process min–max range in parentheses. The ratio is current divided by historical baseline.

### Default profile

| Workload | Retained nodes | Baseline total CPU | Current total CPU | Ratio |
| --- | ---: | ---: | ---: | ---: |
| Plain containers | 10,001 | 68.081 (67.297–69.736) | 160.662 (158.061–184.445) | 2.36× |
| Short text | 10,001 | 75.640 (74.827–137.441) | 193.128 (191.004–231.021) | 2.55× |
| Requested wrapped text | 10,001 | 94.059 (93.096–96.154) | 203.186 (200.388–208.897) | 2.16× |
| Panel form | 601 | 4.004 (3.844–4.708) | 15.253 (13.589–15.992) | 3.81× |

### `-o:speed` profile

| Workload | Retained nodes | Baseline total CPU | Current total CPU | Ratio |
| --- | ---: | ---: | ---: | ---: |
| Plain containers | 10,001 | 23.749 (23.342–25.972) | 49.773 (48.190–53.795) | 2.10× |
| Short text | 10,001 | 28.159 (28.116–29.806) | 65.538 (62.625–68.453) | 2.33× |
| Requested wrapped text | 10,001 | 36.537 (36.054–37.980) | 68.601 (67.091–81.248) | 1.88× |
| Panel form | 601 | 1.507 (1.477–1.553) | 4.206 (4.141–4.352) | 2.79× |

The short-text default range includes a large historical outlier; its median and the optimized-profile result still show a clear difference. Across all workloads, runtime initialization is negligible. Most of the added CPU appears in `end_frame`; description emission grows by roughly 2–6 ms in the 10k cases, while end-frame medians grow by roughly 22–112 ms.

| Profile / workload | Description CPU: baseline → current | `end_frame` CPU: baseline → current |
| --- | ---: | ---: |
| Default, containers | 23.207 → 27.221 ms | 44.850 → 133.785 ms |
| Default, short text | 21.598 → 27.615 ms | 54.034 → 165.867 ms |
| Default, wrapped text | 21.848 → 27.901 ms | 71.856 → 175.367 ms |
| Default, panel form | 0.925 → 1.371 ms | 3.087 → 13.829 ms |
| `-o:speed`, containers | 7.654 → 9.669 ms | 16.272 → 40.252 ms |
| `-o:speed`, short text | 7.118 → 10.391 ms | 21.026 → 54.581 ms |
| `-o:speed`, wrapped text | 7.307 → 10.229 ms | 29.230 → 57.945 ms |
| `-o:speed`, panel form | 0.370 → 0.566 ms | 1.109 → 3.662 ms |

## Attribution: what the evidence says

### Direct timing and CPU-clock evidence

- The largest aggregate increase is inside `end_frame`, which calls `reconcile`; the latter performs retained dirty measurement, layout, adaptive semantic synchronization, semantic commit, motion application, and paint. See [`end_frame` and reconcile ordering](https://github.com/samanshaiza004/alicorn/blob/fe8967f/runtime/reconcile.odin#L1274-L1308) and [the remainder of the reconcile stages](https://github.com/samanshaiza004/alicorn/blob/fe8967f/runtime/reconcile.odin#L1046-L1062).
- A separate coarse-instrumented default run for 10k short-text nodes recorded median inclusive CPU time of 163.088 ms in `reconcile`, 48.742 ms in `layout_tree`, 26.380 ms in paint, and 12.837 ms in display rebuilding on current source; the historical run recorded 53.172, 6.897, 14.741, and 3.098 ms respectively. These timers are nested and instrumented: do not add them together or treat them as exclusive costs. The run's total CPU medians were 191.346 ms current and 74.670 ms baseline.
- Five-second optimized-process samples repeatedly put allocator internals, `reconcile`, `layout_children`, `fmt::sbprintf`, `update_paint`, measurement, and geometry/display finalization on active stacks. These are sampled stack counts, not exclusive CPU percentages. They indicate distributed work rather than identifying a single hot function.

### Historical feature pairs

These are five-sample `-o:speed` CPU-clock comparisons using the same compiler and probe; they identify candidate intervals, not every cause in the full historical range.

| Direct parent pair | Workload | Baseline → later median CPU | Change | Interpretation |
| --- | --- | ---: | ---: | --- |
| `927e74a` → `ac0a420` | Short text, 10k | 33.359 → 46.204 ms | +12.845 ms | The retained measurement/geometry introduction contributes measurable cost; most of this pair's delta is in `end_frame`. |
| `927e74a` → `ac0a420` | Containers, 10k | 27.283 → 32.655 ms | +5.372 ms | Same feature boundary affects a workload with no text leaves. |
| `28250e7` → `ec2e081` | Short text, 10k | 43.227 → 44.419 ms wall | +1.192 ms | Ranges overlap (42.797–44.296 vs 44.172–46.892 ms); no clear construction jump is established for completed elastic flow. This older pair is wall-time-only. |
| `7e85689` → `3d10863` | Short text, 10k | 52.400 → 63.179 ms | +10.779 ms | The interval adds more cost, but includes multiple layout/asset/diagnostic changes and cannot isolate formatted tracing as the cause. |
| `7e85689` → `3d10863` | Containers, 10k | 38.012 → 49.087 ms | +11.075 ms | Same qualification; the measured increase is not attributable to a single feature. |

The `3d10863` historical compile needed an unused Odin image-decoder API compatibility substitution in its disposable archive. That does not affect this construction fixture, but it is another reason to treat the interval result as attribution evidence rather than a clean production build comparison.

The history map and its remaining gaps are described in [`issue-157-construction-history.md`](../research/issue-157-construction-history.md). A full initial-construction bisection is not complete.

## Candidate experiment: trace allocation reduction

The current trace recorder copies owned reason strings into its bounded ring; see [`record_trace_with_cause`](https://github.com/samanshaiza004/alicorn/blob/fe8967f/runtime/runtime_state.odin#L9-L19). A disposable patch changed selected constant trace reasons to borrowed literals and changed one formatted axis-set reason to a fixed enum string.

In three separate allocation-capture processes, this reduced end-frame allocation traffic by 20,002 calls and 530,069 requested bytes for each 10k plain/short workload, and 1,202 calls / 31,869 bytes for the panel workload. Requested-live high-water was effectively unchanged. In ordinary five-process `-o:speed` timing runs, ranges overlapped: for short text, base was 93.531–161.776 ms and the literal-only candidate was 97.453–179.260 ms; for containers, base was 110.216–129.590 ms and literal-only was 99.119–117.275 ms. The inconsistent direction and broad overlap do not establish a CPU win. This remains an allocation reduction, not a proven performance fix; no part of the patch was applied to production.

### Cost-bound invalidation trace experiment

A second, seven-process `-o:speed` A/B targeted all five dynamic-reason calls in `mark_layout_ancestors`. The disposable patch changed those calls to `record_trace_literal` with generic reasons. It kept the trace call sites, event kinds, node IDs, causes, event order, and event count; it deliberately did **not** preserve the axis and boundary details in `Trace_Event.reason`. The paired source revision was `fe8967f` in both arms. The exact diagnostic-only patch is [`issue-157-generic-invalidation-trace-cost-bound.patch`](raw/issue-157-generic-invalidation-trace-cost-bound.patch), and the patch SHA-256 plus per-process samples are recorded in the raw data file. Reproduce with `python3 tools/bench_construction.py --odin "$ODIN" --ref base=fe8967f08fed8b29e7cd27d5989f52b7a85f405c --ref generic_trace=fe8967f08fed8b29e7cd27d5989f52b7a85f405c --patch generic_trace=docs/benchmarks/raw/issue-157-generic-invalidation-trace-cost-bound.patch --runs 7 --speed --workloads containers:10000,short:10000,panel:100 --output out/issue157/invalidation-trace-literals`.

| Workload | Total CPU, detailed → generic | `end_frame` CPU, detailed → generic | Median change in `end_frame` |
| --- | ---: | ---: | ---: |
| 10k containers | 48.853 → 41.652 ms | 39.941 → 32.671 ms | −18.2% |
| 10k short text | 63.001 → 54.514 ms | 53.270 → 44.118 ms | −17.2% |
| 100 panels | 4.232 → 3.242 ms | 3.656 → 2.691 ms | −26.4% |

The seven-process `end_frame` ranges did not overlap for these cases. This is strong evidence that the combined cost of per-node reason formatting and owned-string recording is material. Because the patch removes detail exposed by Alicorn's trace and inspector consumers, these numbers are a cost bound, not an acceptable user-facing tradeoff. A second experiment below separates persistent string ownership from formatting.

### Behavior-preserving structured invalidation traces

The candidate replaces the five eager formatted reasons in `mark_layout_ancestors` with compact payloads containing the reason kind and historical axis/node values. `trace_snapshot` and the visual inspector materialize the exact previous message on first inspection and cache it in the bounded trace entry. Repeated snapshots reuse the same string. Events overwritten before inspection are never formatted. Trace sequence, causes, nodes, event ordering, and layout propagation are unchanged.

The regression tests check all five messages byte-for-byte, partial boundary containment, FIT_CONTENT rejection, repeated invalidation, cause/node ordering, ring wrap, and that snapshot materialization adds no events or layout-root work. The existing runtime suite passes 320 tests.

The benchmark used the same `fe8967f` source for every arm, Odin `dev-2026-11-nightly:9a69916`, `-o:speed`, and 10,000 containers, 10,000 short text nodes, or 100 panels. CPU is Darwin process CPU time. The latest 11-process sample ranges are shown in parentheses.

| Workload | Original detailed trace | Format, skip persistent copy | Structured, lazy formatting | `end_frame` CPU reduction, original → structured |
| --- | ---: | ---: | ---: | ---: |
| 10k containers | 42.652 ms (39.696–47.044) | 38.686 ms (37.450–41.753) | 33.466 ms (31.497–38.662) | −21.5% |
| 10k short text | 51.032 ms (50.714–54.734) | 49.357 ms (48.572–53.718) | 43.058 ms (42.640–44.284) | −15.6% |
| 100 panels | 3.615 ms (3.545–4.202) | 3.354 ms (3.256–3.792) | 2.726 ms (2.646–2.853) | −24.6% |

The format-without-copy arm still creates the formatted text but stores it as a transient borrowed string. It is a cost-isolation experiment only; its string lifetime is not safe for production snapshots. In both timing passes it remained close to the original, while structured formatting was consistently faster. This points to eager formatting as the larger CPU cost; skipping the persistent copy primarily reduces allocation traffic. The ranges for baseline versus structured did not overlap in the 11-run repeat.

In a separate three-process allocation capture, original versus structured end-frame persistent allocation traffic was:

| Workload | End-frame persistent allocation calls | End-frame requested bytes | Additional live/high-water bytes from larger event record |
| --- | ---: | ---: | ---: |
| 10k containers | 100,111 → 70,107 | 37,087,206 → 34,562,933 | +32 |
| 10k short text | 130,133 → 100,129 | 56,351,718 → 53,827,445 | +32 |
| 100 panels | 9,423 → 6,119 | 4,315,027 → 4,026,955 | +32 |

`Trace_Event` grows from 72 to 104 bytes. The default trace capacity is one entry, so the measured runtime high-water increase is 32 bytes; a configured capacity of 512 adds 16 KiB for structured payload slots. Trace strings are still allocated only when inspected. The allocation-tracking runs are separate from the CPU timing runs and are not latency evidence.

The exact structured production diff and the cost-isolation patch are [`issue-157-structured-invalidation-trace.patch.gz`](raw/issue-157-structured-invalidation-trace.patch.gz) and [`issue-157-formatted-borrowed-invalidation-trace.patch.gz`](raw/issue-157-formatted-borrowed-invalidation-trace.patch.gz). Their uncompressed SHA-256 hashes, compiler, per-process samples, and allocation records are in [`issue-157-structured-invalidation-trace-macos-m1-2026-11-04.json`](raw/issue-157-structured-invalidation-trace-macos-m1-2026-11-04.json). Reproduce the optimized comparison with:

```sh
mkdir -p out/issue157
gzip -dc docs/benchmarks/raw/issue-157-formatted-borrowed-invalidation-trace.patch.gz > out/issue157/formatted-borrowed-invalidation-trace.patch
gzip -dc docs/benchmarks/raw/issue-157-structured-invalidation-trace.patch.gz > out/issue157/structured-invalidation-trace.patch
python3 tools/bench_construction.py \
  --odin "$ODIN" \
  --ref baseline=fe8967f08fed8b29e7cd27d5989f52b7a85f405c \
  --ref formatted_no_copy=fe8967f08fed8b29e7cd27d5989f52b7a85f405c \
  --patch formatted_no_copy=out/issue157/formatted-borrowed-invalidation-trace.patch \
  --ref structured=fe8967f08fed8b29e7cd27d5989f52b7a85f405c \
  --patch structured=out/issue157/structured-invalidation-trace.patch \
  --runs 11 --speed --workloads containers:10000,short:10000,panel:100 \
  --output out/issue157/structured-trace-speed
```

The candidate establishes a repeatable improvement for the tested synthetic construction workloads without losing trace detail. It does not establish the total construction regression's cause or the effect on representative Scratchpad startup.

The source also confirms that ordinary measurement work now drains a deduplicated queue, with a deliberate full retained-order scan only when font generation changes ([`layout_measure_retained_dirty_nodes`](https://github.com/samanshaiza004/alicorn/blob/fe8967f/runtime/layout_measure.odin#L725-L769)). Display-slot updates have a local finalization path and full finalization remains for structural/scale changes ([`layout_finalize_display_slot`](https://github.com/samanshaiza004/alicorn/blob/fe8967f/runtime/layout_measure.odin#L841-L864)). These locality protections should not be bypassed to improve initial construction.

## Native Scratchpad smoke and limits

A temporary Scratchpad source snapshot at `4d4cfd52904b1fd8a20d8433aad2612421f8d68b` was built against Alicorn `fe8967f` with the November Odin compiler. Its checked-in macOS font-discovery code used the older Odin CoreFoundation type `CF.String`; the disposable snapshot needed a one-line compatibility adaptation to `CF.StringRef`. The user checkout was not changed. The smoke used a disposable workspace and a diagnostics capture at first presentation.

The native macOS run selected Cocoa/Metal, produced a rendered publication, observed a wake, and shut down in order. The record included `application_build_max_ns=24,058,000`, `frame_p95_ns=192,257,000`, and `SDL application PASS wall_ns=3,007,301,000`. The process wrapper reported about 7.37 seconds wall time including capture/serialization/shutdown, 0.332 seconds user CPU, 1.325 seconds system CPU, and 97,533,952 bytes maximum RSS (about 93 MiB).

These are **one instrumented smoke**, not normal cold-start or first-visible-pixel timing. The capture path adds work; the `SDL application PASS wall_ns` value is the host loop duration, not launch-to-first-frame. The run did not exercise open/close/settings interactions or measure their high-water, and no matched native Scratchpad baseline was available because the historical Alicorn API/toolchain cannot build this current Scratchpad snapshot unchanged.

A synthetic `/usr/bin/time -l` RSS attempt was blocked by the sandbox's `sysctl kern.clockrate` restriction. No synthetic peak-RSS result is claimed. The single native max-RSS sample is process-level evidence, but not a high-water distribution.

## Closure assessment and next evidence

| #157 requirement | Result |
| --- | --- |
| Reproducible same-machine baseline/current CPU A/B | Complete for synthetic workloads: 7-run plus 11-run optimized captures, and a separate allocation capture, on the same November compiler. |
| Broad CPU attribution | Strongly narrowed: the behavior-preserving structured-trace candidate cuts `end_frame` CPU 15.6–24.6% in the 11-run comparison. Other reconciliation/layout costs remain. |
| Historical feature attribution | Partial: direct pairs show measurable intervals, but the full construction-only bisection is incomplete and some intervals contain multiple features. |
| Measured improvement | Behavior-preserving structured traces reduce synthetic `end_frame` CPU while retaining exact messages; representative application impact is not measured. |
| Peak memory | Partial: one instrumented native Scratchpad maximum-RSS sample; synthetic RSS capture was blocked. |
| Representative Scratchpad startup/high-water | Incomplete: smoke only; no normal-start distribution and no open/close/settings interaction sequence. |
| Correctness | 320 runtime tests pass, including exact trace-output, event/cause ordering, ring-wrap, and passive-snapshot checks. Benchmark guards verify retained counts and geometry. |

To close #157, profile the remaining construction cost only if it is still material after integrating this candidate, and complete any required historical attribution. Also collect a clean Scratchpad native startup distribution and process high-water over startup, opening/closing representative panels/documents, and changing settings. Use the normal compiler-compatible Scratchpad tree, disable diagnostic capture for timing runs, and report first presentation separately from host-loop/shutdown time. If a compatible historical app baseline cannot be built, record a current-only app budget and compare runtime changes with the synthetic A/B rather than presenting an unmatched app comparison.
