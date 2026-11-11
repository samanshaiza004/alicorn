package main

import "core:testing"
import alicorn "alicorn:runtime"
import segmented "./segmented"
import testui "alicorn:testui"

custom_segmented_test_open :: proc(app: ^App) -> (handle: testui.Test_Handle(App), status: testui.Status) {
	handle, status = testui.open(
		app,
		width=1180,
		height=680,
		initialize=initialize,
		build_application=proc(state: rawptr, rt: ^alicorn.Runtime, _width, _height: int, _scale: f32) -> alicorn.Node_ID {
			app := cast(^App)state
			ctx, should_build := alicorn.begin_frame(rt)
			if !should_build { return 0 }
			root := alicorn.container_begin(&ctx, .Root, key="custom-segmented-test-root",
				style=alicorn.layout_style(.Column, grow=1))
			render_contents(app, &ctx)
			alicorn.container_end(&ctx)
			alicorn.end_frame(&ctx)
			return root
		},
	)
	return
}

@(test)
test_custom_segmented_control_uses_its_theme_and_keeps_native_button_semantics :: proc(t: ^testing.T) {
	app := app_default()
	handle, status := custom_segmented_test_open(&app)
	defer testui.close(&handle)
	testing.expect(t, status == .Ok && app.theme_id != 0 && !app.theme_error,
		"the embedded package theme should satisfy the component's declared extension-role contract")
	if status != .Ok { return }

	accent, accent_found := alicorn.style_extension_color(handle.runtime, app.theme_id, app.recipe.accent_role)
	custom_accent, custom_found := alicorn.style_extension_color(handle.runtime, app.theme_id, app.custom_style.instance_accent_role)
	testing.expect(t, accent_found && custom_found && accent != custom_accent,
		"the second instance should resolve a distinct application-owned accent token without cloning the recipe")

	edit, edit_found := alicorn.semantic_node_lookup(handle.runtime, segmented.semantic_id(101, .Edit))
	compare, compare_found := alicorn.semantic_node_lookup(handle.runtime, segmented.semantic_id(202, .Compare))
	testing.expect(t, edit_found && edit.role == .Button && edit.label == "Edit" &&
		edit.description == "Make changes in the active document." &&
		alicorn.semantic_states_has(edit.states, .Selected) && alicorn.semantic_actions_has(edit.actions, .Press),
		"the custom face should retain Button name, selection and activation semantics while adding its own description")
	testing.expect(t, compare_found && alicorn.semantic_states_has(compare.states, .Disabled) &&
		!alicorn.semantic_actions_has(compare.actions, .Press),
		"a disabled segment should remain explicitly unavailable to assistive technology")
	if edit_found && edit.visual_node != 0 {
		focus_ok := alicorn.focus(handle.runtime, edit.visual_node)
		status = testui.step(&handle, testui.Input{kind=.Time_Advance})
		frame_attached := alicorn.visual_part_owner_has_role(handle.runtime, edit.visual_node, .Overlay)
		face_attached := alicorn.visual_part_owner_has_role(handle.runtime, edit.visual_node, .Surface)
		label_attached := alicorn.visual_part_owner_has_role(handle.runtime, edit.visual_node, .Label)
		testing.expect(t, focus_ok && status == .Ok && alicorn.focused_node(handle.runtime) == edit.visual_node &&
			frame_attached && face_attached && label_attached,
			"custom surfaces and visual parts should provide the focused presentation around the native interaction owner")
	}
}

@(test)
test_custom_segmented_control_keyboard_activation_and_pointer_hit_testing_update_app_state :: proc(t: ^testing.T) {
	app := app_default()
	handle, status := custom_segmented_test_open(&app)
	defer testui.close(&handle)
	testing.expect(t, status == .Ok, "the production build callback should run in testui")
	if status != .Ok { return }

	edit, edit_found := alicorn.semantic_node_lookup(handle.runtime, segmented.semantic_id(101, .Edit))
	compare, compare_found := alicorn.semantic_node_lookup(handle.runtime, segmented.semantic_id(101, .Compare))
	if edit_found && compare_found && edit.visual_node != 0 && compare.visual_node != 0 {
		_ = alicorn.focus(handle.runtime, edit.visual_node)
		status = testui.step(&handle, testui.Input{kind=.Key, key=.Tab})
		testing.expect(t, status == .Ok && alicorn.focused_node(handle.runtime) == compare.visual_node,
			"Tab should traverse to the next custom-drawn segment using Alicorn's Button focus order")
		status = testui.step(&handle, testui.Input{kind=.Key, key=.Space})
		testing.expect(t, status == .Ok && app.primary.selected == .Compare,
			"Space should activate the focused custom-drawn segment through Alicorn's normal Button path")
		// The native ui.run host performs this corrective description after a
		// consumed interaction. Request the same state refresh in this testui app.
		alicorn.invalidate_root(handle.runtime, "verify custom control semantic selection")
		status = testui.step(&handle, testui.Input{kind=.Time_Advance})
		compare_after, compare_after_found := alicorn.semantic_node_lookup(handle.runtime,
			segmented.semantic_id(101, .Compare))
		testing.expect(t, status == .Ok && compare_after_found && alicorn.semantic_states_has(compare_after.states, .Selected),
			"the accessibility tree should publish the application-owned selection after activation")
	}

	preview, preview_found := alicorn.semantic_node_lookup(handle.runtime, segmented.semantic_id(202, .Preview))
	if preview_found && preview.has_bounds {
		app.custom.selected = .Edit
		status = testui.click_at(&handle, preview.bounds.x+preview.bounds.w*0.5, preview.bounds.y+preview.bounds.h*0.5)
		testing.expect(t, status == .Ok && app.custom.selected == .Preview,
			"pointer hit testing should resolve to the hidden-paint Button owner and update only its app-owned selection")
		alicorn.invalidate_root(handle.runtime, "verify custom pointer selection semantics")
		status = testui.step(&handle, testui.Input{kind=.Time_Advance})
		preview_after, preview_after_found := alicorn.semantic_node_lookup(handle.runtime,
			segmented.semantic_id(202, .Preview))
		testing.expect(t, status == .Ok && preview_after_found && alicorn.semantic_states_has(preview_after.states, .Selected),
			"the custom instance should expose its independently updated selection to assistive technology")
	}
	custom_compare, custom_compare_found := alicorn.semantic_node_lookup(handle.runtime, segmented.semantic_id(202, .Compare))
	if custom_compare_found && custom_compare.has_bounds {
		status = testui.click_at(&handle, custom_compare.bounds.x+custom_compare.bounds.w*0.5,
			custom_compare.bounds.y+custom_compare.bounds.h*0.5)
		testing.expect(t, status == .Ok && app.custom.selected == .Preview,
			"the disabled custom segment should reject pointer activation")
	}
}

@(test)
test_custom_segmented_control_preserves_logical_focus_across_responsive_presentations :: proc(t: ^testing.T) {
	app := app_default()
	handle, status := custom_segmented_test_open(&app)
	defer testui.close(&handle)
	if status != .Ok { testing.expect(t, false, "the application should initialize"); return }

	semantic := segmented.semantic_id(101, .Edit)
	wide, found := alicorn.semantic_node_lookup(handle.runtime, semantic)
	if !found || wide.visual_node == 0 { testing.expect(t, false, "wide Edit should have a semantic owner"); return }
	wide_id := wide.visual_node
	_ = alicorn.focus(handle.runtime, wide_id)
	status = testui.resize(&handle, 460, 680)
	compact, compact_found := alicorn.semantic_node_lookup(handle.runtime, semantic)
	testing.expect(t, status == .Ok, "the narrow responsive rebuild should complete")
	testing.expect(t, compact_found && compact.visual_node != 0, "the compact Edit option should remain in the semantic tree")
	testing.expect(t, compact_found && compact.visual_node != wide_id,
		"the narrow width should select a distinct compact Button presentation")
	testing.expect(t, compact_found && alicorn.focused_node(handle.runtime) == compact.visual_node,
		"the compact Button should inherit focus through its stable logical semantic ID")
	if status != .Ok { return }

	status = testui.resize(&handle, 1180, 680)
	wide_again, wide_again_found := alicorn.semantic_node_lookup(handle.runtime, semantic)
	testing.expect(t, status == .Ok && wide_again_found && wide_again.visual_node == wide_id &&
		alicorn.focused_node(handle.runtime) == wide_id,
		"switching back should restore focus to the same retained wide interaction owner")
}

@(test)
test_custom_segmented_control_motion_is_interruptible_and_returns_to_idle :: proc(t: ^testing.T) {
	app := app_default()
	handle, status := custom_segmented_test_open(&app)
	defer testui.close(&handle)
	if status != .Ok { testing.expect(t, false, "the application should initialize"); return }
	activity := alicorn.motion_activity(handle.runtime)
	testing.expect(t, activity.active_owners > 0,
		"the selected custom marker should use retained motion when first presented")

	for target in ([3]segmented.Choice{.Preview, .Compare, .Edit}) {
		option, found := alicorn.semantic_node_lookup(handle.runtime, segmented.semantic_id(101, target))
		if !found || !option.has_bounds { testing.expect(t, false, "each active wide option should have hit-testable geometry"); continue }
		status = testui.click_at(&handle, option.bounds.x+option.bounds.w*0.5, option.bounds.y+option.bounds.h*0.5)
		testing.expect(t, status == .Ok && app.primary.selected == target,
			"rapid pointer retargeting should update the application-owned selection without changing the interaction owner")
	}
	activity = alicorn.motion_activity(handle.runtime)
	testing.expect(t, activity.active_owners > 0, "retargeted custom markers should animate from their current presentation")
	status = testui.advance_time(&handle, 1_000_000_000)
	activity = alicorn.motion_activity(handle.runtime)
	testing.expect(t, status == .Ok && activity.active_owners == 0 && activity.unestablished_deadlines == 0,
		"custom motion should settle with no continuing scheduled work")

	app.accessibility = alicorn.Accessibility_Appearance_Preferences{
		increased_contrast=true,
		differentiate_without_color=true,
		reduce_motion=true,
	}
	app.accessibility_set = true
	app.text_scale = 1.35
	alicorn.invalidate_root(handle.runtime, "custom segmented accessibility appearance")
	status = testui.step(&handle, testui.Input{kind=.Time_Advance})
	activity = alicorn.motion_activity(handle.runtime)
	testing.expect(t, status == .Ok && activity.active_owners == 0,
		"the custom geometry should respect reduced motion and keep accessibility-size labels laid out")
}
