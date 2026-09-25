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
	application := Application{
		state=rawptr(&state),
		on_menu_command=menu_dispatch_test_callback,
	}
	menu := Native_Menu_Runtime{application=&application}
	command := Application_Command_ID(0x1234)
	native_menu_dispatch_command(&menu, command)
	testing.expect(t, state.calls == 1, "one native selection must invoke one application command")
	testing.expect(t, state.last_command == command, "native menu IDs must map back to the semantic command ID")
}

@(test)
test_menu_description_supports_nested_items_and_states :: proc(t: ^testing.T) {
	children := [?]Application_Menu_Item{
		{kind=.Command, command=Application_Command_ID(7), label="Checked", enabled=true, checked=true},
		{kind=.Command, command=Application_Command_ID(8), label="Disabled", enabled=false},
	}
	items := [?]Application_Menu_Item{
		{kind=.Submenu, label="Recent", enabled=true, items=children[:]},
		{kind=.Separator},
	}
	menu := Application_Menu{label="File", items=items[:]}
	testing.expect(t, menu.items[0].kind == .Submenu && len(menu.items[0].items) == 2, "menu descriptions must retain nested items")
	testing.expect(t, menu.items[0].items[0].checked, "menu descriptions must retain checked state")
	testing.expect(t, !menu.items[0].items[1].enabled, "menu descriptions must retain disabled state")
	testing.expect(t, menu.items[1].kind == .Separator, "menu descriptions must retain separators")
	children[0].checked = false
	testing.expect(t, !menu.items[0].items[0].checked, "applications must be able to update borrowed menu state in place")
}
