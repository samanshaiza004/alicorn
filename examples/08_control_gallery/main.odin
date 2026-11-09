package main

// 08 · Control Gallery demonstrates color-only live theme editing through
// Alicorn's domain-aware runtime theme replacement API.

import "core:fmt"
import "core:mem"
import "core:os"
import "core:sync"
import "core:thread"
import "core:time"
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
	theme_generation: u64,
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
		gallery_status_set(app, "The theme must contain at least one color token.")
		return
	}
	if app.active_output.ok && !theme.theme_preview_structure_compatible(app.active_output, candidate^) {
		gallery_status_set(app, "Rejected: token names, bindings, lengths, recipes, and materials must stay fixed.")
		return
	}
	runtime_theme, adapted := theme.theme_runtime_style_theme(candidate.compiled, app.allocator)
	if !adapted {
		gallery_status_set(app, "Theme compiled but could not adapt to Alicorn's runtime style contract.")
		return
	}
	defer theme.theme_runtime_style_theme_destroy(&runtime_theme, app.allocator)
	// The Gallery is the opt-in dogfood surface. Three flat Button recipes use
	// distinct timing policies; other controls retain immediate style updates.
	durations := [3]time.Duration{
		time.Duration(120)*time.Millisecond,
		time.Duration(180)*time.Millisecond,
		time.Duration(300)*time.Millisecond,
	}
	button_variants := [3]alicorn.Button_Variant{.Default, .Primary, .Toolbar}
	for variant in 0..<len(durations) {
		duration := durations[variant]
		button_variant := button_variants[variant]
		recipe := runtime_theme.button_recipes.recipes[int(button_variant)]
		recipe.hover_fill_transition = alicorn.Style_Transition{
			duration=duration,
			easing=.Ease,
		}
		runtime_theme.button_recipes.recipes[int(button_variant)] = recipe
	}

	if app.active_output.ok {
		switch alicorn.style_theme_replace(rt, app.registered_theme, runtime_theme) {
		case .Rejected:
			gallery_status_set(app, "Alicorn rejected the candidate; the last good theme remains active.")
			return
		case .Unchanged:
			gallery_status_set(app, "Theme is unchanged; the last good theme remains active.")
		case .Replaced:
			app.theme_generation += 1
			if app.theme_generation == 0 { app.theme_generation = 1 }
			gallery_status_set(app, fmt.tprintf("Applied theme generation %d.", app.theme_generation))
		}
	} else {
		registered := alicorn.style_theme_register(rt, runtime_theme)
		if registered == 0 {
			gallery_status_set(app, "Alicorn rejected the initial runtime theme.")
			return
		}
		app.registered_theme = registered
		app.theme_generation = 1
		gallery_status_set(app, "Theme loaded. Edit colors in theme.json and choose Reload Theme.")
	}

	theme.theme_json_compile_output_destroy(&app.active_output, app.allocator)
	app.active_output = candidate^
	candidate^ = theme.Theme_JSON_Compile_Output{}
	return true
}

render :: proc(app: ^App, ctx: ^ui.UI) {
	preview_scope := alicorn.Style_Environment_Scope{}
	if app.registered_theme != 0 {
		preview_scope = alicorn.style_environment_push(ctx, alicorn.Style_Environment{theme=app.registered_theme})
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
		ui.text(ctx, "Opt-in Button hover fill · CSS Ease")
		if ui.row(ctx, gap=8) {
			_ = ui.button(ctx, "120 ms", key=alicorn.key_string("gallery-transition-120"),
				height=32, variant=.Default)
			_ = ui.button(ctx, "180 ms", key=alicorn.key_string("gallery-transition-180"),
				height=32, variant=.Primary)
			_ = ui.button(ctx, "300 ms", key=alicorn.key_string("gallery-transition-300"),
				height=32, variant=.Toolbar)
			_ = ui.button(ctx, "Immediate", key=alicorn.key_string("gallery-transition-immediate"),
				height=32, variant=.Quiet)
		}

		if ui.row(ctx, gap=10, align=.Center) {
			if ui.button(ctx, "Reload Theme", key=alicorn.key_string("gallery-reload-theme"),
				state=ui.Button_State{disabled=app.compiling}, width=132, height=32, variant=.Primary) {
				gallery_start_compile(app)
			}
			if app.registered_theme != 0 {
				ui.text(ctx, fmt.tprintf("Theme generation %d", app.theme_generation))
				_ = ui.box(ctx, key=alicorn.key_string("gallery-accent-swatch"), width=34, height=22,
					fill=alicorn.style_color(ctx, .Accent), radius=3)
			} else {
			ui.text(ctx, "Theme loading…")
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
			gallery_status_set(app, "Theme candidate was not applied; last good theme remains active.")
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
