# Alicorn #103 — Native source-over blend readback

This record covers the GPU blending portion of #103 only. It does not establish
the physical input, accessibility, mixed-DPI, or secondary-window acceptance
gates.

## Candidate and method

- Production blend-state fix: [`e02a59d`](https://github.com/samanshaiza004/alicorn/commit/e02a59d68076ae62c2a5bbf211c67c2002090622).
- Exact case-count guard: [`0902c1d`](https://github.com/samanshaiza004/alicorn/commit/0902c1dadb7a989e572bf3115237facfa55cff87). It requires exactly 156 cases: 48 surface, 24 geometry, 24 icon, 24 image, 24 text, and 12 mixed.
- Final guarded test revision: [`543c652`](https://github.com/samanshaiza004/alicorn/commit/543c6523b4103bceb1c4a06511ee2d90e194c0da), merged to master as [`610fd6e`](https://github.com/samanshaiza004/alicorn/commit/610fd6ea6fbc4afe7a91884f88e908a5b40ecdac).
- Windows local run: Windows 10, build 19045, AMD64; Odin `dev-2026-09-nightly:a2fb372`; Direct3D 12. The GPU adapter model was not captured.
- Windows CI on `543c652`: [Alicorn foundation](https://github.com/samanshaiza004/alicorn/actions/runs/40524378606), runner image `windows-2025-vs2026`; Direct3D 12 readback reported 156 cases, 156 expected, per-family counts valid, zero failures.
- macOS CI on `543c652`: [Alicorn foundation (macOS)](https://github.com/samanshaiza004/alicorn/actions/runs/40524378796), runner image `macos-26-arm64`; Metal readback reported 156 cases, 156 expected, per-family counts valid, zero failures.
- Same-revision packaging and icon checks passed: [Native packaging](https://github.com/samanshaiza004/alicorn/actions/runs/40524378539) and [Icon asset reproducibility](https://github.com/samanshaiza004/alicorn/actions/runs/40524378434).
- `sh tools/check.sh` passed locally on the merged master tree `610fd6e`.
- Readback target: offscreen `R8G8B8A8_UNORM` texture, not a native swapchain or display-color-space test. Coverage uses six renderer families, scales 1, 1.25, 1.5, and 2; destination alpha 0, 0.4, and 1; tolerance 2 RGBA8 values.
- Commands: `tools/validate_blending.ps1 -Odin <odin.exe>` on Windows and `tools/validate_blending.sh` on macOS.

## Results

| Platform / backend | Result | Evidence |
| --- | --- | --- |
| Windows local / Direct3D 12 | PASS | 156/156 readback cases; all six families passed |
| Windows CI / Direct3D 12 on `543c652` | PASS | Run `40524378606`; 156 expected and executed, exact family counts, zero failures |
| macOS CI / Metal on `543c652` | PASS | Run `40524378796`; 156 expected and executed, exact family counts, zero failures |
| Same-revision native packaging and icon workflows | PASS | Runs `40524378539` and `40524378434` |
| Merged-tree `sh tools/check.sh` | PASS | Local validation on `610fd6e` |
| Local Metal executable in this non-desktop session | BLOCKED | SDL could not initialize a display; hosted Metal readback passed on the exact guarded revision |
| Windows / legacy blend factors | FAIL as expected | 108/156 cases failed; surface, geometry, text, and mixed failed; icon and image passed |
| Physical Apple Silicon desktop / Metal presentation | BLOCKED | Hosted Metal CI is not physical desktop acceptance |
| Full #103 physical acceptance | BLOCKED | Foreground input/IME, assistive technology, mixed-DPI movement, and secondary-window interaction remain unverified |

The legacy-factor run used `.SRC_ALPHA` for solid, surface, and text output
alpha, and `.ONE` for icon and image output alpha. Its failures confirm that
the probe detects the defect under investigation.

## Limitations

The probe exercises Alicorn production renderer pipelines and actual GPU
compositing on an offscreen target. It does not prove swapchain-format, display
color-space, or physical presentation parity. The GPU adapter model was not
captured in the Windows local run or the cited hosted CI runs. Keep #103 open
until its remaining physical acceptance matrix is recorded against an
identifiable candidate commit.