# Retained-locality performance rerun — Windows — 2026-10-28

This rerun measures current `master` after `cc88bfd` restored retained update
locality. It is machine-specific headless CPU evidence, not a claim about native
frame latency, memory residency, or cross-platform performance.

## Environment and method

| Item | Value |
| --- | --- |
| Source | `d8b011ac5384cea71643176e49ed952852b9da38` (`master`) |
| Git tree | `ae05443fa7f8663c7a3db486df4c8dffccc42130` |
| OS | Windows 10 Home 22H2, build 19045 |
| CPU | AMD Ryzen 5 7600X, 12 logical processors |
| GPU | NVIDIA GeForce RTX 2080 SUPER |
| Memory | 16 GiB installed |
| Odin | `dev-2026-09-nightly:a2fb372` |

The matched locality harness built the older baseline (`9646122`), the known
regressed revision (`3e31c74`), and current `master` from Git snapshots, then
ran three alternating fresh-process samples per revision in the default and
`-o:speed` profiles. The broader retained, text-layout, and material suites
were also run in three fresh processes per workload. Raw output is preserved
in [`raw/`](raw/) with the `performance-rerun-windows-2026-10-28-` prefix.

## Matched locality results

Times are medians per operation. Lower is better.

| Profile | Workload | Older baseline | Regressed | Current master |
| --- | --- | ---: | ---: | ---: |
| Default | Reuse a 10,000-descendant region | 0.307 ms | 5.976 ms | 0.056 ms |
| Default | Initial 10,000-node tree | 52.852 ms | 129.312 ms | 132.902 ms |
| Default | Unchanged 10,000-node root | 20.074 ms | 36.470 ms | 32.576 ms |
| `-o:speed` | Reuse a 10,000-descendant region | 0.207 ms | 2.323 ms | 0.036 ms |
| `-o:speed` | Initial 10,000-node tree | 30.001 ms | 57.435 ms | 58.969 ms |
| `-o:speed` | Unchanged 10,000-node root | 9.302 ms | 16.819 ms | 15.306 ms |

Current region reuse is about 107× faster than the regressed default build and
65× faster with `-o:speed`; it is also below the older baseline in both
profiles. The fixed path reports zero measurement nodes examined or executed,
one display command finalized, zero full display passes, zero semantic-order
nodes examined, and zero global fallbacks.

Initial construction did not improve: current master measured about 3% slower
than the regressed revision in both profiles, while remaining about 2.5× the
older baseline in the default profile. This change targets post-construction
locality. The timing does not identify why initial construction is slower.

## Broader current-master rerun

These medians compare the earlier three-process capture from
[`performance-final-windows-2026-10-28.md`](performance-final-windows-2026-10-28.md)
(source `3e31c74`) with this current-master rerun. The same machine and workload
scripts were used; noise and source differences mean small changes should not
be attributed to code improvements.

| Profile | Workload | Earlier | Current master | Change |
| --- | --- | ---: | ---: | ---: |
| Default | 10,000-node unchanged root | 39.052 ms | 33.734 ms | −13.6% |
| Default | 10,000-node one-value update | 40.322 ms | 30.846 ms | −23.5% |
| Default | 100-node region update | 6.460 ms | 0.694 ms | −89.3% |
| Default | Reuse a 10,000-node subtree | 6.346 ms | 0.052 ms | −99.2% |
| Default | 1M-item virtual list, 100 frames | 27.466 ms | 26.781 ms | −2.5% |
| `-o:speed` | 10,000-node unchanged root | 16.393 ms | 14.579 ms | −11.1% |
| `-o:speed` | 10,000-node one-value update | 15.499 ms | 14.291 ms | −7.8% |
| `-o:speed` | 100-node region update | 2.190 ms | 0.321 ms | −85.4% |
| `-o:speed` | Reuse a 10,000-node subtree | 2.427 ms | 0.038 ms | −98.4% |
| `-o:speed` | 1M-item virtual list, 100 frames | 8.325 ms | 8.456 ms | +1.6% |

The million-item workload is effectively unchanged. The text-layout medians
were also effectively flat: variable-height scrolling was 2.939 ms/frame
before and 2.925 ms/frame now; wrapped reflow was 3.307 and 3.297 ms/frame.
Current material expansion measured 8.52 ns/surface for direct quads and
8.29 ns/surface for flat materials. Output checksums matched, and every
vertex-budget case passed at scales 1, 1.25, 1.5, and 2. These small timing
moves are within run-to-run noise and do not establish a material-path speedup.

The 10,000-node idle fixture continued to report zero allocations, reconciliation,
layout, paint/composition visits, and GPU submissions across 10,000 frames.
The million-item visual list retained 23 nodes. The 1,200 custom-surface update
fixture reported zero ordinary UI work and zero allocations.

## macOS benchmark context and next validation

The checked-in [Mac locality report](retained-locality.md) records Apple M1
results for the same three-revision experiment: region reuse measured 0.050 ms
versus 11.420 ms at the regression in the default profile, and 0.043 ms versus
3.750 ms with `-o:speed`. Initial 10,000-node construction remained around
2.6× the older baseline in the default profile. Those captures used the
documented rebased candidate `f5e7888`; that commit object is not available in
this Windows clone, so its tree could not be compared directly to current
`master` here.

To validate the merged head on the Mac, run both profiles from a clean checkout
of `d8b011a` with the same Odin nightly and three samples:

```sh
python3 tools/bench_retained_locality.py --odin /path/to/odin --runs 3
python3 tools/bench_retained_locality.py --odin /path/to/odin --runs 3 --speed
```

These benchmarks are headless. They do not measure native startup, interactive
latency, RSS, GPU residency, or long-term memory retention.
