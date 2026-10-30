package alicorn

import "core:mem"
import text_selection "../text_interaction"

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
	Grid,
	Button,
	// Deprecated compatibility kinds. TabBar now composes ordinary Buttons
	// and visual-part children; these values remain for existing API callers.
	Tab,
	Tab_Close,
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
	Image,
}

// Visual parts describe the meaning of retained presentation nodes without
// changing their interaction semantics. Applications may use a namespaced ID
// when the core roles do not describe a product-specific part.
Visual_Part_Core_ID :: enum {
	Surface,
	Content,
	Label,
	Icon,
	Indicator,
	Selected_Indicator,
	Overlay,
	Focus_Indicator,
	Count,
}

Visual_Part_Extension_ID :: distinct u64
Visual_Part_ID :: union #no_nil { Visual_Part_Core_ID, Visual_Part_Extension_ID }

Visual_Part_Visibility :: enum {
	Always,
	Owner_Hovered,
	Owner_Selected_Or_Hovered,
	Owner_Not_Hovered,
}

// Visual_Part_Style lives in Runtime side storage rather than Node or
// Description. Visibility is deliberately limited to reusable owner-state
// conditions; layout and positioning remain ordinary retained layout.
Visual_Part_Style :: struct {
	defined: bool,
	owner: Node_ID,
	identity: Visual_Part_ID,
	visibility: Visual_Part_Visibility,
	reveal_on_direct_hover: bool,
}

visual_part_core :: proc(role: Visual_Part_Core_ID) -> Visual_Part_ID { return role }

visual_part_extension_id :: proc(namespace, name: string) -> Visual_Part_ID {
	return Visual_Part_Extension_ID(style_extension_role_hash(namespace, name, 3))
}

visual_part_identity_is_valid :: proc(identity: Visual_Part_ID) -> bool {
	switch value in identity {
	case Visual_Part_Core_ID:
		return value >= .Surface && value < .Count
	case Visual_Part_Extension_ID:
		return value != 0
	}
	return false
}

visual_part_identity_hash :: proc(identity: Visual_Part_ID) -> u64 {
	switch value in identity {
	case Visual_Part_Core_ID:
		return hash_mix(1, u64(value))
	case Visual_Part_Extension_ID:
		return hash_mix(2, u64(value))
	}
	return 0
}

visual_part_style_hash :: proc(style: Visual_Part_Style) -> u64 {
	if !style.defined { return 0 }
	h := hash_mix(1469598103934665603, u64(style.owner))
	h = hash_mix(h, visual_part_identity_hash(style.identity))
	h = hash_mix(h, u64(style.visibility))
	h = hash_mix(h, 1 if style.reveal_on_direct_hover else 0)
	return h
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

Layout_Direction :: enum u8 { Row, Column }
Align :: enum u8 { Start, Center, End, Stretch, Baseline }
Main_Axis_Distribution :: enum u8 { Start, Center, End, Space_Between, Space_Around }
Writing_Direction :: enum u8 { Inherit, Left_To_Right, Right_To_Left }
Layout_Options :: distinct u8

layout_options_make :: proc(distribution: Main_Axis_Distribution, direction: Writing_Direction) -> Layout_Options {
	return Layout_Options(u8(distribution)&0x07 | ((u8(direction)&0x03)<<3))
}

layout_options_distribution :: proc(options: Layout_Options) -> Main_Axis_Distribution {
	return Main_Axis_Distribution(u8(options)&0x07)
}

layout_options_writing_direction :: proc(options: Layout_Options) -> Writing_Direction {
	return Writing_Direction((u8(options)>>3)&0x03)
}

Button_Content_Alignment :: enum { Start, Center, End }

// Tab_Close_Policy controls the embedded close affordance without changing
// the tab's geometry. Auto keeps it visible at comfortable widths and reveals
// it on hover for compact tabs.
Tab_Close_Policy :: enum { Always, Hover, Selected_Or_Hover, Auto }

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
	compress_weight: u8,
	options:   Layout_Options,
}

Grid_Track_Kind :: enum u8 { Fixed, Auto, Fraction, Min_Max }

Grid_Track :: struct {
	kind: Grid_Track_Kind,
	value: f32,
	minimum: f32,
	maximum: f32,
}

Grid_Item_Alignment :: enum u8 { Stretch, Start, Center, End, Baseline }

// LAYOUT_SIZE_FIT_CONTENT is an opt-in Layout_Style width/height value.
// Retained content-height measurement supports Row and Column Containers and
// Scroll_Region viewports; ordinary -1 dimensions keep their existing
// externally allocated behavior.
LAYOUT_SIZE_FIT_CONTENT :: f32(-2)

Rect :: struct {
	x, y, w, h: f32,
}

// Layout_Unit is an experimental fixed-point scalar for retained measurement
// products. Public layout styles and Rect remain f32 during this contract
// slice; conversion is centralized at the measurement/geometry boundary.
Layout_Unit :: distinct i64

Layout_Size :: struct {
	width:  Layout_Unit,
	height: Layout_Unit,
}

Layout_Axis_Constraint :: struct {
	min: Layout_Unit,
	max: Layout_Unit,
	unbounded_max: bool,
}

Layout_Constraints :: struct {
	width:  Layout_Axis_Constraint,
	height: Layout_Axis_Constraint,
}

Layout_Axis :: enum { Width, Height }
Layout_Axes :: distinct bit_set[Layout_Axis; u8]

Axis_Dependency :: enum {
	Width_To_Width,
	Width_To_Height,
	Height_To_Width,
	Height_To_Height,
}
Measure_Constraint_Dependencies :: distinct bit_set[Axis_Dependency; u8]

// These are separate types on purpose. The first describes how a measurer's
// input constraints affect its own output; the second maps child size changes
// to a container's externally measured size.
Parent_Size_Dependencies :: distinct bit_set[Axis_Dependency; u8]

// Keep this key limited to Runtime state that the retained measurement and
// shaping paths consume. Text scale and density flow through the style
// generations below. Device presentation scale only snaps finalized geometry;
// writing direction currently changes placement, and text shaping has no
// locale input, so those values are deliberately not measurement dependencies.
Measure_Dependencies :: struct {
	metrics_generation:    u32,
	typography_generation: u32,
	font_generation:       u64,
}

Measure_Result :: struct {
	size:                    Layout_Size,
	baseline:                Layout_Unit,
	baseline_valid:          bool,
	input_axis_dependencies: Measure_Constraint_Dependencies,
}

Measure_Cache_Key :: struct {
	constraints:    Layout_Constraints,
	input_revision: u64,
	content_signature: u64,
	dependencies:   Measure_Dependencies,
	valid:          bool,
}

Measure_State :: struct {
	input_hash: u64,
	input_revision: u64,
	cache_key: Measure_Cache_Key,
	result: Measure_Result,
	parent_size_dependencies: Parent_Size_Dependencies,
	parent_layout_dependencies: Layout_Axes,
}

Measure_Queue_Entry :: struct {
	node: Node_ID,
	generation: u64,
}

// Target_Layout_Rect is the canonical unsnapped solver result. Finalization
// derives a presentation Rect from these absolute edges and never feeds the
// snapped result back into the next layout solve.
Target_Layout_Rect :: struct {
	left, top, right, bottom: Layout_Unit,
}

Finalized_Geometry :: struct {
	bounds:     Rect,
	hit_bounds: Rect,
	clip:       Rect,
	valid:      bool,
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
	// Pointer position is local to the Runtime viewport. It is present on
	// release events so hosts can distinguish an outside-window tear-off from
	// an ordinary drag that ended without a valid drop target.
	pointer_x, pointer_y: f32,
	has_pointer_position: bool,
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
// Positive deltas describe content motion right/down, decreasing the viewport
// offset on that axis. Hosts translate platform axes while respecting the
// user's scroll direction setting; ticks use the same signs as precise deltas.
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

// A one-frame layout intent used by retained controls whose scrollable content
// must reveal a range after their actual viewport has been allocated.
Scroll_Visibility_Request :: struct {
	node: Node_ID,
	start_x, end_x: f32,
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

// Image_Load_Error is intentionally small and format-independent. Alicorn's
// built-in byte decoder currently accepts PNG and QOI images with bounded
// dimensions. Decoding may run on a worker; adoption remains UI-thread owned.
Image_Load_Error :: enum {
	None,
	Empty_Input,
	Input_Too_Large,
	Unsupported_Format,
	Invalid_Header,
	Dimensions_Too_Large,
	Decode_Failed,
	Unsupported_Pixel_Format,
	Resource_Limit,
}

Image_Resource :: struct {
	width, height: int,
	rgba8:         []u8,
	allocator:     mem.Allocator,
}

// Image_Decoded owns straight-alpha RGBA8 pixels independently of a Runtime.
// Treat it as move-only: destroy it or transfer it once with image_adopt_decoded.
// Its allocator must remain valid until the resource is released by its owner.
Image_Decoded :: struct {
	width, height: int,
	rgba8: []u8,
	allocator: mem.Allocator,
}

Text_Overflow :: enum {
	Wrap,
	Clip,
	Ellipsis,
}

Style_Theme_ID :: distinct u32
Style_Accent :: distinct u32

// Accessibility_Appearance_Preferences contains normalized host/user
// preferences that influence visual treatment only. Roles, names, values,
// actions, and semantic state remain owned by the semantic model.
Accessibility_Appearance_Preferences :: struct {
	increased_contrast:         bool,
	reduce_motion:              bool,
	reduce_transparency:        bool,
	differentiate_without_color: bool,
}

Accessibility_Appearance_Field :: enum {
	Increased_Contrast,
	Reduce_Motion,
	Reduce_Transparency,
	Differentiate_Without_Color,
}

Accessibility_Appearance_Known_Fields :: distinct bit_set[Accessibility_Appearance_Field; u8]

// Accessibility_Appearance_Observation is the normalized host preference
// snapshot plus the fields the platform could actually report. An unset
// known bit means unsupported or unavailable, not a known false preference.
// text_scale_known independently reports whether the host has a coherent
// system text scale. Unknown scale observations preserve the previous value.
Accessibility_Appearance_Observation :: struct {
	preferences:     Accessibility_Appearance_Preferences,
	known:           Accessibility_Appearance_Known_Fields,
	text_scale:      f32,
	text_scale_known: bool,
}

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
	Danger,
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

// Omitted treatments inherit the ordinary flat surface (or the rest treatment
// for pressed). defined=true with MATERIAL_FLAT explicitly selects flat paint.
// Material handles belong to the Runtime registering the containing theme.
Button_Surface_Treatment :: struct {
	defined: bool,
	material: Material_ID,
	physical_height: f32,
}

Button_Recipe :: struct {
	defined:                bool,
	shape:                  Surface_Shape,
	surface_role:           Style_Color_Role,
	text_role:              Style_Color_Role,
	surface_visible:        bool,
	selected:               Style_Transform,
	hovered:                Style_Transform,
	pressed:                Style_Transform,
	disabled:               Style_Transform,
	selected_indicator:     Button_Indicator,
	selected_indicator_role: Style_Color_Role,
	focus_indicator_mode:   Focus_Indicator_Mode,
	focus_role:             Style_Color_Role,
	semantic_active_role:   Style_Color_Role,
	rest_surface:           Button_Surface_Treatment,
	pressed_surface:        Button_Surface_Treatment,
}

Button_Recipe_Set :: struct {
	recipes: [BUTTON_VARIANT_COUNT]Button_Recipe,
}

Button_Indicator :: enum { None, Underline }
Focus_Indicator_Mode :: enum { Always, Keyboard_Only }
Button_Focus_Indicator_Mode :: Focus_Indicator_Mode

Style_Control_State :: enum { Selected, Hovered, Pressed, Disabled }
Style_Control_States :: distinct bit_set[Style_Control_State; u8]

// Button aliases preserve the original public names while keeping the shared
// transform vocabulary independent of any one built-in control.
Style_Button_State :: Style_Control_State
Style_Button_States :: Style_Control_States

Button_Visual_State :: struct {
	selected: bool,
	hovered:  bool,
	pressed:  bool,
	disabled: bool,
}

// Resolved outputs are small renderer-facing values, not widget state.
Button_Resolved_Style :: struct {
	shape:                  Surface_Shape,
	material:                Material_ID,
	physical_height:         f32,
	surface:                 Color,
	text:                    Color,
	focus:                   Color,
	semantic_active:         Color,
	selected_indicator:      Button_Indicator,
	selected_indicator_color: Color,
	focus_indicator_mode:    Focus_Indicator_Mode,
	applied_transforms:      Style_Control_States,
}

// Style_Provenance retains semantic inputs, not duplicated theme data. Token
// IDs and role-to-value mapping are derived from the immutable theme while an
// inspector query is formatted. Optional authored names/alias edges are kept
// as lightweight theme metadata; source spans remain compiler-only.
Style_Provenance :: struct {
	theme:          Style_Theme_ID,
	accent:         Style_Accent,
	variant:        u8,
	state_bits:     u8,
	accessibility_bits: u8,
	drop_target_on: bool,
	surface_signature: u64,
}

Computed_Style_Family :: enum { Button, Checkbox, Slider, Text_Field, Scrollbar, Semantic_Surface }

Computed_Style_Payload :: union #no_nil {
	Button_Resolved_Style,
	Checkbox_Resolved_Style,
	Slider_Resolved_Style,
	Text_Field_Resolved_Style,
	Scrollbar_Resolved_Style,
	Semantic_Surface_Resolved_Style,
}

// Computed_Style entries live in Runtime side storage keyed by Node_ID so
// resolved values do not consume the retained Node byte budget.
Computed_Style :: struct {
	family:       Computed_Style_Family,
	payload:      Computed_Style_Payload,
	dependencies: Style_Domains,
	generations:  Style_Generations,
	provenance:   Style_Provenance,
	valid:        bool,
}

DEFAULT_BUTTON_RECIPES :: Button_Recipe_Set{recipes={
	Button_Recipe{
		defined=true, surface_role=.Subtle_Surface, text_role=.Text, surface_visible=true,
		selected=Style_Transform{surface_role=.Accent, surface_mix=0.24},
		// The neutral Surface and Subtle_Surface roles can be nearly identical
		// in a theme, making the hover state appear to disappear. A restrained
		// accent tint stays visible without turning an ordinary button primary.
		hovered=Style_Transform{surface_role=.Accent_Hover, surface_mix=0.18},
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
		defined=true, surface_role=.Subtle_Surface, text_role=.Muted_Text, surface_visible=false,
		selected=Style_Transform{surface_role=.Accent, surface_mix=0.18},
		hovered=Style_Transform{surface_role=.Subtle_Surface, surface_mix=1, text_role=.Text, text_mix=0.45},
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
		focus_indicator_mode=.Keyboard_Only,
		focus_role=.Focus, semantic_active_role=.Semantic_Focus,
	},
	Button_Recipe{
		defined=true, surface_role=.Danger, text_role=.Danger, surface_visible=false,
		hovered=Style_Transform{surface_role=.Danger, surface_mix=0.3, text_role=.Accent_Text, text_mix=1},
		pressed=Style_Transform{surface_role=.Danger, surface_mix=1, text_role=.Accent_Text, text_mix=1},
		disabled=Style_Transform{surface_role=.Subtle_Surface, surface_mix=1, text_role=.Muted_Text, text_mix=1},
		focus_role=.Focus, semantic_active_role=.Semantic_Focus,
	},
}}

// A registered theme is immutable and retained once per Runtime. Nodes carry
// only the compact ID through Style_Environment, not a copy of this palette.
// Control_Metric provides a preferred intrinsic height, a minimum target
// height, and vertical content padding. These are separate inputs: the
// preferred height is a theme default, the minimum target protects ordinary
// controls, and measured text plus padding may require more room. Explicit
// Layout_Style dimensions remain an application override.
Control_Metric :: struct {
	preferred_height: f32,
	minimum_hit_height: f32,
	content_padding_y: f32,
}

Control_Metrics :: struct {
	defined: bool,
	button: Control_Metric,
	checkbox: Control_Metric,
	slider: Control_Metric,
	text_field: Control_Metric,
}

Control_Metric_Kind :: enum { Button, Checkbox, Slider, Text_Field }

DEFAULT_CONTROL_METRICS :: Control_Metrics{
	defined=true,
	button=Control_Metric{preferred_height=32, minimum_hit_height=32, content_padding_y=4},
	checkbox=Control_Metric{preferred_height=28, minimum_hit_height=32, content_padding_y=4},
	slider=Control_Metric{preferred_height=44, minimum_hit_height=32, content_padding_y=12},
	text_field=Control_Metric{preferred_height=28, minimum_hit_height=32, content_padding_y=4},
}

Style_Theme :: struct {
	colors:                 [STYLE_COLOR_ROLE_COUNT]Color,
	button_recipes:         Button_Recipe_Set,
	checkbox_recipe:        Checkbox_Recipe,
	slider_recipe:          Slider_Recipe,
	text_field_recipe:      Text_Field_Recipe,
	scrollbar_recipe:       Scrollbar_Recipe,
	control_metrics:        Control_Metrics,
	color_tokens:           []Color,
	length_tokens:          []Style_Length,
	core_color_tokens:      [STYLE_COLOR_ROLE_COUNT]Style_Color_Token_ID,
	extension_color_roles:  []Style_Extension_Color_Role_Binding,
	extension_length_roles: []Style_Extension_Length_Role_Binding,
	color_token_provenance:  []Style_Token_Provenance,
	length_token_provenance: []Style_Token_Provenance,
	extension_color_role_provenance: []Style_Extension_Color_Role_Provenance,
	extension_length_role_provenance: []Style_Extension_Length_Role_Provenance,
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
}, button_recipes=DEFAULT_BUTTON_RECIPES, checkbox_recipe=DEFAULT_CHECKBOX_RECIPE, slider_recipe=DEFAULT_SLIDER_RECIPE, text_field_recipe=DEFAULT_TEXT_FIELD_RECIPE, scrollbar_recipe=DEFAULT_SCROLLBAR_RECIPE, control_metrics=DEFAULT_CONTROL_METRICS}

DEFAULT_STYLE_THEME_ID :: Style_Theme_ID(1)

// Style_Environment contains intentionally subtree-wide presentation inputs.
// Zero values in a pushed environment mean "inherit"; accessibility_set
// distinguishes an explicit all-disabled preference value from inheritance.
// text_scale is the normalized user/host text scaling input.
Style_Environment :: struct {
	theme: Style_Theme_ID,
	density: f32,
	text_scale: f32,
	accent: Style_Accent,
	accessibility: Accessibility_Appearance_Preferences,
	accessibility_set: bool,
}

// Description keeps only the compact, frequently hashed style values here;
// accessibility preferences travel beside it in Pending_Item and are retained
// on Node so the per-description size budget remains stable.
Style_Environment_Core :: struct {
	theme: Style_Theme_ID,
	density: f32,
	text_scale: f32,
	accent: Style_Accent,
}

DEFAULT_STYLE_ENVIRONMENT :: Style_Environment{
	theme=DEFAULT_STYLE_THEME_ID,
	density=1,
	text_scale=1,
	accessibility_set=true,
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
	// font_size is a logical-unit override. Zero preserves the default text
	// size; Style_Environment.text_scale is applied to either value.
	font_size:   f32,
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
	// activated distinguishes a user-produced value from initial range
	// normalization, which can make changed true during an ordinary description.
	activated: bool,
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
	Measure,
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
	Measure,
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

// Application_Mutation_Diagnostics is compile-time empty unless an Odin debug
// build enables ALICORN_APP_MUTATION_DIAGNOSTICS. The app reports its own
// mutation domains; Alicorn only checks whether the matching UI work was
// explicitly requested.
APP_MUTATION_DIAGNOSTICS_ENABLED :: ODIN_DEBUG && #config(ALICORN_APP_MUTATION_DIAGNOSTICS, false)

Application_Mutation_Impact :: enum {
	Background,
	Description,
	Presentation,
}

when APP_MUTATION_DIAGNOSTICS_ENABLED {
	Application_Mutation_Entry :: struct {
		id: u64,
		domain: string,
		impact: Application_Mutation_Impact,
		before_revision: u64,
		reason: string,
		description_requested: bool,
		presentation_requested: bool,
		cause: Cause_Context,
	}

	Application_Mutation_Tracking :: struct {
		entries: [dynamic]Application_Mutation_Entry,
		sequence: u64,
	}

	Application_Mutation_Scope :: struct {
		runtime: ^Runtime,
		id: u64,
		cause_scope: Cause_Scope,
		active: bool,
	}
} else {
	Application_Mutation_Tracking :: struct {}
	Application_Mutation_Scope :: struct {}
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
	icon_id: Icon_ID,
	text_paint_spans: []Text_Paint_Span,
	text_style_spans: []Text_Style_Span,
	font:        Font_Role,
	text_style:  Text_Style,
	style_environment: Style_Environment_Core,
	style_scope_boundary: bool,
	layout_boundary_axes: Layout_Axes,
	adaptive_owner: bool,
	adaptive_alternative: bool,
	adaptive_min_width: f32,
	button_content_style: Button_Content_Style,
	button_variant: Button_Variant,
	style:       Layout_Style,
	grid_row: u16,
	grid_column: u16,
	grid_row_span: u16,
	grid_column_span: u16,
	grid_item: bool,
	grid_align_x, grid_align_y: Grid_Item_Alignment,
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
	visual_part: Visual_Part_Style,
	semantic:    Semantic_Descriptor,
	accessibility: Accessibility_Appearance_Preferences,
	grid_columns: []Grid_Track,
	grid_rows: []Grid_Track,
	grid_gap_x, grid_gap_y: f32,
}

// Percentage width relationships live in an optional sparse Runtime sidecar.
// Ordinary retained Nodes and Pending_Items pay no per-node field cost.
Percent_Width_Declaration :: struct {
	parent: Node_ID,
	fraction: f32,
}

Percent_Width_Dependency :: struct {
	parent: Node_ID,
	fraction: f32,
	layout_hash_base: u64,
	measure_input_hash_base: u64,
	measure_input_has_width: bool,
	parent_invalid_reported: bool,
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
	icon_id: Icon_ID,
	text_paint_spans: [dynamic]Text_Paint_Span,
	text_style_spans: [dynamic]Text_Style_Span,
	font:        Font_Role,
	text_style:  Text_Style,
	style_environment: Style_Environment,
	style_scope_boundary: bool,
	layout_boundary_axes: Layout_Axes,
	adaptive_owner: bool,
	adaptive_alternative: bool,
	adaptive_min_width: f32,
	adaptive_available_width: f32,
	adaptive_selected_alternative: Node_ID,
	adaptive_selection_reason: Adaptive_Selection_Reason,
	style_generations: Style_Generations,
	button_content_style: Button_Content_Style,
	button_variant: Button_Variant,
	style:       Layout_Style,
	grid_configuration_hash: u64,
	grid_columns: [dynamic]Grid_Track,
	grid_rows: [dynamic]Grid_Track,
	grid_gap_x, grid_gap_y: f32,
	grid_work_units: u64,
	grid_row: u16,
	grid_column: u16,
	grid_row_span: u16,
	grid_column_span: u16,
	grid_item: bool,
	grid_align_x, grid_align_y: Grid_Item_Alignment,
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
	// Preserve the requested extent when current constraints temporarily clamp it.
	split_preferred_position: f32,
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
	measure_queued: bool,
	measure_queue_generation: u64,
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

// Restore_Token identifies one application-owned intent during this Runtime's
// lifetime. It is not durable state and must never be saved across Runtime
// destruction.
Restore_Token :: distinct u64
RESTORE_TOKEN_NONE :: Restore_Token(0)

Restore_Control :: enum {
	Split,
	Scroll,
	Semantic_Focus,
}

// Requested and Deferred are in-progress states. Every request ends in exactly
// one of Applied, Clamped, Cancelled, or Superseded.
Restore_Outcome :: enum {
	None,
	Requested,
	Deferred,
	Applied,
	Clamped,
	Cancelled,
	Superseded,
}

Restore_Reason :: enum {
	None,
	Awaiting_Layout,
	Awaiting_Corrective_Description,
	Resolved,
	Constrained,
	Invalid_Value,
	User_Interaction,
	Newer_Request,
	Target_Retired,
	Owner_Unavailable,
	Owner_Mismatch,
	Application_Cancelled,
}

Restore_Value :: struct {
	x, y: f32,
}

Split_Restore_Request :: struct {
	token: Restore_Token,
	preferred_position: f32,
}

Scroll_Restore_Request :: struct {
	token: Restore_Token,
	offset_x, offset_y: f32,
}

Restore_Control_State :: struct {
	token: Restore_Token,
	control: Restore_Control,
	outcome: Restore_Outcome,
	reason: Restore_Reason,
	requested: Restore_Value,
	preferred: Restore_Value,
	resolved: Restore_Value,
	described: Restore_Value,
	described_viewport: Restore_Value,
	semantic_id: Semantic_ID,
	realized_node: Node_ID,
	layout_generation: u64,
	awaiting_description: bool,
}

Restore_Target :: struct {
	control: Restore_Control,
	node: Node_ID,
}

Restore_Report :: struct {
	target: Node_ID,
	state: Restore_Control_State,
}

RESTORE_REPORT_CAPACITY :: 64

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

NOTICE_QUEUE_CAPACITY :: 4
NOTICE_ACTION_CAPACITY :: 3
NOTICE_ACTION_EVENT_CAPACITY :: NOTICE_QUEUE_CAPACITY * NOTICE_ACTION_CAPACITY
NOTICE_ID_MAX_BYTES :: 96
NOTICE_TITLE_MAX_BYTES :: 128
NOTICE_MESSAGE_MAX_BYTES :: 512
NOTICE_DETAILS_MAX_BYTES :: 1024
NOTICE_ACTION_LABEL_MAX_BYTES :: 64

Notice_Handle :: distinct u64

Notice_Severity :: enum { Info, Success, Warning, Error }
Notice_Lifetime :: enum { Transient, Persistent }
Notice_Placement :: enum { Toast, Contextual }

Notice_Action :: struct {
	id: Action_ID,
	label: string,
}

// Notice is a bounded, application-authored notification request. The
// runtime copies all strings into inline storage when notice_post accepts it.
Notice :: struct {
	id: string,
	title: string,
	message: string,
	details: string,
	severity: Notice_Severity,
	lifetime: Notice_Lifetime,
	placement: Notice_Placement,
	anchor: Node_ID,
	actions: []Notice_Action,
	duration_ms: u32,
	// A zeroed environment keeps the runtime's standard notice appearance.
	// Nonzero fields are captured with the notice and applied to its card.
	style_environment: Style_Environment,
}

Notice_Action_Record :: struct {
	id: Action_ID,
	label: [NOTICE_ACTION_LABEL_MAX_BYTES]u8,
	label_length: int,
}

Notice_Record :: struct {
	handle: Notice_Handle,
	id: [NOTICE_ID_MAX_BYTES]u8,
	id_length: int,
	id_hash: u64,
	title: [NOTICE_TITLE_MAX_BYTES]u8,
	title_length: int,
	message: [NOTICE_MESSAGE_MAX_BYTES]u8,
	message_length: int,
	details: [NOTICE_DETAILS_MAX_BYTES]u8,
	details_length: int,
	severity: Notice_Severity,
	lifetime: Notice_Lifetime,
	placement: Notice_Placement,
	anchor: Node_ID,
	style_environment: Style_Environment,
	style_environment_set: bool,
	actions: [NOTICE_ACTION_CAPACITY]Notice_Action_Record,
	action_count: int,
	deadline_ns: u64,
	sequence: u64,
}

Notice_Action_Event :: struct {
	notice: Notice_Handle,
	notice_id_hash: u64,
	action: Action_ID,
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
	Measure,
	Layout,
	Paint,
	Composite,
	Submit,
	Retire,
	Restore,
	Mutation_Diagnostic,
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
	// Cumulative adaptive_presentation_nodes_visited counts descendants
	// inspected when a selected branch changes presentation state. It excludes
	// fast paths whose branch root already has the requested state.
	adaptive_presentation_nodes_visited: u64,
	// style_resolutions counts computed-style cache misses; style_cache_hits
	// counts retained values reused while rebuilding paint. Both are cumulative.
	style_resolutions: u64,
	style_cache_hits: u64,
	stage_visits:      [Runtime_Stage]u64,
	layout_updates:    u64,
	measure_requests:  u64,
	measure_cache_hits: u64,
	measure_cache_misses: u64,
	// These counters include scheduling work which is otherwise hidden by the
	// stage-level visit counts. measure_nodes_examined includes queued entries
	// and the deliberately broad font-generation invalidation pass; executed
	// counts cache misses which perform a fresh measurement.
	measure_nodes_examined: u64,
	measure_nodes_executed: u64,
	display_commands_finalized: u64,
	display_finalization_full_passes: u64,
	semantic_order_nodes_examined: u64,
	global_fallbacks: u64,
	global_work_by_reason: [Retained_Global_Work_Reason]u64,
	text_shape_requests: u64,
	paint_updates:     u64,
	composite_updates:  u64,
	adjacency_rebuilds: u64,
	// pointer_events counts delivered runtime pointer events. Hover transitions
	// count target identity changes, not every motion within an unchanged target.
	pointer_events:    u64,
	hover_target_transitions: u64,
	semantic_descriptions_emitted: u64,
	semantic_entities_resolved: u64,
	semantic_structure_changes: u64,
	semantic_property_changes: u64,
	semantic_projection_nodes_added: u64,
	semantic_projection_nodes_updated: u64,
	semantic_projection_nodes_removed: u64,
	accessibility_activation_wakes: u64,
	accessibility_action_wakes: u64,
	accessibility_reveal_wakes: u64,
	accessibility_updates_submitted: u64,
	accessibility_requests_received: u64,
	accessibility_requests_dropped: u64,
	semantic_focus_search_visits: u64,
	semantic_active_update_visits: u64,
	gpu_submits:       u64,
	surface_updates:  u64,
	surface_frames_consumed: u64,
	surface_geometry_updates: u64,
	surface_geometry_overflow_rejections: u64,
	surface_clear_count: u64,
	surface_stale_update_rejections: u64,
}

// Retained_Global_Work_Reason identifies the intentional operations whose
// cost may scale with the retained tree or display list. Keeping reasons
// separate makes broad invalidation distinguishable from locality fallbacks.
Retained_Global_Work_Reason :: enum {
	Measure_Font_Generation,
	Display_Structure_Rebuild,
	Display_Scale_Change,
	Display_Transient_Update,
	Display_Incremental_Fallback,
	Semantic_Order_Rebuild,
}

// Runtime's fields remain exported because Odin does not support private
Controlled_Text_Field_State :: struct {
	model_text: string,
	edit_revision: u64,
	seen_edit_revision: u64,
	submit_pending: bool,
}

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
	controlled_text_fields: map[Node_ID]Controlled_Text_Field_State,
	measure_states: map[Node_ID]Measure_State,
	percent_width_dependencies: map[Node_ID]Percent_Width_Dependency,
	pending_percent_widths: map[Node_ID]Percent_Width_Declaration,
	percent_width_sidecar_initialized: bool,
	measure_queue: [dynamic]Measure_Queue_Entry,
	measure_queue_sequence: u64,
	finalized_geometry: map[Node_ID]Finalized_Geometry,
	computed_styles: map[Node_ID]Computed_Style,
	style_stats_suppressed: bool,
	semantic_surfaces: map[Node_ID]Semantic_Surface_Style,
	surface_top_edge_links: map[Node_ID]Node_ID,
	visual_parts: map[Node_ID]Visual_Part_Style,
	semantic_entities: map[Semantic_ID]Semantic_Entity,
	semantic_tree_orders: map[Node_ID]u64,
	// Adaptive alternatives retain their authored semantic descriptors outside
	// the per-frame pending buffer so retained-only constraint selection can
	// rebind semantics without invoking application code.
	adaptive_semantic_descriptors: map[Node_ID]Semantic_Descriptor,
	adaptive_semantic_previous_ids: map[Node_ID]Semantic_ID,
	semantic_pending_changed: map[Semantic_ID]bool,
	semantic_pending_added: map[Semantic_ID]bool,
	semantic_pending_structure: map[Semantic_ID]bool,
	semantic_pending_removed: map[Semantic_ID]bool,
	semantic_last_changed: [dynamic]Semantic_ID,
	semantic_last_removed: [dynamic]Semantic_ID,
	semantic_revision: u64,
	semantic_last_from_revision: u64,
	semantic_last_to_revision: u64,
	semantic_collection_generation: u64,
	semantic_collection_touched: map[Semantic_ID]u64,
	semantic_collection_prune_pending: bool,
	semantic_keyboard_focus: Semantic_ID,
	semantic_keyboard_focus_pending: bool,
	semantic_requests: [dynamic]Semantic_Request_Event,
	semantic_request_read_index: int,
	order:       [dynamic]Node_ID,
	top_level:   [dynamic]Node_ID,
	pending:     [dynamic]Pending_Item,
	scroll_visibility_requests: [dynamic]Scroll_Visibility_Request,
	seen:        map[Node_ID]Identity_Declaration,
	identity_scopes: map[Node_ID]Identity_Declaration,
	grid_pending_scopes: map[Node_ID]bool,
	stack:       [dynamic]Node_ID,
	identity_stack: [dynamic]Node_ID,
	identity_labels: [dynamic]string,
	identity_key_u64: [dynamic]u64,
	identity_key_numeric: [dynamic]bool,
	identity_key_kind: [dynamic]u8,
	identity_key_pair: [dynamic]UI_Key_Pair,
	viewport:    Rect,
	presentation_scale_x: f32,
	presentation_scale_y: f32,
	style_environment: Style_Environment,
	root_accessibility_appearance: Accessibility_Appearance_Preferences,
	root_accessibility_appearance_known: Accessibility_Appearance_Known_Fields,
	root_text_scale: f32,
	root_text_scale_known: bool,
	style_themes: [dynamic]Style_Theme,
	style_materials: [dynamic]Style_Material,
	style_scope_stack: [dynamic]Style_Environment_Scope,
	adaptive_description_scopes: [dynamic]Adaptive_Description_Scope,
	layout_roots: [dynamic]Node_ID,
	layout_visit_probe: map[Node_ID]u64,
	focused:     Node_ID,
	// focus_visible tracks keyboard modality for controls whose persistent
	// selected state is already conveyed separately (notably tabs).
	focus_visible: bool,
	context_menu: Context_Menu_State,
	select: Select_State,
	notices: [NOTICE_QUEUE_CAPACITY]Notice_Record,
	notice_count: int,
	notice_sequence: u64,
	notice_handle_sequence: u64,
	notice_event_sequence: u64,
	notice_actions: [NOTICE_ACTION_EVENT_CAPACITY]Notice_Action_Event,
	notice_action_read: int,
	notice_action_write: int,
	notice_action_count: int,
	tooltip: Tooltip_State,
	transient_overlay_kind: Transient_Overlay_Kind,
	selected:    Node_ID,
	semantic_focus: Semantic_Focus_State,
	semantic_focus_restore: Restore_Control_State,
	restore_token_sequence: u64,
	restore_controls: map[Restore_Target]^Restore_Control_State,
	restore_reports: [RESTORE_REPORT_CAPACITY]Restore_Report,
	restore_report_next: int,
	restore_report_count: int,
	last_hovered: Node_ID,
	captured_node: Node_ID,
	text_field_selection_owner: Node_ID,
	text_field_selection_drag: text_selection.Text_Selection_Drag_State,
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
	interaction_consumption_sequence: u64,
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
	application_mutation_tracking: Application_Mutation_Tracking,
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
	display_target: [dynamic]Paint_Command,
	paint_resource_generation: u64,
	images: map[u64]Image_Resource,
	image_resource_sequence: u64,
	gpu_surface_images: map[Node_ID][dynamic]GPU_Surface_Image,
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
