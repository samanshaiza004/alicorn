# Alicorn v0.2.0

Alicorn is an experimental native GUI runtime for Odin. Applications describe
interfaces with ordinary Odin code; Alicorn retains identity, interaction,
layout, text, semantics, and rendering products between updates. v0.2.0 keeps
that model and adds a simpler authoring surface, more capable layout and
controls, native accessibility on Windows and macOS, and reusable native-app
packaging tools.

This changelog summarizes the changes from [v0.1.0 to the release-candidate
tree](https://github.com/samanshaiza004/alicorn/compare/v0.1.0...3e31c743298f758b4cafd4f425e296a59cd95e34).
It groups related fixes and features instead of repeating merge commits.

## Highlights

- **Direct to write, retained to run.** The new `alicorn:ui` package lets
  applications write controls and interactions procedurally while preserving
  ordinary Odin application state and the retained runtime underneath.
- **A broader native application surface.** Alicorn now has composite tabs,
  adaptive and elastic layout, richer text editing, secondary windows, and
  integrated titlebar/menu options.
- **Accessible GPU-rendered controls.** Windows UI Automation and macOS
  Accessibility receive semantic controls and text interaction through
  AccessKit; the controls remain Alicorn-rendered rather than native text
  widgets.
- **Measured retained work.** The runtime continues to avoid work on idle and
  preserve localized updates. The final Windows benchmark refresh is recorded
  in the [performance report](docs/benchmarks/performance-final-windows-2026-10-28.md).

## Changelog

### Added

- Added `alicorn:ui`, a concise procedural API for ordinary application
  composition, controlled text fields, pointer-bound checkboxes and sliders,
  icon controls, automatic informational-text semantics, interaction results,
  and common layout helpers. The form example imports only this package;
  repeated data retains stable explicit-key support.
- Added a composite `Tab_Bar` with selected and dirty states, an integrated
  close action, hover and pressed treatment, shrink-to-fit and overflow
  behavior, active-tab visibility, reorder feedback, and keyboard navigation.
- Added Checkbox and Slider recipes, accessible Select and notice controls,
  delayed tooltips, and opt-in analytic raised/recessed materials and button
  relief.
- Added adaptive regions; elastic Row/Column allocation; bounded retained
  Grid layout; content-sized and fit-content sizing; retained leaf measurement;
  and typed measurement dependencies with inspector explanations.
- Added scoped theme, density, text-scale, and accessibility-appearance
  environments. Added a typed design-token/theme compiler, static Odin theme
  generation, component recipes, retained computed styles, and composable
  visual parts.
- Added renderer-neutral paint commands so component composition and style
  output are separate from native GPU drawing.
- Added secondary native windows on Windows and macOS, durable UI restoration
  hooks, and integrated client-area menus/titlebar controls on Windows. Added
  integrated titlebar tabs on Windows and macOS.
- Added native accessibility appearance detection for increased contrast,
  reduced motion, reduced transparency, and color differentiation where the
  platform reports support. Added Windows system text-scale import.
- Added the bounded semantic accessibility core and an experimental AccessKit
  bridge for Windows UI Automation and macOS Accessibility. The bridge covers
  common controls, tabs, static text, text runs, selection, editing actions,
  keyboard focus, modal boundaries, and bounded virtual collections.
- Extracted a reusable Odin AccessKit package with typed nodes/actions,
  explicit ownership-transfer APIs, platform adapters, and an ABI contract
  probe against AccessKit C 0.23.1.
- Added asynchronous image decoding with runtime-owned adoption, corrected SDR
  image color handling, and added compiled Reicon mask atlases with
  cross-platform generation/reproducibility checks.
- Added Linux per-glyph font fallback through Fontconfig and native acceptance
  tooling for a documented NixOS/Mango environment.
- Expanded diagnostics with nonmodal visual inspection, mutation invalidation
  causes, typed measurement traces, package provenance, and more focused native
  fixtures and regression checks.
- Added native application packaging and dependency-audit tools. These can
  build Windows applications with static SDL linkage and construct/audit
  macOS `.app` bundles.

### Changed and improved

- Text fields now expose controlled value APIs and interaction state, with
  content geometry and typography, caret/selection support, clipboard
  integration, IME composition, and shared pointer/text-interaction logic.
- Text measurement and layout now track relevant metric dependencies so density,
  text scale, and content-size changes invalidate the affected measurements
  without treating every style change as a full layout change.
- Tab close visibility and dirty markers share a stable trailing slot; hover
  work is scoped to the tab subtree so close-state changes do not reflow the
  bar or traverse unrelated UI.
- Image decoding and runtime adoption have separate ownership/lifecycle paths;
  native diagnostics preserve pixel channel order and SDR color encoding.
- Windows and macOS build/package scripts now report resolved toolchain and
  architecture details, verify native dependency assumptions, and provide
  clearer failure output.
- Moved the interactive macOS package-launch acceptance app and result protocol
  out of `01_hello` into a dedicated fixture, keeping the starter focused on
  ordinary application state and controls.

### Fixed

- **Windows native chrome and menus:** corrected caption button alignment,
  full-edge close hover and hit testing, hover contrast, popup-cancel state,
  F10 DevTools handling, and redraw wakeups. Kept editor hit-testing separate
  from native frame areas and preserved the window position when pointer
  tracking begins.
- **macOS input and titlebars:** preserved pointer-button identity through
  release, mapped Control-click to context-click, corrected fullscreen/titlebar
  geometry and lifecycle, and kept shortcut key storage alive for native
  callbacks.
- **Multiple windows and text input:** fixed Darwin shared-host inclusion,
  cross-window text-input state/diagnostics, secondary-input backpressure, and
  region identity handling. Added regression coverage for secondary-window
  interaction and close/reopen behavior.
- **Accessibility contracts:** aligned tab collection positions with the
  platform's zero-based set indexing; preserved the first item's position;
  unified action payloads across platforms; corrected Windows AccessKit hash
  setup; and enforced modal/disabled action eligibility for semantic requests.
- **System appearance:** corrected Windows reduced-transparency detection and
  WinRT activation, and made native preference changes update the inherited
  appearance input without overriding application-scoped values.
- **Text and layout correctness:** preserved text-change ownership without a
  runtime, guarded nested adaptive presentation changes, corrected RTL Grid
  end alignment, retained fit-content cross sizing, and fixed split-drag event
  routing and diagnostics.
- **Rendering and assets:** preserved SDR color encoding and diagnostic
  swapchain channel order, validated source-over blending, normalized shader
  hashes across platforms, checked generated icon pixels, and removed an unused
  icon stroke-width API.
- **Packaging:** corrected static SDL link requirements and Windows CRT
  alignment, validated macOS binary architecture and desktop launch, and fixed
  Windows/macOS packaging probes and workflow toolchain selection.
- Closed additional runtime correctness findings in retained layout, input,
  styles, semantics, images, and lifecycle paths; the related checks are part
  of the Windows/macOS foundation and native-packaging workflows.

### Performance and validation

- Removed redundant semantic-focus node visits when no realized semantic focus
  exists, and skipped virtual-collection pruning scans when no collection was
  touched. The relevant counters and regression tests verify the bounded work.
- Preserved idle behavior: the 10,000-node retained-work fixture completed
  10,000 idle frames with zero allocations or reconciliation/layout/paint/
  composition work and zero GPU submissions.
- In the final matched Windows `-o:speed` rerun, all five retained-work median
  timings were lower than the October 27 post-merge medians. The largest
  reductions were 13.7% for a 10,000-node root invalidation with one changed
  value, 11.9% for reuse of a retained 10,000-node subtree, and 5.1% for a
  changed 100-node region. The one-million-item virtual-list result was
  effectively unchanged. These are same-machine, three-process observations;
  the runtime source did not change between captures, so they are not attributed
  to a new optimization. Text and material timings remain within overlapping
  ranges. See the [full methodology, ranges, and raw capture](docs/benchmarks/performance-final-windows-2026-10-28.md).
- The earlier release-candidate workflows passed Windows foundation, macOS
  foundation, native packaging, and icon reproducibility checks on implementation
  commit `e00b966`: [Windows foundation](https://github.com/samanshaiza004/alicorn/actions/runs/40631856576),
  [macOS foundation](https://github.com/samanshaiza004/alicorn/actions/runs/40631856709),
  [native packaging](https://github.com/samanshaiza004/alicorn/actions/runs/40631856629),
  and [icon reproducibility](https://github.com/samanshaiza004/alicorn/actions/runs/40631856602).
  The later authoring-experience follow-up is covered by the Windows `tools/check.ps1`
  run and the hosted workflows for its exact commit; do not treat the earlier
  candidate runs as validation for this follow-up. The physical acceptance
  details are in the [candidate validation record](docs/validation/issue-103-final.md).

## Dependencies and platform baseline

- Native host and release packaging pin **SDL 3.4.18**.
- Text shaping, segmentation, line breaking, and rasterization use vendored
  **Runa v1.5.3**.
- Windows/macOS accessibility uses **AccessKit C 0.23.1**, with a reusable
  Odin binding in this repository.
- The tested Odin compiler is **`dev-2026-09-nightly:a2fb372`**.
- Linux glyph fallback uses the system **Fontconfig** facilities. Linux native
  support has only a conditional NixOS/Mango validation record and has no
  AccessKit adapter.

## Tested platforms

Physical validation is recorded for **Windows 10 22H2 x64 with Direct3D 12**
and **macOS 27.0 on Apple M1 with Metal**. The final acceptance matrix records
foreground input, IME, mixed-DPI movement, lifecycle, appearance changes, and
real screen-reader checks, including modal boundaries and virtualized content.
Some per-session reader/IME versions, display scales, and action traces were
not supplied; see the [acceptance matrix](docs/validation/issue-103-final.md)
for the exact evidence boundaries. This is focused validation, not a claim of
support for every OS version, device, GPU driver, or assistive technology.

## Experimental status and known limitations

- Alicorn remains **experimental and API-unstable**; this release does not
  promise production readiness or long-term API compatibility.
- Accessibility is not comprehensive WCAG or platform conformance. Linux has
  no screen-reader adapter, and some less common widgets/context menus may have
  incomplete semantics.
- The blend readback suite covers offscreen RGBA8 targets; it does not validate
  every native swapchain format or display color-management path.
- macOS packages are locally ad-hoc signed, not Developer ID signed or
  notarized. Signing, notarization, installers, updates, and distribution are
  the application's release responsibility.
- No process-memory high-water/leak comparison or representative Scratchpad
  stress benchmark was completed for this candidate. Headless timings do not
  measure GPU residency or native startup/interactive latency.

## Release artifacts

v0.2.0 is a **source/toolkit release**. It does not include prebuilt example
applications. Follow [Getting Started](docs/getting-started.md) to build the
examples, and the [packaging guide](docs/packaging.md) to package an application.
