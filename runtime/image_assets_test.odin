package alicorn

import "core:testing"
import "core:mem"
import runa "../third_party/Runa"

IMAGE_ASSET_TEST_FONT :: #load("../assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf")
IMAGE_ASSET_TEST_MONO_FONT :: #load("../assets/fonts/AtkinsonHyperlegibleMono-Variable.ttf")

font_test_read_be_u16 :: proc(data: []u8, offset: int) -> u16 {
	return u16(data[offset])<<8 | u16(data[offset+1])
}

font_test_read_be_u32 :: proc(data: []u8, offset: int) -> u32 {
	return u32(data[offset])<<24 | u32(data[offset+1])<<16 | u32(data[offset+2])<<8 | u32(data[offset+3])
}

font_test_write_be_u32 :: proc(data: []u8, offset: int, value: u32) {
	data[offset+0] = u8(value >> 24)
	data[offset+1] = u8(value >> 16)
	data[offset+2] = u8(value >> 8)
	data[offset+3] = u8(value)
}

font_test_adjust_ttc_face_offsets :: proc(data: []u8, face_offset: int) {
	table_count := int(font_test_read_be_u16(data, face_offset+4))
	for i in 0..<table_count {
		record_offset := face_offset + 12 + i*16
		table_offset := font_test_read_be_u32(data, record_offset+8)
		font_test_write_be_u32(data, record_offset+8, table_offset+u32(face_offset))
	}
}

font_test_make_two_face_ttc :: proc(first, second: []u8) -> []u8 {
	first_offset := 20
	second_offset := first_offset + len(first)
	data := make([]u8, second_offset+len(second), context.temp_allocator)
	data[0], data[1], data[2], data[3] = 0x74, 0x74, 0x63, 0x66 // ttcf
	data[5] = 1 // version 1.0
	font_test_write_be_u32(data, 8, 2)
	font_test_write_be_u32(data, 12, u32(first_offset))
	font_test_write_be_u32(data, 16, u32(second_offset))
	copy(data[first_offset:], first)
	copy(data[second_offset:], second)
	font_test_adjust_ttc_face_offsets(data, first_offset)
	font_test_adjust_ttc_face_offsets(data, second_offset)
	return data
}

image_asset_test_qoi :: proc() -> [27]u8 {
	return [27]u8{
		'q','o','i','f', 0,0,0,1, 0,0,0,1, 4,0,
		0xFF, 0x23, 0x78, 0xC1, 0x80,
		0,0,0,0,0,0,0,1,
	}
}

@(test)
test_image_bytes_are_copied_decoded_and_generation_safe :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0,0,80,50})
	defer destroy_runtime(&rt)
	encoded := image_asset_test_qoi()
	handle, err := image_load_bytes(&rt, encoded[:])
	testing.expect(t, err == .None && u64(handle) != 0, "valid QOI bytes should decode into a nonzero Runtime-owned image handle")
	encoded[15] = 0
	view, valid := image_resolve(&rt, handle)
	testing.expect(t, valid && view.width == 1 && view.height == 1 && len(view.rgba8) == 4,
		"decoded image should expose stable RGBA8 pixels after the encoded input changes")
	if len(view.rgba8) == 4 {
		testing.expect(t, view.rgba8[0] == 0x23 && view.rgba8[1] == 0x78 && view.rgba8[2] == 0xC1 && view.rgba8[3] == 0x80,
			"QOI pixels should preserve straight RGBA channels")
	}
	testing.expect(t, image_release(&rt, handle), "a live image resource should release exactly once")
	_, still_valid := image_resolve(&rt, handle)
	testing.expect(t, !still_valid && !image_release(&rt, handle), "released image handles should stay stale")
	if _, err = image_load_bytes(&rt, []u8{1,2,3}); err != .Unsupported_Format {
		testing.expect(t, false, "unsupported image input should have a stable format error")
	}
}

@(test)
test_image_widget_uses_intrinsic_size_and_retained_image_paint :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0,0,80,50})
	defer destroy_runtime(&rt)
	encoded := image_asset_test_qoi()
	handle, err := image_load_bytes(&rt, encoded[:])
	testing.expect(t, err == .None, "QOI fixture should load")
	ui, build := begin_frame(&rt)
	if build {
		container_begin_simple(&ui, .Root, label="image-root", style=layout_style(.Column, -1, -1, padding=0, gap=0))
		id := image(&ui, handle, alt_text="One pixel", key=key_string("fixture-image"), style=layout_style(align=.Start))
		container_end(&ui)
		end_frame(&ui)
		node, found := rt.nodes[id]
		testing.expect(t, found && node != nil && node.kind == .Image && node.bounds.w == 1 && node.bounds.h == 1,
			"omitted image dimensions should use the decoded intrinsic size")
		found_paint := false
		if found && node != nil {
			for command in node.paint {
				if paint, ok := command.payload.(Image_Paint); ok && paint.image == handle { found_paint = true }
			}
		}
		testing.expect(t, found_paint, "image widget should emit a retained image paint payload")
		semantic := false
		for _, candidate in rt.semantic_entities { if candidate.node.label == "One pixel" { semantic = true } }
		testing.expect(t, semantic, "alt text should be represented in the semantic tree")
	} else {
		testing.expect(t, false, "initial image frame should build")
	}
}

@(test)
test_custom_surface_image_layers_are_bounded_retained_and_cleared :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0,0,100,80})
	defer destroy_runtime(&rt)
	encoded := image_asset_test_qoi()
	handle, err := image_load_bytes(&rt, encoded[:])
	if err != .None { testing.expect(t, false, "custom-surface image fixture should decode"); return }
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "custom-surface image fixture should build"); return }
	container_begin(&ui, .Root, key=key_string("surface-image-root"), style=layout_style(.Column, width=100, height=80))
	surface := custom_surface(&ui, "image-layer-surface", Rect{0,0,40,30}, 40, 30, 1)
	container_end(&ui)
	end_frame(&ui)
	layers := [1]GPU_Surface_Image{{image=handle, bounds=Rect{4,6,10,8}, opacity=0.5}}
	testing.expect(t, gpu_surface_update_images(&rt, surface, layers[:]),
		"a live image handle and bounded local rectangle should be accepted for a custom surface")
	layers[0].bounds.x = 99
	retained, found := rt.gpu_surface_images[surface]
	testing.expect(t, found && len(retained) == 1 && retained[0].bounds.x == 4,
		"surface layers should copy descriptors instead of retaining the caller's slice")
	node := rt.nodes[surface]
	revision := node.surface_payload_revision
	invalid := [1]GPU_Surface_Image{{image=Image_Handle(999), bounds=Rect{0,0,1,1}}}
	testing.expect(t, !gpu_surface_update_images(&rt, surface, invalid[:]) && node.surface_payload_revision == revision && len(rt.gpu_surface_images[surface]) == 1,
		"invalid image handles must be rejected atomically without replacing valid layers")
	presentation, ready := begin_presentation_frame(&rt)
	if ready { end_presentation_frame(&presentation) }
	image_commands := 0
	for command in rt.display {
		if paint, image_command := command.payload.(Image_Paint); image_command && command.owner == surface && paint.image == handle {
			image_commands += 1
			testing.expect(t, command.bounds == Rect{4,6,10,8} && command.opacity == 0.5,
				"surface-local image geometry and opacity should resolve into the retained paint stream")
		}
	}
	testing.expect(t, ready && image_commands == 1,
		"updating a surface image layer should schedule retained paint composition")
	testing.expect(t, gpu_surface_clear(&rt, surface), "gpu_surface_clear should clear image layers as part of its payload")
	presentation, ready = begin_presentation_frame(&rt)
	if ready { end_presentation_frame(&presentation) }
	image_commands = 0
	for command in rt.display { if command.owner == surface { if _, ok := command.payload.(Image_Paint); ok { image_commands += 1 } } }
	_, still_retained := rt.gpu_surface_images[surface]
	testing.expect(t, ready && !still_retained && image_commands == 0,
		"clearing a custom surface should remove its retained image references and paint commands")
}

@(test)
test_font_asset_api_copies_input_and_invalidates_typography :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0,0,80,50})
	defer destroy_runtime(&rt)
	input := make([]u8, len(IMAGE_ASSET_TEST_FONT))
	defer delete(input)
	copy(input, IMAGE_ASSET_TEST_FONT)
	loaded := font_load_bytes(&rt, .Monospace, input)
	input[0] = 0
	testing.expect(t, loaded && rt.text_engine.monospace_font_loaded && len(rt.text_engine.monospace_font_data) == len(IMAGE_ASSET_TEST_FONT),
		"font API should install caller bytes and retain an owned copy")
	testing.expect(t, rt.text_engine.monospace_font_data[0] == IMAGE_ASSET_TEST_FONT[0],
		"changing the source buffer must not alter the installed font")
	generation := rt.text_engine.font_generation
	bad := []u8{0,1,2,3}
	testing.expect(t, !font_load_bytes(&rt, .Monospace, bad) && rt.text_engine.font_generation == generation,
		"invalid replacement bytes should leave the last valid face and generation intact")
}

@(test)
test_font_file_registry_copies_deduplicates_and_retains_face :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0,0,80,50})
	defer destroy_runtime(&rt)
	input := make([]u8, len(IMAGE_ASSET_TEST_FONT))
	copy(input, IMAGE_ASSET_TEST_FONT)
	file := font_file_load_bytes(&rt, input)
	input[0] = 0
	duplicate := font_file_load_bytes(&rt, IMAGE_ASSET_TEST_FONT)
	face := font_face_load(&rt, file, 0)
	duplicate_face := font_face_load(&rt, file, 0)
	bad_file := font_file_load_bytes(&rt, []u8{0, 1, 2, 3})
	_, file_lookup_found := rt.text_engine.font_files[file]
	_, invalid_face := rt.text_engine.font_faces[Font_Face_ID(999)]
	testing.expect(t, file != 0 && duplicate == file && text_engine_registered_font_file_count(&rt.text_engine) == 1,
		"equal font inputs should share one Runtime-owned backing file")
	testing.expect(t, face != 0 && duplicate_face == face && text_engine_registered_font_face_count(&rt.text_engine) == 1,
		"re-registering one file face should preserve its stable face identity")
	stored := rt.text_engine.font_files[file]
	testing.expect(t, stored != nil && stored.data[0] == IMAGE_ASSET_TEST_FONT[0] && rt.text_engine.font_file_bytes == len(IMAGE_ASSET_TEST_FONT),
		"the registry should retain an owned byte copy and account unique file bytes once")
	testing.expect(t, font_face_load(&rt, file, 1) == 0 && file_lookup_found && !invalid_face,
		"invalid face indices and unknown face IDs should be rejected without adding entries")
	testing.expect(t, bad_file == 0 && text_engine_registered_font_file_count(&rt.text_engine) == 1,
		"malformed or unsupported font bytes should not occupy the bounded file registry")
	delete(input)
}

@(test)
test_font_registry_loads_distinct_ttc_faces_and_owns_collection_bytes :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0,0,80,50})
	defer destroy_runtime(&rt)
	collection := font_test_make_two_face_ttc(IMAGE_ASSET_TEST_FONT, IMAGE_ASSET_TEST_MONO_FONT)
	file := font_file_load_bytes(&rt, collection)
	delete(collection, context.temp_allocator)
	face0_id := font_face_load(&rt, file, 0)
	face1_id := font_face_load(&rt, file, 1)
	face0, face0_found := text_engine_font_face(&rt.text_engine, face0_id)
	face1, face1_found := text_engine_font_face(&rt.text_engine, face1_id)
	face0_glyph: runa.Glyph_ID
	face1_glyph: runa.Glyph_ID
	if face0_found { face0_glyph = runa.font_lookup_glyph(&face0.font, 'A') }
	if face1_found { face1_glyph = runa.font_lookup_glyph(&face1.font, 'A') }
	_, face0_drawable, face0_ok := text_engine_glyph(&rt.text_engine, face0_glyph, 16, face_id=face0_id)
	_, face1_drawable, face1_ok := text_engine_glyph(&rt.text_engine, face1_glyph, 16, face_id=face1_id)
	testing.expect(t, file != 0 && text_engine_registered_font_file_count(&rt.text_engine) == 1 && text_engine_registered_font_face_count(&rt.text_engine) == 2,
		"a TTC should register one owned file and distinct faces by collection index")
	testing.expect(t, face0_found && face1_found && face0.id != face1.id && face0.face_index == 0 && face1.face_index == 1,
		"collection indices should resolve to stable, distinct face records")
	testing.expect(t, face0_glyph != 0 && face1_glyph != 0 && face0_ok && face1_ok && face0_drawable && face1_drawable,
		"both parsed faces should remain usable for glyph lookup and rasterization after the caller releases the TTC bytes")
	testing.expect(t, len(rt.text_engine.glyphs) == 2,
		"equal glyph IDs from different TTC faces must not alias in the raster cache")
}

@(test)
test_glyph_resource_identity_includes_stable_font_face_id :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0,0,80,50})
	defer destroy_runtime(&rt)
	testing.expect(t, text_engine_load_font(&rt.text_engine, IMAGE_ASSET_TEST_FONT), "primary font should load")
	file := font_file_load_bytes(&rt, #load("../assets/fonts/AtkinsonHyperlegibleMono-Variable.ttf"))
	face_id := font_face_load(&rt, file, 0)
	primary_id := rt.text_engine.primary_face_ids[.UI]
	face, face_found := text_engine_font_face(&rt.text_engine, face_id)
	primary_glyph := runa.font_lookup_glyph(&rt.text_engine.font, 'A')
	secondary_glyph: runa.Glyph_ID
	if face_found { secondary_glyph = runa.font_lookup_glyph(&face.font, 'A') }
	_, primary_drawable, primary_ok := text_engine_glyph(&rt.text_engine, primary_glyph, 16, face_id=primary_id)
	_, secondary_drawable, secondary_ok := text_engine_glyph(&rt.text_engine, secondary_glyph, 16, face_id=face_id)
	testing.expect(t, face_id != 0 && face_id != primary_id && primary_glyph != 0 && secondary_glyph != 0,
		"the registry face and primary face should have independent identities and the shared test glyph")
	testing.expect(t, primary_ok && secondary_ok && primary_drawable && secondary_drawable && len(rt.text_engine.glyphs) == 2,
		"the same glyph index from distinct faces must occupy separate raster-cache entries")
}

@(test)
test_font_fallback_face_refresh_is_targeted_to_unresolved_runs :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0,0,120,60})
	defer destroy_runtime(&rt)
	testing.expect(t, font_load_bytes(&rt, .Monospace, IMAGE_ASSET_TEST_MONO_FONT), "primary font should load")
	testing.expect(t, font_load_bytes(&rt, .UI, IMAGE_ASSET_TEST_FONT), "UI primary font should load")
	latin, latin_ok := text_run_build(&rt.text_engine, "plain Latin text", 16, font_role=.Monospace)
	defer text_run_destroy(&latin)
	missing, missing_ok := text_run_build(&rt.text_engine, "日本語", 16, font_role=.Monospace)
	defer text_run_destroy(&missing)
	ui_missing, ui_missing_ok := text_run_build(&rt.text_engine, "日本語", 16, font_role=.UI)
	defer text_run_destroy(&ui_missing)
	testing.expect(t, latin_ok && latin.font_generation & TEXT_RUN_FALLBACK_GENERATION_MASK == 0,
		"primary-covered Latin text should not depend on future fallback discovery")
	testing.expect(t, missing_ok && missing.font_generation & TEXT_RUN_FALLBACK_GENERATION_MASK != 0,
		"text whose grapheme has no loaded face should record unresolved fallback coverage")
	testing.expect(t, ui_missing_ok && ui_missing.font_generation & TEXT_RUN_FALLBACK_GENERATION_MASK != 0,
		"unresolved UI text should also track UI-role fallback discovery")
	file := font_file_load_bytes(&rt, IMAGE_ASSET_TEST_FONT)
	face := font_face_load(&rt, file, 0)
	ui_generation := rt.text_engine.font_fallback_generation[text_font_role_index(.UI)]
	testing.expect(t, face != 0 && font_face_add_fallback(&rt, .UI, face),
		"a registered face should be addable to the UI role's ordered fallback stack")
	testing.expect(t, rt.text_engine.font_fallback_generation[text_font_role_index(.UI)] > ui_generation &&
		!text_run_fallback_refresh_needed(&latin, &rt.text_engine) &&
		!text_run_fallback_refresh_needed(&missing, &rt.text_engine) &&
		text_run_fallback_refresh_needed(&ui_missing, &rt.text_engine),
		"adding a UI fallback should stale only unresolved UI runs, not Latin or monospace runs")
	testing.expect(t, font_face_add_fallback(&rt, .Monospace, face) &&
		text_run_fallback_refresh_needed(&missing, &rt.text_engine),
		"adding a monospace fallback should stale unresolved monospace runs")
	stack := text_engine_font_stack(&rt.text_engine, .Monospace)
	testing.expect(t, len(stack) == 2 && stack[1] == &rt.text_engine.font_faces[face].font,
		"registered fallback faces should participate after the primary role face")
}

@(test)
test_worker_decoded_image_adoption_transfers_pixels_once :: proc(t: ^testing.T) {
    encoded := image_asset_test_qoi()
    decoded, err := image_decode_bytes(encoded[:], context.allocator, context.temp_allocator)
    testing.expect(t, err == .None && decoded.width == 1, "image should decode without any Runtime")
    if err != .None { return }
    defer image_decoded_destroy(&decoded)
    original := rawptr(&decoded.rgba8[0])
    rt := new_runtime(Rect{0,0,80,50})
    defer destroy_runtime(&rt)
    handle, adopt_error := image_adopt_decoded(&rt, &decoded)
    pixels, live := image_resolve(&rt, handle)
    testing.expect(t, adopt_error == .None && live && rawptr(&pixels.rgba8[0]) == original && decoded.rgba8 == nil,
        "UI adoption should move the worker's buffer without copying or decoding")
    _, duplicate_error := image_adopt_decoded(&rt, &decoded)
    testing.expect(t, duplicate_error != .None, "a consumed decoded buffer must not be adopted twice")
    testing.expect(t, image_release(&rt, handle), "adopted buffer should release using its original allocator")
}

@(test)
test_failed_image_adoption_preserves_worker_ownership :: proc(t: ^testing.T) {
    encoded := image_asset_test_qoi()
    decoded, err := image_decode_bytes(encoded[:])
    if err != .None { testing.expect(t, false, "fixture should decode"); return }
    defer image_decoded_destroy(&decoded)
    _, adopt_error := image_adopt_decoded(nil, &decoded)
    testing.expect(t, adopt_error != .None && len(decoded.rgba8) == 4,
        "failure must leave the buffer available for its worker to destroy")
}

@(test)
test_failed_image_decode_releases_partial_scratch_image :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)

	encoded := image_asset_test_qoi()
	_, err := image_decode_bytes(encoded[:len(encoded)-1], context.allocator, mem.tracking_allocator(&tracking))
	testing.expect(t, err == .Decode_Failed, "truncated QOI data should report a decode failure")
	testing.expect(t, tracking.current_memory_allocated == 0,
		"a failed decoder result must release any partially allocated image and pixels")
}
