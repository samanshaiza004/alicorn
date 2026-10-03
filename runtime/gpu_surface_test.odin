package alicorn

import "core:testing"

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
