package alicorn_sdl_gpu

import "core:fmt"
import "core:os"
import "core:strings"
import alicorn "../../runtime"
import "vendor:sdl3"

Menu_Fixture_State :: struct {
	command_count:                 u64,
	last_command:                  Application_Command_ID,
	titlebar_fixture:              bool,
	titlebar_control_bounds:       [3]alicorn.Rect,
	titlebar_header_height:        f32,
	titlebar_control_start_x:      f32,
	titlebar_window_width:         f32,
	titlebar_logical_height:       f32,
	titlebar_window_origin_x:     f32,
	titlebar_window_origin_y:     f32,
	titlebar_tab_start_x:          f32,
	titlebar_tab_width:            f32,
	titlebar_drag_region:          alicorn.Rect,
	titlebar_tab_order:            [2]u64,
	titlebar_selected_tab:         u64,
	titlebar_closed_tabs:          [2]bool,
	titlebar_selection_count:     u64,
	titlebar_close_count:         u64,
	titlebar_reorder_count:       u64,
	titlebar_cancel_count:        u64,
	titlebar_text_change_count:   u64,
	titlebar_text:                string,
	titlebar_fullscreen_enters:   u64,
	titlebar_fullscreen_exits:    u64,
	titlebar_fullscreen_active:   bool,
	titlebar_style_resets:        u64,
	titlebar_pointer_event_count:  u64,
	titlebar_pointer_x:           f32,
	titlebar_pointer_y:           f32,
	titlebar_pointer_down_x:      f32,
	titlebar_pointer_down_y:      f32,
	titlebar_pointer_up_x:        f32,
	titlebar_pointer_up_y:        f32,
	titlebar_raw_pointer_count:   u64,
	titlebar_raw_down_x:          f32,
	titlebar_raw_down_y:          f32,
	titlebar_raw_up_x:            f32,
	titlebar_raw_up_y:            f32,
	titlebar_raw_motion_x:        f32,
	titlebar_raw_motion_y:        f32,
	titlebar_callback_motion_x:    f32,
	titlebar_callback_motion_y:    f32,
	titlebar_pointer_target:      alicorn.Node_ID,
	titlebar_pointer_kind:        alicorn.Pointer_Kind,
	titlebar_hit_test_count:      u64,
	titlebar_hit_x:               int,
	titlebar_hit_y:               int,
	titlebar_hit_result:          sdl3.HitTestResult,
	titlebar_consumed_count:      u64,
}

TITLEBAR_FIXTURE_NAMESPACE :: u64(0x616c69636f726e)
TITLEBAR_FIXTURE_TAB_DRAG_TYPE :: alicorn.Drag_Type(0x746162)

menu_fixture_build :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	logical_width, logical_height: int,
	dpi_scale: f32,
) -> alicorn.Node_ID {
	app := cast(^Menu_Fixture_State)state
	if app.titlebar_fixture {
		return menu_fixture_titlebar_build(app, rt, logical_width, logical_height)
	}
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

menu_fixture_titlebar_build :: proc(
	app: ^Menu_Fixture_State,
	rt: ^alicorn.Runtime,
	logical_width, logical_height: int,
) -> alicorn.Node_ID {
	ui, should_build := alicorn.begin_frame(rt)
	if !should_build { return 0 }
	app.titlebar_window_width = f32(logical_width)
	app.titlebar_logical_height = f32(logical_height)
	app.titlebar_tab_start_x = app.titlebar_control_start_x
	app.titlebar_tab_width = max(f32(logical_width)-app.titlebar_tab_start_x-160, 0)
	app.titlebar_drag_region = alicorn.Rect{
		app.titlebar_tab_start_x+app.titlebar_tab_width,
		0,
		max(f32(logical_width)-app.titlebar_tab_start_x-app.titlebar_tab_width, 0),
		app.titlebar_header_height,
	}
	root := alicorn.container_begin(
		&ui,
		.Root,
		label="macos-titlebar-fixture",
		style=alicorn.layout_style(.Column, grow=1, padding=0, gap=0, clip=true),
		color=alicorn.Color{0.04, 0.05, 0.08, 1},
	)
	bar := alicorn.container_begin(
		&ui,
		.Container,
		label="macos-titlebar-fixture-header",
		style=alicorn.layout_style(.Row, height=app.titlebar_header_height, gap=0, clip=true),
		color=alicorn.Color{0.13, 0.15, 0.19, 1},
	)
	_ = alicorn.container_begin(
		&ui,
		.Container,
		label="native-traffic-light-reservation",
		style=alicorn.layout_style(.Row, width=app.titlebar_control_start_x, height=app.titlebar_header_height),
	)
	alicorn.container_end(&ui)
	items: [2]alicorn.Tab_Bar_Item
	item_ids: [2]u64
	item_count := 0
	for tab_id in app.titlebar_tab_order {
		if tab_id == 0 || tab_id > 2 || app.titlebar_closed_tabs[tab_id-1] { continue }
		key := alicorn.key_string("macos-titlebar-tab-one") if tab_id == 1 else alicorn.key_string("macos-titlebar-tab-two")
		label := "Alicorn Overview" if tab_id == 1 else "Native Input Probe"
		items[item_count] = alicorn.Tab_Bar_Item{
			key=key,
			label=label,
			selected=app.titlebar_selected_tab == tab_id,
			closable=true,
			semantic_id=alicorn.Semantic_ID{namespace=TITLEBAR_FIXTURE_NAMESPACE, value=tab_id},
		}
		item_ids[item_count] = tab_id
		item_count += 1
	}
	tab_options := alicorn.DEFAULT_TAB_BAR_OPTIONS
	tab_options.height = app.titlebar_header_height
	tab_options.close_policy = .Always
	tab_options.drag_type = TITLEBAR_FIXTURE_TAB_DRAG_TYPE
	tab_result := alicorn.tab_bar(
		&ui,
		alicorn.key_string("macos-titlebar-tabs"),
		items[:item_count],
		tab_options,
		alicorn.layout_style(.Row, width=app.titlebar_tab_width, height=app.titlebar_header_height),
	)
	if tab_result.item_index >= 0 && tab_result.item_index < item_count {
		tab_id := item_ids[tab_result.item_index]
		switch tab_result.action {
		case .Select:
			app.titlebar_selected_tab = tab_id
			app.titlebar_selection_count += 1
			fmt.println("macos_titlebar_tab_selected", "tab", tab_id, "count", app.titlebar_selection_count)
			alicorn.invalidate_root(rt, "titlebar fixture tab selected")
		case .Close:
			app.titlebar_closed_tabs[tab_id-1] = true
			app.titlebar_close_count += 1
			if app.titlebar_selected_tab == tab_id {
				for candidate in app.titlebar_tab_order {
					if candidate != 0 && candidate <= 2 && !app.titlebar_closed_tabs[candidate-1] {
						app.titlebar_selected_tab = candidate
						break
					}
				}
			}
			fmt.println("macos_titlebar_tab_closed", "tab", tab_id, "count", app.titlebar_close_count)
			alicorn.invalidate_root(rt, "titlebar fixture tab closed")
		case .None:
		}
	}
	_ = alicorn.container_begin(
		&ui,
		.Container,
		label="blank-native-window-drag-region",
		style=alicorn.layout_style(.Row, grow=1, height=app.titlebar_header_height),
	)
	alicorn.container_end(&ui)
	alicorn.container_end(&ui)
	alicorn.container_begin(
		&ui,
		.Container,
		label="macos-titlebar-fixture-body",
		style=alicorn.layout_style(.Column, grow=1, padding=20, gap=10, clip=true),
	)
	alicorn.text(&ui, "Alicorn-rendered tabs share this row with native macOS traffic lights.")
	alicorn.text(&ui, "Click, close, and drag the tabs. Drag an empty part of the header to move the window.")
	alicorn.text(&ui, "Text input below verifies ordinary SDL client events.")
	alicorn.text_field(&ui, app.titlebar_text, key=alicorn.key_string("macos-titlebar-text-field"), style=alicorn.layout_style(.Row, width=420, height=36))
	alicorn.text(
		&ui,
		fmt.tprintf(
			"selected=%d · selections=%d · closes=%d · reorders=%d · canceled=%d · text changes=%d",
			app.titlebar_selected_tab,
			app.titlebar_selection_count,
			app.titlebar_close_count,
			app.titlebar_reorder_count,
			app.titlebar_cancel_count,
			app.titlebar_text_change_count,
		),
	)
	alicorn.text(&ui, fmt.tprintf("Native control bounds (window points): %v", app.titlebar_control_bounds))
	alicorn.text(&ui, fmt.tprintf("Header %0.1fpt · blank window-drag tail %0.1fpt", app.titlebar_header_height, f32(160)))
	alicorn.text(
		&ui,
		fmt.tprintf(
			"Window %0.0f×%0.0fpt @ %0.0f,%0.0f · fullscreen=%v (%d/%d) · titlebar style resets %d",
			app.titlebar_window_width,
			app.titlebar_logical_height,
			app.titlebar_window_origin_x,
			app.titlebar_window_origin_y,
			app.titlebar_fullscreen_active,
			app.titlebar_fullscreen_enters,
			app.titlebar_fullscreen_exits,
			app.titlebar_style_resets,
		),
	)
	alicorn.text(
		&ui,
		fmt.tprintf(
			"input hits=%d (%d,%d → %d), SDL raw=%d (move %0.0f,%0.0f down %0.0f,%0.0f up %0.0f,%0.0f), callbacks=%d (move %0.0f,%0.0f down %0.0f,%0.0f up %0.0f,%0.0f; last %0.0f,%0.0f → node %d, kind %d), Cocoa-consumed=%d",
			app.titlebar_hit_test_count,
			app.titlebar_hit_x,
			app.titlebar_hit_y,
			u32(app.titlebar_hit_result),
			app.titlebar_raw_pointer_count,
			app.titlebar_raw_motion_x,
			app.titlebar_raw_motion_y,
			app.titlebar_raw_down_x,
			app.titlebar_raw_down_y,
			app.titlebar_raw_up_x,
			app.titlebar_raw_up_y,
			app.titlebar_pointer_event_count,
			app.titlebar_callback_motion_x,
			app.titlebar_callback_motion_y,
			app.titlebar_pointer_down_x,
			app.titlebar_pointer_down_y,
			app.titlebar_pointer_up_x,
			app.titlebar_pointer_up_y,
			app.titlebar_pointer_x,
			app.titlebar_pointer_y,
			u64(app.titlebar_pointer_target),
			u32(app.titlebar_pointer_kind),
			app.titlebar_consumed_count,
		),
	)
	alicorn.container_end(&ui)
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

menu_fixture_text_change :: proc(state: rawptr, rt: ^alicorn.Runtime, change: alicorn.Text_Change) {
	app := cast(^Menu_Fixture_State)state
	if !app.titlebar_fixture { return }
	app.titlebar_text_change_count += 1
	if change.changed {
		copy, err := strings.clone(change.text)
		if err == nil {
			if len(app.titlebar_text) > 0 { delete(app.titlebar_text) }
			app.titlebar_text = copy
			alicorn.invalidate_root(rt, "titlebar fixture text changed")
		}
	}
	fmt.println("macos_titlebar_text_change", change.text, "count", app.titlebar_text_change_count)
}

menu_fixture_pointer :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	event: alicorn.Pointer_Event,
	target: alicorn.Node_ID,
) {
	app := cast(^Menu_Fixture_State)state
	if !app.titlebar_fixture { return }
	app.titlebar_pointer_event_count += 1
	app.titlebar_pointer_x = event.x
	app.titlebar_pointer_y = event.y
	app.titlebar_pointer_target = target
	app.titlebar_pointer_kind = event.kind
	if event.kind == .Down {
		app.titlebar_pointer_down_x = event.x
		app.titlebar_pointer_down_y = event.y
	} else if event.kind == .Up {
		app.titlebar_pointer_up_x = event.x
		app.titlebar_pointer_up_y = event.y
	} else if event.kind == .Move {
		app.titlebar_callback_motion_x = event.x
		app.titlebar_callback_motion_y = event.y
	}
	fmt.println(
		"macos_titlebar_sdl_pointer",
		"kind", u32(event.kind),
		"position", event.x, event.y,
		"target", target,
	)
}

menu_fixture_drag_event :: proc(state: rawptr, rt: ^alicorn.Runtime, event: alicorn.Drag_Event) {
	app := cast(^Menu_Fixture_State)state
	if !app.titlebar_fixture || event.drag_type != TITLEBAR_FIXTURE_TAB_DRAG_TYPE { return }
	fmt.println(
		"macos_titlebar_tab_drag",
		"kind", event.kind,
		"source", event.source.value,
		"target", event.target.value,
		"position", event.position,
	)
	switch event.kind {
	case .Dropped:
		if event.target.value == 0 || event.source.value == event.target.value { return }
		if event.position == .Before {
			app.titlebar_tab_order = [2]u64{event.source.value, event.target.value}
		} else if event.position == .After {
			app.titlebar_tab_order = [2]u64{event.target.value, event.source.value}
		}
		app.titlebar_reorder_count += 1
		alicorn.invalidate_root(rt, "titlebar fixture tabs reordered")
	case .Cancelled:
		app.titlebar_cancel_count += 1
		alicorn.invalidate_root(rt, "titlebar fixture tab drag canceled")
	case .Started, .Target_Changed:
	}
}

// run_menu_fixture backs both the native menu smoke fixture and the macOS
// titlebar interaction fixture. The optional mode is deliberately host-test
// only; it does not add a public titlebar option to Application.
run_menu_fixture :: proc(titlebar_fixture, smoke: bool, decoration_mode: Window_Decoration_Mode) {
	recent_items := [?]Application_Menu_Item{
		{kind=.Command, command=Application_Command_ID(4), label="Trace A", state=alicorn.Action_State{enabled=true}},
		{kind=.Command, command=Application_Command_ID(5), label="Trace B", state=alicorn.Action_State{enabled=true}},
	}
	file_items := [?]Application_Menu_Item{
		{kind=.Command, command=Application_Command_ID(1), label="Open Trace…", state=alicorn.Action_State{enabled=true}, shortcut=Application_Menu_Shortcut{'O', {.Primary}}},
		{kind=.Submenu, label="Open Recent", state=alicorn.Action_State{enabled=true}, items=recent_items[:]},
		{kind=.Separator},
		{kind=.Command, command=Application_Command_ID(2), label="Save", state=alicorn.Action_State{enabled=false}, shortcut=Application_Menu_Shortcut{'S', {.Primary}}},
		{kind=.Command, command=Application_Command_ID(3), label="Follow Tail", state=alicorn.Action_State{enabled=true, checked=true}},
	}
	edit_items := [?]Application_Menu_Item{
		{kind=.Command, command=Application_Command_ID(6), label="Copy", state=alicorn.Action_State{enabled=true}, shortcut=Application_Menu_Shortcut{'C', {.Primary}}},
		{kind=.Command, command=Application_Command_ID(7), label="Paste", state=alicorn.Action_State{enabled=false}, shortcut=Application_Menu_Shortcut{'V', {.Primary}}},
	}
	view_items := [?]Application_Menu_Item{
		{kind=.Command, command=Application_Command_ID(8), label="Show Timeline", state=alicorn.Action_State{enabled=true, checked=true}},
	}
	help_items := [?]Application_Menu_Item{
		{kind=.Command, command=Application_Command_ID(9), label="About Alicorn", state=alicorn.Action_State{enabled=true}},
	}
	menus := [?]Application_Menu{
		{label="File", items=file_items[:]},
		{label="Edit", items=edit_items[:]},
		{label="View", items=view_items[:]},
		{label="Help", items=help_items[:]},
	}
	state := Menu_Fixture_State{
		titlebar_fixture=titlebar_fixture,
		titlebar_tab_order=[2]u64{1, 2},
		titlebar_selected_tab=1,
	}
	fixture_application := Application{
		state=rawptr(&state),
		title="Alicorn Titlebar Input Fixture" if titlebar_fixture else "Alicorn Menu Fixture",
		width=900,
		height=560,
		menus=menus[:],
		window_decorations=decoration_mode,
		build=menu_fixture_build,
		on_text_change=menu_fixture_text_change,
		on_pointer=menu_fixture_pointer,
		on_drag=menu_fixture_drag_event,
		on_menu_command=menu_fixture_command,
	}
	if titlebar_fixture {
		native_run_application(fixture_application, smoke=smoke, macos_titlebar_fixture=true)
	} else {
		Run(fixture_application, smoke=smoke)
	}
}

// RunMenuFixture is a small end-to-end host fixture for menu rendering,
// native keyboard navigation, and semantic command delivery.
RunMenuFixture :: proc() {
	titlebar_fixture := false
	smoke := false
	decoration_mode := Window_Decoration_Mode.System
	for argument in os.args {
		if argument == "--macos-titlebar-fixture" { titlebar_fixture = true }
		if argument == "--integrated-title-bar" { decoration_mode = .Integrated_Title_Bar }
		if argument == "--menu-fixture-smoke" { smoke = true }
	}
	run_menu_fixture(titlebar_fixture, smoke, decoration_mode)
}

// RunMacOSTitlebarFixture is used only by the dedicated native fixture app
// entrypoint, which avoids relying on LaunchServices preserving argv.
RunMacOSTitlebarFixture :: proc() {
	run_menu_fixture(true, false, .System)
}
