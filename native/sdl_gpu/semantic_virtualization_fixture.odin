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

semantic_virtual_fixture_reveal_offset :: proc(current_offset, viewport_height: f32, position: int) -> f32 {
	row_top := f32(position)*SEMANTIC_VIRTUAL_FIXTURE_ROW_HEIGHT
	row_bottom := row_top+SEMANTIC_VIRTUAL_FIXTURE_ROW_HEIGHT
	if row_top < current_offset { return max(row_top, 0) }
	viewport_bottom := current_offset+viewport_height
	if row_bottom > viewport_bottom { return max(row_bottom-viewport_height, 0) }
	return max(current_offset, 0)
}

Semantic_Virtualization_Fixture_State :: struct {
	runtime: ^alicorn.Runtime,
	list: alicorn.Node_ID,
	first: int,
	last: int,
	current_position: int,
	has_current: bool,
	reveal_requests: u64,
	reveal_forward_requests: u64,
	reveal_backward_requests: u64,
	last_reveal_position: int,
	last_reveal_delta: int,
	has_last_reveal: bool,
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

semantic_virtual_fixture_action_name :: proc(action: alicorn.Semantic_Action) -> string {
	#partial switch action {
	case .Focus: return "Focus"
	case .Press: return "Press"
	case .Select: return "Select"
	case .Scroll_Into_View: return "Scroll_Into_View"
	case .Scroll_Forward: return "Scroll_Forward"
	case .Scroll_Backward: return "Scroll_Backward"
	}
	return "Other"
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
				delta := 0
				if app.has_last_reveal {
					delta = position-app.last_reveal_position
					if delta > 0 { app.reveal_forward_requests += 1 }
					if delta < 0 { app.reveal_backward_requests += 1 }
				}
				app.last_reveal_position = position
				app.last_reveal_delta = delta
				app.has_last_reveal = true
				if app.diagnostics {
					fmt.println("semantic_request", "kind", "Reveal", "position", position+1,
						"delta", delta, "from", app.first+1, app.last, "to", position+1)
				}
				scroll := alicorn.scroll_region_state(rt, app.list)
				next_offset := semantic_virtual_fixture_reveal_offset(scroll.offset_y, scroll.viewport_height, position)
				if next_offset != scroll.offset_y {
					if app.diagnostics {
						fmt.println("semantic_reveal_scroll", "position", position+1,
							"offset", scroll.offset_y, "to", next_offset)
					}
					_ = alicorn.scroll_region_set_offset(
						rt,
						app.list,
						next_offset,
						"screen reader requested an offscreen virtual row reveal",
					)
				} else if app.diagnostics {
					fmt.println("semantic_reveal_scroll", "position", position+1, "already_visible", true)
				}
				app.current_position, app.has_current = position, true
				app.reveal_requests += 1
			}
		case .Perform:
			if app.diagnostics {
				target := "other"
				if event.id == SEMANTIC_VIRTUAL_FIXTURE_COLLECTION {
					target = "collection"
				} else if position, valid := semantic_virtual_fixture_item_position(event.id); valid {
					target = fmt.tprintf("Record %d", position+1)
				}
				fmt.println("semantic_request", "kind", "Perform", "target", target,
					"action", semantic_virtual_fixture_action_name(event.action))
			}
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

@(test)
test_semantic_virtual_fixture_reveal_scrolls_only_to_expose_offscreen_rows :: proc(t: ^testing.T) {
	viewport_height := f32(608)
	unchanged := semantic_virtual_fixture_reveal_offset(0, viewport_height, 18)
	just_below := semantic_virtual_fixture_reveal_offset(0, viewport_height, 19)
	back_to_top := semantic_virtual_fixture_reveal_offset(32, viewport_height, 0)
	testing.expect(t, unchanged == 0,
		"revealing a row already inside the viewport should not move the scroll position")
	testing.expect(t, just_below == 32,
		"revealing a row just below the viewport should scroll only enough to expose it")
	testing.expect(t, back_to_top == 0,
		"revealing a row above the viewport should align its top without producing a negative offset")
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
		color=alicorn.Color{0.055, 0.065, 0.09, 1},
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
		alicorn.text(&ui, row_label, style=alicorn.layout_style(grow=1))
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
	alicorn.text(&ui,
		fmt.tprintf("Visible records: %d–%d of %d", app.first+1, app.last, SEMANTIC_VIRTUAL_FIXTURE_ITEM_COUNT),
		style=alicorn.layout_style(height=24))
	last_reveal := "none"
	last_direction := "none"
	if app.has_last_reveal {
		last_reveal = fmt.tprintf("Record %d", app.last_reveal_position+1)
		if app.last_reveal_delta > 0 {
			last_direction = fmt.tprintf("forward %d", app.last_reveal_delta)
		} else if app.last_reveal_delta < 0 {
			last_direction = fmt.tprintf("backward %d", -app.last_reveal_delta)
		} else {
			last_direction = "same position"
		}
	}
	alicorn.text(&ui,
		fmt.tprintf("Last revealed: %s · %s · reveal forward/back: %d/%d · scroll forward/back: %d/%d · focus: %d",
			last_reveal, last_direction, app.reveal_forward_requests, app.reveal_backward_requests,
			app.scroll_forward_requests, app.scroll_backward_requests, app.focus_requests),
		style=alicorn.layout_style(height=24))
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	if app.diagnostics && (!app.has_logged_range || app.logged_first != app.first || app.logged_last != app.last) {
		current_record := 0
		if app.has_current { current_record = app.current_position+1 }
		fmt.println("semantic_working_set",
			"visible_range", app.first+1, app.last,
			"retained_entities", len(rt.semantic_entities),
			"revision", alicorn.semantic_revision(rt),
			"current_record", current_record,
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
	}, smoke=native_fixture_smoke_requested(os.args))
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
	revealed_bound := app.last-app.first+2*SEMANTIC_VIRTUAL_FIXTURE_HORIZON+1
	testing.expect(t, len(rt.semantic_entities) <= revealed_bound,
		"minimal reveal scrolling should keep the collection's semantic store bounded")

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
