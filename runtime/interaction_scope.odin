package alicorn

// interaction_scope_register installs one retained input scope for the next
// completed description. The owner must be a node described in the current
// frame and remain stable while the component is mounted. State is borrowed by
// callbacks until the scope is replaced or the Runtime is destroyed.
interaction_scope_register :: proc(
	rt: ^Runtime,
	owner: Node_ID,
	state: rawptr,
	options: Interaction_Scope_Options,
) -> bool {
	if rt == nil || !rt.frame_open || owner == 0 { return false }
	_, declared := rt.seen[owner]
	if !declared { return false }
	scope := Retained_Interaction_Scope{owner=owner, state=state, options=options}
	for index in 0..<len(rt.pending_interaction_scopes) {
		if rt.pending_interaction_scopes[index].owner == owner {
			rt.pending_interaction_scopes[index] = scope
			return true
		}
	}
	append(&rt.pending_interaction_scopes, scope)
	return true
}

// interaction_event_next consumes one queued key or pointer event for owner.
// Input handlers run during native event dispatch, while this call runs during
// description so the component can use the application's current data slice.
interaction_event_next :: proc(rt: ^Runtime, owner: Node_ID) -> (event: Interaction_Event, found: bool) {
	if rt == nil || owner == 0 || !rt.frame_open { return }
	for index in 0..<len(rt.interaction_events) {
		if rt.interaction_events[index].owner != owner { continue }
		event = rt.interaction_events[index].event
		for next in index+1..<len(rt.interaction_events) {
			rt.interaction_events[next-1] = rt.interaction_events[next]
		}
		_ = pop(&rt.interaction_events)
		found = true
		if len(rt.interaction_events) > 0 {
			invalidate_root(rt, "pending scoped interaction input")
		}
		return
	}
	return
}

// interaction_after_frame_register schedules a one-shot callback after the
// next completed description has reconciled and laid out. It may be called
// from an application input callback before that description begins. The
// caller keeps state alive until the callback runs.
interaction_after_frame_register :: proc(
	rt: ^Runtime,
	state: rawptr,
	callback: Interaction_After_Frame_Proc,
) -> bool {
	if rt == nil || callback == nil { return false }
	append(&rt.interaction_after_frame, Retained_After_Frame_Callback{state, callback})
	return true
}

// interaction_scope_has_input is a cheap host hint. Routing still checks the
// scope's key and pointer filters against the actual event.
interaction_scope_has_input :: proc(rt: ^Runtime) -> bool {
	return rt != nil && len(rt.interaction_scopes) > 0
}

@(private)
interaction_scope_for_key :: proc(
	rt: ^Runtime,
	key: Application_Key,
	composition_active: bool,
) -> (owner: Node_ID, found: bool) {
	if rt == nil { return }
	for i := len(rt.interaction_scopes)-1; i >= 0; i -= 1 {
		scope := rt.interaction_scopes[i]
		if !scope.options.modal || key not_in scope.options.keys { continue }
		if composition_active && key in scope.options.composition_yield_keys { continue }
		return scope.owner, true
	}
	ancestor := rt.focused
	for ancestor != 0 {
		for scope in rt.interaction_scopes {
			if scope.owner != ancestor || key not_in scope.options.keys { continue }
			if composition_active && key in scope.options.composition_yield_keys { continue }
			return scope.owner, true
		}
		node, exists := rt.nodes[ancestor]
		if !exists || node == nil { break }
		ancestor = node.parent
	}
	return
}

// interaction_scope_dispatch_key queues a key for the focused component (or
// the topmost matching modal scope). Native text composition can retain keys
// explicitly listed in composition_yield_keys.
interaction_scope_dispatch_key :: proc(rt: ^Runtime, key: Application_Key, composition_active := false) -> bool {
	owner, found := interaction_scope_for_key(rt, key, composition_active)
	if !found { return false }
	append(&rt.interaction_events, Interaction_Event_Record{
		owner=owner,
		event=Interaction_Event{kind=.Key, key=key},
	})
	invalidate_root(rt, "scoped component keyboard input")
	return true
}

@(private)
interaction_pointer_kind :: proc(event: Pointer_Event) -> (kind: Interaction_Pointer_Kind, found: bool) {
	if event.kind != .Down { return }
	switch event.button {
	case POINTER_BUTTON_PRIMARY: return .Primary_Down, true
	case POINTER_BUTTON_SECONDARY: return .Secondary_Down, true
	case: return
	}
}

@(private)
interaction_scope_for_pointer :: proc(
	rt: ^Runtime,
	event: Pointer_Event,
	target: Node_ID,
) -> (owner: Node_ID, found: bool) {
	if rt == nil { return }
	kind, supported := interaction_pointer_kind(event)
	if !supported { return }
	for i := len(rt.interaction_scopes)-1; i >= 0; i -= 1 {
		scope := rt.interaction_scopes[i]
		if scope.options.modal && kind in scope.options.pointers { return scope.owner, true }
	}
	ancestor := target
	for ancestor != 0 {
		for scope in rt.interaction_scopes {
			if scope.owner == ancestor && kind in scope.options.pointers { return scope.owner, true }
		}
		node, exists := rt.nodes[ancestor]
		if !exists || node == nil { break }
		ancestor = node.parent
	}
	return
}

interaction_scope_dispatch_pointer :: proc(
	rt: ^Runtime,
	event: Pointer_Event,
	target: Node_ID,
) -> bool {
	owner, found := interaction_scope_for_pointer(rt, event, target)
	if !found { return false }
	append(&rt.interaction_events, Interaction_Event_Record{
		owner=owner,
		event=Interaction_Event{kind=.Pointer, pointer=event, target=target},
	})
	return true
}

interaction_scope_dispatch_text_change :: proc(rt: ^Runtime, change: Text_Change) -> bool {
	if rt == nil || change.node == 0 { return false }
	ancestor := change.node
	for ancestor != 0 {
		for scope in rt.interaction_scopes {
			if scope.owner == ancestor && scope.options.on_text_change != nil &&
				scope.options.on_text_change(scope.state, rt, change) {
				invalidate_root(rt, "scoped component text change")
				return true
			}
		}
		node, exists := rt.nodes[ancestor]
		if !exists || node == nil { break }
		ancestor = node.parent
	}
	return false
}

@(private)
interaction_scope_owner_active :: proc(rt: ^Runtime, owner: Node_ID) -> bool {
	for scope in rt.interaction_scopes { if scope.owner == owner { return true } }
	return false
}

@(private)
interaction_scopes_publish :: proc(rt: ^Runtime) {
	old := rt.interaction_scopes
	rt.interaction_scopes = rt.pending_interaction_scopes
	rt.pending_interaction_scopes = old
	clear(&rt.pending_interaction_scopes)
	write := 0
	for record in rt.interaction_events {
		if !interaction_scope_owner_active(rt, record.owner) { continue }
		rt.interaction_events[write] = record
		write += 1
	}
	for len(rt.interaction_events) > write { _ = pop(&rt.interaction_events) }
}

@(private)
interaction_after_frame_dispatch :: proc(rt: ^Runtime) {
	if rt == nil { return }
	callbacks := rt.interaction_after_frame
	rt.interaction_after_frame = rt.dispatching_after_frame
	rt.dispatching_after_frame = callbacks
	clear(&rt.interaction_after_frame)
	for callback in rt.dispatching_after_frame {
		if callback.callback != nil { callback.callback(callback.state, rt) }
	}
	clear(&rt.dispatching_after_frame)
}
