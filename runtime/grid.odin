package alicorn

import "core:math"

grid_fixed :: proc(size: f32) -> Grid_Track {
	return Grid_Track{kind=.Fixed, value=size}
}

grid_auto :: proc() -> Grid_Track { return Grid_Track{kind=.Auto} }

grid_fraction :: proc(weight: f32 = 1) -> Grid_Track {
	return Grid_Track{kind=.Fraction, value=weight}
}

// grid_min_max creates a bounded flexible track. A negative maximum means
// unbounded; otherwise the shared allocator keeps the track within both ends.
grid_min_max :: proc(minimum, maximum: f32) -> Grid_Track {
	return Grid_Track{kind=.Min_Max, minimum=minimum, maximum=maximum}
}

grid_track_config_hash :: proc(columns, rows: []Grid_Track, gap_x, gap_y: f32) -> u64 {
	h := hash_mix(1469598103934665603, u64(len(columns)))
	h = hash_mix(h, u64(len(rows)))
	h = hash_mix(h, u64(transmute(u32)gap_x))
	h = hash_mix(h, u64(transmute(u32)gap_y))
	for track in columns {
		h = hash_mix(h, u64(track.kind))
		h = hash_mix(h, u64(transmute(u32)track.value))
		h = hash_mix(h, u64(transmute(u32)track.minimum))
		h = hash_mix(h, u64(transmute(u32)track.maximum))
	}
	for track in rows {
		h = hash_mix(h, u64(track.kind))
		h = hash_mix(h, u64(transmute(u32)track.value))
		h = hash_mix(h, u64(transmute(u32)track.minimum))
		h = hash_mix(h, u64(transmute(u32)track.maximum))
	}
	return h
}

grid_begin :: proc(
	ui: ^UI,
	key: UI_Key,
	columns, rows: []Grid_Track,
	style := DEFAULT_STYLE,
	gap_x: f32 = 0,
	gap_y: f32 = 0,
	label := "grid",
	loc := #caller_location,
	layout_boundary := false,
) -> Node_ID {
	rt := ui.runtime
	if len(columns) == 0 || len(rows) == 0 {
		append_diagnostic(rt, "Grid requires at least one explicit row and column track")
		return 0
	}
	if len(columns) > int(max(u16))+1 || len(rows) > int(max(u16))+1 {
		append_diagnostic(rt, "Grid row and column track counts cannot exceed 65536 because cell indices use 16-bit identities")
		return 0
	}
	normalized_gap_x := gap_x
	normalized_gap_y := gap_y
	if math.is_nan(normalized_gap_x) || math.is_inf(normalized_gap_x) || normalized_gap_x < 0 { normalized_gap_x = 0 }
	if math.is_nan(normalized_gap_y) || math.is_inf(normalized_gap_y) || normalized_gap_y < 0 { normalized_gap_y = 0 }
	id := container_begin_simple(ui, .Grid, label=label, key=key, style=style, loc=loc, layout_boundary=layout_boundary)
	if id == 0 { return 0 }
	index := len(rt.pending)-1
	item := &rt.pending[index]
	item.grid_gap_x = normalized_gap_x
	item.grid_gap_y = normalized_gap_y
	item.grid_columns = make([]Grid_Track, len(columns), allocator=rt.scratch_allocator)
	item.grid_rows = make([]Grid_Track, len(rows), allocator=rt.scratch_allocator)
	copy(item.grid_columns, columns)
	copy(item.grid_rows, rows)
	rt.grid_pending_scopes[id] = true
	return id
}

grid_end :: proc(ui: ^UI) { container_end(ui) }

// grid_cell assigns an already-emitted direct child of the current Grid to a
// logical cell. Its alignment is independent of the Grid's track sizing.
grid_cell :: proc(
	ui: ^UI,
	child_id: Node_ID,
	row, column: int,
	row_span: int = 1,
	column_span: int = 1,
	align_x := Grid_Item_Alignment.Stretch,
	align_y := Grid_Item_Alignment.Stretch,
) -> bool {
	rt := ui.runtime
	if rt == nil || !rt.frame_open || child_id == 0 {
		if rt != nil { append_diagnostic(rt, "grid_cell requires a live child in an open description frame") }
		return false
	}
	parent_id := current_node_parent(ui)
	if _, parent_is_grid := rt.grid_pending_scopes[parent_id]; !parent_is_grid {
		append_diagnostic(rt, "grid_cell must be called while its direct parent Grid is open")
		return false
	}
	for i := len(rt.pending)-1; i >= 0; i -= 1 {
		item := &rt.pending[i]
		if item.kind != .Description || item.description.id != child_id { continue }
		if item.description.parent != parent_id {
			append_diagnostic(rt, "grid_cell child must be a direct child of a Grid")
			return false
		}
		if item.description.grid_item {
			append_diagnostic(rt, "grid_cell may assign a child to only one cell")
			return false
		}
		if row < 0 || column < 0 || row_span < 1 || column_span < 1 ||
			row > int(max(u16)) || column > int(max(u16)) || row_span > int(max(u16)) || column_span > int(max(u16)) {
			append_diagnostic(rt, "Grid cell indices must fit 16-bit nonnegative values and spans must be positive")
			return false
		}
		item.description.grid_item = true
		item.description.grid_row = u16(row)
		item.description.grid_column = u16(column)
		item.description.grid_row_span = u16(row_span)
		item.description.grid_column_span = u16(column_span)
		item.description.grid_align_x = align_x
		item.description.grid_align_y = align_y
		return true
	}
	append_diagnostic(rt, "grid_cell references a child that was not emitted in the current frame")
	return false
}

// grid_tracks_copy_retained replaces the track declarations only when their
// content hash changes. Pending slices live in the frame scratch arena; the
// retained copies belong to the owning Node and are released with it.
grid_tracks_copy_retained :: proc(rt: ^Runtime, node: ^Node, item: Pending_Item) {
	if rt == nil || node == nil { return }
	hash := grid_track_config_hash(item.grid_columns, item.grid_rows, item.grid_gap_x, item.grid_gap_y)
	if node.grid_configuration_hash == hash { return }
	if len(node.grid_columns) > 0 { delete(node.grid_columns) }
	if len(node.grid_rows) > 0 { delete(node.grid_rows) }
	node.grid_columns = make([dynamic]Grid_Track, 0, len(item.grid_columns), allocator=rt.persistent_allocator)
	node.grid_rows = make([dynamic]Grid_Track, 0, len(item.grid_rows), allocator=rt.persistent_allocator)
	for track in item.grid_columns { append(&node.grid_columns, track) }
	for track in item.grid_rows { append(&node.grid_rows, track) }
	node.grid_gap_x = item.grid_gap_x
	node.grid_gap_y = item.grid_gap_y
	node.grid_configuration_hash = hash
}

grid_tracks_destroy :: proc(node: ^Node) {
	if node == nil { return }
	if len(node.grid_columns) > 0 { delete(node.grid_columns) }
	if len(node.grid_rows) > 0 { delete(node.grid_rows) }
}

