package main

// 11 · Third-Party Component demonstrates a distributable compound control:
// its typed theme contract, custom recipe, responsive presentation,
// accessibility identities, and interruptible motion all use public APIs.

import "core:fmt"
import alicorn "alicorn:runtime"
import mode_rail "./mode_rail"
import theme "alicorn:theme"
import ui "alicorn:ui"

THEME_PATH :: "examples/11_third_party_component/mode_rail/theme.json"
THEME_JSON :: mode_rail.DEFAULT_THEME_JSON

App :: struct {
	standard: mode_rail.State,
	attention: mode_rail.State,
	custom: mode_rail.State,
	custom_style: mode_rail.Instance_Overrides,
	recipe: mode_rail.Recipe,
	theme_id: alicorn.Style_Theme_ID,
	canvas_role: alicorn.Style_Extension_Color_Role_ID,
	theme_error: bool,
	missing_required_roles: [3]string,
	missing_required_role_count: int,
	test_text_scale: f32,
	test_accessibility: alicorn.Accessibility_Appearance_Preferences,
	test_accessibility_set: bool,
}

initialize_app :: proc(app: ^App, rt: ^alicorn.Runtime) {
	registration := theme.theme_json_register(rt, string(THEME_JSON), THEME_PATH)
	defer theme.theme_json_register_result_destroy(&registration)
	app.theme_id = registration.theme_id
	if app.theme_id == 0 {
		if registration.failure == .Compile && len(registration.output.parsed.diagnostics) > 0 {
			diagnostic := registration.output.parsed.diagnostics[0]
			fmt.println("Theme error", diagnostic.span.line, diagnostic.span.column, diagnostic.message)
		} else if registration.failure == .Compile && len(registration.output.compiled.diagnostics) > 0 {
			diagnostic := registration.output.compiled.diagnostics[0]
			fmt.println("Theme rejected", diagnostic.span.line, diagnostic.span.column, diagnostic.code)
		} else {
			fmt.println("The embedded component theme could not be registered:", registration.failure)
		}
		app.theme_error = true
		return
	}

	contract := mode_rail.theme_contract_default(app.recipe, app.custom_style.indicator_role)
	report := mode_rail.theme_contract_check(rt, app.theme_id, contract)
	missing, missing_count := mode_rail.theme_contract_missing_required(contract, report)
	app.missing_required_roles = missing
	app.missing_required_role_count = missing_count
	for index in 0..<missing_count { fmt.println("Missing required Mode Rail theme role:", missing[index]) }
	if missing_count > 0 {
		app.theme_error = true
		return
	}
	if !report.optional_available[0] {
		fmt.println("Optional Mode Rail theme role vendor.acme.mode_rail.attention is unbound; using the signal role.")
		app.recipe.attention_role = 0
	}
	if !report.optional_available[1] {
		fmt.println("Optional per-instance indicator role is unbound; the custom rail will inherit the signal role.")
		app.custom_style.indicator_role = 0
	}

	app.canvas_role = alicorn.style_extension_color_role_id("app.example", "window_background")
	_, canvas_role_found := alicorn.style_extension_color(rt, app.theme_id, app.canvas_role)
	if !canvas_role_found {
		fmt.println("Missing application theme role: app.example.window_background")
		app.theme_error = true
	}
}

initialize :: proc(state: rawptr, rt: ^alicorn.Runtime) {
	initialize_app(cast(^App)state, rt)
}

render_contents :: proc(app: ^App, ctx: ^ui.UI) {
	if app.theme_error || app.theme_id == 0 {
		ui.text(ctx, "The Mode Rail theme contract is incomplete.", size=20)
		if app.missing_required_role_count > 0 {
			for index in 0..<app.missing_required_role_count {
				ui.text(ctx, fmt.tprintf("Missing theme role: %s", app.missing_required_roles[index]))
			}
		} else {
			ui.text(ctx, "Check the launch log for the missing application theme role.")
		}
		return
	}

	preferences := alicorn.Style_Environment{
		theme=app.theme_id,
		text_scale=app.test_text_scale,
		accessibility=app.test_accessibility,
		accessibility_set=app.test_accessibility_set,
	}
	scope := alicorn.style_environment_push(ctx, preferences)
	canvas := alicorn.surface_begin(ctx,
		alicorn.surface_extension_color_role(app.canvas_role),
		key=ui.key_u64(1),
		style=ui.layout_style(.Column, grow=1, padding=24, gap=12),
		label="component-demo-canvas",
	)
	if canvas != 0 {
		ui.text(ctx, "Third-party component", size=26)
		ui.text(ctx,
			"Three instances share one recipe. Resize below each rail's wide threshold, change options quickly, and try keyboard activation.")
		_ = mode_rail.mode_rail(ctx, "Update cadence", &app.standard, app.recipe,
			key=ui.key_u64(100), instance_id=11)
		_ = mode_rail.mode_rail(ctx, "Incident response", &app.attention, app.recipe,
			key=ui.key_u64(200), instance_id=22, tone=.Attention)
		_ = mode_rail.mode_rail(ctx, "Custom response", &app.custom, app.recipe,
			key=ui.key_u64(300), instance_id=33, overrides=app.custom_style)
		ui.text(ctx,
			"Each option keeps Button keyboard, focus, disabled, and Press semantics. The selected marker changes size as well as color.",
			size=13,
		)
		alicorn.surface_end(ctx)
	}
	alicorn.style_environment_pop(ctx, scope)
}

build :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	_logical_width, _logical_height: int,
	_dpi_scale: f32,
) -> alicorn.Node_ID {
	app := cast(^App)state
	ctx, should_build := alicorn.begin_frame(rt)
	if !should_build { return 0 }

	root := alicorn.container_begin(&ctx, .Root, key="alicorn.ui.root", label="ui-root",
		style=ui.layout_style(.Column, grow=1))
	render_contents(app, &ctx)
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	return root
}

main :: proc() {
	app := App{
		standard=mode_rail.State{selected=.Balanced},
		attention=mode_rail.State{selected=.Urgent},
		custom=mode_rail.State{selected=.Balanced, disabled={true, false, false}},
		recipe=mode_rail.recipe_default(),
		custom_style=mode_rail.Instance_Overrides{
			indicator_role=alicorn.style_extension_color_role_id("app.example", "custom_indicator"),
			container_height=268,
			container_padding=15,
			container_corner_radius=22,
			option_corner_radius=22,
			option_button_height=46,
			indicator_width=34,
			indicator_height=8,
			indicator_corner_radius=4,
			label_size=20,
			detail_size=15,
		},
	}
	ui.run(&app, render_contents,
		title="Alicorn · Third-Party Component",
		width=960,
		height=1100,
		on_initialize=initialize_app,
	)
}
