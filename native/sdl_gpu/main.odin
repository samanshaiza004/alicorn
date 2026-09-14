package main

// Native SDL3/SDL_GPU proof path. It renders Alicorn's retained display list
// as solid rectangles using a 1x1 offscreen texture and GPU blits. This keeps
// the first native compositor proof shader-free while still exercising real
// swapchain acquisition, render passes, composition and asynchronous resource
// retirement.
import "core:fmt"
import "core:os"
import "vendor:sdl3"
import alicorn "../../runtime"

Native_In_Flight :: struct {
	fence:   ^sdl3.GPUFence,
	texture: ^sdl3.GPUTexture,
}

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

render_native_ui :: proc(rt: ^alicorn.Runtime, frame: u64) {
	alicorn.invalidate_root(rt, "native frame")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin(&ui, .Root, label="native-root", style=alicorn.Layout_Style{.Column, -1, -1, 0, -1, 0, -1, 0, 12, 8, .Stretch, true})
	alicorn.text(&ui, "Alicorn retained display list", style=alicorn.Layout_Style{.Column, -1, 32, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
	alicorn.button(&ui, "GPU frame", style=alicorn.Layout_Style{.Column, 180, 32, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
	alicorn.custom_surface(&ui, "animated-surface", frame, alicorn.Rect{0, 0, 280, 120}, 560, 240, 2, style_source())
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
}

style_source :: proc() -> alicorn.Source_Site {
	return alicorn.caller_site("custom_surface")
}

make_color_target :: proc(texture: ^sdl3.GPUTexture, color: sdl3.FColor, cycle: bool) -> sdl3.GPUColorTargetInfo {
	return sdl3.GPUColorTargetInfo{
		texture = texture,
		clear_color = color,
		load_op = .CLEAR,
		store_op = .STORE,
		cycle = cycle,
	}
}

draw_display_list :: proc(command: ^sdl3.GPUCommandBuffer, swapchain: ^sdl3.GPUTexture, swap_w, swap_h: sdl3.Uint32, temporary: ^sdl3.GPUTexture, display: []alicorn.Display_Command) -> bool {
	// Establish a known swapchain image before applying retained commands.
	background := make_color_target(swapchain, sdl3.FColor{0.035, 0.045, 0.065, 1}, false)
	pass := sdl3.BeginGPURenderPass(command, &background, 1, nil)
	if pass == nil { return false }
	sdl3.EndGPURenderPass(pass)

	index: int = 0
	for draw in display {
		x0 := int(draw.bounds.x)
		y0 := int(draw.bounds.y)
		x1 := int(draw.bounds.x + draw.bounds.w)
		y1 := int(draw.bounds.y + draw.bounds.h)
		if x0 < 0 { x0 = 0 }
		if y0 < 0 { y0 = 0 }
		if x1 > int(swap_w) { x1 = int(swap_w) }
		if y1 > int(swap_h) { y1 = int(swap_h) }
		if x1 <= x0 || y1 <= y0 { continue }

		color := sdl3.FColor{draw.color.r, draw.color.g, draw.color.b, draw.color.a}
		target := make_color_target(temporary, color, index > 0)
		offscreen_pass := sdl3.BeginGPURenderPass(command, &target, 1, nil)
		if offscreen_pass == nil { return false }
		sdl3.EndGPURenderPass(offscreen_pass)

		blit := sdl3.GPUBlitInfo{
			source = sdl3.GPUBlitRegion{texture=temporary, w=1, h=1},
			destination = sdl3.GPUBlitRegion{texture=swapchain, x=sdl3.Uint32(x0), y=sdl3.Uint32(y0), w=sdl3.Uint32(x1-x0), h=sdl3.Uint32(y1-y0)},
			load_op = .LOAD,
			flip_mode = .NONE,
			filter = .NEAREST,
			cycle = index > 0,
		}
		sdl3.BlitGPUTexture(command, blit)
		index += 1
	}
	return true
}

retire_completed :: proc(device: ^sdl3.GPUDevice, in_flight: ^[dynamic]Native_In_Flight) -> int {
	retired: int = 0
	write: int = 0
	for entry in in_flight {
		if sdl3.QueryGPUFence(device, entry.fence) {
			sdl3.ReleaseGPUTexture(device, entry.texture)
			sdl3.ReleaseGPUFence(device, entry.fence)
			retired += 1
		} else {
			in_flight[write] = entry
			write += 1
		}
	}
	for len(in_flight) > write { pop(in_flight) }
	return retired
}

main :: proc() {
	if !sdl3.Init(sdl3.INIT_VIDEO) {
		fmt.println("SDL_Init failed:", sdl3.GetError())
		os.exit(1)
	}
	defer sdl3.Quit()

	window := sdl3.CreateWindow("Alicorn SDL_GPU proof", 640, 480, sdl3.WindowFlags{.HIDDEN, .RESIZABLE})
	if window == nil {
		fmt.println("SDL_CreateWindow failed:", sdl3.GetError())
		os.exit(1)
	}
	defer sdl3.DestroyWindow(window)

	formats := sdl3.GPUShaderFormat{.SPIRV, .DXIL, .MSL}
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
	if !sdl3.SetGPUAllowedFramesInFlight(device, 3) {
		fmt.println("SDL_SetGPUAllowedFramesInFlight failed:", sdl3.GetError())
		return
	}

	event: sdl3.Event
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 640, 480})
	in_flight := make([dynamic]Native_In_Flight, 0, 3)
	defer delete(in_flight)
	quit_requested := false
	submitted: int = 0
	retired: int = 0
	for frame := 0; frame < 6; frame += 1 {
		for sdl3.PollEvent(&event) {
			if event.type == .QUIT || event.type == .WINDOW_CLOSE_REQUESTED { quit_requested = true }
			if pointer, ok := pointer_from_sdl(event); ok { alicorn.process_pointer(&rt, pointer) }
			if event.type == .WINDOW_RESIZED || event.type == .WINDOW_PIXEL_SIZE_CHANGED {
				rt.viewport.w = f32(event.window.data1)
				rt.viewport.h = f32(event.window.data2)
				alicorn.invalidate_root(&rt, "SDL window size changed")
			}
		}
		if quit_requested { break }
		render_native_ui(&rt, u64(frame))

		command := sdl3.AcquireGPUCommandBuffer(device)
		if command == nil { fmt.println("SDL_AcquireGPUCommandBuffer failed:", sdl3.GetError()); return }
		swapchain: ^sdl3.GPUTexture
		swap_w, swap_h: sdl3.Uint32
		if !sdl3.AcquireGPUSwapchainTexture(command, window, &swapchain, &swap_w, &swap_h) {
			_ = sdl3.CancelGPUCommandBuffer(command)
			continue
		}
		if swapchain == nil || swap_w == 0 || swap_h == 0 {
			_ = sdl3.CancelGPUCommandBuffer(command)
			continue
		}
		temporary := sdl3.CreateGPUTexture(device, sdl3.GPUTextureCreateInfo{
			type = .D2,
			format = .R8G8B8A8_UNORM,
			usage = sdl3.GPUTextureUsageFlags{.SAMPLER, .COLOR_TARGET},
			width = 1,
			height = 1,
			layer_count_or_depth = 1,
			num_levels = 1,
			sample_count = ._1,
		})
		if temporary == nil {
			_ = sdl3.CancelGPUCommandBuffer(command)
			fmt.println("SDL_CreateGPUTexture failed:", sdl3.GetError())
			return
		}
		if !draw_display_list(command, swapchain, swap_w, swap_h, temporary, rt.display[:]) {
			sdl3.ReleaseGPUTexture(device, temporary)
			_ = sdl3.CancelGPUCommandBuffer(command)
			fmt.println("Alicorn display-list pass failed:", sdl3.GetError())
			return
		}
		fence := sdl3.SubmitGPUCommandBufferAndAcquireFence(command)
		if fence == nil {
			sdl3.ReleaseGPUTexture(device, temporary)
			fmt.println("SDL_SubmitGPUCommandBufferAndAcquireFence failed:", sdl3.GetError())
			return
		}
		append(&in_flight, Native_In_Flight{fence, temporary})
		submitted += 1
		rt.stats.gpu_submits += 1
		retired += retire_completed(device, &in_flight)
		if len(in_flight) >= 3 {
			old := in_flight[0]
			if !sdl3.WaitForGPUFences(device, true, &old.fence, 1) {
				fmt.println("SDL_WaitForGPUFences failed:", sdl3.GetError())
				return
			}
			retired += retire_completed(device, &in_flight)
		}
	}
	if len(in_flight) > 0 {
		_ = sdl3.WaitForGPUIdle(device)
		for entry in in_flight {
			sdl3.ReleaseGPUTexture(device, entry.texture)
			sdl3.ReleaseGPUFence(device, entry.fence)
			retired += 1
		}
		clear(&in_flight)
	}
	fmt.println("SDL3/SDL_GPU retained compositor: PASS; submitted=", submitted, "retired=", retired, "display_commands=", len(rt.display), "frames_in_flight=3")
	alicorn.destroy_runtime(&rt)
}
