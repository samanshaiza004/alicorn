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
