package alicorn

import "core:strings"
import "core:testing"

@(test)
test_visual_part_extension_ids_are_stable_and_namespaced :: proc(t: ^testing.T) {
	first := visual_part_extension_id("app.history", "commit.ref-badge")
	repeat := visual_part_extension_id("app.history", "commit.ref-badge")
	other_namespace := visual_part_extension_id("app.scratchpad", "commit.ref-badge")
	other_name := visual_part_extension_id("app.history", "commit.graph-marker")
	testing.expect(t, visual_part_identity_is_valid(first), "a nonempty namespaced extension ID should be valid")
	testing.expect(t, visual_part_identity_hash(first) == visual_part_identity_hash(repeat),
		"the same namespaced part should retain stable identity across descriptions")
	testing.expect(t, visual_part_identity_hash(first) != visual_part_identity_hash(other_namespace),
		"extension namespaces should distinguish otherwise identical part names")
	testing.expect(t, visual_part_identity_hash(first) != visual_part_identity_hash(other_name),
		"extension part names should distinguish identities within one namespace")
}

@(test)
test_visual_part_requires_descendant_and_inspects_owner_state :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 120})
	defer destroy_runtime(&rt)
	ui, ready := begin_frame(&rt)
	if !ready { return }
	container_begin_simple(&ui, .Root, label="visual-part-test-root", key=key_string("root"), style=layout_style(.Column))
	owner_id, _ := button_begin(&ui, "Owner", key=key_string("owner"), style=layout_style(.Column, width=180, height=72))
	container_begin_simple(&ui, .Container, label="visual-part-content", key=key_string("content"), style=layout_style(.Column, grow=1))
	label_id := text(&ui, "Nested label", key=key_string("label"), style=layout_style(.Row, height=24))
	valid_attachment := visual_part_attach(&ui, label_id, owner_id, visual_part_core(.Label))
	container_end(&ui)
	button_end(&ui)
	unrelated_id := surface_begin(&ui, surface_core_color_role(.Surface), key=key_string("unrelated"), style=layout_style(.Row, width=32, height=24))
	unrelated_attachment := visual_part_attach(&ui, unrelated_id, owner_id, visual_part_core(.Icon))
	surface_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	testing.expect(t, valid_attachment, "a retained child under a Button should accept a visual-part identity")
	testing.expect(t, !unrelated_attachment, "visual-part attachment must reject unrelated retained nodes")
	part, attached := rt.visual_parts[label_id]
	testing.expect(t, attached && part.owner == owner_id,
		"the sidecar should retain the owning interaction control for the part")
	testing.expect(t, visual_part_owner_has_role(&rt, owner_id, .Label),
		"owner role queries should find parts nested below ordinary layout containers")
	lines := inspector_overlay_node_lines(&rt, owner_id, rt.scratch_allocator)
	inspector_reports_part := false
	for line in lines {
		if strings.contains(line, "identity=label") && strings.contains(line, "owner=") && strings.contains(line, "visibility=always") {
			inspector_reports_part = true
		}
	}
	testing.expect(t, inspector_reports_part,
		"the runtime inspector should report each nested part identity, owner component, and visibility policy")
}

@(test)
test_visual_part_static_surface_owner_uses_generic_composition :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 120})
	defer destroy_runtime(&rt)
	ui, ready := begin_frame(&rt)
	if !ready { return }
	container_begin_simple(&ui, .Root, label="static-part-root", key=key_string("root"), style=layout_style(.Column))
	owner_id := surface_begin(
		&ui,
		surface_core_color_role(.Surface),
		key=key_string("ref-badge-surface"),
		style=layout_style(.Row, width=140, height=36, padding=6),
		label="ref-badge",
	)
	label_id := text(&ui, "main", key=key_string("label"), style=layout_style(.Row, width=64, height=24))
	label_attached := visual_part_attach(&ui, label_id, owner_id, visual_part_core(.Label))
	indicator_id := surface_begin(
		&ui,
		surface_core_color_role(.Accent),
		key=key_string("indicator"),
		style=layout_style(.Row, width=6, height=6),
		label="ref-badge-indicator",
	)
	indicator_attached := visual_part_attach(&ui, indicator_id, owner_id, visual_part_core(.Indicator))
	custom_id := surface_begin(
		&ui,
		surface_core_color_role(.Subtle_Surface),
		key=key_string("custom-part"),
		style=layout_style(.Row, width=10, height=10),
		label="ref-badge-custom-mark",
	)
	custom_identity := visual_part_extension_id("app.example", "ref-badge.mark")
	custom_attached := visual_part_attach(&ui, custom_id, owner_id, custom_identity)
	surface_end(&ui)
	surface_end(&ui)
	surface_end(&ui)
	container_end(&ui)
	end_frame(&ui)

	owner, owner_found := rt.nodes[owner_id]
	owner_has_surface_paint := false
	if owner_found {
		for command in owner.paint {
			if _, is_surface := command.payload.(Surface_Paint); is_surface { owner_has_surface_paint = true }
		}
	}
	label_part, label_found := rt.visual_parts[label_id]
	indicator_part, indicator_found := rt.visual_parts[indicator_id]
	custom_part, custom_found := rt.visual_parts[custom_id]
	_, inherits_button_recipe := visual_part_label_color(&rt, label_id)
	lines := inspector_overlay_node_lines(&rt, owner_id, rt.scratch_allocator)
	inspector_reports_indicator := false
	for line in lines {
		if strings.contains(line, "identity=indicator") && strings.contains(line, "visibility=always") {
			inspector_reports_indicator = true
		}
	}
	testing.expect(t, owner_found && owner.kind == .Container && owner_has_surface_paint,
		"the proof owner should be a non-Button retained semantic surface")
	testing.expect(t, label_attached && indicator_attached && custom_attached && label_found && indicator_found && custom_found &&
		label_part.owner == owner_id && indicator_part.owner == owner_id && custom_part.owner == owner_id &&
		custom_part.identity == custom_identity,
		"a retained surface should own core and app-defined parts without a parallel control")
	testing.expect(t, !inherits_button_recipe,
		"a non-Button visual owner should keep its label's own style instead of inheriting Button recipe state")
	testing.expect(t, visual_part_owner_has_role(&rt, owner_id, .Label) &&
		visual_part_owner_has_role(&rt, owner_id, .Indicator) && inspector_reports_indicator,
		"generic role lookup and inspection should expose parts beneath a non-Button owner")
}

@(test)
test_visual_part_non_control_owner_rejects_interaction_visibility :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 100})
	defer destroy_runtime(&rt)
	ui, ready := begin_frame(&rt)
	if !ready { return }
	container_begin_simple(&ui, .Root, label="static-policy-root", key=key_string("root"), style=layout_style(.Column))
	owner_id := surface_begin(&ui, surface_core_color_role(.Surface), key=key_string("owner"), style=layout_style(.Column, width=160, height=60))
	part_id := surface_begin(&ui, surface_core_color_role(.Accent), key=key_string("part"), style=layout_style(.Row, width=12, height=12))
	attached := visual_part_attach(&ui, part_id, owner_id, visual_part_core(.Indicator), .Owner_Hovered)
	surface_end(&ui)
	surface_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	_, retained := rt.visual_parts[part_id]
	testing.expect(t, !attached && !retained,
		"a static surface cannot claim hover-dependent visibility without control hover state")
	testing.expect(t, strings.contains(rt.diagnostic, "non-control owners support Always"),
		"the rejected policy should explain the supported static-owner contract")
}

visual_part_selected_visibility_build :: proc(rt: ^Runtime, owner_selected: bool) -> (owner_id, child_id: Node_ID) {
	ui, ready := begin_frame(rt)
	if !ready { return }
	container_begin_simple(&ui, .Root, label="visual-part-selection-root", key=key_string("root"), style=layout_style(.Column))
	owner_id, _ = button_begin(&ui, "Owner", key=key_string("owner"), style=layout_style(.Column, width=120, height=64),
		state=Button_State{selected=owner_selected})
	child_id, _ = button_begin(&ui, "x", key=key_string("conditional-child"), style=layout_style(.Row, width=40, height=24), focusable=false)
	_ = visual_part_attach(&ui, child_id, owner_id, visual_part_core(.Overlay), .Owner_Selected_Or_Hovered)
	button_end(&ui)
	button_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	return
}

@(test)
test_visual_part_selected_visibility_invalidates_paint_and_hit_testing :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt)
	_ = text_engine_load_font(&rt.text_engine, #load("../assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf"))
	owner, child := visual_part_selected_visibility_build(&rt, false)
	if owner == 0 || child == 0 { return }
	child_bounds := rt.nodes[child].bounds
	x, y := child_bounds.x+child_bounds.w*0.5, child_bounds.y+child_bounds.h*0.5
	_, child_visible := rt.visual_parts[child]
	child_visible = child_visible && visual_part_is_visible(&rt, child)
	child_in_display := false
	for command in rt.display { if command.owner == child { child_in_display = true } }
	initial_hit := hit_test(&rt, x, y)
	initial_ok := !child_visible && !child_in_display && initial_hit != child

	invalidate_root(&rt, "owner selection fixture changed")
	owner_after, child_after := visual_part_selected_visibility_build(&rt, true)
	visible_after := visual_part_is_visible(&rt, child_after)
	child_in_display_after := false
	for command in rt.display { if command.owner == child_after { child_in_display_after = true } }
	after_hit := hit_test(&rt, x, y)
	testing.expect(t, owner_after == owner && child_after == child,
		"owner and conditional child identities should remain stable as selected state changes")
	testing.expect(t, initial_ok,
		"an unselected owner should keep its conditional visual child unpainted and out of hit testing")
	testing.expect(t, visible_after && child_in_display_after && after_hit == child_after,
		"selecting the owner should repaint and activate its selected-dependent visual child")
}
