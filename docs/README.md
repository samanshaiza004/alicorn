# Alicorn documentation

This directory contains the design notes, implementation record, proof
reports, and platform notes for Project Alicorn. The root
[`README.md`](../README.md) is the short introduction; this is the detailed
project record.

## Start here

- [Overview](overview.md) — what Alicorn is, why it exists, and the design bets.
- [Thesis](thesis.md) — the short statement the foundation is trying to prove.
- [Architecture](architecture.md) — the mechanics that are actually implemented.
- [Proof report](proof.md) — tests, measurements, limitations, and verdicts.

## Runtime foundations

- [Identity](identity.md) — runtime identity, scopes, keys, and ambiguity rules.
- [Roadmap](roadmap.md) — foundation, scale, observability, experimental, and research work.
- [Research notes](research.md) — external precedents and what transfers to Alicorn.
- [Dependencies](dependencies.md) — versions, vendor boundaries, and license notes.

## Current GPU and platform work

- [GPU text gate](gpu-text-gate.md) — the GPU text implementation and closure record.
- [SDL3 / SDL_GPU boundary](platform/sdl-gpu.md) — native backend lifetime and composition notes.
- [macOS validation](platform/macos-validation.md) — Apple Silicon validation history and limits.

## Examples

- [Examples and fixtures](examples.md) — identity torture, Crucible, benchmarks, and Runa text.

The documentation is intentionally organized as ordinary Markdown so it can be
turned into a documentation site later without changing the source record.
