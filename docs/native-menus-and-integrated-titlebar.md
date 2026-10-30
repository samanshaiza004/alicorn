# Native menus and integrated title bar

For the macOS tab/titlebar integration, see the
[research and implementation record](archive/research/macos-integrated-titlebar.md)
and its [macOS validation record](archive/validation/macos-sync-2026-10-20.md).
The Linux host evidence is recorded in the
[NixOS/Mango validation record](validation/linux-nixos-mangowc-2026-10-23.md).

This experiment adds a small semantic menu description to the SDL host. Menu
trees are borrowed for `Run`; labels and structure are copied into native
controls at startup, while each item's `Action_State` is read from the
borrowed item storage each time a menu opens. `Application_Command_ID` is an
alias of runtime `Action_ID`, so native menus transport the same semantic
identity used by shortcuts, direct controls, and the command palette. The
application remains responsible for dispatch and explicitly publishes action
descriptors/state with `action_update`. SDL event handling, retained focus,
and runtime nodes remain unaware of native menu handles and selectors.

## Platform verdict

SDL exposes the Windows `HWND` and macOS `NSWindow` through
`SDL_GetWindowProperties`. SDL does not provide native application menus or a
hit-test path that can preserve DWM caption behavior. Windows therefore uses
Win32 `HMENU`, a chained `SetWindowSubclass` hook, and `DwmDefWindowProc` for
non-client caption messages. macOS uses `NSApplication.mainMenu`, `NSMenu`, and
`NSMenuItem` on the `NSWindow` SDL owns.

On Windows, system-decorated windows attach a normal HMENU below the caption.
The opt-in integrated mode extends the DWM frame into the SDL-created window,
then removes the standard non-client frame while retaining the native window
styles needed for resize, system menu, minimize, maximize, and restore. The
host draws the title, menu labels, and caption glyphs with SDL_GPU and opens
native HMENU popups. Menu-label and caption-control rectangles belong to the
SDL host; they are not application-retained nodes, and hover only schedules
host presentation work.

The default integrated mode owns two logical coordinate spaces: the window
space includes the chrome, while the application viewport begins below it.
Applications that supply both `window_chrome_metrics` and
`window_chrome_layout` instead opt into ordinary retained content at the top of
the Windows client area. In that mode the host removes the content inset,
keeps Win32 menu labels and caption controls above application hit regions, and
draws the application header below those host-owned elements. Metrics report
the usable horizontal span between menu labels and caption controls. Explicit
blank drag regions become `HTCAPTION`; all other unregistered header pixels
remain normal client input. Rendering and pointer transforms therefore still
share the same window-logical coordinate space without application-side DPI
adjustments.

Win32 non-client handling asks `DwmDefWindowProc` first for caption-button
behavior. Caption-control bounds come from `DWMWA_CAPTION_BUTTON_BOUNDS` in
outer-window physical pixels. They are translated into client pixels and split
into minimize, maximize, and close rectangles with a common visible band. The
band is at least 32 Windows DIPs high; DWM's negative maximized Y offset cannot
move the marks above it. The maximized Close target reaches the client edge;
restored windows reserve an outer resize strip. Those same rectangles position
the GPU glyphs and return `HTMINBUTTON`, `HTMAXBUTTON`, and `HTCLOSE`;
DWM receives the caption messages and performs the system actions, including
Windows 11 Snap Layout for `HTMAXBUTTON`. The host draws its own caption marks.
SDL_GPU rejects transparent windows; this alone does not establish that an
AppWindow caption overlay is incompatible with the opaque swapchain. The
bounded deployment experiment is recorded in
[Windows caption validation](archive/validation/windows-captions.md).
The integrated band uses the resolved application menu chrome colors (or
Windows menu colors when no appearance is supplied), keeps ordinary hover
neutral, and uses the conventional red close-button hover. High-contrast mode
uses Windows highlight colors. Caption state changes post one coalesced SDL wake
so hover and press feedback redraws even while the app loop is waiting. HMENU
popup surfaces remain OS-drawn.

Caption marks use a common 10-DIP symbol box and rounded physical-pixel stroke
widths. Windows 11 gets rounded window outlines; Windows 10 gets square ones.
Restore occludes its rear outline, and Close is geometric rather than a font
character. Four tiny coverage masks are retained per host and replaced only
when DPI changes. Their physical output is converted into SDL window units at
the paint boundary using pixel density, which need not equal Windows DPI scale.
Title and menu runs refresh on that same effective typography-scale change;
ordinary resizing does not reshape them. Each label clips to its own allocated
content box; a truncated title includes an ellipsis. None of this describes
application nodes or adds an idle tick.

This is the framework-drawn fallback approved for the caption correction. It
differs from #6's original system-owned-pixels/non-redrawing goal. #6 must remain
open until that scope is reconciled and the outstanding manual Windows checks
are recorded. `System` decorations continue to use OS-owned caption pixels.

Windows menu navigation keeps the system-menu shortcut separate: Alt+Space
continues to open the native system menu. Alt+F/E/V opens the matching
application menu, and bare Alt enters top-level menu navigation. Left/Right
moves between top-level menus, and Escape leaves menu mode. F10 remains
Alicorn's DevTools HUD shortcut. Native HMENU owns navigation after a popup
opens.

Applications with retained titlebar content may set
`Application.menu_presentation=.Hidden` on Windows. This removes top-level
label paint and pointer exclusions while retaining the same HMENU descriptions,
enabled/checked state, command IDs, and accelerators. Press and release Alt to
open the first native menu, or use Alt plus the first letter of a menu name to
open that category directly. Hidden popups anchor below the caption band.
Alt+Space remains the Windows system menu and F10 remains DevTools. This option
does not hide the macOS system menu bar or a Windows system-decorated menu bar.

On macOS, the menu is the normal system menu bar and the SDL window retains its
standard title bar and traffic lights. `Integrated_Title_Bar` does not remove
or overlay macOS chrome. AppKit owns keyboard navigation and native shortcut
presentation; command items route through the same semantic IDs as Windows.
The adapter supplies conventional application and Window menus around the
application's File/Edit/View/Help menus.

On Linux, SDL keeps the normal system-decorated window and Alicorn does not
create an application menu. `Application.menus` is still borrowed by the host
as semantic accelerator metadata. The shared accelerator matcher walks direct
and nested command items, requires the command to be enabled, requires an exact
modifier set, maps `Primary` to Ctrl and `Super` to the window-system key, and
dispatches the same `Application.on_menu_command` callback used by native
menus. Repeated matching key-down events are consumed without dispatch, and
the event loop does not run menu accelerators while an IME composition is
active. Inspector/context-menu ownership remains earlier in event routing.

## Public API

`Application.menus` is a slice of `Application_Menu`. Each menu has a label and
items. An item is a command, separator, or recursively nested submenu. Command
items carry an `Application_Command_ID` (the same `Action_ID`), an explicit
`Action_State`, and an optional shortcut. Publish the matching action metadata
and state to the runtime with `action_update`; keep that state synchronized
with the menu and guard app-owned dispatch as well. Applications may update
the state between menu openings on the UI thread. Keep menu
labels, ordering, slice lengths, and backing storage stable for the duration
of `Run`; native controls snapshot that structure at startup. `Primary` means Ctrl on Windows
and Command on macOS. Shift and Alt retain their names; `Super` means the
Windows key on Windows and Control on macOS. Applications handle selected items with
`Application.on_menu_command`.

macOS applications that want content beside native traffic lights opt into
`Content_Title_Bar`; Windows applications keep `Integrated_Title_Bar` and may
provide both chrome callbacks to place retained content in its menu/titlebar
band. The application receives `Window_Chrome_Metrics` and declares an ordinary
retained header node plus up to `WINDOW_CHROME_REGION_CAPACITY`
interactive/window-drag nodes in `Window_Chrome_Layout`. Metrics use
window-logical coordinates and include the available `content_start_x` and
`content_end_x`; on Windows these fall between native menu labels and caption
controls. The host copies finalized retained geometry after layout, including
retained-only layout changes; callbacks and application-owned slices are not
retained. Native controls and menus keep hit-test priority, followed by
interactive app regions and explicit blank drag regions. A captured tab drag
stays client-owned through release even when it crosses blank space. Windows
without callbacks keep the original inset and host title label. The
`--macos-titlebar-fixture` and `--windows-titlebar-fixture` modes exercise the
shared contract on their native platforms.

`Application.window_decorations` defaults to `System`. Set it to
`Integrated_Title_Bar` to use the Windows native menu and caption band; the
chrome callbacks are optional and opt the application into retained content in
that band. On macOS, `Content_Title_Bar` extends Alicorn-rendered content under
the native titlebar. No native handle appears in this API.

## Validation

The fixture is available from the native entry point:

```powershell
. .\tools\common.ps1
$AccessKit = Get-AlicornAccessKit
odin build native/sdl_gpu_entry @($AccessKit.CompilerArguments) -out:out/menu_fixture.exe
Copy-Item <odin-root>\vendor\sdl3\SDL3.dll out\SDL3.dll
out\menu_fixture.exe --menu-fixture
out\menu_fixture.exe --menu-fixture --integrated-title-bar
out\menu_fixture.exe --menu-fixture --windows-titlebar-fixture
```

The fixture includes File, Edit, View, and Help; a nested recent-items menu; a
separator; disabled and checked items; and Ctrl shortcuts. Its callback prints
the semantic command ID and invocation count. `--menu-fixture-smoke` initializes
the host and exits after the normal three-second smoke interval.

`tools/validate_captions.ps1` additionally checks real D3D12 pixels and writes
restored/maximized caption captures at four DPIs under `out/caption-fixtures/`.
It tests Windows 10/11 marks, both SDL pixel-density conventions, narrow titles,
active/inactive, hover/pressed and high-contrast paint policy. A live SDL HWND
then exercises restore/maximize/restore, chained caption hit tests, and monitor
work-area bounds at the current desktop DPI. The synthetic scale and contrast
cases are renderer tests, not evidence of physical monitor or OS contrast
transitions. See the linked validation record for limits and remaining checks.

Validation record (2026-10-02): the project owner manually verified on macOS
that AppKit menu commands activate, keyboard shortcuts dispatch, IME works,
and native window resizing works. The project owner had previously confirmed
that the file/folder picker works on macOS. The local native SDL_GPU fixture
also passed on macOS 27.0/arm64 with SDL 3.4.16 and Metal selected; it exercised
2x Retina metrics, 300 resize iterations, and 303 submitted/retired frames.
macOS verification for this pass is complete for these owner-confirmed items;
unreported host details below are deferred rather than claimed as tested.

Remaining manual acceptance is platform-specific. Windows still needs native
command selection and keyboard menu navigation, drag/no-drag regions, all
resize edges, minimize, maximize/restore and its restore glyph, dragging a
maximized window to restore, caption double-click, Alt+Space, DPI and monitor
movement, light/dark and active/inactive appearance, high-contrast colors,
caption hover/press/leave feedback, taskbar/work-area behavior while maximized,
and hover over maximize for Snap Layouts. The SDL-owned window must apply a
`WM_DPICHANGED` suggested rectangle exactly once; Alicorn should observe the
resulting geometry and refresh chrome metrics. macOS traffic-light behavior and
focus reacquisition were not separately recorded. Headless geometry/menu tests
and native smoke do not replace those interaction checks.

## Platform references

- [SDL window properties](https://wiki.libsdl.org/SDL3/SDL_GetWindowProperties)
- [DWM custom window frames](https://learn.microsoft.com/en-us/windows/win32/dwm/customframe)
- [Subclassing controls](https://learn.microsoft.com/en-us/windows/win32/controls/subclassing-controls)
- [Windows 11 Snap Layout guidance](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/ui/apply-snap-layout-menu)
- [AppKit `NSApplication.mainMenu`](https://developer.apple.com/documentation/appkit/nsapplication/mainmenu)
- [AppKit `NSMenuItem`](https://developer.apple.com/documentation/appkit/nsmenuitem)
