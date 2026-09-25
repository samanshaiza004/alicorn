package alicorn_sdl_gpu

import "core:fmt"
import "core:os"
import alicorn "../../runtime"

Menu_Fixture_State :: struct {
	command_count: u64,
	last_command:  Application_Command_ID,
}

menu_fixture_build :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	logical_width, logical_height: int,
	dpi_scale: f32,
) -> alicorn.Node_ID {
	app := cast(^Menu_Fixture_State)state
	ui, should_build := alicorn.begin_frame(rt)
	if !should_build { return 0 }
	root := alicorn.container_begin(
		&ui,
		.Root,
		label="native-menu-fixture",
		style=alicorn.layout_style(.Column, grow=1, padding=24, gap=12, clip=true),
		color=alicorn.Color{0.04, 0.05, 0.08, 1},
	)
	alicorn.text(&ui, "Native application menu fixture")
	alicorn.text(&ui, "Choose a native menu command. On Windows, launch with --integrated-title-bar to test menus in the caption.")
	alicorn.text(&ui, fmt.tprintf("Commands received: %d", app.command_count))
	alicorn.text(&ui, fmt.tprintf("Last command ID: %d", u32(app.last_command)))
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return root
}

menu_fixture_command :: proc(state: rawptr, rt: ^alicorn.Runtime, command: Application_Command_ID) {
	app := cast(^Menu_Fixture_State)state
	app.command_count += 1
	app.last_command = command
	fmt.println("menu_command", u32(command), "count", app.command_count)
}

// RunMenuFixture is a small end-to-end host fixture for menu rendering,
// native keyboard navigation, and semantic command delivery.
RunMenuFixture :: proc() {
	recent_items := [?]Application_Menu_Item{
		{kind=.Command, command=Application_Command_ID(4), label="Trace A", enabled=true},
		{kind=.Command, command=Application_Command_ID(5), label="Trace B", enabled=true},
	}
	file_items := [?]Application_Menu_Item{
		{kind=.Command, command=Application_Command_ID(1), label="Open Trace…", enabled=true, shortcut=Application_Menu_Shortcut{'O', {.Primary}}},
		{kind=.Submenu, label="Open Recent", enabled=true, items=recent_items[:]},
		{kind=.Separator},
		{kind=.Command, command=Application_Command_ID(2), label="Save", enabled=false, shortcut=Application_Menu_Shortcut{'S', {.Primary}}},
		{kind=.Command, command=Application_Command_ID(3), label="Follow Tail", enabled=true, checked=true},
	}
	edit_items := [?]Application_Menu_Item{
		{kind=.Command, command=Application_Command_ID(6), label="Copy", enabled=true, shortcut=Application_Menu_Shortcut{'C', {.Primary}}},
		{kind=.Command, command=Application_Command_ID(7), label="Paste", enabled=false, shortcut=Application_Menu_Shortcut{'V', {.Primary}}},
	}
	view_items := [?]Application_Menu_Item{
		{kind=.Command, command=Application_Command_ID(8), label="Show Timeline", enabled=true, checked=true},
	}
	help_items := [?]Application_Menu_Item{
		{kind=.Command, command=Application_Command_ID(9), label="About Alicorn", enabled=true},
	}
	menus := [?]Application_Menu{
		{label="File", items=file_items[:]},
		{label="Edit", items=edit_items[:]},
		{label="View", items=view_items[:]},
		{label="Help", items=help_items[:]},
	}
	state := Menu_Fixture_State{}
	decoration_mode := Window_Decoration_Mode.System
	smoke := false
	for argument in os.args {
		if argument == "--integrated-title-bar" {
			decoration_mode = .Integrated_Title_Bar
		}
		if argument == "--menu-fixture-smoke" { smoke = true }
	}
	Run(Application{
		state=rawptr(&state),
		title="Alicorn Menu Fixture",
		width=900,
		height=560,
		menus=menus[:],
		window_decorations=decoration_mode,
		build=menu_fixture_build,
		on_menu_command=menu_fixture_command,
	}, smoke=smoke)
}
