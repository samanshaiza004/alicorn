package alicorn

import "core:testing"

gpu_surface_retype_test_describe :: proc(rt: ^Runtime, kind: Node_Kind) -> Node_ID {
	invalidate_root(rt, "custom surface retype test")
	ui, build := begin_frame(rt)
	if !build { return 0 }
	container_begin(&ui, .Root, key=key_string("surface-retype-root"), style=layout_style(.Column, width=100, height=80))
	text_value := ""
	if kind == .Text { text_value = "plain text" }
	id := emit_key(
		&ui,
		kind,
		Source_Site{file="gpu_surface_test.odin", line=1},
		label="retyped surface",
		text=text_value,
		key=key_string("surface-retype-node"),
		style=layout_style(.Row, width=40, height=30),
		paint_background=false,
		surface_pixel_width=40,
		surface_pixel_height=30,
	)
	container_end(&ui)
	end_frame(&ui)
	return id
}

@(test)
test_gpu_surface_waveform_sample_limit_is_atomic :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 180})
	defer destroy_runtime(&rt)

	invalidate_root(&rt, "waveform sample limit test")
	ui, should_build := begin_frame(&rt)
	if !should_build {
		testing.expect(t, false, "initial surface tree should build")
		return
	}
	container_begin(&ui, .Root, label="waveform-limit-root")
	surface := gpu_surface(&ui, "waveform-limit-surface", Rect{0, 0, 120, 40}, 120, 40, 1)
	container_end(&ui)
	end_frame(&ui)

	samples := make([]f32, GPU_SURFACE_MAX_WAVEFORM_SAMPLES)
	defer delete(samples)
	for i in 0..<len(samples) { samples[i] = f32(i) / f32(len(samples)) }
	testing.expect(t, gpu_surface_update(&rt, surface, samples),
		"the exact waveform sample limit should be accepted")
	node := rt.nodes[surface]
	testing.expect(t, u64(node.surface_payload_revision) == 1 && len(node.surface_samples) == GPU_SURFACE_MAX_WAVEFORM_SAMPLES,
		"accepted boundary update should retain the full payload and assign a payload revision")
	if len(node.surface_samples) != GPU_SURFACE_MAX_WAVEFORM_SAMPLES { return }
	first_sample := node.surface_samples[0]
	last_sample := node.surface_samples[len(node.surface_samples)-1]
	gpu_surface_frame_consumed(&rt)
	previous_presentation_revision := rt.presentation_revision
	previous_update_count := rt.stats.surface_updates

	oversized := make([]f32, GPU_SURFACE_MAX_WAVEFORM_SAMPLES+1)
	defer delete(oversized)
	for i in 0..<len(oversized) { oversized[i] = 1 }
	testing.expect(t, !gpu_surface_update(&rt, surface, oversized),
		"one sample above the waveform limit should be rejected")
	testing.expect(t,
		u64(node.surface_payload_revision) == 1 && len(node.surface_samples) == GPU_SURFACE_MAX_WAVEFORM_SAMPLES &&
			node.surface_samples[0] == first_sample && node.surface_samples[len(node.surface_samples)-1] == last_sample,
		"rejected update should preserve the previous samples and revision")
	testing.expect(t,
		!rt.surface_frame_pending && rt.presentation_revision == previous_presentation_revision &&
			rt.stats.surface_updates == previous_update_count,
		"rejected update should not queue a frame, advance presentation, or increment updates")
}

@(test)
test_retyping_away_from_custom_surface_discards_image_layers :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 100, 80})
	defer destroy_runtime(&rt)
	encoded := image_asset_test_qoi()
	handle, err := image_load_bytes(&rt, encoded[:])
	if err != .None { testing.expect(t, false, "QOI image fixture should load"); return }
	id := gpu_surface_retype_test_describe(&rt, .Custom_Surface)
	if id == 0 { testing.expect(t, false, "initial custom surface should be retained"); return }
	layer := GPU_Surface_Image{image=handle, bounds=Rect{0,0,10,10}}
	testing.expect(t, gpu_surface_update_images(&rt, id, []GPU_Surface_Image{layer}),
		"a valid image layer should be retained by the custom surface")

	id_after_text := gpu_surface_retype_test_describe(&rt, .Text)
	_, retained_while_text := rt.gpu_surface_images[id]
	testing.expect(t, id_after_text == id && !retained_while_text,
		"changing the same retained identity away from Custom_Surface should release its image layers")

	id_after_surface := gpu_surface_retype_test_describe(&rt, .Custom_Surface)
	presentation, ready := begin_presentation_frame(&rt)
	if ready { end_presentation_frame(&presentation) }
	image_commands := 0
	for command in rt.display {
		if command.owner == id {
			if paint, ok := command.payload.(Image_Paint); ok && paint.image == handle { image_commands += 1 }
		}
	}
	_, retained_after_return := rt.gpu_surface_images[id]
	testing.expect(t, id_after_surface == id && !retained_after_return && image_commands == 0,
		"returning to Custom_Surface should not resurrect image layers from the prior surface kind")
}
