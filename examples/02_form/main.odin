package main

// 02 · Widget Gallery exercises accessible static text, composite tabs,
// controlled selection and notices, app-owned values, controlled text input,
// and per-widget style/color overrides.
// Run with `odin run examples/02_form` and interact with the controls.

import "core:fmt"
import "core:strings"
import alicorn "../../runtime"
import host "../../native/sdl_gpu"
import sdl3 "vendor:sdl3"

App :: struct {
	show_grid: bool,
	auto_save: bool,
	gain: f32,
	exposure: f32,
	offset: f32,
	clicks: int,
	selected_gallery_tab: int,
	tab_close_requests: int,
	last_closed_tab: int,
	selected_choice: u64,
	notice_request: int,
	notice_feedback: string,
	notice_action_count: int,
	notice_handles: [alicorn.NOTICE_QUEUE_CAPACITY]alicorn.Notice_Handle,
	notice_handle_write: int,
	name: string,
	name_owned: bool,
}

GALLERY_TAB_SEMANTIC_NAMESPACE :: u64(0x5749444745544741)
GALLERY_NOTICE_NONE :: 0
GALLERY_NOTICE_TRANSIENT :: 1
GALLERY_NOTICE_PERSISTENT :: 2
GALLERY_NOTICE_ACTIONABLE :: 3
GALLERY_NOTICE_DISMISS_ALL :: 4
GALLERY_NOTICE_RETRY :: alicorn.Action_ID(7101)
GALLERY_NOTICE_DETAILS :: alicorn.Action_ID(7102)

gallery_remember_notice_handle :: proc(app: ^App, handle: alicorn.Notice_Handle) {
	if app == nil || handle == 0 { return }
	app.notice_handles[app.notice_handle_write] = handle
	app.notice_handle_write = (app.notice_handle_write+1)%len(app.notice_handles)
}

GALLERY_SELECT_OPTIONS :: [4]alicorn.Select_Option{
	{key=1, label="Warm"},
	{key=2, label="Cool Light"},
	{key=3, label="Forest"},
	{key=4, label="High Contrast"},
}

gallery_select_label :: proc(key: u64) -> string {
	for option in GALLERY_SELECT_OPTIONS {
		if option.key == key { return option.label }
	}
	return "No selection"
}

gallery_process_notice_request :: proc(app: ^App, rt: ^alicorn.Runtime) {
	if app == nil || rt == nil { return }
	request := app.notice_request
	app.notice_request = GALLERY_NOTICE_NONE
	if request == GALLERY_NOTICE_NONE { return }

	accepted := false
	switch request {
	case GALLERY_NOTICE_TRANSIENT:
		handle, emitted := alicorn.notice_emit(rt, alicorn.Notice{
			title="Saved",
			message="This success notice expires after five seconds.",
			severity=.Success,
			lifetime=.Transient,
			placement=.Toast,
			duration_ms=5_000,
		}, u64(sdl3.GetTicksNS()))
		accepted = emitted
		gallery_remember_notice_handle(app, handle)
		app.notice_feedback = "Emitted a success event; repeated events stack."
	case GALLERY_NOTICE_PERSISTENT:
		accepted = alicorn.notice_post(rt, alicorn.Notice{
			id="gallery-persistent",
			title="Folder needs attention",
			message="This warning stays until you dismiss it.",
			details="Persistent notices do not expire automatically.",
			severity=.Warning,
			lifetime=.Persistent,
			placement=.Toast,
		}, u64(sdl3.GetTicksNS()))
		app.notice_feedback = "Posted or updated the stable warning condition."
	case GALLERY_NOTICE_ACTIONABLE:
		actions := [2]alicorn.Notice_Action{
			{id=GALLERY_NOTICE_DETAILS, label="Details"},
			{id=GALLERY_NOTICE_RETRY, label="Retry"},
		}
		handle, emitted := alicorn.notice_emit(rt, alicorn.Notice{
			title="Couldn't refresh folder",
			message="The folder's contents may be out of date.",
			details="The gallery leaves recovery decisions to the application.",
			severity=.Error,
			lifetime=.Persistent,
			placement=.Toast,
			actions=actions[:],
		}, u64(sdl3.GetTicksNS()))
		accepted = emitted
		gallery_remember_notice_handle(app, handle)
		app.notice_feedback = "Emitted an actionable error event; each has its own actions."
	case GALLERY_NOTICE_DISMISS_ALL:
		dismissed := false
		for handle in app.notice_handles {
			dismissed = alicorn.notice_dismiss_handle(rt, handle) || dismissed
		}
		dismissed = alicorn.notice_dismiss(rt, "gallery-persistent") || dismissed
		app.notice_feedback = "Dismissed the gallery notices." if dismissed else "There are no gallery notices to dismiss."
		alicorn.invalidate_root(rt, "gallery notice dismissal feedback changed")
		return
	}
	if accepted {
		// notice_post already invalidates the root when it accepts the record.
	} else {
		app.notice_feedback = "Notice request was rejected; the queue may be full of persistent notices."
		alicorn.invalidate_root(rt, "gallery notice request was rejected")
	}
}

gallery_process_notice_actions :: proc(app: ^App, rt: ^alicorn.Runtime) {
	if app == nil || rt == nil { return }
	for {
		event, found := alicorn.notice_take_action(rt)
		if !found { break }
		app.notice_action_count += 1
		switch event.action {
		case GALLERY_NOTICE_DETAILS:
			app.notice_feedback = "Details action reached the application; the notice remains open."
		case GALLERY_NOTICE_RETRY:
			app.notice_feedback = "Retry action reached the application; the demo dismissed that occurrence."
			_ = alicorn.notice_dismiss_handle(rt, event.notice)
		case:
			app.notice_feedback = "A notice action reached the application."
		}
		alicorn.invalidate_root(rt, "gallery notice action handled")
	}
}

reset_values :: proc(app: ^App) {
	app.show_grid = true
	app.auto_save = false
	app.gain = 0.65
	app.exposure = 0.4
	app.offset = -1.5
}

form_text_change :: proc(state: rawptr, rt: ^alicorn.Runtime, change: alicorn.Text_Change) {
	if !change.changed { return }
	app := cast(^App)state
	value, err := strings.clone(change.text)
	if err != nil { return }
	if app.name_owned { delete(app.name) }
	app.name, app.name_owned = value, true
	alicorn.invalidate_root(rt, "form text field changed")
}

form_stop :: proc(state: rawptr) {
	app := cast(^App)state
	if app.name_owned { delete(app.name) }
}

build_app :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	logical_width, logical_height: int,
	dpi_scale: f32,
) -> alicorn.Node_ID {
	app := cast(^App)state
	ui, should_build := alicorn.begin_frame(rt)
	if !should_build {
		return 0
	}

	root := alicorn.container_begin(
		&ui,
		.Root,
		label="widget-gallery-root",
		style=alicorn.layout_style(.Column, grow=1, padding=24, gap=14, clip=true),
		color=alicorn.Color{0.035, 0.045, 0.065, 1},
	)
	alicorn.text(&ui, "Alicorn Widget Gallery", style=alicorn.layout_style(height=32), text_style=alicorn.Text_Style{font_weight=alicorn.FONT_WEIGHT_BOLD})
	_ = alicorn.semantic_static_text(&ui)
	alicorn.text(&ui, "Interactive controls · Tab to focus · Space toggles · arrows adjust sliders · select/close a document tab to test tab actions")
	_ = alicorn.semantic_static_text(&ui)

	document_tabs := [4]alicorn.Tab_Bar_Item{
		{key=alicorn.key_string("gallery-tab-readme"), label="README.md", selected=app.selected_gallery_tab == 0, closable=true,
			semantic_id=alicorn.Semantic_ID{namespace=GALLERY_TAB_SEMANTIC_NAMESPACE, value=1}},
		{key=alicorn.key_string("gallery-tab-main"), label="main.odin", selected=app.selected_gallery_tab == 1, closable=true,
			semantic_id=alicorn.Semantic_ID{namespace=GALLERY_TAB_SEMANTIC_NAMESPACE, value=2}},
		{key=alicorn.key_string("gallery-tab-license"), label="LICENSE", selected=app.selected_gallery_tab == 2, closable=true, dirty=true,
			semantic_id=alicorn.Semantic_ID{namespace=GALLERY_TAB_SEMANTIC_NAMESPACE, value=3}},
		{key=alicorn.key_string("gallery-tab-select-notices"), label="Select + Notices", selected=app.selected_gallery_tab == 3,
			semantic_id=alicorn.Semantic_ID{namespace=GALLERY_TAB_SEMANTIC_NAMESPACE, value=4}},
	}
	tab_result := alicorn.tab_bar(
		&ui,
		alicorn.key_string("gallery-document-tabs"),
		document_tabs[:],
		style=alicorn.layout_style(.Row, height=38),
	)
	if tab_result.action == .Select && tab_result.item_index >= 0 && tab_result.item_index < len(document_tabs) {
		app.selected_gallery_tab = tab_result.item_index
		alicorn.invalidate_root(rt, "widget gallery tab selection changed")
	} else if tab_result.action == .Close && tab_result.item_index >= 0 && tab_result.item_index < len(document_tabs) {
		app.tab_close_requests += 1
		app.last_closed_tab = tab_result.item_index
	}
	selected_tab_index := app.selected_gallery_tab
	tab_status := fmt.tprintf(
		"Selected tab: %s · close requests: %d",
		document_tabs[selected_tab_index].label,
		app.tab_close_requests,
	)
	if app.tab_close_requests > 0 {
		tab_status = fmt.tprintf("%s · last close: %s", tab_status, document_tabs[app.last_closed_tab].label)
	}
	alicorn.text(&ui, tab_status, style=alicorn.layout_style(height=20))
	_ = alicorn.semantic_static_text(&ui)

	alicorn.container_begin(
		&ui,
		.Container,
		label="gallery-panels",
		style=alicorn.layout_style(.Row, grow=1, gap=16, clip=true),
	)
	if app.selected_gallery_tab == 3 {
		alicorn.container_begin(
			&ui,
			.Container,
			label="select-panel",
			style=alicorn.layout_style(.Column, grow=1, padding=20, gap=12, clip=true),
			color=alicorn.Color{0.075, 0.09, 0.125, 1},
		)
		alicorn.text(&ui, "Select", style=alicorn.layout_style(height=28), text_style=alicorn.Text_Style{font_weight=alicorn.FONT_WEIGHT_SEMIBOLD})
		_ = alicorn.semantic_static_text(&ui)
		alicorn.text(&ui, "Choose one value from a fixed set. The selection remains app-owned.")
		_ = alicorn.semantic_static_text(&ui)
		alicorn.text(&ui, "Theme")
		select_options := GALLERY_SELECT_OPTIONS
		choice := alicorn.select_control(
			&ui,
			alicorn.key_string("gallery-theme-select"),
			"Theme",
			select_options[:],
			app.selected_choice,
			style=alicorn.layout_style(.Row, width=300, height=36),
		)
		if choice.changed {
			app.selected_choice = choice.selected_key
		}
		alicorn.text(&ui, "Font-independent indicators", style=alicorn.layout_style(height=22))
		alicorn.container_begin(&ui, .Container, label="gallery-icon-samples", style=alicorn.layout_style(.Row, height=24, gap=8, align=.Center))
		_ = alicorn.icon(&ui, .Folder_Closed, key=alicorn.key_string("gallery-folder-closed"), size=18)
		alicorn.text(&ui, "Closed")
		_ = alicorn.icon(&ui, .Folder_Open, key=alicorn.key_string("gallery-folder-open"), size=18)
		alicorn.text(&ui, "Open")
		_ = alicorn.icon(&ui, .Search, key=alicorn.key_string("gallery-search-icon"), size=18)
		alicorn.text(&ui, "Search")
		alicorn.container_end(&ui)
		alicorn.text(&ui, fmt.tprintf("Application value: %s", gallery_select_label(app.selected_choice)))
		_ = alicorn.semantic_static_text(&ui)
		alicorn.text(&ui, "Keyboard: Up/Down, Home/End, type to jump, Enter to choose, Escape to close.")
		_ = alicorn.semantic_static_text(&ui)
		alicorn.text(&ui, "Open the list, switch focus away with Tab, then return to inspect focus restoration.")
		_ = alicorn.semantic_static_text(&ui)
		alicorn.container_begin(&ui, .Container, label="select-panel-spacer", style=alicorn.layout_style(grow=1))
		alicorn.container_end(&ui)
		alicorn.container_end(&ui)

		alicorn.container_begin(
			&ui,
			.Container,
			label="notices-panel",
			style=alicorn.layout_style(.Column, grow=1, padding=20, gap=10, clip=true),
			color=alicorn.Color{0.075, 0.09, 0.125, 1},
		)
		alicorn.text(&ui, "Notices", style=alicorn.layout_style(height=28), text_style=alicorn.Text_Style{font_weight=alicorn.FONT_WEIGHT_SEMIBOLD})
		_ = alicorn.semantic_static_text(&ui)
		alicorn.text(&ui, "Notices float above the gallery without moving its layout or taking editor focus.")
		_ = alicorn.semantic_static_text(&ui)
		alicorn.container_begin(&ui, .Container, label="notice-demo-actions", style=alicorn.layout_style(.Row, gap=8))
		if alicorn.button(&ui, "Emit transient", key=alicorn.key_string("notice-transient"), style=alicorn.layout_style(.Row, width=142, height=34)) {
			app.notice_request = GALLERY_NOTICE_TRANSIENT
		}
		if alicorn.button(&ui, "Post/update warning", key=alicorn.key_string("notice-persistent"), style=alicorn.layout_style(.Row, width=164, height=34)) {
			app.notice_request = GALLERY_NOTICE_PERSISTENT
		}
		alicorn.container_end(&ui)
		alicorn.container_begin(&ui, .Container, label="notice-demo-actions-secondary", style=alicorn.layout_style(.Row, gap=8))
		if alicorn.button(&ui, "Emit actionable error", key=alicorn.key_string("notice-actionable"), style=alicorn.layout_style(.Row, width=184, height=34)) {
			app.notice_request = GALLERY_NOTICE_ACTIONABLE
		}
		if alicorn.button(&ui, "Dismiss examples", key=alicorn.key_string("notice-dismiss-all"), style=alicorn.layout_style(.Row, width=148, height=34)) {
			app.notice_request = GALLERY_NOTICE_DISMISS_ALL
		}
		alicorn.container_end(&ui)
		alicorn.text(&ui, app.notice_feedback, style=alicorn.layout_style(height=48))
		_ = alicorn.semantic_static_text(&ui)
		alicorn.text(&ui, fmt.tprintf("Notice actions handled: %d", app.notice_action_count))
		_ = alicorn.semantic_static_text(&ui)
		alicorn.text(&ui, "Errors announce assertively; informational notices use a polite live announcement.")
		_ = alicorn.semantic_static_text(&ui)
		alicorn.text(&ui, "Repeated events stack; a repeated stable warning ID updates the existing notice.")
		_ = alicorn.semantic_static_text(&ui)
		alicorn.container_begin(&ui, .Container, label="notices-panel-spacer", style=alicorn.layout_style(grow=1))
		alicorn.container_end(&ui)
		alicorn.container_end(&ui)
	} else {

	alicorn.container_begin(
		&ui,
		.Container,
		label="checkbox-panel",
		style=alicorn.layout_style(.Column, grow=1, padding=20, gap=12, clip=true),
		color=alicorn.Color{0.075, 0.09, 0.125, 1},
	)
	alicorn.text(&ui, "Checkboxes", style=alicorn.layout_style(height=28), text_style=alicorn.Text_Style{font_weight=alicorn.FONT_WEIGHT_SEMIBOLD})
	_ = alicorn.semantic_static_text(&ui)
	alicorn.text(&ui, "Name", style=alicorn.layout_style(height=22))
	alicorn.text_field(&ui, app.name, key=alicorn.key_string("name"), style=alicorn.layout_style(height=36))
	_ = alicorn.semantic_description(&ui, .Text_Field, "Name")
	alicorn.text(&ui, fmt.tprintf("Hello, %s", app.name), style=alicorn.layout_style(height=24))
	alicorn.text(&ui, "Click or focus a checkbox and press Space to toggle it. Enter is reserved for buttons.")
	alicorn.container_begin(&ui, .Container, label="gallery-actions", style=alicorn.layout_style(.Row, gap=8))
	if alicorn.button(&ui, "Reset values", key=alicorn.key_string("reset"), style=alicorn.layout_style(.Row, width=140, height=36)) {
		reset_values(app)
	}
	if alicorn.button(&ui, "Click me", key=alicorn.key_string("click"), style=alicorn.layout_style(.Row, width=120, height=36)) {
		app.clicks += 1
	}
	alicorn.container_end(&ui)
	alicorn.text(&ui, fmt.tprintf("Button activations: %d", app.clicks))
	_ = alicorn.semantic_static_text(&ui)

	show_grid := alicorn.checkbox(
		&ui,
		"Show grid",
		app.show_grid,
		key=alicorn.key_string("show-grid"),
		style=alicorn.layout_style(.Row, height=36),
	)
	if show_grid.changed {
		app.show_grid = show_grid.value
	}

	auto_save := alicorn.checkbox(
		&ui,
		"Auto-save changes",
		app.auto_save,
		key=alicorn.key_string("auto-save"),
		style=alicorn.layout_style(.Row, height=36),
	)
	if auto_save.changed {
		app.auto_save = auto_save.value
	}

	_ = alicorn.checkbox(
		&ui,
		"Disabled option",
		true,
		key=alicorn.key_string("disabled-option"),
		style=alicorn.layout_style(.Row, height=36),
		disabled=true,
	)
	// Keep the status line explicit without requiring a formatting helper for
	// booleans: it also makes app-authoritative state easy to inspect in a run.
	status := "Grid off · Auto-save off"
	if app.show_grid && app.auto_save {
		status = "Grid on · Auto-save on"
	} else if app.show_grid {
		status = "Grid on · Auto-save off"
	} else if app.auto_save {
		status = "Grid off · Auto-save on"
	}
	alicorn.text(&ui, status)
	_ = alicorn.semantic_static_text(&ui)

	alicorn.container_begin(&ui, .Container, label="checkbox-panel-spacer", style=alicorn.layout_style(grow=1))
	alicorn.container_end(&ui)
	alicorn.container_end(&ui)

	alicorn.container_begin(
		&ui,
		.Container,
		label="slider-panel",
		style=alicorn.layout_style(.Column, grow=1, padding=20, gap=8, clip=true),
		color=alicorn.Color{0.075, 0.09, 0.125, 1},
	)
	alicorn.text(&ui, "Sliders", style=alicorn.layout_style(height=28), text_style=alicorn.Text_Style{font_weight=alicorn.FONT_WEIGHT_SEMIBOLD})
	_ = alicorn.semantic_static_text(&ui)
	alicorn.text(&ui, "Drag or click the track · Left/Down decrease · Right/Up increase · Home/End jump to bounds.")

	gain := alicorn.slider_f32(
		&ui,
		"Gain · stepped (0–100%, 5% steps)",
		app.gain,
		0,
		1,
		0.05,
		key=alicorn.key_string("gain"),
		style=alicorn.layout_style(height=56),
	)
	_ = alicorn.semantic_range_value_text(&ui, fmt.tprintf("%.0f%%", gain.value*100))
	if gain.changed {
		app.gain = gain.value
	}
	alicorn.text(&ui, fmt.tprintf("Gain: %.0f%%", app.gain*100))

	exposure := alicorn.slider_f32(
		&ui,
		"Exposure · continuous (0–1)",
		app.exposure,
		0,
		1,
		key=alicorn.key_string("exposure"),
		style=alicorn.layout_style(height=56),
	)
	_ = alicorn.semantic_range_value_text(&ui, fmt.tprintf("%.2f", exposure.value))
	if exposure.changed {
		app.exposure = exposure.value
	}
	alicorn.text(&ui, fmt.tprintf("Exposure: %.2f", app.exposure))

	offset := alicorn.slider_f32(
		&ui,
		"Offset · negative range (−5 to 5, 0.5 steps)",
		app.offset,
		-5,
		5,
		0.5,
		key=alicorn.key_string("offset"),
		style=alicorn.layout_style(height=56),
	)
	_ = alicorn.semantic_range_value_text(&ui, fmt.tprintf("%.1f", offset.value))
	if offset.changed {
		app.offset = offset.value
	}
	alicorn.text(&ui, fmt.tprintf("Offset: %.1f", app.offset))

	_ = alicorn.slider_f32(
		&ui,
		"Disabled slider",
		0.3,
		0,
		1,
		0.1,
		key=alicorn.key_string("disabled-slider"),
		style=alicorn.layout_style(height=52),
		disabled=true,
	)
	alicorn.container_end(&ui)
	}
	alicorn.container_end(&ui)
	alicorn.text(&ui, "Controlled values live in the application · Reset values restores the initial settings")
	alicorn.container_end(&ui)

	alicorn.end_frame(&ui)
	gallery_process_notice_request(app, rt)
	gallery_process_notice_actions(app, rt)
	return root
}

main :: proc() {
	app := App{
		show_grid=true,
		gain=0.65,
		exposure=0.4,
		offset=-1.5,
		selected_gallery_tab=0,
		last_closed_tab=-1,
		selected_choice=1,
		notice_feedback="Post examples to inspect transient, persistent, and actionable presentation.",
		name="Alicorn",
	}
	host.Run(host.Application{
		state=rawptr(&app),
		title="Alicorn Widget Gallery",
		width=1000,
		height=760,
		build=build_app,
		on_text_change=form_text_change,
		on_stop=form_stop,
	})
}
