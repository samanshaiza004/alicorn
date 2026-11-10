# Unicode font fallback

## Current prototype: face registry foundation

The first prototype stage adds Runtime-owned font-file and face identities.
`font_file_load_bytes` copies one SFNT/TTC backing file into the Runtime and
deduplicates identical bytes. `font_face_load` parses a requested collection
index through Runa and returns a `Font_Face_ID` that remains stable until the
Runtime is destroyed. The parsed `runa.Font` records have stable heap addresses,
which is required because Runa's shaping cache uses the font pointer as part of
its key. Glyph raster cache entries also include the resolved face ID.

Additional registry storage is bounded to 64 MiB, 64 unique files, and 32
registered faces per Runtime. Collection files are retained until Runtime
destruction so parsed table slices cannot outlive their bytes. These limits
are initial safety bounds for the prototype, not a platform font-discovery
policy.

This stage does not add the registered faces to text shaping. Existing
primary-font and single-fallback behavior remains unchanged. The next stage
must add grapheme-aware candidate selection and script/style-compatible shaping
runs before platform fallback providers can use this registry. In particular,
emoji ZWJ sequences, variation selectors, keycaps, modifiers, and regional
indicator pairs must not be split by per-code-point face selection.

## Remaining release gates

1. Add cluster-aware selection while keeping adjacent compatible script runs
   together; test the supported emoji sequence cases and Arabic shaping.
2. Add a Windows DirectWrite resolver that returns face descriptors and mapped
   ranges, with asynchronous/coalesced loading and negative-result caching.
3. Verify color glyph compositing and support boundaries. Runa's current color
   path must not be treated as support for Apple `sbix` or Linux `CBDT/CBLC`.
   Until those formats are implemented and tested, macOS/Linux color emoji
   remain incomplete even when native font discovery finds a matching face.
4. Add CoreText and Fontconfig providers, preferred Han language selection,
   detached-window coverage, and platform-native visual/editing validation.
5. Measure fallback resolution and ensure adding a face reshapes only retained
   text that had unresolved glyphs; Latin-only cached text must avoid fallback
   discovery work.

Scratchpad remains responsible for its editor font preference. Alicorn owns
font-file and face lifetimes, resolution, shaped face identity, and raster
resources. Runa owns parsing, shaping, glyph metrics, and rasterization.
