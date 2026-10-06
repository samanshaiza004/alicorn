package main

// 02 · Widget Gallery exercises accessible static text, composite tabs,
// app-owned values, controlled text input, and per-widget style/color overrides.
// Run with `odin run examples/02_form` and interact with the controls.

import "core:fmt"
import "core:strings"
import alicorn "../../runtime"
import host "../../native/sdl_gpu"

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
	name: string,
	name_owned: bool,
}

GALLERY_TAB_SEMANTIC_NAMESPACE :: u64(0x5749444745544741)

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

	document_tabs := [3]alicorn.Tab_Bar_Item{
		{key=alicorn.key_string("gallery-tab-readme"), label="README.md", selected=app.selected_gallery_tab == 0, closable=true,
			semantic_id=alicorn.Semantic_ID{namespace=GALLERY_TAB_SEMANTIC_NAMESPACE, value=1}},
		{key=alicorn.key_string("gallery-tab-main"), label="main.odin", selected=app.selected_gallery_tab == 1, closable=true,
			semantic_id=alicorn.Semantic_ID{namespace=GALLERY_TAB_SEMANTIC_NAMESPACE, value=2}},
		{key=alicorn.key_string("gallery-tab-license"), label="LICENSE", selected=app.selected_gallery_tab == 2, closable=true, dirty=true,
			semantic_id=alicorn.Semantic_ID{namespace=GALLERY_TAB_SEMANTIC_NAMESPACE, value=3}},
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

	alicorn.container_end(&ui)
	alicorn.text(&ui, "Controlled values live in the application · Reset values restores the initial settings")
	alicorn.container_end(&ui)

	alicorn.end_frame(&ui)
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
