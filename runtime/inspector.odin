package alicorn

import "core:fmt"
import "core:strings"

stage_word :: proc(value: bool) -> string {
	if value { return "changed" }
	return "reused"
}

inspect :: proc(rt: ^Runtime) -> string {
	sb := strings.builder_make()
	fmt.sbprintln(&sb, "Alicorn inspector")
	fmt.sbprintf(&sb, "focused: %d selected: %d captured: %d\n", rt.focused, rt.selected, rt.captured_node)
	fmt.sbprintf(&sb, "retained nodes: %d\n", len(rt.nodes))
	fmt.sbprintf(&sb, "last invalidation: %s\n", rt.last_invalidation_reason)
	fmt.sbprintf(&sb, "frame: %d built=%d idle=%d regions-skipped=%d subtrees-reused=%d adjacency-rebuilds=%d surface-updates=%d surface-pending=%t\n", rt.stats.frame, rt.stats.frames_built, rt.stats.idle_frames, rt.stats.regions_skipped, rt.stats.retained_subtrees_reused, rt.stats.adjacency_rebuilds, rt.stats.surface_updates, rt.surface_frame_pending)
	fmt.sbprintf(&sb, "work: reconcile=%d layout=%d paint=%d compose=%d created=%d retired=%d\n", rt.stats.reconcile_nodes_visited, rt.stats.layout_nodes_visited, rt.stats.paint_nodes_visited, rt.stats.composition_nodes_visited, rt.stats.nodes_created, rt.stats.nodes_retired)
	for id in rt.order {
		node, ok := rt.nodes[id]
		if !ok { continue }
		if node.identity_key_kind == 3 {
			fmt.sbprintf(&sb, "Node: %d parent=%d kind=%v source=%s:%d:%d component=%s key=%q scope_pair=(%d,%d) bounds=(%.1f,%.1f %.1fx%.1f)\n", node.id, node.parent, node.kind, node.site.file, node.site.line, node.site.column, node.site.component, node.key, node.identity_key_pair.first, node.identity_key_pair.second, node.bounds.x, node.bounds.y, node.bounds.w, node.bounds.h)
		} else if node.identity_key_numeric {
			fmt.sbprintf(&sb, "Node: %d parent=%d kind=%v source=%s:%d:%d component=%s key=%q scope_u64=%d bounds=(%.1f,%.1f %.1fx%.1f)\n", node.id, node.parent, node.kind, node.site.file, node.site.line, node.site.column, node.site.component, node.key, node.identity_key_u64, node.bounds.x, node.bounds.y, node.bounds.w, node.bounds.h)
		} else {
			fmt.sbprintf(&sb, "Node: %d parent=%d kind=%v source=%s:%d:%d component=%s key=%q scope=%q bounds=(%.1f,%.1f %.1fx%.1f)\n", node.id, node.parent, node.kind, node.site.file, node.site.line, node.site.column, node.site.component, node.key, node.identity_key, node.bounds.x, node.bounds.y, node.bounds.w, node.bounds.h)
		}
		fmt.sbprintf(&sb, "  description: %s layout: %s paint: %s composite: %s\n", stage_word(dirty_has(node.dirty, .Description)), stage_word(dirty_has(node.dirty, .Layout)), stage_word(dirty_has(node.dirty, .Paint)), stage_word(dirty_has(node.dirty, .Composite)))
		if node.kind == .Custom_Surface {
			fmt.sbprintf(&sb, "  surface: revision=%d samples=%d pixels=%dx%d dpi=%.2f clip=(%.1f,%.1f %.1fx%.1f)\n", node.surface_revision, len(node.surface_samples), node.surface_pixel_width, node.surface_pixel_height, node.surface_dpi_scale, node.clip.x, node.clip.y, node.clip.w, node.clip.h)
		}
		fmt.sbprintf(&sb, "  selected=%t hovered=%t pressed=%t caret=(%d,%v) selection=(%d,%v)->(%d,%v) reason: %s\n", node.selected, node.hovered, node.pressed, node.caret.byte, node.caret.affinity, node.selection_anchor.byte, node.selection_anchor.affinity, node.selection_focus.byte, node.selection_focus.affinity, node.last_reason)
		if node.composition.active {
			fmt.sbprintf(&sb, "  composition: active text-bytes=%d selection=(%d,%d) replaces=(%d,%v)->(%d,%v)\n", len(node.composition.text), node.composition.selection_start, node.composition.selection_end, node.composition.replace_anchor.byte, node.composition.replace_anchor.affinity, node.composition.replace_focus.byte, node.composition.replace_focus.affinity)
		}
	}
	if rt.hard_error {
		fmt.sbprintf(&sb, "HARD ERROR: %s\n", rt.diagnostic)
	}
	return strings.to_string(sb)
}

trace_snapshot :: proc(rt: ^Runtime) -> []Trace_Event {
	result := make([]Trace_Event, rt.trace.count)
	start := (rt.trace.next - rt.trace.count + len(rt.trace.events)) % len(rt.trace.events)
	for i := 0; i < rt.trace.count; i += 1 {
		result[i] = rt.trace.events[(start+i)%len(rt.trace.events)]
	}
	return result
}
