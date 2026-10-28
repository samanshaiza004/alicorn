# Typed themes

Alicorn's theme compiler is a small design-token compiler, not a runtime
stylesheet engine. It compiles source values, aliases, and semantic-role
bindings into immutable typed arrays. The runtime resolves those values by
theme-local numeric IDs; it does not parse files or look up token strings while
describing a frame.

## Ownership and identities

- Alicorn owns the fixed `Style_Color_Role` vocabulary used by built-in
  components.
- Application and vendor roles use qualified names such as
  `app.editor.current_line` and `vendor.audio.meter.hot`; they do not extend
  Alicorn's core enum.
- Color and length token IDs are distinct and local to one compiled/registered
  theme. A token ID is only meaningful together with its immutable theme ID.
- Extension-role IDs are typed, namespaced hashes. The compiler rejects a
  collision among roles of the same type instead of letting one binding win.
- The runtime retains one `Computed_Style` entry per resolved node in a
  Runtime-owned sidecar map, keyed by `Node_ID`; the retained `Node` stays under
  its byte budget. Button, Checkbox, Slider, Text Field, Scrollbar, and
  Semantic Surface results share exact dependency-domain snapshots and
  semantic input signatures.
  Scope changes advance only affected nodes; cache hits reuse the resolved
  payload and its provenance. Retirement and runtime destruction release the
  corresponding sidecar storage.
- Button, Checkbox, Slider, Text Field, and Scrollbar recipes depend on Paint.
  An opt-in Button surface treatment also depends on Material.
  Semantic Surface resolution depends on Paint for its role color and Material for its shape,
  material, optical height, and group. Theme registrations and material
  registrations are immutable; recipe/state/theme identity is part of the
  computed-style signature, and semantic-surface description changes are
  hashed into its signature and advance their respective domains.
- Theme and accent changes schedule Paint only; immutable opt-in Button
  treatments are selected with the recipe and never invalidate measurement.
  Built-in widgets do not implicitly consume theme lengths
  as geometry, but applications can pass an explicitly resolved logical length
  through `style_metric`; the #28 fixture and Scratchpad's editor-padding
  dimension exercise that Metrics → Layout seam. Theme lengths do not implicitly
  change typography or material selection. Text scale still advances Metrics
  and Typography for its scoped subtree, while color-only recipe caches remain
  valid. Optional authored token names, immediate alias edges, and qualified
  extension-role names are copied into registered themes for inspector output;
  source spans and parser structures remain compiler-only. These names are
  diagnostic metadata, not runtime lookup keys.

## Accessibility appearance inputs

`Style_Environment.accessibility` carries normalized visual preferences from
the application or host. Set `accessibility_set=true` when pushing the value;
this lets an explicit all-false value reset an inherited scope. The existing
`Style_Environment.text_scale` is the normalized user/host text scale and
continues to invalidate Metrics and Typography. Accessibility appearance state
is separate from `Semantic_Node`: it never changes semantic role, name, value,
actions, or state.

Increased contrast resolves text and structural roles to stronger ink/boundary
colors, thickens focus and structural outlines, and strengthens analytic
material bevels. Built-in control recipes run a final text/focus/indicator
contrast fallback after theme transforms, so choosing an unusual custom role
cannot erase these required signals. For opaque resolved control surfaces, the
fallback targets at least 4.5:1 for control text and 3:1 for focus/selection
indicators; translucent themes can pair increased contrast with reduced
transparency for the same visible contrast guarantee.
`differentiate_without_color` adds an underline to selected
buttons; Checkbox marks remain glyph-based and Slider values remain marked by
the outlined thumb. Reduced transparency makes semantic theme surfaces opaque
and removes analytic materials' translucent outer shadows. Preference-adapted
materials are immutable, cached variants in the Runtime material registry, so
re-describing a surface does not append an unbounded series of duplicates.

The runtime currently has no animated style transitions or animated material
responses. `reduce_motion` is retained and inspectable, and changing it advances
the Material dependency so future motion-sensitive material behavior must
consume it. It does not flatten static relief. Applications can also pass
normalized values through `Style_Environment` for a manual scoped override.
The native SDL host imports the normalized appearance preferences exposed by
Windows and macOS and listens for platform change notifications. Windows
provides increased contrast, reduced motion, reduced transparency, and the
system text scale from `UISettings`; macOS provides all four boolean
accessibility preferences but no corresponding general text-scale value in
this adapter. The Windows text scale is normalized to Alicorn's `text_scale`
input (the native setting ranges from 1 to 2.25). Notifications are coalesced
into a host-only wake; the host rereads the snapshot on its event loop and
updates the persistent root appearance only when a supported value changes.
The runtime applies the reported factor uniformly to its text products; Windows
documents more nuanced scaling behavior across different text sizes, so this
does not exactly reproduce how Windows UI frameworks scale each text style.
Failed or unsupported native queries preserve the last known value rather than
turning it into `false` or resetting the scale. Linux currently uses the
default appearance and text scale and has no native preference monitor.

The host base contains the normalized text scale and
`Accessibility_Appearance_Preferences`, rather than a complete persistent
`Style_Environment`. `style_root_accessibility_observation_set` accepts the
platform's known preference fields and optional text scale between frames;
unknown scale observations preserve the last accepted value. The simpler
`style_root_accessibility_set` remains available for preference-only updates.
Normal scopes inherit the host values; applications can explicitly override
text scale or the complete accessibility bundle with
`style_environment_push`. These changes affect visual style dependencies only
and do not mutate semantic roles, labels, values, actions, or states. Windows
integrated menu/title-bar chrome consumes the same normalized increased-
contrast value. Native high-contrast system-palette integration remains
separate; Alicorn does not yet resolve an application-wide system color theme.

```odin
appearance := alicorn.Accessibility_Appearance_Preferences{
  increased_contrast=true,
  reduce_motion=false,
  reduce_transparency=true,
  differentiate_without_color=true,
}
scope := alicorn.style_environment_push(&ui, alicorn.Style_Environment{
  text_scale=1.15,
  accessibility=appearance,
  accessibility_set=true,
})
// Describe the themed subtree here.
alicorn.style_environment_pop(&ui, scope)
```

## Built-in control recipes

The built-in recipe families describe semantic visual parts; layout and input
geometry remain with their existing control APIs. `Button_Recipe_Set` supplies
explicit button variants; `Checkbox_Recipe` supplies box, checkmark, label, and
focus parts; `Slider_Recipe` supplies track, fill, thumb, label, and focus
parts; `Text_Field_Recipe` supplies the field surface, text, border, selection,
caret, and independent focus treatment; and `Scrollbar_Recipe` supplies the
track, thumb, and corner. Checkbox and Slider parts apply selected (checked
for Checkbox), hovered, pressed, and disabled transforms in that order. Focus
remains a separate overlay, so it does not erase the resolved state colors.

Theme source can sparsely override built-in Button variants. For example, a
selected tab underline can use the theme accent while other values inherit the
typed runtime default:

```json
"recipes": {
  "button": {
    "tab": {
      "selected_indicator_role": "accent"
    }
  }
}
```

Recipes primarily contain semantic color roles and state transforms.
`Text_Field_Recipe.horizontal_inset` is the exception: it sets the logical
horizontal content inset, which Alicorn scales by the active density and uses
consistently for shaping, clipping, pointer geometry, caret, selection, and
IME positioning. Checkbox and Slider parts resolve independently through the
same recipe vocabulary, so themes can change their appearance without
changing widget semantics. The strict JSON source currently authors
sparse Button variants and selected/hovered/pressed/disabled role transforms;
Checkbox, Slider, Text Field, and Scrollbar recipe authoring remains a typed
Odin setup API.

## Semantic surface composition

### Optional Button relief (typed setup API)

`Button_Recipe.rest_surface` and `pressed_surface` optionally carry a
`Button_Surface_Treatment{defined, material, physical_height}`. Register the
immutable material in the same Runtime before registering its theme. Optical
height is bounded to -2 through 2 and never changes layout, hits, focus,
semantics, or compositor ordering. Omitted rest is flat; omitted pressed
inherits rest. An explicitly defined flat pressed treatment overrides relief.
Disabled controls use rest. Selected/hovered color transforms retain their
existing order, and focus remains an independent outline.

```odin
theme := alicorn.DEFAULT_STYLE_THEME
recipe := &theme.button_recipes.recipes[int(alicorn.Button_Variant.Default)]
recipe.rest_surface = {defined=true, material=mounted, physical_height=0.5}
recipe.pressed_surface = {defined=true, material=mounted, physical_height=-0.25}
theme_id := alicorn.style_theme_register(rt, theme)
```

This is a setup-only typed recipe extension. JSON contract 0.2 still authors
colors, lengths, analytic material definitions, and the documented sparse
Button color/state recipes; it does **not** author these Runtime-local material
handles. Existing generated themes and default Buttons remain flat. Contrast
and reduced-transparency preferences adapt relief through the same immutable
material variants used by semantic surfaces. No style animation or polling is
introduced.

Applications can wrap ordinary layout content in a semantic surface without
calculating paint bounds or constructing renderer commands. A surface resolves
either a core color role or an app/vendor extension role against the active
theme scope, then paints its resolved container bounds and clip. This
high-level helper currently accepts rectangular surfaces only. Rounded and
other shapes remain in the lower-level paint contract but are rejected here
until the native renderer can draw them. Registered material and optical
height describe appearance only; optical height does not affect layout or
ordering.

```odin
paper_role := alicorn.style_extension_color_role_id(
  "app.scratchpad.editor",
  "paper_surface",
)
paper_material := alicorn.style_material_register(&runtime, alicorn.Style_Material{
  kind=.Analytic_Relief,
  bevel_width=1,
  bevel_strength=0.12,
})

scope := alicorn.style_environment_push(&ui, alicorn.Style_Environment{theme=paper_theme})
alicorn.surface_begin(
  &ui,
  alicorn.surface_extension_color_role(paper_role),
  key="editor-paper",
  style=alicorn.layout_style(width=640, height=480, padding=12),
  shape=alicorn.Surface_Shape{kind=.Rectangle},
  material=paper_material,
  physical_height=0.5,
)
alicorn.text(&ui, "content is laid out inside the resolved paper bounds")
alicorn.surface_end(&ui)
alicorn.style_environment_pop(&ui, scope)
```

Use `surface_core_color_role(.Surface)` for a built-in role or
`surface_extension_color_role(role_id)` for a namespaced theme role. The
extension role must be present in the active theme when the surface is
described. Register materials during setup; runtime descriptions carry only
the immutable `Material_ID`. Surface role changes advance the node's Paint
generation; shape/material/height/group changes advance its Material
generation, while the description/paint hashes schedule the actual redraw.
Material registrations and registered themes are immutable, so a registry
append cannot change an already-resolved surface.

Complete document/theme ownership stays outside the runtime: parsing and
compilation happen in the `theme` package, then
`theme_runtime_style_theme` adapts a successful compiled result to
`Style_Theme`. Register it with `style_theme_register`; registration copies
token and role-binding storage, so the adapter-owned value can then be
destroyed. The built-in theme remains a typed `DEFAULT_STYLE_THEME` value and
does not need a parser or filesystem access to start Alicorn.

## Supported source subset

The first source frontend is strict JSON with a documented DTCG-inspired
subset. It is not a claim of full DTCG compatibility. Schema version is exact;
the current theme contract is `0.2`. Contract compatibility requires the same
major version and a minor version no newer than the compiler supports.

```json
{
  "schema": 1,
  "contract": "0.2",
  "extends": "alicorn.base",
  "tokens": {
    "palette.ink": {
      "$type": "color",
      "$value": {
        "colorSpace": "srgb",
        "components": [0.08, 0.10, 0.14],
        "alpha": 1
      }
    },
    "text.primary": {
      "$type": "color",
      "$value": "{palette.ink}"
    },
    "space.gutter": {
      "$type": "dimension",
      "$value": {"value": 8, "unit": "px"}
    }
  },
  "roles": {
    "core": {"text": "{text.primary}"},
    "extensions": {
      "app.editor.gutter": {
        "$type": "dimension",
        "$value": "{space.gutter}"
      }
    }
  },
  "materials": {
    "app.editor.paper": {
      "kind": "analytic_relief",
      "bevel_width": 1,
      "bevel_strength": 0.36,
      "inner_shadow_strength": 0.18
    }
  },
  "recipes": {
    "button": {
      "tab": {
        "selected_indicator_role": "accent",
        "states": {
          "hovered": {"surface_mix": 0.42}
        }
      }
    }
  }
}
```

Only `color` and `dimension` tokens are supported. Color source values must
explicitly use `srgb` components; the frontend decodes encoded sRGB RGB
components to linear-sRGB float channels, while alpha remains straight
normalized alpha. Other color spaces and DTCG color forms are rejected rather
than guessed. Lengths accept only `px`, interpreted as context-free Alicorn
logical units; `em`, `%`, viewport units, and DPI conversion are not part of
this contract. Values may be literals or `{token.name}` aliases. Aliases are
resolved after base-to-derived symbolic definitions are overlaid, so an
inherited alias observes a child's override of its target.

`extends` is metadata, not an instruction to read arbitrary files. The compiler
API accepts ordered source layers supplied by its caller; the initial command
line tool accepts only the built-in `alicorn.base` identifier. File loading,
inheritance policy, and application-specific theme discovery remain with the
host application.

### Version compatibility and fallback policy

The source schema is exact (`1`) and independent from style semantics. Alicorn
currently supports this contract matrix:

| Theme contract | Result with Alicorn contract 0.2 | Reason |
| --- | --- | --- |
| `0.0` | Accepted | Same major; older minor |
| `0.1` | Accepted | Same major; older minor |
| `0.2` | Accepted | Current contract |
| `0.3` | Rejected | Future minor may require semantics this compiler lacks |
| `1.0` | Rejected | Different major is incompatible |
| Any schema other than `1` | Rejected | Source parsing is an exact schema contract |

The compiler accepts the same contract major and any minor no newer than its
supported minor. A layered compile reports the highest compatible minor among
its input layers. A future optional contract feature must define a deterministic
fallback before it ships; an older theme must not acquire a different meaning
merely because a new optional role or recipe property was added.

The initial source requires `schema`, `contract`, and a `tokens` object;
`roles`, `materials`, `recipes`, and `extends` are optional.
`extends: "alicorn.base"` supplies typed symbolic values for aliases and role
overrides. It never loads a file path.

Fallbacks are part of the contract, not a parser convenience:

| Omitted value | Resolved behavior | Inspection |
| --- | --- | --- |
| Core color-role binding | Preserve the corresponding typed `DEFAULT_STYLE_THEME` color | `theme explain <file> role.<name>` reports the value and binding/token source; `alicorn.base` is identified as a typed built-in source |
| Button recipe or individual recipe field | Preserve that field from `DEFAULT_STYLE_THEME.button_recipes`; sparse overlays replace only fields they specify | `theme explain <file> recipe.button.<variant>` distinguishes authored fields from inherited defaults |
| App/vendor extension role | No binding is created; lookup remains unresolved until an explicit declaration is present | `theme check` reports the declared extension count |
| Named material definition | No named definition is synthesized; ordinary flat surfaces continue to use `MATERIAL_FLAT` / `STYLE_MATERIAL_FLAT` | `theme explain <file> material.flat` shows the built-in fallback |

The built-in base is a complete typed source projection of Alicorn defaults. A
theme that omits `extends` can still omit core bindings: the runtime adapter
preserves `DEFAULT_STYLE_THEME` values. `theme check` reports resolved counts
and the fallback source categories. `theme explain role.*` reports the concrete
linear-sRGB value, role binding location, and terminal token location, including
alias chains.

`materials` names must use the `app.*` or `vendor.*` namespace. The supported
kinds are `flat` and `analytic_relief`; analytic bevel and shadow parameters
have explicit runtime bounds. A later layer may replace a same-kind material,
but cannot change its kind. `theme explain <file> material.<name>` reports the
resolved parameters and defining source location.

`recipes.button` currently accepts sparse overrides for `default`, `primary`,
`toolbar`, `quiet`, `tab`, and `danger`. State transforms can set semantic
surface/text roles and bounded mixes for selected, hovered, pressed, and
disabled states. Unspecified values inherit the built-in or preceding layer.
`theme explain <file> recipe.button.<variant>` prints the authored fields and
source location. This is Alicorn's sole native v0.2 authoring format; the JSON
subset stays limited to features exercised by real consumers.

Core color-role bindings are optional overrides. Any omitted role retains its
required Alicorn `DEFAULT_STYLE_THEME` value in the runtime adapter. An explicit
unknown core role or unsupported core field is an error rather than a silently
ignored typo. App/vendor extension roles are also optional, but have no
implicit runtime value: a role is resolvable only when declared, and its type
cannot change across source layers. Extension declarations must use `app.*` or
`vendor.*`; they do not add names to Alicorn's core role vocabulary.

## Color and length runtime contract

`Theme_Color` channels are linear-sRGB values in `[0,1]`; alpha is linear,
straight (not premultiplied) alpha. The JSON frontend's sRGB conversion is the
only color-space conversion in this compiler slice. The runtime adapter copies
those values unchanged into Alicorn `Color`; the current native vertex path
also uploads the channels unchanged. Output transfer encoding remains the
renderer/swapchain contract and is not inferred from a theme file. P3, OKLCH,
color mixing in perceptual spaces, and extra GPU-side conversions are
unsupported. This deliberately keeps authoring conversion explicit without
silently changing the native renderer's behavior.

`Theme_Length` is a finite nonnegative logical-unit value capped at the
runtime's supported maximum. It has no implicit dependency on DPI, font size,
parent size, or viewport dimensions.

## Diagnostics and determinism

The JSON frontend preserves byte offsets and one-based line/column positions
for source values and declarations. It rejects duplicate JSON keys, duplicate
token/role declarations, unsupported fields, malformed aliases, unknown core
roles, and unsupported units/spaces. The compiler reports typed alias errors,
cycles, incompatible overrides, invalid values, unsupported schema/contract
versions, and extension-role hash collisions. Compiler output separates the
compact `Compiled_Theme` from source names/spans in `Theme_Debug_Metadata`;
debug provenance can be discarded after tooling/inspector use without making
runtime token IDs depend on string lookups.

Layer and declaration order do not affect the compiled semantic signature.
Source spans and diagnostics remain ordered by path and byte offset for
repeatable tooling output. A failed parse or compile must not replace an
already-active runtime theme; only a successful immutable result is suitable
for registration.

Compatibility fixtures freeze this behavior. `theme/compatibility_test.odin`
checks contract 0.0, 0.1, and 0.2; rejects a future minor, a different major,
an unsupported schema, an unknown core role, and an extension type change; and
asserts that omitted core roles, recipes, and named materials follow the rules
above. The Scratchpad Warm and Cool Light JSON fixtures are copied from
Scratchpad commit `ff5cddf23c4efd97564f9c9fcc4072f6165088a8`. Their compiled
and adapted theme signatures are release-contract snapshots. Updating a golden
is a deliberate contract review: inspect the resolved values and document why
an existing compatible theme should now resolve differently. A new compiler
must not silently refresh the expected signatures.

### Deprecation and migration policy

Contract 0.2 has no deprecated theme names or properties. When Alicorn
introduces a real replacement, it will keep the old form accepted for the rest
of that contract major, emit a source-located warning, and name the exact
replacement in the diagnostic. Warnings do not make a theme invalid. The
compiler diagnostic carries the deprecated `related_name` and optional exact
`replacement`; `theme check` prints the warning and replacement, while
`theme explain` continues to show the resolved value and origin. The compiler
returns a successful result when diagnostics contain warnings only.

Contract-minor releases add backward-compatible behavior with explicit
fallbacks. A breaking semantic removal requires a new contract major. The JSON
source schema remains exact; a syntax-breaking schema change is not silently
rewritten by `theme check` or `theme compile`. Alicorn will add a one-time
conversion command only when a concrete source-format transition exists, and
that command must report each transformed or unsupported field. There is no
speculative general migration language or automatic source rewrite today.

The built-in Odin test suite exercises the source model, compiler, JSON
frontend, and runtime adapter with:

```sh
odin test theme
```

For authoring feedback, the small CLI validates a file and explains resolved
token values/alias chains:

```sh
odin run tools/theme -- check path/to/theme.json
odin run tools/theme -- explain path/to/theme.json text.primary
odin run tools/theme -- explain path/to/theme.json role.text
odin run tools/theme -- explain path/to/theme.json recipe.button.tab
odin run tools/theme -- explain path/to/theme.json material.flat
odin run tools/theme -- compile path/to/theme.json --output generated_theme.odin --symbol APP_THEME
```

`theme compile` validates and compiles the source through the same runtime
adapter, then emits deterministic Odin source containing a factory procedure
for an owned `Style_Theme`. The generated file is parser-free at application
startup. Its matching `<symbol>_destroy` procedure releases the token and role
binding slices after use; after `style_theme_register` copies the theme, call
that destroy helper immediately. Token and role provenance text is emitted as
static Odin string literals; the generated cleanup frees the containing slices
but does not try to free those literals. The generated package defaults to `main`
and the runtime import defaults to `alicorn:runtime`. Use `--package` and
`--runtime-import` when the consuming Odin package uses different names, for
example:

```sh
odin run tools/theme -- compile themes/workbench.json \
  --output generated/workbench_theme.odin \
  --symbol WORKBENCH_THEME \
  --package main \
  --runtime-import alicorn:runtime
```

The factory accepts an optional allocator and returns owned slices. The
generated source only captures what the current runtime adapter supports; it
does not broaden the runtime style contract or add a theme file parser to the
application.

This is intentionally a narrow v0.2 foundation rather than a general cascade:
there are no selectors, arbitrary properties, inheritance filesystem loader,
theme hot reload, or global cross-node memoization.

## Runtime contract conformance

`tests/style_environment.odin` contains the end-to-end styling contract fixture.
It compiles the strict JSON source through alias resolution and the built-in
base, adapts and registers the immutable runtime theme, then uses its core and
app-namespaced roles in a scoped editor subtree with a normal Button recipe and
a semantic Surface. The fixture also checks retained `Computed_Style`
provenance and verifies that visual changes leave the semantic entity unchanged.

The retained domain boundary is part of the contract:

- Metrics can drive layout when an application explicitly uses a resolved
  logical-length token through `style_metric`.
- Typography reshapes text and relayouts only the affected environment scope.
- Paint changes repaint that scope and do not visit layout.
- Material changes repaint/recompose without changing layout bounds or hit
  geometry.
- Sibling scopes keep their own generations, and an unchanged idle frame does
  no style-resolution or layout work.

This fixture closes the runtime architecture proof for issue #28. The current
JSON source still accepts explicit sRGB and logical `px` dimensions only.

## Control metrics

`Style_Theme.control_metrics` is a typed setup API for ordinary control geometry. It keeps three concepts separate for Button, Checkbox, Slider, and Text Field: preferred height, minimum target height, and vertical content padding. A default height is resolved as the maximum of the preferred height, the target height, and measured text height plus twice the content padding. Text scale affects measured text; environment density scales the theme's logical metric values once.

An explicit `Layout_Style.height` takes precedence over theme preferences and the theme target minimum. This permits specialized compact controls, but can produce undersized hit targets; applications should use `min_height` when a minimum must remain enforced. An explicit `max_height` may cap the implicit target. The theme minimum also survives parent compression when height is omitted. Theme metric changes invalidate measurement only for the affected control family. Palette, material, and other paint-only changes do not.

The current JSON theme source does not author `control_metrics`; applications can configure them through the typed `Style_Theme` setup API. This is an experimental #109 surface pending the authoring and dogfood decision.
