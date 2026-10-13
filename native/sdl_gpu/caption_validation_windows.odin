#+build windows

package alicorn_sdl_gpu

import "core:fmt"
import "core:os"
import win "core:sys/windows"
import alicorn "../../runtime"
import "vendor:sdl3"

// Exercise the production paint path using synthetic DWM measurements. This
// checks GPU pixels; it does not simulate native Snap or monitor transitions.
native_caption_capture_case :: proc(
	device: ^sdl3.GPUDevice, text: ^Native_Text_Renderer,
	surface: ^Native_Surface_Renderer, solid: ^Native_Solid_Renderer,
	dpi: u32, density: f32, windows_11: bool, case_index: int,
) -> bool {
	scale := f32(dpi)/96
	width := i32(native_pixel_edge(560 if case_index != 8 else 200,scale))
	height := i32(native_pixel_edge(32,scale))
	edge := i32(native_pixel_edge(8,scale))
	menus := [2]Application_Menu{{label="File"},{label="Edit"}}
	app := Application{menus=menus[:],window_decorations=.Integrated_Title_Bar}
	menu := Native_Menu_Runtime{application=&app,
		chrome_appearance={defined=true,background={0.07,0.07,0.07,1},foreground={1,1,1,1}}}
	labels := [2]Win32_Menu_Label{{host_node=NATIVE_MENU_HOST_NODE_BASE+1},{host_node=NATIVE_MENU_HOST_NODE_BASE+2}}
	state := Win32_Menu_State{menu=&menu,allocator=context.allocator,dpi=dpi,pixels_per_unit=density,
		chrome_height_pixels=height,chrome_height=f32(height)/density,frame_enabled=true,
		maximized=case_index != 0,windows_11=windows_11,active=case_index != 6,
		caption_hovered=-1,caption_pressed=-1,hovered=-1,active_menu=-1,
		text_renderer=text,title_text="Alicorn Menu Fixture — long title",
		title=Win32_Menu_Label{host_node=NATIVE_MENU_HOST_NODE_BASE},labels=labels[:],
		ellipsis_host_node=NATIVE_MENU_HOST_NODE_BASE+4}
	if case_index == 2 { state.caption_hovered = 0 }
	if case_index == 3 { state.caption_hovered = 1 }
	if case_index == 4 || case_index == 5 { state.caption_hovered = 2 }
	if case_index == 5 { state.caption_pressed = 2 }
	if case_index == 7 { state.high_contrast = true; state.caption_hovered = 2 }
	menu.platform_data = rawptr(&state)
	defer win32_caption_destroy_masks(&state)
	raw := win.RECT{win.LONG(width-i32(native_pixel_edge(138,scale))-edge),-win.LONG(edge),win.LONG(width-edge),win.LONG(height-edge)}
	state.caption_controls = win32_caption_layout_controls(raw,true,width,height,dpi,state.maximized)
	if !win32_menu_refresh_text(&state,text.runtime) { return false }
	win32_menu_layout_label_bounds(&state)
	display := native_menu_overlay_commands(&menu,f32(width)/density,f32(height)/density,context.allocator)
	defer delete(display)
	names := [9]string{"restored","maximized","minimize-hover","restore-hover","close-hover","close-pressed","inactive","high-contrast","narrow"}
	path := fmt.tprintf("out/caption-fixtures/win%d-%d-dpi-density%d-%s.ppm",11 if windows_11 else 10,dpi,int(density),names[case_index])
	if !native_capture_display_ppm(device,text,surface,solid,display,sdl3.Uint32(width),sdl3.Uint32(height),density,density,path) { return false }
	bytes,err := os.read_entire_file(path,context.allocator)
	if err != nil { return false }
	defer delete(bytes)
	header := fmt.tprintf("P6\n%d %d\n255\n",width,height)
	if len(bytes) != len(header)+int(width)*int(height)*3 { return false }
	background,foreground := win32_menu_chrome_colors(&state)
	hover,_,pressed := win32_menu_feedback_colors(background,foreground)
	highlight,highlight_text := win32_menu_high_contrast_selection_colors()
	for control,index in state.caption_controls {
		back,ink := background,foreground
		if state.caption_hovered == index {
			back = hover
			if index == 2 && !state.high_contrast {
				back = win32_color_rgb(232,17,35)
				ink = win32_color_rgb(255,255,255)
				if state.caption_pressed == index { back = win32_color_mix(background,back,0.60) }
			} else if state.high_contrast { back,ink = highlight,highlight_text }
			else if state.caption_pressed == index { back = pressed }
		}
		icon := Win32_Caption_Icon.Minimize
		if index == 1 { icon = .Restore if state.maximized else .Maximize }
		if index == 2 { icon = .Close }
		mask := state.caption_masks[int(icon)]
		x0 := int(control.bounds.left)+(int(control.bounds.right-control.bounds.left)-mask.size)/2
		y0 := int(control.bounds.top)+(int(control.bounds.bottom-control.bounds.top)-mask.size)/2
		for y in int(control.bounds.top)..<int(control.bounds.bottom) {
			for x in int(control.bounds.left)..<int(control.bounds.right) {
				coverage: f32
				if x >= x0 && x < x0+mask.size && y >= y0 && y < y0+mask.size {
					coverage = f32(mask.pixels[(y-y0)*mask.size+x-x0])/255
				}
				expected := win32_color_mix(back,ink,coverage)
				channels := [3]f32{expected.r,expected.g,expected.b}
				for channel in 0..<3 {
					actual := bytes[len(header)+(y*int(width)+x)*3+channel]
					if abs(f32(actual)-channels[channel]*255) > 2 {
						fmt.println("caption_gpu_mismatch",path,"pixel",x,y,"channel",channel,"actual",actual,"expected",channels[channel]*255)
						return false
					}
				}
			}
		}
	}
	// Repeated painting at the same DPI must reuse masks and shaped host text.
	generation,builds,shapes := text.host_run_generation,state.caption_mask_builds,text.runtime.text_engine.shape_calls
	again := native_menu_overlay_commands(&menu,f32(width)/density,f32(height)/density,context.allocator)
	defer delete(again)
	return generation == text.host_run_generation && builds == state.caption_mask_builds && shapes == text.runtime.text_engine.shape_calls
}

native_caption_validate_window :: proc(
	device: ^sdl3.GPUDevice, text: ^Native_Text_Renderer,
	surface: ^Native_Surface_Renderer, solid: ^Native_Solid_Renderer,
) -> bool {
	window := sdl3.CreateWindow("Alicorn caption validation",640,360,{.HIDDEN,.RESIZABLE,.HIGH_PIXEL_DENSITY})
	if window == nil { return false }
	defer sdl3.DestroyWindow(window)
	menus := [2]Application_Menu{{label="File"},{label="Edit"}}
	app := Application{title="Alicorn caption validation",menus=menus[:],window_decorations=.Integrated_Title_Bar}
	menu := Native_Menu_Runtime{window=window,application=&app,runtime=text.runtime,
		chrome_appearance={defined=true,background={0.07,0.07,0.07,1},foreground={1,1,1,1}}}
	defer native_menu_destroy(&menu)
	if !native_menu_prepare(&menu) || !native_menu_prepare_gpu(&menu,text.runtime,text) { return false }
	if !sdl3.ClaimWindowForGPUDevice(device,window) { return false }
	defer sdl3.ReleaseWindowFromGPUDevice(device,window)
	state := cast(^Win32_Menu_State)menu.platform_data
	_ = win.ShowWindow(state.hwnd,win.SW_SHOWNOACTIVATE)
	sdl3.PumpEvents()
	commands := [3]win.WPARAM{win.WPARAM(win.SC_RESTORE),win.WPARAM(win.SC_MAXIMIZE),win.WPARAM(win.SC_RESTORE)}
	for command,index in commands {
		_ = win.SendMessageW(state.hwnd,win.WM_SYSCOMMAND,command,0)
		sdl3.PumpEvents()
		client: win.RECT
		if !win.GetClientRect(state.hwnd,&client) { return false }
		width,height := i32(client.right-client.left),i32(client.bottom-client.top)
		origin: win.POINT
		if !win.ClientToScreen(state.hwnd,&origin) || state.maximized != (index == 1) {
			fmt.println("caption_window_state_mismatch",index,state.maximized)
			return false
		}
		for control in state.caption_controls {
			x := origin.x+(control.bounds.left+control.bounds.right)/2
			y := origin.y+(control.bounds.top+control.bounds.bottom)/2
			packed := win.LPARAM(uintptr(u16(cast(i16)x)) | uintptr(u16(cast(i16)y))<<16)
			hit := win.SendMessageW(state.hwnd,win.WM_NCHITTEST,0,packed)
			if hit != control.hit_test { fmt.println("caption_native_hit_mismatch",x,y,hit,control.hit_test); return false }
		}
		if index == 1 {
			monitor := win.MonitorFromWindow(state.hwnd,.MONITOR_DEFAULTTONEAREST)
			info := win.MONITORINFO{cbSize=win.DWORD(size_of(win.MONITORINFO))}
			if !win.GetMonitorInfoW(monitor,&info) || origin.x != info.rcWork.left || origin.y != info.rcWork.top ||
				width != i32(info.rcWork.right-info.rcWork.left) || height != i32(info.rcWork.bottom-info.rcWork.top) { return false }
		}
		display := native_menu_overlay_commands(&menu,f32(width)/state.pixels_per_unit,f32(height)/state.pixels_per_unit,context.allocator)
		path := fmt.tprintf("out/caption-fixtures/native-%s-%d.ppm","maximized" if index == 1 else "restored",index)
		ok := native_capture_display_ppm(device,text,surface,solid,display,sdl3.Uint32(width),sdl3.Uint32(state.chrome_height_pixels),state.pixels_per_unit,state.pixels_per_unit,path)
		delete(display)
		if !ok { return false }
		fmt.println("caption_native_window","maximized",state.maximized,"dpi",state.dpi,"density",state.pixels_per_unit,
			"dwm_bounds_valid",state.caption_button_bounds_valid,"raw_bounds",state.caption_button_bounds,"controls",state.caption_controls)
	}
	return true
}

RunCaptionValidation :: proc() {
	if !sdl3.Init(sdl3.INIT_VIDEO) { fail("caption validation SDL init") }
	defer sdl3.Quit()
	device := sdl3.CreateGPUDevice({.DXIL},false,"direct3d12")
	if device == nil { fail("caption validation D3D12 device") }
	defer sdl3.DestroyGPUDevice(device)
	rt := alicorn.new_runtime(alicorn.Rect{0,0,1200,200})
	defer alicorn.destroy_runtime(&rt)
	if !native_load_default_fonts(&rt) { fail("caption validation fonts") }
	text,ok := native_text_make(device,.R8G8B8A8_UNORM,&rt)
	defer native_text_destroy(&text)
	if !ok { fail("caption validation text renderer") }
	surface,surface_ok := native_surface_make(device,.R8G8B8A8_UNORM,&rt)
	defer native_surface_destroy(&surface)
	if !surface_ok { fail("caption validation surface renderer") }
	solid,solid_ok := native_solid_make(device,.R8G8B8A8_UNORM,&rt)
	defer native_solid_destroy(&solid)
	if !solid_ok { fail("caption validation solid renderer") }
	dpis := [4]u32{96,120,144,192}
	versions := [2]bool{false,true}
	densities := [2]f32{1,2}
	count := 0
	for dpi in dpis { for windows_11 in versions { for density in densities { for case_index in 0..<9 {
		if !native_caption_capture_case(device,&text,&surface,&solid,dpi,density,windows_11,case_index) { fail("caption GPU pixels disagree with canonical geometry") }
		count += 1
	} } } }
	if !native_caption_validate_window(device,&text,&surface,&solid) { fail("caption native maximize/restore/hit-test validation") }
	fmt.println("caption_gpu_validation","driver",sdl3.GetGPUDeviceDriver(device),"captures",count,"dpi",dpis,"pixel_geometry",true)
}
