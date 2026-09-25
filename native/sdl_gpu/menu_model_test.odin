package alicorn_sdl_gpu

import "core:testing"
import alicorn "../../runtime"

Menu_Dispatch_Test_State :: struct {
	calls:        int,
	last_command: Application_Command_ID,
}

menu_dispatch_test_callback :: proc(state: rawptr, rt: ^alicorn.Runtime, command: Application_Command_ID) {
	test_state := cast(^Menu_Dispatch_Test_State)state
	test_state.calls += 1
	test_state.last_command = command
}

@(test)
test_menu_dispatch_preserves_semantic_command_id :: proc(t: ^testing.T) {
	state := Menu_Dispatch_Test_State{}
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 200}, alicorn.Runtime_Config{trace_capacity=8})
	defer alicorn.destroy_runtime(&rt)
	application := Application{
		state=rawptr(&state),
		on_menu_command=menu_dispatch_test_callback,
	}
	menu := Native_Menu_Runtime{application=&application, runtime=&rt}
	command := Application_Command_ID(0x1234)
	testing.expect(t, alicorn.action_update(&rt,
		alicorn.Action_Descriptor{id=command, name="test.open", label="Open"},
		alicorn.Action_State{enabled=true}), "native menu action should share runtime action identity")
	native_menu_dispatch_command(&menu, command)
	testing.expect(t, state.calls == 1, "one native selection must invoke one application command")
	testing.expect(t, state.last_command == command, "native menu IDs must map back to the semantic command ID")
	events := alicorn.trace_snapshot(&rt)
	defer delete(events)
	found_action_cause := false
	for event in events {
		if event.kind == .Cause {
			found_action_cause = event.action_id == command && event.cause_kind == .Native_Command
		}
	}
	testing.expect(t, found_action_cause, "native transport should preserve the typed action identity in causal runtime events")
}

@(test)
test_disabled_runtime_action_rejects_native_menu_invocation :: proc(t: ^testing.T) {
	state := Menu_Dispatch_Test_State{}
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 200}, alicorn.Runtime_Config{trace_capacity=8})
	defer alicorn.destroy_runtime(&rt)
	application := Application{state=rawptr(&state), on_menu_command=menu_dispatch_test_callback}
	menu := Native_Menu_Runtime{application=&application, runtime=&rt}
	command := Application_Command_ID(0x1235)
	testing.expect(t, alicorn.action_update(&rt,
		alicorn.Action_Descriptor{id=command, name="test.disabled", label="Disabled"},
		alicorn.Action_State{enabled=false}), "test action should register as disabled")
	native_menu_dispatch_command(&menu, command)
	testing.expect(t, state.calls == 0, "native dispatch must not invoke a disabled action")
	testing.expect(t, rt.trace.sequence == 0, "rejected disabled invocation must not manufacture a causal transaction")
}

@(test)
test_application_can_preempt_text_field_navigation_and_dismissal :: proc(t: ^testing.T) {
	interceptable_keys := [?]Application_Key{Application_Key.Up, Application_Key.Down, Application_Key.Page_Up, Application_Key.Page_Down, Application_Key.Open_Repository, Application_Key.Open_Command_Palette, Application_Key.Escape, Application_Key.Return}
	for key in interceptable_keys {
		testing.expect(t, application_key_can_preempt_text_field(key), "transient UI key should be offered before text-field handling")
	}
	normal_keys := [?]Application_Key{Application_Key.Home, Application_Key.Fit_Selection}
	for key in normal_keys {
		testing.expect(t, !application_key_can_preempt_text_field(key), "unrelated application key should retain normal routing")
	}
	testing.expect(t, !application_key_can_preempt_text_field(.Escape, true), "Escape must cancel active text composition before transient UI dismissal")
}

@(test)
test_menu_description_supports_nested_items_and_states :: proc(t: ^testing.T) {
	children := [?]Application_Menu_Item{
		{kind=.Command, command=Application_Command_ID(7), label="Checked", state=alicorn.Action_State{enabled=true, checked=true}},
		{kind=.Command, command=Application_Command_ID(8), label="Disabled", state=alicorn.Action_State{enabled=false}},
	}
	items := [?]Application_Menu_Item{
		{kind=.Submenu, label="Recent", state=alicorn.Action_State{enabled=true}, items=children[:]},
		{kind=.Separator},
	}
	menu := Application_Menu{label="File", items=items[:]}
	testing.expect(t, menu.items[0].kind == .Submenu && len(menu.items[0].items) == 2, "menu descriptions must retain nested items")
	testing.expect(t, menu.items[0].items[0].state.checked, "menu descriptions must retain checked state")
	testing.expect(t, !menu.items[0].items[1].state.enabled, "menu descriptions must retain disabled state")
	testing.expect(t, menu.items[1].kind == .Separator, "menu descriptions must retain separators")
	children[0].state.checked = false
	testing.expect(t, !menu.items[0].items[0].state.checked, "applications must be able to update borrowed menu state in place")
}
