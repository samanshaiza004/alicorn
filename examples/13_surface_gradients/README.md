# Surface Gradients

Run it from the repository root:

```sh
./tools/run_example.sh 13_surface_gradients
```

This native example demonstrates three static, semantic surface gradients:
inactive and active tab fills on the horizontal axis, and a Pulse meter fill on
the vertical axis. Both stops are ordinary namespaced extension-color roles
bound to theme tokens. The surfaces retain their rounded geometry and clipping;
no gradient mesh, texture, render target, shader, or extra render pass is
created.

Try changing the stop colors in `initialize` or the axes passed to
`surface_gradient_to`. Theme colors use Alicorn's linear-sRGB channel values.
Gradient stop alpha must match because the existing renderer interpolates
straight-alpha vertex colors. Increased Contrast uses the first stop as a solid
fill; Reduce Transparency keeps the gradient and makes both stops opaque.
