package alicorn

import "core:fmt"
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
	Container,
	Button,
	Text,
	Text_Field,
	Text_Composition,
	Text_Selection,
	Text_Caret,
	Virtual_List,
	Virtual_Row,
	Custom_Surface,
}

GPU_Surface_Kind :: enum {
	Waveform,
}

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

Source_Site :: struct {
	file:      string,
	line:      int,
	column:    int,
	component: string,
}

Pointer_Kind :: enum { Move, Down, Up }

Pointer_Event :: struct {
	kind:   Pointer_Kind,
	x, y:   f32,
	button: int,
}

// Scroll_Event preserves both precise device deltas and whole wheel ticks.
// Hosts normalize their platform direction before handing the event to an
// application; the application decides how many logical pixels a tick means.
Scroll_Event :: struct {
	delta_x: f32,
	delta_y: f32,
	ticks_x: int,
	ticks_y: int,
	x, y:    f32,
}

Text_Edit_Kind :: enum { Insert, Backspace, Delete }

Text_Edit :: struct {
	kind: Text_Edit_Kind,
	text: string,
}

Button_State :: struct {
	selected: bool,
	disabled: bool,
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
	style:       Layout_Style,
	color:       Color,
	paint_background: bool,
	paint_value: u64,
	region_revision: u64,
	region:      bool,
	focusable:   bool,
	selected:    bool,
	disabled:    bool,
	identity_key: string,
	identity_key_u64: u64,
	identity_key_numeric: bool,
	surface_kind: GPU_Surface_Kind,
	surface_pixel_width: int,
	surface_pixel_height: int,
	surface_dpi_scale: f32,
	scroll_offset_y: f32,
	// The logical scroll position remains authoritative for application state
	// and scrollbar calculations. Virtualized lists use this residual offset
	// to place only the realized rows after preceding rows were omitted.
	layout_scroll_offset_y: f32,
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
	style:       Layout_Style,
	color:       Color,
	paint_background: bool,
	paint_value: u64,
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
	last_consumed_activation: u64,
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
	layout_scroll_offset_y: f32,
	surface_revision: u64,
	surface_samples: [dynamic]f32,
	bounds:      Rect,
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

Trace_Kind :: enum {
	Pointer,
	Focus,
	Invalidation,
	Reconcile,
	Layout,
	Paint,
	Composite,
	Retire,
}

Trace_Event :: struct {
	sequence: u64,
	kind:     Trace_Kind,
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
	seen:        map[Node_ID]bool,
	identity_scopes: map[Node_ID]bool,
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
	last_hovered: Node_ID,
	captured_node: Node_ID,
	activation_node: Node_ID,
	activation_sequence: u64,
	paint_queue: [dynamic]Node_ID,
	composition_rebuild: bool,
	invalidated: bool,
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
	display:     [dynamic]Display_Command,
	text_engine: Text_Engine,
	text_font_generation_seen: u64,
	surface_frame_pending: bool,
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
	rt.seen = make(map[Node_ID]bool, allocator=rt.persistent_allocator)
	rt.identity_scopes = make(map[Node_ID]bool, allocator=rt.persistent_allocator)
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

record_trace :: proc(rt: ^Runtime, kind: Trace_Kind, node: Node_ID, reason: string) {
	rt.trace.sequence += 1
	entry := Trace_Event{sequence=rt.trace.sequence, kind=kind, node=node, reason=owned_with_allocator(reason, rt.persistent_allocator), reason_owned=true}
	old := &rt.trace.events[rt.trace.next]
	if old.reason_owned && len(old.reason) > 0 { delete(old.reason, rt.persistent_allocator) }
	rt.trace.events[rt.trace.next] = entry
	rt.trace.next = (rt.trace.next + 1) % len(rt.trace.events)
	if rt.trace.count < len(rt.trace.events) {
		rt.trace.count += 1
	}
}

// High-frequency retained products can use an immutable literal reason
// without creating one heap string per update. The ring still bounds event
// storage; only the ownership policy differs for this process-lifetime text.
record_trace_literal :: proc(rt: ^Runtime, kind: Trace_Kind, node: Node_ID, reason: string) {
	rt.trace.sequence += 1
	entry := Trace_Event{sequence=rt.trace.sequence, kind=kind, node=node, reason=reason, reason_owned=false}
	old := &rt.trace.events[rt.trace.next]
	if old.reason_owned && len(old.reason) > 0 { delete(old.reason, rt.persistent_allocator) }
	rt.trace.events[rt.trace.next] = entry
	rt.trace.next = (rt.trace.next + 1) % len(rt.trace.events)
	if rt.trace.count < len(rt.trace.events) { rt.trace.count += 1 }
}

invalidate_root :: proc(rt: ^Runtime, reason := "explicit root invalidation") {
	rt.invalidated = true
	if len(rt.last_invalidation_reason) > 0 { delete(rt.last_invalidation_reason, rt.persistent_allocator) }
	rt.last_invalidation_reason = owned(reason, rt.persistent_allocator)
	record_trace(rt, .Invalidation, 0, reason)
}

// request_presentation wakes the retained presentation path without making
// the application re-emit its description. It is intended for hover, focus,
// caret, selection, and other interaction-only visual changes.
request_presentation :: proc(rt: ^Runtime, reason := "retained presentation changed") {
	rt.presentation_pending = true
	record_trace(rt, .Invalidation, 0, reason)
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

// frame_submission_succeeded is the native-host acknowledgement boundary.
// It must be called only after the command buffer has been submitted
// successfully. In particular, a nil swapchain texture is not an
// acknowledgement: the revision remains pending so the host can retry.
frame_submission_succeeded :: proc(rt: ^Runtime) {
	rt.submitted_revision = rt.presentation_revision
}

presentation_frame_consumed :: proc(rt: ^Runtime) {
	// Keep the existing API as a compatibility spelling for hosts that used it
	// as their post-submit acknowledgement. New hosts should call the more
	// explicit frame_submission_succeeded procedure.
	rt.presentation_pending = false
	frame_submission_succeeded(rt)
}

invalidate_region :: proc(rt: ^Runtime, key: string, revision: u64, reason := "explicit region invalidation") {
	// Region revisions are carried by the next description. The key is included
	// in the trace so the invalidation remains structurally inspectable.
	rt.invalidated = true
	if len(rt.last_invalidation_reason) > 0 { delete(rt.last_invalidation_reason, rt.persistent_allocator) }
	rt.last_invalidation_reason = owned(fmt.tprintf("region %s revision %d: %s", key, revision, reason), rt.persistent_allocator)
	record_trace(rt, .Invalidation, 0, rt.last_invalidation_reason)
}

begin_frame :: proc(rt: ^Runtime) -> (ui: UI, should_build: bool) {
	ui = UI{runtime = rt}
	if !rt.invalidated {
		rt.stats.idle_frames += 1
		return ui, false
	}
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

emit :: proc(ui: ^UI, kind: Node_Kind, source: Source_Site, label := "", text := "", key := "", explicit_key := false, style := DEFAULT_STYLE, color := DEFAULT_COLOR, paint_value: u64 = 0, region_revision: u64 = 0, is_region := false, focusable := false, surface_kind := GPU_Surface_Kind.Waveform, surface_pixel_width: int = 0, surface_pixel_height: int = 0, surface_dpi_scale: f32 = 1, paint_background := true, scroll_offset_y: f32 = 0, layout_scroll_offset_y: f32 = -1) -> Node_ID {
	rt := ui.runtime
	parent_node := current_node_parent(ui)
	parent_identity := current_identity_parent(ui)
	id := identity_hash(parent_identity, source, key, explicit_key)
	if rt.seen[id] {
		kind_text := explicit_key ? "duplicate key" : "repeated unkeyed sibling"
		append_diagnostic(rt, fmt.tprintf("%s at %s:%d:%d component=%s key=%q; add a unique ui.key_scope or key", kind_text, source.file, source.line, source.column, source.component, key))
		return 0
	}
	rt.seen[id] = true
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
	description := Description{
		id=id, parent=parent_node, site=source, key=key, explicit_key=explicit_key,
		kind=kind, label=label, text=text, style=style, color=color, paint_background=paint_background,
		paint_value=paint_value, region_revision=region_revision, region=is_region,
		focusable=focusable, identity_key=identity_key,
		identity_key_u64=identity_key_u64, identity_key_numeric=identity_key_numeric,
		surface_kind=surface_kind, surface_pixel_width=surface_pixel_width,
		surface_pixel_height=surface_pixel_height, surface_dpi_scale=surface_dpi_scale,
		scroll_offset_y=scroll_offset_y, layout_scroll_offset_y=effective_layout_scroll_offset_y,
	}
	append(&rt.pending, Pending_Item{.Description, description, 0})
	rt.stats.descriptions_emitted += 1
	rt.stats.stage_visits[.Description] += 1
	return id
}

emit_key :: proc(ui: ^UI, kind: Node_Kind, source: Source_Site, label := "", text := "", key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, color := DEFAULT_COLOR, state_bits: u64 = 0, selected := false, disabled := false, region_revision: u64 = 0, is_region := false, focusable := false, surface_kind := GPU_Surface_Kind.Waveform, surface_pixel_width: int = 0, surface_pixel_height: int = 0, surface_dpi_scale: f32 = 1, paint_background := true, scroll_offset_y: f32 = 0, layout_scroll_offset_y: f32 = -1) -> Node_ID {
	rt := ui.runtime
	parent_node := current_node_parent(ui)
	parent_identity := current_identity_parent(ui)
	id := identity_hash_key(parent_identity, source, key)
	if rt.seen[id] {
		kind_text := ui_key_is_explicit(key) ? "duplicate key" : "repeated unkeyed sibling"
		append_diagnostic(rt, fmt.tprintf("%s at %s:%d:%d component=%s; add a unique key", kind_text, source.file, source.line, source.column, source.component))
		return 0
	}
	rt.seen[id] = true
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
	description := Description{
		id=id, parent=parent_node, site=source, key=key_string_value, explicit_key=ui_key_is_explicit(key),
		identity_key_kind=key_kind, identity_key_pair=identity_key_pair,
		kind=kind, label=label, text=text, style=style, color=color, paint_background=paint_background,
		paint_value=state_bits, region_revision=region_revision, region=is_region,
		focusable=focusable, selected=selected, disabled=disabled, identity_key=identity_key,
		identity_key_u64=identity_key_u64, identity_key_numeric=identity_key_numeric,
		surface_kind=surface_kind, surface_pixel_width=surface_pixel_width,
		surface_pixel_height=surface_pixel_height, surface_dpi_scale=surface_dpi_scale,
		scroll_offset_y=scroll_offset_y, layout_scroll_offset_y=effective_layout_scroll_offset_y,
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
	if rt.identity_scopes[id] {
		append_diagnostic(rt, fmt.tprintf("duplicate key scope at %s:%d:%d component=%s key=%q", resolved_source.file, resolved_source.line, resolved_source.column, resolved_source.component, key))
		return false
	}
	rt.identity_scopes[id] = true
	push_identity_scope(rt, id, key, 1)
	return true
}

key_scope_begin_key :: proc(ui: ^UI, key: UI_Key, source := Source_Site{}, loc := #caller_location) -> bool {
	rt := ui.runtime
	resolved_source := resolve_source(source, "key_scope", loc)
	parent := current_identity_parent(ui)
	id := identity_hash_key(parent, resolved_source, key)
	if rt.identity_scopes[id] {
		append_diagnostic(rt, fmt.tprintf("duplicate key scope at %s:%d:%d component=%s", resolved_source.file, resolved_source.line, resolved_source.column, resolved_source.component))
		return false
	}
	rt.identity_scopes[id] = true
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
	if rt.identity_scopes[id] {
		append_diagnostic(rt, fmt.tprintf("duplicate numeric key scope at %s:%d:%d component=%s key=%d", resolved_source.file, resolved_source.line, resolved_source.column, resolved_source.component, key))
		return false
	}
	rt.identity_scopes[id] = true
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

container_begin_ex :: proc(ui: ^UI, kind: Node_Kind, source := Source_Site{}, label := "", key := "", explicit_key := false, style := DEFAULT_STYLE, color := NO_BACKGROUND_COLOR, paint_value: u64 = 0, focusable := false, loc := #caller_location, scroll_offset_y: f32 = 0, layout_scroll_offset_y: f32 = -1) -> Node_ID {
	resolved_source := resolve_source(source, "container", loc)
	resolved_color, paints := resolve_container_color(kind, color)
	id := emit(ui, kind, resolved_source, label=label, key=key, explicit_key=explicit_key, style=style, color=resolved_color, paint_value=paint_value, focusable=focusable, paint_background=paints, scroll_offset_y=scroll_offset_y, layout_scroll_offset_y=layout_scroll_offset_y)
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

container_ex :: proc(ui: ^UI, kind: Node_Kind, source := Source_Site{}, body: proc(), label := "", key := "", explicit_key := false, style := DEFAULT_STYLE, color := NO_BACKGROUND_COLOR, paint_value: u64 = 0, focusable := false, loc := #caller_location, scroll_offset_y: f32 = 0, layout_scroll_offset_y: f32 = -1) -> Node_ID {
	resolved_source := resolve_source(source, "container", loc)
	id := container_begin_ex(ui, kind, resolved_source, label, key, explicit_key, style, color, paint_value, focusable, scroll_offset_y=scroll_offset_y, layout_scroll_offset_y=layout_scroll_offset_y)
	if id == 0 { return 0 }
	body()
	container_end(ui)
	return id
}

root_ex :: proc(ui: ^UI, source := Source_Site{}, body: proc(), style := DEFAULT_STYLE, loc := #caller_location) -> Node_ID {
	resolved_source := resolve_source(source, "root", loc)
	return container_ex(ui, .Root, resolved_source, body, label="root", style=style)
}

container_begin_simple :: proc(ui: ^UI, kind: Node_Kind, label := "", key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, color := NO_BACKGROUND_COLOR, state_bits: u64 = 0, selected := false, disabled := false, focusable := false, loc := #caller_location, scroll_offset_y: f32 = 0, layout_scroll_offset_y: f32 = -1) -> Node_ID {
	resolved_source := resolve_source(Source_Site{}, "container", loc)
	resolved_color, paints := resolve_container_color(kind, color)
	id := emit_key(ui, kind, resolved_source, label=label, key=key, style=style, color=resolved_color, state_bits=state_bits, selected=selected, disabled=disabled, focusable=focusable && !disabled, paint_background=paints, scroll_offset_y=scroll_offset_y, layout_scroll_offset_y=layout_scroll_offset_y)
	if id != 0 {
		append(&ui.runtime.stack, id)
		push_identity_scope(ui.runtime, id, "", 0)
	}
	return id
}

container_simple :: proc(ui: ^UI, kind: Node_Kind, body: proc(), label := "", key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, color := NO_BACKGROUND_COLOR, loc := #caller_location, scroll_offset_y: f32 = 0, layout_scroll_offset_y: f32 = -1) -> Node_ID {
	id := container_begin_simple(ui, kind, label, key, style, color, 0, false, false, false, loc, scroll_offset_y, layout_scroll_offset_y)
	if id == 0 { return 0 }
	body()
	container_end(ui)
	return id
}

root_simple :: proc(ui: ^UI, body: proc(), style := DEFAULT_STYLE, loc := #caller_location) -> Node_ID {
	return container_simple(ui, .Root, body, label="root", style=style, loc=loc)
}

container_begin :: proc(ui: ^UI, kind: Node_Kind, label := "", key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, color := NO_BACKGROUND_COLOR, state_bits: u64 = 0, selected := false, disabled := false, focusable := false, loc := #caller_location, scroll_offset_y: f32 = 0, layout_scroll_offset_y: f32 = -1) -> Node_ID {
	return container_begin_simple(ui, kind, label, key, style, color, state_bits, selected, disabled, focusable, loc, scroll_offset_y, layout_scroll_offset_y)
}

container :: proc(ui: ^UI, kind: Node_Kind, body: proc(), label := "", key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, color := NO_BACKGROUND_COLOR, loc := #caller_location) -> Node_ID {
	return container_simple(ui, kind, body, label, key, style, color, loc)
}

root :: proc(ui: ^UI, body: proc(), style := DEFAULT_STYLE, loc := #caller_location) -> Node_ID {
	return root_simple(ui, body, style, loc)
}

button_ex :: proc(ui: ^UI, label: string, source := Source_Site{}, key := "", explicit_key := false, style := DEFAULT_STYLE, paint_value: u64 = 0, loc := #caller_location) -> (id: Node_ID, clicked: bool) {
	resolved_source := resolve_source(source, "button", loc)
	id = emit(ui, .Button, resolved_source, label=label, key=key, explicit_key=explicit_key, style=style, paint_value=paint_value, focusable=true)
	if id != 0 && ui.runtime.activation_node == id && ui.runtime.activation_sequence > 0 {
		if node, ok := ui.runtime.nodes[id]; ok {
			if node.last_consumed_activation < ui.runtime.activation_sequence {
				node.last_consumed_activation = ui.runtime.activation_sequence
				clicked = true
			}
		}
	}
	return
}

text_ex :: proc(ui: ^UI, value: string, source := Source_Site{}, key := "", explicit_key := false, style := DEFAULT_STYLE, paint_value: u64 = 0, loc := #caller_location) -> Node_ID {
	resolved_source := resolve_source(source, "text", loc)
	return emit(ui, .Text, resolved_source, text=value, key=key, explicit_key=explicit_key, style=style, paint_value=paint_value)
}

text_field_ex :: proc(ui: ^UI, value: string, source := Source_Site{}, key := "", explicit_key := false, style := DEFAULT_STYLE, loc := #caller_location) -> Node_ID {
	resolved_source := resolve_source(source, "text_field", loc)
	return emit(ui, .Text_Field, resolved_source, text=value, key=key, explicit_key=explicit_key, style=style, focusable=true)
}

button_simple :: proc(ui: ^UI, label: string, key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, state := Button_State{}, loc := #caller_location) -> bool {
	resolved_source := resolve_source(Source_Site{}, "button", loc)
	paint_state: u64 = 0
	if state.selected { paint_state |= 1 }
	if state.disabled { paint_state |= 2 }
	id := emit_key(ui, .Button, resolved_source, label=label, key=key, style=style, state_bits=paint_state, selected=state.selected, disabled=state.disabled, focusable=!state.disabled)
	if id == 0 || state.disabled { return false }
	if ui.runtime.activation_node == id && ui.runtime.activation_sequence > 0 {
		if node, ok := ui.runtime.nodes[id]; ok && node.last_consumed_activation < ui.runtime.activation_sequence {
			node.last_consumed_activation = ui.runtime.activation_sequence
			return true
		}
	}
	return false
}

text_simple :: proc(ui: ^UI, value: string, key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, loc := #caller_location) -> Node_ID {
	return emit_key(ui, .Text, resolve_source(Source_Site{}, "text", loc), text=value, key=key, style=style)
}

text_field_simple :: proc(ui: ^UI, value: string, key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, loc := #caller_location) -> Node_ID {
	return emit_key(ui, .Text_Field, resolve_source(Source_Site{}, "text_field", loc), text=value, key=key, style=style, focusable=true)
}

button :: proc(ui: ^UI, label: string, key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, state := Button_State{}, loc := #caller_location) -> bool {
	return button_simple(ui, label, key, style, state, loc)
}

text :: proc(ui: ^UI, value: string, key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, loc := #caller_location) -> Node_ID {
	return text_simple(ui, value, key, style, loc)
}

text_field :: proc(ui: ^UI, value: string, key: UI_Key = UI_Unkeyed{}, style := DEFAULT_STYLE, loc := #caller_location) -> Node_ID {
	return text_field_simple(ui, value, key, style, loc)
}

region_begin :: proc(ui: ^UI, key: string, revision: u64, source := Source_Site{}, style := DEFAULT_STYLE, loc := #caller_location) -> (id: Node_ID, reused: bool) {
	rt := ui.runtime
	resolved_source := resolve_source(source, "region", loc)
	id = emit(ui, .Container, resolved_source, label=key, key=key, explicit_key=true, style=style, region_revision=revision, is_region=true)
	if id == 0 {
		return 0, false
	}
	if old, ok := rt.nodes[id]; ok && old.region && old.region_cached && old.region_revision == revision {
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
