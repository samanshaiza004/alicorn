package alicorn

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

intrinsic_main :: proc(node: ^Node, direction: Layout_Direction) -> f32 {
	if direction == .Row {
		if node.style.width >= 0 { return node.style.width }
		return 80
	}
	if node.style.height >= 0 { return node.style.height }
	return 24
}

layout_children :: proc(rt: ^Runtime, parent_id: Node_ID) {
	parent, ok := rt.nodes[parent_id]
	if !ok { return }
	children := parent.children[:]
	count := len(children)
	if count == 0 { return }
	inner := Rect{parent.bounds.x + parent.style.padding, parent.bounds.y + parent.style.padding, parent.bounds.w - 2*parent.style.padding, parent.bounds.h - 2*parent.style.padding}
	if inner.w < 0 { inner.w = 0 }
	if inner.h < 0 { inner.h = 0 }
	main_size := parent.style.direction == .Row ? inner.w : inner.h
	cross_size := parent.style.direction == .Row ? inner.h : inner.w
	gap_total := parent.style.gap * f32(count-1)
	available := maxf(main_size-gap_total, 0)
	fixed: f32 = 0
	grow: f32 = 0
	for id in children {
		rt.stats.layout_nodes_visited += 1
		child := rt.nodes[id]
		if child.style.grow > 0 {
			grow += child.style.grow
		} else {
			fixed += intrinsic_main(child, parent.style.direction)
		}
	}
	remaining := maxf(available-fixed, 0)
	main_offset: f32 = 0
	for id in children {
		child := rt.nodes[id]
		old_bounds := child.bounds
		main := intrinsic_main(child, parent.style.direction)
		if child.style.grow > 0 && grow > 0 {
			main = remaining * child.style.grow / grow
		}
		if parent.style.direction == .Row {
			cross := child.style.height >= 0 ? child.style.height : cross_size
			cross = clampf(cross, child.style.min_height, child.style.max_height)
			cross_pos := inner.y
			if parent.style.align == .Center { cross_pos += (cross_size-cross)/2 }
			if parent.style.align == .End { cross_pos += cross_size-cross }
			child.bounds = Rect{inner.x+main_offset, cross_pos, clampf(main, child.style.min_width, child.style.max_width), cross}
		} else {
			cross := child.style.width >= 0 ? child.style.width : cross_size
			cross = clampf(cross, child.style.min_width, child.style.max_width)
			cross_pos := inner.x
			if parent.style.align == .Center { cross_pos += (cross_size-cross)/2 }
			if parent.style.align == .End { cross_pos += cross_size-cross }
			child.bounds = Rect{cross_pos, inner.y+main_offset, cross, clampf(main, child.style.min_height, child.style.max_height)}
		}
		old_clip := child.clip
		if parent.style.clip { child.clip = rect_intersection(parent.clip, parent.bounds) } else { child.clip = parent.clip }
		bounds_changed := !same_rect(old_bounds, child.bounds)
		clip_changed := !same_rect(old_clip, child.clip)
		if bounds_changed || clip_changed {
			child.dirty.layout = true
			child.dirty.paint = true
			child.dirty.composite = true
			queue_paint(rt, id)
			rt.stats.layout_updates += 1
			record_trace(rt, .Layout, id, "layout hash or parent bounds changed")
		} else if child.dirty.layout {
			rt.stats.layout_updates += 1
			record_trace(rt, .Layout, id, "layout hash changed")
		}
		if bounds_changed || clip_changed || child.dirty.layout {
			layout_children(rt, id)
		}
		child.dirty.layout = false
		main_offset += main + parent.style.gap
	}
}

layout_tree :: proc(rt: ^Runtime) {
	for id in rt.top_level {
		node, ok := rt.nodes[id]
		if !ok || !node.active { continue }
		rt.stats.layout_nodes_visited += 1
		if node.parent == 0 {
			old := node.bounds
			node.bounds = rt.viewport
			node.clip = rt.viewport
			if !same_rect(old, node.bounds) {
				node.dirty.layout = true
				node.dirty.paint = true
				node.dirty.composite = true
				queue_paint(rt, id)
			}
			if !same_rect(old, node.bounds) || node.dirty.layout {
				layout_children(rt, id)
			}
			node.dirty.layout = false
		}
	}
}
