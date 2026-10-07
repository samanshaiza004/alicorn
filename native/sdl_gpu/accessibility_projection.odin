package alicorn_sdl_gpu

import "core:mem"
import "core:strings"
import alicorn "../../runtime"

// This is a backend-neutral projection format. The native AccessKit adapter
// can translate these records to AccessKit nodes without making AccessKit's
// retained tree Alicorn's semantic source of truth.
Accessibility_Projection_Role :: enum {
	Window,
	Group,
	Static_Text,
	Button,
	Check_Box,
	Slider,
	Text_Input,
	Text_Area,
	Text_Run,
	Tab_List,
	Tab,
	List,
	List_Item,
	Tree,
	Tree_Item,
	Menu,
	Menu_Item,
	Dialog,
	Tooltip,
	Scroll_View,
	Generic_Container,
}

Accessibility_Projection_State :: enum {
	Disabled,
	Selected,
	Checked,
	Expanded,
	Read_Only,
	Required,
	Invalid,
	Busy,
	Modified,
	Current,
}

Accessibility_Projection_States :: distinct bit_set[Accessibility_Projection_State; u32]

Accessibility_Projection_Action :: enum {
	Press,
	Focus,
	Set_Value,
	Set_Text_Selection,
	Replace_Selected_Text,
	Increment,
	Decrement,
	Select,
	Expand,
	Collapse,
	Scroll_Into_View,
	Scroll_Forward,
	Scroll_Backward,
	Dismiss,
}

Accessibility_Projection_Actions :: distinct bit_set[Accessibility_Projection_Action; u32]

Accessibility_Projection_Text_Position :: struct {
	node_id: u64,
	character_index: u64,
}

Accessibility_Projection_Text_Selection :: struct {
	anchor: Accessibility_Projection_Text_Position,
	focus: Accessibility_Projection_Text_Position,
	valid: bool,
}

Accessibility_Projection_Node :: struct {
	// id is the stable AccessKit-sized ID; semantic_id is its full reverse key.
	id: u64,
	semantic_id: alicorn.Semantic_ID,
	semantic_parent: alicorn.Semantic_ID,
	role: Accessibility_Projection_Role,
	label: string,
	description: string,
	value: string,
	text_run_character_lengths: []u8,
	text_selection: Accessibility_Projection_Text_Selection,
	authored_states: alicorn.Semantic_States,
	states: Accessibility_Projection_States,
	actions: Accessibility_Projection_Actions,
	bounds: alicorn.Rect,
	has_bounds: bool,
	is_collection: bool,
	logical_count: u64,
	position_in_set: u64,
	size_of_set: u64,
	selected_item_id: u64,
	current_item_id: u64,
	numeric_value: f64,
	numeric_minimum: f64,
	numeric_maximum: f64,
	numeric_step: f64,
	has_numeric_value: bool,
	tree_order: u64,
	// Children are platform IDs, in deterministic semantic tree order.
	children: [dynamic]u64,
}

Accessibility_Projection :: struct {
	revision: u64,
	keyboard_focus: u64,
	keyboard_focus_semantic_id: alicorn.Semantic_ID,
	root_id: u64,
	// Enumerable node set, synthetic root first. Node strings/children are
	// owned by this projection until it is updated or destroyed.
	nodes: [dynamic]Accessibility_Projection_Node,
	allocator: mem.Allocator,
}

Accessibility_Projection_Status :: enum {
	Success,
	Invalid_Semantic_ID,
	Duplicate_Semantic_ID,
	ID_Collision,
	Invalid_Text_Model,
	Allocation_Failed,
}

Accessibility_Projection_Delta :: struct {
	from_revision: u64,
	to_revision: u64,
	keyboard_focus: u64,
	changed_nodes: [dynamic]Accessibility_Projection_Node,
	removed_ids: [dynamic]u64,
	requires_snapshot: bool,
	allocator: mem.Allocator,
}

Accessibility_Projection_Apply_Result :: enum {
	Applied,
	Requires_Snapshot,
}

ACCESSIBILITY_PROJECTION_ROOT_ID :: u64(0xA11C_0A11_C0A11C01)

@(private)
Accessibility_Projection_ID_Hash :: proc(id: alicorn.Semantic_ID) -> u64

// accessibility_semantic_to_node_id maps the complete stable Alicorn
// identity to a deterministic platform-sized ID. Callers must still check
// collisions against the other IDs in the current projection.
accessibility_semantic_to_node_id :: proc(id: alicorn.Semantic_ID) -> (node_id: u64, ok: bool) {
	if id == (alicorn.Semantic_ID{}) { return 0, false }
	node_id = accessibility_semantic_id_hash(id)
	if node_id == 0 || node_id == ACCESSIBILITY_PROJECTION_ROOT_ID { return 0, false }
	return node_id, true
}

@(private)
accessibility_semantic_id_hash :: proc(id: alicorn.Semantic_ID) -> u64 {
	// SplitMix64 finalization on both halves. This consumes the complete
	// application identity and is stable across processes and architectures.
	h := id.namespace + 0x9E37_79B9_7F4A_7C15
	h = (h ~ (h >> 30)) * 0xBF58_476D_1CE4_E5B9
	h = (h ~ (h >> 27)) * 0x94D0_49BB_1331_11EB
	h = h ~ (h >> 31)
	h = h ~ (id.value + 0xD6E8_FEB8_6659_FD93)
	h = (h ~ (h >> 30)) * 0xBF58_476D_1CE4_E5B9
	h = (h ~ (h >> 27)) * 0x94D0_49BB_1331_11EB
	h = h ~ (h >> 31)
	if h == 0 { h = 1 }
	return h
}

// Build a complete deterministic projection from the semantic working set.
// The snapshot's node count bounds the output; logical collection size does
// not cause additional item materialization.
accessibility_projection_from_snapshot :: proc(
	snapshot: alicorn.Semantic_Snapshot,
	allocator := context.allocator,
) -> (projection: Accessibility_Projection, status: Accessibility_Projection_Status) {
	return accessibility_projection_from_snapshot_with_hash(snapshot, allocator, accessibility_semantic_id_hash)
}

@(private)
accessibility_projection_from_snapshot_with_hash :: proc(
	snapshot: alicorn.Semantic_Snapshot,
	allocator: mem.Allocator,
	hash_id: Accessibility_Projection_ID_Hash,
) -> (projection: Accessibility_Projection, status: Accessibility_Projection_Status) {
	previous_allocator := context.allocator
	context.allocator = allocator
	defer context.allocator = previous_allocator
	projection = Accessibility_Projection{
		revision=snapshot.revision,
		keyboard_focus_semantic_id=snapshot.keyboard_focus,
		root_id=ACCESSIBILITY_PROJECTION_ROOT_ID,
		allocator=allocator,
		nodes=make([dynamic]Accessibility_Projection_Node, 0, len(snapshot.nodes)+1, allocator=allocator),
	}
	root := Accessibility_Projection_Node{
		id=ACCESSIBILITY_PROJECTION_ROOT_ID,
		role=.Window,
		children=make([dynamic]u64, 0, allocator=allocator),
	}
	root_label, root_label_error := strings.clone("Alicorn", allocator)
	if root_label_error != nil {
		accessibility_projection_destroy(&projection)
		return {}, .Allocation_Failed
	}
	root.label = root_label
	append(&projection.nodes, root)

	semantic_indices := make(map[alicorn.Semantic_ID]int, allocator=allocator)
	defer delete(semantic_indices)
	platform_ids := make(map[u64]alicorn.Semantic_ID, allocator=allocator)
	defer delete(platform_ids)
	platform_ids[ACCESSIBILITY_PROJECTION_ROOT_ID] = {}
	for source, source_index in snapshot.nodes {
		if source.id == (alicorn.Semantic_ID{}) {
			accessibility_projection_destroy(&projection)
			return {}, .Invalid_Semantic_ID
		}
		if _, exists := semantic_indices[source.id]; exists {
			accessibility_projection_destroy(&projection)
			return {}, .Duplicate_Semantic_ID
		}
		platform_id := hash_id(source.id)
		if platform_id == 0 { platform_id = 1 }
		if platform_id == ACCESSIBILITY_PROJECTION_ROOT_ID {
			accessibility_projection_destroy(&projection)
			return {}, .ID_Collision
		}
		if previous, exists := platform_ids[platform_id]; exists {
			_ = previous
			accessibility_projection_destroy(&projection)
			return {}, .ID_Collision
		}
		projected, ok := accessibility_projection_node_from_semantic(source, platform_id, allocator)
		if !ok {
			accessibility_projection_destroy(&projection)
			return {}, .Allocation_Failed
		}
		semantic_indices[source.id] = source_index + 1
		platform_ids[platform_id] = source.id
		append(&projection.nodes, projected)
	}

	accessibility_projection_sort_semantic_nodes(&projection)
	clear(&semantic_indices)
	for index := 1; index < len(projection.nodes); index += 1 {
		semantic_indices[projection.nodes[index].semantic_id] = index
	}
	accessibility_projection_apply_collection_selection(&projection, snapshot, semantic_indices)
	if !accessibility_projection_apply_text_selections(&projection, snapshot, semantic_indices) {
		accessibility_projection_destroy(&projection)
		return {}, .Invalid_Text_Model
	}
	if !accessibility_projection_rebuild_structure(&projection) {
		accessibility_projection_destroy(&projection)
		return {}, .ID_Collision
	}
	if focus_index, found := semantic_indices[snapshot.keyboard_focus]; found && snapshot.keyboard_focus != (alicorn.Semantic_ID{}) {
		projection.keyboard_focus = projection.nodes[focus_index].id
	} else {
		projection.keyboard_focus = projection.root_id
	}
	return projection, .Success
}

@(private)
accessibility_projection_node_from_semantic :: proc(
	source: alicorn.Semantic_Node,
	platform_id: u64,
	allocator: mem.Allocator,
) -> (node: Accessibility_Projection_Node, ok: bool) {
	previous_allocator := context.allocator
	context.allocator = allocator
	defer context.allocator = previous_allocator
	node = Accessibility_Projection_Node{
		id=platform_id,
		semantic_id=source.id,
		semantic_parent=source.parent,
		role=accessibility_projection_role(source.role),
		authored_states=source.states,
		bounds=source.bounds,
		has_bounds=source.has_bounds,
		is_collection=source.is_collection,
		logical_count=source.logical_count,
		position_in_set=source.position_in_set,
		size_of_set=source.size_of_set,
		numeric_value=source.numeric_value,
		numeric_minimum=source.numeric_minimum,
		numeric_maximum=source.numeric_maximum,
		numeric_step=source.numeric_step,
		has_numeric_value=source.has_numeric_value,
		tree_order=source.tree_order,
		children=make([dynamic]u64, 0, allocator=allocator),
	}
	if source.is_collection { node.size_of_set = source.logical_count }
	if !source.is_collection && source.size_of_set > 0 { node.position_in_set += 1 }
	node.states = accessibility_projection_states(source.states)
	node.actions = accessibility_projection_actions(source.actions)
	if len(source.label) > 0 {
		value, err := strings.clone(source.label, allocator)
		if err != nil { accessibility_projection_destroy_node(&node, allocator); return {}, false }
		node.label = value
	}
	if len(source.description) > 0 {
		value, err := strings.clone(source.description, allocator)
		if err != nil { accessibility_projection_destroy_node(&node, allocator); return {}, false }
		node.description = value
	}
	if len(source.value) > 0 {
		value, err := strings.clone(source.value, allocator)
		if err != nil { accessibility_projection_destroy_node(&node, allocator); return {}, false }
		node.value = value
	}
	if len(source.text_run_character_lengths) > 0 {
		node.text_run_character_lengths = make([]u8, len(source.text_run_character_lengths), allocator=allocator)
		if node.text_run_character_lengths == nil { accessibility_projection_destroy_node(&node, allocator); return {}, false }
		copy(node.text_run_character_lengths, source.text_run_character_lengths)
	}
	return node, true
}

@(private)
accessibility_projection_role :: proc(role: alicorn.Semantic_Role) -> Accessibility_Projection_Role {
	switch role {
	case .Window: return .Window
	case .Group: return .Group
	case .Static_Text: return .Static_Text
	case .Button: return .Button
	case .Checkbox: return .Check_Box
	case .Slider: return .Slider
	case .Text_Field: return .Text_Input
	case .Text_Area: return .Text_Area
	case .Text_Run: return .Text_Run
	case .Tab_List: return .Tab_List
	case .Tab: return .Tab
	case .List: return .List
	case .List_Item: return .List_Item
	case .Tree: return .Tree
	case .Tree_Item: return .Tree_Item
	case .Menu: return .Menu
	case .Menu_Item: return .Menu_Item
	case .Dialog: return .Dialog
	case .Tooltip: return .Tooltip
	case .Scroll_View: return .Scroll_View
	case .None: return .Generic_Container
	}
	return .Generic_Container
}

@(private)
accessibility_projection_states :: proc(source: alicorn.Semantic_States) -> Accessibility_Projection_States {
	bits := transmute(bit_set[alicorn.Semantic_State; u32])source
	result := Accessibility_Projection_States{}
	if alicorn.Semantic_State.Disabled in bits { result += {.Disabled} }
	if alicorn.Semantic_State.Selected in bits { result += {.Selected} }
	if alicorn.Semantic_State.Checked in bits { result += {.Checked} }
	if alicorn.Semantic_State.Expanded in bits { result += {.Expanded} }
	if alicorn.Semantic_State.Read_Only in bits { result += {.Read_Only} }
	if alicorn.Semantic_State.Required in bits { result += {.Required} }
	if alicorn.Semantic_State.Invalid in bits { result += {.Invalid} }
	if alicorn.Semantic_State.Busy in bits { result += {.Busy} }
	if alicorn.Semantic_State.Modified in bits { result += {.Modified} }
	if alicorn.Semantic_State.Current in bits { result += {.Current} }
	return result
}

@(private)
accessibility_projection_actions :: proc(source: alicorn.Semantic_Actions) -> Accessibility_Projection_Actions {
	bits := transmute(bit_set[alicorn.Semantic_Action; u32])source
	result := Accessibility_Projection_Actions{}
	if alicorn.Semantic_Action.Press in bits { result += {.Press} }
	if alicorn.Semantic_Action.Focus in bits { result += {.Focus} }
	if alicorn.Semantic_Action.Set_Value in bits { result += {.Set_Value} }
	if alicorn.Semantic_Action.Set_Text_Selection in bits { result += {.Set_Text_Selection} }
	if alicorn.Semantic_Action.Replace_Selected_Text in bits { result += {.Replace_Selected_Text} }
	if alicorn.Semantic_Action.Increment in bits { result += {.Increment} }
	if alicorn.Semantic_Action.Decrement in bits { result += {.Decrement} }
	if alicorn.Semantic_Action.Select in bits { result += {.Select} }
	if alicorn.Semantic_Action.Expand in bits { result += {.Expand} }
	if alicorn.Semantic_Action.Collapse in bits { result += {.Collapse} }
	if alicorn.Semantic_Action.Scroll_Into_View in bits { result += {.Scroll_Into_View} }
	if alicorn.Semantic_Action.Scroll_Forward in bits { result += {.Scroll_Forward} }
	if alicorn.Semantic_Action.Scroll_Backward in bits { result += {.Scroll_Backward} }
	if alicorn.Semantic_Action.Dismiss in bits { result += {.Dismiss} }
	return result
}

@(private)
accessibility_projection_apply_text_selections :: proc(
	projection: ^Accessibility_Projection,
	snapshot: alicorn.Semantic_Snapshot,
	semantic_indices: map[alicorn.Semantic_ID]int,
) -> bool {
	if projection == nil { return false }
	for &node in projection.nodes { node.text_selection = {} }
	for semantic in snapshot.nodes {
		if semantic.role != .Text_Area || !semantic.text_selection.valid { continue }
		area_index, area_found := semantic_indices[semantic.id]
		anchor_index, anchor_found := semantic_indices[semantic.text_selection.anchor.run_id]
		focus_index, focus_found := semantic_indices[semantic.text_selection.focus.run_id]
		if !area_found || !anchor_found || !focus_found { return false }
		area := projection.nodes[area_index]
		anchor := projection.nodes[anchor_index]
		focus := projection.nodes[focus_index]
		if area.role != .Text_Area || anchor.role != .Text_Run || focus.role != .Text_Run ||
		   anchor.semantic_parent != semantic.id || focus.semantic_parent != semantic.id ||
		   semantic.text_selection.anchor.character_index > u64(len(anchor.text_run_character_lengths)) ||
		   semantic.text_selection.focus.character_index > u64(len(focus.text_run_character_lengths)) { return false }
		projection.nodes[area_index].text_selection = Accessibility_Projection_Text_Selection{
			anchor={anchor.id, semantic.text_selection.anchor.character_index},
			focus={focus.id, semantic.text_selection.focus.character_index},
			valid=true,
		}
	}
	return true
}

// These predicates let a platform adapter translate flags without depending
// on this module's internal bitset representation.
accessibility_projection_action_has :: proc(actions: Accessibility_Projection_Actions, action: Accessibility_Projection_Action) -> bool {
	return action in transmute(bit_set[Accessibility_Projection_Action; u32])actions
}

accessibility_projection_state_has :: proc(states: Accessibility_Projection_States, state: Accessibility_Projection_State) -> bool {
	return state in transmute(bit_set[Accessibility_Projection_State; u32])states
}

@(private)
accessibility_projection_apply_collection_selection :: proc(
	projection: ^Accessibility_Projection,
	snapshot: alicorn.Semantic_Snapshot,
	semantic_indices: map[alicorn.Semantic_ID]int,
) {
	for &node in projection.nodes {
		node.states = accessibility_projection_states(node.authored_states)
		node.selected_item_id = 0
		node.current_item_id = 0
	}
	for collection in snapshot.nodes {
		if !collection.is_collection { continue }
		collection_index, collection_found := semantic_indices[collection.id]
		if !collection_found { continue }
		if collection.selected_id != (alicorn.Semantic_ID{}) {
			if item_index, found := semantic_indices[collection.selected_id]; found {
				item := &projection.nodes[item_index]
				if item.semantic_parent == collection.id { item.states += {.Selected} }
				projection.nodes[collection_index].selected_item_id = item.id
			}
		}
		if collection.current_id != (alicorn.Semantic_ID{}) {
			if item_index, found := semantic_indices[collection.current_id]; found {
				item := &projection.nodes[item_index]
				if item.semantic_parent == collection.id { item.states += {.Current} }
				projection.nodes[collection_index].current_item_id = item.id
			}
		}
	}
}

@(private)
accessibility_projection_rebuild_structure :: proc(projection: ^Accessibility_Projection) -> bool {
	if projection == nil || len(projection.nodes) == 0 || projection.nodes[0].id != projection.root_id { return false }
	previous_allocator := context.allocator
	context.allocator = projection.allocator
	defer context.allocator = previous_allocator
	semantic_indices := make(map[alicorn.Semantic_ID]int, allocator=projection.allocator)
	defer delete(semantic_indices)
	platform_indices := make(map[u64]int, allocator=projection.allocator)
	defer delete(platform_indices)
	platform_indices[projection.root_id] = 0
	for index in 1..<len(projection.nodes) {
		node := projection.nodes[index]
		if node.semantic_id == (alicorn.Semantic_ID{}) || node.id == projection.root_id { return false }
		if _, exists := semantic_indices[node.semantic_id]; exists { return false }
		if _, exists := platform_indices[node.id]; exists { return false }
		semantic_indices[node.semantic_id] = index
		platform_indices[node.id] = index
	}

	parents := make([]int, len(projection.nodes), allocator=projection.allocator)
	colors := make([]u8, len(projection.nodes), allocator=projection.allocator)
	defer delete(parents, projection.allocator)
	defer delete(colors, projection.allocator)
	for index := 1; index < len(projection.nodes); index += 1 {
		parents[index] = 0
		if projection.nodes[index].semantic_parent == (alicorn.Semantic_ID{}) { continue }
		if parent_index, found := semantic_indices[projection.nodes[index].semantic_parent]; found && parent_index != index {
			parents[index] = parent_index
		}
	}
	stack := make([dynamic]int, 0, len(projection.nodes), allocator=projection.allocator)
	defer delete(stack)
	for start := 1; start < len(projection.nodes); start += 1 {
		if colors[start] != 0 { continue }
		clear(&stack)
		current := start
		for current > 0 && colors[current] == 0 {
			colors[current] = 1
			append(&stack, current)
			current = parents[current]
		}
		if current > 0 && colors[current] == 1 {
			cycle_start := -1
		for candidate, stack_index in stack {
				if candidate == current { cycle_start = stack_index; break }
			}
			if cycle_start < 0 { return false }
			cut := stack[cycle_start]
			for candidate in stack[cycle_start+1:] {
				if accessibility_semantic_id_less(projection.nodes[candidate].semantic_id, projection.nodes[cut].semantic_id) { cut = candidate }
			}
			parents[cut] = 0
		}
		for candidate in stack { colors[candidate] = 2 }
	}

	for &node in projection.nodes {
		if len(node.children) > 0 { delete(node.children) }
		node.children = make([dynamic]u64, 0, allocator=projection.allocator)
	}
	for index := 1; index < len(projection.nodes); index += 1 {
		parent_index := parents[index]
		append(&projection.nodes[parent_index].children, projection.nodes[index].id)
	}
	return true
}

@(private)
accessibility_semantic_id_less :: proc(a, b: alicorn.Semantic_ID) -> bool {
	if a.namespace != b.namespace { return a.namespace < b.namespace }
	return a.value < b.value
}

@(private)
accessibility_projection_destroy_node :: proc(node: ^Accessibility_Projection_Node, allocator: mem.Allocator) {
	if node == nil { return }
	previous_allocator := context.allocator
	context.allocator = allocator
	defer context.allocator = previous_allocator
	if len(node.label) > 0 { delete(node.label, allocator) }
	if len(node.description) > 0 { delete(node.description, allocator) }
	if len(node.value) > 0 { delete(node.value, allocator) }
	if len(node.text_run_character_lengths) > 0 { delete(node.text_run_character_lengths, allocator) }
	if len(node.children) > 0 { delete(node.children) }
	node^ = {}
}

accessibility_projection_destroy :: proc(projection: ^Accessibility_Projection) {
	if projection == nil { return }
	previous_allocator := context.allocator
	context.allocator = projection.allocator
	defer context.allocator = previous_allocator
	for &node in projection.nodes { accessibility_projection_destroy_node(&node, projection.allocator) }
	if len(projection.nodes) > 0 { delete(projection.nodes) }
	projection^ = {}
}

accessibility_projection_delta_destroy :: proc(delta: ^Accessibility_Projection_Delta) {
	if delta == nil { return }
	previous_allocator := context.allocator
	context.allocator = delta.allocator
	defer context.allocator = previous_allocator
	for &node in delta.changed_nodes { accessibility_projection_destroy_node(&node, delta.allocator) }
	if len(delta.changed_nodes) > 0 { delete(delta.changed_nodes) }
	if len(delta.removed_ids) > 0 { delete(delta.removed_ids) }
	delta^ = {}
}

// Apply only an exact-base semantic transition. On Requires_Snapshot, current
// remains unchanged and delta.requires_snapshot is true. changed_nodes also
// contains any retained parent whose ordered child list changed.
accessibility_projection_apply_update :: proc(
	projection: ^Accessibility_Projection,
	update: alicorn.Semantic_Update_View,
	snapshot: alicorn.Semantic_Snapshot,
	allocator := context.allocator,
) -> (delta: Accessibility_Projection_Delta, result: Accessibility_Projection_Apply_Result) {
	previous_allocator := context.allocator
	context.allocator = allocator
	defer context.allocator = previous_allocator
	delta = Accessibility_Projection_Delta{
		from_revision=update.from_revision,
		to_revision=update.to_revision,
		allocator=allocator,
		changed_nodes=make([dynamic]Accessibility_Projection_Node, 0, allocator=allocator),
		removed_ids=make([dynamic]u64, 0, allocator=allocator),
	}
	if projection == nil || update.requires_snapshot || update.from_revision != projection.revision ||
	   update.to_revision != snapshot.revision || update.to_revision < update.from_revision ||
	   update.keyboard_focus != snapshot.keyboard_focus ||
	   (update.to_revision == update.from_revision && (len(update.changed_ids) > 0 || len(update.removed_ids) > 0)) {
		delta.requires_snapshot = true
		return delta, .Requires_Snapshot
	}
	if update.to_revision == update.from_revision {
		if snapshot.keyboard_focus != projection.keyboard_focus_semantic_id {
			delta.requires_snapshot = true
			return delta, .Requires_Snapshot
		}
		delta.keyboard_focus = projection.keyboard_focus
		return delta, .Applied
	}
	working, cloned := accessibility_projection_clone(projection^, allocator)
	if !cloned { delta.requires_snapshot = true; return delta, .Requires_Snapshot }
	old := projection^
	changed_semantics := make(map[alicorn.Semantic_ID]bool, allocator=allocator)
	defer delete(changed_semantics)
	removed_semantics := make(map[alicorn.Semantic_ID]bool, allocator=allocator)
	defer delete(removed_semantics)

	for semantic_id in update.removed_ids {
		if semantic_id == (alicorn.Semantic_ID{}) || removed_semantics[semantic_id] || changed_semantics[semantic_id] {
			accessibility_projection_destroy(&working)
			accessibility_projection_delta_destroy(&delta)
			return accessibility_projection_requires_snapshot(update, allocator), .Requires_Snapshot
		}
		index := accessibility_projection_find_semantic(working, semantic_id)
		if index <= 0 {
			accessibility_projection_destroy(&working)
			accessibility_projection_delta_destroy(&delta)
			return accessibility_projection_requires_snapshot(update, allocator), .Requires_Snapshot
		}
		platform_id := working.nodes[index].id
		accessibility_projection_destroy_node(&working.nodes[index], allocator)
		ordered_remove(&working.nodes, index)
		removed_semantics[semantic_id] = true
		append(&delta.removed_ids, platform_id)
	}

	for semantic_id in update.changed_ids {
		if semantic_id == (alicorn.Semantic_ID{}) || changed_semantics[semantic_id] || removed_semantics[semantic_id] {
			accessibility_projection_destroy(&working)
			accessibility_projection_delta_destroy(&delta)
			return accessibility_projection_requires_snapshot(update, allocator), .Requires_Snapshot
		}
		source, found := accessibility_snapshot_find_node(snapshot, semantic_id)
		if !found {
			accessibility_projection_destroy(&working)
			accessibility_projection_delta_destroy(&delta)
			return accessibility_projection_requires_snapshot(update, allocator), .Requires_Snapshot
		}
		platform_id := accessibility_semantic_id_hash(semantic_id)
		if platform_id == 0 { platform_id = 1 }
		for candidate in working.nodes {
			if candidate.id == platform_id && candidate.semantic_id != semantic_id {
				accessibility_projection_destroy(&working)
				accessibility_projection_delta_destroy(&delta)
				return accessibility_projection_requires_snapshot(update, allocator), .Requires_Snapshot
			}
		}
		projected, ok := accessibility_projection_node_from_semantic(source, platform_id, allocator)
		if !ok {
			accessibility_projection_destroy(&working)
			accessibility_projection_delta_destroy(&delta)
			return accessibility_projection_requires_snapshot(update, allocator), .Requires_Snapshot
		}
		index := accessibility_projection_find_semantic(working, semantic_id)
		if index > 0 {
			accessibility_projection_destroy_node(&working.nodes[index], allocator)
			working.nodes[index] = projected
		} else {
			append(&working.nodes, projected)
		}
		changed_semantics[semantic_id] = true
	}

	accessibility_projection_sort_semantic_nodes(&working)
	semantic_indices := accessibility_projection_semantic_indices(working, allocator)
	defer delete(semantic_indices)
	accessibility_projection_apply_collection_selection(&working, snapshot, semantic_indices)
	if !accessibility_projection_apply_text_selections(&working, snapshot, semantic_indices) ||
	   !accessibility_projection_rebuild_structure(&working) || !accessibility_projection_matches_snapshot(working, snapshot) {
		accessibility_projection_destroy(&working)
		accessibility_projection_delta_destroy(&delta)
		return accessibility_projection_requires_snapshot(update, allocator), .Requires_Snapshot
	}
	if focus_index, found := semantic_indices[snapshot.keyboard_focus]; found && snapshot.keyboard_focus != (alicorn.Semantic_ID{}) {
		working.keyboard_focus = working.nodes[focus_index].id
	} else {
		working.keyboard_focus = working.root_id
	}
	delta.keyboard_focus = working.keyboard_focus

	for node in working.nodes {
		old_index := accessibility_projection_find_platform_id(old, node.id)
		is_changed := node.semantic_id != (alicorn.Semantic_ID{}) && changed_semantics[node.semantic_id]
		if !is_changed && (old_index < 0 || !accessibility_projection_nodes_equal(node, old.nodes[old_index])) {
			is_changed = true
		}
		if is_changed {
			copy, ok := accessibility_projection_clone_node(node, allocator)
			if !ok {
				accessibility_projection_destroy(&working)
				accessibility_projection_delta_destroy(&delta)
				return accessibility_projection_requires_snapshot(update, allocator), .Requires_Snapshot
			}
			append(&delta.changed_nodes, copy)
		}
	}
	working.revision = snapshot.revision
	working.keyboard_focus = delta.keyboard_focus
	working.keyboard_focus_semantic_id = snapshot.keyboard_focus
	accessibility_projection_destroy(projection)
	projection^ = working
	return delta, .Applied
}

@(private)
accessibility_projection_requires_snapshot :: proc(update: alicorn.Semantic_Update_View, allocator: mem.Allocator) -> Accessibility_Projection_Delta {
	return Accessibility_Projection_Delta{
		from_revision=update.from_revision,
		to_revision=update.to_revision,
		requires_snapshot=true,
		allocator=allocator,
	}
}

@(private)
accessibility_projection_clone :: proc(source: Accessibility_Projection, allocator: mem.Allocator) -> (copy: Accessibility_Projection, ok: bool) {
	previous_allocator := context.allocator
	context.allocator = allocator
	defer context.allocator = previous_allocator
	copy = Accessibility_Projection{
		revision=source.revision,
		keyboard_focus=source.keyboard_focus,
		keyboard_focus_semantic_id=source.keyboard_focus_semantic_id,
		root_id=source.root_id,
		allocator=allocator,
		nodes=make([dynamic]Accessibility_Projection_Node, 0, len(source.nodes), allocator=allocator),
	}
	for node in source.nodes {
		cloned, cloned_ok := accessibility_projection_clone_node(node, allocator)
		if !cloned_ok { accessibility_projection_destroy(&copy); return {}, false }
		append(&copy.nodes, cloned)
	}
	return copy, true
}

@(private)
accessibility_projection_clone_node :: proc(source: Accessibility_Projection_Node, allocator: mem.Allocator) -> (copy: Accessibility_Projection_Node, ok: bool) {
	previous_allocator := context.allocator
	context.allocator = allocator
	defer context.allocator = previous_allocator
	copy = source
	copy.label, copy.description, copy.value = "", "", ""
	copy.text_run_character_lengths = nil
	copy.children = make([dynamic]u64, 0, len(source.children), allocator=allocator)
	if len(source.label) > 0 {
		value, err := strings.clone(source.label, allocator)
		if err != nil { accessibility_projection_destroy_node(&copy, allocator); return {}, false }
		copy.label = value
	}
	if len(source.description) > 0 {
		value, err := strings.clone(source.description, allocator)
		if err != nil { accessibility_projection_destroy_node(&copy, allocator); return {}, false }
		copy.description = value
	}
	if len(source.value) > 0 {
		value, err := strings.clone(source.value, allocator)
		if err != nil { accessibility_projection_destroy_node(&copy, allocator); return {}, false }
		copy.value = value
	}
	if len(source.text_run_character_lengths) > 0 {
		copy.text_run_character_lengths = make([]u8, len(source.text_run_character_lengths), allocator=allocator)
		if copy.text_run_character_lengths == nil { accessibility_projection_destroy_node(&copy, allocator); return {}, false }
		for i in 0..<len(source.text_run_character_lengths) {
			copy.text_run_character_lengths[i] = source.text_run_character_lengths[i]
		}
	}
	for child in source.children { append(&copy.children, child) }
	return copy, true
}

@(private)
accessibility_projection_find_semantic :: proc(projection: Accessibility_Projection, semantic_id: alicorn.Semantic_ID) -> int {
	for node, index in projection.nodes {
		if node.semantic_id == semantic_id { return index }
	}
	return -1
}

@(private)
accessibility_projection_find_platform_id :: proc(projection: Accessibility_Projection, platform_id: u64) -> int {
	for node, index in projection.nodes {
		if node.id == platform_id { return index }
	}
	return -1
}

// The nodes slice is the enumerable platform-neutral tree (including its
// synthetic root); these lookups expose both directions without making map
// storage or allocator lifetime part of the caller contract.
accessibility_projection_node_by_id :: proc(projection: Accessibility_Projection, id: u64) -> (node: Accessibility_Projection_Node, found: bool) {
	index := accessibility_projection_find_platform_id(projection, id)
	if index < 0 { return {}, false }
	return projection.nodes[index], true
}

// Converts AccessKit text-run node positions to Alicorn semantic positions and
// rejects stale, cross-editor, or out-of-range endpoints.
accessibility_projection_text_selection_decode :: proc(
	projection: Accessibility_Projection,
	area_id: alicorn.Semantic_ID,
	anchor_node_id, anchor_character_index: u64,
	focus_node_id, focus_character_index: u64,
) -> (selection: alicorn.Semantic_Text_Selection, ok: bool) {
	area, area_found := accessibility_projection_node_by_semantic_id(projection, area_id)
	anchor, anchor_found := accessibility_projection_node_by_id(projection, anchor_node_id)
	focus, focus_found := accessibility_projection_node_by_id(projection, focus_node_id)
	if !area_found || area.role != .Text_Area || !anchor_found || !focus_found ||
	   anchor.role != .Text_Run || focus.role != .Text_Run ||
	   anchor.semantic_parent != area_id || focus.semantic_parent != area_id ||
	   anchor_character_index > u64(len(anchor.text_run_character_lengths)) ||
	   focus_character_index > u64(len(focus.text_run_character_lengths)) { return {}, false }
	return alicorn.Semantic_Text_Selection{
		anchor={run_id=anchor.semantic_id, character_index=anchor_character_index},
		focus={run_id=focus.semantic_id, character_index=focus_character_index},
		valid=true,
	}, true
}

// Lookup results are shallow borrowed records; their strings and children are
// valid until the projection is updated or destroyed.
accessibility_projection_node_by_semantic_id :: proc(projection: Accessibility_Projection, id: alicorn.Semantic_ID) -> (node: Accessibility_Projection_Node, found: bool) {
	index := accessibility_projection_find_semantic(projection, id)
	if index < 0 { return {}, false }
	return projection.nodes[index], true
}

@(private)
accessibility_snapshot_find_node :: proc(snapshot: alicorn.Semantic_Snapshot, semantic_id: alicorn.Semantic_ID) -> (node: alicorn.Semantic_Node, found: bool) {
	for candidate in snapshot.nodes {
		if candidate.id == semantic_id { return candidate, true }
	}
	return {}, false
}

@(private)
accessibility_projection_semantic_indices :: proc(projection: Accessibility_Projection, allocator: mem.Allocator) -> map[alicorn.Semantic_ID]int {
	result := make(map[alicorn.Semantic_ID]int, allocator=allocator)
	for index in 1..<len(projection.nodes) { result[projection.nodes[index].semantic_id] = index }
	return result
}

@(private)
accessibility_projection_matches_snapshot :: proc(projection: Accessibility_Projection, snapshot: alicorn.Semantic_Snapshot) -> bool {
	if len(projection.nodes) != len(snapshot.nodes)+1 { return false }
	seen := make(map[alicorn.Semantic_ID]bool, allocator=context.allocator)
	defer delete(seen)
	for source in snapshot.nodes {
		if source.id == (alicorn.Semantic_ID{}) || seen[source.id] { return false }
		seen[source.id] = true
		if accessibility_projection_find_semantic(projection, source.id) <= 0 { return false }
	}
	return true
}

@(private)
accessibility_projection_sort_semantic_nodes :: proc(projection: ^Accessibility_Projection) {
	for index := 2; index < len(projection.nodes); index += 1 {
		at := index
		for at > 1 {
			left := projection.nodes[at-1]
			right := projection.nodes[at]
			ordered := left.tree_order < right.tree_order ||
				(left.tree_order == right.tree_order && !accessibility_semantic_id_less(right.semantic_id, left.semantic_id))
			if ordered { break }
			projection.nodes[at-1], projection.nodes[at] = projection.nodes[at], projection.nodes[at-1]
			at -= 1
		}
	}
}

@(private)
accessibility_projection_nodes_equal :: proc(a, b: Accessibility_Projection_Node) -> bool {
	if a.id != b.id || a.semantic_id != b.semantic_id || a.semantic_parent != b.semantic_parent ||
	   a.role != b.role || a.label != b.label || a.description != b.description || a.value != b.value ||
	   a.text_selection != b.text_selection || !accessibility_projection_byte_lengths_equal(a.text_run_character_lengths, b.text_run_character_lengths) ||
	   a.states != b.states || a.actions != b.actions || a.bounds != b.bounds || a.has_bounds != b.has_bounds ||
	   a.is_collection != b.is_collection || a.logical_count != b.logical_count ||
	   a.position_in_set != b.position_in_set || a.size_of_set != b.size_of_set ||
	   a.selected_item_id != b.selected_item_id || a.current_item_id != b.current_item_id ||
	   a.numeric_value != b.numeric_value || a.numeric_minimum != b.numeric_minimum ||
	   a.numeric_maximum != b.numeric_maximum || a.numeric_step != b.numeric_step ||
	   a.has_numeric_value != b.has_numeric_value || len(a.children) != len(b.children) { return false }
	for child, index in a.children { if child != b.children[index] { return false } }
	return true
}

@(private)
accessibility_projection_byte_lengths_equal :: proc(a, b: []u8) -> bool {
	if len(a) != len(b) { return false }
	for i in 0..<len(a) { if a[i] != b[i] { return false } }
	return true
}

// Delta application is transactional: on any mismatch or collision, the
// caller receives Requires_Snapshot and the existing projection is untouched.
