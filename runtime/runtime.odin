package alicorn

import "core:fmt"
import "core:math"
import "core:mem"
import "core:strings"

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
	Container,
	Button,
	Checkbox,
	Slider,
	Text,
	Text_Field,
	Text_Composition,
	Text_Selection,
	Text_Caret,
	Virtual_List,
	Virtual_Row,
	Scroll_Region,
	Scrollbar_Track,
	Scrollbar_Thumb,
	Scrollbar_Corner,
	Split,
	Split_Handle,
	Custom_Surface,
}

Split_Axis :: enum { Horizontal, Vertical }

GPU_Surface_Kind :: enum {
	Waveform,
	Geometry,
}

// Geometry surfaces share the native SDL_GPU triangle budget. Transparent
// geometry emits no background vertices; a segment uses six vertices and a
// filled circle uses 16 fan triangles (48 vertices).
GPU_SURFACE_MAX_VERTICES :: 8192
GPU_SURFACE_CIRCLE_SEGMENTS :: 16

// GPU_Surface_Context is the backend-neutral placement contract. The runtime
// owns these values; a backend must not infer them from the window or retain an
// application pointer to obtain them later.
GPU_Surface_Context :: struct {
	logical_bounds: Rect,
	pixel_width:    int,
	pixel_height:   int,
	dpi_scale:      f32,
	clip:           Rect,
	revision:       u64,
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

Pointer_Event :: struct {
	kind:   Pointer_Kind,
	x, y:   f32,
	button: int,
}

Input_Modifiers :: struct {
	shift:   bool,
	control: bool,
	alt:     bool,
	super:   bool,
}

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

Display_Command :: struct {
	node:   Node_ID,
	kind: Node_Kind,
	bounds: Rect,
	clip:   Rect,
	text:   string,
	color:  Color,
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
	font:        Font_Role,
	text_style:  Text_Style,
	button_content_style: Button_Content_Style,
	style:       Layout_Style,
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
	selected:    bool,
	semantic_id: Semantic_ID,
	disabled:    bool,
	identity_key: string,
	identity_key_u64: u64,
	identity_key_numeric: bool,
	surface_kind: GPU_Surface_Kind,
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
	font:        Font_Role,
	text_style:  Text_Style,
	button_content_style: Button_Content_Style,
	style:       Layout_Style,
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
	disabled:    bool,
	active:      bool,
	present:     bool,
	hovered:     bool,
	pressed:     bool,
	selected:    bool,
	semantic_id: Semantic_ID,
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
	surface_revision: u64,
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
	composition: Text_Composition,
	composition_run: Text_Run,
	composition_run_valid: bool,
	composition_run_generation: u64,
	paint:       [dynamic]Display_Command,
	display_index: int,
	paint_queued: bool,
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
	pointer_events:    u64,
	gpu_submits:       u64,
	surface_updates:  u64,
	surface_frames_consumed: u64,
	surface_geometry_updates: u64,
	surface_geometry_overflow_rejections: u64,
}

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
	focused:     Node_ID,
	selected:    Node_ID,
	semantic_focus: Semantic_Focus_State,
	last_hovered: Node_ID,
	captured_node: Node_ID,
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
	display:     [dynamic]Display_Command,
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

DEFAULT_STYLE :: Layout_Style{
	direction = .Column,
	width = -1,
	height = -1,
	min_width = 0,
	max_width = -1,
	min_height = 0,
	max_height = -1,
	grow = 0,
	padding = 0,
	gap = 0,
	align = .Stretch,
	clip = false,
}

// layout_style starts from Alicorn's ordinary layout defaults and lets an
// application name only the values that express its intent. It is a
// constructor, not a second styling language: advanced callers can still use
// Layout_Style directly when they need every field.
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
) -> Layout_Style {
	return Layout_Style{
		direction = direction,
		width = width,
		height = height,
		min_width = min_width,
		max_width = max_width,
		min_height = min_height,
		max_height = max_height,
		grow = grow,
		padding = padding,
		gap = gap,
		align = align,
		clip = clip,
	}
}

DEFAULT_COLOR :: Color{0.78, 0.82, 0.90, 1.0}

// Container APIs use this sentinel to distinguish an omitted background from
// an explicitly requested color. Root resolves the omitted value to
// DEFAULT_COLOR; ordinary layout containers remain non-painting by default.
NO_BACKGROUND_COLOR :: Color{0, 0, 0, 0}

color_equal :: proc(a, b: Color) -> bool {
	return a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a
}

resolve_container_color :: proc(kind: Node_Kind, color: Color) -> (resolved: Color, paints: bool) {
	if color_equal(color, NO_BACKGROUND_COLOR) {
		if kind == .Root {
			return DEFAULT_COLOR, true
		}
		return color, false
	}
	return color, true
}

site :: proc(file: string, line, column: int, component: string) -> Source_Site {
	return Source_Site{file, line, column, component}
}

caller_site :: proc(component: string, loc := #caller_location) -> Source_Site {
	return Source_Site{loc.file_path, int(loc.line), int(loc.column), component}
}

resolve_source :: proc(source: Source_Site, component: string, loc := #caller_location) -> Source_Site {
	if source.file != "" { return source }
	return Source_Site{loc.file_path, int(loc.line), int(loc.column), component}
}

new_runtime :: proc(viewport: Rect, config := Runtime_Config{}) -> Runtime {
	persistent_backing_allocator := config.persistent_allocator
	if persistent_backing_allocator.procedure == nil {
		persistent_backing_allocator = context.allocator
	}
	scratch_backing_allocator := config.scratch_backing_allocator
	if scratch_backing_allocator.procedure == nil {
		scratch_backing_allocator = persistent_backing_allocator
	}
	capacity := config.trace_capacity
	if capacity < 1 { capacity = 1 }
	stats := config.allocation_stats
	stats_owned := false
	if stats == nil {
		stats = new(Runtime_Allocation_Stats, allocator=persistent_backing_allocator)
		stats_owned = true
	}
	persistent_state := new(Runtime_Allocator_State, allocator=persistent_backing_allocator)
	persistent_state^ = Runtime_Allocator_State{backing=persistent_backing_allocator, stats=stats, scratch=false}
	rt := Runtime{
		persistent_backing_allocator = persistent_backing_allocator,
		persistent_allocator = runtime_allocator(persistent_state),
		scratch_backing_allocator = scratch_backing_allocator,
		allocation_stats = stats,
		allocation_stats_owned = stats_owned,
		persistent_allocator_state = persistent_state,
		viewport = viewport,
		invalidated = true,
	}
	rt.scratch_arena = new(mem.Dynamic_Arena, allocator=rt.persistent_allocator)
	mem.dynamic_arena_init(rt.scratch_arena, block_allocator=scratch_backing_allocator, array_allocator=rt.persistent_allocator)
	rt.scratch_allocator_state = new(Runtime_Allocator_State, allocator=rt.persistent_allocator)
	rt.scratch_allocator_state^ = Runtime_Allocator_State{
		backing=mem.dynamic_arena_allocator(rt.scratch_arena),
		stats=stats,
		scratch=true,
	}
	rt.scratch_allocator = runtime_allocator(rt.scratch_allocator_state)
	rt.nodes = make(map[Node_ID]^Node, allocator=rt.persistent_allocator)
	rt.order = make([dynamic]Node_ID, 0, allocator=rt.persistent_allocator)
	rt.top_level = make([dynamic]Node_ID, 0, allocator=rt.persistent_allocator)
	rt.pending = make([dynamic]Pending_Item, 0, allocator=rt.persistent_allocator)
	rt.seen = make(map[Node_ID]Identity_Declaration, allocator=rt.persistent_allocator)
	rt.identity_scopes = make(map[Node_ID]Identity_Declaration, allocator=rt.persistent_allocator)
	rt.stack = make([dynamic]Node_ID, 0, allocator=rt.persistent_allocator)
	rt.identity_stack = make([dynamic]Node_ID, 0, allocator=rt.persistent_allocator)
	rt.identity_labels = make([dynamic]string, 0, allocator=rt.persistent_allocator)
	rt.identity_key_u64 = make([dynamic]u64, 0, allocator=rt.persistent_allocator)
	rt.identity_key_numeric = make([dynamic]bool, 0, allocator=rt.persistent_allocator)
	rt.identity_key_kind = make([dynamic]u8, 0, allocator=rt.persistent_allocator)
	rt.identity_key_pair = make([dynamic]UI_Key_Pair, 0, allocator=rt.persistent_allocator)
	rt.paint_queue = make([dynamic]Node_ID, 0, allocator=rt.persistent_allocator)
	rt.display = make([dynamic]Display_Command, 0, allocator=rt.persistent_allocator)
	rt.trace = Trace_Ring{events = make([dynamic]Trace_Event, capacity, allocator=rt.persistent_allocator)}
	rt.actions = make([dynamic]Action_Entry, 0, allocator=rt.persistent_allocator)
	rt.text_engine = new_text_engine("runtime text", false, rt.persistent_allocator)
	return rt
}

hash_mix :: proc(h, value: u64) -> u64 {
	result := h ~ value
	result *= 1099511628211
	return result
}

hash_string :: proc(value: string) -> u64 {
	h: u64 = 1469598103934665603
	for i := 0; i < len(value); i += 1 {
		h = hash_mix(h, u64(value[i]))
	}
	return h
}

identity_hash :: proc(parent: Node_ID, source: Source_Site, key: string, explicit_key: bool) -> Node_ID {
	h := u64(1469598103934665603)
	h = hash_mix(h, u64(parent))
	h = hash_mix(h, hash_string(source.file))
	h = hash_mix(h, u64(source.line))
	h = hash_mix(h, u64(source.column))
	h = hash_mix(h, hash_string(source.component))
	if explicit_key {
		h = hash_mix(h, hash_string(key))
	}
	if h == 0 {
		h = 1
	}
	return Node_ID(h)
}

identity_hash_u64 :: proc(parent: Node_ID, source: Source_Site, key: u64) -> Node_ID {
	h := u64(1469598103934665603)
	h = hash_mix(h, u64(parent))
	h = hash_mix(h, hash_string(source.file))
	h = hash_mix(h, u64(source.line))
	h = hash_mix(h, u64(source.column))
	h = hash_mix(h, hash_string(source.component))
	h = hash_mix(h, key)
	if h == 0 { h = 1 }
	return Node_ID(h)
}

identity_hash_key :: proc(parent: Node_ID, source: Source_Site, key: UI_Key) -> Node_ID {
	h := u64(1469598103934665603)
	h = hash_mix(h, u64(parent))
	h = hash_mix(h, hash_string(source.file))
	h = hash_mix(h, u64(source.line))
	h = hash_mix(h, u64(source.column))
	h = hash_mix(h, hash_string(source.component))
	switch value in key {
	case UI_Unkeyed:
		h = hash_mix(h, 0)
	case string:
		h = hash_mix(h, 1)
		h = hash_mix(h, hash_string(value))
	case u64:
		h = hash_mix(h, 2)
		h = hash_mix(h, value)
	case UI_Key_Pair:
		h = hash_mix(h, 3)
		h = hash_mix(h, value.first)
		h = hash_mix(h, value.second)
	}
	if h == 0 { h = 1 }
	return Node_ID(h)
}

owned :: proc(value: string, allocator := context.allocator) -> string {
	if value == "" {
		return ""
	}
	copy, _ := strings.clone(value, allocator)
	return copy
}

owned_with_allocator :: proc(value: string, allocator: mem.Allocator) -> string {
	if value == "" { return "" }
	copy, err := strings.clone(value, allocator)
	if err != nil { return "" }
	return copy
}

trace_current_cause :: proc(rt: ^Runtime) -> Cause_Context {
	if rt.active_cause.id != 0 { return rt.active_cause }
	return rt.frame_cause
}

record_trace_with_cause :: proc(rt: ^Runtime, kind: Trace_Kind, node: Node_ID, reason: string, cause: Cause_Context) {
	rt.trace.sequence += 1
	entry := Trace_Event{sequence=rt.trace.sequence, kind=kind, cause_id=cause.id, cause_kind=cause.kind, action_id=cause.action_id, node=node, reason=owned_with_allocator(reason, rt.persistent_allocator), reason_owned=true}
	old := &rt.trace.events[rt.trace.next]
	if old.reason_owned && len(old.reason) > 0 { delete(old.reason, rt.persistent_allocator) }
	rt.trace.events[rt.trace.next] = entry
	rt.trace.next = (rt.trace.next + 1) % len(rt.trace.events)
	if rt.trace.count < len(rt.trace.events) {
		rt.trace.count += 1
	}
}

record_trace :: proc(rt: ^Runtime, kind: Trace_Kind, node: Node_ID, reason: string) {
	record_trace_with_cause(rt, kind, node, reason, trace_current_cause(rt))
}

// High-frequency retained products can use an immutable literal reason
// without creating one heap string per update. The ring still bounds event
// storage; only the ownership policy differs for this process-lifetime text.
record_trace_literal :: proc(rt: ^Runtime, kind: Trace_Kind, node: Node_ID, reason: string) {
	record_trace_literal_with_cause(rt, kind, node, reason, trace_current_cause(rt))
}

record_trace_literal_with_cause :: proc(rt: ^Runtime, kind: Trace_Kind, node: Node_ID, reason: string, cause: Cause_Context) {
	rt.trace.sequence += 1
	entry := Trace_Event{sequence=rt.trace.sequence, kind=kind, cause_id=cause.id, cause_kind=cause.kind, action_id=cause.action_id, node=node, reason=reason, reason_owned=false}
	old := &rt.trace.events[rt.trace.next]
	if old.reason_owned && len(old.reason) > 0 { delete(old.reason, rt.persistent_allocator) }
	rt.trace.events[rt.trace.next] = entry
	rt.trace.next = (rt.trace.next + 1) % len(rt.trace.events)
	if rt.trace.count < len(rt.trace.events) { rt.trace.count += 1 }
}

cause_begin :: proc(rt: ^Runtime, kind: Cause_Kind, reason: string, action_id: Action_ID = Action_ID(0)) -> Cause_Scope {
	previous := rt.active_cause
	cause_ctx := trace_current_cause(rt)
	if cause_ctx.id == 0 {
		rt.cause_sequence += 1
		if rt.cause_sequence == 0 { rt.cause_sequence = 1 }
		cause_ctx = Cause_Context{id=rt.cause_sequence, kind=kind, action_id=action_id}
		rt.active_cause = cause_ctx
		record_trace_with_cause(rt, .Cause, 0, reason, cause_ctx)
	} else {
		if cause_ctx.action_id == Action_ID(0) && action_id != Action_ID(0) { cause_ctx.action_id = action_id }
		rt.active_cause = cause_ctx
	}
	return Cause_Scope{previous=previous, cause=cause_ctx}
}

cause_resume :: proc(rt: ^Runtime, cause_ctx: Cause_Context) -> Cause_Scope {
	previous := rt.active_cause
	if cause_ctx.id != 0 { rt.active_cause = cause_ctx }
	return Cause_Scope{previous=previous, cause=cause_ctx}
}

cause_end :: proc(rt: ^Runtime, scope: Cause_Scope) {
	rt.active_cause = scope.previous
	if scope.clear_pointer_gesture { rt.pointer_gesture_cause = Cause_Context{} }
}

// pointer_cause_begin keeps a press/drag/release sequence under one cause ID.
// Uncaptured motion remains presentation-only and does not manufacture causes.
pointer_cause_begin :: proc(rt: ^Runtime, kind: Pointer_Kind) -> Cause_Scope {
	if kind == .Down {
		scope := cause_begin(rt, .Pointer, "pointer gesture")
		rt.pointer_gesture_cause = scope.cause
		return scope
	}
	if rt.pointer_gesture_cause.id != 0 {
		scope := cause_resume(rt, rt.pointer_gesture_cause)
		scope.clear_pointer_gesture = kind == .Up || kind == .Cancel
		return scope
	}
	if kind == .Move { return Cause_Scope{previous=rt.active_cause, cause=rt.active_cause} }
	return cause_begin(rt, .Pointer, "pointer gesture")
}

note_pending_work_cause :: proc(rt: ^Runtime, cause: Cause_Context) {
	if rt.frame_open { return }
	if !rt.pending_work_seen {
		rt.pending_work_seen = true
		rt.pending_work_cause = cause
		return
	}
	if rt.pending_work_mixed { return }
	if rt.pending_work_cause.id != cause.id {
		rt.pending_work_mixed = true
		rt.pending_work_cause = Cause_Context{}
	} else if cause.id != 0 && rt.pending_work_cause.action_id == Action_ID(0) {
		rt.pending_work_cause.action_id = cause.action_id
	}
}

// action_update publishes an application's current action metadata and state
// to this runtime. Action names are stable for an ID; labels and state may be
// refreshed explicitly. Strings are copied so callers may use temporary data.
action_update :: proc(rt: ^Runtime, descriptor: Action_Descriptor, state: Action_State) -> bool {
	if descriptor.id == Action_ID(0) || len(descriptor.name) == 0 || len(descriptor.label) == 0 { return false }
	for index := 0; index < len(rt.actions); index += 1 {
		entry := &rt.actions[index]
		if entry.descriptor.id != descriptor.id { continue }
		if entry.descriptor.name != descriptor.name { return false }
		if entry.descriptor.label != descriptor.label {
			label_copy := owned_with_allocator(descriptor.label, rt.persistent_allocator)
			if len(label_copy) == 0 { return false }
			if entry.label_owned && len(entry.descriptor.label) > 0 { delete(entry.descriptor.label, rt.persistent_allocator) }
			entry.descriptor.label = label_copy
			entry.label_owned = true
		}
		entry.state = state
		return true
	}
	name_copy := owned_with_allocator(descriptor.name, rt.persistent_allocator)
	label_copy := owned_with_allocator(descriptor.label, rt.persistent_allocator)
	if len(name_copy) == 0 || len(label_copy) == 0 {
		if len(name_copy) > 0 { delete(name_copy, rt.persistent_allocator) }
		if len(label_copy) > 0 { delete(label_copy, rt.persistent_allocator) }
		return false
	}
	append(&rt.actions, Action_Entry{
		descriptor=Action_Descriptor{id=descriptor.id, name=name_copy, label=label_copy},
		state=state,
		name_owned=true,
		label_owned=true,
	})
	return true
}

action_lookup :: proc(rt: ^Runtime, id: Action_ID) -> (descriptor: Action_Descriptor, state: Action_State, found: bool) {
	if id == Action_ID(0) { return }
	for entry in rt.actions {
		if entry.descriptor.id == id { return entry.descriptor, entry.state, true }
	}
	return
}

semantic_id_is_valid :: proc(id: Semantic_ID) -> bool {
	return id.namespace != 0
}

// semantic_focus_state reports the independent logical focus identity, its
// durable keyboard-focus owner, and the currently realized presentation node.
semantic_focus_state :: proc(rt: ^Runtime) -> Semantic_Focus_State {
	return rt.semantic_focus
}

// semantic_focus_set changes the logical entity being operated on without
// changing keyboard focus or application selection. Bind that identity to a
// described node with semantic_bind; reconciliation then updates realized_node
// as the presentation appears and disappears.
semantic_focus_set :: proc(rt: ^Runtime, id: Semantic_ID, owner: Node_ID) -> bool {
	if !semantic_id_is_valid(id) { return semantic_focus_clear(rt) }
	if rt.semantic_focus.id == id && rt.semantic_focus.owner == owner { return false }
	rt.semantic_focus.id = id
	rt.semantic_focus.owner = owner
	refresh_semantic_focus_realization(rt)
	record_trace(rt, .Focus, rt.semantic_focus.realized_node,
		fmt.tprintf("semantic focus set namespace=%d value=%d owner=%d", id.namespace, id.value, owner))
	return true
}

semantic_focus_clear :: proc(rt: ^Runtime) -> bool {
	if rt.semantic_focus.id.namespace == 0 && rt.semantic_focus.owner == 0 && rt.semantic_focus.realized_node == 0 {
		return false
	}
	previous := rt.semantic_focus.id
	rt.semantic_focus = Semantic_Focus_State{}
	refresh_semantic_focus_realization(rt)
	record_trace(rt, .Focus, 0,
		fmt.tprintf("semantic focus cleared namespace=%d value=%d", previous.namespace, previous.value))
	return true
}

semantic_node_within_owner :: proc(rt: ^Runtime, id, owner: Node_ID) -> bool {
	if owner == 0 { return false }
	current := id
	for current != 0 {
		if current == owner { return true }
		node, ok := rt.nodes[current]
		if !ok { return false }
		current = node.parent
	}
	return false
}

refresh_semantic_focus_realization :: proc(rt: ^Runtime) {
	previous := rt.semantic_focus.realized_node
	next := Node_ID(0)
	fallback := Node_ID(0)
	if semantic_id_is_valid(rt.semantic_focus.id) {
		for id in rt.order {
			node, ok := rt.nodes[id]
			if !ok || !node.active || node.semantic_id != rt.semantic_focus.id { continue }
			if fallback == 0 { fallback = id }
			if semantic_node_within_owner(rt, id, rt.semantic_focus.owner) {
				next = id
				break
			}
		}
		if next == 0 { next = fallback }
	}
	for id, node in rt.nodes {
		should_be_active := id == next
		if node.semantic_active != should_be_active {
			node.semantic_active = should_be_active
			invalidate_interaction_paint(rt, id, "semantic focus presentation changed")
		}
	}
	rt.semantic_focus.realized_node = next
	if previous != next {
		if next == 0 && semantic_id_is_valid(rt.semantic_focus.id) {
			record_trace(rt, .Focus, 0, "semantic focus has no realized presentation")
		} else if next != 0 {
			record_trace(rt, .Focus, next, "semantic focus presentation realized")
		}
	}
}

trace_action :: proc(rt: ^Runtime, action_id: Action_ID, label: string) {
	cause_ctx := trace_current_cause(rt)
	scope: Cause_Scope
	if cause_ctx.id == 0 {
		scope = cause_begin(rt, .Application, "application action")
		cause_ctx = scope.cause
	}
	cause_ctx.action_id = action_id
	if rt.active_cause.id == cause_ctx.id { rt.active_cause.action_id = action_id }
	if rt.frame_cause.id == cause_ctx.id { rt.frame_cause.action_id = action_id }
	if rt.pending_work_cause.id == cause_ctx.id { rt.pending_work_cause.action_id = action_id }
	if rt.pointer_gesture_cause.id == cause_ctx.id { rt.pointer_gesture_cause.action_id = action_id }
	record_trace_with_cause(rt, .Action, 0, label, cause_ctx)
	if scope.cause.id != 0 { cause_end(rt, scope) }
}

trace_mutation :: proc(rt: ^Runtime, reason: string) {
	cause_ctx := trace_current_cause(rt)
	scope: Cause_Scope
	if cause_ctx.id == 0 {
		scope = cause_begin(rt, .Application, reason)
		cause_ctx = scope.cause
	}
	record_trace_with_cause(rt, .Mutation, 0, reason, cause_ctx)
	if scope.cause.id != 0 { cause_end(rt, scope) }
}

invalidate_root :: proc(rt: ^Runtime, reason := "explicit root invalidation") {
	rt.invalidated = true
	cause_ctx := trace_current_cause(rt)
	scope: Cause_Scope
	if cause_ctx.id == 0 {
		scope = cause_begin(rt, .Application, reason)
		cause_ctx = scope.cause
	}
	if len(rt.last_invalidation_reason) > 0 { delete(rt.last_invalidation_reason, rt.persistent_allocator) }
	rt.last_invalidation_reason = owned(reason, rt.persistent_allocator)
	record_trace_with_cause(rt, .Invalidation, 0, reason, cause_ctx)
	note_pending_work_cause(rt, cause_ctx)
	if scope.cause.id != 0 { cause_end(rt, scope) }
}

// request_presentation wakes the retained presentation path without making
// the application re-emit its description. It is intended for hover, focus,
// caret, selection, and other interaction-only visual changes.
request_presentation :: proc(rt: ^Runtime, reason := "retained presentation changed") {
	rt.presentation_pending = true
	record_trace(rt, .Invalidation, 0, reason)
	note_pending_work_cause(rt, trace_current_cause(rt))
}

advance_presentation_revision :: proc(rt: ^Runtime) {
	rt.presentation_revision += 1
	if rt.presentation_revision == 0 {
		// Keep zero available as the initial generation and force a pending
		// acknowledgement after the practically unreachable u64 wraparound.
		rt.presentation_revision = 1
		rt.submitted_revision = 0
	}
}

presentation_needs_frame :: proc(rt: ^Runtime) -> bool {
	return rt.presentation_pending
}

frame_needs_submission :: proc(rt: ^Runtime) -> bool {
	return rt.presentation_revision != rt.submitted_revision || rt.surface_frame_pending
}

note_submission_cause :: proc(rt: ^Runtime, cause: Cause_Context) {
	if !rt.submission_cause_seen {
		rt.submission_cause_seen = true
		rt.submission_cause = cause
		return
	}
	if rt.submission_cause_mixed { return }
	if rt.submission_cause.id != cause.id {
		rt.submission_cause = Cause_Context{}
		rt.submission_cause_mixed = true
	} else if cause.id != 0 && rt.submission_cause.action_id == Action_ID(0) {
		rt.submission_cause.action_id = cause.action_id
	}
}

// frame_submission_succeeded is the native-host acknowledgement boundary.
// It must be called only after the command buffer has been submitted
// successfully. In particular, a nil swapchain texture is not an
// acknowledgement: the revision remains pending so the host can retry.
frame_submission_succeeded :: proc(rt: ^Runtime) {
	rt.submitted_revision = rt.presentation_revision
	cause := rt.submission_cause if !rt.submission_cause_mixed else Cause_Context{}
	record_trace_with_cause(rt, .Submit, 0, "GPU frame submission acknowledged", cause)
	rt.submission_cause = Cause_Context{}
	rt.submission_cause_seen = false
	rt.submission_cause_mixed = false
}

presentation_frame_consumed :: proc(rt: ^Runtime) {
	// Keep the existing API as a compatibility spelling for hosts that used it
	// as their post-submit acknowledgement. New hosts should call the more
	// explicit frame_submission_succeeded procedure.
	rt.presentation_pending = false
	frame_submission_succeeded(rt)
}

invalidate_region :: proc(rt: ^Runtime, key: string, revision: u64, reason := "explicit region invalidation") {
	// Region keys are the public invalidation handle. Resolve only live regions
	// with that label; silently accepting a typo would make the requested cache
	// invalidation indistinguishable from a successful one.
	match_count := 0
	for _, node in rt.nodes {
		if node.active && node.region && node.label == key { match_count += 1 }
	}
	if match_count == 0 {
		append_diagnostic(rt, fmt.tprintf("invalidate_region could not find a live region named %q at revision %d.\nSuggestion: call it with the same key used by region_begin, after that region has been described at least once.", key, revision))
		return
	}
	// A local region key can intentionally occur under several keyed component
	// scopes. In that case this API invalidates every matching instance, but the
	// requested revision must remain monotonic for every one of them.
	for _, node in rt.nodes {
		if !node.active || !node.region || node.label != key { continue }
		if revision < node.region_revision {
			append_diagnostic(rt, fmt.tprintf("invalidate_region revision regressed for %q.\n  retained region: %s:%d:%d component=%q scope=%q revision=%d\n  requested revision: %d\nSuggestion: keep region revisions monotonic; increment the application's revision when its logical output changes.", key, node.site.file, node.site.line, node.site.column, node.site.component, node.identity_key, node.region_revision, revision))
			return
		}
	}
	for _, node in rt.nodes {
		if !node.active || !node.region || node.label != key { continue }
		// Mark the region's high-water revision before the next build and clear
		// its cache marker. region_begin will therefore reject a stale revision
		// and rebuild when the application supplies the requested revision.
		node.region_revision = revision
		node.region_cached = false
	}
	rt.invalidated = true
	cause_ctx := trace_current_cause(rt)
	scope: Cause_Scope
	if cause_ctx.id == 0 {
		scope = cause_begin(rt, .Application, reason)
		cause_ctx = scope.cause
	}
	if len(rt.last_invalidation_reason) > 0 { delete(rt.last_invalidation_reason, rt.persistent_allocator) }
	rt.last_invalidation_reason = owned(fmt.tprintf("region %s revision %d: %s", key, revision, reason), rt.persistent_allocator)
	record_trace_with_cause(rt, .Invalidation, 0, rt.last_invalidation_reason, cause_ctx)
	note_pending_work_cause(rt, cause_ctx)
	if scope.cause.id != 0 { cause_end(rt, scope) }
}

begin_frame :: proc(rt: ^Runtime) -> (ui: UI, should_build: bool) {
	ui = UI{runtime = rt}
	if !rt.invalidated {
		rt.stats.idle_frames += 1
		return ui, false
	}
	if rt.pending_work_seen {
		rt.frame_cause = rt.pending_work_cause if !rt.pending_work_mixed else Cause_Context{}
	} else {
		rt.frame_cause = Cause_Context{}
	}
	rt.pending_work_cause = Cause_Context{}
	rt.pending_work_seen = false
	rt.pending_work_mixed = false
	// Scratch reset is performed after the previous frame has closed; keep the
	// first frame path minimal while the arena is still empty.
	runtime_scratch_reset(rt)
	rt.frame_open = true
	clear(&rt.pending)
	clear(&rt.seen)
	clear(&rt.identity_scopes)
	clear(&rt.stack)
	clear(&rt.identity_stack)
	clear(&rt.identity_labels)
	clear(&rt.identity_key_u64)
	clear(&rt.identity_key_numeric)
	clear(&rt.identity_key_kind)
	clear(&rt.identity_key_pair)
	// Interaction invalidation may have queued a retained node before the
	// next frame begins. update_paint clears the queue after consuming it;
	// clearing it here would discard focus/caret/selection repaint requests.
	rt.stats.frames_built += 1
	return ui, true
}

// begin_presentation_frame opens a retained-only frame. It never clears or
// reconstructs pending application descriptions, so end_presentation_frame
// cannot accidentally retire the tree. Hosts may use this when an interaction
// update needs paint/composition work but no application callback is needed.
begin_presentation_frame :: proc(rt: ^Runtime) -> (ui: UI, ready: bool) {
	ui = UI{runtime = rt}
	if rt.invalidated || !rt.presentation_pending || rt.frame_open {
		return ui, false
	}
	if rt.pending_work_seen {
		rt.frame_cause = rt.pending_work_cause if !rt.pending_work_mixed else Cause_Context{}
	} else {
		rt.frame_cause = Cause_Context{}
	}
	rt.pending_work_cause = Cause_Context{}
	rt.pending_work_seen = false
	rt.pending_work_mixed = false
	runtime_scratch_reset(rt)
	rt.frame_open = true
	return ui, true
}

current_node_parent :: proc(ui: ^UI) -> Node_ID {
	if len(ui.runtime.stack) == 0 {
		return 0
	}
	return ui.runtime.stack[len(ui.runtime.stack)-1]
}

current_identity_parent :: proc(ui: ^UI) -> Node_ID {
	if len(ui.runtime.identity_stack) == 0 {
		return 0
	}
	return ui.runtime.identity_stack[len(ui.runtime.identity_stack)-1]
}

push_identity_scope :: proc(rt: ^Runtime, id: Node_ID, label: string, kind: u8, numeric: u64 = 0, pair := UI_Key_Pair{}) {
	append(&rt.identity_stack, id)
	append(&rt.identity_labels, label)
	append(&rt.identity_key_u64, numeric)
	append(&rt.identity_key_numeric, kind == 2)
	append(&rt.identity_key_kind, kind)
	append(&rt.identity_key_pair, pair)
}

identity_declaration :: proc(
	rt: ^Runtime,
	source: Source_Site,
	key: UI_Key,
	parent: Node_ID,
	kind: Identity_Declaration_Kind,
	node_kind: Node_Kind = .Root,
	label := "",
) -> Identity_Declaration {
	result := Identity_Declaration{
		source=source,
		parent=parent,
		kind=kind,
		node_kind=node_kind,
		label=label,
		key=key,
		scope_depth=len(rt.identity_stack),
	}
	if len(rt.identity_key_kind) > 0 {
		last := len(rt.identity_key_kind)-1
		result.scope_key_kind = rt.identity_key_kind[last]
		result.scope_key_text = rt.identity_labels[last]
		result.scope_key_u64 = rt.identity_key_u64[last]
		result.scope_key_pair = rt.identity_key_pair[last]
	}
	return result
}

append_identity_key_text :: proc(sb: ^strings.Builder, key: UI_Key) {
	switch value in key {
	case UI_Unkeyed:
		fmt.sbprintf(sb, "unkeyed")
	case string:
		fmt.sbprintf(sb, "string:%q", value)
	case u64:
		fmt.sbprintf(sb, "u64:%d", value)
	case UI_Key_Pair:
		fmt.sbprintf(sb, "pair:(%d,%d)", value.first, value.second)
	}
}

identity_declaration_text :: proc(rt: ^Runtime, declaration: Identity_Declaration) -> string {
	sb := strings.builder_make(0, 128, allocator=rt.scratch_allocator)
	fmt.sbprintf(&sb, "%s:%d:%d component=%q declaration=%v",
		declaration.source.file, declaration.source.line, declaration.source.column,
		declaration.source.component, declaration.kind)
	if declaration.kind == .Node {
		fmt.sbprintf(&sb, " node-kind=%v label=%q", declaration.node_kind, declaration.label)
	} else if declaration.label != "" {
		fmt.sbprintf(&sb, " label=%q", declaration.label)
	}
	fmt.sbprintf(&sb, " identity-parent=%d scope-depth=%d scope-leaf=",
		declaration.parent, declaration.scope_depth)
	switch declaration.scope_key_kind {
	case 1:
		fmt.sbprintf(&sb, "string:%q", declaration.scope_key_text)
	case 2:
		fmt.sbprintf(&sb, "u64:%d", declaration.scope_key_u64)
	case 3:
		pair := declaration.scope_key_pair
		fmt.sbprintf(&sb, "pair:(%d,%d)", pair.first, pair.second)
	case:
		fmt.sbprintf(&sb, "<root-or-node>")
	}
	fmt.sbprintf(&sb, " item-key=")
	append_identity_key_text(&sb, declaration.key)
	return strings.to_string(sb)
}

pop_identity_scope :: proc(rt: ^Runtime) {
	if len(rt.identity_stack) > 0 { pop(&rt.identity_stack) }
	if len(rt.identity_labels) > 0 { pop(&rt.identity_labels) }
	if len(rt.identity_key_u64) > 0 { pop(&rt.identity_key_u64) }
	if len(rt.identity_key_numeric) > 0 { pop(&rt.identity_key_numeric) }
	if len(rt.identity_key_kind) > 0 { pop(&rt.identity_key_kind) }
	if len(rt.identity_key_pair) > 0 { pop(&rt.identity_key_pair) }
}

append_diagnostic :: proc(rt: ^Runtime, message: string) {
	rt.hard_error = true
	if len(rt.diagnostic) > 0 { delete(rt.diagnostic, rt.persistent_allocator) }
	rt.diagnostic = owned(message, rt.persistent_allocator)
	record_trace(rt, .Reconcile, 0, message)
}

	emit :: proc(ui: ^UI, kind: Node_Kind, source: Source_Site, label := "", text := "", key := "", explicit_key := false, style := DEFAULT_STYLE, color := DEFAULT_COLOR, paint_value: u64 = 0, region_revision: u64 = 0, is_region := false, focusable := false, surface_kind := GPU_Surface_Kind.Waveform, surface_pixel_width: int = 0, surface_pixel_height: int = 0, surface_dpi_scale: f32 = 1, paint_background := true, scroll_offset_y: f32 = 0, layout_scroll_offset_y: f32 = -1, scroll_content_height: f32 = 0, scroll_viewport_height: f32 = 0, scroll_line_height: f32 = 0, scroll_offset_x: f32 = 0, layout_scroll_offset_x: f32 = -1, scroll_content_width: f32 = 0, scroll_viewport_width: f32 = 0, scroll_line_width: f32 = 0, scroll_axes := Scroll_Axes.Both, scroll_axis_behavior := Scroll_Axis_Behavior.Auto_Lock, font := Font_Role.UI, text_style := DEFAULT_TEXT_STYLE, button_content := DEFAULT_BUTTON_CONTENT_STYLE) -> Node_ID {
	rt := ui.runtime
	parent_node := current_node_parent(ui)
	parent_identity := current_identity_parent(ui)
	id := identity_hash(parent_identity, source, key, explicit_key)
	identity_key_value: UI_Key = UI_Unkeyed{}
	if explicit_key { identity_key_value = key }
	current_context := identity_declaration(rt, source, identity_key_value, parent_identity, .Node, kind, label)
	if first_context, exists := rt.seen[id]; exists {
		kind_text := explicit_key ? "duplicate key" : "repeated unkeyed sibling"
		append_diagnostic(rt, fmt.tprintf("%s resolved to retained identity %d.\n  first declaration: %s\n  duplicate declaration: %s\nSuggestion: give repeated data items stable unique keys with ui.key_scope/component_begin, and keep the widget call site stable.", kind_text, id, identity_declaration_text(rt, first_context), identity_declaration_text(rt, current_context)))
		return 0
	}
	rt.seen[id] = current_context
	identity_key := ""
	if len(rt.identity_labels) > 0 { identity_key = rt.identity_labels[len(rt.identity_labels)-1] }
	identity_key_u64: u64 = 0
	identity_key_numeric := false
	if len(rt.identity_key_u64) > 0 {
		identity_key_u64 = rt.identity_key_u64[len(rt.identity_key_u64)-1]
		identity_key_numeric = rt.identity_key_numeric[len(rt.identity_key_numeric)-1]
	}
	effective_layout_scroll_offset_y := layout_scroll_offset_y
	if effective_layout_scroll_offset_y < 0 { effective_layout_scroll_offset_y = scroll_offset_y }
	effective_layout_scroll_offset_x := layout_scroll_offset_x
	if effective_layout_scroll_offset_x < 0 { effective_layout_scroll_offset_x = scroll_offset_x }
	description := Description{
		id=id, parent=parent_node, site=source, key=key, explicit_key=explicit_key,
		kind=kind, label=label, text=text, font=font, text_style=text_style, button_content_style=button_content, style=style, color=color, paint_background=paint_background,
		paint_value=paint_value, region_revision=region_revision, region=is_region,
		focusable=focusable, identity_key=identity_key,
		identity_key_u64=identity_key_u64, identity_key_numeric=identity_key_numeric,
		surface_kind=surface_kind, surface_pixel_width=surface_pixel_width,
		surface_pixel_height=surface_pixel_height, surface_dpi_scale=surface_dpi_scale,
		scroll_offset_y=scroll_offset_y, scroll_offset_x=scroll_offset_x,
		layout_scroll_offset_y=effective_layout_scroll_offset_y, layout_scroll_offset_x=effective_layout_scroll_offset_x,
		scroll_content_height=scroll_content_height, scroll_viewport_height=scroll_viewport_height, scroll_line_height=scroll_line_height,
		scroll_content_width=scroll_content_width, scroll_viewport_width=scroll_viewport_width, scroll_line_width=scroll_line_width,
		scroll_axes=scroll_axes, scroll_axis_behavior=scroll_axis_behavior,
	}
	append(&rt.pending, Pending_Item{.Description, description, 0})
	rt.stats.descriptions_emitted += 1
	rt.stats.stage_visits[.Description] += 1
	return id
}

	emit_key :: proc(ui: ^UI, kind: Node_Kind, source: Source_Site, label := "", text := "", key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, color := DEFAULT_COLOR, state_bits: u64 = 0, selected := false, disabled := false, region_revision: u64 = 0, is_region := false, focusable := false, surface_kind := GPU_Surface_Kind.Waveform, surface_pixel_width: int = 0, surface_pixel_height: int = 0, surface_dpi_scale: f32 = 1, paint_background := true, scroll_offset_y: f32 = 0, layout_scroll_offset_y: f32 = -1, scroll_content_height: f32 = 0, scroll_viewport_height: f32 = 0, scroll_line_height: f32 = 0, scroll_offset_x: f32 = 0, layout_scroll_offset_x: f32 = -1, scroll_content_width: f32 = 0, scroll_viewport_width: f32 = 0, scroll_line_width: f32 = 0, scroll_axes := Scroll_Axes.Both, scroll_axis_behavior := Scroll_Axis_Behavior.Auto_Lock, font := Font_Role.UI, text_style := DEFAULT_TEXT_STYLE, button_content := DEFAULT_BUTTON_CONTENT_STYLE) -> Node_ID {
	rt := ui.runtime
	parent_node := current_node_parent(ui)
	parent_identity := current_identity_parent(ui)
	id := identity_hash_key(parent_identity, source, key)
	current_context := identity_declaration(rt, source, key, parent_identity, .Node, kind, label)
	if first_context, exists := rt.seen[id]; exists {
		kind_text := ui_key_is_explicit(key) ? "duplicate key" : "repeated unkeyed sibling"
		append_diagnostic(rt, fmt.tprintf("%s resolved to retained identity %d.\n  first declaration: %s\n  duplicate declaration: %s\nSuggestion: give repeated data items stable unique keys with ui.key_scope/component_begin, and keep the widget call site stable.", kind_text, id, identity_declaration_text(rt, first_context), identity_declaration_text(rt, current_context)))
		return 0
	}
	rt.seen[id] = current_context
	identity_key := ""
	identity_key_u64: u64 = 0
	identity_key_numeric := false
	identity_key_kind: u8 = 0
	identity_key_pair := UI_Key_Pair{}
	if len(rt.identity_labels) > 0 { identity_key = rt.identity_labels[len(rt.identity_labels)-1] }
	if len(rt.identity_key_u64) > 0 {
		identity_key_u64 = rt.identity_key_u64[len(rt.identity_key_u64)-1]
		identity_key_numeric = rt.identity_key_numeric[len(rt.identity_key_numeric)-1]
		identity_key_kind = rt.identity_key_kind[len(rt.identity_key_kind)-1]
		identity_key_pair = rt.identity_key_pair[len(rt.identity_key_pair)-1]
	}
	key_string_value := ""
	key_kind: u8 = 0
	switch value in key {
	case UI_Unkeyed:
		key_kind = 0
	case string:
		key_string_value = value
		key_kind = 1
	case u64:
		identity_key_u64 = value
		identity_key_numeric = true
		key_kind = 2
	case UI_Key_Pair:
		identity_key_pair = value
		key_kind = 3
	}
	effective_layout_scroll_offset_y := layout_scroll_offset_y
	if effective_layout_scroll_offset_y < 0 { effective_layout_scroll_offset_y = scroll_offset_y }
	effective_layout_scroll_offset_x := layout_scroll_offset_x
	if effective_layout_scroll_offset_x < 0 { effective_layout_scroll_offset_x = scroll_offset_x }
	description := Description{
		id=id, parent=parent_node, site=source, key=key_string_value, explicit_key=ui_key_is_explicit(key),
		identity_key_kind=key_kind, identity_key_pair=identity_key_pair,
		kind=kind, label=label, text=text, font=font, text_style=text_style, button_content_style=button_content, style=style, color=color, paint_background=paint_background,
		paint_value=state_bits, region_revision=region_revision, region=is_region,
		focusable=focusable, selected=selected, disabled=disabled, identity_key=identity_key,
		identity_key_u64=identity_key_u64, identity_key_numeric=identity_key_numeric,
		surface_kind=surface_kind, surface_pixel_width=surface_pixel_width,
		surface_pixel_height=surface_pixel_height, surface_dpi_scale=surface_dpi_scale,
		scroll_offset_y=scroll_offset_y, scroll_offset_x=scroll_offset_x,
		layout_scroll_offset_y=effective_layout_scroll_offset_y, layout_scroll_offset_x=effective_layout_scroll_offset_x,
		scroll_content_height=scroll_content_height, scroll_viewport_height=scroll_viewport_height, scroll_line_height=scroll_line_height,
		scroll_content_width=scroll_content_width, scroll_viewport_width=scroll_viewport_width, scroll_line_width=scroll_line_width,
		scroll_axes=scroll_axes, scroll_axis_behavior=scroll_axis_behavior,
	}
	append(&rt.pending, Pending_Item{.Description, description, 0})
	rt.stats.descriptions_emitted += 1
	rt.stats.stage_visits[.Description] += 1
	return id
}

key_scope :: proc(ui: ^UI, key: string, source: Source_Site, body: proc()) {
	if !key_scope_begin_ex(ui, key, source) { return }
	body()
	key_scope_end(ui)
}

key_scope_begin_ex :: proc(ui: ^UI, key: string, source := Source_Site{}, loc := #caller_location) -> bool {
	rt := ui.runtime
	resolved_source := resolve_source(source, "key_scope", loc)
	parent := current_identity_parent(ui)
	id := identity_hash(parent, resolved_source, key, true)
	current_context := identity_declaration(rt, resolved_source, UI_Key(key), parent, .Key_Scope, label=key)
	if first_context, exists := rt.identity_scopes[id]; exists {
		append_diagnostic(rt, fmt.tprintf("duplicate key scope resolved to identity %d.\n  first declaration: %s\n  duplicate declaration: %s\nSuggestion: use a different stable key for each sibling item.", id, identity_declaration_text(rt, first_context), identity_declaration_text(rt, current_context)))
		return false
	}
	rt.identity_scopes[id] = current_context
	push_identity_scope(rt, id, key, 1)
	return true
}

key_scope_begin_key :: proc(ui: ^UI, key: UI_Key, source := Source_Site{}, loc := #caller_location) -> bool {
	rt := ui.runtime
	resolved_source := resolve_source(source, "key_scope", loc)
	parent := current_identity_parent(ui)
	id := identity_hash_key(parent, resolved_source, key)
	current_context := identity_declaration(rt, resolved_source, key, parent, .Key_Scope)
	if first_context, exists := rt.identity_scopes[id]; exists {
		append_diagnostic(rt, fmt.tprintf("duplicate key scope resolved to identity %d.\n  first declaration: %s\n  duplicate declaration: %s\nSuggestion: use a different stable key for each sibling item.", id, identity_declaration_text(rt, first_context), identity_declaration_text(rt, current_context)))
		return false
	}
	rt.identity_scopes[id] = current_context
	switch value in key {
	case UI_Unkeyed:
		push_identity_scope(rt, id, "", 0)
	case string:
		push_identity_scope(rt, id, value, 1)
	case u64:
		push_identity_scope(rt, id, "", 2, value)
	case UI_Key_Pair:
		push_identity_scope(rt, id, "", 3, pair=value)
	}
	return true
}

key_scope_begin :: proc(ui: ^UI, key: UI_Key, loc := #caller_location) -> bool {
	return key_scope_begin_key(ui, key, Source_Site{}, loc)
}

// key_scope_u64 is the allocation-free typed-key path used by large keyed
// trees. It has the same identity and ambiguity rules as string keys.
key_scope_u64 :: proc(ui: ^UI, key: u64, source := Source_Site{}, loc := #caller_location) -> bool {
	rt := ui.runtime
	resolved_source := resolve_source(source, "key_scope_u64", loc)
	parent := current_identity_parent(ui)
	id := identity_hash_u64(parent, resolved_source, key)
	current_context := identity_declaration(rt, resolved_source, UI_Key(key), parent, .Numeric_Key_Scope)
	if first_context, exists := rt.identity_scopes[id]; exists {
		append_diagnostic(rt, fmt.tprintf("duplicate numeric key scope resolved to identity %d.\n  first declaration: %s\n  duplicate declaration: %s\nSuggestion: use a different stable numeric key for each sibling item.", id, identity_declaration_text(rt, first_context), identity_declaration_text(rt, current_context)))
		return false
	}
	rt.identity_scopes[id] = current_context
	push_identity_scope(rt, id, "", 2, key)
	return true
}

// component_begin creates an invocation scope from the actual application
// call site. It is the ergonomic boundary for reusable helpers that need
// distinct identity even when their widget call sites are shared.
component_begin_key :: proc(ui: ^UI, key: UI_Key, loc := #caller_location) -> bool {
	return key_scope_begin_key(ui, key, resolve_source(Source_Site{}, "component", loc))
}

component_begin_ex :: proc(ui: ^UI, key: string, loc := #caller_location) -> bool {
	return key_scope_begin_ex(ui, key, resolve_source(Source_Site{}, "component", loc))
}

component_begin :: proc(ui: ^UI, key: UI_Key, loc := #caller_location) -> bool {
	return component_begin_key(ui, key, loc)
}

component_end :: proc(ui: ^UI) {
	key_scope_end(ui)
}

key_scope_end :: proc(ui: ^UI) {
	pop_identity_scope(ui.runtime)
}

container_begin_ex :: proc(ui: ^UI, kind: Node_Kind, source := Source_Site{}, label := "", key := "", explicit_key := false, style := DEFAULT_STYLE, color := NO_BACKGROUND_COLOR, paint_value: u64 = 0, focusable := false, loc := #caller_location, scroll_offset_y: f32 = 0, layout_scroll_offset_y: f32 = -1, scroll_offset_x: f32 = 0, layout_scroll_offset_x: f32 = -1) -> Node_ID {
	resolved_source := resolve_source(source, "container", loc)
	resolved_color, paints := resolve_container_color(kind, color)
	id := emit(ui, kind, resolved_source, label=label, key=key, explicit_key=explicit_key, style=style, color=resolved_color, paint_value=paint_value, focusable=focusable, paint_background=paints, scroll_offset_y=scroll_offset_y, layout_scroll_offset_y=layout_scroll_offset_y, scroll_offset_x=scroll_offset_x, layout_scroll_offset_x=layout_scroll_offset_x)
	if id != 0 {
		append(&ui.runtime.stack, id)
		push_identity_scope(ui.runtime, id, "", 0)
	}
	return id
}

container_end :: proc(ui: ^UI) {
	if len(ui.runtime.stack) > 0 { pop(&ui.runtime.stack) }
	pop_identity_scope(ui.runtime)
}

// A structural wrapper can be made identity-transparent when a caller wants a
// keyed item's descendants to survive that wrapper being introduced or
// removed. The retained hierarchy still records the wrapper for layout.
transparent_container_begin :: proc(ui: ^UI, kind: Node_Kind, source := Source_Site{}, label := "", key := "", explicit_key := false, style := DEFAULT_STYLE, color := NO_BACKGROUND_COLOR, paint_value: u64 = 0, focusable := false, loc := #caller_location) -> Node_ID {
	resolved_source := resolve_source(source, "container", loc)
	resolved_color, paints := resolve_container_color(kind, color)
	id := emit(ui, kind, resolved_source, label=label, key=key, explicit_key=explicit_key, style=style, color=resolved_color, paint_value=paint_value, focusable=focusable, paint_background=paints)
	if id != 0 { append(&ui.runtime.stack, id) }
	return id
}

transparent_container_end :: proc(ui: ^UI) {
	if len(ui.runtime.stack) > 0 { pop(&ui.runtime.stack) }
}

container_ex :: proc(ui: ^UI, kind: Node_Kind, source := Source_Site{}, body: proc(), label := "", key := "", explicit_key := false, style := DEFAULT_STYLE, color := NO_BACKGROUND_COLOR, paint_value: u64 = 0, focusable := false, loc := #caller_location, scroll_offset_y: f32 = 0, layout_scroll_offset_y: f32 = -1, scroll_offset_x: f32 = 0, layout_scroll_offset_x: f32 = -1) -> Node_ID {
	resolved_source := resolve_source(source, "container", loc)
	id := container_begin_ex(ui, kind, resolved_source, label, key, explicit_key, style, color, paint_value, focusable, loc, scroll_offset_y, layout_scroll_offset_y, scroll_offset_x, layout_scroll_offset_x)
	if id == 0 { return 0 }
	body()
	container_end(ui)
	return id
}

root_ex :: proc(ui: ^UI, source := Source_Site{}, body: proc(), style := DEFAULT_STYLE, loc := #caller_location) -> Node_ID {
	resolved_source := resolve_source(source, "root", loc)
	return container_ex(ui, .Root, resolved_source, body, label="root", style=style)
}

container_begin_simple :: proc(ui: ^UI, kind: Node_Kind, label := "", key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, color := NO_BACKGROUND_COLOR, state_bits: u64 = 0, selected := false, disabled := false, focusable := false, loc := #caller_location, scroll_offset_y: f32 = 0, layout_scroll_offset_y: f32 = -1, scroll_offset_x: f32 = 0, layout_scroll_offset_x: f32 = -1) -> Node_ID {
	resolved_source := resolve_source(Source_Site{}, "container", loc)
	resolved_color, paints := resolve_container_color(kind, color)
	id := emit_key(ui, kind, resolved_source, label=label, key=key, style=style, color=resolved_color, state_bits=state_bits, selected=selected, disabled=disabled, focusable=focusable && !disabled, paint_background=paints, scroll_offset_y=scroll_offset_y, layout_scroll_offset_y=layout_scroll_offset_y, scroll_offset_x=scroll_offset_x, layout_scroll_offset_x=layout_scroll_offset_x)
	if id != 0 {
		append(&ui.runtime.stack, id)
		push_identity_scope(ui.runtime, id, "", 0)
	}
	return id
}

container_simple :: proc(ui: ^UI, kind: Node_Kind, body: proc(), label := "", key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, color := NO_BACKGROUND_COLOR, loc := #caller_location, scroll_offset_y: f32 = 0, layout_scroll_offset_y: f32 = -1, scroll_offset_x: f32 = 0, layout_scroll_offset_x: f32 = -1) -> Node_ID {
	id := container_begin_simple(ui, kind, label, key, style, color, 0, false, false, false, loc, scroll_offset_y, layout_scroll_offset_y, scroll_offset_x, layout_scroll_offset_x)
	if id == 0 { return 0 }
	body()
	container_end(ui)
	return id
}

root_simple :: proc(ui: ^UI, body: proc(), style := DEFAULT_STYLE, loc := #caller_location) -> Node_ID {
	return container_simple(ui, .Root, body, label="root", style=style, loc=loc)
}

container_begin :: proc(ui: ^UI, kind: Node_Kind, label := "", key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, color := NO_BACKGROUND_COLOR, state_bits: u64 = 0, selected := false, disabled := false, focusable := false, loc := #caller_location, scroll_offset_y: f32 = 0, layout_scroll_offset_y: f32 = -1, scroll_offset_x: f32 = 0, layout_scroll_offset_x: f32 = -1) -> Node_ID {
	return container_begin_simple(ui, kind, label, key, style, color, state_bits, selected, disabled, focusable, loc, scroll_offset_y, layout_scroll_offset_y, scroll_offset_x, layout_scroll_offset_x)
}

container :: proc(ui: ^UI, kind: Node_Kind, body: proc(), label := "", key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, color := NO_BACKGROUND_COLOR, loc := #caller_location) -> Node_ID {
	return container_simple(ui, kind, body, label, key, style, color, loc)
}

// modal_overlay_begin starts a viewport-sized top-level layer. Describe the
// ordinary application roots first, close them, then describe the overlay.
// Its children paint above the workspace; pointer, wheel, and focus traversal
// stay inside the overlay until it is removed from the next description.
modal_overlay_begin :: proc(
	ui: ^UI,
	key: UI_Key,
	style := DEFAULT_STYLE,
	backdrop_color := Color{0.02, 0.025, 0.04, 0.68},
	loc := #caller_location,
) -> Node_ID {
	if len(ui.runtime.stack) != 0 {
		append_diagnostic(ui.runtime, "modal_overlay_begin must be called after closing the ordinary root")
		return 0
	}
	return container_begin_simple(
		ui,
		.Modal_Overlay,
		label="modal-overlay",
		key=key,
		style=style,
		color=backdrop_color,
		loc=loc,
	)
}

modal_overlay_end :: proc(ui: ^UI) {
	if len(ui.runtime.stack) == 0 {
		append_diagnostic(ui.runtime, "modal_overlay_end called without an open modal overlay")
		return
	}
	id := ui.runtime.stack[len(ui.runtime.stack)-1]
	is_overlay := false
	for item in ui.runtime.pending {
		if item.kind == .Description && item.description.id == id && item.description.kind == .Modal_Overlay {
			is_overlay = true
			break
		}
	}
	if !is_overlay {
		append_diagnostic(ui.runtime, "modal_overlay_end must follow its overlay children")
		return
	}
	container_end(ui)
}

// Split_Handle is a lightweight description-time handle for one retained
// two-pane split. Its position and drag state live on the keyed runtime node.
Split_Handle :: struct {
	id:       Node_ID,
	axis:     Split_Axis,
	position: f32,
}

DEFAULT_SPLIT_STYLE :: Layout_Style{.Column, -1, -1, 0, -1, 0, -1, 1, 0, 0, .Stretch, true}
SPLIT_DIVIDER_MIN_THICKNESS :: 1.0
SPLIT_DIVIDER_MAX_THICKNESS :: 4.0
SPLIT_DIVIDER_MIN_HIT_SIZE :: 8.0
SPLIT_DIVIDER_MAX_HIT_SIZE :: 12.0

// split_begin opens a keyed split container. Compose two panes with
// split_first_begin/end and split_second_begin/end, placing split_divider
// between them, then close the split with split_end. The preferred position
// seeds new retained state; later application builds preserve the user's drag.
split_begin :: proc(
	ui: ^UI,
	key: UI_Key,
	axis: Split_Axis,
	initial: f32,
	min_first: f32 = 0,
	min_second: f32 = 0,
	style := DEFAULT_SPLIT_STYLE,
	label := "split",
	loc := #caller_location,
) -> Split_Handle {
	split_style := style
	split_style.direction = .Row if axis == .Horizontal else .Column
	source := resolve_source(Source_Site{}, "split", loc)
	id := emit_key(ui, .Split, source, label=label, key=key, style=split_style, paint_background=false)
	if id == 0 { return {} }
	item := &ui.runtime.pending[len(ui.runtime.pending)-1].description
	item.split_axis = axis
	item.split_position = maxf(initial, 0)
	item.split_min_first = maxf(min_first, 0)
	item.split_min_second = maxf(min_second, 0)
	append(&ui.runtime.stack, id)
	push_identity_scope(ui.runtime, id, "", 0)
	position := item.split_position
	if previous, ok := ui.runtime.nodes[id]; ok && previous.kind == .Split {
		position = previous.split_position
	}
	return Split_Handle{id, axis, position}
}

split_first_begin :: proc(ui: ^UI, split: Split_Handle) -> Node_ID {
	return container_begin_simple(
		ui, .Container, label="split-first", key=key_string("first"),
		style=layout_style(grow=1, clip=true),
	)
}

split_first_end :: proc(ui: ^UI, split: Split_Handle) { container_end(ui) }

split_second_begin :: proc(ui: ^UI, split: Split_Handle) -> Node_ID {
	return container_begin_simple(
		ui, .Container, label="split-second", key=key_string("second"),
		style=layout_style(grow=1, clip=true),
	)
}

split_second_end :: proc(ui: ^UI, split: Split_Handle) { container_end(ui) }

// split_divider inserts the runtime-owned interaction target between the two
// panes. Visual thickness is kept narrow while hit_size makes it easy to grab.
split_divider :: proc(ui: ^UI, split: Split_Handle, thickness: f32 = 2, hit_size: f32 = 10, loc := #caller_location) -> Node_ID {
	if split.id == 0 { return 0 }
	visible_thickness := clampf(thickness, SPLIT_DIVIDER_MIN_THICKNESS, SPLIT_DIVIDER_MAX_THICKNESS)
	interaction_size := clampf(hit_size, SPLIT_DIVIDER_MIN_HIT_SIZE, SPLIT_DIVIDER_MAX_HIT_SIZE)
	style := layout_style(width=visible_thickness, height=-1) if split.axis == .Horizontal else layout_style(width=-1, height=visible_thickness)
	id := emit_key(ui, .Split_Handle, resolve_source(Source_Site{}, "split_divider", loc), label="split-divider", key=key_string("divider"), style=style)
	if id != 0 {
		description := &ui.runtime.pending[len(ui.runtime.pending)-1].description
		description.split_owner = split.id
		description.split_axis = split.axis
		description.split_handle_size = visible_thickness
		description.split_hit_size = maxf(interaction_size, visible_thickness)
	}
	return id
}

split_end :: proc(ui: ^UI, split: Split_Handle) { container_end(ui) }

root :: proc(ui: ^UI, body: proc(), style := DEFAULT_STYLE, loc := #caller_location) -> Node_ID {
	return root_simple(ui, body, style, loc)
}

// Scroll_Region_Handle is the resolved, retained state of a fixed-height
// scroll region. The offset is owned by the runtime; applications use the
// handle only to virtualize their content during the current description.
Scroll_Region_Handle :: struct {
	id:              Node_ID,
	offset_y:        f32,
	offset_x:        f32,
	viewport_height: f32,
	viewport_width:  f32,
	content_height:  f32,
	content_width:   f32,
	max_scroll_y:    f32,
	max_scroll_x:    f32,
	viewport_bounds: Rect,
	vertical_bar_visible: bool,
	horizontal_bar_visible: bool,
}

scroll_region_begin :: proc(
	ui: ^UI,
	key: UI_Key = UI_Unkeyed{},
	viewport_height: f32 = 0,
	content_height: f32 = 0,
	line_height: f32 = 24,
	viewport_width: f32 = 0,
	content_width: f32 = 0,
	line_width: f32 = 24,
	style := DEFAULT_STYLE,
	color := NO_BACKGROUND_COLOR,
	label := "scroll-region",
	loc := #caller_location,
	axes := Scroll_Axes.Both,
	axis_behavior := Scroll_Axis_Behavior.Auto_Lock,
	scrollbars := Scrollbar_Policy.Auto,
	focusable := false,
) -> Scroll_Region_Handle {
	rt := ui.runtime
	resolved_source := resolve_source(Source_Site{}, "scroll_region", loc)
	resolved_color, paints := resolve_container_color(.Scroll_Region, color)
	resolved_viewport := viewport_height
	if resolved_viewport <= 0 {
		if style.height >= 0 { resolved_viewport = style.height }
		if resolved_viewport <= 0 { resolved_viewport = 180 }
	}
	resolved_width := viewport_width
	if resolved_width <= 0 {
		if style.width >= 0 { resolved_width = style.width }
		if resolved_width <= 0 { resolved_width = 320 }
	}
	outer_height, outer_width := resolved_viewport, resolved_width
	geometry := scroll_bar_geometry(Rect{0, 0, outer_width, outer_height}, content_width, content_height, style.padding, axes, scrollbars)
	resolved_viewport = geometry.viewport.h
	resolved_width = geometry.viewport.w
	max_scroll := maxf(content_height-resolved_viewport, 0)
	max_scroll_x := maxf(content_width-resolved_width, 0)
	id := emit_key(
		ui, .Scroll_Region, resolved_source, label=label, key=key,
		style=style, color=resolved_color, paint_background=paints, focusable=focusable,
		scroll_content_height=content_height,
		scroll_viewport_height=resolved_viewport,
		scroll_line_height=line_height,
		scroll_content_width=content_width,
		scroll_viewport_width=resolved_width,
		scroll_line_width=line_width,
		scroll_axes=axes,
		scroll_axis_behavior=axis_behavior,
	)
	if id == 0 { return {} }
	last := len(rt.pending)-1
	if last >= 0 && rt.pending[last].kind == .Description && rt.pending[last].description.id == id {
		rt.pending[last].description.scrollbar_policy = scrollbars
	}
	// A description is emitted before layout resolves the new bounds. Reuse
	// the previous retained offset so a rebuild does not jump to the top.
	offset_y := f32(0)
	offset_x := f32(0)
	if previous, ok := rt.nodes[id]; ok {
		// An explicit viewport is authoritative (useful for fixed layouts and
		// resize tests). Grow-based regions pass zero and reuse the last
		// resolved layout height until the new layout has run.
		if viewport_height <= 0 && style.height < 0 && previous.bounds.h > 0 {
			outer_height = previous.bounds.h
		}
		if viewport_width <= 0 && style.width < 0 && previous.bounds.w > 0 {
			outer_width = previous.bounds.w
		}
		geometry = scroll_bar_geometry(Rect{0, 0, outer_width, outer_height}, content_width, content_height, style.padding, axes, scrollbars, previous.scroll_offset_x, previous.scroll_offset_y)
		resolved_viewport = geometry.viewport.h
		resolved_width = geometry.viewport.w
		offset_y = clampf(previous.scroll_offset_y, 0, maxf(content_height-resolved_viewport, 0))
		offset_x = clampf(previous.scroll_offset_x, 0, maxf(content_width-resolved_width, 0))
		max_scroll = maxf(content_height-resolved_viewport, 0)
		max_scroll_x = maxf(content_width-resolved_width, 0)
	}
	last = len(rt.pending)-1
	if last >= 0 && rt.pending[last].kind == .Description && rt.pending[last].description.id == id {
		rt.pending[last].description.scroll_offset_y = offset_y
		rt.pending[last].description.scroll_viewport_height = resolved_viewport
		rt.pending[last].description.layout_scroll_offset_y = 0
		rt.pending[last].description.scroll_offset_x = offset_x
		rt.pending[last].description.scroll_viewport_width = resolved_width
		rt.pending[last].description.layout_scroll_offset_x = 0
	}
	append(&rt.stack, id)
	push_identity_scope(rt, id, "", 0)
	return Scroll_Region_Handle{
		id=id,
		offset_y=offset_y,
		offset_x=offset_x,
		viewport_height=resolved_viewport,
		viewport_width=resolved_width,
		content_height=content_height,
		content_width=content_width,
		max_scroll_y=max_scroll,
		max_scroll_x=max_scroll_x,
		vertical_bar_visible=geometry.vertical_visible,
		horizontal_bar_visible=geometry.horizontal_visible,
	}
}

scroll_region_end :: proc(ui: ^UI) {
	container_end(ui)
}

scroll_region_offset :: proc(rt: ^Runtime, id: Node_ID) -> f32 {
	if node, ok := rt.nodes[id]; ok && node.kind == .Scroll_Region { return node.scroll_offset_y }
	return 0
}

scroll_region_offset_x :: proc(rt: ^Runtime, id: Node_ID) -> f32 {
	if node, ok := rt.nodes[id]; ok && node.kind == .Scroll_Region { return node.scroll_offset_x }
	return 0
}

// scroll_region_state exposes the retained geometry needed by event handlers
// and other explicit application commands. It does not expose the retained
// node or transfer ownership of any runtime state.
scroll_region_state :: proc(rt: ^Runtime, id: Node_ID) -> Scroll_Region_Handle {
	if node, ok := rt.nodes[id]; ok && node.kind == .Scroll_Region {
		viewport_height := node.scroll_viewport_height
		if viewport_height <= 0 && !node.scroll_geometry_resolved { viewport_height = node.bounds.h }
		viewport_width := node.scroll_viewport_width
		if viewport_width <= 0 && !node.scroll_geometry_resolved { viewport_width = node.bounds.w }
		return Scroll_Region_Handle{
			id = id,
			offset_y = node.scroll_offset_y,
			offset_x = node.scroll_offset_x,
			viewport_height = viewport_height,
			viewport_width = viewport_width,
			content_height = node.scroll_content_height,
			content_width = node.scroll_content_width,
			max_scroll_y = maxf(node.scroll_content_height-viewport_height, 0),
			max_scroll_x = maxf(node.scroll_content_width-viewport_width, 0),
			viewport_bounds = node.scroll_viewport_bounds,
			vertical_bar_visible = node.scrollbar_vertical_visible,
			horizontal_bar_visible = node.scrollbar_horizontal_visible,
		}
	}
	return {}
}

scroll_region_set_offset :: proc(rt: ^Runtime, id: Node_ID, offset_y: f32, reason := "scroll region offset changed") -> bool {
	node, ok := rt.nodes[id]
	if !ok || !node.active || node.kind != .Scroll_Region { return false }
	viewport := node.scroll_viewport_height
	if viewport <= 0 && !node.scroll_geometry_resolved { viewport = node.bounds.h }
	max_scroll := maxf(node.scroll_content_height-viewport, 0)
	next := clampf(offset_y, 0, max_scroll)
	if next == node.scroll_offset_y { return false }
	node.scroll_offset_y = next
	invalidate_root(rt, reason)
	return true
}

scroll_region_set_offset_x :: proc(rt: ^Runtime, id: Node_ID, offset_x: f32, reason := "horizontal scroll region offset changed") -> bool {
	node, ok := rt.nodes[id]
	if !ok || !node.active || node.kind != .Scroll_Region { return false }
	viewport := node.scroll_viewport_width
	if viewport <= 0 && !node.scroll_geometry_resolved { viewport = node.bounds.w }
	max_scroll := maxf(node.scroll_content_width-viewport, 0)
	next := clampf(offset_x, 0, max_scroll)
	if next == node.scroll_offset_x { return false }
	node.scroll_offset_x = next
	node.layout_scroll_offset_x = next
	invalidate_root(rt, reason)
	return true
}

// virtual_list_ensure_visible is the intent-level companion to
// virtual_list_begin. The retained region already knows its fixed row height
// and viewport, so selection/navigation code need not duplicate scroll math.
virtual_list_ensure_visible :: proc(rt: ^Runtime, id: Node_ID, index: int, reason := "virtual list selection visibility changed") -> bool {
	node, ok := rt.nodes[id]
	if !ok || !node.active || node.kind != .Scroll_Region || index < 0 { return false }
	row_height := node.scroll_line_height
	if row_height <= 0 { return false }
	viewport := node.scroll_viewport_height
	if viewport <= 0 && !node.scroll_geometry_resolved { viewport = node.bounds.h }
	if viewport <= 0 { return false }
	top := f32(index) * row_height
	bottom := top + row_height
	next := node.scroll_offset_y
	if top < next {
		next = top
	} else if bottom > next+viewport {
		next = bottom-viewport
	}
	return scroll_region_set_offset(rt, id, next, reason)
}

button_ex :: proc(ui: ^UI, label: string, source := Source_Site{}, key := "", explicit_key := false, style := DEFAULT_STYLE, paint_value: u64 = 0, loc := #caller_location, text_style := DEFAULT_BUTTON_TEXT_STYLE, content_style := DEFAULT_BUTTON_CONTENT_STYLE) -> (id: Node_ID, clicked: bool) {
	resolved_source := resolve_source(source, "button", loc)
	id = emit(ui, .Button, resolved_source, label=label, key=key, explicit_key=explicit_key, style=style, paint_value=paint_value, focusable=true, text_style=text_style, button_content=content_style)
	clicked = consume_activation(ui.runtime, id)
	return
}

text_ex :: proc(ui: ^UI, value: string, source := Source_Site{}, key := "", explicit_key := false, style := DEFAULT_STYLE, paint_value: u64 = 0, loc := #caller_location, font := Font_Role.UI, text_style := DEFAULT_TEXT_STYLE) -> Node_ID {
	resolved_source := resolve_source(source, "text", loc)
	return emit(ui, .Text, resolved_source, text=value, key=key, explicit_key=explicit_key, style=style, paint_value=paint_value, font=font, text_style=text_style)
}

text_field_ex :: proc(ui: ^UI, value: string, source := Source_Site{}, key := "", explicit_key := false, style := DEFAULT_STYLE, loc := #caller_location, font := Font_Role.UI, text_style := DEFAULT_TEXT_STYLE) -> Node_ID {
	resolved_source := resolve_source(source, "text_field", loc)
	return emit(ui, .Text_Field, resolved_source, text=value, key=key, explicit_key=explicit_key, style=style, focusable=true, font=font, text_style=text_style)
}

consume_activation :: proc(rt: ^Runtime, id: Node_ID) -> bool {
	if id == 0 || rt.activation_node != id || rt.activation_sequence == 0 { return false }
	if node, ok := rt.nodes[id]; ok && node.last_consumed_activation < rt.activation_sequence {
		node.last_consumed_activation = rt.activation_sequence
		return true
	}
	return false
}

slider_normalize :: proc(value, minimum, maximum, step: f32) -> f32 {
	// Unlike layout's sentinel-aware clampf, slider ranges may legitimately be
	// entirely negative, so both bounds are always applied explicitly here.
	result := minf(maxf(value, minimum), maximum)
	// Keep the endpoints reachable even when the range is not an exact multiple
	// of the snapping increment (for example 0..1 with step 0.3).
	if result <= minimum || result >= maximum { return result }
	if step > 0 {
		steps := int((result-minimum)/step + 0.5)
		result = minf(maximum, minimum+f32(steps)*step)
	}
	return result
}

// checkbox is app-authoritative: store the returned value when changed. A
// focused checkbox activates with Space; pointer activation uses the same
// one-shot retained input path as button.
checkbox :: proc(
	ui: ^UI,
	label: string,
	checked: bool,
	key: UI_Key = UI_Unkeyed{},
	style := DEFAULT_STYLE,
	disabled := false,
	loc := #caller_location,
) -> Control_Change_Bool {
	source := resolve_source(Source_Site{}, "checkbox", loc)
	paint_value: u64 = 0
	if checked { paint_value = 1 }
	id := emit_key(ui, .Checkbox, source, label=label, key=key, style=style, state_bits=paint_value, disabled=disabled, focusable=!disabled, text_style=DEFAULT_BUTTON_TEXT_STYLE)
	result := Control_Change_Bool{value=checked}
	if id == 0 || disabled { return result }
	if consume_activation(ui.runtime, id) {
		result.value = !checked
		result.changed = true
		ui.runtime.pending[len(ui.runtime.pending)-1].description.paint_value = 1 if result.value else 0
	}
	return result
}

// slider_f32 describes a horizontal, controlled slider. A zero step is
// continuous; arrow keys then move by one percent of the range. Positive
// steps quantize to the nearest step from `minimum` and clamp at both ends.
// Store the returned value when changed. Pointer coordinates and dimensions
// are logical units, so the control follows the runtime's DPI-independent
// layout contract.
slider_f32 :: proc(
	ui: ^UI,
	label: string,
	value, minimum, maximum: f32,
	step: f32 = 0,
	key: UI_Key = UI_Unkeyed{},
	style := DEFAULT_STYLE,
	disabled := false,
	loc := #caller_location,
) -> Control_Change_F32 {
	result := Control_Change_F32{value=value}
	range := maximum-minimum
	if math.is_nan(minimum) || math.is_inf(minimum) || math.is_nan(maximum) || math.is_inf(maximum) ||
		math.is_nan(value) || math.is_inf(value) || math.is_nan(step) || math.is_inf(step) ||
		math.is_inf(range) || maximum <= minimum || step < 0 {
		append_diagnostic(ui.runtime, fmt.tprintf("slider_f32 requires a finite value, an increasing finite range, and a finite step >= 0 (got value=%.4f range=%.4f..%.4f step=%.4f).\nSuggestion: use step=0 for continuous input.", value, minimum, maximum, step))
		return result
	}
	result.value = slider_normalize(value, minimum, maximum, step)
	result.changed = result.value != value
	source := resolve_source(Source_Site{}, "slider_f32", loc)
	id := emit_key(ui, .Slider, source, label=label, key=key, style=style, disabled=disabled, focusable=!disabled, text_style=DEFAULT_BUTTON_TEXT_STYLE)
	if id == 0 { return result }
	if node, ok := ui.runtime.nodes[id]; ok && node.control_pending {
		result.value = slider_normalize(node.control_pending_value, minimum, maximum, step)
		result.changed = result.value != value
		node.control_pending = false
	}
	description := &ui.runtime.pending[len(ui.runtime.pending)-1].description
	description.control_value = result.value
	description.control_minimum = minimum
	description.control_maximum = maximum
	description.control_step = step
	return result
}

button_simple :: proc(ui: ^UI, label: string, key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, state := Button_State{}, loc := #caller_location, text_style := DEFAULT_BUTTON_TEXT_STYLE, content_style := DEFAULT_BUTTON_CONTENT_STYLE) -> bool {
	resolved_source := resolve_source(Source_Site{}, "button", loc)
	paint_state: u64 = 0
	if state.selected { paint_state |= 1 }
	if state.disabled { paint_state |= 2 }
	if state.quiet { paint_state |= 4 }
	id := emit_key(ui, .Button, resolved_source, label=label, key=key, style=style, state_bits=paint_state, selected=state.selected, disabled=state.disabled, focusable=!state.disabled, text_style=text_style, button_content=content_style)
	if id == 0 || state.disabled { return false }
	return consume_activation(ui.runtime, id)
}

text_simple :: proc(ui: ^UI, value: string, key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, loc := #caller_location, font := Font_Role.UI, text_style := DEFAULT_TEXT_STYLE) -> Node_ID {
	return emit_key(ui, .Text, resolve_source(Source_Site{}, "text", loc), text=value, key=key, style=style, font=font, text_style=text_style)
}

text_field_simple :: proc(ui: ^UI, value: string, key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, loc := #caller_location, font := Font_Role.UI, text_style := DEFAULT_TEXT_STYLE) -> Node_ID {
	return emit_key(ui, .Text_Field, resolve_source(Source_Site{}, "text_field", loc), text=value, key=key, style=style, focusable=true, font=font, text_style=text_style)
}

button :: proc(ui: ^UI, label: string, key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, state := Button_State{}, loc := #caller_location, text_style := DEFAULT_BUTTON_TEXT_STYLE, content_style := DEFAULT_BUTTON_CONTENT_STYLE) -> bool {
	return button_simple(ui, label, key, style, state, loc, text_style, content_style)
}

// semantic_bind associates the most recently described presentation node with
// an application-owned logical identity. Call it immediately after describing
// the widget; the identity is retained independently from that node's lifetime.
semantic_bind :: proc(ui: ^UI, id: Semantic_ID) -> bool {
	if !semantic_id_is_valid(id) { return false }
	rt := ui.runtime
	if len(rt.pending) == 0 { return false }
	last := len(rt.pending)-1
	if rt.pending[last].kind != .Description { return false }
	rt.pending[last].description.semantic_id = id
	return true
}

text :: proc(ui: ^UI, value: string, key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, loc := #caller_location, font := Font_Role.UI, text_style := DEFAULT_TEXT_STYLE) -> Node_ID {
	return text_simple(ui, value, key, style, loc, font, text_style)
}

text_field :: proc(ui: ^UI, value: string, key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, loc := #caller_location, font := Font_Role.UI, text_style := DEFAULT_TEXT_STYLE) -> Node_ID {
	return text_field_simple(ui, value, key, style, loc, font, text_style)
}

region_begin :: proc(ui: ^UI, key: string, revision: u64, source := Source_Site{}, style := DEFAULT_STYLE, loc := #caller_location) -> (id: Node_ID, reused: bool) {
	rt := ui.runtime
	resolved_source := resolve_source(source, "region", loc)
	id = emit(ui, .Container, resolved_source, label=key, key=key, explicit_key=true, style=style, region_revision=revision, is_region=true)
	if id == 0 {
		return 0, false
	}
	effective_revision := revision
	if old, ok := rt.nodes[id]; ok && old.region && revision < old.region_revision {
		append_diagnostic(rt, fmt.tprintf("region revision regressed for %q.\n  retained region: %s:%d:%d component=%q key=%q scope=%q revision=%d\n  new description: %s:%d:%d component=%q key=%q scope-depth=%d revision=%d\nSuggestion: keep the region revision monotonic; increment it when the region's logical output changes.", key, old.site.file, old.site.line, old.site.column, old.site.component, old.key, old.identity_key, old.region_revision, resolved_source.file, resolved_source.line, resolved_source.column, resolved_source.component, key, len(rt.identity_stack), revision))
		// Preserve the retained high-water revision so another stale description
		// cannot make the cache appear current on a later frame.
		effective_revision = old.region_revision
		rt.pending[len(rt.pending)-1].description.region_revision = effective_revision
	}
	if old, ok := rt.nodes[id]; ok && old.region && old.region_cached && old.region_revision == effective_revision {
		rt.stats.regions_skipped += 1
		rt.stats.retained_subtrees_reused += 1
		// The cached retained hierarchy is already authoritative. A marker is
		// enough to keep the subtree present; descendants are not copied into a
		// flat pending description list.
		append(&rt.pending, Pending_Item{.Reuse_Subtree, Description{}, id})
		record_trace(rt, .Reconcile, id, "retained subtree reused without descendant descriptions")
		return id, true
	}
	append(&rt.stack, id)
	push_identity_scope(rt, id, "", 0)
	return id, false
}

region_end :: proc(ui: ^UI, id: Node_ID, reused: bool, start: int) {
	if reused || id == 0 { return }
	pop(&ui.runtime.stack)
	pop_identity_scope(ui.runtime)
}

region_ex :: proc(ui: ^UI, key: string, revision: u64, source := Source_Site{}, body: proc(), style := DEFAULT_STYLE, loc := #caller_location) -> Node_ID {
	resolved_source := resolve_source(source, "region", loc)
	id, reused := region_begin(ui, key, revision, resolved_source, style)
	if !reused && id != 0 {
		start := len(ui.runtime.pending)
		body()
		region_end(ui, id, false, start)
	}
	return id
}

region_simple :: proc(ui: ^UI, key: string, revision: u64, body: proc(), style := DEFAULT_STYLE, loc := #caller_location) -> Node_ID {
	return region_ex(ui, key, revision, Source_Site{}, body, style, loc)
}

region :: proc(ui: ^UI, key: string, revision: u64, body: proc(), style := DEFAULT_STYLE, loc := #caller_location) -> Node_ID {
	return region_simple(ui, key, revision, body, style, loc)
}

Virtual_List_Metrics :: struct {
	first:          int,
	last:           int,
	content_height: f32,
	max_scroll_y:   f32,
	offset_y:       f32,
	leading_offset_y: f32,
}

// virtual_list_metrics is the shared fixed-height scroll calculation. It
// clamps the offset to the actual content/viewport bounds and preserves the
// fractional leading offset so a list can move continuously between rows.
virtual_list_metrics :: proc(item_count: int, scroll_y, viewport_height, row_height: f32) -> Virtual_List_Metrics {
	result := Virtual_List_Metrics{}
	if item_count <= 0 || row_height <= 0 || viewport_height <= 0 { return result }
	result.content_height = f32(item_count) * row_height
	result.max_scroll_y = maxf(result.content_height-viewport_height, 0)
	result.offset_y = clampf(scroll_y, 0, result.max_scroll_y)
	result.first = int(result.offset_y / row_height)
	if result.first >= item_count { result.first = item_count-1 }
	result.last = int((result.offset_y+viewport_height) / row_height) + 1
	if result.last > item_count { result.last = item_count }
	if result.last < result.first+1 { result.last = result.first+1 }
	result.leading_offset_y = result.offset_y - f32(result.first)*row_height
	return result
}

// Virtual_List_Handle is the resolved, current-description view of a retained
// fixed-row list. The application owns row data and logical keys; Alicorn owns
// the retained scroll offset and returns only the range that needs emission.
Virtual_List_Handle :: struct {
	scroll: Scroll_Region_Handle,
	first:  int,
	last:   int,
}

// virtual_list_begin composes the common retained scroll-region and
// fixed-height virtualization path. It opens both the scroll region and its
// clipped virtual-list content container; call virtual_list_end after emitting
// rows. The range is bounded to visible/frontier work and remains valid for
// fractional scroll offsets.
virtual_list_begin :: proc(
	ui: ^UI,
	item_count: int,
	row_height: f32,
	key: UI_Key = UI_Unkeyed{},
	style := DEFAULT_STYLE,
	content_width: f32 = 0,
	line_width: f32 = 24,
	color := NO_BACKGROUND_COLOR,
	label := "virtual-list",
	loc := #caller_location,
	axes := Scroll_Axes.Vertical,
	axis_behavior := Scroll_Axis_Behavior.Auto_Lock,
	scrollbars := Scrollbar_Policy.Auto,
	focusable := false,
) -> Virtual_List_Handle {
	if item_count < 0 || row_height <= 0 { return {} }
	region_style := style
	region_style.direction = .Column
	region_style.clip = true
	content_height := f32(item_count) * row_height
	scroll := scroll_region_begin(
		ui,
		key=key,
		content_height=content_height,
		line_height=row_height,
		content_width=content_width,
		line_width=line_width,
		style=region_style,
		color=color,
		label=label,
		loc=loc,
		axes=axes,
		axis_behavior=axis_behavior,
		scrollbars=scrollbars,
		focusable=focusable,
	)
	if scroll.id == 0 { return {} }
	metrics := virtual_list_metrics(item_count, scroll.offset_y, scroll.viewport_height, row_height)
	// The content node is clipped to the resolved scroll viewport. Give it
	// that same height explicitly: an unconstrained Column child otherwise
	// falls back to intrinsic_main's default 24 logical pixels, which clips
	// taller rows differently across displays with different pixel densities.
	content_style := layout_style(width=-1, height=scroll.viewport_height, clip=true)
	if content_width > 0 { content_style.width = content_width }
	container_begin(
		ui,
		.Virtual_List,
		label=label,
		style=content_style,
		loc=loc,
		scroll_offset_y=metrics.offset_y,
		layout_scroll_offset_y=metrics.leading_offset_y,
		scroll_offset_x=scroll.offset_x,
		layout_scroll_offset_x=scroll.offset_x,
	)
	return Virtual_List_Handle{scroll=scroll, first=metrics.first, last=metrics.last}
}

virtual_list_end :: proc(ui: ^UI, list: Virtual_List_Handle) {
	if list.scroll.id == 0 { return }
	container_end(ui)
	scroll_region_end(ui)
}

// virtual_list requires a logical item key. Viewport position is not identity:
// callers must return the same key for an item when it moves in the source data.
// The realized children are clipped to the list viewport and receive the
// fractional offset from virtual_list_metrics.
virtual_list_ex :: proc(ui: ^UI, item_count: int, scroll_y, viewport_height, row_height: f32, source: Source_Site, item_key: proc(index: int) -> string, row: proc(ui: ^UI, index: int)) -> (first, last: int) {
	metrics := virtual_list_metrics(item_count, scroll_y, viewport_height, row_height)
	first, last = metrics.first, metrics.last
	if first == last { return }
	style := Layout_Style{.Column, -1, viewport_height, 0, -1, 0, -1, 0, 0, 0, .Stretch, true}
	container_begin_ex(ui, .Virtual_List, source, label="virtual-list", style=style, scroll_offset_y=metrics.offset_y, layout_scroll_offset_y=metrics.leading_offset_y)
	for i := first; i < last; i += 1 {
		if key_scope_begin_ex(ui, item_key(i), source) {
			row(ui, i)
			key_scope_end(ui)
		}
	}
	container_end(ui)
	return
}

virtual_list_simple :: proc(ui: ^UI, item_count: int, scroll_y, viewport_height, row_height: f32, item_key: proc(index: int) -> UI_Key, row: proc(ui: ^UI, index: int), loc := #caller_location) -> (first, last: int) {
	metrics := virtual_list_metrics(item_count, scroll_y, viewport_height, row_height)
	first, last = metrics.first, metrics.last
	if first == last { return }
	style := Layout_Style{.Column, -1, viewport_height, 0, -1, 0, -1, 0, 0, 0, .Stretch, true}
	container_begin_simple(ui, .Virtual_List, label="virtual-list", style=style, loc=loc, scroll_offset_y=metrics.offset_y, layout_scroll_offset_y=metrics.leading_offset_y)
	for i := first; i < last; i += 1 {
		if key_scope_begin_key(ui, item_key(i), Source_Site{}, loc) {
			row(ui, i)
			key_scope_end(ui)
		}
	}
	container_end(ui)
	return
}

virtual_list :: proc(ui: ^UI, item_count: int, scroll_y, viewport_height, row_height: f32, item_key: proc(index: int) -> UI_Key, row: proc(ui: ^UI, index: int), loc := #caller_location) -> (first, last: int) {
	return virtual_list_simple(ui, item_count, scroll_y, viewport_height, row_height, item_key, row, loc)
}

custom_surface :: proc(ui: ^UI, surface_key: string, frame: u64, logical_bounds: Rect, pixel_width, pixel_height: int, dpi_scale: f32, source := Source_Site{}, loc := #caller_location) -> Node_ID {
	resolved_source := resolve_source(source, "custom_surface", loc)
	style := DEFAULT_STYLE
	style.width = logical_bounds.w
	style.height = logical_bounds.h
	return emit(ui, .Custom_Surface, resolved_source, label=surface_key, key=surface_key, explicit_key=true, style=style, paint_value=frame, color=Color{0.15, 0.25, 0.42, 1}, surface_pixel_width=pixel_width, surface_pixel_height=pixel_height, surface_dpi_scale=dpi_scale)
}

// gpu_surface is the explicit public name for the retained surface contract;
// custom_surface remains as the compatibility spelling used by the first
// native fixture.
gpu_surface_ex :: proc(ui: ^UI, surface_key: string, revision: u64, logical_bounds: Rect, pixel_width, pixel_height: int, dpi_scale: f32, source := Source_Site{}, loc := #caller_location) -> Node_ID {
	return custom_surface(ui, surface_key, revision, logical_bounds, pixel_width, pixel_height, dpi_scale, source, loc)
}

gpu_surface_simple :: proc(ui: ^UI, surface_key: string, revision: u64, logical_bounds: Rect, pixel_width, pixel_height: int, dpi_scale: f32, loc := #caller_location) -> Node_ID {
	return custom_surface(ui, surface_key, revision, logical_bounds, pixel_width, pixel_height, dpi_scale, Source_Site{}, loc)
}

gpu_surface :: proc(ui: ^UI, surface_key: string, revision: u64, logical_bounds: Rect, pixel_width, pixel_height: int, dpi_scale: f32, loc := #caller_location) -> Node_ID {
	return gpu_surface_simple(ui, surface_key, revision, logical_bounds, pixel_width, pixel_height, dpi_scale, loc)
}

// gpu_geometry_surface_ex creates a retained colored-geometry surface whose
// bounds are resolved by Alicorn layout. Geometry update coordinates are
// logical units local to the resulting bounds. Pixel extent is derived from
// the resolved bounds and dpi_scale when queried through gpu_surface_context.
gpu_geometry_surface_ex :: proc(
	ui: ^UI,
	surface_key: string,
	revision: u64,
	style: Layout_Style,
	dpi_scale: f32 = 1,
	source := Source_Site{},
	loc := #caller_location,
) -> Node_ID {
	resolved_source := resolve_source(source, "gpu_geometry_surface", loc)
	return emit(
		ui, .Custom_Surface, resolved_source,
		label=surface_key,
	key=surface_key,
	explicit_key=true,
	style=style,
	paint_value=revision,
	color=Color{0.08, 0.14, 0.24, 1},
	surface_kind=.Geometry,
	surface_dpi_scale=dpi_scale,
	)
}

gpu_geometry_surface_simple :: proc(
	ui: ^UI,
	surface_key: string,
	revision: u64,
	style: Layout_Style,
	dpi_scale: f32 = 1,
	loc := #caller_location,
) -> Node_ID {
	return gpu_geometry_surface_ex(ui, surface_key, revision, style, dpi_scale, Source_Site{}, loc)
}

gpu_geometry_surface :: proc(
	ui: ^UI,
	surface_key: string,
	revision: u64,
	style: Layout_Style,
	dpi_scale: f32 = 1,
	loc := #caller_location,
) -> Node_ID {
	return gpu_geometry_surface_simple(ui, surface_key, revision, style, dpi_scale, loc)
}
