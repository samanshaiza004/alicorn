package alicorn

import "core:fmt"
import "core:math"

maxf :: proc(a, b: f32) -> f32 {
	if a > b { return a }
	return b
}

minf :: proc(a, b: f32) -> f32 {
	if a < b { return a }
	return b
}

clampf :: proc(v, low, high: f32) -> f32 {
	result := maxf(v, low)
	if high >= 0 {
		result = minf(result, high)
	}
	return result
}

rect_contains :: proc(rect: Rect, x, y: f32) -> bool {
	return x >= rect.x && y >= rect.y && x < rect.x+rect.w && y < rect.y+rect.h
}

rect_intersection :: proc(a, b: Rect) -> Rect {
	left := maxf(a.x, b.x)
	top := maxf(a.y, b.y)
	right := minf(a.x+a.w, b.x+b.w)
	bottom := minf(a.y+a.h, b.y+b.h)
	if right < left || bottom < top {
		return Rect{left, top, 0, 0}
	}
	return Rect{left, top, right-left, bottom-top}
}

Scroll_Bar_Geometry :: struct {
	viewport: Rect,
	vertical_visible: bool,
	horizontal_visible: bool,
	vertical_track: Rect,
	vertical_thumb: Rect,
	horizontal_track: Rect,
	horizontal_thumb: Rect,
	corner: Rect,
}

scrollbar_thumb_rect :: proc(track: Rect, horizontal: bool, content, viewport, offset: f32) -> Rect {
	track_length := track.h
	track_start := track.y
	if horizontal { track_length, track_start = track.w, track.x }
	if track_length <= 0 { return Rect{} }
	thumb_length := track_length
	if content > viewport && content > 0 {
		thumb_length = track_length * viewport / content
		thumb_length = minf(track_length, maxf(SCROLLBAR_MIN_THUMB, thumb_length))
	}
	max_offset := maxf(content-viewport, 0)
	thumb_start := track_start
	if max_offset > 0 {
		thumb_start += clampf(offset, 0, max_offset) / max_offset * (track_length-thumb_length)
	}
	if horizontal { return Rect{thumb_start, track.y, thumb_length, track.h} }
	return Rect{track.x, thumb_start, track.w, thumb_length}
}

// scroll_bar_geometry resolves both axes together because reserving one bar
// can make the other axis overflow. The viewport is the content clip after
// padding and solid scrollbar reservation; the corner is left clear when both
// bars are present.
scroll_bar_geometry :: proc(
	bounds: Rect,
	content_width, content_height, padding: f32,
	axes: Scroll_Axes,
	policy: Scrollbar_Policy,
	offset_x: f32 = 0,
	offset_y: f32 = 0,
) -> Scroll_Bar_Geometry {
	base := Rect{
		bounds.x+padding,
		bounds.y+padding,
		maxf(bounds.w-2*padding, 0),
		maxf(bounds.h-2*padding, 0),
	}
	allow_x := axes == .Horizontal || axes == .Both
	allow_y := axes == .Vertical || axes == .Both
	vertical_thickness := minf(SCROLLBAR_THICKNESS, base.w)
	horizontal_thickness := minf(SCROLLBAR_THICKNESS, base.h)
	show_x := policy == .Always && allow_x
	show_y := policy == .Always && allow_y
	if policy == .Auto {
		// Two passes are sufficient for the only dependency: a vertical bar
		// reduces width and a horizontal bar reduces height.
		for _ in 0..<3 {
			view_w := maxf(base.w-(show_y ? vertical_thickness : 0), 0)
			view_h := maxf(base.h-(show_x ? horizontal_thickness : 0), 0)
			next_y := allow_y && content_height > view_h
			next_x := allow_x && content_width > view_w
			if next_x == show_x && next_y == show_y { break }
			show_x, show_y = next_x, next_y
		}
	}
	view := Rect{
		base.x,
		base.y,
		maxf(base.w-(show_y ? vertical_thickness : 0), 0),
		maxf(base.h-(show_x ? horizontal_thickness : 0), 0),
	}
	result := Scroll_Bar_Geometry{viewport=view, vertical_visible=show_y, horizontal_visible=show_x}
	if show_y {
		track_h := base.h-(show_x ? horizontal_thickness : 0)
		result.vertical_track = Rect{base.x+base.w-vertical_thickness, base.y, vertical_thickness, maxf(track_h, 0)}
		result.vertical_thumb = scrollbar_thumb_rect(result.vertical_track, false, content_height, view.h, offset_y)
	}
	if show_x {
		track_w := base.w-(show_y ? vertical_thickness : 0)
		result.horizontal_track = Rect{base.x, base.y+base.h-horizontal_thickness, maxf(track_w, 0), horizontal_thickness}
		result.horizontal_thumb = scrollbar_thumb_rect(result.horizontal_track, true, content_width, view.w, offset_x)
	}
	if show_x && show_y {
		result.corner = Rect{base.x+base.w-vertical_thickness, base.y+base.h-horizontal_thickness, vertical_thickness, horizontal_thickness}
	}
	return result
}

intrinsic_main :: proc(rt: ^Runtime, node: ^Node, direction: Layout_Direction) -> f32 {
	state := rt.measure_states[node.id]
	if state.cache_key.valid {
		if direction == .Row && node.style.width >= 0 { return node.style.width }
		if direction == .Column && node.style.height >= 0 { return node.style.height }
		return layout_unit_to_f32(state.result.size.width if direction == .Row else state.result.size.height)
	}
	padding_x: f32 = 0
	padding_y: f32 = 0
	if node.kind == .Button {
		padding_x = maxf(node.button_content_style.padding_x, 0)
		padding_y = maxf(node.button_content_style.padding_y, 0)
	}
	if direction == .Row {
		if node.style.width >= 0 { return node.style.width }
		if node.kind == .Checkbox {
			if node.text_run_valid { return node.text_run.width + 36 }
			return 116
		}
		if node.kind == .Slider { return 180 }
		if node.text_run_valid {
			return node.text_run.width + 2*padding_x
		}
		return 80 + 2*padding_x
	}
	if node.style.height >= 0 { return node.style.height }
	if node.kind == .Checkbox {
		if node.text_run_valid { return maxf(28, node.text_run.height+8) }
		return 28
	}
	if node.kind == .Slider {
		if node.text_run_valid { return maxf(44, node.text_run.height+24) }
		return 44
	}
	if node.text_run_valid { return node.text_run.height + 2*padding_y }
	return 24 + 2*padding_y
}

main_axis_min :: proc(style: Layout_Style, direction: Layout_Direction) -> f32 {
	return style.min_width if direction == .Row else style.min_height
}

main_axis_max :: proc(style: Layout_Style, direction: Layout_Direction) -> f32 {
	return style.max_width if direction == .Row else style.max_height
}

resolved_main_size :: proc(node: ^Node, direction: Layout_Direction, basis: f32) -> f32 {
	return clampf(basis, main_axis_min(node.style, direction), main_axis_max(node.style, direction))
}

// Float grow weights are normalized against the largest participant before
// conversion so equivalent ratios have the same integer representation even
// when callers use small or very large positive values.
LAYOUT_GROW_WEIGHT_QUANTIZATION :: f32(1 << 24)

layout_grow_weight_is_finite_positive :: proc(value: f32) -> bool {
	return value > 0 && !math.is_nan(value) && !math.is_inf(value)
}

layout_grow_weight_units :: proc(value, maximum: f32) -> u32 {
	if !layout_grow_weight_is_finite_positive(value) || !layout_grow_weight_is_finite_positive(maximum) { return 0 }
	ratio := clampf(value/maximum, 0, 1)
	units := math.floor(ratio*LAYOUT_GROW_WEIGHT_QUANTIZATION+0.5)
	if units < 1 { units = 1 }
	if units > LAYOUT_GROW_WEIGHT_QUANTIZATION { units = LAYOUT_GROW_WEIGHT_QUANTIZATION }
	return u32(units)
}

layout_main_measured_units :: proc(rt: ^Runtime, node: ^Node, direction: Layout_Direction) -> Layout_Unit {
	if node_has_text_product(node.kind) {
		if state, ok := rt.measure_states[node.id]; ok && state.cache_key.valid {
			measured := layout_unit_to_f32(state.result.size.width if direction == .Row else state.result.size.height)
			return layout_unit_extent(resolved_main_size(node, direction, measured))
		}
	}
	// Containers and other non-text nodes retain their existing fixed/natural
	// size policy. This fallback reads retained inputs only; allocation never
	// shapes text or mutates measurement state.
	size := resolved_main_size(node, direction, intrinsic_main(rt, node, direction))
	return layout_unit_extent(size)
}

layout_trace_allocator_input_error :: proc(rt: ^Runtime, node: ^Node, message: string) {
	if rt == nil || node == nil { return }
	record_trace(rt, .Layout, node.id, fmt.tprintf(
		"invalid 1D layout input (%s) at %s:%d:%d",
		message,
		node.site.file,
		node.site.line,
		node.site.column,
	))
}

// Resolve Row/Column main-axis sizes through the shared fixed-point allocator.
// Non-growing children are fixed at their measured/natural size; grow maps to
// expansion weight and starts at the child's hard minimum, matching the
// previous Row/Column policy. Cross-axis placement and Split remain separate.
resolve_main_sizes :: proc(
	rt: ^Runtime,
	children: []Node_ID,
	direction: Layout_Direction,
	available: f32,
	sizes: []f32,
	) -> Axis_Allocation_Result {
	items := make([]Elastic_Item, len(children), allocator=rt.scratch_allocator)
	defer delete(items, rt.scratch_allocator)
	allocated := make([]Layout_Unit, len(children), allocator=rt.scratch_allocator)
	defer delete(allocated, rt.scratch_allocator)
	maximum_grow: f32 = 0
	for id, index in children {
		child := rt.nodes[id]
		grow := child.style.grow
		if layout_grow_weight_is_finite_positive(grow) {
			if grow > maximum_grow { maximum_grow = grow }
		} else if math.is_nan(grow) || math.is_inf(grow) {
			layout_trace_allocator_input_error(rt, child, "grow weight must be finite")
		}
	}

	for id, index in children {
		child := rt.nodes[id]
		grow := child.style.grow
		if layout_grow_weight_is_finite_positive(grow) {
			minimum_value := main_axis_min(child.style, direction)
			maximum_value := main_axis_max(child.style, direction)
			minimum := layout_unit_extent(maxf(minimum_value, 0))
			max_unbounded := maximum_value < 0
			maximum := minimum
			if math.is_nan(maximum_value) || math.is_inf(maximum_value) {
				layout_trace_allocator_input_error(rt, child, "maximum must be finite or negative for unbounded")
				max_unbounded = true
			} else if !max_unbounded {
				maximum = layout_unit_maximum(maxf(maximum_value, 0))
			}
			if math.is_nan(minimum_value) || math.is_inf(minimum_value) || minimum_value < 0 {
				layout_trace_allocator_input_error(rt, child, "minimum must be finite and nonnegative")
			}
			items[index] = Elastic_Item{
				minimum=minimum,
				ideal=minimum,
				maximum=maximum,
				max_unbounded=max_unbounded,
				expand_weight=layout_grow_weight_units(grow, maximum_grow),
			}
		} else {
			fixed := layout_main_measured_units(rt, child, direction)
			items[index] = Elastic_Item{minimum=fixed, ideal=fixed, maximum=fixed}
		}
	}

	axis := "row"
	if direction == .Column { axis = "column" }
	result := layout_allocate_axis(layout_unit_maximum(maxf(available, 0)), items, allocated)
	for id, index in children {
		child := rt.nodes[id]
		sizes[index] = layout_unit_to_f32(allocated[index])
		canonical, invalid := layout_allocator_canonical_item(items[index])
		if invalid {
			layout_trace_allocator_input_error(rt, child, "minimum exceeds maximum or a bound is outside the supported range; canonicalized safely")
		}
		if items[index].expand_weight > 0 && allocated[index] != canonical.ideal {
			record_trace(rt, .Layout, child.id, fmt.tprintf(
				"%s allocation: ideal %.3f, allocated %.3f, expand weight %d",
				axis,
				layout_unit_to_f32(canonical.ideal),
				sizes[index],
				items[index].expand_weight,
			))
		}
	}
	if result.overflow > 0 {
		record_trace(rt, .Layout, children[0] if len(children) > 0 else 0, fmt.tprintf(
			"%s allocation overflow: hard minima exceed available by %.3f",
			axis,
			layout_unit_to_f32(result.overflow),
		))
	} else if result.unused > 0 {
		record_trace(rt, .Layout, children[0] if len(children) > 0 else 0, fmt.tprintf(
			"%s allocation leaves %.3f unused after reaching expansion limits",
			axis,
			layout_unit_to_f32(result.unused),
		))
	}
	return result
}

layout_text_constraint :: proc(parent: ^Node, child: ^Node, cross_size: f32) -> f32 {
	if !node_has_text_product(child.kind) { return 0 }
	constraint: f32 = 0
	if child.style.width > 0 {
		constraint = child.style.width
	} else if parent.style.direction == .Column {
		constraint = cross_size
	}
	if constraint <= 0 { return 0 }
	constraint = clampf(constraint, child.style.min_width, child.style.max_width)
	if child.kind == .Button {
		constraint = maxf(constraint-2*maxf(child.button_content_style.padding_x, 0), 0)
	} else if child.kind == .Checkbox {
		constraint = maxf(constraint-36, 0)
	}
	return constraint
}

split_clamp_position :: proc(total, thickness, requested, min_first, min_second: f32) -> f32 {
	available := maxf(total-maxf(thickness, 1), 0)
	minimum_sum := maxf(min_first, 0) + maxf(min_second, 0)
	if available >= minimum_sum {
		return clampf(requested, maxf(min_first, 0), available-maxf(min_second, 0))
	}
	if minimum_sum > 0 { return available * maxf(min_first, 0) / minimum_sum }
	return clampf(requested, 0, available)
}

layout_split_children :: proc(rt: ^Runtime, parent: ^Node, inner: Rect, children: []Node_ID) {
	if len(children) != 3 { return }
	axis := parent.split_axis
	total := inner.w if axis == .Horizontal else inner.h
	thickness := clampf(rt.nodes[children[1]].split_handle_size, 1, total)
	available := maxf(total-thickness, 0)
	// When the window is smaller than both minima, preserve their ratio and
	// keep all geometry nonnegative. Normal-size layouts enforce both mins.
	first := split_clamp_position(total, thickness, parent.split_position, parent.split_min_first, parent.split_min_second)
	parent.split_position = first
	second := maxf(available-first, 0)
	hit_size := minf(total, maxf(rt.nodes[children[1]].split_hit_size, thickness))
	hit_offset := clampf(first+(thickness-hit_size)*0.5, 0, total-hit_size)
	for id, index in children {
		child := rt.nodes[id]
		layout_note_node_visit(rt, child)
		old_bounds := child.bounds
		old_hit_bounds := child.hit_bounds
		main_offset := f32(0)
		main_size := first
		if index == 1 {
			main_offset = first
			main_size = thickness
		} else if index == 2 {
			main_offset = first + thickness
			main_size = second
		}
		if axis == .Horizontal {
			child.bounds = Rect{inner.x+main_offset, inner.y, main_size, inner.h}
			child.hit_bounds = child.bounds
			if index == 1 {
				child.bounds = Rect{inner.x+first, inner.y, thickness, inner.h}
				child.hit_bounds = Rect{inner.x+hit_offset, inner.y, hit_size, inner.h}
			}
		} else {
			child.bounds = Rect{inner.x, inner.y+main_offset, inner.w, main_size}
			child.hit_bounds = child.bounds
			if index == 1 {
				child.bounds = Rect{inner.x, inner.y+first, inner.w, thickness}
				child.hit_bounds = Rect{inner.x, inner.y+hit_offset, inner.w, hit_size}
			}
		}
		old_clip := child.clip
		if parent.style.clip { child.clip = rect_intersection(parent.clip, parent.bounds) } else { child.clip = parent.clip }
		bounds_changed := !same_rect(old_bounds, child.bounds)
		hit_changed := !same_rect(old_hit_bounds, child.hit_bounds)
		clip_changed := !same_rect(old_clip, child.clip)
		layout_finalize_node_geometry_for_node(rt, child)
		semantic_sync_bounds(rt, child)
		if bounds_changed || hit_changed || clip_changed {
			dirty_set(&child.dirty, .Layout, true)
			dirty_set(&child.dirty, .Paint, true)
			dirty_set(&child.dirty, .Composite, true)
			queue_paint(rt, id)
			rt.stats.layout_updates += 1
			record_trace(rt, .Layout, id, "split pane bounds changed")
		}
		if bounds_changed || clip_changed || dirty_has(child.dirty, .Layout) {
			layout_children(rt, id)
		}
		dirty_set(&child.dirty, .Layout, false)
	}
}

layout_note_node_visit :: proc(rt: ^Runtime, node: ^Node) {
	if rt == nil || node == nil { return }
	if len(rt.layout_visit_probe) > 0 { rt.layout_visit_probe[node.id] += 1 }
	rt.stats.layout_nodes_visited += 1
	rt.stats.stage_visits[.Layout] += 1
}

layout_children :: proc(rt: ^Runtime, parent_id: Node_ID) {
	parent, ok := rt.nodes[parent_id]
	if !ok { return }
	children := parent.children[:]
	count := len(children)
	inner := Rect{parent.bounds.x + parent.style.padding, parent.bounds.y + parent.style.padding, parent.bounds.w - 2*parent.style.padding, parent.bounds.h - 2*parent.style.padding}
	if parent.kind == .Scroll_Region {
		geometry := scroll_bar_geometry(
			parent.bounds,
			parent.scroll_content_width,
			parent.scroll_content_height,
			parent.style.padding,
			parent.scroll_axes,
			parent.scrollbar_policy,
			parent.scroll_offset_x,
			parent.scroll_offset_y,
		)
		old_viewport := parent.scroll_viewport_bounds
		old_vertical, old_horizontal := parent.scrollbar_vertical_visible, parent.scrollbar_horizontal_visible
		old_offset_x, old_offset_y := parent.scroll_offset_x, parent.scroll_offset_y
		parent.scroll_viewport_bounds = geometry.viewport
		parent.scroll_geometry_resolved = true
		parent.scrollbar_vertical_visible = geometry.vertical_visible
		parent.scrollbar_horizontal_visible = geometry.horizontal_visible
		parent.scrollbar_vertical_track = geometry.vertical_track
		parent.scrollbar_vertical_thumb = geometry.vertical_thumb
		parent.scrollbar_horizontal_track = geometry.horizontal_track
		parent.scrollbar_horizontal_thumb = geometry.horizontal_thumb
		parent.scroll_viewport_width = geometry.viewport.w
		parent.scroll_viewport_height = geometry.viewport.h
		parent.scroll_offset_x = clampf(parent.scroll_offset_x, 0, maxf(parent.scroll_content_width-geometry.viewport.w, 0))
		parent.scroll_offset_y = clampf(parent.scroll_offset_y, 0, maxf(parent.scroll_content_height-geometry.viewport.h, 0))
		parent.layout_scroll_offset_x = parent.scroll_offset_x
		parent.layout_scroll_offset_y = parent.scroll_offset_y
		inner = geometry.viewport
		if !same_rect(old_viewport, geometry.viewport) || old_vertical != geometry.vertical_visible || old_horizontal != geometry.horizontal_visible ||
			old_offset_x != parent.scroll_offset_x || old_offset_y != parent.scroll_offset_y {
			rt.scroll_geometry_changed = true
		}
		if old_viewport.h != geometry.viewport.h || old_offset_y != parent.scroll_offset_y {
			for child_id in children {
				if child, ok := rt.nodes[child_id]; ok && child.kind == .Virtual_List {
					rt.virtual_viewport_changed = true
					break
				}
			}
		}
	}
	if count == 0 { return }
	if inner.w < 0 { inner.w = 0 }
	if inner.h < 0 { inner.h = 0 }
	if parent.kind == .Context_Menu_Overlay {
		context_menu_layout_children(rt, parent, children[:])
		return
	}
	if parent.kind == .Split && len(children) == 3 {
		layout_split_children(rt, parent, inner, children[:])
		return
	}
	main_size := parent.style.direction == .Row ? inner.w : inner.h
	cross_size := parent.style.direction == .Row ? inner.h : inner.w
	gap_total := parent.style.gap * f32(count-1)
	available := maxf(main_size-gap_total, 0)
	// Leaf measurement is retained against the actual constraints this parent
	// supplies. Containers keep their existing external sizing policies; this
	// pass does not recursively derive preferred container sizes.
	has_grow := false
	for id in children {
		child := rt.nodes[id]
		layout_note_node_visit(rt, child)
		if child.style.grow > 0 || math.is_nan(child.style.grow) || math.is_inf(child.style.grow) { has_grow = true }
		if layout_node_has_content_height(child) {
			parent_constraints := Layout_Constraints{
				width=layout_axis_constraint_normalize(inner.w, inner.w),
				height=layout_axis_constraint_normalize(0, available),
			}
			constraints := layout_content_child_constraints(parent, child, parent_constraints)
			_ = layout_measure_node(rt, child, constraints)
		}
		// A Row grow child's width is not known until the existing allocator
		// distributes space below. Avoid shaping it with an invented width.
		if node_has_text_product(child.kind) && !(parent.style.direction == .Row && layout_grow_weight_is_finite_positive(child.style.grow)) {
			_ = layout_measure_node(rt, child, layout_text_measure_constraints(parent, child, cross_size))
		}
	}
	main_sizes: []f32
	if has_grow {
		main_sizes = make([]f32, count, allocator=rt.scratch_allocator)
		resolve_main_sizes(rt, children, parent.style.direction, available, main_sizes)
	}
	// A fixed-height virtual list realizes only the visible rows. Its first
	// realized row may begin above the viewport when the scroll position is
	// between row boundaries; the retained clip on the list protects the
	// surrounding UI while preserving continuous motion.
	main_offset: f32 = 0
	cross_offset: f32 = 0
	if parent.kind == .Virtual_List {
		if parent.style.direction == .Column {
			main_offset = -parent.layout_scroll_offset_y
			cross_offset = -parent.layout_scroll_offset_x
		} else {
			main_offset = -parent.layout_scroll_offset_x
			cross_offset = -parent.layout_scroll_offset_y
		}
	}
	for id, index in children {
		child := rt.nodes[id]
		layout_note_node_visit(rt, child)
		old_bounds := child.bounds
		main := resolved_main_size(child, parent.style.direction, intrinsic_main(rt, child, parent.style.direction))
		if has_grow { main = main_sizes[index] }
		if layout_grow_weight_is_finite_positive(child.style.grow) && node_has_text_product(child.kind) {
			_ = layout_measure_node(rt, child, layout_grow_measure_constraints(parent, child, main, cross_size))
		}
		if parent.style.direction == .Row {
			cross := child.style.height >= 0 ? child.style.height : cross_size
			cross = clampf(cross, child.style.min_height, child.style.max_height)
			cross_pos := inner.y + cross_offset
			if parent.style.align == .Center { cross_pos += (cross_size-cross)/2 }
			if parent.style.align == .End { cross_pos += cross_size-cross }
			child.bounds = Rect{inner.x+main_offset, cross_pos, clampf(main, child.style.min_width, child.style.max_width), cross}
		} else {
			cross := child.style.width >= 0 ? child.style.width : cross_size
			cross = clampf(cross, child.style.min_width, child.style.max_width)
			cross_pos := inner.x + cross_offset
			if parent.style.align == .Center { cross_pos += (cross_size-cross)/2 }
			if parent.style.align == .End { cross_pos += cross_size-cross }
			child.bounds = Rect{cross_pos, inner.y+main_offset, cross, clampf(main, child.style.min_height, child.style.max_height)}
		}
		old_clip := child.clip
		if parent.kind == .Scroll_Region {
			child.clip = rect_intersection(parent.clip, parent.scroll_viewport_bounds)
		} else if parent.style.clip { child.clip = rect_intersection(parent.clip, parent.bounds) } else { child.clip = parent.clip }
		layout_finalize_node_geometry_for_node(rt, child)
		semantic_sync_bounds(rt, child)
		bounds_changed := !same_rect(old_bounds, child.bounds)
		clip_changed := !same_rect(old_clip, child.clip)
		if bounds_changed && child.kind == .Custom_Surface && child.surface_kind == .Geometry &&
			(old_bounds.w != child.bounds.w || old_bounds.h != child.bounds.h) {
			// Geometry is authored in this surface's logical coordinate space.
			// Retained-only layout can move it freely, but a changed extent needs
			// one app description rebuild to regenerate the projection.
			rt.geometry_surface_bounds_changed = true
		}
		if bounds_changed && child.kind == .Scroll_Region {
			// The first layout pass resolves grow-based scroll regions. Ask for
			// one follow-up description so virtualization uses that real viewport
			// instead of the conservative pre-layout fallback.
			rt.scroll_geometry_changed = true
		}
		if bounds_changed || clip_changed {
			dirty_set(&child.dirty, .Layout, true)
			dirty_set(&child.dirty, .Paint, true)
			dirty_set(&child.dirty, .Composite, true)
			queue_paint(rt, id)
			rt.stats.layout_updates += 1
			record_trace(rt, .Layout, id, "layout hash or parent bounds changed")
		} else if dirty_has(child.dirty, .Layout) {
			rt.stats.layout_updates += 1
			record_trace(rt, .Layout, id, "layout hash changed")
		}
		if bounds_changed || clip_changed || dirty_has(child.dirty, .Layout) {
			layout_children(rt, id)
		}
		dirty_set(&child.dirty, .Layout, false)
		main_offset += main + parent.style.gap
	}
	if has_grow { delete(main_sizes, rt.scratch_allocator) }
}

layout_tree :: proc(rt: ^Runtime) {
	for id in rt.top_level {
		node, ok := rt.nodes[id]
		if !ok || !node.active { continue }
		if node.parent == 0 {
			old := node.bounds
			old_clip := node.clip
			node.bounds = rt.viewport
			node.clip = rt.viewport
			layout_finalize_node_geometry_for_node(rt, node)
			semantic_sync_bounds(rt, node)
			if !same_rect(old, node.bounds) {
				dirty_set(&node.dirty, .Layout, true)
				dirty_set(&node.dirty, .Paint, true)
				dirty_set(&node.dirty, .Composite, true)
				queue_paint(rt, id)
			}
			if !same_rect(old_clip, node.clip) {
				dirty_set(&node.dirty, .Paint, true)
				dirty_set(&node.dirty, .Composite, true)
				queue_paint(rt, id)
			}
			if !same_rect(old, node.bounds) || dirty_has(node.dirty, .Layout) {
				layout_note_node_visit(rt, node)
				layout_children(rt, id)
			}
			dirty_set(&node.dirty, .Layout, false)
		}
	}
	for id in rt.layout_roots {
		node, ok := rt.nodes[id]
		if !ok { continue }
		node.layout_root_queued = false
		if !node.active || !dirty_has(node.dirty, .Layout) { continue }
		parent_is_dirty := false
		if parent, found := rt.nodes[node.parent]; found && dirty_has(parent.dirty, .Layout) {
			parent_is_dirty = true
		}
		if parent_is_dirty { continue }
		layout_note_node_visit(rt, node)
		layout_children(rt, id)
		dirty_set(&node.dirty, .Layout, false)
	}
	clear(&rt.layout_roots)
	rt.layout_pending = false
}
