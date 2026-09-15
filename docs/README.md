# Alicorn documentation

This directory contains the design notes, implementation record, proof
reports, and platform notes for Project Alicorn. The root
[`README.md`](../README.md) is the short introduction; this is the detailed
project record.

## Start here

- [Five-minute tutorial](guide/tutorial.md) — build a first UI with ordinary Odin.
- [Mental model](guide/mental-model.md) — the few concepts behind retained execution.
- [Canonical API](guide/api.md) — the public calls most applications should use.
- [Odin for Alicorn](guide/odin-for-alicorn.md) — Odin features encountered naturally.
- [Advanced identity and allocation](guide/advanced.md) — escape hatches and ownership.
- [API and ownership pass](api-ownership.md) — canonical calls, typed keys, and allocator lifetime.
- [Overview](overview.md) — what Alicorn is, why it exists, and the design bets.
- [Thesis](thesis.md) — the short statement the foundation is trying to prove.
- [Architecture](architecture.md) — the mechanics that are actually implemented.
- [Proof report](proof.md) — tests, measurements, limitations, and verdicts.
- [Native observability](observability.md) — CLI/F12 diagnostics, timings,
  retained inspection, and dependency-free screenshot captures.

## Runtime foundations

- [Identity](identity.md) — runtime identity, scopes, keys, and ambiguity rules.
- [Roadmap](roadmap.md) — foundation, scale, observability, experimental, and research work.
- [Research notes](research.md) — external precedents and what transfers to Alicorn.
- [Dependencies](dependencies.md) — versions, vendor boundaries, and license notes.

## Current GPU and platform work

- [GPU text gate](gpu-text-gate.md) — the GPU text implementation and closure record.
- [Text input and IME](text-input.md) — committed input, transient composition,
  ownership and the remaining native proof boundary.
- [SDL3 / SDL_GPU boundary](platform/sdl-gpu.md) — native backend lifetime and composition notes.
- [macOS validation](platform/macos-validation.md) — Apple Silicon validation history and limits.
- [GPU surface gate](gpu-surface-gate.md) — explicit high-frequency waveform updates beside retained UI.

## Examples

- [Examples and fixtures](examples.md) — identity torture, Crucible, benchmarks, and Runa text.
- [Process monitor dogfood](process-monitor.md) — the first application-sized
  Windows test combining sampling, keyed rows, text, and a live GPU surface.

The documentation is intentionally organized as ordinary Markdown so it can be
turned into a documentation site later without changing the source record.
