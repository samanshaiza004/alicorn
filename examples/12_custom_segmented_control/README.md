# Custom Segmented Control

This is a standalone third-party control package. It imports only
`alicorn:runtime` and `alicorn:ui`; it does not read `Runtime` storage, call
private layout or paint functions, or edit Alicorn source.

Run it from any working directory through the repository runner:

```sh
./tools/run_example.sh 12_custom_segmented_control
```

The package owns the track and segment surfaces, shapes, label styling, hover
accent, keyboard-focus frame, disabled treatment, selection indicator, responsive
layout, semantic identities, theme contract, and per-instance overrides. Its
embedded theme is independent of the process working directory.

Each segment uses public `button_begin` / `button_end` as its interaction
owner. That retains Alicorn's pointer hit testing, Tab focus, Space/Return
activation, disabled behavior, and Button accessibility semantics. It opts
into `presentation=.Custom`, so Alicorn leaves the recipe fill, label,
selection decoration, and focus paint to the package. The Button label remains
the accessible name and does not create a hidden text-layout requirement.
Selection belongs to the caller's `Segmented_State`, not to a second widget
state or an Alicorn internal.

The two responsive alternatives bind equivalent choices to the same semantic
IDs, so focus continuity can be checked while resizing. The moving marker uses
public `ui.motion`; it retargets from its current presentation and settles
without continued idle work. Selection remains apparent without relying on
color alone: it changes the surface, label weight, and opacity and position of
a consistently sized marker. Hover has a separate accent beside the label,
while keyboard focus is an independently themed frame attached with
`.Owner_Focus_Visible`. Equal label gutters preserve text centering as the hover
accent appears. Disabled options place a muted “Unavailable” caption below the
centered label.

The responsive segment rows use zero layout gap. In the wide presentation,
Preview rounds its left corners, Edit stays square, and Compare rounds its
right corners. The compact presentation maps the same endpoints to the top and
bottom. Both the face and its keyboard-focus frame use the public
`Surface_Corner_Radii` API. The existing focus inset leaves a narrow track
separator between face fills so focus does not change their layout; it is a
deliberate shared-edge treatment rather than an overlap or clipping workaround.

## Theme and instance contract

The component declares seven required extension-color roles. The consuming app
checks those bindings once during initialization, reports missing roles, and
stops rendering the control if a required role is absent. A per-instance
accent is optional and falls back to the recipe accent. Geometry overrides
are ordinary typed values on `segmented.Style`; they do not fork a recipe.

The sample's purple instance has a different accent, track and segment radii,
padding, focus inset, option height, marker geometry, and label size. Its
Compare option is disabled to demonstrate accessible disabled state and muted
presentation.

## Validation

The `testui` checks drive the same theme initializer and content renderer as
the native demo. They cover role resolution, custom Button semantics, disabled
state, keyboard activation, pointer hit testing, responsive semantic focus,
per-instance tokens, rapid motion retargeting, idle settlement, reduced motion,
and larger text scale. These checks do not replace a physical VoiceOver or
Windows UIA session.

## Friction found

The `.Custom` Button presentation and `.Owner_Focus_Visible` visual-part
condition remove the main paint-ownership workaround from the first version of
this experiment. The component owns the visible control while Alicorn retains
the interaction, semantic, and keyboard-modality contracts.

The example deliberately keeps Button semantics rather than claiming radio
group arrow-key behavior. Adding arrow-key navigation would be a separate
interaction contract for this control.
