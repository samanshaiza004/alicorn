package main

// 12 · Custom Segmented Control proves that a package can own a control's
// visible shape while Alicorn's public Button continues to own interaction.

import "core:fmt"
import alicorn "alicorn:runtime"
import segmented "./segmented"
import theme "alicorn:theme"
import ui "alicorn:ui"

THEME_PATH :: "examples/12_custom_segmented_control/segmented/theme.json"
THEME_JSON :: segmented.DEFAULT_THEME_JSON

custom_accent_role :: proc() -> alicorn.Style_Extension_Color_Role_ID {
	return alicorn.style_extension_color_role_id("app.example", "segmented_custom_accent")
}

window_role :: proc() -> alicorn.Style_Extension_Color_Role_ID {
	return alicorn.style_extension_color_role_id("app.example", "segmented_window")
}

App :: struct {
	primary: segmented.Segmented_State,
	custom: segmented.Segmented_State,
	recipe: segmented.Recipe,
	custom_style: segmented.Style,
	theme_id: alicorn.Style_Theme_ID,
	theme_error: bool,
	missing_roles: [7]string,
	missing_role_count: int,
	text_scale: f32,
	accessibility: alicorn.Accessibility_Appearance_Preferences,
	accessibility_set: bool,
}

app_default :: proc() -> App {
	custom_style := segmented.style_default()
	custom_style.instance_accent_role = custom_accent_role()
	custom_style.track_height = 212
	custom_style.track_radius = 30
	custom_style.segment_radius = 24
	custom_style.segment_padding = 12
	custom_style.focus_inset = 3
	custom_style.segment_height = 68
	custom_style.compact_height = 46
	custom_style.marker_width = 38
	custom_style.marker_height = 7
	custom_style.label_size = 19
	return App{
		primary=segmented.Segmented_State{selected=.Edit},
		custom=segmented.Segmented_State{selected=.Preview, disabled={false, false, true}},
		recipe=segmented.recipe_default(),
		custom_style=custom_style,
	}
}

initialize_app :: proc(app: ^App, rt: ^alicorn.Runtime) {
	compiled := theme.theme_compile_json(string(THEME_JSON), THEME_PATH)
	defer theme.theme_json_compile_output_destroy(&compiled)
	if !compiled.ok {
		if len(compiled.parsed.diagnostics) > 0 {
			diagnostic := compiled.parsed.diagnostics[0]
			fmt.println("Theme error", diagnostic.span.line, diagnostic.span.column, diagnostic.message)
		} else {
			fmt.println("The embedded segmented-control theme could not be compiled.")
		}
		app.theme_error = true
		return
	}
	runtime_theme, adapted := theme.theme_runtime_style_theme(compiled.compiled)
	if !adapted {
		fmt.println("The segmented-control theme could not be adapted to Alicorn's style contract.")
		app.theme_error = true
		return
	}
	defer theme.theme_runtime_style_theme_destroy(&runtime_theme)
	app.theme_id = alicorn.style_theme_register(rt, runtime_theme)
	if app.theme_id == 0 {
		fmt.println("Alicorn rejected the segmented-control theme.")
		app.theme_error = true
		return
	}
	contract := segmented.theme_contract_default(app.recipe, app.custom_style.instance_accent_role)
	report := segmented.theme_contract_check(rt, app.theme_id, contract)
	missing, missing_count := segmented.theme_contract_missing_required(contract, report)
	app.missing_roles = missing
	app.missing_role_count = missing_count
	for index in 0..<missing_count { fmt.println("Missing segmented-control theme role:", missing[index]) }
	if missing_count > 0 {
		app.theme_error = true
		return
	}
	if !report.optional_available[0] {
		fmt.println("Optional per-instance accent is unbound; the selected marker will use the component accent.")
		app.custom_style.instance_accent_role = 0
	}
	_, window_found := alicorn.style_extension_color(rt, app.theme_id, window_role())
	if !window_found {
		fmt.println("Missing application theme role: app.example.segmented.window")
		app.theme_error = true
	}
}

initialize :: proc(state: rawptr, rt: ^alicorn.Runtime) {
	initialize_app(cast(^App)state, rt)
}

render_contents :: proc(app: ^App, ctx: ^ui.UI) {
	if app.theme_error || app.theme_id == 0 {
		ui.text(ctx, "The custom segmented-control theme is incomplete.", size=20)
		for index in 0..<app.missing_role_count {
			ui.text(ctx, fmt.tprintf("Missing theme role: %s", app.missing_roles[index]))
		}
		return
	}
	if ui.panel(ctx, key=ui.key_u64(1), grow=1, padding=24, gap=18,
		fill=alicorn.Color{0.045, 0.055, 0.08, 1}, label="segmented-control-demo") {
		ui.text(ctx, "Custom segmented control", size=26)
		ui.text(ctx,
			"Each segment owns its shape and state visuals. Resize the window, use Tab and Space, and compare the two independent instances.")
		environment := alicorn.Style_Environment{
			theme=app.theme_id,
			text_scale=app.text_scale,
			accessibility=app.accessibility,
			accessibility_set=app.accessibility_set,
		}
		scope := alicorn.style_environment_push(ctx, environment)
		if ui.row(ctx, key=ui.key_u64(2), gap=18, align=.Center, label="segmented-control-examples") {
			_ = segmented.segmented_control(ctx, "Workspace view", &app.primary, app.recipe,
				segmented.style_default(), key=ui.key_u64(10), instance_id=101)
			_ = segmented.segmented_control(ctx, "Review mode", &app.custom, app.recipe,
				app.custom_style, key=ui.key_u64(20), instance_id=202)
		}
		alicorn.style_environment_pop(ctx, scope)
		ui.text(ctx,
			"The purple instance uses the same recipe with its own token, pill geometry, sizing, and an unavailable Compare option.",
			size=13)
		alicorn.surface_end(ctx)
	}
}

main :: proc() {
	app := app_default()
	ui.run(&app, render_contents, title="Alicorn · Custom Segmented Control", width=1180, height=620,
		on_initialize=initialize_app)
}
