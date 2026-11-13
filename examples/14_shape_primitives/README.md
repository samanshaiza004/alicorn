# Shape Primitives

Run from the repository root:

```sh
./tools/run_example.sh 14_shape_primitives
```

The example builds three kinds of semantic surface geometry: filled circles,
an open circular arc for a meter, and an open cubic Bezier for a signal cable.
The Gain control uses `button_begin(presentation=.Custom,
pointer_hit_shape=.Circle)`, so Alicorn continues to own Button focus,
keyboard activation, accessibility identity, and interaction while the
component owns its visible concentric surfaces.

The curve coordinates are normalized to their retained surface bounds. SDL
lowers these shapes into the existing solid batch with a 16–96 segment cap and
a transparent subpixel fringe. Ordinary rectangles stay on their existing
six-vertex path. The opt-in circle hit target changes pointer targeting only;
layout, keyboard focus, and accessibility bounds remain rectangular.
