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

layout_measure_key_matches :: proc(state: Measure_State, key: Measure_Cache_Key) -> bool {
	if !state.cache_key.valid { return false }
	old := state.cache_key
	return old.input_revision == key.input_revision && old.dependencies == key.dependencies &&
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
	// The parent's normalized constraints are part of the measure contract.
	// In particular, a stretched cross axis is an exact measured output even
	// when the content's natural extent is smaller.
	result.size.width = layout_measure_constrain_axis(result.size.width, constraints.width)
	result.size.height = layout_measure_constrain_axis(result.size.height, constraints.height)
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
	state.cache_key = key
	state.result = result
	rt.measure_states[node.id] = state
	dirty_set(&node.dirty, .Measure, false)
	return result
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
