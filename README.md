# Project Alicorn

Project Alicorn is an experimental native GUI runtime for Odin.

Its central idea is simple:

> **Direct to write. Retained to run. Semantic to understand. Causal to inspect. Scheduled to respond.**

The foundation phase concentrates on the first two clauses. An application
emits a small procedural description using ordinary Odin state. Alicorn
retains the runtime facts that are expensive or interaction-sensitive:
identity, focus, layout products, paint products, display data and GPU-facing
resources.

The application does not own a widget tree. Alicorn does not silently observe
arbitrary Odin memory. The application explicitly invalidates the root or a
logical region when its state changes; the runtime then decides which retained
work can be reused.

**Status: early experimental runtime; architecture is being proven before API
stability or widget breadth.**

## The thesis

The thesis is not that immediate-mode APIs are secretly retained widgets. It
is that these two properties can coexist at different layers:

```text
application code       procedural and ephemeral
runtime execution      retained and identity-stable
application state      ordinary Odin data
invalidation           explicit root/region revisions
```

The primary question is:

> Can a GUI expose immediate-style procedural ergonomics while maintaining
> stable identity, granular work avoidance, virtualization, correct input and
> GPU-native composition without requiring a mandatory reactive state model?

This repository treats that as an engineering claim. Tests, counters,
benchmarks and native probes are the evidence. [`PROOF.md`](PROOF.md) records
what has actually been demonstrated and what remains uncertain.

## Why Alicorn exists

Traditional immediate APIs make small interfaces pleasant to describe, but a
large or interactive application still needs stable answers to questions such
as:

- Which logical item owns this focus, caret, selection or hover state?
- Which subtree needs to be described again after one domain revision changes?
- Which shaped text, layout result, GPU resource or display command is still
  valid?
- Why did this node perform work?
- What happened after a pointer event?

Traditional retained widget trees answer those questions, but they often move
ownership of application state into widget objects and make a simple screen
depend on a large lifecycle model.

Alicorn is an attempt to keep the application-facing side small and
procedural while putting identity, lifetime, caching and observability in the
runtime where they can be tested and inspected.

## Why Odin

Odin is a good fit for this experiment because its normal style is close to the
desired programming model:

- application state can remain plain structs, arrays, maps and pointers;
- procedures and ordinary control flow are enough to describe a UI;
- explicit allocators and manual ownership make retained lifetime boundaries
  visible;
- strong, simple data types are useful for distinguishing runtime IDs, keys,
  revisions, geometry and GPU handles;
- compile-time/source-location facilities such as `#caller_location` can add
  ergonomic structural identity without requiring application code generation;
- native interoperation can stay at a narrow SDL boundary.

Odin is not being used as a reason to pretend that arbitrary memory mutation is
observable. Its explicitness is part of the contract: if a logical region
changed, the application tells Alicorn by changing its revision or invalidating
the root.

## The important design choices

### Ordinary application state

Conceptual target ergonomics, not a promise that every call below is the
current compiled public API:

```odin
if ui.button("Save") {
    save(app)
}

ui.text_input(&app.query)

ui.region("sidebar", app.sidebar_revision) {
    project_tree(&app.project)
}
```

A retained node may own runtime interaction state, geometry, caches, display
data and GPU handles. It does not silently retain an arbitrary application
pointer or closure. Text-edit results are handed back to the application,
which copies them into its own state before the next description pass.

### Explicit invalidation

The runtime cannot know that `track.muted = true` changed unless the
application invalidates something. This is a deliberate trust boundary, not a
missing feature:

```odin
track.muted = !track.muted
track.revision += 1
```

Root invalidation is simple and appropriate for small applications. Region
revisions let larger applications identify a smaller logical frontier. If the
application lies about a revision, Alicorn is allowed to reuse stale retained
content. There is no hidden dependency tracker and no mandatory signal graph.

### Hierarchical identity and keys

Identity comes before caching, semantics, accessibility or causality. A
runtime identity combines its parent scope, structural source site and an
optional explicit key. `#caller_location` supplies source identity for
ergonomic calls; it is not sufficient for repeated runtime data.

Repeated items must use explicit keys:

```odin
for track in tracks {
    if alicorn.key_scope_u64(&ui, track.id) {
        track_row(track)
        alicorn.key_scope_end(&ui)
    }
}
```

The same logical key must keep its retained state through insertion, removal,
reordering, filtering, conditional structure and representation changes that
are explicitly mapped. Missing keys in ambiguous repeated scopes and duplicate
keys in one scope are hard diagnostics in debug/test paths. A runtime ID is not
assumed to be a durable semantic ID across application versions.

### Regions as explicit pruning boundaries

A region revision says that the application-provided description for that
logical region is still valid. When the identity and revision match, the
region body is skipped and the retained subtree is represented by one reuse
marker rather than by copying every cached descendant description.

This is a pruning mechanism, not automatic reactivity. Parent constraints can
still invalidate layout inside a reused description. A removed region retires
its complete retained adjacency, including descendants and runtime resources.

### Separate work stages

Description, reconciliation, layout, paint and composition are distinct stages.
Reuse at one stage does not imply reuse at every stage:

```text
description  → retained identity and state
layout       → geometry under incoming constraints
paint        → display products and text/glyph references
composition  → ordered GPU submission data
```

That separation is what permits a reused text description to lay out again
after a window constraint changes, or a changed glyph resource to update while
unrelated controls remain untouched.

### SDL3, SDL_GPU and Runa

SDL3 is the initial platform boundary for windows and input. SDL_GPU gives the
native path explicit command-buffer, render-pass, resource and fence
lifetime. Alicorn owns the policy around those handles rather than exposing
SDL objects to application code.

Runa supplies the text machinery that would be unreasonable to recreate inside
the GUI runtime: shaping, bidi, segmentation, line breaking, font parsing and
rasterization. The Alicorn text layer keeps its own font policy, layout and
editing abstractions separate from Runa's atlas representation. The first
Runa-to-SDL_GPU alpha glyph path now exists; its next gate is native text
geometry and editing. See
[`GPU_TEXT_GATE.md`](GPU_TEXT_GATE.md).

## What we are betting on

The architecture makes five bets:

1. Explicit root/region invalidation can provide useful work locality without
   making application state reactive.
2. Hierarchical source identity plus explicit keys can preserve retained state
   through adversarial structural changes.
3. The runtime can retain expensive execution products without taking
   ownership of arbitrary application objects.
4. SDL_GPU's explicit resource and fence model is sufficient for safe,
   persistent composition and custom surfaces across native backends.
5. Semantic, causal and scheduled layers can attach to runtime identity and
   invalidation traces later without distorting this small core.

The fifth bet is intentionally not claimed as proven by the foundation.

## What we are not betting on

Alicorn does not depend on:

- automatic observation of arbitrary Odin memory;
- a mandatory signal, observable-wrapper, Redux, Elm or reducer architecture;
- application-owned widget objects;
- a general-purpose virtual DOM with global liveness scans;
- CSS compatibility, a giant widget catalog or physics-driven layout;
- a promise that every root wake is sublinear;
- imaginary GPU preemption or a scheduler that hides resource lifetime.

The explicit-region model is the optimization boundary. A flat root that the
application deliberately invalidates may still require a flat walk.

## Current foundation evidence

The current foundation has executable evidence for:

- hierarchical keyed identity, duplicate-key diagnostics and identity torture
  sequences;
- retained regions with atomic subtree reuse and deterministic subtree
  retirement;
- stage counters for reconciliation, layout, paint and composition;
- deterministic pointer capture, activation and focus fallback;
- fixed-height virtualization with one million logical rows and bounded
  retained nodes;
- Runa-backed font loading, shaping, grapheme-safe editing and multiline
  metrics;
- retained rectangle display data and a native SDL3/SDL_GPU compositor with
  three frames in flight and deferred resource retirement;
- a first real Runa-to-SDL_GPU alpha glyph path: runtime-owned retained glyph
  runs, a generation-keyed CPU glyph cache, persistent atlas textures,
  conservative full-page-on-cycle uploads, ordered/scissored text passes and
  a portable shader pipeline selected per SDL backend;
- a bounded structural trace and an inspector-facing runtime state model;
- an eight-track Crucible and headless tests that exercise the above together.

The GPU text path is an early alpha-glyph proof, not a finished text system:
color-glyph rendering, broad screenshot comparison, caret/selection geometry,
real native editing, IME behavior, Linux native validation, process-wide idle
wakeup telemetry and the semantic/causal layers are not yet proven.

## Benchmark evidence

These are raw one-shot Windows measurements from the retained-work gate on
Odin `dev-2026-09-nightly:a2fb372`, 2026-09-14. Counters are more important
than the wall-clock values; the full table and methodology are in
[`PROOF.md`](PROOF.md).

| case | wall time | description/reconcile | retained-region reuse | paint | composition | retained nodes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| true idle, 10k tree, 10k attempted frames | 18,400 ns total | 0 | 0 | 0 | 0 | 10,001 |
| 10k root wake, unchanged | 12,772,400 ns | 10,001 / 10,001 | 0 | 0 | 0 | 10,001 |
| regional tree, unchanged root wake | 144,700 ns | 102 / 102 | 100 | 0 | 0 | 10,102 |
| one 100-node region changed | 294,100 ns | 202 / 202 | 99 | 101 | 101 | 10,102 |
| 10k-descendant region reused | 13,200 ns | 3 / 3 | 1 | 1 | 1 | 10,003 |
| full keyed reorder | 12,724,000 ns | 10,001 / 10,001 | 10,000 | 1 | 10,001 | 10,001 |

The first GPU-text smoke run is a separate native measurement, because its
wall time includes window/swapchain stress rather than a headless text-only
loop:

| case | submissions | shape calls | run misses/hits | glyph misses/hits | rasterizations | atlas pages | quads |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Windows D3D12, 303 submissions / 300 resizes | 303 | 1 | 1 / 603 | 15 / 14 | 15 | 1 | 26 |

The evidence supports a narrower claim than “everything is incremental”: true
idle is constant with respect to the retained tree, and explicit region
changes are local in description/reconciliation. Flat root wakes and global
structural reorders remain more expensive by design.

## Next gate

The first Runa raster → persistent atlas → SDL_GPU alpha text stage is now
implemented and partially proven. The next gate is a genuinely usable native
editable field:

1. caret geometry, selection rectangles, mouse
   hit testing, visual/logical movement and clipboard.
2. SDL text input and IME composition.
3. One shader-backed custom surface beside ordinary retained UI.

The completed stage is documented in [`GPU_TEXT_GATE.md`](GPU_TEXT_GATE.md) and
[`PROOF.md`](PROOF.md). Screenshot/readback validation, color glyphs, native
caret/selection and non-Windows execution remain open evidence.

## Build and test

Set `ALICORN_ODIN` to the Odin executable, or let the scripts resolve `odin`
through `PATH`:

```powershell
powershell -ExecutionPolicy Bypass -File tools/test.ps1
powershell -ExecutionPolicy Bypass -File tools/check.ps1
powershell -ExecutionPolicy Bypass -File tools/bench.ps1
```

On macOS and other Unix-like hosts:

```sh
./tools/test.sh
./tools/check.sh
./tools/bench.sh
./tools/native_sdl_gpu.sh
```

Build output is written under `out/` and ignored by Git. SDL3 is required only
for the native fixture; the headless runtime and structural proof tests use
Odin's core packages.

## Repository guide

- [`THESIS.md`](THESIS.md) — the short foundation thesis.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — implemented runtime mechanics.
- [`IDENTITY.md`](IDENTITY.md) — identity construction and ambiguity rules.
- [`PROOF.md`](PROOF.md) — tests, benchmarks, limitations and verdicts.
- [`GPU_TEXT_GATE.md`](GPU_TEXT_GATE.md) — researched next-gate plan.
- [`DEPENDENCIES.md`](DEPENDENCIES.md) — pinned/vendor dependency notes.
- [`ROADMAP.md`](ROADMAP.md) — foundation, scale, observability, experimental
  and research work kept separate.
