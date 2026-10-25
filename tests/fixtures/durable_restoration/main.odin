package main

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import alicorn "../../../runtime"

// An application schema. No Runtime, Node_ID, token, or derived text/geometry
// product crosses the file boundary. The version belongs to this application.
Session :: struct {
	version: int,
	split_ratio: f32,
	scroll_y: f32,
	focused_record: u64,
}

App :: struct {
	saved: Session,
	loaded: bool,
	started: bool,
	token: alicorn.Restore_Token,
	split, scroll: alicorn.Node_ID,
	first, last: int,
	count: int,
}

DEFAULT_SESSION :: Session{version=1, split_ratio=0.3}
ROW_HEIGHT :: f32(24)
DIVIDER_WIDTH :: f32(2)
RECORD_NAMESPACE :: u64(40)

load_session :: proc(path: string) -> (saved: Session, loaded: bool) {
	saved = DEFAULT_SESSION
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil { return }
	defer delete(data, context.temp_allocator)
	decoded: Session
	if len(data) > 4096 || json.unmarshal(data, &decoded, allocator=context.temp_allocator) != nil || decoded.version != 1 { return }
	if math.is_nan(decoded.split_ratio) || math.is_inf(decoded.split_ratio) ||
	   math.is_nan(decoded.scroll_y) || math.is_inf(decoded.scroll_y) { return }
	decoded.split_ratio = clamp(decoded.split_ratio, 0, 1)
	decoded.scroll_y = max(decoded.scroll_y, 0)
	return decoded, true
}

save_session :: proc(path: string, saved: Session) -> bool {
	data, err := json.marshal(saved, allocator=context.temp_allocator)
	if err != nil { return false }
	defer delete(data, context.temp_allocator)
	return os.write_entire_file(path, data) == nil
}

build_app :: proc(state: rawptr, rt: ^alicorn.Runtime, width, height: int, dpi: f32) -> alicorn.Node_ID {
	app := cast(^App)state
	ui, build := alicorn.begin_frame(rt)
	if !build { return 0 }
	if !app.started {
		app.started = true
		app.token = alicorn.restore_token_next(rt)
	}
	split_request := alicorn.Split_Restore_Request{}
	scroll_request := alicorn.Scroll_Restore_Request{}
	if app.loaded {
		// This example's root fills the window with no padding. Other apps may
		// prefer to persist split_state().preferred_position in logical units.
		split_request = alicorn.Split_Restore_Request{token=app.token, preferred_position=app.saved.split_ratio*max(f32(width)-DIVIDER_WIDTH, 0)}
		scroll_request = alicorn.Scroll_Restore_Request{token=app.token, offset_y=app.saved.scroll_y}
	}
	root := alicorn.container_begin(&ui, .Root, key=alicorn.key_string("restoration-root"), style=alicorn.layout_style(.Row, grow=1, clip=true))
	split := alicorn.split_begin(&ui, alicorn.key_string("sidebar"), .Horizontal, 180, min_first=80, min_second=80, restore=split_request)
	app.split = split.id
	alicorn.split_first_begin(&ui, split)
	alicorn.text(&ui, "Drag the split, scroll, and select a record. Close and rerun with the same session path.", style=alicorn.layout_style(height=120), text_style=alicorn.Text_Style{overflow=.Wrap})
	alicorn.split_first_end(&ui, split)
	alicorn.split_divider(&ui, split, thickness=DIVIDER_WIDTH)
	alicorn.split_second_begin(&ui, split)
	list := alicorn.virtual_list_begin(&ui, app.count, ROW_HEIGHT, key=alicorn.key_string("records"), style=alicorn.layout_style(grow=1, clip=true), focusable=true, restore=scroll_request)
	app.scroll, app.first, app.last = list.scroll.id, list.first, list.last
	if app.loaded && app.saved.focused_record > 0 && app.saved.focused_record <= u64(app.count) {
		_ = alicorn.semantic_focus_restore_request(rt, alicorn.Semantic_ID{RECORD_NAMESPACE, app.saved.focused_record}, list.scroll.id, app.token)
	}
	for index := list.first; index < list.last; index += 1 {
		identity := alicorn.Semantic_ID{RECORD_NAMESPACE, u64(index+1)}
		selected := alicorn.semantic_focus_state(rt).id == identity
		if alicorn.button(&ui, fmt.tprintf("Record %d", index+1), key=alicorn.key_u64(u64(index+1)), style=alicorn.layout_style(height=ROW_HEIGHT), state=alicorn.Button_State{selected=selected}) {
			_ = alicorn.semantic_focus_set(rt, identity, list.scroll.id)
			_ = alicorn.focus(rt, list.scroll.id)
		}
		_ = alicorn.semantic_bind(&ui, identity)
	}
	alicorn.virtual_list_end(&ui, list)
	alicorn.split_second_end(&ui, split)
	alicorn.split_end(&ui, split)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return root
}

snapshot :: proc(app: ^App, rt: ^alicorn.Runtime) -> Session {
	split, ok := alicorn.split_state(rt, app.split)
	if !ok { return DEFAULT_SESSION }
	ratio := split.preferred_position / max(split.bounds.w-DIVIDER_WIDTH, 1)
	return Session{1, ratio, alicorn.scroll_region_state(rt, app.scroll).offset_y, alicorn.semantic_focus_state(rt).id.value}
}

// Run this mode twice to prove serialization across OS process lifetimes.
// --write creates app state; --read restores it; --short clamps shrunken data.
restart_check :: proc(mode, path: string) -> bool {
	app := App{saved=DEFAULT_SESSION, count=10000}
	if mode != "--write" { app.saved, app.loaded = load_session(path) }
	if mode == "--short" { app.count = 2 }
	width := 800
	if mode == "--narrow" { width = 200 }
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, f32(width), 240})
	defer alicorn.destroy_runtime(&rt)
	_ = build_app(&app, &rt, width, 240, 1)
	if mode == "--write" {
		_ = alicorn.scroll_region_set_offset(&rt, app.scroll, 8400)
		_ = alicorn.semantic_focus_set(&rt, alicorn.Semantic_ID{RECORD_NAMESPACE, 351}, app.scroll)
		alicorn.invalidate_root(&rt, "application changed view")
		_ = build_app(&app, &rt, width, 240, 1)
		return save_session(path, snapshot(&app, &rt))
	}
	{
		_ = build_app(&app, &rt, width, 240, 1)
	}
	scroll := alicorn.scroll_region_state(&rt, app.scroll)
	state, found := alicorn.restore_state_query(&rt, .Scroll, app.scroll, app.token)
	ok := app.loaded && found && state.outcome == .Applied && scroll.offset_y == 8400 && app.last-app.first < 30
	if mode == "--short" { ok = app.loaded && found && state.outcome == .Clamped && scroll.offset_y == 0 && app.last == 2 }
	if mode == "--read" {
		focus := alicorn.semantic_focus_state(&rt)
		ok = ok && focus.id.value == 351 && focus.realized_node != 0
	}
	split, split_ok := alicorn.split_state(&rt, app.split)
	if mode == "--read" { ok = ok && split_ok && math.abs(split.position-180) < 0.016 }
	if mode == "--narrow" {
		report, reported := alicorn.restore_state_query(&rt, .Split, app.split, app.token)
		ok = ok && reported && report.outcome == .Clamped && split.position == 80 && split.preferred_position < 80
	}
	if mode == "--defaults" { ok = !app.loaded && !found && scroll.offset_y == 0 && split_ok && split.position == 180 }
	// Once settled, a pending/unavailable semantic target must not poll.
	_, builds := alicorn.begin_frame(&rt)
	ok = ok && !builds
	fmt.printf("restart %s: ok=%t scroll=%.1f range=%d..%d outcome=%v\n", mode, ok, scroll.offset_y, app.first, app.last, state.outcome)
	return ok
}

main :: proc() {
	if len(os.args) == 3 {
		if !restart_check(os.args[1], os.args[2]) { os.exit(1) }
		return
	}
	fmt.println("Usage: durable_restoration --write|--read|--short|--narrow|--defaults session.json")
}
