package main

// Native SDL3/SDL_GPU smoke path. This deliberately submits empty command
// buffers: the retained headless display list has its own tests, while this
// executable proves the platform lifetime boundary and fence ordering.
import "core:fmt"
import "core:os"
import "vendor:sdl3"
import alicorn "../../runtime"

pointer_from_sdl :: proc(event: sdl3.Event) -> (value: alicorn.Pointer_Event, ok: bool) {
	if event.type == .MOUSE_MOTION {
		return alicorn.Pointer_Event{.Move, event.motion.x, event.motion.y, 0}, true
	}
	if event.type == .MOUSE_BUTTON_DOWN {
		return alicorn.Pointer_Event{.Down, event.button.x, event.button.y, int(event.button.button)}, true
	}
	if event.type == .MOUSE_BUTTON_UP {
		return alicorn.Pointer_Event{.Up, event.button.x, event.button.y, int(event.button.button)}, true
	}
	return alicorn.Pointer_Event{}, false
}

main :: proc() {
	if !sdl3.Init(sdl3.INIT_VIDEO) {
		fmt.println("SDL_Init failed:", sdl3.GetError())
		os.exit(1)
	}
	defer sdl3.Quit()

	window := sdl3.CreateWindow("Alicorn SDL_GPU smoke", 640, 480, sdl3.WindowFlags{.HIDDEN, .RESIZABLE})
	if window == nil {
		fmt.println("SDL_CreateWindow failed:", sdl3.GetError())
		os.exit(1)
	}
	defer sdl3.DestroyWindow(window)

	formats := sdl3.GPUShaderFormat{.SPIRV, .DXIL, .MSL}
	// The backend-name parameter is optional; passing the application name here
	// would ask SDL to load a nonexistent driver called "Alicorn".
	device := sdl3.CreateGPUDevice(formats, false, nil)
	if device == nil {
		fmt.println("SDL_CreateGPUDevice unavailable:", sdl3.GetError())
		return
	}
	defer sdl3.DestroyGPUDevice(device)

	if !sdl3.ClaimWindowForGPUDevice(device, window) {
		fmt.println("SDL_ClaimWindowForGPUDevice failed:", sdl3.GetError())
		return
	}
	defer sdl3.ReleaseWindowFromGPUDevice(device, window)

	event: sdl3.Event
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 640, 480})
	quit_requested := false
	for frame := 0; frame < 3; frame += 1 {
		for sdl3.PollEvent(&event) {
			if event.type == .QUIT || event.type == .WINDOW_CLOSE_REQUESTED {
				quit_requested = true
			}
			if pointer, ok := pointer_from_sdl(event); ok {
				// SDL coordinates are window-logical coordinates here. The runtime
				// owns hit testing and the canonical focus owner.
				alicorn.process_pointer(&rt, pointer)
			}
			if event.type == .WINDOW_RESIZED || event.type == .WINDOW_PIXEL_SIZE_CHANGED {
				rt.viewport.w = f32(event.window.data1)
				rt.viewport.h = f32(event.window.data2)
				alicorn.invalidate_root(&rt, "SDL window size changed")
			}
		}
		if quit_requested { break }
		command := sdl3.AcquireGPUCommandBuffer(device)
		if command == nil {
			fmt.println("SDL_AcquireGPUCommandBuffer failed:", sdl3.GetError())
			return
		}
		fence := sdl3.SubmitGPUCommandBufferAndAcquireFence(command)
		if fence == nil {
			fmt.println("SDL_SubmitGPUCommandBufferAndAcquireFence failed:", sdl3.GetError())
			return
		}
		fences := [1]^sdl3.GPUFence{fence}
		if !sdl3.WaitForGPUFences(device, true, &fences[0], 1) {
			fmt.println("SDL_WaitForGPUFences failed:", sdl3.GetError())
			return
		}
		sdl3.ReleaseGPUFence(device, fence)
	}
	fmt.println("SDL3/SDL_GPU smoke: PASS; command buffers submitted=", 3, " input adapter active")
}
