package alicorn

// Application_Key is Alicorn's platform-neutral command vocabulary. Native
// hosts translate platform events into these values; headless hosts can use
// the same dispatch policy without importing a windowing backend.
Application_Key :: enum {
	Left,
	Right,
	Up,
	Down,
	Page_Up,
	Page_Down,
	Home,
	End,
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
	Escape,
	Return,
}

Application_Key_Proc :: proc(state: rawptr, rt: ^Runtime, key: Application_Key) -> bool
Application_Text_Change_Proc :: proc(state: rawptr, rt: ^Runtime, change: Text_Change)
Application_Text_Input_Event_Kind :: enum { Commit, Preedit, Cancel }
// Application_Text_Input_Event text is borrowed for the callback. Preedit
// selection offsets are UTF-8 byte offsets, matching the native application
// contract after SDL character indexes are normalized by the host.
Application_Text_Input_Event :: struct {
	kind: Application_Text_Input_Event_Kind,
	text: string,
	selection_start_byte, selection_end_byte: int,
}
Application_Text_Input_Proc :: proc(
	state: rawptr,
	rt: ^Runtime,
	owner: Node_ID,
	event: Application_Text_Input_Event,
)
Application_Pointer_Proc :: proc(state: rawptr, rt: ^Runtime, event: Pointer_Event, target: Node_ID)

// Interaction_Key_Set and Interaction_Pointer_Set describe the input a
// retained interaction scope wants Alicorn to route to it. Keys and pointers
// are delivered once to the next application description, where the component
// still has access to the current application-owned data projection.
Interaction_Key_Set :: bit_set[Application_Key; u64]
Interaction_Pointer_Kind :: enum { Primary_Down, Secondary_Down }
Interaction_Pointer_Set :: bit_set[Interaction_Pointer_Kind; u8]

Interaction_Text_Change_Proc :: proc(state: rawptr, rt: ^Runtime, change: Text_Change) -> bool
Interaction_After_Frame_Proc :: proc(state: rawptr, rt: ^Runtime)

// Interaction_Scope_Options are registered during a description. The owner
// should be a stable retained ancestor of the component's focusable nodes.
// A modal scope receives matching input before focused scopes. A composition
// yield key remains with the native text host while IME composition is active.
Interaction_Scope_Options :: struct {
	keys: Interaction_Key_Set,
	composition_yield_keys: Interaction_Key_Set,
	pointers: Interaction_Pointer_Set,
	modal: bool,
	on_text_change: Interaction_Text_Change_Proc,
}

Interaction_Event_Kind :: enum { Key, Pointer }
Interaction_Event :: struct {
	kind: Interaction_Event_Kind,
	key: Application_Key,
	pointer: Pointer_Event,
	target: Node_ID,
}
Application_Scroll_Capture_Proc :: proc(state: rawptr, rt: ^Runtime, event: Scroll_Event, target: Node_ID) -> bool
Application_Scroll_Proc :: proc(state: rawptr, rt: ^Runtime, event: Scroll_Event)

// Application_Text_Navigation_Key is a host-normalized editing intent. SDL
// hosts translate platform conventions; synthetic input can produce the same
// event directly.
Application_Text_Navigation_Key :: enum {
	Left, Right, Home, End, Up, Down, Page_Up, Page_Down, Backspace, Delete, Tab,
	Word_Left, Word_Right, Line_Start, Line_End, Document_Start, Document_End,
	Delete_Word_Backward, Delete_Word_Forward, Delete_Line_Backward, Delete_Line_Forward,
}

Application_Text_Key_Event :: struct {
	key: Application_Text_Navigation_Key,
	shift, control, alt, super: bool,
}

Application_Text_Key_Proc :: proc(
	state: rawptr,
	rt: ^Runtime,
	owner: Node_ID,
	event: Application_Text_Key_Event,
) -> bool

Application_Text_Field_Key_Result :: enum { Unhandled, Navigation, Edit }

application_key_can_preempt_text_field :: proc(key: Application_Key, composition_active := false) -> bool {
	if key == .Escape && composition_active { return false }
	if key == .Workspace_Rename && composition_active { return false }
	if composition_active && (key == .Zoom_In || key == .Zoom_Out || key == .Zoom_Reset) { return false }
	#partial switch key {
	case .Up, .Down, .Page_Up, .Page_Down, .Open_Repository, .Open_Command_Palette,
	     .Find, .Workspace_Search, .Workspace_Rename, .Context_Menu, .Find_Next, .Find_Previous,
	     .Tab_Next, .Tab_Previous, .Zoom_In, .Zoom_Out, .Zoom_Reset, .Escape, .Return:
		return true
	case:
		return false
	}
}

// application_dispatch_key shares the native host's rule for offering a
// translated command to application state. A focused text owner keeps keys
// unless the command is explicitly allowed to preempt it. Composition state
// is supplied by the host because native IME state may outlive runtime preedit.
application_dispatch_key :: proc(
	rt: ^Runtime,
	state: rawptr,
	callback: Application_Key_Proc,
	key: Application_Key,
	text_input_focused := false,
	composition_active := false,
) -> bool {
	if rt == nil { return false }
	if text_input_focused && !application_key_can_preempt_text_field(key, composition_active) { return false }
	if interaction_scope_dispatch_key(rt, key, composition_active) { return true }
	if callback == nil { return false }
	if !callback(state, rt, key) { return false }
	reason := "application keyboard command"
	if text_input_focused { reason = "application handled focused text-field key" }
	invalidate_root(rt, reason)
	return true
}

// application_dispatch_tab_navigation handles the host-independent part of
// Control+Tab document navigation. Ctrl+Tab is consumed even when the app has
// no document navigation callback, matching the native host's no-op policy.
application_dispatch_tab_navigation :: proc(
	rt: ^Runtime,
	state: rawptr,
	callback: Application_Key_Proc,
	control, shift: bool,
) -> bool {
	if !control { return false }
	if rt == nil { return true }
	key := Application_Key.Tab_Next
	if shift { key = .Tab_Previous }
	if callback != nil && callback(state, rt, key) {
		invalidate_root(rt, "application handled Control+Tab document navigation")
	}
	return true
}

// application_dispatch_tab_focus gives a generic text-input owner first
// refusal, then uses Alicorn's ordinary retained focus traversal. Native
// adapters may invoke their platform-specific text-key callback first.
application_dispatch_tab_focus :: proc(rt: ^Runtime, shift: bool) -> bool {
	if rt == nil { return false }
	direction := Focus_Direction.Next
	if shift { direction = .Previous }
	return focus_traverse(rt, direction) != 0
}

// application_dispatch_overlay_key shares keyboard ownership for Alicorn's
// transient Select and context-menu overlays. Native hosts translate physical
// keys to Context_Menu_Key; headless hosts supply the same logical value.
application_dispatch_overlay_key :: proc(
	rt: ^Runtime,
	key: Context_Menu_Key,
	is_tab := false,
	reverse_tab := false,
) -> bool {
	if rt == nil { return false }
	if is_tab && select_wants_text_input(rt) {
		return select_handle_tab(rt, reverse_tab)
	}
	select_handled := select_handle_key(rt, key)
	return select_handled || context_menu_handle_key(rt, key)
}

// application_route_focused_control_key is shared by native and headless
// hosts after text and transient overlay routing has declined the key.
application_route_focused_control_key :: proc(rt: ^Runtime, key: Application_Key) -> bool {
	#partial switch key {
	case .Toggle: return activate_focused(rt, .Space)
	case .Return: return activate_focused(rt, .Enter)
	case .Left, .Down: return adjust_focused_slider(rt, -1)
	case .Right, .Up: return adjust_focused_slider(rt, 1)
	case .Home: return set_focused_slider_bound(rt, .Minimum)
	case .End: return set_focused_slider_bound(rt, .Maximum)
	case:
		return false
	}
}

// application_dispatch_text_key routes editing intent only to an active
// generic text-input owner. Built-in Text_Field controls retain their own
// interaction path and are intentionally excluded, as in the SDL host.
application_dispatch_text_key :: proc(
	rt: ^Runtime,
	state: rawptr,
	callback: Application_Text_Key_Proc,
	event: Application_Text_Key_Event,
) -> bool {
	if rt == nil || callback == nil { return false }
	owner := rt.focused
	node, found := rt.nodes[owner]
	if !found || !node.active || node.kind == .Text_Field || !text_input_target_is_active(rt, owner) { return false }
	if !callback(state, rt, owner, event) { return false }
	invalidate_root(rt, "application handled focused text key")
	return true
}

// application_route_text_field_key applies the host-normalized editing intent
// to a built-in Text_Field after application callbacks decline it. Native and
// headless hosts use this same path so caret, selection, and deletion behavior
// stays aligned.
application_route_text_field_key :: proc(
	rt: ^Runtime,
	owner: Node_ID,
	event: Application_Text_Key_Event,
) -> (result: Application_Text_Field_Key_Result, change: Text_Change) {
	if rt == nil || owner == 0 || owner != rt.focused { return .Unhandled, {} }
	field, found := rt.nodes[owner]
	if !found || !field.active || field.kind != .Text_Field || field.composition.active { return .Unhandled, {} }

	command: Text_Command
	#partial switch event.key {
	case .Backspace: command = .Delete_Backward
	case .Delete: command = .Delete_Forward
	case .Delete_Word_Backward: command = .Delete_Word_Backward
	case .Delete_Word_Forward: command = .Delete_Word_Forward
	case:
		command = .Move_Left
	}
	#partial switch event.key {
	case .Backspace, .Delete, .Delete_Word_Backward, .Delete_Word_Forward:
		return .Edit, process_text_command(rt, owner, command)
	case:
	}

	selection_nonempty := field.selection_anchor.byte != field.selection_focus.byte
	target := field.caret.byte
	shift := event.shift
	#partial switch event.key {
	case .Left, .Right, .Word_Left, .Word_Right:
		direction := -1 if event.key == .Left || event.key == .Word_Left else 1
		if !shift && selection_nonempty {
			target = field.selection_anchor.byte if direction < 0 else field.selection_focus.byte
			if field.selection_anchor.byte > field.selection_focus.byte {
				target = field.selection_focus.byte if direction < 0 else field.selection_anchor.byte
			}
		} else if !shift {
			is_word := event.key == .Word_Left || event.key == .Word_Right
			command = .Move_Left if direction < 0 else .Move_Right
			if is_word { command = .Move_Word_Left if direction < 0 else .Move_Word_Right }
			return .Navigation, process_text_command(rt, owner, command)
		} else if event.key == .Word_Left || event.key == .Word_Right {
			target_position := text_move_word(
				field.text,
				Text_Position{target, .Leading},
				direction,
				rt.scratch_allocator,
			)
			target = target_position.byte
		} else {
			target_position := text_move_logical(field.text, Text_Position{target, .Leading}, direction)
			target = target_position.byte
		}
	case .Line_Start: target = 0
	case .Line_End: target = len(field.text)
	case .Home, .Document_Start: target = 0
	case .End, .Document_End: target = len(field.text)
	case:
		return .Unhandled, {}
	}
	if shift {
		_ = set_text_selection(rt, owner, field.selection_anchor.byte, target)
	} else {
		_ = set_text_caret(rt, owner, target)
	}
	return .Navigation, {}
}

application_dispatch_text_change :: proc(
	rt: ^Runtime,
	state: rawptr,
	callback: Application_Text_Change_Proc,
	change: Text_Change,
) {
	if rt == nil { return }
	if !interaction_scope_dispatch_text_change(rt, change) && callback != nil {
		callback(state, rt, change)
	}
	owned_change := change
	text_change_destroy(rt, &owned_change)
}

// application_dispatch_text_input shares delivery for generic application
// text-input targets. Event text is borrowed for the callback; accepted
// events invalidate the application description just as native SDL delivery
// does. Lifecycle cancellation may explicitly allow an owner that was just
// suspended or omitted from the latest description.
application_dispatch_text_input :: proc(
	rt: ^Runtime,
	state: rawptr,
	callback: Application_Text_Input_Proc,
	owner: Node_ID,
	event: Application_Text_Input_Event,
	require_live_target := true,
) -> bool {
	if rt == nil || callback == nil || owner == 0 { return false }
	if require_live_target && !text_input_target_is_active(rt, owner) { return false }
	callback(state, rt, owner, event)
	reason := "application text input"
	#partial switch event.kind {
	case .Preedit: reason = "application text preedit"
	case .Cancel: reason = "application text composition canceled"
	}
	invalidate_root(rt, reason)
	return true
}

// Call only after host-specific arbitration has decided that application
// pointer input is not blocked by a native overlay or drag session.
application_dispatch_pointer :: proc(
	rt: ^Runtime,
	state: rawptr,
	callback: Application_Pointer_Proc,
	event: Pointer_Event,
	target: Node_ID,
) -> bool {
	if rt == nil { return false }
	handled := interaction_scope_dispatch_pointer(rt, event, target)
	if !handled && callback != nil {
		callback(state, rt, event, target)
		handled = true
	}
	if !handled { return false }
	// Application pointer handlers may mutate app state even when hit testing
	// intentionally produced no retained target.
	if event.kind == .Down || event.kind == .Up {
		invalidate_root(rt, "application pointer callback")
	}
	return true
}

application_dispatch_scroll :: proc(
	rt: ^Runtime,
	state: rawptr,
	event: Scroll_Event,
	capture: Application_Scroll_Capture_Proc,
	fallback: Application_Scroll_Proc,
) -> bool {
	if rt == nil { return false }
	target := scroll_region_hit_test(rt, event.x, event.y)
	if target != 0 && capture != nil && capture(state, rt, event, target) { return true }
	if process_scroll(rt, event) { return true }
	if fallback == nil { return false }
	fallback(state, rt, event)
	return true
}
