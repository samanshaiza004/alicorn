package alicorn

import "core:testing"

NOTICE_TEST_FONT :: #load("../assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf")

notice_test_find_node :: proc(rt: ^Runtime, label: string, kind: Node_Kind = .Container) -> Node_ID {
	for id in rt.order {
		node, ok := rt.nodes[id]
		if ok && node.active && node.label == label && node.kind == kind { return id }
	}
	return 0
}

notice_test_find_text :: proc(rt: ^Runtime, value: string) -> Node_ID {
	for id in rt.order {
		node, ok := rt.nodes[id]
		if ok && node.active && node.kind == .Text && node.text == value { return id }
	}
	return 0
}

notice_test_build :: proc(rt: ^Runtime, add_modal := false, add_context_overlay := false) -> (workspace, notice_root: Node_ID) {
	ui, should_build := begin_frame(rt)
	if !should_build { return }
	container_begin_simple(&ui, .Root, label="notice-test-workspace", key=key_string("notice-test-workspace"), style=layout_style(.Column))
	workspace, _ = button_ex(&ui, "Workspace action", key="workspace-action", style=layout_style(width=180, height=36))
	container_end(&ui)
	if add_modal {
		modal_overlay_begin(&ui, key_string("notice-test-modal"), style=layout_style(.Column, align=.Center))
		container_begin_simple(&ui, .Container, label="notice-test-modal-panel", key=key_string("notice-test-modal-panel"), style=layout_style(.Column, width=300, height=160))
		text(&ui, "Modal dialog")
		container_end(&ui)
		modal_overlay_end(&ui)
	}
	if add_context_overlay {
		container_begin_simple(&ui, .Context_Menu_Overlay, label="notice-test-transient-popup", key=key_string("notice-test-transient-popup"), style=layout_style(.Column, width=180, height=80))
		container_end(&ui)
	}
	end_frame(&ui)
	notice_root = notice_test_find_node(rt, "notice-toast-overlay")
	return
}

@(test)
test_notice_post_deduplicates_and_bounds_queue :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 640, 480})
	defer destroy_runtime(&rt)
	first := Notice{id="workspace-scan", title="Couldn't refresh", message="Folder scan failed.", severity=.Warning, lifetime=.Persistent, placement=.Toast}
	second := Notice{id="theme-save", message="Theme preference could not be saved.", severity=.Error, lifetime=.Transient, placement=.Toast, duration_ms=1_000}
	third := Notice{id="save-error", message="Document could not be saved.", severity=.Error, lifetime=.Persistent, placement=.Contextual, anchor=Node_ID(44)}
	fourth := Notice{id="extra-a", message="A", severity=.Info, lifetime=.Persistent, placement=.Toast}
	fifth := Notice{id="extra-b", message="B", severity=.Success, lifetime=.Persistent, placement=.Toast}

	testing.expect(t, notice_post(&rt, first, 100), "the first notice should be accepted")
	testing.expect(t, notice_post(&rt, second, 100), "a transient notice should be accepted")
	updated := first
	updated.message = "Folder scan failed again."
	testing.expect(t, notice_post(&rt, updated, 200), "posting an existing ID should replace it")
	testing.expect(t, rt.notice_count == 2 && notice_record_message(&rt.notices[0]) == "Folder scan failed again.",
		"deduplication should update the record in place without growing the queue")
	testing.expect(t, notice_next_deadline(&rt) == 1_000_000_100,
		"replacing a different ID should preserve its deadline")
	testing.expect(t, notice_post(&rt, third, 300), "a contextual notice with an anchor should be accepted")
	testing.expect(t, notice_post(&rt, fourth, 400), "the bounded queue should accept its final slot")
	testing.expect(t, rt.notice_count == NOTICE_QUEUE_CAPACITY, "the notice queue must never exceed its fixed capacity")
	testing.expect(t, notice_post(&rt, fifth, 500), "a new record should evict the oldest transient before persistent notices")
	testing.expect(t, rt.notice_count == NOTICE_QUEUE_CAPACITY && notice_find(&rt, "theme-save") < 0 && notice_find(&rt, "workspace-scan") >= 0,
		"overflow should evict the transient without discarding a persistent notice")

	for index in 0..<rt.notice_count { rt.notices[index].lifetime = .Persistent; rt.notices[index].deadline_ns = 0 }
	testing.expect(t, !notice_post(&rt, Notice{id="overflow", message="Overflow", lifetime=.Persistent, placement=.Toast}, 600),
		"when all retained items are persistent, overflow must be rejected rather than silently dropping one")
	bad_anchor := Notice{id="bad-anchor", message="No anchor", lifetime=.Persistent, placement=.Contextual}
	testing.expect(t, !notice_post(&rt, bad_anchor, 700), "contextual notices require an anchor ID")
}

@(test)
test_notice_expiration_uses_one_shot_deadlines_and_returns_to_idle :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 400, 300})
	defer destroy_runtime(&rt)
	transient := Notice{id="transient", message="Saved", severity=.Success, lifetime=.Transient, placement=.Toast, duration_ms=2_000}
	persistent := Notice{id="persistent", message="Still needs attention", severity=.Warning, lifetime=.Persistent, placement=.Toast}
	testing.expect(t, notice_post(&rt, transient, 10_000), "transient notice should post")
	testing.expect(t, notice_post(&rt, persistent, 10_000), "persistent notice should post")
	testing.expect(t, notice_next_deadline(&rt) == 2_000_010_000,
		"the host should receive exactly the next notice expiration deadline")
	testing.expect(t, !notice_advance(&rt, 2_000_009_999) && rt.notice_count == 2,
		"a transient notice must remain before its deadline")
	testing.expect(t, notice_advance(&rt, 2_000_010_000) && rt.notice_count == 1,
		"the due transient should be removed at its deadline")
	testing.expect(t, notice_find(&rt, "persistent") == 0 && notice_next_deadline(&rt) == 0,
		"persistent notices remain with no recurring wake deadline")
	testing.expect(t, !notice_advance(&rt, 9_000_000_000), "an idle queue should do no repeated timer work")

	action_rt := new_runtime(Rect{0, 0, 400, 300})
	defer destroy_runtime(&action_rt)
	actions := [1]Notice_Action{{id=Action_ID(12), label="Retry"}}
	actionable := Notice{id="actionable", message="Folder scan failed", severity=.Warning, lifetime=.Transient, placement=.Toast, duration_ms=1_000, actions=actions[:]}
	testing.expect(t, notice_post(&action_rt, actionable, 10), "an action-bearing notice should post")
	stored_actionable := action_rt.notices[0]
	testing.expect(t, stored_actionable.lifetime == .Persistent && stored_actionable.deadline_ns == 0 && notice_next_deadline(&action_rt) == 0,
		"action-bearing transient requests should be promoted to persistent so the action cannot expire before activation")
	testing.expect(t, !notice_advance(&action_rt, 10_000_000_000) && action_rt.notice_count == 1,
		"an actionable notice must remain available even after its requested transient deadline")
}

@(test)
test_notice_overlay_is_separate_click_through_and_nonfocus_stealing :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 800, 600})
	defer destroy_runtime(&rt)
	if !text_engine_load_font(&rt.text_engine, NOTICE_TEST_FONT) {
		testing.expect(t, false, "notice fixture should load its UI font")
		return
	}
	workspace, _ := notice_test_build(&rt)
	if workspace == 0 { testing.expect(t, false, "workspace button should be retained"); return }
	baseline := rt.nodes[workspace].bounds
	testing.expect(t, focus(&rt, workspace), "the workspace control should accept focus before a notice appears")
	message := Notice{id="overlay-test", title="Folder scan", message="The folder could not be refreshed.", severity=.Warning, lifetime=.Persistent, placement=.Toast}
	testing.expect(t, notice_post(&rt, message, 1), "test notice should post")
	workspace_after, notice_root := notice_test_build(&rt)
	if workspace_after == 0 || notice_root == 0 { testing.expect(t, false, "workspace and separate notice roots should be retained"); return }
	notice_card := notice_test_find_node(&rt, "notice-card")
	notice_semantic, semantic_found := semantic_node_lookup(&rt, semantic_visual_id(notice_card))
	testing.expect(t, semantic_found && notice_semantic.role == .Status && notice_semantic.live == .Polite && notice_semantic.live_atomic,
		"noncritical notices should publish a polite atomic Status announcement")
	testing.expect(t, rt.nodes[workspace_after].bounds == baseline,
		"adding a separate top-level notice must leave workspace geometry unchanged")
	testing.expect(t, rt.focused == workspace_after,
		"describing a notice must not move keyboard focus")
	testing.expect(t, modal_overlay_root(&rt) == 0,
		"a notice overlay must not establish modal input ownership")
	underlying_hit := hit_test(&rt, 20, 20)
	testing.expect(t, underlying_hit == workspace_after,
		"pointer space outside the notice must click through to the workspace")
	close_id := notice_test_find_node(&rt, "×", .Button)
	if close_id != 0 {
		bounds := rt.nodes[close_id].bounds
		testing.expect(t, hit_test(&rt, bounds.x+bounds.w/2, bounds.y+bounds.h/2) == close_id,
			"the close action should have its own retained hit target")
	}
}

@(test)
test_notice_overlay_keeps_record_text_and_distinct_action_labels :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 800, 600})
	defer destroy_runtime(&rt)
	if !text_engine_load_font(&rt.text_engine, NOTICE_TEST_FONT) {
		testing.expect(t, false, "notice fixture should load its UI font")
		return
	}
	actions := [2]Notice_Action{{id=Action_ID(88), label="Details"}, {id=Action_ID(89), label="Retry"}}
	notice := Notice{
		id="scan-failed",
		title="Couldn't refresh folder",
		message="Folder contents may be out of date.",
		severity=.Warning,
		lifetime=.Persistent,
		placement=.Toast,
		actions=actions[:],
	}
	testing.expect(t, notice_post(&rt, notice, 0), "the notice should post")
	_, notice_root := notice_test_build(&rt)
	if notice_root == 0 { testing.expect(t, false, "the toast should be described"); return }
	testing.expect(t, notice_test_find_text(&rt, "Couldn't refresh folder") != 0,
		"the retained title should still reference runtime-owned notice storage")
	testing.expect(t, notice_test_find_text(&rt, "Folder contents may be out of date.") != 0,
		"the retained message should still reference runtime-owned notice storage")
	testing.expect(t, notice_test_find_node(&rt, "Details", .Button) != 0 && notice_test_find_node(&rt, "Retry", .Button) != 0,
		"each action label should remain distinct through end-of-frame reconciliation")
}

@(test)
test_notice_action_is_delivered_and_modal_overlay_suppresses_notice :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 800, 600})
	defer destroy_runtime(&rt)
	if !text_engine_load_font(&rt.text_engine, NOTICE_TEST_FONT) {
		testing.expect(t, false, "notice fixture should load its UI font")
		return
	}
	actions := [1]Notice_Action{{id=Action_ID(77), label="Retry"}}
	notice := Notice{id="retry", title="Couldn't refresh folder", message="Contents may be out of date.", severity=.Warning, lifetime=.Persistent, placement=.Toast, actions=actions[:]}
	testing.expect(t, notice_post(&rt, notice, 0), "actionable notice should post")
	_, notice_root := notice_test_build(&rt)
	if notice_root == 0 { testing.expect(t, false, "toast root should be retained"); return }
	retry_id := notice_test_find_node(&rt, "Retry", .Button)
	if retry_id == 0 { testing.expect(t, false, "Retry should be a retained button"); return }
	retry_bounds := rt.nodes[retry_id].bounds
	x, y := retry_bounds.x+retry_bounds.w/2, retry_bounds.y+retry_bounds.h/2
	_ = process_pointer(&rt, Pointer_Event{kind=.Down, x=x, y=y, button=POINTER_BUTTON_PRIMARY})
	_ = process_pointer(&rt, Pointer_Event{kind=.Up, x=x, y=y, button=POINTER_BUTTON_PRIMARY})
	_, _ = notice_test_build(&rt)
	event, event_found := notice_take_action(&rt)
	testing.expect(t, event_found && event.action == Action_ID(77) && event.notice_id_hash == notice_string_hash("retry"),
		"the app should receive the chosen Action_ID without Alicorn performing the operation")

	modal_rt := new_runtime(Rect{0, 0, 800, 600})
	defer destroy_runtime(&modal_rt)
	if !text_engine_load_font(&modal_rt.text_engine, NOTICE_TEST_FONT) {
		testing.expect(t, false, "modal fixture should load its UI font")
		return
	}
	testing.expect(t, notice_post(&modal_rt, notice, 0), "modal test notice should post")
	_, suppressed_root := notice_test_build(&modal_rt, add_modal=true)
	testing.expect(t, modal_overlay_root(&modal_rt) != 0 && suppressed_root == 0,
		"a modal confirmation should suppress the noncritical notice layer")

	popup_rt := new_runtime(Rect{0, 0, 800, 600})
	defer destroy_runtime(&popup_rt)
	if !text_engine_load_font(&popup_rt.text_engine, NOTICE_TEST_FONT) {
		testing.expect(t, false, "popup fixture should load its UI font")
		return
	}
	testing.expect(t, notice_post(&popup_rt, notice, 0), "popup test notice should post")
	_, popup_suppressed_root := notice_test_build(&popup_rt, add_context_overlay=true)
	testing.expect(t, popup_suppressed_root == 0,
		"a Select or context-menu overlay pending in this frame should take precedence over notices")

	menu_state_rt := new_runtime(Rect{0, 0, 800, 600})
	defer destroy_runtime(&menu_state_rt)
	if !text_engine_load_font(&menu_state_rt.text_engine, NOTICE_TEST_FONT) {
		testing.expect(t, false, "menu-state fixture should load its UI font")
		return
	}
	testing.expect(t, notice_post(&menu_state_rt, notice, 0), "menu-state test notice should post")
	menu_state_rt.context_menu.open = true
	_, open_menu_suppressed_root := notice_test_build(&menu_state_rt)
	testing.expect(t, open_menu_suppressed_root == 0,
		"an open context-menu interaction should suppress notices")
	menu_state_rt.context_menu.dismissed = true
	_, dismissed_menu_suppressed_root := notice_test_build(&menu_state_rt)
	testing.expect(t, dismissed_menu_suppressed_root == 0,
		"a context menu dismissed during this interaction frame should still suppress notices")

	error_rt := new_runtime(Rect{0, 0, 800, 600})
	defer destroy_runtime(&error_rt)
	if !text_engine_load_font(&error_rt.text_engine, NOTICE_TEST_FONT) {
		testing.expect(t, false, "error notice fixture should load its UI font")
		return
	}
	error_notice := Notice{id="urgent-error", message="Save failed.", severity=.Error, lifetime=.Persistent, placement=.Toast}
	testing.expect(t, notice_post(&error_rt, error_notice, 0), "error notice should post")
	_, _ = notice_test_build(&error_rt)
	error_card := notice_test_find_node(&error_rt, "notice-card")
	error_semantic, error_found := semantic_node_lookup(&error_rt, semantic_visual_id(error_card))
	testing.expect(t, error_found && error_semantic.role == .Alert && error_semantic.live == .Assertive,
		"errors requiring attention should publish an assertive Alert announcement")
}
