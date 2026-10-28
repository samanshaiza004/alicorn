# v0.2 release stabilization — 2026-10-23

> **Historical snapshot (2026-10-23).** Its open-gate and blocked/pending
> entries below describe the candidate state at that date, not current release
> status. #103 is now closed as completed; physical accessibility, appearance,
> DPI, input, and GPU acceptance are summarized in the
> [final acceptance matrix](../../validation/issue-103-final.md). Native packaging and SDL 3.4.18
> checks are documented in [packaging](../../packaging.md) and the dated
> [SDL validation record](sdl-3.4.18.md).

This is an initial candidate audit, not a release certification. The starting
framework revision is `d7e5441` (merged #99 and #100). #24 is complete; #27 remains
the deferred architecture roadmap. #98 is an opt-in experiment with the
[implementation and measured evidence](workbench-relief-v0.2.md) recorded separately.

## Accessibility acceptance

| Gate | Automated evidence | Outstanding acceptance |
| --- | --- | --- |
| #42 retained semantic tree | `runtime/semantics*`, semantic focus/text/range/virtualization regressions; native projection tests check incremental updates, bounded collection exports and focus/actions | Windows UIA and macOS AX exposure must be verified on real desktops; decorative relief adds no entities |
| #51 AccessKit bridge | `native/sdl_gpu/accessibility_projection_test.odin` covers role/value/action translation, static text, text selection, numeric ranges, live regions and snapshot/delta boundaries; bridge ABI/runtime separation remains intact | Narrator or NVDA and VoiceOver traversal, focus, text editing and actions; record at least one real assistive-technology session before claiming end-user support |
| #64 native appearance | `test_native_appearance_snapshot_merges_only_known_fields` and runtime appearance regressions verify known/unknown field merging, scoped invalidation and preference-aware material behavior | Toggle supported native preferences on Windows and macOS; confirm notifications update once, unchanged values cause no style update, and application returns to idle |

These issues remain open. Native text scaling remains an explicitly documented
unsupported mapping; application text scale remains supported. No new
accessibility implementation is justified by the passing structural tests alone.

## Candidate checks on this Windows machine

| Command / gate | Status |
| --- | --- |
| `tools/test.ps1` | PASS: runtime, theme and native-host regressions, restart and text-input contract |
| `tools/build_examples.ps1` | PASS: 14 examples |
| `tools/bench.ps1`, `tools/bench_text_layout.ps1` | PASS: all 25 comparable retained-work counter lines match the #24 acceptance baseline; text benchmark retains 23 nodes for one million logical items, 246 scroll shapes and 362 width-reflow shapes |
| `tools/bench_material.ps1` | PASS: canonical flat equality, bounded relief geometry at 100/125/150/200% |
| Scratchpad native test/build and three D3D12 appearance smokes | PASS: 13 bridge and 161 frontend tests, successful publication/wake/shutdown |
| `tools/build_native_release.ps1 -SDLLinkage Shared` | PASS: import audit, bundled SDL, empty-directory launch smoke |
| `tools/build_native_release.ps1` (static default) | BLOCKED: missing CMake build prerequisite; no dependency installed or upgraded |
| Native input D3D12 foundation executable | BLOCKED: foreground focus/text-input activation could not be established in this automated session |
| Physical Windows AT, IME and mixed-DPI displays | BLOCKED: desktop/hardware validation needed |
| macOS foundation, packaging, signing/lifecycle, VoiceOver, native preference changes | Pending CI and macOS desktop evidence; Windows success does not establish these |

## Release recommendation

Raw outputs: [retained](../../benchmarks/raw/workbench-relief-windows-2026-10-23-retained.txt),
[text layout](../../benchmarks/raw/workbench-relief-windows-2026-10-23-text.txt),
[material](../../benchmarks/raw/workbench-relief-windows-2026-10-23-material.txt).

Do not label or publish a v0.2.0 release candidate yet. Finish the physical
accessibility sessions, recover the foreground-focus native input run, obtain
green static and shared packaging checks and macOS CI, then perform the desktop
cross-display, IME and lifecycle checklist. A passing CI build does not close
the real assistive-technology gates. No additional layout mechanism is needed
to advance this sequence.
