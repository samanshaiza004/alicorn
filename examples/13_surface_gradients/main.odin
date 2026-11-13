package main

// 13 · Surface Gradients demonstrates opt-in, theme-resolved two-stop fills
// on ordinary semantic surfaces. The runtime still owns shape, clipping, and
// paint order; the native renderer reuses existing surface vertices.

import alicorn "alicorn:runtime"
import ui "alicorn:ui"


Gradient_Roles :: struct {
	tab_inactive_start, tab_inactive_end: alicorn.Style_Extension_Color_Role_ID,
	tab_active_start, tab_active_end: alicorn.Style_Extension_Color_Role_ID,
	meter_start, meter_end: alicorn.Style_Extension_Color_Role_ID,
}

App :: struct {
	theme: alicorn.Style_Theme_ID,
	roles: Gradient_Roles,
}

initialize :: proc(app: ^App, rt: ^alicorn.Runtime) {
	app.roles = Gradient_Roles{
		tab_inactive_start=alicorn.style_extension_color_role_id("app.example.gradients", "tab.inactive.start"),
		tab_inactive_end=alicorn.style_extension_color_role_id("app.example.gradients", "tab.inactive.end"),
		tab_active_start=alicorn.style_extension_color_role_id("app.example.gradients", "tab.active.start"),
		tab_active_end=alicorn.style_extension_color_role_id("app.example.gradients", "tab.active.end"),
		meter_start=alicorn.style_extension_color_role_id("app.example.gradients", "meter.start"),
		meter_end=alicorn.style_extension_color_role_id("app.example.gradients", "meter.end"),
	}
	theme := alicorn.DEFAULT_STYLE_THEME
	theme.color_tokens = {
		alicorn.Color{0.105, 0.135, 0.19, 1}, // inactive tab start
		alicorn.Color{0.075, 0.095, 0.145, 1}, // inactive tab end
		alicorn.Color{0.12, 0.34, 0.62, 1}, // active tab start
		alicorn.Color{0.08, 0.58, 0.67, 1}, // active tab end
		alicorn.Color{0.11, 0.25, 0.43, 1}, // pulse meter start
		alicorn.Color{0.08, 0.39, 0.31, 1}, // pulse meter end
	}
	theme.extension_color_roles = {
		alicorn.Style_Extension_Color_Role_Binding{app.roles.tab_inactive_start, alicorn.Style_Color_Token_ID(1)},
		alicorn.Style_Extension_Color_Role_Binding{app.roles.tab_inactive_end, alicorn.Style_Color_Token_ID(2)},
		alicorn.Style_Extension_Color_Role_Binding{app.roles.tab_active_start, alicorn.Style_Color_Token_ID(3)},
		alicorn.Style_Extension_Color_Role_Binding{app.roles.tab_active_end, alicorn.Style_Color_Token_ID(4)},
		alicorn.Style_Extension_Color_Role_Binding{app.roles.meter_start, alicorn.Style_Color_Token_ID(5)},
		alicorn.Style_Extension_Color_Role_Binding{app.roles.meter_end, alicorn.Style_Color_Token_ID(6)},
	}
	app.theme = alicorn.style_theme_register(rt, theme)
}

gradient_surface :: proc(
	ctx: ^ui.UI,
	label: string,
	start_role, end_role: alicorn.Style_Extension_Color_Role_ID,
	axis: alicorn.Surface_Gradient_Axis,
	key: u64,
) {
	id := alicorn.surface_begin(
		ctx,
		alicorn.surface_extension_color_role(start_role),
		key=ui.key_u64(key),
		style=alicorn.layout_style(.Column, width=150, height=52, padding=12, align=.Center),
		shape=alicorn.surface_shape_rounded_corners({top_left=12, top_right=12, bottom_right=12, bottom_left=12}),
		gradient=alicorn.surface_gradient_to(alicorn.surface_extension_color_role(end_role), axis),
		label=label,
	)
	if id != 0 {
		ui.text(ctx, label, color=alicorn.Color{0.93, 0.96, 1, 1})
		alicorn.surface_end(ctx)
	}
}

render :: proc(app: ^App, ctx: ^ui.UI) {
	if ui.column(ctx, grow=1, padding=28, gap=20, clip=true) {
		ui.text(ctx, "Semantic surface gradients", size=28)
		ui.text(ctx, "Static, theme-owned two-stop fills. Resize the window; clipping and rounded edges stay attached to each surface.")
		if ui.panel(ctx, grow=1, padding=24, gap=22, label="surface-gradient-demo") {
			if app.theme != 0 {
				scope := alicorn.style_environment_push(ctx, alicorn.Style_Environment{theme=app.theme})
				ui.text(ctx, "Tab surfaces", size=19)
				if ui.row(ctx, gap=12, align=.Center) {
					gradient_surface(ctx, "Inactive", app.roles.tab_inactive_start, app.roles.tab_inactive_end, .Horizontal, 1)
					gradient_surface(ctx, "Active", app.roles.tab_active_start, app.roles.tab_active_end, .Horizontal, 2)
				}
				ui.text(ctx, "Pulse meter · vertical gradient", size=19)
				meter := alicorn.surface_begin(
					ctx,
					alicorn.surface_extension_color_role(app.roles.meter_start),
					key=ui.key_u64(3),
					style=alicorn.layout_style(.Row, width=520, height=94, padding=18, gap=20, align=.Center),
					shape=alicorn.surface_shape_rounded_corners({top_left=18, top_right=18, bottom_right=18, bottom_left=18}),
					gradient=alicorn.surface_gradient_to(alicorn.surface_extension_color_role(app.roles.meter_end), .Vertical),
					label="Pulse meter",
				)
				if meter != 0 {
					if ui.column(ctx, gap=4) {
						ui.text(ctx, "Pulse", size=17, color=alicorn.Color{0.95, 0.98, 1, 1})
						ui.text(ctx, "Signal steady", size=12, color=alicorn.Color{0.75, 0.86, 0.91, 1})
					}
					ui.text(ctx, "72%", size=20, color=alicorn.Color{0.95, 0.98, 1, 1})
					if ui.row(ctx, grow=1, height=44, gap=5, align=.Center) {
						heights := [16]f32{12, 20, 28, 18, 32, 24, 38, 30, 22, 40, 30, 36, 24, 32, 18, 26}
						for height, index in heights {
							ui.box(ctx, key=ui.key_u64(u64(100+index)), width=5, height=height,
								fill=alicorn.Color{0.84, 0.94, 0.93, 0.86}, radius=3)
						}
					}
					alicorn.surface_end(ctx)
				}
				ui.text(ctx, "Colors resolve through ordinary namespaced color roles. The stroke, rounded shape, opacity, and clip remain independent surface properties.", size=14)
				alicorn.style_environment_pop(ctx, scope)
			}
			alicorn.surface_end(ctx)
		}
	}
}

main :: proc() {
	app := App{}
	ui.run(&app, render, title="Alicorn · Surface Gradients", width=940, height=620, on_initialize=initialize)
}
