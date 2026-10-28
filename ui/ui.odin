package ui

import "core:mem"
import "core:math"
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
Virtual_List :: alicorn.Virtual_List_Handle

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

@(private)
key_scope_end :: proc(ui: ^UI, _key: UI_Key, _loc: odin_runtime.Source_Code_Location, opened: bool) {
	if opened { alicorn.key_scope_end(ui) }
}

// key_scope identifies one reusable component instance without adding a layout
// node. Use directly as an if condition; its identity scope closes on block
// exit, including return, break and continue. The key must follow the data,
// rather than its current position in a collection.
@(deferred_in_out=key_scope_end)
key_scope :: proc(ui: ^UI, key: UI_Key, loc := #caller_location) -> bool {
	return alicorn.key_scope_begin(ui, key, loc=loc)
}

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
layout_sized_end :: proc(
	ui: ^UI,
	_base: alicorn.Layout_Style,
	_declaration: Sizing,
	_key: UI_Key,
	_label: string,
	_loc: odin_runtime.Source_Code_Location,
	opened: bool,
) {
	if opened { alicorn.container_end(ui) }
}

// resolve_sizing_for_ui lowers typed values and resolves the one supported
// parent-relative declaration before a node is emitted. It keeps layout_sized
// and paint-bearing surfaces on the same validation and diagnostic path.
@(private)
resolve_sizing_for_ui :: proc(
	ui: ^UI,
	base: alicorn.Layout_Style,
	declaration: Sizing,
	loc: odin_runtime.Source_Code_Location,
) -> (alicorn.Layout_Style, bool) {
	lowered_declaration := declaration
	percent_width := declaration.width.kind == .Percentage
	if percent_width {
		if base.width != alicorn.DEFAULT_STYLE.width {
			alicorn.layout_sizing_report_invalid(ui.runtime,
				"percentage width cannot be combined with a width already set in the base Layout_Style", loc)
			return base, false
		}
		lowered_declaration.width = {}
	}
	style, valid := resolve_sizing(base, lowered_declaration)
	if !valid {
		alicorn.layout_sizing_report_invalid(ui.runtime,
			"unsupported, conflicting, nonfinite, or out-of-range typed sizing input", loc)
		return base, false
	}
	if percent_width {
		style.width, valid = alicorn.layout_percent_width_resolve(ui, declaration.width.value, loc)
		if !valid { return base, false }
	}
	return style, true
}

// layout_sized is the low-level percentage-width scope. Fixed, fit-height,
// and grow inputs lower to ordinary Layout_Style values. A percentage width is
// resolved against the current parent's definite inner width before emission;
// invalid declarations produce source-located diagnostics and do not open a
// scope. This adds no percentage fields to retained nodes.
@(deferred_in_out=layout_sized_end)
layout_sized :: proc(
	ui: ^UI,
	base: alicorn.Layout_Style,
	declaration: Sizing,
	key: UI_Key = alicorn.UI_Unkeyed{},
	label: string = "layout",
	loc := #caller_location,
) -> bool {
	style, valid := resolve_sizing_for_ui(ui, base, declaration, loc)
	if !valid { return false }
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
	_sizing: Sizing,
	_shape: alicorn.Surface_Shape,
	_material: alicorn.Material_ID,
	_physical_height: f32,
	opened: bool,
) {
	if opened { alicorn.surface_end(ui) }
}

// panel is a layout column with one ordinary retained surface paint command.
// Its optional typed sizing lowers onto the same surface node; percentage
// width remains subject to the current parent's definiteness rules. Omitted
// fill uses the active theme's Surface role.
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
	sizing: Sizing = {},
	shape: alicorn.Surface_Shape = {kind=.Rectangle},
	material: alicorn.Material_ID = alicorn.MATERIAL_FLAT,
	physical_height: f32 = 0,
) -> bool {
	resolved_shape := shape
	if radius != 0 { resolved_shape = alicorn.Surface_Shape{kind=.Rounded_Rectangle, corner_radius=radius} }
	style := alicorn.layout_style(.Column, width=width, height=height, grow=grow, padding=padding, gap=gap, align=align, justify=justify, clip=clip)
	resolved_style, valid := resolve_sizing_for_ui(ui, style, sizing, loc)
	if !valid { return false }
	id := alicorn.surface_begin(
		ui,
		alicorn.surface_core_color_role(.Surface),
		key=key,
		style=resolved_style,
		shape=resolved_shape,
		material=material,
		physical_height=physical_height,
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

@(private)
virtual_list_end :: proc(
	ui: ^UI, _item_count: int, _row_height: f32, _key: UI_Key,
	_width, _height, _grow: f32, _label: string, _loc: odin_runtime.Source_Code_Location,
	_focusable: bool, list: Virtual_List, opened: bool,
) {
	if opened { alicorn.virtual_list_end(ui, list) }
}

// Use `if list, ok := virtual_list(...); ok { ... }` to close the retained
// scroll/content scopes automatically. Emit only [first, last), with one
// row occupying exactly row_height and stable data keys for its component.
@(deferred_in_out=virtual_list_end)
virtual_list :: proc(
	ui: ^UI,
	item_count: int,
	row_height: f32,
	key: UI_Key = alicorn.UI_Unkeyed{},
	width: f32 = -1,
	height: f32 = -1,
	grow: f32 = 1,
	label: string = "virtual-list",
	loc := #caller_location,
	focusable: bool = false,
) -> (list: Virtual_List, opened: bool) {
	if item_count < 0 || row_height <= 0 || math.is_nan(row_height) || math.is_inf(row_height) ||
		math.is_inf(f32(item_count)*row_height) { return }
	list = alicorn.virtual_list_begin(
		ui,
		item_count,
		row_height,
		key=key,
		style=alicorn.layout_style(.Column, width=width, height=height, grow=grow, clip=true),
		label=label,
		loc=loc,
		focusable=focusable,
	)
	opened = list.scroll.id != 0
	return
}

// Application_Context is borrowed for one application-thread wake callback.
// Do not retain it or pass it to a worker. Only Application_Waker may cross
// that boundary; the app owns result storage and its synchronization.
Application_Context :: distinct ^alicorn.Runtime
Application_Waker :: host.Application_Waker

// wake is the native host's thread-safe event request. It does not publish or
// synchronize application data. Stop and join every producer in on_stop before
// returning; no borrowed waker may be used afterward.
wake :: proc(waker: Application_Waker) {
	host.application_wake(waker)
}

invalidate :: proc {invalidate_ui, invalidate_application}

@(private)
invalidate_ui :: proc(ui: ^UI, reason := "simple UI explicitly invalidated") {
	if ui != nil && ui.runtime != nil { alicorn.invalidate_root(ui.runtime, reason) }
}

@(private)
invalidate_application :: proc(ctx: Application_Context, reason := "application explicitly invalidated") {
	rt := cast(^alicorn.Runtime)ctx
	if rt != nil { alicorn.invalidate_root(rt, reason) }
}

@(private)
Run_State :: struct($T: typeid) {
	app: ^T,
	render: proc(^T, ^UI),
	render_overlays: proc(^T, ^UI),
	on_start: proc(^T, Application_Waker),
	on_wake: proc(^T, Application_Context),
	on_stop: proc(^T),
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

@(private)
run_application :: proc(run_state: ^Run_State($T), title: string, width, height: int) -> host.Application {
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
	start :: proc(data: rawptr, waker: host.Application_Waker) {
		state := cast(^Run_State(T))data
		state.on_start(state.app, waker)
	}
	woken :: proc(data: rawptr, rt: ^alicorn.Runtime) {
		state := cast(^Run_State(T))data
		state.on_wake(state.app, Application_Context(rt))
	}
	stop :: proc(data: rawptr) {
		state := cast(^Run_State(T))data
		state.on_stop(state.app)
	}

	application := host.Application{
		state=rawptr(run_state),
		title=title,
		width=width,
		height=height,
		build=build,
		interaction_update_policy=.Correct_After_Interaction,
	}
	if run_state.on_start != nil { application.on_start = start }
	if run_state.on_wake != nil { application.on_wake = woken }
	if run_state.on_stop != nil { application.on_stop = stop }
	return application
}

// run borrows state until the synchronous native host returns. Optional hooks
// run on the application thread: on_start receives the borrowed worker waker;
// on_wake adopts results and explicitly invalidates through its context;
// on_stop stops and joins all producers before the host destroys the waker.
// Rendering uses the same bounded corrective-description policy as host.Run.
run :: proc(
	state: ^$T,
	render: proc(^T, ^UI),
	title: string = "Alicorn",
	width: int = 720,
	height: int = 480,
	render_overlays: proc(^T, ^UI) = nil,
	on_start: proc(^T, Application_Waker) = nil,
	on_wake: proc(^T, Application_Context) = nil,
	on_stop: proc(^T) = nil,
	smoke: bool = false,
) {
	run_state := Run_State(T){
		app=state, render=render, render_overlays=render_overlays,
		on_start=on_start, on_wake=on_wake, on_stop=on_stop,
	}
	host.Run(run_application(&run_state, title, width, height), smoke=smoke)
}
