package alicorn

import "core:mem"

// DEFAULT_TEXT_SIZE is the logical text size used by retained text widgets.
DEFAULT_TEXT_SIZE :: f32(16)

// Node_Info is a read-only snapshot of stable node properties useful to
// application interaction and layout logic. key strings borrow runtime-owned
// storage and remain valid until the next runtime mutation, application
// description, or runtime destruction. It intentionally excludes retained
// products such as Text_Run.
Node_Info :: struct {
	id: Node_ID,
	kind: Node_Kind,
	key: UI_Key,
	bounds: Rect,
	active: bool,
	disabled: bool,
	focusable: bool,
	text_input_target: bool,
	focused: bool,
	captured: bool,
	split_owner: Node_ID,
	split_position: f32,
	split_dragging: bool,
	text_geometry_available: bool,
	text_content_width, text_content_height: f32,
	scroll_offset_x, scroll_offset_y: f32,
	scroll_content_width, scroll_content_height: f32,
	scroll_viewport_width, scroll_viewport_height: f32,
	scroll_viewport_bounds: Rect,
	scroll_geometry_resolved: bool,
}

// Text_Line_Geometry describes one retained visual line in absolute logical
// window coordinates. Byte boundaries are local to the retained text value.
Text_Line_Geometry :: struct {
	index: int,
	byte_start, byte_end: int,
	bounds: Rect,
}

focused_node :: proc(rt: ^Runtime) -> Node_ID {
	if rt == nil { return 0 }
	return rt.focused
}

captured_node :: proc(rt: ^Runtime) -> Node_ID {
	if rt == nil { return 0 }
	return rt.captured_node
}

viewport_bounds :: proc(rt: ^Runtime) -> Rect {
	if rt == nil { return {} }
	return rt.viewport
}

layout_is_pending :: proc(rt: ^Runtime) -> bool {
	return rt != nil && rt.layout_pending
}

// runtime_scratch_allocator returns the runtime's frame scratch allocator.
// Allocations from it must not outlive the next runtime scratch reset.
runtime_scratch_allocator :: proc(rt: ^Runtime) -> mem.Allocator {
	if rt == nil { return {} }
	return rt.scratch_allocator
}

node_info :: proc(rt: ^Runtime, id: Node_ID) -> (info: Node_Info, ok: bool) {
	if rt == nil || id == 0 { return }
	node, found := rt.nodes[id]
	if !found || node == nil { return }
	key, key_ok := node_identity_key(rt, id)
	if !key_ok { key = UI_Unkeyed{} }
	info = Node_Info{
		id=node.id,
		kind=node.kind,
		key=key,
		bounds=layout_node_finalized_geometry(rt, id).bounds,
		active=node.active,
		disabled=node.disabled,
		focusable=node.focusable,
		text_input_target=node.text_input_target && !node.text_input_target_suspended,
		focused=rt.focused == id,
		captured=rt.captured_node == id,
		split_owner=node.split_owner,
		split_position=node.split_position,
		split_dragging=node.split_dragging,
		text_geometry_available=node.text_run_valid,
		text_content_width=node.text_run.width,
		text_content_height=node.text_run.height,
		scroll_offset_x=node.scroll_offset_x,
		scroll_offset_y=node.scroll_offset_y,
		scroll_content_width=node.scroll_content_width,
		scroll_content_height=node.scroll_content_height,
		scroll_viewport_width=node.scroll_viewport_width,
		scroll_viewport_height=node.scroll_viewport_height,
		scroll_viewport_bounds=layout_finalize_rect(node.scroll_viewport_bounds, rt.presentation_scale_x, rt.presentation_scale_y),
		scroll_geometry_resolved=node.scroll_geometry_resolved,
	}
	return info, true
}

// node_identity_key returns the explicit key for a retained node. The returned
// string variant borrows runtime-owned storage as documented by Node_Info.
node_identity_key :: proc(rt: ^Runtime, id: Node_ID) -> (key: UI_Key, ok: bool) {
	if rt == nil || id == 0 { return }
	node, found := rt.nodes[id]
	if !found || node == nil { return }
	switch node.identity_key_kind {
	case 1:
		// identity_key is the containing identity scope. The node's explicit
		// string key is stored separately as key; returning the scope here
		// makes keyed items impossible to resolve from pointer events.
		key = node.key
	case 2:
		key = node.identity_key_u64
	case 3:
		key = node.identity_key_pair
	case:
		key = UI_Unkeyed{}
		return key, false
	}
	return key, true
}

// node_by_key finds the first active node matching a typed UI key and kind.
// Prefer retaining the Node_ID returned during description; this query is for
// application flows that intentionally resolve a semantic key after a frame.
node_by_key :: proc(rt: ^Runtime, key: UI_Key, kind: Node_Kind) -> (id: Node_ID, ok: bool) {
	if rt == nil || !ui_key_is_explicit(key) { return }
	for candidate_id in rt.order {
		node, found := rt.nodes[candidate_id]
		if !found || node == nil || !node.active || node.kind != kind { continue }
		switch value in key {
		case string:
			if node.identity_key_kind == 1 && node.key == value { return candidate_id, true }
		case u64:
			if node.identity_key_kind == 2 && node.identity_key_u64 == value { return candidate_id, true }
		case UI_Key_Pair:
			if node.identity_key_kind == 3 && node.identity_key_pair == value { return candidate_id, true }
		case UI_Unkeyed:
			// Unkeyed items cannot be resolved semantically.
		}
	}
	return
}

// text_field_value returns the borrowed value of an active retained text
// field. The value remains valid until that field is mutated (including by
// input), the next application description, or runtime destruction. Clone it
// before retaining it in application state.
text_field_value :: proc(rt: ^Runtime, id: Node_ID) -> (value: string, ok: bool) {
	if rt == nil || id == 0 { return }
	node, found := rt.nodes[id]
	if !found || node == nil || !node.active || node.kind != .Text_Field { return }
	return node.text, true
}

// text_node_line_count returns the number of visual lines in an active shaped
// Text or Text_Field node, or zero when its run is unavailable.
text_node_line_count :: proc(rt: ^Runtime, id: Node_ID) -> int {
	if rt == nil || id == 0 { return 0 }
	node, found := rt.nodes[id]
	if !found || node == nil || !node.active || !node.text_run_valid { return 0 }
	return len(node.text_run.lines)
}

// text_node_line_geometry returns retained visual-line bounds and byte range.
// Geometry is in logical window coordinates, matching text_node_hit_test.
text_node_line_geometry :: proc(rt: ^Runtime, id: Node_ID, index: int) -> (line: Text_Line_Geometry, ok: bool) {
	if rt == nil || id == 0 { return }
	node, found := rt.nodes[id]
	if !found || node == nil || !node.active || !node.text_run_valid ||
	   (node.kind != .Text && node.kind != .Text_Field) || index < 0 || index >= len(node.text_run.lines) {
		return
	}
	shaped := node.text_run.lines[index]
	bounds := layout_node_finalized_geometry(rt, id).bounds
	line = Text_Line_Geometry{
		index=index,
		byte_start=shaped.byte_start,
		byte_end=shaped.byte_end,
		bounds=Rect{bounds.x+shaped.x, bounds.y+shaped.y, shaped.width, shaped.height},
	}
	return line, true
}

// text_node_hit_test_line finds a text position at x on the requested retained
// visual line. x is an absolute logical window coordinate.
text_node_hit_test_line :: proc(rt: ^Runtime, id: Node_ID, x: f32, line_index: int) -> (position: Text_Position, ok: bool) {
	line, found := text_node_line_geometry(rt, id, line_index)
	if !found { return }
	node := rt.nodes[id]
	bounds := layout_node_finalized_geometry(rt, id).bounds
	position = text_run_hit_test(&node.text_run, x-bounds.x, line.bounds.y-bounds.y+line.bounds.h*0.5, rt.scratch_allocator)
	return position, true
}

// runtime_text_run_build shapes temporary application text with Alicorn's
// retained text engine and the same text normalization/style path. The caller
// owns the returned run and must call text_run_destroy. Use DEFAULT_TEXT_SIZE
// when matching standard retained text widgets.
runtime_text_run_build :: proc(
	rt: ^Runtime,
	value: string,
	size: f32 = DEFAULT_TEXT_SIZE,
	max_width: f32 = 0,
	font := Font_Role.UI,
	font_weight: f32 = FONT_WEIGHT_REGULAR,
	overflow := Text_Overflow.Wrap,
	editable := false,
	text_style_spans: []Text_Style_Span = nil,
	allocator := context.allocator,
	scratch_allocator := context.temp_allocator,
) -> (run: Text_Run, ok: bool) {
	if rt == nil { return }
	return text_run_build_with_overflow(
		&rt.text_engine, value, size, max_width, allocator, scratch_allocator,
		font, font_weight, overflow, editable, text_style_spans,
	)
}
