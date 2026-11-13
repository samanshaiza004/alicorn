---
title: Project status
description: Alicorn's current scope, maturity, platform evidence, and known limitations.
---

Alicorn is an **experimental GUI runtime for Odin**. Its API is evolving, and
it is not production-ready. The project is a research and application-building
effort around direct procedural authoring with retained runtime execution.

## What exists

- A high-level <code>alicorn:ui</code> entry point and lower-level runtime API.
- A native SDL3 / SDL_GPU host with input, layout, text, paint, and retained
  identity.
- Typed themes, common controls, virtualized collections, retained motion,
  semantics, and diagnostic tooling.
- Windows and macOS native host validation.

## Platform limits

Linux has conditional native evidence from a limited set of configurations;
that is not broad Linux support. The native accessibility adapter currently
covers Windows and macOS, and accessibility validation is representative,
not comprehensive.

These boundaries can change. Read the current
[validation index](https://github.com/samanshaiza004/alicorn/tree/master/docs/validation)
and [release notes](https://github.com/samanshaiza004/alicorn/blob/master/CHANGELOG.md)
before making a support decision.

## Contribute

Reproducible bug reports and focused contributions are welcome. Include the
operating system, compiler revision, build command, and a minimal reproduction
when reporting native or runtime behavior.

[Source repository](https://github.com/samanshaiza004/alicorn) ·
[Open an issue](https://github.com/samanshaiza004/alicorn/issues) ·
[Contributing guide](https://github.com/samanshaiza004/alicorn/blob/master/docs/development.md)
