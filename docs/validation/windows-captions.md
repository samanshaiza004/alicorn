# Windows captions: feasibility and validation

## System-drawn feasibility gate (2026-10-13)

The requested first experiment had a 15-minute cap and stopped at the deployment
gate within that budget. No SDK/runtime was installed or upgraded. The local
Windows SDK is 10.0.26100.0; Windows App Runtime 1.8 x64/x86 packages
8000.946.1701.0 are installed. Alicorn has no App SDK bootstrap/package graph
initialization or language projection.

A standalone Odin probe created a hidden, resizable, high-pixel-density SDL
HWND, claimed its opaque D3D12 swapchain, initialized WinRT, and requested the
`Microsoft.UI.Windowing.AppWindow` activation factory. Output:

```text
window_geometry 640 360 640 360 pixel_density 1 display_scale 1 window_dpi 96
SDL HWND present true GPU driver direct3d12 opaque swapchain claimed true
RoInitialize HRESULT 0x00000001
AppWindow activation HRESULT 0x80040154 factory_present false
```

`0x80040154` is `REGDB_E_CLASSNOTREG`: the existing unpackaged host cannot
activate AppWindow with only the installed runtime. Microsoft documents
bootstrap/dynamic dependency setup for unpackaged App SDK applications. Under
the agreed dependency stop condition, this slice uses the existing GPU-drawn
host. It does **not** demonstrate overlay/swapchain incompatibility; testing
`ExtendsContentIntoTitleBar`, overlay composition and its lifecycle still needs
an App SDK dependency experiment. The probe stays a diagnostic artifact under
`out/experiments/appwindow-caption/`, outside the production host.

The original #6 contract says Windows owns the caption pixels and excludes
redrawing them. The approved fallback owns pixels in Alicorn and window actions
in Win32/DWM. Reconcile that contract before closing #6; no issue was closed by
this pass.

## Correction

- Keep raw DWM bounds, hit testing and canonical control rectangles in physical
  client pixels. Convert only emitted paint geometry into SDL window units.
- Give all three buttons the same visible vertical band. Negative maximized
  DWM offsets no longer move Minimize/Restore independently of Close.
- Extend both the maximized Close backplate and its hit target to the client
  edge. Restored windows keep an explicit resize strip.
- Use cached 10-DIP geometric symbols, scale-rounded strokes, Windows 10/11
  outline variants and proper rear-window occlusion in Restore. Close has no
  font dependency. The small algorithms were reimplemented in Odin following
  Chromium/Electron conventions; their notice is included in Windows packages.
- Clip each title/menu run to its allocated content box. Truncated title text
  gets an ellipsis. Refresh owned host runs and their resource generations when
  effective DPI typography changes, without reconstructing application nodes.
- Preserve subdued inactive glyphs, neutral ordinary hover and red Close hover;
  high-contrast paint uses system menu/highlight colors.
- Ignore duplicate activation notifications without clearing hover/pressed
  state or scheduling another frame. Actual active/inactive transitions repaint.

## Automated coverage

Run from the repository root:

```powershell
./tools/check.ps1
./tools/validate_captions.ps1
./out/alicorn_sdl_gpu.exe --menu-fixture --integrated-title-bar --menu-fixture-smoke
```

The native package has regressions for four DPIs (96/120/144/192), negative
monitor origins, one-pixel boundaries, maximized negative DWM offsets,
paint/hit-test agreement, invalid-DWM fallback, Restore occlusion, mask ownership
and reuse, bounded text clips, and host text replacement/generation. Repeated
mask/text refreshes retain storage and skip shaping until scale changes.

The caption validator renders **144** production-paint captures into D3D12
textures: four DPIs × two Windows icon variants × two SDL pixel densities × nine
states. Readback checks every caption pixel against the expected coverage and
colors; unwanted title/menu pixels inside caption controls fail this check.
PPM screenshots are retained under `out/caption-fixtures/` for inspection.

A live SDL-created HWND additionally passes restored → maximized → restored,
caption-center `WM_NCHITTEST` calls through the installed subclass, and
maximized client bounds equal to the current monitor's work area. On this
96-DPI desktop, DWM reports `top=-8` when maximized; all corrected caption
controls use `top=0, bottom=32`. Three native-layout GPU captures are also saved.

Local `tools/check.ps1` passed: 205 runtime tests, 35 theme tests, 88 native tests,
all example builds, theme CLI/codegen and foundation/text-input contracts.
The normal integrated-menu D3D12 smoke also passed. The Windows shared-SDL
package build/audit passed and includes the Chromium caption notice.

For an unchanged five-second idle sample, set these SDL hints only in the test
process environment before running the integrated fixture:

```powershell
$env:SDL_WINDOW_ACTIVATE_WHEN_RAISED = '0'
$env:SDL_WINDOW_ACTIVATE_WHEN_SHOWN = '0'
./out/alicorn_sdl_gpu.exe --menu-fixture --integrated-title-bar --idle-validation-seconds=5
```

Result: one initial submission/retirement, one text mesh build/upload, zero
`native_host_wake_events`, and zero `native_chrome_encode_ns`. Without the hints,
this background launch receives alternating `WM_NCACTIVATE` states about every
half second while another window remains foreground; the additional frames
correspond to changing native caption state, consistent with Windows attention
flashing, rather than an unchanged-idle sample. The application retains its
normal activation behavior; the hints are not production defaults.

Pixel expectations cover geometry, clipping and blend correctness. Human
inspection is still required for native visual fidelity. Synthetic high-contrast
state does not toggle the OS, and synthetic DPI does not exercise
`WM_DPICHANGED` on physical monitor movement.

## Remaining manual acceptance

- Windows 11 maximize-hover Snap Layouts; caption drag, double-click,
  minimize/restore/close, maximized drag-to-restore and Alt+Space.
- Physical 100/125/150/200% DPI and movement between monitors, including negative
  desktop coordinates. SDL must apply the suggested DPI rectangle once.
- Actual Windows high-contrast transitions and inactive-window appearance.
- Native popup selection/keyboard navigation, all resize edges, taskbar/work-area
  behavior and unchanged idle GPU/wake counters on the user's desktop.
- Visual comparison in Scratchpad using the updated dependency, rather than
  only the host fixture.

## Primary references

- [Microsoft title-bar customization](https://learn.microsoft.com/en-us/windows/apps/develop/title-bar)
- [Unpackaged App SDK dependency setup](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/deploy-unpackaged-apps)
- [DWM custom-frame contract](https://learn.microsoft.com/en-us/windows/win32/dwm/customframe)
- [Caption title-bar design](https://learn.microsoft.com/en-us/windows/apps/design/basics/titlebar-design)
- [Windows 11 Snap Layouts](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/ui/apply-snap-layout-menu)
- [SDL activation-on-raise hint](https://wiki.libsdl.org/SDL3/SDL_HINT_WINDOW_ACTIVATE_WHEN_RAISED)
- [Electron caption painter](https://github.com/electron/electron/blob/main/shell/browser/ui/views/win_caption_button.cc)
- [Chromium icon painter](https://github.com/chromium/chromium/blob/main/chrome/browser/ui/views/frame/windows_icon_painter.cc)
