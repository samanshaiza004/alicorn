# Alicorn

Alicorn is an experimental native GUI runtime for [Odin](https://odin-lang.org/).

It lets you describe a window with ordinary Odin code while the runtime keeps
the parts that need to survive between frames: identity, focus, layout, text,
paint data, and GPU resources.

```odin
if alicorn.button(ui, "Save") {
	app.saved = true
}

alicorn.text(ui, app.title)
```

Your application keeps its own state. You do not build a widget-object tree,
adopt a reactive state system, or give Alicorn pointers to arbitrary data.
When state changes, you explicitly invalidate the root or a region.

## Who it is for

Alicorn is for people who want to build native Odin tools, editors, creative
software, and other interactive desktop applications. It is also an experiment
for programmers who are curious about Odin and want a small, direct example to
learn from.

The project is not production-ready. The API and implementation are still
changing.

## Why it exists

Small immediate-style APIs are easy to write. Larger applications still need
stable identity, focus, virtualization, caching, predictable input, and safe
GPU lifetimes.

Alicorn asks whether those needs can live inside the runtime without making
application code own a large widget hierarchy or adopt a mandatory reactive
architecture.

The short version is:

> Direct to write. Retained to run.

## What is different

- State stays ordinary Odin data.
- Invalidation is explicit; Alicorn does not watch arbitrary memory.
- Source location gives structural identity. A key identifies a repeated data
  item.
- Retained regions can avoid reevaluating unchanged subtrees.
- Layout, text, input, GPU composition, tests, and benchmarks are built as one
  measurable system.
- Odin's defaults remain optional: start with `text`, `button`, and normal
  control flow, then learn keys, regions, and allocator configuration only when
  your application needs them.

## Current status

The repository contains a working experimental foundation with retained keyed
identity, explicit region reuse, layout, focus and pointer input, fixed-height
virtualization, Runa-backed text and editing, SDL3/SDL_GPU composition, GPU
text, transient IME composition, and a shader-backed surface seam.

The separate [Alicorn Monitor](https://github.com/samanshaiza004/alicorn-monitor)
dogfood application exercises the public API against live Windows process data.

## Try it

You need Odin for the headless tests. The native fixture also needs SDL3 from
the Odin distribution on Windows; the validated Darwin host requires SDL3
`3.4.16`.

```powershell
powershell -ExecutionPolicy Bypass -File tools/check.ps1
powershell -ExecutionPolicy Bypass -File tools/bench.ps1
powershell -ExecutionPolicy Bypass -File tools/native_sdl_gpu.ps1 -SurfaceStress
```

Start with the [five-minute tutorial](docs/guide/tutorial.md). The full
technical record is in [docs](docs/README.md), including the architecture,
identity rules, proof report, benchmarks, platform notes, and roadmap.

## License

Project Alicorn is released under the [zlib License](LICENSE). Vendored
dependencies retain their own licenses; see
[docs/dependencies.md](docs/dependencies.md).
