package main

// 14 · Shape Primitives demonstrates renderer-neutral semantic surfaces for
// circles, arcs, and cubic Bezier strokes, plus an opt-in circular Button hit.

import "core:fmt"
import alicorn "alicorn:runtime"
import ui "alicorn:ui"

Roles :: struct {
	knob, knob_center, meter, cable: alicorn.Style_Extension_Color_Role_ID,
}

App :: struct {
	theme: alicorn.Style_Theme_ID,
	roles: Roles,
	gain: int,
}

initialize :: proc(app: ^App, rt: ^alicorn.Runtime) {
	app.gain = 62
	app.roles = Roles{
		knob=alicorn.style_extension_color_role_id("app.example.shapes", "knob.surface"),
		knob_center=alicorn.style_extension_color_role_id("app.example.shapes", "knob.center"),
		meter=alicorn.style_extension_color_role_id("app.example.shapes", "meter.arc"),
		cable=alicorn.style_extension_color_role_id("app.example.shapes", "cable.stroke"),
	}
	theme := alicorn.DEFAULT_STYLE_THEME
	theme.color_tokens = {
		alicorn.Color{0.10, 0.19, 0.30, 1},
		alicorn.Color{0.035, 0.065, 0.105, 1},
		alicorn.Color{0.15, 0.73, 0.63, 1},
		alicorn.Color{0.95, 0.55, 0.22, 1},
	}
	theme.extension_color_roles = {
		alicorn.Style_Extension_Color_Role_Binding{app.roles.knob, alicorn.Style_Color_Token_ID(1)},
		alicorn.Style_Extension_Color_Role_Binding{app.roles.knob_center, alicorn.Style_Color_Token_ID(2)},
		alicorn.Style_Extension_Color_Role_Binding{app.roles.meter, alicorn.Style_Color_Token_ID(3)},
		alicorn.Style_Extension_Color_Role_Binding{app.roles.cable, alicorn.Style_Color_Token_ID(4)},
	}
	app.theme = alicorn.style_theme_register(rt, theme)
}

knob :: proc(app: ^App, ctx: ^ui.UI) {
	label := fmt.tprintf("Gain, %d percent", app.gain)
	if ui.column(ctx, align=.Center, gap=6) {
		owner, activated := alicorn.button_begin(
			ctx,
			label,
			key=ui.key_u64(1),
			style=alicorn.layout_style(.Column, width=92, height=92, align=.Center),
			presentation=.Custom,
			pointer_hit_shape=.Circle,
		)
		if owner != 0 {
			if activated { app.gain = (app.gain+5)%101 }
			_ = alicorn.semantic_augment(ctx, description=fmt.tprintf("Gain is %d percent. Activate to increase it.", app.gain))

			frame := alicorn.surface_begin(
				ctx,
				alicorn.surface_extension_color_role(app.roles.knob),
				key=ui.key_u64(2),
				style=alicorn.layout_style(.Column, width=92, height=92, padding=4, align=.Center),
				shape=alicorn.surface_shape_circle(),
				fill=alicorn.Color{0, 0, 0, 0},
				stroke=alicorn.Paint_Stroke{color=alicorn.style_color(ctx, .Focus), width=2},
				label="knob keyboard focus ring",
			)
			if frame != 0 {
				_ = alicorn.visual_part_attach(ctx, frame, owner, alicorn.visual_part_core(.Focus_Indicator), .Owner_Focus_Visible)
				face := alicorn.surface_begin(
					ctx,
					alicorn.surface_extension_color_role(app.roles.knob),
					key=ui.key_u64(3),
					style=alicorn.layout_style(.Column, width=78, height=78, align=.Center),
					shape=alicorn.surface_shape_circle(),
					label="gain knob face",
				)
				if face != 0 {
					center := alicorn.surface_begin(
						ctx,
						alicorn.surface_extension_color_role(app.roles.knob_center),
						key=ui.key_u64(4),
						style=alicorn.layout_style(.Column, width=50, height=50, align=.Center),
						shape=alicorn.surface_shape_circle(),
						label="gain knob center",
					)
					if center != 0 {
						ui.text(ctx, fmt.tprintf("%d%%", app.gain), size=15)
						alicorn.surface_end(ctx)
					}
					alicorn.surface_end(ctx)
				}
				alicorn.surface_end(ctx)
			}
			alicorn.button_end(ctx)
		}
		ui.text(ctx, "GAIN", size=12)
	}
}

meter :: proc(app: ^App, ctx: ^ui.UI) {
	ui.text(ctx, "OUTPUT METER", size=12)
	_ = alicorn.surface_begin(
		ctx,
		alicorn.surface_extension_color_role(app.roles.meter),
		key=ui.key_u64(20),
		style=alicorn.layout_style(width=230, height=132),
		shape=alicorn.surface_shape_arc(2.36, 4.71, radius=0.42, center={0.5, 0.58}),
		fill=alicorn.Color{0, 0, 0, 0},
		stroke=alicorn.Paint_Stroke{color=alicorn.Color{0.15, 0.73, 0.63, 1}, width=9},
		label="curved output meter arc",
	)
	alicorn.surface_end(ctx)
	ui.text(ctx, "−12 dB  ·  Peak −3 dB", size=13)
}

cable :: proc(app: ^App, ctx: ^ui.UI) {
	_ = alicorn.surface_begin(
		ctx,
		alicorn.surface_extension_color_role(app.roles.cable),
		key=ui.key_u64(30),
		style=alicorn.layout_style(width=420, height=96),
		shape=alicorn.surface_shape_cubic_bezier({
			{0.02, 0.78}, {0.24, 0.02}, {0.74, 0.98}, {0.98, 0.24},
		}),
		fill=alicorn.Color{0, 0, 0, 0},
		stroke=alicorn.Paint_Stroke{color=alicorn.Color{0.95, 0.55, 0.22, 1}, width=4},
		label="curved signal connection",
	)
	alicorn.surface_end(ctx)
}

render :: proc(app: ^App, ctx: ^ui.UI) {
	if ui.column(ctx, grow=1, padding=28, gap=18, clip=true) {
		ui.text(ctx, "Shape primitives", size=28)
		ui.text(ctx, "Semantic surfaces lower to bounded geometry; the Gain button keeps ordinary keyboard and accessibility behavior with a circular pointer target.")
		if ui.panel(ctx, grow=1, padding=24, gap=20, label="shape-primitives-demo") {
			if app.theme != 0 {
				scope := alicorn.style_environment_push(ctx, alicorn.Style_Environment{theme=app.theme})
				if ui.row(ctx, gap=38, align=.Center) {
					knob(app, ctx)
					if ui.column(ctx, gap=8, align=.Center) { meter(app, ctx) }
				}
				ui.text(ctx, "Curved connection · cubic Bezier", size=13)
				cable(app, ctx)
				ui.text(ctx, "Tab to the Gain control and press Space; pointer hits outside its circular face pass through.", size=13)
				alicorn.style_environment_pop(ctx, scope)
			}
			alicorn.surface_end(ctx)
		}
	}
}

main :: proc() {
	app := App{}
	ui.run(&app, render, title="Alicorn · Shape Primitives", width=940, height=620, on_initialize=initialize)
}
