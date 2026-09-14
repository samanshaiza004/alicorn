# Project Alicorn

Project Alicorn is an experimental native GUI runtime for Odin. This repository
is intentionally foundation-first: the retained runtime is tested headlessly
before native rendering is allowed to influence the architecture.

## Current status

The repository contains a working, dependency-light retained runtime with:

- hierarchical source/key identity and hard ambiguity diagnostics;
- retained node state, explicit invalidation, retained regions and stage counters;
- deterministic flex-like layout, hit testing and one canonical focus owner;
- retained display commands and a bounded structural trace ring;
- a fixed-height million-row virtual-list proof;
- a custom-surface/GPU lifetime seam with deferred retirement bookkeeping;
- identity torture, property, layout, input, lifetime and benchmark executables.

The SDL3/SDL_GPU boundary includes a native retained compositor proof with
three frames in flight and deferred texture retirement.
Runa is vendored at a recorded commit; the adapter performs real font loading,
paragraph layout and bounded shape-cache reuse.

## Build and test

Set `ALICORN_ODIN` to the Odin executable, or use the default path in
`tools/test.ps1`:

```powershell
powershell -ExecutionPolicy Bypass -File tools/test.ps1
```

For the non-mutating style/type gate plus all headless target builds:

```powershell
powershell -ExecutionPolicy Bypass -File tools/check.ps1
```

Run the benchmark suite:

```powershell
powershell -ExecutionPolicy Bypass -File tools/bench.ps1
```

The commands write build outputs under `out/`, which is ignored by Git.
