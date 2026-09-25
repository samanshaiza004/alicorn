# Native menus and integrated title bar

This experiment adds a small semantic menu description to the SDL host. Menu
trees are borrowed for `Run`; labels and structure are copied into native
controls at startup, while enabled and checked fields are read from the
borrowed item storage each time a menu opens. Applications receive their own
`Application_Command_ID` in `on_menu_command`. SDL event handling, retained
focus, and runtime nodes remain unaware of native menu handles and selectors.

## Platform verdict

SDL exposes the Windows `HWND` and macOS `NSWindow` through
`SDL_GetWindowProperties`. SDL does not provide native application menus or a
hit-test path that can preserve DWM caption behavior. Windows therefore uses
Win32 `HMENU`, a chained `SetWindowSubclass` hook, and `DwmDefWindowProc` for
non-client caption messages. macOS uses `NSApplication.mainMenu`, `NSMenu`, and
`NSMenuItem` on the `NSWindow` SDL owns.

On Windows, system-decorated windows attach a normal HMENU below the caption.
The opt-in integrated mode keeps the SDL-created decorated/resizable window and
its DWM caption buttons, resize borders, system menu, and native title text. The
host draws the top-level menu labels into the existing caption using GDI and
opens native HMENU popups. The menu hit rectangles are host-owned static
geometry, so `WM_NCHITTEST` does not call application code. Empty caption space
and native caption buttons continue through the original SDL/window procedure.
Calling DWM first preserves its caption-button hit testing, including the
Windows 11 maximize-button path used by Snap Layouts. Alicorn does not redraw
caption buttons or emulate Snap Layouts.
The integrated labels use Windows caption, inactive-caption, and highlight
system colors; HMENU popup surfaces remain OS-drawn.

The Windows integrated proof uses GDI for non-client labels instead of the
SDL_GPU renderer. That keeps native caption painting and GPU client rendering
separate, and avoids adding a retained title-bar layout contract before the
proof establishes a need for one. It currently places labels after the native
window title, so this is a structural integration seam rather than a finished
product title bar.

On macOS, the menu is the normal system menu bar and the SDL window retains its
standard title bar and traffic lights. `Integrated_Title_Bar` does not remove
or overlay macOS chrome. AppKit owns keyboard navigation and native shortcut
presentation; command items route through the same semantic IDs as Windows.
The adapter supplies conventional application and Window menus around the
application's File/Edit/View/Help menus.

## Public API

`Application.menus` is a slice of `Application_Menu`. Each menu has a label and
items. An item is a command, separator, or recursively nested submenu. Command
items carry an application-owned `Application_Command_ID`, enabled and checked
state, and an optional shortcut. Applications may update enabled and checked
fields between menu openings on the UI thread. Keep menu labels, ordering,
slice lengths, and backing storage stable for the duration of `Run`; native
controls snapshot that structure at startup. `Primary` means Ctrl on Windows
and Command on macOS. Shift and Alt retain their names; `Super` means the
Windows key on Windows and Control on macOS. Applications handle selected items with
`Application.on_menu_command`.

`Application.window_decorations` defaults to `System`. Set it to
`Integrated_Title_Bar` to opt into the Windows caption-label proof. Other
platforms preserve system decorations. No native handle appears in this API.

## Validation

The fixture is available from the native entry point:

```powershell
odin build native/sdl_gpu_entry -out:out/menu_fixture.exe
Copy-Item <odin-root>\vendor\sdl3\SDL3.dll out\SDL3.dll
out\menu_fixture.exe --menu-fixture
out\menu_fixture.exe --menu-fixture --integrated-title-bar
```

The fixture includes File, Edit, View, and Help; a nested recent-items menu; a
separator; disabled and checked items; and Ctrl shortcuts. Its callback prints
the semantic command ID and invocation count. `--menu-fixture-smoke` initializes
the host and exits after the normal three-second smoke interval.

Windows manual acceptance still needs to cover native command selection,
keyboard menu navigation, drag/no-drag regions, all resize edges, minimize,
maximize/restore, caption double-click, Alt+Space, DPI and monitor movement,
light/dark and active/inactive appearance, and hover over maximize for Snap
Layouts. macOS runtime
validation still needs to confirm menu placement, traffic lights, shortcut
dispatch, and focus behavior on a real AppKit host. Headless menu-model tests
and cross-target type checking do not replace those native checks.

## Platform references

- [SDL window properties](https://wiki.libsdl.org/SDL3/SDL_GetWindowProperties)
- [DWM custom window frames](https://learn.microsoft.com/en-us/windows/win32/dwm/customframe)
- [Subclassing controls](https://learn.microsoft.com/en-us/windows/win32/controls/subclassing-controls)
- [Windows 11 Snap Layout guidance](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/ui/apply-snap-layout-menu)
- [AppKit `NSApplication.mainMenu`](https://developer.apple.com/documentation/appkit/nsapplication/mainmenu)
- [AppKit `NSMenuItem`](https://developer.apple.com/documentation/appkit/nsmenuitem)
