# macOS desktop launch acceptance — 2026-10-26

## Tested build

- Alicorn revision: `40819c86745b302d2be78ea54f4346cc6a91be26`
- Host: macOS 27.0, Apple Silicon (`arm64`), active logged-in desktop session
- SDL: 3.4.18
- Bundle signing: ad hoc; both bundles passed signature verification
- Variants: static SDL and shared SDL

## Desktop matrix

| Variant | Direct executable | Launch Services (`open -n`) |
| --- | --- | --- |
| Static SDL | PASS | PASS |
| Shared SDL | PASS | PASS |

Each cell recorded a verified process executable, successful first frame, one operator-attested pointer activation and one operator-attested keyboard activation, normal quit, and a successful relaunch with clean shutdown. The Launch Services runs captured application output. Direct-launch runs used a working directory whose path contains spaces.

The machine-readable report, screenshots, and per-run logs are retained locally under `out/native-package/desktop-matrix-40819c8/desktop-acceptance/`; they are not committed because they contain machine-specific paths and bulky run artifacts.

## Hosted checks for the tested revision

All listed push-triggered workflows completed successfully on the exact tested revision:

- [Native packaging](https://github.com/samanshaiza004/alicorn/actions/runs/40426132213)
- [macOS foundation](https://github.com/samanshaiza004/alicorn/actions/runs/40426132066)
- [Alicorn foundation](https://github.com/samanshaiza004/alicorn/actions/runs/40426133668)
- [Icon asset reproducibility](https://github.com/samanshaiza004/alicorn/actions/runs/40426132136)

Issue [#102](https://github.com/samanshaiza004/alicorn/issues/102) was closed after this acceptance passed.

## Scope

This validates ad hoc signed bundles on the tested interactive desktop. It does not validate Developer ID distribution, notarization, or Gatekeeper behavior for downloaded applications.
