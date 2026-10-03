package main

// 04 · Custom Surface teaches bounded retained GPU geometry inside ordinary
// clipped layout, including resize/DPI updates. Run with
// `odin run examples/04_custom_surface`; change the waveform geometry.

// Scheduled main-thread callbacks update only retained GPU geometry; they do
// not invalidate or rebuild the ordinary UI description.
import "core:math"
import "core:os"
import alicorn "../../runtime"
import host "../../native/sdl_gpu"

SURFACE_PERIOD :: 33 * 1_000_000
WAVE_SEGMENTS  :: 64

App :: struct {
	surface:   alicorn.Node_ID,
	phase:     f32,
	scheduler: host.Application_Scheduler,
}

build_app :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	logical_width, logical_height: int,
	dpi_scale: f32,
) -> alicorn.Node_ID {
	_ = logical_width
	_ = logical_height
	app := cast(^App)state
	ui, should_build := alicorn.begin_frame(rt)
	if !should_build { return 0 }

	root := alicorn.container_begin(
		&ui,
		.Root,
		label="custom-surface-root",
		style=alicorn.layout_style(.Column, grow=1, padding=24, gap=12, clip=true),
		color=alicorn.Color{0.035, 0.045, 0.065, 1},
	)
	alicorn.text(&ui, "Retained GPU surface", style=alicorn.layout_style(height=34), text_style=alicorn.Text_Style{font_weight=alicorn.FONT_WEIGHT_BOLD})
	alicorn.text(&ui, "A scheduled callback updates geometry at 30 Hz. The ordinary description, layout, and paint remain idle.", style=alicorn.layout_style(height=48))
	alicorn.container_begin(
		&ui,
		.Container,
		label="surface-panel",
		style=alicorn.layout_style(grow=1, padding=12, clip=true),
		color=alicorn.Color{0.075, 0.095, 0.135, 1},
	)
	app.surface = alicorn.gpu_geometry_surface(
		&ui,
		"animated-waveform",
		alicorn.layout_style(grow=1, width=-1, height=-1),
		dpi_scale,
	)
	alicorn.container_end(&ui)
	alicorn.text(&ui, "The description remains static while the retained GPU payload revision advances.", style=alicorn.layout_style(height=26))
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return root
}

services_app :: proc(state: rawptr, services: host.Application_Services) {
	app := cast(^App)state
	app.scheduler = services.scheduler
}

start_app :: proc(state: rawptr, waker: host.Application_Waker) {
	_ = waker
	app := cast(^App)state
	_ = host.application_schedule_after(app.scheduler, .Frequent, SURFACE_PERIOD)
}

scheduled_wake_app :: proc(state: rawptr, rt: ^alicorn.Runtime, class: host.Scheduled_Wake_Class) {
	_ = class
	app := cast(^App)state
	surface, ok := alicorn.gpu_surface_context(rt, app.surface)
	if ok && surface.logical_bounds.w > 0 && surface.logical_bounds.h > 0 {
		width := surface.logical_bounds.w
		height := surface.logical_bounds.h
		segments: [WAVE_SEGMENTS+11]alicorn.GPU_Surface_Line_Segment
		count := 0
		grid := alicorn.Color{0.22, 0.31, 0.43, 0.72}
		for guide in 0..=3 {
			y := height * f32(guide) / 3
			segments[count] = alicorn.GPU_Surface_Line_Segment{
				start={0, y}, end={width, y}, thickness=1, color=grid,
			}
			count += 1
		}
		for guide in 0..=6 {
			x := width * f32(guide) / 6
			segments[count] = alicorn.GPU_Surface_Line_Segment{
				start={x, 0}, end={x, height}, thickness=1, color=grid,
			}
			count += 1
		}
		wave_color := alicorn.Color{0.25, 0.86, 0.98, 1}
		previous := alicorn.GPU_Surface_Point{}
		for point in 0..=WAVE_SEGMENTS {
			x := width * f32(point) / WAVE_SEGMENTS
			normalized_x := f32(point) / WAVE_SEGMENTS
			angle := normalized_x * 6.2831853 * 2 + app.phase
			y := height * (0.5 - 0.34*math.sin(angle) - 0.12*math.sin(angle*2.3))
			current := alicorn.GPU_Surface_Point{x, y}
			if point > 0 {
				segments[count] = alicorn.GPU_Surface_Line_Segment{
					start=previous, end=current, thickness=2, color=wave_color,
				}
				count += 1
			}
			previous = current
		}
		marker := [1]alicorn.GPU_Surface_Filled_Circle{{
			center=previous, radius=4, color=alicorn.Color{1, 0.74, 0.28, 1},
		}}
		if alicorn.gpu_surface_update_geometry(rt, app.surface, segments[:count], marker[:]) {
			app.phase += 0.16
		}
	}
	_ = host.application_schedule_after(app.scheduler, .Frequent, SURFACE_PERIOD)
}

main :: proc() {
	app := App{}
	smoke := false
	for argument in os.args {
		if argument == "--smoke" { smoke = true }
	}
	host.Run(host.Application{
		state=rawptr(&app),
		title="Alicorn Custom Surface",
		width=900,
		height=620,
		build=build_app,
		on_services=services_app,
		on_start=start_app,
		on_scheduled_wake=scheduled_wake_app,
	}, smoke=smoke)
}
