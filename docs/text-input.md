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
range through the ordinary text-editing path and returns an owned
`Text_Change`. The application copies that result into its ordinary Odin state
before the next description. This keeps IME state out of application-owned
buffers and avoids a second hidden text model.

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

On Windows, run `out\alicorn_sdl_gpu.exe --manual-ime` from a normal GUI
session for a hands-on check. Manual mode keeps the window alive, redraws only
after an invalidation, and logs raw `KEY_DOWN`, `TEXT_EDITING`, and
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
