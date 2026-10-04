package alicorn
import "core:fmt"

trace_current_cause :: proc(rt: ^Runtime) -> Cause_Context {
	if rt.active_cause.id != 0 { return rt.active_cause }
	return rt.frame_cause
}

record_trace_with_cause :: proc(rt: ^Runtime, kind: Trace_Kind, node: Node_ID, reason: string, cause: Cause_Context) {
	rt.trace.sequence += 1
	entry := Trace_Event{sequence=rt.trace.sequence, kind=kind, cause_id=cause.id, cause_kind=cause.kind, action_id=cause.action_id, node=node, reason=owned_with_allocator(reason, rt.persistent_allocator), reason_owned=true}
	old := &rt.trace.events[rt.trace.next]
	if old.reason_owned && len(old.reason) > 0 { delete(old.reason, rt.persistent_allocator) }
	rt.trace.events[rt.trace.next] = entry
	rt.trace.next = (rt.trace.next + 1) % len(rt.trace.events)
	if rt.trace.count < len(rt.trace.events) {
		rt.trace.count += 1
	}
}

record_trace :: proc(rt: ^Runtime, kind: Trace_Kind, node: Node_ID, reason: string) {
	record_trace_with_cause(rt, kind, node, reason, trace_current_cause(rt))
}

// High-frequency retained products can use an immutable literal reason
// without creating one heap string per update. The ring still bounds event
// storage; only the ownership policy differs for this process-lifetime text.
record_trace_literal :: proc(rt: ^Runtime, kind: Trace_Kind, node: Node_ID, reason: string) {
	record_trace_literal_with_cause(rt, kind, node, reason, trace_current_cause(rt))
}

record_trace_literal_with_cause :: proc(rt: ^Runtime, kind: Trace_Kind, node: Node_ID, reason: string, cause: Cause_Context) {
	rt.trace.sequence += 1
	entry := Trace_Event{sequence=rt.trace.sequence, kind=kind, cause_id=cause.id, cause_kind=cause.kind, action_id=cause.action_id, node=node, reason=reason, reason_owned=false}
	old := &rt.trace.events[rt.trace.next]
	if old.reason_owned && len(old.reason) > 0 { delete(old.reason, rt.persistent_allocator) }
	rt.trace.events[rt.trace.next] = entry
	rt.trace.next = (rt.trace.next + 1) % len(rt.trace.events)
	if rt.trace.count < len(rt.trace.events) { rt.trace.count += 1 }
}

cause_begin :: proc(rt: ^Runtime, kind: Cause_Kind, reason: string, action_id: Action_ID = Action_ID(0)) -> Cause_Scope {
	previous := rt.active_cause
	cause_ctx := trace_current_cause(rt)
	if cause_ctx.id == 0 {
		rt.cause_sequence += 1
		if rt.cause_sequence == 0 { rt.cause_sequence = 1 }
		cause_ctx = Cause_Context{id=rt.cause_sequence, kind=kind, action_id=action_id}
		rt.active_cause = cause_ctx
		record_trace_with_cause(rt, .Cause, 0, reason, cause_ctx)
	} else {
		if cause_ctx.action_id == Action_ID(0) && action_id != Action_ID(0) { cause_ctx.action_id = action_id }
		rt.active_cause = cause_ctx
	}
	return Cause_Scope{previous=previous, cause=cause_ctx}
}

cause_resume :: proc(rt: ^Runtime, cause_ctx: Cause_Context) -> Cause_Scope {
	previous := rt.active_cause
	if cause_ctx.id != 0 { rt.active_cause = cause_ctx }
	return Cause_Scope{previous=previous, cause=cause_ctx}
}

cause_end :: proc(rt: ^Runtime, scope: Cause_Scope) {
	rt.active_cause = scope.previous
	if scope.clear_pointer_gesture { rt.pointer_gesture_cause = Cause_Context{} }
}

// pointer_cause_begin keeps a press/drag/release sequence under one cause ID.
// Uncaptured motion remains presentation-only and does not manufacture causes.
pointer_cause_begin :: proc(rt: ^Runtime, kind: Pointer_Kind) -> Cause_Scope {
	if kind == .Down {
		scope := cause_begin(rt, .Pointer, "pointer gesture")
		rt.pointer_gesture_cause = scope.cause
		return scope
	}
	if rt.pointer_gesture_cause.id != 0 {
		scope := cause_resume(rt, rt.pointer_gesture_cause)
		scope.clear_pointer_gesture = kind == .Up || kind == .Cancel
		return scope
	}
	if kind == .Move { return Cause_Scope{previous=rt.active_cause, cause=rt.active_cause} }
	return cause_begin(rt, .Pointer, "pointer gesture")
}

note_pending_work_cause :: proc(rt: ^Runtime, cause: Cause_Context) {
	if rt.frame_open { return }
	if !rt.pending_work_seen {
		rt.pending_work_seen = true
		rt.pending_work_cause = cause
		return
	}
	if rt.pending_work_mixed { return }
	if rt.pending_work_cause.id != cause.id {
		rt.pending_work_mixed = true
		rt.pending_work_cause = Cause_Context{}
	} else if cause.id != 0 && rt.pending_work_cause.action_id == Action_ID(0) {
		rt.pending_work_cause.action_id = cause.action_id
	}
}

// action_update publishes an application's current action metadata and state
// to this runtime. Action names are stable for an ID; labels and state may be
// refreshed explicitly. Strings are copied so callers may use temporary data.
action_update :: proc(rt: ^Runtime, descriptor: Action_Descriptor, state: Action_State) -> bool {
	if descriptor.id == Action_ID(0) || len(descriptor.name) == 0 || len(descriptor.label) == 0 { return false }
	for index := 0; index < len(rt.actions); index += 1 {
		entry := &rt.actions[index]
		if entry.descriptor.id != descriptor.id { continue }
		if entry.descriptor.name != descriptor.name { return false }
		if entry.descriptor.label != descriptor.label {
			label_copy := owned_with_allocator(descriptor.label, rt.persistent_allocator)
			if len(label_copy) == 0 { return false }
			if entry.label_owned && len(entry.descriptor.label) > 0 { delete(entry.descriptor.label, rt.persistent_allocator) }
			entry.descriptor.label = label_copy
			entry.label_owned = true
		}
		entry.state = state
		return true
	}
	name_copy := owned_with_allocator(descriptor.name, rt.persistent_allocator)
	label_copy := owned_with_allocator(descriptor.label, rt.persistent_allocator)
	if len(name_copy) == 0 || len(label_copy) == 0 {
		if len(name_copy) > 0 { delete(name_copy, rt.persistent_allocator) }
		if len(label_copy) > 0 { delete(label_copy, rt.persistent_allocator) }
		return false
	}
	append(&rt.actions, Action_Entry{
		descriptor=Action_Descriptor{id=descriptor.id, name=name_copy, label=label_copy},
		state=state,
		name_owned=true,
		label_owned=true,
	})
	return true
}

action_lookup :: proc(rt: ^Runtime, id: Action_ID) -> (descriptor: Action_Descriptor, state: Action_State, found: bool) {
	if id == Action_ID(0) { return }
	for entry in rt.actions {
		if entry.descriptor.id == id { return entry.descriptor, entry.state, true }
	}
	return
}

semantic_id_is_valid :: proc(id: Semantic_ID) -> bool {
	return id.namespace != 0
}

// semantic_focus_state reports the independent logical focus identity, its
// durable keyboard-focus owner, and the currently realized presentation node.
semantic_focus_state :: proc(rt: ^Runtime) -> Semantic_Focus_State {
	return rt.semantic_focus
}

semantic_focus_owner_needs_outline :: proc(rt: ^Runtime, owner: Node_ID) -> bool {
	if rt.focused != owner { return false }
	if rt.semantic_focus.owner != owner || rt.semantic_focus.realized_node == 0 { return true }

	realized, ok := rt.nodes[rt.semantic_focus.realized_node]
	return !ok || !realized.active || !semantic_node_within_owner(rt, realized.id, owner)
}

// semantic_focus_set changes the logical entity being operated on without
// changing keyboard focus or application selection. Bind that identity to a
// described node with semantic_bind; reconciliation then updates realized_node
// as the presentation appears and disappears.
semantic_focus_set :: proc(rt: ^Runtime, id: Semantic_ID, owner: Node_ID) -> bool {
	if !semantic_id_is_valid(id) { return semantic_focus_clear(rt) }
	if rt.semantic_focus.id == id && rt.semantic_focus.owner == owner { return false }
	previous_owner := rt.semantic_focus.owner
	rt.semantic_focus.id = id
	rt.semantic_focus.owner = owner
	refresh_semantic_focus_realization(rt)
	if previous_owner != owner {
		invalidate_interaction_paint(rt, previous_owner, "semantic focus owner changed")
		invalidate_interaction_paint(rt, owner, "semantic focus owner changed")
	}
	record_trace(rt, .Focus, rt.semantic_focus.realized_node,
		fmt.tprintf("semantic focus set namespace=%d value=%d owner=%d", id.namespace, id.value, owner))
	return true
}

semantic_focus_clear :: proc(rt: ^Runtime) -> bool {
	if rt.semantic_focus.id.namespace == 0 && rt.semantic_focus.owner == 0 && rt.semantic_focus.realized_node == 0 {
		return false
	}
	previous := rt.semantic_focus.id
	previous_owner := rt.semantic_focus.owner
	rt.semantic_focus = Semantic_Focus_State{}
	refresh_semantic_focus_realization(rt)
	invalidate_interaction_paint(rt, previous_owner, "semantic focus cleared")
	record_trace(rt, .Focus, 0,
		fmt.tprintf("semantic focus cleared namespace=%d value=%d", previous.namespace, previous.value))
	return true
}

semantic_node_within_owner :: proc(rt: ^Runtime, id, owner: Node_ID) -> bool {
	if owner == 0 { return false }
	current := id
	for current != 0 {
		if current == owner { return true }
		node, ok := rt.nodes[current]
		if !ok { return false }
		current = node.parent
	}
	return false
}

refresh_semantic_focus_realization :: proc(rt: ^Runtime) {
	previous := rt.semantic_focus.realized_node
	next := Node_ID(0)
	fallback := Node_ID(0)
	if semantic_id_is_valid(rt.semantic_focus.id) {
		for id in rt.order {
			node, ok := rt.nodes[id]
			if !ok || !node.active || node.semantic_id != rt.semantic_focus.id { continue }
			if fallback == 0 { fallback = id }
			if semantic_node_within_owner(rt, id, rt.semantic_focus.owner) {
				next = id
				break
			}
		}
		if next == 0 { next = fallback }
	}
	for id, node in rt.nodes {
		should_be_active := id == next
		if node.semantic_active != should_be_active {
			node.semantic_active = should_be_active
			invalidate_interaction_paint(rt, id, "semantic focus presentation changed")
		}
	}
	rt.semantic_focus.realized_node = next
	if previous != next {
		invalidate_interaction_paint(rt, rt.semantic_focus.owner, "semantic focus realization changed")
		if next == 0 && semantic_id_is_valid(rt.semantic_focus.id) {
			record_trace(rt, .Focus, 0, "semantic focus has no realized presentation")
		} else if next != 0 {
			record_trace(rt, .Focus, next, "semantic focus presentation realized")
		}
	}
}

trace_action :: proc(rt: ^Runtime, action_id: Action_ID, label: string) {
	cause_ctx := trace_current_cause(rt)
	scope: Cause_Scope
	if cause_ctx.id == 0 {
		scope = cause_begin(rt, .Application, "application action")
		cause_ctx = scope.cause
	}
	cause_ctx.action_id = action_id
	if rt.active_cause.id == cause_ctx.id { rt.active_cause.action_id = action_id }
	if rt.frame_cause.id == cause_ctx.id { rt.frame_cause.action_id = action_id }
	if rt.pending_work_cause.id == cause_ctx.id { rt.pending_work_cause.action_id = action_id }
	if rt.pointer_gesture_cause.id == cause_ctx.id { rt.pointer_gesture_cause.action_id = action_id }
	record_trace_with_cause(rt, .Action, 0, label, cause_ctx)
	if scope.cause.id != 0 { cause_end(rt, scope) }
}

trace_mutation :: proc(rt: ^Runtime, reason: string) {
	cause_ctx := trace_current_cause(rt)
	scope: Cause_Scope
	if cause_ctx.id == 0 {
		scope = cause_begin(rt, .Application, reason)
		cause_ctx = scope.cause
	}
	record_trace_with_cause(rt, .Mutation, 0, reason, cause_ctx)
	if scope.cause.id != 0 { cause_end(rt, scope) }
}

invalidate_root :: proc(rt: ^Runtime, reason := "explicit root invalidation") {
	rt.invalidated = true
	cause_ctx := trace_current_cause(rt)
	scope: Cause_Scope
	if cause_ctx.id == 0 {
		scope = cause_begin(rt, .Application, reason)
		cause_ctx = scope.cause
	}
	if len(rt.last_invalidation_reason) > 0 { delete(rt.last_invalidation_reason, rt.persistent_allocator) }
	rt.last_invalidation_reason = owned(reason, rt.persistent_allocator)
	record_trace_with_cause(rt, .Invalidation, 0, reason, cause_ctx)
	note_pending_work_cause(rt, cause_ctx)
	if scope.cause.id != 0 { cause_end(rt, scope) }
}

// request_presentation wakes the retained presentation path without making
// the application re-emit its description. It is intended for hover, focus,
// caret, selection, and other interaction-only visual changes.
request_presentation :: proc(rt: ^Runtime, reason := "retained presentation changed") {
	rt.presentation_pending = true
	record_trace(rt, .Invalidation, 0, reason)
	note_pending_work_cause(rt, trace_current_cause(rt))
}

advance_presentation_revision :: proc(rt: ^Runtime) {
	rt.presentation_revision += 1
	if rt.presentation_revision == 0 {
		// Keep zero available as the initial generation and force a pending
		// acknowledgement after the practically unreachable u64 wraparound.
		rt.presentation_revision = 1
		rt.submitted_revision = 0
	}
}

presentation_needs_frame :: proc(rt: ^Runtime) -> bool {
	return rt.presentation_pending
}

frame_needs_submission :: proc(rt: ^Runtime) -> bool {
	return rt.presentation_revision != rt.submitted_revision || rt.surface_frame_pending
}

note_submission_cause :: proc(rt: ^Runtime, cause: Cause_Context) {
	if !rt.submission_cause_seen {
		rt.submission_cause_seen = true
		rt.submission_cause = cause
		return
	}
	if rt.submission_cause_mixed { return }
	if rt.submission_cause.id != cause.id {
		rt.submission_cause = Cause_Context{}
		rt.submission_cause_mixed = true
	} else if cause.id != 0 && rt.submission_cause.action_id == Action_ID(0) {
		rt.submission_cause.action_id = cause.action_id
	}
}

// frame_submission_succeeded is the native-host acknowledgement boundary.
// It must be called only after the command buffer has been submitted
// successfully. In particular, a nil swapchain texture is not an
// acknowledgement: the revision remains pending so the host can retry.
frame_submission_succeeded :: proc(rt: ^Runtime) {
	rt.submitted_revision = rt.presentation_revision
	cause := rt.submission_cause if !rt.submission_cause_mixed else Cause_Context{}
	record_trace_with_cause(rt, .Submit, 0, "GPU frame submission acknowledged", cause)
	rt.submission_cause = Cause_Context{}
	rt.submission_cause_seen = false
	rt.submission_cause_mixed = false
}

presentation_frame_consumed :: proc(rt: ^Runtime) {
	// Keep the existing API as a compatibility spelling for hosts that used it
	// as their post-submit acknowledgement. New hosts should call the more
	// explicit frame_submission_succeeded procedure.
	rt.presentation_pending = false
	frame_submission_succeeded(rt)
}

invalidate_region :: proc(rt: ^Runtime, key: string, revision: u64, reason := "explicit region invalidation") {
	// Region keys are the public invalidation handle. Resolve only live regions
	// with that label; silently accepting a typo would make the requested cache
	// invalidation indistinguishable from a successful one.
	match_count := 0
	for _, node in rt.nodes {
		if node.active && node.region && node.label == key { match_count += 1 }
	}
	if match_count == 0 {
		append_diagnostic(rt, fmt.tprintf("invalidate_region could not find a live region named %q at revision %d.\nSuggestion: call it with the same key used by region_begin, after that region has been described at least once.", key, revision))
		return
	}
	// A local region key can intentionally occur under several keyed component
	// scopes. In that case this API invalidates every matching instance, but the
	// requested revision must remain monotonic for every one of them.
	for _, node in rt.nodes {
		if !node.active || !node.region || node.label != key { continue }
		if revision < node.region_revision {
			append_diagnostic(rt, fmt.tprintf("invalidate_region revision regressed for %q.\n  retained region: %s:%d:%d component=%q scope=%q revision=%d\n  requested revision: %d\nSuggestion: keep region revisions monotonic; increment the application's revision when its logical output changes.", key, node.site.file, node.site.line, node.site.column, node.site.component, node.identity_key, node.region_revision, revision))
			return
		}
	}
	for _, node in rt.nodes {
		if !node.active || !node.region || node.label != key { continue }
		// Mark the region's high-water revision before the next build and clear
		// its cache marker. region_begin will therefore reject a stale revision
		// and rebuild when the application supplies the requested revision.
		node.region_revision = revision
		node.region_cached = false
	}
	rt.invalidated = true
	cause_ctx := trace_current_cause(rt)
	scope: Cause_Scope
	if cause_ctx.id == 0 {
		scope = cause_begin(rt, .Application, reason)
		cause_ctx = scope.cause
	}
	if len(rt.last_invalidation_reason) > 0 { delete(rt.last_invalidation_reason, rt.persistent_allocator) }
	rt.last_invalidation_reason = owned(fmt.tprintf("region %s revision %d: %s", key, revision, reason), rt.persistent_allocator)
	record_trace_with_cause(rt, .Invalidation, 0, rt.last_invalidation_reason, cause_ctx)
	note_pending_work_cause(rt, cause_ctx)
	if scope.cause.id != 0 { cause_end(rt, scope) }
}

begin_frame :: proc(rt: ^Runtime) -> (ui: UI, should_build: bool) {
	ui = UI{runtime = rt}
	if !rt.invalidated {
		rt.stats.idle_frames += 1
		return ui, false
	}
	if rt.pending_work_seen {
		rt.frame_cause = rt.pending_work_cause if !rt.pending_work_mixed else Cause_Context{}
	} else {
		rt.frame_cause = Cause_Context{}
	}
	rt.pending_work_cause = Cause_Context{}
	rt.pending_work_seen = false
	rt.pending_work_mixed = false
	// Scratch reset is performed after the previous frame has closed; keep the
	// first frame path minimal while the arena is still empty.
	runtime_scratch_reset(rt)
	// Consume the invalidation that requested this description now. Any
	// invalidate_root call made while the application is describing the frame
	// then represents new work and must remain pending after reconciliation.
	rt.invalidated = false
	rt.frame_open = true
	rt.context_menu.described = false
	clear(&rt.pending)
	clear(&rt.seen)
	clear(&rt.identity_scopes)
	clear(&rt.stack)
	clear(&rt.identity_stack)
	clear(&rt.identity_labels)
	clear(&rt.identity_key_u64)
	clear(&rt.identity_key_numeric)
	clear(&rt.identity_key_kind)
	clear(&rt.identity_key_pair)
	rt.style_environment = DEFAULT_STYLE_ENVIRONMENT
	clear(&rt.style_scope_stack)
	// Interaction invalidation may have queued a retained node before the
	// next frame begins. update_paint clears the queue after consuming it;
	// clearing it here would discard focus/caret/selection repaint requests.
	rt.stats.frames_built += 1
	return ui, true
}

// begin_presentation_frame opens a retained-only frame. It never clears or
// reconstructs pending application descriptions, so end_presentation_frame
// cannot accidentally retire the tree. Hosts may use this when an interaction
// update needs paint/composition work but no application callback is needed.
begin_presentation_frame :: proc(rt: ^Runtime) -> (ui: UI, ready: bool) {
	ui = UI{runtime = rt}
	if rt.invalidated || !rt.presentation_pending || rt.frame_open {
		return ui, false
	}
	if rt.pending_work_seen {
		rt.frame_cause = rt.pending_work_cause if !rt.pending_work_mixed else Cause_Context{}
	} else {
		rt.frame_cause = Cause_Context{}
	}
	rt.pending_work_cause = Cause_Context{}
	rt.pending_work_seen = false
	rt.pending_work_mixed = false
	runtime_scratch_reset(rt)
	rt.frame_open = true
	return ui, true
}

