# Project Alicorn

Project Alicorn is an experimental native GUI runtime for [Odin](https://odin-lang.org/).

## What is it?

Alicorn lets an application describe its interface with ordinary Odin code.
The runtime keeps the identity, interaction state, layout results, drawing data,
and GPU resources that should survive from one frame to the next.

```odin
if ui.button("Save") {
    save(app)
}

ui.text_input(&app.query)

ui.region("sidebar", app.sidebar_revision) {
    project_tree(&app.project)
}
```

This is the intended style; the public API is still experimental.

The application owns its data. It does not need to build or manage a tree of
widget objects.

## Who is it for?

Alicorn is for people building native Odin tools, editors, creative software,
and other applications where a small UI should stay simple without giving up
stable interaction and efficient updates at larger scale.

It is an engineering project, not a production-ready toolkit. APIs and
implementation details are still changing.

## Why does it exist?

Small immediate-style APIs are pleasant to write, but larger interactive
applications need stable focus, identity, layout, caching, and input behavior.
Traditional retained widget trees provide those things, but can make the
application own a large object hierarchy and lifecycle.

Alicorn explores whether the two strengths can live at different layers:

> Direct to write. Retained to run.

The application writes a procedural description. Alicorn retains the runtime
work that is expensive or interaction-sensitive.

## What makes it different?

- Application state stays ordinary Odin data.
- Invalidation is explicit. Alicorn does not watch arbitrary memory or require
  a signal graph.
- Stable runtime identity comes from structure and explicit keys.
- Regions give larger applications a clear boundary for reusing unchanged UI.
- Tests, counters, benchmarks, and native probes are part of the design proof.

The project is deliberately proving its foundation before growing a large
widget catalog or adding higher-level systems.

## Current status

The foundation includes retained identity, keyed reconciliation, explicit
region reuse, layout, input and focus, virtualization, Runa-backed text, a
native SDL3/SDL_GPU compositor, and a retained GPU text path with basic text
geometry.

The current GPU text path is an alpha-glyph proof with platform-neutral caret,
selection, wrapping, and hit-testing foundations. Committed SDL Unicode input
and transient preedit composition now work through the retained text field;
real OS IME validation, color glyphs, and broader platform proof remain. A
separate retained GPU-surface gate now proves a small shader-backed waveform
can update without rebuilding the surrounding UI on Windows Direct3D12.

## Try it

You need Odin for the headless tests and SDL3 from the Odin SDK for the native
fixture.

```powershell
powershell -ExecutionPolicy Bypass -File tools/check.ps1
powershell -ExecutionPolicy Bypass -File tools/bench.ps1
powershell -ExecutionPolicy Bypass -File tools/native_sdl_gpu.ps1 -SurfaceStress
```

See [`docs/examples.md`](docs/examples.md) for the available examples and
[`docs/`](docs/) for the architecture, proof reports, benchmarks, and roadmap.

## License

Project Alicorn is released under the [zlib License](LICENSE). Vendored
dependencies retain their own licenses; see [`docs/dependencies.md`](docs/dependencies.md).
