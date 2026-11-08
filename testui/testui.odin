package testui

import "core:fmt"
import "core:mem"
import "core:strings"
import sync "core:sync"
import alicorn "alicorn:runtime"

Status :: enum {
	Ok,
	Allocation_Failed,
	Invalid_Application,
	Invalid_Viewport,
	Font_Initialization_Failed,
	Did_Not_Stabilize,
	Stale_Snapshot,
	Not_Realized,
	Not_Hit_Testable,
	No_Focused_Element,
	Unsupported_Input,
	Invalid_Time,
	Motion_Failure,
}

Key :: enum {
	Tab,
	Space,
	Return,
	Escape,
	Left,
	Right,
	Up,
	Down,
	Page_Up,
	Page_Down,
	Home,
	End,
	Backspace,
	Delete,
	Word_Left,
	Word_Right,
	Line_Start,
	Line_End,
	Document_Start,
	Document_End,
	Delete_Word_Backward,
	Delete_Word_Forward,
	Delete_Line_Backward,
	Delete_Line_Forward,
	Fit_Selection,
	Command_1,
	Command_2,
	Command_3,
	Toggle,
	Open_Repository,
	Open_Command_Palette,
	Find,
	Workspace_Search,
	Context_Menu,
	Workspace_Rename,
	Find_Next,
	Find_Previous,
	Tab_Next,
	Tab_Previous,
	Zoom_In,
	Zoom_Out,
	Zoom_Reset,
}

Input_Kind :: enum { Key, Text_Commit, Text_Preedit, Text_Cancel, Pointer, Scroll, Semantic_Action, Time_Advance }

Input :: struct {
	kind: Input_Kind,
	key: Key,
	modifiers: alicorn.Input_Modifiers,
	text: string,
	composition_start_char: int,
	composition_length_char: int,
	selection_start_byte, selection_end_byte: int,
	delta_ns: u64,
	repeat: bool,
	pointer: alicorn.Pointer_Event,
	scroll: alicorn.Scroll_Event,
	semantic_id: alicorn.Semantic_ID,
	semantic_action: alicorn.Semantic_Action,
	semantic_text: string,
}

Application_Initialize_Proc :: proc(state: rawptr, rt: ^alicorn.Runtime)
Application_Key_Proc :: alicorn.Application_Key_Proc
Application_Text_Key_Proc :: alicorn.Application_Text_Key_Proc
Application_Text_Change_Proc :: alicorn.Application_Text_Change_Proc
Application_Text_Input_Proc :: alicorn.Application_Text_Input_Proc
Application_Pointer_Proc :: alicorn.Application_Pointer_Proc
Application_Scroll_Capture_Proc :: alicorn.Application_Scroll_Capture_Proc
Application_Scroll_Proc :: alicorn.Application_Scroll_Proc

MAX_DESCRIPTIONS_PER_TURN :: 4

Turn_Report :: struct {
	input: Input_Kind,
	key: Key,
	descriptions: int,
	stabilized: bool,
	layout_pending: bool,
	focus: alicorn.Node_ID,
	pointer_target: alicorn.Node_ID,
	message: string,
}

Test_Handle :: struct($T: typeid) {
	state: ^T,
	render: proc(^T, ^alicorn.UI),
	render_overlays: proc(^T, ^alicorn.UI),
	initialize: Application_Initialize_Proc,
	on_key: Application_Key_Proc,
	on_text_key: Application_Text_Key_Proc,
	on_text_change: Application_Text_Change_Proc,
	on_text_input: Application_Text_Input_Proc,
	on_pointer: Application_Pointer_Proc,
	on_scroll_capture: Application_Scroll_Capture_Proc,
	on_scroll: Application_Scroll_Proc,
	runtime: ^alicorn.Runtime,
	allocator: mem.Allocator,
	viewport_width, viewport_height: int,
	scale: f32,
	generation: u64,
	description_epoch: u64,
	now_ns: u64,
	application_composition_owner: alicorn.Node_ID,
	last_turn: Turn_Report,
}

Find_Match :: enum { None, Unique, Ambiguous }

Query :: struct {
	role: alicorn.Semantic_Role,
	name: string,
	key: alicorn.UI_Key,
	match_role, match_name, match_key: bool,
}

Element :: struct {
	handle_generation: u64,
	description_epoch: u64,
	semantic_id: alicorn.Semantic_ID,
	role: alicorn.Semantic_Role,
	name, description, value: string,
	states: alicorn.Semantic_States,
	actions: alicorn.Semantic_Actions,
	visual_node: alicorn.Node_ID,
	key: alicorn.UI_Key,
	key_valid: bool,
	bounds, hit_bounds, scroll_viewport_bounds: alicorn.Rect,
	has_bounds, focused: bool,
	scroll_offset_x, scroll_offset_y: f32,
	scroll_content_width, scroll_content_height: f32,
	scroll_viewport_width, scroll_viewport_height: f32,
	scroll_geometry_resolved: bool,
	allocator: mem.Allocator,
}

Find_Result :: struct {
	match: Find_Match,
	element: Element,
	status: Status,
}

test_handle_generation: u64

// open borrows application state until close. It creates Alicorn's normal
// Runtime, loads the same bundled primary fonts as the native host, and runs
// the supplied application description without creating an SDL window/GPU.
open :: proc(
	state: ^$T,
	render: proc(^T, ^alicorn.UI),
	width: int = 720,
	height: int = 480,
	scale: f32 = 1,
	allocator := context.allocator,
	initialize: Application_Initialize_Proc = nil,
	render_overlays: proc(^T, ^alicorn.UI) = nil,
	on_key: Application_Key_Proc = nil,
	on_text_key: Application_Text_Key_Proc = nil,
	on_text_change: Application_Text_Change_Proc = nil,
	on_text_input: Application_Text_Input_Proc = nil,
	on_pointer: Application_Pointer_Proc = nil,
	on_scroll_capture: Application_Scroll_Capture_Proc = nil,
	on_scroll: Application_Scroll_Proc = nil,
) -> (handle: Test_Handle(T), status: Status) {
	if state == nil || render == nil { return {}, .Invalid_Application }
	if width <= 0 || height <= 0 || scale <= 0 || !alicorn.number_is_finite(scale) {
		return {}, .Invalid_Viewport
	}
	handle.allocator = allocator
	handle.state = state
	handle.render = render
	handle.render_overlays = render_overlays
	handle.initialize = initialize
	handle.on_key = on_key
	handle.on_text_key = on_text_key
	handle.on_text_change = on_text_change
	handle.on_text_input = on_text_input
	handle.on_pointer = on_pointer
	handle.on_scroll_capture = on_scroll_capture
	handle.on_scroll = on_scroll
	handle.viewport_width = width
	handle.viewport_height = height
	handle.scale = scale
	handle.generation = sync.atomic_add(&test_handle_generation, 1)+1
	if handle.generation == 0 { handle.generation = sync.atomic_add(&test_handle_generation, 1)+1 }
	handle.runtime = new(alicorn.Runtime, allocator=allocator)
	if handle.runtime == nil {
		return {}, .Allocation_Failed
	}
	handle.runtime^ = alicorn.new_runtime(
		alicorn.Rect{0, 0, f32(width), f32(height)},
		alicorn.Runtime_Config{
			persistent_allocator=allocator,
			scratch_backing_allocator=allocator,
		},
	)
	_ = alicorn.set_presentation_scale(handle.runtime, scale, scale)
	if initialize != nil { initialize(rawptr(state), handle.runtime) }
	if !alicorn.text_engine_load_default_fonts(handle.runtime) {
		close(&handle)
		return {}, .Font_Initialization_Failed
	}
	status = run_descriptions(&handle, .Key, .Tab)
	handle.last_turn.input = .Key
	handle.last_turn.key = .Tab
	return handle, status
}

close :: proc(handle: ^Test_Handle($T)) {
	if handle == nil { return }
	if handle.runtime != nil {
		alicorn.destroy_runtime(handle.runtime)
		free(handle.runtime, allocator=handle.allocator)
	}
	handle^ = {}
}

describe_once :: proc(handle: ^Test_Handle($T)) -> bool {
	rt := handle.runtime
	ui, should_build := alicorn.begin_frame(rt)
	if !should_build { return false }
	root := alicorn.container_begin(
		&ui,
		.Root,
		label="ui-root",
		key=alicorn.key_string("alicorn.ui.root"),
		style=alicorn.layout_style(.Column, grow=1),
	)
	if root != 0 {
		handle.render(handle.state, &ui)
		alicorn.container_end(&ui)
		if handle.render_overlays != nil { handle.render_overlays(handle.state, &ui) }
	}
	alicorn.end_frame(&ui)
	handle.description_epoch += 1
	return true
}

run_descriptions :: proc(handle: ^Test_Handle($T), input: Input_Kind, key: Key) -> Status {
	handle.last_turn = Turn_Report{input=input, key=key}
	for pass := 0; pass < MAX_DESCRIPTIONS_PER_TURN; pass += 1 {
		if !handle.runtime.invalidated {
			handle.last_turn.stabilized = true
			break
		}
		if alicorn.motion_clock_set_time(handle.runtime, alicorn.Motion_Time(i64(handle.now_ns))) != .Ok {
			handle.last_turn.message = "virtual motion clock rejected the current harness timestamp"
			return .Invalid_Time
		}
		if !describe_once(handle) { break }
		handle.last_turn.descriptions += 1
	}
	handle.last_turn.layout_pending = alicorn.layout_is_pending(handle.runtime)
	handle.last_turn.focus = alicorn.focused_node(handle.runtime)
	if handle.runtime.invalidated {
		handle.last_turn.message = "bounded description limit reached; application invalidated during each corrective description"
		return .Did_Not_Stabilize
	}
	handle.last_turn.stabilized = true
	return .Ok
}

application_has_text_focus :: proc(handle: ^Test_Handle($T)) -> (focused, composing: bool) {
	rt := handle.runtime
	id := alicorn.focused_node(rt)
	info, ok := alicorn.node_info(rt, id)
	if !ok { return }
	focused = info.kind == .Text_Field || alicorn.text_input_target_is_active(rt, id)
	if info.kind == .Text_Field {
		interaction, interaction_ok := alicorn.text_field_interaction(rt, id)
		composing = interaction_ok && interaction.composition_active
	}
	composing = composing || handle.application_composition_owner == id
	return
}

map_application_key :: proc(key: Key) -> (mapped: alicorn.Application_Key, ok: bool) {
	switch key {
	case .Left: return .Left, true
	case .Right: return .Right, true
	case .Up: return .Up, true
	case .Down: return .Down, true
	case .Page_Up: return .Page_Up, true
	case .Page_Down: return .Page_Down, true
	case .Home: return .Home, true
	case .End: return .End, true
	case .Fit_Selection: return .Fit_Selection, true
	case .Command_1: return .Command_1, true
	case .Command_2: return .Command_2, true
	case .Command_3: return .Command_3, true
	case .Toggle: return .Toggle, true
	case .Space: return .Toggle, true
	case .Open_Repository: return .Open_Repository, true
	case .Open_Command_Palette: return .Open_Command_Palette, true
	case .Find: return .Find, true
	case .Workspace_Search: return .Workspace_Search, true
	case .Context_Menu: return .Context_Menu, true
	case .Workspace_Rename: return .Workspace_Rename, true
	case .Find_Next: return .Find_Next, true
	case .Find_Previous: return .Find_Previous, true
	case .Tab_Next: return .Tab_Next, true
	case .Tab_Previous: return .Tab_Previous, true
	case .Zoom_In: return .Zoom_In, true
	case .Zoom_Out: return .Zoom_Out, true
	case .Zoom_Reset: return .Zoom_Reset, true
	case .Escape: return .Escape, true
	case .Return: return .Return, true
	case .Backspace, .Delete, .Word_Left, .Word_Right, .Line_Start, .Line_End,
	     .Document_Start, .Document_End, .Delete_Word_Backward, .Delete_Word_Forward,
	     .Delete_Line_Backward, .Delete_Line_Forward:
		return {}, false
	case .Tab:
		return {}, false
	}
	return {}, false
}

map_context_menu_key :: proc(key: Key) -> alicorn.Context_Menu_Key {
	#partial switch key {
	case .Up: return .Up
	case .Down: return .Down
	case .Home: return .Home
	case .End: return .End
	case .Return, .Space: return .Activate
	case .Escape: return .Cancel
	case:
		return .Other
	}
}

application_text_key_event :: proc(
	key: Key,
	modifiers: alicorn.Input_Modifiers,
) -> (event: alicorn.Application_Text_Key_Event, ok: bool) {
	#partial switch key {
	case .Left: event.key = .Left
	case .Right: event.key = .Right
	case .Up: event.key = .Up
	case .Down: event.key = .Down
	case .Page_Up: event.key = .Page_Up
	case .Page_Down: event.key = .Page_Down
	case .Home: event.key = .Home
	case .End: event.key = .End
	case .Tab: event.key = .Tab
	case .Backspace: event.key = .Backspace
	case .Delete: event.key = .Delete
	case .Word_Left: event.key = .Word_Left
	case .Word_Right: event.key = .Word_Right
	case .Line_Start: event.key = .Line_Start
	case .Line_End: event.key = .Line_End
	case .Document_Start: event.key = .Document_Start
	case .Document_End: event.key = .Document_End
	case .Delete_Word_Backward: event.key = .Delete_Word_Backward
	case .Delete_Word_Forward: event.key = .Delete_Word_Forward
	case .Delete_Line_Backward: event.key = .Delete_Line_Backward
	case .Delete_Line_Forward: event.key = .Delete_Line_Forward
	case:
		return {}, false
	}
	event.shift = modifiers.shift
	event.control = modifiers.control
	event.alt = modifiers.alt
	event.super = modifiers.super
	return event, true
}

step :: proc(handle: ^Test_Handle($T), input: Input) -> Status {
	if handle == nil || handle.runtime == nil { return .Invalid_Application }
	rt := handle.runtime
	#partial switch input.kind {
	case .Key:
		context_key := map_context_menu_key(input.key)
		if alicorn.application_dispatch_overlay_key(
			rt,
			context_key,
			is_tab=input.key == .Tab,
			reverse_tab=input.modifiers.shift,
		) {
			// Alicorn's Select and context-menu overlays own input first.
		} else if input.key == .Tab {
			if input.modifiers.control {
				_ = alicorn.application_dispatch_tab_navigation(
					rt, rawptr(handle.state), handle.on_key, true, input.modifiers.shift,
				)
			} else {
				text_event := alicorn.Application_Text_Key_Event{
					key=.Tab,
					shift=input.modifiers.shift,
					control=input.modifiers.control,
					alt=input.modifiers.alt,
					super=input.modifiers.super,
				}
				if !alicorn.application_dispatch_text_key(rt, rawptr(handle.state), handle.on_text_key, text_event) {
					_ = alicorn.application_dispatch_tab_focus(rt, input.modifiers.shift)
				}
			}
		} else {
			text_focused, composing := application_has_text_focus(handle)
			app_key, mapped := map_application_key(input.key)
			if input.key == .Return && input.modifiers.shift && text_focused {
				app_key, mapped = .Find_Previous, true
			}
			handled := false
			application_key_offered := false
			if text_focused && mapped {
				application_key_offered = true
				handled = alicorn.application_dispatch_key(
					rt, rawptr(handle.state), handle.on_key, app_key, true, composing,
				)
			}
			if !handled {
				if text_event, text_key := application_text_key_event(input.key, input.modifiers); text_key {
					handled = alicorn.application_dispatch_text_key(
						rt, rawptr(handle.state), handle.on_text_key, text_event,
					)
				}
			}
			if !handled && input.key == .Return {
				if node, found := rt.nodes[rt.focused]; found && node.kind == .Text_Field {
					modified := input.modifiers.shift || input.modifiers.control ||
						input.modifiers.alt || input.modifiers.super
					if !input.repeat && !modified && !composing && !node.composition.active {
						handled = alicorn.text_field_request_submit(rt, node.id)
					}
				}
			}
			if !handled && text_focused {
				if node, found := rt.nodes[rt.focused]; found && node.kind == .Text_Field {
					if text_event, mapped := application_text_key_event(input.key, input.modifiers); mapped {
						result, change := alicorn.application_route_text_field_key(rt, node.id, text_event)
						if result == .Edit {
							alicorn.application_dispatch_text_change(rt, rawptr(handle.state), handle.on_text_change, change)
							handled = true
						} else {
							handled = result == .Navigation
						}
					}
				}
			}
			if !handled && input.key == .Escape && composing {
				if node, found := rt.nodes[rt.focused]; found && node.kind == .Text_Field {
					handled = alicorn.cancel_text_composition(rt, node.id, "Escape canceled headless text composition")
				} else if handle.application_composition_owner == rt.focused {
					handled = alicorn.application_dispatch_text_input(
						rt, rawptr(handle.state), handle.on_text_input, handle.application_composition_owner,
						alicorn.Application_Text_Input_Event{kind=.Cancel}, require_live_target=false,
					)
					handle.application_composition_owner = 0
				}
			}
			// Native routing offers focused controls first when no text input
			// owner has focus. Only then does the application see the key.
			if !handled && !text_focused && mapped {
				handled = alicorn.application_route_focused_control_key(rt, app_key)
			}
			if !handled && mapped && !application_key_offered {
				handled = alicorn.application_dispatch_key(rt, rawptr(handle.state), handle.on_key, app_key)
			}
		}
	case .Text_Commit:
		if alicorn.select_typeahead(rt, input.text) { break }
		id := alicorn.focused_node(rt)
		info, found := alicorn.node_info(rt, id)
		if !found { return .No_Focused_Element }
		if info.kind == .Text_Field {
			change := alicorn.process_text_input(rt, id, input.text)
			alicorn.application_dispatch_text_change(rt, rawptr(handle.state), handle.on_text_change, change)
		} else if alicorn.text_input_target_is_active(rt, id) {
			if !alicorn.application_dispatch_text_input(rt, rawptr(handle.state), handle.on_text_input, id,
				alicorn.Application_Text_Input_Event{kind=.Commit, text=input.text}) { return .Unsupported_Input }
			handle.application_composition_owner = 0
		} else {
			return .Unsupported_Input
		}
	case .Text_Preedit:
		id := alicorn.focused_node(rt)
		info, found := alicorn.node_info(rt, id)
		if !found { return .No_Focused_Element }
		if info.kind == .Text_Field {
			if !alicorn.process_text_editing(rt, id, input.text, input.composition_start_char, input.composition_length_char) {
				return .Unsupported_Input
			}
		} else if alicorn.text_input_target_is_active(rt, id) {
			event := alicorn.Application_Text_Input_Event{
				kind=.Preedit,
				text=input.text,
				selection_start_byte=input.selection_start_byte,
				selection_end_byte=input.selection_end_byte,
			}
			if len(input.text) == 0 { event.kind = .Cancel }
			if !alicorn.application_dispatch_text_input(rt, rawptr(handle.state), handle.on_text_input, id, event) {
				return .Unsupported_Input
			}
			handle.application_composition_owner = id if event.kind == .Preedit else 0
		} else {
			return .Unsupported_Input
		}
	case .Text_Cancel:
		id := alicorn.focused_node(rt)
		info, found := alicorn.node_info(rt, id)
		if found && info.kind == .Text_Field {
			_ = alicorn.cancel_text_composition(rt, id, "headless text composition canceled")
		} else {
			owner := handle.application_composition_owner
			if owner == 0 && found && alicorn.text_input_target_is_active(rt, id) { owner = id }
			if owner == 0 { return .Unsupported_Input }
			if !alicorn.application_dispatch_text_input(rt, rawptr(handle.state), handle.on_text_input, owner,
				alicorn.Application_Text_Input_Event{kind=.Cancel}, require_live_target=false) { return .Unsupported_Input }
			handle.application_composition_owner = 0
		}
	case .Pointer:
		event := input.pointer
		event.timestamp_ns = handle.now_ns
		target := alicorn.process_pointer(rt, event)
		if key, ok := alicorn.node_identity_key(rt, target); ok { event.target_key = key }
		handle.last_turn.pointer_target = target
		if !alicorn.context_menu_pointer_consumed(rt) {
			_ = alicorn.application_dispatch_pointer(rt, rawptr(handle.state), handle.on_pointer, event, target)
		}
	case .Scroll:
		event := input.scroll
		_ = alicorn.application_dispatch_scroll(rt, rawptr(handle.state), event, handle.on_scroll_capture, handle.on_scroll)
	case .Semantic_Action:
		if !alicorn.semantic_action_request(rt, input.semantic_id, input.semantic_action, text_value=input.semantic_text) {
			return .Unsupported_Input
		}
	case .Time_Advance:
		return advance_time(handle, input.delta_ns)
	}
	return run_descriptions(handle, input.kind, input.key)
}

// find queries only semantics published by the application/runtime. It does
// not manufacture accessible names from visual text. Every returned Element
// owns its strings and is safe to keep until destroy_element is called.
find :: proc(handle: ^Test_Handle($T), query: Query) -> (result: Find_Result) {
	if handle == nil || handle.runtime == nil {
		result.status = .Invalid_Application
		return
	}
	snapshot := alicorn.semantic_snapshot(handle.runtime, handle.allocator)
	defer alicorn.semantic_snapshot_destroy(&snapshot)
	for semantic in snapshot.nodes {
		if query.match_role && semantic.role != query.role { continue }
		if query.match_name && semantic.label != query.name { continue }
		if query.match_key {
			if semantic.visual_node == 0 { continue }
			key, key_ok := alicorn.node_identity_key(handle.runtime, semantic.visual_node)
			if !key_ok || !ui_keys_equal(key, query.key) { continue }
		}
		element, ok := element_from_semantic(handle, semantic)
		if !ok {
			destroy_element(&result.element)
			result.status = .Allocation_Failed
			result.match = .None
			return
		}
		switch result.match {
		case .None:
			result.match = .Unique
			result.element = element
		case .Unique:
			destroy_element(&result.element)
			destroy_element(&element)
			result.match = .Ambiguous
		case .Ambiguous:
			destroy_element(&element)
		}
	}
	return
}

ui_keys_equal :: proc(a, b: alicorn.UI_Key) -> bool {
	#partial switch left in a {
	case string:
		#partial switch right in b {
		case string: return left == right
		case: return false
		}
	case u64:
		#partial switch right in b {
		case u64: return left == right
		case: return false
		}
	case alicorn.UI_Key_Pair:
		#partial switch right in b {
		case alicorn.UI_Key_Pair: return left == right
		case: return false
		}
	case:
		return false
	}
	return false
}

element_from_semantic :: proc(handle: ^Test_Handle($T), semantic: alicorn.Semantic_Node) -> (element: Element, ok: bool) {
	element = Element{
		handle_generation=handle.generation,
		description_epoch=handle.description_epoch,
		semantic_id=semantic.id,
		role=semantic.role,
		states=semantic.states,
		actions=semantic.actions,
		visual_node=semantic.visual_node,
		bounds=semantic.bounds,
		has_bounds=semantic.has_bounds,
		allocator=handle.allocator,
	}
	clone_ok: bool
	element.name, clone_ok = clone_string(semantic.label, handle.allocator)
	if !clone_ok { destroy_element(&element); return {}, false }
	element.description, clone_ok = clone_string(semantic.description, handle.allocator)
	if !clone_ok { destroy_element(&element); return {}, false }
	element.value, clone_ok = clone_string(semantic.value, handle.allocator)
	if !clone_ok { destroy_element(&element); return {}, false }
	if semantic.visual_node != 0 {
		if info, found := alicorn.node_info(handle.runtime, semantic.visual_node); found {
			element.bounds = info.bounds
			element.hit_bounds = info.hit_bounds
			element.has_bounds = info.bounds.w > 0 && info.bounds.h > 0
			element.focused = info.focused
			element.scroll_viewport_bounds = info.scroll_viewport_bounds
			element.scroll_offset_x = info.scroll_offset_x
			element.scroll_offset_y = info.scroll_offset_y
			element.scroll_content_width = info.scroll_content_width
			element.scroll_content_height = info.scroll_content_height
			element.scroll_viewport_width = info.scroll_viewport_width
			element.scroll_viewport_height = info.scroll_viewport_height
			element.scroll_geometry_resolved = info.scroll_geometry_resolved
			if key, key_ok := alicorn.node_identity_key(handle.runtime, semantic.visual_node); key_ok {
				element.key, element.key_valid, clone_ok = clone_key(key, handle.allocator)
				if !clone_ok { destroy_element(&element); return {}, false }
			}
		}
	}
	return element, true
}

clone_string :: proc(value: string, allocator: mem.Allocator) -> (copy: string, ok: bool) {
	if len(value) == 0 { return "", true }
	cloned, err := strings.clone(value, allocator)
	return cloned, err == nil
}

clone_key :: proc(key: alicorn.UI_Key, allocator: mem.Allocator) -> (copy: alicorn.UI_Key, valid, ok: bool) {
	#partial switch value in key {
	case string:
		text, cloned := clone_string(value, allocator)
		if !cloned { return {}, false, false }
		return alicorn.key_string(text), true, true
	case u64:
		return alicorn.key_u64(value), true, true
	case alicorn.UI_Key_Pair:
		return alicorn.key_pair(value.first, value.second), true, true
	case:
		return {}, false, true
	}
}

destroy_element :: proc(element: ^Element) {
	if element == nil { return }
	if len(element.name) > 0 { delete(element.name, element.allocator) }
	if len(element.description) > 0 { delete(element.description, element.allocator) }
	if len(element.value) > 0 { delete(element.value, element.allocator) }
	if element.key_valid {
		#partial switch value in element.key {
		case string:
			if len(value) > 0 { delete(value, element.allocator) }
		case:
		}
	}
	element^ = {}
}

destroy_find_result :: proc(result: ^Find_Result) {
	if result == nil { return }
	destroy_element(&result.element)
	result^ = {}
}

// click uses the element's resolved bounds and verifies that the runtime's
// ordinary hit test currently targets that exact control. Logical virtual
// semantics without a realized rectangle are intentionally not clickable.
click :: proc(handle: ^Test_Handle($T), element: ^Element) -> Status {
	if handle == nil || handle.runtime == nil || element == nil { return .Invalid_Application }
	if element.handle_generation != handle.generation || element.description_epoch != handle.description_epoch {
		return .Stale_Snapshot
	}
	if !element.has_bounds || element.visual_node == 0 { return .Not_Realized }
	x := element.bounds.x + element.bounds.w*0.5
	y := element.bounds.y + element.bounds.h*0.5
	if alicorn.hit_test(handle.runtime, x, y) != element.visual_node { return .Not_Hit_Testable }
	status := step(handle, Input{kind=.Pointer, pointer=alicorn.Pointer_Event{kind=.Down, x=x, y=y, button=alicorn.POINTER_BUTTON_PRIMARY}})
	if status != .Ok {
		_ = step(handle, Input{kind=.Pointer, pointer=alicorn.Pointer_Event{kind=.Cancel}})
		return status
	}
	status = step(handle, Input{kind=.Pointer, pointer=alicorn.Pointer_Event{kind=.Up, x=x, y=y, button=alicorn.POINTER_BUTTON_PRIMARY}})
	if status != .Ok {
		_ = step(handle, Input{kind=.Pointer, pointer=alicorn.Pointer_Event{kind=.Cancel}})
	}
	return status
}

click_at :: proc(handle: ^Test_Handle($T), x, y: f32, button := alicorn.POINTER_BUTTON_PRIMARY) -> Status {
	if handle == nil || handle.runtime == nil { return .Invalid_Application }
	status := step(handle, Input{kind=.Pointer, pointer=alicorn.Pointer_Event{kind=.Down, x=x, y=y, button=button}})
	if status != .Ok {
		_ = step(handle, Input{kind=.Pointer, pointer=alicorn.Pointer_Event{kind=.Cancel}})
		return status
	}
	status = step(handle, Input{kind=.Pointer, pointer=alicorn.Pointer_Event{kind=.Up, x=x, y=y, button=button}})
	if status != .Ok {
		_ = step(handle, Input{kind=.Pointer, pointer=alicorn.Pointer_Event{kind=.Cancel}})
	}
	return status
}

// advance_time moves an explicit monotonic virtual clock by nanoseconds. It
// runs due retained motion once, then performs only bounded corrective
// descriptions; it never sleeps or auto-advances until the app settles.
advance_time :: proc(handle: ^Test_Handle($T), delta_ns: u64) -> Status {
	if handle == nil || handle.runtime == nil { return .Invalid_Application }
	if delta_ns > 0x7fffffffffffffff-u64(handle.now_ns) { return .Invalid_Time }
	handle.now_ns += delta_ns
	if alicorn.motion_clock_set_time(handle.runtime, alicorn.Motion_Time(i64(handle.now_ns))) != .Ok {
		return .Invalid_Time
	}
	tick := alicorn.motion_tick(handle.runtime, alicorn.Motion_Time(i64(handle.now_ns)))
	if tick.status != .Ok {
		handle.last_turn = Turn_Report{
			input=.Time_Advance,
			stabilized=false,
			message=fmt.tprintf("retained motion tick failed: %v", tick.status),
		}
		return .Motion_Failure
	}
	return run_descriptions(handle, .Time_Advance, .Tab)
}

last_turn :: proc(handle: ^Test_Handle($T)) -> Turn_Report {
	if handle == nil { return Turn_Report{message="invalid test handle"} }
	return handle.last_turn
}

last_turn_diagnostic :: proc(handle: ^Test_Handle($T)) -> string {
	if handle == nil { return "invalid test handle" }
	r := handle.last_turn
	return fmt.tprintf(
		"input=%v key=%v descriptions=%d stabilized=%v layout_pending=%v focus=%d pointer_target=%d %s",
		r.input, r.key, r.descriptions, r.stabilized, r.layout_pending, r.focus, r.pointer_target, r.message,
	)
}
