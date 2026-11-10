package main

// 11 · Third-Party Component proves that an application package can provide
// its own typed recipe, adaptive presentation, accessible semantics, and
// interruptible motion using Alicorn's public UI/runtime APIs.

import "core:fmt"
import "core:os"
import alicorn "alicorn:runtime"
import host "alicorn:native/sdl_gpu"
import mode_rail "./mode_rail"
import theme "alicorn:theme"
import ui "alicorn:ui"

THEME_PATH :: "examples/11_third_party_component/theme.json"

App :: struct {
	standard: mode_rail.State,
	attention: mode_rail.State,
	recipe: mode_rail.Recipe,
	theme_id: alicorn.Style_Theme_ID,
	canvas_role: alicorn.Style_Extension_Color_Role_ID,
	theme_error: bool,
}

initialize :: proc(state: rawptr, rt: ^alicorn.Runtime) {
	app := cast(^App)state
	bytes, read_error := os.read_entire_file(THEME_PATH, context.allocator)
	if read_error != nil {
		fmt.println("Could not read component theme:", THEME_PATH, read_error)
		app.theme_error = true
		return
	}
	defer delete(bytes, context.allocator)

	compiled := theme.theme_compile_json(string(bytes), THEME_PATH)
	defer theme.theme_json_compile_output_destroy(&compiled)
	if !compiled.ok {
		if len(compiled.parsed.diagnostics) > 0 {
			diagnostic := compiled.parsed.diagnostics[0]
			fmt.println("Theme error", diagnostic.span.line, diagnostic.span.column, diagnostic.message)
		} else if len(compiled.compiled.diagnostics) > 0 {
			diagnostic := compiled.compiled.diagnostics[0]
			fmt.println("Theme rejected", diagnostic.span.line, diagnostic.span.column, diagnostic.code)
		} else {
			fmt.println("The component theme could not be compiled.")
		}
		app.theme_error = true
		return
	}

	runtime_theme, adapted := theme.theme_runtime_style_theme(compiled.compiled)
	if !adapted {
		fmt.println("The compiled theme could not be adapted to the runtime style contract.")
		app.theme_error = true
		return
	}
	defer theme.theme_runtime_style_theme_destroy(&runtime_theme)
	app.theme_id = alicorn.style_theme_register(rt, runtime_theme)
	app.canvas_role = alicorn.style_extension_color_role_id("app.example", "window_background")
	if app.theme_id == 0 {
		fmt.println("The Runtime rejected the third-party component theme.")
		app.theme_error = true
	}
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

	root := alicorn.container_begin(&ctx, .Root, label="third-party-component-root",
		style=ui.layout_style(.Column, grow=1))
	// Environment scopes need a described boundary. Keep this after Root so
	// the custom role surfaces below resolve through the registered theme.
	theme_scope := alicorn.Style_Environment_Scope{}
	if app.theme_id != 0 {
		theme_scope = alicorn.style_environment_push(&ctx,
			alicorn.Style_Environment{theme=app.theme_id})
	}
	canvas := alicorn.surface_begin(&ctx,
		alicorn.surface_extension_color_role(app.canvas_role),
		key=ui.key_u64(1),
		style=ui.layout_style(.Column, grow=1, padding=24, gap=14),
		label="component-demo-canvas",
	)
	if canvas != 0 {
		ui.text(&ctx, "Third-party component", size=26)
		ui.text(&ctx,
			"Two instances share one recipe. Resize the window to switch layout; click choices quickly to interrupt the marker motion.",
		)
		if app.theme_error {
			ui.text(&ctx, "Theme loading failed. See the launch output for details.", color=ui.rgb(0xD86E63))
		} else {
			_ = mode_rail.mode_rail(&ctx, "Update cadence", &app.standard, app.recipe,
				key=ui.key_u64(100), tone=.Standard)
			_ = mode_rail.mode_rail(&ctx, "Incident response", &app.attention, app.recipe,
				key=ui.key_u64(200), tone=.Attention)
		}
		ui.text(&ctx,
			"Accessibility: each rail is a named group; options are native Button semantics with selected state and Press action.",
			size=13,
		)
		alicorn.surface_end(&ctx)
	}
	if theme_scope.active { alicorn.style_environment_pop(&ctx, theme_scope) }
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	return root
}

main :: proc() {
	app := App{
		standard=mode_rail.State{selected=.Balanced},
		attention=mode_rail.State{selected=.Urgent},
		recipe=mode_rail.recipe_default(),
		canvas_role=alicorn.style_extension_color_role_id("app.example", "window_background"),
	}
	host.Run(host.Application{
		state=rawptr(&app),
		title="Alicorn · Third-Party Component",
		width=960,
		height=820,
		interaction_update_policy=.Correct_After_Interaction,
		on_initialize=initialize,
		build=build,
	})
}
