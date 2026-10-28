# macOS integrated titlebar

Research date: 2026-10-20; implementation status updated 2026-10-22. The bounded
native fixture passed fullscreen geometry checks, the user confirmed tab
selection/closing/reordering and blank-header window dragging work physically,
and Scratchpad now dogfoods the public API. See the
[fixture validation record](../validation/macos-titlebar-input-fixture.md).
The initial research used Alicorn `d0cf8f5`, Scratchpad `eae8c9b`. See the separate
[macOS validation record](../validation/macos-sync-2026-10-20.md) for tests,
native launches, packaging, and the two development setup problems reproduced.

## Recommendation

Keep the real AppKit window controls and existing native system menu. Extend
the SDL content view into the titlebar and let Scratchpad render its ordinary
tabs there. The native host owns control geometry, window dragging, and lifecycle;
Scratchpad owns documents, tab selection/reordering/detachment, and layout.

These remain two separate macOS surfaces:

- The **system menu bar** is at the top of the display. Alicorn already has an
  AppKit `NSMenu` adapter and semantic command dispatch.
- The **window titlebar/tab row** is the surface shown in the user's reference
  screenshots. It is now implemented as an opt-in native-host capability.

The green control remains AppKit's zoom/fullscreen control, including its native
modifier and hover behavior. Scratchpad should not draw three colored circles
and emulate those actions.

Proposed product geometry, with header height and native exclusions resolved by
the host rather than copied from a screenshot:

```text
macOS system menu: Scratchpad  File  Workspace  Edit  View  Window  Help

┌───────────────────────┬────────────────────────────────────────────┐
│ ● ● ●   sidebar tools │ [ document A × ][ document B × ]  +   blank │
├───────────────────────┼────────────────────────────────────────────┤
│ Files / Search        │ editor / image viewer                      │
│ workspace tree        │                                            │
└───────────────────────┴────────────────────────────────────────────┘
                        ↑ retained splitter
```

The layout can preserve Scratchpad's existing split: give its two panes aligned
top rows, with the left row reserving the actual native button cluster and the
right row containing `alicorn.tab_bar`. A root-level header is another option
if needed for narrow/no-workspace layouts, but it must share the split's resolved
width rather than keep another sidebar-width calculation. The requirement is
that the header occupies the extended top area and sits outside scrolling
content; moving tabs to another native view or Runtime is unnecessary.

## Current implementation

`native/sdl_gpu/menus_darwin.odin` installs the native menu through AppKit;
`native/sdl_gpu/titlebar_darwin.odin` owns native titlebar lifecycle, measured
control exclusions, retained hit regions, and window-drag arbitration. The
public `Application` contract opts into `.Content_Title_Bar`, sets a fixed
`window_chrome_height`, receives `Window_Chrome_Metrics`, and supplies a
`Window_Chrome_Layout` containing the header and bounded `.Interactive` /
`.Window_Drag` regions. Alicorn copies finalized node geometry into host-owned
rectangles; it does not retain application closures or tab models.

The feature is opt-in and Darwin-only. Windows keeps its existing host-owned
title/menu/caption band and content inset. Scratchpad sets its 42-point macOS
header independently of measured traffic-light geometry, keeps native
AppKit controls, and places its ordinary document tab bar in the same row. Its
document state and tab actions remain application-owned.

The system menu remains application-global; titlebar geometry is per window.
Content-titlebar setup therefore does not depend on installing menu descriptions.

## Prior art and what to take from it

| System | Relevant mechanism | Fit for Alicorn |
| --- | --- | --- |
| AppKit | A titled window can use `fullSizeContentView`, hide its visible title, and make the titlebar background transparent. | Use the native window and controls beneath a small Odin/AppKit adapter. [Full-size content](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/fullsizecontentview), [titlebar transparency](https://developer.apple.com/documentation/appkit/nswindow/titlebarappearstransparent). |
| Electron | `hidden` keeps traffic lights while content fills the window; `hiddenInset` changes their inset. Drag areas require exclusions for interactive elements. | Take the explicit separation between native controls, app content, and drag regions. [Titlebars](https://www.electronjs.org/docs/latest/tutorial/custom-title-bar), [drag regions](https://www.electronjs.org/docs/latest/tutorial/custom-window-interactions). |
| Qt 6.9+ | `ExpandedClientAreaHint`, `NoTitleBarBackgroundHint`, and safe-area geometry/change notifications. | Expose measured native geometry; normal layout decides how to use it. Qt's system menu remains separate through `QMenuBar`. [Window flags](https://doc.qt.io/qt-6/qt.html#WindowType-enum), [safe margins](https://doc.qt.io/qt-6/qwindow.html#safeAreaMargins), [native menu](https://doc.qt.io/qt-6/qmenubar.html#nativeMenuBar-prop). |
| Chromium | Native frame code and content hit testing coordinate app interaction with window movement/fullscreen. | Use the separation of responsibilities; avoid importing its private frame machinery. [Content hit testing](https://github.com/chromium/chromium/blob/5513451630f041dfe24e6c1db0c64458ce7d2871/components/remote_cocoa/app_shim/bridged_content_view.mm#L364), [native frame](https://github.com/chromium/chromium/blob/5513451630f041dfe24e6c1db0c64458ce7d2871/components/remote_cocoa/app_shim/browser_native_widget_window_mac.mm). |
| Firefox | The Cocoa backend extends content into the frame and maintains native control geometry; it also contains private titlebar/dragging overrides. | Its behavior is useful evidence, but those private hooks should not become Alicorn's dependency. [Cocoa implementation](https://github.com/mozilla-firefox/firefox/blob/main/widget/cocoa/nsCocoaWindow.mm), [macOS titlebar styles](https://github.com/mozilla-firefox/firefox/blob/main/browser/themes/osx/browser.css). |

This research does not establish which exact Electron settings Obsidian uses.
Its screenshot is a product reference. Electron's documented capabilities are
independent evidence that this arrangement is feasible.

AppKit toolbar styles and `NSTitlebarAccessoryViewController` provide supported
native-view alternatives with fullscreen integration. They are worth considering
if direct SDL input in the titlebar fails the first proof. They would add a second
view/layout boundary, so they are not the starting recommendation. [Toolbar
style](https://developer.apple.com/documentation/appkit/nswindow/toolbarstyle-swift.enum/unifiedcompact),
[titlebar accessories](https://developer.apple.com/documentation/appkit/nstitlebaraccessoryviewcontroller).

## Native fixture result

The native fixture contains actual Alicorn tabs and a text field in one SDL
window, native AppKit traffic lights, and explicitly classified drag space.
Automated checks cover geometry, fullscreen entry/exit, restore cycles, and
layout bounds. The user physically confirmed tab selection, close, reorder,
blank-header window dragging, and native control behavior on the Apple Silicon
desktop. The fixture also confirmed text entry and Retina-scale coordinate
alignment.

Firefox's `NonDraggableView` implementation warned that ordinary hit-test
classification might not prevent all native titlebar dragging. The fixture
confirmed this concern: tabs initially moved the window even though SDL treated
them as client input. Alicorn now latches the hit-test decision and gates
AppKit's public `isMovable` property for the gesture. Physical testing then
confirmed tab drag and blank-area window drag have distinct owners. No private
selectors, browser swizzling, accessory view, or second AppKit tab surface was
needed. [Firefox source, `NonDraggableView` and frame handling](https://github.com/mozilla-firefox/firefox/blob/main/widget/cocoa/nsCocoaWindow.mm).

## Public contract and ownership

The API is implemented in `native/sdl_gpu/application_api.odin` and documented
in the [reference](../../reference.md):

1. `.Content_Title_Bar` opts a Darwin window into the extended content area;
   `System` remains the default and Windows behavior is unchanged.
2. `window_chrome_height` specifies app layout height; the host delivers measured
   `Window_Chrome_Metrics`, including header bounds, native control rectangles,
   content start, display scale, and fullscreen state.
3. `window_chrome_layout` returns one retained header node and a bounded list of
   `.Interactive` / `.Window_Drag` retained nodes. The host resolves them after
   layout/presentation and refreshes on retained-only geometry changes.

The native host copies only bounded node IDs and rectangles. It retains no
application closures, pointers to documents, or tab models. Scratchpad continues
to own document selection, close/reorder/detach actions, and content layout.
The low-level regions remain explicit; there is no second native tab view or
second runtime.

Avoid adding these queries to the existing `Application_Window_Service` without
clarifying its target: that service currently controls the secondary-window
manager, including from the primary application's callbacks. A chrome service
should always refer to the window whose callbacks received it.

Applications continue to use ordinary `alicorn.tab_bar`, controls, semantic
actions, and their own document state. The host retains native resources,
geometry, and interaction metadata; it does not retain application closures,
document pointers, or a model of Scratchpad tabs.

## Native adapter details

### Window setup and lifetime

Obtain the SDL-owned `NSWindow` with `SDL_GetWindowProperties`. Preserve its
titled, closable, miniaturizable, and resizable styles; add full-size content,
hide only the visible title, and make the titlebar background transparent.
Keep the meaningful window title for native accessibility and window lists.
This does not require a transparent SDL/GPU window. SDL exposes the native
pointer but no equivalent titlebar option in its pinned 3.4.16 public header.
[Window properties](https://wiki.libsdl.org/SDL3/SDL_GetWindowProperties),
[pinned SDL header](https://github.com/libsdl-org/SDL/blob/release-3.4.16/include/SDL3/SDL_video.h).

Preserve SDL's content view, delegate, text input, and event listener. Use removable
notification/KVO observers for geometry, focus, scale, and fullscreen changes.
The pinned Cocoa backend can rebuild style masks during fullscreen and other
window changes, so reconcile the extension after those transitions settle;
do not repeatedly change styles while drawing or during an animation.
[Pinned Cocoa backend](https://github.com/libsdl-org/SDL/blob/release-3.4.16/src/video/cocoa/SDL_cocoawindow.m).

### Measure controls and convert coordinates once

Query the window's existing `standardWindowButton` objects. Convert each
button's bounds into the SDL content view; a frame instead must be converted
from its superview. Preserve the actual native controls and their hit areas.
[Existing window buttons](https://developer.apple.com/documentation/appkit/nswindow/standardwindowbutton(_:)),
[view rectangle conversion](https://developer.apple.com/documentation/appkit/nsview/convert(_:to:)-3cqqt).

`contentLayoutRect` reports unobscured content in window coordinates. It and
safe-area insets are useful body-layout inputs but not an exact three-button
exclusion map. Reserving their full top inset before laying out the tabs would
put tabs back below the controls. [Content layout rectangle](https://developer.apple.com/documentation/appkit/nswindow/contentlayoutrect),
[view safe area](https://developer.apple.com/documentation/appkit/nsview/safeareainsets).

Publish geometry in top-left SDL window logical units. For unflipped view bounds
`B` and converted rectangle `R`, use `x = minX(R) - minX(B)` and
`y = maxY(B) - maxY(R)` before applying the actual SDL-view transform. Handle
flipped views separately. Round exclusion edges outward, and apply the existing
logical-to-pixel transform only at the renderer boundary. Do not multiply all
coordinates by a guessed Retina factor.

For the first fixture keep the controls in AppKit's default positions. For a
polished taller header, native control insetting needs its own bounded decision:
Electron's inset mode actually adjusts the button/container layout, and its
proxy contains OS-version-specific relayout handling. Three style flags alone
do not promise vertically centered controls in an arbitrary 44-point row.
Prefer measuring and a host-resolved header height initially; add a compact/inset
policy only with resize/fullscreen validation. [Electron native inset policy](https://github.com/electron/electron/blob/30db518815328281dcebeec382baf9b44dea2bf7/shell/browser/native_window_mac.mm#L241),
[button proxy](https://github.com/electron/electron/blob/30db518815328281dcebeec382baf9b44dea2bf7/shell/browser/ui/cocoa/window_buttons_proxy.mm).

### Window drag and application gestures

Try SDL's hit-test path against the published geometry. The callback should only
read bounded host-owned data; no layout, AppKit measurement, application
callbacks, or allocation. Native-control exclusions, tabs, tab-close buttons,
toolbars, splitters, text inputs, popups, and captured app gestures remain normal
input. Only explicitly blank areas are window-drag areas. SDL documents that
special hit-test areas can consume input. [SDL hit testing](https://wiki.libsdl.org/SDL3/SDL_SetWindowHitTest).

The pinned Cocoa backend consumes draggable events and may also consume a
transition event after leaving such an area. Test hover-then-click boundaries
and stationary-pointer geometry changes. A tab gesture must retain ownership
until release/cancel even when it crosses blank chrome. If the proof needs
AppKit's `performWindowDragWithEvent`, choose one drag path per gesture and
account for its potentially missing mouse-up. [SDL Cocoa implementation](https://github.com/libsdl-org/SDL/blob/release-3.4.16/src/video/cocoa/SDL_cocoawindow.m),
[AppKit system window drag](https://developer.apple.com/documentation/appkit/nswindow/performdrag(with:)).

### Fullscreen, text, menus, and idle

Refresh geometry on relevant native events and after app layout changes, then
coalesce one wake/invalidation only when the snapshot changes. No periodic
polling and no style/geometry mutation inside hit testing. Observers and
snapshots belong to the native window and are removed before destruction.

Keep SDL's normal fullscreen lifecycle, AppKit control reveal, and appropriate
screen safe areas. In native fullscreen, do not add screen/titlebar insets a
second time. Treat fullscreen transition/failure/restore as explicit states.
The pinned SDL safe-area API is not a documented traffic-light geometry API.
[SDL fullscreen policy](https://wiki.libsdl.org/SDL3/SDL_HINT_VIDEO_MAC_FULLSCREEN_MENU_VISIBILITY),
[screen safe area](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets).

The app viewport in content-titlebar mode includes the top row; host-owned
caption inset should be zero. App layout reserves the header once. The caret's
final position must still reach SDL text-input candidate geometry and AccessKit
screen bounds through the same window-coordinate transform. Custom tabs need
their existing accessibility semantics and keyboard focus, while native controls
remain AppKit-accessible. [SDL text-input area](https://wiki.libsdl.org/SDL3/SDL_SetTextInputArea),
[AppKit accessibility](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol).

Keep NSMenu on the existing semantic command path and verify shortcuts against
the focused primary/floating document. Window styling does not install editor
commands or prevent duplicate accelerator dispatch. Application-global menu
ownership must remain separate from each window's chrome lifecycle.
[AppKit main menu](https://developer.apple.com/documentation/appkit/nsapplication/mainmenu).

## Remaining validation and decision

The first fixture and Scratchpad integration are complete. Keep the feature
opt-in. Before broad product use, validate mixed-scale monitor transitions,
focus-loss interruption, IME composition/candidate placement, VoiceOver,
floating-window behavior, and titlebar double-click preferences. These are
remaining platform-coverage items, not blockers for the verified primary-window
tab and drag interaction.

Native acceptance must cover click/close/reorder/detach across the entire top
row; capture and drag-boundary transitions; narrow windows and RTL; every native
control, hover and Option behavior; native titlebar double-click preferences;
mixed-scale monitors; fullscreen entry, exit, hover reveal and cancellation;
IME candidates near the top edge; VoiceOver; menu shortcuts; primary/floating
focus and shutdown. Automated startup is insufficient for those interactions.

Core full-size/titlebar APIs predate Scratchpad's macOS 13 deployment floor;
newer AppKit additions still need availability guards. Qt's expanded-area APIs
begin at 6.9; Electron's current docs and pinned source describe their own
versions. The Firefox `main` links are moving references inspected during the
research, not a claim about every shipped Firefox version. The current host
requires SDL 3.4.18, and the titlebar remains an explicit opt-in rather than a
new default for every application.
