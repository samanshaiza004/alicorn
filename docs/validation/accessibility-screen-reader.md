# Screen-reader validation

The project maintainer confirmed the physical Windows and macOS screen-reader
checks summarized in the [final #103 acceptance matrix](issue-103-final.md).
The recorded scope includes Narrator/NVDA and VoiceOver interaction, editable
controls including slider adjustment, modal containment, and traversal of the
bounded million-row virtual collection.

The matrix preserves details not supplied with the confirmation, including
exact reader versions and some per-session traces. Automated Windows UI
Automation and native projection tests provide additional contract evidence.
This is representative physical validation, not comprehensive accessibility
conformance; Linux has no platform adapter and some custom widget patterns may
remain incomplete.
