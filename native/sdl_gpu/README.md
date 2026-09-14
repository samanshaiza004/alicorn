# SDL3 / SDL_GPU boundary

The retained runtime does not import SDL types. The native adapter maps the
following lifecycle to the SDL3 vendor package:

1. initialize SDL video and create a high-pixel-density window;
2. claim the window for an SDL_GPU device and configure three frames in flight;
3. acquire a command buffer and swapchain texture for the retained display list;
4. convert logical display-command bounds to physical swapchain pixels;
5. render each retained command as a solid-color rectangle using a 1x1
   offscreen GPU texture and `SDL_BlitGPUTexture`;
6. associate the temporary texture with the submission fence and release it only
   after a blocking fence wait confirms completion;
7. release the command buffer/pass/window/device in SDL's required order.

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

The compositor is still rectangle-based: shader pipelines, glyph-atlas upload,
and visual screenshot comparison are not claimed. Build and run it from a
normal macOS GUI login session with:

```sh
ALICORN_ODIN=/path/to/odin ./tools/native_sdl_gpu.sh
```
