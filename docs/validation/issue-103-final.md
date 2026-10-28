# Alicorn #103 — Acceptance matrix

**Status: OPEN — acceptance is incomplete.** This matrix consolidates the
current evidence after PR [#151](https://github.com/samanshaiza004/alicorn/pull/151)
and PR [#150](https://github.com/samanshaiza004/alicorn/pull/150) merged. It is
not a release acceptance or issue closure record.

## Candidate and evidence boundary

- Current integrated candidate: [`6fb430a`](https://github.com/samanshaiza004/alicorn/commit/6fb430a11b9ced75dca13650554429a6a212f041), the merge of #150 onto #151's `c3cab06`.
- The updated PR #150 head [`af0e8ff`](https://github.com/samanshaiza004/alicorn/commit/af0e8ff8ae34151a3b259999bd94aa7918bcc0a5) has the same source tree as `6fb430a`. Its Windows, macOS, packaging, and icon workflows passed.
- The Windows physical report records a session on Alicorn candidate `02d050a`, Windows 10 build 19045, Odin `dev-2026-09-nightly:a2fb372`, SDL 3.4.2, AccessKit 0.23.1. It reports an RTX 2080 SUPER and AMD Radeon graphics adapter, but does not identify which adapter SDL selected.
- The macOS physical report contains maintainer-reported results and supplied probe output from before the Windows and VoiceOver branches were combined. The exact macOS test revision is not established for every observation. Current-tree CI and local Windows regression tests do not substitute for a physical retest of the combined candidate.
- Detailed platform records: [Windows acceptance](issue-103-windows-2026-10-27.md) and [macOS acceptance](issue-103-macos-2026-10-27.md). Raw Windows outputs are in [the validation raw folder](raw/).

## Current results

| Gate | Status | Evidence and remaining work |
| --- | --- | --- |
| D3D12 / Metal source-over parity | **PASS — automated** | On updated PR #150 candidate `af0e8ff`, [Windows foundation](https://github.com/samanshaiza004/alicorn/actions/runs/40628541521) and [macOS foundation](https://github.com/samanshaiza004/alicorn/actions/runs/40628541508) each passed 156/156 cases. The target was offscreen `R8G8B8A8_UNORM`; this does not establish swapchain/color-space or physical display parity. |
| Windows foundation, native packaging, icons | **PASS — CI** | [Foundation](https://github.com/samanshaiza004/alicorn/actions/runs/40628541521), [native packaging](https://github.com/samanshaiza004/alicorn/actions/runs/40628541592), and [icon reproducibility](https://github.com/samanshaiza004/alicorn/actions/runs/40628541498) passed on `af0e8ff`. Packaging uses the current SDL package recipe, but this is not a physical text-input session in the packaged application. |
| Combined accessibility projection regressions | **PASS — local and CI** | Windows `tools/test.ps1` passed on `af0e8ff`; 254 runtime tests and the AccessKit/native contract checks passed. Windows and macOS foundation workflows also passed. |
| Windows foreground input and lifecycle | **PARTIAL — maintainer-reported on earlier candidate** | Input validation was reported, but key down/up, focus transitions, controlled editing, clipboard/selection, close/reopen, and primary/child-window outcomes were not itemized. Repeat the short foreground check on the packaged SDL 3.4.18 application and record the candidate, exact actions, and results. |
| Windows non-Latin IME | **PARTIAL — maintainer-reported on earlier candidate** | IME testing was reported, but the IME name and composition, commit, and cancel outcomes were not captured. Record each outcome on the current packaged candidate. |
| Narrator / NVDA | **PASS — maintainer-reported; details incomplete** | The Windows report says both readers were used and modal/virtualized content checked. Record reader versions, actions, names/states, action routing, and virtualized range transitions if available from the session. |
| Windows mixed-DPI movement | **PASS — maintainer-reported; scales unrecorded** | Movement across displays was reported, but actual scale factors and per-window checks for clipping, caret/selection, hit targets, and focus outlines were not saved. Record the tested scales and geometry results, or mark unavailable scales blocked. |
| macOS IME and window lifecycle | **PASS — maintainer-reported; details incomplete** | Japanese IME and two-window focus were reported working with Cocoa, SDL 3.4.18, and Metal. The stored record lacks composition/commit/cancel, focus-transfer, close/reopen actions, display scales, and exact current-candidate provenance. Confirm against `6fb430a` where practical. |
| VoiceOver editable text and controls | **PARTIAL** | Text-field and control use was reported working. A post-fix physical adjustment of the Volume slider has not been confirmed; explicitly test and record it. |
| VoiceOver modal containment | **PARTIAL** | VoiceOver announced the confirmation dialog, but the record does not prove navigation stays inside it. Verify background controls cannot receive VoiceOver navigation/actions while the modal is open. |
| VoiceOver million-row virtual collection | **PARTIAL — earlier traversal reported** | Traversal worked in the rebuilt tester, but the saved trace is from before the final combined candidate. Capture a post-merge trace with forward and reverse movement across working-set boundaries, the last announced row, and the resulting exported range. Full traversal to row 1,000,000 is not required. |
| macOS mixed-DPI and display movement | **PARTIAL** | Popup/scroll clipping was reported checked, but display scale factors and cross-display movement results for primary and secondary windows are missing. Record actual available scales and the affected caret, hit-target, clipping, and focus-outline checks. |
| Appearance preferences / return to idle | **PARTIAL** | Increased contrast and reduced transparency looked correct in a maintainer screenshot. Reduced motion and one-change/repeated-value update or wake counts, plus return-to-idle behavior, are not recorded. Check supported preferences on both platforms. |
| GPU adapter and display formats | **LIMITED EVIDENCE** | GPU adapter identity was not captured. Offscreen blend readbacks use RGBA8; they do not verify native swapchain formats or display color management. Keep these limitations explicit; hardware unavailable can be marked blocked. |

## Close decision

Keep #103 open. Close it only after the remaining physical checks are recorded
against the integrated candidate or explicitly marked blocked with the
unavailable hardware/configuration, and the release scope is revised to match.
Do not treat successful hosted GPU readbacks, native fixtures, or earlier
candidate observations as substitutes for the missing physical acceptance.
