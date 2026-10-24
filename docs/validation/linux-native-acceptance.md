# Linux Native Acceptance Matrix

This is the reusable runbook for Linux native evidence. It supplements the
[NixOS/Mango validation record](linux-nixos-mangowc-2026-10-23.md); it does not
turn one desktop run into broad Linux certification.

## Evidence rules

- `PASS (automated)` means a deterministic test or a captured host result passed.
- `PASS (manual)` means a person performed the stated action on the named
  session and recorded the result.
- `PENDING` means the action has not been performed. Do not infer it from a
  build, synthetic event, screenshot, or idle smoke.
- `UNSUPPORTED` means the current Linux adapter cannot provide the capability;
  it is not a passing accessibility or integration result.

The runner deliberately does not synthesize keyboard, pointer, clipboard,
dialog, IME, accessibility-client, monitor, or Mango behavior.

## Automated run

Run from the Alicorn checkout inside the target Wayland session:

```sh
sh tools/linux_native_acceptance.sh \
  --odin /path/to/odin \
  --report-dir out/linux-native-acceptance
```

The runner requires `XDG_SESSION_TYPE=wayland`, `WAYLAND_DISPLAY`, and
`XDG_RUNTIME_DIR`, and selects `SDL_VIDEO_DRIVER=wayland` and
`SDL_GPU_DRIVER=vulkan`. Use the following mode when only a compiler and
headless contracts are available:

```sh
sh tools/linux_native_acceptance.sh --headless --odin /path/to/odin
```

Headless mode skips all window, compositor, and GPU-session gates. It is useful
for checking the runner and deterministic contracts, but it cannot be reported
as native NixOS/Mango validation.

The evidence directory contains:

| Artifact | Purpose |
| --- | --- |
| `environment.txt` | Selected session, toolchain, revision, and SDL variables |
| `summary.tsv` | Machine-readable gate status and log paths |
| `commands.txt` | Commands invoked by the runner |
| `logs/*.log` | Full stdout/stderr for each gate or probe |
| `diagnostics/*` | Native host diagnostics, if the session smoke reaches a frame |

The diagnostic bundle's `diagnostics.json`, `windows.json`, `timeline.json`,
and `screenshot.ppm` are investigation artifacts. The screenshot still needs
human review; telemetry does not prove visual correctness or interaction.

## Automated matrix

| Area | Automated evidence | Boundary |
| --- | --- | --- |
| Odin and repository build | `check.sh` builds the foundation, benchmark, and examples | Build success is not desktop acceptance |
| Runtime and native contracts | `test.sh`, native text-input/navigation contracts, and surface geometry contracts | Synthetic SDL text events are not a real IME session |
| Font fallback | Native Linux Fontconfig tests plus the `fc-match` probe | The selected face does not prove every glyph or desktop font setup |
| Wayland/Vulkan host | Bounded custom-surface smoke and injected surface stress | It proves host startup/submission/retirement, not physical input or Mango layout |
| Native diagnostics | A repeatable retained-tree/timing/window capture | It does not prove visual parity without review |
| Semantic accelerators | Native matcher tests cover nested commands, exact modifiers, disabled commands, repeats, and IME-composition suppression | Physical shortcut use and compositor/window-manager conflicts remain manual |
| Wayland/Vulkan inventory | `wayland-info`, `vulkaninfo --summary`, Nix, SDL, and Fontconfig probes when installed | Tool output describes one host only |

## Manual acceptance checklist

Record the machine, commit, Odin/SDL versions, GPU/driver, Mango version,
active outputs and scales, and the evidence path before checking an item.

| Check | User action | Expected observation | Status/evidence |
| --- | --- | --- | --- |
| Keyboard and focus | In a real app, Tab/Shift+Tab through controls, type, change focus, and refocus after another window is focused | Focus ring, caret, text ownership, and activation remain correct | `PENDING` |
| Pointer and resize | Click controls, drag within and outside controls, resize from every practical edge, and restore focus | Hit targets follow content; no stale geometry or lost input | `PENDING` |
| Drag/drop | Drag a supported file or text payload into the app and cancel a drag | Accepted and cancelled paths are clear and do not leave capture stuck | `PENDING` |
| Clipboard | Copy, cut, paste, empty clipboard, and try unavailable clipboard access if applicable | UTF-8 text and empty-state behavior match the application contract | `PENDING` |
| Dialogs and portals | Open file and folder dialogs, cancel and accept, and test the configured portal/backend | Dialog result, cancellation, focus return, and portal errors are handled | `PENDING` |
| Real IME | With an installed Linux IME, compose text, inspect the candidate window, commit, cancel, and change focus mid-composition | Preedit/candidate placement, commit, cancellation, and caret state are correct | `PENDING` |
| Accessibility client | Attempt an actual supported Linux screen-reader/AT session and record the adapter result | Do not claim a pass if the current Linux AccessKit adapter is absent | `UNSUPPORTED` on this revision |
| Mixed DPI and monitors | Move primary and secondary windows across outputs with different scales; inspect caret, selection, hit targets, popups, and window bounds | Logical/physical conversion remains aligned at each output and transition | `PENDING` |
| Mango tiled/floating | Review tiled and floating placement, focus, maximize/fullscreen, decoration, and close behavior | Window state and decoration remain usable in both Mango modes | `PENDING` |
| Visual output | Review the captured frame and live UI at normal, tiled, floating, and output-transition states | No clipping, missing glyphs, incorrect scale, or unexpected decoration | `PENDING` |
| Semantic accelerators | Physically try Ctrl+S, Ctrl+Shift+S, Ctrl+O, Ctrl+Shift+P, nested commands, disabled commands, repeats, and shortcuts during IME composition | Enabled exact-match commands dispatch once; disabled/repeated/composing cases do not dispatch | `PENDING` |

Linux intentionally keeps the SDL system-decorated window and does not create a
native application menu. `Application.menus` is consumed as semantic
accelerator metadata. The shared matcher walks direct and nested commands,
requires enabled state and exact modifiers, maps `Primary` to Ctrl on Linux,
suppresses repeated key-down dispatch, and does not match while IME composition
is active. The callback is the same application command callback used by native
menus on other platforms. See [native menus and integrated titlebar](../native-menus-and-integrated-titlebar.md).

## Validation request

An issue-closing report should attach the runner's evidence directory and fill
the manual table with a result or an explicit blocker for every row. In
particular, report the IME name, screen reader/AT name or the unsupported Linux
adapter result, output names/scales before and after movement, Mango tiled and
floating observations, and the exact semantic accelerator cases exercised.
