package alicorn_sdl_gpu

// Native SDL3/SDL_GPU host entry point. Subsystems are kept in neighboring
// same-package files so the host wiring stays easy to follow.
import "core:fmt"
import "core:os"
import "core:c"
import "core:strconv"
import "core:strings"
import alicorn "../../runtime"
import "vendor:sdl3"

// Run owns the complete SDL3/SDL_GPU application shell.
// Applications supply their state and callbacks.
Run :: proc(application: Application, smoke := false) {
	input_debug := false
	validation_timeout_seconds := 0
	for argument in os.args {
		if argument == "--input-debug" { input_debug = true }
		prefix := "--idle-validation-seconds="
		legacy_prefix := "--idle-proof-seconds="
		if strings.has_prefix(argument, legacy_prefix) { prefix = legacy_prefix }
		if strings.has_prefix(argument, prefix) {
			parsed, ok := strconv.parse_int(argument[len(prefix):])
			if ok && parsed > 0 { validation_timeout_seconds = int(parsed) }
		}
	}
	if !sdl3.SetHint(sdl3.HINT_IME_IMPLEMENTED_UI, "composition") {
		fail("SDL_IME_IMPLEMENTED_UI hint could not be set")
	}
	configure_platform_activation()
	if !sdl3.Init(sdl3.INIT_VIDEO) { fail("SDL_Init failed") }
	defer sdl3.Quit()
	linked_sdl_version := sdl3.GetVersion()
	fmt.println(
		"sdl3_version",
		sdl3.VERSIONNUM_MAJOR(linked_sdl_version),
		sdl3.VERSIONNUM_MINOR(linked_sdl_version),
		sdl3.VERSIONNUM_MICRO(linked_sdl_version),
	)
	when ODIN_OS == .Darwin {
		if linked_sdl_version != sdl3.VERSIONNUM(3, 4, 16) {
			fail("macOS requires SDL3 3.4.16")
		}
	}
	title := application.title
	if title == "" { title = "Alicorn application" }
	width := application.width
	if width <= 0 { width = 960 }
	height := application.height
	if height <= 0 { height = 640 }
	title_cstring, title_err := strings.clone_to_cstring(title, context.temp_allocator)
	if title_err != nil { fail("application title allocation failed") }
	window := sdl3.CreateWindow(title_cstring, c.int(width), c.int(height), sdl3.WindowFlags{.RESIZABLE, .HIGH_PIXEL_DENSITY})
	if window == nil { fail("SDL_CreateWindow failed") }
	defer sdl3.DestroyWindow(window)
	menu_application := application
	native_menu := Native_Menu_Runtime{window=window, application=&menu_application}
	defer native_menu_destroy(&native_menu)
	if !native_menu_prepare(&native_menu) {
		fail("native application menu or integrated title bar setup failed")
	}
	if !sdl3.RaiseWindow(window) { fail("SDL_RaiseWindow failed") }
	if input_debug {
		fmt.println("sdl_input_debug", "window_flags", sdl3.GetWindowFlags(window))
	}
	metrics: Window_Metrics
	if !read_window_metrics(window, &metrics, native_menu.content_inset_top) { fail("initial application window metrics unavailable") }
	formats := sdl3.GPUShaderFormat{.SPIRV, .DXIL, .MSL}
	gpu_driver_name: cstring = nil
	when ODIN_OS == .Darwin { gpu_driver_name = "metal" }
	device := sdl3.CreateGPUDevice(formats, false, gpu_driver_name)
	if device == nil { fail("SDL_CreateGPUDevice failed") }
	defer sdl3.DestroyGPUDevice(device)
	selected_driver := sdl3.GetGPUDeviceDriver(device)
	fmt.println("gpu_driver_requested", gpu_driver_name, "gpu_driver_selected", selected_driver)
	when ODIN_OS == .Darwin {
		if selected_driver == nil || string(selected_driver) != "metal" {
			fail("macOS SDL_GPU did not select the requested Metal driver")
		}
	}
		if !sdl3.ClaimWindowForGPUDevice(device, window) { fail("SDL_ClaimWindowForGPUDevice failed") }
	defer sdl3.ReleaseWindowFromGPUDevice(device, window)
	// The reusable desktop host favors interaction latency. The foundation
	// stress fixture below intentionally uses three frames; ordinary apps use
	// two unless they explicitly opt into throughput-oriented stress behavior.
	if !sdl3.SetGPUAllowedFramesInFlight(device, 2) { fail("SDL_SetGPUAllowedFramesInFlight failed") }
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, f32(metrics.logical_width), f32(metrics.logical_height)})
	defer alicorn.destroy_runtime(&rt)
	if !native_load_default_fonts(&rt) { fail("application bundled Runa fonts could not be initialized") }
	text_renderer, text_ok := native_text_make(device, sdl3.GetGPUSwapchainTextureFormat(device, window), &rt)
	if !text_ok { fail("application GPU text pipeline initialization failed") }
	defer native_text_destroy(&text_renderer)
	when ODIN_OS == .Windows {
		if !native_menu_prepare_gpu(&native_menu, &rt, &text_renderer) {
			fail("integrated title bar GPU text initialization failed")
		}
	}
	surface_renderer, surface_ok := native_surface_make(device, sdl3.GetGPUSwapchainTextureFormat(device, window), &rt)
	if !surface_ok { fail("application GPU surface pipeline initialization failed") }
	defer native_surface_destroy(&surface_renderer)
	solid_renderer, solid_ok := native_solid_make(device, sdl3.GetGPUSwapchainTextureFormat(device, window), &rt)
	if !solid_ok { fail("application solid rectangle pipeline initialization failed") }
	defer native_solid_destroy(&solid_renderer)
	// Metal/text/surface setup can briefly return focus to the launching
	// terminal on macOS. Raise again only after the application is ready so a
	// visible-but-inert window is not handed to the user.
	if !sdl3.RaiseWindow(window) { fail("SDL_RaiseWindow failed after host initialization") }
	run_application_loop(window, device, &rt, &text_renderer, &surface_renderer, &solid_renderer, &metrics, application, smoke, input_debug, string(selected_driver), validation_timeout_seconds=validation_timeout_seconds, native_menu=&native_menu)
}
