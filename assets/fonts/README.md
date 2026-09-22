# Bundled fonts

Alicorn's native SDL/GPU host embeds these variable TrueType fonts as its
default UI and monospace faces. The binaries are unmodified. Their `wght`
axes are selected through `Text_Style.font_weight` and are applied consistently
to shaping, intrinsic layout, and glyph rasterization.

Each family has its own OFL notice in this directory. Keep the corresponding
license file with its font if distributing the font separately.

## Atkinson Hyperlegible Next

- Source: <https://github.com/googlefonts/atkinson-hyperlegible-next>
- Upstream revision: `7925f50f649b3813257faf2f4c0b381011f434f1`
- File: `AtkinsonHyperlegibleNext-Variable.ttf` (upstream: `AtkinsonHyperlegibleNext[wght].ttf`)
- SHA-256: `5a455d1cfa099b601ab70751bb9673e8fe1854dc4500c80e1a220d0d75e31745`
- License: `OFL-Atkinson-Hyperlegible-Next.txt`

## Atkinson Hyperlegible Mono

- Source: <https://github.com/googlefonts/atkinson-hyperlegible-next-mono>
- Upstream revision: `154d50362016cc3e873eb21d242cd0772384c8f9`
- File: `AtkinsonHyperlegibleMono-Variable.ttf` (upstream: `AtkinsonHyperlegibleMono[wght].ttf`)
- SHA-256: `5ce8b1698d1ded7dff2178c1a3ad159470085a58ea239e8b2cb88f4fb4a6f646`
- License: `OFL-Atkinson-Hyperlegible-Mono.txt`

These families cover many Latin-based languages but not every writing system.
The SDL/GPU host may load an optional platform fallback face (for example,
Noto Sans JP on Windows). If any character in a shaped run is absent from its
bundled primary face and present in that fallback, Alicorn shapes the entire
run with the fallback face. This preserves face-correct glyph metrics, but is
not per-character mixed-font fallback; applications needing broader or
deterministic script coverage should provide their own font strategy.
