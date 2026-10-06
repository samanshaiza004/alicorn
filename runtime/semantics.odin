package alicorn

import "core:mem"
import "core:slice"

Semantic_Role :: enum {
	None,
	Window,
	Group,
	Button,
	Checkbox,
	Slider,
	Text_Field,
	Text_Area,
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
}

Semantic_State :: enum {
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

Semantic_States :: distinct bit_set[Semantic_State; u32]

semantic_states_add :: proc(states: Semantic_States, state: Semantic_State) -> Semantic_States {
	result := states
	result += {state}
	return result
}

semantic_states_remove :: proc(states: Semantic_States, state: Semantic_State) -> Semantic_States {
	result := states
	result -= {state}
	return result
}

semantic_states_has :: proc(states: Semantic_States, state: Semantic_State) -> bool {
	return state in states
}

Semantic_Action :: enum {
	None,
	Press,
	Focus,
	Set_Value,
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

Semantic_Actions :: distinct bit_set[Semantic_Action; u32]

// Semantic_Descriptor travels with a pending application description. Keeping
// it out of Description and Node protects their fixed-size budgets; resolved
// semantic entities live in Runtime.semantic_entities instead.
Semantic_Descriptor :: struct {
	role: Semantic_Role,
	label: string,
	description: string,
	value: string,
	states: Semantic_States,
	actions: Semantic_Actions,
	parent: Semantic_ID,
	is_collection: bool,
	logical_count: u64,
	realized_first: u64,
	realized_last: u64,
	selected_id: Semantic_ID,
	current_id: Semantic_ID,
	collection_id: Semantic_ID,
	collection_index: u64,
	numeric_value: f64,
	numeric_minimum: f64,
	numeric_maximum: f64,
	numeric_step: f64,
	has_numeric_value: bool,
}

semantic_actions_add :: proc(actions: Semantic_Actions, action: Semantic_Action) -> Semantic_Actions {
	result := actions
	result += {action}
	return result
}

semantic_actions_has :: proc(actions: Semantic_Actions, action: Semantic_Action) -> bool {
	return action in actions
}

// The reserved namespace is used only for semantic IDs derived from stable
// retained node identities. Applications should use their own nonzero
// namespace when supplying logical IDs.
ALICORN_SEMANTIC_NAMESPACE :: u64(0x414C49434F524E01)

semantic_visual_id :: proc(node: Node_ID) -> Semantic_ID {
	if node == 0 { return {} }
	return Semantic_ID{namespace=ALICORN_SEMANTIC_NAMESPACE, value=u64(node)}
}

Semantic_Node :: struct {
	id: Semantic_ID,
	role: Semantic_Role,
	label: string,
	description: string,
	value: string,
	states: Semantic_States,
	actions: Semantic_Actions,
	parent: Semantic_ID,
	visual_node: Node_ID,
	bounds: Rect,
	has_bounds: bool,
	tree_order: u64,
	is_collection: bool,
	logical_count: u64,
	realized_first: u64,
	realized_last: u64,
	selected_id: Semantic_ID,
	current_id: Semantic_ID,
	collection_id: Semantic_ID,
	position_in_set: u64,
	size_of_set: u64,
	is_virtual_item: bool,
	numeric_value: f64,
	numeric_minimum: f64,
	numeric_maximum: f64,
	numeric_step: f64,
	has_numeric_value: bool,
}

Semantic_Node_Description :: struct {
	id: Semantic_ID,
	role: Semantic_Role,
	label: string,
	description: string,
	value: string,
	states: Semantic_States,
	actions: Semantic_Actions,
	parent: Semantic_ID,
	visual_node: Node_ID,
	bounds: Rect,
	has_bounds: bool,
	tree_order: u64,
	is_collection: bool,
	logical_count: u64,
	realized_first: u64,
	realized_last: u64,
	selected_id: Semantic_ID,
	current_id: Semantic_ID,
	collection_id: Semantic_ID,
	position_in_set: u64,
	size_of_set: u64,
	is_virtual_item: bool,
	numeric_value: f64,
	numeric_minimum: f64,
	numeric_maximum: f64,
	numeric_step: f64,
	has_numeric_value: bool,
}

Semantic_Entity :: struct {
	node: Semantic_Node,
	collection_generation: u64,
}

// Semantic_Update_View borrows the runtime's single most-recent delta. Its
// changed_ids/removed_ids slices remain valid only until the next semantic
// commit or runtime destruction. A consumer with any other base revision must
// request a full semantic_snapshot instead of applying a gap.
Semantic_Update_View :: struct {
	from_revision: u64,
	to_revision: u64,
	keyboard_focus: Semantic_ID,
	changed_ids: []Semantic_ID,
	removed_ids: []Semantic_ID,
	requires_snapshot: bool,
}

Semantic_Request_Kind :: enum {
	Perform,
	Reveal,
}

Semantic_Request_Event :: struct {
	kind: Semantic_Request_Kind,
	id: Semantic_ID,
	action: Semantic_Action,
	text_value: string,
	numeric_value: f64,
	has_numeric_value: bool,
}

SEMANTIC_REQUEST_QUEUE_CAPACITY :: 256

Semantic_Snapshot :: struct {
	revision: u64,
	keyboard_focus: Semantic_ID,
	nodes: [dynamic]Semantic_Node,
	allocator: mem.Allocator,
}

Semantic_Collection_Handle :: struct {
	id: Semantic_ID,
	generation: u64,
	logical_count: u64,
	selected_id: Semantic_ID,
	current_id: Semantic_ID,
}

semantic_node_from_description :: proc(d: Semantic_Node_Description) -> Semantic_Node {
	return Semantic_Node{
		id=d.id,
		role=d.role,
		label=d.label,
		description=d.description,
		value=d.value,
		states=d.states,
		actions=d.actions,
		parent=d.parent,
		visual_node=d.visual_node,
		bounds=d.bounds,
		has_bounds=d.has_bounds,
		tree_order=d.tree_order,
		is_collection=d.is_collection,
		logical_count=d.logical_count,
		realized_first=d.realized_first,
		realized_last=d.realized_last,
		selected_id=d.selected_id,
		current_id=d.current_id,
		collection_id=d.collection_id,
		position_in_set=d.position_in_set,
		size_of_set=d.size_of_set,
		is_virtual_item=d.is_virtual_item,
		numeric_value=d.numeric_value,
		numeric_minimum=d.numeric_minimum,
		numeric_maximum=d.numeric_maximum,
		numeric_step=d.numeric_step,
		has_numeric_value=d.has_numeric_value,
	}
}

semantic_node_equal :: proc(a, b: Semantic_Node) -> bool {
	return a.id == b.id &&
		a.role == b.role && a.label == b.label && a.description == b.description && a.value == b.value &&
		a.states == b.states && a.actions == b.actions && a.parent == b.parent &&
		a.visual_node == b.visual_node && a.bounds == b.bounds && a.has_bounds == b.has_bounds &&
		a.tree_order == b.tree_order && a.is_collection == b.is_collection &&
		a.logical_count == b.logical_count && a.realized_first == b.realized_first && a.realized_last == b.realized_last &&
		a.selected_id == b.selected_id && a.current_id == b.current_id && a.collection_id == b.collection_id &&
		a.position_in_set == b.position_in_set && a.size_of_set == b.size_of_set &&
		a.is_virtual_item == b.is_virtual_item && a.numeric_value == b.numeric_value &&
		a.numeric_minimum == b.numeric_minimum && a.numeric_maximum == b.numeric_maximum &&
		a.numeric_step == b.numeric_step && a.has_numeric_value == b.has_numeric_value
}

semantic_node_set :: proc(rt: ^Runtime, description: Semantic_Node_Description) -> bool {
	if rt == nil || !semantic_id_is_valid(description.id) || description.role == .None { return false }
	if description.collection_id.namespace != 0 && description.size_of_set != 0 && description.position_in_set >= description.size_of_set {
		return false
	}
	if description.is_collection && description.role != .List && description.role != .Tree && description.role != .Tab_List {
		return false
	}
	next := semantic_node_from_description(description)
	previous, found := rt.semantic_entities[description.id]
	collection_generation: u64 = 0
	if description.collection_id.namespace != 0 {
		collection_generation = rt.semantic_collection_touched[description.collection_id]
	}
	if found && semantic_node_equal(previous.node, next) {
		previous.collection_generation = collection_generation
		rt.semantic_entities[description.id] = previous
		return false
	}
	was_removed := rt.semantic_pending_removed[description.id]
	label_copy := owned_with_allocator(next.label, rt.persistent_allocator)
	description_copy := owned_with_allocator(next.description, rt.persistent_allocator)
	value_copy := owned_with_allocator(next.value, rt.persistent_allocator)
	if (len(next.label) > 0 && len(label_copy) == 0) ||
	   (len(next.description) > 0 && len(description_copy) == 0) ||
	   (len(next.value) > 0 && len(value_copy) == 0) {
		if len(label_copy) > 0 { delete(label_copy, rt.persistent_allocator) }
		if len(description_copy) > 0 { delete(description_copy, rt.persistent_allocator) }
		if len(value_copy) > 0 { delete(value_copy, rt.persistent_allocator) }
		return false
	}
	if found {
		semantic_entity_strings_destroy(&previous, rt.persistent_allocator)
	}
	next.label = label_copy
	next.description = description_copy
	next.value = value_copy
	rt.semantic_entities[description.id] = Semantic_Entity{node=next, collection_generation=collection_generation}
	delete_key(&rt.semantic_pending_removed, description.id)
	rt.semantic_pending_changed[description.id] = true
	if !found && !was_removed { rt.semantic_pending_added[description.id] = true }
	structural_change := !found && !was_removed
	if found {
		structural_change = previous.node.role != next.role || previous.node.parent != next.parent ||
			previous.node.is_collection != next.is_collection || previous.node.logical_count != next.logical_count ||
			previous.node.collection_id != next.collection_id || previous.node.position_in_set != next.position_in_set ||
			previous.node.size_of_set != next.size_of_set
	}
	if structural_change { rt.semantic_pending_structure[description.id] = true }
	rt.stats.semantic_entities_resolved += 1
	return true
}

semantic_entity_strings_destroy :: proc(entity: ^Semantic_Entity, allocator: mem.Allocator) {
	if len(entity.node.label) > 0 { delete(entity.node.label, allocator) }
	if len(entity.node.description) > 0 { delete(entity.node.description, allocator) }
	if len(entity.node.value) > 0 { delete(entity.node.value, allocator) }
	entity.node.label = ""
	entity.node.description = ""
	entity.node.value = ""
}

semantic_node_remove :: proc(rt: ^Runtime, id: Semantic_ID) -> bool {
	if rt == nil || !semantic_id_is_valid(id) { return false }
	entity, found := rt.semantic_entities[id]
	if !found { return false }
	semantic_entity_strings_destroy(&entity, rt.persistent_allocator)
	delete_key(&rt.semantic_entities, id)
	delete_key(&rt.semantic_pending_changed, id)
	delete_key(&rt.semantic_pending_structure, id)
	if !rt.semantic_pending_added[id] { rt.semantic_pending_removed[id] = true }
	delete_key(&rt.semantic_pending_added, id)
	return true
}

// semantic_node_lookup returns a borrowed entity. Its string fields remain
// valid until that entity is updated/removed or the runtime is destroyed. Use
// semantic_snapshot when data must outlive the current runtime publication.
semantic_node_lookup :: proc(rt: ^Runtime, id: Semantic_ID) -> (node: Semantic_Node, found: bool) {
	if rt == nil { return }
	entity, exists := rt.semantic_entities[id]
	found = exists
	if found { node = entity.node }
	return
}

// semantic_commit publishes all semantic changes made during one application
// reconciliation as a single revision. Only the newest delta is retained; a
// consumer that missed its base revision must request a full snapshot.
semantic_commit :: proc(rt: ^Runtime) -> bool {
	if rt == nil || (len(rt.semantic_pending_changed) == 0 && len(rt.semantic_pending_removed) == 0 && !rt.semantic_keyboard_focus_pending) { return false }
	delete(rt.semantic_last_changed)
	delete(rt.semantic_last_removed)
	rt.semantic_last_changed = make([dynamic]Semantic_ID, 0, len(rt.semantic_pending_changed), allocator=rt.persistent_allocator)
	rt.semantic_last_removed = make([dynamic]Semantic_ID, 0, len(rt.semantic_pending_removed), allocator=rt.persistent_allocator)
	for id in rt.semantic_pending_changed { append(&rt.semantic_last_changed, id) }
	for id in rt.semantic_pending_removed { append(&rt.semantic_last_removed, id) }
	rt.semantic_last_from_revision = rt.semantic_revision
	rt.semantic_revision += 1
	if rt.semantic_revision == 0 { rt.semantic_revision = 1 }
	rt.semantic_last_to_revision = rt.semantic_revision
	for id in rt.semantic_last_changed {
		if rt.semantic_pending_added[id] { rt.stats.semantic_projection_nodes_added += 1 }
		else { rt.stats.semantic_projection_nodes_updated += 1 }
		if rt.semantic_pending_structure[id] { rt.stats.semantic_structure_changes += 1 }
		else { rt.stats.semantic_property_changes += 1 }
	}
	rt.stats.semantic_structure_changes += u64(len(rt.semantic_last_removed))
	rt.stats.semantic_projection_nodes_removed += u64(len(rt.semantic_last_removed))
	clear(&rt.semantic_pending_added)
	clear(&rt.semantic_pending_structure)
	clear(&rt.semantic_pending_changed)
	clear(&rt.semantic_pending_removed)
	rt.semantic_keyboard_focus_pending = false
	return true
}

semantic_revision :: proc(rt: ^Runtime) -> u64 {
	if rt == nil { return 0 }
	return rt.semantic_revision
}

semantic_update_since :: proc(rt: ^Runtime, from_revision: u64) -> Semantic_Update_View {
	if rt == nil { return Semantic_Update_View{requires_snapshot=true} }
	if from_revision == rt.semantic_revision {
		return Semantic_Update_View{from_revision=from_revision, to_revision=from_revision, keyboard_focus=rt.semantic_keyboard_focus}
	}
	if from_revision == rt.semantic_last_from_revision && rt.semantic_revision == rt.semantic_last_to_revision {
		return Semantic_Update_View{
			from_revision=rt.semantic_last_from_revision,
			to_revision=rt.semantic_last_to_revision,
			keyboard_focus=rt.semantic_keyboard_focus,
			changed_ids=rt.semantic_last_changed[:],
			removed_ids=rt.semantic_last_removed[:],
		}
	}
	return Semantic_Update_View{from_revision=from_revision, to_revision=rt.semantic_revision, requires_snapshot=true}
}

semantic_snapshot :: proc(rt: ^Runtime, allocator := context.allocator) -> Semantic_Snapshot {
	if rt == nil { return Semantic_Snapshot{allocator=allocator} }
	result := Semantic_Snapshot{revision=rt.semantic_revision, keyboard_focus=rt.semantic_keyboard_focus, allocator=allocator}
	result.nodes = make([dynamic]Semantic_Node, 0, len(rt.semantic_entities), allocator=allocator)
	for _, entity in rt.semantic_entities {
		node := entity.node
		node.label = owned_with_allocator(node.label, allocator)
		node.description = owned_with_allocator(node.description, allocator)
		node.value = owned_with_allocator(node.value, allocator)
		append(&result.nodes, node)
	}
	// Map iteration is intentionally unordered. Sort by stable order and ID for
	// deterministic snapshots without quadratic work on large ordinary trees.
	slice.sort_by(result.nodes[:], proc(a, b: Semantic_Node) -> bool {
		if a.tree_order != b.tree_order { return a.tree_order < b.tree_order }
		if a.id.namespace != b.id.namespace { return a.id.namespace < b.id.namespace }
		return a.id.value < b.id.value
	})
	return result
}

semantic_snapshot_destroy :: proc(snapshot: ^Semantic_Snapshot) {
	if snapshot == nil { return }
	for node in snapshot.nodes {
		if len(node.label) > 0 { delete(node.label, snapshot.allocator) }
		if len(node.description) > 0 { delete(node.description, snapshot.allocator) }
		if len(node.value) > 0 { delete(node.value, snapshot.allocator) }
	}
	delete(snapshot.nodes)
	snapshot^ = Semantic_Snapshot{}
}

semantic_collection_begin :: proc(
	ui: ^UI,
	owner: Node_ID,
	id: Semantic_ID,
	role: Semantic_Role,
	label: string,
	logical_count: u64,
	selected_id := Semantic_ID{},
	current_id := Semantic_ID{},
	realized_first: u64 = 0,
	realized_last: u64 = 0,
) -> Semantic_Collection_Handle {
	if ui == nil || ui.runtime == nil || !semantic_id_is_valid(id) ||
	   (role != .List && role != .Tree && role != .Tab_List) ||
	   realized_first > realized_last || realized_last > logical_count { return {} }
	rt := ui.runtime
	rt.semantic_collection_generation += 1
	if rt.semantic_collection_generation == 0 { rt.semantic_collection_generation = 1 }
	generation := rt.semantic_collection_generation
	rt.semantic_collection_touched[id] = generation
	for index := len(rt.pending)-1; index >= 0; index -= 1 {
		pending := &rt.pending[index]
		if pending.kind != .Description || pending.description.id != owner { continue }
		pending.description.semantic_id = id
		if pending.semantic.role == .None { rt.stats.semantic_descriptions_emitted += 1 }
		pending.semantic.role = role
		pending.semantic.label = label
		pending.semantic.is_collection = true
		pending.semantic.logical_count = logical_count
		pending.semantic.realized_first = realized_first
		pending.semantic.realized_last = realized_last
		pending.semantic.selected_id = selected_id
		pending.semantic.current_id = current_id
		pending.semantic.actions = semantic_actions_add(pending.semantic.actions, .Focus)
		return Semantic_Collection_Handle{id, generation, logical_count, selected_id, current_id}
	}
	delete_key(&rt.semantic_collection_touched, id)
	return {}
}

semantic_collection_item :: proc(
	ui: ^UI,
	collection: Semantic_Collection_Handle,
	position: u64,
	item: Semantic_Node_Description,
) -> bool {
	if ui == nil || ui.runtime == nil || !semantic_id_is_valid(collection.id) ||
	   !semantic_id_is_valid(item.id) || item.role == .None || position >= collection.logical_count || len(ui.runtime.pending) == 0 ||
	   ui.runtime.semantic_collection_touched[collection.id] != collection.generation { return false }
	last := len(ui.runtime.pending)-1
	if ui.runtime.pending[last].kind != .Description { return false }
	pending := &ui.runtime.pending[last]
	pending.description.semantic_id = item.id
	if pending.semantic.role == .None { ui.runtime.stats.semantic_descriptions_emitted += 1 }
	pending.semantic.role = item.role
	pending.semantic.label = item.label
	pending.semantic.description = item.description
	pending.semantic.value = item.value
	pending.semantic.states = item.states
	pending.semantic.actions = item.actions
	pending.semantic.parent = collection.id
	pending.semantic.collection_id = collection.id
	pending.semantic.collection_index = position
	ui.runtime.semantic_collection_touched[collection.id] = collection.generation
	return true
}

semantic_collection_selection_set :: proc(ui: ^UI, owner: Node_ID, selected_id, current_id: Semantic_ID) -> bool {
	if ui == nil || ui.runtime == nil { return false }
	for index := len(ui.runtime.pending)-1; index >= 0; index -= 1 {
		pending := &ui.runtime.pending[index]
		if pending.kind != .Description || pending.description.id != owner { continue }
		if !pending.semantic.is_collection { return false }
		pending.semantic.selected_id = selected_id
		pending.semantic.current_id = current_id
		return true
	}
	return false
}

semantic_collection_virtual_item :: proc(
	ui: ^UI,
	collection: Semantic_Collection_Handle,
	position: u64,
	item: Semantic_Node_Description,
) -> bool {
	if ui == nil || ui.runtime == nil || !semantic_id_is_valid(collection.id) ||
	   !semantic_id_is_valid(item.id) || item.role == .None || position >= collection.logical_count ||
	   ui.runtime.semantic_collection_touched[collection.id] != collection.generation { return false }
	ui.runtime.stats.semantic_descriptions_emitted += 1
	node := semantic_node_from_description(item)
	node.parent = collection.id
	node.collection_id = collection.id
	node.position_in_set = position
	node.size_of_set = collection.logical_count
	node.is_virtual_item = true
	node.visual_node = 0
	description := Semantic_Node_Description{
		id=node.id,
		role=node.role,
		label=node.label,
		description=node.description,
		value=node.value,
		states=node.states,
		actions=node.actions,
		parent=node.parent,
		visual_node=0,
		tree_order=node.tree_order,
		is_collection=node.is_collection,
		logical_count=node.logical_count,
		realized_first=node.realized_first,
		realized_last=node.realized_last,
		selected_id=node.selected_id,
		current_id=node.current_id,
		collection_id=node.collection_id,
		position_in_set=node.position_in_set,
		size_of_set=node.size_of_set,
		is_virtual_item=true,
		numeric_value=node.numeric_value,
		numeric_minimum=node.numeric_minimum,
		numeric_maximum=node.numeric_maximum,
		numeric_step=node.numeric_step,
		has_numeric_value=node.has_numeric_value,
	}
	changed := semantic_node_set(ui.runtime, description)
	if changed {
		entity, found := ui.runtime.semantic_entities[item.id]
		if found {
			entity.collection_generation = collection.generation
			ui.runtime.semantic_entities[item.id] = entity
		}
	}
	ui.runtime.semantic_collection_touched[collection.id] = collection.generation
	_ = changed
	return true
}

semantic_description_defaults :: proc(d: ^Description, semantic: ^Semantic_Descriptor) {
	if d == nil || semantic == nil || semantic.role != .None { return }
	states := Semantic_States{}
	actions := Semantic_Actions{}
	if d.disabled { states = semantic_states_add(states, .Disabled) }
	#partial switch d.kind {
	case .Button:
		semantic.role = .Button
		semantic.label = d.label
		if d.selected { states = semantic_states_add(states, .Selected) }
		if !d.disabled { actions = semantic_actions_add(actions, .Press) }
	case .Tab:
		semantic.role = .Tab
		semantic.label = d.label
		if d.selected { states = semantic_states_add(states, .Selected) }
		actions = semantic_actions_add(actions, .Select)
	case .Tab_Close:
		semantic.role = .Button
		semantic.label = d.label
		if !d.disabled { actions = semantic_actions_add(actions, .Press) }
	case .Checkbox:
		semantic.role = .Checkbox
		semantic.label = d.label
		if d.paint_value != 0 { states = semantic_states_add(states, .Checked) }
		if !d.disabled { actions = semantic_actions_add(actions, .Press) }
	case .Slider:
		semantic.role = .Slider
		semantic.label = d.label
		semantic.numeric_value = f64(d.control_value)
		semantic.numeric_minimum = f64(d.control_minimum)
		semantic.numeric_maximum = f64(d.control_maximum)
		semantic.numeric_step = f64(d.control_step)
		semantic.has_numeric_value = true
		if !d.disabled {
			actions = semantic_actions_add(actions, .Set_Value)
			actions = semantic_actions_add(actions, .Increment)
			actions = semantic_actions_add(actions, .Decrement)
		}
	case .Text_Field:
		semantic.role = .Text_Field
		semantic.value = d.text
		actions = semantic_actions_add(actions, .Focus)
		if !d.disabled { actions = semantic_actions_add(actions, .Set_Value) }
	case:
		return
	}
	semantic.states = states
	semantic.actions = actions
	if d.semantic_id.namespace == 0 { d.semantic_id = semantic_visual_id(d.id) }
}

semantic_description :: proc(
	ui: ^UI,
	role: Semantic_Role,
	label: string,
	description := "",
	value := "",
	states := Semantic_States{},
	actions := Semantic_Actions{},
	loc := #caller_location,
) -> bool {
	_ = loc
	if ui == nil || ui.runtime == nil || len(ui.runtime.pending) == 0 { return false }
	last := len(ui.runtime.pending)-1
	if ui.runtime.pending[last].kind != .Description || role == .None { return false }
	pending := &ui.runtime.pending[last]
	d := &pending.description
	if pending.semantic.role == .None { ui.runtime.stats.semantic_descriptions_emitted += 1 }
	pending.semantic.role = role
	pending.semantic.label = label
	pending.semantic.description = description
	pending.semantic.value = value
	pending.semantic.states = states
	pending.semantic.actions = actions
	if d.semantic_id.namespace == 0 { d.semantic_id = semantic_visual_id(d.id) }
	return true
}

semantic_describe_as :: proc(
	ui: ^UI,
	id: Semantic_ID,
	role: Semantic_Role,
	label: string,
	description := "",
	value := "",
	states := Semantic_States{},
	actions := Semantic_Actions{},
) -> bool {
	if !semantic_id_is_valid(id) || !semantic_description(ui, role, label, description, value, states, actions) { return false }
	ui.runtime.pending[len(ui.runtime.pending)-1].description.semantic_id = id
	return true
}

// semantic_sync_node publishes only nodes with an explicit or built-in
// semantic role. Visual identity is a fallback for ordinary controls; logical
// collection items should supply a durable application Semantic_ID.
semantic_sync_node :: proc(rt: ^Runtime, node: ^Node, semantic: Semantic_Descriptor, previous_id: Semantic_ID) {
	if rt == nil || node == nil { return }
	if semantic.role == .None {
		if old, found := rt.semantic_entities[previous_id]; found && old.node.visual_node == node.id {
			_ = semantic_node_remove(rt, previous_id)
		}
		return
	}
	id := node.semantic_id
	if !semantic_id_is_valid(id) { id = semantic_visual_id(node.id) }
	if semantic_id_is_valid(previous_id) && previous_id != id {
		if old, found := rt.semantic_entities[previous_id]; found && old.node.visual_node == node.id {
			_ = semantic_node_remove(rt, previous_id)
		}
	}
	parent := semantic.parent
	if !semantic_id_is_valid(parent) && semantic_id_is_valid(semantic.collection_id) {
		parent = semantic.collection_id
	}
	if !semantic_id_is_valid(parent) {
		ancestor_id := node.parent
		for ancestor_id != 0 {
			ancestor, found := rt.nodes[ancestor_id]
			if !found { break }
			if entity, semantic_found := rt.semantic_entities[ancestor.semantic_id]; semantic_found && entity.node.visual_node == ancestor_id {
				parent = ancestor.semantic_id
				break
			}
			ancestor_id = ancestor.parent
		}
	}
	tree_order: u64 = 0
	if previous, found := rt.semantic_entities[id]; found && previous.node.visual_node == node.id {
		tree_order = previous.node.tree_order
	}
	description := Semantic_Node_Description{
		id=id,
		role=semantic.role,
		label=semantic.label,
		description=semantic.description,
		value=semantic.value,
		states=semantic.states,
		actions=semantic.actions,
		parent=parent,
		visual_node=node.id,
		bounds=node.bounds,
		has_bounds=node.active,
		tree_order=tree_order,
		is_collection=semantic.is_collection,
		logical_count=semantic.logical_count,
		realized_first=semantic.realized_first,
		realized_last=semantic.realized_last,
		selected_id=semantic.selected_id,
		current_id=semantic.current_id,
		collection_id=semantic.collection_id,
		position_in_set=semantic.collection_index,
		numeric_value=semantic.numeric_value,
		numeric_minimum=semantic.numeric_minimum,
		numeric_maximum=semantic.numeric_maximum,
		numeric_step=semantic.numeric_step,
		has_numeric_value=semantic.has_numeric_value,
	}
	if semantic_id_is_valid(semantic.collection_id) {
		if collection, found := rt.semantic_entities[semantic.collection_id]; found {
			description.size_of_set = collection.node.logical_count
		}
	}
	_ = semantic_node_set(rt, description)
}

// Called from the retained preorder rebuild, where the runtime is already
// walking every realized node after a structural change. This keeps semantic
// order aligned with keyed visual reorder without an extra per-frame scan.
semantic_sync_tree_order :: proc(rt: ^Runtime, node_id: Node_ID, tree_order: u64) {
	if rt == nil { return }
	node, found := rt.nodes[node_id]
	if !found || !semantic_id_is_valid(node.semantic_id) { return }
	entity, semantic_found := rt.semantic_entities[node.semantic_id]
	if !semantic_found || entity.node.visual_node != node_id || entity.node.tree_order == tree_order { return }
	entity.node.tree_order = tree_order
	rt.semantic_entities[node.semantic_id] = entity
	rt.semantic_pending_changed[node.semantic_id] = true
	rt.semantic_pending_structure[node.semantic_id] = true
	rt.stats.semantic_entities_resolved += 1
}

// semantic_retire_node severs the visual lifetime without discarding a
// virtual/current/selected/focused logical entity. The entity can be rebound
// to a later realization with the same Semantic_ID.
semantic_retire_node :: proc(rt: ^Runtime, node: ^Node) {
	if rt == nil || node == nil || !semantic_id_is_valid(node.semantic_id) { return }
	entity, found := rt.semantic_entities[node.semantic_id]
	if !found || entity.node.visual_node != node.id { return }
	preserve := entity.node.is_virtual_item || rt.semantic_focus.id == node.semantic_id ||
		semantic_states_has(entity.node.states, .Selected) || semantic_states_has(entity.node.states, .Current)
	if entity.node.is_collection {
		_, selected_found := rt.semantic_entities[entity.node.selected_id]
		_, current_found := rt.semantic_entities[entity.node.current_id]
		focused_child, focused_found := rt.semantic_entities[rt.semantic_focus.id]
		preserve = preserve || (semantic_id_is_valid(entity.node.selected_id) && selected_found) ||
			(semantic_id_is_valid(entity.node.current_id) && current_found) ||
			(focused_found && focused_child.node.collection_id == node.semantic_id)
	}
	if semantic_id_is_valid(entity.node.collection_id) {
		if collection, collection_found := rt.semantic_entities[entity.node.collection_id]; collection_found {
			preserve = preserve || collection.node.selected_id == node.semantic_id || collection.node.current_id == node.semantic_id
		}
	}
	if preserve {
		description := Semantic_Node_Description{
			id=entity.node.id,
			role=entity.node.role,
			label=entity.node.label,
			description=entity.node.description,
			value=entity.node.value,
			states=entity.node.states,
			actions=entity.node.actions,
			parent=entity.node.parent,
			visual_node=0,
			tree_order=entity.node.tree_order,
			is_collection=entity.node.is_collection,
			logical_count=entity.node.logical_count,
			realized_first=entity.node.realized_first,
			realized_last=entity.node.realized_last,
			selected_id=entity.node.selected_id,
			current_id=entity.node.current_id,
			collection_id=entity.node.collection_id,
			position_in_set=entity.node.position_in_set,
			size_of_set=entity.node.size_of_set,
			is_virtual_item=entity.node.is_virtual_item,
			numeric_value=entity.node.numeric_value,
			numeric_minimum=entity.node.numeric_minimum,
			numeric_maximum=entity.node.numeric_maximum,
			numeric_step=entity.node.numeric_step,
			has_numeric_value=entity.node.has_numeric_value,
		}
		_ = semantic_node_set(rt, description)
		entity, found = rt.semantic_entities[node.semantic_id]
		if found { entity.node.has_bounds = false; entity.node.bounds = {}; rt.semantic_entities[node.semantic_id] = entity }
		if found && entity.node.is_collection {
			// The collection remains logical truth only while it has a selected,
			// current, or semantically focused item. Advance its working-set
			// generation so detaching the visual owner drops incidental rows.
			rt.semantic_collection_generation += 1
			if rt.semantic_collection_generation == 0 { rt.semantic_collection_generation = 1 }
			rt.semantic_collection_touched[node.semantic_id] = rt.semantic_collection_generation
		}
	} else {
		_ = semantic_node_remove(rt, node.semantic_id)
	}
}

// semantic_prune_touched_collections bounds virtual semantics by the entities
// described for each collection explicitly rebuilt in this frame. An omitted
// collection in a reused subtree keeps its prior working set. Current,
// selected, and logical semantic-focus entities stay pinned beyond the range.
semantic_prune_touched_collections :: proc(rt: ^Runtime) {
	if rt == nil { return }
	remove_ids := make([dynamic]Semantic_ID, 0, allocator=rt.scratch_allocator)
	for id, &entity in rt.semantic_entities {
		collection_id := entity.node.collection_id
		if !semantic_id_is_valid(collection_id) { continue }
		generation, touched := rt.semantic_collection_touched[collection_id]
		collection, collection_found := rt.semantic_entities[collection_id]
		if !collection_found {
			if id != rt.semantic_focus.id { append(&remove_ids, id) }
			continue
		}
		// A collection omitted from this build may live in an intentionally
		// reused retained subtree. Its previous semantic working set remains
		// authoritative until that collection is explicitly re-described.
		if !touched { continue }
		if entity.collection_generation == generation { continue }
		// The collection descriptor is authoritative for its members. State bits
		// on rows outside the described working set may be stale after selection
		// changes, because those rows are not necessarily emitted again.
		pinned := id == rt.semantic_focus.id || id == collection.node.selected_id || id == collection.node.current_id
		if pinned {
			entity.collection_generation = generation
		} else {
			append(&remove_ids, id)
		}
	}
	for id in remove_ids { _ = semantic_node_remove(rt, id) }
	delete(remove_ids)
}

semantic_keyboard_focus_resolve :: proc(rt: ^Runtime) -> Semantic_ID {
	if rt == nil { return {} }
	current := rt.focused
	for current != 0 {
		node, found := rt.nodes[current]
		if !found { return {} }
		if entity, semantic_found := rt.semantic_entities[node.semantic_id]; semantic_found && entity.node.visual_node == current {
			return node.semantic_id
		}
		current = node.parent
	}
	return {}
}

semantic_keyboard_focus_refresh :: proc(rt: ^Runtime) {
	if rt == nil { return }
	next := semantic_keyboard_focus_resolve(rt)
	if next != rt.semantic_keyboard_focus {
		rt.semantic_keyboard_focus = next
		rt.semantic_keyboard_focus_pending = true
	}
}

// semantic_action_request routes realized Press/Select/Focus actions through
// the same activation/focus machinery used by keyboard and pointer input.
// Actions on logical-only entities are queued for the next application build;
// callers decide whether to reveal or realize them.
semantic_action_request :: proc(
	rt: ^Runtime,
	id: Semantic_ID,
	action: Semantic_Action,
	text_value := "",
	numeric_value: f64 = 0,
	has_numeric_value := false,
) -> bool {
	if rt == nil || !semantic_id_is_valid(id) { return false }
	entity, found := rt.semantic_entities[id]
	if !found || !semantic_actions_has(entity.node.actions, action) { return false }
	if action == .None { return false }
	if entity.node.visual_node != 0 {
		visual, visual_found := rt.nodes[entity.node.visual_node]
		if !visual_found || !visual.active || visual.disabled { return false }
		#partial switch action {
		case .Press:
			if entity.node.role != .Button && entity.node.role != .Checkbox { break }
			rt.activation_sequence += 1
			rt.activation_node = visual.id
			rt.stats.accessibility_action_wakes += 1
			invalidate_root(rt, "semantic action requested")
			record_trace(rt, .Action, visual.id, "semantic Press/Select routed as control activation")
			return true
		case .Select:
			if entity.node.role != .Tab { break }
			rt.activation_sequence += 1
			rt.activation_node = visual.id
			rt.stats.accessibility_action_wakes += 1
			invalidate_root(rt, "semantic action requested")
			record_trace(rt, .Action, visual.id, "semantic Select routed as tab activation")
			return true
		case .Focus:
			if visual.focusable && focus(rt, visual.id) {
				rt.stats.accessibility_action_wakes += 1
				record_trace(rt, .Action, visual.id, "semantic Focus routed as keyboard focus")
				return true
			}
		case:
			// Value and collection actions are delivered as domain events even
			// when a visual node is present; they are not synthetic pointer input.
		}
	}
	if len(rt.semantic_requests)-rt.semantic_request_read_index >= SEMANTIC_REQUEST_QUEUE_CAPACITY { return false }
	copy := owned_with_allocator(text_value, rt.persistent_allocator)
	if len(text_value) > 0 && len(copy) == 0 { return false }
	append(&rt.semantic_requests, Semantic_Request_Event{
		kind=.Perform,
		id=id,
		action=action,
		text_value=copy,
		numeric_value=numeric_value,
		has_numeric_value=has_numeric_value,
	})
	rt.stats.accessibility_action_wakes += 1
	invalidate_root(rt, "logical semantic action requested")
	record_trace(rt, .Action, entity.node.visual_node, "logical semantic action queued for application")
	return true
}

// semantic_reveal_request is deliberately separate from performing an action.
// It asks the owning application to reveal a logical collection item; that may
// change scroll position and realization, but does not synthesize a click.
semantic_reveal_request :: proc(rt: ^Runtime, id: Semantic_ID) -> bool {
	if rt == nil || !semantic_id_is_valid(id) ||
	   len(rt.semantic_requests)-rt.semantic_request_read_index >= SEMANTIC_REQUEST_QUEUE_CAPACITY { return false }
	entity, found := rt.semantic_entities[id]
	if !found || !semantic_id_is_valid(entity.node.collection_id) { return false }
	if _, collection_found := rt.semantic_entities[entity.node.collection_id]; !collection_found { return false }
	append(&rt.semantic_requests, Semantic_Request_Event{kind=.Reveal, id=id})
	rt.stats.accessibility_reveal_wakes += 1
	invalidate_root(rt, "logical semantic reveal requested")
	record_trace(rt, .Action, entity.node.visual_node, "logical semantic reveal queued for application")
	return true
}

// semantic_request_pop transfers ownership of one queued text value to the
// caller. Drain requests during the bounded application wake; do not poll while
// idle. Reveal is distinct from perform and can be handled without a visual node.
semantic_request_pop :: proc(rt: ^Runtime) -> (event: Semantic_Request_Event, found: bool) {
	if rt == nil || rt.semantic_request_read_index >= len(rt.semantic_requests) { return }
	event = rt.semantic_requests[rt.semantic_request_read_index]
	rt.semantic_requests[rt.semantic_request_read_index].text_value = ""
	rt.semantic_request_read_index += 1
	found = true
	if rt.semantic_request_read_index >= len(rt.semantic_requests) {
		clear(&rt.semantic_requests)
		rt.semantic_request_read_index = 0
	}
	return
}

semantic_request_event_destroy :: proc(rt: ^Runtime, event: ^Semantic_Request_Event) {
	if rt == nil || event == nil { return }
	if len(event.text_value) > 0 { delete(event.text_value, rt.persistent_allocator) }
	event^ = Semantic_Request_Event{}
}

semantic_sync_bounds :: proc(rt: ^Runtime, node: ^Node) {
	if rt == nil || node == nil || !semantic_id_is_valid(node.semantic_id) { return }
	entity, found := rt.semantic_entities[node.semantic_id]
	if !found || entity.node.visual_node != node.id { return }
	if entity.node.visual_node != node.id || (entity.node.has_bounds && entity.node.bounds == node.bounds) { return }
	entity.node.visual_node = node.id
	entity.node.bounds = node.bounds
	entity.node.has_bounds = true
	rt.semantic_entities[node.semantic_id] = entity
	rt.semantic_pending_changed[node.semantic_id] = true
	rt.stats.semantic_entities_resolved += 1
}
