package main

import "core:testing"
import alicorn "alicorn:runtime"
import mode_rail "./mode_rail"
import testui "alicorn:testui"

Mode :: mode_rail.Mode

third_party_component_test_app :: proc() -> App {
	return App{
		standard=mode_rail.State{selected=.Balanced},
		attention=mode_rail.State{selected=.Urgent},
		custom=mode_rail.State{selected=.Balanced, disabled={true, false, false}},
		recipe=mode_rail.recipe_default(),
		custom_style=mode_rail.Instance_Overrides{
			indicator_role=alicorn.style_extension_color_role_id("app.example", "custom_indicator"),
			container_height=268,
			container_padding=15,
			container_corner_radius=22,
			option_corner_radius=22,
			option_button_height=46,
			indicator_width=34,
			indicator_height=8,
			indicator_corner_radius=4,
			label_size=20,
			detail_size=15,
		},
	}
}

third_party_component_test_open :: proc(app: ^App) -> (handle: testui.Test_Handle(App), status: testui.Status) {
	handle, status = testui.open(
		app,
		width=960,
		height=1100,
		initialize=initialize,
		build_application=build,
	)
	return
}

@(test)
test_third_party_mode_rail_loads_its_shipped_theme_and_preserves_button_semantics :: proc(t: ^testing.T) {
	app := third_party_component_test_app()
	handle, status := third_party_component_test_open(&app)
	defer testui.close(&handle)
	testing.expect(t, status == .Ok && !app.theme_error && app.theme_id != 0,
		"the full production build callback should initialize from the theme JSON embedded beside the component")
	if status != .Ok { return }

	signal, signal_found := alicorn.style_extension_color(handle.runtime, app.theme_id, app.recipe.signal_role)
	custom, custom_found := alicorn.style_extension_color(handle.runtime, app.theme_id, app.custom_style.indicator_role)
	testing.expect(t, signal_found && abs(signal.r-0.05087609) < 0.00001 &&
		abs(signal.g-0.4769998) < 0.00001 && abs(signal.b-0.67385954) < 0.00001 &&
		custom_found && abs(custom.r-0.4769998) < 0.00001 &&
		abs(custom.g-0.19599418) < 0.00001 && abs(custom.b-0.9114075) < 0.00001,
		"the shipped theme should bind the component's required signal and one-off purple instance roles")

	balanced_id := mode_rail.semantic_id_for_instance(11, .Balanced)
	balanced, balanced_found := alicorn.semantic_node_lookup(handle.runtime, balanced_id)
	testing.expect(t, balanced_found && balanced.role == .Button && balanced.label == "Balanced" &&
		balanced.description == "Steady updates with balanced attention." &&
		alicorn.semantic_states_has(balanced.states, .Selected) &&
		alicorn.semantic_actions_has(balanced.actions, .Press),
		"semantic augmentation should add the description while preserving the built-in Button role, selection, and Press action")

	disabled_id := mode_rail.semantic_id_for_instance(33, .Calm)
	disabled, disabled_found := alicorn.semantic_node_lookup(handle.runtime, disabled_id)
	testing.expect(t, disabled_found && alicorn.semantic_states_has(disabled.states, .Disabled) &&
		!alicorn.semantic_actions_has(disabled.actions, .Press),
		"a disabled third-party option should retain native disabled state and suppress Press")
	if disabled_found && disabled.visual_node != 0 {
		testing.expect(t, !alicorn.focus(handle.runtime, disabled.visual_node),
			"the disabled option must not enter keyboard focus")
	}
}

@(test)
test_third_party_mode_rail_focus_and_keyboard_activation_survive_adaptive_resize :: proc(t: ^testing.T) {
	app := third_party_component_test_app()
	handle, status := third_party_component_test_open(&app)
	defer testui.close(&handle)
	testing.expect(t, status == .Ok, "the native application description should open through testui")
	if status != .Ok { return }

	balanced_id := mode_rail.semantic_id_for_instance(11, .Balanced)
	balanced, found := alicorn.semantic_node_lookup(handle.runtime, balanced_id)
	testing.expect(t, found && balanced.visual_node != 0 && alicorn.focus(handle.runtime, balanced.visual_node),
		"the wide Balanced option should receive keyboard focus")
	if !found { return }
	wide_node := balanced.visual_node

	resize_status := testui.resize(&handle, 480, 1100)
	compact, compact_found := alicorn.semantic_node_lookup(handle.runtime, balanced_id)
	testing.expect(t, resize_status == .Ok && compact_found && compact.visual_node != 0 && compact.visual_node != wide_node &&
		alicorn.focused_node(handle.runtime) == compact.visual_node,
		"the same logical choice should retain focus when the compact presentation replaces the wide one")
	if resize_status != .Ok { return }

	resize_status = testui.resize(&handle, 960, 1100)
	wide_again, wide_again_found := alicorn.semantic_node_lookup(handle.runtime, balanced_id)
	testing.expect(t, resize_status == .Ok && wide_again_found && wide_again.visual_node == wide_node &&
		alicorn.focused_node(handle.runtime) == wide_node,
		"returning to the wide presentation should restore the same logical focus identity")

	urgent_id := mode_rail.semantic_id_for_instance(11, .Urgent)
	urgent, urgent_found := alicorn.semantic_node_lookup(handle.runtime, urgent_id)
	if urgent_found && urgent.visual_node != 0 {
		testing.expect(t, alicorn.focus(handle.runtime, urgent.visual_node), "Urgent should accept keyboard focus")
		key_status := testui.step(&handle, testui.Input{kind=.Key, key=.Space})
		testing.expect(t, key_status == .Ok && app.standard.selected == .Urgent,
			"Space should activate the focused option through Alicorn's normal Button keyboard path")
	}
}

@(test)
test_third_party_mode_rail_theme_contract_reports_missing_roles_and_optional_fallbacks :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 400, 240})
	defer alicorn.destroy_runtime(&rt)
	recipe := mode_rail.recipe_default()
	roles := [3]alicorn.Style_Extension_Color_Role_ID{
		recipe.container_role,
		recipe.option_role,
		recipe.signal_role,
	}
	bindings := [3]alicorn.Style_Extension_Color_Role_Binding{}
	colors := [3]alicorn.Color{
		{0.1, 0.1, 0.1, 1},
		{0.2, 0.2, 0.2, 1},
		{0.3, 0.4, 0.5, 1},
	}
	for role, index in roles {
		bindings[index] = alicorn.Style_Extension_Color_Role_Binding{
			role=role,
			token=alicorn.Style_Color_Token_ID(index+1),
		}
	}
	theme := alicorn.DEFAULT_STYLE_THEME
	theme.color_tokens = colors[:]
	theme.extension_color_roles = bindings[:]
	theme_id := alicorn.style_theme_register(&rt, theme)
	contract := mode_rail.theme_contract_default(
		recipe,
		alicorn.style_extension_color_role_id("app.example", "custom_indicator"),
	)
	report := mode_rail.theme_contract_check(&rt, theme_id, contract)
	missing, missing_count := mode_rail.theme_contract_missing_required(contract, report)
	testing.expect(t, theme_id != 0 && mode_rail.theme_contract_satisfied(report) && missing_count == 0 &&
		!report.optional_available[0] && !report.optional_available[1],
		"a theme may omit both optional colors while still satisfying required component roles")
	fallback_recipe := recipe
	fallback_recipe.attention_role = 0
	fallback := mode_rail.option_indicator_role(fallback_recipe, .Attention, true, {})
	testing.expect(t, fallback == recipe.signal_role,
		"an omitted optional attention role should use the required signal role")

	missing_required_theme := theme
	missing_required_theme.extension_color_roles = bindings[:2]
	missing_id := alicorn.style_theme_register(&rt, missing_required_theme)
	missing_report := mode_rail.theme_contract_check(&rt, missing_id, contract)
	missing_names, missing_required_count := mode_rail.theme_contract_missing_required(contract, missing_report)
	testing.expect(t, missing_id != 0 && !mode_rail.theme_contract_satisfied(missing_report) && missing_required_count == 1 &&
		missing_names[0] == "vendor.acme.mode_rail.signal",
		"missing required roles should be named explicitly during setup rather than failing silently during rendering")
}

@(test)
test_third_party_mode_rail_retargets_interruptibly_settles_and_snaps_for_reduced_motion :: proc(t: ^testing.T) {
	app := third_party_component_test_app()
	handle, status := third_party_component_test_open(&app)
	defer testui.close(&handle)
	testing.expect(t, status == .Ok, "the actual app build callback should initialize")
	if status != .Ok { return }

	activity := alicorn.motion_activity(handle.runtime)
	testing.expect(t, activity.active_owners > 0,
		"the selected markers should animate when the component is first presented")

	for target in ([3]Mode{Mode.Calm, Mode.Urgent, Mode.Balanced}) {
		id := mode_rail.semantic_id_for_instance(11, target)
		option, found := alicorn.semantic_node_lookup(handle.runtime, id)
		if !found || !option.has_bounds { testing.expect(t, false, "every active wide option should have hit-testable geometry"); continue }
		status = testui.click_at(&handle, option.bounds.x+option.bounds.w*0.5, option.bounds.y+option.bounds.h*0.5)
		testing.expect(t, status == .Ok && app.standard.selected == target,
			"rapid option changes should update app-owned state without replacing the component recipe")
	}
	activity = alicorn.motion_activity(handle.runtime)
	testing.expect(t, activity.active_owners > 0,
		"rapid retargeting should leave visible markers moving from their current presentation")

	status = testui.advance_time(&handle, 1_000_000_000)
	activity = alicorn.motion_activity(handle.runtime)
	testing.expect(t, status == .Ok && activity.active_owners == 0 && activity.unestablished_deadlines == 0,
		"after enough virtual time the component should settle and return to true idle")
	status = testui.step(&handle, testui.Input{kind=.Time_Advance})
	activity = alicorn.motion_activity(handle.runtime)
	testing.expect(t, status == .Ok && activity.active_owners == 0,
		"re-describing hidden responsive alternatives after settlement must not restart motion or schedule another wake")

	app.test_accessibility = alicorn.Accessibility_Appearance_Preferences{
		increased_contrast=true,
		differentiate_without_color=true,
		reduce_motion=true,
	}
	app.test_accessibility_set = true
	app.test_text_scale = 1.4
	alicorn.invalidate_root(handle.runtime, "exercise component accessibility appearance")
	status = testui.step(&handle, testui.Input{kind=.Time_Advance})
	activity = alicorn.motion_activity(handle.runtime)
	testing.expect(t, status == .Ok && activity.active_owners == 0,
		"reduced motion should snap the custom indicators while increased contrast and text scaling remain valid")
	for mode in Mode {
		option, found := alicorn.semantic_node_lookup(handle.runtime, mode_rail.semantic_id_for_instance(11, mode))
		testing.expect(t, found && option.has_bounds && option.bounds.w > 0 && option.bounds.h > 0,
			"large-text and high-contrast preferences should retain realized, accessible options")
	}

	custom_calm, custom_calm_found := alicorn.semantic_node_lookup(
		handle.runtime,
		mode_rail.semantic_id_for_instance(33, .Calm),
	)
	if custom_calm_found && custom_calm.has_bounds {
		status = testui.click_at(&handle, custom_calm.bounds.x+custom_calm.bounds.w*0.5,
			custom_calm.bounds.y+custom_calm.bounds.h*0.5)
		testing.expect(t, status == .Ok && app.custom.selected == .Balanced,
			"a disabled custom option should remain inoperable after accessibility preference updates")
	}
}
