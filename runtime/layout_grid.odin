package alicorn

import "core:fmt"
import "core:math"
import "core:mem"

grid_axis_size :: proc(size: Layout_Size, direction: Layout_Direction) -> Layout_Unit {
	return size.width if direction == .Row else size.height
}

grid_axis_minimum :: proc(style: Layout_Style, direction: Layout_Direction) -> f32 {
	return style.min_width if direction == .Row else style.min_height
}

grid_axis_maximum :: proc(style: Layout_Style, direction: Layout_Direction) -> f32 {
	return style.max_width if direction == .Row else style.max_height
}

grid_axis_track_items :: proc(
	rt: ^Runtime,
	parent: ^Node,
	tracks: []Grid_Track,
	direction: Layout_Direction,
) -> []Elastic_Item {
	items := make([]Elastic_Item, len(tracks), allocator=rt.scratch_allocator)
	maximum_weight: f32 = 0
	for track in tracks {
		parent.grid_work_units += 1
		if track.kind == .Fraction && layout_grow_weight_is_finite_positive(track.value) && track.value > maximum_weight {
			maximum_weight = track.value
		}
	}
	for track, index in tracks {
		parent.grid_work_units += 1
		item := Elastic_Item{}
		switch track.kind {
		case .Fixed:
			value := track.value
			if math.is_nan(value) || math.is_inf(value) || value < 0 {
				record_trace(rt, .Layout, parent.id, fmt.tprintf("Grid %v track %d has invalid fixed extent; using zero", direction, index))
				value = 0
			}
			units := layout_unit_extent(value)
			item = Elastic_Item{minimum=units, ideal=units, maximum=units}
		case .Auto:
			item = Elastic_Item{minimum=0, ideal=0, max_unbounded=true, compress_weight=1}
		case .Fraction:
			weight := layout_grow_weight_units(track.value, maximum_weight)
			if weight == 0 {
				record_trace(rt, .Layout, parent.id, fmt.tprintf("Grid %v fraction track %d has a nonpositive weight; using weight 1", direction, index))
				weight = 1
			}
			item = Elastic_Item{minimum=0, ideal=0, max_unbounded=true, expand_weight=weight, compress_weight=1}
		case .Min_Max:
			minimum := track.minimum
			maximum := track.maximum
			if math.is_nan(minimum) || math.is_inf(minimum) || minimum < 0 {
				record_trace(rt, .Layout, parent.id, fmt.tprintf("Grid %v minmax track %d has invalid minimum; using zero", direction, index))
				minimum = 0
			}
			min_units := layout_unit_extent(minimum)
			unbounded := maximum < 0 && !math.is_nan(maximum) && !math.is_inf(maximum)
			max_units := min_units
			if !unbounded {
				if math.is_nan(maximum) || math.is_inf(maximum) {
					record_trace(rt, .Layout, parent.id, fmt.tprintf("Grid %v minmax track %d has invalid maximum; using its minimum", direction, index))
				} else {
					max_units = layout_unit_maximum(maximum)
				}
			}
			if !unbounded && max_units < min_units {
				record_trace(rt, .Layout, parent.id, fmt.tprintf("Grid %v minmax track %d has maximum below minimum; clamping maximum", direction, index))
				max_units = min_units
			}
			item = Elastic_Item{minimum=min_units, ideal=min_units, maximum=max_units, max_unbounded=unbounded, expand_weight=1, compress_weight=1}
		}
		items[index] = item
	}
	return items
}

grid_item_cell_valid :: proc(rt: ^Runtime, parent: ^Node, child: ^Node, report := true) -> bool {
	if !child.grid_item {
		if report { record_trace(rt, .Layout, child.id, "Grid child has no explicit cell; skipped") }
		return false
	}
	if int(child.grid_row)+int(child.grid_row_span) > len(parent.grid_rows) ||
		int(child.grid_column)+int(child.grid_column_span) > len(parent.grid_columns) {
		if report {
			record_trace(rt, .Layout, child.id, fmt.tprintf(
				"Grid cell (%d,%d) span (%d,%d) is outside %d rows x %d columns; skipped",
				int(child.grid_row), int(child.grid_column), int(child.grid_row_span), int(child.grid_column_span),
				len(parent.grid_rows), len(parent.grid_columns),
			))
		}
		return false
	}
	return true
}

grid_child_constraints_unbounded :: proc() -> Layout_Constraints {
	unbounded := layout_axis_constraint_normalize(0, -1)
	return Layout_Constraints{width=unbounded, height=unbounded}
}

grid_add_track_contribution :: proc(
	rt: ^Runtime,
	parent: ^Node,
	child: ^Node,
	items: []Elastic_Item,
	tracks: []Grid_Track,
	index: int,
	direction: Layout_Direction,
) {
	if index < 0 || index >= len(items) { return }
	minimum_value := grid_axis_minimum(child.style, direction)
	if math.is_nan(minimum_value) || math.is_inf(minimum_value) || minimum_value < 0 {
		record_trace(rt, .Layout, child.id, fmt.tprintf("Grid item has invalid %v minimum; using zero", direction))
		minimum_value = 0
	}
	minimum := layout_unit_extent(minimum_value)
	measured := layout_unit_maximum(layout_unit_to_f32(grid_axis_size(rt.measure_states[child.id].result.size, direction)))
	item := &items[index]
	if tracks[index].kind == .Fixed {
		if max(measured, minimum) > item.ideal {
			record_trace(rt, .Layout, child.id, fmt.tprintf("Grid %v fixed track %d is smaller than its item minimum or measurement", direction, index))
		}
		return
	}
	if !item.max_unbounded && minimum > item.maximum {
		record_trace(rt, .Layout, child.id, fmt.tprintf("Grid %v item minimum %.3f exceeds track %d maximum %.3f; clamping to the track maximum", direction, layout_unit_to_f32(minimum), index, layout_unit_to_f32(item.maximum)))
		minimum = item.maximum
	}
	if minimum > item.minimum { item.minimum = minimum }
	ideal := max(item.ideal, measured)
	ideal = max(ideal, item.minimum)
	if !item.max_unbounded && ideal > item.maximum { ideal = item.maximum }
	item.ideal = ideal
}

grid_axis_available :: proc(extent, gap: f32, track_count: int) -> Layout_Unit {
	available := i64(layout_unit_maximum(maxf(extent, 0)))
	gap_units := max(i64(layout_unit_extent(maxf(gap, 0))), 0)
	gap_total := u128(gap_units)*u128(max(track_count-1, 0))
	if gap_total >= u128(available) { return 0 }
	return Layout_Unit(available-i64(gap_total))
}

grid_span_extent :: proc(sizes: []Layout_Unit, start, span: int, gap: Layout_Unit) -> Layout_Unit {
	limit := u128(i64(LAYOUT_ALLOCATOR_UNIT_LIMIT))
	extent := u128(max(i64(gap), 0))*u128(max(span-1, 0))
	if extent >= limit { return LAYOUT_ALLOCATOR_UNIT_LIMIT }
	for i in start..<start+span {
		extent += u128(max(i64(sizes[i]), 0))
		if extent >= limit { return LAYOUT_ALLOCATOR_UNIT_LIMIT }
	}
	return Layout_Unit(i64(extent))
}

grid_axis_positions :: proc(parent: ^Node, sizes: []Layout_Unit, gap: Layout_Unit, allocator: mem.Allocator) -> []Layout_Unit {
	positions := make([]Layout_Unit, len(sizes), allocator=allocator)
	limit := u128(i64(LAYOUT_ALLOCATOR_UNIT_LIMIT))
	cursor: u128 = 0
	for size, index in sizes {
		positions[index] = Layout_Unit(i64(min(cursor, limit)))
		cursor += u128(max(i64(size), 0))
		if index+1 < len(sizes) { cursor += u128(max(i64(gap), 0)) }
		if cursor > limit { cursor = limit }
		parent.grid_work_units += 1
	}
	return positions
}

grid_span_minimum_extent :: proc(items: []Elastic_Item, start, span: int, gap: Layout_Unit) -> Layout_Unit {
	limit := u128(i64(LAYOUT_ALLOCATOR_UNIT_LIMIT))
	extent := u128(max(i64(gap), 0))*u128(max(span-1, 0))
	if extent >= limit { return LAYOUT_ALLOCATOR_UNIT_LIMIT }
	for i in start..<start+span {
		extent += u128(max(i64(items[i].minimum), 0))
		if extent >= limit { return LAYOUT_ALLOCATOR_UNIT_LIMIT }
	}
	return Layout_Unit(i64(extent))
}

grid_adjust_span_minimums :: proc(
	rt: ^Runtime,
	parent: ^Node,
	children: []Node_ID,
	items: []Elastic_Item,
	tracks: []Grid_Track,
	gap: Layout_Unit,
	direction: Layout_Direction,
) {
	for child_id in children {
		child := rt.nodes[child_id]
		parent.grid_work_units += 1
		if !grid_item_cell_valid(rt, parent, child, report=false) { continue }
		start := int(child.grid_column)
		span := int(child.grid_column_span)
		if direction == .Column { start, span = int(child.grid_row), int(child.grid_row_span) }
		if span <= 1 { continue }
		minimum_value := grid_axis_minimum(child.style, direction)
		if math.is_nan(minimum_value) || math.is_inf(minimum_value) || minimum_value < 0 {
			record_trace(rt, .Layout, child_id, fmt.tprintf("Grid %v span [%d,%d) has invalid item minimum; using zero", direction, start, start+span))
			minimum_value = 0
		}
		required := layout_unit_extent(minimum_value)
		parent.grid_work_units += u64(span)
		current := grid_span_minimum_extent(items, start, span, gap)
		remaining := i64(required)-i64(current)
		adjusted := false
		if remaining > 0 {
			eligible := 0
			for i in start..<start+span {
				parent.grid_work_units += 1
				if tracks[i].kind != .Fixed && (items[i].max_unbounded || items[i].maximum > items[i].minimum) { eligible += 1 }
			}
			if eligible > 0 {
				share := (remaining+i64(eligible)-1)/i64(eligible)
				for i in start..<start+span {
					if tracks[i].kind == .Fixed { continue }
					room := remaining
					if !items[i].max_unbounded { room = i64(items[i].maximum-items[i].minimum) }
					if room <= 0 { continue }
					add := min(share, min(room, remaining))
					items[i].minimum += Layout_Unit(add)
					if items[i].ideal < items[i].minimum { items[i].ideal = items[i].minimum }
					remaining -= add
					parent.grid_work_units += 1
					adjusted = true
				}
				for i in start..<start+span {
					if remaining <= 0 { break }
					if tracks[i].kind == .Fixed { continue }
					room := remaining
					if !items[i].max_unbounded { room = i64(items[i].maximum-items[i].minimum) }
					if room <= 0 { continue }
					add := min(room, remaining)
					items[i].minimum += Layout_Unit(add)
					if items[i].ideal < items[i].minimum { items[i].ideal = items[i].minimum }
					remaining -= add
					parent.grid_work_units += 1
					adjusted = true
				}
			}
		}
		record_trace(rt, .Layout, child_id, fmt.tprintf("Grid %v span [%d,%d) minimum=%.3f tracks-before=%.3f raised=%t unresolved=%.3f after track limits", direction, start, start+span, layout_unit_to_f32(required), layout_unit_to_f32(current), adjusted, layout_unit_to_f32(Layout_Unit(remaining))))
	}
}

grid_adjust_span_ideals :: proc(
	rt: ^Runtime,
	parent: ^Node,
	children: []Node_ID,
	items: []Elastic_Item,
	tracks: []Grid_Track,
	sizes: []Layout_Unit,
	gap: Layout_Unit,
	direction: Layout_Direction,
) -> bool {
	changed := false
	for child_id in children {
		child := rt.nodes[child_id]
		parent.grid_work_units += 1
		if !grid_item_cell_valid(rt, parent, child, report=false) { continue }
		start := int(child.grid_column)
		span := int(child.grid_column_span)
		if direction == .Column { start, span = int(child.grid_row), int(child.grid_row_span) }
		if span <= 1 { continue }
		demand := grid_axis_size(rt.measure_states[child_id].result.size, direction)
		parent.grid_work_units += u64(span)
		current := grid_span_extent(sizes, start, span, gap)
		deficit := i64(demand)-i64(current)
		if deficit <= 0 {
			record_trace(rt, .Layout, child_id, fmt.tprintf("Grid %v span [%d,%d) measured=%.3f current=%.3f adjusted=false unresolved=0.000", direction, start, start+span, layout_unit_to_f32(demand), layout_unit_to_f32(current)))
			continue
		}
		eligible := 0
		for i in start..<start+span {
			parent.grid_work_units += 1
			if tracks[i].kind != .Fixed && (items[i].max_unbounded || items[i].maximum > items[i].ideal) { eligible += 1 }
		}
		if eligible == 0 {
			record_trace(rt, .Layout, child_id, fmt.tprintf("Grid %v span [%d,%d) measured=%.3f current=%.3f adjusted=false unresolved=%.3f; fixed/capped tracks prevent contribution", direction, start, start+span, layout_unit_to_f32(demand), layout_unit_to_f32(current), layout_unit_to_f32(Layout_Unit(deficit))))
			continue
		}
		remaining := deficit
		adjusted := false
		// One fair-share pass, then one stable remainder pass. This keeps span
		// work proportional to the total covered track length.
		share := (remaining+i64(eligible)-1)/i64(eligible)
		for i in start..<start+span {
			if tracks[i].kind == .Fixed { continue }
			room := remaining
			if !items[i].max_unbounded { room = i64(items[i].maximum-items[i].ideal) }
			if room <= 0 { continue }
			add := min(share, min(room, remaining))
			items[i].ideal += Layout_Unit(add)
			sizes[i] += Layout_Unit(add)
			remaining -= add
			parent.grid_work_units += 1
			adjusted = true
		}
		for i in start..<start+span {
			if remaining <= 0 { break }
			if tracks[i].kind == .Fixed { continue }
			room := remaining
			if !items[i].max_unbounded { room = i64(items[i].maximum-items[i].ideal) }
			if room <= 0 { continue }
			add := min(room, remaining)
			items[i].ideal += Layout_Unit(add)
			sizes[i] += Layout_Unit(add)
			remaining -= add
			parent.grid_work_units += 1
			adjusted = true
		}
		record_trace(rt, .Layout, child_id, fmt.tprintf("Grid %v span [%d,%d) measured=%.3f current=%.3f adjusted=%t unresolved=%.3f after track limits", direction, start, start+span, layout_unit_to_f32(demand), layout_unit_to_f32(current), adjusted, layout_unit_to_f32(Layout_Unit(remaining))))
		changed = changed || adjusted
	}
	return changed
}

grid_resolve_axis :: proc(
	rt: ^Runtime,
	parent: ^Node,
	children: []Node_ID,
	items: []Elastic_Item,
	tracks: []Grid_Track,
	available: Layout_Unit,
	gap: Layout_Unit,
	direction: Layout_Direction,
	sizes: []Layout_Unit,
) {
	grid_adjust_span_minimums(rt, parent, children, items, tracks, gap, direction)
	allocation := layout_allocate_axis(available, items, sizes)
	record_trace(rt, .Layout, parent.id, fmt.tprintf("Grid %v allocation available=%.3f overflow=%.3f unused=%.3f redistribution-passes=%d invalid-items=%d", direction, layout_unit_to_f32(available), layout_unit_to_f32(allocation.overflow), layout_unit_to_f32(allocation.unused), allocation.redistribution_passes, allocation.invalid_items))
	if grid_adjust_span_ideals(rt, parent, children, items, tracks, sizes, gap, direction) {
		allocation = layout_allocate_axis(available, items, sizes)
		record_trace(rt, .Layout, parent.id, fmt.tprintf("Grid %v post-span allocation available=%.3f overflow=%.3f unused=%.3f redistribution-passes=%d invalid-items=%d", direction, layout_unit_to_f32(available), layout_unit_to_f32(allocation.overflow), layout_unit_to_f32(allocation.unused), allocation.redistribution_passes, allocation.invalid_items))
	}
	for index in 0..<len(tracks) {
		parent.grid_work_units += 1
		if items[index].max_unbounded {
			record_trace(rt, .Layout, parent.id, fmt.tprintf(
				"Grid %v track %d declared=%v resolved=%.3f min=%.3f ideal=%.3f max=unbounded",
				direction, index, tracks[index].kind, layout_unit_to_f32(sizes[index]),
				layout_unit_to_f32(items[index].minimum), layout_unit_to_f32(items[index].ideal),
			))
		} else {
			record_trace(rt, .Layout, parent.id, fmt.tprintf(
				"Grid %v track %d declared=%v resolved=%.3f min=%.3f ideal=%.3f max=%.3f",
				direction, index, tracks[index].kind, layout_unit_to_f32(sizes[index]),
				layout_unit_to_f32(items[index].minimum), layout_unit_to_f32(items[index].ideal),
				layout_unit_to_f32(items[index].maximum),
			))
		}
	}
}

grid_child_span_width :: proc(sizes: []Layout_Unit, child: ^Node, gap: Layout_Unit) -> f32 {
	return layout_unit_to_f32(grid_span_extent(sizes, int(child.grid_column), int(child.grid_column_span), gap))
}

grid_cell_bounds :: proc(
	child: ^Node,
	inner: Rect,
	column_sizes, row_sizes: []Layout_Unit,
	column_positions, row_positions: []Layout_Unit,
	gap_x, gap_y: Layout_Unit,
	rtl: bool,
) -> Rect {
	column_offset := column_positions[int(child.grid_column)]
	row_offset := row_positions[int(child.grid_row)]
	w := grid_span_extent(column_sizes, int(child.grid_column), int(child.grid_column_span), gap_x)
	h := grid_span_extent(row_sizes, int(child.grid_row), int(child.grid_row_span), gap_y)
	x := inner.x+layout_unit_to_f32(column_offset)
	if rtl { x = inner.x+inner.w-layout_unit_to_f32(column_offset)-layout_unit_to_f32(w) }
	y := inner.y+layout_unit_to_f32(row_offset)
	return Rect{x, y, layout_unit_to_f32(w), layout_unit_to_f32(h)}
}

grid_desired_child_extent :: proc(rt: ^Runtime, child: ^Node, direction: Layout_Direction, available: f32) -> f32 {
	style_extent := child.style.width if direction == .Row else child.style.height
	if style_extent >= 0 { return clampf(style_extent, grid_axis_minimum(child.style, direction), grid_axis_maximum(child.style, direction)) }
	if state, ok := rt.measure_states[child.id]; ok && state.cache_key.valid {
		measured := layout_unit_to_f32(grid_axis_size(state.result.size, direction))
		if node_has_text_product(child.kind) && child.text_run_valid {
			if direction == .Row {
				measured = child.text_run.width
				if child.kind == .Button { measured += 2*maxf(child.button_content_style.padding_x, 0) }
				if child.kind == .Checkbox { measured += 36 }
			}
		}
		return minf(clampf(measured, grid_axis_minimum(child.style, direction), grid_axis_maximum(child.style, direction)), available)
	}
	return minf(available, 24)
}

grid_align_x_position :: proc(rt: ^Runtime, parent: ^Node, child: ^Node, cell: Rect, width: f32) -> f32 {
	space := maxf(cell.w-width, 0)
	align := child.grid_align_x
	if align == .Start && layout_effective_writing_direction(rt, parent) == .Left_To_Right ||
		align == .End && layout_effective_writing_direction(rt, parent) == .Right_To_Left { return cell.x }
	if align == .End && layout_effective_writing_direction(rt, parent) == .Left_To_Right ||
		align == .Start && layout_effective_writing_direction(rt, parent) == .Right_To_Left { return cell.x+space }
	if align == .Center { return cell.x+space*0.5 }
	return cell.x
}

layout_grid_children :: proc(rt: ^Runtime, parent: ^Node, inner: Rect, children: []Node_ID) {
	column_count, row_count := len(parent.grid_columns), len(parent.grid_rows)
	if column_count == 0 || row_count == 0 {
		record_trace(rt, .Layout, parent.id, "Grid has no retained track configuration")
		return
	}
	if layout_size_is_fit_content(parent.style.width) || layout_size_is_fit_content(parent.style.height) {
		record_trace(rt, .Layout, parent.id, "Grid content-sized outer bounds are unsupported; set explicit or parent-allocated dimensions")
	}
	parent.grid_work_units = 0
	column_gap := layout_unit_extent(maxf(parent.grid_gap_x, 0))
	row_gap := layout_unit_extent(maxf(parent.grid_gap_y, 0))
	column_items := grid_axis_track_items(rt, parent, parent.grid_columns[:], .Row)
	defer delete(column_items, rt.scratch_allocator)
	row_items := grid_axis_track_items(rt, parent, parent.grid_rows[:], .Column)
	defer delete(row_items, rt.scratch_allocator)
	column_sizes := make([]Layout_Unit, column_count, allocator=rt.scratch_allocator)
	defer delete(column_sizes, rt.scratch_allocator)
	row_sizes := make([]Layout_Unit, row_count, allocator=rt.scratch_allocator)
	defer delete(row_sizes, rt.scratch_allocator)
	// First measure each realized item with no guessed width. This supplies
	// horizontal auto-track and non-spanning contributions only.
	for child_id in children {
		child := rt.nodes[child_id]
		layout_note_node_visit(rt, child)
		parent.grid_work_units += 1
		if !grid_item_cell_valid(rt, parent, child) { continue }
		// Grid needs intrinsic column contributions even when a retained Text_Run
		// currently reflects an older, narrower assigned cell width.
		_ = layout_measure_node(rt, child, grid_child_constraints_unbounded(), force_unbounded_text_shape=true)
		if child.grid_column_span == 1 {
			grid_add_track_contribution(rt, parent, child, column_items, parent.grid_columns[:], int(child.grid_column), .Row)
		}
	}
	column_available := grid_axis_available(inner.w, parent.grid_gap_x, column_count)
	grid_resolve_axis(rt, parent, children, column_items, parent.grid_columns[:], column_available, column_gap, .Row, column_sizes)
	rtl := layout_effective_writing_direction(rt, parent) == .Right_To_Left
	// Resolve final columns before measuring width-dependent children. This is
	// the one supported width -> wrapped-height coupling phase.
	for child_id in children {
		child := rt.nodes[child_id]
		parent.grid_work_units += 1
		if !grid_item_cell_valid(rt, parent, child, report=false) { continue }
		parent.grid_work_units += u64(child.grid_column_span)
		assigned_width := grid_child_span_width(column_sizes, child, column_gap)
		constraints := Layout_Constraints{
			width=layout_axis_constraint_normalize(assigned_width, assigned_width),
			height=layout_axis_constraint_normalize(0, -1),
		}
		_ = layout_measure_node(rt, child, constraints)
		if child.grid_row_span == 1 {
			grid_add_track_contribution(rt, parent, child, row_items, parent.grid_rows[:], int(child.grid_row), .Column)
		}
	}
	row_available := grid_axis_available(inner.h, parent.grid_gap_y, row_count)
	grid_resolve_axis(rt, parent, children, row_items, parent.grid_rows[:], row_available, row_gap, .Column, row_sizes)
	column_positions := grid_axis_positions(parent, column_sizes, column_gap, rt.scratch_allocator)
	defer delete(column_positions, rt.scratch_allocator)
	row_positions := grid_axis_positions(parent, row_sizes, row_gap, rt.scratch_allocator)
	defer delete(row_positions, rt.scratch_allocator)
	baseline_by_row := make([]f32, row_count, allocator=rt.scratch_allocator)
	defer delete(baseline_by_row, rt.scratch_allocator)
	for child_id in children {
		child := rt.nodes[child_id]
		parent.grid_work_units += 1
		if !grid_item_cell_valid(rt, parent, child, report=false) || child.grid_row_span != 1 || child.grid_align_y != .Baseline { continue }
		if state, ok := rt.measure_states[child_id]; ok && state.result.baseline_valid {
			baseline := layout_unit_to_f32(state.result.baseline)
			if baseline > baseline_by_row[int(child.grid_row)] { baseline_by_row[int(child.grid_row)] = baseline }
		}
	}
	for child_id in children {
		child := rt.nodes[child_id]
		layout_note_node_visit(rt, child)
		parent.grid_work_units += 1
		if !grid_item_cell_valid(rt, parent, child, report=false) { continue }
		parent.grid_work_units += u64(child.grid_column_span)+u64(child.grid_row_span)
	cell := grid_cell_bounds(child, inner, column_sizes, row_sizes, column_positions, row_positions, column_gap, row_gap, rtl)
		old_bounds, old_clip := child.bounds, child.clip
		child.bounds = cell
		if child.grid_align_x != .Stretch {
			width := grid_desired_child_extent(rt, child, .Row, cell.w)
			child.bounds.x = grid_align_x_position(rt, parent, child, cell, width)
			child.bounds.w = width
		}
		if child.grid_align_y == .Baseline && child.grid_row_span == 1 {
			if state, ok := rt.measure_states[child_id]; ok && state.result.baseline_valid {
				height := grid_desired_child_extent(rt, child, .Column, cell.h)
				child.bounds.h = height
				child.bounds.y = cell.y+baseline_by_row[int(child.grid_row)]-layout_unit_to_f32(state.result.baseline)
			}
		} else if child.grid_align_y != .Stretch {
			height := grid_desired_child_extent(rt, child, .Column, cell.h)
			child.bounds.h = height
			if child.grid_align_y == .Center { child.bounds.y += maxf(cell.h-height, 0)*0.5 }
			else if child.grid_align_y == .End { child.bounds.y += maxf(cell.h-height, 0) }
		}
		child.hit_bounds = child.bounds
		if parent.style.clip { child.clip = rect_intersection(parent.clip, parent.bounds) } else { child.clip = parent.clip }
		layout_finalize_node_geometry_for_node(rt, child)
		semantic_sync_bounds(rt, child)
		bounds_changed := !same_rect(old_bounds, child.bounds)
		clip_changed := !same_rect(old_clip, child.clip)
		if bounds_changed || clip_changed || dirty_has(child.dirty, .Layout) {
			dirty_set(&child.dirty, .Layout, true)
			dirty_set(&child.dirty, .Paint, true)
			dirty_set(&child.dirty, .Composite, true)
			queue_paint(rt, child_id)
			if bounds_changed || clip_changed { rt.stats.layout_updates += 1 }
			if bounds_changed || clip_changed || dirty_has(child.dirty, .Layout) { layout_children(rt, child_id) }
			dirty_set(&child.dirty, .Layout, false)
		}
	}
	record_trace(rt, .Layout, parent.id, fmt.tprintf("Grid staged solve completed; work units=%d", parent.grid_work_units))
}
