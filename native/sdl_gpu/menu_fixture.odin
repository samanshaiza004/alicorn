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
	windows_titlebar_fixture:      bool,
	titlebar_root_node:            alicorn.Node_ID,
	titlebar_header_node:          alicorn.Node_ID,
	titlebar_body_node:            alicorn.Node_ID,
	titlebar_tabs_region_node:     alicorn.Node_ID,
	titlebar_blank_node:           alicorn.Node_ID,
	titlebar_chrome_regions:       [2]Window_Chrome_Region,
	titlebar_chrome_region_count:  int,
	titlebar_theme:                alicorn.Style_Theme_ID,
	titlebar_window_service:        Application_Window_Service,
	titlebar_detach_count:          u64,
	titlebar_detached_tab_id:       u64,
	titlebar_control_bounds:       [3]alicorn.Rect,
	titlebar_header_height:        f32,
	titlebar_safe_top:             f32,
	titlebar_control_start_x:      f32,
	titlebar_control_end_x:        f32,
	titlebar_window_width:         f32,
	titlebar_logical_height:       f32,
	titlebar_display_scale:        f32,
	titlebar_tab_width:            f32,
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
	titlebar_pointer_event_count:  u64,
	titlebar_pointer_x:           f32,
	titlebar_pointer_y:           f32,
	titlebar_pointer_down_x:      f32,
	titlebar_pointer_down_y:      f32,
	titlebar_pointer_up_x:        f32,
	titlebar_pointer_up_y:        f32,
	titlebar_pointer_target:      alicorn.Node_ID,
	titlebar_pointer_kind:        alicorn.Pointer_Kind,
}

TITLEBAR_FIXTURE_NAMESPACE :: u64(0x616c69636f726e)
TITLEBAR_FIXTURE_TAB_DRAG_TYPE :: alicorn.Drag_Type(0x746162)
TITLEBAR_FIXTURE_HEADER_HEIGHT :: f32(32)
TITLEBAR_FIXTURE_BACKGROUND :: alicorn.Color{0.125, 0.137, 0.16, 1}

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
	if app.titlebar_theme == 0 {
		theme := alicorn.DEFAULT_STYLE_THEME
		theme.colors[int(alicorn.Style_Color_Role.Subtle_Surface)] = TITLEBAR_FIXTURE_BACKGROUND
		theme.colors[int(alicorn.Style_Color_Role.Surface)] = alicorn.Color{0.18, 0.195, 0.22, 1}
		theme.colors[int(alicorn.Style_Color_Role.Text)] = alicorn.Color{0.88, 0.89, 0.91, 1}
		theme.colors[int(alicorn.Style_Color_Role.Muted_Text)] = alicorn.Color{0.65, 0.68, 0.72, 1}
		theme.colors[int(alicorn.Style_Color_Role.Accent)] = alicorn.Color{0.48, 0.60, 0.72, 1}
		theme.button_recipes.recipes[int(alicorn.Button_Variant.Tab)].selected.surface_role = .Surface
		app.titlebar_theme = alicorn.style_theme_register(rt, theme)
	}
	ui, should_build := alicorn.begin_frame(rt)
	if !should_build { return 0 }
	app.titlebar_window_width = f32(logical_width)
	app.titlebar_logical_height = f32(logical_height)
	root := alicorn.container_begin(
		&ui,
		.Root,
		label="macos-titlebar-fixture",
		style=alicorn.layout_style(.Column, grow=1, padding=0, gap=0, clip=true),
		color=alicorn.Color{0.04, 0.05, 0.08, 1},
	)
	if app.titlebar_safe_top > 0 {
		_ = alicorn.container_begin(&ui, .Container, label="macos-titlebar-safe-area",
			style=alicorn.layout_style(.Row, height=app.titlebar_safe_top))
		alicorn.container_end(&ui)
	}
	bar := alicorn.container_begin(
		&ui,
		.Container,
		label="native-titlebar-fixture-header",
		style=alicorn.layout_style(.Row, height=app.titlebar_header_height, gap=0, clip=true),
		color=TITLEBAR_FIXTURE_BACKGROUND,
	)
	_ = alicorn.container_begin(
		&ui,
		.Container,
		label="native-leading-control-reservation",
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
	tab_options.min_tab_width = 150
	tab_options.max_tab_width = 180
	tab_options.gap = 0
	tab_options.close_policy = .Selected_Or_Hover
	tab_options.presentation = .Compact
	tab_options.drag_type = TITLEBAR_FIXTURE_TAB_DRAG_TYPE
	preferred_width := f32(item_count)*tab_options.max_tab_width
	// This bounded fixture owns the whole row. Give the component its real
	// available width so its overflow controls agree with the outer layout.
	preferred_width = min(preferred_width, max(app.titlebar_control_end_x-app.titlebar_control_start_x, 0))
	tab_scope := alicorn.style_environment_push(&ui, alicorn.Style_Environment{theme=app.titlebar_theme, text_scale=13.0/16.0})
	tab_region := alicorn.container_begin(
		&ui,
		.Container,
		label="macos-titlebar-interactive-tabs-region",
		style=alicorn.layout_style(.Row, width=preferred_width, height=app.titlebar_header_height, clip=true),
	)
	tab_result := alicorn.tab_bar(
		&ui,
		alicorn.key_string("macos-titlebar-tabs"),
		items[:item_count],
		tab_options,
		alicorn.layout_style(.Row, width=preferred_width, height=app.titlebar_header_height, compress_weight=1),
	)
	alicorn.container_end(&ui)
	alicorn.style_environment_pop(&ui, tab_scope)
	app.titlebar_tabs_region_node = tab_region
	app.titlebar_tab_width = preferred_width
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
	blank := alicorn.container_begin(
		&ui,
		.Container,
		label="blank-native-window-drag-region",
		style=alicorn.layout_style(.Row, grow=1, height=app.titlebar_header_height),
	)
	alicorn.container_end(&ui)
	right_reserved := max(f32(logical_width)-app.titlebar_control_end_x, 0)
	if right_reserved > 0 {
		_ = alicorn.container_begin(&ui, .Container, label="native-caption-control-reservation",
			style=alicorn.layout_style(.Row, width=right_reserved, height=app.titlebar_header_height))
		alicorn.container_end(&ui)
	}
	alicorn.container_end(&ui)
	body := alicorn.container_begin(
		&ui,
		.Container,
		label="native-titlebar-fixture-body",
		style=alicorn.layout_style(.Column, grow=1, padding=20, gap=10, clip=true),
	)
	alicorn.text(&ui, "Alicorn-rendered document tabs share the native titlebar band.")
	alicorn.text(&ui, "Click, close, and drag tabs. Drag an empty header area to move the window.")
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
	alicorn.text(&ui, fmt.tprintf("Native controls (window points): %v", app.titlebar_control_bounds))
	alicorn.text(&ui, fmt.tprintf("Header %0.1fpt · tab width %0.1fpt · display scale %0.2f", app.titlebar_header_height, app.titlebar_tab_width, app.titlebar_display_scale))
	alicorn.text(
		&ui,
		fmt.tprintf(
			"Window %0.0f×%0.0fpt · fullscreen=%v (%d/%d)",
			app.titlebar_window_width,
			app.titlebar_logical_height,
			app.titlebar_fullscreen_active,
			app.titlebar_fullscreen_enters,
			app.titlebar_fullscreen_exits,
		),
	)
	alicorn.text(&ui, fmt.tprintf(
		"Alicorn pointer callbacks=%d (last %0.0f,%0.0f → node %d, kind %d; down %0.0f,%0.0f up %0.0f,%0.0f)",
		app.titlebar_pointer_event_count,
		app.titlebar_pointer_x,
		app.titlebar_pointer_y,
		u64(app.titlebar_pointer_target),
		u32(app.titlebar_pointer_kind),
		app.titlebar_pointer_down_x,
		app.titlebar_pointer_down_y,
		app.titlebar_pointer_up_x,
		app.titlebar_pointer_up_y,
	))
	alicorn.container_end(&ui)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	app.titlebar_root_node = root
	app.titlebar_header_node = bar
	app.titlebar_body_node = body
	app.titlebar_blank_node = blank
	return root
}

menu_fixture_command :: proc(state: rawptr, rt: ^alicorn.Runtime, command: Application_Command_ID) {
	app := cast(^Menu_Fixture_State)state
	app.command_count += 1
	app.last_command = command
	fmt.println("menu_command", u32(command), "count", app.command_count)
}

menu_fixture_services :: proc(state: rawptr, services: Application_Services) {
	app := cast(^Menu_Fixture_State)state
	if app == nil { return }
	app.titlebar_window_service = services.windows
}

menu_fixture_detached_tab_build :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	logical_width, logical_height: int,
	dpi_scale: f32,
) -> alicorn.Node_ID {
	app := cast(^Menu_Fixture_State)state
	ui, should_build := alicorn.begin_frame(rt)
	if !should_build { return 0 }
	root := alicorn.container_begin(&ui, .Root, label="detached-titlebar-fixture-tab",
		style=alicorn.layout_style(.Column, grow=1, padding=24, gap=12, clip=true),
		color=TITLEBAR_FIXTURE_BACKGROUND)
	alicorn.text(&ui, fmt.tprintf("Detached tab %d", app.titlebar_detached_tab_id))
	alicorn.text(&ui, "This secondary native window was opened by dropping a tab outside the strip.")
	alicorn.text(&ui, "Close this window to return to the titlebar interaction fixture.")
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return root
}

menu_fixture_window_chrome_metrics :: proc(state: rawptr, rt: ^alicorn.Runtime, metrics: Window_Chrome_Metrics) {
	app := cast(^Menu_Fixture_State)state
	if !app.titlebar_fixture { return }
	if metrics.fullscreen != app.titlebar_fullscreen_active {
		if metrics.fullscreen { app.titlebar_fullscreen_enters += 1 }
		else { app.titlebar_fullscreen_exits += 1 }
	}
	app.titlebar_fullscreen_active = metrics.fullscreen
	app.titlebar_control_bounds = metrics.native_controls
	app.titlebar_safe_top = metrics.header.y
	app.titlebar_control_start_x = metrics.content_start_x
	app.titlebar_control_end_x = metrics.content_end_x
	app.titlebar_window_width = metrics.header.w
	app.titlebar_header_height = metrics.header.h
	app.titlebar_logical_height = rt.viewport.h
	app.titlebar_display_scale = metrics.display_scale
}

menu_fixture_window_chrome_layout :: proc(state: rawptr, rt: ^alicorn.Runtime) -> Window_Chrome_Layout {
	app := cast(^Menu_Fixture_State)state
	if !app.titlebar_fixture { return {} }
	app.titlebar_chrome_region_count = 0
	if app.titlebar_tabs_region_node != 0 {
		app.titlebar_chrome_regions[app.titlebar_chrome_region_count] = Window_Chrome_Region{
			node=app.titlebar_tabs_region_node, kind=.Interactive,
		}
		app.titlebar_chrome_region_count += 1
	}
	if app.titlebar_blank_node != 0 {
		app.titlebar_chrome_regions[app.titlebar_chrome_region_count] = Window_Chrome_Region{
			node=app.titlebar_blank_node, kind=.Window_Drag,
		}
		app.titlebar_chrome_region_count += 1
	}
	return Window_Chrome_Layout{
		header=app.titlebar_header_node,
		regions=app.titlebar_chrome_regions[:app.titlebar_chrome_region_count],
	}
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
		if event.target.value == 0 {
			description := Application_Window_Description{
				application=Application{
					state=rawptr(app),
					title="Detached Alicorn titlebar fixture tab",
					width=560,
					height=360,
					build=menu_fixture_detached_tab_build,
				},
				width=560,
				height=360,
			}
			if application_open_window(app.titlebar_window_service, description) {
				app.titlebar_detached_tab_id = event.source.value
				app.titlebar_detach_count += 1
				if event.source.value > 0 && event.source.value <= u64(len(app.titlebar_closed_tabs)) {
					app.titlebar_closed_tabs[event.source.value-1] = true
					if app.titlebar_selected_tab == event.source.value {
						for candidate in app.titlebar_tab_order {
							if candidate != 0 && candidate != event.source.value && candidate <= u64(len(app.titlebar_closed_tabs)) &&
								!app.titlebar_closed_tabs[candidate-1] {
								app.titlebar_selected_tab = candidate
								break
							}
						}
					}
				}
				fmt.println("native_titlebar_tab_detached", "tab", event.source.value, "count", app.titlebar_detach_count)
				alicorn.invalidate_root(rt, "titlebar fixture tab detached")
			} else {
				fmt.println("native_titlebar_tab_detach_failed", "tab", event.source.value)
			}
			return
		}
		if event.source.value == event.target.value { return }
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
// titlebar interaction fixture. The latter exercises Application's public
// content-titlebar contract.
run_menu_fixture :: proc(titlebar_fixture, windows_titlebar_fixture, smoke: bool, decoration_mode: Window_Decoration_Mode) {
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
		titlebar_fixture=titlebar_fixture || windows_titlebar_fixture,
		windows_titlebar_fixture=windows_titlebar_fixture,
		titlebar_header_height=TITLEBAR_FIXTURE_HEADER_HEIGHT,
		titlebar_control_end_x=900,
		titlebar_tab_order=[2]u64{1, 2},
		titlebar_selected_tab=1,
	}
	fixture_application := Application{
		state=rawptr(&state),
		title="Alicorn Titlebar Input Fixture" if titlebar_fixture else "Alicorn Menu Fixture",
		width=900,
		height=560,
		menus=menus[:],
		window_decorations=.Content_Title_Bar if titlebar_fixture else (.Integrated_Title_Bar if windows_titlebar_fixture else decoration_mode),
		window_chrome_height=TITLEBAR_FIXTURE_HEADER_HEIGHT if titlebar_fixture else 0,
		window_chrome_metrics=menu_fixture_window_chrome_metrics if state.titlebar_fixture else nil,
		window_chrome_layout=menu_fixture_window_chrome_layout if state.titlebar_fixture else nil,
		build=menu_fixture_build,
		on_text_change=menu_fixture_text_change,
		on_pointer=menu_fixture_pointer,
		on_drag=menu_fixture_drag_event,
		on_services=menu_fixture_services if state.titlebar_fixture else nil,
		on_menu_command=menu_fixture_command,
	}
	if titlebar_fixture || windows_titlebar_fixture {
		native_run_application(
			fixture_application,
			smoke=smoke,
			macos_titlebar_fixture=titlebar_fixture,
			windows_titlebar_fixture=windows_titlebar_fixture,
		)
	} else {
		Run(fixture_application, smoke=smoke)
	}
}

native_fixture_smoke_requested :: proc(arguments: []string) -> bool {
	for argument in arguments {
		if argument == "--smoke" || argument == "--menu-fixture-smoke" { return true }
	}
	return false
}

// RunMenuFixture is a small end-to-end host fixture for menu rendering,
// native keyboard navigation, and semantic command delivery.
RunMenuFixture :: proc() {
	titlebar_fixture := false
	windows_titlebar_fixture := false
	decoration_mode := Window_Decoration_Mode.System
	for argument in os.args {
		if argument == "--macos-titlebar-fixture" { titlebar_fixture = true }
		if argument == "--windows-titlebar-fixture" { windows_titlebar_fixture = true }
		if argument == "--integrated-title-bar" { decoration_mode = .Integrated_Title_Bar }
	}
	run_menu_fixture(titlebar_fixture, windows_titlebar_fixture, native_fixture_smoke_requested(os.args), decoration_mode)
}

// RunMacOSTitlebarFixture is used only by the dedicated native fixture app
// entrypoint, which avoids relying on LaunchServices preserving argv.
RunMacOSTitlebarFixture :: proc() {
	when ODIN_OS == .Darwin {
		for argument in os.args {
			if argument == "--geometry-check" {
				if !native_darwin_titlebar_geometry_check() { os.exit(1) }
				return
			}
		}
	}
	run_menu_fixture(true, false, false, .System)
}
