package alicorn

import "core:testing"

motion_retained_test_build :: proc(
	rt: ^Runtime,
	include_child: bool,
	include_outer_semantic: bool = false,
) -> (outer, child, sibling: Node_ID) {
	ui, ready := begin_frame(rt)
	if !ready { return }
	container_begin_simple(&ui, .Root, key="motion-root", style=layout_style(.Column))
	outer = surface_begin(
		&ui,
		surface_core_color_role(.Surface),
		key="motion-outer",
		style=layout_style(.Column, width=180, height=80),
		fill=Color{0.2, 0.2, 0.2, 1},
	)
	if include_outer_semantic {
		_ = semantic_description(&ui, .Group, "Decorative reveal content")
	}
	if include_child {
		child = surface_begin(
			&ui,
			surface_core_color_role(.Accent),
			key="motion-child",
			style=layout_style(.Row, width=60, height=30),
			fill=Color{0.8, 0.4, 0.2, 1},
		)
		surface_end(&ui)
	}
	surface_end(&ui)
	sibling = surface_begin(
		&ui,
		surface_core_color_role(.Surface),
		key="motion-sibling",
		style=layout_style(.Row, width=40, height=20),
		fill=Color{0.1, 0.4, 0.7, 1},
	)
	surface_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	return
}

motion_retained_test_find_command :: proc(rt: ^Runtime, owner: Node_ID) -> (command: Paint_Command, found: bool) {
	for candidate in rt.display {
		if candidate.owner == owner { return candidate, true }
	}
	return
}

@(test)
test_retained_motion_composes_parent_and_child_without_description_or_layout :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 180})
	defer destroy_runtime(&rt)
	testing.expect(t, rt.motion_owners == nil,
		"ordinary runtimes should not allocate the opt-in retained motion sidecar")
	outer, child, _ := motion_retained_test_build(&rt, true)
	child_target_bounds := rt.nodes[child].hit_bounds
	child_target_clip := rt.nodes[child].clip
	outer_handle, outer_status := motion_owner_begin(&rt, outer)
	child_handle, child_status := motion_owner_begin(&rt, child)
	testing.expect(t, outer_status == .Ok && child_status == .Ok,
		"live retained nodes should acquire generation-checked motion owners")
	if outer_status != .Ok || child_status != .Ok { return }
	config := Motion_Config{omega=12, position_tolerance=0.001, velocity_tolerance=0.001}
	testing.expect(t, motion_target_translation(&rt, outer_handle, Motion_Vector2{10, 5}, config, .Snap, Motion_Time(0)) == .Ok,
		"parent translation should be accepted")
	testing.expect(t, motion_target_translation(&rt, child_handle, Motion_Vector2{2, 3}, config, .Snap, Motion_Time(0)) == .Ok,
		"child translation should be accepted")
	testing.expect(t, motion_target_opacity(&rt, outer_handle, 0.5, config, .Snap, Motion_Time(0)) == .Ok,
		"parent opacity should be accepted")
	testing.expect(t, motion_target_opacity(&rt, child_handle, 0.5, config, .Snap, Motion_Time(0)) == .Ok,
		"child opacity should be accepted")

	before := rt.stats
	ui, ready := begin_presentation_frame(&rt)
	testing.expect(t, ready, "motion target updates should request a retained presentation frame")
	if ready { end_presentation_frame(&ui) }
	parent_command, parent_found := motion_retained_test_find_command(&rt, outer)
	child_command, child_found := motion_retained_test_find_command(&rt, child)
	testing.expect(t, parent_found && parent_command.translation == [2]f32{10, 5} && parent_command.opacity == 0.5,
		"the parent command should consume its local translation and opacity")
	testing.expect(t, child_found && child_command.translation == [2]f32{12, 8} && child_command.opacity == 0.25,
		"child paint should compose parent and child translation and opacity exactly once")
	testing.expect(t, child_found && child_command.clip == child_target_clip && rt.nodes[child].hit_bounds == child_target_bounds,
		"paint translation must preserve logical clips and target hit geometry under the documented static-input policy")
	testing.expect(t, rt.stats.frames_built == before.frames_built &&
		rt.stats.reconcile_nodes_visited == before.reconcile_nodes_visited &&
		rt.stats.measure_nodes_executed == before.measure_nodes_executed &&
		rt.stats.layout_nodes_visited == before.layout_nodes_visited &&
		rt.stats.layout_updates == before.layout_updates,
		"a retained motion frame must not invoke application description, reconciliation, measurement, or layout")
	owner_presentation := motion_presentation(&rt, child_handle)
	testing.expect(t, owner_presentation.status == .Ok && !owner_presentation.active &&
		owner_presentation.target_translation == Motion_Vector2{2, 3} &&
		owner_presentation.presented_translation == [2]f32{2, 3} &&
		owner_presentation.target_opacity == 0.5 && owner_presentation.presented_opacity == 0.5,
		"the typed readback should expose final sampled presentation independently of target geometry")
}

@(test)
test_retained_motion_sidecar_enforces_global_owner_bound :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 220})
	defer destroy_runtime(&rt)
	ui, ready := begin_frame(&rt)
	if !ready { testing.expect(t, false, "fixture should begin an application frame"); return }
	container_begin_simple(&ui, .Root, key="motion-cap-root", style=layout_style(.Column))
	owners: [MOTION_RETAINED_MAX_OWNERS+1]Node_ID
	for index in 0..<MOTION_RETAINED_MAX_OWNERS+1 {
		owners[index] = surface_begin(
			&ui,
			surface_core_color_role(.Surface),
			key=key_u64(u64(index+1)),
			style=layout_style(.Row, width=1, height=1),
		)
		surface_end(&ui)
	}
	container_end(&ui)
	end_frame(&ui)
	last_status := Motion_Runtime_Status.Ok
	first_handle: Motion_Owner_Handle
	for index in 0..<MOTION_RETAINED_MAX_OWNERS+1 {
		handle, status := motion_owner_begin(&rt, owners[index])
		if index == 0 { first_handle = handle }
		if index == MOTION_RETAINED_MAX_OWNERS { last_status = status }
		else { testing.expect(t, status == .Ok, "every owner below the explicit global bound should be accepted") }
	}
	testing.expect(t, last_status == .Owner_Limit && len(rt.motion_owners) == MOTION_RETAINED_MAX_OWNERS,
		"the sparse sidecar should reject excess retained owners without growing unboundedly")
	testing.expect(t, motion_owner_release(&rt, first_handle) == .Ok && rt.nodes[owners[0]].active &&
		len(rt.motion_owners) == MOTION_RETAINED_MAX_OWNERS-1,
		"releasing an owner should free its sidecar slot without retiring the retained node")
	_, replacement_status := motion_owner_begin(&rt, owners[MOTION_RETAINED_MAX_OWNERS])
	testing.expect(t, replacement_status == .Ok && len(rt.motion_owners) == MOTION_RETAINED_MAX_OWNERS &&
		motion_presentation(&rt, first_handle).status == .Stale_Owner,
		"a released slot should be reusable while the old generation remains invalid")
}

@(test)
test_retained_motion_handles_are_isolated_between_runtimes :: proc(t: ^testing.T) {
	rt_a := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt_a)
	rt_b := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt_b)
	_, node_a, _ := motion_retained_test_build(&rt_a, true)
	_, node_b, _ := motion_retained_test_build(&rt_b, true)
	testing.expect(t, node_a == node_b, "independent runtimes should reproduce the same retained Node_ID for this fixture")
	handle_a, status_a := motion_owner_begin(&rt_a, node_a)
	handle_b, status_b := motion_owner_begin(&rt_b, node_b)
	if status_a != .Ok || status_b != .Ok {
		testing.expect(t, false, "both runtimes should register their corresponding live nodes")
		return
	}
	testing.expect(t, handle_a.runtime_identity != 0 && handle_b.runtime_identity != 0 &&
		handle_a.runtime_identity != handle_b.runtime_identity && handle_a.generation == handle_b.generation,
		"runtime lifetime identity should distinguish handles even when node and local generation match")
	config := Motion_Config{omega=10, position_tolerance=0.001, velocity_tolerance=0.001}
	testing.expect(t, motion_target_translation(&rt_a, handle_b, Motion_Vector2{8, 0}, config, .Snap, Motion_Time(0)) == .Stale_Owner &&
		motion_target_translation(&rt_b, handle_a, Motion_Vector2{8, 0}, config, .Snap, Motion_Time(0)) == .Stale_Owner &&
		motion_presentation(&rt_a, handle_b).status == .Stale_Owner && motion_presentation(&rt_b, handle_a).status == .Stale_Owner,
		"neither runtime should accept another runtime's motion handle for the same retained identity")
}

@(test)
test_retained_motion_activity_and_sampling_scale_to_one_thousand_owners :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt)
	response, status := motion_scalar_create(
		1, 0, 0,
		Motion_Config{omega=10, position_tolerance=0.001, velocity_tolerance=0.001},
		Motion_Time(0),
	)
	if status != .Ok { testing.expect(t, false, "the fixture response should be valid"); return }
	rt.motion_owners = make(map[Node_ID]Motion_Retained_Owner, allocator=rt.persistent_allocator)
	for index in 0..<1000 {
		rt.motion_owners[Node_ID(index+1)] = Motion_Retained_Owner{
			generation=u64(index+1),
			has_opacity=true,
			opacity=response,
			presented_opacity=1,
			opacity_active=true,
			opacity_deadline_established=response.deadline_established,
		}
	}
	activity := motion_activity(&rt)
	tick := motion_tick(&rt, Motion_Time(16_666_667))
	testing.expect(t, len(rt.motion_owners) == 1000 && activity.active_owners == 1000 &&
		activity.active_properties == 1000,
		"the bounded sidecar should represent one thousand active owner records")
	testing.expect(t, tick.status == .Ok && tick.active_owners == 1000 && tick.active_properties == 1000,
		"one injected sample should advance all one thousand active records together")
}

@(test)
test_uncertified_motion_can_be_bounded_to_an_exact_target :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt)
	_, child, _ := motion_retained_test_build(&rt, true)
	handle, owner_status := motion_owner_begin(&rt, child)
	if owner_status != .Ok { testing.expect(t, false, "the retained node should acquire a motion owner"); return }
	config := Motion_Config{omega=1e-20, position_tolerance=1e-12, velocity_tolerance=1e-12}
	if motion_target_opacity(&rt, handle, 0.25, config, .Settle, Motion_Time(0)) != .Ok {
		testing.expect(t, false, "the valid but extremely slow response should be accepted")
		return
	}
	activity := motion_activity(&rt)
	testing.expect(t, activity.active_owners == 1 && activity.unestablished_deadlines == 1,
		"an unestablished deadline should remain visible to the host policy")
	bounded := motion_snap_unestablished(&rt, Motion_Time(5_000_000_000))
	presentation := motion_presentation(&rt, handle)
	testing.expect(t, bounded.status == .Ok && bounded.active_owners == 0 &&
		bounded.unestablished_deadlines == 0 && !presentation.active &&
		presentation.presented_opacity == 0.25,
		"bounded retirement should snap only the uncertified response to its exact target")
}

@(test)
test_bounded_uncertified_snap_retires_all_current_window_responses :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt)
	_, first_node, second_node := motion_retained_test_build(&rt, true)
	first_handle, first_status := motion_owner_begin(&rt, first_node)
	second_handle, second_status := motion_owner_begin(&rt, second_node)
	if first_status != .Ok || second_status != .Ok {
		testing.expect(t, false, "both retained nodes should acquire motion owners")
		return
	}
	config := Motion_Config{omega=1e-20, position_tolerance=1e-12, velocity_tolerance=1e-12}
	if motion_target_opacity(&rt, first_handle, 0.25, config, .Settle, Motion_Time(1_000_000_000)) != .Ok {
		testing.expect(t, false, "the first slow response should be accepted")
		return
	}
	if motion_target_opacity(&rt, second_handle, 0.5, config, .Settle, Motion_Time(5_900_000_000)) != .Ok {
		testing.expect(t, false, "a later slow response should be accepted in the same window")
		return
	}
	activity := motion_activity(&rt)
	_ = motion_tick(&rt, Motion_Time(6_000_000_000))
	bounded := motion_snap_unestablished(&rt, Motion_Time(6_000_000_000))
	first := motion_presentation(&rt, first_handle)
	second := motion_presentation(&rt, second_handle)
	testing.expect(t, activity.active_owners == 2 && activity.unestablished_deadlines == 2,
		"both the older and later response should be active when the window budget expires")
	testing.expect(t, bounded.status == .Ok && bounded.active_owners == 0 &&
		!first.active && first.presented_opacity == 0.25 &&
		!second.active && second.presented_opacity == 0.5,
		"the window-wide bounded fallback should snap every currently active uncertified response")
}

@(test)
test_retained_motion_release_resets_presentation_without_retiring_node :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt)
	_, child, _ := motion_retained_test_build(&rt, true)
	handle, status := motion_owner_begin(&rt, child)
	if status != .Ok { testing.expect(t, false, "fixture node should acquire a motion owner"); return }
	config := Motion_Config{omega=10, position_tolerance=0.001, velocity_tolerance=0.001}
	testing.expect(t, motion_target_translation(&rt, handle, Motion_Vector2{12, -3}, config, .Snap, Motion_Time(0)) == .Ok &&
		motion_target_opacity(&rt, handle, 0.4, config, .Snap, Motion_Time(0)) == .Ok,
		"fixture motion should establish a non-neutral presentation")
	ui, ready := begin_presentation_frame(&rt)
	if ready { end_presentation_frame(&ui) }
	command, found := motion_retained_test_find_command(&rt, child)
	testing.expect(t, ready && found && command.translation == [2]f32{12, -3} && command.opacity == 0.4,
		"the fixture should first display its committed motion values")
	testing.expect(t, motion_owner_release(&rt, handle) == .Ok && rt.nodes[child].active && rt.presentation_pending,
		"releasing non-neutral motion should retain the node and request one composition to reset it")
	new_ui, reset_ready := begin_presentation_frame(&rt)
	if reset_ready { end_presentation_frame(&new_ui) }
	reset, reset_found := motion_retained_test_find_command(&rt, child)
	_, record_found := rt.motion_owners[child]
	testing.expect(t, reset_ready && reset_found && reset.translation == [2]f32{} && reset.opacity == 1 && !record_found &&
		motion_owner_release(&rt, handle) == .Stale_Owner,
		"release should reset only the paint presentation, remove the record, and invalidate the old handle")
	new_handle, new_status := motion_owner_begin(&rt, child)
	testing.expect(t, new_status == .Ok && new_handle.generation != handle.generation &&
		new_handle.runtime_identity == handle.runtime_identity,
		"re-registering the still-live node should preserve runtime identity and issue a new owner generation")
}

@(test)
test_retained_motion_samples_and_retires_without_history_dependent_work :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt)
	_, child, _ := motion_retained_test_build(&rt, true)
	handle, status := motion_owner_begin(&rt, child)
	if status != .Ok { testing.expect(t, false, "fixture node should acquire a motion owner"); return }
	config := Motion_Config{omega=18, position_tolerance=0.001, velocity_tolerance=0.001}
	testing.expect(t, motion_target_translation(&rt, handle, Motion_Vector2{30, -4}, config, .Settle, Motion_Time(0)) == .Ok,
		"settling target should initialize from the neutral presentation")
	first := motion_tick(&rt, Motion_Time(100_000_000))
	first_presentation := motion_presentation(&rt, handle)
	testing.expect(t, first.status == .Ok && first.active_properties == 1 && first.active_owners == 1 && first.changed_owners == 1 &&
		first_presentation.active && first_presentation.deadline_established,
		"an injected timestamp should sample active motion and report its bounded retirement deadline")
	deadline := rt.motion_owners[child].translation.x.settle_after_ns
	settled := motion_tick(&rt, Motion_Time(i64(deadline)))
	settled_presentation := motion_presentation(&rt, handle)
	testing.expect(t, settled.status == .Ok && settled.active_properties == 0 && settled.unestablished_deadlines == 0 &&
		settled_presentation.status == .Ok && !settled_presentation.active &&
		settled_presentation.presented_translation == [2]f32{30, -4} &&
		settled_presentation.target_translation == Motion_Vector2{30, -4},
		"at the certified deadline the target is exact and no active motion work remains")
	ui, ready := begin_presentation_frame(&rt)
	if ready { end_presentation_frame(&ui) }
	for opportunity in 0..<5 {
		at := Motion_Time(i64(deadline)+100_000_000+i64(opportunity)*100_000_000)
		unchanged := motion_tick(&rt, at)
		_, ready := begin_presentation_frame(&rt)
		testing.expect(t, unchanged.status == .Ok && unchanged.changed_owners == 0 && unchanged.active_properties == 0 &&
			unchanged.active_owners == 0 && unchanged.unestablished_deadlines == 0 && !rt.presentation_pending && !ready,
			"repeated presentation opportunities after settlement should produce no active motion or scheduled frame")
	}
}

@(test)
test_retained_motion_reports_unestablished_deadlines_for_scheduler_policy :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 180, 80})
	defer destroy_runtime(&rt)
	_, child, _ := motion_retained_test_build(&rt, true)
	handle, status := motion_owner_begin(&rt, child)
	if status != .Ok { testing.expect(t, false, "fixture node should acquire a motion owner"); return }
	config := Motion_Config{omega=1e-20, position_tolerance=1e-12, velocity_tolerance=1e-12}
	testing.expect(t, motion_target_opacity(&rt, handle, 0.5, config, .Settle, Motion_Time(0)) == .Ok,
		"a valid slow response remains usable even when no safe deadline fits the time horizon")
	tick := motion_tick(&rt, Motion_Time(1_000_000_000))
	presentation := motion_presentation(&rt, handle)
	testing.expect(t, tick.status == .Ok && tick.active_properties == 1 && tick.unestablished_deadlines == 1 &&
		presentation.active && !presentation.deadline_established,
		"the retained API must expose unbounded-to-certify motion so a future scheduler can cap it explicitly")
}

@(test)
test_retained_motion_retarget_is_continuous_and_mode_change_is_not_ignored :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 220, 100})
	defer destroy_runtime(&rt)
	_, child, _ := motion_retained_test_build(&rt, true)
	handle, status := motion_owner_begin(&rt, child)
	if status != .Ok { testing.expect(t, false, "fixture node should acquire a motion owner"); return }
	config := Motion_Config{omega=10, position_tolerance=0.001, velocity_tolerance=0.001}
	testing.expect(t, motion_target_translation(&rt, handle, Motion_Vector2{18, 0}, config, .Settle, Motion_Time(0)) == .Ok,
		"first target should begin a settling response from the neutral visual position")
	_ = motion_tick(&rt, Motion_Time(120_000_000))
	before_retarget := motion_presentation(&rt, handle)
	testing.expect(t, motion_target_translation(&rt, handle, Motion_Vector2{28, 4}, config, .Settle, Motion_Time(120_000_000)) == .Ok,
		"a repeated target should rebase from the current sampled response")
	after_retarget := motion_presentation(&rt, handle)
	testing.expect(t, after_retarget.presented_translation == before_retarget.presented_translation && after_retarget.active &&
		after_retarget.target_translation == Motion_Vector2{28, 4},
		"retargeting must preserve presentation while exposing the newly committed target separately")
	testing.expect(t, motion_target_translation(&rt, handle, Motion_Vector2{28, 4}, config, .Snap, Motion_Time(120_000_000)) == .Ok,
		"changing response mode must take effect even when the numeric target is unchanged")
	snapped := motion_presentation(&rt, handle)
	testing.expect(t, snapped.presented_translation == [2]f32{28, 4} && !snapped.active,
		"Snap should immediately commit the target and retire transient motion")
}

@(test)
test_motion_intent_retargets_and_reduce_motion_snaps_midflight :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt)
	_, child, _ := motion_retained_test_build(&rt, true)
	testing.expect(t, motion_clock_set_time(&rt, Motion_Time(0)) == .Ok,
		"the host/test clock should be injectable before a declarative motion request")
	target := Motion_Target{translation=Motion_Vector2{80, 0}, has_translation=true}
	testing.expect(t, motion_apply_intent(&rt, child, target) == .Ok,
		"the small intent API should create and retarget its own retained owner")
	handle, handle_status := motion_owner_begin(&rt, child)
	first := motion_presentation(&rt, handle)
	testing.expect(t, handle_status == .Ok && first.active && first.target_translation == target.translation,
		"a settled target should be visible through the low-level diagnostic query without requiring apps to use it")
	if handle_status != .Ok { return }

	_ = motion_clock_set_time(&rt, Motion_Time(100_000_000))
	second_target := Motion_Target{translation=Motion_Vector2{120, 6}, has_translation=true}
	testing.expect(t, motion_apply_intent(&rt, child, second_target, .Settle) == .Ok,
		"retargeting should preserve sampled position and velocity without an application handle")
	retargeted := motion_presentation(&rt, handle)
	testing.expect(t, retargeted.active && retargeted.target_translation == second_target.translation &&
		retargeted.presented_translation != first.presented_translation,
		"the new target should be committed from the latest sampled presentation")

	if node, found := rt.nodes[child]; found { node.style_environment.accessibility.reduce_motion = true }
	testing.expect(t, motion_apply_intent(&rt, child, second_target, .Settle) == .Ok,
		"the current accessibility motion preference should be reevaluated on each intent declaration")
	reduced := motion_presentation(&rt, handle)
	testing.expect(t, !reduced.active && reduced.presented_translation == [2]f32{120, 6},
		"enabling Reduce Motion during a response should deterministically snap spatial presentation to its target")
	if node, found := rt.nodes[child]; found { node.style_environment.accessibility.reduce_motion = false }
	direct_target := Motion_Target{translation=Motion_Vector2{32, -3}, has_translation=true}
	testing.expect(t, motion_apply_intent(&rt, child, direct_target, .Direct) == .Ok,
		"Direct intent should commit the declared position without residual velocity")
	direct := motion_presentation(&rt, handle)
	testing.expect(t, !direct.active && direct.presented_translation == [2]f32{32, -3},
		"Direct presentation should equal its authoritative target immediately")
	if node, found := rt.nodes[child]; found { node.disabled = true }
	settle_target := Motion_Target{translation=Motion_Vector2{48, 2}, has_translation=true}
	testing.expect(t, motion_apply_intent(&rt, child, settle_target) == .Ok,
		"disabled motion owners should continue to accept target declarations")
	disabled := motion_presentation(&rt, handle)
	testing.expect(t, !disabled.active && disabled.presented_translation == [2]f32{48, 2},
		"disabled owners should snap rather than animate interactive content")
}

@(test)
test_motion_intent_uses_new_theme_policy_without_changing_owner_identity :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt)
	_, child, _ := motion_retained_test_build(&rt, true)
	_ = motion_clock_set_time(&rt, Motion_Time(0))
	target := Motion_Target{translation=Motion_Vector2{75, 0}, has_translation=true}
	testing.expect(t, motion_apply_intent(&rt, child, target) == .Ok,
		"the default theme should support explicit motion intent")
	handle, _ := motion_owner_begin(&rt, child)
	old_state := rt.motion_owners[child]

	theme := DEFAULT_STYLE_THEME
	theme.motion_policy = Motion_Theme_Policy{
		defined=true,
		translation=Motion_Config{omega=7, position_tolerance=0.02, velocity_tolerance=0.04},
		opacity=DEFAULT_MOTION_THEME_POLICY.opacity,
		reduced_motion=.Snap,
		reduced_opacity=DEFAULT_MOTION_THEME_POLICY.reduced_opacity,
	}
	theme_id := style_theme_register(&rt, theme)
	testing.expect(t, theme_id != 0, "a theme may provide its own explicit response policy")
	if node, found := rt.nodes[child]; found { node.style_environment.theme = theme_id }
	_ = motion_clock_set_time(&rt, Motion_Time(50_000_000))
	testing.expect(t, motion_apply_intent(&rt, child, target) == .Ok,
		"the intent helper should re-resolve the current node theme while motion is active")
	new_state := rt.motion_owners[child]
	presentation := motion_presentation(&rt, handle)
	testing.expect(t, presentation.status == .Ok && presentation.active &&
		new_state.generation == old_state.generation &&
		new_state.translation.x.config == theme.motion_policy.translation,
		"theme policy changes should retarget the same owner from its sampled presentation with the new configuration")
}

@(test)
test_reduced_motion_theme_policy_only_allows_opted_in_opacity_fade :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt)
	_, child, _ := motion_retained_test_build(&rt, true)
	theme := DEFAULT_STYLE_THEME
	theme.motion_policy = Motion_Theme_Policy{
		defined=true,
		translation=DEFAULT_MOTION_THEME_POLICY.translation,
		opacity=DEFAULT_MOTION_THEME_POLICY.opacity,
		reduced_motion=.Opacity_Fade,
		reduced_opacity=Motion_Config{omega=100, position_tolerance=0.005, velocity_tolerance=0.02},
	}
	theme_id := style_theme_register(&rt, theme)
	if node, found := rt.nodes[child]; found {
		node.style_environment.theme = theme_id
		node.style_environment.accessibility.reduce_motion = true
	}
	_ = motion_clock_set_time(&rt, Motion_Time(0))
	target := Motion_Target{
		translation=Motion_Vector2{24, 0},
		opacity=0,
		has_translation=true,
		has_opacity=true,
	}
	testing.expect(t, motion_apply_intent(&rt, child, target) == .Ok,
		"a theme may opt into a short opacity transition under reduced motion")
	state := rt.motion_owners[child]
	translation_sample := motion_translation_sample(state.translation, Motion_Time(0))
	opacity_sample := motion_scalar_sample(state.opacity, Motion_Time(0))
	testing.expect(t, translation_sample.status == .Ok && !translation_sample.active &&
		translation_sample.value == target.translation && opacity_sample.status == .Ok && opacity_sample.active &&
		state.opacity.config == theme.motion_policy.reduced_opacity &&
		state.opacity.deadline_established && state.opacity.settle_after_ns <= MOTION_REDUCED_OPACITY_MAX_NS,
		"the reduced-motion policy must snap spatial changes while using only the explicitly configured opacity response")
}

@(test)
test_reduced_motion_opacity_fade_over_250ms_is_snapped_and_explained :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt)
	_, child, _ := motion_retained_test_build(&rt, true)
	theme := DEFAULT_STYLE_THEME
	theme.motion_policy = Motion_Theme_Policy{
		defined=true,
		translation=DEFAULT_MOTION_THEME_POLICY.translation,
		opacity=DEFAULT_MOTION_THEME_POLICY.opacity,
		reduced_motion=.Opacity_Fade,
		reduced_opacity=Motion_Config{omega=1, position_tolerance=0.001, velocity_tolerance=0.001},
	}
	theme_id := style_theme_register(&rt, theme)
	if node, found := rt.nodes[child]; found {
		node.style_environment.theme = theme_id
		node.style_environment.accessibility.reduce_motion = true
	}
	_ = motion_clock_set_time(&rt, Motion_Time(0))
	target := Motion_Target{opacity=0.25, has_opacity=true}
	cause := Cause_Context{id=551, kind=.Keyboard, action_id=Action_ID(5)}
	source := Source_Site{"slow_motion_theme.odin", 44, 9, "toast opacity"}
	testing.expect(t, motion_apply_intent(&rt, child, target, source=source, cause=cause) == .Ok,
		"a theme with a very slow reduced-motion fade should still apply safely")
	handle, handle_status := motion_owner_begin(&rt, child)
	presentation := motion_presentation(&rt, handle)
	event, found_event := motion_diagnostics_event_recent(&rt, 0)
	testing.expect(t, handle_status == .Ok && presentation.status == .Ok && !presentation.active &&
		presentation.presented_opacity == f32(target.opacity) && presentation.target_opacity == target.opacity,
		"a reduced-motion opacity response whose certified bound exceeds 250 ms must snap to the requested target")
	testing.expect(t, found_event && event.kind == .Reduced_Motion_Rewrite &&
		event.reason == .Reduced_Opacity_Fade_Exceeded_Bound && event.owner.source == source && event.owner.cause == cause,
		"the motion trace should explain the reduced-opacity snap and retain its declaration site and cause")
}

@(test)
test_motion_reveal_is_paint_only_and_rejects_interactive_subtrees :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt)
	outer, child, _ := motion_retained_test_build(&rt, true, true)
	_ = motion_clock_set_time(&rt, Motion_Time(0))
	reveal := Motion_Target{
		translation=Motion_Vector2{0, 0}, opacity=1,
		has_translation=true, has_opacity=true,
	}
	status := motion_apply_intent(&rt, outer, reveal, .Reveal, Motion_Vector2{0, 8})
	testing.expect(t, status == .Ok,
		"a decorative container and inert surface descendants may use the paint-only Reveal intent")
	if handle, handle_status := motion_owner_begin(&rt, outer); handle_status == .Ok {
		presentation := motion_presentation(&rt, handle)
		semantic, semantic_found := semantic_node_lookup(&rt, semantic_visual_id(outer))
		testing.expect(t, presentation.active && presentation.presented_opacity == 0 &&
			presentation.presented_translation == [2]f32{0, 8},
			"Reveal should start at its declared hidden/offset presentation and settle toward authoritative layout")
		testing.expect(t, semantic_found && semantic.role == .Group && semantic.label == "Decorative reveal content",
			"Reveal changes paint presentation only; its semantic content is exposed immediately")
	}
	if child_node, found := rt.nodes[child]; found { child_node.kind = .Button }
	_ = motion_clock_set_time(&rt, Motion_Time(20_000_000))
	testing.expect(t, motion_apply_intent(&rt, outer, reveal, .Reveal, Motion_Vector2{0, 8}) == .Interactive_Reveal_Unsupported,
		"Reveal must reject interactive descendants because input and accessibility are ready immediately")
}

@(test)
test_retained_motion_generation_changes_when_node_identity_is_recreated :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 260, 120})
	defer destroy_runtime(&rt)
	_, old_child, _ := motion_retained_test_build(&rt, true)
	old_handle, old_status := motion_owner_begin(&rt, old_child)
	testing.expect(t, old_status == .Ok, "initial retained child should acquire a motion generation")
	if old_status != .Ok { return }
	invalidate_root(&rt, "remove motion test child")
	_, _, _ = motion_retained_test_build(&rt, false)
	_, old_record_retained := rt.motion_owners[old_child]
	testing.expect(t, !old_record_retained && motion_presentation(&rt, old_handle).status == .Stale_Owner,
		"retiring a subtree must retire its motion record and invalidate its handle")
	invalidate_root(&rt, "recreate motion test child")
	_, new_child, _ := motion_retained_test_build(&rt, true)
	new_handle, new_status := motion_owner_begin(&rt, new_child)
	testing.expect(t, new_child == old_child && new_status == .Ok && new_handle.generation != old_handle.generation,
		"recreating the same logical Node_ID must receive a fresh motion generation")
	testing.expect(t, motion_target_opacity(&rt, old_handle, 0.25,
		Motion_Config{omega=8, position_tolerance=0.01, velocity_tolerance=0.01}, .Snap, Motion_Time(0)) == .Stale_Owner,
		"an old owner handle must not mutate a newly created retained node with the same identity")
}

@(test)
test_motion_diagnostics_trace_causal_targets_noop_and_settlement_without_frame_records :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 280, 140}, Runtime_Config{trace_capacity=64})
	defer destroy_runtime(&rt)
	_, child, _ := motion_retained_test_build(&rt, true)
	config := Motion_Config{omega=12, position_tolerance=0.01, velocity_tolerance=0.05}
	target := Motion_Target{translation=Motion_Vector2{40, 4}, has_translation=true}
	first_cause := Cause_Context{id=401, kind=.Pointer, action_id=Action_ID(41)}
	first_source := Source_Site{"fixture.odin", 12, 8, "tab indicator"}
	_ = motion_clock_set_time(&rt, Motion_Time(0))
	testing.expect(t, motion_apply_intent(&rt, child, target, .Settle, source=first_source, cause=first_cause) == .Ok,
		"an accepted target should start a retained response")
	declared, found := motion_diagnostics_event_recent(&rt, 0)
	testing.expect(t, found && declared.kind == .Target_Declared && declared.owner.owner == child &&
		declared.owner.source == first_source && declared.owner.cause == first_cause &&
		declared.owner.translation.target == target.translation && declared.owner.translation.active &&
		declared.owner.translation.deadline_established,
		"the bounded trace should preserve source, cause, target, mode state and settle bound")
	after_seq := rt.motion_diagnostics.sequence
	_ = motion_tick(&rt, Motion_Time(80_000_000))
	second_cause := Cause_Context{id=402, kind=.Keyboard, action_id=Action_ID(42)}
	retarget := Motion_Target{translation=Motion_Vector2{80, 0}, has_translation=true}
	testing.expect(t, motion_apply_intent(&rt, child, retarget, .Settle, source=first_source, cause=second_cause) == .Ok,
		"an interrupted target should retarget from the current analytic presentation")
	latest, retarget_found := motion_diagnostics_event_recent(&rt, 0)
	testing.expect(t, retarget_found && latest.kind == .Retarget && latest.owner.cause == second_cause &&
		latest.owner.translation.target == retarget.translation,
		"the trace should distinguish interruption and carry the new triggering cause")
	change_seq := rt.motion_diagnostics.sequence
	_ = motion_clock_set_time(&rt, Motion_Time(90_000_000))
	testing.expect(t, motion_apply_intent(&rt, child, retarget, .Settle, source=first_source, cause=second_cause) == .Ok,
		"an unchanged target should be a safe no-op")
	noop, noop_found := motion_diagnostics_event_recent(&rt, 0)
	first_noop_seq := rt.motion_diagnostics.sequence
	_ = motion_clock_set_time(&rt, Motion_Time(100_000_000))
	_ = motion_apply_intent(&rt, child, retarget, .Settle, source=first_source, cause=second_cause)
	coalesced, found_coalesced := motion_diagnostics_event_recent(&rt, 0)
	testing.expect(t, noop_found && found_coalesced && noop.kind == .Unchanged_Target &&
		coalesced.sequence == first_noop_seq && coalesced.repeat_count == 2 &&
		rt.motion_diagnostics.sequence == first_noop_seq,
		"repeated no-op declarations should aggregate without a per-frame transition history")
	testing.expect(t, after_seq < change_seq && motion_diagnostics_stats(&rt).unchanged_target_noops == 2,
		"transition sequence and aggregate no-op counts should remain independently observable")
	state := rt.motion_owners[child]
	deadline := Motion_Time(i64(state.translation.x.start_time) + i64(state.translation.x.settle_after_ns))
	settled := motion_tick(&rt, deadline)
	settled_event, found_settled := motion_diagnostics_event_recent(&rt, 0)
	testing.expect(t, settled.status == .Ok && settled.active_owners == 0 && found_settled &&
		settled_event.kind == .Settled && settled_event.owner.translation.presented == retarget.translation,
		"settlement should be one transition event at the deterministic target endpoint")
	stats := motion_diagnostics_stats(&rt)
	testing.expect(t, stats.settlements == 1 && stats.owner_visits > 0 && stats.property_samples > 0,
		"sampling work should be aggregated rather than stored as frame-by-frame events")
}

@(test)
test_motion_diagnostics_report_invalid_ids_and_owner_cap :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 280, 140})
	defer destroy_runtime(&rt)
	_, child, _ := motion_retained_test_build(&rt, true)
	_, invalid_status := motion_owner_begin(&rt, Node_ID(0xfedcba9876543210))
	invalid, invalid_found := motion_diagnostics_event_recent(&rt, 0)
	testing.expect(t, invalid_status == .Owner_Not_Retained && invalid_found &&
		invalid.kind == .Failure && invalid.status == .Owner_Not_Retained,
		"an invalid retained-node identity should be visible in diagnostics")
	delete(rt.motion_owners)
	rt.motion_owners = make(map[Node_ID]Motion_Retained_Owner, allocator=rt.persistent_allocator)
	for index in 0..<MOTION_RETAINED_MAX_OWNERS {
		id := Node_ID(0x100000+u64(index))
		if id == child { id += Node_ID(0x100000000) }
		rt.motion_owners[id] = Motion_Retained_Owner{generation=u64(index+1)}
	}
	_, limit_status := motion_owner_begin(&rt, child)
	limit, limit_found := motion_diagnostics_event_recent(&rt, 0)
	testing.expect(t, limit_status == .Owner_Limit && limit_found && limit.kind == .Failure &&
		limit.status == .Owner_Limit && motion_diagnostics_stats(&rt).failures >= 2,
		"the retained-owner cap should be logged with its explicit failure status")
}

@(test)
test_motion_diagnostic_ring_bounds_events_and_accounts_for_presentation_work :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 280, 140})
	defer destroy_runtime(&rt)
	_, child, _ := motion_retained_test_build(&rt, true)
	_ = motion_clock_set_time(&rt, Motion_Time(0))
	handle, handle_status := motion_owner_begin(&rt, child)
	testing.expect(t, handle_status == .Ok, "the work-count fixture should acquire one retained owner")
	if handle_status != .Ok { return }
	config := Motion_Config{omega=20, position_tolerance=0.01, velocity_tolerance=0.05}
	for index in 0..<MOTION_DIAGNOSTIC_EVENT_CAPACITY+12 {
		x := f64(12) if index%2 == 0 else f64(24)
		testing.expect(t, motion_target_translation(&rt, handle, Motion_Vector2{x, 0}, config, .Snap, Motion_Time(0)) == .Ok,
			"valid snap transitions should enter the bounded event ring")
	}
	stats_before_ack := motion_diagnostics_stats(&rt)
	testing.expect(t, motion_diagnostics_event_count(&rt) == MOTION_DIAGNOSTIC_EVENT_CAPACITY &&
		stats_before_ack.trace_evictions == 12 && stats_before_ack.presentation_requests == u64(MOTION_DIAGNOSTIC_EVENT_CAPACITY+12) &&
		stats_before_ack.presentation_requests_coalesced == u64(MOTION_DIAGNOSTIC_EVENT_CAPACITY+11) &&
		stats_before_ack.presentation_submissions == 0 && rt.motion_frame_pending,
		"transition history should stay bounded while recording coalesced presentation requests before acknowledgement")
	oldest, oldest_found := motion_diagnostics_event_recent(&rt, MOTION_DIAGNOSTIC_EVENT_CAPACITY-1)
	newest, newest_found := motion_diagnostics_event_recent(&rt, 0)
	testing.expect(t, oldest_found && newest_found && oldest.sequence == 13 && newest.sequence == 140,
		"the circular trace should return the bounded sequence in newest-first order")
	frame_submission_succeeded(&rt)
	stats_after_ack := motion_diagnostics_stats(&rt)
	testing.expect(t, !rt.motion_frame_pending && stats_after_ack.presentation_submissions == 1,
		"only successful app-frame acknowledgement should count a motion-associated submission")
	invalid_source := Source_Site{"bad_motion.odin", 9, 3, "test control"}
	invalid_cause := Cause_Context{id=777, kind=.Pointer}
	status := motion_target_opacity(&rt, handle, 0.5,
		Motion_Config{omega=0, position_tolerance=0.01, velocity_tolerance=0.01},
		.Settle, Motion_Time(0), source=invalid_source, cause=invalid_cause)
	failure, failure_found := motion_diagnostics_event_recent(&rt, 0)
	testing.expect(t, status == .Invalid_Configuration && failure_found && failure.kind == .Failure &&
		failure.status == .Invalid_Configuration && failure.owner.source == invalid_source && failure.owner.cause == invalid_cause,
		"invalid response configuration should be diagnosed with its source and cause")
}

@(test)
test_motion_diagnostics_report_opacity_clamp_once_per_excursion :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 280, 140})
	defer destroy_runtime(&rt)
	_, child, _ := motion_retained_test_build(&rt, true)
	_ = motion_clock_set_time(&rt, Motion_Time(0))
	config := Motion_Config{omega=10, position_tolerance=0.001, velocity_tolerance=0.001}
	handle, _ := motion_owner_begin(&rt, child)
	_ = motion_target_opacity(&rt, handle, 0.5, config, .Settle, Motion_Time(0))
	state := rt.motion_owners[child]
	state.opacity.residual_0 = -2
	state.opacity.presented_0 = -1.5
	rt.motion_owners[child] = state
	_ = motion_tick(&rt, Motion_Time(0))
	clamp_event, found := motion_diagnostics_event_recent(&rt, 0)
	_ = motion_tick(&rt, Motion_Time(1_000_000))
	still_one := motion_diagnostics_stats(&rt).opacity_clamps == 1
	testing.expect(t, found && clamp_event.kind == .Opacity_Clamp && clamp_event.detail_value.x < 0 &&
		still_one && rt.motion_owners[child].presented_opacity == 0,
		"alpha clamp diagnostics should record the raw sample once while presentation remains bounded")
}
