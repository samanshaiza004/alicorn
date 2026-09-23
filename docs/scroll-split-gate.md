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
- Scope and History use two nested splits for their three panes. Scope still
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

## Native interaction gate still to record

On macOS, build Scope at its pinned Alicorn/Caliber revisions and History with
its recursive Alicorn submodule. With a trace containing enough events and a
History patch containing long lines, inspect the visible vertical/horizontal
bars, drag both pane dividers, page a scrollbar track, drag each thumb to both
ends, resize very narrow/wide, release a drag outside the window, and leave
each app stationary after load. Record the machine, build revisions, observed
behavior, and any errors here before treating cross-platform interaction as
fully validated.
