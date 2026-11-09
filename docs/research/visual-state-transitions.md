# Timed transitions for retained visual states

Prototype, 2026-11-09. The Button hover-fill slice is implemented on
`codex/visual-state-transitions`; see the validation notes below. The original
proposal reviewed source at [Alicorn `0fc31ca`](https://github.com/samanshaiza004/alicorn/commit/0fc31ca75c0c666a9be4d766fd91a96acbc14c26).
This remains a bounded prototype under [#91](https://github.com/samanshaiza004/alicorn/issues/91),
with the property and authoring contracts in [#138](https://github.com/samanshaiza004/alicorn/issues/138)
and [#141](https://github.com/samanshaiza004/alicorn/issues/141). Use the existing
[Control Gallery](../../examples/08_control_gallery/main.odin) for the first demonstration.

## Recommendation

Let a recipe opt a visual property into a timed response. Start with the
fill of an ordinary Button on hover entry and exit. Alicorn resolves the
target appearance from its existing interaction state and theme, then
samples a separate presented fill on the retained motion clock. Applications
declare the targets and timing through the recipe. The runtime owns the
clock, interruption, repaint, and settlement.

Keep the duration and curve as a response policy. The existing `Motion_Intent`
vocabulary still describes how an explicit target is used, including Direct,
Snap, Settle, and Reveal. Critically damped Settle remains useful for targets
that need velocity continuity.

## What exists today

| Capability | Verified behavior |
| --- | --- |
| Rest and hover styles | Pointer routing updates retained hover state and queues paint. The Button recipe resolves selected, hover, pressed, and disabled transforms in order. `Style_Transform` mixes color roles. [Input](../../runtime/input.odin#L583-L615), [resolver](../../runtime/style.odin#L709-L779) |
| Explicit motion | `ui.motion` queues targets during description. Retained translation and opacity use a critically damped response for Settle, and compose over the painted subtree. `omega` is a response rate with position and velocity tolerances. [Motion types](../../runtime/motion_math.odin#L9-L45), [reference](../reference.md#L1218-L1276) |
| State driven timing and the example card | Ordinary Buttons can opt their flat opaque hover fill into `.Linear` or CSS `.Ease` timing. The sparse sidecar is separate from computed-style cache and explicit spring owners. Scale and interpolated shadows need new property support. Translation preserves logical hit testing and accessibility bounds. [Button paint](../../runtime/paint.odin), [transition state](../../runtime/style_transition.odin), [motion target](../../runtime/motion_math.odin#L106-L122) |

## Authoring for the first slice

Proposed Odin, using the existing theme registration and scope. The
recipe's existing surface role and hover mix supply the two fill targets.

```odin
theme := alicorn.DEFAULT_STYLE_THEME
recipe := &theme.button_recipes.recipes[int(alicorn.Button_Variant.Default)]
recipe.hover_fill_transition = alicorn.Style_Transition{
    duration = 300 * time.Millisecond,
    easing   = .Ease,
}
```

The policy lives beside the state definitions and applies in both directions.
A zero duration keeps today's immediate behavior. Start with `.Linear` and
`.Ease` presets. `.Ease` uses the W3C curve `(0.25, 0.1, 0.25, 1)`. Evaluate
its y coordinate for the given x progress using a bounded solve. The same
duration and easing type can later serve other typed properties with independent
timings. Start with the Odin recipe field and add JSON authoring once the
behavior has a real consumer. [CSS Easing §2.2](https://www.w3.org/TR/css-easing-1/#cubic-bezier-easing-functions)

This seam keeps the theme as the owner of appearance. Driving hover with
`ui.motion` directly would require application code to observe an interaction
the runtime already handles. Driving it in SDL would place style targets
and owner lifetime outside the shared runtime.

## Timing and state contract

| Event | Presented fill |
| --- | --- |
| First paint, new owner, or motion policy added | Seed at the resolved target. |
| Hover changes with the same compatible recipe and style inputs | Ease between the resting and hovered fills. A full traversal takes the declared duration. |
| Pointer reverses during a leg | Sample the old leg at the current timestamp, then ease back from that value over the remaining fraction of the full span. The resting and hovered endpoints stay fixed. |
| Hover and target stay the same | Continue the existing leg at its original deadline, including across unrelated descriptions. |
| Press, selection, disable, drop cue, theme/recipe change, or preference change | Commit the new resolved target immediately and retire the active fill. Focus and semantic cues stay immediate throughout. |
| Owner leaves the presented tree or retires | Drop its transition state. Returning or recycled controls start at their currently resolved target. |
| Reduced Motion, Increased Contrast, no clock, or exhausted capacity | Present the resolved fill immediately. A mid-flight preference change cancels the track on the next eligible frame. |

For the two-state hover pair, store mix `m` in [0, 1]. On a true reversal,
sample the eased presentation `m` from the current leg, set the new goal `g` to
0 or 1, and use `duration * abs(g - m)` for the new leg. For example, 90 ms
into a 300 ms CSS Ease entry, `m` is about 0.513, so exit takes about 154 ms;
with Linear it takes 90 ms. Keep the original endpoint pair fixed through
repeated reversals. The curve restarts from the sampled value, so color
position is continuous and velocity may change. Validate duration and easing
and check timestamp arithmetic. At or beyond the deadline return the exact
endpoint, including after a missed frame. A native display shows it on its
next presentation opportunity. [CSS Transitions §3.1](https://www.w3.org/TR/css-transitions-1/#reversing)

Initially require a flat, opaque surface at both endpoints and unchanged
foreground color between those endpoints. Use the existing linear component
mix on resolved fills. The theme compiler already decodes source sRGB into
linear-sRGB runtime colors. For a later translucent property, interpolate
premultiplied linear RGB and alpha, then return straight-alpha paint with a
zero-alpha guard and exact endpoint handling. Verify the in-between color
and contrast in the actual renderer. [Alicorn color contract](../themes.md#color-and-length-runtime-contract),
[CSS Color §13.5](https://www.w3.org/TR/css-color-4/#interpolation-alpha)

## Runtime integration

1. **Retarget at the Button paint seam.** In the ordinary Button branch of
   `update_paint`, resolve the current target using the effective hover
   state, which includes linked visual parts. Compare it to the target and
   style stamp from the previous paint of that owner. The computed style
   cache is shared with the inspector and composed labels, so either can
   resolve the new target before the button paints. Record the paint
   baseline in the transition state and feed the sample only to the surface
   command. A theme replacement can retain the same ID, so the stamp includes
   dependency generations and the policy. Connected tabs, context-menu
   rows, and tab close buttons have separate paint paths.
   [Computed style](../../runtime/style_resolution.odin#L134-L204),
   [inspector](../../runtime/inspector.odin#L388-L399),
   [theme replacement](../../runtime/style.odin#L483-L521),
   [Button paint](../../runtime/paint.odin#L450-L540)
2. **Keep transition state sparse.** Allocate a bounded sidecar only for
   eligible, opted-in, realized owners. Each entry holds the adopted target,
   compatible style stamp, fixed endpoint pair, and presented sample, with a
   timed segment while active. Sample only active
   entries. Copy the numeric endpoints by value. Disarm the segment on
   settlement or snap, and remove the entry on opt-out, loss of presentation,
   retirement or runtime destruction. An owner can also have an explicit
   translation or opacity response. Its fill lifetime follows the recipe
   and node independently of explicit motion handle release.
   [Owner retirement](../../runtime/reconcile.odin#L752-L769),
   [explicit release](../../runtime/motion_retained.odin#L1360-L1377)
3. **Use the existing motion tick and activity.** Include active fill tracks
   in the same `motion_tick` and `motion_activity` that serve explicit
   motion, including when the explicit motion map is empty. Count unique
   owners for scheduler decisions. When a sampled fill changes, queue Paint
   and request one retained presentation for the window. Reuse the paint
   queue and keep sampling off the allocating interaction-reason path.
   Report fill retarget, reversal, snap reason and settlement through the
   bounded motion diagnostics. [Tick and activity](../../runtime/motion_retained.odin),
   [paint queue](../../runtime/reconcile.odin#L657-L674)
4. **Arm the first frame and disarm the last.** Inject the current monotonic
   timestamp for retained frames as well as descriptions. The SDL loop
   currently advances the motion scheduler before flushing interaction-only
   paint. If the flush starts the first track, the same turn must refresh the
   existing scheduler's deadline from the new activity before waiting for
   events. Check primary, secondary, and live-resize host paths. When a
   window is hidden, use existing suspension behavior and sample at the
   restore time. The last active fill's settlement or cancellation should
   leave no motion deadline. [Native turn](../../native/sdl_gpu/application_loop.odin#L694-L730),
   [wait deadline](../../native/sdl_gpu/application_loop.odin#L291-L298),
   [scheduler](../../native/sdl_gpu/scheduling.odin#L85-L143)
5. **Flush the same retained work in `testui`.** Its virtual clock already
   calls `motion_tick`. Its turn currently runs descriptions while the root
   is invalidated, so hover alone can leave queued paint unflushed. Give input
   and time advances the same timestamped retained-frame flush using
   `begin_presentation_frame` and `end_presentation_frame`, with existing
   bounded corrective descriptions if the flush exposes further work.
   [Harness turn](../../testui/testui.odin#L327-L363),
   [virtual time](../../testui/testui.odin#L899-L928),
   [retained frame](../../runtime/reconcile.odin#L1095-L1122)

Paint-local is a statement about which nodes are repainted. A Button with
fill and text has multiple commands. The current incremental display slot
update requires one command, so even a local fill change can recompose the
display list. Measure compose visits, full rebuild reasons, text mesh work
and CPU encode time in a dense real scene before expanding adoption. If that
cost dominates, prototype a fixed fill slot update that preserves composed
clip, translation, opacity, painter order and revision. [Composition fallback](../../runtime/paint.odin#L714-L736)

## Prototype gate and rollout

| Check | Evidence required |
| --- | --- |
| Virtual time | Physical hover in/out, exact endpoints and deadline, intermediate fill, reversal at 30%, repeated same target, and a late sample. Inspect emitted fill as well as target. |
| State and ownership | Press/disable and focus feedback remain correct. Resolve the new target through the inspector before paint. Replace a theme under the same ID mid-flight. Flip Reduced Motion and Increased Contrast. Exercise retirement, reappearance, same-key reuse, and capacity fallback. |
| Retained work | In an otherwise stable scene, zero application descriptions, reconciliation, measure, layout, or reshaping for hover and sampling. Count paint/compose work and allocations after warmup. The opt-out control schedules no motion. |
| Native | Run a matched Gallery comparison on macOS/Metal and Windows/D3D12. Move onto the control and hold the pointer still. Check progression, completion, rapid reversal, hide/restore and a secondary window. Compare pre/mid/post frames and confirm motion wakes and submissions stop when settled. |

The Gallery demonstrates 120 ms, 180 ms and 300 ms CSS Ease hover fills on
Default, Primary and Toolbar buttons, with an immediate Quiet control. The
headless regression checks emitted fill colors, inspector independence,
reversal, exact settlement, no description/layout/shaping work, and a Reduced
Motion snap. Native Metal and D3D12 comparison is still required before
promoting this beyond the prototype. After that dogfood, try a second real
consumer on a stable visual part before making transition fields available to
more recipes. Add JSON authoring only when a real consumer needs it.

The card can add a timed translation for a small lift once the fill seam
works. Give its visual group a stable logical interaction owner and room for
the lift and shadow within ancestor clips. Scale needs a pivot and coherent
subtree composition for text, clips, icons, and focus decoration. Keep a
stable hover region even if a later interactive control chooses presented
hit bounds, so the lift cannot change its own hover state. For shadows,
interpolate compatible analytic paint parameters as values with bounded
outsets. Preserve immutable material registrations and Reduced Transparency.
An exact CSS shadow with independently authored offset and blur requires
its own typed paint representation. [Clip and hit policy](../reference.md#L1232-L1237),
[analytic material](../../runtime/material.odin#L10-L24), [property roadmap](https://github.com/samanshaiza004/alicorn/issues/138)

## Primary precedents

- CSS associates timing with each transitionable property, compares previous
  and new computed styles, and starts replacement motion at the current
  sample. It shortens interrupted reversals. The Alicorn proposal adopts
  property opt-in and continuous retargeting, with presentation kept outside
  style resolution. [CSS Transitions §§3–4](https://www.w3.org/TR/css-transitions-1/#starting)
- Jetpack Compose's `animate*AsState` seeds the first target and tracks a new
  target from the current value. Compose offers both spring and tween specs.
  A spring can preserve velocity when interrupted, and a tween specifies a
  duration and curve. Alicorn can make the same distinction behind one
  retained clock. [Value-based animations](https://developer.android.com/develop/ui/compose/animation/value-based),
  [animation specs](https://developer.android.com/develop/ui/compose/animation/customize)
- Qt Quick's `Behavior` attaches an animation to one property. Its documented
  hover-state example can drift if an in-flight sample becomes the resting
  endpoint. Alicorn should retain the resolved endpoints independently of
  the sampled value. [Behavior](https://doc.qt.io/qt-6.8/qml-qtquick-behavior.html),
  [Behaviors with States](https://doc.qt.io/qt-6/qtquick-statesanimations-behaviors.html)
