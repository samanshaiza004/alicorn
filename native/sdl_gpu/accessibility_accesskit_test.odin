package alicorn_sdl_gpu

import "core:testing"
import "core:c/libc"
import alicorn "../../runtime"
import ak "accesskit:accesskit"

when ODIN_OS == .Windows || ODIN_OS == .Darwin {
@(test)
test_native_accessibility_node_builder_returns_live_owned_node :: proc(t: ^testing.T) {
	node, ok := native_accessibility_build_node(
		Accessibility_Projection_Node{role = .Button, label = "Accessible action"},
		0,
	)
	testing.expect(t, ok && node.raw != nil,
		"the native builder must return a live owned AccessKit node")
	if !ok { return }
	defer ak.node_destroy(&node)

	label := ak.accesskit_node_label(node.raw)
	if label == nil {
		testing.expect(t, false, "the returned node must remain readable after the builder returns")
		return
	}
	defer ak.accesskit_string_free(label)
	testing.expect(t, libc.strcmp(label, cstring("Accessible action")) == 0,
		"the returned node must retain the expected label")
}
}
when ODIN_OS == .Windows || ODIN_OS == .Darwin {
@(test)
test_native_accessibility_exported_bounds_include_host_inset :: proc(t: ^testing.T) {
	source := alicorn.Rect{4, 10, 80, 20}
	without_inset := native_accessibility_bounds(source, 0)
	with_inset := native_accessibility_bounds(source, 8)
	retina := native_accessibility_bounds(source, 8, 2, 2)
	testing.expect(t,
		without_inset.x0 == 4 && without_inset.y0 == 10 && without_inset.x1 == 84 && without_inset.y1 == 30 &&
		with_inset.x0 == 4 && with_inset.y0 == 18 && with_inset.x1 == 84 && with_inset.y1 == 38,
		"host inset must translate exported Y bounds while preserving horizontal position and dimensions")
	testing.expect(t,
		retina.x0 == 8 && retina.y0 == 36 && retina.x1 == 168 && retina.y1 == 76,
		"2x accessibility bounds must be physical pixels after applying the logical host inset")
}
}

@(test)
test_native_accessibility_sync_tracks_host_bounds_geometry :: proc(t: ^testing.T) {
	settled := native_accessibility_sync_plan(
		true, 12, 12,
		20, 20,
	)
	testing.expect(t, !settled.required && !settled.force_snapshot,
		"unchanged semantic and host geometry must stay idle")

	inset_changed := native_accessibility_sync_plan(
		true, 12, 12,
		20, 28,
	)
	testing.expect(t, inset_changed.required && inset_changed.force_snapshot,
		"a host inset change must refresh all exported bounds with a full snapshot")

	settled_after_update := native_accessibility_sync_plan(
		true, 12, 12,
		28, 28,
	)
	testing.expect(t, !settled_after_update.required,
		"once the changed geometry is observed, repeated syncs must return to true idle")
}

@(test)
test_native_accessibility_sync_distinguishes_incremental_and_host_geometry :: proc(t: ^testing.T) {
	semantic_change := native_accessibility_sync_plan(
		true, 12, 13,
		20, 20,
	)
	testing.expect(t, semantic_change.required && !semantic_change.force_snapshot,
		"a new semantic revision can use the existing incremental update path")

	semantic_and_geometry_change := native_accessibility_sync_plan(
		true, 12, 12,
		20, 28,
	)
	testing.expect(t, semantic_and_geometry_change.required && semantic_and_geometry_change.force_snapshot,
		"a host geometry change must force full bounds even with an unchanged semantic revision")

	semantic_change_with_host_current := native_accessibility_sync_plan(
		true, 12, 13,
		20, 20,
	)
	testing.expect(t, semantic_change_with_host_current.required && !semantic_change_with_host_current.force_snapshot,
		"semantic-only updates retain their incremental path regardless of adapter activation")
}

@(test)
test_native_accessibility_sync_refreshes_after_backing_scale_change :: proc(t: ^testing.T) {
	changed := native_accessibility_sync_plan(
		true, 12, 12,
		0, 0,
		1, 1, 2, 2,
	)
	settled := native_accessibility_sync_plan(
		true, 12, 12,
		0, 0,
		2, 2, 2, 2,
	)
	changed_y_only := native_accessibility_sync_plan(
		true, 12, 12,
		0, 0,
		2, 1, 2, 1.5,
	)
	testing.expect(t, changed.required && changed.force_snapshot,
		"backing-scale changes must refresh physical accessibility bounds without semantic changes")
	testing.expect(t, !settled.required && !settled.force_snapshot,
		"a stable backing scale must return to the idle path")
	testing.expect(t, changed_y_only.required && changed_y_only.force_snapshot,
		"per-axis backing-scale changes must be detected independently")
}
