package alicorn

import "core:fmt"
import "core:mem"

INSPECTOR_CAUSE_LIMIT :: 20
INSPECTOR_ROW_HEIGHT :: f32(28)
INSPECTOR_LINE_HEIGHT :: f32(24)

Inspector_Tab :: enum { Tree, Focus, Work, Causes }

// The host owns this state and a separate Runtime used to describe the panel.
// IDs in selected/collapsed belong to the inspected Runtime; they are never
// used as that runtime's interaction state or persisted across process runs.
Inspector_Overlay :: struct {
	allocator: mem.Allocator,
	visible: bool,
	picking: bool,
	selected: Node_ID,
	collapsed: map[Node_ID]bool,
	tab: Inspector_Tab,
	panel_bounds: Rect,
	initial_focus: Node_ID,
	focus_initial_pending: bool,
}

// Platform-neutral data borrowed only while building the Work tab. Native
// handles and the host's telemetry storage stay outside the runtime package.
Inspector_Host_Summary :: struct {
	host_wakes: u64,
	application_builds: u64,
	application_submits: u64,
	overlay_submits: u64,
	event_ms: f64,
	build_ms: f64,
	encode_ms: f64,
	submit_ms: f64,
}

Inspector_Tree_Row :: struct {
	id: Node_ID,
	depth: int,
	has_children: bool,
}

// Cause summaries borrow their strings from the existing bounded trace ring.
// They live only through this description and are copied by reconciliation.
Inspector_Cause :: struct {
	id: u64,
	kind: Cause_Kind,
	action: Action_ID,
	latest_sequence: u64,
	node: Node_ID,
	origin: string,
	action_reason: string,
	invalidation: string,
	mutation: string,
	last_reason: string,
	visits: [Trace_Kind]u64,
}

inspector_overlay_make :: proc(allocator := context.allocator) -> Inspector_Overlay {
	return Inspector_Overlay{allocator=allocator, collapsed=make(map[Node_ID]bool, allocator=allocator)}
}

inspector_overlay_destroy :: proc(state: ^Inspector_Overlay) {
	if state == nil { return }
	delete(state.collapsed)
	state^ = Inspector_Overlay{}
}

inspector_overlay_open :: proc(state: ^Inspector_Overlay) {
	if state == nil { return }
	if !state.visible { state.focus_initial_pending = true }
	state.visible = true
}

inspector_overlay_close :: proc(state: ^Inspector_Overlay) {
	if state == nil { return }
	state.visible = false
	state.picking = false
	state.initial_focus = 0
	state.focus_initial_pending = false
}

// This tracks application truth, including its successful GPU acknowledgement.
// The host must acknowledge inspector-only submissions on its separate runtime.
inspector_overlay_source_fingerprint :: proc(inspected: ^Runtime) -> u64 {
	if inspected == nil { return 0 }
	h := hash_mix(1469598103934665603, inspected.presentation_revision)
	h = hash_mix(h, inspected.submitted_revision)
	h = hash_mix(h, inspected.stats.gpu_submits)
	h = hash_mix(h, inspected.trace.sequence)
	h = hash_mix(h, inspected.stats.frames_built)
	h = hash_mix(h, u64(inspected.focused))
	h = hash_mix(h, u64(inspected.selected))
	h = hash_mix(h, u64(inspected.captured_node))
	h = hash_mix(h, u64(inspected.last_hovered))
	h = hash_mix(h, inspected.semantic_focus.id.namespace)
	h = hash_mix(h, inspected.semantic_focus.id.value)
	h = hash_mix(h, u64(inspected.semantic_focus.owner))
	h = hash_mix(h, u64(inspected.semantic_focus.realized_node))
	h = hash_mix(h, u64(inspected.hard_error))
	h = hash_mix(h, hash_string(inspected.diagnostic))
	h = hash_mix(h, u64(inspected.invalidated))
	h = hash_mix(h, u64(inspected.layout_pending))
	h = hash_mix(h, u64(inspected.presentation_pending))
	h = hash_mix(h, u64(inspected.surface_frame_pending))
	return h
}

inspector_overlay_prune :: proc(state: ^Inspector_Overlay, inspected: ^Runtime, allocator := context.temp_allocator) {
	retired := make([dynamic]Node_ID, 0, allocator=allocator)
	defer delete(retired)
	for id in state.collapsed {
		if node, ok := inspected.nodes[id]; !ok || !node.active { append(&retired, id) }
	}
	for id in retired { delete_key(&state.collapsed, id) }
	if state.selected != 0 {
		if node, ok := inspected.nodes[state.selected]; !ok || !node.active { state.selected = 0 }
	}
}

inspector_overlay_toggle_collapsed :: proc(state: ^Inspector_Overlay, inspected: ^Runtime, id: Node_ID) -> bool {
	if state == nil || inspected == nil { return false }
	node, ok := inspected.nodes[id]
	if !ok || !node.active || len(node.children) == 0 { return false }
	if state.collapsed[id] { delete_key(&state.collapsed, id) }
	else { state.collapsed[id] = true }
	return true
}

// Traverse retained adjacency, preserving parents and omitting descendants of
// collapsed nodes before calculating the virtualized range.
inspector_overlay_tree_rows :: proc(state: ^Inspector_Overlay, inspected: ^Runtime, allocator := context.allocator) -> [dynamic]Inspector_Tree_Row {
	rows := make([dynamic]Inspector_Tree_Row, 0, allocator=allocator)
	if state == nil || inspected == nil { return rows }
	inspector_overlay_prune(state, inspected, allocator)
	stack := make([dynamic]Inspector_Tree_Row, 0, allocator=allocator)
	visited := make(map[Node_ID]bool, allocator=allocator)
	defer delete(stack)
	defer delete(visited)
	for index := len(inspected.top_level)-1; index >= 0; index -= 1 {
		append(&stack, Inspector_Tree_Row{id=inspected.top_level[index]})
	}
	for len(stack) > 0 {
		row := pop(&stack)
		if visited[row.id] { continue }
		visited[row.id] = true
		node, ok := inspected.nodes[row.id]
		if !ok || !node.active { continue }
		for child in node.children {
			if child_node, found := inspected.nodes[child]; found && child_node.active { row.has_children = true; break }
		}
		append(&rows, row)
		if state.collapsed[row.id] { continue }
		for index := len(node.children)-1; index >= 0; index -= 1 {
			append(&stack, Inspector_Tree_Row{id=node.children[index], depth=row.depth+1})
		}
	}
	return rows
}

// Geometry picking deliberately includes disabled controls and noninteractive
// presentation nodes. The normal input hit tester excludes those by design.
inspector_overlay_pick :: proc(state: ^Inspector_Overlay, inspected: ^Runtime, x, y: f32) -> Node_ID {
	if state == nil || inspected == nil || !state.visible || !state.picking { return 0 }
	modal_root := modal_overlay_root(inspected)
	for index := len(inspected.order)-1; index >= 0; index -= 1 {
		id := inspected.order[index]
		node, ok := inspected.nodes[id]
		geometry := layout_node_finalized_geometry(inspected, id)
		if ok && node.active && node_is_in_modal_overlay(inspected, id, modal_root) &&
			rect_contains(geometry.bounds, x, y) && rect_contains(geometry.clip, x, y) {
			state.selected = id
			state.picking = false
			return id
		}
	}
	return 0
}

// Group up to 20 recent cause IDs without copying or extending telemetry. A
// zero ID is shown explicitly as unassigned work; no attribution is inferred.
inspector_overlay_recent_causes :: proc(inspected: ^Runtime, allocator := context.allocator) -> [dynamic]Inspector_Cause {
	causes := make([dynamic]Inspector_Cause, 0, INSPECTOR_CAUSE_LIMIT, allocator)
	if inspected == nil { return causes }
	for offset := 0; offset < inspected.trace.count; offset += 1 {
		index := (inspected.trace.next-1-offset+len(inspected.trace.events)) % len(inspected.trace.events)
		event := inspected.trace.events[index]
		found := -1
		for cause, cause_index in causes { if cause.id == event.cause_id { found = cause_index; break } }
		if found < 0 {
			if len(causes) >= INSPECTOR_CAUSE_LIMIT { continue }
			append(&causes, Inspector_Cause{id=event.cause_id, kind=event.cause_kind, latest_sequence=event.sequence, node=event.node, last_reason=event.reason})
			found = len(causes)-1
		}
		cause := &causes[found]
		cause.visits[event.kind] += 1
		if cause.action == Action_ID(0) && event.action_id != Action_ID(0) { cause.action = event.action_id }
		#partial switch event.kind {
		case .Cause: if len(cause.origin) == 0 { cause.origin = event.reason }
		case .Action: if len(cause.action_reason) == 0 { cause.action_reason = event.reason }
		case .Invalidation: if len(cause.invalidation) == 0 { cause.invalidation = event.reason }
		case .Mutation: if len(cause.mutation) == 0 { cause.mutation = event.reason }
		}
	}
	return causes
}

inspector_overlay_lines :: proc(ui: ^UI, lines: []string, key: string, height: f32) {
	content_width := f32(0)
	for line in lines {
		// Match prepare_text_run_node's logical text size and typography. A
		// byte-width estimate can leave the final glyph beyond max_scroll_x.
		run, measured := text_run_build(&ui.runtime.text_engine, line, 16,
			allocator=ui.runtime.scratch_allocator, scratch_allocator=ui.runtime.scratch_allocator,
			font_role=.Monospace, font_weight=FONT_WEIGHT_REGULAR, overflow=.Clip)
		width := f32(len(line))*16
		if measured { width = run.width; text_run_destroy(&run) }
		content_width = maxf(content_width, width+16)
	}
	list := virtual_list_begin(ui, len(lines), INSPECTOR_LINE_HEIGHT, key=key_string(key),
		style=layout_style(height=height, clip=true), content_width=content_width, axes=.Both,
		label=key, focusable=true)
	if list.scroll.id == 0 { return }
	for index := list.first; index < list.last; index += 1 {
		text(ui, lines[index], key=key_u64(u64(index)), style=layout_style(.Row, height=INSPECTOR_LINE_HEIGHT),
			font=.Monospace, text_style=Text_Style{font_weight=FONT_WEIGHT_REGULAR, overflow=.Clip})
	}
	virtual_list_end(ui, list)
}

inspector_overlay_node_lines :: proc(inspected: ^Runtime, id: Node_ID, allocator := context.temp_allocator) -> [dynamic]string {
	lines := make([dynamic]string, 0, allocator=allocator)
	node, ok := inspected.nodes[id]
	if !ok { append(&lines, "Select a retained node in the tree, or use Pick."); return lines }
	append(&lines, fmt.tprintf("Node_ID: %d   parent: %d", node.id, node.parent))
	append(&lines, fmt.tprintf("kind: %v   component: %s", node.kind, node.site.component))
	append(&lines, fmt.tprintf("label: %q", node.label))
	append(&lines, fmt.tprintf("source: %s:%d:%d", node.site.file, node.site.line, node.site.column))
	append(&lines, fmt.tprintf("key: %q   explicit: %t", node.key, node.explicit_key))
	if node.identity_key_kind == 3 {
		append(&lines, fmt.tprintf("scope: pair(%d, %d)", node.identity_key_pair.first, node.identity_key_pair.second))
	} else if node.identity_key_numeric {
		append(&lines, fmt.tprintf("scope: u64(%d)", node.identity_key_u64))
	} else { append(&lines, fmt.tprintf("scope: %q", node.identity_key)) }
	geometry := layout_node_finalized_geometry(inspected, node.id)
	append(&lines, fmt.tprintf("target bounds: x=%.1f y=%.1f w=%.1f h=%.1f", node.bounds.x, node.bounds.y, node.bounds.w, node.bounds.h))
	append(&lines, fmt.tprintf("final bounds: x=%.1f y=%.1f w=%.1f h=%.1f", geometry.bounds.x, geometry.bounds.y, geometry.bounds.w, geometry.bounds.h))
	append(&lines, fmt.tprintf("final clip: x=%.1f y=%.1f w=%.1f h=%.1f", geometry.clip.x, geometry.clip.y, geometry.clip.w, geometry.clip.h))
	append(&lines, fmt.tprintf("active=%t present=%t focusable=%t disabled=%t", node.active, node.present, node.focusable, node.disabled))
	append(&lines, fmt.tprintf("hovered=%t pressed=%t selected=%t semantic_active=%t", node.hovered, node.pressed, node.selected, node.semantic_active))
	append(&lines, fmt.tprintf("keyboard_focus=%t captured=%t", inspected.focused == node.id, inspected.captured_node == node.id))
	append(&lines, fmt.tprintf("semantic: namespace=%d value=%d", node.semantic_id.namespace, node.semantic_id.value))
	append(&lines, fmt.tprintf("caret: (%d,%v) selection: (%d,%v) -> (%d,%v)", node.caret.byte, node.caret.affinity, node.selection_anchor.byte, node.selection_anchor.affinity, node.selection_focus.byte, node.selection_focus.affinity))
	append(&lines, fmt.tprintf("dirty: description=%t layout=%t paint=%t composite=%t", dirty_has(node.dirty,.Description), dirty_has(node.dirty,.Layout), dirty_has(node.dirty,.Paint), dirty_has(node.dirty,.Composite)))
	append(&lines, fmt.tprintf("reason: %s", node.last_reason))
	if part, attached := inspected.visual_parts[id]; attached && part.defined {
		owner_component := "<missing>"
		if owner, owner_found := inspected.nodes[part.owner]; owner_found { owner_component = owner.site.component }
		append(&lines, fmt.tprintf("visual part: %s identity=%d owner=%d component=%s visibility=%s reveal-on-direct-hover=%t visible=%t",
			visual_part_role_name(part.identity), visual_part_identity_hash(part.identity), part.owner,
			owner_component, visual_part_visibility_name(part.visibility), part.reveal_on_direct_hover, visual_part_is_visible(inspected, id)))
	}
	for child_id in inspected.order {
		part, attached := inspected.visual_parts[child_id]
		if !attached || !part.defined || part.owner != id { continue }
		hovered := visual_part_owner_hovered(inspected, id)
		state := ""
		switch part.visibility {
		case .Always: state = "unconditional"
		case .Owner_Hovered: state = fmt.tprintf("owner hovered=%t", hovered)
		case .Owner_Selected_Or_Hovered: state = fmt.tprintf("owner selected=%t hovered=%t", node.selected, hovered)
		case .Owner_Not_Hovered: state = fmt.tprintf("owner hovered=%t", hovered)
		}
		append(&lines, fmt.tprintf("visual child: node=%d identity=%s hash=%d owner=%d component=%s visibility=%s (%s) reveal-on-direct-hover=%t visible=%t",
			child_id, visual_part_role_name(part.identity), visual_part_identity_hash(part.identity), id, node.site.component,
			visual_part_visibility_name(part.visibility), state, part.reveal_on_direct_hover, visual_part_is_visible(inspected, child_id)))
	}
	if node.region { append(&lines, fmt.tprintf("region: revision=%d cached=%t", node.region_revision, node.region_cached)) }
	if node.kind == .Custom_Surface { append(&lines, fmt.tprintf("surface: payload-revision=%d kind=%v pixels=%dx%d dpi=%.2f", u64(node.surface_payload_revision), node.surface_kind, node.surface_pixel_width, node.surface_pixel_height, node.surface_dpi_scale)) }
	return lines
}

inspector_overlay_tree :: proc(ui: ^UI, state: ^Inspector_Overlay, inspected: ^Runtime, height: f32) {
	rows := inspector_overlay_tree_rows(state, inspected, ui.runtime.scratch_allocator)
	list_height := maxf(INSPECTOR_ROW_HEIGHT, height*0.43)
	content_width := f32(780)
	for row in rows { content_width = maxf(content_width, 780+f32(min(row.depth, 64))*14) }
	list := virtual_list_begin(ui, len(rows), INSPECTOR_ROW_HEIGHT, key=key_string("inspector-tree"),
		style=layout_style(height=list_height, clip=true), content_width=content_width, axes=.Both,
		label="inspector-tree", focusable=true)
	if list.scroll.id != 0 {
		for index := list.first; index < list.last; index += 1 {
			row := rows[index]
			node := inspected.nodes[row.id]
			container_begin(ui, .Virtual_Row, label="inspector-tree-row", key=key_u64(u64(row.id)), style=layout_style(.Row, height=INSPECTOR_ROW_HEIGHT))
			container_begin(ui, .Container, label="tree-indent", style=layout_style(width=f32(min(row.depth,64))*14)); container_end(ui)
			if button(ui, "+" if state.collapsed[row.id] else "-", key=key_string("collapse"),
				style=layout_style(.Row, width=26, height=INSPECTOR_ROW_HEIGHT), state=Button_State{disabled=!row.has_children}, variant=.Quiet) {
				_ = inspector_overlay_toggle_collapsed(state, inspected, row.id)
				invalidate_root(ui.runtime, "inspector hierarchy toggled")
			}
			if button(ui, fmt.tprintf("%v  %s  #%d", node.kind, node.label if len(node.label)>0 else node.site.component, row.id), key=key_string("node"),
				style=layout_style(.Row, height=INSPECTOR_ROW_HEIGHT, grow=1), state=Button_State{selected=state.selected==row.id}, variant=.Quiet,
				content_style=button_content_style(.Start,.Center,padding_x=6)) {
				state.selected = row.id
				invalidate_root(ui.runtime, "inspector selection changed")
			}
			container_end(ui)
		}
		virtual_list_end(ui, list)
	}
	text(ui, "Selected node", style=layout_style(.Row,height=24), text_style=Text_Style{font_weight=FONT_WEIGHT_SEMIBOLD})
	lines := inspector_overlay_node_lines(inspected, state.selected, ui.runtime.scratch_allocator)
	inspector_overlay_lines(ui, lines[:], "inspector-node-details", maxf(height-list_height-24,0))
}

inspector_overlay_focus :: proc(ui: ^UI, inspected: ^Runtime, height: f32) {
	lines := make([dynamic]string,0,allocator=ui.runtime.scratch_allocator)
	append(&lines, fmt.tprintf("Keyboard focus: %d", inspected.focused))
	append(&lines, fmt.tprintf("Selection: %d   capture: %d", inspected.selected, inspected.captured_node))
	append(&lines, fmt.tprintf("Hover: %d", inspected.last_hovered))
	semantic := inspected.semantic_focus
	if semantic_id_is_valid(semantic.id) {
		append(&lines, fmt.tprintf("Semantic ID: namespace=%d value=%d",semantic.id.namespace,semantic.id.value))
		append(&lines, fmt.tprintf("Semantic owner: %d",semantic.owner))
		append(&lines, fmt.tprintf("Realized presentation: %d",semantic.realized_node))
		if semantic.realized_node == 0 { append(&lines,"Logical focus exists; its presentation is unrealized.") }
	} else { append(&lines,"Semantic focus: none") }
	append(&lines, "", "Keyboard focus owner:")
	owner := inspector_overlay_node_lines(inspected, inspected.focused, ui.runtime.scratch_allocator)
	append(&lines, ..owner[:])
	inspector_overlay_lines(ui, lines[:], "inspector-focus", height)
}

inspector_overlay_work :: proc(ui: ^UI, inspected: ^Runtime, host: ^Inspector_Host_Summary, height: f32) {
	lines := make([dynamic]string,0,allocator=ui.runtime.scratch_allocator)
	stats := inspected.stats
	append(&lines,fmt.tprintf("Presentation revision: %d",inspected.presentation_revision))
	append(&lines,fmt.tprintf("Submitted revision: %d",inspected.submitted_revision))
	append(&lines,fmt.tprintf("Pending: description=%t layout=%t presentation=%t",inspected.invalidated,inspected.layout_pending,inspected.presentation_pending))
	append(&lines,fmt.tprintf("Surface frame pending: %t",inspected.surface_frame_pending))
	append(&lines,fmt.tprintf("Retained nodes: %d   frame: %d",len(inspected.nodes),stats.frame))
	append(&lines,fmt.tprintf("Descriptions: built=%d emitted=%d reused=%d",stats.frames_built,stats.descriptions_emitted,stats.descriptions_reused))
	append(&lines,fmt.tprintf("Regions skipped=%d subtrees reused=%d",stats.regions_skipped,stats.retained_subtrees_reused))
	append(&lines,fmt.tprintf("Visited: reconcile=%d layout=%d style resolutions=%d cache hits=%d",stats.reconcile_nodes_visited,stats.layout_nodes_visited,stats.style_resolutions,stats.style_cache_hits))
	append(&lines,fmt.tprintf("Visited: paint=%d composite=%d",stats.paint_nodes_visited,stats.composition_nodes_visited))
	append(&lines,fmt.tprintf("Updates: layout=%d paint=%d composite=%d",stats.layout_updates,stats.paint_updates,stats.composite_updates))
	append(&lines,fmt.tprintf("Nodes: created=%d retired=%d adjacency=%d",stats.nodes_created,stats.nodes_retired,stats.adjacency_rebuilds))
	append(&lines,fmt.tprintf("Pointer events=%d hover transitions=%d",stats.pointer_events,stats.hover_target_transitions))
	append(&lines,fmt.tprintf("GPU submits=%d surface updates=%d",stats.gpu_submits,stats.surface_updates))
	append(&lines,fmt.tprintf("Invalidation: %s",inspected.last_invalidation_reason))
	if allocation := inspected.allocation_stats; allocation != nil {
		append(&lines,fmt.tprintf("Persistent bytes: live=%d peak=%d",allocation.persistent_requested_bytes_live,allocation.persistent_requested_bytes_peak))
		append(&lines,fmt.tprintf("Persistent calls: alloc=%d free=%d",allocation.persistent_alloc_calls,allocation.persistent_free_calls))
		append(&lines,fmt.tprintf("Scratch bytes: epoch=%d peak=%d resets=%d",allocation.scratch_requested_bytes_epoch,allocation.scratch_requested_bytes_peak,allocation.scratch_resets))
	}
	if host != nil {
		append(&lines,"",fmt.tprintf("Host wakes=%d app builds=%d",host.host_wakes,host.application_builds))
		append(&lines,fmt.tprintf("App submits=%d inspector submits=%d",host.application_submits,host.overlay_submits))
		append(&lines,fmt.tprintf("Total event=%.3f ms build=%.3f ms",host.event_ms,host.build_ms))
		append(&lines,fmt.tprintf("Total encode=%.3f ms submit=%.3f ms",host.encode_ms,host.submit_ms))
	}
	if inspected.hard_error { append(&lines,"",fmt.tprintf("HARD ERROR: %s",inspected.diagnostic)) }
	inspector_overlay_lines(ui,lines[:],"inspector-work",height)
}

inspector_overlay_causes :: proc(ui: ^UI, inspected: ^Runtime, height: f32) {
	lines := make([dynamic]string,0,allocator=ui.runtime.scratch_allocator)
	causes := inspector_overlay_recent_causes(inspected,ui.runtime.scratch_allocator)
	if len(causes) == 0 { append(&lines,"No recorded causes.") }
	for cause in causes {
		if cause.id == 0 { append(&lines,fmt.tprintf("Unassigned work  (latest trace #%d)",cause.latest_sequence)) }
		else { append(&lines,fmt.tprintf("Cause #%d  %v  (latest trace #%d)",cause.id,cause.kind,cause.latest_sequence)) }
		if len(cause.origin)>0 { append(&lines,fmt.tprintf("  Origin: %s",cause.origin)) }
		if cause.action != Action_ID(0) {
			descriptor,state,found := action_lookup(inspected,cause.action)
			if found { append(&lines,fmt.tprintf("  Action: %s | %s  (id=%d enabled=%t checked=%t)",descriptor.name,descriptor.label,u32(cause.action),state.enabled,state.checked)) }
			else { append(&lines,fmt.tprintf("  Action: %d  %s",u32(cause.action),cause.action_reason)) }
		} else if len(cause.action_reason)>0 { append(&lines,fmt.tprintf("  Action: %s",cause.action_reason)) }
		if len(cause.mutation)>0 { append(&lines,fmt.tprintf("  Mutation: %s",cause.mutation)) }
		if len(cause.invalidation)>0 { append(&lines,fmt.tprintf("  Invalidated: %s",cause.invalidation)) }
		append(&lines,fmt.tprintf("  Stages: reconcile=%d layout=%d paint=%d composite=%d",cause.visits[.Reconcile],cause.visits[.Layout],cause.visits[.Paint],cause.visits[.Composite]))
		append(&lines,fmt.tprintf("  Submissions: %d  pointer=%d focus=%d retire=%d",cause.visits[.Submit],cause.visits[.Pointer],cause.visits[.Focus],cause.visits[.Retire]))
		append(&lines,fmt.tprintf("  Last: node=%d %s",cause.node,cause.last_reason),"")
	}
	inspector_overlay_lines(ui,lines[:],"inspector-causes",height)
}

// Four ordinary solid containers outline the selected bounds. They are
// retained by the inspector runtime and use its normal solid compositor.
inspector_overlay_highlight :: proc(ui: ^UI, state: ^Inspector_Overlay, inspected: ^Runtime) {
	node, ok := inspected.nodes[state.selected]
	if !ok || !node.active { return }
	viewport := ui.runtime.viewport
	clip := Rect{viewport.x,viewport.y,maxf(state.panel_bounds.x-viewport.x,0),viewport.h}
	geometry := layout_node_finalized_geometry(inspected, node.id)
	bounds := rect_intersection(rect_intersection(geometry.bounds,geometry.clip),clip)
	if bounds.w <= 0 || bounds.h <= 0 { return }
	border := minf(2,minf(bounds.w,bounds.h)/2)
	color := Color{0.20,0.80,1,1}
	container_begin(ui,.Container,label="inspector-highlight-layer",key=key_string("inspector-highlight"),style=layout_style(.Row,clip=true))
	container_begin(ui,.Container,label="highlight-x",style=layout_style(width=maxf(bounds.x-viewport.x,0))); container_end(ui)
	container_begin(ui,.Container,label="highlight-column",style=layout_style(width=bounds.w))
	container_begin(ui,.Container,label="highlight-y",style=layout_style(height=maxf(bounds.y-viewport.y,0))); container_end(ui)
	container_begin(ui,.Container,label="highlight-top",style=layout_style(height=border),color=color); container_end(ui)
	container_begin(ui,.Container,label="highlight-middle",style=layout_style(.Row,height=maxf(bounds.h-2*border,0)))
	container_begin(ui,.Container,label="highlight-left",style=layout_style(width=border),color=color); container_end(ui)
	container_begin(ui,.Container,label="highlight-space",style=layout_style(grow=1)); container_end(ui)
	container_begin(ui,.Container,label="highlight-right",style=layout_style(width=border),color=color); container_end(ui)
	container_end(ui)
	container_begin(ui,.Container,label="highlight-bottom",style=layout_style(height=border),color=color); container_end(ui)
	container_end(ui)
	container_end(ui)
}

// The inspected runtime is read-only throughout this procedure, including
// when it has a hard error. All UI input, allocation, focus and retained work
// belong to ui.runtime, which must be the host's separate inspector runtime.
inspector_overlay_build :: proc(ui: ^UI, state: ^Inspector_Overlay, inspected: ^Runtime, host: ^Inspector_Host_Summary = nil) {
	if ui == nil || ui.runtime == nil || state == nil || inspected == nil || !state.visible ||
		ui.runtime == inspected || !ui.runtime.frame_open { return }
	context.temp_allocator = ui.runtime.scratch_allocator
	inspector_overlay_prune(state,inspected,ui.runtime.scratch_allocator)
	viewport := ui.runtime.viewport
	width := minf(480,viewport.w)
	state.panel_bounds = Rect{viewport.x+viewport.w-width,viewport.y,width,viewport.h}
	container_begin(ui,.Container,label="inspector-overlay",key=key_string("inspector-overlay"),style=layout_style(.Row,clip=true))
	container_begin(ui,.Container,label="inspector-spacer",style=layout_style(grow=1)); container_end(ui)
	container_begin(ui,.Container,label="inspector-panel",style=layout_style(width=width,height=viewport.h,padding=8,gap=4,clip=true),color=Color{0.045,0.06,0.085,0.98})
	container_begin(ui,.Container,label="inspector-toolbar",style=layout_style(.Row,height=30,gap=6))
	text(ui,"Alicorn inspector",style=layout_style(.Row,grow=1,height=30),text_style=Text_Style{font_weight=FONT_WEIGHT_SEMIBOLD,overflow=.Ellipsis})
	if button(ui,"Pick",key=key_string("pick"),style=layout_style(.Row,width=56,height=30),state=Button_State{selected=state.picking}) { state.picking = !state.picking; invalidate_root(ui.runtime,"inspector picking toggled") }
	if state.focus_initial_pending && len(ui.runtime.pending)>0 {
		state.initial_focus = ui.runtime.pending[len(ui.runtime.pending)-1].description.id
		state.focus_initial_pending = false
	}
	if button(ui,"Close",key=key_string("close"),style=layout_style(.Row,width=60,height=30)) { inspector_overlay_close(state) }
	container_end(ui)
	container_begin(ui,.Container,label="inspector-tabs",style=layout_style(.Row,height=30,gap=4))
	for tab in Inspector_Tab {
		if button(ui,fmt.tprintf("%v",tab),key=key_u64(u64(tab)),style=layout_style(.Row,height=30,grow=1),state=Button_State{selected=state.tab==tab},variant=.Tab) {
			state.tab = tab
			invalidate_root(ui.runtime,"inspector tab changed")
		}
	}
	container_end(ui)
	text(ui,"Click an app node to pick." if state.picking else fmt.tprintf("%d retained nodes | selected #%d",len(inspected.nodes),state.selected),style=layout_style(.Row,height=22),text_style=Text_Style{overflow=.Ellipsis})
	if inspected.hard_error { text(ui,"App hard error - retained state is available.",style=layout_style(.Row,height=22),text_style=Text_Style{overflow=.Ellipsis}) }
	height := maxf(viewport.h-110-(state.tab == .Tree ? 8 : 0)-(inspected.hard_error ? 26 : 0),0)
	switch state.tab {
	case .Tree: inspector_overlay_tree(ui,state,inspected,height)
	case .Focus: inspector_overlay_focus(ui,inspected,height)
	case .Work: inspector_overlay_work(ui,inspected,host,height)
	case .Causes: inspector_overlay_causes(ui,inspected,height)
	}
	container_end(ui)
	container_end(ui)
	inspector_overlay_highlight(ui,state,inspected)
}
