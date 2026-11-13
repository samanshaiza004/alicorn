# Native mesh locality — issue #169

Research and implementation note, 2026-11-13. See [issue #169](https://github.com/samanshaiza004/alicorn/issues/169) and its [#168 baseline requirement](https://github.com/samanshaiza004/alicorn/issues/168).

## Finding

The SDL_GPU text renderer already retains one text vertex mesh and its GPU
buffer between presentations. `native_text_mesh_fingerprint` decides whether
to rebuild it; a matching fingerprint also leaves the uploaded vertex buffer
untouched. The fingerprint included each text command's absolute index in the
whole paint stream. Selection surfaces are emitted before their text, so
adding or removing one shifted that index and rebuilt an otherwise unchanged
text mesh. Caret surfaces are emitted after text and did not trigger this same
false invalidation.

The other native paths have different boundaries: icons and images retain
whole-stage meshes, custom geometry retains one mesh per command, and ordinary
solid geometry is rebuilt as a stage on each presentation. These are not
interchangeable cache opportunities. In particular, a per-owner solid/text
range cache would need to preserve painter order and keep GPU buffer ranges
valid while submissions are in flight.

SDL documents that cycling a GPU buffer makes its previous contents undefined;
partial updates therefore cannot assume unchanged ranges survive a cycle. See
[`SDL_UploadToGPUBuffer`](https://wiki.libsdl.org/SDL3/SDL_UploadToGPUBuffer)
and SDL's [GPU resource notes](https://wiki.libsdl.org/SDL3/CategoryGPU).

## Implemented

The text fingerprint now assigns ordinals only to text commands. It continues
to hash text order, run identity and generation, geometry, clipping, opacity,
translation state, color, spans, font properties, and display scale. Native
draw records use the same text-only ordinal, so inserting a selection surface
does not require rebuilding or remapping the retained text mesh. Reordering
text or changing a run generation still invalidates it.

The regression checks that a selection surface inserted before text preserves
the fingerprint and produces a mesh-cache hit, while caret surfaces leave the
same fingerprint unchanged. Separate assertions cover text ordering and draw
identity when run handles are reused.

## Decision and remaining evidence

This is a scoped GO for fixing the verified false invalidation by using the
existing whole-text-stage cache. It avoids adding a new range allocator,
fragmentation policy, or per-range GPU lifetime bookkeeping without evidence
that those costs buy a meaningful application-level win.

The broader per-owner GPU-buffer cache question remains open. The repository's
native diagnostics expose text mesh rebuild/cache-hit counts, cumulative
fingerprint/rebuild time, upload counts, and whole-frame p50/p95/p99, but this
change has not been measured with matched Scratchpad caret, selection, text
edit, and tab-indicator traces. No GPU timestamp query or cross-platform
Metal/D3D12 A/B was run here. Keep issue #169 open until those measurements
establish whether more granular caching improves an actual interaction and
does not regress bulk edits, resize, or device recreation.

## Verification

- `./tools/test.sh --odin /opt/homebrew/bin/odin` — passed on macOS with Odin
  `dev-2026-11:9a6991685`; includes the native SDL_GPU unit suite. Clang emitted
  existing stack-usage warnings; no test failures were reported.
- `./tools/native_sdl_gpu.sh --odin /opt/homebrew/bin/odin --smoke --diagnostics
  --capture-after=0 --capture-dir=/private/tmp/issue169-native
  --idle-validation-seconds=3` — compiled, but native presentation could not
  start because SDL reported `The video driver did not add any displays`.
  Pixel/readback parity and real Scratchpad interaction measurements therefore
  remain unverified in this environment.
- `git diff --check` — passed.
