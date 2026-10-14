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
test_notice_emit_stacks_occurrences_while_post_updates_stable_condition :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 640, 480})
	defer destroy_runtime(&rt)
	condition := Notice{id="offline", title="Workspace is offline", message="Reconnect to refresh files.", severity=.Warning, lifetime=.Persistent, placement=.Toast}
	testing.expect(t, notice_post(&rt, condition, 10), "the first stable condition should post")
	stable_handle := rt.notices[0].handle
	condition.message = "Still offline; reconnect to refresh files."
	testing.expect(t, notice_post(&rt, condition, 20), "a repeated stable condition should update")
	testing.expect(t, rt.notice_count == 1 && rt.notices[0].handle == stable_handle &&
		notice_record_message(&rt.notices[0]) == "Still offline; reconnect to refresh files.",
		"stable IDs should deduplicate while retaining their occurrence handle")

	event := Notice{title="Saved", message="Document saved.", severity=.Success, lifetime=.Transient, placement=.Toast, duration_ms=5_000}
	first, first_ok := notice_emit(&rt, event, 30)
	second, second_ok := notice_emit(&rt, event, 40)
	third, third_ok := notice_emit(&rt, event, 50)
	testing.expect(t, first_ok && second_ok && third_ok && first != 0 && second != 0 && third != 0 &&
		first != second && second != third && first != third,
		"notice_emit should assign a distinct handle to every repeated event")
	testing.expect(t, rt.notice_count == 4,
		"identical success events should stack beside a stable persistent condition")
	testing.expect(t, notice_dismiss_handle(&rt, second) && rt.notice_count == 3 &&
		notice_dismiss_handle(&rt, first) && notice_dismiss_handle(&rt, third) && rt.notice_count == 1,
		"a returned handle should dismiss only its own emitted occurrence")
	testing.expect(t, notice_dismiss_handle(&rt, stable_handle) && rt.notice_count == 0,
		"stable notice handles should also identify their retained record")
}

@(test)
test_notice_overlay_displays_independent_events_as_a_nonoverlapping_stack :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 800, 600})
	defer destroy_runtime(&rt)
	if !text_engine_load_font(&rt.text_engine, NOTICE_TEST_FONT) {
		testing.expect(t, false, "notice stack fixture should load its UI font")
		return
	}
	condition := Notice{id="offline", title="Workspace is offline", message="Reconnect to refresh files.", severity=.Warning, lifetime=.Persistent, placement=.Toast}
	testing.expect(t, notice_post(&rt, condition, 1), "the persistent condition should be accepted")
	condition.message = "Still offline; reconnect to refresh files."
	testing.expect(t, notice_post(&rt, condition, 2), "repeating one condition should update it")
	for _ in 0..<3 {
		_, accepted := notice_emit(&rt, Notice{title="Saved", message="Document saved.", severity=.Success, lifetime=.Transient, placement=.Toast}, 3)
		testing.expect(t, accepted, "each independent success should be retained as its own event")
	}
	_, notice_root := notice_test_build(&rt)
	if notice_root == 0 { testing.expect(t, false, "the notice stack should be rendered"); return }
	cards: [NOTICE_QUEUE_CAPACITY]Rect
	card_count := 0
	for id in rt.order {
		node, ok := rt.nodes[id]
		if !ok || !node.active || node.kind != .Container || node.label != "notice-card" { continue }
		if card_count < len(cards) { cards[card_count] = node.bounds }
		card_count += 1
	}
	testing.expect(t, card_count == 4,
		"one stable condition plus three independent events should render four retained cards")
	for first in 0..<min(card_count, len(cards)) {
		for second in first+1..<min(card_count, len(cards)) {
			overlap := rect_intersection(cards[first], cards[second])
			testing.expect(t, overlap.w <= 0 || overlap.h <= 0,
				"separate notice cards should occupy distinct, non-overlapping positions")
		}
	}
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
test_notice_style_environment_uses_theme_and_repaints_without_layout :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 800, 600})
	defer destroy_runtime(&rt)
	if !text_engine_load_font(&rt.text_engine, NOTICE_TEST_FONT) {
		testing.expect(t, false, "notice theme fixture should load its UI font")
		return
	}
	first_theme := DEFAULT_STYLE_THEME
	first_theme.colors[int(Style_Color_Role.Surface)] = Color{0.82, 0.9, 0.98, 1}
	first_theme.colors[int(Style_Color_Role.Subtle_Surface)] = Color{0.72, 0.84, 0.94, 1}
	first_theme.colors[int(Style_Color_Role.Text)] = Color{0.04, 0.08, 0.15, 1}
	first_theme.colors[int(Style_Color_Role.Danger)] = Color{0.68, 0.12, 0.16, 1}
	first_theme_id := style_theme_register(&rt, first_theme)
	second_theme := DEFAULT_STYLE_THEME
	second_theme.colors[int(Style_Color_Role.Surface)] = Color{0.94, 0.95, 0.88, 1}
	second_theme.colors[int(Style_Color_Role.Subtle_Surface)] = Color{0.86, 0.89, 0.73, 1}
	second_theme.colors[int(Style_Color_Role.Text)] = Color{0.12, 0.14, 0.04, 1}
	second_theme.colors[int(Style_Color_Role.Danger)] = Color{0.52, 0.22, 0.04, 1}
	second_theme_id := style_theme_register(&rt, second_theme)
	testing.expect(t, first_theme_id != 0 && second_theme_id != 0,
		"both notice themes should register")
	if first_theme_id == 0 || second_theme_id == 0 { return }

	notice := Notice{
		id="themed-error",
		title="Operation needs attention",
		message="The requested operation could not finish.",
		severity=.Error,
		lifetime=.Persistent,
		placement=.Toast,
		style_environment=Style_Environment{theme=first_theme_id},
	}
	testing.expect(t, notice_post(&rt, notice, 1), "a notice with a registered style environment should post")
	stored := &rt.notices[0]
	testing.expect(t, stored.style_environment_set && stored.style_environment.theme == first_theme_id,
		"the notice record should retain its validated style environment")
	_, first_root := notice_test_build(&rt)
	if first_root == 0 { testing.expect(t, false, "the themed toast should render"); return }
	card_id := notice_test_find_node(&rt, "notice-card")
	title_id := notice_test_find_text(&rt, "Operation needs attention")
	icon_id := Node_ID(0)
	for id in rt.order {
		if node, ok := rt.nodes[id]; ok && node.active && node.icon_id == .Warning { icon_id = id; break }
	}
	if card_id == 0 || title_id == 0 || icon_id == 0 {
		testing.expect(t, false, "the themed toast should retain its card, title, and severity icon")
		return
	}
	testing.expect(t, rt.nodes[card_id].color == first_theme.colors[int(Style_Color_Role.Surface)] &&
		rt.nodes[title_id].color == first_theme.colors[int(Style_Color_Role.Text)] &&
		rt.nodes[icon_id].color == first_theme.colors[int(Style_Color_Role.Danger)],
		"the notice card, text, and error severity icon should resolve from the captured theme")

	layout_before := rt.stats.layout_nodes_visited
	measure_before := rt.stats.measure_requests
	paint_before := rt.stats.paint_nodes_visited
	notice.style_environment = Style_Environment{theme=second_theme_id}
	testing.expect(t, notice_post(&rt, notice, 2), "updating the existing notice theme should replace its style environment")
	_, second_root := notice_test_build(&rt)
	second_card_id := notice_test_find_node(&rt, "notice-card")
	second_title_id := notice_test_find_text(&rt, "Operation needs attention")
	second_icon_id := Node_ID(0)
	for id in rt.order {
		if node, ok := rt.nodes[id]; ok && node.active && node.icon_id == .Warning { second_icon_id = id; break }
	}
	testing.expect(t, second_root == first_root && second_card_id == card_id && second_title_id == title_id && second_icon_id == icon_id,
		"changing a notice theme should preserve retained notice identities")
	testing.expect(t, rt.nodes[second_card_id].color == second_theme.colors[int(Style_Color_Role.Surface)] &&
		rt.nodes[second_title_id].color == second_theme.colors[int(Style_Color_Role.Text)] &&
		rt.nodes[second_icon_id].color == second_theme.colors[int(Style_Color_Role.Danger)],
		"updating a notice should repaint its surface, text, and semantic severity color")
	testing.expect(t, rt.stats.layout_nodes_visited == layout_before && rt.stats.measure_requests == measure_before &&
		rt.stats.paint_nodes_visited > paint_before,
		"a theme-only notice update should repaint without layout or text measurement")

	invalid_notice := notice
	invalid_notice.style_environment.theme = Style_Theme_ID(0xFFFFFFFF)
	testing.expect(t, !notice_post(&rt, invalid_notice, 3) &&
		rt.notices[0].style_environment.theme == second_theme_id,
		"an unknown theme should be rejected without replacing the retained notice")
}

@(test)
test_notice_severity_icon_prevents_header_label_wrapping :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 420, 300})
	defer destroy_runtime(&rt)
	if !text_engine_load_font(&rt.text_engine, NOTICE_TEST_FONT) {
		testing.expect(t, false, "notice fixture should load its UI font")
		return
	}
	notice := Notice{
		id="warning-wrap",
		title="Folder needs attention",
		message="This warning stays until you dismiss it.",
		severity=.Warning,
		lifetime=.Persistent,
		placement=.Toast,
	}
	testing.expect(t, notice_post(&rt, notice, 0), "warning notice should be accepted")
	_, notice_root := notice_test_build(&rt)
	if notice_root == 0 { testing.expect(t, false, "the warning toast should be rendered"); return }

	title_id := notice_test_find_text(&rt, "Folder needs attention")
	warning_icon_seen := false
	for id in rt.order {
		node, ok := rt.nodes[id]
		if !ok || !node.active { continue }
		for command in node.paint {
			if painted, ok := command.payload.(Icon_Paint); ok && painted.id == .Warning {
				warning_icon_seen = true
			}
		}
	}
	testing.expect(t, warning_icon_seen && notice_test_find_text(&rt, "Warning") == 0,
		"severity should use a font-independent warning icon rather than a narrow text label")
	testing.expect(t, title_id != 0 && text_node_line_count(&rt, title_id) == 1,
		"the icon should free the heading width so the notice title fits on one line")
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
	close_id := notice_test_find_node(&rt, "", .Button)
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
	actionable_handle := rt.notices[0].handle
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
	testing.expect(t, event_found && event.action == Action_ID(77) && event.notice_id_hash == notice_string_hash("retry") && event.notice == actionable_handle,
		"the app should receive the chosen action and exact notice occurrence without Alicorn performing the operation")

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
		"an ordinary context-menu overlay pending in this frame should take precedence over notices")

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
