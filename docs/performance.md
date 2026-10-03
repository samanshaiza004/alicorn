# Performance evidence

These are author-run, workload-specific measurements. They are intended to
be reproducible and falsifiable, not to claim that Alicorn is faster than
another GUI framework. Read the machine, compiler, build mode, workload, and
limitations before using a number.

## Reports

- [Wrapped text/layout](benchmarks/text-layout.md): the same 20,000-logical-row
  headless scroll/reflow workload, measured separately on Windows and macOS,
  with raw per-run output for both platforms.
- [Retained-work suite on macOS](benchmarks/retained-work-macos.md): tree
  sizes, retained-region reuse, keyed churn, true-idle counters, custom-surface
  locality, and million-item virtualization. One Mac run; raw output included.
- [Retained-work suite on Windows](benchmarks/retained-work-windows.md): the
  same headless workloads repeated in three fresh processes, with raw output.
- [Native hello on macOS](benchmarks/native-hello-macos.md): Metal host,
  one controlled no-input idle observation, process RSS/CPU sampling, binary
  size, and qualified startup markers.
- [Native and dogfood apps on Windows](benchmarks/native-dogfood-windows.md):
  Direct3D 12 idle/submission, process-memory and qualified startup samples,
  plus bounded Monitor, History, and fixed-fixture Scope smoke runs.

## Reproduce

From a fresh checkout with the documented Odin toolchain:

```sh
./tools/bench.sh
./tools/bench_text_layout.sh
```

The equivalent PowerShell entry points are `tools/bench.ps1` and
`tools/bench_text_layout.ps1`. Both scripts accept an explicit Odin path.
Native-host measurements require a supported desktop session; commands,
environment, raw captures, and workload limitations are in the platform
reports above.

## Coverage boundary

The v0.1.0 evidence now contains Windows/macOS focused text-layout results,
retained-work results on both platforms, native-host idle/startup samples, and
bounded Windows dogfood runs for Monitor, History, and Scope. Monitor observes
the live machine; History uses a 27-commit local repository; Scope uses the
published deterministic 100,000-event fixture. Only native hello is used for
the controlled idle CPU/submission claim. The dogfood smoke captures are short
startup/load samples, not steady-state idle or long-term memory tests. These
are author-run, workload-specific baselines. Never compare results from
different machines as if they were the same experiment.
