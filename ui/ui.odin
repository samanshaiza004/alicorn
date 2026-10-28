package ui

import "core:mem"
import alicorn "alicorn:runtime"
import host "alicorn:native/sdl_gpu"
import odin_runtime "base:runtime"

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
UI_Key_Pair :: alicorn.UI_Key_Pair
Layout_Direction :: alicorn.Layout_Direction
Layout_Style :: alicorn.Layout_Style
Text_Style :: alicorn.Text_Style
Font_Role :: alicorn.Font_Role
Button_State :: alicorn.Button_State
Button_Content_Style :: alicorn.Button_Content_Style
Button_Variant :: alicorn.Button_Variant
Style_Color_Role :: alicorn.Style_Color_Role
Icon_ID :: alicorn.Icon_ID
Text_Buffer :: alicorn.Text_Field_Buffer
Text_Field_Response :: alicorn.Text_Field_Response

@(private)
DEFAULT_CHECKBOX_STYLE :: Layout_Style{
	direction=.Row,
	width=-1,
	height=-1,
	min_width=0,
	max_width=-1,
	min_height=0,
	max_height=-1,
	align=.Stretch,
	options=alicorn.Layout_Options(0),
}

key_u64 :: proc(value: u64) -> UI_Key { return alicorn.key_u64(value) }
key_pair :: proc(first, second: u64) -> UI_Key { return alicorn.key_pair(first, second) }

layout_style :: proc(
	direction: Layout_Direction = .Column,
	width: f32 = -1,
	height: f32 = -1,
	min_width: f32 = 0,
	max_width: f32 = -1,
	min_height: f32 = 0,
	max_height: f32 = -1,
	grow: f32 = 0,
	padding: f32 = 0,
	gap: f32 = 0,
	align: Align = .Stretch,
	clip: bool = false,
	compress_weight: u8 = 0,
	justify: Main_Axis_Distribution = .Start,
	writing_direction: alicorn.Writing_Direction = .Inherit,
) -> Layout_Style {
	return alicorn.layout_style(direction, width, height, min_width, max_width, min_height, max_height,
		grow, padding, gap, align, clip, compress_weight, justify, writing_direction)
}

// Border combines the retained stroke paint with its geometry-only placement.
// Placement lives in Alicorn's semantic-surface sidecar, keeping it out of
// the bounded Paint_Command payload.
Border :: struct {
	color: Color,
	width: f32,
	placement: Stroke_Placement,
}

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

border :: proc(width: f32, color: Color, placement: Stroke_Placement = .Inside) -> Border {
	return Border{color=color, width=width, placement=placement}
}

@(private)
paint_stroke :: proc(value: Border) -> Paint_Stroke {
	return Paint_Stroke{color=value.color, width=value.width}
}

@(private)
scope_end :: proc(
	ui: ^UI,
	_key: UI_Key,
	_width, _height, _grow, _padding, _gap: f32,
	_align: Align,
	_justify: Main_Axis_Distribution,
	_clip: bool,
	_loc: odin_runtime.Source_Code_Location,
	_label: string,
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
	loc := #caller_location,
	label: string = "row",
) -> bool {
	style := alicorn.layout_style(.Row, width=width, height=height, grow=grow, padding=padding, gap=gap, align=align, justify=justify, clip=clip)
	return alicorn.container_begin(ui, .Container, label=label, key=key, style=style, loc=loc) != 0
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
	loc := #caller_location,
	label: string = "column",
) -> bool {
	style := alicorn.layout_style(.Column, width=width, height=height, grow=grow, padding=padding, gap=gap, align=align, justify=justify, clip=clip)
	return alicorn.container_begin(ui, .Container, label=label, key=key, style=style, loc=loc) != 0
}

@(private)
layout_end :: proc(
	ui: ^UI,
	_style: alicorn.Layout_Style,
	_key: UI_Key,
	_label: string,
	_loc: odin_runtime.Source_Code_Location,
	opened: bool,
) {
	if opened { alicorn.container_end(ui) }
}

// layout scopes an exact runtime style on one plain, non-painting container.
// Unlike row/column, it supplies no convenience sizing defaults.
@(deferred_in_out=layout_end)
layout :: proc(
	ui: ^UI,
	style: alicorn.Layout_Style,
	key: UI_Key = alicorn.UI_Unkeyed{},
	label: string = "layout",
	loc := #caller_location,
) -> bool {
	return alicorn.container_begin(ui, .Container, label=label, key=key, style=style, loc=loc) != 0
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
	_stroke: Border,
	_loc: odin_runtime.Source_Code_Location,
	_label: string,
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
	stroke: Border = {},
	loc := #caller_location,
	label: string = "panel",
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
		stroke=paint_stroke(stroke),
		stroke_placement=stroke.placement,
		label=label,
		loc=loc,
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
	stroke: Border = {},
	loc := #caller_location,
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
		stroke=paint_stroke(stroke),
		stroke_placement=stroke.placement,
		label="box",
		loc=loc,
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
	loc := #caller_location,
	style: alicorn.Layout_Style = alicorn.DEFAULT_STYLE,
	font: alicorn.Font_Role = .UI,
	text_style: alicorn.Text_Style = alicorn.DEFAULT_TEXT_STYLE,
	decorative: bool = false,
) -> alicorn.Node_ID {
	effective_text_style := text_style
	if size > 0 { effective_text_style.font_size = size }
	id := alicorn.text(ui, value, key, style=style, loc=loc, font=font, text_style=effective_text_style, color=color)
	if id != 0 && !decorative { _ = alicorn.semantic_static_text(ui) }
	return id
}

// Text_Buffer owns committed editable text through an explicit allocator.
// The allocator must outlive the buffer; destroy each initialized buffer once.
text_buffer :: proc(initial: string, allocator: mem.Allocator = context.allocator) -> (Text_Buffer, bool) {
	return alicorn.text_field_buffer_init(initial, allocator)
}

text_buffer_destroy :: proc(buffer: ^Text_Buffer) {
	alicorn.text_field_buffer_destroy(buffer)
}

@(private)
control_style :: proc(style: alicorn.Layout_Style, width, height, grow: f32) -> alicorn.Layout_Style {
	result := style
	if width >= 0 { result.width = width }
	if height >= 0 { result.height = height }
	if grow >= 0 { result.grow = grow }
	return result
}

// text_field draws a visible, decorative label followed by the controlled
// field. The field carries that label in semantics while retaining its value,
// selection, and editing actions. Buffer storage remains application-owned.
text_field :: proc(
	ui: ^UI,
	label: string,
	buffer: ^Text_Buffer,
	key: UI_Key = alicorn.UI_Unkeyed{},
	loc := #caller_location,
	style: alicorn.Layout_Style = alicorn.DEFAULT_STYLE,
	width: f32 = -1,
	height: f32 = -1,
	grow: f32 = -1,
	font: alicorn.Font_Role = .UI,
	text_style: alicorn.Text_Style = alicorn.DEFAULT_TEXT_STYLE,
) -> Text_Field_Response {
	_ = text(ui, label, decorative=true, loc=loc)
	response := alicorn.text_field_controlled(
		ui,
		buffer,
		key=key,
		style=control_style(style, width, height, grow),
		loc=loc,
		font=font,
		text_style=text_style,
	)
	if response.node != 0 { _ = alicorn.semantic_text_field_label(ui, label) }
	return response
}

// checkbox adopts a one-shot activation into application-owned state. A
// normal description never writes through the pointer.
checkbox :: proc(
	ui: ^UI,
	label: string,
	value: ^bool,
	key: UI_Key = alicorn.UI_Unkeyed{},
	loc := #caller_location,
	style: alicorn.Layout_Style = DEFAULT_CHECKBOX_STYLE,
	width: f32 = -1,
	height: f32 = -1,
	grow: f32 = -1,
	disabled: bool = false,
) -> bool {
	if value == nil { return false }
	effective_style := control_style(style, width, height, grow)
	result := alicorn.checkbox(
		ui,
		label,
		value^,
		key=key,
		style=effective_style,
		disabled=disabled,
		loc=loc,
	)
	if result.changed { value^ = result.value }
	return result.changed
}

// slider_f32 adopts only values produced by a user interaction. Runtime
// normalization of an out-of-range model value during description does not
// mutate application state through this convenience API.
slider_f32 :: proc(
	ui: ^UI,
	label: string,
	value: ^f32,
	minimum, maximum: f32,
	step: f32 = 0,
	key: UI_Key = alicorn.UI_Unkeyed{},
	loc := #caller_location,
	style: alicorn.Layout_Style = alicorn.DEFAULT_STYLE,
	width: f32 = -1,
	height: f32 = -1,
	grow: f32 = -1,
	disabled: bool = false,
) -> bool {
	if value == nil { return false }
	result := alicorn.slider_f32(
		ui,
		label,
		value^,
		minimum,
		maximum,
		step,
		key=key,
		style=control_style(style, width, height, grow),
		disabled=disabled,
		loc=loc,
	)
	if result.activated { value^ = result.value }
	return result.activated
}

icon :: proc(
	ui: ^UI,
	id: Icon_ID,
	key: UI_Key = alicorn.UI_Unkeyed{},
	size: f32 = 16,
	color_role := alicorn.Style_Color_Role.Muted_Text,
	loc := #caller_location,
) -> Node_ID {
	return alicorn.icon(ui, id, key=key, size=size, color_role=color_role, loc=loc)
}

icon_button :: proc(
	ui: ^UI,
	accessible_label: string,
	id: Icon_ID,
	key: UI_Key = alicorn.UI_Unkeyed{},
	style: alicorn.Layout_Style = alicorn.DEFAULT_STYLE,
	variant: alicorn.Button_Variant = .Quiet,
	disabled: bool = false,
	loc := #caller_location,
) -> bool {
	_, clicked := alicorn.icon_button(ui, accessible_label, id, key=key, style=style, variant=variant, disabled=disabled, loc=loc)
	return clicked
}

button :: proc(
	ui: ^UI,
	label: string,
	key: UI_Key = alicorn.UI_Unkeyed{},
	loc := #caller_location,
	style: alicorn.Layout_Style = alicorn.DEFAULT_STYLE,
	state: alicorn.Button_State = {},
	text_style: alicorn.Text_Style = alicorn.DEFAULT_BUTTON_TEXT_STYLE,
	content_style: alicorn.Button_Content_Style = alicorn.DEFAULT_BUTTON_CONTENT_STYLE,
	variant: alicorn.Button_Variant = .Default,
	width: f32 = -1,
	height: f32 = -1,
	grow: f32 = -1,
) -> bool {
	effective_style := control_style(style, width, height, grow)
	return alicorn.button(ui, label, key=key, style=effective_style, state=state, loc=loc,
		text_style=text_style, content_style=content_style, variant=variant)
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
