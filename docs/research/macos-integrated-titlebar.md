# macOS integrated titlebar proposal

Research date: 2026-10-20. Status: proposal; no titlebar implementation changes.
Repository evidence: Alicorn `d0cf8f5`, Scratchpad `eae8c9b`. See the separate
[macOS validation record](../validation/macos-sync-2026-10-20.md) for tests,
native launches, packaging, and the two development setup problems reproduced.

## Recommendation

Keep the real AppKit window controls and existing native system menu. Extend
the SDL content view into the titlebar and let Scratchpad render its ordinary
tabs there. The native host owns control geometry, window dragging, and lifecycle;
Scratchpad owns documents, tab selection/reordering/detachment, and layout.

These are two separate macOS surfaces:

- The **system menu bar** is at the top of the display. Alicorn already has an
  AppKit `NSMenu` adapter and semantic command dispatch.
- The **window titlebar/tab row** is the surface shown in the user's reference
  screenshots. This is the missing integration.

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

## Current implementation and the missing seam

`native/sdl_gpu/menus_darwin.odin` installs the native menu through AppKit.
The existing [menu/titlebar documentation](../native-menus-and-integrated-titlebar.md)
explicitly describes `Integrated_Title_Bar` as preserving standard macOS chrome.
Scratchpad selects `System` on Darwin in `frontends/alicorn/main.odin:2889`.
Its document tabs are inside the editor pane in `app_layout.odin:140`.

Windows now has a different contract: the host renders a fixed title/menu/caption
band and translates application content below `content_inset_top`. That is
appropriate to that existing host-owned band, but it does not provide a place
for Scratchpad's interactive document tabs. Extending that inset to macOS would
keep the very second row this proposal is intended to remove.

The secondary-window path also needs explicit attention: on Darwin,
`secondary_window_host.odin` clears child menus and forces `System` decorations.
The system menu is application-global; titlebar geometry is per window. Prepare
per-window chrome independently of installing the global NSMenu, including for
a window with no menu descriptions.

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

## First milestone: prove real titlebar input

The first native fixture should contain a real Alicorn tab/close button inside
the actual titlebar band, a text input below it, and adjacent blank drag space.
Verify selection, close, tab drag, and window drag before finalizing the public
API or migrating the workbench.

There is a concrete reason for this order. Firefox's `NonDraggableView`
implementation says ordinary `mouseDownCanMoveWindow = NO` does not prevent
all forced titlebar dragging in a full-size content window; it uses an
undocumented override. That is a source observation about Firefox's integration,
not proof that Alicorn necessarily needs it. An SDL `NORMAL` hit-test result alone
does not establish that the OS will deliver an interactive tab gesture.
[Firefox source, `NonDraggableView` and frame handling](https://github.com/mozilla-firefox/firefox/blob/main/widget/cocoa/nsCocoaWindow.mm).

Use public AppKit/SDL mechanisms in the fixture first. If they cannot meet the
input contract, evaluate a documented native control/accessory integration and
record the tradeoff before choosing a different backend technique. Do not
silently copy browser swizzling or private selectors.

## Proposed public contract

Keep the final API small. These names are sketches, not existing APIs:

1. An opt-in **content titlebar** decoration mode. `System` remains the default.
   A separate enum value such as `Content_Title_Bar` would distinguish app-owned
   content from the existing Windows host-owned integrated menu band.
2. A read-only **window chrome metrics** snapshot, bound to the current window:
   full logical bounds, top-band bounds, native control exclusions, unobscured
   body bounds, fullscreen/transition state, validity, and a revision.
3. Declarative **drag / interactive regions** tied to resolved retained layout.
   A convenience helper should cover ordinary containers and tab bars; applications
   should not duplicate caption pixel arithmetic.

The native host can resolve node-based declarations into copied rectangles
after layout and presentation. Their meaning must survive region reuse and
retained-only geometry changes, such as a splitter drag that does not call the
application builder. Retired nodes must stop contributing regions. The final
primitive should be chosen after the native fixture establishes what the
backend needs; this proposal does not prescribe a callback registry or another
widget tree.

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

## Implementation sequence and acceptance

1. Add a bounded native fixture for full-size drawing, actual titlebar input,
   native controls, and blank dragging. Resolve the forced-drag and header-height
   questions before expanding the public API.
2. Add the smallest public metrics/region contract proved necessary by that
   fixture, support primary and floating windows, and migrate Scratchpad's
   existing tab layout. Keep the default `System` path and current Windows mode.
3. Lock down geometry transforms, exclusion priority, retired/retained regions,
   splitter-only layout changes, and zero recurring idle work in deterministic
   tests. Complete the native matrix before making the mode a product default.

Native acceptance must cover click/close/reorder/detach across the entire top
row; capture and drag-boundary transitions; narrow windows and RTL; every native
control, hover and Option behavior; native titlebar double-click preferences;
mixed-scale monitors; fullscreen entry, exit, hover reveal and cancellation;
IME candidates near the top edge; VoiceOver; menu shortcuts; primary/floating
focus and shutdown. Automated startup is insufficient for those interactions.

Core full-size/titlebar APIs predate Scratchpad's macOS 13 deployment floor;
newer AppKit additions still need availability guards. Qt's expanded-area APIs
begin at 6.9; Electron's current docs and pinned source describe their own
versions. The Firefox `main` links are moving references inspected for this
proposal, not a claim about every shipped Firefox version. The proposal does
not require an SDL upgrade or promise the first direct-SDL proof will pass.
