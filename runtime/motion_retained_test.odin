package alicorn

import "core:testing"

motion_retained_test_build :: proc(rt: ^Runtime, include_child: bool) -> (outer, child, sibling: Node_ID) {
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
