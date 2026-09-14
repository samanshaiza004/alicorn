package alicorn

import "core:fmt"
import "core:strings"

Node_ID :: distinct u64

Node_Kind :: enum {
	Root,
	Container,
	Button,
	Text,
	Text_Field,
	Text_Selection,
	Text_Caret,
	Virtual_List,
	Virtual_Row,
	Custom_Surface,
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

Text_Edit_Kind :: enum { Insert, Backspace, Delete }

Text_Edit :: struct {
	kind: Text_Edit_Kind,
	text: string,
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

Dirty_Stages :: struct {
	description: bool,
	layout:      bool,
	paint:       bool,
	composite:   bool,
}

Description :: struct {
	id:          Node_ID,
	parent:      Node_ID,
	site:        Source_Site,
	key:         string,
	explicit_key: bool,
	kind:        Node_Kind,
	label:       string,
	text:        string,
	style:       Layout_Style,
	color:       Color,
	paint_value: u64,
	region_revision: u64,
	region:      bool,
	focusable:   bool,
	identity_key: string,
	identity_key_u64: u64,
	identity_key_numeric: bool,
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
	kind:        Node_Kind,
	label:       string,
	text:        string,
	style:       Layout_Style,
	color:       Color,
	paint_value: u64,
	region_revision: u64,
	region:      bool,
	region_cached: bool,
	focusable:   bool,
	active:      bool,
	present:     bool,
	hovered:     bool,
	pressed:     bool,
	selected:    bool,
	last_consumed_activation: u64,
	caret_byte:  int,
	selection_start: int,
	selection_end:   int,
	local_counter: int,
	identity_key: string,
	identity_key_u64: u64,
	identity_key_numeric: bool,
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
	layout_updates:    u64,
	paint_updates:     u64,
	composite_updates:  u64,
	adjacency_rebuilds: u64,
	pointer_events:    u64,
	gpu_submits:       u64,
}

Runtime :: struct {
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
	frame_open:  bool,
	hard_error:  bool,
	diagnostic:  string,
	last_invalidation_reason: string,
	stats:       Frame_Stats,
	trace:       Trace_Ring,
	display:     [dynamic]Display_Command,
	text_engine: Text_Engine,
	text_font_generation_seen: u64,
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

new_runtime :: proc(viewport: Rect, trace_capacity := 256) -> Runtime {
	capacity := trace_capacity
	if capacity < 1 { capacity = 1 }
	rt := Runtime{
		nodes = make(map[Node_ID]^Node),
		order = make([dynamic]Node_ID, 0),
		top_level = make([dynamic]Node_ID, 0),
		pending = make([dynamic]Pending_Item, 0),
		seen = make(map[Node_ID]bool),
		identity_scopes = make(map[Node_ID]bool),
		stack = make([dynamic]Node_ID, 0),
		identity_stack = make([dynamic]Node_ID, 0),
		identity_labels = make([dynamic]string, 0),
		identity_key_u64 = make([dynamic]u64, 0),
		identity_key_numeric = make([dynamic]bool, 0),
		paint_queue = make([dynamic]Node_ID, 0),
		viewport = viewport,
		invalidated = true,
		trace = Trace_Ring{events = make([dynamic]Trace_Event, capacity)},
		text_engine = new_text_engine("runtime text", false),
	}
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

owned :: proc(value: string) -> string {
	if value == "" {
		return ""
	}
	copy, _ := strings.clone(value)
	return copy
}

record_trace :: proc(rt: ^Runtime, kind: Trace_Kind, node: Node_ID, reason: string) {
	rt.trace.sequence += 1
	entry := Trace_Event{rt.trace.sequence, kind, node, owned(reason)}
	old := &rt.trace.events[rt.trace.next]
	if len(old.reason) > 0 { delete(old.reason) }
	rt.trace.events[rt.trace.next] = entry
	rt.trace.next = (rt.trace.next + 1) % len(rt.trace.events)
	if rt.trace.count < len(rt.trace.events) {
		rt.trace.count += 1
	}
}

invalidate_root :: proc(rt: ^Runtime, reason := "explicit root invalidation") {
	rt.invalidated = true
	if len(rt.last_invalidation_reason) > 0 { delete(rt.last_invalidation_reason) }
	rt.last_invalidation_reason = owned(reason)
	record_trace(rt, .Invalidation, 0, reason)
}

invalidate_region :: proc(rt: ^Runtime, key: string, revision: u64, reason := "explicit region invalidation") {
	// Region revisions are carried by the next description. The key is included
	// in the trace so the invalidation remains structurally inspectable.
	rt.invalidated = true
	if len(rt.last_invalidation_reason) > 0 { delete(rt.last_invalidation_reason) }
	rt.last_invalidation_reason = owned(fmt.tprintf("region %s revision %d: %s", key, revision, reason))
	record_trace(rt, .Invalidation, 0, rt.last_invalidation_reason)
}

begin_frame :: proc(rt: ^Runtime) -> (ui: UI, should_build: bool) {
	ui = UI{runtime = rt}
	if !rt.invalidated {
		rt.stats.idle_frames += 1
		return ui, false
	}
	rt.frame_open = true
	clear(&rt.pending)
	clear(&rt.seen)
	clear(&rt.identity_scopes)
	clear(&rt.stack)
	clear(&rt.identity_stack)
	clear(&rt.identity_labels)
	clear(&rt.identity_key_u64)
	clear(&rt.identity_key_numeric)
	clear(&rt.paint_queue)
	rt.stats.frames_built += 1
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

append_diagnostic :: proc(rt: ^Runtime, message: string) {
	rt.hard_error = true
	rt.diagnostic = owned(message)
	record_trace(rt, .Reconcile, 0, message)
}

emit :: proc(ui: ^UI, kind: Node_Kind, source: Source_Site, label := "", text := "", key := "", explicit_key := false, style := DEFAULT_STYLE, color := DEFAULT_COLOR, paint_value: u64 = 0, region_revision: u64 = 0, is_region := false, focusable := false) -> Node_ID {
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
	description := Description{id, parent_node, source, key, explicit_key, kind, label, text, style, color, paint_value, region_revision, is_region, focusable, identity_key, identity_key_u64, identity_key_numeric}
	append(&rt.pending, Pending_Item{.Description, description, 0})
	rt.stats.descriptions_emitted += 1
	return id
}

key_scope :: proc(ui: ^UI, key: string, source: Source_Site, body: proc()) {
	if !key_scope_begin(ui, key, source) { return }
	body()
	key_scope_end(ui)
}

key_scope_begin :: proc(ui: ^UI, key: string, source := Source_Site{}, loc := #caller_location) -> bool {
	rt := ui.runtime
	resolved_source := resolve_source(source, "key_scope", loc)
	parent := current_identity_parent(ui)
	id := identity_hash(parent, resolved_source, key, true)
	if rt.identity_scopes[id] {
		append_diagnostic(rt, fmt.tprintf("duplicate key scope at %s:%d:%d component=%s key=%q", resolved_source.file, resolved_source.line, resolved_source.column, resolved_source.component, key))
		return false
	}
	rt.identity_scopes[id] = true
	append(&rt.identity_stack, id)
	append(&rt.identity_labels, key)
	append(&rt.identity_key_u64, 0)
	append(&rt.identity_key_numeric, false)
	return true
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
	append(&rt.identity_stack, id)
	append(&rt.identity_labels, "")
	append(&rt.identity_key_u64, key)
	append(&rt.identity_key_numeric, true)
	return true
}

// component_begin creates an invocation scope from the actual application
// call site. It is the ergonomic boundary for reusable helpers that need
// distinct identity even when their widget call sites are shared.
component_begin :: proc(ui: ^UI, key: string, loc := #caller_location) -> bool {
	return key_scope_begin(ui, key, resolve_source(Source_Site{}, "component", loc))
}

component_end :: proc(ui: ^UI) {
	key_scope_end(ui)
}

key_scope_end :: proc(ui: ^UI) {
	if len(ui.runtime.identity_stack) > 0 { pop(&ui.runtime.identity_stack) }
	if len(ui.runtime.identity_labels) > 0 { pop(&ui.runtime.identity_labels) }
	if len(ui.runtime.identity_key_u64) > 0 { pop(&ui.runtime.identity_key_u64) }
	if len(ui.runtime.identity_key_numeric) > 0 { pop(&ui.runtime.identity_key_numeric) }
}

container_begin :: proc(ui: ^UI, kind: Node_Kind, source := Source_Site{}, label := "", key := "", explicit_key := false, style := DEFAULT_STYLE, color := DEFAULT_COLOR, paint_value: u64 = 0, focusable := false, loc := #caller_location) -> Node_ID {
	resolved_source := resolve_source(source, "container", loc)
	id := emit(ui, kind, resolved_source, label=label, key=key, explicit_key=explicit_key, style=style, color=color, paint_value=paint_value, focusable=focusable)
	if id != 0 {
		append(&ui.runtime.stack, id)
		append(&ui.runtime.identity_stack, id)
		append(&ui.runtime.identity_labels, "")
		append(&ui.runtime.identity_key_u64, 0)
		append(&ui.runtime.identity_key_numeric, false)
	}
	return id
}

container_end :: proc(ui: ^UI) {
	if len(ui.runtime.stack) > 0 { pop(&ui.runtime.stack) }
	if len(ui.runtime.identity_stack) > 0 { pop(&ui.runtime.identity_stack) }
	if len(ui.runtime.identity_labels) > 0 { pop(&ui.runtime.identity_labels) }
	if len(ui.runtime.identity_key_u64) > 0 { pop(&ui.runtime.identity_key_u64) }
	if len(ui.runtime.identity_key_numeric) > 0 { pop(&ui.runtime.identity_key_numeric) }
}

// A structural wrapper can be made identity-transparent when a caller wants a
// keyed item's descendants to survive that wrapper being introduced or
// removed. The retained hierarchy still records the wrapper for layout.
transparent_container_begin :: proc(ui: ^UI, kind: Node_Kind, source := Source_Site{}, label := "", key := "", explicit_key := false, style := DEFAULT_STYLE, color := DEFAULT_COLOR, paint_value: u64 = 0, focusable := false, loc := #caller_location) -> Node_ID {
	resolved_source := resolve_source(source, "container", loc)
	id := emit(ui, kind, resolved_source, label=label, key=key, explicit_key=explicit_key, style=style, color=color, paint_value=paint_value, focusable=focusable)
	if id != 0 { append(&ui.runtime.stack, id) }
	return id
}

transparent_container_end :: proc(ui: ^UI) {
	if len(ui.runtime.stack) > 0 { pop(&ui.runtime.stack) }
}

container :: proc(ui: ^UI, kind: Node_Kind, source := Source_Site{}, body: proc(), label := "", key := "", explicit_key := false, style := DEFAULT_STYLE, color := DEFAULT_COLOR, paint_value: u64 = 0, focusable := false, loc := #caller_location) -> Node_ID {
	resolved_source := resolve_source(source, "container", loc)
	id := container_begin(ui, kind, resolved_source, label, key, explicit_key, style, color, paint_value, focusable)
	if id == 0 { return 0 }
	body()
	container_end(ui)
	return id
}

root :: proc(ui: ^UI, source := Source_Site{}, body: proc(), style := DEFAULT_STYLE, loc := #caller_location) -> Node_ID {
	resolved_source := resolve_source(source, "root", loc)
	return container(ui, .Root, resolved_source, body, label="root", style=style)
}

button :: proc(ui: ^UI, label: string, source := Source_Site{}, key := "", explicit_key := false, style := DEFAULT_STYLE, paint_value: u64 = 0, loc := #caller_location) -> (id: Node_ID, clicked: bool) {
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

text :: proc(ui: ^UI, value: string, source := Source_Site{}, key := "", explicit_key := false, style := DEFAULT_STYLE, paint_value: u64 = 0, loc := #caller_location) -> Node_ID {
	resolved_source := resolve_source(source, "text", loc)
	return emit(ui, .Text, resolved_source, text=value, key=key, explicit_key=explicit_key, style=style, paint_value=paint_value)
}

text_field :: proc(ui: ^UI, value: string, source := Source_Site{}, key := "", explicit_key := false, style := DEFAULT_STYLE, loc := #caller_location) -> Node_ID {
	resolved_source := resolve_source(source, "text_field", loc)
	return emit(ui, .Text_Field, resolved_source, text=value, key=key, explicit_key=explicit_key, style=style, focusable=true)
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
	append(&rt.identity_stack, id)
	append(&rt.identity_labels, "")
	append(&rt.identity_key_u64, 0)
	append(&rt.identity_key_numeric, false)
	return id, false
}

region_end :: proc(ui: ^UI, id: Node_ID, reused: bool, start: int) {
	if reused || id == 0 { return }
	pop(&ui.runtime.stack)
	pop(&ui.runtime.identity_stack)
	pop(&ui.runtime.identity_labels)
	pop(&ui.runtime.identity_key_u64)
	pop(&ui.runtime.identity_key_numeric)
}

region :: proc(ui: ^UI, key: string, revision: u64, source := Source_Site{}, body: proc(), style := DEFAULT_STYLE, loc := #caller_location) -> Node_ID {
	resolved_source := resolve_source(source, "region", loc)
	id, reused := region_begin(ui, key, revision, resolved_source, style)
	if !reused && id != 0 {
		start := len(ui.runtime.pending)
		body()
		region_end(ui, id, false, start)
	}
	return id
}

// virtual_list requires a logical item key. Viewport position is not identity:
// callers must return the same key for an item when it moves in the source data.
// The fixed-height proof currently returns a visible range and does not apply
// fractional pixel offset to row geometry; callers should treat that as an
// explicit limitation until scroll anchoring is added.
virtual_list :: proc(ui: ^UI, item_count: int, scroll_y, viewport_height, row_height: f32, source: Source_Site, item_key: proc(index: int) -> string, row: proc(ui: ^UI, index: int)) -> (first, last: int) {
	if item_count <= 0 || row_height <= 0 || viewport_height <= 0 {
		return 0, 0
	}
	first = int(scroll_y / row_height)
	if first < 0 { first = 0 }
	if first >= item_count { first = item_count - 1 }
	last = int((scroll_y + viewport_height) / row_height) + 1
	if last > item_count { last = item_count }
	container_begin(ui, .Virtual_List, source, label="virtual-list", style=Layout_Style{.Column, -1, -1, 0, -1, 0, -1, 0, 0, 0, .Stretch, true})
	for i := first; i < last; i += 1 {
		if key_scope_begin(ui, item_key(i), source) {
			row(ui, i)
			key_scope_end(ui)
		}
	}
	container_end(ui)
	return
}

custom_surface :: proc(ui: ^UI, surface_key: string, frame: u64, logical_bounds: Rect, pixel_width, pixel_height: int, dpi_scale: f32, source := Source_Site{}, loc := #caller_location) -> Node_ID {
	resolved_source := resolve_source(source, "custom_surface", loc)
	style := DEFAULT_STYLE
	style.width = logical_bounds.w
	style.height = logical_bounds.h
	return emit(ui, .Custom_Surface, resolved_source, label=surface_key, key=surface_key, explicit_key=true, style=style, paint_value=frame, color=Color{0.15, 0.25, 0.42, 1})
}
