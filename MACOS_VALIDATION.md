# macOS Validation

Date: 2026-09-13

Recommendation: `MACOS_READY_WITH_GAPS`

The current `master` compositor and Runa-enabled headless foundation run on
the tested Apple Silicon macOS configuration. The native fixture exercises the
real retained rectangle compositor through SDL_GPU Metal, including logical to
physical scaling, resize handling, three-frame retirement, and clean shutdown.
IME composition, glyph-atlas rendering, Intel macOS, and hosted macOS CI remain
unverified.

## Baseline

- Base SHA: `702a56527137bb7aca32dfd67e2ddf7e0c114825`
- Base branch: `master`; tree clean before validation changes
- Validation branch: `port/macos-current-702a565`
- macOS: 26.6.2, build 25G83
- Architecture: Apple Silicon, `arm64`
- Darwin: 25.6.0
- Xcode: 26.6, build 17F113
- Developer directory: `/Applications/Xcode.app/Contents/Developer`
- Clang: Apple clang 21.0.0, target `arm64-apple-darwin25.6.0`
- Odin: `dev-2026-09-nightly:a2fb372`
- Odin executable: `/Users/keina/Documents/odin-macos-arm64-nightly+2026-09-01/odin`
- SDL3: 3.4.14 from Homebrew at `/opt/homebrew/opt/sdl3`
- SDL3 library: arm64 `/opt/homebrew/opt/sdl3/lib/libSDL3.0.dylib`
- GPU: Apple M1, 8 cores; Metal supported

## Existing tests

| Command | Result | Notes |
| --- | --- | --- |
| `git diff --check` | PASS | Clean before changes and after validation changes |
| `ALICORN_ODIN=/Users/keina/Documents/odin-macos-arm64-nightly+2026-09-01/odin ./tools/test.sh` | PASS | `Alicorn foundation tests: PASS` |
| `ALICORN_ODIN=/Users/keina/Documents/odin-macos-arm64-nightly+2026-09-01/odin ./tools/check.sh` | PASS | Builds tests, benchmarks, identity, Crucible, and Runa targets; runs tests |
| `ALICORN_ODIN=/Users/keina/Documents/odin-macos-arm64-nightly+2026-09-01/odin ./tools/bench.sh` | PASS | Raw macOS sample below |
| `odin build examples/identity_torture && ./out/identity_torture` | PASS | 5,000 operations; 3 live nodes |
| `odin build examples/crucible && ./out/crucible` | PASS | 27 retained nodes; 31 regions skipped; 5 composites |
| `odin build examples/runa_text && ./out/runa_text /System/Library/Fonts/Supplemental/Georgia.ttf` | PASS | Real font load, multiline/wrap metrics, cache `4 -> 4` |

The current-master direct baseline was also built and run before source
changes: tests, benchmarks, identity torture, Crucible, Runa compilation, and
the existing native compositor all compiled successfully. The untouched native
compositor silently stopped after three submissions on this Mac because it
treated a temporarily unavailable swapchain texture as a dropped frame.

### Benchmark sample

Odin `dev-2026-09-nightly:a2fb372`, Apple M1, macOS 26.6.2; raw wall-clock
nanoseconds, not a cross-platform performance comparison.

| workload | first ns | unchanged ns | one change ns | keyed reorder ns | retained nodes | adjacency rebuilds |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 100 nodes | 361000 | 131000 | 134000 | 145000 | 101 | 2 |
| 1,000 nodes | 3065000 | 1364000 | 2205000 | 2842000 | 1001 | 2 |
| 10,000 nodes | 40437000 | 14889000 | 15152000 | 16012000 | 10001 | 2 |

- Virtual list: 1,000,000 logical rows, 100 frames, `6675000 ns`, 23 retained nodes.
- Idle: 10,000 attempted frames, `24000 ns`, `idle_count=10000`, GPU submits `0`.

## Native validation

Command:

```sh
ALICORN_ODIN=/Users/keina/Documents/odin-macos-arm64-nightly+2026-09-01/odin ./tools/native_sdl_gpu.sh
```

The first run from the restricted automation shell failed at SDL initialization
with `The video driver did not add any displays`. The same command in a normal
GUI-session context passed. This is an environment access limitation, not an
Alicorn failure.

- SDL initialization: PASS in GUI session.
- Requested SDL_GPU backend on Darwin: `metal`.
- Selected SDL_GPU backend: `metal`.
- Initial logical window: `640 x 480`.
- Initial physical drawable: `1280 x 960`.
- Initial pixel density: `2`.
- Initial display scale: `2`.
- Resized logical sample: `801 x 601`, then `640 x 480`.
- Resized physical sample: `1602 x 1202`, then `1280 x 960`.
- Resize stress: 300 programmatic resizes.
- Logical resize events: 300.
- Pixel/Metal-view resize events: 301, including the initial drawable event.
- Display-scale events: 1.
- Real compositor submissions: 303 (three-frame burst plus 300 resize iterations).
- Retained display commands per frame: 4 rectangle commands.
- Maximum frames in flight: 3.
- Fence waits: 303.
- Temporary GPU textures retired: 303.
- Device idle and shutdown: PASS.
- Hide/show lifecycle: PASS.
- Pointer adapter: fractional coordinates pass through unchanged in logical units.
- Text-input boundary: `SDL_StartTextInput`, `SDL_SetTextInputArea`,
  `SDL_TextInputActive`, and `SDL_StopTextInput` passed with logical input-area
  coordinates `(16,16 320x24)`.
- `SDL_EVENT_TEXT_INPUT`: 0 observed.
- `SDL_EVENT_TEXT_EDITING`: 0 observed.
- All SDL calls remain on the window-creating main thread.

### Fence observation

The fixture queries each real render/blit fence before and after its blocking
wait. On this SDL3 3.4.14 Metal path, the post-wait query was false for all
observed waits (`fence_query_after_wait_true=0`); the query-before-wait count
varied by run because this small workload often completed before observation.
There was no SDL error. The fixture uses the successful blocking wait as the
completion authority for the known oldest submission, then releases its
temporary texture and fence. It does not claim post-wait query correctness for
this backend behavior.

### Resize behavior

The current SDL/Metal combination did not reliably expose a new drawable after
`SetWindowSize` while the old SDL window claim remained active, even after old
fences and a GPU-idle drain. The fixture therefore releases and reclaims only
the SDL window claim around each resize, leaving the Alicorn runtime and GPU
device alive. With that isolated platform-boundary workaround, all 300 resize
iterations acquired a drawable and ran the current real compositor. This is a
validation finding to revisit with newer SDL3; it is not a generic runtime
policy.

## Fixes made

### Portable Unix tooling and macOS CI

- Symptom: developer automation was PowerShell-only.
- Root cause: no Unix equivalents existed.
- Change: added `tools/test.sh`, `tools/check.sh`, `tools/bench.sh`, and
  `tools/native_sdl_gpu.sh`. They resolve Odin through `PATH` or
  `ALICORN_ODIN`, run from any working directory, quote paths, write under
  `out/`, preserve exit codes, and do not invoke a package manager.
- Regression: shell syntax checks, explicit Odin runs, and the shared check/test/
  benchmark scripts passed.
- CI: added isolated `.github/workflows/foundation-macos.yml` using
  `macos-latest`, Homebrew Odin installation, version reporting, and
  `./tools/check.sh`. Hosted execution was not available locally.

### Current retained compositor and macOS platform boundary

- Symptom: the native path used SDL's default driver, fed physical resize
  dimensions into logical layout, scaled retained logical rectangles incorrectly
  on Retina, and silently dropped unavailable swapchain frames.
- Root cause: the old adapter had no explicit logical/pixel metrics contract or
  robust drawable/fence sequencing.
- Change: Darwin requests and verifies Metal; the adapter records logical size,
  pixel size, density, and display scale separately; event classes remain
  distinct; pointer/text-input coordinates stay logical; compositor bounds are
  converted to physical pixels exactly once; the current retained display-list
  render/blit path is retained; missing drawables are handled as hard failures;
  and known-oldest resources retire after blocking fence waits.
- Regression: pure logical-to-pixel and pointer no-double-scaling checks pass;
  303 real submissions, three-frame burst, 300 resizes, 303 retirements, and
  clean shutdown pass on Metal.

## Diagnostics

- `odin help build` advertises `-sanitize:address`, but
  `odin build tests -sanitize:address` fails at arm64 link time with undefined
  `___asan_version_mismatch_check_v8`.
- Adding `-extra-linker-flags:-fsanitize=address` produces the same link failure.
  No sanitizer result is claimed.
- `leaks --atExit -- ./out/alicorn_sdl_gpu` reached the native PASS result but
  reported 288 leaks / 18,816 bytes. Apple security restrictions marked the
  process not debuggable, and the report is dominated by system-framework
  allocations; no Alicorn-owned leak is isolated.

## Unverified areas

- Real Japanese/Chinese or other IME composition, marked ranges, candidate
  window behavior, and committed text were not automated; no text-input or
  editing events were generated.
- Manual pointer interaction against visible controls at top-left, center,
  bottom-right, and clip boundaries was not automated. The native adapter's
  fractional-coordinate no-double-scaling check and headless hit tests passed.
- Glyph-atlas upload, GPU text rendering, visual screenshot comparison, and a
  full rendered text field remain absent from this foundation path.
- Intel macOS was not tested locally.
- Hosted macOS CI was added but not executed here.
- Native OS wakeup/CPU behavior and allocator telemetry remain unmeasured.

## Merge notes

No files under `runtime/` changed; the portability change is confined to
`native/sdl_gpu/main.odin`. The shell scripts, isolated
workflow, and report are additive. Likely conflict points with parallel work
are `README.md`, `native/sdl_gpu/README.md`, and `native/sdl_gpu/main.odin`.
Cherry-pick the tooling/CI commit first, the native compositor/platform commit
second, and documentation last. Do not replace the current Runa-enabled
runtime or current real retained compositor with the older empty-command
validator.
