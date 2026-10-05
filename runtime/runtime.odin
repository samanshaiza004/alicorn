package alicorn

import "core:mem"

Node_ID :: distinct u64

UI_Unkeyed :: struct {}

UI_Key_Pair :: struct {
	first:  u64,
	second: u64,
}

// UI_Key is the public identity value for repeated runtime data. The explicit
// unkeyed variant keeps the zero value safe and makes empty strings and zero
// numeric keys valid, distinct explicit identities.
UI_Key :: union #no_nil {
	UI_Unkeyed,
	string,
	u64,
	UI_Key_Pair,
}

key_string :: proc(value: string) -> UI_Key { return value }
key_u64    :: proc(value: u64) -> UI_Key { return value }
key_pair   :: proc(first, second: u64) -> UI_Key { return UI_Key_Pair{first, second} }

ui_key_is_explicit :: proc(key: UI_Key) -> bool {
	switch value in key {
	case UI_Unkeyed:
		return false
	case string, u64, UI_Key_Pair:
		return true
	}
	return false
}

Node_Kind :: enum {
	Root,
	Modal_Overlay,
	Context_Menu_Overlay,
	Context_Menu_Panel,
	Container,
	Button,
	Checkbox,
	Slider,
	Text,
	Text_Field,
	Text_Composition,
	Virtual_List,
	Virtual_Row,
	Scroll_Region,
	Split,
	Split_Handle,
	Custom_Surface,
}

Split_Axis :: enum { Horizontal, Vertical }

GPU_Surface_Kind :: enum {
	Waveform,
	Geometry,
}

// A GPU surface is presentation-only unless pointer interaction is explicitly
// requested by its declaration.
GPU_Surface_Interaction :: enum {
	Inert,
	Pointer,
}

// Versioned payload updates use a distinct type so they cannot be confused
// with a surface declaration or another application's unrelated counter.
GPU_Surface_Update_Revision :: distinct u64

// Geometry surfaces share the native SDL_GPU triangle budget. Transparent
// geometry emits no background vertices; a segment uses six vertices and a
// filled circle uses 16 fan triangles (48 vertices).
GPU_SURFACE_MAX_VERTICES :: 8192
GPU_SURFACE_CIRCLE_SEGMENTS :: 16

// Waveform surfaces reserve one six-vertex background quad and emit one
// six-vertex segment for each adjacent sample pair. This is the largest
// sample count whose complete mesh fits GPU_SURFACE_MAX_VERTICES.
GPU_SURFACE_MAX_WAVEFORM_SAMPLES :: GPU_SURFACE_MAX_VERTICES / 6

// GPU_Surface_Context is the backend-neutral placement contract. The runtime
// owns these values; a backend must not infer them from the window or retain an
// application pointer to obtain them later.
GPU_Surface_Context :: struct {
	logical_bounds: Rect,
	pixel_width:    int,
	pixel_height:   int,
	dpi_scale:      f32,
	clip:           Rect,
	payload_revision: GPU_Surface_Update_Revision,
}

// GPU_Surface_Payload_View is borrowed for the duration of one host render
// step. It contains resource data only; placement and clipping travel with the
// generic Paint_Command that refers to it.
GPU_Surface_Payload_View :: struct {
	revision: GPU_Surface_Update_Revision,
	samples:  []f32,
	segments: []GPU_Surface_Line_Segment,
	circles:  []GPU_Surface_Filled_Circle,
}

Layout_Direction :: enum { Row, Column }
Align :: enum { Start, Center, End, Stretch }

Button_Content_Alignment :: enum { Start, Center, End }

// Button_Content_Style controls only where a button places its label inside
// its outer bounds. It is independent from Layout_Style.padding, which pads
// children inside a layout container.
Button_Content_Style :: struct {
	horizontal: Button_Content_Alignment,
	vertical:   Button_Content_Alignment,
	padding_x:  f32,
	padding_y:  f32,
}

DEFAULT_BUTTON_CONTENT_STYLE :: Button_Content_Style{
	horizontal = .Center,
	vertical = .Center,
	padding_x = 8,
	padding_y = 4,
}

button_content_style :: proc(
	horizontal := Button_Content_Alignment.Center,
	vertical := Button_Content_Alignment.Center,
	padding_x: f32 = 8,
	padding_y: f32 = 4,
) -> Button_Content_Style {
	return Button_Content_Style{
		horizontal = horizontal,
		vertical = vertical,
		padding_x = maxf(padding_x, 0),
		padding_y = maxf(padding_y, 0),
	}
}

Layout_Style :: struct {
	direction: Layout_Direction,
	width:     f32,
	height:    f32,
	min_width: f32,
	max_width: f32,
	min_height: f32,
	max_height: f32,
	grow:      f32,
	padding:   f32,
	gap:       f32,
	align:     Align,
	clip:      bool,
}

Rect :: struct {
	x, y, w, h: f32,
}

Color :: struct {
	r, g, b, a: f32,
}

// Text_Paint_Span decorates a half-open UTF-8 byte range in a retained Text
// run. Foreground/background attributes are independent; later spans win for
// those attributes when set. Underline and strike are additive. These paint
// attributes never participate in shaping or layout.
Text_Paint_Span :: struct {
	start, end: int,
	color: Color,
	color_set: bool,
	underline: bool,
	strikethrough: bool,
	background: Color,
	background_set: bool,
}

// Text_Style_Span changes typography over a half-open UTF-8 byte range. These
// effects participate in shaping and can change glyph metrics; use paint spans
// for color and decorations that must preserve editor geometry. The last span
// that sets an attribute wins independently for weight and italic face.
Text_Style_Span :: struct {
	start, end: int,
	font_weight: f32,
	font_weight_set: bool,
	italic: bool,
	italic_set: bool,
}

text_style_span_has_effect :: proc(span: Text_Style_Span) -> bool {
	return span.font_weight_set || span.italic_set
}

text_paint_span_has_effect :: proc(span: Text_Paint_Span) -> bool {
	return span.color_set || span.background_set || span.underline || span.strikethrough
}

text_paint_color_for_cluster :: proc(spans: []Text_Paint_Span, cluster_start, cluster_end: int, fallback: Color) -> Color {
	result := fallback
	for span in spans {
		if span.color_set && span.start < cluster_end && span.end > cluster_start { result = span.color }
	}
	return result
}

// GPU_Surface_Point is expressed in logical coordinates local to the resolved
// bounds of its geometry surface.
GPU_Surface_Point :: struct {
	x, y: f32,
}

GPU_Surface_Line_Segment :: struct {
	start:     GPU_Surface_Point,
	end:       GPU_Surface_Point,
	thickness: f32,
	color:     Color,
}

GPU_Surface_Filled_Circle :: struct {
	center: GPU_Surface_Point,
	radius: f32,
	color:  Color,
}

Source_Site :: struct {
	file:      string,
	line:      int,
	column:    int,
	component: string,
}

Identity_Declaration_Kind :: enum { Node, Key_Scope, Numeric_Key_Scope }

// These records borrow call-site strings only until the current description
// finishes. Formatting/allocation is deferred until an actual collision.
Identity_Declaration :: struct {
	source:          Source_Site,
	parent:          Node_ID,
	kind:            Identity_Declaration_Kind,
	node_kind:       Node_Kind,
	label:           string,
	key:             UI_Key,
	scope_depth:     int,
	scope_key_kind:  u8,
	scope_key_text:  string,
	scope_key_u64:   u64,
	scope_key_pair:  UI_Key_Pair,
}

Pointer_Kind :: enum { Move, Down, Up, Cancel }

// Drag_Type is an application-defined local drag category. Alicorn only uses
// it to match a source to compatible targets; it does not interpret payloads.
Drag_Type :: distinct u64

Drop_Target_Mode :: enum {
	On,
	Between_Horizontal,
	Between_Vertical,
}

Drop_Position :: enum { None, On, Before, After }
Drag_Phase :: enum { Idle, Candidate, Dragging }
Drag_Event_Kind :: enum { Started, Target_Changed, Dropped, Cancelled }

Drag_Event :: struct {
	kind: Drag_Event_Kind,
	drag_type: Drag_Type,
	source: Semantic_ID,
	previous_target: Semantic_ID,
	target: Semantic_ID,
	position: Drop_Position,
}

Drag_Session :: struct {
	phase: Drag_Phase,
	drag_type: Drag_Type,
	source: Semantic_ID,
	source_node: Node_ID, // presentation hint only; never the source identity
	start_x, start_y: f32,
	x, y: f32,
	target: Semantic_ID,
	target_node: Node_ID, // presentation hint only; never the target identity
	position: Drop_Position,
	target_mode: Drop_Target_Mode,
}

// Drag_Preview is a small runtime-owned presentation snapshot. The shaped run
// remains available while a virtualized source row is temporarily unrealized.
Drag_Preview :: struct {
	run: Text_Run,
	run_generation: u64,
	width, height: f32,
	ready: bool,
}

DRAG_START_THRESHOLD :: 5.0

Input_Modifiers :: struct {
	shift:   bool,
	control: bool,
	alt:     bool,
	super:   bool,
}

Pointer_Event :: struct {
	kind:        Pointer_Kind,
	x, y:        f32,
	button:      int,
	modifiers:   Input_Modifiers, // keyboard modifiers held when the host dispatches this event
	click_count: u8,               // platform click sequence count for button events; zero when unavailable
	timestamp_ns: u64,             // monotonic host time used by delayed interactions; zero for synthetic events
	// target_key is filled by the native host after hit testing and is available
	// to application pointer callbacks. Direct process_pointer callers should
	// use the returned Node_ID with node_identity_key when they need the key.
	target_key:  UI_Key,
}

POINTER_BUTTON_PRIMARY :: 1
POINTER_BUTTON_MIDDLE :: 2
POINTER_BUTTON_SECONDARY :: 3

// Scroll_Event preserves both precise device deltas and whole wheel ticks.
// The precise deltas are authoritative for scrolling. Whole ticks remain
// available to diagnostics and applications that explicitly need coarse
// wheel semantics.
Scroll_Event :: struct {
	delta_x: f32,
	delta_y: f32,
	ticks_x: int,
	ticks_y: int,
	x, y:    f32,
	modifiers: Input_Modifiers,
}

// Scroll_Axes describes which directions a retained region accepts. A region
// that accepts both directions can choose whether small perpendicular motion
// is suppressed for code/list-style scrolling or preserved for a free-form
// canvas.
Scroll_Axes :: enum {
	Vertical,
	Horizontal,
	Both,
}

Scroll_Axis_Behavior :: enum {
	Auto_Lock,
	Free,
}

// Scrollbar_Policy controls the solid, layout-reserving bars retained by a
// scroll region. Auto is the default and shows only bars needed by its content.
Scrollbar_Policy :: enum { Hidden, Auto, Always }
Scroll_Axis :: enum { Horizontal, Vertical }
SCROLLBAR_THICKNESS :: f32(12)
SCROLLBAR_MIN_THUMB :: f32(24)

Text_Edit_Kind :: enum { Insert, Backspace, Delete }

Text_Edit :: struct {
	kind: Text_Edit_Kind,
	text: string,
}

// Font_Role selects one of the runtime's small built-in text roles. Applications
// may load a role-specific font; an unloaded role falls back to the UI font.
Font_Role :: enum {
	UI,
	Monospace,
}

Text_Overflow :: enum {
	Wrap,
	Clip,
	Ellipsis,
}

Style_Theme_ID :: distinct u32
Style_Accent :: distinct u32

Style_Color_Role :: enum {
	Window_Background,
	Surface,
	Subtle_Surface,
	Editor_Background,
	Text,
	Muted_Text,
	Accent,
	Accent_Hover,
	Accent_Pressed,
	Accent_Text,
	Selection,
	Focus,
	Semantic_Focus,
	Border,
	Danger,
	Success,
	Scrollbar_Track,
	Scrollbar_Thumb,
	Count,
}

STYLE_COLOR_ROLE_COUNT :: int(Style_Color_Role.Count)

// Button variants express component intent. They all resolve through one
// recipe family so themes do not need a separate state table per product
// control.
Button_Variant :: enum {
	Default,
	Primary,
	Toolbar,
	Quiet,
	Tab,
	Count,
}

BUTTON_VARIANT_COUNT :: int(Button_Variant.Count)

// Style_Transform blends semantic surface/text roles into the current recipe
// result. A zero mix leaves that channel unchanged; one replaces it. State
// transforms compose in the documented selected → hovered → pressed →
// disabled order.
Style_Transform :: struct {
	surface_role: Style_Color_Role,
	surface_mix:  f32,
	text_role:    Style_Color_Role,
	text_mix:     f32,
}

Button_Recipe :: struct {
	defined:                bool,
	surface_role:           Style_Color_Role,
	text_role:              Style_Color_Role,
	surface_visible:        bool,
	selected:               Style_Transform,
	hovered:                Style_Transform,
	pressed:                Style_Transform,
	disabled:               Style_Transform,
	selected_indicator:     Button_Indicator,
	selected_indicator_role: Style_Color_Role,
	focus_role:             Style_Color_Role,
	semantic_active_role:   Style_Color_Role,
}

Button_Recipe_Set :: struct {
	recipes: [BUTTON_VARIANT_COUNT]Button_Recipe,
}

Button_Indicator :: enum { None, Underline }

Style_Button_State :: enum { Selected, Hovered, Pressed, Disabled }
Style_Button_States :: distinct bit_set[Style_Button_State; u8]

Button_Visual_State :: struct {
	selected: bool,
	hovered:  bool,
	pressed:  bool,
	disabled: bool,
}

// This is the resolved output of the button recipe family, not a general
// computed-style cache. Focus and semantic-active remain separate overlays.
Button_Resolved_Style :: struct {
	surface:                 Color,
	text:                    Color,
	focus:                   Color,
	semantic_active:         Color,
	selected_indicator:      Button_Indicator,
	selected_indicator_color: Color,
	applied_transforms:      Style_Button_States,
}

// Style_Provenance retains semantic inputs, not duplicated theme data. Token
// IDs and role-to-value mapping are derived from the immutable theme while an
// inspector query is formatted. Alias names/spans remain compiler debug data.
Style_Provenance :: struct {
	theme:          Style_Theme_ID,
	accent:         Style_Accent,
	variant:        u8,
	state_bits:     u8,
	drop_target_on: bool,
}

// Computed_Style retains the resolved recipe result, its domain dependencies,
// and the dependency generations/provenance that produced it. The first
// recipe-family payload is the button style; cache metadata is shared.
Computed_Style :: struct {
	button:       Button_Resolved_Style,
	dependencies: Style_Domains,
	generations:  Style_Generations,
	provenance:   Style_Provenance,
	valid:        bool,
}

DEFAULT_BUTTON_RECIPES :: Button_Recipe_Set{recipes={
	Button_Recipe{
		defined=true, surface_role=.Subtle_Surface, text_role=.Text, surface_visible=true,
		selected=Style_Transform{surface_role=.Accent, surface_mix=0.24},
		hovered=Style_Transform{surface_role=.Surface, surface_mix=0.60},
		pressed=Style_Transform{surface_role=.Border, surface_mix=0.45},
		disabled=Style_Transform{surface_role=.Surface, surface_mix=1, text_role=.Muted_Text, text_mix=1},
		selected_indicator_role=.Text,
		focus_role=.Focus, semantic_active_role=.Semantic_Focus,
	},
	Button_Recipe{
		defined=true, surface_role=.Accent, text_role=.Accent_Text, surface_visible=true,
		selected=Style_Transform{surface_role=.Accent_Hover, surface_mix=0.35},
		hovered=Style_Transform{surface_role=.Accent_Hover, surface_mix=1},
		pressed=Style_Transform{surface_role=.Accent_Pressed, surface_mix=1},
		disabled=Style_Transform{surface_role=.Subtle_Surface, surface_mix=1, text_role=.Muted_Text, text_mix=1},
		selected_indicator_role=.Text,
		focus_role=.Focus, semantic_active_role=.Semantic_Focus,
	},
	Button_Recipe{
		defined=true, surface_role=.Surface, text_role=.Text, surface_visible=true,
		selected=Style_Transform{surface_role=.Accent, surface_mix=0.22},
		hovered=Style_Transform{surface_role=.Subtle_Surface, surface_mix=0.70},
		pressed=Style_Transform{surface_role=.Border, surface_mix=0.55},
		disabled=Style_Transform{surface_role=.Window_Background, surface_mix=1, text_role=.Muted_Text, text_mix=1},
		selected_indicator_role=.Text,
		focus_role=.Focus, semantic_active_role=.Semantic_Focus,
	},
	Button_Recipe{
		defined=true, surface_role=.Subtle_Surface, text_role=.Text, surface_visible=false,
		selected=Style_Transform{surface_role=.Accent, surface_mix=0.18},
		hovered=Style_Transform{surface_role=.Subtle_Surface, surface_mix=1},
		pressed=Style_Transform{surface_role=.Border, surface_mix=1},
		disabled=Style_Transform{text_role=.Muted_Text, text_mix=1},
		selected_indicator_role=.Text,
		focus_role=.Focus, semantic_active_role=.Semantic_Focus,
	},
	Button_Recipe{
		defined=true, surface_role=.Subtle_Surface, text_role=.Muted_Text, surface_visible=false,
		selected=Style_Transform{surface_role=.Subtle_Surface, surface_mix=1, text_role=.Text, text_mix=1},
		hovered=Style_Transform{surface_role=.Subtle_Surface, surface_mix=0.55, text_role=.Text, text_mix=0.45},
		pressed=Style_Transform{surface_role=.Border, surface_mix=0.4},
		disabled=Style_Transform{text_role=.Muted_Text, text_mix=1},
		selected_indicator=.Underline,
		selected_indicator_role=.Text,
		focus_role=.Focus, semantic_active_role=.Semantic_Focus,
	},
}}

// A registered theme is immutable and retained once per Runtime. Nodes carry
// only the compact ID through Style_Environment, not a copy of this palette.
Style_Theme :: struct {
	colors:                 [STYLE_COLOR_ROLE_COUNT]Color,
	button_recipes:         Button_Recipe_Set,
	text_field_recipe:      Text_Field_Recipe,
	scrollbar_recipe:       Scrollbar_Recipe,
	color_tokens:           []Color,
	length_tokens:          []Style_Length,
	core_color_tokens:      [STYLE_COLOR_ROLE_COUNT]Style_Color_Token_ID,
	extension_color_roles:  []Style_Extension_Color_Role_Binding,
	extension_length_roles: []Style_Extension_Length_Role_Binding,
}

DEFAULT_STYLE_THEME :: Style_Theme{colors={
	Color{0.055, 0.065, 0.09, 1},
	Color{0.08, 0.095, 0.13, 1},
	Color{0.08, 0.10, 0.14, 1},
	Color{0.04, 0.05, 0.07, 1},
	Color{0.88, 0.91, 0.96, 1},
	Color{0.57, 0.63, 0.74, 1},
	Color{0.27, 0.48, 0.70, 1},
	Color{0.33, 0.57, 0.80, 1},
	Color{0.36, 0.62, 0.86, 1},
	Color{0.94, 0.97, 1, 1},
	Color{0.20, 0.42, 0.78, 0.45},
	Color{0.76, 0.86, 1, 1},
	Color{0.12, 0.78, 0.82, 1},
	Color{0.20, 0.24, 0.31, 1},
	Color{0.55, 0.18, 0.20, 1},
	Color{0.17, 0.39, 0.34, 1},
	Color{0.08, 0.10, 0.14, 1},
	Color{0.38, 0.48, 0.62, 1},
}, button_recipes=DEFAULT_BUTTON_RECIPES, text_field_recipe=DEFAULT_TEXT_FIELD_RECIPE, scrollbar_recipe=DEFAULT_SCROLLBAR_RECIPE}

DEFAULT_STYLE_THEME_ID :: Style_Theme_ID(1)

// Style_Environment contains intentionally subtree-wide presentation inputs.
// Zero values in a pushed environment mean "inherit"; this keeps compact
// scopes such as Style_Environment{text_scale=1.25} composable.
Style_Environment :: struct {
	theme: Style_Theme_ID,
	density: f32,
	text_scale: f32,
	accent: Style_Accent,
}

DEFAULT_STYLE_ENVIRONMENT :: Style_Environment{
	theme=DEFAULT_STYLE_THEME_ID,
	density=1,
	text_scale=1,
}

Style_Environment_Scope :: struct {
	runtime: ^Runtime,
	previous: Style_Environment,
	depth: int,
	active: bool,
}

Style_Domain :: enum {
	Metrics,
	Typography,
	Paint,
	Material,
}

Style_Domains :: distinct bit_set[Style_Domain; u8]

// Generations are local to a retained node. A scope change advances only the
// nodes whose inherited environment changed, leaving sibling caches intact.
// u32 keeps retained-node growth bounded; reconciliation invalidates a style
// cache if a counter wraps before its generation can be reused.
Style_Generations :: struct {
	metrics:    u32,
	typography: u32,
	paint:      u32,
	material:   u32,
}

// Text_Style controls typography and single-line overflow independently from
// Layout_Style. Font weight is an OpenType `wght` user coordinate; 400 is the
// default regular face. Wrap remains the backwards-compatible default.
Text_Style :: struct {
	font_weight: f32,
	overflow:    Text_Overflow,
}

FONT_WEIGHT_REGULAR :: f32(400)
FONT_WEIGHT_MEDIUM :: f32(500)
FONT_WEIGHT_SEMIBOLD :: f32(600)
FONT_WEIGHT_BOLD :: f32(700)

DEFAULT_TEXT_STYLE :: Text_Style{font_weight=FONT_WEIGHT_REGULAR}
// Button labels are single-line controls by default. Callers that intentionally
// need a multiline button can opt into Text_Overflow.Wrap explicitly.
DEFAULT_BUTTON_TEXT_STYLE :: Text_Style{font_weight=FONT_WEIGHT_REGULAR, overflow=.Ellipsis}

Button_State :: struct {
	selected: bool,
	disabled: bool,
	// Deprecated compatibility flag. New code should use Button_Variant.Quiet.
	quiet:    bool,
}

// Control_Change is the result of a controlled widget. The application owns
// the value and should store `value` when `changed` is true.
Control_Change_Bool :: struct {
	value:   bool,
	changed: bool,
}

Control_Change_F32 :: struct {
	value:   f32,
	changed: bool,
}

// Text_Composition is transient interaction state owned by one retained text
// field. Its text is an owned copy of the platform preedit string and is never
// silently written into the application's committed value. The replacement
// positions are captured when composition begins so repeated platform updates
// continue to edit the same committed selection until a commit arrives.
Text_Composition :: struct {
	active:          bool,
	text:            string,
	selection_start: int,
	selection_end:   int,
	replace_anchor:  Text_Position,
	replace_focus:   Text_Position,
}

Text_Change :: struct {
	node: Node_ID,
	text: string,
	changed: bool,
}

// Text_Input_Area is the native platform's candidate-window anchor in logical
// client coordinates. cursor_x is relative to rect.x, matching SDL's input
// area contract while remaining independent of any particular widget kind.
Text_Input_Area :: struct {
	rect: Rect,
	cursor_x: f32,
}

Dirty_Stage :: enum {
	Description,
	Layout,
	Paint,
	Composite,
}

Dirty_Stages :: distinct bit_set[Dirty_Stage; u8]

dirty_has :: proc(dirty: Dirty_Stages, stage: Dirty_Stage) -> bool {
	return stage in dirty
}

dirty_set :: proc(dirty: ^Dirty_Stages, stage: Dirty_Stage, value: bool) {
	if value { dirty^ += {stage} } else { dirty^ -= {stage} }
}

Runtime_Stage :: enum {
	Description,
	Reconcile,
	Layout,
	Paint,
	Composite,
}

Runtime_Allocation_Stats :: struct {
	persistent_alloc_calls:          u64,
	persistent_free_calls:           u64,
	persistent_requested_bytes_live: i64,
	persistent_requested_bytes_peak: i64,
	scratch_alloc_calls:             u64,
	scratch_requested_bytes_epoch:   u64,
	scratch_requested_bytes_peak:    u64,
	scratch_resets:                  u64,
}

Runtime_Config :: struct {
	persistent_allocator:      mem.Allocator,
	scratch_backing_allocator: mem.Allocator,
	trace_capacity:            int,
	allocation_stats:          ^Runtime_Allocation_Stats,
}

Description :: struct {
	id:          Node_ID,
	parent:      Node_ID,
	site:        Source_Site,
	key:         string,
	explicit_key: bool,
	identity_key_kind: u8,
	identity_key_pair: UI_Key_Pair,
	kind:        Node_Kind,
	label:       string,
	text:        string,
	tooltip_text: string,
	tooltip_delay_ms: u32,
	text_paint_spans: []Text_Paint_Span,
	text_style_spans: []Text_Style_Span,
	font:        Font_Role,
	text_style:  Text_Style,
	style_environment: Style_Environment,
	style_scope_boundary: bool,
	button_content_style: Button_Content_Style,
	button_variant: Button_Variant,
	style:       Layout_Style,
	context_menu_bounds: Rect,
	color:       Color,
	paint_background: bool,
	paint_value: u64,
	control_value: f32,
	control_minimum: f32,
	control_maximum: f32,
	control_step: f32,
	region_revision: u64,
	region:      bool,
	focusable:   bool,
	text_input_target: bool,
	text_interaction: bool,
	text_interaction_anchor: Text_Position,
	text_interaction_focus: Text_Position,
	text_interaction_show_caret: bool,
	visual_row_text_node: Node_ID,
	visual_row_position: Text_Position,
	visual_row_color: Color,
	visual_row_enabled: bool,
	selected:    bool,
	semantic_id: Semantic_ID,
	drag_source_type: Drag_Type,
	drag_source_id: Semantic_ID,
	drop_target_type: Drag_Type,
	drop_target_id: Semantic_ID,
	drop_target_mode: Drop_Target_Mode,
	disabled:    bool,
	identity_key: string,
	identity_key_u64: u64,
	identity_key_numeric: bool,
	surface_kind: GPU_Surface_Kind,
	surface_interaction: GPU_Surface_Interaction,
	surface_pixel_width: int,
	surface_pixel_height: int,
	surface_dpi_scale: f32,
	scroll_offset_y: f32,
	scroll_offset_x: f32,
	scroll_content_height: f32,
	scroll_viewport_height: f32,
	scroll_line_height: f32,
	scroll_content_width: f32,
	scroll_viewport_width: f32,
	scroll_line_width: f32,
	scroll_axes: Scroll_Axes,
	scroll_axis_behavior: Scroll_Axis_Behavior,
	scrollbar_policy: Scrollbar_Policy,
	split_axis: Split_Axis,
	split_position: f32,
	split_min_first: f32,
	split_min_second: f32,
	split_owner: Node_ID,
	split_handle_size: f32,
	split_hit_size: f32,
	// The logical scroll position remains authoritative for application state
	// and scrollbar calculations. Virtualized lists use this residual offset
	// to place only the realized rows after preceding rows were omitted.
	layout_scroll_offset_y: f32,
	layout_scroll_offset_x: f32,
}

Pending_Kind :: enum {
	Description,
	Reuse_Subtree,
}

Pending_Item :: struct {
	kind:        Pending_Kind,
	description: Description,
	subtree:     Node_ID,
	semantic_surface_style: Semantic_Surface_Style,
}

Node :: struct {
	id:          Node_ID,
	parent:      Node_ID,
	children:    [dynamic]Node_ID,
	site:        Source_Site,
	key:         string,
	explicit_key: bool,
	kind:        Node_Kind,
	label:       string,
	text:        string,
	tooltip_text: string,
	tooltip_delay_ms: u32,
	text_paint_spans: [dynamic]Text_Paint_Span,
	text_style_spans: [dynamic]Text_Style_Span,
	font:        Font_Role,
	text_style:  Text_Style,
	style_environment: Style_Environment,
	style_scope_boundary: bool,
	style_generations: Style_Generations,
	button_content_style: Button_Content_Style,
	button_variant: Button_Variant,
	computed_style: Computed_Style,
	style:       Layout_Style,
	context_menu_bounds: Rect,
	color:       Color,
	paint_background: bool,
	paint_value: u64,
	control_value: f32,
	control_minimum: f32,
	control_maximum: f32,
	control_step: f32,
	region_revision: u64,
	region:      bool,
	region_cached: bool,
	focusable:   bool,
	text_input_target: bool,
	text_input_target_suspended: bool,
	text_interaction: bool,
	text_interaction_anchor: Text_Position,
	text_interaction_focus: Text_Position,
	text_interaction_show_caret: bool,
	visual_row_text_node: Node_ID,
	visual_row_position: Text_Position,
	visual_row_color: Color,
	visual_row_enabled: bool,
	text_input_area: Text_Input_Area,
	text_input_area_set: bool,
	disabled:    bool,
	active:      bool,
	present:     bool,
	hovered:     bool,
	pressed:     bool,
	selected:    bool,
	semantic_id: Semantic_ID,
	drag_source_type: Drag_Type,
	drag_source_id: Semantic_ID,
	drop_target_type: Drag_Type,
	drop_target_id: Semantic_ID,
	drop_target_mode: Drop_Target_Mode,
	drop_position: Drop_Position,
	semantic_active: bool,
	last_consumed_activation: u64,
	control_pending: bool,
	control_pending_value: f32,
	caret:       Text_Position,
	selection_anchor: Text_Position,
	selection_focus:  Text_Position,
	local_counter: int,
	identity_key: string,
	identity_key_u64: u64,
	identity_key_numeric: bool,
	identity_key_kind: u8,
	identity_key_pair: UI_Key_Pair,
	surface_kind: GPU_Surface_Kind,
	surface_interaction: GPU_Surface_Interaction,
	surface_pixel_width: int,
	surface_pixel_height: int,
	surface_dpi_scale: f32,
	scroll_offset_y: f32,
	scroll_offset_x: f32,
	layout_scroll_offset_y: f32,
	layout_scroll_offset_x: f32,
	scroll_content_height: f32,
	scroll_viewport_height: f32,
	scroll_line_height: f32,
	scroll_content_width: f32,
	scroll_viewport_width: f32,
	scroll_line_width: f32,
	scroll_axes: Scroll_Axes,
	scroll_axis_behavior: Scroll_Axis_Behavior,
	scrollbar_policy: Scrollbar_Policy,
	scrollbar_vertical_visible: bool,
	scrollbar_horizontal_visible: bool,
	scroll_viewport_bounds: Rect,
	scroll_geometry_resolved: bool,
	scrollbar_vertical_track: Rect,
	scrollbar_vertical_thumb: Rect,
	scrollbar_horizontal_track: Rect,
	scrollbar_horizontal_thumb: Rect,
	split_axis: Split_Axis,
	split_position: f32,
	split_min_first: f32,
	split_min_second: f32,
	split_owner: Node_ID,
	split_handle_size: f32,
	split_hit_size: f32,
	split_drag_start_position: f32,
	split_drag_start_coordinate: f32,
	split_dragging: bool,
	surface_payload_revision: GPU_Surface_Update_Revision,
	surface_samples: [dynamic]f32,
	surface_geometry_active: bool,
	surface_segments: [dynamic]GPU_Surface_Line_Segment,
	surface_circles: [dynamic]GPU_Surface_Filled_Circle,
	bounds:      Rect,
	hit_bounds:  Rect,
	clip:        Rect,
	dirty:       Dirty_Stages,
	last_reason: string,
	description_hash: u64,
	layout_hash: u64,
	paint_hash: u64,
	text_run:  Text_Run,
	text_run_valid: bool,
	text_run_generation: u64,
	text_run_handle_generation: u64,
	composition: Text_Composition,
	composition_run: Text_Run,
	composition_run_valid: bool,
	composition_run_generation: u64,
	composition_run_handle_generation: u64,
	paint:       [dynamic]Paint_Command,
	surface_resource_generation: u64,
	display_index: int,
	paint_queued: bool,
	layout_root_queued: bool,
}

Cause_Kind :: enum {
	None,
	Pointer,
	Keyboard,
	Text_Input,
	Text_Composition,
	Scroll,
	Native_Command,
	Async_Wake,
	Scheduled_Wake,
	Application,
	Host_Event,
}

// Action_ID identifies an application-owned operation independently of the
// input path that invoked it. Zero is reserved for events without an action.
Action_ID :: distinct u32

// Semantic_ID names an application entity independently from any retained
// node that happens to present it. Namespace separates domains whose numeric
// values may overlap; namespace zero is reserved for "no semantic entity".
Semantic_ID :: struct {
	namespace: u64,
	value:     u64,
}

Semantic_Focus_State :: struct {
	id:            Semantic_ID,
	owner:         Node_ID,
	realized_node: Node_ID,
}

Action_Descriptor :: struct {
	id:    Action_ID,
	name:  string,
	label: string,
}

// Action state is explicit application data. Updating it has no observable
// side effects; applications publish it when their state changes.
Action_State :: struct {
	enabled: bool,
	checked: bool,
}

Context_Menu_State :: struct {
	open: bool,
	dismissed: bool,
	described: bool,
	pointer_consumed: bool,
	focus_initial_pending: bool,
	anchor: Rect,
	panel_bounds: Rect,
	restore_focus: Node_ID,
	overlay: Node_ID,
	panel: Node_ID,
	preferred_width: f32,
	item_height: f32,
	separator_height: f32,
	padding: f32,
	content_height: f32,
	item_index: int,
	activation_action: Action_ID,
	pending_start: int,
}

Context_Menu_Key :: enum {
	Other,
	Up,
	Down,
	Home,
	End,
	Activate,
	Cancel,
}

Tooltip_State :: struct {
	target: Node_ID,
	deadline_ns: u64,
	visible: bool,
	run: Text_Run,
	run_ready: bool,
	run_generation: u64,
}

Transient_Overlay_Kind :: enum {
	None,
	Drag_Preview,
	Tooltip,
}

Action_Entry :: struct {
	descriptor: Action_Descriptor,
	state:      Action_State,
	name_owned: bool,
	label_owned: bool,
}

Cause_Context :: struct {
	id: u64,
	kind: Cause_Kind,
	action_id: Action_ID,
}

Cause_Scope :: struct {
	previous: Cause_Context,
	cause: Cause_Context,
	clear_pointer_gesture: bool,
}

Trace_Kind :: enum {
	Cause,
	Action,
	Mutation,
	Pointer,
	Focus,
	Invalidation,
	Reconcile,
	Layout,
	Paint,
	Composite,
	Submit,
	Retire,
}

Trace_Event :: struct {
	sequence: u64,
	kind:     Trace_Kind,
	cause_id: u64,
	cause_kind: Cause_Kind,
	action_id: Action_ID,
	node:     Node_ID,
	reason:   string,
	reason_owned: bool,
}

Trace_Ring :: struct {
	events: [dynamic]Trace_Event,
	next:   int,
	count:  int,
	sequence: u64,
}

Frame_Stats :: struct {
	frame:             u64,
	frames_built:      u64,
	idle_frames:       u64,
	descriptions_emitted: u64,
	descriptions_reused:  u64,
	regions_skipped:   u64,
	retained_subtrees_reused: u64,
	nodes_created:     u64,
	nodes_retired:     u64,
	reconcile_nodes_visited: u64,
	layout_nodes_visited: u64,
	paint_nodes_visited: u64,
	composition_nodes_visited: u64,
	stage_visits:      [Runtime_Stage]u64,
	layout_updates:    u64,
	paint_updates:     u64,
	composite_updates:  u64,
	adjacency_rebuilds: u64,
	// pointer_events counts delivered runtime pointer events. Hover transitions
	// count target identity changes, not every motion within an unchanged target.
	pointer_events:    u64,
	hover_target_transitions: u64,
	gpu_submits:       u64,
	surface_updates:  u64,
	surface_frames_consumed: u64,
	surface_geometry_updates: u64,
	surface_geometry_overflow_rejections: u64,
	surface_clear_count: u64,
	surface_stale_update_rejections: u64,
}

// Runtime's fields remain exported because Odin does not support private
// struct fields. Applications should treat them as implementation details and
// use the query and mutation procedures in this package instead. The fields
// can change between releases without preserving application compatibility.
Runtime :: struct {
	persistent_backing_allocator: mem.Allocator,
	persistent_allocator:      mem.Allocator,
	scratch_backing_allocator: mem.Allocator,
	scratch_arena:             ^mem.Dynamic_Arena,
	scratch_allocator:         mem.Allocator,
	allocation_stats:          ^Runtime_Allocation_Stats,
	allocation_stats_owned:    bool,
	persistent_allocator_state: ^Runtime_Allocator_State,
	scratch_allocator_state:    ^Runtime_Allocator_State,
	nodes:       map[Node_ID]^Node,
	semantic_surfaces: map[Node_ID]Semantic_Surface_Style,
	order:       [dynamic]Node_ID,
	top_level:   [dynamic]Node_ID,
	pending:     [dynamic]Pending_Item,
	seen:        map[Node_ID]Identity_Declaration,
	identity_scopes: map[Node_ID]Identity_Declaration,
	stack:       [dynamic]Node_ID,
	identity_stack: [dynamic]Node_ID,
	identity_labels: [dynamic]string,
	identity_key_u64: [dynamic]u64,
	identity_key_numeric: [dynamic]bool,
	identity_key_kind: [dynamic]u8,
	identity_key_pair: [dynamic]UI_Key_Pair,
	viewport:    Rect,
	style_environment: Style_Environment,
	style_themes: [dynamic]Style_Theme,
	style_materials: [dynamic]Style_Material,
	style_scope_stack: [dynamic]Style_Environment_Scope,
	layout_roots: [dynamic]Node_ID,
	layout_visit_probe: map[Node_ID]u64,
	focused:     Node_ID,
	context_menu: Context_Menu_State,
	tooltip: Tooltip_State,
	transient_overlay_kind: Transient_Overlay_Kind,
	selected:    Node_ID,
	semantic_focus: Semantic_Focus_State,
	last_hovered: Node_ID,
	captured_node: Node_ID,
	drag: Drag_Session,
	drag_preview: Drag_Preview,
	drag_event: Drag_Event,
	drag_event_pending: bool,
	scrollbar_drag_node: Node_ID,
	scrollbar_drag_axis: Scroll_Axis,
	scrollbar_drag_pointer_origin: f32,
	scrollbar_drag_offset_origin: f32,
	activation_node: Node_ID,
	activation_sequence: u64,
	paint_queue: [dynamic]Node_ID,
	composition_rebuild: bool,
	invalidated: bool,
	layout_pending: bool,
	// presentation_pending means retained interaction/presentation work is
	// ready to submit, but the application description is still valid. It is
	// deliberately separate from invalidated so hover can repaint without
	// re-running application code.
	presentation_pending: bool,
	// presentation_revision identifies the newest retained display state. A
	// native host acknowledges it only after a successful GPU submission;
	// keeping the two generations separate preserves pending work when a
	// swapchain has no drawable texture for a loop iteration.
	presentation_revision: u64,
	submitted_revision:    u64,
	frame_open:  bool,
	hard_error:  bool,
	diagnostic:  string,
	last_invalidation_reason: string,
	stats:       Frame_Stats,
	trace:       Trace_Ring,
	actions:     [dynamic]Action_Entry,
	cause_sequence: u64,
	active_cause: Cause_Context,
	frame_cause: Cause_Context,
	pending_work_cause: Cause_Context,
	pending_work_seen: bool,
	pending_work_mixed: bool,
	pointer_gesture_cause: Cause_Context,
	submission_cause: Cause_Context,
	submission_cause_seen: bool,
	submission_cause_mixed: bool,
	display:     [dynamic]Paint_Command,
	paint_resource_generation: u64,
	text_engine: Text_Engine,
	text_font_generation_seen: u64,
	surface_frame_pending: bool,
	scroll_geometry_changed: bool,
	// A retained-only pane resize can change how many fixed-height rows a
	// virtual list must describe. Geometry surfaces separately invalidate on
	// extent changes because their payload coordinates are app-authored.
	virtual_viewport_changed: bool,
	// Geometry payloads are projected in application-authored logical bounds.
	// A retained-only resize must request one description rebuild so the app
	// can reproject; translating a surface does not change that projection.
	geometry_surface_bounds_changed: bool,
}

UI :: struct {
	runtime: ^Runtime,
}
