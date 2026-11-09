package main

// 10 · Live Theme is an explicit development-only theme-editing dogfood.
// Without --live-theme it starts no worker. With a source path, a sleeping
// worker debounces metadata changes, compiles through Alicorn's strict JSON
// parser/compiler, and posts one owned last-good candidate to the UI thread.

import odin_runtime "base:runtime"
import "core:fmt"
import "core:os"
import "core:sync"
import "core:thread"
import "core:time"
import alicorn "alicorn:runtime"
import theme "alicorn:theme"
import ui "alicorn:ui"

LIVE_THEME_POLL_INTERVAL :: 80 * time.Millisecond
LIVE_THEME_DEBOUNCE :: 240 * time.Millisecond
LIVE_THEME_MAX_SOURCE_BYTES :: i64(1024 * 1024)

File_Stamp :: struct {
	size: i64,
	modified_ns: i64,
}

Live_Candidate :: struct {
	style: alicorn.Style_Theme,
	has_style: bool,
	diagnostic: string,
	signature: u64,
	source_bytes: i64,
	change_detected_unix_ns: i64,
	compile_duration: time.Duration,
	compiled_at_unix_ns: i64,
}

App :: struct {
	theme_path: string,
	theme_id: alicorn.Style_Theme_ID,
	theme_signature: u64,
	status: string,
	status_owned: bool,
	worker: ^thread.Thread,
	waker: ui.Application_Waker,
	mutex: sync.Mutex,
	stop_requested: bool,
	candidate_ready: bool,
	candidate: Live_Candidate,
}

file_stamp_read :: proc(path: string, allocator: odin_runtime.Allocator) -> (stamp: File_Stamp, ok: bool) {
	info, err := os.stat(path, allocator)
	if err != nil { return {}, false }
	defer os.file_info_delete(info, allocator)
	return File_Stamp{
		size=info.size,
		modified_ns=time.to_unix_nanoseconds(info.modification_time),
	}, true
}

file_stamp_equal :: proc(a, b: File_Stamp) -> bool {
	return a.size == b.size && a.modified_ns == b.modified_ns
}

live_candidate_destroy :: proc(candidate: ^Live_Candidate, allocator: odin_runtime.Allocator) {
	if candidate == nil { return }
	if candidate.has_style { theme.theme_runtime_style_theme_destroy(&candidate.style, allocator) }
	delete(candidate.diagnostic, allocator)
	candidate^ = Live_Candidate{}
}

live_candidate_error :: proc(path: string, line, column: u32, message: string, allocator: odin_runtime.Allocator) -> Live_Candidate {
	return Live_Candidate{
		diagnostic=fmt.aprintf("%s:%d:%d: %s", path, line, column, message, allocator=allocator),
	}
}

live_theme_compile :: proc(path: string, allocator: odin_runtime.Allocator) -> Live_Candidate {
	data, read_error := os.read_entire_file(path, allocator)
	if read_error != nil {
		return live_candidate_error(path, 1, 1, "could not read theme source", allocator)
	}
	defer delete(data, allocator)

	parsed := theme.theme_json_parse(string(data), path, allocator)
	defer theme.theme_json_output_destroy(&parsed, allocator)
	if !parsed.ok {
		if len(parsed.diagnostics) > 0 {
			diagnostic := parsed.diagnostics[0]
			return live_candidate_error(path, diagnostic.span.line, diagnostic.span.column, diagnostic.message, allocator)
		}
		return live_candidate_error(path, 1, 1, "theme JSON is invalid", allocator)
	}
	if parsed.extends != "" && parsed.extends != "alicorn.base" {
		span := parsed.source.metadata.span
		return live_candidate_error(path, span.line, span.column, "only extends = alicorn.base is supported", allocator)
	}

	base := theme.theme_builtin_base_source_create(allocator)
	defer theme.theme_builtin_base_source_destroy(&base, allocator)
	compiled := theme.theme_compile({base.model, parsed.source},
		support=theme.THEME_COMPILER_SUPPORT, allocator=allocator)
	defer theme.theme_output_destroy(&compiled, allocator)
	if !compiled.ok {
		if len(compiled.diagnostics) > 0 {
			diagnostic := compiled.diagnostics[0]
			message := fmt.aprintf("theme compile rejected candidate (%v)", diagnostic.code, allocator=allocator)
			result := live_candidate_error(diagnostic.path, diagnostic.span.line, diagnostic.span.column, message, allocator)
			delete(message, allocator)
			return result
		}
		return live_candidate_error(path, 1, 1, "theme compiler rejected candidate", allocator)
	}

	style, style_ok := theme.theme_runtime_style_theme(compiled, allocator)
	if !style_ok {
		return live_candidate_error(path, 1, 1, "compiled theme does not fit the current runtime style contract", allocator)
	}
	materials, materials_ok := theme.theme_runtime_style_materials(compiled, allocator)
	theme.theme_runtime_style_materials_destroy(&materials, allocator)
	if !materials_ok {
		theme.theme_runtime_style_theme_destroy(&style, allocator)
		return live_candidate_error(path, 1, 1, "compiled materials do not fit the current runtime style contract", allocator)
	}
	return Live_Candidate{style=style, has_style=true, signature=compiled.theme.content_signature}
}

live_candidate_publish :: proc(app: ^App, candidate: Live_Candidate) {
	sync.mutex_lock(&app.mutex)
	if app.stop_requested {
		sync.mutex_unlock(&app.mutex)
		candidate_to_destroy := candidate
		live_candidate_destroy(&candidate_to_destroy, odin_runtime.heap_allocator())
		return
	}
	if app.candidate_ready { live_candidate_destroy(&app.candidate, odin_runtime.heap_allocator()) }
	app.candidate = candidate
	app.candidate_ready = true
	sync.mutex_unlock(&app.mutex)
	ui.wake(app.waker)
}

watch_theme_file :: proc(data: rawptr) {
	context.allocator = odin_runtime.heap_allocator()
	app := cast(^App)data
	allocator := odin_runtime.heap_allocator()
	observed: File_Stamp
	attempted: File_Stamp
	change_detected_unix_ns: i64
	stable_since := time.now()
	for {
		sync.mutex_lock(&app.mutex)
		stopping := app.stop_requested
		sync.mutex_unlock(&app.mutex)
		if stopping { break }

		stamp, exists := file_stamp_read(app.theme_path, allocator)
		if !exists {
			observed, attempted = {}, {}
		} else {
			if !file_stamp_equal(stamp, observed) {
				observed = stamp
				stable_since = time.now()
				change_detected_unix_ns = time.to_unix_nanoseconds(stable_since)
			}
			if !file_stamp_equal(stamp, attempted) && time.diff(stable_since, time.now()) >= LIVE_THEME_DEBOUNCE {
				compile_started := time.now()
				candidate: Live_Candidate
				if stamp.size > LIVE_THEME_MAX_SOURCE_BYTES {
					candidate = live_candidate_error(app.theme_path, 1, 1, "theme source exceeds the 1 MiB development limit", allocator)
				} else {
					candidate = live_theme_compile(app.theme_path, allocator)
				}
				candidate.source_bytes = stamp.size
				candidate.change_detected_unix_ns = change_detected_unix_ns
				candidate.compile_duration = time.diff(compile_started, time.now())
				candidate.compiled_at_unix_ns = time.to_unix_nanoseconds(time.now())
				latest, still_exists := file_stamp_read(app.theme_path, allocator)
				if still_exists && file_stamp_equal(stamp, latest) {
					attempted = stamp
					live_candidate_publish(app, candidate)
				} else {
					live_candidate_destroy(&candidate, allocator)
					observed = latest
					stable_since = time.now()
				}
			}
		}
		time.sleep(LIVE_THEME_POLL_INTERVAL)
	}
}

render :: proc(app: ^App, ctx: ^ui.UI) {
	if ui.column(ctx, grow=1, padding=24, gap=14) {
		ui.text(ctx, "10 · Live Theme", size=24)
		ui.text(ctx, "Edit the opted-in JSON file. Invalid saves keep the last good theme.")
		if ui.panel(ctx, grow=1, padding=20, gap=12, label="live-theme-preview") {
			scope := alicorn.Style_Environment_Scope{}
			if app.theme_id != 0 {
				scope = alicorn.style_environment_push(ctx, alicorn.Style_Environment{theme=app.theme_id})
			}
			ui.text(ctx, "Theme preview", size=22)
			ui.text(ctx, "Palette and button recipe edits repaint this retained preview.")
			if ui.row(ctx, gap=10) {
				ui.button(ctx, "Primary action", variant=.Primary)
				ui.button(ctx, "Quiet action", variant=.Quiet)
			}
			if scope.active { alicorn.style_environment_pop(ctx, scope) }
		}
		if app.status != "" { ui.text(ctx, app.status) }
		if app.theme_path == "" {
			ui.text(ctx, "Watcher disabled. Run with --live-theme <path> to opt in.")
		} else if app.theme_id == 0 {
			ui.text(ctx, "Waiting for the first valid theme compile…")
		} else {
			ui.text(ctx, "Last-good theme is active; save the file to apply changes.")
		}
		if app.theme_path != "" { ui.text(ctx, fmt.tprintf("Watching: %s", app.theme_path)) }
	}
}

start_app :: proc(app: ^App, waker: ui.Application_Waker) {
	app.waker = waker
	if app.theme_path == "" { return }
	app.worker = thread.create_and_start_with_data(rawptr(app), watch_theme_file, name="alicorn-live-theme")
	if app.worker == nil { app.status = "Could not start the opt-in theme watcher." }
}

wake_app :: proc(app: ^App, ctx: ui.Application_Context) {
	sync.mutex_lock(&app.mutex)
	if !app.candidate_ready {
		sync.mutex_unlock(&app.mutex)
		return
	}
	candidate := app.candidate
	app.candidate = {}
	app.candidate_ready = false
	sync.mutex_unlock(&app.mutex)

	accepted := false
	registered_now := false
	unchanged := false
	if candidate.has_style {
		rt := cast(^alicorn.Runtime)ctx
		if app.theme_id == 0 {
			app.theme_id = alicorn.style_theme_register(rt, candidate.style)
			accepted = app.theme_id != 0
			registered_now = accepted
		} else {
			replacement := alicorn.style_theme_replace(rt, app.theme_id, candidate.style)
			accepted = replacement == .Replaced
			unchanged = replacement == .Unchanged
		}
	}
	status_changed := false
	if candidate.has_style && accepted {
		app.theme_signature = candidate.signature
		status_changed = live_status_clear(app)
		now_ns := time.to_unix_nanoseconds(time.now())
		adoption_delay_ns := now_ns - candidate.compiled_at_unix_ns
		change_to_adoption_ns := now_ns - candidate.change_detected_unix_ns
		fmt.println("[live-theme] applied signature=", candidate.signature,
			" source_bytes=", candidate.source_bytes, " compile=", candidate.compile_duration,
			" change_detected_to_adoption_ns=", change_to_adoption_ns,
			" compile_to_adoption_ns=", adoption_delay_ns)
	} else if candidate.has_style && unchanged {
		app.theme_signature = candidate.signature
		status_changed = live_status_clear(app)
		fmt.println("[live-theme] valid candidate produced no runtime changes; source_bytes=",
			candidate.source_bytes, " compile=", candidate.compile_duration)
	} else if candidate.has_style {
		live_status_set(app, "Runtime rejected the candidate; the previous last-good theme remains active.")
		status_changed = true
	} else {
		fmt.println("[live-theme] rejected; last-good theme retained: ", candidate.diagnostic)
		live_status_set_owned(app, candidate.diagnostic)
		candidate.diagnostic = ""
		status_changed = true
	}
	live_candidate_destroy(&candidate, odin_runtime.heap_allocator())
	if registered_now {
		// The first accepted candidate gives the following description a stable
		// theme ID to scope the preview under.
		ui.invalidate(ctx, "initial live theme registered")
	} else if status_changed {
		// Paint-only replacements already request presentation in the runtime;
		// rebuild the application only when visible diagnostic text changes.
		ui.invalidate(ctx, "live theme diagnostic changed")
	}
}

live_status_set :: proc(app: ^App, value: string) {
	if app.status_owned { delete(app.status, odin_runtime.heap_allocator()) }
	app.status = value
	app.status_owned = false
}

live_status_set_owned :: proc(app: ^App, value: string) {
	if app.status_owned { delete(app.status, odin_runtime.heap_allocator()) }
	app.status = value
	app.status_owned = value != ""
}

live_status_clear :: proc(app: ^App) -> (changed: bool) {
	changed = app.status != ""
	if app.status_owned { delete(app.status, odin_runtime.heap_allocator()) }
	app.status = ""
	app.status_owned = false
	return
}

stop_app :: proc(app: ^App) {
	if app.worker != nil {
		sync.mutex_lock(&app.mutex)
		app.stop_requested = true
		sync.mutex_unlock(&app.mutex)
		thread.join(app.worker)
		thread.destroy(app.worker)
		app.worker = nil
	}
	if app.candidate_ready { live_candidate_destroy(&app.candidate, odin_runtime.heap_allocator()) }
	if app.status_owned { delete(app.status, odin_runtime.heap_allocator()) }
}

main :: proc() {
	theme_path := ""
	for index := 1; index < len(os.args); index += 1 {
		if os.args[index] == "--live-theme" {
			if index+1 >= len(os.args) || os.args[index+1] == "" {
				fmt.eprintln("usage: 10_live_theme [--live-theme <theme.json>]")
				os.exit(2)
			}
			theme_path = os.args[index+1]
			index += 1
		} else {
			fmt.eprintln("unknown option:", os.args[index])
			fmt.eprintln("usage: 10_live_theme [--live-theme <theme.json>]")
			os.exit(2)
		}
	}
	status := "Watcher disabled; the preview uses Alicorn's built-in theme."
	if theme_path != "" { status = "Waiting for the first valid theme compile…" }
	app := App{theme_path=theme_path, status=status}
	ui.run(&app, render, title="Alicorn · Live Theme", width=720, height=520,
		on_start=start_app, on_wake=wake_app, on_stop=stop_app)
}
