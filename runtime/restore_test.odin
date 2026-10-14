package alicorn

import "core:fmt"
import "core:testing"

restore_test_split_describe :: proc(rt: ^Runtime, width: f32, request: Split_Restore_Request) -> Node_ID {
	invalidate_root(rt, "split restore test")
	ui, build := begin_frame(rt)
	if !build { return 0 }
	container_begin(&ui, .Root, key=key_string("restore-split-root"), style=layout_style(.Column, width=width, height=100))
	split := split_begin(
		&ui,
		key=key_string("restore-split"),
		axis=.Horizontal,
		initial=80,
		style=layout_style(.Row, grow=1, clip=true),
		restore=request,
	)
	first := split_first_begin(&ui, split)
	text(&ui, "first", key=key_string("restore-split-first"), style=layout_style(.Row, height=24))
	split_first_end(&ui, split)
	_ = first
	split_divider(&ui, split)
	_ = split_second_begin(&ui, split)
	text(&ui, "second", key=key_string("restore-split-second"), style=layout_style(.Row, height=24))
	split_second_end(&ui, split)
	split_end(&ui, split)
	container_end(&ui)
	end_frame(&ui)
	return split.id
}

restore_test_virtual_list_describe :: proc(rt: ^Runtime, request: Scroll_Restore_Request, include_list := true) -> (owner: Node_ID, first, last: int) {
	invalidate_root(rt, "virtual scroll restore test")
	ui, build := begin_frame(rt)
	if !build { return }
	container_begin(&ui, .Root, key=key_string("restore-scroll-root"), style=layout_style(.Column, width=320, height=320))
	if include_list {
		list := virtual_list_begin(
			&ui,
			500,
			20,
			key=key_string("restore-scroll-list"),
			style=layout_style(.Column, grow=1, clip=true),
			label="restore-scroll-list",
			restore=request,
		)
		owner, first, last = list.scroll.id, list.first, list.last
		for index := first; index < last; index += 1 {
			text(&ui, fmt.tprintf("row %d", index), key=fmt.tprintf("restore-row-%d", index), style=layout_style(.Row, height=20))
		}
		virtual_list_end(&ui, list)
	}
	container_end(&ui)
	end_frame(&ui)
	return
}

restore_test_semantic_describe :: proc(rt: ^Runtime, event: Semantic_ID, place_in_first_owner: bool) -> (first_owner, second_owner: Node_ID) {
	invalidate_root(rt, "semantic restore ownership test")
	ui, build := begin_frame(rt)
	if !build { return }
	container_begin(&ui, .Root, key=key_string("semantic-restore-root"), style=layout_style(.Column, width=320, height=120))
	first_owner = container_begin(&ui, .Container, key=key_string("semantic-restore-owner-a"), style=layout_style(.Column, height=48))
	if place_in_first_owner {
		text(&ui, "target A", key=key_string("semantic-restore-row-a"), style=layout_style(.Row, height=24))
		_ = semantic_bind(&ui, event)
	}
	container_end(&ui)
	second_owner = container_begin(&ui, .Container, key=key_string("semantic-restore-owner-b"), style=layout_style(.Column, height=48))
	if !place_in_first_owner {
		text(&ui, "target B", key=key_string("semantic-restore-row-b"), style=layout_style(.Row, height=24))
		_ = semantic_bind(&ui, event)
	}
	container_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	return
}

restore_test_workspace_describe :: proc(
	rt: ^Runtime,
	initial_split: f32,
	split_request: Split_Restore_Request = {},
	scroll_request: Scroll_Restore_Request = {},
) -> (split_id, scroll_id: Node_ID, first, last: int) {
	invalidate_root(rt, "fresh runtime restore test")
	ui, build := begin_frame(rt)
	if !build { return }
	container_begin(&ui, .Root, key=key_string("fresh-restore-root"), style=layout_style(.Row, width=rt.viewport.w, height=rt.viewport.h))
	split := split_begin(
		&ui,
		key=key_string("fresh-restore-split"),
		axis=.Horizontal,
		initial=initial_split,
		min_second=40,
		style=layout_style(.Row, grow=1, clip=true),
		restore=split_request,
	)
	split_id = split.id
	_ = split_first_begin(&ui, split)
	text(&ui, "sidebar", key=key_string("fresh-restore-sidebar"), style=layout_style(.Row, height=24))
	split_first_end(&ui, split)
	split_divider(&ui, split)
	_ = split_second_begin(&ui, split)
	list := virtual_list_begin(
		&ui,
		500,
		20,
		key=key_string("fresh-restore-list"),
		style=layout_style(.Column, grow=1, clip=true),
		restore=scroll_request,
	)
	scroll_id, first, last = list.scroll.id, list.first, list.last
	for index := first; index < last; index += 1 {
		text(&ui, fmt.tprintf("row %d", index), key=fmt.tprintf("fresh-restore-row-%d", index), style=layout_style(.Row, height=20))
	}
	virtual_list_end(&ui, list)
	split_second_end(&ui, split)
	split_end(&ui, split)
	container_end(&ui)
	end_frame(&ui)
	return
}

@(test)
test_split_restore_keeps_preferred_extent_after_clamp_and_resize :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 182, 100})
	defer destroy_runtime(&rt)
	token := restore_token_next(&rt)
	request := Split_Restore_Request{token=token, preferred_position=300}
	id := restore_test_split_describe(&rt, 182, request)
	state, found := restore_state_query(&rt, .Split, id, token)
	node := rt.nodes[id]
	testing.expect(t, found && state.outcome == .Clamped && state.requested.x == 300 &&
		state.preferred.x == 300 && state.resolved.x == 180,
		"a constrained split restore should report requested, preferred, and resolved extents separately")
	testing.expect(t, node.split_preferred_position == 300 && node.split_position == 180,
		"the narrow viewport should clamp the resolved split without replacing its preference")

	rt.viewport = Rect{0, 0, 302, 100}
	_ = restore_test_split_describe(&rt, 302, request)
	node = rt.nodes[id]
	testing.expect(t, node.split_preferred_position == 300 && node.split_position == 300,
		"a later resize should recover the original split preference without replaying the request")
	state_after_resize, found_after_resize := restore_state_query(&rt, .Split, id, token)
	testing.expect(t, found_after_resize && state_after_resize.outcome == .Clamped && state_after_resize.resolved.x == 180,
		"terminal restore diagnostics should remain an immutable account of the original layout generation")
}

@(test)
test_application_values_restore_into_a_fresh_runtime :: proc(t: ^testing.T) {
	first_runtime := new_runtime(Rect{0, 0, 302, 180})
	_, first_scroll, _, _ := restore_test_workspace_describe(&first_runtime, 260)
	_ = scroll_region_set_offset(&first_runtime, first_scroll, 7000, "save app-owned scroll preference")
	first_split, updated_scroll, _, _ := restore_test_workspace_describe(&first_runtime, 260)
	first_scroll = updated_scroll
	saved_split := first_runtime.nodes[first_split].split_preferred_position
	saved_scroll := scroll_region_state(&first_runtime, first_scroll).offset_y
	testing.expect(t, saved_split == 260 && saved_scroll == 7000,
		"the first Runtime should expose only logical split and scroll values for the application to save")
	destroy_runtime(&first_runtime)

	second_runtime := new_runtime(Rect{0, 0, 182, 180})
	defer destroy_runtime(&second_runtime)
	split_token := restore_token_next(&second_runtime)
	scroll_token := restore_token_next(&second_runtime)
	split_id, scroll_id, first, _ := restore_test_workspace_describe(
		&second_runtime,
		0,
		Split_Restore_Request{token=split_token, preferred_position=saved_split},
		Scroll_Restore_Request{token=scroll_token, offset_y=saved_scroll},
	)
	if second_runtime.invalidated {
		split_id, scroll_id, first, _ = restore_test_workspace_describe(
			&second_runtime,
			0,
			Split_Restore_Request{token=split_token, preferred_position=saved_split},
			Scroll_Restore_Request{token=scroll_token, offset_y=saved_scroll},
		)
	}
	split_state, split_found := restore_state_query(&second_runtime, .Split, split_id, split_token)
	scroll_state, scroll_found := restore_state_query(&second_runtime, .Scroll, scroll_id, scroll_token)
	testing.expect(t, split_found && split_state.outcome == .Clamped &&
		split_state.preferred.x == saved_split && split_state.resolved.x == 140,
		"a fresh narrow Runtime should keep the saved split preference while reporting its current clamp")
	testing.expect(t, scroll_found && scroll_state.outcome == .Applied,
		fmt.tprintf("fresh Runtime scroll result: found=%t outcome=%v reason=%v requested=%.2f resolved=%.2f first=%d viewport=%.2f offset=%.2f",
			scroll_found, scroll_state.outcome, scroll_state.reason, scroll_state.requested.y,
			scroll_state.resolved.y, first, scroll_region_state(&second_runtime, scroll_id).viewport_height,
			scroll_region_state(&second_runtime, scroll_id).offset_y))
	testing.expect(t, first == 350, "the fresh virtual list should begin at the saved logical offset")
	testing.expect(t, scroll_region_state(&second_runtime, scroll_id).offset_y == saved_scroll,
		"the fresh Runtime should retain the saved scroll offset")
}

@(test)
test_restore_rejects_non_finite_values :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 302, 100})
	defer destroy_runtime(&rt)
	nan := transmute(f32)u32(0x7fc00000)
	token := restore_token_next(&rt)
	id := restore_test_split_describe(&rt, 302, Split_Restore_Request{token=token, preferred_position=nan})
	state, found := restore_state_query(&rt, .Split, id, token)
	testing.expect(t, found && state.outcome == .Cancelled && state.reason == .Invalid_Value,
		"non-finite restoration input should terminate as invalid without reaching layout")
	testing.expect(t, rt.nodes[id].split_preferred_position == 80,
		"invalid restoration input should leave the Split's existing initial preference intact")
}

@(test)
test_scroll_user_interaction_supersedes_pending_restore :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 320})
	defer destroy_runtime(&rt)
	token := restore_token_next(&rt)
	request := Scroll_Restore_Request{token=token, offset_y=9900}
	owner, _, _ := restore_test_virtual_list_describe(&rt, request)
	state, found := restore_state_query(&rt, .Scroll, owner, token)
	testing.expect(t, found && state.outcome == .Deferred && state.reason == .Awaiting_Corrective_Description,
		"a virtual range whose estimate differs from final geometry should defer once for correction")
	if !found || state.outcome != .Deferred { return }

	_ = scroll_region_set_offset(&rt, owner, 100, "user moved before restored range settled")
	state, found = restore_state_query(&rt, .Scroll, owner, token)
	testing.expect(t, found && state.outcome == .Cancelled && state.reason == .User_Interaction,
		"a user's scroll input should cancel the pending restoration even before a value is applied")
	_, first, _ := restore_test_virtual_list_describe(&rt, request)
	final := scroll_region_state(&rt, owner)
	testing.expect(t, first == 5 && final.offset_y == 100,
		"a stale request token should not replace the user's scroll position or virtual range")
}

@(test)
test_new_restore_token_supersedes_old_pending_request :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 320})
	defer destroy_runtime(&rt)
	old_token := restore_token_next(&rt)
	owner, _, _ := restore_test_virtual_list_describe(
		&rt,
		Scroll_Restore_Request{token=old_token, offset_y=9900},
	)
	old_state, found := restore_state_query(&rt, .Scroll, owner, old_token)
	testing.expect(t, found && old_state.outcome == .Deferred, "the first request should be pending for its range correction")
	if !found || old_state.outcome != .Deferred { return }

	new_token := restore_token_next(&rt)
	_, _, _ = restore_test_virtual_list_describe(
		&rt,
		Scroll_Restore_Request{token=new_token, offset_y=200},
	)
	terminal_old_state, old_found := restore_state_query(&rt, .Scroll, owner, old_token)
	new_state, new_found := restore_state_query(&rt, .Scroll, owner, new_token)
	testing.expect(t, old_found && terminal_old_state.outcome == .Superseded && terminal_old_state.reason == .Newer_Request,
		"a newer token should complete the older pending request as superseded")
	testing.expect(t, new_found && new_state.outcome == .Applied && new_state.resolved.y == 200,
		"the newer request should resolve independently")
}

@(test)
test_destroyed_restore_target_reports_cancellation :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 320})
	defer destroy_runtime(&rt)
	token := restore_token_next(&rt)
	request := Scroll_Restore_Request{token=token, offset_y=9900}
	owner, _, _ := restore_test_virtual_list_describe(&rt, request)
	state, found := restore_state_query(&rt, .Scroll, owner, token)
	testing.expect(t, found && state.outcome == .Deferred, "the fixture should have a pending correction before retirement")
	if !found || state.outcome != .Deferred { return }
	_, _, _ = restore_test_virtual_list_describe(&rt, request, false)
	state, found = restore_state_query(&rt, .Scroll, owner, token)
	testing.expect(t, found && state.outcome == .Cancelled && state.reason == .Target_Retired,
		"retiring a control with a pending restore should complete it as cancelled")
}

@(test)
test_semantic_restore_stays_with_its_requested_owner :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 120})
	defer destroy_runtime(&rt)
	event := Semantic_ID{namespace=41, value=9001}
	owner_a, owner_b := restore_test_semantic_describe(&rt, event, false)
	token := restore_token_next(&rt)
	keyboard_focus := rt.focused
	testing.expect(t, semantic_focus_restore_request(&rt, event, owner_a, token),
		"semantic restore should accept the application identity and current owner")
	state, found := restore_state_query(&rt, .Semantic_Focus, owner_a, token)
	testing.expect(t, found && state.outcome == .Deferred && state.reason == .Owner_Mismatch,
		"a matching ID under another owner should remain unrealized and report the mismatch")
	testing.expect(t, semantic_focus_state(&rt).realized_node == 0 && rt.focused == keyboard_focus,
		"owner-scoped logical restoration must not bind to another panel or take keyboard focus")

	owner_a_after, owner_b_after := restore_test_semantic_describe(&rt, event, true)
	state, found = restore_state_query(&rt, .Semantic_Focus, owner_a_after, token)
	testing.expect(t, owner_a_after == owner_a && owner_b_after == owner_b && found && state.outcome == .Applied,
		"the request should complete once the same semantic identity is described under its intended owner")
	testing.expect(t, semantic_focus_state(&rt).realized_node != 0 && rt.focused == keyboard_focus,
		"successful logical restoration should remain separate from native keyboard focus")
}
