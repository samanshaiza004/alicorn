package ui

import alicorn "alicorn:runtime"
import host "alicorn:native/sdl_gpu"

// UI is the ordinary authoring context. It is the same context used by the
// lower-level runtime API; these helpers do not create another UI tree.
UI :: alicorn.UI
Node_ID :: alicorn.Node_ID
Color :: alicorn.Color
Paint_Stroke :: alicorn.Paint_Stroke
Stroke_Placement :: alicorn.Paint_Stroke_Placement
Align :: alicorn.Align
Main_Axis_Distribution :: alicorn.Main_Axis_Distribution
UI_Key :: alicorn.UI_Key

DEFAULT_COLOR :: alicorn.DEFAULT_COLOR

@(private)
PANEL_THEME_FILL :: alicorn.NO_BACKGROUND_COLOR

red :: Color{1, 0, 0, 1}
green :: Color{0, 1, 0, 1}
blue :: Color{0, 0, 1, 1}
yellow :: Color{1, 1, 0, 1}
black :: Color{0, 0, 0, 1}
white :: Color{1, 1, 1, 1}

rgb :: proc(hex: u32) -> Color {
	return Color{
		f32((hex >> 16) & 0xff) / 255,
		f32((hex >> 8) & 0xff) / 255,
		f32(hex & 0xff) / 255,
		1,
	}
}

border :: proc(width: f32, color: Color, placement: Stroke_Placement = .Inside) -> Paint_Stroke {
	return Paint_Stroke{color=color, width=width, placement=placement}
}

@(private)
scope_end :: proc(
	ui: ^UI,
	_key: UI_Key,
	_width, _height, _grow, _padding, _gap: f32,
	_align: Align,
	_justify: Main_Axis_Distribution,
	_clip: bool,
	opened: bool,
) {
	if opened { alicorn.container_end(ui) }
}

// row and column fill their allocated width and measure their height from
// their children. Parent main-axis allocation follows Alicorn's usual rules;
// pass grow=1 when this scope should take a share of its parent's leftover.
@(deferred_in_out=scope_end)
row :: proc(
	ui: ^UI,
	key: UI_Key = alicorn.UI_Unkeyed{},
	width: f32 = -1,
	height: f32 = alicorn.LAYOUT_SIZE_FIT_CONTENT,
	grow: f32 = 0,
	padding: f32 = 0,
	gap: f32 = 0,
	align: Align = .Stretch,
	justify: Main_Axis_Distribution = .Start,
	clip: bool = false,
) -> bool {
	style := alicorn.layout_style(.Row, width=width, height=height, grow=grow, padding=padding, gap=gap, align=align, justify=justify, clip=clip)
	return alicorn.container_begin(ui, .Container, label="row", key=key, style=style, loc=#caller_location) != 0
}

@(deferred_in_out=scope_end)
column :: proc(
	ui: ^UI,
	key: UI_Key = alicorn.UI_Unkeyed{},
	width: f32 = -1,
	height: f32 = alicorn.LAYOUT_SIZE_FIT_CONTENT,
	grow: f32 = 0,
	padding: f32 = 0,
	gap: f32 = 0,
	align: Align = .Stretch,
	justify: Main_Axis_Distribution = .Start,
	clip: bool = false,
) -> bool {
	style := alicorn.layout_style(.Column, width=width, height=height, grow=grow, padding=padding, gap=gap, align=align, justify=justify, clip=clip)
	return alicorn.container_begin(ui, .Container, label="column", key=key, style=style, loc=#caller_location) != 0
}

@(private)
panel_end :: proc(
	ui: ^UI,
	_key: UI_Key,
	_width, _height, _grow, _padding, _gap: f32,
	_align: Align,
	_justify: Main_Axis_Distribution,
	_clip: bool,
	_fill: Color,
	_radius: f32,
	_stroke: Paint_Stroke,
	opened: bool,
) {
	if opened { alicorn.surface_end(ui) }
}

// panel is a layout column with one ordinary retained surface paint command.
// Omitted fill uses the active theme's Surface role; radius and border are
// explicit logical-unit decorations.
@(deferred_in_out=panel_end)
panel :: proc(
	ui: ^UI,
	key: UI_Key = alicorn.UI_Unkeyed{},
	width: f32 = -1,
	height: f32 = alicorn.LAYOUT_SIZE_FIT_CONTENT,
	grow: f32 = 0,
	padding: f32 = 0,
	gap: f32 = 0,
	align: Align = .Stretch,
	justify: Main_Axis_Distribution = .Start,
	clip: bool = false,
	fill: Color = PANEL_THEME_FILL,
	radius: f32 = 0,
	stroke: Paint_Stroke = {},
) -> bool {
	shape := alicorn.Surface_Shape{kind=.Rectangle}
	if radius != 0 { shape = alicorn.Surface_Shape{kind=.Rounded_Rectangle, corner_radius=radius} }
	style := alicorn.layout_style(.Column, width=width, height=height, grow=grow, padding=padding, gap=gap, align=align, justify=justify, clip=clip)
	id := alicorn.surface_begin(
		ui,
		alicorn.surface_core_color_role(.Surface),
		key=key,
		style=style,
		shape=shape,
		fill=fill,
		stroke=stroke,
		label="panel",
		loc=#caller_location,
	)
	return id != 0
}

// box is a leaf surface. size sets both axes; an explicitly supplied width or
// height overrides that square default.
box :: proc(
	ui: ^UI,
	key: UI_Key = alicorn.UI_Unkeyed{},
	size: f32 = 24,
	width: f32 = -1,
	height: f32 = -1,
	fill: Color = DEFAULT_COLOR,
	radius: f32 = 0,
	stroke: Paint_Stroke = {},
) -> alicorn.Node_ID {
	resolved_width := size if width < 0 else width
	resolved_height := size if height < 0 else height
	shape := alicorn.Surface_Shape{kind=.Rectangle}
	if radius != 0 { shape = alicorn.Surface_Shape{kind=.Rounded_Rectangle, corner_radius=radius} }
	id := alicorn.surface_begin(
		ui,
		alicorn.surface_core_color_role(.Surface),
		key=key,
		style=alicorn.layout_style(.Column, width=resolved_width, height=resolved_height),
		shape=shape,
		fill=fill,
		stroke=stroke,
		label="box",
		loc=#caller_location,
	)
	if id != 0 { alicorn.surface_end(ui) }
	return id
}

text :: proc(
	ui: ^UI,
	value: string,
	key: UI_Key = alicorn.UI_Unkeyed{},
	size: f32 = 0,
	color: Color = DEFAULT_COLOR,
) -> alicorn.Node_ID {
	effective_text_style := alicorn.DEFAULT_TEXT_STYLE
	if size > 0 { effective_text_style.font_size = size }
	return alicorn.text(ui, value, key, loc=#caller_location, text_style=effective_text_style, color=color)
}

button :: proc(
	ui: ^UI,
	label: string,
	key: UI_Key = alicorn.UI_Unkeyed{},
) -> bool {
	return alicorn.button(ui, label, key=key, loc=#caller_location)
}

invalidate :: proc(ui: ^UI, reason := "simple UI explicitly invalidated") {
	if ui != nil && ui.runtime != nil { alicorn.invalidate_root(ui.runtime, reason) }
}

@(private)
Run_State :: struct($T: typeid) {
	app: ^T,
	render: proc(^T, ^UI),
	render_overlays: proc(^T, ^UI),
}

@(private)
run_describe :: proc(state: ^Run_State($T), ctx: ^UI) -> alicorn.Node_ID {
	root := alicorn.container_begin(
		ctx,
		.Root,
		label="ui-root",
		key="alicorn.ui.root",
		style=alicorn.layout_style(.Column, grow=1),
	)
	if root == 0 { return 0 }
	state.render(state.app, ctx)
	alicorn.container_end(ctx)
	if state.render_overlays != nil { state.render_overlays(state.app, ctx) }
	return root
}

// run is a typed convenience over the native host. It uses the same Runtime,
// identity, layout, paint, event, and bounded corrective-description paths as
// host.Run. An optional overlay description runs after the main root closes.
run :: proc(
	state: ^$T,
	render: proc(^T, ^UI),
	title: string = "Alicorn",
	width: int = 720,
	height: int = 480,
	render_overlays: proc(^T, ^UI) = nil,
) {
	run_state := Run_State(T){
		app=state,
		render=render,
		render_overlays=render_overlays,
	}
	build :: proc(
		data: rawptr,
		rt: ^alicorn.Runtime,
		_logical_width, _logical_height: int,
		_dpi_scale: f32,
	) -> alicorn.Node_ID {
		ctx, should_build := alicorn.begin_frame(rt)
		if !should_build { return 0 }
		root := run_describe(cast(^Run_State(T))data, &ctx)
		alicorn.end_frame(&ctx)
		return root
	}

	application := host.Application{
		state=rawptr(&run_state),
		title=title,
		width=width,
		height=height,
		build=build,
		interaction_update_policy=.Correct_After_Interaction,
	}
	host.Run(application)
}
