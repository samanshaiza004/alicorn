# Text input and IME

This page describes the Stage 3 text-input boundary. It is intentionally
small: committed Unicode input and transient preedit composition are in scope;
clipboard, drag selection, rich candidate lists and full editor behavior are
not.

## Two kinds of text

A text field has a committed value and, while an IME is active, a temporary
preedit:

```text
committed application value
        +
temporary platform composition
        ↓
temporary display projection
```

`TEXT_EDITING` updates only the projection. The retained field copies the
preedit string, converts its SDL character-index selection to byte offsets,
and remembers the committed anchor/focus range that the composition replaces.
The committed field text does not change during `TEXT_EDITING` updates.

`TEXT_INPUT` is the commit boundary. Alicorn replaces the captured committed
range through the ordinary text-editing path and returns a runtime-owned
`Text_Change`. A native host callback borrows `change.text` for the duration of
the callback and must clone it into application-owned state if it keeps the
value. The host releases the returned string through the runtime's captured
persistent allocator after the callback returns. This keeps IME state out of
application-owned buffers and avoids a second hidden text model.

## Lifetime and cancellation

Composition is owned by the retained text-field node. Its string and projected
logical `Text_Run` are released when composition is canceled or the node is
retired. Cancellation occurs when:

- SDL sends an empty preedit;
- focus moves to another node;
- pointer placement begins a new caret operation;
- the composing field disappears;
- the native adapter shuts down text input.

The platform adapter calls `SDL_ClearComposition` before stopping or changing
the SDL text-input owner. The application never receives a committed change
for a preedit that was canceled.

## SDL boundary

The native adapter starts SDL text input only while a focused text field owns
keyboard focus. It copies event strings immediately. SDL's
`SDL_TextEditingEvent.start` and `.length` are UTF-8 character indexes, not
Alicorn byte offsets; the conversion is explicit in
`utf8_character_index_to_byte_offset`.

After layout, Alicorn derives a caret rectangle from the retained text run.
The adapter supplies the field bounds and the caret's horizontal offset to
`SDL_SetTextInputArea` in logical window coordinates. The operating system
continues to own candidate-window presentation.

The native proof fixture also handles non-composition Backspace, Delete, and
logical Left/Right movement from SDL key events. While a preedit is active,
those keys are left for the IME rather than mutating committed text.

## Editing commands

The runtime exposes a small platform-neutral command vocabulary through
`Text_Command`. Hosts translate their key conventions into these commands;
the runtime owns grapheme and word boundaries.

```odin
Move_Left, Move_Right
Move_Word_Left, Move_Word_Right
Delete_Backward, Delete_Forward
Delete_Word_Backward, Delete_Word_Forward
```

Word commands use Runa's Unicode word iterator and never split a grapheme.
On Windows, Ctrl+Left/Right and Ctrl+Backspace/Delete are the usual word
bindings. On macOS, the native adapter maps Option to word movement/deletion
and Command to the platform's document/selection conventions. Shift extends
the current selection, while an unmodified arrow collapses a non-empty
selection before moving.

Committed edits all use the same `Text_Change` ownership path, whether they
come from `TEXT_INPUT`, Backspace, Delete, or a word deletion. A changed result
is handed to the application's text-change callback as a borrowed runtime
product; a no-op result is still released by the host. Caret and selection
movement only requests a retained presentation frame, so it does not make the
application rebuild its description.

Operating-system key repeat remains event-driven. If several repeat events
arrive while a host is busy, the runtime processes them in order; native
diagnostics expose edit/navigation counts and text-mesh rebuild/cache-hit
counters so repeat latency can be distinguished from application or GPU
latency.

On Windows, run `.\tools\native_sdl_gpu.ps1 -ManualIme` from a normal GUI
session for a hands-on check. The runner bundles `SDL3.dll` and passes the
manual-mode switch to the fixture. Manual mode keeps the window alive, redraws
only after an invalidation, and logs raw `KEY_DOWN`, `TEXT_EDITING`, and
`TEXT_INPUT` events. It is a diagnostic aid, not a substitute for a recorded
real-IME test result.

## Proof status

Headless tests cover Unicode index conversion, non-mutation during preedit,
selection replacement, cancellation, focus transfer and node retirement. The
native Windows SDL3/D3D12 fixture pushes one editing event and one committed
event through SDL's event queue and verifies the complete adapter path.

This is not yet a complete real OS-IME proof. A manual Windows run has shown
the candidate UI and committed input in the development environment, but the
repository still needs a reproducible recorded result covering Japanese or
Chinese composition, candidate placement, preedit updates and final commit.
