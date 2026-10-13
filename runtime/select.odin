package alicorn

import "core:strings"
import "core:unicode"

// Select is a controlled, select-only choice control. Options are ordinary
// application data; stable keys, rather than list positions, name choices.
SELECT_MAX_OPTIONS :: 128
SELECT_OPTION_LABEL_MAX_BYTES :: 256
SELECT_DEFAULT_WIDTH :: f32(240)
SELECT_TRIGGER_HEIGHT :: f32(36)
SELECT_OPTION_HEIGHT :: f32(32)
SELECT_TYPEAHEAD_CAPACITY :: 64

DEFAULT_SELECT_STYLE :: Layout_Style{
	direction=.Row,
	width=SELECT_DEFAULT_WIDTH,
	height=SELECT_TRIGGER_HEIGHT,
	max_width=-1,
	max_height=-1,
	align=.Center,
}

Select_Option :: struct {
	key: u64,
	label: string,
	disabled: bool,
}

Select_Result :: struct {
	selected_key: u64,
	changed: bool,
	open: bool,
	valid: bool,
}

// Select_State is bounded because only one popup may own the runtime's
// transient overlay plane at once. frame_options borrows the current
// description's scratch arena and is only read when described_frame matches.
Select_State :: struct {
	open: bool,
	expand_pending: bool,
	pending_expand_id: Semantic_ID,
	trigger_node: Node_ID,
	trigger_semantic_id: Semantic_ID,
	list_semantic_id: Semantic_ID,
	field_label: string,
	anchor: Rect,
	style_environment: Style_Environment,
	described_frame: u64,
	frame_options: []Select_Option,
	option_count: int,
	option_keys: [SELECT_MAX_OPTIONS]u64,
	option_disabled: [SELECT_MAX_OPTIONS]bool,
	option_nodes: [SELECT_MAX_OPTIONS]Node_ID,
	option_semantic_ids: [SELECT_MAX_OPTIONS]Semantic_ID,
	selected_key: u64,
	active_key: u64,
	active_index: int,
	scroll_node: Node_ID,
	changed_pending: bool,
	changed_trigger: Node_ID,
	changed_key: u64,
	typeahead: [SELECT_TYPEAHEAD_CAPACITY]u8,
	typeahead_length: int,
	typeahead_pending: bool,
}

select_semantic_namespace :: u64(0x53454C4543540001)

select_list_semantic_id :: proc(trigger: Node_ID) -> Semantic_ID {
	value := hash_mix(u64(trigger), 0x4C495354424F58)
	if value == 0 { value = 1 }
	return Semantic_ID{namespace=select_semantic_namespace, value=value}
}

select_option_semantic_id :: proc(trigger: Node_ID, key: u64) -> Semantic_ID {
	value := hash_mix(u64(trigger), key)
	value = hash_mix(value, 0x4F5054494F4E)
	if value == 0 { value = 1 }
	return Semantic_ID{namespace=select_semantic_namespace, value=value}
}

select_option_index :: proc(options: []Select_Option, key: u64) -> int {
	for option, index in options { if option.key == key { return index } }
	return -1
}

select_options_valid :: proc(options: []Select_Option) -> bool {
	if len(options) > SELECT_MAX_OPTIONS { return false }
	for option, index in options {
		if len(option.label) == 0 || len(option.label) > SELECT_OPTION_LABEL_MAX_BYTES { return false }
		for other in options[:index] { if other.key == option.key { return false } }
	}
	return true
}

select_has_enabled_option :: proc(options: []Select_Option) -> bool {
	for option in options { if !option.disabled { return true } }
	return false
}

select_options_clone :: proc(rt: ^Runtime, options: []Select_Option) -> (copy: []Select_Option, ok: bool) {
	copy = make([]Select_Option, len(options), allocator=rt.scratch_allocator)
	if copy == nil && len(options) > 0 { return nil, false }
	for option, index in options {
		label, err := strings.clone(option.label, rt.scratch_allocator)
		if err != nil { return nil, false }
		copy[index] = Select_Option{option.key, label, option.disabled}
	}
	return copy, true
}

select_trigger_environment :: proc(rt: ^Runtime, trigger: Node_ID) -> Style_Environment {
	if rt == nil { return DEFAULT_STYLE_ENVIRONMENT }
	for index := len(rt.pending)-1; index >= 0; index -= 1 {
		item := rt.pending[index]
		if item.kind == .Description && item.description.id == trigger {
			return style_environment_with_accessibility(item.description.style_environment, item.accessibility)
		}
	}
	return rt.style_environment
}

select_open_owned :: proc(rt: ^Runtime, state: ^Select_State) -> bool {
	return rt != nil && state != nil && state.open && rt.context_menu.open &&
		rt.context_menu.restore_focus == state.trigger_node
}

select_first_enabled :: proc(state: ^Select_State) -> int {
	if state == nil { return -1 }
	for index in 0..<state.option_count { if !state.option_disabled[index] { return index } }
	return -1
}

select_find_key :: proc(state: ^Select_State, key: u64) -> int {
	if state == nil { return -1 }
	for index in 0..<state.option_count { if state.option_keys[index] == key { return index } }
	return -1
}

select_first_active :: proc(state: ^Select_State, selected_key: u64) -> int {
	if index := select_find_key(state, state.active_key); index >= 0 && !state.option_disabled[index] { return index }
	if index := select_find_key(state, selected_key); index >= 0 && !state.option_disabled[index] { return index }
	return select_first_enabled(state)
}

select_refresh_options :: proc(
	rt: ^Runtime,
	trigger: Node_ID,
	semantic_id: Semantic_ID,
	field_label: string,
	options: []Select_Option,
	selected_key: u64,
	frame: u64,
) -> bool {
	state := &rt.select
	if !select_open_owned(rt, state) || state.trigger_node != trigger { return false }
	copy, copied := select_options_clone(rt, options)
	if !copied { return false }
	state.frame_options = copy
	state.described_frame = frame
	state.trigger_semantic_id = semantic_id
	state.list_semantic_id = select_list_semantic_id(trigger)
	state.field_label = field_label
	state.option_count = len(options)
	state.selected_key = selected_key
	previous_active := state.active_key
	for option, index in options {
		state.option_keys[index] = option.key
		state.option_disabled[index] = option.disabled
		state.option_nodes[index] = 0
		state.option_semantic_ids[index] = select_option_semantic_id(trigger, option.key)
	}
	if state.option_count == 0 {
		state.active_index = -1
		state.active_key = 0
		return true
	}
	if state.typeahead_pending {
		state.active_index = select_typeahead_match(state, state.frame_options[:], string(state.typeahead[:state.typeahead_length]))
		state.typeahead_pending = false
	} else if active := select_find_key(state, previous_active); active >= 0 && !state.option_disabled[active] {
		state.active_index = active
	} else {
		state.active_index = select_first_active(state, selected_key)
	}
	if state.active_index >= 0 { state.active_key = state.option_keys[state.active_index] }
	return true
}

// select emits a themed button-like trigger and reports the controlled value.
// The caller owns the selection: apply result.selected_key when result.changed
// is true, then pass that key on the next description.
select_control :: proc(
	ui: ^UI,
	key: UI_Key,
	label: string,
	options: []Select_Option,
	selected_key: u64,
	style := DEFAULT_SELECT_STYLE,
	loc := #caller_location,
) -> Select_Result {
	if ui == nil || ui.runtime == nil || !ui.runtime.frame_open { return Select_Result{selected_key=selected_key} }
	rt := ui.runtime
	state := &rt.select
	source := resolve_source(Source_Site{}, "select", loc)
	expected_trigger := identity_hash_key(current_identity_parent(ui), source, key)
	valid := select_options_valid(options)
	selected_index := select_option_index(options, selected_key)
	if len(options) > 0 && selected_index < 0 { valid = false }
	if !valid { append_diagnostic(rt, "select requires unique stable option keys, labels of 1 to 256 bytes, at most 128 options, and a selected key present in the options") }

	if state.open && (!rt.context_menu.open || rt.context_menu.restore_focus != state.trigger_node) { state.open = false }
	display_value := label
	if selected_index >= 0 { display_value = options[selected_index].label }
	if state.changed_pending && state.changed_trigger == expected_trigger {
		if changed_index := select_option_index(options, state.changed_key); changed_index >= 0 {
			display_value = options[changed_index].label
		}
	}
	disabled := !valid || len(options) == 0 || !select_has_enabled_option(options)
	trigger := emit_key(
		ui,
		.Button,
		source,
		label=display_value,
		key=key,
		style=style,
		focusable=!disabled,
		disabled=disabled,
		button_content=button_content_style(.Start, .Center, padding_x=10, padding_y=4),
		button_variant=.Default,
	)
	if trigger == 0 { return Select_Result{selected_key=selected_key, valid=valid} }
	for index := len(rt.pending)-1; index >= 0; index -= 1 {
		item := &rt.pending[index]
		if item.kind == .Description && item.description.id == trigger {
			item.description.icon_id = .Chevron_Down
			break
		}
	}
	trigger_semantic := semantic_visual_id(trigger)
	anchor := layout_node_finalized_geometry(rt, trigger).bounds
	can_claim_state := !state.open || state.trigger_node == trigger ||
		(state.expand_pending && state.pending_expand_id == trigger_semantic)
	if can_claim_state {
		state.trigger_node = trigger
		state.trigger_semantic_id = trigger_semantic
		state.list_semantic_id = select_list_semantic_id(trigger)
		state.anchor = anchor
		state.field_label = label
		state.style_environment = select_trigger_environment(rt, trigger)
		state.option_count = len(options) if valid else 0
		state.selected_key = selected_key
		if valid {
			for option, index in options {
				state.option_keys[index] = option.key
				state.option_disabled[index] = option.disabled
				state.option_nodes[index] = 0
				state.option_semantic_ids[index] = select_option_semantic_id(trigger, option.key)
			}
		}
	}
	owned_open := state.open && rt.context_menu.open && rt.context_menu.restore_focus == trigger
	if state.expand_pending && state.pending_expand_id == trigger_semantic {
		if !disabled && !rt.context_menu.open &&
			context_menu_open(rt, anchor, trigger, maxf(style.width, SELECT_DEFAULT_WIDTH), SELECT_OPTION_HEIGHT) {
			state.open = true
			selected_option := select_option_index(options, selected_key)
			state.active_index = selected_option if selected_option >= 0 && !options[selected_option].disabled else select_first_enabled(state)
			state.active_key = state.option_keys[state.active_index] if state.active_index >= 0 else 0
			state.typeahead_length = 0
			state.typeahead_pending = false
			owned_open = true
		}
		state.expand_pending = false
		state.pending_expand_id = {}
	}

	activated := consume_activation(rt, trigger)
	if activated && !disabled {
		if owned_open {
			state.open = false
			context_menu_close_internal(rt, true)
			owned_open = false
		} else if !rt.context_menu.open {
			if context_menu_open(rt, anchor, trigger, maxf(style.width, SELECT_DEFAULT_WIDTH), SELECT_OPTION_HEIGHT) {
				state.open = true
				state.list_semantic_id = select_list_semantic_id(trigger)
				state.active_index = selected_index if selected_index >= 0 && !options[selected_index].disabled else select_first_enabled(state)
				state.active_key = state.option_keys[state.active_index] if state.active_index >= 0 else 0
				state.typeahead_length = 0
				state.typeahead_pending = false
				owned_open = true
			}
		}
	}

	// Close a stale owned overlay if a rebuild replaced or removed the trigger.
	if state.open && state.trigger_node == trigger && !rt.context_menu.open { state.open = false }
	owned_open = state.open && rt.context_menu.open && rt.context_menu.restore_focus == trigger
	if owned_open && disabled {
		state.open = false
		context_menu_close_internal(rt, true)
		owned_open = false
	}
	states := Semantic_States{}
	actions := Semantic_Actions{}
	if !disabled {
		actions = semantic_actions_add(actions, .Focus)
		if owned_open {
			states = semantic_states_add(states, .Expanded)
			actions = semantic_actions_add(actions, .Collapse)
		} else {
			actions = semantic_actions_add(actions, .Expand)
		}
	}
	_ = semantic_description(ui, .Combo_Box, label, value=display_value, states=states, actions=actions)
	if owned_open && valid && len(options) > 0 {
		state.style_environment = select_trigger_environment(rt, trigger)
		if !select_refresh_options(rt, trigger, trigger_semantic, label, options, selected_key, rt.stats.frames_built) {
			state.open = false
			context_menu_close_internal(rt, true)
			owned_open = false
		}
	} else if owned_open {
		state.open = false
		context_menu_close_internal(rt, true)
		owned_open = false
	}

	result := Select_Result{selected_key=selected_key, open=owned_open, valid=valid}
	if state.changed_pending && state.changed_trigger == trigger {
		result.selected_key = state.changed_key
		result.changed = true
		state.changed_pending = false
		state.changed_trigger = 0
	}
	return result
}

select_text_has_prefix :: proc(value, prefix: string) -> bool {
	if len(prefix) == 0 || len(prefix) > SELECT_TYPEAHEAD_CAPACITY || len(value) > SELECT_OPTION_LABEL_MAX_BYTES { return false }
	value_runes: [SELECT_OPTION_LABEL_MAX_BYTES]rune
	value_count := 0
	for value_rune in value {
		value_runes[value_count] = unicode.to_lower(value_rune)
		value_count += 1
	}
	prefix_runes: [SELECT_TYPEAHEAD_CAPACITY]rune
	prefix_count := 0
	for prefix_rune in prefix {
		prefix_runes[prefix_count] = unicode.to_lower(prefix_rune)
		prefix_count += 1
	}
	if prefix_count > value_count { return false }
	for index in 0..<prefix_count { if prefix_runes[index] != value_runes[index] { return false } }
	return true
}

select_typeahead_match :: proc(state: ^Select_State, options: []Select_Option, prefix: string) -> int {
	if state == nil || len(options) == 0 { return -1 }
	start := state.active_index
	if start < 0 || start >= len(options) { start = 0 }
	for offset in 1..=len(options) {
		index := (start + offset) % len(options)
		if options[index].disabled { continue }
		if select_text_has_prefix(options[index].label, prefix) { return index }
	}
	return -1
}

select_typeahead_has_match :: proc(options: []Select_Option, prefix: string) -> bool {
	if len(prefix) == 0 { return false }
	for option in options {
		if !option.disabled && select_text_has_prefix(option.label, prefix) { return true }
	}
	return false
}

select_result_set :: proc(rt: ^Runtime, index: int) -> bool {
	if rt == nil || index < 0 || index >= rt.select.option_count || rt.select.option_disabled[index] { return false }
	state := &rt.select
	key := state.option_keys[index]
	if key == state.selected_key {
		state.open = false
		context_menu_close_internal(rt, true)
		return true
	}
	state.changed_pending = true
	state.changed_trigger = state.trigger_node
	state.changed_key = key
	state.open = false
	context_menu_close_internal(rt, false)
	invalidate_root(rt, "select option selected")
	return true
}

select_overlay_result_set :: proc(rt: ^Runtime, index: int) -> bool {
	if rt == nil || index < 0 || index >= rt.select.option_count || rt.select.option_disabled[index] { return false }
	state := &rt.select
	if state.option_keys[index] != state.selected_key {
		state.changed_pending = true
		state.changed_trigger = state.trigger_node
		state.changed_key = state.option_keys[index]
		invalidate_root(rt, "select option selected")
	}
	state.open = false
	// context_menu_end owns retirement of the just-described overlay and its
	// pending nodes, so leave the shared menu open until it consumes this token.
	rt.context_menu.activation_action = Action_ID(0x53454C)
	return true
}

select_move_active :: proc(rt: ^Runtime, index: int) -> bool {
	if rt == nil || index < 0 || index >= rt.select.option_count || rt.select.option_disabled[index] { return false }
	state := &rt.select
	state.active_index = index
	state.active_key = state.option_keys[index]
	if row := state.option_nodes[index]; row != 0 { _ = context_menu_set_focus(rt, row) }
	select_ensure_active_visible(rt)
	invalidate_root(rt, "select active option changed")
	return true
}

select_ensure_active_visible :: proc(rt: ^Runtime) {
	if rt == nil { return }
	state := &rt.select
	if state.scroll_node == 0 || state.active_index < 0 { return }
	region := scroll_region_state(rt, state.scroll_node)
	if region.id == 0 || region.viewport_height <= 0 { return }
	item_top := f32(state.active_index)*SELECT_OPTION_HEIGHT
	item_bottom := item_top+SELECT_OPTION_HEIGHT
	next := region.offset_y
	if item_top < next { next = item_top }
	if item_bottom > next+region.viewport_height { next = item_bottom-region.viewport_height }
	_ = scroll_region_set_offset(rt, state.scroll_node, next, "select active option revealed")
}

// select_handle_key owns keydown while the Select listbox is open. Host input
// should call it before ordinary ContextMenu routing.
select_handle_key :: proc(rt: ^Runtime, key: Context_Menu_Key) -> bool {
	if !select_open_owned(rt, &rt.select) { return false }
	state := &rt.select
	if state.option_count <= 0 { return true }
	switch key {
	case .Up:
		start := state.active_index
		for offset in 1..=state.option_count {
			index := (start-offset)%state.option_count
			if index < 0 { index += state.option_count }
			if !state.option_disabled[index] { _ = select_move_active(rt, index); break }
		}
	case .Down:
		start := state.active_index
		if start < 0 { start = state.option_count-1 }
		for offset in 1..=state.option_count {
			index := (start+offset)%state.option_count
			if !state.option_disabled[index] { _ = select_move_active(rt, index); break }
		}
	case .Home:
		if index := select_first_enabled(state); index >= 0 { _ = select_move_active(rt, index) }
	case .End:
		for index := state.option_count-1; index >= 0; index -= 1 {
			if !state.option_disabled[index] { _ = select_move_active(rt, index); break }
		}
	case .Activate:
		if state.active_index >= 0 { _ = select_result_set(rt, state.active_index) }
	case .Cancel:
		state.open = false
		state.typeahead_length = 0
		context_menu_close_internal(rt, true)
	case .Other:
		// SDL_TEXT_INPUT is routed separately through select_typeahead.
	}
	return true
}

// select_handle_tab closes the popup and moves focus from its trigger to the
// next focusable control in ordinary application order. The retiring popup
// nodes are skipped even though they remain retained until reconciliation.
select_handle_tab :: proc(rt: ^Runtime, reverse := false) -> bool {
	if rt == nil || !select_open_owned(rt, &rt.select) { return false }
	trigger := rt.select.trigger_node
	overlay := rt.context_menu.overlay
	_ = select_handle_key(rt, .Cancel)
	// A dismissal normally keeps the transient overlay as an input shield for
	// the rest of the pointer event. Tab intentionally transfers focus out.
	rt.context_menu.dismissed = false
	start := -1
	for id, index in rt.order { if id == trigger { start = index; break } }
	if start < 0 { return true }
	step := 1
	if reverse { step = -1 }
	for offset := 1; offset <= len(rt.order); offset += 1 {
		index := start+step*offset
		for index < 0 { index += len(rt.order) }
		for index >= len(rt.order) { index -= len(rt.order) }
		id := rt.order[index]
		if node_is_in_modal_overlay(rt, id, overlay) { continue }
		node, found := rt.nodes[id]
		if !found || !node_is_presentation_active(rt, id) || !node.focusable || node.disabled { continue }
		if focus(rt, id) {
			focus_indicator_set(rt, true)
			return true
		}
	}
	return true
}

// select_typeahead receives committed SDL text input while the listbox owns
// focus. It is separate from keydown so keyboard layouts and IME input work.
select_typeahead :: proc(rt: ^Runtime, text: string) -> bool {
	if rt == nil || len(text) == 0 || !select_open_owned(rt, &rt.select) { return false }
	state := &rt.select
	if state.typeahead_length > 0 && len(state.frame_options) > 0 {
		candidate: [SELECT_TYPEAHEAD_CAPACITY]u8
		candidate_length := min(state.typeahead_length+len(text), SELECT_TYPEAHEAD_CAPACITY)
		for index in 0..<state.typeahead_length { candidate[index] = state.typeahead[index] }
		copy_count := min(len(text), SELECT_TYPEAHEAD_CAPACITY-state.typeahead_length)
		for index in 0..<copy_count { candidate[state.typeahead_length+index] = text[index] }
		if !select_typeahead_has_match(state.frame_options[:], string(candidate[:candidate_length])) &&
			select_typeahead_has_match(state.frame_options[:], text) {
			state.typeahead_length = 0
		}
	}
	copy_count := min(len(text), SELECT_TYPEAHEAD_CAPACITY-state.typeahead_length)
	if copy_count <= 0 { return true }
	for index in 0..<copy_count {
		state.typeahead[state.typeahead_length+index] = text[index]
	}
	state.typeahead_length += copy_count
	state.typeahead_pending = true
	invalidate_root(rt, "select type-ahead input")
	return true
}

select_wants_text_input :: proc(rt: ^Runtime) -> bool {
	return rt != nil && select_open_owned(rt, &rt.select)
}

// select_semantic_action handles AccessKit Combo_Box expand/collapse requests
// on the UI thread. List_Box_Option Select requests activate their realized
// button node through the normal one-shot activation path.
select_semantic_action :: proc(rt: ^Runtime, id: Semantic_ID, action: Semantic_Action) -> bool {
	if rt == nil { return false }
	semantic, found := semantic_node_lookup(rt, id)
	if !found || semantic.role != .Combo_Box { return false }
	state := &rt.select
	if action == .Expand {
		if id == state.trigger_semantic_id && select_open_owned(rt, state) { return true }
		if rt.context_menu.open { return false }
		state.expand_pending = true
		state.pending_expand_id = id
		invalidate_root(rt, "select expanded by accessibility action")
		return true
	}
	if action == .Collapse {
		if state.expand_pending && state.pending_expand_id == id {
			state.expand_pending = false
			state.pending_expand_id = {}
			return true
		}
		if id != state.trigger_semantic_id { return false }
		if !select_open_owned(rt, state) { return true }
		state.open = false
		context_menu_close_internal(rt, true)
		return true
	}
	return false
}

select_patch_pending_scroll :: proc(rt: ^Runtime, scroll_id, content_id: Node_ID, offset: f32) {
	if rt == nil { return }
	for index := len(rt.pending)-1; index >= 0; index -= 1 {
		item := &rt.pending[index]
		if item.kind != .Description { continue }
		if item.description.id == scroll_id || item.description.id == content_id {
			item.description.scroll_offset_y = offset
			item.description.layout_scroll_offset_y = offset
		}
	}
}

// select_overlay_describe adds the owned listbox after the ordinary root.
// end_frame calls it after ordinary app content, alongside retained overlays.
select_overlay_describe :: proc(ui: ^UI) {
	if ui == nil || ui.runtime == nil { return }
	rt := ui.runtime
	state := &rt.select
	// A semantic Expand must target a Select that is described by this frame;
	// expire requests for controls that disappeared before their next build.
	if state.expand_pending {
		state.expand_pending = false
		state.pending_expand_id = {}
	}
	if !select_open_owned(rt, state) { return }
	if !rt.frame_open || len(rt.stack) != 0 {
		append_diagnostic(rt, "select_overlay_describe must follow the ordinary root")
		return
	}
	if state.described_frame != rt.stats.frames_built || len(state.frame_options) != state.option_count || state.option_count <= 0 {
		state.open = false
		context_menu_close_internal(rt, true)
		return
	}

	previous_environment := rt.style_environment
	rt.style_environment = state.style_environment
	overlay_key := key_pair(u64(state.trigger_node), 0x53454C454354)
	if !context_menu_begin(ui, overlay_key, width=maxf(state.anchor.w, SELECT_DEFAULT_WIDTH), item_height=SELECT_OPTION_HEIGHT) {
		rt.style_environment = previous_environment
		return
	}
	panel := rt.context_menu.panel
	for index := len(rt.pending)-1; index >= 0; index -= 1 {
		item := &rt.pending[index]
		if item.kind == .Description && item.description.id == panel {
			item.description.color = style_environment_color(rt, state.style_environment, .Surface)
			item.description.paint_background = true
			item.description.style_environment = style_environment_core(state.style_environment)
			item.accessibility = state.style_environment.accessibility
			break
		}
	}

	selected_id := Semantic_ID{}
	selected_index := select_find_key(state, state.selected_key)
	if selected_index >= 0 { selected_id = state.option_semantic_ids[selected_index] }
	current_id := Semantic_ID{}
	if state.active_index >= 0 { current_id = state.option_semantic_ids[state.active_index] }
	collection := semantic_collection_begin(
		ui,
		panel,
		state.list_semantic_id,
		.List_Box,
		state.field_label,
		u64(state.option_count),
		selected_id=selected_id,
		current_id=current_id,
		realized_first=0,
		realized_last=u64(state.option_count),
		actions=semantic_actions_add({}, .Focus),
	)
	if len(rt.pending) > 0 && rt.pending[len(rt.pending)-1].kind == .Description {
		rt.pending[len(rt.pending)-1].semantic.parent = state.trigger_semantic_id
	}

	item_height := rt.context_menu.item_height
	content_height := f32(state.option_count)*item_height
	max_panel_height := maxf(rt.viewport.h-2*CONTEXT_MENU_VIEWPORT_MARGIN, item_height+2*rt.context_menu.padding)
	visible_height := minf(content_height, maxf(max_panel_height-2*rt.context_menu.padding, item_height))
	content_width := maxf(rt.context_menu.preferred_width-2*rt.context_menu.padding, 0)
	list_style := layout_style(.Column, width=content_width, height=visible_height, clip=true)
	list := virtual_list_begin(
		ui,
		state.option_count,
		item_height,
		key=key_string("select-options-scroll"),
		style=list_style,
		label="select-options",
		axes=.Vertical,
		scrollbars=.Auto,
	)
	if list.scroll.id == 0 {
		state.open = false
		_ = context_menu_end(ui)
		rt.style_environment = previous_environment
		return
	}
	state.scroll_node = list.scroll.id
	rt.context_menu.content_height = 2*rt.context_menu.padding+visible_height
	for option, index in state.frame_options {
		option_semantic_id := state.option_semantic_ids[index]
		row_key := key_pair(u64(state.trigger_node), option.key)
		row := emit_key(
			ui,
			.Button,
			resolve_source(Source_Site{}, "select-option"),
			label=option.label,
			key=row_key,
			style=layout_style(.Row, height=item_height),
			focusable=!option.disabled,
			disabled=option.disabled,
			selected=(option.key == state.selected_key),
			button_content=button_content_style(.Start, .Center, padding_x=10, padding_y=2),
			button_variant=.Quiet,
		)
		state.option_nodes[index] = row
		if row != 0 {
			option_states := Semantic_States{}
			option_actions := Semantic_Actions{}
			if option.key == state.selected_key { option_states = semantic_states_add(option_states, .Selected) }
			if option.disabled {
				option_states = semantic_states_add(option_states, .Disabled)
			} else {
				option_actions = semantic_actions_add(option_actions, .Select)
				option_actions = semantic_actions_add(option_actions, .Focus)
			}
			_ = semantic_collection_item(ui, collection, u64(index), Semantic_Node_Description{
				id=option_semantic_id,
				role=.List_Box_Option,
				label=option.label,
				value=option.label,
				states=option_states,
				actions=option_actions,
				visual_node=row,
			})
			if consume_activation(rt, row) {
				_ = select_overlay_result_set(rt, index)
			}
		}
	}
	virtual_list_end(ui, list)
	if state.active_index >= 0 && state.active_index < state.option_count {
		if id := state.option_nodes[state.active_index]; id != 0 { _ = context_menu_set_focus(rt, id) }
		if state.scroll_node != 0 {
			region := list.scroll
			item_top := f32(state.active_index)*item_height
			item_bottom := item_top+item_height
			desired := region.offset_y
			if item_top < desired { desired = item_top }
			if item_bottom > desired+visible_height { desired = item_bottom-visible_height }
			desired = clampf(desired, 0, maxf(content_height-visible_height, 0))
			if desired != region.offset_y {
				content_node: Node_ID = 0
				for index := len(rt.pending)-1; index >= 0; index -= 1 {
					item := rt.pending[index]
					if item.kind == .Description && item.description.kind == .Virtual_List { content_node = item.description.id; break }
				}
				select_patch_pending_scroll(rt, list.scroll.id, content_node, desired)
			}
		}
	}
	_ = context_menu_end(ui)
	if !state.open && rt.context_menu.open { context_menu_close_internal(rt, false) }
	rt.style_environment = previous_environment
}
