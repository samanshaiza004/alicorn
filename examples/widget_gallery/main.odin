package main

import "core:fmt"
import alicorn "../../runtime"
import host "../../native/sdl_gpu"

App :: struct {
	show_grid: bool,
	auto_save: bool,
	gain: f32,
	exposure: f32,
	offset: f32,
	clicks: int,
}

reset_values :: proc(app: ^App) {
	app.show_grid = true
	app.auto_save = false
	app.gain = 0.65
	app.exposure = 0.4
	app.offset = -1.5
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
	alicorn.text(&ui, "Interactive reference for controlled widgets · Tab to focus · Space toggles · arrows adjust sliders · Home/End set bounds")

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
	app := App{show_grid=true, gain=0.65, exposure=0.4, offset=-1.5}
	host.Run(host.Application{
		state=rawptr(&app),
		title="Alicorn Widget Gallery",
		width=1000,
		height=760,
		build=build_app,
	})
}
