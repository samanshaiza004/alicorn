# Changelog

All notable Alicorn releases are recorded here. The project release notes are
consolidated in this file; vendored components retain their own upstream
changelogs.

## [Unreleased]

### Added

- Added opt-in magnetic horizontal drag tracking for tab bars, with a vertical
  tear-off threshold, reattachment hysteresis, constrained reorder hit testing,
  and raw pointer coordinates preserved for host decisions.

### Fixed

- Restore macOS trackpad momentum scrolling in the SDL host while preserving
  SDL environment overrides.

---

## [0.2.1] — 2026-11-06

Alicorn remains an experimental native GUI runtime for Odin. This release
collects the merged runtime, authoring, native-host, rendering-test, build, and
performance work after v0.2.0.

Compare: [v0.2.0...v0.2.1](https://github.com/samanshaiza004/alicorn/compare/v0.2.0...v0.2.1)

### Highlights

- Retained motion now has generation-checked targets, intent-based authoring,
  reduced-motion handling, per-window scheduling, replay/causal diagnostics,
  and native Windows move/minimize lifecycle handling.
- Connected document tabs share a consistent curved silhouette, support live
  reorder previews and motion indicators, and use a font-independent close
  affordance while preserving the existing hit targets.
- Layout invalidation traces retain structured causes and format diagnostic
  text only when inspected. This preserves diagnostic output while reducing
  construction work and allocations.
- Alicorn includes a bounded test-only CPU paint reference renderer and a
  Windows/macOS GPU comparison corpus for the supported paint subset.

### Added

- Added lexical UI key scopes, actionable identity diagnostics, explicit
  virtual-list focusability, and a text-buffer update helper.
- Added native lifecycle breadcrumbs as an opt-in diagnostic, a native OS file
  drag service, and content-owned scroll focus visuals.
- Added typed size declarations for the demonstrated fixed/fit/expansion and
  definite-parent percentage-width cases. Percentage widths remain opt-in and
  broader sizing research remains deferred.
- Added analytic residual motion response, generation-safe retained targets,
  per-window presentation scheduling, reduced-motion intent controls, and
  causal diagnostics/replay. Tab bars can expose motion indicator owners and
  render live browser-style reorder previews.
- Added a bounded, headless CPU reference for flat integer-aligned rectangles,
  stationary clipping, integer translation, opacity, and per-pass RGBA8
  source-over quantization. Unsupported operations return typed diagnostics;
  the production renderer and app-facing paint APIs are unchanged.
- Moved the reusable Odin AccessKit binding to the standalone
  [odin-accesskit](https://github.com/samanshaiza004/odin-accesskit) dependency.

### Fixed

- Corrected typed panel sizing precedence and retained definite-parent
  percentage dependencies across cached-region reuse and viewport resizing.
- Fixed motion owner isolation and release, coherent inspector velocity
  samples, and local clips moving with animated subtrees.
- On Windows, avoid tight SDL timeout retries; suspend motion while minimized;
  advance motion during native move loops; stop the move timer after settling;
  and service every window during a move loop. Added secondary-window lifecycle
  regressions for motion.
- Filled editor row-selection backgrounds for hard line-break/control rows.
- Refined connected-tab close painting with a centered font-independent icon,
  contrast-aware ink, and hover treatment kept inside the tab contour; dirty
  markers and close hit targets remain intact.
- Corrected helper-default normalization and cached percentage sizing bugs
  discovered during the #109 Scratchpad/Punks experiment.

### Performance and measurement

- PR [#159](https://github.com/samanshaiza004/alicorn/pull/159) replaces five
  eagerly formatted invalidation reasons with structured events and lazy,
  cached formatting. On the Apple M1 comparison, median end-frame CPU fell
  21.5% for 10,000 containers, 15.6% for 10,000 short-text nodes, and 24.6%
  for the 100-panel form; approximately 30,000 persistent allocation calls
  were removed per 10,000-node workload. The exact trace text and event order
  remain covered by regressions.
- PR [#160](https://github.com/samanshaiza004/alicorn/pull/160) completes
  bounded construction-cost attribution. Remaining retained measurement and
  geometry costs were accepted based on the recorded workload evidence rather
  than prompting a speculative allocator or data-layout rewrite.
- The matched Windows candidate scorecard measured lower construction time
  across four synthetic workloads. Its Scratchpad nine-action workload showed
  a paired median 6.19% reduction in cumulative app-build callback time;
  first submission, process CPU, and peak working set were effectively flat.
  The separate macOS Scratchpad comparison recorded an 8% callback-time
  improvement with process CPU and peak RSS flat.
- These are workload- and machine-specific results, not universal performance
  guarantees. Active native frame p99, continuous resize/input responsiveness,
  DPI/refresh transitions, and a comparable second-GPU-backend performance run
  remain outside the recorded benchmark coverage. See the
  [performance scorecard](docs/benchmarks/performance-scorecard-v0.2.1-windows-2026-11-04.md).

### Validation

- PR [#161](https://github.com/samanshaiza004/alicorn/pull/161) passed its
  Windows D3D12 and macOS Metal CPU/GPU comparison suites: 156 targeted cases,
  32 generated scenes, and a permanent minimized clip/translation regression
  on each backend, at 2/255 per-channel tolerance. The CPU renderer is test
  support only and intentionally does not model fractional geometry, non-unit
  DPI, antialiasing, rounded surfaces, text, icons, images, or materials.
- The Odin dev-2026-11 migration record reports Windows validation with
  317 runtime, 39 UI, 35 theme, 168 native SDL GPU, 6 scroll/capture, and
  1 accessibility-contract tests passing, along with examples, AccessKit ABI,
  package smoke, and atomic-access checks. The report also marks macOS/Linux
  physical behavior, Intel macOS execution, and local static-SDL packaging
  without CMake as unverified.
- Windows and macOS performance reports are separate experiments. Their
  measurements must not be combined as if they were a single cross-platform
  run. The complete evidence and limits are indexed in
  [validation](docs/validation/README.md) and
  [benchmarks](docs/benchmarks/README.md).

### Dependencies and toolchain

- Odin baseline: dev-2026-11. The checked migration evidence uses the Windows
  archive compiler dev-2026-11-nightly:9a69916.
- The native host remains on SDL 3.4.18; text shaping/rasterization remains
  on vendored Runa 1.5.3; the AccessKit C ABI remains 0.23.1. The Odin
  binding is now pinned separately in dependencies/odin-accesskit.json.
- Linux font fallback continues to use Fontconfig. Linux has no AccessKit
  adapter, and this release does not claim broad Linux desktop validation.

### Scope and known limitations

- v0.2.1 includes the already merged typed fixed/fit-height and
  definite-parent percentage-width behavior. It does not expand layout
  resizing into percentage height, intrinsic fit width, arbitrary relative
  constraints, aspect-ratio solving, or a general constraint solver. Broader
  layout-resizing work is deferred to a future pass; see the v0.3.0
  [#109 research record](docs/research/issue-109-completion-plan.md).
- Alicorn remains experimental and API-unstable; this release does not promise
  production readiness or long-term API compatibility.
- The CPU reference renderer is deliberately bounded test support, not a
  general software renderer.
- Windows and macOS native acceptance is limited to the exact reports and
  commits cited above. This release does not certify every OS version, driver,
  display scale, assistive technology, or GPU.
- macOS development packages are ad-hoc signed, not Developer ID signed or
  notarized. Distribution signing, installers, updates, and notarization remain
  application-release responsibilities.

### Merged pull requests

- [#159 — Defer layout trace formatting until inspection](https://github.com/samanshaiza004/alicorn/pull/159)
- [#160 — Complete Issue #157 construction attribution](https://github.com/samanshaiza004/alicorn/pull/160)
- [#161 — Add a bounded CPU paint reference for #90](https://github.com/samanshaiza004/alicorn/pull/161)
- [#176 — Refine the connected-tab close affordance](https://github.com/samanshaiza004/alicorn/pull/176)

### Complete commit ledger

Every commit from the v0.2.0 tag through the v0.2.1 source baseline
072aaf5a29e97f5dad6296dff84835f9f707fcbf is listed below: 60 implementation,
test, build, research, benchmark, and validation commits.
- [6aba0b2](https://github.com/samanshaiza004/alicorn/commit/6aba0b2bdbbc0a02147958a65679191103a8e0ed) — feat(ui): add lexical key scopes and actionable identity diagnostics
- [7980c0d](https://github.com/samanshaiza004/alicorn/commit/7980c0d27fec6ff2aff53e4641b2d90137e5303a) — feat(ui): bridge native lifecycle and scoped virtual lists
- [1d20f30](https://github.com/samanshaiza004/alicorn/commit/1d20f308643d9a2900d0c26a90137b4d8e5850d7) — feat(ui): prototype theme metrics and typed sizing
- [b78d834](https://github.com/samanshaiza004/alicorn/commit/b78d834d698b1b30507523f823317e9972315f17) — feat(ui): prototype definite percentage widths
- [0792ecd](https://github.com/samanshaiza004/alicorn/commit/0792ecda71a5d21013fe90d9bbe658f6fbb1a65e) — feat(ui): support percentage sized panels
- [835b832](https://github.com/samanshaiza004/alicorn/commit/835b8322b128ae4b84090206b96fd224aea7549b) — docs(ui): show percentage overflow with sibling gap
- [046c9cd](https://github.com/samanshaiza004/alicorn/commit/046c9cd2c55f5750dc075b8c1893d129be930cb3) — feat(ui): expose virtual list focusability
- [0f842c7](https://github.com/samanshaiza004/alicorn/commit/0f842c73ed297a6594c0d7389403b6260953b8da) — feat(ui): expose text buffer update helper
- [829e463](https://github.com/samanshaiza004/alicorn/commit/829e463b16fbb8d8a73bc9f186c9f2afaf1696c3) — feat(native): add opt-in persistent lifecycle breadcrumbs
- [006871f](https://github.com/samanshaiza004/alicorn/commit/006871f3f3e7347dc745b964c410dc027ddaffd4) — docs(layout): propose issue 109 completion with app evidence gates
- [21a91a9](https://github.com/samanshaiza004/alicorn/commit/21a91a99569c080abeed85107f51eac7f7063b64) — fix(ui): let typed panel sizing override helper defaults
- [075e517](https://github.com/samanshaiza004/alicorn/commit/075e5176821d2a04e9791eb76107b0c16d2e8981) — fix(layout): retain percentages through cached regions
- [974baf8](https://github.com/samanshaiza004/alicorn/commit/974baf86dffa3b9732fa4a6ee45fb1e97c33a8af) — feat(tabs): unify connected tab silhouettes
- [6d1cdae](https://github.com/samanshaiza004/alicorn/commit/6d1cdaecca09d18c3aa1221d71580b34b8faf1bc) — docs: record issue 109 dogfood results
- [29c5f6b](https://github.com/samanshaiza004/alicorn/commit/29c5f6baeaa93926b533f5cb48a97fca4a5e36db) — docs: record issue 109 sizing dogfood evidence
- [01d9253](https://github.com/samanshaiza004/alicorn/commit/01d925303d8198e6969b64dceeb774261134a2b1) — docs: close issue 109 research decision
- [bd0dd59](https://github.com/samanshaiza004/alicorn/commit/bd0dd594609599a81aa2662759522770d71339d2) — Move AccessKit Odin binding to standalone dependency
- [f49562c](https://github.com/samanshaiza004/alicorn/commit/f49562c442e0140ebdf996d993b510b0a511d089) — feat(motion): add analytic residual response math
- [4c2873f](https://github.com/samanshaiza004/alicorn/commit/4c2873f2b7c29bc58b3f8068b1a8624afe55d78f) — feat(motion): add generation-safe retained targets
- [78295ff](https://github.com/samanshaiza004/alicorn/commit/78295ffe8348d0d63744c20a4330ac9df3fb398f) — fix(motion): isolate runtime handles and release owners
- [84edd5e](https://github.com/samanshaiza004/alicorn/commit/84edd5e3aae071176e115eaf96e11605ea503232) — feat(motion): schedule retained presentation per window
- [7ed32c2](https://github.com/samanshaiza004/alicorn/commit/7ed32c2c98303677e618fb9797a145756c59816b) — test(motion): clarify bounded window fallback
- [9690333](https://github.com/samanshaiza004/alicorn/commit/9690333ea5dbe335737d59a1c0bfb331edd3ee44) — feat(motion): add intent-based authoring and reduced motion
- [82e415d](https://github.com/samanshaiza004/alicorn/commit/82e415d39d1b265024bc366c2df9563a06e70241) — feat(motion): add causal diagnostics and replay
- [e93ac0d](https://github.com/samanshaiza004/alicorn/commit/e93ac0d58ed3ccfbc4617691a8c3bc9b0073279a) — fix(motion): keep inspector velocity sample-coherent
- [92ad5dd](https://github.com/samanshaiza004/alicorn/commit/92ad5dd1e4df471919ec86142d106cfb0f477ebb) — docs(validation): record motion diagnostics overhead
- [d9e3c88](https://github.com/samanshaiza004/alicorn/commit/d9e3c8827c0375ec84c1aa7ae3871c5677fb354c) — docs(validation): note hosted CI status limitation
- [7b637a5](https://github.com/samanshaiza004/alicorn/commit/7b637a5eeb2d0bb8317ccf8e7a64835d6a97417c) — feat(native): add OS file drag service
- [772ac45](https://github.com/samanshaiza004/alicorn/commit/772ac4546ef81d3282969b993e67cc07dd0c390d) — test(motion): cover native interrupted settling
- [01b6b34](https://github.com/samanshaiza004/alicorn/commit/01b6b34ded7a41297eac637f9c1b5b2fb3c517e8) — docs(validation): record Windows motion smoke
- [719029f](https://github.com/samanshaiza004/alicorn/commit/719029f5f9d171879d38475a991ab9e6f09a90d6) — docs(validation): confirm motion CI results
- [5f7913b](https://github.com/samanshaiza004/alicorn/commit/5f7913b15f6ace26917d2b7322db63f16eb6393f) — fix(native): avoid tight SDL timeout retries on Windows
- [45c9f48](https://github.com/samanshaiza004/alicorn/commit/45c9f4846064725582906a8c9cbd71d2ba358e01) — docs(validation): record Windows wait-loop findings
- [cf3f0b4](https://github.com/samanshaiza004/alicorn/commit/cf3f0b4db60bf70b1ac1511c8c0d5871f7f2852f) — docs(validation): record Windows motion lifecycle
- [4e6ac10](https://github.com/samanshaiza004/alicorn/commit/4e6ac10d51e3746b3e84cae30d95a5c71f70666e) — fix(native): suspend motion for minimized Win32 windows
- [ccc9a66](https://github.com/samanshaiza004/alicorn/commit/ccc9a66d95580cae94635d3da7e18b7d17523fa8) — docs(validation): record active motion restore on Windows
- [c01c149](https://github.com/samanshaiza004/alicorn/commit/c01c149070616fa292c131a5f2295d9035ac5d4e) — test(native): validate secondary-window motion lifecycle
- [06e93ea](https://github.com/samanshaiza004/alicorn/commit/06e93ea30c10e175586768bc4ed8523e4201def4) — docs(validation): record secondary window motion results
- [7f697c5](https://github.com/samanshaiza004/alicorn/commit/7f697c5d4761eebfc439da7bbf5f0bc3a1dcdcfb) — fix(native): advance motion during Windows window moves
- [d0595a7](https://github.com/samanshaiza004/alicorn/commit/d0595a7594d73b90002dab7f8797fc36d043625e) — docs(validation): add Windows move-loop acceptance
- [35d3953](https://github.com/samanshaiza004/alicorn/commit/35d395327eceeb6f1fd22c92e8dc66547df02cba) — fix(native): stop move timer at motion settlement
- [08ff726](https://github.com/samanshaiza004/alicorn/commit/08ff726db59bbd0ece247fb2e326aa994a3ecdcd) — docs(validation): record move timer settlement behavior
- [1a1cff7](https://github.com/samanshaiza004/alicorn/commit/1a1cff797c88d0e0cf52eea63834a635d71666ad) — fix(native): service motion in all windows during move loop
- [b257f4f](https://github.com/samanshaiza004/alicorn/commit/b257f4fd714e07858f7260fefbbddd7b16cde3c4) — docs(validation): record dual-window move observation
- [1e207dd](https://github.com/samanshaiza004/alicorn/commit/1e207dd3f533bca79fa099f3dd90b244967e8426) — feat(tabs): expose motion indicator owners
- [54aec2c](https://github.com/samanshaiza004/alicorn/commit/54aec2cf22e1fccf8de2d63cec347b1f57aa02ad) — feat(motion): complete causal inspector replay gaps
- [571db7b](https://github.com/samanshaiza004/alicorn/commit/571db7b3d306eab4cd7753f37324c8271b4e91da) — docs(motion): record issue 144 failure-path audit
- [403e775](https://github.com/samanshaiza004/alicorn/commit/403e7751a0543c43efd3bac0f1ab5e4a932203c6) — test(runtime): add seeded invalidation coherence oracle
- [06daa41](https://github.com/samanshaiza004/alicorn/commit/06daa41350472aba20bd68c6d3cb51e8e30592fa) — feat(runtime): add browser-style live tab reorder previews
- [1fd3779](https://github.com/samanshaiza004/alicorn/commit/1fd3779907b845ff03287e0b7e10418fe3ccedc2) — fix(motion): move local clips with animated subtrees
- [0349be5](https://github.com/samanshaiza004/alicorn/commit/0349be5c0127a1e65d07ff515d8b796f1b0d72e4) — feat: support content-owned scroll focus visuals
- [5930abb](https://github.com/samanshaiza004/alicorn/commit/5930abbe3a4d813ce4fdceccc9882f44b31287a5) — fix(text): fill editor row selection backgrounds
- [1fde82b](https://github.com/samanshaiza004/alicorn/commit/1fde82b324be957ee685a5b7b3ce0fffef19bf3b) — build: adopt Odin dev-2026-11
- [fe8967f](https://github.com/samanshaiza004/alicorn/commit/fe8967f08fed8b29e7cd27d5989f52b7a85f405c) — fix(build): correct Odin macOS archive checksum
- [067ff0c](https://github.com/samanshaiza004/alicorn/commit/067ff0c73551821474c30fc12d0eea2dea4a3009) — perf: defer layout invalidation trace formatting
- [736277f](https://github.com/samanshaiza004/alicorn/commit/736277f899b7777d0cf907a1b7c962370d7217b0) — perf: complete Issue #157 construction attribution
- [bafe2fa](https://github.com/samanshaiza004/alicorn/commit/bafe2fa6db6b49c404538d63756b32590566d89a) — docs: record v0.2.1 Windows performance benchmarks
- [c6eb8fe](https://github.com/samanshaiza004/alicorn/commit/c6eb8fe6fd0c6229cafb2f2d2592876ca786a6cc) — docs: record matched Windows Scratchpad benchmarks
- [a2f1be0](https://github.com/samanshaiza004/alicorn/commit/a2f1be071d3856a7c356025f98cc415a6c09c600) — test(renderer): add bounded CPU paint reference for #90
- [072aaf5](https://github.com/samanshaiza004/alicorn/commit/072aaf5a29e97f5dad6296dff84835f9f707fcbf) — style: refine tab close affordance

---

## Alicorn v0.2.0

Alicorn is an experimental native GUI runtime for Odin. Applications describe
interfaces with ordinary Odin code; Alicorn retains identity, interaction,
layout, text, semantics, and rendering products between updates. v0.2.0 keeps
that model and adds a simpler authoring surface, more capable layout and
controls, native accessibility on Windows and macOS, and reusable native-app
packaging tools.

This changelog summarizes the changes from [v0.1.0 to v0.2.0](https://github.com/samanshaiza004/alicorn/compare/v0.1.0...v0.2.0).
It groups related fixes and features instead of repeating merge commits.

### Highlights

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

### Changelog

#### Added

- Added `alicorn:ui`, a concise procedural API for ordinary application
  composition, controlled text fields, pointer-bound checkboxes and sliders,
  icon controls, automatic informational-text semantics, interaction results,
  and common layout helpers. The form example imports only this package;
  repeated data retains stable explicit-key support. The focused form lesson
  uses bare widget calls, with icon examples in a separate Control Gallery.
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

#### Changed and improved

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

#### Fixed

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

#### Performance and validation

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

### Dependencies and platform baseline

- Native host and release packaging pin **SDL 3.4.18**.
- Text shaping, segmentation, line breaking, and rasterization use vendored
  **Runa v1.5.3**.
- Windows/macOS accessibility uses **AccessKit C 0.23.1**, with a reusable
  Odin binding in this repository.
- The tested Odin compiler is **`dev-2026-09-nightly:a2fb372`**.
- Linux glyph fallback uses the system **Fontconfig** facilities. Linux native
  support has only a conditional NixOS/Mango validation record and has no
  AccessKit adapter.

### Tested platforms

Physical validation is recorded for **Windows 10 22H2 x64 with Direct3D 12**
and **macOS 27.0 on Apple M1 with Metal**. The final acceptance matrix records
foreground input, IME, mixed-DPI movement, lifecycle, appearance changes, and
real screen-reader checks, including modal boundaries and virtualized content.
Some per-session reader/IME versions, display scales, and action traces were
not supplied; see the [acceptance matrix](docs/validation/issue-103-final.md)
for the exact evidence boundaries. This is focused validation, not a claim of
support for every OS version, device, GPU driver, or assistive technology.

### Experimental status and known limitations

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

### Release artifacts

v0.2.0 is a **source/toolkit release**. It does not include prebuilt example
applications. Follow [Getting Started](docs/getting-started.md) to build the
examples, and the [packaging guide](docs/packaging.md) to package an application.

---

## Alicorn v0.1.0

Alicorn is an experimental native GUI runtime for Odin. This first release
provides a small retained UI runtime and an SDL3/SDL_GPU native host, with
application state kept in ordinary Odin code.

### What’s included

- Procedural UI descriptions with retained identity, layout, focus, and
  interaction state.
- Common controls and text input, plus native-host keyboard, pointer, window,
  and menu integration.
- Keyed virtual lists, retained regions, and bounded custom GPU surfaces for
  larger collections and visualization workloads.
- An opt-in visual inspector for the retained tree, focus, runtime work, and
  recent causes; the host also provides a runtime HUD and diagnostic captures.
- A five-step example progression from a native window and controls through
  asynchronous virtual lists, custom surfaces, and the inspector.

Start with [Getting Started](docs/getting-started.md), then see the
[application guide](docs/guide.md), [API reference](docs/reference.md),
[examples](examples/README.md), and [native diagnostics guide](docs/development.md#native-diagnostics).

### Platform validation

The native path has been exercised on Windows and macOS. Checked-in validation
records include Windows 10 22H2 and macOS 27.0 on Apple silicon. Linux has a
conditional validation record for one NixOS 26.11/Mango 0.16.2 machine; it is
not broad Linux support or certification across OS versions, hardware, or GPU
drivers. See the [Linux validation record](docs/validation/linux-nixos-mangowc-2026-10-23.md).

### Experimental status and limitations

This release is **not production-ready**. Alicorn is experimental, its public
API is not frozen and may change, and the available widget set is intentionally
small. v0.1.0 does not promise a full-featured toolkit or long-term production
API stability.

Keyboard focus and operation, semantic focus identities, and native text-input
composition are supported. They are not a platform accessibility bridge:
Alicorn does not expose its GPU-rendered controls as Windows UI Automation or
macOS Accessibility/NSAccessibility elements, so screen readers cannot inspect
or operate that control tree.

The native starter scripts are development workflows, not a general app
packager. Windows development currently stages SDL3 beside the executable;
macOS development links the installed SDL3 library. v0.1.0 does not provide a
first-party self-contained app bundle, installer, signing, or notarization
pipeline. Those deployment responsibilities remain with each application for
now; reusable SDL/runtime packaging belongs with Alicorn's native-host tools,
not Caliber's frontend-neutral ABI layer.

### Performance evidence

The published measurements are author-run, workload-specific observations,
not cross-framework comparisons or general performance guarantees. They cover
focused text-layout workloads and retained-work tests on Windows and macOS,
plus bounded native-host samples. See the [performance evidence index](docs/performance.md)
for methodology, platform reports, raw captures, and limitations.
