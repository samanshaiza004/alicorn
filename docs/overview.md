# Alicorn overview

## What Alicorn is

Alicorn is an experimental native GUI runtime for Odin. Application code emits
a temporary, procedural description of its interface. Alicorn retains the
runtime facts that should survive between frames: identity, focus, geometry,
paint products, display data, and GPU resources.

The application keeps ownership of its own state. Alicorn does not silently
copy or observe arbitrary Odin memory. The application explicitly invalidates
the root or a logical region after a change, and the runtime decides what work
can be reused.

## Why it exists

Immediate-style APIs make small interfaces easy to write. Interactive tools
also need stable answers to harder questions:

- Which logical item owns focus, selection, hover, or text editing state?
- Which part of the interface needs to be described again?
- Which layout, text, paint, or GPU products are still valid?
- Why did a node do work after an input event?

Retained widget trees answer these questions, but they can move application
state into widget objects and impose a large lifecycle model on simple code.
Alicorn tests whether procedural application code and retained runtime
execution can coexist without requiring a reactive application architecture.

## Why Odin

Odin fits this experiment because its normal style keeps the important
boundaries visible:

- state can remain plain structs, arrays, maps, and pointers;
- ordinary procedures and control flow can describe a UI;
- explicit allocators make runtime ownership and lifetime inspectable;
- strong data types distinguish IDs, keys, revisions, geometry, and handles;
- `#caller_location` can add source identity without code generation;
- native interoperation can stay behind a narrow SDL boundary.

Odin's explicitness is part of the contract. It does not make arbitrary memory
mutation observable, and Alicorn does not pretend that it does.

## The design in one picture

```text
ordinary Odin state
        │
        ▼
procedural UI description
        │
        ▼
retained identity and runtime products
        │
        ├── input and focus
        ├── layout
        ├── paint and text
        └── native composition
```

The application does not own a widget tree. A retained node may own runtime
interaction state, geometry, caches, display data, and explicit GPU handles.
It must not silently retain an arbitrary application pointer.

## The important choices

### Explicit invalidation

The runtime cannot know that `track.muted = true` changed unless the
application invalidates something. Root invalidation is suitable for small
applications. Region revisions provide a smaller work boundary for larger
ones:

```odin
track.muted = !track.muted
track.revision += 1
```

If an application fails to update a revision, Alicorn is allowed to reuse
stale content. That is a documented trust boundary, not hidden reactivity.

### Identity and keys

Source locations identify structural program sites. Explicit keys identify
repeated runtime data. Together they let retained state follow a logical item
through insertion, removal, filtering, reordering, and conditional structure.

Duplicate keys and ambiguous repeated items are errors in debug and test paths.
Runtime IDs are not treated as durable IDs for persistence across application
versions.

### Regions

A region revision says that the application-provided description for that
region is still valid. An unchanged region can be represented by one retained
subtree marker instead of rebuilding every descendant description. Removing a
region retires its entire retained subtree deterministically.

Regions are pruning boundaries, not automatic dependency tracking. Parent
constraints may still require layout inside a reused description.

### Separate work stages

Description, reconciliation, layout, paint, and composition are separate
stages. Reusing one stage does not imply that every later stage is reusable.
This allows, for example, a text description to remain unchanged while its
layout is recomputed for a new window width.

### SDL3, SDL_GPU, and Runa

SDL3 provides the initial window and input boundary. SDL_GPU provides explicit
command-buffer, render-pass, resource, and fence lifetimes. Runa provides font
parsing, shaping, bidi, segmentation, line breaking, and rasterization.

Alicorn keeps its GUI text model separate from Runa's atlas representation.
The current native path proves retained monochrome glyph rendering; editing,
IME, and broader platform validation remain later gates.

## What we are betting on

1. Explicit invalidation can provide useful locality without reactive state.
2. Hierarchical identity and explicit keys can preserve interaction state under
   adversarial structural changes.
3. The runtime can retain expensive products without owning application data.
4. SDL_GPU's explicit lifetime model is enough for safe composition and custom
   surfaces across native backends.
5. Future semantic, causal, and scheduling layers can attach to runtime
   identity without distorting the small core.

Only the first four are being exercised by the current foundation. The fifth is
an open architectural bet.

## What Alicorn does not require

- automatic observation of arbitrary Odin memory;
- a mandatory signal, observable-wrapper, reducer, Redux, or Elm architecture;
- application-owned widget objects;
- CSS compatibility or a giant widget catalog;
- a claim that every full-root wake is sublinear;
- imaginary GPU preemption or hidden resource scheduling.

The detailed mechanics and evidence live in the [architecture](architecture.md)
and [proof](proof.md) documents.
