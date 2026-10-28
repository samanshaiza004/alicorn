# VoiceOver test gallery

Run this app on macOS to manually check Alicorn controls with VoiceOver:

```sh
sh tests/fixtures/voiceover_gallery/run.sh
```

The script builds and launches the gallery. Enable VoiceOver with **Command-F5**
or from System Settings → Accessibility → VoiceOver. Use VoiceOver navigation
to inspect the window title, static descriptions, tab list, form controls,
collection items, live announcements, and modal dialog.

By default, **VO** means Control-Option. Move through items with VO-Left/Right,
perform a control's default action with VO-Space, and enter or leave a group
with VO-Shift-Down/Up. The VoiceOver rotor (VO-U) can jump by control type.
These are Apple's default VoiceOver commands; use the bindings configured in
VoiceOver Utility if yours differ.

## Suggested tour

1. On **Controls**, navigate to **Activate action**, activate it, and confirm
   the action count changes. Verify **Disabled action** is announced disabled
   and cannot activate. Inspect the named Search icon button.
2. Inspect **Enable notifications** and toggle it. Check its checked state.
   In VoiceOver Utility, set typing echo to **Characters and Words**. Focus
   **Display name**, select its text, type `hello world`, and check that
   characters are spoken as typed and the completed word is spoken at Space.
   Confirm the VoiceOver focus ring follows the full field bounds. Then use the
   validation and reset buttons.
   Inspect the required/invalid states. Interact with **Volume** and change it
   with VoiceOver's value controls; verify the percentage updates.
3. Activate **Announce saved status** and **Announce error alert** one at a
   time. Confirm the status is polite and the error is assertive, then dismiss
   each from its named control.
4. Navigate to **Collections**. Test tab selection, the **Appearance** combo
   box (including the disabled option), and the **Sample documents** list.
   Move through items, select another item, and scroll past the initially
   visible rows to check that the virtualized collection continues to expose
   new items.
5. Navigate to **Dialog**, open the confirmation dialog, inspect its name and
   contents, and confirm/cancel. Check that focus remains inside while it is
   open and returns to the opener after dismissal.

Record the macOS version, VoiceOver version, Alicorn commit, which controls
were announced, and any focus or action failures. The gallery exercises the
implemented semantic roles and actions; it does not claim that every possible
assistive-technology gesture or every application-specific semantic tree is
covered.
