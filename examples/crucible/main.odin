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

ROOT :: alicorn.Source_Site{"crucible/app.odin", 1, 1, "root"}
TRACK :: alicorn.Source_Site{"crucible/app.odin", 10, 1, "track_row"}
MUTE :: alicorn.Source_Site{"crucible/app.odin", 11, 3, "mute"}
NAME :: alicorn.Source_Site{"crucible/app.odin", 12, 3, "name"}
METER :: alicorn.Source_Site{"crucible/app.odin", 13, 3, "meter"}
REGION :: alicorn.Source_Site{"crucible/app.odin", 14, 3, "meter_region"}
SURFACE :: alicorn.Source_Site{"crucible/app.odin", 30, 1, "custom_surface"}

render :: proc(rt: ^alicorn.Runtime, app: ^Crucible) {
	alicorn.invalidate_root(rt, "crucible state update")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin(&ui, .Root, ROOT, label="Alicorn Crucible", style=alicorn.Layout_Style{.Column, -1, -1, 0, -1, 0, -1, 0, 8, 4, .Stretch, true})
	alicorn.text(&ui, "8 tracks / keyed state / deterministic LOD", NAME)
	for track in app.tracks {
		if alicorn.key_scope_begin(&ui, fmt.aprintf("%d", track.id), TRACK) {
			if !app.compact {
				alicorn.button(&ui, track.name, MUTE, paint_value=u64(track.muted ? 1 : 0), style=alicorn.Layout_Style{.Column, -1, 28, 0, -1, 0, -1, 0, 0, 0, .Stretch, false})
				region_id, reused := alicorn.region_begin(&ui, "meter", track.revision, REGION)
				if region_id != 0 && !reused {
					start := len(rt.pending)
					alicorn.text(&ui, fmt.aprintf("meter %d", track.meter), METER)
					alicorn.region_end(&ui, region_id, false, start)
				}
			} else {
				alicorn.text(&ui, track.name, NAME)
				alicorn.text(&ui, "activity", METER, paint_value=track.meter)
			}
			alicorn.key_scope_end(&ui)
		}
	}
	// The surface is continuously changing beside ordinary retained UI.
	alicorn.custom_surface(&ui, "spectrum", app.surface_frame, alicorn.Rect{0, 0, 320, 120}, 640, 240, 2, SURFACE)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
}

find_button :: proc(rt: ^alicorn.Runtime, key: string) -> alicorn.Node_ID {
	for id in rt.order {
		if node, ok := rt.nodes[id]; ok && node.kind == .Button && node.identity_key == key { return id }
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
	focused_button := find_button(&rt, "3")
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

