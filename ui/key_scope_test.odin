package ui

import "core:strings"
import "core:testing"
import alicorn "alicorn:runtime"

Key_Scope_Test_Item :: struct {
	ordinal: int,
	key: UI_Key,
	buffer: Text_Buffer,
	caption, field: Node_ID,
}

key_scope_test_component :: proc(ctx: ^UI, item: ^Key_Scope_Test_Item) {
	if key_scope(ctx, item.key) {
		item.caption = text(ctx, "Record")
		if key_scope(ctx, "details") {
			item.field = text_field(ctx, "Name", &item.buffer, height=30).node
		}
	}
}

key_scope_test_frame :: proc(rt: ^alicorn.Runtime, items: []Key_Scope_Test_Item) -> Node_ID {
	ctx, build := alicorn.begin_frame(rt)
	if !build { return 0 }
	root := alicorn.container_begin(&ctx, .Root, key="scope-test", style=layout_style(width=300, height=200))
	for &item in items { key_scope_test_component(&ctx, &item) }
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	return root
}

@(test)
test_keyed_components_keep_nested_identity_and_focus_through_reorder :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 300, 200})
	defer alicorn.destroy_runtime(&rt)
	items := [3]Key_Scope_Test_Item{
		{ordinal=0, key="7"}, {ordinal=1, key=u64(7)}, {ordinal=2, key=key_pair(7, 0)},
	}
	for &item in items {
		ok: bool
		item.buffer, ok = text_buffer("Alicorn")
		testing.expect(t, ok)
	}
	defer { for &item in items { text_buffer_destroy(&item.buffer) } }
	root := key_scope_test_frame(&rt, items[:])
	ids: [3]Node_ID
	for item in items {
		ids[item.ordinal] = item.field
		info, found := rt.nodes[item.caption]
		testing.expect(t, found && info.parent == root,
			"key scopes must identify multiple helper invocations without introducing layout parents")
	}
	testing.expect(t, !rt.hard_error && len(rt.order) == 10 && len(rt.identity_stack) == 0,
		"string, numeric and pair keys should isolate nested scopes with no extra retained nodes")
	testing.expect(t, alicorn.focus(&rt, ids[1]) && alicorn.set_text_selection(&rt, ids[1], 1, 4))
	items[0], items[1], items[2] = items[2], items[0], items[1]
	alicorn.invalidate_root(&rt, "reorder component instances")
	_ = key_scope_test_frame(&rt, items[:])
	for item in items {
		testing.expect(t, item.field == ids[item.ordinal], "nested child identities must follow the logical key after reorder")
	}
	selection, found := alicorn.text_field_interaction(&rt, ids[1])
	testing.expect(t, found && selection.focused && selection.selection_start == 1 && selection.selection_end == 4,
		"reordering must retain focus and selection on the same component, not its former array position")
	alicorn.invalidate_root(&rt, "filter another component")
	_ = key_scope_test_frame(&rt, items[1:])
	selection, found = alicorn.text_field_interaction(&rt, ids[1])
	testing.expect(t, !rt.hard_error && found && selection.focused && selection.has_selection,
		"omitting a sibling must not disturb the remaining component's retained interaction state")
	_, build := alicorn.begin_frame(&rt)
	testing.expect(t, !build, "the keyed component description must settle to true idle")
}

key_scope_test_unkeyed_helper :: proc(ctx: ^UI, label: string) -> Node_ID {
	return text(ctx, label)
}

@(test)
test_repeated_helper_diagnostic_explains_missing_keys :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 300, 200})
	defer alicorn.destroy_runtime(&rt)
	ctx, _ := alicorn.begin_frame(&rt)
	alicorn.container_begin(&ctx, .Root, key="missing-key-test")
	first := key_scope_test_unkeyed_helper(&ctx, "First instance")
	duplicate := key_scope_test_unkeyed_helper(&ctx, "Second instance")
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	testing.expect(t, first != 0 && duplicate == 0 && rt.hard_error,
		"ambiguous helper instances must fail visibly rather than receive sequential identities")
	expected_messages := []string{"Repeated widget identity", "same call site", "key=item.id", "ui.key_scope(ctx, item.id)",
		"first declaration:", "duplicate declaration:", "key_scope_test.odin:", "scope-depth="}
	for expected in expected_messages {
		testing.expect(t, strings.contains(rt.diagnostic, expected), expected)
	}
}

key_scope_test_duplicate_button :: proc(ctx: ^UI, label: string) {
	_ = button(ctx, label, key="same")
}

@(test)
test_duplicate_widget_key_diagnostic_distinguishes_both_declarations :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 300, 200})
	defer alicorn.destroy_runtime(&rt)
	ctx, _ := alicorn.begin_frame(&rt)
	alicorn.container_begin(&ctx, .Root, key="duplicate-widget-test")
	key_scope_test_duplicate_button(&ctx, "First button")
	key_scope_test_duplicate_button(&ctx, "Second button")
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	expected_messages := []string{"Repeated widget identity", "same explicit key", "unique stable key=item.id",
		"first declaration:", "duplicate declaration:", "First button", "Second button", "string:\"same\""}
	testing.expect(t, rt.hard_error)
	for expected in expected_messages { testing.expect(t, strings.contains(rt.diagnostic, expected), expected) }
}

key_scope_test_repeated_scope :: proc(ctx: ^UI) -> bool {
	if key_scope(ctx, u64(42)) {
		text(ctx, "One component")
		return true
	}
	return false
}

@(test)
test_duplicate_scope_does_not_close_its_enclosing_scope :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 300, 200})
	defer alicorn.destroy_runtime(&rt)
	ctx, _ := alicorn.begin_frame(&rt)
	alicorn.container_begin(&ctx, .Root, key="duplicate-scope-test")
	root_depth := len(rt.identity_stack)
	if key_scope(&ctx, "outer") {
		depth := len(rt.identity_stack)
		testing.expect(t, key_scope_test_repeated_scope(&ctx))
		testing.expect(t, !key_scope_test_repeated_scope(&ctx))
		testing.expect(t, len(rt.identity_stack) == depth,
			"a rejected duplicate scope must not pop its still-open parent")
	}
	testing.expect(t, len(rt.identity_stack) == root_depth)
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	expected_messages := []string{"Repeated key scope identity", "unique stable key", "first declaration:", "duplicate declaration:", "u64:42", "key_scope_test.odin:"}
	for expected in expected_messages {
		testing.expect(t, strings.contains(rt.diagnostic, expected), expected)
	}
}

key_scope_test_return_early :: proc(ctx: ^UI) {
	if key_scope(ctx, "return") { return }
}

@(test)
test_key_scope_balances_return_break_continue_and_preserves_caller_site :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 300, 200})
	defer alicorn.destroy_runtime(&rt)
	ctx, _ := alicorn.begin_frame(&rt)
	root := alicorn.container_begin(&ctx, .Root, key="early-exit-test")
	depth := len(rt.identity_stack)
	key_scope_test_return_early(&ctx)
	testing.expect(t, len(rt.identity_stack) == depth)
	for i in 0..<3 {
		if key_scope(&ctx, u64(i)) {
			if i == 0 { continue }
			break
		}
	}
	testing.expect(t, len(rt.identity_stack) == depth && len(rt.stack) == 1)
	for _, declaration in rt.identity_scopes {
		testing.expect(t, strings.contains(declaration.source.file, "key_scope_test.odin"),
			"scope identity must use the application caller location rather than the wrapper's source")
	}
	after := text(&ctx, "After scopes")
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	info, found := rt.nodes[after]
	testing.expect(t, !rt.hard_error && found && info.parent == root && len(rt.identity_stack) == 0,
		"early exits must leave the following UI outside the component scope")
}
