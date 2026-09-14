# SDL3 / SDL_GPU boundary

The retained runtime does not import SDL types. The native adapter is expected
to map the following lifecycle to the SDL3 vendor package:

1. initialize SDL video and create a window;
2. claim the window for an SDL_GPU device and allow three frames in flight;
3. acquire a command buffer and swapchain texture for a built display list;
4. render each retained display command as a solid-color rectangle using a
   1x1 offscreen GPU texture and `SDL_BlitGPUTexture`;
5. acquire the submission fence and associate the temporary texture referenced by
   that submission;
6. only destroy retired resources after the fence is observed complete;
7. release the command buffer/pass/window/device in SDL's required order.

`runtime.GPU_Backend` is the headless lifetime model used by tests. It rejects
submission of a command buffer that is not open and makes deferred retirement
observable. The native executable runs six real swapchain/render-pass frames,
keeps three submissions in flight, and retires six concrete offscreen textures
only after their fences complete. It is still a rectangle compositor: shader
pipelines, glyph-atlas upload and visual screenshot comparison are not yet
claimed.

SDL command buffers are frame-scoped. Alicorn must never retain one in a node
or use it after `gpu_submit` returns. Nodes retain display data and resource
handles, not submitted command buffers.
