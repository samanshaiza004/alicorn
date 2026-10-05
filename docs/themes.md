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
- The runtime retains resolved button style per node with the theme and
  environment signature that produced it. This is invalidation state, not a
  global style memoization table.

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
```

This is intentionally a narrow v0.2 foundation rather than a general cascade:
there are no selectors, arbitrary properties, inheritance filesystem loader,
theme hot reload, or global cross-node memoization.
