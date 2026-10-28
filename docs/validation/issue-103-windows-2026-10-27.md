# Alicorn #103 — Windows acceptance (2026-10-27)

This is the Windows half of the physical acceptance record for #103. It records
maintainer-reported desktop checks separately from reproducible checks run in
this checkout. The macOS half is pending maintainer validation.

## Candidate and machine

- Candidate: Alicorn merge commit [`02d050a`](https://github.com/samanshaiza004/alicorn/commit/02d050a19664b694b9ff3a2c80fb351b5a015a5c), merged from #149.
- Candidate tree: `c49d4901fca3e0b5bae8fe283e586830193779b9`.
- Local validation checkout: `410d8bfbc0cfc8db28dd8451be32489b87480434`; its tree exactly matches the candidate tree.
- OS: Windows 10 Home, build 19045, x64.
- CPU: AMD Ryzen 5 7600X.
- GPU inventory: NVIDIA GeForce RTX 2080 SUPER (driver `32.0.15.9597`) and AMD Radeon(TM) Graphics (driver `31.0.24002.92`). The D3D12 validation output does not identify which adapter SDL selected.
- Displays reported by Windows: SPT F22 and GBT AORUS CV27Q. The exact scale factors used during the manual move test were not recorded.
- Odin: `dev-2026-09-nightly:a2fb372`; SDL: 3.4.2; AccessKit: 0.23.1.

## Results

| Gate | Windows result | Evidence and limits |
| --- | --- | --- |
| Foreground keyboard, focus, editing, clipboard/selection, close/reopen | **PASS — maintainer-reported** | The maintainer reports Windows input validation. The individual key/edit/clipboard/lifecycle cases and whether each used the primary or child window were not itemized in the record. |
| Non-Latin IME composition, commit, cancel | **PASS — maintainer-reported, details incomplete** | IME validation was reported. The IME name and separate composition/commit/cancel outcomes were not captured. The native text-input contract also passed in `tools/test.ps1`, but that is not a substitute for OS IME input. |
| Narrator and NVDA | **PASS — maintainer-reported** | Both latest installed readers were used on this candidate; the maintainer reports successful checks for modal boundaries and virtualized content. Exact reader versions, actions, and observed exported-range transitions were not recorded. |
| Mixed-DPI movement | **PASS — maintainer-reported, details incomplete** | Movement across mixed-scale displays was reported. Exact scales and per-window checks for clipping, caret/selection, hit targets, and focus outlines were not itemized. |
| OS accessibility appearance changes | **PASS — maintainer-reported, counters not captured** | Physical appearance changes were reported. No log records the individual settings or the one-change / repeated-value update and wake counts. |
| D3D12 blend readback | **PASS — agent-run** | Direct3D 12, offscreen `R8G8B8A8_UNORM`: 156/156 cases, six renderer families, scales 1/1.25/1.5/2, destination alpha 0/0.4/1, tolerance 2 RGBA8 values, zero failures. This does not cover native swapchain/display color-space parity or identify the selected GPU adapter. See [raw output](raw/issue-103-windows-d3d12-02d050a.txt). |
| Native titlebar host startup/shutdown | **PASS — agent-run smoke** | The Windows titlebar fixture selected Direct3D 12, completed its bounded run, and retired all 6 submitted frames. This is a startup/shutdown smoke, not a manual menu, caption, or drag acceptance run. See [raw output](raw/issue-103-windows-titlebar-smoke-02d050a.txt). |
| Alicorn Windows project checks | **PASS — agent-run** | `tools/test.ps1` passed: AccessKit C-header ABI contract, AccessKit package and consumer, runtime/UI/theme/native tests, restoration checks, and generic native text-input contract. The final host contract printed `PASS`. See [raw output](raw/issue-103-windows-project-tests-02d050a.txt). |

## MacOS follow-up

Run these from the Alicorn checkout at the same candidate tree and keep the
terminal output for the report:

1. Run `sh tools/validate_blending.sh`. Record the selected Metal backend,
   target format, scales, case counts, and any failures. This provides the
   same-revision Metal side of the D3D12 readback comparison.
2. Run `sh tools/native_sdl_gpu.sh --accessibility-virtualization`. With
   VoiceOver, navigate beyond the initially exposed million-row horizon. Note
   the last announced row, whether VoiceOver requests reveal/scroll, whether
   the visible/exported range advances, and whether navigation continues.
3. Run `sh tests/fixtures/accessibility_contract/run.sh`, then in another
   terminal run `swift tests/fixtures/accessibility_contract/query_macos.swift`.
   Also use VoiceOver to confirm control names/roles/states, focus, text value
   and selection, and action routing. The query probe requires Accessibility
   permission for the terminal or Swift runner.
4. Run `sh tools/native_sdl_gpu.sh --menu-fixture --macos-titlebar-fixture`
   for the interactive titlebar fixture. Check native controls and menus,
   tab select/close/reorder, text entry, resizing, fullscreen/restore, and
   pointer behavior around the titlebar. The bounded startup check is
   `sh tools/native_sdl_gpu.sh --menu-fixture --macos-titlebar-fixture --menu-fixture-smoke`.
5. For real non-Latin IME input and ordinary editor lifecycle, run Scratchpad
   from its repository with `./tools/alicorn.sh run`; test composition,
   commit, cancel, selection, close/reopen, and movement across displays with
   different scales. Record macOS and IME names and the tested scale factors.
6. Physically change the macOS accessibility display settings supported by
   the host and record what Alicorn detects. If available, capture the runtime
   update/wake counters for one change and an identical repeated value, then
   confirm the app returns to idle.

## Remaining evidence before closing #103

The maintainer-reported Windows results cover the important real-reader and
desktop behaviors, so this report does not request another Windows test pass.
For a complete record, the Windows subcase details above can be filled in if
they were retained. The required remaining platform pass is macOS/VoiceOver
and Metal readback on this candidate. The final comparison should also state
that the blend probe is an offscreen RGBA8 test, not a physical display
color-management test. Keep #103 open until the macOS results and any blocked
cases are recorded.
