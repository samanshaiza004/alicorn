# Third-Party Mode Rail

This example is a reusable compound control that stays entirely in the public
`alicorn:ui` and `alicorn:runtime` interfaces. The package owns its layout,
theme-role contract, responsive presentations, and visual policy. The app owns
the selected and disabled values.

Run it from any working directory with the repository runner:

```sh
./tools/run_example.sh 11_third_party_component
```

The theme JSON is embedded at compile time beside `main.odin`, so launching the
executable does not depend on the current working directory.

## Extending the component

`mode_rail/theme.json` ships the component's default token bindings and is
embedded by the component package. A consumer can copy those defaults into its
application theme, replace token values or role bindings, and register the
result without changing the component recipe. The demo also adds its own
window-background and purple per-instance roles.

`mode_rail.Recipe` declares three required extension-color roles and one
optional attention role. `theme_contract_check` validates role bindings during
initialization or theme replacement. The app reports missing required role
names once, displays the missing names, and uses a visible error state. When
the optional attention role is missing, the component uses its required signal
role.

Each rail receives a stable, unique `instance_id`. The wide and compact buttons
for the same choice bind to the same logical semantic ID. Alicorn can therefore
move keyboard focus to the equivalent option when the assigned width changes.
The ID is separate from the retained presentation key, which may differ by
layout.

`Instance_Overrides` supplies a narrow set of optional instance-level values.
Zero fields inherit the recipe's defaults. The third rail uses the same recipe
as the other two while choosing its own purple token, larger labels, pill
corners, and a taller marker. It also demonstrates a disabled choice.

Options use ordinary Alicorn Buttons for pointer hit testing, keyboard
activation, focus treatment, and disabled behavior. `semantic_augment` adds a
spoken description without replacing the Button's role, name, selected or
disabled states, or Press action. `semantic_bind` preserves each choice's
logical identity across adaptive alternatives.

The selected marker differs in size and opacity as well as color. Motion uses
the retained `ui.motion` interface, so new targets interrupt from the current
presentation, reduced-motion preferences are honored, and settled markers
return the window to idle.

This sample deliberately exposes each choice as a Button. It does not claim
radio-group arrow-key navigation; a radio-style interaction contract would be
a separate component decision.

## Validation

The native demo uses `ui.run` and its typed `on_initialize` hook. The example
tests call the production theme initializer and full application
build callback through `alicorn:testui`. They cover the embedded JSON theme,
required and optional role handling, Button semantic augmentation, disabled
options, keyboard activation, focus continuity across resize, rapid motion
retargeting, idle settlement, and accessibility appearance preferences.

`testui.resize` updates the harness viewport and runs that same app build
callback, so tests can exercise adaptive selection and focus repair without a
native window. These headless checks do not replace a physical VoiceOver or
Windows UIA session.
