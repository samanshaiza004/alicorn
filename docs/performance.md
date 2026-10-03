# Performance evidence

These are author-run, workload-specific measurements. They are intended to
be reproducible and falsifiable, not to claim that Alicorn is faster than
another GUI framework. Read the machine, compiler, build mode, workload, and
limitations before using a number.

## Reports

- [Wrapped text/layout](benchmarks/text-layout.md): the same 20,000-logical-row
  headless scroll/reflow workload, measured separately on Windows and macOS,
  with per-run Mac output and the supplied Windows summary.
- [Retained-work suite on macOS](benchmarks/retained-work-macos.md): tree
  sizes, retained-region reuse, keyed churn, true-idle counters, custom-surface
  locality, and million-item virtualization. One Mac run; raw output included.
- [Native hello on macOS](benchmarks/native-hello-macos.md): Metal host,
  one controlled no-input idle observation, process RSS/CPU sampling, binary
  size, and qualified startup markers.

## Reproduce

From a fresh checkout with the documented Odin toolchain:

```sh
./tools/bench.sh
./tools/bench_text_layout.sh
```

The equivalent PowerShell entry points are `tools/bench.ps1` and
`tools/bench_text_layout.ps1`. Both scripts accept an explicit Odin path.
Native-host measurements require a supported desktop session and are described
in the native hello report.

## Coverage boundary

The current report contains Windows/macOS results for the focused headless
text workload, a macOS retained-work suite, and a macOS native-host sample.
It does not yet contain a matching Windows retained-work run, a Windows
native-host idle/startup baseline, or fixed-fixture native measurements for
Monitor, History, and Scope. The benchmark issue remains open while those
items are unresolved. Do not compare separate machines as if they were the
same performance experiment.
