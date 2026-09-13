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
	fmt.sbprintf(&sb, "focused: %d\n", rt.focused)
	fmt.sbprintf(&sb, "retained nodes: %d\n", len(rt.nodes))
	fmt.sbprintf(&sb, "last invalidation: %s\n", rt.last_invalidation_reason)
	fmt.sbprintf(&sb, "frame: %d built=%d idle=%d regions-skipped=%d\n", rt.stats.frame, rt.stats.frames_built, rt.stats.idle_frames, rt.stats.regions_skipped)
	for id in rt.order {
		node, ok := rt.nodes[id]
		if !ok { continue }
		fmt.sbprintf(&sb, "Node: %d parent=%d kind=%v source=%s:%d:%d component=%s key=%q scope=%q bounds=(%.1f,%.1f %.1fx%.1f)\n", node.id, node.parent, node.kind, node.site.file, node.site.line, node.site.column, node.site.component, node.key, node.identity_key, node.bounds.x, node.bounds.y, node.bounds.w, node.bounds.h)
		fmt.sbprintf(&sb, "  description: %s layout: %s paint: %s composite: %s\n", stage_word(node.dirty.description), stage_word(node.dirty.layout), stage_word(node.dirty.paint), stage_word(node.dirty.composite))
		fmt.sbprintf(&sb, "  reason: %s\n", node.last_reason)
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
