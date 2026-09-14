# macOS Validation

Date: 2026-09-13

Recommendation: `MACOS_READY_WITH_GAPS`

The headless foundation and the SDL3 Metal platform boundary work on the
tested Apple Silicon GUI session. The base commit does not contain a retained
GPU display-list renderer, and real IME composition and manual pointer
interaction remain unautomated. SDL3 3.4.14 also reports an inconsistent query
result for the intentionally empty Metal command-buffer fence path; the wait,
idle, and release lifecycle succeeds.

## Baseline

- Base SHA: `df9cfc90d309e88e056c1d2e05a7520fd813a933`
- Base branch: `master`
- Base tree: clean
- Validation branch: `port/macos-df9cfc9`
- macOS: 26.6.2, build 25G83
- Architecture: Apple Silicon, `arm64`
- Xcode: 26.6, build 17F113
- Developer directory: `/Applications/Xcode.app/Contents/Developer`
- Clang: Apple clang 21.0.0, target `arm64-apple-darwin25.6.0`
- Odin: `dev-2026-09-nightly:a2fb372`
- Odin executable: `/Users/keina/Documents/odin-macos-arm64-nightly+2026-09-01/odin`
- SDL3: 3.4.14 from Homebrew at `/opt/homebrew/opt/sdl3`
- SDL3 library: arm64 `/opt/homebrew/opt/sdl3/lib/libSDL3.0.dylib`
- GPU: Apple M1, 8 cores; `system_profiler` reports Metal supported

The initial non-interactive shell capture returned `odin not found` because
that shell did not source the user's interactive PATH. All repository checks
used `ALICORN_ODIN` with the exact executable above, and the new scripts also
passed PATH-only resolution from outside the repository.

## Existing tests

All of these were run from the unmodified base tree before source changes.

| Command | Result | Notes |
| --- | --- | --- |
| `git diff --check` | PASS | Clean baseline |
| `odin build tests -out:out/alicorn_tests` | PASS | |
| `./out/alicorn_tests` | PASS | `Alicorn foundation tests: PASS` |
| `odin build benchmarks -out:out/alicorn_benchmarks` | PASS | |
| `./out/alicorn_benchmarks` | PASS | Raw sample below |
| `odin build examples/identity_torture -out:out/identity_torture` | PASS | |
| `./out/identity_torture` | PASS | 5,000 operations; 3 live nodes |
| `odin build examples/crucible -out:out/crucible` | PASS | |
| `./out/crucible` | PASS | Meter delta 2; retained nodes 27; regions skipped 31; composites 6 |

Untouched baseline benchmark sample:

| workload | first ns | unchanged ns | one change ns | keyed reorder ns | retained nodes | layout updates |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 100 nodes | 688000 | 477000 | 472000 | 486000 | 101 | 200 |
| 1,000 nodes | 52626000 | 39999000 | 36431000 | 36869000 | 1001 | 2000 |
| 10,000 nodes | 4851240000 | 4637919000 | 4691907000 | 4880506000 | 10001 | 20000 |

- Virtual list: 1,000,000 logical rows, 100 frames, `7766000 ns`, 23 retained nodes.
- Idle: 10,000 frames, `23000 ns`, `idle_count=10000`, `gpu_submits=0`.

The final unchanged benchmark run through `tools/bench.sh` retained 23 virtual
nodes and recorded `idle_count=10000`, `gpu_submits=0`. Its raw virtual-list
time was `8802000 ns`; the tree samples were 687000/527000/547000/504000 ns
for 100 nodes, 63590000/42464000/37840000/37291000 ns for 1,000 nodes, and
4595120000/4480855000/5211094000/7388475000 ns for 10,000 nodes. These are
wall-clock samples, not cross-platform performance claims.

## Native validation

### Build and environment

- `odin build native/sdl_gpu -out:out/alicorn_sdl_gpu`: PASS.
- The original smoke binary launched from the automation shell but SDL failed
  with `The video driver did not add any displays`; this environment lacked
  WindowServer access in that shell. The same validation run with GUI-session
  access succeeded.
- `otool -L` shows `/opt/homebrew/opt/sdl3/lib/libSDL3.0.dylib`.
- All SDL calls are made from `main`; no background event loop was added.

### Final GUI run

Command: `ALICORN_ODIN=/Users/keina/Documents/odin-macos-arm64-nightly+2026-09-01/odin ./tools/native_sdl_gpu.sh`

- SDL initialization: PASS.
- Requested SDL_GPU driver: `metal` on Darwin.
- Selected SDL_GPU driver: `metal`.
- Initial logical size: `640 x 480`.
- Initial physical pixel size: `1280 x 960`.
- Initial pixel density: `2`.
- Initial display scale: `2`.
- Final resized logical size: `1024 x 768`.
- Final resized physical pixel size: `2048 x 1536`.
- Logical resize events: 299.
- Physical resize / Metal-view resize events: 300.
- Display-scale events: 1.
- Programmatic resize stress: 300 iterations.
- Empty command-buffer submissions: 300.
- `SDL_WaitForGPUFences`: passed for all submissions.
- `SDL_ReleaseGPUFence`: completed for all submissions.
- `SDL_WaitForGPUIdle`: PASS.
- Hide/show lifecycle: PASS.
- Text input boundary: `SDL_StartTextInput`, `SDL_SetTextInputArea`,
  `SDL_TextInputActive`, and `SDL_StopTextInput` all passed. The input area
  used logical coordinates `(16,16 320x24)`.
- `SDL_EVENT_TEXT_INPUT`: 0 observed.
- `SDL_EVENT_TEXT_EDITING`: 0 observed.
- Pointer adapter regression: fractional logical coordinates passed through
  unchanged; no double scaling.
- Shutdown: PASS; the process exited cleanly.

### Fence query note

The validator calls `SDL_QueryGPUFence` before and after each wait and records
the result. With Homebrew SDL3 3.4.14 and empty command buffers, the post-wait
query was false for all 300 submissions. A temporary C-only probe against the
same dylib reproduced `query_before=1 wait=1 query_after=0 idle=1
query_after_idle=0` with no SDL error. The validator therefore treats the
blocking wait and final device-idle result as completion authority, retains the
query call as observable evidence, and does not claim post-wait query
correctness for this empty-buffer backend path. A real transfer/render command
buffer or newer SDL3 version should be tested before relying on this query for
resource retirement.

### Diagnostics

- `odin build tests ... -sanitize:address`: FAIL at link time with undefined
  `___asan_version_mismatch_check_v8` for arm64.
- Adding the documented Odin extra-linker-flags mechanism with
  `-fsanitize=address` did not resolve the missing runtime symbol. No sanitizer
  result is claimed.
- Apple `leaks --atExit -- ./out/alicorn_sdl_gpu`: the fixture reached PASS,
  but `leaks` reported 709 leaks / 57,952 bytes and exited nonzero. Apple
  security restrictions also reported that the process was not debuggable.
- Comparison `leaks --atExit -- ./out/alicorn_tests` reported 20,855 leaks /
  2,061,760 bytes while the unchanged headless tests passed, so no macOS-only
  allocator regression was isolated. Existing Odin/runtime teardown and SDL
  allocations remain a follow-up.

## Fixes made

### Portable developer scripts

- Symptom: developer automation was PowerShell-only.
- Root cause: no Unix equivalents existed.
- Change: added `tools/test.sh`, `tools/check.sh`, `tools/bench.sh`, and the
  native `tools/native_sdl_gpu.sh` wrapper. They resolve Odin through `PATH` or
  `ALICORN_ODIN`, operate from any working directory, quote paths, write to
  `out/`, and preserve the Windows scripts.
- Regression/validation: `sh -n`, explicit-Odin runs from outside the repo,
  PATH fallback, missing-Odin handling, and full headless runs passed.

### SDL3 Metal, metrics, and lifecycle fixture

- Symptom: the old smoke path used SDL's default GPU driver, did not expose
  logical/pixel metrics, treated logical and physical resize events alike, and
  only submitted three frames.
- Root cause: the native probe did not enforce the macOS platform boundary.
- Change: the Darwin adapter requests and verifies Metal, creates a
  high-pixel-density window, keeps logical layout/pointer/text-input units
  separate from physical pixels, handles resize/scale event classes
  distinctly, exercises text-input APIs, performs 300 resize/submission
  iterations, checks waits/idle/release, and adds a no-double-scaling pointer
  regression check.
- Regression/validation: native GUI run passed the metrics, driver, event,
  text-input boundary, stress, and shutdown checks above.

### CI and documentation

- Change: added an isolated `.github/workflows/foundation-macos.yml` using
  `macos-latest`, Homebrew Odin installation, version reporting, and the same
  `tools/check.sh` used locally. Updated the project and SDL boundary docs.
- Regression/validation: workflow YAML is isolated from the existing Windows
  workflow; local shell syntax and headless behavior passed. GitHub-hosted CI
  execution was not available during this run.

## Unverified areas

- Real IME composition and candidate-window behavior were not automated; no
  text-input or editing events were generated. The SDL calls and logical input
  area boundary were exercised.
- Manual pointer hit testing against visible controls at top-left, center,
  bottom-right, and clip boundaries was not automated. Headless focus/hit tests
  and the native fractional-coordinate no-scale check passed.
- The base commit has no retained GPU display-list renderer, swapchain render
  pass, surface compositing, or resource upload path to prove.
- The SDL empty-command-buffer post-wait fence query inconsistency remains a
  dependency/backend gap; non-empty transfer/render command buffers need a
  separate test.
- Intel macOS was not tested locally.
- GitHub `macos-latest` CI was added but not executed here.
- Runa is absent at the base commit and was not introduced.

## Merge notes

The headless runtime files under `runtime/` were not changed. The additive
workflow, shell scripts, and `MACOS_VALIDATION.md` should cherry-pick cleanly.
The likely conflict points with parallel Windows work are `README.md`,
`native/sdl_gpu/README.md`, and especially `native/sdl_gpu/main.odin`; the
native change is confined to the SDL/platform validation boundary. Preserve
the Windows PowerShell tooling and merge the native fixture before any later
renderer work that depends on its logical/pixel contract.
