# Linux NixOS/Mango Validation

Date: 2026-10-23

Host: NixOS 26.11.20260831.34ab990 (Zokor), Mango 0.16.2(release), Wayland

## Verdict

The Alicorn SDL3/SDL_GPU host passes the automated native Wayland/Vulkan
validation used here. Scratchpad also passes its pinned and local-Alicorn
native smoke paths after a Linux menu integration fix.

This is a conditional validation result, not a release sign-off. Physical
interaction, visual review, dialogs/portals, clipboard, IME behavior, Linux
accessibility clients, DPI transitions, and multi-monitor movement remain
unverified. Linux has system decorations but no native application-menu
adapter; the Scratchpad menu model is passed to the Linux host as semantic
accelerator metadata, but no native application menu is created.

## Checkouts

| Repository | Branch | HEAD | Lock/candidate |
| --- | --- | --- | --- |
| `/home/saman/dev/alicorn` | `validation/linux-nixos-mangowc-2026-10-23` | Base `2063b03e612ef172a66eabb2127fd6a304c808de` | Validation changes committed on this branch; local candidate tested |
| `/home/saman/dev/scratchpad` | `validation/linux-nixos-mangowc-2026-10-23` | Base `990b200c46643d27c936da609ddc01e35151be3f` | Locked Alicorn `af21f3862b2d3cd959a62373bf5e147a04a2ee77`; Caliber `197cd964cc7265bc60df599a6b8562eac7c75f3a` |

The adversarial Alicorn commit `1690aaa9c961b318d817e2ebeb75ded9b6d66598`
exists locally but is not in the current HEAD ancestry. It is contained by
`remotes/origin/codex/v02-adversarial-validation`.

## Host Inventory

| Item | Result |
| --- | --- |
| Kernel | `7.2.2`, x86_64 |
| Nix | `2.34.8` |
| nixpkgs | `34ab99075ac4f7e40cf037eef32cb1c360bb85e9` |
| Session | `XDG_SESSION_TYPE=wayland`, `WAYLAND_DISPLAY=wayland-0`, `DISPLAY=:1` |
| Runtime | `XDG_RUNTIME_DIR=/run/user/1000` |
| Desktop | `XDG_CURRENT_DESKTOP=mango`, `DESKTOP_SESSION=mango`, `XDG_SESSION_DESKTOP=mango:wlroots` |
| IME environment | `GTK_IM_MODULE`, `QT_IM_MODULE`, `GLFW_IM_MODULE`, and `IBUS_ADDRESS` unset; `NO_AT_BRIDGE=1` |
| Active outputs | DP-3, 2560x1440 at 165 Hz; HDMI-A-1, 1920x1080 at 60 Hz |
| Output scale | Wayland scale 1 on both active outputs |
| GPU 0 | NVIDIA GeForce RTX 2080 SUPER, NVK TU104, PCI `10de:1e81` |
| GPU 1 | AMD Ryzen 5 7600X integrated graphics, RADV Raphael/Mendocino, PCI `1002:164e` |
| Vulkan software device | llvmpipe also enumerated |
| Vulkan | Instance 1.4.357; hardware device API 1.4.354; Mesa 26.2.1 |

`wayland-info` reports `wl_compositor` v6, `xdg_wm_base` v6,
`zwp_linux_dmabuf_v1` v4, fractional-scale, text-input-v3, input-method-v2,
data-control, screencopy, and XWayland protocols. The main Wayland DRM device
is `/dev/dri/card0`/`renderD128`.

## Toolchain

The base shell has Go `1.26.7`, but no Rust/Cargo, C compiler, pkg-config, or
Vulkan tools. Validation used a temporary Nix shell with:

| Tool | Version |
| --- | --- |
| clang | `21.1.8` |
| rustc | `1.97.1` |
| cargo | `1.97.0` |
| cmake | `4.3.4` |
| pkg-config | `0.29.2` |
| SDL3 | `3.4.14` |
| Vulkan tools | `1.4.357.0` |
| wayland-utils | `1.3.0` |

The tested Odin SDK is the official `dev-2026-09` Linux AMD64 archive:

`https://github.com/odin-lang/Odin/releases/download/dev-2026-09/odin-linux-amd64-dev-2026-09.tar.gz`

It was extracted to `/tmp/opencode/odin-dev-2026-09` and reports
`dev-2026-09-nightly:a2fb372`. SHA-256:

`167c3e1d7056419dad2e04bb3bd98715b7ff286d4c125f3c5a5ee337c6254283`

SDL development and library paths were supplied explicitly:

```text
PKG_CONFIG_PATH=/nix/store/ybrxrfpbvbaikdjha5dczx049wagplx5-sdl3-3.4.14-dev/lib/pkgconfig
LIBRARY_PATH=/nix/store/63ai3hhggv9r9bxvw2qmzml9gh108b9h-sdl3-3.4.14-lib/lib
NIX_LDFLAGS=-L/nix/store/63ai3hhggv9r9bxvw2qmzml9gh108b9h-sdl3-3.4.14-lib/lib
```

The Linux run therefore validates SDL3 3.4.14, not the macOS-pinned SDL3
3.4.18. No global `LD_LIBRARY_PATH` or system configuration was changed.

## Changes

### Alicorn

- Added `alicorn_odin_with_linker_flags` in `tools/common.sh` so empty
  `-extra-linker-flags:` arguments are omitted.
- Updated the example, native, test, widget-gallery, custom-surface, and
  validation shell scripts to use that helper.
- Added SDL backend/version diagnostics to `native/sdl_gpu/main.odin` and
  `native/sdl_gpu/validation.odin`.
- Moved menu accelerator matching into the shared native host layer so Linux
  and Windows use the same direct/nested command matching and modifier rules.
- Added Linux accelerator routing with exact modifiers, enabled-state checks,
  repeat suppression, and IME-composition protection. SDL key diagnostics now
  include keycode, scancode, modifiers, repeat state, and window ID when input
  debugging is enabled.
- Replaced the Linux hardcoded DejaVu path with Fontconfig discovery, including
  an `fc-match` fallback for NixOS loader paths and Runa glyph-coverage checks.

The original Linux failure was:

```text
Flag missing for 'extra-linker-flags'
```

It came from an empty Linux AccessKit linker flag, not from SDL or Vulkan.

### Scratchpad

- Added `scratchpad_native_menus` in
  `frontends/alicorn/app_actions.odin`.
- The primary application and floating secondary windows expose the borrowed
  menu model on every platform.
- Linux continues to use system decorations and does not render a native menu,
  but its host now routes the menu-defined Save, Save As, Open, and command
  palette accelerators through the normal application command callback.
- Scratchpad leaves optional system fallback ownership to the native host rather
  than duplicating a distribution-specific Linux font path.

## Validation Results

### Baseline

- `nix shell nixpkgs#vulkan-tools --command vulkaninfo --summary`: PASS.
- `vkcube --wsi wayland --c 3 --gpu_number 0`: PASS on NVIDIA/NVK.
- `vkcube --wsi wayland --c 3 --gpu_number 1`: PASS on AMD/RADV.
- `vkcube --wsi xcb --c 3 --gpu_number 0`: PASS on XWayland.
- `nix shell nixpkgs#wayland-utils --command wayland-info`: PASS.
- The Vulkan loader emitted non-fatal dzn/display-extension warnings; NVK,
  RADV, and llvmpipe enumerated successfully.

### Alicorn

- Foundation suite: 245 tests PASS.
- Theme suite: 35 tests PASS.
- Native host suite: 97 tests PASS.
- Linux fallback fixture: Fontconfig-resolved DejaVu Sans covers the UI arrows
  and the verified text run selects the fallback face.
- Generic text-input/navigation/paint-span contract: PASS.
- Native shortcut matcher: PASS for nested items, Ctrl+S, Ctrl+Shift+S, Ctrl+O,
  Ctrl+Shift+P, exact modifiers, disabled commands, and repeat suppression.
- Retained-work, text-layout, and material benchmarks: PASS.
- Surface geometry, text-input, surface stress, widget-gallery, custom-surface,
  inspector, and secondary-window smoke fixtures: PASS.
- Forced Wayland idle smoke: PASS; 2 GPU submissions retired, zero application
  ticks after settling.
- Forced X11 idle smoke: PASS; 2 GPU submissions retired, zero application
  ticks after settling.
- `sh tools/validate_icons.sh`: PASS.
- `sh tools/validate_images.sh`: PASS.

The diagnostic inspector capture was written under:

`out/diagnostics/20261023T234126.392Z-0001/`

with `diagnostics.json`, `inspector.txt`, `timeline.json`, `windows.json`, and
`screenshot.ppm`.

### Scratchpad

- `go test -tags treesitter_release ./...` with `CC=clang`: PASS.
- Pinned `./tools/alicorn.sh test`: PASS, including 13 bridge tests and 163
  frontend tests.
- Pinned `./tools/alicorn.sh build`: PASS.
- Pinned forced-Wayland `./tools/alicorn.sh smoke`: PASS; SDL3 3.4.14,
  Vulkan selected, 2 submissions retired, `publication_rendered true`,
  `wake_observed true`, `ordered_shutdown true`.
- Local candidate test with `--alicorn-root /home/saman/dev/alicorn
  --allow-alicorn-revision`: PASS.
- Local candidate forced-Wayland smoke with the same flags: PASS; diagnostic
  output reported `sdl_video_driver wayland`, `gpu_driver_selected vulkan`,
  `publication_rendered true`, `wake_observed true`, and
  `ordered_shutdown true`.
- Local candidate forced-X11 smoke: PASS and reported `sdl_video_driver x11`.

## Unverified or Unsupported

| Area | Status |
| --- | --- |
| Physical keyboard, pointer, resize, focus, drag/drop | Not manually exercised |
| IME composition and candidate-window behavior | Automated contract only; no physical IME client tested |
| Clipboard and file/folder dialogs | Not manually exercised; portal behavior unknown |
| Native Linux application menus | Not implemented by Alicorn; semantic keyboard accelerators are automated, physical shortcut use remains pending |
| Linux AccessKit/screen readers | Unsupported by the current native adapter |
| DPI change and monitor movement | Not manually exercised; current outputs are scale 1 |
| Mango tiled/floating decoration review | Not manually reviewed |
| Visual pixel comparison | No human visual review completed |
| Release packaging | Not attempted |

`tools/validate_icons.sh` is not executable in the checkout; invoking it
directly gives `Permission denied`, while invoking it through `sh` passes.

## Reproduction

Use the official Odin SDK and a Nix shell containing clang, Rust/Cargo,
pkg-config, and the SDL3 development/library outputs. For native smoke, set:

```text
SDL_VIDEO_DRIVER=wayland
SDL_GPU_DRIVER=vulkan
ALICORN_ODIN=/tmp/opencode/odin-dev-2026-09/odin
ODIN_ROOT=/tmp/opencode/odin-dev-2026-09
CC=clang
```

Pinned Scratchpad smoke:

```sh
sh tools/alicorn.sh smoke
```

Local Alicorn candidate smoke:

```sh
sh tools/alicorn.sh smoke \
  --alicorn-root /home/saman/dev/alicorn \
  --allow-alicorn-revision
```

Both commands must be run from `/home/saman/dev/scratchpad` inside the
toolchain shell described above.
