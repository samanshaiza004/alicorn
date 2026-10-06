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
  its byte budget. Button, Text Field, Scrollbar, and Semantic Surface results
  share exact dependency-domain snapshots and semantic input signatures.
  Scope changes advance only affected nodes; cache hits reuse the resolved
  payload and its provenance. Retirement and runtime destruction release the
  corresponding sidecar storage.
- Button, Text Field, and Scrollbar recipes depend on Paint. Semantic Surface
  resolution depends on Paint for its role color and Material for its shape,
  material, optical height, and group. Theme registrations and material
  registrations are immutable; recipe/state/theme identity is part of the
  computed-style signature, and semantic-surface description changes are
  hashed into its signature and advance their respective domains.
- Theme and accent changes are Paint-only today because built-in recipes consume
  color roles only. No theme length token currently drives layout metrics,
  typography, or material selection. Text scale still advances Metrics and
  Typography for its scoped subtree, while color-only recipe caches remain
  valid. Optional authored token names, immediate alias edges, and qualified
  extension-role names are copied into registered themes for inspector output;
  source spans and parser structures remain compiler-only. These names are
  diagnostic metadata, not runtime lookup keys.

## Built-in control recipes

The built-in recipe families describe semantic visual parts; layout and input
geometry remain with their existing control APIs. `Button_Recipe_Set` supplies
explicit button variants, `Text_Field_Recipe` supplies the field surface,
text, border, selection, caret, and independent focus treatment, and
`Scrollbar_Recipe` supplies the track, thumb, and corner. Hover/press color
transforms compose in a fixed order and do not replace the separate focus
overlay.

Themes can override these recipes before registration:

```odin
theme := alicorn.DEFAULT_STYLE_THEME
theme.text_field_recipe.focused_border_role = .Accent
theme.scrollbar_recipe.thumb_role = .Muted_Text
theme_id := alicorn.style_theme_register(&runtime, theme)
```

Recipes contain semantic color roles and state transforms, not padding,
thickness, or scroll geometry. The current JSON token frontend compiles colors
and lengths; it does not yet encode control recipes, so its runtime adapter
inherits the built-in recipes unless the application overrides them in Odin.

## Semantic surface composition

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
