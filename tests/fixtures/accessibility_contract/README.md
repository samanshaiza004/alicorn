# Native accessibility contract fixture

This small app exposes a named button, an editable text field, a stateful
button that can become disabled, and a named status value that changes when
the button is activated. It exercises the native UIA/AX tree produced by the
Alicorn integration.

The Windows and macOS probes use their operating-system accessibility APIs.
They do not import Alicorn semantic IDs or inspect Alicorn runtime data.

## Build and launch

From the repository root, run the platform script:

```sh
sh tests/fixtures/accessibility_contract/run.sh
```

On Windows PowerShell:

```powershell
.\tests\fixtures\accessibility_contract\run.ps1
```

Keep the fixture open while running a query probe in a second terminal.

## Query the native tree

On macOS, from the repository root:

```sh
swift tests/fixtures/accessibility_contract/query_macos.swift
```

The first run may prompt for Accessibility permission for Terminal (or the
Swift runner). If macOS denies the query, enable that app under System
Settings → Privacy & Security → Accessibility, then rerun the probe.

On Windows PowerShell, from the repository root:

```powershell
.\tests\fixtures\accessibility_contract\query_windows.ps1
```

The Windows AccessKit fragment root currently exposes the generic name
`Alicorn`; the probe uses that root name to find the fixture window. The
macOS probe finds the native window by its application title.

The probes check the window and control names/roles, field value and focus,
native value setting, and activation that changes the status value. The fixture
adopts AccessKit `SetValue` requests into its application-owned controlled text
buffer on the next wake; this is the application-side action handling required
by Alicorn's explicit ownership model. Each probe
resizes the window through the platform accessibility API and verifies that
the editable field's native bounds grow with it. The probes also invoke the
state toggle through that API and require the guarded button to report enabled,
disabled, then enabled. Successful probes emit JSON evidence, including
before/after bounds and the guarded-button state sequence; a failed property,
resize, or action exits with a diagnostic.

## Screen-reader check for a virtualized collection

The native host executable also includes Alicorn's million-row collection
fixture. Build it with the normal platform test command, then launch:

```sh
./out/alicorn_sdl_gpu --accessibility-virtualization
```

On Windows, use `.\out\alicorn_sdl_gpu.exe --accessibility-virtualization` after
running `tools/test.ps1`. Navigate the list with VoiceOver, Narrator, or NVDA;
confirm the collection announces its million-item size and the current row,
and that moving beyond the initially exposed rows continues to reveal rows.
The fixture prints the exported working-set range and handled focus, paging,
and reveal requests to its launching terminal. Record where navigation stops
or whether it requires an explicit scroll/reveal action. This is a bounded
working-set acceptance check, not a promise that every logical row is retained
in the platform tree simultaneously.

## Still requires a person

These probes establish native tree exposure and programmatic accessibility
actions. They do not replace a screen-reader session. Confirm that Narrator or
NVDA can navigate to and announce the button, editable field, disabled state,
and changing status on Windows, and that VoiceOver can do the same on macOS.
Note the OS version, screen reader/version, fixture revision, and any manual
action that was required. Windows execution and screen-reader acceptance
require a Windows desktop; macOS AX queries require Accessibility permission.
