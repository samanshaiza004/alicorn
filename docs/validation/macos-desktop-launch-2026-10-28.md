# macOS static/shared desktop launch acceptance — 2026-10-28

**Status: PASS — maintainer-run physical acceptance on the integrated revision.**

## Tested build

- Alicorn source revision: [`cc88bfd`](https://github.com/samanshaiza004/alicorn/commit/cc88bfde3271f0f558894b5be1acdeb5ed8a64d5).
- Host: macOS 27.2, arm64, active console session.
- SDL runtime: 3.4.18 in both packaged variants.
- Static bundle: SDL built from the pinned SDL source archive.
- Shared bundle: bundled Homebrew SDL 3.4.18 runtime.
- The machine-readable result identifies both bundles as matching the tested revision and records successful code-signature verification.

## Results

| SDL packaging | Launch path | Interactive first frame and input | Normal quit | Unattended relaunch |
| --- | --- | --- | --- | --- |
| Static | Direct executable | **PASS** — visible first frame; one pointer and one keyboard activation | **PASS** | **PASS** — exit status 0 |
| Static | Launch Services (`open`) | **PASS** — visible first frame; one pointer and one keyboard activation | **PASS** | **PASS** — exit status 0 |
| Shared | Direct executable | **PASS** — visible first frame; one pointer and one keyboard activation | **PASS** | **PASS** — exit status 0 |
| Shared | Launch Services (`open`) | **PASS** — visible first frame; one pointer and one keyboard activation | **PASS** | **PASS** — exit status 0 |

The pointer and keyboard activations and normal quits were physically performed and attested by the maintainer. The validator separately confirmed process identity, startup/frame evidence, shutdown completion, and unattended relaunch for each cell. Direct launches used a working directory whose path contains spaces; Launch Services launches used `/` as the working directory.

## Evidence and scope

The full JSON report, screenshots, host logs, and shutdown markers are in the local ignored build output at:

`out/native-package/desktop fixture results integrated/macos-desktop-validation.json`

The report contains machine-specific absolute paths and the associated artifacts are local build output, so they are intentionally not committed. This tracked summary preserves the tested revision, environment, launch matrix, and evidence boundary.

This validates static and shared SDL desktop launch, first-frame presentation, pointer/keyboard interaction, clean shutdown, and relaunch on this macOS host. It does not establish Developer ID distribution, notarization, or Gatekeeper behavior for downloaded applications.
