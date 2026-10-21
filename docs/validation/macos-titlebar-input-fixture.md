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
- Clicking the native green traffic-light control removed the native controls
  and entered a full-display AppKit state. One immediate capture showed the
  fixture body; the next stable capture showed only the tab strip. The fixture
  diagnostic remained `fullscreen=false (0/0)` during that state, so it did not
  observe an SDL fullscreen event or refresh its state. Selecting the View-menu
  `Enter Full Screen` toggle returned the window to windowed mode, restored the
  native controls, and reported `fullscreen=false (1/1)`. But its logical size
  changed from 900×560 points before entry to 900×528 after exit (32 points
  shorter). Treat the inconsistent fullscreen capture/event diagnostics and
  changed restore geometry as a **failure to investigate**, not an acceptance
  pass. Typing `input-after-exit` into the ordinary text field worked after
  returning to windowed mode.
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

## Verification

- macOS `odin test native/sdl_gpu`: 88 tests passed, including measured-rect
  conversion, native/Sdl point pairing, gesture ownership, and fullscreen style
  mutation guards, plus consumed-sample draining.
- `odin check native/sdl_gpu -target:windows_amd64 -no-entry-point`: passed.
- The macOS fixture app bundle built and passed ad-hoc code-sign verification
  against the pinned SDL dylib.
- The native checks do not substitute for the unverified held-drag/window-move,
  fullscreen-rendering, resize, IME, and idle acceptance cases above.

## Current API recommendation

Keep Scratchpad's tabs as an ordinary Alicorn `tab_bar`; do not add an AppKit
tab view or a second Runtime. The live click and text-field evidence supports
keeping the tabs in Alicorn's content view. Do **not** freeze a public chrome
API yet: tab-drag ownership, native window movement, fullscreen persistence,
resize/Retina changes, and cancellation still need a physical desktop pass.

The likely minimum API remains an opt-in integrated-content window mode plus
host-measured chrome metrics and explicit interactive/blank-drag regions, with
layout-resolved geometry copied into the host. The fixture supports that
direction but does not yet establish its full contract. If a physical drag or
fullscreen event is consumed without the expected SDL event, record the exact
AppKit behavior before considering a titlebar accessory view or another
supported integration path.
