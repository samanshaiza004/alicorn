# macOS integrated-titlebar input fixture

This is a bounded native proof for Alicorn's proposed macOS integrated titlebar.
It uses one SDL window, Alicorn's ordinary retained tab bar and text field, and
AppKit's standard window controls. It adds no public chrome API and no second
Runtime.

## Rebuild and run

Use SDL 3.4.16 and run:

```sh
SDL3_PREFIX=/path/to/SDL-3.4.16 tools/build_macos_titlebar_fixture.sh
open out/native-titlebar-fixture/AlicornTitlebarFixture.app
```

Run the opt-in native geometry regression on an unlocked desktop:

```sh
out/native-titlebar-fixture/AlicornTitlebarFixture.app/Contents/MacOS/AlicornTitlebarFixture --geometry-check
```

It uses the actual AppKit window and the fixture's ordinary Alicorn builder,
checks green-control and menu fullscreen entry, two restore cycles and resizing,
and prints native/SDL/finalized-layout measurements before returning a status.
Its bounded event pumping runs only in this diagnostic mode.

If AccessKit is not already available to the checkout's common build helper,
set `ALICORN_ACCESSKIT_LINK_FLAGS` to its static-library linker flags. The app
retains Alicorn's strict SDL version check. `SDL3_LIBRARY` can select a dylib
explicitly.

## Observed on Apple Silicon

Test environment: macOS 27, Retina scale 2, bundled SDL 3.4.16 (`current
version 401.16.0`). Native observations below were made against the fixture
window on the unlocked desktop.

- AppKit's standard close/minimize/fullscreen controls were present and their
  measured bounds were `{x=9,y=9,w=14,h=14}`, `{x=32,y=9,w=14,h=14}`, and
  `{x=55,y=9,w=14,h=14}` in logical points. The rendered tabs began after the
  measured control cluster and shared the 44-point header row.
- A real pointer click selected the second tab. A real pointer click on its
  close affordance closed it without closing the window.
- Clicking the Alicorn text field and typing `titlebar text probe` displayed
  the typed value in the field. This exercises ordinary SDL client input,
  including the text-change callback and app-owned text state.
- Pinned SDL 3.4.16 source explains a coordinate mismatch observed before the
  fixture bridge: Cocoa's hit-test callback uses the current `NSEvent` point,
  while SDL's queued button event can use stale `mouse->x/y`. The fixture now
  pairs bounded native hit-test samples with SDL pointer events and uses the
  contemporaneous point. See the pinned
  [SDL Cocoa backend](https://github.com/libsdl-org/SDL/blob/release-3.4.16/src/video/cocoa/SDL_cocoawindow.m).
- A drag initiated on a tab selected the tab but did not increment the fixture's
  reorder count. The automation delivered a down/up pair and only an endpoint
  motion, not a reliable held-motion sequence. Therefore tab reordering has not
  been demonstrated with a physical gesture.
- A drag attempt in the explicitly declared blank tail produced three Cocoa
  `SDL_EVENT_WINDOW_HIT_TEST` callbacks. The fixture's AppKit frame diagnostic
  read `{x=270,y=155}` before and after that automation drag, so it did not
  demonstrate actual window movement. A physical held drag is still required
  to distinguish an automation limitation from an input-arbitration defect.
- Fullscreen now retains a normal-height header and a visible body. The native
  green control and menu action both enter fullscreen; an active text field
  accepts input there, and Escape returns to the original 900×560-point window
  with text and focus preserved. The live diagnostic reports `true (1/0)` while
  fullscreen and `false (1/1)` after exit. Escape first lets menus, a tab drag,
  or IME composition consume cancellation before the fixture exits fullscreen.
- Style-mask reapplication is skipped in the fullscreen transition callbacks.
  It preserves the existing SDL content-view responder link around any later
  `setStyleMask` call, following SDL's AppKit responder-chain repair pattern.
  Post-transition text entry exercises this path at a basic level; IME
  composition remains untested.
- Only the initial Retina scale was exercised. Live resize, moving between
  displays/scales, gesture cancellation after focus loss, and idle-work counts
  were not proven by this desktop run.
- Cocoa-consumed hit-test samples are drained when SDL reports
  `SDL_EVENT_WINDOW_HIT_TEST`; a consumed release also clears the latched owner.
  This prevents a Cocoa-owned pointer coordinate from being paired with a later
  ordinary client event. The bounded queue behavior is unit-tested.

## Confirmed fullscreen causes and regression

The native regression reproduced the original screenshot twice before the fix,
without creating a GPU renderer. In fullscreen AppKit's hidden/reparented
traffic-light rectangles converted to `y=877`. The old `button_bottom+12`
calculation therefore requested a 903-point header in a 900-point viewport.
The retained layout obeyed it and gave the body zero height.

The app now chooses the header height independently. Native controls exclude
only visible, overlapping header space; safe-area top inset is separate from
the row height. Hidden/transitional button geometry cannot enlarge the row.

| Native phase | Viewport | Header height | Body height |
| --- | --- | --- | --- |
| Windowed | 900×560 | 44 | 516 |
| Fullscreen before fix | 1440×900 | 903 | 0 |
| Fullscreen after fix | 1440×900 | 44 | 856 |
| Restored after two cycles | 900×560 | 44 | 516 |
| Resized | 720×480 | 44 | 436 |

The restore defect was separate: AppKit changed the native frame from
900×560 to 900×528 inside `setStyleMask` when re-adding `FullSizeContentView`.
The adapter now preserves the complete restored frame around reapplication;
initial setup still preserves the requested content size. Host metrics are read
after that repair, including in the retained live-resize path. SDL's fullscreen
style construction omits the full-size-content bit, so reapplication is still
necessary. See the [pinned Cocoa backend](https://github.com/libsdl-org/SDL/blob/release-3.4.16/src/video/cocoa/SDL_cocoawindow.m).

The apparent missing fullscreen event was ruled out: the diagnostic harness
observed both SDL events, and the corrected live layout displays the expected
enter/leave counts. Fixture-only event callbacks are guarded before casting
application state, so ordinary apps with native menus are unaffected.

## Verification

- macOS `odin test native/sdl_gpu`: 90 tests passed, including measured-rect
  conversion, native/Sdl point pairing, gesture ownership, and fullscreen style
  mutation guards, consumed-sample draining, safe-area/hidden-control geometry,
  and isolation from ordinary application state.
- `odin check native/sdl_gpu -target:windows_amd64 -no-entry-point`: passed.
- The macOS fixture app bundle built and passed ad-hoc code-sign verification
  against the pinned SDL dylib.
- `--geometry-check`: passed green-control/menu entry, two fullscreen restores,
  and resize on the actual Apple Silicon desktop.

## Desktop test matrix

| Action | Current result |
| --- | --- |
| Select/close a titlebar tab | Passed visibly |
| Type in a normal field | Passed in windowed/fullscreen and after restore |
| Green-control and native-menu fullscreen entry | Passed; header/body remain visible |
| Escape from focused fullscreen field | Passed; original size and text restored |
| Repeated fullscreen restore | Two native regression cycles passed without height loss |
| Resize | Native 720×480 geometry regression passed |
| Retina | Scale 2 passed; another display/scale remains untested |
| Physical tab reorder / blank-header window move | Still requires a physical held-gesture pass |
| Interrupted physical drag, IME, VoiceOver | Still requires desktop validation |
| Idle after interaction | Pending explicit counter capture |

## Current API recommendation

Keep Scratchpad's tabs as an ordinary Alicorn `tab_bar`; do not add an AppKit
tab view or a second Runtime. The live click and text-field evidence supports
keeping the tabs in Alicorn's content view. Do **not** freeze a public chrome
API yet: tab-drag ownership, native window movement, Retina display changes,
and cancellation still need a physical desktop pass.

The likely minimum API remains an opt-in integrated-content window mode plus
host-measured chrome metrics and explicit interactive/blank-drag regions, with
layout-resolved geometry copied into the host. The fixture supports that
direction but does not yet establish its full contract. If a physical drag or
fullscreen event is consumed without the expected SDL event, record the exact
AppKit behavior before considering a titlebar accessory view or another
supported integration path.
