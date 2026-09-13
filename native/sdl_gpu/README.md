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
observable. `vendor:sdl3` is available in the installed Odin SDK at the time of
this build, including `SDL3.lib`, but no native window/driver run is asserted by
the foundation report until the smoke executable is executed on that machine.

SDL command buffers are frame-scoped. Alicorn must never retain one in a node
or use it after `gpu_submit` returns. Nodes retain display data and resource
handles, not submitted command buffers.

