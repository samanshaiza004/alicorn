package alicorn_sdl_gpu

import "core:fmt"
import "core:math"
import "core:time"
import alicorn "../../runtime"
import paint_reference "../../tests/paint_reference"
import runa "../../third_party/Runa"
import "vendor:sdl3"

BLEND_VALIDATION_SIZE :: 128

Blend_Validation_Renderers :: struct {
	text: Native_Text_Renderer,
	geometry: Native_Surface_Renderer,
	solid: Native_Solid_Renderer,
}

Blend_Validation_Sample :: struct {
	x, y: int,
	coverage: f32,
}

Blend_Validation_Family :: enum { Surface, Per_Corner_Surface, Geometry, Icon, Image, Text, Mixed }
Blend_Validation_Stats :: struct {
	cases, failed: int,
	family_cases, family_failed: [Blend_Validation_Family]int,
}

BLEND_VALIDATION_EXPECTED_CASES :: 348

blend_validation_expected_family_cases :: proc(family: Blend_Validation_Family) -> int {
	switch family {
	case .Surface:  return 48
	case .Per_Corner_Surface: return 192
	case .Geometry: return 24
	case .Icon:     return 24
	case .Image:    return 24
	case .Text:     return 24
	case .Mixed:    return 12
	}
	return -1
}

// Straight source RGB is weighted by coverage/opacity once; destination RGB
// already contains its composited contribution. Alpha uses As + Ad*(1-As).
// Worked anchors: half red then half blue over clear = (.25,0,.5,.75);
// a half-opacity (.8,.4,.2) surface over clear = (.4,.2,.1,.5).
blend_validation_over :: proc(destination: [4]f32, source: alicorn.Color, opacity: f32 = 1, coverage: f32 = 1) -> [4]f32 {
	a := source.a*opacity*coverage
	return {source.r*a+destination[0]*(1-a), source.g*a+destination[1]*(1-a),
		source.b*a+destination[2]*(1-a), a+destination[3]*(1-a)}
}

blend_validation_record :: proc(stats: ^Blend_Validation_Stats, family: Blend_Validation_Family, ok: bool) {
	stats.cases += 1
	stats.family_cases[family] += 1
	if !ok { stats.failed += 1; stats.family_failed[family] += 1 }
}

blend_validation_background :: proc(background: sdl3.FColor) -> [4]f32 {
	return {background.r, background.g, background.b, background.a}
}

// Exercise the application compositor, including its real upload, batching,
// shader, and submission paths. No window or replacement test pipeline is used.
blend_validation_readback :: proc(
	renderers: ^Blend_Validation_Renderers,
	target: ^sdl3.GPUTexture,
	download: ^sdl3.GPUTransferBuffer,
	display: []alicorn.Paint_Command,
	scale: f32,
	background: sdl3.FColor,
	pixels: []u8,
) -> bool {
	device := renderers.solid.device
	command := sdl3.AcquireGPUCommandBuffer(device)
	if command == nil { return false }
	submitted := false
	defer if !submitted { _ = sdl3.CancelGPUCommandBuffer(command) }
	clear_target := sdl3.GPUColorTargetInfo{texture=target, clear_color=background, load_op=.CLEAR, store_op=.STORE}
	pass := sdl3.BeginGPURenderPass(command, &clear_target, 1, nil)
	if pass == nil { return false }
	sdl3.EndGPURenderPass(pass)
	if !draw_display_list(command, target, BLEND_VALIDATION_SIZE, BLEND_VALIDATION_SIZE,
		&renderers.text, &renderers.geometry, &renderers.solid, display, scale, scale, clear_background=false) { return false }
	copy_pass := sdl3.BeginGPUCopyPass(command)
	if copy_pass == nil { return false }
	source := sdl3.GPUTextureRegion{texture=target, w=BLEND_VALIDATION_SIZE, h=BLEND_VALIDATION_SIZE, d=1}
	destination := sdl3.GPUTextureTransferInfo{transfer_buffer=download, pixels_per_row=BLEND_VALIDATION_SIZE, rows_per_layer=BLEND_VALIDATION_SIZE}
	sdl3.DownloadFromGPUTexture(copy_pass, source, destination)
	sdl3.EndGPUCopyPass(copy_pass)
	fence := sdl3.SubmitGPUCommandBufferAndAcquireFence(command)
	submitted = true
	if fence == nil { return false }
	defer sdl3.ReleaseGPUFence(device, fence)
	native_text_commit_submission(&renderers.text)
	native_surface_commit_submission(&renderers.geometry)
	native_solid_commit_submission(&renderers.solid)
	fences := [1]^sdl3.GPUFence{fence}
	if !sdl3.WaitForGPUFences(device, true, &fences[0], 1) { return false }
	mapped := sdl3.MapGPUTransferBuffer(device, download, false)
	if mapped == nil { return false }
	defer sdl3.UnmapGPUTransferBuffer(device, download)
	copy(pixels, (cast([^]u8)mapped)[:len(pixels)])
	return true
}

blend_validation_pixel :: proc(pixels: []u8, x, y: int) -> [4]u8 {
	i := (y*BLEND_VALIDATION_SIZE+x)*4
	return {pixels[i], pixels[i+1], pixels[i+2], pixels[i+3]}
}

blend_validation_expect :: proc(name: string, scale: f32, background: sdl3.FColor, pixels: []u8, x, y: int, expected: [4]f32) -> bool {
	actual := blend_validation_pixel(pixels, x, y)
	want: [4]int
	ok := true
	for c in 0..<4 {
		want[c] = int(math.round(expected[c]*255))
		if abs(int(actual[c])-want[c]) > 2 { ok = false }
	}
	if !ok {
		fmt.println("blend_readback_mismatch", "case", name, "scale", scale, "destination_alpha", background.a,
			"pixel", x, y, "actual_rgba8", actual, "expected_rgba8", want)
	}
	return ok
}

// Pick both a fully covered and an antialiased texel from CPU-owned masks.
// Expected coverage never comes from GPU readback or a blend-state enum.
blend_validation_icon_samples :: proc(scale: f32) -> (samples: [2]Blend_Validation_Sample, ok: bool) {
	origin := int(8*scale)
	size := int(16*scale)
	entry, valid := alicorn.icon_atlas_lookup(.Search, size)
	if !valid || entry.size != size { return }
	page := alicorn.ICON_ATLAS_PAGES[entry.page]
	full, edge := false, false
	for y in 0..<size {
		for x in 0..<size {
			mask := page.pixels[(entry.y+y)*page.width+entry.x+x]
			if mask == 255 && !full {
				samples[0] = {origin+x, origin+y, 1}
				full = true
			}
			if mask >= 64 && mask <= 192 && !edge {
				samples[1] = {origin+x, origin+y, f32(mask)/255}
				edge = true
			}
		}
	}
	return samples, full && edge
}

blend_validation_text_samples :: proc(renderer: ^Native_Text_Renderer) -> (samples: [2]Blend_Validation_Sample, ok: bool) {
	if len(renderer.draws) != 1 { fmt.println("blend_text_fixture_draw_count",len(renderer.draws)); return }
	draw := renderer.draws[0]
	page, valid := runa.atlas_page_view(&renderer.runtime.text_engine.atlas, draw.page_index, draw.is_color)
	if !valid || draw.is_color { return }
	quad := renderer.vertices[int(draw.first_vertex):][:6]
	x0, y0 := int(math.round(quad[0].position[0])), int(math.round(quad[0].position[1]))
	width := int(math.round(quad[2].position[0]-quad[0].position[0]))
	height := int(math.round(quad[2].position[1]-quad[0].position[1]))
	if abs(quad[0].position[0]-f32(x0)) > 0.001 || abs(quad[0].position[1]-f32(y0)) > 0.001 {
		fmt.println("blend_text_fixture_fractional_origin",quad[0].position)
		return
	}
	u0 := int(math.round(quad[0].uv[0]*f32(page.Width)))
	v0 := int(math.round(quad[0].uv[1]*f32(page.Height)))
	full, edge := false, false
	for y in 0..<height {
		for x in 0..<width {
			px, py := x0+x, y0+y
			if px < 0 || py < 0 || px >= BLEND_VALIDATION_SIZE || py >= BLEND_VALIDATION_SIZE { continue }
			mask := page.Pixels[(v0+y)*int(page.Width)+u0+x]
			if mask == 255 && !full { samples[0] = {px,py,1}; full = true }
			if mask >= 64 && mask <= 192 && !edge { samples[1] = {px,py,f32(mask)/255}; edge = true }
		}
	}
	if !full || !edge { fmt.println("blend_text_fixture_coverage_missing", "full",full,"edge",edge,"size",width,height) }
	return samples, full && edge
}

blend_validation_check_samples :: proc(name: string, scale: f32, background: sdl3.FColor, pixels: []u8, samples: [2]Blend_Validation_Sample, source: alicorn.Color, opacity: f32, layers: int) -> bool {
	ok := true
	for sample in samples {
		expected := blend_validation_background(background)
		for _ in 0..<layers { expected = blend_validation_over(expected, source, opacity, sample.coverage) }
		if !blend_validation_expect(name, scale, background, pixels, sample.x, sample.y, expected) { ok = false }
	}
	if !blend_validation_expect(name, scale, background, pixels, 0, 0, blend_validation_background(background)) { ok = false }
	return ok
}

blend_validation_check_per_corner_surface :: proc(
	mask: int,
	scale: f32,
	background: sdl3.FColor,
	pixels: []u8,
	color: alicorn.Color,
) -> bool {
	left := native_pixel_edge(8, scale)
	top := native_pixel_edge(8, scale)
	right := native_pixel_edge(32, scale)
	bottom := native_pixel_edge(32, scale)
	points := [4][2]int{{left,top}, {right-1,top}, {right-1,bottom-1}, {left,bottom-1}}
	bits := [4]int{1,2,4,8}
	names := [?]string{"per_corner_top_left", "per_corner_top_right", "per_corner_bottom_right", "per_corner_bottom_left"}
	destination := blend_validation_background(background)
	ok := true
	for corner in 0..<4 {
		expected := destination
		if (mask & bits[corner]) == 0 {
			expected = blend_validation_over(destination, color, 0.5)
		}
		if !blend_validation_expect(names[corner], scale, background, pixels, points[corner][0], points[corner][1], expected) {
			fmt.println("blend_per_corner_pattern", "mask", mask, "corner", names[corner])
			ok = false
		}
	}
	center := native_pixel_edge(20, scale)
	if !blend_validation_expect("per_corner_center", scale, background, pixels, center, center,
		blend_validation_over(destination, color, 0.5)) {
		fmt.println("blend_per_corner_pattern", "mask", mask, "corner", "center")
		ok = false
	}
	return ok
}

blend_validation_cases :: proc(renderers: ^Blend_Validation_Renderers, rt: ^alicorn.Runtime, target: ^sdl3.GPUTexture, download: ^sdl3.GPUTransferBuffer, pixels: []u8) -> bool {
	if !alicorn.text_engine_load_font(&rt.text_engine, NATIVE_UI_FONT_DATA) { return false }
	// Curved glyph retains antialiased texels even when hinted stems align
	// exactly to the pixel grid at a particular raster scale.
	run, shaped := alicorn.text_run_build(&rt.text_engine, "O", 24)
	if !shaped { return false }
	if !native_text_register_host_run(&renderers.text, 1, run) {
		alicorn.text_run_destroy(&run)
		return false
	}
	text_handle := native_text_host_handle(&renderers.text, 1)
	ui, build := alicorn.begin_frame(rt)
	if !build { return false }
	alicorn.container_begin(&ui, .Root, label="blend-probe")
	geometry := alicorn.gpu_geometry_surface(&ui, "blend-line-circle", alicorn.layout_style(width=64,height=48), 1)
	backdrop := alicorn.gpu_geometry_surface(&ui, "blend-full-geometry", alicorn.layout_style(width=64,height=48), 1)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	geometry_color := alicorn.Color{0.8,0.4,0.2,0.5}
	segments := [1]alicorn.GPU_Surface_Line_Segment{{start={0,12}, end={24,12}, thickness=8, color=geometry_color}}
	circles := [1]alicorn.GPU_Surface_Filled_Circle{{center={40,12}, radius=8, color=geometry_color}}
	backdrop_segments := [1]alicorn.GPU_Surface_Line_Segment{{start={0,24}, end={64,24}, thickness=48, color=geometry_color}}
	if !alicorn.gpu_surface_update_geometry(rt, geometry, segments[:], circles[:]) ||
		!alicorn.gpu_surface_update_geometry(rt, backdrop, backdrop_segments[:], nil) { return false }
	geometry_handle := alicorn.paint_geometry_handle_for_node(rt.nodes[geometry])
	backdrop_handle := alicorn.paint_geometry_handle_for_node(rt.nodes[backdrop])
	// A single known QOI pixel, RGB=(.2,.4,.8), alpha=128/255.
	encoded := [27]u8{'q','o','i','f',0,0,0,1,0,0,0,1,4,0,0xFF,51,102,204,128,0,0,0,0,0,0,0,1}
	image, load_error := alicorn.image_load_bytes(rt, encoded[:])
	if load_error != .None { return false }
	defer _ = alicorn.image_release(rt, image)
	image_color := alicorn.Color{0.2,0.4,0.8,128.0/255.0}
	clip := alicorn.Rect{0,0,64,64}
	bounds := alicorn.Rect{8,8,24,24}
	text_color := alicorn.Color{0.2,0.8,0.4,0.8}
	icon_color := alicorn.Color{1,0.25,0.5,0.8}
	stats: Blend_Validation_Stats
	scales := [4]f32{1,1.25,1.5,2}
	backgrounds := [3]sdl3.FColor{{}, {0.2,0.4,0.6,0.4}, {0.2,0.4,0.6,1}}
	for scale in scales {
		icon_samples, icon_ok := blend_validation_icon_samples(scale)
		if !icon_ok { fmt.println("blend_mask_fixture_failed", "icon", "scale", scale); return false }
		for background in backgrounds {
			destination := blend_validation_background(background)
			probe := int(16*scale)
			surface := alicorn.paint_surface_command(1, bounds, clip, alicorn.Color{0.8,0.4,0.2,1}, opacity=0.5)
			display := [2]alicorn.Paint_Command{surface,surface}
			if !blend_validation_readback(renderers,target,download,display[:1],scale,background,pixels) { return false }
			blend_validation_record(&stats, .Surface, blend_validation_expect("surface_half_opacity",scale,background,pixels,probe,probe,
				blend_validation_over(destination,alicorn.Color{0.8,0.4,0.2,1},0.5)))
			// The source's own alpha and paint-command opacity must multiply.
			display[0] = alicorn.paint_surface_command(1,bounds,clip,geometry_color,opacity=0.5)
			if !blend_validation_readback(renderers,target,download,display[:1],scale,background,pixels) { return false }
			blend_validation_record(&stats,.Surface,blend_validation_expect("surface_alpha_times_opacity",scale,background,pixels,probe,probe,
				blend_validation_over(destination,geometry_color,0.5)))
			display[0] = alicorn.paint_surface_command(1,bounds,clip,geometry_color,opacity=0.5,
				shape=alicorn.Surface_Shape{kind=.Rounded_Rectangle,corner_radius=6})
			if !blend_validation_readback(renderers,target,download,display[:1],scale,background,pixels) { return false }
			blend_validation_record(&stats,.Surface,blend_validation_expect("rounded_surface_interior",scale,background,pixels,probe,probe,
				blend_validation_over(destination,geometry_color,0.5)))
			for mask in 0..<16 {
				radii := alicorn.Surface_Corner_Radii{
					top_left=6 if (mask & 1) != 0 else 0,
					top_right=6 if (mask & 2) != 0 else 0,
					bottom_right=6 if (mask & 4) != 0 else 0,
					bottom_left=6 if (mask & 8) != 0 else 0,
				}
				shape := alicorn.surface_shape_rounded_corners(radii)
				rt.semantic_surfaces[1] = alicorn.Semantic_Surface_Style{
					defined=true,
					role=alicorn.surface_core_color_role(.Surface),
					shape=shape,
				}
				display[0] = alicorn.paint_surface_command(1,bounds,clip,geometry_color,opacity=0.5,shape=shape)
				if !blend_validation_readback(renderers,target,download,display[:1],scale,background,pixels) { return false }
				blend_validation_record(&stats,.Per_Corner_Surface,
					blend_validation_check_per_corner_surface(mask,scale,background,pixels,geometry_color))
			}
			// Over clear the literal answer is (.25,0,.5,.75). Reversal gives
			// (.5,0,.25,.75), so RGB also locks down retained stream order.
			display[0] = alicorn.paint_surface_command(1,bounds,clip,alicorn.Color{1,0,0,0.5})
			display[1] = alicorn.paint_surface_command(2,bounds,clip,alicorn.Color{0,0,1,0.5})
			if !blend_validation_readback(renderers,target,download,display[:],scale,background,pixels) { return false }
			overlap := blend_validation_over(blend_validation_over(destination,alicorn.Color{1,0,0,0.5}),alicorn.Color{0,0,1,0.5})
			blend_validation_record(&stats,.Surface,blend_validation_expect("overlapping_red_then_blue",scale,background,pixels,probe,probe,overlap))
			for layers in 1..=2 {
				geometry_draw := alicorn.paint_geometry_command(geometry,alicorn.Rect{8,8,56,40},clip,geometry_handle,opacity=0.5)
				display = {geometry_draw,geometry_draw}
				if !blend_validation_readback(renderers,target,download,display[:layers],scale,background,pixels) { return false }
				expected := destination
				for _ in 0..<layers { expected = blend_validation_over(expected,geometry_color,0.5) }
				geometry_ok := blend_validation_expect("custom_geometry_line",scale,background,pixels,int(16*scale),int(20*scale),expected)
				if !blend_validation_expect("custom_geometry_circle",scale,background,pixels,int(48*scale),int(20*scale),expected) { geometry_ok = false }
				blend_validation_record(&stats,.Geometry,geometry_ok)
				icon := alicorn.paint_icon_command(1,alicorn.Rect{8,8,16,16},clip,.Search,icon_color,opacity=0.5)
				display = {icon,icon}
				if !blend_validation_readback(renderers,target,download,display[:layers],scale,background,pixels) { return false }
				blend_validation_record(&stats,.Icon,blend_validation_check_samples("icon_mask",scale,background,pixels,icon_samples,icon_color,0.5,layers))
				image_draw := alicorn.paint_image_command(1,bounds,clip,image,opacity=0.5)
				display = {image_draw,image_draw}
				if !blend_validation_readback(renderers,target,download,display[:layers],scale,background,pixels) { return false }
				expected = destination
				for _ in 0..<layers { expected = blend_validation_over(expected,image_color,0.5) }
				blend_validation_record(&stats,.Image,blend_validation_expect("sampled_image",scale,background,pixels,probe,probe,expected))
			}
			text := alicorn.paint_text_command(1,alicorn.Rect{8,8,48,48},clip,text_handle,text_color,opacity=0.5)
			display = {text,text}
			if !blend_validation_readback(renderers,target,download,display[:1],scale,background,pixels) { return false }
			text_samples, text_ok := blend_validation_text_samples(&renderers.text)
			if !text_ok { fmt.println("blend_mask_fixture_failed", "text", "scale", scale); return false }
			blend_validation_record(&stats,.Text,blend_validation_check_samples("text_mask",scale,background,pixels,text_samples,text_color,0.5,1))
			if !blend_validation_readback(renderers,target,download,display[:],scale,background,pixels) { return false }
			blend_validation_record(&stats,.Text,blend_validation_check_samples("text_mask_overlap",scale,background,pixels,text_samples,text_color,0.5,2))
			// Align a full-coverage glyph texel with a full-coverage icon texel.
			// All five real pipelines now contribute at one known pixel.
			text.translation = {(f32(icon_samples[0].x-text_samples[0].x))/scale,(f32(icon_samples[0].y-text_samples[0].y))/scale}
			mixed := [5]alicorn.Paint_Command{
				alicorn.paint_surface_command(1,clip,clip,alicorn.Color{1,0,0,0.5}),
				text,
				alicorn.paint_geometry_command(backdrop,clip,clip,backdrop_handle,opacity=0.5),
				alicorn.paint_icon_command(1,alicorn.Rect{8,8,16,16},clip,.Search,icon_color,opacity=0.5),
				alicorn.paint_image_command(1,clip,clip,image,opacity=0.5),
			}
			if !blend_validation_readback(renderers,target,download,mixed[:],scale,background,pixels) { return false }
			expected := blend_validation_over(destination,alicorn.Color{1,0,0,0.5})
			expected = blend_validation_over(expected,text_color,0.5)
			expected = blend_validation_over(expected,geometry_color,0.5)
			expected = blend_validation_over(expected,icon_color,0.5)
			expected = blend_validation_over(expected,image_color,0.5)
			blend_validation_record(&stats,.Mixed,blend_validation_expect("mixed_surface_text_geometry_icon_image",scale,background,pixels,icon_samples[0].x,icon_samples[0].y,expected))
			if background.a == 0 {
				fmt.println("blend_mask_coverage", "scale",scale,"text",text_samples,"icon",icon_samples)
			}
		}
	}
	case_counts_ok := stats.cases == BLEND_VALIDATION_EXPECTED_CASES
	if !case_counts_ok {
		fmt.println("blend_gpu_case_count_mismatch", "actual",stats.cases,"expected",BLEND_VALIDATION_EXPECTED_CASES)
	}
	for family in Blend_Validation_Family {
		expected_family_cases := blend_validation_expected_family_cases(family)
		if stats.family_cases[family] != expected_family_cases {
			case_counts_ok = false
			fmt.println("blend_gpu_family_count_mismatch",family,"actual",stats.family_cases[family],
				"expected",expected_family_cases)
		}
		fmt.println("blend_gpu_family",family,"cases",stats.family_cases[family],"failed",stats.family_failed[family])
	}
	fmt.println("blend_gpu_validation", "driver",sdl3.GetGPUDeviceDriver(renderers.solid.device),
		"target","R8G8B8A8_UNORM","scales","1,1.25,1.5,2","destination_alpha","0,0.4,1",
		"per_corner_masks",16,"cases",stats.cases,"expected_cases",BLEND_VALIDATION_EXPECTED_CASES,
		"case_counts_ok",case_counts_ok,"failed",stats.failed,"rgba_tolerance_bytes",2)
	return stats.failed == 0 && case_counts_ok
}

blend_validation_motion_clip_case :: proc(
	renderers: ^Blend_Validation_Renderers,
	rt: ^alicorn.Runtime,
	target: ^sdl3.GPUTexture,
	download: ^sdl3.GPUTransferBuffer,
	pixels: []u8,
) -> bool {
	alicorn.invalidate_root(rt, "motion clip GPU regression")
	ui, build := alicorn.begin_frame(rt)
	if !build { fmt.println("motion_clip_gpu_fixture", "begin_frame_failed"); return false }
	alicorn.container_begin_simple(&ui, .Root, key="motion-clip-gpu-root",
		style=alicorn.layout_style(.Column, width=64, height=64, clip=true))
	alicorn.container_begin_simple(&ui, .Container, key="motion-clip-gpu-viewport",
		style=alicorn.layout_style(.Row, width=64, height=48, clip=true))
	moving := alicorn.container_begin_simple(&ui, .Container, key="motion-clip-gpu-tab",
		style=alicorn.layout_style(.Row, width=18, height=32, clip=true))
	label := alicorn.text(&ui, "O", key="motion-clip-gpu-label",
		style=alicorn.layout_style(.Row, width=48, height=32), color=alicorn.Color{1, 1, 1, 1})
	alicorn.container_end(&ui)
	alicorn.container_end(&ui)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	if moving == 0 || label == 0 { fmt.println("motion_clip_gpu_fixture", "missing_nodes"); return false }

	if status := alicorn.motion_clock_set_time(rt, alicorn.Motion_Time(0)); status != .Ok {
		fmt.println("motion_clip_gpu_fixture", "clock_failed", status); return false
	}
	target_motion := alicorn.Motion_Target{
		translation=alicorn.Motion_Vector2{24, 0},
		clip_policy=.Follow_Visual,
		has_translation=true,
	}
	if status := alicorn.motion_apply_intent(rt, moving, target_motion, .Snap); status != .Ok {
		fmt.println("motion_clip_gpu_fixture", "initial_motion_failed", status); return false
	}
	present_ui, ready := alicorn.begin_presentation_frame(rt)
	if !ready { fmt.println("motion_clip_gpu_fixture", "presentation_not_requested"); return false }
	alicorn.end_presentation_frame(&present_ui)

	text_command, found := alicorn.Paint_Command{}, false
	for command in rt.display {
		if command.owner == label && alicorn.paint_command_is_text(command) {
			text_command, found = command, true
			break
		}
	}
	expected_clip := alicorn.Rect{24, 0, 18, 32}
	expected_translation := [2]f32{24, 0}
	if !found || text_command.clip != expected_clip || text_command.translation != expected_translation {
		fmt.println("motion_clip_gpu_fixture", "composed_clip_mismatch", text_command.clip,
			"expected", expected_clip, "translation", text_command.translation)
		return false
	}
	background := sdl3.FColor{0, 0, 0, 1}
	scales := [3]f32{1, 1.5, 2}
	for scale in scales {
		if !blend_validation_readback(renderers, target, download, rt.display[:], scale, background, pixels) {
			fmt.println("motion_clip_gpu_fixture", "initial_readback_failed", "scale", scale, "SDL_error", sdl3.GetError())
			return false
		}
		samples, ok := blend_validation_text_samples(&renderers.text)
		text_paint, paint_ok := text_command.payload.(alicorn.Text_Paint)
		sample := samples[0]
		sample.x += int(math.round(text_command.translation[0]*scale))
		sample.y += int(math.round(text_command.translation[1]*scale))
		if !ok || !paint_ok || !blend_validation_expect("motion_followed_tab_text", scale, background, pixels,
			sample.x, sample.y,
			blend_validation_over(blend_validation_background(background), text_paint.color, sample.coverage)) {
			fmt.println("motion_clip_gpu_fixture", "translated_glyph_readback_failed", "scale", scale)
			return false
		}
	}

	if status := alicorn.motion_clock_set_time(rt, alicorn.Motion_Time(300_000_000)); status != .Ok {
		fmt.println("motion_clip_gpu_fixture", "edge_clock_failed", status); return false
	}
	edge_target := alicorn.Motion_Target{
		translation=alicorn.Motion_Vector2{55, 0},
		clip_policy=.Follow_Visual,
		has_translation=true,
	}
	if status := alicorn.motion_apply_intent(rt, moving, edge_target, .Snap); status != .Ok {
		fmt.println("motion_clip_gpu_fixture", "edge_motion_failed", status); return false
	}
	present_ui, ready = alicorn.begin_presentation_frame(rt)
	if !ready { fmt.println("motion_clip_gpu_fixture", "edge_presentation_not_requested"); return false }
	alicorn.end_presentation_frame(&present_ui)
	for command in rt.display {
		if command.owner == label && alicorn.paint_command_is_text(command) {
			text_command = command
			break
		}
	}
	if text_command.clip.x != 55 || text_command.clip.x+text_command.clip.w != 64 {
		fmt.println("motion_clip_gpu_fixture", "viewport_clip_mismatch", text_command.clip)
		return false
	}
	edge_scale := f32(1.5)
	if !blend_validation_readback(renderers, target, download, rt.display[:], edge_scale, background, pixels) {
		fmt.println("motion_clip_gpu_fixture", "edge_readback_failed", "SDL_error", sdl3.GetError())
		return false
	}
	visible_pixels := 0
	for y in 0..<int(48*edge_scale) {
		for x in int(55*edge_scale)..<int(64*edge_scale) {
			pixel := blend_validation_pixel(pixels, x, y)
			if pixel[0] > 8 || pixel[1] > 8 || pixel[2] > 8 { visible_pixels += 1 }
		}
	}
	outside_pixels := 0
	for y in 0..<int(48*edge_scale) {
		for x in int(64*edge_scale)..<int(BLEND_VALIDATION_SIZE) {
			pixel := blend_validation_pixel(pixels, x, y)
			if pixel[0] > 8 || pixel[1] > 8 || pixel[2] > 8 { outside_pixels += 1 }
		}
	}
	if visible_pixels == 0 || outside_pixels != 0 {
		fmt.println("motion_clip_gpu_fixture", "stationary_viewport_readback_failed",
			"visible", visible_pixels, "outside", outside_pixels)
		return false
	}
	fmt.println("motion_clip_gpu_validation", "scales", "1,1.5,2", "local_clip_follows", true, "outer_viewport_fixed", true)
	return true
}

blend_validation_reference_scene_dump :: proc(seed: u64, commands: []alicorn.Paint_Command) {
	fmt.println("cpu_reference_replay_seed", seed, "command_count", len(commands))
	for command, index in commands {
		surface := command.payload.(alicorn.Surface_Paint)
		fmt.println("cpu_reference_command", "index", index, "owner", command.owner,
			"bounds", command.bounds, "clip", command.clip,
			"translation", command.translation, "opacity", command.opacity,
			"fill", surface.fill)
	}
}

Blend_Reference_Diff :: struct {
	max_channel_error: int,
	mismatched_pixels: int,
	first_x, first_y, first_channel: int,
	first_expected, first_actual: int,
}

blend_validation_reference_diff :: proc(expected, actual: []u8) -> Blend_Reference_Diff {
	diff := Blend_Reference_Diff{first_x=-1, first_y=-1, first_channel=-1}
	if len(expected) != len(actual) { diff.mismatched_pixels = -1; return diff }
	for pixel in 0..<(BLEND_VALIDATION_SIZE*BLEND_VALIDATION_SIZE) {
		pixel_mismatch := false
		for channel in 0..<4 {
			index := pixel*4+channel
			difference := abs(int(expected[index])-int(actual[index]))
			if difference > diff.max_channel_error { diff.max_channel_error = difference }
			if difference > 2 {
				pixel_mismatch = true
				if diff.first_x < 0 {
					diff.first_x, diff.first_y, diff.first_channel = pixel%BLEND_VALIDATION_SIZE, pixel/BLEND_VALIDATION_SIZE, channel
					diff.first_expected, diff.first_actual = int(expected[index]), int(actual[index])
				}
			}
		}
		if pixel_mismatch { diff.mismatched_pixels += 1 }
	}
	return diff
}

blend_validation_reference_compare :: proc(seed: u64, expected, actual: []u8) -> bool {
	diff := blend_validation_reference_diff(expected, actual)
	if diff.mismatched_pixels != 0 {
		fmt.println("cpu_gpu_reference_mismatch", "seed", seed, "mismatched_pixels", diff.mismatched_pixels,
			"max_channel_error_bytes", diff.max_channel_error, "first_pixel", diff.first_x, diff.first_y,
			"channel_rgba", diff.first_channel, "expected", diff.first_expected, "actual", diff.first_actual,
			"per_channel_tolerance_bytes", 2)
		return false
	}
	return true
}

blend_validation_reference_replay_differs :: proc(
	commands: []alicorn.Paint_Command,
	renderers: ^Blend_Validation_Renderers,
	target: ^sdl3.GPUTexture,
	download: ^sdl3.GPUTransferBuffer,
	actual: []u8,
) -> (differs, valid: bool) {
	expected: [BLEND_VALIDATION_SIZE*BLEND_VALIDATION_SIZE*4]u8
	if error := paint_reference.paint_reference_render(commands, BLEND_VALIDATION_SIZE, BLEND_VALIDATION_SIZE, {}, expected[:]); error.code != .None {
		return false, false
	}
	if !blend_validation_readback(renderers, target, download, commands, 1, {}, actual) { return false, false }
	return blend_validation_reference_diff(expected[:], actual).mismatched_pixels > 0, true
}

// Remove a command only when the same CPU/GPU mismatch still reproduces.
blend_validation_reference_reduce_failure :: proc(
	seed: u64,
	commands: []alicorn.Paint_Command,
	renderers: ^Blend_Validation_Renderers,
	target: ^sdl3.GPUTexture,
	download: ^sdl3.GPUTransferBuffer,
	actual: []u8,
) {
	if len(commands) > paint_reference.PAINT_REFERENCE_SCENE_RECTANGLES { return }
	current: [paint_reference.PAINT_REFERENCE_SCENE_RECTANGLES]alicorn.Paint_Command
	trial: [paint_reference.PAINT_REFERENCE_SCENE_RECTANGLES]alicorn.Paint_Command
	copy(current[:], commands)
	count := len(commands)
	changed := true
	for changed {
		changed = false
		index := 0
		for index < count {
			candidate_count := count-1
			copy(trial[:index], current[:index])
			copy(trial[index:candidate_count], current[index+1:count])
			differs, completed := blend_validation_reference_replay_differs(trial[:candidate_count], renderers, target, download, actual)
			if !completed {
				fmt.println("cpu_reference_reducer_aborted", "seed", seed, "candidate_count", candidate_count)
				return
			}
			if differs {
				copy(current[:candidate_count], trial[:candidate_count])
				count = candidate_count
				changed = true
			} else {
				index += 1
			}
		}
	}
	fmt.println("cpu_reference_replay_minimized", "seed", seed, "original_commands", len(commands), "reduced_commands", count)
	blend_validation_reference_scene_dump(seed, current[:count])
}

blend_validation_reference_scenes :: proc(
	renderers: ^Blend_Validation_Renderers,
	target: ^sdl3.GPUTexture,
	download: ^sdl3.GPUTransferBuffer,
	actual: []u8,
) -> bool {
	commands: [paint_reference.PAINT_REFERENCE_SCENE_RECTANGLES]alicorn.Paint_Command
	expected: [BLEND_VALIDATION_SIZE*BLEND_VALIDATION_SIZE*4]u8
	cpu_render_ns: i64
	gpu_readback_ns: i64
	for seed in 1..=32 {
		count := paint_reference.paint_reference_generate_scene(u64(seed), BLEND_VALIDATION_SIZE, BLEND_VALIDATION_SIZE, commands[:])
		if count != paint_reference.PAINT_REFERENCE_SCENE_RECTANGLES {
			fmt.println("cpu_reference_scene_generation_failed", "seed", seed)
			return false
		}
		display := commands[:count]
		started := time.now()
		if error := paint_reference.paint_reference_render(display, BLEND_VALIDATION_SIZE, BLEND_VALIDATION_SIZE, {}, expected[:]); error.code != .None {
			fmt.println("cpu_reference_rejected_generated_scene", "seed", seed, "command_index", error.command_index,
				"owner", error.owner, "reason", error.code)
			blend_validation_reference_scene_dump(u64(seed), display)
			return false
		}
		cpu_render_ns += time.duration_nanoseconds(time.since(started))
		started = time.now()
		if !blend_validation_readback(renderers, target, download, display, 1, {}, actual) {
			fmt.println("cpu_gpu_reference_readback_failed", "seed", seed)
			blend_validation_reference_scene_dump(u64(seed), display)
			return false
		}
		gpu_readback_ns += time.duration_nanoseconds(time.since(started))
		if !blend_validation_reference_compare(u64(seed), expected[:], actual) {
			blend_validation_reference_reduce_failure(u64(seed), display, renderers, target, download, actual)
			return false
		}
	}

	// Keep the reduced mutation failure as a fixed GPU regression, independent
	// of seed generation. This protects the specific stationary-clip contract.
	fixed_commands := [1]alicorn.Paint_Command{paint_reference.paint_reference_stationary_clip_regression()}
	if error := paint_reference.paint_reference_render(fixed_commands[:], BLEND_VALIDATION_SIZE,
		BLEND_VALIDATION_SIZE, {}, expected[:]); error.code != .None {
		fmt.println("cpu_reference_rejected_fixed_regression", "command_index", error.command_index,
			"owner", error.owner, "reason", error.code)
		return false
	}
	if !blend_validation_readback(renderers, target, download, fixed_commands[:], 1, {}, actual) {
		fmt.println("cpu_gpu_reference_fixed_regression_readback_failed", "stationary_clip_after_translation")
		blend_validation_reference_scene_dump(0xC11F, fixed_commands[:])
		return false
	}
	if !blend_validation_reference_compare(0xC11F, expected[:], actual) {
		fmt.println("cpu_gpu_reference_fixed_regression_failed", "stationary_clip_after_translation")
		blend_validation_reference_scene_dump(0xC11F, fixed_commands[:])
		return false
	}
	fmt.println("cpu_gpu_reference_fixed_regression", "stationary_clip_after_translation", "PASS")
	fmt.println("cpu_gpu_reference_scenes", "seeds", 32, "rectangles_per_scene",
		paint_reference.PAINT_REFERENCE_SCENE_RECTANGLES, "target", "128x128", "scale", 1,
		"target_format", "R8G8B8A8_UNORM", "rgba_tolerance_bytes", 2,
		"cpu_total_ns", cpu_render_ns, "cpu_mean_ns", cpu_render_ns/32,
		"gpu_readback_total_ns", gpu_readback_ns, "gpu_readback_mean_ns", gpu_readback_ns/32,
		"cpu_reference_allocations_per_scene", 0)
	return true
}

blend_validation_gradient_fixture :: proc(rt: ^alicorn.Runtime) -> (
	horizontal, vertical: alicorn.Paint_Command,
	ok: bool,
) {
	start_role := alicorn.style_extension_color_role_id("app.validation", "gradient_start")
	end_role := alicorn.style_extension_color_role_id("app.validation", "gradient_end")
	vertical_start_role := alicorn.style_extension_color_role_id("app.validation", "vertical_start")
	vertical_end_role := alicorn.style_extension_color_role_id("app.validation", "vertical_end")
	start := alicorn.Color{0.86, 0.16, 0.08, 0.5}
	end := alicorn.Color{0.08, 0.34, 0.92, 0.5}
	vertical_start := alicorn.Color{0.08, 0.74, 0.2, 0.6}
	vertical_end := alicorn.Color{0.76, 0.12, 0.4, 0.6}
	theme := alicorn.DEFAULT_STYLE_THEME
	theme.color_tokens = {start, end, vertical_start, vertical_end}
	theme.extension_color_roles = {
		alicorn.Style_Extension_Color_Role_Binding{role=start_role, token=alicorn.Style_Color_Token_ID(1)},
		alicorn.Style_Extension_Color_Role_Binding{role=end_role, token=alicorn.Style_Color_Token_ID(2)},
		alicorn.Style_Extension_Color_Role_Binding{role=vertical_start_role, token=alicorn.Style_Color_Token_ID(3)},
		alicorn.Style_Extension_Color_Role_Binding{role=vertical_end_role, token=alicorn.Style_Color_Token_ID(4)},
	}
	theme_id := alicorn.style_theme_register(rt, theme)
	if theme_id == 0 { return }
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin(&ui, .Root, key=alicorn.key_string("gradient-validation-root"),
		style=alicorn.layout_style(.Column, width=128, height=128, clip=true))
	scope := alicorn.style_environment_push(&ui, alicorn.Style_Environment{theme=theme_id})
	horizontal_id := alicorn.surface_begin(&ui, alicorn.surface_extension_color_role(start_role),
		key=alicorn.key_string("gradient-validation-horizontal"),
		style=alicorn.layout_style(width=48, height=40),
		gradient=alicorn.surface_gradient_to(alicorn.surface_extension_color_role(end_role), .Horizontal))
	alicorn.surface_end(&ui)
	vertical_id := alicorn.surface_begin(&ui, alicorn.surface_extension_color_role(vertical_start_role),
		key=alicorn.key_string("gradient-validation-vertical"),
		style=alicorn.layout_style(width=48, height=48),
		shape=alicorn.surface_shape_rounded_corners({top_left=6, top_right=6, bottom_right=6, bottom_left=6}),
		gradient=alicorn.surface_gradient_to(alicorn.surface_extension_color_role(vertical_end_role), .Vertical))
	alicorn.surface_end(&ui)
	alicorn.style_environment_pop(&ui, scope)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	horizontal_node, horizontal_found := rt.nodes[horizontal_id]
	vertical_node, vertical_found := rt.nodes[vertical_id]
	if !horizontal_found || !vertical_found || len(horizontal_node.paint) != 1 || len(vertical_node.paint) != 1 { return }
	horizontal = horizontal_node.paint[0]
	horizontal.bounds = {8, 8, 48, 40}
	horizontal.clip = {20, 8, 36, 40}
	horizontal.opacity = 0.8
	horizontal.stroke_placement = .Inside
	horizontal_surface, horizontal_surface_ok := horizontal.payload.(alicorn.Surface_Paint)
	if !horizontal_surface_ok { return }
	horizontal_surface.stroke = alicorn.Paint_Stroke{color={0.94, 0.78, 0.12, 1}, width=2}
	horizontal.payload = horizontal_surface
	vertical = vertical_node.paint[0]
	vertical.bounds = {16, 8, 48, 48}
	vertical.clip = {16, 20, 48, 36}
	vertical.opacity = 0.75
	return horizontal, vertical, horizontal.semantic_surface_gradient && vertical.semantic_surface_gradient
}

blend_validation_gradient_interpolate :: proc(start, end: alicorn.Color, t: f32) -> alicorn.Color {
	return alicorn.Color{
		start.r+(end.r-start.r)*t,
		start.g+(end.g-start.g)*t,
		start.b+(end.b-start.b)*t,
		start.a,
	}
}

BLEND_GRADIENT_BENCHMARK_SURFACES :: 256
BLEND_GRADIENT_BENCHMARK_SAMPLES  :: 51

blend_validation_sort_durations :: proc(samples: []i64) {
	for i in 1..<len(samples) {
		value := samples[i]
		j := i
		for j > 0 && samples[j-1] > value {
			samples[j] = samples[j-1]
			j -= 1
		}
		samples[j] = value
	}
}

// Report synchronous offscreen submission-to-readback latency for identical
// 256-surface batches. This is a GPU completion round trip, not presented-frame
// latency; the separate CPU benchmark isolates mesh expansion.
blend_validation_gradient_gpu_benchmark :: proc(
	renderers: ^Blend_Validation_Renderers,
	rt: ^alicorn.Runtime,
	target: ^sdl3.GPUTexture,
	download: ^sdl3.GPUTransferBuffer,
	pixels: []u8,
) -> bool {
	horizontal, _, fixture_ok := blend_validation_gradient_fixture(rt)
	if !fixture_ok { return false }
	previous_runtime := renderers.solid.runtime
	renderers.solid.runtime = rt
	defer renderers.solid.runtime = previous_runtime

	solid := make([dynamic]alicorn.Paint_Command, 0, BLEND_GRADIENT_BENCHMARK_SURFACES, allocator=context.temp_allocator)
	defer delete(solid)
	gradient := make([dynamic]alicorn.Paint_Command, 0, BLEND_GRADIENT_BENCHMARK_SURFACES, allocator=context.temp_allocator)
	defer delete(gradient)
	for i in 0..<BLEND_GRADIENT_BENCHMARK_SURFACES {
		bounds := alicorn.Rect{f32(i%16)*4, f32(i/16)*4, 4, 4}
		solid_command := horizontal
		solid_command.bounds = bounds
		solid_command.clip = {0, 0, 64, 64}
		solid_command.opacity = 1
		solid_command.semantic_surface_gradient = false
		gradient_command := solid_command
		gradient_command.semantic_surface_gradient = true
		append(&solid, solid_command)
		append(&gradient, gradient_command)
	}

	for _ in 0..<3 {
		if !blend_validation_readback(renderers, target, download, solid[:], 2, {}, pixels) { return false }
		if !blend_validation_readback(renderers, target, download, gradient[:], 2, {}, pixels) { return false }
	}
	solid_samples: [BLEND_GRADIENT_BENCHMARK_SAMPLES]i64
	gradient_samples: [BLEND_GRADIENT_BENCHMARK_SAMPLES]i64
	for sample in 0..<BLEND_GRADIENT_BENCHMARK_SAMPLES {
		first, second := solid[:], gradient[:]
		if sample%2 != 0 { first, second = gradient[:], solid[:] }
		started := time.now()
		if !blend_validation_readback(renderers, target, download, first, 2, {}, pixels) { return false }
		first_ns := time.duration_nanoseconds(time.since(started))
		started = time.now()
		if !blend_validation_readback(renderers, target, download, second, 2, {}, pixels) { return false }
		second_ns := time.duration_nanoseconds(time.since(started))
		if sample%2 == 0 {
			solid_samples[sample] = first_ns
			gradient_samples[sample] = second_ns
		} else {
			gradient_samples[sample] = first_ns
			solid_samples[sample] = second_ns
		}
	}
	blend_validation_sort_durations(solid_samples[:])
	blend_validation_sort_durations(gradient_samples[:])
	p50 := BLEND_GRADIENT_BENCHMARK_SAMPLES/2
	p95 := (BLEND_GRADIENT_BENCHMARK_SAMPLES*95+99)/100-1
	bytes_per_batch := BLEND_GRADIENT_BENCHMARK_SURFACES*6*size_of(Native_Text_Vertex)
	fmt.println("surface_gradient_gpu_roundtrip",
		"device", sdl3.GetGPUDeviceDriver(renderers.solid.device),
		"surfaces", BLEND_GRADIENT_BENCHMARK_SURFACES,
		"solid_draw_calls", BLEND_GRADIENT_BENCHMARK_SURFACES,
		"gradient_draw_calls", BLEND_GRADIENT_BENCHMARK_SURFACES,
		"solid_passes", 1, "gradient_passes", 1,
		"vertices_per_batch", BLEND_GRADIENT_BENCHMARK_SURFACES*6,
		"uploaded_bytes_per_batch", bytes_per_batch,
		"samples", BLEND_GRADIENT_BENCHMARK_SAMPLES,
		"scale", 2,
		"solid_p50_ns", solid_samples[p50], "solid_p95_ns", solid_samples[p95],
		"gradient_p50_ns", gradient_samples[p50], "gradient_p95_ns", gradient_samples[p95],
		"measurement", "offscreen_submit_fence_and_readback_not_presented_frame")
	return true
}

blend_validation_gradient_readbacks :: proc(
	renderers: ^Blend_Validation_Renderers,
	rt: ^alicorn.Runtime,
	target: ^sdl3.GPUTexture,
	download: ^sdl3.GPUTransferBuffer,
	pixels: []u8,
) -> bool {
	horizontal, vertical, fixture_ok := blend_validation_gradient_fixture(rt)
	if !fixture_ok {
		fmt.println("surface_gradient_gpu_fixture_failed")
		return false
	}
	previous_runtime := renderers.solid.runtime
	renderers.solid.runtime = rt
	defer renderers.solid.runtime = previous_runtime
	background := sdl3.FColor{0.11, 0.17, 0.23, 1}
	background_rgba := blend_validation_background(background)
	horizontal_start := alicorn.Color{0.86, 0.16, 0.08, 0.5}
	horizontal_end := alicorn.Color{0.08, 0.34, 0.92, 0.5}
	vertical_start := alicorn.Color{0.08, 0.74, 0.2, 0.6}
	vertical_end := alicorn.Color{0.76, 0.12, 0.4, 0.6}
	for scale in ([4]f32{1, 1.25, 1.5, 2}) {
		horizontal_display := [1]alicorn.Paint_Command{horizontal}
		if !blend_validation_readback(renderers, target, download, horizontal_display[:], scale, background, pixels) {
			fmt.println("surface_gradient_horizontal_readback_failed", "scale", scale, "SDL_error", sdl3.GetError())
			return false
		}
		for logical_x in ([2]int{32, 50}) {
			pixel_x := int(f32(logical_x)*scale)
			pixel_y := int(28*scale)
			t := (f32(pixel_x)+0.5-8*scale)/(48*scale)
			source := blend_validation_gradient_interpolate(horizontal_start, horizontal_end, t)
			if !blend_validation_expect("surface_gradient_horizontal", scale, background, pixels,
				pixel_x, pixel_y, blend_validation_over(background_rgba, source, horizontal.opacity)) {
				fmt.println("surface_gradient_horizontal_sample_failed", "scale", scale, "logical_x", logical_x)
				return false
			}
		}
		if !blend_validation_expect("surface_gradient_clip", scale, background, pixels,
			int(18*scale), int(28*scale), background_rgba) {
			fmt.println("surface_gradient_clip_failed", "scale", scale)
			return false
		}
		stroke_pixel_x := int(32*scale)
		stroke_pixel_y := int(9*scale)
		stroke := alicorn.Color{0.94, 0.78, 0.12, 1}
		// The inside stroke is painted over the gradient fill, so the reference
		// must composite the gradient against the background before the stroke.
		stroke_t := (f32(stroke_pixel_x)+0.5-8*scale)/(48*scale)
		gradient_below_stroke := blend_validation_gradient_interpolate(horizontal_start, horizontal_end, stroke_t)
		under_stroke := blend_validation_over(background_rgba, gradient_below_stroke, horizontal.opacity)
		expected_stroke := blend_validation_over(under_stroke, stroke, horizontal.opacity)
		if !blend_validation_expect("surface_gradient_independent_stroke", scale, background, pixels,
			stroke_pixel_x, stroke_pixel_y, expected_stroke) {
			fmt.println("surface_gradient_independent_stroke_failed", "scale", scale)
			return false
		}

		horizontal_unclipped := horizontal
		horizontal_unclipped.clip = {0, 0, 128, 128}
		horizontal_unclipped_display := [1]alicorn.Paint_Command{horizontal_unclipped}
		if !blend_validation_readback(renderers, target, download, horizontal_unclipped_display[:], scale, background, pixels) {
			fmt.println("surface_gradient_horizontal_unclipped_readback_failed", "scale", scale, "SDL_error", sdl3.GetError())
			return false
		}
		for logical_x in ([3]int{9, 32, 55}) {
			pixel_x := int(f32(logical_x)*scale)
			pixel_y := int(28*scale)
			t := (f32(pixel_x)+0.5-8*scale)/(48*scale)
			source := blend_validation_gradient_interpolate(horizontal_start, horizontal_end, t)
			expected := blend_validation_over(background_rgba, source, horizontal.opacity)
			if logical_x == 9 || logical_x == 55 {
				expected = blend_validation_over(expected, stroke, horizontal.opacity)
			}
			if !blend_validation_expect("surface_gradient_horizontal_stop_and_midpoint", scale, background, pixels,
				pixel_x, pixel_y, expected) {
				fmt.println("surface_gradient_horizontal_stop_or_midpoint_failed", "scale", scale, "logical_x", logical_x)
				return false
			}
		}

		vertical_display := [1]alicorn.Paint_Command{vertical}
		if !blend_validation_readback(renderers, target, download, vertical_display[:], scale, background, pixels) {
			fmt.println("surface_gradient_vertical_readback_failed", "scale", scale, "SDL_error", sdl3.GetError())
			return false
		}
		pixel_x := int(40*scale)
		pixel_y := int(32*scale)
		t := (f32(pixel_y)+0.5-8*scale)/(48*scale)
		source := blend_validation_gradient_interpolate(vertical_start, vertical_end, t)
		if !blend_validation_expect("surface_gradient_vertical", scale, background, pixels,
			pixel_x, pixel_y, blend_validation_over(background_rgba, source, vertical.opacity)) {
			fmt.println("surface_gradient_vertical_sample_failed", "scale", scale)
			return false
		}
		if !blend_validation_expect("surface_gradient_rounded_clip", scale, background, pixels,
			int(40*scale), int(18*scale), background_rgba) {
			fmt.println("surface_gradient_rounded_clip_failed", "scale", scale)
			return false
		}

		unclipped := vertical
		unclipped.clip = {0, 0, 128, 128}
		unclipped_display := [1]alicorn.Paint_Command{unclipped}
		if !blend_validation_readback(renderers, target, download, unclipped_display[:], scale, background, pixels) {
			fmt.println("surface_gradient_rounded_readback_failed", "scale", scale, "SDL_error", sdl3.GetError())
			return false
		}
		for logical_y in ([3]int{9, 32, 55}) {
			pixel_y := int(f32(logical_y)*scale)
			pixel_x := int(40*scale)
			t := (f32(pixel_y)+0.5-8*scale)/(48*scale)
			source := blend_validation_gradient_interpolate(vertical_start, vertical_end, t)
			if !blend_validation_expect("surface_gradient_vertical_stop_and_midpoint", scale, background, pixels,
				pixel_x, pixel_y, blend_validation_over(background_rgba, source, vertical.opacity)) {
				fmt.println("surface_gradient_vertical_stop_or_midpoint_failed", "scale", scale, "logical_y", logical_y)
				return false
			}
		}
		if !blend_validation_expect("surface_gradient_rounded_corner", scale, background, pixels,
			int(16*scale), int(8*scale), background_rgba) {
			fmt.println("surface_gradient_rounded_corner_failed", "scale", scale)
			return false
		}
	}
	fmt.println("surface_gradient_gpu_readback", "scales", "1,1.25,1.5,2", "horizontal_vertical_stops_midpoints", "PASS", "rounded", "PASS", "stroke", "PASS", "clipping", "PASS", "source_over", "PASS")
	return true
}

blend_validation_device :: proc() -> bool {
	driver: cstring = nil
	when ODIN_OS == .Darwin { driver = "metal" }
	when ODIN_OS == .Windows { driver = "direct3d12" }
	device := sdl3.CreateGPUDevice({.DXIL,.MSL,.SPIRV}, false, driver)
	if device == nil {
		fmt.println("blend_gpu_device_failed", "requested_driver", driver, "SDL_error", sdl3.GetError())
		return false
	}
	defer sdl3.DestroyGPUDevice(device)
	fmt.println("blend_gpu_backend", sdl3.GetGPUDeviceDriver(device), "offscreen", true)
	rt := alicorn.new_runtime(alicorn.Rect{0,0,64,64})
	defer alicorn.destroy_runtime(&rt)
	renderers: Blend_Validation_Renderers
	ok := false
	renderers.text, ok = native_text_make(device, .R8G8B8A8_UNORM, &rt)
	defer native_text_destroy(&renderers.text)
	if !ok { return false }
	renderers.geometry, ok = native_surface_make(device, .R8G8B8A8_UNORM, &rt)
	defer native_surface_destroy(&renderers.geometry)
	if !ok { return false }
	renderers.solid, ok = native_solid_make(device, .R8G8B8A8_UNORM, &rt)
	defer native_solid_destroy(&renderers.solid)
	if !ok { return false }
	target := sdl3.CreateGPUTexture(device, sdl3.GPUTextureCreateInfo{
		type=.D2, format=.R8G8B8A8_UNORM, usage={.COLOR_TARGET},
		width=BLEND_VALIDATION_SIZE, height=BLEND_VALIDATION_SIZE, layer_count_or_depth=1, num_levels=1, sample_count=._1,
	})
	if target == nil { return false }
	defer sdl3.ReleaseGPUTexture(device, target)
	download := sdl3.CreateGPUTransferBuffer(device, sdl3.GPUTransferBufferCreateInfo{usage=.DOWNLOAD, size=BLEND_VALIDATION_SIZE*BLEND_VALIDATION_SIZE*4})
	if download == nil { return false }
	defer sdl3.ReleaseGPUTransferBuffer(device, download)
	pixels := make([]u8, BLEND_VALIDATION_SIZE*BLEND_VALIDATION_SIZE*4)
	defer delete(pixels)
	if !blend_validation_cases(&renderers, &rt, target, download, pixels) { return false }
	if !blend_validation_gradient_readbacks(&renderers, &rt, target, download, pixels) { return false }
	if !blend_validation_gradient_gpu_benchmark(&renderers, &rt, target, download, pixels) { return false }
	if !blend_validation_reference_scenes(&renderers, target, download, pixels) { return false }
	return blend_validation_motion_clip_case(&renderers, &rt, target, download, pixels)
}

// Real GPU source-over regression probe; a device/setup failure is never a skip.
RunBlendValidation :: proc() {
	if !sdl3.Init(sdl3.INIT_VIDEO) { fail("blend validation SDL initialization failed") }
	defer sdl3.Quit()
	if !blend_validation_device() { fail("source-over GPU blending validation failed") }
}
