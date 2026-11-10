package main

import "core:testing"
import alicorn "alicorn:runtime"
import mode_rail "./mode_rail"
import ui "alicorn:ui"

third_party_component_test_theme :: proc(rt: ^alicorn.Runtime) -> alicorn.Style_Theme_ID {
	recipe := mode_rail.recipe_default()
	colors := [4]alicorn.Color{
		{0.1, 0.1, 0.1, 1},
		{0.2, 0.2, 0.2, 1},
		{0.2, 0.7, 0.8, 1},
		{0.9, 0.5, 0.2, 1},
	}
	bindings := [4]alicorn.Style_Extension_Color_Role_Binding{
		{role=recipe.container_role, token=alicorn.Style_Color_Token_ID(1)},
		{role=recipe.option_role, token=alicorn.Style_Color_Token_ID(2)},
		{role=recipe.signal_role, token=alicorn.Style_Color_Token_ID(3)},
		{role=recipe.attention_role, token=alicorn.Style_Color_Token_ID(4)},
	}
	theme := alicorn.DEFAULT_STYLE_THEME
	theme.color_tokens = colors[:]
	theme.extension_color_roles = bindings[:]
	return alicorn.style_theme_register(rt, theme)
}

third_party_component_test_describe :: proc(
	rt: ^alicorn.Runtime,
	theme_id: alicorn.Style_Theme_ID,
	state: ^mode_rail.State,
	second_state: ^mode_rail.State = nil,
) {
	alicorn.invalidate_root(rt, "component test description")
	ctx, ready := alicorn.begin_frame(rt)
	if !ready { return }
	alicorn.container_begin(&ctx, .Root, key="component-test-root",
		style=ui.layout_style(.Column, width=-1, height=-1))
	scope := alicorn.style_environment_push(&ctx, alicorn.Style_Environment{theme=theme_id})
	_ = mode_rail.mode_rail(&ctx, "Test delivery mode", state, mode_rail.recipe_default(), ui.key_u64(91))
	if second_state != nil {
		_ = mode_rail.mode_rail(&ctx, "Test incident mode", second_state, mode_rail.recipe_default(),
			ui.key_u64(92), .Attention)
	}
	alicorn.style_environment_pop(&ctx, scope)
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
}

@(test)
test_third_party_mode_rail_instances_have_independent_identity_and_actions :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 840, 320})
	defer alicorn.destroy_runtime(&rt)
	theme_id := third_party_component_test_theme(&rt)
	first := mode_rail.State{selected=.Calm}
	second := mode_rail.State{selected=.Balanced}
	third_party_component_test_describe(&rt, theme_id, &first, &second)

	snapshot := alicorn.semantic_snapshot(&rt)
	first_group_id := alicorn.Semantic_ID{}
	second_group_id := alicorn.Semantic_ID{}
	first_choices_id := alicorn.Semantic_ID{}
	second_choices_id := alicorn.Semantic_ID{}
	button_count := 0
	selected_count := 0
	urgent_id := alicorn.Semantic_ID{}
	for node in snapshot.nodes {
		if node.role == .Group && node.label == "Test delivery mode" { first_group_id = node.id }
		if node.role == .Group && node.label == "Test incident mode" { second_group_id = node.id }
		if node.role == .Group && node.label == "Horizontal mode choices" {
			if node.parent == first_group_id { first_choices_id = node.id }
			if node.parent == second_group_id { second_choices_id = node.id }
		}
		if node.role == .Button {
			button_count += 1
			if alicorn.semantic_states_has(node.states, .Selected) { selected_count += 1 }
			if node.label == "Urgent" && node.parent == first_choices_id { urgent_id = node.id }
		}
	}
	alicorn.semantic_snapshot_destroy(&snapshot)
	testing.expect(t, alicorn.semantic_id_is_valid(first_group_id) && alicorn.semantic_id_is_valid(second_group_id) &&
		alicorn.semantic_id_is_valid(first_choices_id) && alicorn.semantic_id_is_valid(second_choices_id) &&
		first_group_id != second_group_id &&
		button_count == 6 && selected_count == 2 && urgent_id != (alicorn.Semantic_ID{}),
		"two third-party instances should retain distinct groups and six accessible choices")
	testing.expect(t, alicorn.semantic_action_request(&rt, urgent_id, .Press),
		"the option should accept the same native semantic Press action as a built-in button")
	third_party_component_test_describe(&rt, theme_id, &first, &second)
	testing.expect(t, first.selected == .Urgent && second.selected == .Balanced,
		"activating one instance must update only its application-owned state")
	// The native host performs this bounded corrective description when a
	// component adopts an action during build; model that final stable frame.
	third_party_component_test_describe(&rt, theme_id, &first, &second)

	snapshot = alicorn.semantic_snapshot(&rt)
	selected_count = 0
	first_urgent_selected := false
	second_balanced_selected := false
	for node in snapshot.nodes {
		if node.role != .Button || !alicorn.semantic_states_has(node.states, .Selected) { continue }
		selected_count += 1
		if node.parent == first_choices_id && node.label == "Urgent" { first_urgent_selected = true }
		if node.parent == second_choices_id && node.label == "Balanced" { second_balanced_selected = true }
	}
	alicorn.semantic_snapshot_destroy(&snapshot)
	testing.expect(t, selected_count == 2 && first_urgent_selected && second_balanced_selected,
		"application state changes should publish selected semantics to the correct instance")
}

@(test)
test_third_party_mode_rail_exposes_one_adaptive_semantic_projection_and_interruptible_motion :: proc(t: ^testing.T) {
	wide := alicorn.new_runtime(alicorn.Rect{0, 0, 840, 280})
	defer alicorn.destroy_runtime(&wide)
	wide_theme := third_party_component_test_theme(&wide)
	wide_state := mode_rail.State{selected=.Calm}
	_ = alicorn.motion_clock_set_time(&wide, alicorn.Motion_Time(0))
	third_party_component_test_describe(&wide, wide_theme, &wide_state)
	wide_snapshot := alicorn.semantic_snapshot(&wide)
	wide_layout_found := false
	wide_stack_found := false
	wide_options := 0
	wide_selected := false
	for node in wide_snapshot.nodes {
		wide_layout_found = wide_layout_found || node.label == "Horizontal mode choices"
		wide_stack_found = wide_stack_found || node.label == "Stacked mode choices"
		for label in mode_rail.OPTION_LABELS {
			if node.role == .Button && node.label == label {
				wide_options += 1
				if label == "Calm" { wide_selected = alicorn.semantic_states_has(node.states, .Selected) }
			}
		}
	}
	alicorn.semantic_snapshot_destroy(&wide_snapshot)
	testing.expect(t, wide_layout_found && !wide_stack_found && wide_options == 3 && wide_selected,
		"the wide branch should expose one accessible choice set with the selected option state")

	// Change the application-owned value twice while the retained markers are
	// still moving. The second target must be accepted as a new intent without
	// replacing component state or using a Runtime field.
	_ = alicorn.motion_tick(&wide, alicorn.Motion_Time(28_000_000))
	wide_state.selected = .Balanced
	alicorn.invalidate_root(&wide, "component test retarget one")
	third_party_component_test_describe(&wide, wide_theme, &wide_state)
	_ = alicorn.motion_tick(&wide, alicorn.Motion_Time(42_000_000))
	wide_state.selected = .Urgent
	alicorn.invalidate_root(&wide, "component test retarget two")
	third_party_component_test_describe(&wide, wide_theme, &wide_state)
	activity := alicorn.motion_activity(&wide)
	testing.expect(t, activity.active_owners > 0,
		"rapid state changes should leave the selected marker on an active interruptible presentation")

	compact := alicorn.new_runtime(alicorn.Rect{0, 0, 430, 280})
	defer alicorn.destroy_runtime(&compact)
	compact_theme := third_party_component_test_theme(&compact)
	compact_state := mode_rail.State{selected=.Balanced}
	third_party_component_test_describe(&compact, compact_theme, &compact_state)
	compact_snapshot := alicorn.semantic_snapshot(&compact)
	compact_layout_found := false
	compact_wide_found := false
	compact_options := 0
	for node in compact_snapshot.nodes {
		compact_layout_found = compact_layout_found || node.label == "Stacked mode choices"
		compact_wide_found = compact_wide_found || node.label == "Horizontal mode choices"
		if node.role == .Button && (node.label == "Calm" || node.label == "Balanced" || node.label == "Urgent") {
			compact_options += 1
		}
	}
	alicorn.semantic_snapshot_destroy(&compact_snapshot)
	testing.expect(t, compact_layout_found && !compact_wide_found && compact_options == 3,
		"narrow assigned width should select the compact layout without dropping controls from semantics")
}
