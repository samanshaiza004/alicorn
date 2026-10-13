package alicorn

import "core:testing"

IMAGE_ASSET_TEST_FONT :: #load("../assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf")

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
