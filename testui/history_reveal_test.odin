package testui

import "core:fmt"
import "core:testing"
import alicorn "alicorn:runtime"

HISTORY_TEST_ROW_COUNT :: 48
HISTORY_TEST_ROW_HEIGHT :: 24
HISTORY_TEST_PAGE_STEP :: 8
HISTORY_TEST_COLLECTION_ID :: alicorn.Semantic_ID{namespace=0x414C49434F524E, value=0x484953544F5259}

History_Test_App :: struct {
	selected: int,
	scroll: alicorn.Node_ID,
	reveal_selection: bool,
}

history_test_item_id :: proc(index: int) -> alicorn.Semantic_ID {
	return alicorn.Semantic_ID{namespace=HISTORY_TEST_COLLECTION_ID.namespace, value=u64(index+1)}
}

history_test_item_label :: proc(index: int) -> string {
	return fmt.tprintf("Commit %02d", index+1)
}

history_test_render :: proc(app: ^History_Test_App, ui: ^alicorn.UI) {
	list := alicorn.virtual_list_begin(
		ui,
		HISTORY_TEST_ROW_COUNT,
		HISTORY_TEST_ROW_HEIGHT,
		key=alicorn.key_string("history-commit-list"),
		style=alicorn.layout_style(width=280, height=96),
		label="Commits",
		focusable=true,
	)
	app.scroll = list.scroll.id
	selected_id := history_test_item_id(app.selected)
	collection_actions := alicorn.semantic_actions_add({}, .Focus)
	collection_actions = alicorn.semantic_actions_add(collection_actions, .Scroll_Forward)
	collection_actions = alicorn.semantic_actions_add(collection_actions, .Scroll_Backward)
	collection := alicorn.semantic_collection_begin(
		ui,
		list.scroll.id,
		HISTORY_TEST_COLLECTION_ID,
		.List,
		"Commits",
		HISTORY_TEST_ROW_COUNT,
		selected_id=selected_id,
		current_id=selected_id,
		realized_first=u64(list.first),
		realized_last=u64(list.last),
		actions=collection_actions,
	)
	for index := 0; index < HISTORY_TEST_ROW_COUNT; index += 1 {
		item_id := history_test_item_id(index)
		label := history_test_item_label(index)
		states := alicorn.Semantic_States{}
		if index == app.selected { states = alicorn.semantic_states_add(states, .Selected) }
		if index >= list.first && index < list.last {
			alicorn.container_begin(
				ui,
				.Virtual_Row,
				label=label,
				key=alicorn.key_u64(u64(index+1)),
				style=alicorn.layout_style(.Row, width=-1, height=HISTORY_TEST_ROW_HEIGHT),
			)
			_ = alicorn.semantic_collection_item(ui, collection, u64(index), alicorn.Semantic_Node_Description{
				id=item_id,
				role=.List_Item,
				label=label,
				states=states,
				actions=alicorn.Semantic_Actions{.Focus, .Scroll_Into_View},
			})
			alicorn.text(ui, label)
			alicorn.container_end(ui)
		} else {
			_ = alicorn.semantic_collection_virtual_item(ui, collection, u64(index), alicorn.Semantic_Node_Description{
				id=item_id,
				role=.List_Item,
				label=label,
				states=states,
				actions=alicorn.Semantic_Actions{.Focus, .Scroll_Into_View},
			})
		}
	}
	alicorn.virtual_list_end(ui, list)
}

history_test_on_key :: proc(state: rawptr, rt: ^alicorn.Runtime, key: alicorn.Application_Key) -> bool {
	if key != .Page_Down { return false }
	app := cast(^History_Test_App)state
	if alicorn.focused_node(rt) != app.scroll { return false }
	app.selected = min(app.selected+HISTORY_TEST_PAGE_STEP, HISTORY_TEST_ROW_COUNT-1)
	if app.reveal_selection {
		_ = alicorn.scroll_region_set_offset(
			rt,
			app.scroll,
			f32(app.selected*HISTORY_TEST_ROW_HEIGHT),
			"History keyboard selection reveal",
		)
	}
	return true
}

history_test_open :: proc(app: ^History_Test_App) -> (Test_Handle(History_Test_App), Status) {
	return open(
		app,
		history_test_render,
		width=320,
		height=140,
		on_key=history_test_on_key,
	)
}

history_test_focus_list :: proc(t: ^testing.T, handle: ^Test_Handle(History_Test_App)) -> bool {
	list := find(handle, Query{role=.List, name="Commits", match_role=true, match_name=true})
	defer destroy_find_result(&list)
	if !testing.expect(t, list.match == .Unique && list.element.visual_node != 0,
		"the application must publish a uniquely named retained commit list") {
		return false
	}
	status := step(handle, Input{
		kind=.Semantic_Action,
		semantic_id=list.element.semantic_id,
		semantic_action=.Focus,
	})
	return testing.expect(t, status == .Ok && alicorn.focused_node(handle.runtime) == list.element.visual_node,
		"semantic focus should focus the same retained list owner used by keyboard input")
}

@(test)
test_headless_history_page_down_selects_and_reveals_the_commit :: proc(t: ^testing.T) {
	app := History_Test_App{reveal_selection=true}
	h, status := history_test_open(&app)
	defer if h.runtime != nil { close(&h) }
	if !testing.expect(t, status == .Ok, "History fixture should stabilize in a headless runtime") { return }
	if !history_test_focus_list(t, &h) { return }
	if !testing.expect(t, step(&h, Input{kind=.Key, key=.Page_Down}) == .Ok,
		"Page Down should be dispatched through the public test input boundary") {
		return
	}
	selected_label := history_test_item_label(app.selected)
	selected := find(&h, Query{role=.List_Item, name=selected_label, match_role=true, match_name=true})
	defer destroy_find_result(&selected)
	if !testing.expect(t, selected.match == .Unique && selected.element.has_bounds &&
		alicorn.semantic_states_has(selected.element.states, .Selected),
		"the selected logical commit should have a realized, selected row after Page Down") {
		return
	}
	list := find(&h, Query{role=.List, name="Commits", match_role=true, match_name=true})
	defer destroy_find_result(&list)
	if !testing.expect(t, list.match == .Unique && list.element.scroll_geometry_resolved &&
		list.element.scroll_offset_y > 0,
		"the list should report resolved scroll geometry and a moved viewport") {
		return
	}
	row := selected.element.bounds
	viewport := list.element.scroll_viewport_bounds
	inside := row.y >= viewport.y-0.01 && row.y+row.h <= viewport.y+viewport.h+0.01
	testing.expect(t, inside, "the selected commit row must be completely inside the list viewport")
}

@(test)
test_headless_history_regression_detects_selection_without_reveal :: proc(t: ^testing.T) {
	app := History_Test_App{reveal_selection=false}
	h, status := history_test_open(&app)
	defer if h.runtime != nil { close(&h) }
	if !testing.expect(t, status == .Ok, "History regression fixture should stabilize") { return }
	if !history_test_focus_list(t, &h) { return }
	if !testing.expect(t, step(&h, Input{kind=.Key, key=.Page_Down}) == .Ok,
		"Page Down should update the selected commit even in the deliberately broken fixture") {
		return
	}
	selected_label := history_test_item_label(app.selected)
	selected := find(&h, Query{role=.List_Item, name=selected_label, match_role=true, match_name=true})
	defer destroy_find_result(&selected)
	selected_updates := selected.match == .Unique && alicorn.semantic_states_has(selected.element.states, .Selected)
	missing_reveal := selected.match == .Unique && !selected.element.has_bounds
	testing.expect(t, selected_updates && missing_reveal,
		"the negative control should show correct selection while proving the selected row was not revealed")
}
