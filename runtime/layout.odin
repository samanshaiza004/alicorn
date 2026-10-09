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

layout_main_style_bounds :: proc(rt: ^Runtime, node: ^Node, direction: Layout_Direction) -> (minimum, maximum: Layout_Unit, max_unbounded: bool) {
	minimum_value := main_axis_min(node.style, direction)
	if math.is_nan(minimum_value) || math.is_inf(minimum_value) || minimum_value < 0 {
		layout_trace_allocator_input_error(rt, node, "minimum must be finite and nonnegative; using zero")
		minimum_value = 0
	}
	minimum = layout_unit_extent(minimum_value)
	maximum_value := main_axis_max(node.style, direction)
	if maximum_value < 0 && !math.is_nan(maximum_value) && !math.is_inf(maximum_value) {
		max_unbounded = true
		maximum = minimum
		return
	}
	if math.is_nan(maximum_value) || math.is_inf(maximum_value) {
		layout_trace_allocator_input_error(rt, node, "maximum must be finite or a negative unbounded sentinel; using minimum")
		maximum = minimum
		return
	}
	maximum = layout_unit_maximum(maximum_value)
	if maximum < minimum {
		layout_trace_allocator_input_error(rt, node, "minimum exceeds maximum; canonicalizing maximum to minimum")
		maximum = minimum
	}
	return
}

layout_main_measured_units :: proc(rt: ^Runtime, node: ^Node, direction: Layout_Direction) -> Layout_Unit {
	// Allocation consumes the retained measure product when available. This
	// fallback reads existing natural-size policy only; it never shapes text.
	size := intrinsic_main(rt, node, direction)
	minimum, maximum, unbounded := layout_main_style_bounds(rt, node, direction)
	measured := layout_unit_extent(size)
	// Explicit extents are hard authored sizes, so quantize them inward. The
	// ceiling used for measured content is conservative for text, but can make
	// a fixed child overrun its parent by one Layout_Unit.
	if direction == .Row && node.style.width >= 0 || direction == .Column && node.style.height >= 0 {
		measured = layout_unit_maximum(size)
	}
	if measured < minimum { measured = minimum }
	if !unbounded && measured > maximum { measured = maximum }
	return measured
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
	available: Layout_Unit,
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
		} else if grow < 0 || math.is_nan(grow) || math.is_inf(grow) {
			layout_trace_allocator_input_error(rt, child, "expand weight must be finite and nonnegative")
		}
	}

	for id, index in children {
		child := rt.nodes[id]
		grow := child.style.grow
		if !layout_grow_weight_is_finite_positive(grow) { grow = 0 }
		minimum, maximum, max_unbounded := layout_main_style_bounds(rt, child, direction)
		ideal := layout_main_measured_units(rt, child, direction)
		if ideal < minimum { ideal = minimum }
		if !max_unbounded && ideal > maximum { ideal = maximum }
		expand_weight := layout_grow_weight_units(grow, maximum_grow)
		compress_weight := u32(child.style.compress_weight)
		// Compatibility: ordinary grow starts at the hard minimum exactly as
		// before. Supplying a compression weight opts into a measured ideal so
		// the allocator can shrink toward the minimum under a deficit.
		if expand_weight > 0 && compress_weight == 0 { ideal = minimum }
		item_maximum := maximum
		item_unbounded := max_unbounded
		if expand_weight == 0 && compress_weight == 0 {
			// Fixed and natural children remain rigid unless compression is
			// explicitly requested.
			item_maximum = ideal
			item_unbounded = false
		}
		items[index] = Elastic_Item{
			minimum=minimum,
			ideal=ideal,
			maximum=item_maximum,
			max_unbounded=item_unbounded,
			expand_weight=expand_weight,
			compress_weight=compress_weight,
		}
	}

	axis := "row"
	if direction == .Column { axis = "column" }
	result := layout_allocate_axis(available, items, allocated)
	for id, index in children {
		child := rt.nodes[id]
		sizes[index] = layout_unit_to_f32(allocated[index])
		canonical, invalid := layout_allocator_canonical_item(items[index])
		if invalid {
			layout_trace_allocator_input_error(rt, child, "minimum exceeds maximum or a bound is outside the supported range; canonicalized safely")
		}
		if allocated[index] < canonical.ideal {
			record_trace(rt, .Layout, child.id, fmt.tprintf(
				"%s compressed: ideal %.3f, allocated %.3f, compress weight %d",
				axis,
				layout_unit_to_f32(canonical.ideal),
				sizes[index],
				items[index].compress_weight,
			))
			if allocated[index] == canonical.minimum {
				record_trace(rt, .Layout, child.id, fmt.tprintf("%s compression reached hard minimum %.3f", axis, sizes[index]))
			}
		} else if allocated[index] > canonical.ideal {
			record_trace(rt, .Layout, child.id, fmt.tprintf(
				"%s expanded: ideal %.3f, allocated %.3f, expand weight %d",
				axis,
				layout_unit_to_f32(canonical.ideal),
				sizes[index],
				items[index].expand_weight,
			))
			if !canonical.max_unbounded && allocated[index] == canonical.maximum {
				record_trace(rt, .Layout, child.id, fmt.tprintf("%s expansion reached hard maximum %.3f", axis, sizes[index]))
			}
		}
	}
	if result.overflow > 0 {
		record_trace(rt, .Layout, children[0] if len(children) > 0 else 0, fmt.tprintf(
			"%s allocation overflow: hard minima exceed available by %.3f; minima preserved",
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

layout_effective_writing_direction :: proc(rt: ^Runtime, node: ^Node) -> Writing_Direction {
	current := node
	for current != nil {
		direction := layout_options_writing_direction(current.style.options)
		if direction == .Left_To_Right || direction == .Right_To_Left { return direction }
		parent, ok := rt.nodes[current.parent]
		if !ok || current.parent == 0 { break }
		current = parent
	}
	return .Left_To_Right
}

layout_child_cross_size :: proc(rt: ^Runtime, parent, child: ^Node, cross_size: f32) -> f32 {
	if parent.style.direction == .Row {
		cross := child.style.height if child.style.height >= 0 else cross_size
		if layout_node_has_content_height(child) {
			if state, ok := rt.measure_states[child.id]; ok && state.cache_key.valid {
				cross = layout_unit_to_f32(state.result.size.height)
			}
		}
		return clampf(cross, child.style.min_height, child.style.max_height)
	}
	cross := child.style.width if child.style.width >= 0 else cross_size
	return clampf(cross, child.style.min_width, child.style.max_width)
}

layout_child_baseline :: proc(rt: ^Runtime, child: ^Node, cross_size: f32) -> f32 {
	if state, ok := rt.measure_states[child.id]; ok && state.cache_key.valid && state.result.baseline_valid {
		return layout_unit_to_f32(state.result.baseline)
	}
	// A non-text visual such as an icon aligns its bottom edge to the text
	// baseline, which is the useful desktop convention for mixed toolbars.
	return cross_size
}

layout_distribution_leading :: proc(free: Layout_Unit, count: int, distribution: Main_Axis_Distribution) -> Layout_Unit {
	units := i64(free)
	if units <= 0 || count <= 0 { return 0 }
	#partial switch distribution {
	case .Center: return Layout_Unit(units/2)
	case .End: return free
	case .Space_Around:
		first_slot := units/i64(count)
		if units%i64(count) > 0 { first_slot += 1 }
		return Layout_Unit(first_slot/2)
	}
	return 0
}

layout_distribution_gap :: proc(free: Layout_Unit, count, after_index: int, distribution: Main_Axis_Distribution) -> Layout_Unit {
	units := i64(free)
	if units <= 0 || after_index < 0 || after_index >= count-1 { return 0 }
	#partial switch distribution {
	case .Space_Between:
		divisor := i64(count-1)
		gap := units/divisor
		if i64(after_index) < units%divisor { gap += 1 }
		return Layout_Unit(gap)
	case .Space_Around:
		divisor := i64(count)
		base, remainder := units/divisor, units%divisor
		before_slot := base
		after_slot := base
		if i64(after_index) < remainder { before_slot += 1 }
		if i64(after_index+1) < remainder { after_slot += 1 }
		return Layout_Unit((before_slot+1)/2 + after_slot/2)
	}
	return 0
}

layout_split_pane_bounds :: proc(
	rt: ^Runtime,
	owner, pane: ^Node,
	explicit_minimum: f32,
	direction: Layout_Direction,
) -> (minimum, maximum: f32, max_unbounded: bool) {
	minimum = explicit_minimum
	style_minimum := main_axis_min(pane.style, direction)
	if math.is_nan(minimum) || math.is_inf(minimum) || minimum < 0 {
		layout_trace_allocator_input_error(rt, owner, "Split minimum must be finite and nonnegative; using zero")
		minimum = 0
	}
	if math.is_nan(style_minimum) || math.is_inf(style_minimum) || style_minimum < 0 {
		layout_trace_allocator_input_error(rt, pane, "Split pane minimum must be finite and nonnegative; using zero")
		style_minimum = 0
	}
	minimum = maxf(minimum, style_minimum)
	maximum = main_axis_max(pane.style, direction)
	if maximum < 0 && !math.is_nan(maximum) && !math.is_inf(maximum) {
		max_unbounded = true
		return
	}
	if math.is_nan(maximum) || math.is_inf(maximum) {
		layout_trace_allocator_input_error(rt, pane, "Split pane maximum must be finite or a negative unbounded sentinel; using minimum")
		maximum = minimum
		return
	}
	if maximum < minimum {
		layout_trace_allocator_input_error(rt, pane, "Split pane minimum exceeds maximum; canonicalizing maximum to minimum")
		maximum = minimum
	}
	return
}

layout_split_item :: proc(
	rt: ^Runtime,
	owner, pane: ^Node,
	explicit_minimum, ideal: f32,
	direction: Layout_Direction,
	expand_weight, compress_weight: u32,
) -> Elastic_Item {
	minimum, maximum, max_unbounded := layout_split_pane_bounds(rt, owner, pane, explicit_minimum, direction)
	return Elastic_Item{
		minimum=layout_unit_extent(minimum),
		ideal=layout_unit_extent(ideal),
		maximum=layout_unit_maximum(maximum),
		max_unbounded=max_unbounded,
		expand_weight=expand_weight,
		compress_weight=compress_weight,
	}
}

layout_split_allocate_pair :: proc(
	available: Layout_Unit,
	requested_first: Layout_Unit,
	first_item, second_item: Elastic_Item,
) -> (first, second: Layout_Unit, result: Axis_Allocation_Result) {
	items := [2]Elastic_Item{first_item, second_item}
	first_canonical, _ := layout_allocator_canonical_item(items[0])
	second_canonical, _ := layout_allocator_canonical_item(items[1])
	available_i := max(i64(available), 0)
	minimum_total := i64(first_canonical.minimum)+i64(second_canonical.minimum)
	if minimum_total <= available_i {
		lower := i64(first_canonical.minimum)
		upper := available_i-i64(second_canonical.minimum)
		preferred := i64(requested_first)
		if preferred < lower { preferred = lower }
		if preferred > upper { preferred = upper }
		items[0].ideal = Layout_Unit(preferred)
		items[1].ideal = Layout_Unit(available_i-preferred)
	}
	output: [2]Layout_Unit
	result = layout_allocate_axis(available, items[:], output[:])
	return output[0], output[1], result
}

split_clamp_position :: proc(
	total, thickness, requested, min_first, min_second: f32,
	max_first: f32 = -1,
	max_second: f32 = -1,
) -> f32 {
	available := layout_unit_maximum(maxf(total-maxf(thickness, 1), 0))
	item := proc(minimum, maximum, ideal: f32) -> Elastic_Item {
		min_units := layout_unit_extent(maxf(minimum, 0))
		unbounded := maximum < 0 && !math.is_nan(maximum) && !math.is_inf(maximum)
		max_units := min_units
		if !unbounded && !math.is_nan(maximum) && !math.is_inf(maximum) { max_units = layout_unit_maximum(maximum) }
		return Elastic_Item{minimum=min_units, ideal=layout_unit_extent(maxf(ideal, 0)), maximum=max_units, max_unbounded=unbounded, expand_weight=1, compress_weight=1}
	}
	first_item := item(min_first, max_first, requested)
	second_item := item(min_second, max_second, maxf(layout_unit_to_f32(available)-requested, 0))
	first, _, _ := layout_split_allocate_pair(available, layout_unit_extent(requested), first_item, second_item)
	return layout_unit_to_f32(first)
}

layout_split_children :: proc(rt: ^Runtime, parent: ^Node, inner: Rect, children: []Node_ID) {
	if len(children) != 3 { return }
	axis := parent.split_axis
	total := inner.w if axis == .Horizontal else inner.h
	total = maxf(total, 0)
	thickness := minf(maxf(rt.nodes[children[1]].split_handle_size, 1), total)
	available := maxf(total-thickness, 0)
	available_units := layout_unit_maximum(available)
	// Split keeps its established absolute logical-unit preference on resize;
	// the shared allocator applies pane bounds and fills the second pane.
	requested_first := parent.split_preferred_position
	direction := Layout_Direction.Row if axis == .Horizontal else .Column
	first_pane, second_pane := rt.nodes[children[0]], rt.nodes[children[2]]
	maximum_grow := maxf(first_pane.style.grow, second_pane.style.grow)
	if !layout_grow_weight_is_finite_positive(maximum_grow) { maximum_grow = 1 }
	first_expand := layout_grow_weight_units(first_pane.style.grow, maximum_grow)
	second_expand := layout_grow_weight_units(second_pane.style.grow, maximum_grow)
	if first_expand == 0 { first_expand = 1 }
	if second_expand == 0 { second_expand = 1 }
	first_compress := u32(first_pane.style.compress_weight)
	second_compress := u32(second_pane.style.compress_weight)
	if first_compress == 0 { first_compress = 1 }
	if second_compress == 0 { second_compress = 1 }
	first_item := layout_split_item(rt, parent, first_pane, parent.split_min_first, requested_first, direction, first_expand, first_compress)
	second_item := layout_split_item(rt, parent, second_pane, parent.split_min_second, available-requested_first, direction, second_expand, second_compress)
	first_units, second_units, allocation := layout_split_allocate_pair(available_units, layout_unit_extent(requested_first), first_item, second_item)
	first, second := layout_unit_to_f32(first_units), layout_unit_to_f32(second_units)
	parent.split_position = first
	if allocation.invalid_items > 0 {
		record_trace(rt, .Layout, parent.id, "Split allocation canonicalized invalid pane bounds")
	}
	if allocation.overflow > 0 {
		record_trace(rt, .Layout, parent.id, fmt.tprintf("Split allocation overflow: pane hard minima exceed available by %.3f; minima preserved", layout_unit_to_f32(allocation.overflow)))
	}
	if allocation.unused > 0 {
		record_trace(rt, .Layout, parent.id, fmt.tprintf("Split allocation leaves %.3f unused after pane maxima", layout_unit_to_f32(allocation.unused)))
	}
	hit_size := minf(total, maxf(rt.nodes[children[1]].split_hit_size, thickness))
	hit_offset := clampf(first+(thickness-hit_size)*0.5, 0, total-hit_size)
	rtl := axis == .Horizontal && layout_effective_writing_direction(rt, parent) == .Right_To_Left
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
			physical_offset := main_offset
			if rtl { physical_offset = total-main_offset-main_size }
			child.bounds = Rect{inner.x+physical_offset, inner.y, main_size, inner.h}
			child.hit_bounds = child.bounds
			if index == 1 {
				handle_offset := first
				hit_physical_offset := hit_offset
				if rtl {
					handle_offset = total-first-thickness
					hit_physical_offset = total-hit_offset-hit_size
				}
				child.bounds = Rect{inner.x+handle_offset, inner.y, thickness, inner.h}
				child.hit_bounds = Rect{inner.x+hit_physical_offset, inner.y, hit_size, inner.h}
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

layout_adaptive_children :: proc(rt: ^Runtime, parent: ^Node, inner: Rect, children: []Node_ID) {
	if rt == nil || parent == nil { return }
	content := inner
	if content.w < 0 { content.w = 0 }
	if content.h < 0 { content.h = 0 }
	available_width := layout_rect_to_target(content).w
	selected := Node_ID(0)
	reason := Adaptive_Selection_Reason.Invalid_Configuration_Fallback
	first_minimum: f32 = -1
	second_minimum: f32 = -1
	valid_alternatives := len(children) == 2
	for id, index in children {
		alternative, found := rt.nodes[id]
		if !found || !alternative.adaptive_alternative { valid_alternatives = false; continue }
		if index == 0 { first_minimum = alternative.adaptive_min_width }
		else if index == 1 { second_minimum = alternative.adaptive_min_width }
	}
	valid_alternatives = valid_alternatives && first_minimum > 0 && second_minimum == 0 && first_minimum > second_minimum
	if valid_alternatives {
		if available_width >= first_minimum {
			selected = children[0]
			reason = .Minimum_Fit
		} else {
			selected = children[1]
			reason = .Fallback
		}
	} else if len(children) > 0 {
		// Invalid declarations still resolve deterministically and stay bounded:
		// try the first fitting candidate, then use the final declared candidate.
		for id in children {
			alternative, found := rt.nodes[id]
			if found && alternative.adaptive_alternative && available_width >= alternative.adaptive_min_width {
				selected = id
				reason = .Minimum_Fit
				break
			}
		}
		if selected == 0 { selected = children[len(children)-1] }
	}
	previous_selected := parent.adaptive_selected_alternative
	parent.adaptive_available_width = available_width
	parent.adaptive_selected_alternative = selected
	parent.adaptive_selection_reason = reason
	if selected != 0 && selected != previous_selected {
		selected_node, selected_found := rt.nodes[selected]
		selected_name := "<missing>"
		if selected_found { selected_name = selected_node.label }
		rejected := "none"
		for id in children {
			if id == selected { continue }
			candidate, found := rt.nodes[id]
			if !found { continue }
			rejected = fmt.tprintf("%s (requires %.3f)", candidate.label, candidate.adaptive_min_width)
			break
		}
		record_trace(rt, .Layout, parent.id, fmt.tprintf(
			"adaptive selected %s at %.3f available width (%s); rejected %s",
			selected_name,
			available_width,
			adaptive_selection_reason_name(reason),
			rejected,
		))
	}
	if selected == 0 { return }
	// Make the new branch presentation-active before hiding the old one. This
	// lets focus repair find an equivalent focused node when both alternatives
	// intentionally bind the same application Semantic_ID.
	for id in children {
		if id == selected { _ = adaptive_set_subtree_presentation(rt, id, true); break }
	}
	for id in children {
		alternative, found := rt.nodes[id]
		if !found { continue }
		was_present := alternative.present
		_ = adaptive_set_subtree_presentation(rt, id, id == selected)
		if id != selected {
			alternative.bounds = Rect{content.x, content.y, 0, 0}
			alternative.clip = {}
			layout_finalize_node_geometry_for_node(rt, alternative)
			continue
		}
		old_bounds := alternative.bounds
		old_clip := alternative.clip
		alternative.bounds = content
		if parent.style.clip { alternative.clip = rect_intersection(parent.clip, parent.bounds) }
		else { alternative.clip = parent.clip }
		layout_finalize_node_geometry_for_node(rt, alternative)
		semantic_sync_bounds(rt, alternative)
		bounds_changed := !same_rect(old_bounds, alternative.bounds)
		clip_changed := !same_rect(old_clip, alternative.clip)
		if bounds_changed || clip_changed {
			dirty_set(&alternative.dirty, .Layout, true)
			dirty_set(&alternative.dirty, .Paint, true)
			dirty_set(&alternative.dirty, .Composite, true)
			queue_paint(rt, id)
			rt.stats.layout_updates += 1
		}
		if !was_present || bounds_changed || clip_changed || dirty_has(alternative.dirty, .Layout) {
			layout_note_node_visit(rt, alternative)
			layout_children(rt, id)
		}
		dirty_set(&alternative.dirty, .Layout, false)
	}
}

adaptive_selection_reason_name :: proc(reason: Adaptive_Selection_Reason) -> string {
	switch reason {
	case .Minimum_Fit: return "minimum fit"
	case .Fallback: return "fallback"
	case .Invalid_Configuration_Fallback: return "invalid configuration fallback"
	case .Unresolved: return "unresolved"
	}
	return "unresolved"
}

layout_children :: proc(rt: ^Runtime, parent_id: Node_ID) {
	parent, ok := rt.nodes[parent_id]
	if !ok || !parent.active || !parent.present { return }
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
	if parent.kind == .Grid {
		layout_grid_children(rt, parent, inner, children[:])
		return
	}
	if parent.kind == .Split && len(children) == 3 {
		layout_split_children(rt, parent, inner, children[:])
		return
	}
	if parent.adaptive_owner {
		layout_adaptive_children(rt, parent, inner, children[:])
		return
	}
	main_size := parent.style.direction == .Row ? inner.w : inner.h
	cross_size := parent.style.direction == .Row ? inner.h : inner.w
	gap := parent.style.gap
	if math.is_nan(gap) || math.is_inf(gap) || gap < 0 {
		record_trace(rt, .Layout, parent.id, "invalid gap; using zero")
		gap = 0
	}
	gap_units := layout_unit_extent(gap)
	gap = layout_unit_to_f32(gap_units)
	// Parent capacity is a constraint, so quantize it inward. Rounding a
	// fractional available edge outward can place the final child a fraction
	// beyond its parent's content bounds.
	main_units := i64(layout_unit_maximum(maxf(main_size, 0)))
	gap_total_units := u128(i64(gap_units))*u128(count-1)
	available_units: Layout_Unit = 0
	if gap_total_units < u128(main_units) { available_units = Layout_Unit(main_units-i64(gap_total_units)) }
	available := layout_unit_to_f32(available_units)
	// Leaf measurement is retained against the actual constraints this parent
	// supplies. Containers keep their existing external sizing policies; this
	// pass does not recursively derive preferred container sizes.
	for id in children {
		child := rt.nodes[id]
		layout_note_node_visit(rt, child)
		if parent.style.direction == .Column && layout_node_has_content_height(child) {
			parent_constraints := Layout_Constraints{
				// layout_content_child_constraints subtracts the parent's padding,
				// so pass its outer width here and let that helper derive the
				// actual content width once.
				width=layout_axis_constraint_normalize(parent.bounds.w, parent.bounds.w),
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
	main_sizes := make([]f32, count, allocator=rt.scratch_allocator)
	resolve_main_sizes(rt, children, parent.style.direction, available_units, main_sizes)
	// Width-sensitive row measurement waits until elastic allocation supplies
	// the real main-axis constraint. Measurement still finishes before any child
	// geometry is placed.
	for id, index in children {
		child := rt.nodes[id]
		main := main_sizes[index]
		if parent.style.direction == .Row && layout_node_has_content_height(child) {
			parent_constraints := Layout_Constraints{
				width=layout_axis_constraint_normalize(main, main),
				height=layout_axis_constraint_normalize(0, cross_size),
			}
			constraints := layout_content_child_constraints(parent, child, parent_constraints, assigned_width=main)
			_ = layout_measure_node(rt, child, constraints)
		}
		if (layout_grow_weight_is_finite_positive(child.style.grow) || child.style.compress_weight > 0) && node_has_text_product(child.kind) {
			_ = layout_measure_node(rt, child, layout_grow_measure_constraints(parent, child, main, cross_size))
		}
	}

	used_units: i64 = 0
	for id, index in children {
		main := main_sizes[index]
		used_units += i64(layout_unit_extent(main))
	}
	free_units := i64(available_units)-used_units
	if free_units < 0 { free_units = 0 }
	distribution := layout_options_distribution(parent.style.options)
	main_leading := layout_distribution_leading(Layout_Unit(free_units), count, distribution)
	main_offset_units := main_leading
	// A fixed-height virtual list realizes only the visible rows. Its first
	// realized row may begin above the viewport when the scroll position is
	// between row boundaries; the retained clip protects surrounding UI.
	main_scroll_offset: f32 = 0
	cross_offset: f32 = 0
	if parent.kind == .Virtual_List {
		if parent.style.direction == .Column {
			main_scroll_offset = -parent.layout_scroll_offset_y
			cross_offset = -parent.layout_scroll_offset_x
		} else {
			main_scroll_offset = -parent.layout_scroll_offset_x
			cross_offset = -parent.layout_scroll_offset_y
		}
	}
	main_offset_units += layout_unit_position(main_scroll_offset)
	row_rtl := parent.style.direction == .Row && layout_effective_writing_direction(rt, parent) == .Right_To_Left
	baseline_target := f32(0)
	if parent.style.direction == .Row && parent.style.align == .Baseline {
		for id in children {
			child := rt.nodes[id]
			cross := layout_child_cross_size(rt, parent, child, cross_size)
			baseline := layout_child_baseline(rt, child, cross)
			if baseline > baseline_target { baseline_target = baseline }
		}
	}
	for id, index in children {
		child := rt.nodes[id]
		layout_note_node_visit(rt, child)
		old_bounds := child.bounds
		main := main_sizes[index]
		main_units := layout_unit_extent(main)
		main_offset := layout_unit_to_f32(main_offset_units)
		if parent.style.direction == .Row {
			cross := layout_child_cross_size(rt, parent, child, cross_size)
			cross_pos := inner.y + cross_offset
			if parent.style.align == .Center { cross_pos += (cross_size-cross)/2 }
			if parent.style.align == .End { cross_pos += cross_size-cross }
			if parent.style.align == .Baseline {
				cross_pos = inner.y + cross_offset + baseline_target-layout_child_baseline(rt, child, cross)
			}
			main_pos := inner.x+main_offset
			if row_rtl { main_pos = inner.x+inner.w-main_offset-main }
			child.bounds = Rect{main_pos, cross_pos, clampf(main, child.style.min_width, child.style.max_width), cross}
		} else {
			cross := layout_child_cross_size(rt, parent, child, cross_size)
			cross_pos := inner.x + cross_offset
			cross_is_reversed := layout_effective_writing_direction(rt, parent) == .Right_To_Left
			if parent.style.align == .Center { cross_pos += (cross_size-cross)/2 }
			if parent.style.align == .End && !cross_is_reversed || parent.style.align == .Start && cross_is_reversed { cross_pos += cross_size-cross }
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
		main_offset_units += main_units + gap_units + layout_distribution_gap(Layout_Unit(free_units), count, index, distribution)
	}
	delete(main_sizes, rt.scratch_allocator)
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
