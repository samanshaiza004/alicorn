package ui

import "core:testing"
import "core:strings"
import "core:math"
import alicorn "alicorn:runtime"

UI_List_Test_App :: struct {
	count: int,
	owner, first_row, after: Node_ID,
	first, last: int,
}

ui_list_test_render :: proc(app: ^UI_List_Test_App, ctx: ^UI) {
	if list, ok := virtual_list(ctx, app.count, 20, key="records", height=100, grow=0, focusable=true); ok {
		app.owner, app.first, app.last = list.scroll.id, list.first, list.last
		for i in list.first..<list.last {
			if key_scope(ctx, u64(i)) {
				id := text(ctx, "Record", style=layout_style(height=20))
				if i == list.first { app.first_row = id }
			}
		}
	}
	app.after = text(ctx, "After list")
}

@(test)
test_scoped_virtual_list_bounds_realization_and_preserves_fractional_scrolling :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 240, 160})
	defer alicorn.destroy_runtime(&rt)
	app := UI_List_Test_App{count=10_000}
	state := Run_State(UI_List_Test_App){app=&app, render=ui_list_test_render}
	application := run_application(&state, "List", 240, 160)
	root := application.build(application.state, &rt, 240, 160, 1)
	testing.expect(t, root != 0 && app.first == 0 && app.last == 6 && len(rt.nodes) < 20 && !rt.hard_error,
		"ten thousand fixed-height records must realize only the visible/frontier rows")
	after, found := rt.nodes[app.after]
	testing.expect(t, found && after.parent == root && len(rt.stack) == 0 && len(rt.identity_stack) == 0,
		"the if initializer must close both retained list scopes before the next sibling")
	owner := app.owner
	testing.expect(t, strings.contains(rt.nodes[owner].site.file, "virtual_list_test.odin"), "forward the application list call site")
	owner_info, owner_info_ok := alicorn.node_info(&rt, owner)
	testing.expect(t, owner_info_ok && owner_info.focusable, "the scoped helper must forward keyboard focusability to its scroll owner")
	testing.expect(t, alicorn.scroll_region_set_offset(&rt, owner, 50, "fractional row scroll"))
	_ = application.build(application.state, &rt, 240, 160, 1)
	first := rt.nodes[app.first_row]
	testing.expect(t, app.owner == owner && app.first == 2 && app.last == 8 && first.bounds.y == rt.nodes[owner].bounds.y-10,
		"fractional scrolling must retain the owner, advance the bounded range and clip the leading partial row")
	testing.expect(t, application.build(application.state, &rt, 240, 160, 1) == 0, "a settled list must return to idle")
}

ui_list_test_early_return :: proc(ctx: ^UI) {
	if _, ok := virtual_list(ctx, 1, 20, key="early", height=20); ok { return }
}

@(test)
test_scoped_virtual_list_closes_on_early_exit_and_leaves_invalid_or_empty_ranges_balanced :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 240, 160})
	defer alicorn.destroy_runtime(&rt)
	ctx, _ := alicorn.begin_frame(&rt)
	alicorn.container_begin(&ctx, .Root, key="list-cleanup")
	depth := len(rt.identity_stack)
	ui_list_test_early_return(&ctx)
	for i in 0..<3 {
		if _, ok := virtual_list(&ctx, 1, 20, key=u64(i), height=20); ok {
			if i == 0 { continue }
			break
		}
	}
	if empty, ok := virtual_list(&ctx, 0, 20, key="empty", height=20); ok {
		testing.expect(t, empty.first == 0 && empty.last == 0, "an empty list still owns a valid balanced viewport")
	} else { testing.expect(t, false, "empty collections are valid") }
	invalid_heights := []f32{0, -1, math.nan_f32(), math.INF_F32}
	for height in invalid_heights {
		if _, ok := virtual_list(&ctx, 1, height); ok { testing.expect(t, false, "row height must be finite and positive") }
	}
	if _, ok := virtual_list(&ctx, -1, 20); ok { testing.expect(t, false, "a negative count must be rejected") }
	testing.expect(t, len(rt.stack) == 1 && len(rt.identity_stack) == depth && !rt.hard_error,
		"early returns, break/continue and rejected list inputs must leave the enclosing parent open")
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
}
