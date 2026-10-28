# Retained-work locality regression

The runtime tests assert that a paint-only change to a sibling of a reused
10,000-descendant region does not examine or measure those descendants, does
not refresh retained semantic order, and finalizes only the changed display
command. They also compare incremental display output with full finalization
and cover fractional and round-trip DPI changes.

Run the deterministic runtime contract and broader benchmark with:

```sh
odin test runtime
sh tools/bench.sh --odin /path/to/odin
```

For an alternating, same-machine timing comparison against the pre-regression
baseline, include the known regression revision, and keep the compiler and host
unchanged:

```sh
python3 tools/bench_retained_locality.py \
  --odin /path/to/odin \
  --baseline 96461223cdbf43080acb957276c045ad704f4606 \
  --regressed 3e31c743298f758b4cafd4f425e296a59cd95e34 \
  --candidate HEAD
```

Add `--speed` to compile every snapshot with `-o:speed`. The comparison writes
raw samples and a JSON summary under `out/retained-locality-comparison/`. Its
timing threshold is a diagnostic signal; the deterministic work-count tests
are the correctness gate. The candidate check fails only when region-reuse
latency exceeds both 1.5 times the baseline and 1 ms.

## Validation on the v0.2.0 candidate

Measured on the same MacBookAir10,1 / Apple M1 / 8 GB machine running macOS
27.2, with Odin `dev-2026-09-nightly:a2fb372`. Each profile built the baseline,
known regressed commit, and fix from Git snapshots, then ran three alternating
fresh-process samples per revision. The default profile is Odin's default;
the optimized profile uses `-o:speed` for every snapshot.

| Profile | Workload | Baseline | Regressed | Fixed |
| --- | --- | ---: | ---: | ---: |
| Default | 10,000-descendant region reuse | 0.278 ms | 11.694 ms | 0.047 ms |
| `-o:speed` | 10,000-descendant region reuse | 0.140 ms | 3.318 ms | 0.027 ms |
| Default | Initial 10,000-node tree | 67.696 ms | 156.381 ms | 164.421 ms |
| `-o:speed` | Initial 10,000-node tree | 22.688 ms | 50.923 ms | 53.205 ms |
| Default | Unchanged 10,000-node root description | 26.287 ms | 55.272 ms | 40.387 ms |
| `-o:speed` | Unchanged 10,000-node root description | 8.819 ms | 16.651 ms | 15.352 ms |

The targeted reused-region update is now about 249× faster than the regressed
revision in the default profile and 123× faster with optimization. It is below
the older baseline in both profiles. The fixed build's locality counters for
that update report zero measurement nodes examined or executed, one display
command finalized, zero full display passes, zero semantic-order nodes examined,
and zero global fallbacks.

Initial construction remains costly and is slightly slower than the regressed
revision in these samples; this change targets post-construction locality and
does not claim to solve construction cost. The fixed 10,000-node initial build
measured 130,195 allocations and 112,173,458 cumulatively allocated bytes
(allocation traffic, not peak resident memory), with 10,000 text measurements,
20,001 layout visits, and 10,001 finalized display commands. These counters
show the work scales with the requested initial tree, but do not yet identify
the dominant allocation or CPU time by function. Native macOS sampling could
not attach to the benchmark process in this environment, so profiling
construction remains a separate follow-up. The deterministic tests guard the
locality contract independently of these noisy timing measurements. The raw
alternating runs are [default profile](raw/retained-locality-macos-m1-2026-10-28-default.txt)
and [`-o:speed`](raw/retained-locality-macos-m1-2026-10-28-speed.txt).
