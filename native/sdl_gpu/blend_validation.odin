package alicorn_sdl_gpu

import "core:fmt"
import "core:math"
import alicorn "../../runtime"
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

Blend_Validation_Family :: enum { Surface, Geometry, Icon, Image, Text, Mixed }
Blend_Validation_Stats :: struct {
	cases, failed: int,
	family_cases, family_failed: [Blend_Validation_Family]int,
}

BLEND_VALIDATION_EXPECTED_CASES :: 156

blend_validation_expected_family_cases :: proc(family: Blend_Validation_Family) -> int {
	switch family {
	case .Surface:  return 48
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
		"cases",stats.cases,"expected_cases",BLEND_VALIDATION_EXPECTED_CASES,
		"case_counts_ok",case_counts_ok,"failed",stats.failed,"rgba_tolerance_bytes",2)
	return stats.failed == 0 && case_counts_ok
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
	return blend_validation_cases(&renderers, &rt, target, download, pixels)
}

// Real GPU source-over regression probe; a device/setup failure is never a skip.
RunBlendValidation :: proc() {
	if !sdl3.Init(sdl3.INIT_VIDEO) { fail("blend validation SDL initialization failed") }
	defer sdl3.Quit()
	if !blend_validation_device() { fail("source-over GPU blending validation failed") }
}
