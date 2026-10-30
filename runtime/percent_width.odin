package alicorn

import "core:fmt"
import "core:math"

layout_percent_width_sidecar_ensure :: proc(rt: ^Runtime) {
	if rt == nil || rt.percent_width_sidecar_initialized { return }
	rt.percent_width_dependencies = make(map[Node_ID]Percent_Width_Dependency, allocator=rt.persistent_allocator)
	rt.pending_percent_widths = make(map[Node_ID]Percent_Width_Declaration, allocator=rt.persistent_allocator)
	rt.percent_width_sidecar_initialized = true
}

// layout_percent_width_register is called by the UI authoring layer after it
// emits a percentage-sized node. The relation is staged with the description
// and retained separately from Node and Pending_Item, so ordinary nodes carry
// no percentage-specific storage.
layout_percent_width_register :: proc(ui: ^UI, child: Node_ID, fraction: f32) {
	if ui == nil || ui.runtime == nil || child == 0 { return }
	rt := ui.runtime
	if len(rt.pending) == 0 { return }
	last := &rt.pending[len(rt.pending)-1]
	if last.kind != .Description || last.description.id != child { return }
	layout_percent_width_sidecar_ensure(rt)
	rt.pending_percent_widths[child] = Percent_Width_Declaration{
		parent=last.description.parent,
		fraction=fraction,
	}
}

layout_percent_width_hash :: proc(base: u64, kind: Node_Kind, width: f32) -> u64 {
	// Text-product width is already represented by its measurement input hash.
	// Other nodes keep effective width in layout hashing as before.
	if node_has_text_product(kind) { return base }
	return hash_mix(base, u64(transmute(u32)width))
}

layout_percent_width_pending_hash :: proc(rt: ^Runtime, d: Description, item: Pending_Item) -> u64 {
	if rt == nil || !rt.percent_width_sidecar_initialized || len(rt.pending_percent_widths) == 0 {
		return layout_hash_pending(d, item)
	}
	declaration, found := rt.pending_percent_widths[d.id]
	if !found { return layout_hash_pending(d, item) }
	_ = declaration
	base_description := d
	base_description.style.width = -1
	base := layout_hash_pending(base_description, item)
	return layout_percent_width_hash(base, d.kind, d.style.width)
}

// layout_percent_width_commit_description updates the retained sparse
// relationship for an explicitly described node. Reused subtree descendants
// do not call this and therefore keep their declarations. Explicitly replacing
// a percentage with ordinary sizing removes the sidecar entry here.
layout_percent_width_commit_description :: proc(rt: ^Runtime, d: Description, item: Pending_Item) {
	if rt == nil || !rt.percent_width_sidecar_initialized || len(rt.pending_percent_widths) == 0 { return }
	declaration, found := rt.pending_percent_widths[d.id]
	if !found { return }
	base_description := d
	base_description.style.width = -1
	measure_base, measure_width_input := measure_input_hash_base(d)
	rt.percent_width_dependencies[d.id] = Percent_Width_Dependency{
		parent=declaration.parent,
		fraction=declaration.fraction,
		layout_hash_base=layout_hash_pending(base_description, item),
		measure_input_hash_base=measure_base,
		measure_input_has_width=measure_width_input,
	}
}

// Explicit descriptions that replace a percentage declaration are uncommon
// relative to the ordinary tree. Prune by walking the sparse dependency set,
// instead of probing an extra map for every described node.
layout_percent_width_prune_explicit :: proc(rt: ^Runtime, described: map[Node_ID]bool) {
	if rt == nil || !rt.percent_width_sidecar_initialized || len(rt.percent_width_dependencies) == 0 { return }
	for {
		retired_id: Node_ID
		found_retired := false
		for child_id, _ in rt.percent_width_dependencies {
			_, explicitly_described := described[child_id]
			if !explicitly_described { continue }
			_, still_percentage := rt.pending_percent_widths[child_id]
			if still_percentage { continue }
			retired_id = child_id
			found_retired = true
			break
		}
		if !found_retired { break }
		delete_key(&rt.percent_width_dependencies, retired_id)
	}
}

layout_percent_width_parent_extent :: proc(rt: ^Runtime, parent: ^Node) -> (f32, bool) {
	if rt == nil || parent == nil { return 0, false }
	if parent.kind == .Root || parent.kind == .Modal_Overlay {
		return rt.viewport.w, true
	}
	if parent.style.width >= 0 && parent.style.grow == 0 && parent.style.compress_weight == 0 {
		return clampf(parent.style.width, maxf(parent.style.min_width, 0), parent.style.max_width), true
	}
	return 0, false
}

layout_percent_width_update_retained :: proc(rt: ^Runtime) {
	if rt == nil || !rt.percent_width_sidecar_initialized || len(rt.percent_width_dependencies) == 0 { return }
	for child_id, &dependency in rt.percent_width_dependencies {
		child, child_found := rt.nodes[child_id]
		if !child_found || child == nil { continue }
		parent, parent_found := rt.nodes[dependency.parent]
		parent_extent: f32
		definite := false
		if parent_found && parent != nil { parent_extent, definite = layout_percent_width_parent_extent(rt, parent) }
		resolved_width := f32(-1)
		if definite {
			if math.is_nan(parent_extent) || math.is_inf(parent_extent) || parent_extent < 0 {
				definite = false
			} else {
				inner := maxf(parent_extent-2*maxf(parent.style.padding, 0), 0)
				resolved_width = inner*dependency.fraction
				if math.is_nan(resolved_width) || math.is_inf(resolved_width) {
					definite = false
					resolved_width = -1
				}
			}
		}
		if !definite {
			if !dependency.parent_invalid_reported {
				parent_label := "<missing parent>"
				if parent_found && parent != nil { parent_label = parent.label }
				append_diagnostic(rt, fmt.tprintf(
					"Invalid retained percentage width at %s:%d:%d: parent %q no longer has an independently definite width; its percentage child was reset to the ordinary unspecified width. A parent that becomes content-sized, allocated, growing, or compressible must be explicitly described with a new valid relationship.",
					child.site.file, child.site.line, child.site.column, parent_label,
				))
			}
			dependency.parent_invalid_reported = true
		} else {
			dependency.parent_invalid_reported = false
		}
		if child.style.width == resolved_width { continue }
		child.style.width = resolved_width
		new_layout_hash := layout_percent_width_hash(dependency.layout_hash_base, child.kind, resolved_width)
		layout_changed := child.layout_hash != new_layout_hash
		if layout_changed { child.layout_hash = new_layout_hash }
		measurement_changed := false
		if dependency.measure_input_has_width {
			new_measure_hash := hash_mix(dependency.measure_input_hash_base, u64(transmute(u32)resolved_width))
			measurement_changed = measure_input_observe(rt, child_id, new_measure_hash)
		}
		if layout_changed || measurement_changed {
			if measurement_changed { layout_measure_mark_dirty(rt, child) }
			dirty_set(&child.dirty, .Layout, true)
			dirty_set(&child.dirty, .Paint, true)
			dirty_set(&child.dirty, .Composite, true)
			queue_paint(rt, child_id)
			mark_layout_ancestors(rt, child_id)
			record_trace(rt, .Layout, child_id, "retained percentage width followed parent basis")
		}
	}
}

layout_percent_width_pending_clear :: proc(rt: ^Runtime) {
	if rt != nil && rt.percent_width_sidecar_initialized { clear(&rt.pending_percent_widths) }
}

layout_percent_width_destroy :: proc(rt: ^Runtime) {
	if rt == nil || !rt.percent_width_sidecar_initialized { return }
	delete(rt.percent_width_dependencies)
	delete(rt.pending_percent_widths)
	rt.percent_width_dependencies = nil
	rt.pending_percent_widths = nil
	rt.percent_width_sidecar_initialized = false
}
