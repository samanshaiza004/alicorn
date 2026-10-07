package alicorn

import "core:math"
import "core:fmt"

// The first geometry experiment uses 1/1024 logical units. This is not a
// public ABI choice: f32 input precision dominates at large coordinates, so
// the conformance tests compare coarser/finer scales and report round-trip
// error before this policy is treated as stable.
LAYOUT_UNIT_SCALE :: f32(1024)
LAYOUT_UNIT_LIMIT :: f32(1 << 50)

layout_round_nearest :: proc(value: f32) -> f32 {
	if value < 0 { return -math.floor(-value+0.5) }
	return math.floor(value+0.5)
}

layout_unit_position :: proc(value: f32) -> Layout_Unit {
	if math.is_nan(value) || math.is_inf(value) { return 0 }
	scaled := value*LAYOUT_UNIT_SCALE
	if scaled > LAYOUT_UNIT_LIMIT { scaled = LAYOUT_UNIT_LIMIT }
	if scaled < -LAYOUT_UNIT_LIMIT { scaled = -LAYOUT_UNIT_LIMIT }
	return Layout_Unit(i64(layout_round_nearest(scaled)))
}

layout_unit_extent :: proc(value: f32) -> Layout_Unit {
	if math.is_nan(value) || math.is_inf(value) || value <= 0 { return 0 }
	scaled := value*LAYOUT_UNIT_SCALE
	if scaled > LAYOUT_UNIT_LIMIT { scaled = LAYOUT_UNIT_LIMIT }
	return Layout_Unit(i64(math.ceil(scaled)))
}

// Finite maximum constraints round inward so quantization never permits a
// measured extent to exceed the caller's bound. Minimum extents round out.
layout_unit_maximum :: proc(value: f32) -> Layout_Unit {
	if math.is_nan(value) || math.is_inf(value) || value < 0 { return 0 }
	scaled := value*LAYOUT_UNIT_SCALE
	if scaled > LAYOUT_UNIT_LIMIT { scaled = LAYOUT_UNIT_LIMIT }
	return Layout_Unit(i64(math.floor(scaled)))
}

layout_unit_to_f32 :: proc(value: Layout_Unit) -> f32 {
	return f32(i64(value))/LAYOUT_UNIT_SCALE
}

layout_target_rect_from_rect :: proc(rect: Rect) -> Target_Layout_Rect {
	left := layout_unit_position(rect.x)
	top := layout_unit_position(rect.y)
	right := layout_unit_position(rect.x+maxf(rect.w, 0))
	bottom := layout_unit_position(rect.y+maxf(rect.h, 0))
	if right < left { right = left }
	if bottom < top { bottom = top }
	return Target_Layout_Rect{left, top, right, bottom}
}

layout_target_rect_to_rect :: proc(target: Target_Layout_Rect) -> Rect {
	left, top := layout_unit_to_f32(target.left), layout_unit_to_f32(target.top)
	right, bottom := layout_unit_to_f32(target.right), layout_unit_to_f32(target.bottom)
	return Rect{left, top, maxf(right-left, 0), maxf(bottom-top, 0)}
}

layout_snap_edge :: proc(edge: Layout_Unit, scale: f32) -> f32 {
	logical := layout_unit_to_f32(edge)
	return layout_round_nearest(logical*scale)/scale
}

layout_finalize_target_rect :: proc(target: Target_Layout_Rect, scale_x, scale_y: f32) -> Rect {
	sx := scale_x if scale_x > 0 && !math.is_nan(scale_x) && !math.is_inf(scale_x) else 1
	sy := scale_y if scale_y > 0 && !math.is_nan(scale_y) && !math.is_inf(scale_y) else 1
	left := layout_snap_edge(target.left, sx)
	right := layout_snap_edge(target.right, sx)
	top := layout_snap_edge(target.top, sy)
	bottom := layout_snap_edge(target.bottom, sy)
	return Rect{left, top, maxf(right-left, 0), maxf(bottom-top, 0)}
}

layout_finalize_rect :: proc(rect: Rect, scale_x, scale_y: f32) -> Rect {
	return layout_finalize_target_rect(layout_target_rect_from_rect(rect), scale_x, scale_y)
}

layout_rect_to_target :: proc(rect: Rect) -> Rect {
	return layout_target_rect_to_rect(layout_target_rect_from_rect(rect))
}

layout_axis_constraint_normalize :: proc(minimum, maximum: f32) -> Layout_Axis_Constraint {
	min_value := minimum
	if math.is_nan(min_value) || math.is_inf(min_value) || min_value < 0 { min_value = 0 }
	min_units := layout_unit_extent(min_value)
	if maximum < 0 || math.is_nan(maximum) || math.is_inf(maximum) {
		return Layout_Axis_Constraint{min=min_units, max=min_units, unbounded_max=true}
	}
	max_units := layout_unit_maximum(maximum)
	if max_units < min_units { max_units = min_units }
	return Layout_Axis_Constraint{min=min_units, max=max_units}
}

layout_constraints_equal :: proc(a, b: Layout_Constraints) -> bool {
	return a.width == b.width && a.height == b.height
}

layout_measure_dependencies :: proc(rt: ^Runtime, node: ^Node) -> Measure_Dependencies {
	if rt == nil || node == nil { return {} }
	return Measure_Dependencies{
		metrics_generation=node.style_generations.metrics,
		typography_generation=node.style_generations.typography,
		font_generation=rt.text_engine.font_generation,
	}
}

layout_size_is_fit_content :: proc(value: f32) -> bool {
	return value == LAYOUT_SIZE_FIT_CONTENT
}

layout_node_has_content_height :: proc(node: ^Node) -> bool {
	if node == nil || !layout_size_is_fit_content(node.style.height) { return false }
	if node.kind == .Scroll_Region { return true }
	return node.kind == .Container && node.style.direction == .Column
}

// Content signatures cover only realized descendants whose sizes contribute
// to this measured container. Virtual lists contribute their declared extent
// through the Scroll_Region node and never walk unrealized items.
layout_measure_content_signature :: proc(rt: ^Runtime, node: ^Node) -> u64 {
	if rt == nil || node == nil || !layout_node_has_content_height(node) { return 0 }
	h := hash_mix(1469598103934665603, node.layout_hash)
	h = hash_mix(h, u64(node.kind))
	h = hash_mix(h, u64(transmute(u32)node.scroll_content_height))
	// Scroll regions measure their declared logical extent, not the currently
	// realized virtual rows. Scrolling therefore does not perturb this key.
	if node.kind == .Scroll_Region { return h }
	for child_id in node.children {
		child, ok := rt.nodes[child_id]
		if !ok || child == nil || !child.active { continue }
		state := rt.measure_states[child_id]
		h = hash_mix(h, u64(child_id))
		h = hash_mix(h, child.layout_hash)
		h = hash_mix(h, state.input_revision)
		h = hash_mix(h, u64(transmute(u32)child.scroll_content_height))
		h = hash_mix(h, u64(state.cache_key.valid ? 1 : 0))
		if state.cache_key.valid {
			h = hash_mix(h, u64(i64(state.result.size.width)))
			h = hash_mix(h, u64(i64(state.result.size.height)))
			h = hash_mix(h, u64(i64(state.cache_key.constraints.width.min)))
			h = hash_mix(h, u64(i64(state.cache_key.constraints.width.max)))
			h = hash_mix(h, u64(state.cache_key.constraints.width.unbounded_max ? 1 : 0))
			h = hash_mix(h, u64(i64(state.cache_key.constraints.height.min)))
			h = hash_mix(h, u64(i64(state.cache_key.constraints.height.max)))
			h = hash_mix(h, u64(state.cache_key.constraints.height.unbounded_max ? 1 : 0))
			h = hash_mix(h, u64(state.cache_key.dependencies.metrics_generation))
			h = hash_mix(h, u64(state.cache_key.dependencies.typography_generation))
			h = hash_mix(h, state.cache_key.dependencies.font_generation)
		}
		if layout_node_has_content_height(child) {
			h = hash_mix(h, layout_measure_content_signature(rt, child))
		}
	}
	return h
}

layout_content_child_constraints :: proc(
	parent: ^Node,
	child: ^Node,
	parent_constraints: Layout_Constraints,
	assigned_width: f32 = -1,
) -> Layout_Constraints {
	if parent == nil || child == nil { return {} }
	content_width: f32 = parent.bounds.w-2*maxf(parent.style.padding, 0)
	if !parent_constraints.width.unbounded_max {
		content_width = layout_unit_to_f32(parent_constraints.width.max)-2*maxf(parent.style.padding, 0)
	}
	if assigned_width >= 0 { content_width = assigned_width
	} else if child.style.width >= 0 { content_width = child.style.width }
	content_width = clampf(content_width, child.style.min_width, child.style.max_width)
	width := layout_axis_constraint_normalize(content_width, content_width)

	height := layout_axis_constraint_normalize(child.style.min_height, child.style.max_height)
	if child.style.height >= 0 {
		assigned_height := clampf(child.style.height, child.style.min_height, child.style.max_height)
		height = layout_axis_constraint_normalize(assigned_height, assigned_height)
	} else if layout_node_has_content_height(child) && !parent_constraints.height.unbounded_max {
		max_height := layout_unit_to_f32(parent_constraints.height.max)
		if child.style.max_height >= 0 { max_height = minf(max_height, child.style.max_height) }
		height = layout_axis_constraint_normalize(child.style.min_height, max_height)
	}
	return Layout_Constraints{width=width, height=height}
}

layout_content_add_units :: proc(total: i64, amount: Layout_Unit) -> i64 {
	limit := i64(1 << 50)
	value := i64(amount)
	if value <= 0 { return total }
	if total >= limit-value { return limit }
	return total+value
}

layout_measure_content_height :: proc(rt: ^Runtime, node: ^Node, constraints: Layout_Constraints) -> Layout_Unit {
	if rt == nil || node == nil { return 0 }
	if node.kind == .Scroll_Region {
		outer := layout_unit_extent(node.scroll_content_height+2*maxf(node.style.padding, 0))
		style_constraint := layout_axis_constraint_normalize(node.style.min_height, node.style.max_height)
		return layout_measure_constrain_axis(outer, style_constraint)
	}
	if node.style.direction != .Column {
		record_trace(rt, .Measure, node.id, "fit-content height currently requires Column direction")
		return 0
	}
	total: i64 = 0
	realized_children := 0
	for child_id in node.children {
		child, ok := rt.nodes[child_id]
		if !ok || child == nil || !child.active { continue }
		realized_children += 1
		child_constraints := layout_content_child_constraints(node, child, constraints)
		measured := layout_measure_node(rt, child, child_constraints)
		child_state := rt.measure_states[child_id]
		child_state.parent_size_dependencies = {.Height_To_Height}
		rt.measure_states[child_id] = child_state
		total = layout_content_add_units(total, measured.size.height)
	}
	if realized_children > 1 {
		gap := layout_unit_extent(maxf(node.style.gap, 0))
		for _ in 1..<realized_children { total = layout_content_add_units(total, gap) }
	}
	padding := layout_unit_extent(maxf(node.style.padding, 0))
	total = layout_content_add_units(total, padding)
	total = layout_content_add_units(total, padding)
	return Layout_Unit(total)
}

layout_measure_key_matches :: proc(state: Measure_State, key: Measure_Cache_Key) -> bool {
	if !state.cache_key.valid { return false }
	old := state.cache_key
	return old.input_revision == key.input_revision && old.content_signature == key.content_signature && old.dependencies == key.dependencies &&
	       layout_constraints_equal(old.constraints, key.constraints)
}

layout_measure_changed_axes :: proc(old, next: Measure_Result) -> Layout_Axes {
	changed: Layout_Axes = {}
	if old.size.width != next.size.width { changed += {.Width} }
	if old.size.height != next.size.height { changed += {.Height} }
	return changed
}

layout_measure_result_equal :: proc(a, b: Measure_Result) -> bool {
	return a.size == b.size && a.baseline == b.baseline && a.baseline_valid == b.baseline_valid &&
	       a.input_axis_dependencies == b.input_axis_dependencies
}

layout_parent_placement_depends_on :: proc(state: Measure_State, changed: Layout_Axes) -> bool {
	for axis in Layout_Axis {
		if axis in changed && axis in state.parent_layout_dependencies { return true }
	}
	return false
}

layout_map_child_size_change :: proc(dependencies: Parent_Size_Dependencies, child_axes: Layout_Axes) -> Layout_Axes {
	changed: Layout_Axes = {}
	if .Width in child_axes {
		if .Width_To_Width in dependencies { changed += {.Width} }
		if .Width_To_Height in dependencies { changed += {.Height} }
	}
	if .Height in child_axes {
		if .Height_To_Width in dependencies { changed += {.Width} }
		if .Height_To_Height in dependencies { changed += {.Height} }
	}
	return changed
}

measure_cache_reason :: proc(old, next: Measure_Cache_Key) -> string {
	if !old.valid { return "no retained constraints; initial measure" }
	if old.input_revision != next.input_revision { return "local measurement-input fingerprint changed" }
	if old.content_signature != next.content_signature { return "realized content measurement signature changed" }
	if old.dependencies.metrics_generation != next.dependencies.metrics_generation { return "metrics generation changed" }
	if old.dependencies.typography_generation != next.dependencies.typography_generation { return "typography generation changed" }
	if old.dependencies.font_generation != next.dependencies.font_generation { return "font generation changed" }
	if !layout_constraints_equal(old.constraints, next.constraints) {
		old_width := "unbounded"
		new_width := "unbounded"
		if !old.constraints.width.unbounded_max { old_width = fmt.tprintf("%.3f", layout_unit_to_f32(old.constraints.width.max)) }
		if !next.constraints.width.unbounded_max { new_width = fmt.tprintf("%.3f", layout_unit_to_f32(next.constraints.width.max)) }
		return fmt.tprintf("normalized width constraint %s → %s", old_width, new_width)
	}
	return "declared measurement dependency changed"
}

layout_measure_intrinsic_size :: proc(node: ^Node) -> Layout_Size {
	padding_x: f32 = 0
	padding_y: f32 = 0
	if node.kind == .Button {
		padding_x = maxf(node.button_content_style.padding_x, 0)
		padding_y = maxf(node.button_content_style.padding_y, 0)
	}
	width := node.style.width
	height := node.style.height
	if width < 0 {
		#partial switch node.kind {
		case .Checkbox:
			width = 116
			if node.text_run_valid { width = node.text_run.width+36 }
		case .Slider: width = 180
		case:
			width = 80+2*padding_x
			if node.text_run_valid { width = node.text_run.width+2*padding_x }
		}
	}
	if height < 0 {
		#partial switch node.kind {
		case .Checkbox:
			height = 28
			if node.text_run_valid { height = maxf(28, node.text_run.height+8) }
		case .Slider:
			height = 44
			if node.text_run_valid { height = maxf(44, node.text_run.height+24) }
		case:
			height = 24+2*padding_y
			if node.text_run_valid { height = node.text_run.height+2*padding_y }
		}
	}
	width = clampf(width, node.style.min_width, node.style.max_width)
	height = clampf(height, node.style.min_height, node.style.max_height)
	return Layout_Size{layout_unit_extent(width), layout_unit_extent(height)}
}

layout_measure_constrain_axis :: proc(value: Layout_Unit, constraint: Layout_Axis_Constraint) -> Layout_Unit {
	result := value
	if result < constraint.min { result = constraint.min }
	if !constraint.unbounded_max && result > constraint.max { result = constraint.max }
	return result
}

layout_measure_node :: proc(rt: ^Runtime, node: ^Node, constraints: Layout_Constraints) -> Measure_Result {
	if rt == nil || node == nil { return {} }
	state := rt.measure_states[node.id]
	state.parent_layout_dependencies = layout_parent_placement_axes(rt, node)
	rt.stats.measure_requests += 1
	rt.stats.stage_visits[.Measure] += 1
	key := Measure_Cache_Key{
		constraints=constraints,
		input_revision=state.input_revision,
		content_signature=layout_measure_content_signature(rt, node),
		dependencies=layout_measure_dependencies(rt, node),
		valid=true,
	}
	rt.measure_states[node.id] = state
	if layout_measure_key_matches(state, key) {
		rt.stats.measure_cache_hits += 1
		dirty_set(&node.dirty, .Measure, false)
		return state.result
	}
	rt.stats.measure_cache_misses += 1
	reason := measure_cache_reason(state.cache_key, key)
	record_trace(rt, .Measure, node.id, fmt.tprintf("measure cache miss: %s", reason))
	if node_has_text_product(node.kind) {
		max_width: f32 = -1
		if !constraints.width.unbounded_max {
			max_width = layout_unit_to_f32(constraints.width.max)
		} else if node.style.width >= 0 {
			max_width = clampf(node.style.width, node.style.min_width, node.style.max_width)
		} else if node.style.max_width >= 0 {
			max_width = node.style.max_width
		}
		if max_width >= 0 {
			if node.kind == .Button { max_width = maxf(max_width-2*maxf(node.button_content_style.padding_x, 0), 0) }
			if node.kind == .Checkbox { max_width = maxf(max_width-36, 0) }
		}
		shape_calls_before := rt.text_engine.shape_calls
		if prepare_text_run_node(rt, node, max_width) {
			dirty_set(&node.dirty, .Paint, true)
			dirty_set(&node.dirty, .Composite, true)
			queue_paint(rt, node.id)
		}
		rt.stats.text_shape_requests += rt.text_engine.shape_calls-shape_calls_before
	}
	result := Measure_Result{size=layout_measure_intrinsic_size(node)}
	content_height: Layout_Unit = 0
	if layout_node_has_content_height(node) {
		content_height = layout_measure_content_height(rt, node, constraints)
		style_constraint := layout_axis_constraint_normalize(node.style.min_height, node.style.max_height)
		result.size.height = layout_measure_constrain_axis(content_height, style_constraint)
	}
	// The parent's normalized constraints are part of the measure contract.
	// In particular, a stretched cross axis is an exact measured output even
	// when the content's natural extent is smaller.
	result.size.width = layout_measure_constrain_axis(result.size.width, constraints.width)
	result.size.height = layout_measure_constrain_axis(result.size.height, constraints.height)
	if layout_node_has_content_height(node) {
		kind := "Column children"
		if node.kind == .Scroll_Region { kind = "scroll extent" }
		record_trace(rt, .Measure, node.id, fmt.tprintf(
			"fit-content height (%s): content %.3f, measured %.3f",
			kind,
			layout_unit_to_f32(content_height),
			layout_unit_to_f32(result.size.height),
		))
	}
	if node.text_run_valid && len(node.text_run.lines) > 0 {
		baseline := node.text_run.lines[0].baseline
		#partial switch node.kind {
		case .Button:
			padding_y := maxf(node.button_content_style.padding_y, 0)
			content_height := maxf(layout_unit_to_f32(result.size.height)-2*padding_y, 0)
			if node.button_content_style.vertical == .Center { baseline += padding_y+(content_height-node.text_run.height)*0.5 }
			else if node.button_content_style.vertical == .End { baseline += padding_y+content_height-node.text_run.height }
			else { baseline += padding_y }
		case .Checkbox:
			baseline += (layout_unit_to_f32(result.size.height)-node.text_run.height)*0.5
		case .Slider:
			baseline += 1
		}
		result.baseline = layout_unit_position(baseline)
		result.baseline_valid = true
		if !constraints.width.unbounded_max {
			result.input_axis_dependencies += {.Width_To_Width}
			if node.kind == .Text_Field || node.text_style.overflow == .Wrap {
				result.input_axis_dependencies += {.Width_To_Height}
			}
		}
		if !constraints.height.unbounded_max { result.input_axis_dependencies += {.Height_To_Height} }
	}
	// Content children may have been measured while producing this result.
	// Retain their settled signature so the next identical request is a hit.
	key.content_signature = layout_measure_content_signature(rt, node)
	state.cache_key = key
	state.result = result
	rt.measure_states[node.id] = state
	dirty_set(&node.dirty, .Measure, false)
	return result
}

layout_measure_propagate_parent_size_change :: proc(rt: ^Runtime, child_id: Node_ID, child_axes: Layout_Axes) {
	if rt == nil || child_id == 0 || child_axes == {} { return }
	child, child_ok := rt.nodes[child_id]
	child_state, state_ok := rt.measure_states[child_id]
	if !child_ok || child == nil || !state_ok { return }
	parent_axes := layout_map_child_size_change(child_state.parent_size_dependencies, child_axes)
	if parent_axes == {} { return }
	parent, parent_ok := rt.nodes[child.parent]
	if !parent_ok || parent == nil || !layout_node_has_content_height(parent) { return }
	parent_state := rt.measure_states[parent.id]
	if !parent_state.cache_key.valid {
		dirty_set(&parent.dirty, .Measure, true)
		mark_layout_ancestors(rt, parent.id)
		return
	}
	old_result := parent_state.result
	dirty_set(&parent.dirty, .Measure, true)
	_ = layout_measure_node(rt, parent, parent_state.cache_key.constraints)
	parent_state = rt.measure_states[parent.id]
	changed_axes := layout_measure_changed_axes(old_result, parent_state.result)
	if changed_axes == {} {
		record_trace(rt, .Measure, parent.id, fmt.tprintf("child size changed on %v; content clamp kept the parent size", parent_axes))
		return
	}
	record_trace(rt, .Measure, parent.id, fmt.tprintf("content size changed on axes %v after child change", changed_axes))
	mark_layout_ancestors(rt, parent.id)
	layout_measure_propagate_parent_size_change(rt, parent.id, changed_axes)
}

// A dirty node can be measured before layout only when a previous parent pass
// supplied real constraints. New nodes and nodes whose constraints changed
// are measured by their parent during layout instead of receiving a guessed
// unconstrained proposal.
layout_measure_retained_dirty_nodes :: proc(rt: ^Runtime) {
	if rt == nil { return }
	font_changed := rt.text_font_generation_seen != rt.text_engine.font_generation
	if font_changed { rt.text_font_generation_seen = rt.text_engine.font_generation }
	for id in rt.order {
		node, ok := rt.nodes[id]
		if !ok || node == nil || !node.active { continue }
		if font_changed && node_has_text_product(node.kind) { dirty_set(&node.dirty, .Measure, true) }
		state := rt.measure_states[id]
		if !dirty_has(node.dirty, .Measure) || !state.cache_key.valid { continue }
		old_result := state.result
		_ = layout_measure_node(rt, node, state.cache_key.constraints)
		state = rt.measure_states[id]
		changed_axes := layout_measure_changed_axes(old_result, state.result)
		if changed_axes == {} {
			record_trace(rt, .Measure, id, "remeasured result unchanged; parent placement retained")
			continue
		}
		record_trace(rt, .Measure, id, fmt.tprintf("measured output changed on axes %v", changed_axes))
		layout_measure_propagate_parent_size_change(rt, id, changed_axes)
		if layout_parent_placement_depends_on(state, changed_axes) {
			mark_layout_ancestors(rt, id)
			record_trace(rt, .Layout, node.parent, "child measurement changed; parent placement invalidated")
		}
	}
}

layout_text_measure_constraints :: proc(parent: ^Node, child: ^Node, cross_size: f32) -> Layout_Constraints {
	width := layout_axis_constraint_normalize(0, -1)
	height := layout_axis_constraint_normalize(0, -1)
	if child.style.width < 0 && parent.style.direction == .Column {
		assigned_width := clampf(cross_size, child.style.min_width, child.style.max_width)
		width = layout_axis_constraint_normalize(assigned_width, assigned_width)
	}
	if child.style.height < 0 && parent.style.direction == .Row {
		assigned_height := clampf(cross_size, child.style.min_height, child.style.max_height)
		height = layout_axis_constraint_normalize(assigned_height, assigned_height)
	}
	return Layout_Constraints{width=width, height=height}
}

layout_grow_measure_constraints :: proc(parent: ^Node, child: ^Node, assigned_main, cross_size: f32) -> Layout_Constraints {
	constraints := layout_text_measure_constraints(parent, child, cross_size)
	assigned := clampf(assigned_main, main_axis_min(child.style, parent.style.direction), main_axis_max(child.style, parent.style.direction))
	if parent.style.direction == .Row {
		constraints.width = layout_axis_constraint_normalize(assigned, assigned)
	} else {
		constraints.height = layout_axis_constraint_normalize(assigned, assigned)
	}
	return constraints
}

layout_node_finalized_geometry :: proc(rt: ^Runtime, id: Node_ID) -> Finalized_Geometry {
	if rt != nil {
		if geometry, ok := rt.finalized_geometry[id]; ok && geometry.valid { return geometry }
		if node, ok := rt.nodes[id]; ok && node != nil {
			return Finalized_Geometry{bounds=node.bounds, hit_bounds=node.hit_bounds, clip=node.clip, valid=true}
		}
	}
	return {}
}

layout_finalize_node_geometry_for_node :: proc(rt: ^Runtime, node: ^Node) {
	if rt == nil || node == nil { return }
	if !node.active {
		delete_key(&rt.finalized_geometry, node.id)
		return
	}
	rt.finalized_geometry[node.id] = Finalized_Geometry{
		bounds=layout_finalize_rect(node.bounds, rt.presentation_scale_x, rt.presentation_scale_y),
		hit_bounds=layout_finalize_rect(node.hit_bounds, rt.presentation_scale_x, rt.presentation_scale_y),
		clip=layout_finalize_rect(node.clip, rt.presentation_scale_x, rt.presentation_scale_y),
		valid=true,
	}
}

layout_finalize_node_geometry :: proc(rt: ^Runtime) {
	if rt == nil { return }
	for id in rt.order {
		node, ok := rt.nodes[id]
		if !ok || node == nil || !node.active { delete_key(&rt.finalized_geometry, id); continue }
		layout_finalize_node_geometry_for_node(rt, node)
	}
}

// display_target retains unsnapped paint geometry. Rebuilding the finalized
// list from it makes repeated DPI changes independent of previous snapping.
layout_finalize_display :: proc(rt: ^Runtime) {
	if rt == nil { return }
	clear(&rt.display)
	for target in rt.display_target {
		command := target
		command.bounds = layout_finalize_rect(target.bounds, rt.presentation_scale_x, rt.presentation_scale_y)
		command.clip = layout_finalize_rect(target.clip, rt.presentation_scale_x, rt.presentation_scale_y)
		append(&rt.display, command)
	}
}

// set_presentation_scale changes only the device-grid finalization. It never
// overwrites Node.bounds, so the next logical solve starts from the same target.
set_presentation_scale :: proc(rt: ^Runtime, scale_x, scale_y: f32) -> bool {
	if rt == nil || scale_x <= 0 || scale_y <= 0 || math.is_nan(scale_x) || math.is_nan(scale_y) ||
		math.is_inf(scale_x) || math.is_inf(scale_y) { return false }
	if rt.presentation_scale_x == scale_x && rt.presentation_scale_y == scale_y { return false }
	rt.presentation_scale_x, rt.presentation_scale_y = scale_x, scale_y
	layout_finalize_node_geometry(rt)
	for id in rt.order {
		if node, ok := rt.nodes[id]; ok { semantic_sync_bounds(rt, node) }
	}
	// Finalized bounds are part of the semantic projection. Publish this
	// presentation-only update immediately so revision-based hosts observe it
	// without waiting for a later application reconciliation.
	_ = semantic_commit(rt)
	layout_finalize_display(rt)
	request_presentation(rt, "device-scale finalization changed")
	advance_presentation_revision(rt)
	return true
}

layout_parent_placement_axes :: proc(rt: ^Runtime, node: ^Node) -> Layout_Axes {
	if rt == nil || node == nil || node.parent == 0 { return {} }
	parent, ok := rt.nodes[node.parent]
	if !ok || parent == nil { return {} }
	if parent.kind == .Split || parent.kind == .Context_Menu_Overlay { return {} }
	if parent.style.direction == .Row { return {.Width} }
	// Column placement consumes child height for following rows and child
	// width for the child's cross-axis bounds/alignment. A width-only change
	// still requires refreshing that parent even though its external size is
	// unaffected.
	return {.Width, .Height}
}
