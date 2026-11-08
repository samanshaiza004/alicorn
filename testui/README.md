# Headless application interaction tests

`alicorn:testui` runs an application's ordinary Alicorn description and state
callbacks against the real retained runtime, without creating a native window
or GPU device. Use it to test interactions that depend on focus, semantics,
hit testing, layout, virtualization, and scroll reveal.

```odin
package example_test

import "core:testing"
import alicorn "alicorn:runtime"
import testui "alicorn:testui"

@(test)
test_save_button :: proc(t: ^testing.T) {
    app := Example_App{}
    h, status := testui.open(&app, example_describe, width=480, height=320)
    defer if h.runtime != nil { testui.close(&h) }
    if !testing.expect(t, status == .Ok, testui.last_turn_diagnostic(&h)) { return }

    save := testui.find(&h, testui.Query{
        role=.Button,
        name="Save",
        match_role=true,
        match_name=true,
    })
    defer testui.destroy_find_result(&save)
    testing.expect(t, save.match == .Unique && save.element.has_bounds,
        "Save should have one semantic node and finalized bounds")
    testing.expect(t, testui.click(&h, &save.element) == .Ok,
        "coordinate input should activate Save through normal hit testing")
    testing.expect(t, app.save_count == 1, "the application should observe the click")
}
```

For an application whose native build callback owns `begin_frame` and
`end_frame`, pass that full callback instead of a subtree renderer:

```odin
h, status := testui.open(
    &app,
    width=480,
    height=320,
    build_application=application_build,
    on_key=application_on_key,
)
```

`build_application` receives the borrowed state pointer, test runtime, logical
viewport size, and display scale. It lets an integration test exercise the
same application composition, focus setup, semantic descriptions, and callbacks
as the native host without creating an SDL window or GPU device. Supplying both
`render` and `build_application`, or neither, returns `.Invalid_Application`.

## Input and queries

- `Key` is Alicorn's logical application-key vocabulary after platform
  translation. It tests shared routing and callbacks; it does not simulate OS
  scancodes, native menu shortcut matching, or platform modifier conventions.
  Text-editing keys such as `Word_Left` and `Delete_Word_Backward` directly
  express the normalized intent delivered to a generic editor callback.
- `step` delivers one typed input turn. A key turn includes up to four normal
  application descriptions while Alicorn's root is invalidated; it does not
  keep describing until arbitrary application work stops.
- `open` performs an initialization description before returning. Its turn
  report says `input=initialization` and `key=none`; `.Initial_Description` is
  reserved for that report and is rejected if passed to `step`.
- `click_at` injects pointer down/up at logical window coordinates. `click`
  uses a current `Element` snapshot, rejects stale snapshots, checks hit-test
  ownership, and then sends ordinary pointer input.
- `Input{kind=.Semantic_Action}` sends an advertised semantic action. This
  tests the semantic contract and is deliberately distinct from a coordinate
  click. A virtual semantic item can accept logical actions without being
  physically clickable.
- `find` reads semantics published by the application/runtime. It never
  guesses accessible names from visible text. Name, role, and explicit key
  filters can be combined; results distinguish none, unique, and ambiguous.
- Each returned `Element` owns its strings and remains a value snapshot. Call
  `destroy_element` or `destroy_find_result` when finished. After an input or
  description, query again before using its bounds to interact.
- `Text_Commit`, `Text_Preedit`, and `Text_Cancel` exercise retained text-field
  input/composition state. For a focused generic `text_input_target`, these
  events reach the same application text-input callback as the native host;
  preedit selection offsets are UTF-8 byte offsets. The text-change and
  text-input callbacks borrow their strings for that callback; clone data the
  application retains.
- `advance_time` advances the harness's monotonic virtual clock explicitly
  and ticks retained motion once. No real sleep or automatic time advancement
  occurs. `last_turn` and `last_turn_diagnostic` explain bounded-turn failures.
  `Turn_Report.key_valid` distinguishes an actual key input from other turns,
  and `pointer_target` retains the physical hit-test result after corrective
  descriptions finish.

## Bounded replay logs

`replay_log_create`, `replay_log_step`, `replay_log_encode`,
`replay_log_decode`, and `replay_log_play` record and replay up to 256 typed
input turns. Each turn records the input kind, stable semantic pointer/focus
IDs, semantic revision before and after the turn, causal ID/kind/action, and
deterministic retained-work deltas for descriptions, reconciliation, measure,
layout, paint, composition, text shaping, and semantic publication. Application
tests still assert their own model state; the harness does not reflect
arbitrary application memory.

Committed text, preedit text, and semantic-action text are **redacted by
default**. The log keeps byte counts and refuses replay if a required text
payload was omitted. Pass `include_text=true` only for fixture data that is
safe to store: opted-in logs contain those exact strings. The recorder caps
logs at 256 turns and 64 KiB of captured text; encoded files are limited to
1 MiB. Treat text-enabled recordings as source documents.

```odin
log := testui.replay_log_create()
defer testui.replay_log_destroy(&log)

status, log_error := testui.replay_log_step(&log, &handle,
    testui.Input{kind=.Key, key=.Page_Down})
if status != .Ok || log_error != .None { return }

data, log_error := testui.replay_log_encode(&log)
defer delete(data) // bytes belong to the allocator passed to encode
if log_error != .None { return }
```

Decode the artifact and call `replay_log_play` on a fresh handle initialized
with the same fixture state. Playback checks semantic identity, focus,
revision, stabilization, and cause metadata. `compare_work=true` also requires
exact retained-work counters, which is useful for same-build regression runs
and may intentionally differ across Alicorn revisions.

Replay logs are CPU-only and do not contain pixels. For a native visual
artifact, run the same fixture through the native host's
`--diagnostics --capture-after=N --capture-dir=...` path; it writes a PPM
screenshot alongside platform/runtime diagnostics. Keep pixel baselines
specific to the backend and display scale. See the
[native diagnostics guide](../docs/development.md#native-diagnostics).

## Guarantee boundary

The harness uses Alicorn's standard runtime, bundled fonts, semantic queries,
layout, and shared host-independent input-routing decisions. Pointer input is
logical window input, so it exercises hit testing and clipping; it does not
model an OS device driver.

It does not create SDL, a GPU device, or a platform accessibility bridge. It
cannot verify rendered pixels, shaders/backdrop effects, native menus/dialogs,
window chrome, physical input latency, OS IME candidate windows, or native
text-input activation. Those remain native-host validation responsibilities.
Synthetic preedit only tests Alicorn's composition handling.

The package has no SDL or AccessKit link requirement. Run its suite with the
repository toolchain:

```sh
odin test testui -collection:alicorn=/path/to/alicorn
```

The standard `tools/test.sh`, `tools/check.sh`, `tools/test.ps1`, and
`tools/check.ps1` commands include this suite.
