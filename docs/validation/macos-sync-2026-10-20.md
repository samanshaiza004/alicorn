# macOS sync and validation — 2026-10-20

This records a local macOS check of the current default branches, including
Scratchpad's normal dependency lock and an explicit check against Alicorn HEAD.
It is evidence for the named machine and toolchain, not every supported macOS
version or a replacement for interactive acceptance.

## Revisions and preserved local work

| Checkout | Before | After | Incoming commits |
| --- | --- | --- | ---: |
| Alicorn `master` | `8dab8d6` | `d0cf8f5114136ae5a88198053ae6e970d76d10ab` | 152 |
| Scratchpad `main` | `72236dc` | `eae8c9b9a00d0bbf1b3761ee7963378214245bbf` | 86 |

Both updates were fast-forwards after fetching origin. No branch was reset.
Existing local edits were preserved in named stashes and were not mixed into
the upstream validation:

- Alicorn: `f03a1de52068f99c6309231cdc8c33874665fa5a`,
  `pre-macos-sync-2026-10-20 local Alicorn work`. Includes the old example work,
  scripts, pointer changes, and diagnostics change. Several fixes now have
  upstream equivalents.
- Scratchpad: `50afa9c742e747946f5b67ecb4aaefad9f034fab`,
  `pre-macos-sync-2026-10-20 local Scratchpad dependency override`. Keeps the
  previous tooltip-branch dependency override; the current upstream lock uses
  Alicorn `0f88a7fe9c69bd047abeb4421cc7d51e1ee7a0f6` and Caliber
  `197cd964cc7265bc60df599a6b8562eac7c75f3a`.

Inspect these snapshots with `git stash show --stat <hash>` in their respective
repositories before deciding whether to reapply any old work. They have not
been dropped.

## Environment

- macOS 27.0, build `26A428`, Apple Silicon/arm64; Retina scale 2.
- Odin `dev-2026-09-nightly:a2fb372`, the supported September SDK.
- Go `go1.27.2 darwin/arm64`; Cargo `1.97.1`.
- Metal GPU backend; pinned AccessKit C 0.23.1.
- Homebrew SDL is **3.4.18**. Supported native checks used **3.4.16** in an
  isolated prefix, without changing Homebrew or the installed Odin SDK.

## Results

| Check | Result |
| --- | --- |
| Alicorn `sh tools/check.sh` | PASS: all checked-in examples build; foundation, runtime, theme, and theme CLI checks pass |
| Alicorn `sh tools/test.sh` | PASS: foundation suite, 215 runtime tests, 35 theme tests, 81 native host tests, generic text-input contract |
| Alicorn `sh tools/bench.sh` | PASS; retained-work evidence below |
| Alicorn `python3 tools/test_package_macos.py` | PASS: 6 packager tests |
| Native foundation fixture | PASS: 300 logical resize iterations; 303 submitted and retired frames; 2x Retina; injected text/preedit and GPU text readback |
| Native menu fixture, integrated option | PASS: startup, AppKit menu construction, Metal rendering, bounded exit; one submitted/retired frame |
| Native `01_hello`, three-second idle validation | PASS: one initial submission, zero application or native-host wakes, zero tick calls, two event waits |
| `sh tools/validate_images.sh` | PASS on Metal: scales 1, 1.25, 1.5, 2; SDR/SDR_LINEAR; translation/clipping, midtones, source-over blending |
| `sh tools/validate_icons.sh` | PASS on Metal: transparent blending, two atlas uploads/1,572,864 bytes, mesh reuse |
| Scratchpad `sh tools/alicorn.sh test` | PASS after isolating an old generated fixture: root Go tests, Go Caliber bridge, type check, 13 Odin bridge tests, 152 frontend tests |
| Scratchpad tests with `--alicorn-root /Users/keina/dev/alicorn --allow-alicorn-revision` | PASS against Alicorn `d0cf8f5`, in a separate output directory |
| Scratchpad native smoke with SDL 3.4.16 | PASS: publication rendered, application wake observed, ordered shutdown; Metal; one submitted/retired frame |
| Scratchpad macOS consumer package | PASS: pinned SDL build, optimized frontend/backend, native dependency audit, ad-hoc signature verification, relocated app smoke, and extracted ZIP launch |

The package command was
`sh tools/alicorn.sh package --version 0.1.1 --out out/macos-sync-validation-2026-10-20`.
It used Scratchpad's unchanged lock and built its own SDL 3.4.16; it did not
require the temporary development prefix. The generated release manifest
records `nativeDependencyAudit`, `codeSignatureVerification`, and
`relocatedArchiveLaunch` as `passed`.

Local artifacts in the Scratchpad checkout:

- `out/macos-sync-validation-2026-10-20/app/Scratchpad.app`
- `out/macos-sync-validation-2026-10-20/Scratchpad-v0.1.1-darwin-arm64.zip`
- `out/macos-sync-validation-2026-10-20/release-manifest.json`

This is a local arm64 test package, ad-hoc signed and not notarized. No release
was published.

The invalid theme fixture intentionally prints an error and is rejected by the
test scripts. It is an expected negative check. The linker also reports an
existing duplicate `-lobjc` warning; it did not prevent linking or tests.

### Retained-work evidence

- A retained 10,001-node tree over 10,000 idle frames: zero emitted nodes,
  allocations, reconciliation/layout/paint/composition visits, or GPU submits.
- Updating one value in 10,000 rows: one paint visit; zero layout visits.
- Reusing a 10,000-descendant region for an unrelated sibling: three emitted
  nodes and one region reuse; zero layout visits.
- 1,200 custom-surface updates: zero ordinary description, reconciliation,
  layout, paint or composition work; zero allocations in the measured window.
- One million logical virtual items over 100 frames: 23 retained nodes.

These counts describe the tested workloads; the wall-clock results are not
cross-machine performance claims.

## Problems reproduced

### Development startup depends on an unavailable Homebrew version

With ordinary Homebrew discovery, both Alicorn's menu fixture and Scratchpad's
`sh tools/alicorn.sh smoke` load SDL **3.4.18**, print that version, and terminate
with `macOS requires SDL3 3.4.16`. Compilation and headless tests alone do not
catch this startup failure.

The guard is in `native/sdl_gpu/main.odin:43`. Scratchpad's development helper
defaults to `brew --prefix sdl3` in `cmd/alicorn-dev/main.go`; its README suggests
installing SDL through Homebrew. The consumer-package path already builds a
pinned SDL version in `cmd/alicorn-dev/package.go`.

For this check, a pre-existing packaged SDL was verified with `SDL_GetVersion`
as 3.4.16 and exposed through
`/private/tmp/alicorn-sdl-3.4.16.pbJtzY/lib`. Scratchpad used `SDL3_PREFIX` and
Alicorn used `DYLD_LIBRARY_PATH`. The prefix includes the `SDL3.dylib` alias
required by that packaged library's install name. This is a temporary test
setup, not a development dependency bootstrap or a change to the version guard.

Recommended follow-up: make normal macOS development use a cached supported SDL
prefix, or validate a newer SDL version and deliberately revise the supported
range. Reuse the existing pinned build mechanism rather than asking users to
downgrade Homebrew. This pass did not change startup/version policy.

### Old generated Go fixtures contaminate recursive source discovery

The first Scratchpad test run failed at
`out/semantic-selection-test-c944acf-6e2280b/fixtures/Selection.go:4:9:
undefined: add`. The ignored bundle contains example Go source without a module
boundary; `go test ./...` still discovers it. Git ignore rules do not affect Go
package discovery. The actual source packages passed.

The complete old bundle was moved intact to
`/private/tmp/scratchpad-pre-sync-artifacts.0jaTYc/semantic-selection-test-c944acf-6e2280b`.
No source or artifact was deleted. The normal test command then passed.

Recommended follow-up: generate such example fixtures outside the source module,
or give the generated fixtures a separate module boundary. A clean CI checkout
does not establish that consecutive development runs are immune to this case.

## Coverage limits

The native menu fixture verifies construction and lifecycle, not manual menu
selection or every key equivalent. The foundation fixture injects text and
composition; this run did not manually exercise a real IME candidate window,
VoiceOver, cross-monitor movement, traffic-light interaction, tab tear-out, or
full-screen Spaces. The new integrated macOS titlebar is a proposal and has not
been implemented or validated by these checks.

Local command logs live under `/private/tmp/` with names beginning
`alicorn-macos-` or `scratchpad-macos-` and ending `2026-10-20.log`. Temporary
files are not a permanent archive; this document retains the decisive results.
