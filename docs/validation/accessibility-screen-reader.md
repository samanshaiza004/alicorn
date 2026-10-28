# Screen-reader validation

Manual checks for the AccessKit integration were reported by the project
maintainer on 2026-10-27:

- macOS: VoiceOver interaction with Alicorn-rendered controls works.
- Windows: screen-reader interaction with the native fixture works.

The Windows reader and both platforms' OS/reader versions were not recorded.
The Windows UI Automation contract probe also passes on the native fixture,
covering names and roles, text value/focus, actions, disabled state, status
changes, and resized bounds.

This validates representative controls and text interaction. It does not
validate navigation across gaps in the million-item virtual collection, the
full widget set, Linux accessibility, or accessibility conformance. Those
remain separate validation work.
