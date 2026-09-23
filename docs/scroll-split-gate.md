# Retained scrollbars and split panes: dogfood gate

## Contract

- `Scroll_Region` owns solid Auto scrollbars on enabled axes. Their strips
  reduce the effective viewport used for clipping and fixed-row realization;
  two visible bars reserve a corner. Thumb drag and track paging update the
  retained offsets without exposing pointer events to applications.
- A keyed `Split` owns its pane position, enlarged divider hit target, and
  horizontal or vertical drag. Nested splits compose multi-pane layouts.
  Focus loss cancels capture. A vertical resize that exposes more virtual
  rows requests a follow-up description; width-only fixed-row drags stay
  presentation-local.
- Scope and History use adjacent-neighbor nesting for their three panes:
  `[left | center] | inspector`. The inner divider redistributes left/center;
  the outer divider redistributes center/inspector. Split nesting is therefore
  part of the intended interaction, not only a layout detail. Scope still
  requests backend event windows only on cache misses; pane and scrollbar
  coordinates do not cross Caliber. Monitor was left unchanged because its
  current layout did not require a split migration.

## Automated and Windows evidence

On Windows x64, `tools/test.ps1` and `tools/check.ps1` pass. The foundation
tests cover Auto/Always visibility, both-axis reservation and corner,
minimum thumb size, clipping, wheel, track paging, thumb capture/drag,
out-of-bounds release, focus-loss cancellation, split minima, nested keys,
tiny-window clamping, retained drag presentation, and virtual-list viewport
follow-up. Scope's full Go/Caliber/Odin build and `go test ./...` pass;
History's self-test passes against its pinned Alicorn submodule. Native
Direct3D12 smoke runs of both applications exit successfully.
The pinned runtime revision `cc0274b` also passed the
[macOS foundation headless workflow](https://github.com/samanshaiza004/alicorn/actions/runs/35817462206)
and the corresponding
[Windows foundation workflow](https://github.com/samanshaiza004/alicorn/actions/runs/35817462213).
This is cross-platform
core/build evidence, not a substitute for physical macOS interaction.

Separate 30-second stationary runs after loading reported:

| App | Host ticks | Total GPU submissions | Event waits |
| --- | ---: | ---: | ---: |
| Scope | 0 | 2 | 1 |
| History | 0 | 3 | 2 |

The submissions are startup/loading work; neither application has a periodic
tick. These counters do not prove that a particular mouse drag feels good.
Windows UI automation identified both SDL windows, but its screenshot capture
failed with `SetIsBorderRequired` (interface unsupported), so no visual drag
claim is made from that tool.

A separate Windows Direct3D12 render capture used a generated trace with
20,000 events across 80 tracks at 1440×900 logical/physical pixels. Both the
track and event panes visibly rendered solid vertical tracks and thumbs; the
track pane had a proportional thumb, while the very large event collection
reached the configured minimum-thumb size. The virtual-list content widths
were reduced by the reserved scrollbar strip, confirming that the bars do not
cover row content. This verifies overflow projection and rendering, not pointer
dragging. Scope currently enables vertical scrolling for those lists;
horizontal bar geometry and interaction are covered by Alicorn's both-axis
runtime tests, and History's patch list uses `.Both`. A fresh diagnostic build
of History from its current source and pinned Alicorn submodule (`cc0274b`)
also showed vertical bars on overflowing lists and a horizontal bar in the
patch viewport: its resolved width was 436 logical pixels while the selected
patch content was 720 pixels wide. The earlier ignored History executable was
stale, so it was rebuilt before using this capture as evidence.

## Native interaction gate

The user reports that macOS testing of Scope and History passed: scrollbar and
divider behavior matched Windows and worked as intended, including the
interactions covered by the native smoke gate. This manual run preceded the
three-pane nesting migration below; the runtime interaction itself is
unchanged, while the new adjacent-pane topology is covered by Alicorn's
headless geometry regression and History's layout self-test. No macOS machine
identifier or exact local build hashes were supplied, so the platform result
is recorded as user-confirmed rather than independently reproducible machine
metadata. Windows native builds, application smokes, and GPU render captures
are recorded above; Alicorn's headless tests cover thumb dragging, paging,
release outside the window, focus-loss cancellation, and pane-split behavior.
