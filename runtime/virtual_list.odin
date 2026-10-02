package alicorn

Virtual_List_Metrics :: struct {
	first:          int,
	last:           int,
	content_height: f32,
	max_scroll_y:   f32,
	offset_y:       f32,
	leading_offset_y: f32,
}

// Variable virtual lists keep only measured rows whose height differs from a
// stable estimate. This makes the index proportional to wrapped/expanded rows
// instead of document length. The application owns the measurements; Alicorn
// uses their prefix geometry to retain scrolling and emit a visible range.
Virtual_List_Height_Entry :: struct {
	index:       int,
	height:      f32,
	prefix_delta: f32,
}

Virtual_List_Height_Index :: struct {
	item_count:     int,
	estimated_height: f32,
	total_height:   f32,
	entries:        [dynamic]Virtual_List_Height_Entry,
	prefix_dirty:   bool,
}

virtual_list_height_index_init :: proc(
	index: ^Virtual_List_Height_Index,
	item_count: int,
	estimated_height: f32,
	allocator := context.allocator,
) -> bool {
	if index == nil || item_count < 0 || estimated_height <= 0 { return false }
	index^ = Virtual_List_Height_Index{
		item_count=item_count,
		estimated_height=estimated_height,
		total_height=f32(item_count)*estimated_height,
		entries=make([dynamic]Virtual_List_Height_Entry, 0, allocator=allocator),
	}
	return true
}

virtual_list_height_index_destroy :: proc(index: ^Virtual_List_Height_Index) {
	if index == nil { return }
	delete(index.entries)
	index^ = {}
}

virtual_list_height_index_rebuild_prefix :: proc(index: ^Virtual_List_Height_Index) {
	if index == nil || !index.prefix_dirty { return }
	delta: f32 = 0
	for &entry in index.entries {
		delta += entry.height-index.estimated_height
		entry.prefix_delta = delta
	}
	index.total_height = maxf(f32(index.item_count)*index.estimated_height+delta, 0)
	index.prefix_dirty = false
}

virtual_list_height_index_set_count :: proc(index: ^Virtual_List_Height_Index, item_count: int) -> bool {
	if index == nil || item_count < 0 || index.estimated_height <= 0 { return false }
	if index.item_count == item_count { return true }
	index.item_count = item_count
	for len(index.entries) > 0 && index.entries[len(index.entries)-1].index >= item_count {
		_ = pop(&index.entries)
	}
	index.prefix_dirty = true
	virtual_list_height_index_rebuild_prefix(index)
	return true
}

// apply_edit drops measurements for the replaced item range and shifts later
// item identities by the insertion/removal delta. The caller supplies the
// resulting collection size so the sparse geometry stays aligned with the
// logical collection after a source edit.
virtual_list_height_index_apply_edit :: proc(
	index: ^Virtual_List_Height_Index,
	first_item, removed_count, inserted_count, resulting_item_count: int,
) -> bool {
	if index == nil || first_item < 0 || removed_count < 0 || inserted_count < 0 || resulting_item_count < 0 ||
	   first_item+removed_count > index.item_count ||
	   resulting_item_count != index.item_count-removed_count+inserted_count {
		return false
	}
	old_end := first_item+removed_count
	delta := inserted_count-removed_count
	write := 0
	for read in 0..<len(index.entries) {
		entry := index.entries[read]
		if entry.index < first_item {
			index.entries[write] = entry
			write += 1
			continue
		}
		if entry.index < old_end { continue }
		entry.index += delta
		if entry.index >= 0 && entry.index < resulting_item_count {
			index.entries[write] = entry
			write += 1
		}
	}
	for len(index.entries) > write { _ = pop(&index.entries) }
	index.item_count = resulting_item_count
	index.prefix_dirty = true
	virtual_list_height_index_rebuild_prefix(index)
	return true
}

// set_height inserts or updates one measured item. Prefix sums are rebuilt
// lazily, so a caller can apply a bounded batch before requesting metrics.
virtual_list_height_index_set_height :: proc(index: ^Virtual_List_Height_Index, item_index: int, height: f32) -> bool {
	if index == nil || item_index < 0 || item_index >= index.item_count || height <= 0 { return false }
	low, high := 0, len(index.entries)
	for low < high {
		mid := (low+high)/2
		if index.entries[mid].index < item_index { low = mid+1 } else { high = mid }
	}
	found := low < len(index.entries) && index.entries[low].index == item_index
	if found {
		previous := index.entries[low].height
		if abs(previous-height) < 0.01 { return false }
		index.entries[low].height = height
		index.total_height = maxf(index.total_height+height-previous, 0)
		if abs(height-index.estimated_height) < 0.01 {
			ordered_remove(&index.entries, low)
		}
	} else {
		if abs(height-index.estimated_height) < 0.01 { return false }
		index.total_height += height-index.estimated_height
		append(&index.entries, Virtual_List_Height_Entry{})
		for move := len(index.entries)-1; move > low; move -= 1 {
			index.entries[move] = index.entries[move-1]
		}
		index.entries[low] = Virtual_List_Height_Entry{index=item_index, height=height}
	}
	index.prefix_dirty = true
	return true
}

virtual_list_height_index_item_height :: proc(index: ^Virtual_List_Height_Index, item_index: int) -> f32 {
	if index == nil || item_index < 0 || item_index >= index.item_count { return 0 }
	low, high := 0, len(index.entries)
	for low < high {
		mid := (low+high)/2
		if index.entries[mid].index < item_index { low = mid+1 } else { high = mid }
	}
	if low < len(index.entries) && index.entries[low].index == item_index {
		return index.entries[low].height
	}
	return index.estimated_height
}

virtual_list_height_index_item_top :: proc(index: ^Virtual_List_Height_Index, item_index: int) -> f32 {
	if index == nil || item_index <= 0 { return 0 }
	virtual_list_height_index_rebuild_prefix(index)
	bounded := min(item_index, index.item_count)
	low, high := 0, len(index.entries)
	for low < high {
		mid := (low+high)/2
		if index.entries[mid].index < bounded { low = mid+1 } else { high = mid }
	}
	extra: f32 = 0
	if low > 0 { extra = index.entries[low-1].prefix_delta }
	return f32(bounded)*index.estimated_height+extra
}

// item_at maps a content-space Y coordinate to its logical item. The result is
// clamped at document edges so caret paging can resolve a visual destination
// through sparse row-height measurements without scanning the document.
virtual_list_height_index_item_at :: proc(index: ^Virtual_List_Height_Index, content_y: f32) -> int {
	if index == nil || index.item_count <= 0 { return -1 }
	virtual_list_height_index_rebuild_prefix(index)
	target := clampf(content_y, 0, max(index.total_height-0.001, 0))
	low, high := 0, index.item_count
	for low < high {
		mid := (low+high)/2
		if virtual_list_height_index_item_top(index, mid+1) <= target { low = mid+1 } else { high = mid }
	}
	return min(low, index.item_count-1)
}

virtual_list_variable_metrics :: proc(
	index: ^Virtual_List_Height_Index,
	scroll_y, viewport_height: f32,
) -> Virtual_List_Metrics {
	result := Virtual_List_Metrics{}
	if index == nil || index.item_count <= 0 || index.estimated_height <= 0 || viewport_height <= 0 { return result }
	virtual_list_height_index_rebuild_prefix(index)
	result.content_height = index.total_height
	result.max_scroll_y = maxf(result.content_height-viewport_height, 0)
	result.offset_y = clampf(scroll_y, 0, result.max_scroll_y)
	// Find the first row whose bottom lies after the viewport's leading edge.
	low, high := 0, index.item_count
	for low < high {
		mid := (low+high)/2
		if virtual_list_height_index_item_top(index, mid+1) <= result.offset_y { low = mid+1 } else { high = mid }
	}
	result.first = min(low, index.item_count-1)
	viewport_end := result.offset_y+viewport_height
	// Include every row whose top is strictly before the viewport's trailing edge.
	low, high = result.first+1, index.item_count
	for low < high {
		mid := (low+high)/2
		if virtual_list_height_index_item_top(index, mid) < viewport_end { low = mid+1 } else { high = mid }
	}
	result.last = max(result.first+1, low)
	result.leading_offset_y = result.offset_y-virtual_list_height_index_item_top(index, result.first)
	return result
}

virtual_list_variable_ensure_visible :: proc(
	rt: ^Runtime,
	index: ^Virtual_List_Height_Index,
	id: Node_ID,
	item_index: int,
	reason := "variable virtual list selection visibility changed",
) -> bool {
	node, ok := rt.nodes[id]
	if !ok || !node.active || node.kind != .Scroll_Region || index == nil || item_index < 0 || item_index >= index.item_count { return false }
	viewport := node.scroll_viewport_height
	if viewport <= 0 && !node.scroll_geometry_resolved { viewport = node.bounds.h }
	if viewport <= 0 { return false }
	top := virtual_list_height_index_item_top(index, item_index)
	bottom := top+virtual_list_height_index_item_height(index, item_index)
	next := node.scroll_offset_y
	if top < next { next = top } else if bottom > next+viewport { next = bottom-viewport }
	return scroll_region_set_offset(rt, id, next, reason)
}

// virtual_list_metrics is the shared fixed-height scroll calculation. It
// clamps the offset to the actual content/viewport bounds and preserves the
// fractional leading offset so a list can move continuously between rows.
virtual_list_metrics :: proc(item_count: int, scroll_y, viewport_height, row_height: f32) -> Virtual_List_Metrics {
	result := Virtual_List_Metrics{}
	if item_count <= 0 || row_height <= 0 || viewport_height <= 0 { return result }
	result.content_height = f32(item_count) * row_height
	result.max_scroll_y = maxf(result.content_height-viewport_height, 0)
	result.offset_y = clampf(scroll_y, 0, result.max_scroll_y)
	result.first = int(result.offset_y / row_height)
	if result.first >= item_count { result.first = item_count-1 }
	result.last = int((result.offset_y+viewport_height) / row_height) + 1
	if result.last > item_count { result.last = item_count }
	if result.last < result.first+1 { result.last = result.first+1 }
	result.leading_offset_y = result.offset_y - f32(result.first)*row_height
	return result
}

// Virtual_List_Handle is the resolved, current-description view of a retained
// fixed-row list. The application owns row data and logical keys; Alicorn owns
// the retained scroll offset and returns only the range that needs emission.
Virtual_List_Handle :: struct {
	scroll: Scroll_Region_Handle,
	first:  int,
	last:   int,
}

// virtual_list_begin composes the common retained scroll-region and
// fixed-height virtualization path. It opens both the scroll region and its
// clipped virtual-list content container; call virtual_list_end after emitting
// rows. The range is bounded to visible/frontier work and remains valid for
// fractional scroll offsets.
virtual_list_begin :: proc(
	ui: ^UI,
	item_count: int,
	row_height: f32,
	key: UI_Key = UI_Unkeyed{},
	style := DEFAULT_STYLE,
	content_width: f32 = 0,
	line_width: f32 = 24,
	color := NO_BACKGROUND_COLOR,
	label := "virtual-list",
	loc := #caller_location,
	axes := Scroll_Axes.Vertical,
	axis_behavior := Scroll_Axis_Behavior.Auto_Lock,
	scrollbars := Scrollbar_Policy.Auto,
	focusable := false,
) -> Virtual_List_Handle {
	if item_count < 0 || row_height <= 0 { return {} }
	region_style := style
	region_style.direction = .Column
	region_style.clip = true
	content_height := f32(item_count) * row_height
	scroll := scroll_region_begin(
		ui,
		key=key,
		content_height=content_height,
		line_height=row_height,
		content_width=content_width,
		line_width=line_width,
		style=region_style,
		color=color,
		label=label,
		loc=loc,
		axes=axes,
		axis_behavior=axis_behavior,
		scrollbars=scrollbars,
		focusable=focusable,
	)
	if scroll.id == 0 { return {} }
	metrics := virtual_list_metrics(item_count, scroll.offset_y, scroll.viewport_height, row_height)
	// The content node is clipped to the resolved scroll viewport. Give it
	// that same height explicitly: an unconstrained Column child otherwise
	// falls back to intrinsic_main's default 24 logical pixels, which clips
	// taller rows differently across displays with different pixel densities.
	content_style := layout_style(width=-1, height=scroll.viewport_height, clip=true)
	if content_width > 0 { content_style.width = content_width }
	container_begin(
		ui,
		.Virtual_List,
		label=label,
		style=content_style,
		loc=loc,
		scroll_offset_y=metrics.offset_y,
		layout_scroll_offset_y=metrics.leading_offset_y,
		scroll_offset_x=scroll.offset_x,
		layout_scroll_offset_x=scroll.offset_x,
	)
	return Virtual_List_Handle{scroll=scroll, first=metrics.first, last=metrics.last}
}

// virtual_list_begin_variable composes the same retained scroll/clip boundary
// as virtual_list_begin while accepting sparse measured item heights. Rows are
// still emitted with stable application keys; their measured sizes determine
// the visible range and the fractional offset of its first item.
virtual_list_begin_variable :: proc(
	ui: ^UI,
	index: ^Virtual_List_Height_Index,
	key: UI_Key = UI_Unkeyed{},
	style := DEFAULT_STYLE,
	content_width: f32 = 0,
	line_width: f32 = 24,
	color := NO_BACKGROUND_COLOR,
	label := "virtual-list",
	loc := #caller_location,
	axes := Scroll_Axes.Vertical,
	axis_behavior := Scroll_Axis_Behavior.Auto_Lock,
	scrollbars := Scrollbar_Policy.Auto,
	focusable := false,
) -> Virtual_List_Handle {
	if index == nil || index.item_count < 0 || index.estimated_height <= 0 { return {} }
	virtual_list_height_index_rebuild_prefix(index)
	region_style := style
	region_style.direction = .Column
	region_style.clip = true
	scroll := scroll_region_begin(
		ui,
		key=key,
		content_height=index.total_height,
		line_height=index.estimated_height,
		content_width=content_width,
		line_width=line_width,
		style=region_style,
		color=color,
		label=label,
		loc=loc,
		axes=axes,
		axis_behavior=axis_behavior,
		scrollbars=scrollbars,
		focusable=focusable,
	)
	if scroll.id == 0 { return {} }
	metrics := virtual_list_variable_metrics(index, scroll.offset_y, scroll.viewport_height)
	content_style := layout_style(width=-1, height=scroll.viewport_height, clip=true)
	if content_width > 0 { content_style.width = content_width }
	container_begin(
		ui,
		.Virtual_List,
		label=label,
		style=content_style,
		loc=loc,
		scroll_offset_y=metrics.offset_y,
		layout_scroll_offset_y=metrics.leading_offset_y,
		scroll_offset_x=scroll.offset_x,
		layout_scroll_offset_x=scroll.offset_x,
	)
	return Virtual_List_Handle{scroll=scroll, first=metrics.first, last=metrics.last}
}

virtual_list_end :: proc(ui: ^UI, list: Virtual_List_Handle) {
	if list.scroll.id == 0 { return }
	container_end(ui)
	scroll_region_end(ui)
}

// virtual_list requires a logical item key. Viewport position is not identity:
// callers must return the same key for an item when it moves in the source data.
// The realized children are clipped to the list viewport and receive the
// fractional offset from virtual_list_metrics.
virtual_list_ex :: proc(ui: ^UI, item_count: int, scroll_y, viewport_height, row_height: f32, source: Source_Site, item_key: proc(index: int) -> string, row: proc(ui: ^UI, index: int)) -> (first, last: int) {
	metrics := virtual_list_metrics(item_count, scroll_y, viewport_height, row_height)
	first, last = metrics.first, metrics.last
	if first == last { return }
	style := Layout_Style{.Column, -1, viewport_height, 0, -1, 0, -1, 0, 0, 0, .Stretch, true}
	container_begin_ex(ui, .Virtual_List, source, label="virtual-list", style=style, scroll_offset_y=metrics.offset_y, layout_scroll_offset_y=metrics.leading_offset_y)
	for i := first; i < last; i += 1 {
		if key_scope_begin_ex(ui, item_key(i), source) {
			row(ui, i)
			key_scope_end(ui)
		}
	}
	container_end(ui)
	return
}

virtual_list_simple :: proc(ui: ^UI, item_count: int, scroll_y, viewport_height, row_height: f32, item_key: proc(index: int) -> UI_Key, row: proc(ui: ^UI, index: int), loc := #caller_location) -> (first, last: int) {
	metrics := virtual_list_metrics(item_count, scroll_y, viewport_height, row_height)
	first, last = metrics.first, metrics.last
	if first == last { return }
	style := Layout_Style{.Column, -1, viewport_height, 0, -1, 0, -1, 0, 0, 0, .Stretch, true}
	container_begin_simple(ui, .Virtual_List, label="virtual-list", style=style, loc=loc, scroll_offset_y=metrics.offset_y, layout_scroll_offset_y=metrics.leading_offset_y)
	for i := first; i < last; i += 1 {
		if key_scope_begin_key(ui, item_key(i), Source_Site{}, loc) {
			row(ui, i)
			key_scope_end(ui)
		}
	}
	container_end(ui)
	return
}

virtual_list :: proc(ui: ^UI, item_count: int, scroll_y, viewport_height, row_height: f32, item_key: proc(index: int) -> UI_Key, row: proc(ui: ^UI, index: int), loc := #caller_location) -> (first, last: int) {
	return virtual_list_simple(ui, item_count, scroll_y, viewport_height, row_height, item_key, row, loc)
}

