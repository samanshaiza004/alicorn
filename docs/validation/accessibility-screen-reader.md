# Screen-reader validation

Manual checks for the AccessKit integration were reported by the project
maintainer on 2026-10-27:

- macOS: VoiceOver interaction with Alicorn-rendered controls works.
- Windows: screen-reader interaction with the native fixture works.

The Windows reader and both platforms' OS/reader versions were not recorded.
The Windows UI Automation contract probe also passes on the native fixture,
covering names and roles, text value/focus, actions, disabled state, status
changes, and resized bounds.

The macOS maintainer later reported that VoiceOver navigation through the
million-item virtual collection worked with the rebuilt tester. The pre-fix
capture showed backward cursor jumps during working-set changes; the post-fix
run did not include a saved trace or final row number. See the
[macOS #103 acceptance record](issue-103-macos-2026-10-27.md) for the exact
scope and remaining gaps, including slider retest and modal containment.

This does not establish complete coverage of every widget, Linux accessibility,
or accessibility conformance.
