package main

// 08 · Control Gallery demonstrates the bounded, development-only live theme
// preview. Normal application themes remain immutable registrations.

import "core:fmt"
import "core:mem"
import "core:os"
import "core:sync"
import "core:thread"
import alicorn "alicorn:runtime"
import theme "alicorn:theme"
import ui "alicorn:ui"

CONTROL_GALLERY_THEME_PATH :: "examples/08_control_gallery/theme.json"

App :: struct {
	searches: int,
	allocator: mem.Allocator,
	waker: ui.Application_Waker,
	worker: ^thread.Thread,
	completion_mutex: sync.Mutex,
	compiling: bool,
	worker_complete: bool,
	read_failed: bool,
	candidate: theme.Theme_JSON_Compile_Output,
	active_output: theme.Theme_JSON_Compile_Output,
	registered_theme: alicorn.Style_Theme_ID,
	preview: alicorn.Style_Theme_Preview_ID,
	status: [256]u8,
	status_len: int,
}

gallery_status_set :: proc(app: ^App, message: string) {
	if app == nil { return }
	app.status_len = min(len(message), len(app.status))
	copy(app.status[:app.status_len], message[:app.status_len])
}

gallery_status_text :: proc(app: ^App) -> string {
	if app == nil { return "" }
	return string(app.status[:app.status_len])
}

gallery_compile_theme_worker :: proc(data: rawptr) {
	app := cast(^App)data
	allocator := app.allocator
	output := theme.Theme_JSON_Compile_Output{}
	read_failed := false
	bytes, err := os.read_entire_file(CONTROL_GALLERY_THEME_PATH, allocator)
	if err != nil {
		read_failed = true
	} else {
		output = theme.theme_compile_json(string(bytes), CONTROL_GALLERY_THEME_PATH, allocator)
		delete(bytes, allocator)
	}
	sync.mutex_lock(&app.completion_mutex)
	app.candidate = output
	app.read_failed = read_failed
	app.worker_complete = true
	sync.mutex_unlock(&app.completion_mutex)
	ui.wake(app.waker)
}

gallery_start_compile :: proc(app: ^App) {
	if app == nil || app.worker != nil { return }
	app.compiling = true
	gallery_status_set(app, "Compiling theme; the last good palette stays active.")
	app.worker = thread.create_and_start_with_data(
		rawptr(app), gallery_compile_theme_worker, name="alicorn-gallery-theme-compiler",
	)
	if app.worker == nil {
		app.compiling = false
		gallery_status_set(app, "Could not start the theme compiler worker.")
	}
}

gallery_compile_error_text :: proc(output: ^theme.Theme_JSON_Compile_Output) -> string {
	if output == nil { return "Theme compilation failed; the last good palette remains active." }
	if output.unsupported_extends { return "Only extends: alicorn.base is supported by the preview." }
	if len(output.parsed.diagnostics) > 0 {
		diagnostic := output.parsed.diagnostics[0]
		return fmt.tprintf("%s:%d:%d: %s", diagnostic.span.path, diagnostic.span.line, diagnostic.span.column, diagnostic.message)
	}
	if len(output.compiled.diagnostics) > 0 {
		diagnostic := output.compiled.diagnostics[0]
		return fmt.tprintf("%s:%d:%d: theme rejected (%v)", diagnostic.path, diagnostic.span.line, diagnostic.span.column, diagnostic.code)
	}
	return "Theme compilation failed; the last good palette remains active."
}

gallery_adopt_candidate :: proc(app: ^App, rt: ^alicorn.Runtime, candidate: ^theme.Theme_JSON_Compile_Output) -> (applied: bool) {
	if app == nil || rt == nil || candidate == nil || !candidate.ok { return }
	if len(candidate.compiled.theme.colors) == 0 {
		gallery_status_set(app, "The preview theme must contain at least one color token.")
		return
	}

	if app.active_output.ok {
		if !theme.theme_preview_structure_compatible(app.active_output, candidate^) {
			gallery_status_set(app, "Rejected: token names, bindings, lengths, recipes, and materials must stay fixed.")
			return
		}
		colors := make([]alicorn.Color, len(candidate.compiled.theme.colors), allocator=app.allocator)
		defer delete(colors, app.allocator)
		for color, index in candidate.compiled.theme.colors {
			colors[index] = alicorn.Color{color.r, color.g, color.b, color.a}
		}
		result := alicorn.style_theme_preview_replace_colors(rt, app.preview, colors)
		if result == .Rejected {
			gallery_status_set(app, "Rejected: Alicorn could not apply the color vector.")
			return
		}
		if result == .Unchanged {
			gallery_status_set(app, "Theme is unchanged; the active preview was kept.")
		} else {
			gallery_status_set(app, fmt.tprintf("Applied preview generation %d.", alicorn.style_theme_preview_generation(rt, app.preview)))
		}
	} else {
		runtime_theme, adapted := theme.theme_runtime_style_theme(candidate.compiled, app.allocator)
		if !adapted {
			gallery_status_set(app, "Theme compiled but could not adapt to Alicorn's runtime style contract.")
			return
		}
		defer theme.theme_runtime_style_theme_destroy(&runtime_theme, app.allocator)
		registered := alicorn.style_theme_register(rt, runtime_theme)
		if registered == 0 {
			gallery_status_set(app, "Alicorn rejected the initial runtime theme; no preview was installed.")
			return
		}
		preview := alicorn.style_theme_preview_begin(rt, registered)
		if preview == 0 {
			gallery_status_set(app, "Alicorn could not create its bounded preview slot.")
			return
		}
		app.registered_theme = registered
		app.preview = preview
		gallery_status_set(app, "Theme loaded. Edit colors in theme.json and choose Reload Theme.")
	}

	theme.theme_json_compile_output_destroy(&app.active_output, app.allocator)
	app.active_output = candidate^
	candidate^ = theme.Theme_JSON_Compile_Output{}
	return true
}

render :: proc(app: ^App, ctx: ^ui.UI) {
	preview_scope := alicorn.Style_Environment_Scope{}
	if app.preview != 0 {
		preview_scope = alicorn.style_environment_push(ctx, alicorn.Style_Environment{
			theme=app.registered_theme,
			preview=app.preview,
		})
	}
	if ui.panel(ctx, grow=1, padding=24, gap=12) {
		ui.text(ctx, "08 · Control Gallery", size=24)
		ui.text(ctx, "Font-independent icons and named icon buttons.")

		if ui.row(ctx, gap=20) {
			if ui.column(ctx, gap=8) {
				ui.icon(ctx, .Folder_Closed, size=24)
				ui.text(ctx, "Folder")
			}
			if ui.column(ctx, gap=8) {
				ui.icon(ctx, .Folder_Open, size=24)
				ui.text(ctx, "Open folder")
			}
			if ui.column(ctx, gap=8) {
				ui.icon(ctx, .Search, size=24)
				ui.text(ctx, "Search")
			}
		}

		if ui.row(ctx, gap=8) {
			if ui.icon_button(ctx, "Search", .Search) { app.searches += 1 }
			ui.text(ctx, fmt.tprintf("Search activations: %d", app.searches))
		}

		if ui.row(ctx, gap=10, align=.Center) {
			if ui.button(ctx, "Reload Theme", key=alicorn.key_string("gallery-reload-theme"),
				state=ui.Button_State{disabled=app.compiling}, width=132, height=32, variant=.Primary) {
				gallery_start_compile(app)
			}
			if app.preview != 0 {
				ui.text(ctx, fmt.tprintf("Preview generation %d", alicorn.style_theme_preview_generation(ctx.runtime, app.preview)))
				_ = ui.box(ctx, key=alicorn.key_string("gallery-accent-swatch"), width=34, height=22,
					fill=alicorn.style_color(ctx, .Accent), radius=3)
			} else {
				ui.text(ctx, "Preview loading…")
			}
		}
		ui.text(ctx, gallery_status_text(app), style=alicorn.layout_style(height=28))
		ui.text(ctx, "Color values can change. Token names, role bindings, lengths, recipes, and materials stay fixed.")
	}
	if preview_scope.active { alicorn.style_environment_pop(ctx, preview_scope) }
}

start_app :: proc(app: ^App, waker: ui.Application_Waker) {
	app.allocator = context.allocator
	app.waker = waker
	gallery_status_set(app, "Loading the Control Gallery theme…")
	gallery_start_compile(app)
}

wake_app :: proc(app: ^App, ctx: ui.Application_Context) {
	sync.mutex_lock(&app.completion_mutex)
	complete := app.worker_complete
	read_failed := app.read_failed
	candidate := app.candidate
	app.candidate = theme.Theme_JSON_Compile_Output{}
	app.worker_complete = false
	app.read_failed = false
	sync.mutex_unlock(&app.completion_mutex)
	if !complete { return }
	if app.worker != nil {
		thread.join(app.worker)
		thread.destroy(app.worker)
		app.worker = nil
	}
	app.compiling = false
	if read_failed {
		gallery_status_set(app, "Could not read examples/08_control_gallery/theme.json from the repository root.")
	} else if !candidate.ok {
		gallery_status_set(app, gallery_compile_error_text(&candidate))
	} else {
		rt := cast(^alicorn.Runtime)ctx
		applied := gallery_adopt_candidate(app, rt, &candidate)
		if !applied && app.status_len == 0 {
			gallery_status_set(app, "Theme candidate was not applied; last good preview remains active.")
		}
	}
	theme.theme_json_compile_output_destroy(&candidate, app.allocator)
	ui.invalidate(ctx, "Control Gallery theme compilation completed")
}

stop_app :: proc(app: ^App) {
	if app.worker != nil {
		thread.join(app.worker)
		thread.destroy(app.worker)
		app.worker = nil
	}
	theme.theme_json_compile_output_destroy(&app.candidate, app.allocator)
	theme.theme_json_compile_output_destroy(&app.active_output, app.allocator)
}

main :: proc() {
	app := App{}
	ui.run(&app, render, title="Alicorn Control Gallery", width=720, height=440,
		on_start=start_app, on_wake=wake_app, on_stop=stop_app)
}
