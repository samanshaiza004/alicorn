# Current validation

This folder keeps current acceptance summaries and reusable validation
runbooks. Dated investigation snapshots and superseded reports are in the
[archive](../archive/README.md); their historical status should not be read as
the current project status.

## Current acceptance and platform limits

- [Issue #165 headless UI replay and native capture](issue-165-2026-11-08.md) —
  public replay harness, History consumer regression, and Windows D3D12 capture;
  records backend-specific screenshot limits.
- [v0.2.1 release validation](release-v0.2.1.md) — included history, checks,
  release scope, and remaining platform-validation boundaries.
- [Odin dev-2026-11 migration](odin-dev-2026-11.md) — Windows validation for
  the current compiler baseline; the record explicitly identifies checks that
  still require another platform or local CMake installation.
- [Issue #90 CPU paint reference](issue-90-cpu-paint-reference.md) — bounded
  CPU/GPU differential evidence for the supported test-only paint subset.
- [Issue #144 motion diagnostics and virtual-clock replay](issue-144-motion-diagnostics.md) — completed diagnostic and replay scope; broader native acceptance remains under #146.
- [Issue #106 incremental-vs-fresh-runtime invalidation oracle](issue-106-invalidation-oracle.md) — bounded deterministic test oracle for retained invalidation misuse; follow-up corpus remains open.
- [Issue #146 motion diagnostics and Punks dogfood progress (2026-10-30)](issue-146-progress-2026-10-30.md) — closed-inspector headless overhead and application integration evidence; native scheduler acceptance remains open.
- [macOS static/shared desktop launch matrix (2026-10-28)](macos-desktop-launch-2026-10-28.md) — current integrated-revision evidence for direct and Launch Services launches.
- [Final Windows/macOS acceptance matrix](issue-103-final.md) — maintainer
  confirmed physical input, IME, mixed-DPI, appearance, and screen-reader checks,
  alongside automated GPU and CI evidence.
- [Screen-reader validation summary](accessibility-screen-reader.md) — scope of
  the physical Narrator/NVDA and VoiceOver checks.
- [Linux native acceptance runbook](linux-native-acceptance.md) — separates
  deterministic checks from desktop-session evidence.
- [Linux NixOS/Mango validation](linux-nixos-mangowc-2026-10-23.md) — the
  recorded native Linux environment and its limitations.
