#+build windows

package alicorn_sdl_gpu

import "core:mem"
import win "core:sys/windows"
import alicorn "../../runtime"

// Caption metrics are physical pixels. Only paint output crosses into SDL's
// window coordinates, which need not have the same scale as Windows DIPs.
// Symbol-box/stroke conventions and restore occlusion follow Electron and
// Chromium. See third_party/windows_caption/LICENSE and the architecture note.
Win32_Caption_Icon :: enum { Minimize, Maximize, Restore, Close }
Win32_Caption_Mask :: struct { size: int, pixels: []u8 }

win32_caption_windows_11 :: proc() -> bool {
	version := win.OSVERSIONINFOEXW{dwOSVersionInfoSize=u32(size_of(win.OSVERSIONINFOEXW))}
	return win.RtlGetVersion(&version) >= 0 && version.dwMajorVersion >= 10 && version.dwBuildNumber >= 22000
}

win32_caption_bounds_to_client_pixels :: proc(
	window_bounds, window_rect: win.RECT,
	client_origin_x, client_origin_y: i32,
) -> win.RECT {
	dx := window_rect.left-win.LONG(client_origin_x)
	dy := window_rect.top-win.LONG(client_origin_y)
	return win.RECT{window_bounds.left+dx, window_bounds.top+dy, window_bounds.right+dx, window_bounds.bottom+dy}
}

win32_caption_layout_controls :: proc(
	dwm_bounds: win.RECT, dwm_valid: bool,
	client_width, chrome_height: i32, dpi: u32, maximized: bool,
) -> [3]Win32_Caption_Control {
	if client_width <= 0 || chrome_height <= 0 { return {} }
	cluster := dwm_bounds
	if !dwm_valid || cluster.right <= cluster.left || cluster.bottom <= cluster.top ||
		cluster.left < 0 || cluster.left >= win.LONG(client_width) {
		button_width := i32(native_pixel_edge(46, f32(dpi if dpi != 0 else 96)/96))
		cluster.right = win.LONG(client_width-1 if !maximized else client_width)
		cluster.left = max(cluster.right-win.LONG(3*button_width), 0)
	}
	cluster.right = min(cluster.right, win.LONG(client_width))
	// DWM's outer-frame Y may be negative after maximize. It describes the
	// native cluster, not the visible custom band. All controls share that band.
	cluster.top = 0 if maximized else 1 // one physical resize pixel when restored
	cluster.bottom = win.LONG(chrome_height)
	rects := win32_caption_control_rects(cluster, true)
	if maximized { rects[2].right = win.LONG(client_width) }
	return [3]Win32_Caption_Control{
		{rects[0], win.LRESULT(win.HTMINBUTTON)},
		{rects[1], win.LRESULT(win.HTMAXBUTTON)},
		{rects[2], win.LRESULT(win.HTCLOSE)},
	}
}

win32_chrome_rect_to_window :: proc(rect: win.RECT, pixels_per_unit: f32) -> alicorn.Rect {
	scale := 1/(pixels_per_unit if pixels_per_unit > 0 else 1)
	return alicorn.Rect{f32(rect.left)*scale, f32(rect.top)*scale,
		f32(max(rect.right-rect.left, 0))*scale, f32(max(rect.bottom-rect.top, 0))*scale}
}

win32_caption_inside_round_rect :: proc(x, y, left, top, width, height, radius: f32) -> bool {
	if width <= 0 || height <= 0 || x < left || y < top || x >= left+width || y >= top+height { return false }
	r := min(max(radius, 0), min(width, height)/2)
	if r == 0 { return true }
	dx := max(max(left+r-x, x-(left+width-r)), 0)
	dy := max(max(top+r-y, y-(top+height-r)), 0)
	return dx*dx+dy*dy <= r*r
}

win32_caption_on_outline :: proc(x, y, left, top, width, height, radius, stroke: f32) -> bool {
	return win32_caption_inside_round_rect(x, y, left, top, width, height, radius) &&
		!win32_caption_inside_round_rect(x, y, left+stroke, top+stroke, width-2*stroke, height-2*stroke, max(radius-stroke, 0))
}

win32_caption_symbol_sample :: proc(icon: Win32_Caption_Icon, x, y, size, stroke, radius, separation: f32) -> bool {
	switch icon {
	case .Minimize:
		top := f32(int(size)/2-int(stroke)/2)
		return y >= top && y < top+stroke
	case .Maximize:
		return win32_caption_on_outline(x, y, 0, 0, size, size, radius, stroke)
	case .Restore:
		extent := size-separation
		front := win32_caption_on_outline(x, y, 0, separation, extent, extent, radius, stroke)
		// The front window occludes the rear window, including its inner edges.
		back := win32_caption_on_outline(x, y, separation, 0, extent, extent, radius, stroke) &&
			!win32_caption_inside_round_rect(x, y, 0, separation, extent, extent, radius)
		return front || back
	case .Close:
		half_width := stroke*0.70710678118
		return abs(x-y) <= half_width || abs(x+y-size) <= half_width
	}
	return false
}

win32_caption_build_mask :: proc(icon: Win32_Caption_Icon, dpi: u32, windows_11: bool, allocator: mem.Allocator) -> Win32_Caption_Mask {
	scale := f32(dpi if dpi != 0 else 96)/96
	size := max(native_pixel_edge(10, scale), 1)
	stroke := f32(max(native_pixel_edge(1, scale), 1))
	radius := f32(int(1.5*scale)) if windows_11 else 0
	separation := f32(max(native_pixel_edge(2, scale), 1))
	mask := Win32_Caption_Mask{size=size, pixels=make([]u8, size*size, allocator=allocator)}
	if mask.pixels == nil { return {} }
	// Small, immutable coverage masks replace the font-shaped close character.
	// Axis-aligned Windows 10 marks are crisp; diagonals/rounded corners use AA.
	samples := 4 if icon == .Close || (windows_11 && icon != .Minimize) else 1
	for y in 0..<size {
		for x in 0..<size {
			coverage := 0
			for sy in 0..<samples {
				for sx in 0..<samples {
					px := f32(x)+(f32(sx)+0.5)/f32(samples)
					py := f32(y)+(f32(sy)+0.5)/f32(samples)
					if win32_caption_symbol_sample(icon, px, py, f32(size), stroke, radius, separation) { coverage += 1 }
				}
			}
			mask.pixels[y*size+x] = u8((coverage*255+samples*samples/2)/(samples*samples))
		}
	}
	return mask
}

win32_caption_destroy_masks :: proc(state: ^Win32_Menu_State) {
	for &mask in state.caption_masks {
		if mask.pixels != nil { delete(mask.pixels, state.allocator) }
		mask = {}
	}
	state.caption_mask_dpi = 0
}

win32_caption_sync_masks :: proc(state: ^Win32_Menu_State) -> bool {
	dpi := state.dpi if state.dpi != 0 else 96
	if state.caption_mask_dpi == dpi && state.caption_mask_windows_11 == state.windows_11 { return true }
	next: [4]Win32_Caption_Mask
	for icon in Win32_Caption_Icon {
		next[int(icon)] = win32_caption_build_mask(icon, dpi, state.windows_11, state.allocator)
		if next[int(icon)].pixels == nil {
			for mask in next { if mask.pixels != nil { delete(mask.pixels, state.allocator) } }
			return false
		}
	}
	win32_caption_destroy_masks(state)
	state.caption_masks = next
	state.caption_mask_dpi = dpi
	state.caption_mask_windows_11 = state.windows_11
	state.caption_mask_builds += 1
	return true
}

win32_caption_append_glyph :: proc(
	commands: ^[dynamic]alicorn.Paint_Command, state: ^Win32_Menu_State,
	index: int, color: alicorn.Color, clip: alicorn.Rect, maximized: bool,
) {
	if state == nil || index < 0 || index >= 3 { return }
	icon := Win32_Caption_Icon.Minimize
	if index == 1 { icon = .Restore if maximized else .Maximize }
	if index == 2 { icon = .Close }
	mask := state.caption_masks[int(icon)]
	if mask.size == 0 { return }
	control := state.caption_controls[index].bounds
	x0 := int(control.left)+(int(control.right-control.left)-mask.size)/2
	y0 := int(control.top)+(int(control.bottom-control.top)-mask.size)/2
	scale := 1/(state.pixels_per_unit if state.pixels_per_unit > 0 else 1)
	owner := NATIVE_MENU_HOST_SOLID_NODE+alicorn.Node_ID(1024*(index+1))
	for y in 0..<mask.size {
		for x := 0; x < mask.size; {
			coverage := mask.pixels[y*mask.size+x]
			end := x+1
			for end < mask.size && mask.pixels[y*mask.size+end] == coverage { end += 1 }
			if coverage != 0 {
				fill := color
				fill.a *= f32(coverage)/255
				append(commands, alicorn.paint_surface_command(owner,
					alicorn.Rect{f32(x0+x)*scale, f32(y0+y)*scale, f32(end-x)*scale, scale}, clip, fill))
				owner += 1
			}
			x = end
		}
	}
}
