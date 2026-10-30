# #109 completion proposal: retained sizing with Scratchpad and Punks

Status: correctness fixes and initial two-app dogfooding are complete. Keep
[#109](https://github.com/samanshaiza004/alicorn/issues/109) open until the
performance and native acceptance evidence below is collected.

Research date: 2026-10-29, America/Guatemala.

## Recommendation

Finish the existing small vocabulary, repair two demonstrated correctness
gaps, and evaluate Scratchpad's font picker plus Punks' results/deck layout.
The intended outcome is a narrow GO for typed local sizing and retained
definite-parent percentage width. Percentage height, intrinsic fit width,
arbitrary allocated-parent percentages, and aspect-ratio syntax should receive
an explicit deferred/NO-GO decision for this iteration.

This is a research decision gate, not a promise that every constructor inspired
by another layout library will ship. If the second app does not benefit over a
simplified legacy implementation, report that result and close the broader
adoption experiment as NO-GO instead of manufacturing a second success.

## Implementation and dogfood update — 2026-10-30

### Correctness fixes

The two reproduced failures are fixed on current Alicorn `master`:

- `21a91a9` lets a typed panel size override an implicit helper default while
  preserving errors for conflicting non-default legacy values.
- `075e517` retains definite-parent percentage-width dependencies through
  cached-region reuse and host viewport resizing. It refreshes effective
  measurement inputs before layout, preserves `Node_ID`, removes relationships
  on replacement/retirement, and diagnoses parents that lose definiteness.
- Current tested library head: `974baf86dffa3b9732fa4a6ee45fb1e97c33a8af`.
  It includes both fixes plus the subsequent connected-tab work.

The standalone reproduction now reports `200 -> 300` for a cached 50% child
when its fixed parent changes from 400 to 600, matching a fresh runtime. The
typed 120-unit panel opens and measures 120 without a hard error. Regression
coverage includes multiple percentage children in a cached region, a nested
text child, an unrelated cached sibling, a parent losing definiteness, removal
and retirement, and fresh-runtime geometry equivalence.

`tools/test.ps1` passed on `974baf8`: 269 runtime, 37 UI, 35 theme, and 156
native tests, plus the AccessKit ABI/consumer, host foundation, restart, and
text-input checks. Reported retained sizes remain `Node=2048`,
`Description=768`, and `Paint_Command=128` bytes. These results establish
correctness and stable record sizes; they are not a p95 or allocation benchmark
for the percentage sidecar.

### Punks results/deck dogfood

Punks commit [`b6ba297`](https://github.com/samanshaiza004/punks/commit/b6ba297)
pins Alicorn `974baf8`. Its audition deck now uses explicit
`ui.sizing(height=ui.fit_content())`; metadata and transport rows, transport
buttons, and the seek slider use measured/theme control metrics. The waveform
keeps its intentional 56-unit inspection height, and the results panel keeps
the remaining-space allocation and fixed virtual-row contract.

The retained-runtime regression starts without a seek control, then adopts a
waveform and duration in one application description. The deck grows, the
results panel and virtual-list viewport shrink in that same update, and the
viewport remains at least 140 units at 960x720. All four Punks UI tests passed
against the pinned Alicorn revision; the Windows executable and runtime folder
also built successfully.

| Punks version | Explicit height declarations | Authoring/result |
| --- | ---: | --- |
| Existing source at `77ee32a` | 8 | Fixed 186-unit deck, fixed metadata/transport/button/slider heights, intentional 56-unit waveform |
| Simplified legacy candidate | 1 | Omit panel height because `ui.panel` already defaults to fit-content; keep the 56-unit waveform |
| Typed candidate at `b6ba297` | 2 | Name fit-content explicitly and keep the intentional waveform extent |

The visual correction comes from removing the fixed deck and duplicated control
heights. The typed fit declaration makes the deck's intent explicit, but is
more syntax than the simplified legacy call and resolves to the same style as
the panel helper's default. This dogfood validates intrinsic measurement and
same-update negotiation; by itself it does not prove a material advantage for
the typed constructor. The main browser still uses the clear legacy
`height=-1, grow=1` form. No `allocated()` constructor was added.

### Scratchpad font-picker dogfood

Scratchpad's working tree is at `c8a70be` and its local dependency lock points
to Alicorn `974baf8`. Its ordinary Go package checks passed. The full Alicorn
frontend run completed 200 tests: 197 passed and three connected-titlebar /
sidebar-width geometry tests failed in pre-existing uncommitted changes to
`app_layout.odin`, `connected_titlebar_test.odin`, and `main_test.odin`. The
font-picker tests were among the passing tests. Those unrelated working-tree
changes were preserved. Because the frontend run is not fully green, this is
not a final Scratchpad acceptance pass.

### Decision and remaining closure gate

The two correctness defects are resolved, and both consumers now exercise the
intended sizing behavior. The evidence supports retaining the narrow typed
fixed/fit declarations and continuing the definite-parent percentage-width
prototype. It does not yet satisfy #109's full decision gate:

- No five-process release comparison has measured p95 layout/description,
  warm allocations, sidecar capacity/peak bytes, cache hits/misses, or idle
  work for the Scratchpad percentage case and ordinary nonpercentage trees.
- The Punks candidate has deterministic geometry evidence but no native
  DPI/text-scale/theme interaction record or complete-frame p95 comparison.
- Scratchpad's full frontend suite needs a green rerun after its existing
  connected-titlebar work is resolved; native font-picker focus/theme/scale
  acceptance also remains unrecorded here.

Do not add `allocated()`, percentage height, aspect ratio, or a general solver
to close this evidence gap. The current decision is: retain the corrected
fixed/fit normalization, keep percentage width experimental pending cost and
native evidence, and defer `allocated()` unless another real consumer shows
that `height=-1, grow=1` is unclear enough to justify the extra syntax.

## Source baseline

The connected GitHub default-branch heads matched the local source inspected
when this proposal was written on 2026-10-29:

| Repository | Revision | Relevant source |
| --- | --- | --- |
| Alicorn | `829e463b16fbb8d8a73bc9f186c9f2afaf1696c3` | `ui/sizing.odin`, `ui/ui.odin`, `runtime/description.odin`, `runtime/layout*.odin` |
| Scratchpad | `bafffe62e3bd9ef7ae49a412cf63d5ad54608c5f` | font picker, settings, command palette, quick open, workbench, editor/image views |
| Punks | `77ee32abf22e6aa8ef1199a3c455a1694e127928` | `punks-standalone/odin/library_view.odin`, layout tests, appearance |

At this initial snapshot, Scratchpad pinned Alicorn `835b832` and Punks pinned
`829e463`. The dogfood update above records the later matching `974baf8` pins.

The first Scratchpad conversion is already documented in
[its sizing report](https://github.com/samanshaiza004/scratchpad/blob/bafffe62e3bd9ef7ae49a412cf63d5ad54608c5f/docs/research/ui-sizing-dogfood.md).
Its width-cap regression now tests 312, 900, then 852 logical units. Do not
repeat the earlier request to add that missing cap test; it is present.

[PanGui's layout report](https://www.pangui.io/blog/05-layout-rework-and-benchmarks/)
remains useful design context. Its timing excludes construction, allocation,
and destruction; Alicorn needs its own description, layout, and complete-frame
measurements.

## Two reproduced blockers

The standalone [research probe](../../benchmarks/diagnostics/issue109_sizing_probe.odin)
was built and run against the Alicorn baseline above. It prints observations
without treating current incorrect behavior as an acceptance pass:

```text
parent=400 child=200; parent=600 cached-child=200 fresh-child=300 regions_skipped=1
panel typed height=120 opened=false diagnostic=Invalid layout sizing ...
```

### Percentage relationships disappear during lowering

`layout_percent_width_resolve` calculates a float from the current pending
parent, and the UI helper retains only that resolved width. `region_begin`
can then reuse the descendants without evaluating their declarations again.
Changing a fixed region parent's width from 400 to 600 while keeping its
application revision unchanged leaves its 50% child at 200. A fresh tree gives
300. The parent's application content did not change; its layout input did.

This is a confirmed retained-versus-fresh mismatch. Having callers increment
region revisions after every size change would turn a framework dependency
into an application workaround. The relationship must survive cached reuse.

### Helper defaults are mistaken for explicit conflicts

`ui.panel` supplies fit-content height by default, while `resolve_sizing`
compares a typed height against the raw `Layout_Style` default of -1. As a
result, the ordinary call below fails even though the caller supplied no
legacy height:

```odin
ui.panel(ctx, sizing=ui.sizing(height=ui.logical(120)))
```

Fix this before extending the vocabulary to more helpers. A low-level exact
style and a helper's implicit defaults need different normalization inputs.

## Refreshed call-site audit

The original issue names four possible consumers. This proposal uses the two
applications requested for completion: Scratchpad and Punks. Record that audit
scope in the final issue decision. These are distinct existing sizing sites,
not 20 repetitions of the same constructor.

| # | Existing site | Current responsibility | Proposed decision |
| --- | --- | --- | --- |
| 1 | Scratchpad `editor_font_picker.odin`, panel width | Parent inner width capped at 900 | Primary percentage-width dogfood; already converted |
| 2 | Same panel, max height | `min(700, max(viewport.h-48, 1))` | Record remaining arithmetic; do not invent height expressions to remove one line |
| 3 | Same file, font results | Fixed row height and bounded visible count | Preserve virtualization contract |
| 4 | `settings_surface.odin`, outer width | Viewport width capped at 1440 | Reserve follow-up; width also drives explicit text measurement |
| 5 | Same settings panel, outer height | Viewport height capped at 1040 | Defer percentage-height capability |
| 6 | Same settings panel, navigation width | 200 times text scale | Application design metric, not a percentage |
| 7 | Same settings form width | Scrollbar lane plus wrapped-text measurement | Keep one consistent measure/render width; no cached-bounds workaround |
| 8 | `command_palette.odin`, panel | Already stretched with max width 760 | Improved legacy baseline; no compelling percentage conversion |
| 9 | Same palette, result list | Content height capped by visible rows | Preserve bounded virtual list |
| 10 | `quick_open.odin`, panel | Already max-width bounded and fit-height | No percentage required |
| 11 | Same quick-open list | Logical row-count cap | Preserve |
| 12 | `workbench_surface.odin`, startup card | Viewport-aware welcome surface | Compare existing stretch/max-width before considering another conversion |
| 13 | `app_layout.odin`, sidebar/editor split | User-adjusted split with minima | Keep split ownership; percentages would change intent |
| 14 | Same file, native titlebar tab span | Host-owned chrome exclusions and drag reserve | Keep host geometry arithmetic |
| 15 | `pinned_surface.odin`, wrapped excerpt width | Actual scroll viewport used for text shaping | Preserve source/viewport measurement contract |
| 16 | `image_preview.odin`, fit/zoom | Image dimensions, zoom, pan, DPI and assigned viewport | This is a camera/viewport operation, not evidence for a new ratio declaration |
| 17 | Punks `render_workspace`, outer panel | `height=-1, grow=1` | Typed allocated extent plus expansion candidate |
| 18 | Same workspace split | Resizable 216-wide sidebar, explicit minima | Keep split behavior |
| 19 | Main audio column | Allocated remaining height | Optional `column(sizing=...)` is justified here |
| 20 | `render_sidebar`, panel | Allocated height containing a virtual list | Same allocated-extent normalization |
| 21 | `render_results`, panel | Remaining height for bounded results | Primary Punks negotiation dogfood, with deck below |
| 22 | Results optional columns | Global viewport threshold 900 | Assigned-width adaptation is a separate concern; do not count it as a percentage benefit |
| 23 | `render_audio_deck`, panel | Fixed height 186 despite conditional content | Replace with measured content-height preference |
| 24 | Deck track metadata row | Fixed height 24 despite text/font changes | Fit row to its actual text |
| 25 | Deck transport row/buttons | Row 34 and buttons 32 | Use theme metrics and content measurement |
| 26 | Deck seek control | Fixed 30, present only with loaded duration | Use control metrics; deck recomputes when control appears |
| 27 | Deck waveform | Deliberate 56-high inspection well | Keep fixed logical height; audio has no natural aspect ratio |
| 28 | Punks result/folder rows and tabs | Fixed virtualization/tab-strip geometry | Preserve these component contracts |

## Implementation slice A: preserve the percentage dependency

Use an opt-in runtime sidecar for relative width declarations. Fixed, fit,
allocated, and expand declarations continue lowering directly to existing
fields. Do not put a sizing expression on every `Pending_Item` or `Node`.

Suggested internal representation, subject to the allocation measurements:

- A reusable pending map of percentage declarations keyed by emitted Node_ID.
- A retained map containing the relationship, fraction, and diagnostic source.
- A sparse parent-to-dependent-child index, updated during reconciliation, so
  a parent input change reaches its dependents without a global scan.
- Derived canonical width requirements cached in that optional state. These
  are layout results, never a second authoritative authored width.

The UI helper emits the normal node and stages the optional relationship for
that ID. Reconciliation adopts it only with that description. An explicitly
described ordinary node clears its former relationship. A reused region keeps
its descendants' relationships. Retirement removes both the relationship and
its dependency-index entry. Warm collections retain capacity.

Resolve a dependent's preferred width in the existing parent negotiation path
before measuring or allocating that child. Use the effective requirement in
text constraints, intrinsic measurement, min/max and main-axis allocation;
changing only arrange-time geometry is insufficient for wrapped text.
Keep the declared style and the relationship distinct from the derived result.
Evaluate the optional lookup cost on ordinary trees as well as percentage-heavy
trees. Do not replace the present pending-list search with another broad scan.

The initial proof of definiteness stays deliberately conservative:

- Root and modal overlay: the host-assigned viewport axis.
- Fixed parent: its current declared width and fixed min/max bounds, with no
  grow or compression participation on that declaration.
- Content-dependent or arbitrary allocated/growing parent: reject. A finite
  maximum or last frame's bounds is not proof of an independent size.

If a parent's policy changes from supported to unsupported, diagnose it at
the original declaration source instead of reusing an old resolved value.
Record the parent key/kind, width provenance, fraction, and resolution or
rejection reason in inspector output. No arbitrary ancestor/cross-tree lookup,
global constraint graph, or iterative layout pass is needed.

Identity remains parent + call site + key. Hash the optional declaration into
layout input identity/versioning, never into Node_ID. Changes to the effective
canonical width feed existing horizontal constraint dependencies. If a cap
keeps the effective width unchanged, wrapped-text measurement should remain a
cache hit. Palette/material-only changes should not dirty those dependencies.

Percentages still request a preferred fraction of the parent's padded inner
width. Sibling gaps are added separately; 50% + 50% + a gap can overflow.
Compression, bounds, canonical layout units and DPI snapping stay owned by the
existing allocator. Quantize logical geometry through the existing unit
conversion, not through a second DPI multiplication.

## Implementation slice B: finish helper normalization

Make helper defaults explicit inputs to normalization. A typed slot overrides
an implicit helper default. A nondefault legacy value and conflicting typed
value produce a source-located error. Equal values remain compatible. The
float-argument API cannot distinguish an explicitly repeated default from an
omitted default; document that default-valued legacy arguments are treated as
omitted. Keep the context-free exact-style normalizer's contract explicit.

Prototype one additional declaration: `ui.allocated()`, permitted only in
width/height slots. It means use the ordinary parent-assigned extent and lowers
to legacy -1. It is distinct from omission and from fit-content; weighted
main-axis growth continues to use `ui.expand(weight)`. Bounds remain fixed
logical values. This introduces no new layout strategy.

Punks currently needs both `height=-1` and `grow=1` because `ui.panel` and
`ui.column` otherwise default to fit-content height. The typed form makes that
choice explicit:

```odin
// Proposed syntax; allocated() and column(sizing=...) are not implemented yet.
fill_remaining := ui.sizing(height=ui.allocated(), grow=ui.expand(1))
if ui.column(ctx, sizing=fill_remaining, gap=8, clip=true) {
    // toolbar, growing results, content-sized deck
}
```

Add `sizing=` to `column` using the same resolver and cleanup contract as
`panel`. Extend `row` only if its actual conversion needs typed inputs; fitting
the transport row already works with its existing default. No wrapper nodes
or duplicated sizing engine. If allocated() is less clear than the improved
legacy version, reject that constructor rather than retaining it to complete a
syntactic set.

## Implementation slice C: both real applications

### Scratchpad: font picker

Preserve the existing percentage-width conversion and 312 -> 900 -> 852 cap
test. Extend its coverage to focus/selection preservation, theme metrics,
scale/RTL, relevant measurement cache behavior and fresh-runtime replay.
Repin to the landed Alicorn implementation. Keep the existing height cap as
recorded friction; do not add stored bounds, viewport fields, extra wrappers,
or a new application revision solely to make relative sizing update.

Settings is deliberately not the second primary conversion: its width is
also an input to explicit two-phase form/text measurement. Replacing the outer
width while retaining equivalent manual calculations internally would overstate
the authoring benefit.

### Punks: results and audition deck

Treat this as one vertical negotiation problem. The results receive allocated
remaining height; preserve the existing test expectations of at least 180 for
the results and 140 for their scroll viewport at supported window sizes. The
deck requests its measured content height and does not grow. Remove its fixed 186 and
ordinary control/row heights that duplicate theme or text measurement. Keep
the intentional waveform extent, fixed virtual-row heights and tab contract.
Use normal fit-height panels/rows; do not replace them with percentage height.

Exercise empty preview, selected file, populated waveform and loaded seek
control, including state changes without reopening the window. Make transport
text and controls readable when text metrics grow. If the supported minimum
window cannot fit its required targets, report/resolve that through the existing
compact-layout or minimum-window policy rather than clipping controls to keep
the old 186-height appearance.

The three comparisons for every consumer are:

1. Current shipped source.
2. Simplified legacy source with the same intended behavior as the candidate.
3. Typed candidate.

For Punks, merely omitting fixed heights can improve geometry using today's
API. That belongs in comparison 2. The typed form must independently improve
the explanation of fit versus assigned extent; it cannot claim all the visual
gain as a new algebra capability. Count real declarations/LOC, helpers, remaining
calculations and new retained application fields. Report an increase honestly.

## Validation and decision evidence

### Deterministic checks

| Case | Required result |
| --- | --- |
| Existing cached-region probe | 400 -> 600 parent yields 200 -> 300 child, identical to fresh layout, without an app revision change |
| Typed fixed panel height | Opens with height 120; default and explicit nondefault conflicts follow the documented rule |
| Fixed/fit/allocated/expand/bounds | Equal normalized legacy style and geometry; no optional retained sizing state for these forms |
| Relative declaration changed/removed; node retired | Stable identity on change; no surviving relationships for unsized/retired nodes |
| Resize, padding, cap reached/released, zero parent | Current-input geometry; no previous-frame fallback |
| More than 100%, sibling gaps, compression | Existing allocator behavior and explainable overflow |
| Max-only/content-sized/growing/compressible parent; NaN/Inf | Source/parent/axis-specific rejection, including under cached reuse |
| Text wrapping and text-scale changes | Relevant constraint/metric dependencies remeasure; unrelated sibling caches remain reusable |
| Palette/material-only theme update | No sizing-induced measurement miss |
| Root resize without descendant redescription | Retained relationship resolves correctly when the existing layout scheduling path runs |
| 1x/1.25x/1.5x/2x, RTL, nested bounded parents | Correct logical geometry, then consistent snapped output/hit regions |
| Return/break/continue and invalid scopes | Existing helper cleanup and stable identity/focus/selection |

Compare full relevant geometry, virtual ranges, retained identities, measurement
constraints and diagnostics between incremental and fresh runtimes. Do not
compare only the outer rectangle. Cover multiple relative nodes inside cached
regions and verify an unrelated region stays reusable.

### Measured cost

Add a small sizing workload to the existing benchmark infrastructure; reuse
its allocator attribution and Frame_Stats. Use frozen app-state fixtures for
the font picker and Punks deck/results. Filesystem, database, decoding, dialog
and worker timing should not contaminate sizing measurements.

Use identical compiler/toolchain, bundled fonts, input trace, host and build
configuration for legacy/candidate runs. A proposed collection protocol is five
fresh release processes per variant, at least 100 warmups and 2,000 measured
operations per scenario. Publish each process's p95 and aggregate comparison;
do not pool a favorable average or include startup in warm timing.

Collect unchanged description, retained idle, width resize below/above caps,
theme metric change, paint-only theme change, deck content change and cached
region reuse separately. Record description, measurement, allocation, layout
and complete UI-build p95; measure input-to-present and host work in native runs
separately from the headless CPU numbers.

Required counters: warm allocations/bytes by phase, sidecar count/capacity and
cold/peak bytes, Node/Pending_Item sizes, nodes visited, measure hits/misses,
text shaping, extra descriptions/passes, and idle wakes/builds/submissions.
Fixed/fit/allocated callers must acquire no new retained sidecar entries.
After capacity warmup, unchanged/repeated traces must add no allocations due
to this feature. Repeated open/close must not grow state without bound.

Use a proposed 5% p95 regression screen for equal-behavior legacy/candidate
comparisons. Repeat suspected regressions beyond measurement noise; report
inconclusive runs rather than calling them passes. Content-sensitive native
comparisons must use the same text, controls and preview state. No new idle
polling or scheduled work is acceptable.

### Native and integration acceptance

On Windows D3D12 and macOS Metal, inspect both apps at normal/narrow/large
sizes, scale settings and text scales available to the maintainer. Resize while
a picker query or Punks search field owns selection/focus, switch themes,
change preview state, and confirm geometry/hit alignment and return to idle.
Record screenshots and short action traces against exact consumer and Alicorn
revisions. Headless presentation-scale fixtures do not prove physical monitor
movement or native DPI events.

Run Alicorn's normal checks plus targeted sizing/region/measurement tests and
platform CI. Repin both consumers to the exact landed commit and run their
frontend/boundary checks and required CI. Punks' deferred native-dialog crash
investigation remains separate. Baseline audio temporary-file failures and the
parallel SQLite test failure observed during earlier work must be reported if
they recur; do not disable them or count a failed required check as green.

## Delivery order and closing record

1. Alicorn: preserve the two probes as regression assertions; fix helper default
   normalization and retain percentage dependencies. Prove ordinary-tree cost
   before broad consumer conversion.
2. Alicorn/Punks: prototype allocated() and only the helper support demanded by
   the results/deck conversion. Compare simplified legacy and typed versions.
3. Scratchpad/Punks: pin one implementation revision, complete app fixtures,
   and record true authoring differences. No application storage redesign.
4. Collect raw performance, replay, invalidation, native and idle evidence;
   publish one final decision table and the exact merged candidate checks.

Close #109 with a decision record, not this proposal. The positive gate is two
materially clearer layouts, including Punks' completed comparison, bounded local
runtime complexity, stable identity, cached/fresh equivalence, selective
measurement invalidation, acceptable cost and no new idle work. If only the
existing font picker clears that bar, say so and reject wider adoption.

Explicit per-capability outcomes in the closing comment should be:

| Capability | Intended decision, contingent on evidence |
| --- | --- |
| Theme control metrics | Retain |
| Fixed, fit height, expansion and fixed min/max normalization | Retain |
| Explicit allocated extent | Adopt only if the Punks comparison supports it |
| Definite-parent percentage width | Adopt after the retained dependency correction and evidence |
| Percentage height/relative bounds | Defer; existing height arithmetic remains visible in the report |
| Aspect ratio | No adoption now: image fit is camera behavior; waveform height is a design metric |
| Content-dependent/arbitrary allocated-parent percentages | Reject for this iteration |
| General constraint solver | Reject |

This addresses the issue's aspect-ratio question explicitly without adding an
artificial ratio requirement to either app. A later consumer can reopen that
capability with a driving-axis use case and its own acceptance tests.
