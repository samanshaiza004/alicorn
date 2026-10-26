# macOS bundle launch acceptance — Alicorn #102

Issue #102 is a release gate for the packaged macOS application, not evidence that Alicorn needs a new SDL or AppKit architecture. The reported Launch Services `kLSNoExecutableErr` and SDL/AppKit initialization abort have not been tied to a common root cause. Keep the issue open until both package variants pass the desktop matrix below on a logged-in macOS desktop.

## Build and automated checks

Build both variants from the same checkout into separate output directories. Keep the direct launch smoke enabled:

```sh
bash tools/build_native_release.sh --sdl-linkage static --output out/native-package/macos-static
bash tools/build_native_release.sh --sdl-linkage shared --output out/native-package/macos-shared
```

The packager now tests the published `.app` executable from a temporary working directory outside the repository. It verifies the runtime SDL version, host completion summary, and at least one submitted frame. Shared packaging queries `SDL_GetVersion()` from the exact dylib it bundles, checks the macOS-required SDL 3.4.18, and records the input filename, SHA-256, detected version, and declared provider. SDL 3 returns its encoded version integer from this no-argument function. [SDL: `SDL_GetVersion`](https://wiki.libsdl.org/SDL3/SDL_GetVersion) Static packages retain the pinned source URL and archive digest.

Run the interactive acceptance from a foreground terminal in the same logged-in GUI session:

```sh
python3 tools/validate_macos_package_desktop.py \
  --static "out/native-package/macos-static/Alicorn Hello.app" \
  --shared "out/native-package/macos-shared/Alicorn Hello.app" \
  --results-dir "out/native-package/desktop acceptance"
```

The validator checks the bundle manifest and signature, confirms that both variants use the same Alicorn revision, then exercises each variant directly and through `open -n -W -a`. It verifies the launched PID's executable path, captures the first-frame screenshot, prompts for a physical pointer activation and Tab+Space activation, and asks the operator to quit normally. The starter writes a unique result marker after `ui.run` returns, so a successful result is emitted after native-host cleanup. Each launch is followed by a fresh relaunch smoke. The JSON report records `PASS`, `FAIL`, or `BLOCKED` per cell; unavailable GUI access or screen-capture permission must remain blocked.

| Variant | Direct executable | Launch Services |
| --- | --- | --- |
| Static SDL | PASS / FAIL / BLOCKED | PASS / FAIL / BLOCKED |
| Shared SDL | PASS / FAIL / BLOCKED | PASS / FAIL / BLOCKED |

CI builds and audits both linkages and runs noninteractive launch smokes. CI is not a substitute for this logged-in desktop interaction matrix. The validation driver detects whether the installed `open` supports application stdout/stderr redirection and records when it cannot capture those logs.

## Why both launch paths matter

Apple documents that Launch Services may activate an existing process unless a new instance is requested. The validator uses `-n`, passes a unique run ID, and verifies the process image rather than trusting `open`'s exit code. [Apple: `createsNewApplicationInstance`](https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/createsnewapplicationinstance)

SDL documents that Finder launches and shell launches can have different working directories. The direct smoke starts outside the repository, and the Launch Services run starts with `/` as its working directory. [SDL: macOS README](https://wiki.libsdl.org/SDL3/README-macos)

Signature verification here covers the locally packaged ad-hoc bundle. Developer ID signing, notarization, Gatekeeper assessment, and a quarantined download launch are separate distribution checks unless required by the release policy. A passing #102 matrix does not close the separate physical accessibility or input requirements for v0.2.0.
