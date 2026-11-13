package alicorn

import "core:testing"

Interaction_Scope_Test_Nodes :: struct {
	owner:       Node_ID,
	modal_owner: Node_ID,
	button:      Node_ID,
	event:       Interaction_Event,
	found:       bool,
}

interaction_scope_test_describe :: proc(
	rt: ^Runtime,
	consume_owner: Node_ID = 0,
	register_normal := true,
	register_modal := true,
) -> Interaction_Scope_Test_Nodes {
	result := Interaction_Scope_Test_Nodes{}
	ui, should_build := begin_frame(rt)
	if !should_build { return result }
	container_begin_simple(&ui, .Root, label="interaction-scope-test-root", key="interaction-scope-test-root", style=layout_style(.Column))
	result.owner = container_begin(&ui, .Container, label="tree-scope", key="tree-scope", style=layout_style(.Column))
	result.button, _ = button_ex(&ui, "Tree item", key="tree-scope-button", style=layout_style(width=120, height=30))
	container_end(&ui)
	result.modal_owner = container_begin(&ui, .Container, label="modal-scope", key="modal-scope", style=layout_style(.Column))
	container_end(&ui)
	container_end(&ui)
	if register_normal {
		options := Interaction_Scope_Options{
			keys={.Down},
			composition_yield_keys={.Down},
			pointers={.Secondary_Down},
		}
		_ = interaction_scope_register(rt, result.owner, nil, options)
	}
	if register_modal {
		_ = interaction_scope_register(rt, result.modal_owner, nil,
			Interaction_Scope_Options{keys={.Escape}, modal=true})
	}
	if consume_owner != 0 {
		result.event, result.found = interaction_event_next(rt, consume_owner)
	}
	end_frame(&ui)
	return result
}

@(test)
test_interaction_scope_routes_to_focused_owner_and_modal_owner :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt)
	nodes := interaction_scope_test_describe(&rt)
	testing.expect(t, nodes.owner != 0 && nodes.modal_owner != 0 && nodes.button != 0,
		"the test should retain a tree scope, modal scope, and focusable descendant")
	if nodes.button == 0 { return }
	_ = focus(&rt, nodes.button)

	testing.expect(t, application_dispatch_key(&rt, nil, nil, .Down),
		"a key registered by the nearest focused ancestor should be consumed")
	nodes = interaction_scope_test_describe(&rt, nodes.owner)
	testing.expect(t, nodes.found && nodes.event.kind == .Key && nodes.event.key == .Down,
		"the focused tree should receive the key during its next description")

	testing.expect(t, application_dispatch_key(&rt, nil, nil, .Escape),
		"a matching modal scope should receive input ahead of the focused tree")
	nodes = interaction_scope_test_describe(&rt, nodes.modal_owner)
	testing.expect(t, nodes.found && nodes.event.kind == .Key && nodes.event.key == .Escape,
		"the modal owner should receive the event in its next description")

	testing.expect(t, !application_dispatch_key(&rt, nil, nil, .Down, composition_active=true),
		"a key yielded by the focused component during native text composition should remain unhandled")
}

@(test)
test_interaction_scope_routes_pointer_and_drops_events_for_retired_scope :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt)
	nodes := interaction_scope_test_describe(&rt, register_modal=false)
	_ = focus(&rt, nodes.button)
	event := Pointer_Event{kind=.Down, x=12, y=12, button=POINTER_BUTTON_SECONDARY}
	testing.expect(t, application_dispatch_pointer(&rt, nil, nil, event, nodes.button),
		"a pointer event should route to the registered focused ancestor")
	nodes = interaction_scope_test_describe(&rt, nodes.owner)
	testing.expect(t, nodes.found && nodes.event.kind == .Pointer && nodes.event.target == nodes.button,
		"the component should receive the original hit target on its next description")

	testing.expect(t, application_dispatch_key(&rt, nil, nil, .Down), "the live scope should accept a key before removal")
	_ = interaction_scope_test_describe(&rt, register_normal=false, register_modal=false)
	testing.expect(t, len(rt.interaction_events) == 0,
		"events owned by a scope omitted from the next description should be discarded")
}

Interaction_Scope_Test_After_Frame_State :: struct {
	count:        int,
	schedule_next: bool,
}

interaction_scope_test_after_frame_callback :: proc(data: rawptr, rt: ^Runtime) {
	state := cast(^Interaction_Scope_Test_After_Frame_State)data
	if state == nil { return }
	state.count += 1
	if state.schedule_next {
		state.schedule_next = false
		_ = interaction_after_frame_register(rt, data, interaction_scope_test_after_frame_callback)
	}
}

@(test)
test_interaction_after_frame_callback_runs_once_after_reconciliation :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 100, 80})
	defer destroy_runtime(&rt)
	state := Interaction_Scope_Test_After_Frame_State{schedule_next=true}
	testing.expect(t, interaction_after_frame_register(&rt, rawptr(&state), interaction_scope_test_after_frame_callback),
		"a valid one-shot callback should be accepted")
	_ = interaction_scope_test_describe(&rt, register_normal=false, register_modal=false)
	testing.expect(t, state.count == 1 && len(rt.interaction_after_frame) == 1,
		"a callback scheduled while dispatching should be reserved for the following description")
	invalidate_root(&rt, "run the callback scheduled during dispatch")
	_ = interaction_scope_test_describe(&rt, register_normal=false, register_modal=false)
	testing.expect(t, state.count == 2 && len(rt.interaction_after_frame) == 0,
		"the deferred callback should run once and then leave the runtime idle")
}
