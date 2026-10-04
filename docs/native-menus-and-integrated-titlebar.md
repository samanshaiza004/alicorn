# Native menus and integrated title bar

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
host draws integrated menu labels with SDL_GPU and opens native HMENU popups.
The labels and their hit rectangles belong to the SDL host; they are not
application-retained nodes, and hover only schedules host presentation work.

The host owns two explicit logical coordinate spaces. The window space includes
the integrated chrome. The application space begins below that chrome, keeps an
origin of `(0, 0)`, and has a viewport shortened by the chrome height. Rendering
translates application display geometry down by that height; pointer and wheel
input is translated back into application coordinates; native text-input
candidate geometry is translated into window coordinates. Applications do not
need to know that an integrated title/menu band exists.

Win32 non-client handling asks `DwmDefWindowProc` first for caption-button
behavior. DWM therefore retains ownership of the native caption buttons and
Windows 11 Snap Layout affordance whenever it handles the message. Alicorn owns
only menu-label, blank-caption, and resize-border hit testing. It does not paint
caption buttons or emulate the system menu, resizing, or Snap Layouts. The
integrated labels use Windows caption, inactive-caption, and highlight system
colors; HMENU popup surfaces remain OS-drawn.

Windows menu navigation keeps the system-menu shortcut separate: Alt+Space
continues to open the native system menu. Alt+F/E/V opens the matching
application menu, and bare Alt enters top-level menu navigation. Left/Right
moves between top-level menus, and Escape leaves menu mode. F10 remains
Alicorn's DevTools HUD shortcut. Native HMENU owns navigation after a popup
opens.

On macOS, the menu is the normal system menu bar and the SDL window retains its
standard title bar and traffic lights. `Integrated_Title_Bar` does not remove
or overlay macOS chrome. AppKit owns keyboard navigation and native shortcut
presentation; command items route through the same semantic IDs as Windows.
The adapter supplies conventional application and Window menus around the
application's File/Edit/View/Help menus.

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
resize edges, minimize, maximize/restore, dragging a maximized window to
restore, caption double-click, Alt+Space, DPI and monitor movement, light/dark
and active/inactive appearance, taskbar/work-area behavior while maximized, and
hover over maximize for Snap Layouts. The SDL-owned window must apply a
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
