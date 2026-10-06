package alicorn_sdl_gpu

import "core:fmt"
import "core:os"
import "core:testing"
import alicorn "../../runtime"

SEMANTIC_VIRTUAL_FIXTURE_NAMESPACE :: u64(0x53454D5649525401)
SEMANTIC_VIRTUAL_FIXTURE_COLLECTION :: alicorn.Semantic_ID{namespace=SEMANTIC_VIRTUAL_FIXTURE_NAMESPACE, value=1}
SEMANTIC_VIRTUAL_FIXTURE_ITEM_BASE :: u64(0x100000000)
SEMANTIC_VIRTUAL_FIXTURE_ITEM_COUNT :: 1_000_000
SEMANTIC_VIRTUAL_FIXTURE_ROW_HEIGHT :: f32(32)
SEMANTIC_VIRTUAL_FIXTURE_HORIZON :: 8

Semantic_Virtualization_Fixture_State :: struct {
	runtime: ^alicorn.Runtime,
	list: alicorn.Node_ID,
	first: int,
	last: int,
	current_position: int,
	has_current: bool,
	reveal_requests: u64,
	scroll_forward_requests: u64,
	scroll_backward_requests: u64,
	focus_requests: u64,
	diagnostics: bool,
	has_logged_range: bool,
	logged_first: int,
	logged_last: int,
}

semantic_virtual_fixture_item_id :: proc(position: int) -> alicorn.Semantic_ID {
	return alicorn.Semantic_ID{
		namespace=SEMANTIC_VIRTUAL_FIXTURE_NAMESPACE,
		value=SEMANTIC_VIRTUAL_FIXTURE_ITEM_BASE+u64(position),
	}
}

semantic_virtual_fixture_item_position :: proc(id: alicorn.Semantic_ID) -> (position: int, found: bool) {
	if id.namespace != SEMANTIC_VIRTUAL_FIXTURE_NAMESPACE || id.value < SEMANTIC_VIRTUAL_FIXTURE_ITEM_BASE { return }
	position = int(id.value-SEMANTIC_VIRTUAL_FIXTURE_ITEM_BASE)
	found = position < SEMANTIC_VIRTUAL_FIXTURE_ITEM_COUNT
	return
}

semantic_virtual_fixture_handle_requests :: proc(app: ^Semantic_Virtualization_Fixture_State, rt: ^alicorn.Runtime) {
	if app == nil || rt == nil { return }
	for {
		event, found := alicorn.semantic_request_pop(rt)
		if !found { break }
		switch event.kind {
		case .Reveal:
			position, valid := semantic_virtual_fixture_item_position(event.id)
			if valid {
				if app.diagnostics {
					fmt.println("semantic_request", "kind", "Reveal", "position", position+1,
						"from", app.first+1, app.last, "to", position+1)
				}
				_ = alicorn.scroll_region_set_offset(
					rt,
					app.list,
					f32(position)*SEMANTIC_VIRTUAL_FIXTURE_ROW_HEIGHT,
					"screen reader requested a virtual row reveal",
				)
				app.current_position, app.has_current = position, true
				app.reveal_requests += 1
			}
		case .Perform:
			if event.id == SEMANTIC_VIRTUAL_FIXTURE_COLLECTION {
				scroll := alicorn.scroll_region_state(rt, app.list)
				page := scroll.viewport_height-SEMANTIC_VIRTUAL_FIXTURE_ROW_HEIGHT
				if page < SEMANTIC_VIRTUAL_FIXTURE_ROW_HEIGHT { page = SEMANTIC_VIRTUAL_FIXTURE_ROW_HEIGHT }
				#partial switch event.action {
				case .Scroll_Forward:
					if app.diagnostics {
						fmt.println("semantic_request", "kind", "Scroll_Forward", "from_offset", scroll.offset_y,
						"to_offset", scroll.offset_y+page)
					}
					_ = alicorn.scroll_region_set_offset(rt, app.list, scroll.offset_y+page,
						"assistive technology scrolled the semantic collection forward")
					app.scroll_forward_requests += 1
				case .Scroll_Backward:
					if app.diagnostics {
						fmt.println("semantic_request", "kind", "Scroll_Backward", "from_offset", scroll.offset_y,
						"to_offset", scroll.offset_y-page)
					}
					_ = alicorn.scroll_region_set_offset(rt, app.list, scroll.offset_y-page,
						"assistive technology scrolled the semantic collection backward")
					app.scroll_backward_requests += 1
				}
			} else if position, valid := semantic_virtual_fixture_item_position(event.id); valid && event.action == .Focus {
				if app.diagnostics {
					fmt.println("semantic_request", "kind", "Focus", "position", position+1)
				}
				app.current_position, app.has_current = position, true
				_ = alicorn.semantic_focus_set(rt, event.id, app.list)
				app.focus_requests += 1
			}
		}
		alicorn.semantic_request_event_destroy(rt, &event)
	}
}

semantic_virtual_fixture_build :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	logical_width, logical_height: int,
	dpi_scale: f32,
) -> alicorn.Node_ID {
	app := cast(^Semantic_Virtualization_Fixture_State)state
	app.runtime = rt
	semantic_virtual_fixture_handle_requests(app, rt)
	ui, should_build := alicorn.begin_frame(rt)
	if !should_build { return 0 }
	root := alicorn.container_begin(
		&ui,
		.Root,
		label="million-row-accessibility-root",
		key=alicorn.key_string("million-row-accessibility-root"),
		style=alicorn.layout_style(.Column, grow=1, padding=20, gap=8, clip=true),
	)
	alicorn.text(&ui, "Alicorn million-row accessibility fixture", style=alicorn.layout_style(height=30))
	alicorn.text(&ui, "Use your screen reader to navigate the list. Scroll actions and ScrollIntoView reveal rows outside the visible range.",
		style=alicorn.layout_style(height=28))
	list := alicorn.virtual_list_begin(
		&ui,
		SEMANTIC_VIRTUAL_FIXTURE_ITEM_COUNT,
		SEMANTIC_VIRTUAL_FIXTURE_ROW_HEIGHT,
		key=alicorn.key_string("million-row-accessibility-list"),
		style=alicorn.layout_style(grow=1, clip=true),
		label="million-row-accessibility-list",
		focusable=true,
	)
	app.list, app.first, app.last = list.scroll.id, list.first, list.last
	current_id := alicorn.Semantic_ID{}
	if app.has_current { current_id = semantic_virtual_fixture_item_id(app.current_position) }
	collection_actions := alicorn.semantic_actions_add({}, .Focus)
	collection_actions = alicorn.semantic_actions_add(collection_actions, .Scroll_Forward)
	collection_actions = alicorn.semantic_actions_add(collection_actions, .Scroll_Backward)
	collection := alicorn.semantic_collection_begin(
		&ui,
		list.scroll.id,
		SEMANTIC_VIRTUAL_FIXTURE_COLLECTION,
		.List,
		"Million row test collection",
		u64(SEMANTIC_VIRTUAL_FIXTURE_ITEM_COUNT),
		current_id=current_id,
		realized_first=u64(list.first),
		realized_last=u64(list.last),
		actions=collection_actions,
	)
	for position := list.first; position < list.last; position += 1 {
		id := semantic_virtual_fixture_item_id(position)
		row_label := fmt.tprintf("Record %d", position+1)
		states := alicorn.Semantic_States{}
		if id == current_id { states = alicorn.semantic_states_add(states, .Current) }
		if !alicorn.key_scope_begin_key(&ui, alicorn.key_u64(id.value)) { continue }
		alicorn.container_begin_simple(
			&ui,
			.Virtual_Row,
			label=row_label,
			style=alicorn.layout_style(.Row, height=SEMANTIC_VIRTUAL_FIXTURE_ROW_HEIGHT),
		)
		row_actions := alicorn.semantic_actions_add({}, .Focus)
		row_actions = alicorn.semantic_actions_add(row_actions, .Scroll_Into_View)
		_ = alicorn.semantic_collection_item(&ui, collection, u64(position), alicorn.Semantic_Node_Description{
			id=id,
			role=.List_Item,
			label=row_label,
			states=states,
			actions=row_actions,
		})
		alicorn.container_end(&ui)
		alicorn.key_scope_end(&ui)
	}
	for position := max(list.first-SEMANTIC_VIRTUAL_FIXTURE_HORIZON, 0); position < list.first; position += 1 {
		id := semantic_virtual_fixture_item_id(position)
		row_label := fmt.tprintf("Record %d", position+1)
		states := alicorn.Semantic_States{}
		if id == current_id { states = alicorn.semantic_states_add(states, .Current) }
		row_actions := alicorn.semantic_actions_add({}, .Focus)
		row_actions = alicorn.semantic_actions_add(row_actions, .Scroll_Into_View)
		_ = alicorn.semantic_collection_virtual_item(&ui, collection, u64(position), alicorn.Semantic_Node_Description{
			id=id, role=.List_Item, label=row_label, states=states, actions=row_actions,
		})
	}
	for position := list.last; position < min(list.last+SEMANTIC_VIRTUAL_FIXTURE_HORIZON, SEMANTIC_VIRTUAL_FIXTURE_ITEM_COUNT); position += 1 {
		id := semantic_virtual_fixture_item_id(position)
		row_label := fmt.tprintf("Record %d", position+1)
		states := alicorn.Semantic_States{}
		if id == current_id { states = alicorn.semantic_states_add(states, .Current) }
		row_actions := alicorn.semantic_actions_add({}, .Focus)
		row_actions = alicorn.semantic_actions_add(row_actions, .Scroll_Into_View)
		_ = alicorn.semantic_collection_virtual_item(&ui, collection, u64(position), alicorn.Semantic_Node_Description{
			id=id, role=.List_Item, label=row_label, states=states, actions=row_actions,
		})
	}
	alicorn.virtual_list_end(&ui, list)
	label := fmt.tprintf(
		"1,000,000 logical rows | visible: %d..%d | reveals: %d | forward/back: %d/%d | focus: %d",
		app.first+1, app.last, app.reveal_requests, app.scroll_forward_requests, app.scroll_backward_requests, app.focus_requests,
	)
	alicorn.text(&ui, label, style=alicorn.layout_style(height=24))
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	if app.diagnostics && (!app.has_logged_range || app.logged_first != app.first || app.logged_last != app.last) {
		fmt.println("semantic_working_set",
			"visible_range", app.first+1, app.last,
			"retained_entities", len(rt.semantic_entities),
			"revision", alicorn.semantic_revision(rt),
			"added", rt.stats.semantic_projection_nodes_added,
			"updated", rt.stats.semantic_projection_nodes_updated,
			"removed", rt.stats.semantic_projection_nodes_removed,
		)
		app.has_logged_range, app.logged_first, app.logged_last = true, app.first, app.last
	}
	_ = logical_width
	_ = logical_height
	_ = dpi_scale
	return root
}

semantic_virtual_fixture_stop :: proc(state: rawptr) {
	app := cast(^Semantic_Virtualization_Fixture_State)state
	fmt.println(
		"semantic_virtualization_fixture",
		"logical_rows", SEMANTIC_VIRTUAL_FIXTURE_ITEM_COUNT,
		"retained_semantics", len(app.runtime.semantic_entities),
		"visible_range", app.first, app.last,
		"reveal_requests", app.reveal_requests,
		"scroll_forward", app.scroll_forward_requests,
		"scroll_backward", app.scroll_backward_requests,
		"focus_requests", app.focus_requests,
	)
}

RunSemanticVirtualizationFixture :: proc() {
	state := Semantic_Virtualization_Fixture_State{diagnostics=true}
	Run(Application{
		state=rawptr(&state),
		title="Alicorn Million-Row Accessibility Fixture",
		width=1100,
		height=760,
		build=semantic_virtual_fixture_build,
		on_stop=semantic_virtual_fixture_stop,
	})
}

@(test)
test_native_semantic_virtual_fixture_reveals_and_pages_with_bounded_working_set :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 1100, 760})
	defer alicorn.destroy_runtime(&rt)
	app := Semantic_Virtualization_Fixture_State{}
	alicorn.invalidate_root(&rt, "native million-row accessibility fixture test")
	_ = semantic_virtual_fixture_build(rawptr(&app), &rt, 1100, 760, 1)
	initial_first, initial_last := app.first, app.last
	initial_count := len(rt.semantic_entities)
	initial_bound := initial_last-initial_first+2*SEMANTIC_VIRTUAL_FIXTURE_HORIZON+1
	testing.expect(t, initial_first == 0 && initial_last > 0 && initial_count <= initial_bound,
		"the native fixture must begin with a viewport-sized semantic working set, not a million entities")

	reveal_position := initial_last+3
	reveal_id := semantic_virtual_fixture_item_id(reveal_position)
	testing.expect(t, alicorn.semantic_reveal_request(&rt, reveal_id),
		"an exported horizon row should accept a distinct ScrollIntoView/reveal request")
	semantic_virtual_fixture_handle_requests(&app, &rt)
	_ = semantic_virtual_fixture_build(rawptr(&app), &rt, 1100, 760, 1)
	testing.expect(t, app.reveal_requests == 1 && app.first <= reveal_position && reveal_position < app.last,
		"handling reveal should move the bounded visible range to include the requested logical row")
	_, old_row_found := alicorn.semantic_node_lookup(&rt, semantic_virtual_fixture_item_id(initial_first))
	revealed_bound := app.last-app.first+2*SEMANTIC_VIRTUAL_FIXTURE_HORIZON+1
	testing.expect(t, !old_row_found && len(rt.semantic_entities) <= revealed_bound,
		"rows leaving the working set should retire while the total semantic store stays bounded")

	previous_offset := alicorn.scroll_region_offset(&rt, app.list)
	testing.expect(t, alicorn.semantic_action_request(&rt, SEMANTIC_VIRTUAL_FIXTURE_COLLECTION, .Scroll_Forward),
		"the semantic collection should accept an advertised forward-scroll action")
	semantic_virtual_fixture_handle_requests(&app, &rt)
	_ = semantic_virtual_fixture_build(rawptr(&app), &rt, 1100, 760, 1)
	testing.expect(t, app.scroll_forward_requests == 1 && alicorn.scroll_region_offset(&rt, app.list) > previous_offset,
		"forward scrolling should advance the viewport through an application-handled semantic action")
	page_bound := app.last-app.first+2*SEMANTIC_VIRTUAL_FIXTURE_HORIZON+2
	testing.expect(t, len(rt.semantic_entities) <= page_bound,
		"paging beyond the exported horizon must not accumulate old semantic rows")
}
