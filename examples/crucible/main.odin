package main

import "core:fmt"
import alicorn "../../runtime"

Track :: struct {
	id:       int,
	name:     string,
	muted:    bool,
	meter:    u64,
	revision: u64,
}

Crucible :: struct {
	tracks:    [8]Track,
	compact:   bool,
	surface_frame: u64,
}

render :: proc(rt: ^alicorn.Runtime, app: ^Crucible) {
	alicorn.invalidate_root(rt, "crucible state update")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin(&ui, .Root, label="Alicorn Crucible", style=alicorn.Layout_Style{.Column, -1, -1, 0, -1, 0, -1, 0, 8, 4, .Stretch, true})
	alicorn.text(&ui, "8 tracks / keyed state / deterministic LOD")
	for track in app.tracks {
		if alicorn.key_scope_begin(&ui, alicorn.key_u64(u64(track.id))) {
			if !app.compact {
				alicorn.button(&ui, track.name, state=alicorn.Button_State{selected=track.muted}, style=alicorn.Layout_Style{.Column, -1, 28, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
				region_id, reused := alicorn.region_begin(&ui, "meter", track.revision)
				if region_id != 0 && !reused {
					start := len(rt.pending)
					alicorn.text(&ui, fmt.aprintf("meter %d", track.meter))
					alicorn.region_end(&ui, region_id, false, start)
				}
			} else {
				alicorn.text(&ui, track.name)
				alicorn.text(&ui, "activity")
			}
			alicorn.key_scope_end(&ui)
		}
	}
	// The surface is continuously changing beside ordinary retained UI.
	alicorn.custom_surface(&ui, "spectrum", app.surface_frame, alicorn.Rect{0, 0, 320, 120}, 640, 240, 2)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
}

find_button :: proc(rt: ^alicorn.Runtime, key: u64) -> alicorn.Node_ID {
	for id in rt.order {
		if node, ok := rt.nodes[id]; ok && node.kind == .Button && node.identity_key_numeric && node.identity_key_u64 == key { return id }
	}
	return 0
}

main :: proc() {
	app := Crucible{}
	for i := 0; i < 8; i += 1 {
		app.tracks[i] = Track{i, fmt.aprintf("Track %d", i+1), false, u64(i*3), 1}
	}
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 900, 720})
	render(&rt, &app)
	focused_button := find_button(&rt, 3)
	if focused_button != 0 {
		node := rt.nodes[focused_button]
		alicorn.process_pointer(&rt, alicorn.Pointer_Event{.Down, node.bounds.x+2, node.bounds.y+2, 1})
		render(&rt, &app)
	}
	app.tracks[1], app.tracks[6] = app.tracks[6], app.tracks[1]
	render(&rt, &app)
	app.tracks[3].meter += 11
	app.tracks[3].revision += 1
	paint_before := rt.stats.paint_updates
	render(&rt, &app)
	fmt.println("Crucible meter-only paint delta:", rt.stats.paint_updates-paint_before)
	app.compact = true
	render(&rt, &app)
	fmt.println("Crucible compact focus fallback:", rt.focused)
	app.compact = false
	render(&rt, &app)
	app.surface_frame += 1
	render(&rt, &app)
	fmt.println("Crucible retained nodes:", len(rt.nodes), "regions skipped:", rt.stats.regions_skipped, "composites:", rt.stats.composite_updates)
	fmt.println(alicorn.inspect(&rt))
}
