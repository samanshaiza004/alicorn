# SDL3 / SDL_GPU boundary

The retained runtime does not import SDL types. The native adapter is expected
to map the following lifecycle to the SDL3 vendor package:

1. initialize SDL video and create a window;
2. claim the window for an SDL_GPU device;
3. acquire a command buffer and swapchain texture for a built display list;
4. set scissor from retained clip rectangles and submit one render pass;
5. acquire the submission fence and associate it with resources referenced by
   that submission;
6. only destroy retired resources after the fence is observed complete;
7. release the command buffer/pass/window/device in SDL's required order.

`runtime.GPU_Backend` is the headless lifetime model used by tests. It rejects
submission of a command buffer that is not open and makes deferred retirement
observable. `vendor:sdl3` links to `system:SDL3` on Unix-like hosts. On macOS,
the validation executable therefore needs SDL3 available through the normal
system linker search path, for example Homebrew's `sdl3` formula; SDL3 is not
made an Alicorn runtime dependency.

Build and run the native validation executable from a normal macOS GUI login
session with:

```sh
ALICORN_ODIN=/path/to/odin ./tools/native_sdl_gpu.sh
```

The fixture requests the `metal` SDL_GPU driver only on Darwin and fails if a
different driver is selected. It creates a high-pixel-density window and
reports `SDL_GetWindowSize`, `SDL_GetWindowSizeInPixels`,
`SDL_GetWindowPixelDensity`, and `SDL_GetWindowDisplayScale` separately. It
keeps layout, pointer, and text-input coordinates in logical window units;
physical pixels are a compositor concern. `WINDOW_RESIZED`,
`WINDOW_PIXEL_SIZE_CHANGED`/`WINDOW_METAL_VIEW_RESIZED`, and
`WINDOW_DISPLAY_SCALE_CHANGED` are handled as distinct events.

All SDL calls in this fixture run on the main thread, including video/window
creation, event polling, text-input activation, and GPU submission. The
fixture deliberately uses empty command buffers, so a successful run proves
platform initialization, Metal selection, window claim, command-buffer/fence
lifecycle, resize handling, and shutdown—not retained display-list rendering.

SDL command buffers are frame-scoped. Alicorn must never retain one in a node
or use it after `gpu_submit` returns. Nodes retain display data and resource
handles, not submitted command buffers.
