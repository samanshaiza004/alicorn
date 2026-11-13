# Issue #119: bounded two-stop surface gradients

**Implementation status (2026-11-12):** The bounded two-stop prototype is implemented on top of `master` at `0beff9d29f6a1f8b32e0cde895fe4f9ce9f8238c` (which includes the per-corner surface validation commit). Runtime, UI, theme, application, and native unit suites pass; the example and native GPU validation target build. The Metal readback target could not start in this shell because SDL reported that the Cocoa video driver had no displays. D3D12 and a stronger-GPU run are also pending. Issue #119 remains open until those hardware acceptance checks are recorded.

The initial design review below was captured against `655c0f07dc73b3e22da184ea78e479acd0b0758f`; implementation decisions and current evidence follow.

## Implementation and validation (2026-11-12)

### Implemented contract

- `surface_begin` accepts an optional `Semantic_Surface_Gradient`: one horizontal or vertical axis and a second color role. The existing fill role is the first stop. Both stops use the existing core or namespaced extension color-role system; no gradient token type or general theme language was added.
- Resolved endpoints and axis live in the computed semantic-surface sidecar. A one-bit paint marker identifies opted-in commands, so `Paint_Command` remains 128 bytes. Runtime tests also confirm `Node` remains 2,048 bytes and `Description` 768 bytes.
- The SDL GPU renderer evaluates the field in linear-sRGB at the existing vertex positions. A rectangular gradient remains six vertices; rounded gradients use the existing 324-vertex contour/fringe budget. The gradient is defined from the translated, unclipped surface bounds, with the existing scissor applied afterward. Strokes remain solid and separate.
- Stop alpha must match exactly. This makes vertex interpolation compatible with the existing straight-alpha source-over blend. Increased Contrast uses the first stop as a solid fill; Reduce Transparency preserves the gradient and makes both stops opaque. Theme replacement updates the paint cache without invalidating measurement or layout.
- Ordinary non-gradient flat surfaces still use the legacy direct-quad path. Gradient and solid geometry have the same vertex and upload-byte counts; the gradient adds CPU color evaluation, not a texture or additional renderer pass.
- The public API and current renderer implementation are in `runtime/style_surface.odin`, `runtime/style_resolution.odin`, `native/sdl_gpu/material.odin`, and `native/sdl_gpu/solid.odin`. Example 13 is a theme-token-driven active/inactive tab and meter demonstration.

### Local validation

Machine: MacBook Air (Apple M1, 8 CPU cores), macOS 27.2 (build 26B123), Odin `dev-2026-11:9a6991685`.

| Check | Result |
|---|---|
| Runtime suite | Pass, 340 tests |
| SDL GPU package suite | Pass, 174 tests |
| UI suite | Pass, 39 tests |
| `testui` suite | Pass, 13 tests |
| Theme suite | Pass, 36 tests |
| Accessibility contract fixture | Pass, 1 test |
| Scroll-capture suite | Pass, 6 tests |
| Foundation test executable | Pass |
| Example 13 build | Pass |
| GPU validation executable build | Pass |
| `git diff --check` | Pass |

The repository-wide `tools/test.sh` bootstrap was previously stopped at its pinned AccessKit dependency check because this shell could not resolve GitHub. The suites above were run directly against the already-installed pinned dependencies. The readback executable then failed during SDL video initialization with `The video driver did not add any displays`, before selecting Metal or running a pixel case. Therefore no gradient GPU pixels or GPU p50/p95 are claimed here. Windows D3D12 and the requested stronger-GPU comparison remain pending.

### CPU geometry measurement

Three fresh optimized processes each measured 101 warmed CPU vertex-expansion samples per case, alternating solid-first and gradient-first order. Each batch contains 256 surfaces. These are CPU mesh-generation timings only; they exclude application description, upload, GPU execution, compositor/presentation, and input-to-frame latency. The output also records identical vertex/upload budgets and one retained draw slot per surface; `additional_passes=0` is source-path accounting, not GPU capture telemetry.

| Shape | Solid median batch across processes | Gradient median batch across processes | Difference |
|---|---:|---:|---:|
| Rectangle | 3.000 µs | 4.000 µs | +1.000 µs / 256 surfaces |
| Uniform rounded | 771.000 µs | 775.000 µs | +4.000 µs (+0.5%) |
| Per-corner rounded | 750.000 µs | 752.000 µs | +2.000 µs (+0.3%) |

The flat case shows a tiny absolute CPU cost for calculating endpoint colors; rounded cases are close in p50. Per-process p95 values vary, so this small CPU-only sample does not establish tail latency. The raw 101-sample summaries are recorded in [the benchmark output](../benchmarks/raw/issue-119-two-stop-gradients-macos-2026-11-12.txt).

This establishes that the mesh path preserves bounded geometry and does not add upload bytes or a rendering pass in the source path. It does **not** establish the issue's requested native GPU frame/p95 acceptance or stronger-GPU behavior. Keep #119 open for those checks.

### Research source update

The W3C gradient specification makes interpolation space and alpha treatment explicit; CSS Images currently defaults its gradient interpolation to Oklab and uses premultiplied alpha, while Alicorn deliberately specifies linear-sRGB to match its existing theme color storage. Equal-alpha stops avoid the different-alpha premultiplication problem on Alicorn's current straight-alpha pipeline ([CSS Images 4 §3.1](https://www.w3.org/TR/css-images-4/#linear-gradients), [CSS Color 4 §13.5](https://www.w3.org/TR/css-color-4/#interpolating-with-alpha)). Apple describes Increase Contrast and Reduce Transparency as separate system accessibility settings; Alicorn maps them to its solid-fill and opaque-stop policies ([Apple accessibility testing guidance](https://developer.apple.com/documentation/accessibility/testing-system-accessibility-features-in-your-app)).

## Recommendation

**Scoped GO for a two-stop horizontal/vertical fill on `Surface_Paint`.** Keep it opt-in, static, and renderer-neutral. Preserve the existing solid constructor and its exact fast path. First measure the retained-command size before choosing the final representation: `Paint_Command` carries a union payload for every command, while the current `Surface_Paint` stores one `Color` (`runtime/paint_types.odin:32–54, 132–142, 192–223`). A fixed gradient descriptor is small in isolation, but can enlarge every retained command if it grows the largest union member.

## Current paint path and smallest viable architecture

Semantic surfaces resolve a fill/stroke through a cached style and emit an ordinary `Surface_Paint` command (`runtime/paint.odin:426–445`; `runtime/style_resolution.odin:311–341`). The native SDL GPU renderer batches surfaces into one retained vertex buffer and solid pipeline; its vertex format already carries an RGBA color, and flat surfaces use six triangle-list vertices (`native/sdl_gpu/solid.odin:21–38, 48–72, 120–130, 230–339`). Rendering binds that pipeline once for the batch, applies per-command scissors, and draws each command in order (`native/sdl_gpu/solid.odin:401–442`).

The least invasive prototype is a typed `Solid | Linear_Gradient` fill on the existing surface command/style, with a fixed axis enum and exactly two colors. Keep `paint_surface_command(color, ...)` source-compatible as the solid shorthand. Have the SDL solid-mesh builder evaluate the gradient into existing vertex colors; do not create application-authored meshes, textures, render targets, per-surface passes, or animated state. A flat gradient still uses six vertices and its existing draw. Rounded fills can evaluate the same field at their existing tessellation vertices. This uses the existing color varying, not an additional shader, provided the alpha contract below is followed.

Do not grow theme syntax into a general gradient language. The compiler currently has only typed Color and Length tokens (`theme/theme.odin:9–22, 189–210`); a pair of ordinary color roles plus an axis is enough. Compare `size_of(Paint_Command)`, allocation/high-water, and upload bytes before accepting the representation. If inline endpoints materially inflate retained commands, investigate a compact runtime-owned gradient handle only then; it adds lookup/lifetime complexity and is not the first choice.

## Color interpolation and alpha contract

Theme colors are stored as **linear-sRGB RGB with straight alpha**, decoded by the authoring frontend and passed through the adapter/SDL path (`theme/theme.odin:14–20`; `theme/runtime_adapter.odin:126–133`). Specify interpolation in linear-sRGB explicitly. Do not inherit CSS defaults: CSS Images permits an explicit interpolation method, and CSS Color describes conversion to the selected space plus premultiplied-alpha interpolation ([CSS Images 4 §3.1](https://www.w3.org/TR/css-images-4/#linear-gradients), [CSS Color 4 §13.5](https://www.w3.org/TR/css-color-4/#interpolating-with-alpha)).

The existing GPU blend state is straight-alpha source-over (`native/sdl_gpu/solid.odin:55–62`; reference equation and examples in `native/sdl_gpu/blend_validation.odin:44–52`). Hardware interpolation of the current straight RGBA vertex colors is **not** generally premultiplied-alpha interpolation when stop alphas differ. To keep this first prototype on the current path, require equal stop alpha and reject unequal-alpha gradients. Then RGB interpolation is equivalent in straight and premultiplied form; that shared alpha is multiplied by command opacity and composited with the established source-over behavior. This still supports translucent gradient surfaces and overlap; it simply avoids an underspecified varying-alpha ramp. If varying stop alpha proves necessary, add a separately measured fragment path that interpolates premultiplied linear-sRGB and unpremultiplies before the existing straight-alpha blend. Do not silently approximate it with straight vertex interpolation.

## Clipping, rounded geometry, strokes, and DPI

The gradient parameter must be measured against the **translated original command bounds**, never the clipped visible bounds. The simple flat path intersects bounds with clip before creating its quad, while the scissor is derived separately from `command.clip` (`native/sdl_gpu/solid.odin:132–157, 195–212, 252–335`). If `t` is computed from that clipped quad, scrolling/reveal/clipping changes the gradient itself. Clip the already-defined field; do not restart it at the clip edge.

Rounded rectangles use a bounded CPU contour, center fan, and 0.75-physical-pixel antialias fringe; a flat rounded surface currently emits 315 vertices (`native/sdl_gpu/material.odin:10–14, 168–189`; invariant in `native/sdl_gpu/material_test.odin:121–141`). Evaluate fill color from each vertex’s position in the original surface-local bounds, including the contour/AA inner edge, with the existing clip scissor. Preserve the rounded geometry and fringe count. Keep stroke a separate solid `Paint_Stroke`; do not imply that gradient paint also gradients the stroke. Device finalization snaps bounds and clip from retained unsnapped targets, and scale changes rebuild the finalized display (`runtime/layout_measure.odin:832–885`). Recompute the vertex field from those finalized bounds at each scale; stop locations remain attached to the surface’s logical edges. Test at 1×, 1.25×, 1.5×, and 2× as the existing GPU validation does (`native/sdl_gpu/blend_validation.odin:228–252`).

## Theme and accessibility behavior

Resolve the two endpoint colors in semantic-surface style resolution, not during layout or typography. The current cache already depends on Paint and Material, includes a semantic-style signature, and theme/accent changes invalidate Paint (`runtime/style_resolution.odin:10, 311–341`; `runtime/style_surface.odin:89–123`; `docs/themes.md:21–47`). Include both endpoint roles/colors and axis in that signature. Prefer two namespaced extension color roles so application themes can override them with existing token bindings; provide a documented optional-role fallback and validate required roles at theme registration/replacement, following the theme contract guidance (`docs/themes.md:50–65`). No new token kind is needed.

Increased contrast must not leave text or focus legibility dependent on a subtle gradient. Keep focus/stroke as independent structural cues; use an accessible solid fallback or contrast-safe endpoints when the foreground cannot meet the project’s existing targets across the surface. WCAG’s 3:1 non-text and 4.5:1 normal-text criteria are useful test references, not a claim that web conformance rules directly govern native UI ([WCAG 2.2 SC 1.4.3 and 1.4.11](https://www.w3.org/TR/WCAG22/#contrast-minimum)). Apple describes Reduce Transparency as reducing transparency and blur on certain backgrounds to improve contrast and legibility ([Apple accessibility testing](https://developer.apple.com/documentation/accessibility/testing-system-accessibility-features-in-your-app)). Under reduced transparency, choose an opaque semantic fallback or composite the stops against a known opaque surface before rendering; do not leave translucent stops over an unknown backdrop. Alicorn already resolves semantic surfaces opaque and removes translucent outer shadows for this preference (`docs/themes.md:77–90`). A static gradient has no reduced-motion behavior to alter.

## Validation and decision gate

Add pure tests for axis/endpoints/midpoint, invalid or zero-size bounds, equal-alpha validation, and style-cache invalidation on theme replacement. Extend the real SDL GPU readback harness (`native/sdl_gpu/blend_validation.odin:66–118, 228–259`) with horizontal and vertical endpoint/midpoint samples, clipped gradients whose origin must not move, rounded-corner coverage and AA, independent solid stroke, uniform-alpha source-over overlaps, and all four scales. Compare pixels to an independent CPU reference with the existing readback tolerance. Also assert theme/high-contrast/reduced-transparency fallbacks and that style changes do not invalidate layout/typography.

Benchmark the same inactive/active tab surfaces and Pulse meter background against equivalent solid fills on an integrated and a stronger GPU. Record paint/build CPU, GPU encode and p95 frame cost, command size, vertices, uploaded bytes, draw calls/passes, and idle work. Accept only if the app-level custom-paint reduction is meaningful and repeatable, color/readback and clipping remain correct, and the flat-surface path adds no pass, draw, texture, or idle update. Any measurable command-size increase must be included in the retained-memory decision. Otherwise keep the app-level paint alternative and close the prototype without expanding the renderer.

## External references

- [W3C CSS Images Module Level 4, linear gradients](https://www.w3.org/TR/css-images-4/#linear-gradients)
- [W3C CSS Color Module Level 4, interpolation with alpha](https://www.w3.org/TR/css-color-4/#interpolating-with-alpha)
- [W3C WCAG 2.2, contrast minimum and non-text contrast](https://www.w3.org/TR/WCAG22/#contrast-minimum)
- [Apple Developer Documentation, testing system accessibility features](https://developer.apple.com/documentation/accessibility/testing-system-accessibility-features-in-your-app)
