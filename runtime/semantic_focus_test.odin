package alicorn

import "core:testing"
import "core:fmt"
import "core:strings"

semantic_focus_test_render :: proc(rt: ^Runtime, detailed: bool) -> (owner, row: Node_ID) {
	invalidate_root(rt, "semantic focus virtual list test")
	ui, should_build := begin_frame(rt)
	if !should_build { return }
	container_begin(&ui, .Root, label="semantic-focus-root", key=key_string("semantic-focus-root"), style=layout_style())
	list := virtual_list_begin(
		&ui,
		16 if detailed else 0,
		24,
		key=key_string("semantic-focus-list"),
		style=layout_style(height=72),
		label="semantic-focus-list",
		focusable=true,
	)
	owner = list.scroll.id
	if detailed {
		for position := list.first; position < list.last; position += 1 {
			entity_id := u64(position+1)
			button_id, _ := button_ex(
				&ui,
				fmt.tprintf("event %d", entity_id),
				key=fmt.tprintf("event-%d", entity_id),
				explicit_key=true,
				style=layout_style(.Row, height=24),
			)
			_ = semantic_bind(&ui, Semantic_ID{namespace=7, value=entity_id})
			if entity_id == 1 { row = button_id }
		}
	} else {
		text(&ui, "aggregate density", style=layout_style(.Row, height=24))
	}
	virtual_list_end(&ui, list)
	container_end(&ui)
	end_frame(&ui)
	return
}

@(test)
test_semantic_focus_survives_virtualization_and_lod :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 320, 120})
	defer destroy_runtime(&rt)

	owner, row := semantic_focus_test_render(&rt, true)
	testing.expect(t, owner != 0 && row != 0, "the detailed list should realize the first event row")
	if owner == 0 || row == 0 { return }

	event := Semantic_ID{namespace=7, value=1}
	track_with_same_numeric_value := Semantic_ID{namespace=8, value=1}
	keyboard_focus_before := rt.focused
	selected_before := rt.selected
	testing.expect(t, semantic_focus_set(&rt, event, owner), "semantic focus should accept an application entity and owner")
	testing.expect(t, rt.focused == keyboard_focus_before && rt.selected == selected_before,
		"setting semantic focus should not take keyboard focus or change retained selection")
	testing.expect(t, focus(&rt, row), "the realized event row should accept keyboard focus")
	_, _ = semantic_focus_test_render(&rt, true)
	state := semantic_focus_state(&rt)
	testing.expect(t, state.id == event && state.owner == owner && state.realized_node == row,
		"semantic identity, durable owner, and realized row should be reported independently")
	inspection := inspect(&rt)
	testing.expect(t, strings.contains(inspection, "semantic focus: namespace=7 value=1 owner="),
		"the runtime inspector should name semantic identity separately from keyboard focus")
	delete(inspection)
	testing.expect(t, rt.selected == 0, "semantic focus should not change retained selection")
	row_node := rt.nodes[row]
	semantic_outline := false
	for command in row_node.paint {
		if command.kind == .Button && command.color.g == 0.78 && command.color.b == 0.82 {
			semantic_outline = true
			break
		}
	}
	testing.expect(t, semantic_outline, "the active semantic presentation should have a distinct visual outline")

	_ = scroll_region_set_offset(&rt, owner, 192, "scroll active semantic row out of view")
	owner_after_scroll, _ := semantic_focus_test_render(&rt, true)
	state = semantic_focus_state(&rt)
	testing.expect(t, owner_after_scroll == owner, "virtualization should preserve its durable focus owner")
	testing.expect(t, state.id == event && state.owner == owner && state.realized_node == 0,
		"retiring the focused row should preserve semantic identity while clearing only its realization")
	testing.expect(t, rt.focused == owner, "keyboard focus should move to the opted-in list owner, not an unrelated control")
	owner_outline := false
	for command in rt.nodes[owner].paint {
		if command.kind == .Button && command.color.r == 0.76 && command.color.g == 0.86 {
			owner_outline = true
			break
		}
	}
	testing.expect(t, owner_outline, "the retained keyboard-focus owner should stay visibly outlined")
	inspection = inspect(&rt)
	testing.expect(t, strings.contains(inspection, "semantic focus: namespace=7 value=1 owner=") && strings.contains(inspection, "realized=0"),
		"the inspector should explain that a virtualized semantic entity has no current node")
	delete(inspection)

	_ = scroll_region_set_offset(&rt, owner, 0, "reveal semantic row again")
	_, row_again := semantic_focus_test_render(&rt, true)
	state = semantic_focus_state(&rt)
	testing.expect(t, row_again != 0 && state.realized_node == row_again,
		"a newly realized matching row should reconnect automatically")
	if row_again != 0 {
		testing.expect(t, rt.nodes[row_again].semantic_active, "re-realization should restore semantic-active presentation")
	}

	_, _ = semantic_focus_test_render(&rt, false)
	state = semantic_focus_state(&rt)
	testing.expect(t, state.id == event && state.owner == owner && state.realized_node == 0,
		"switching to aggregate LOD should retain the entity without requiring a realized row")

	_, row_again = semantic_focus_test_render(&rt, true)
	state = semantic_focus_state(&rt)
	testing.expect(t, row_again != 0 && state.realized_node == row_again,
		"returning to detailed LOD should reconnect the same semantic identity")

	_ = semantic_focus_set(&rt, track_with_same_numeric_value, owner)
	state = semantic_focus_state(&rt)
	testing.expect(t, state.id == track_with_same_numeric_value,
		"namespace must distinguish domain entities that share the same numeric value")
	_ = semantic_focus_clear(&rt)
	testing.expect(t, semantic_focus_state(&rt).id.namespace == 0,
		"semantic focus can be cleared without changing application selection")
}
