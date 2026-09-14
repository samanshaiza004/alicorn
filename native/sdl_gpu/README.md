# SDL3 / SDL_GPU boundary

The retained runtime does not import SDL types. The native adapter maps the
following lifecycle to the SDL3 vendor package:

1. initialize SDL video and create a high-pixel-density window;
2. claim the window for an SDL_GPU device and configure three frames in flight;
3. acquire a command buffer and swapchain texture for the retained display list;
4. convert logical display-command bounds to physical swapchain pixels;
5. render retained rectangles with the existing 1x1 offscreen texture and
   `SDL_BlitGPUTexture`;
6. render retained Runa glyph runs through a persistent RGBA GPU atlas,
   staged dirty-region uploads, a persistent vertex buffer and an SDL_GPU
   text pipeline;
7. associate the temporary texture with the submission fence and release it only
   after a blocking fence wait confirms completion;
8. release the command buffer/pass/window/device in SDL's required order.

`Window_Metrics` keeps logical window size, physical drawable size, pixel
density, and display scale distinct. Layout, pointer events, and the SDL text
input rectangle remain in logical window coordinates. Only the compositor
converts logical rectangles to physical pixels. `WINDOW_RESIZED`,
`WINDOW_PIXEL_SIZE_CHANGED`/`WINDOW_METAL_VIEW_RESIZED`, and
`WINDOW_DISPLAY_SCALE_CHANGED` are handled as separate event classes.

On Darwin the fixture requests and verifies the `metal` SDL_GPU driver. It
submits a three-frame burst, then runs 300 programmatic resize iterations
through the current retained compositor. On the tested SDL 3.4.14 Metal
combination, resizing while the SDL window claim remains active can leave the
swapchain without a drawable even after the old fences are complete. The
validation boundary therefore drains the GPU, recreates only the SDL window
claim, and then continues; the Alicorn runtime and GPU device remain alive.
This is isolated validation behavior, not a cross-platform runtime policy.

SDL command buffers are frame-scoped. Alicorn must never retain one in a node
or use it after submission. Nodes retain display data and resource handles, not
submitted command buffers.

The fixture records `SDL_QueryGPUFence` before and after each blocking wait.
The tested Metal backend returned false after waits for real render/blit
commands, so the blocking wait—not the query result—is used for known-oldest
resource retirement. The anomaly is reported rather than treated as proof of
post-wait query correctness.

The text path currently proves monochrome alpha glyphs and keeps color glyph
pages distinct at the CPU identity boundary; the native fixture does not yet
claim screenshot comparison, caret/selection geometry, IME, or a production
font fallback policy. Build and run it from a normal GUI login session with:

```sh
ALICORN_ODIN=/path/to/odin ./tools/native_sdl_gpu.sh
```
