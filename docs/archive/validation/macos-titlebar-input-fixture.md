# macOS integrated-titlebar input fixture

This record covers the bounded native proof for Alicorn's macOS content titlebar.
It uses one SDL window, Alicorn's ordinary retained tab bar and text field, and
AppKit's standard window controls. The fixture and Scratchpad use the public
Content_Title_Bar contract; there is no second Runtime or native tab view.

## Rebuild and run

Use SDL 3.4.18, the version required by Alicorn's macOS host, and run:

```sh
SDL3_PREFIX=/path/to/SDL-3.4.18 tools/build_macos_titlebar_fixture.sh
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

Original interactive validation: macOS 27, Retina scale 2, bundled SDL 3.4.16
(`current version 401.16.0`). The observations below record that validation;
the fixture build now requires the host's SDL 3.4.18.

- AppKit's standard close/minimize/fullscreen controls were present and their
  measured bounds were `{x=9,y=9,w=14,h=14}`, `{x=32,y=9,w=14,h=14}`, and
  `{x=55,y=9,w=14,h=14}` in logical points. The rendered tabs began after the
  measured control cluster. The final compact preset uses a 32-point row;
  the original correctness proof used 44 points independently of native controls.
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
- Physical testing initially exposed a second native drag path: tab drags moved
  the window even though SDL classified them as ordinary client input. Disabling
  `movableByWindowBackground` did not disable native titlebar dragging. The
  fixture now also gates AppKit's public `isMovable` property from the latched
  hit-test decision, including hover before mouse-down. Only explicit blank drag
  regions enable window movement. See [Apple's property contract](https://developer.apple.com/documentation/appkit/nswindow/ismovable).
- After that fix, the user physically confirmed tab reordering and blank-header
  window movement. Native logs recorded `Started → Target_Changed → Dropped`
  for application tab drags, and `Cancelled` when releasing outside a valid tab
  target. The final live counters showed four reorders, two cancellations and
  two closes; the window moved from `{270,155}` to `{0,143}` and survived a
  fullscreen round trip at 900×560 points. SDL consumed native window-drag
  transitions as `SDL_EVENT_WINDOW_HIT_TEST`; they were not ordinary tab events.
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
- The native geometry regression exercises resize. Retina scale 2 was exercised
  live; moving between displays/scales and interrupted focus-loss gestures still
  need a dedicated physical pass.
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
| Windowed, final compact preset | 900×560 | 32 | 528 |
| Fullscreen before fix | 1440×900 | 903 | 0 |
| Fullscreen after fix, compact preset | 1440×900 | 32 | 868 |
| Restored after two cycles | 900×560 | 32 | 528 |
| Resized | 720×480 | 32 | 448 |

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

- Full `tools/test.sh`: foundation suite, 224 runtime tests, 35 theme tests,
  theme CLI/code-generation checks and generic text-input host contract passed.
- macOS `odin test native/sdl_gpu`: 93 tests passed, including measured-rect
  conversion, native/Sdl point pairing, gesture ownership, and fullscreen style
  mutation guards, consumed-sample draining, safe-area/hidden-control geometry,
  isolation from ordinary application state, empty tab strips, and retained-only
  splitter layout with fractional presentation scaling. The latter changes the
  host drag region without emitting another application description. The
  narrow-width check also covers 400- and 320-point windows, where the selected
  tab remains visible and overflow controls appear at the minimum tab width.
- `odin check native/sdl_gpu -target:windows_amd64 -no-entry-point`: passed.
- The macOS fixture app bundle built and passed ad-hoc code-sign verification
  against the pinned SDL dylib.
- `--geometry-check`: passed green-control/menu entry, two fullscreen restores,
  native `isMovable` gating, and resize on the actual Apple Silicon desktop.
- The headless retained-work benchmarks passed: 10,000 idle attempts over a
  10,001-node tree emitted nothing, allocated nothing and visited no stages;
  a million-item virtual list retained 23 nodes. These are workload counts,
  not universal wall-clock claims.
- A six-second native idle run submitted exactly one startup frame, with one
  text-mesh build/upload, no application/native-host wake events, and no app tick.
  The validation deadline wakes the loop once to finish; normal mode adds none.

## Compact presentation and geometry ownership

The fixture opts into `Tab_Bar_Options.presentation = .Compact`, 150–180-point
tabs, a scoped 13-point text scale, softer local colors, and selected/hover-only
close glyphs. Labels use intrinsic text height and share the close target's
vertical center; one-point top/bottom tracks balance the selection indicator.
The default Standard tab appearance remains unchanged.

The strip is capped at its actual tabs (including overflow controls when needed),
and an explicit growing blank container receives the rest. The host copies both
resolved rectangles after description, retained-only presentation, and live
resize layout. It never estimates them in its hit-test callback. The public
content-titlebar API now exposes this host-owned geometry contract, and
Scratchpad uses it to publish its real tab and blank-drag nodes.

## Current checkout retest (2026-10-22)

The fixture bundle rebuilt and passed ad-hoc code-sign verification against the
installed SDL 3.4.18. It launched through the desktop app path. On the unlocked
Apple Silicon desktop, entering fullscreen with the native green control showed
the 32-point tab row and fixture body at 1440×900 logical points; the app
reported `fullscreen=true (1/0)`. Restoring returned to the windowed fixture.
The automated `--geometry-check` invocation could not be repeated from the
current shell: macOS aborted in `_RegisterApplication` while `NSApplication`
was initializing, before the native check or window setup ran. That launch-path
limitation did not affect the desktop-launched fixture or the earlier recorded
automated fullscreen regression result.

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
| Physical tab reorder / blank-header window move | User confirmed; four reorders and native movement recorded |
| Tab release outside valid target | Native logs/counters record cancellation |
| Interrupted focus-loss drag, IME, VoiceOver | Still requires desktop validation |
| Idle | Six-second unfocused-field run: one startup submission, zero worker/host wakes |

## API conclusion

Keep Scratchpad's tabs as an ordinary Alicorn `tab_bar`; do not add an AppKit
tab view or a second Runtime. The live click, close, reorder, blank-window-drag,
fullscreen, and text-field evidence supports keeping tabs in Alicorn's content
view. The minimum public contract is now implemented: Application opts into
`.Content_Title_Bar`, sets `window_chrome_height`, receives measured
`Window_Chrome_Metrics`, and returns a `Window_Chrome_Layout` with one header
node and explicit `.Interactive` / `.Window_Drag` retained-node regions. The
host copies finalized geometry and preserves the existing native gesture
arbitration. Scratchpad now dogfoods that contract while retaining ownership of
document tabs and their actions.

Retina scale 2 is verified; moving between displays/scales, focus-loss
interruption, IME composition, and VoiceOver remain dedicated follow-up checks.
Those gaps do not invalidate the user-confirmed click/close/reorder/window-drag
contract or the fullscreen geometry result.
