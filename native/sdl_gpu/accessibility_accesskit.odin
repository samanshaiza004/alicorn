package alicorn_sdl_gpu

import "core:c"
import libc "core:c/libc"
import "base:runtime"
import "core:strings"
import alicorn "../../runtime"
import "vendor:sdl3"

when ODIN_OS == .Windows || ODIN_OS == .Darwin {
	when ODIN_OS == .Windows {
		foreign import accesskit "system:accesskit.lib"
	} else when ODIN_OS == .Darwin {
		foreign import accesskit "system:accesskit"
	}

	AccessKit_Tree_Update_Factory :: proc "c" (userdata: rawptr) -> rawptr
	AccessKit_Activation_Callback :: proc "c" (userdata: rawptr) -> rawptr
	AccessKit_Action_Callback :: proc "c" (request, userdata: rawptr)

	AccessKit_Rect :: struct {
		x0, y0, x1, y1: f64,
	}
	#assert(size_of(AccessKit_Rect) == 32)
	#assert(align_of(AccessKit_Rect) == 8)

	AccessKit_Action_Data :: struct {
		tag: c.int,
		padding: c.int,
		// The largest C union arm is accesskit_text_selection (two 16-byte
		// positions), so preserve the full 32-byte payload and its alignment.
		value: [4]u64,
	}

	AccessKit_Optional_Action_Data :: struct {
		has_value: bool,
		padding: [7]u8,
		value: AccessKit_Action_Data,
	}

	AccessKit_Action_Request :: struct {
		action: u8,
		target_tree: [16]u8,
		target_node: u64,
		data: AccessKit_Optional_Action_Data,
	}

	#assert(offset_of(AccessKit_Action_Request, target_node) == 24)
	#assert(offset_of(AccessKit_Action_Request, data) == 32)
	#assert(offset_of(AccessKit_Action_Data, value) == 8)
	#assert(size_of(AccessKit_Action_Data) == 40)
	#assert(align_of(AccessKit_Action_Data) == 8)
	#assert(size_of(AccessKit_Optional_Action_Data) == 48)
	#assert(size_of(AccessKit_Action_Request) == 80)

	foreign accesskit {
		accesskit_node_new :: proc "c" (role: u8) -> rawptr ---
		accesskit_node_free :: proc "c" (node: rawptr) ---
		accesskit_node_push_child :: proc "c" (node: rawptr, item: u64) ---
		accesskit_node_add_action :: proc "c" (node: rawptr, action: u8) ---
		accesskit_node_set_label_with_length :: proc "c" (node: rawptr, value: rawptr, length: uint) ---
		accesskit_node_set_description_with_length :: proc "c" (node: rawptr, value: rawptr, length: uint) ---
		accesskit_node_set_value_with_length :: proc "c" (node: rawptr, value: rawptr, length: uint) ---
		accesskit_node_set_bounds :: proc "c" (node: rawptr, value: AccessKit_Rect) ---
		accesskit_node_set_disabled :: proc "c" (node: rawptr) ---
		accesskit_node_set_required :: proc "c" (node: rawptr) ---
		accesskit_node_set_read_only :: proc "c" (node: rawptr) ---
		accesskit_node_set_expanded :: proc "c" (node: rawptr, value: bool) ---
		accesskit_node_set_selected :: proc "c" (node: rawptr, value: bool) ---
		accesskit_node_set_toggled :: proc "c" (node: rawptr, value: u8) ---
		accesskit_node_set_invalid :: proc "c" (node: rawptr, value: u8) ---
		accesskit_node_set_busy :: proc "c" (node: rawptr) ---
		accesskit_node_set_aria_current :: proc "c" (node: rawptr, value: u8) ---
		accesskit_node_set_size_of_set :: proc "c" (node: rawptr, value: uint) ---
		accesskit_node_set_position_in_set :: proc "c" (node: rawptr, value: uint) ---
		accesskit_node_set_numeric_value :: proc "c" (node: rawptr, value: f64) ---
		accesskit_node_set_min_numeric_value :: proc "c" (node: rawptr, value: f64) ---
		accesskit_node_set_max_numeric_value :: proc "c" (node: rawptr, value: f64) ---
		accesskit_node_set_numeric_value_step :: proc "c" (node: rawptr, value: f64) ---
		accesskit_tree_info_new :: proc "c" (root: u64) -> rawptr ---
		accesskit_tree_info_set_toolkit_name_with_length :: proc "c" (tree: rawptr, value: rawptr, length: uint) ---
		accesskit_tree_info_set_toolkit_version_with_length :: proc "c" (tree: rawptr, value: rawptr, length: uint) ---
		accesskit_tree_info_free :: proc "c" (tree: rawptr) ---
		accesskit_tree_update_with_capacity_and_focus :: proc "c" (capacity: uint, focus: u64) -> rawptr ---
		accesskit_tree_update_free :: proc "c" (update: rawptr) ---
		accesskit_tree_update_push_node :: proc "c" (update: rawptr, id: u64, node: rawptr) ---
		accesskit_tree_update_set_tree_info :: proc "c" (update: rawptr, tree: rawptr) ---
		accesskit_action_request_free :: proc "c" (request: rawptr) ---
	}
}

when ODIN_OS == .Windows {
	foreign accesskit {
		accesskit_windows_subclassing_adapter_new :: proc "c" (
			hwnd: rawptr,
			activation: AccessKit_Activation_Callback,
			activation_userdata: rawptr,
			action: AccessKit_Action_Callback,
			action_userdata: rawptr,
		) -> rawptr ---
		accesskit_windows_subclassing_adapter_free :: proc "c" (adapter: rawptr) ---
		accesskit_windows_subclassing_adapter_update_if_active :: proc "c" (
			adapter: rawptr,
			factory: AccessKit_Tree_Update_Factory,
			userdata: rawptr,
		) -> rawptr ---
		accesskit_windows_queued_events_raise :: proc "c" (events: rawptr) ---
	}
}

when ODIN_OS == .Darwin {
	foreign accesskit {
		accesskit_macos_add_focus_forwarder_to_window_class :: proc "c" (class_name: cstring) ---
		accesskit_macos_subclassing_adapter_for_window :: proc "c" (
			window: rawptr,
			activation: AccessKit_Activation_Callback,
			activation_userdata: rawptr,
			action: AccessKit_Action_Callback,
			action_userdata: rawptr,
		) -> rawptr ---
		accesskit_macos_subclassing_adapter_free :: proc "c" (adapter: rawptr) ---
		accesskit_macos_subclassing_adapter_update_if_active :: proc "c" (
			adapter: rawptr,
			factory: AccessKit_Tree_Update_Factory,
			userdata: rawptr,
		) -> rawptr ---
		accesskit_macos_subclassing_adapter_update_view_focus_state :: proc "c" (adapter: rawptr, focused: bool) -> rawptr ---
		accesskit_macos_queued_events_raise :: proc "c" (events: rawptr) ---
	}
}

ACCESSKIT_ACTION_CLICK :: u8(0)
ACCESSKIT_ACTION_FOCUS :: u8(1)
ACCESSKIT_ACTION_COLLAPSE :: u8(3)
ACCESSKIT_ACTION_EXPAND :: u8(4)
ACCESSKIT_ACTION_HIDE_TOOLTIP :: u8(8)
ACCESSKIT_ACTION_DECREMENT :: u8(6)
ACCESSKIT_ACTION_INCREMENT :: u8(7)
ACCESSKIT_ACTION_SCROLL_DOWN :: u8(11)
ACCESSKIT_ACTION_SCROLL_UP :: u8(14)
ACCESSKIT_ACTION_SCROLL_INTO_VIEW :: u8(15)
ACCESSKIT_ACTION_SET_VALUE :: u8(20)

ACCESSKIT_ACTION_DATA_VALUE :: c.int(1)
ACCESSKIT_ACTION_DATA_NUMERIC_VALUE :: c.int(2)

ACCESSKIT_ROLE_UNKNOWN :: u8(0)
ACCESSKIT_ROLE_LABEL :: u8(3)
ACCESSKIT_ROLE_LIST_ITEM :: u8(7)
ACCESSKIT_ROLE_MENU_ITEM :: u8(11)
ACCESSKIT_ROLE_TREE_ITEM :: u8(9)
ACCESSKIT_ROLE_GENERIC_CONTAINER :: u8(14)
ACCESSKIT_ROLE_CHECK_BOX :: u8(15)
ACCESSKIT_ROLE_TEXT_INPUT :: u8(17)
ACCESSKIT_ROLE_BUTTON :: u8(18)
ACCESSKIT_ROLE_LIST :: u8(24)
ACCESSKIT_ROLE_DIALOG :: u8(66)
ACCESSKIT_ROLE_GROUP :: u8(78)
ACCESSKIT_ROLE_SCROLL_VIEW :: u8(108)
ACCESSKIT_ROLE_SLIDER :: u8(113)
ACCESSKIT_ROLE_TAB :: u8(120)
ACCESSKIT_ROLE_TAB_LIST :: u8(121)
ACCESSKIT_ROLE_TAB_PANEL :: u8(122)
ACCESSKIT_ROLE_MENU :: u8(30)
ACCESSKIT_ROLE_MULTILINE_TEXT_INPUT :: u8(31)
ACCESSKIT_ROLE_TREE :: u8(129)
ACCESSKIT_ROLE_TOOLTIP :: u8(128)
ACCESSKIT_ROLE_WINDOW :: u8(133)

ACCESSKIT_TOGGLED_FALSE :: u8(0)
ACCESSKIT_TOGGLED_TRUE :: u8(1)

NATIVE_ACCESSIBILITY_ACTION_QUEUE_CAPACITY :: 64
NATIVE_ACCESSIBILITY_ACTION_TEXT_LIMIT :: 1 << 20

Native_Accessibility_Queued_Action :: struct {
	semantic_id: alicorn.Semantic_ID,
	action: alicorn.Semantic_Action,
	text_pointer: rawptr,
	text_length: int,
	numeric_value: f64,
	has_numeric_value: bool,
}

Native_Accessibility_Counters :: struct {
	activation_wakes: u64,
	updates_submitted: u64,
	actions_received: u64,
	actions_dropped: u64,
}

Native_Accessibility_Host :: struct {
	adapter: rawptr,
	mutex: ^sdl3.Mutex,
	callback_condition: ^sdl3.Condition,
	callbacks_in_flight: int,
	host_waker: ^Native_Host_Event_Waker,
	projection: Accessibility_Projection,
	projection_ready: bool,
	adapter_revision: u64,
	content_inset_top: f32,
	actions: []Native_Accessibility_Queued_Action,
	action_read: int,
	action_write: int,
	action_count: int,
	counters: Native_Accessibility_Counters,
	active: bool,
}

native_accessibility_host_init :: proc(host: ^Native_Accessibility_Host, waker: ^Native_Host_Event_Waker) -> bool {
	if host == nil { return false }
	host.mutex = sdl3.CreateMutex()
	if host.mutex == nil { return false }
	host.callback_condition = sdl3.CreateCondition()
	if host.callback_condition == nil {
		sdl3.DestroyMutex(host.mutex)
		host.mutex = nil
		return false
	}
	host.actions = make([]Native_Accessibility_Queued_Action, NATIVE_ACCESSIBILITY_ACTION_QUEUE_CAPACITY)
	host.host_waker = waker
	host.active = true
	return true
}

native_accessibility_host_destroy :: proc(host: ^Native_Accessibility_Host) {
	if host == nil { return }
	native_accessibility_host_shutdown(host)
	if host.mutex != nil {
		sdl3.LockMutex(host.mutex)
		for host.action_count > 0 {
			event := host.actions[host.action_read]
			host.actions[host.action_read] = {}
			host.action_read = (host.action_read+1)%len(host.actions)
			host.action_count -= 1
			if event.text_pointer != nil { libc.free(event.text_pointer) }
		}
		sdl3.UnlockMutex(host.mutex)
		sdl3.DestroyMutex(host.mutex)
		host.mutex = nil
	}
	if len(host.actions) > 0 { delete(host.actions) }
	if host.callback_condition != nil {
		sdl3.DestroyCondition(host.callback_condition)
		host.callback_condition = nil
	}
	accessibility_projection_destroy(&host.projection)
	host^ = Native_Accessibility_Host{}
}

native_accessibility_host_shutdown :: proc(host: ^Native_Accessibility_Host) {
	if host == nil { return }
	if host.mutex != nil {
		sdl3.LockMutex(host.mutex)
		host.active = false
		sdl3.UnlockMutex(host.mutex)
	} else {
		host.active = false
	}
	if host.adapter != nil {
		when ODIN_OS == .Windows {
			accesskit_windows_subclassing_adapter_free(host.adapter)
		} else when ODIN_OS == .Darwin {
			accesskit_macos_subclassing_adapter_free(host.adapter)
		}
		host.adapter = nil
	}
	if host.mutex != nil && host.callback_condition != nil {
		sdl3.LockMutex(host.mutex)
		for host.callbacks_in_flight > 0 {
			sdl3.WaitCondition(host.callback_condition, host.mutex)
		}
		sdl3.UnlockMutex(host.mutex)
	}
	if host.host_waker != nil { host.host_waker.active = false }
}

native_accessibility_callback_enter :: proc(host: ^Native_Accessibility_Host) -> bool {
	if host == nil || host.mutex == nil { return false }
	sdl3.LockMutex(host.mutex)
	if !host.active {
		sdl3.UnlockMutex(host.mutex)
		return false
	}
	host.callbacks_in_flight += 1
	sdl3.UnlockMutex(host.mutex)
	return true
}

native_accessibility_callback_leave :: proc(host: ^Native_Accessibility_Host) {
	if host == nil || host.mutex == nil { return }
	sdl3.LockMutex(host.mutex)
	host.callbacks_in_flight -= 1
	if !host.active && host.callbacks_in_flight == 0 && host.callback_condition != nil {
		sdl3.SignalCondition(host.callback_condition)
	}
	sdl3.UnlockMutex(host.mutex)
}

native_accessibility_action_to_semantic :: proc(action: u8, node: Accessibility_Projection_Node) -> (alicorn.Semantic_Action, bool, bool) {
	// The final bool identifies ScrollIntoView, which is a reveal request rather
	// than an action. Select is represented by AccessKit Click on Tab nodes.
	switch action {
	case ACCESSKIT_ACTION_CLICK:
		if accessibility_projection_action_has(node.actions, .Press) { return .Press, false, true }
		if accessibility_projection_action_has(node.actions, .Select) { return .Select, false, true }
	case ACCESSKIT_ACTION_FOCUS:
		if accessibility_projection_action_has(node.actions, .Focus) { return .Focus, false, true }
	case ACCESSKIT_ACTION_SET_VALUE:
		if accessibility_projection_action_has(node.actions, .Set_Value) { return .Set_Value, false, true }
	case ACCESSKIT_ACTION_INCREMENT:
		if accessibility_projection_action_has(node.actions, .Increment) { return .Increment, false, true }
	case ACCESSKIT_ACTION_DECREMENT:
		if accessibility_projection_action_has(node.actions, .Decrement) { return .Decrement, false, true }
	case ACCESSKIT_ACTION_EXPAND:
		if accessibility_projection_action_has(node.actions, .Expand) { return .Expand, false, true }
	case ACCESSKIT_ACTION_COLLAPSE:
		if accessibility_projection_action_has(node.actions, .Collapse) { return .Collapse, false, true }
	case ACCESSKIT_ACTION_SCROLL_INTO_VIEW:
		if accessibility_projection_action_has(node.actions, .Scroll_Into_View) { return .Scroll_Into_View, true, true }
	}
	return .None, false, false
}

when ODIN_OS == .Windows || ODIN_OS == .Darwin {
native_accessibility_action_callback :: proc "c" (request_pointer, userdata: rawptr) {
	context = runtime.default_context()
	if request_pointer == nil { return }
	request := cast(^AccessKit_Action_Request)request_pointer
	host := cast(^Native_Accessibility_Host)userdata
	if !native_accessibility_callback_enter(host) {
		accesskit_action_request_free(request_pointer)
		return
	}
	defer native_accessibility_callback_leave(host)

	// The current semantic projection owns this mapping. It is bounded by the
	// exported working set and is read only under the same mutex as publication.
	sdl3.LockMutex(host.mutex)
	node, found := native_accessibility_semantic_for_node(host, request.target_node)
	if !found {
		host.counters.actions_dropped += 1
		sdl3.UnlockMutex(host.mutex)
		accesskit_action_request_free(request_pointer)
		return
	}
	action, reveal, supported := native_accessibility_action_to_semantic(request.action, node)
	if !supported || host.action_count >= len(host.actions) {
		host.counters.actions_dropped += 1
		sdl3.UnlockMutex(host.mutex)
		accesskit_action_request_free(request_pointer)
		return
	}
	queued := Native_Accessibility_Queued_Action{semantic_id=node.semantic_id, action=action}
	if action == .Set_Value && request.data.has_value {
		if request.data.value.tag == ACCESSKIT_ACTION_DATA_VALUE {
			if node.role != .Text_Input && node.role != .Text_Area {
				host.counters.actions_dropped += 1
				sdl3.UnlockMutex(host.mutex)
				accesskit_action_request_free(request_pointer)
				return
			}
			// AccessKit's Value union arm contains a borrowed char pointer. Copy
			// it before freeing the action request at the end of this callback.
			text := transmute(cstring)request.data.value.value[0]
			if text == nil {
				host.counters.actions_dropped += 1
				sdl3.UnlockMutex(host.mutex)
				accesskit_action_request_free(request_pointer)
				return
			}
			length := native_accessibility_cstring_length(text, NATIVE_ACCESSIBILITY_ACTION_TEXT_LIMIT)
			if length == NATIVE_ACCESSIBILITY_ACTION_TEXT_LIMIT {
				host.counters.actions_dropped += 1
				sdl3.UnlockMutex(host.mutex)
				accesskit_action_request_free(request_pointer)
				return
			}
			copy := libc.malloc(uint(length))
			if length > 0 && copy == nil {
				host.counters.actions_dropped += 1
				sdl3.UnlockMutex(host.mutex)
				accesskit_action_request_free(request_pointer)
				return
			}
			if length > 0 {
				destination := cast([^]u8)copy
				source := cast([^]u8)text
				for i in 0..<length { destination[i] = source[i] }
				queued.text_pointer = copy
				queued.text_length = length
			}
		} else if request.data.value.tag == ACCESSKIT_ACTION_DATA_NUMERIC_VALUE {
			if !node.has_numeric_value {
				host.counters.actions_dropped += 1
				sdl3.UnlockMutex(host.mutex)
				accesskit_action_request_free(request_pointer)
				return
			}
			queued.numeric_value = transmute(f64)request.data.value.value[0]
			queued.has_numeric_value = true
		} else {
			host.counters.actions_dropped += 1
			sdl3.UnlockMutex(host.mutex)
			accesskit_action_request_free(request_pointer)
			return
		}
	} else if action == .Set_Value {
		host.counters.actions_dropped += 1
		sdl3.UnlockMutex(host.mutex)
		accesskit_action_request_free(request_pointer)
		return
	}
	if reveal { queued.action = .Scroll_Into_View }
	host.actions[host.action_write] = queued
	host.action_write = (host.action_write+1)%len(host.actions)
	host.action_count += 1
	host.counters.actions_received += 1
	sdl3.UnlockMutex(host.mutex)
	accesskit_action_request_free(request_pointer)
	native_host_event_wake(host.host_waker)
}
}

native_accessibility_cstring_length :: proc(value: cstring, limit: int) -> int {
	if value == nil { return 0 }
	bytes := cast([^]u8)value
	for i in 0..<limit {
		if bytes[i] == 0 { return i }
	}
	return limit
}

native_accessibility_drain_actions :: proc(host: ^Native_Accessibility_Host, rt: ^alicorn.Runtime) {
	if host == nil || rt == nil || host.mutex == nil { return }
	for {
		sdl3.LockMutex(host.mutex)
		if host.action_count == 0 {
			sdl3.UnlockMutex(host.mutex)
			break
		}
		event := host.actions[host.action_read]
		host.actions[host.action_read] = {}
		host.action_read = (host.action_read+1)%len(host.actions)
		host.action_count -= 1
		sdl3.UnlockMutex(host.mutex)

		if event.action == .Scroll_Into_View {
			_ = alicorn.semantic_reveal_request(rt, event.semantic_id)
		} else {
			text_value := ""
			if event.text_pointer != nil {
				bytes := cast([^]u8)event.text_pointer
				text_value = string(bytes[:event.text_length])
			}
			_ = alicorn.semantic_action_request(
				rt, event.semantic_id, event.action, text_value,
				event.numeric_value, event.has_numeric_value,
			)
		}
		if event.text_pointer != nil { libc.free(event.text_pointer) }
	}
}

native_accessibility_take_counters :: proc(host: ^Native_Accessibility_Host) -> (result: Native_Accessibility_Counters) {
	if host == nil || host.mutex == nil { return }
	sdl3.LockMutex(host.mutex)
	result = host.counters
	host.counters = {}
	sdl3.UnlockMutex(host.mutex)
	return
}

native_accessibility_focus_changed :: proc(host: ^Native_Accessibility_Host, focused: bool) {
	if host == nil || host.adapter == nil { return }
	when ODIN_OS == .Darwin {
		events := accesskit_macos_subclassing_adapter_update_view_focus_state(host.adapter, focused)
		if events != nil { accesskit_macos_queued_events_raise(events) }
	}
}

native_accessibility_prepare_platform :: proc() -> bool {
	when ODIN_OS == .Darwin {
		// SDL's NSWindow subclass needs this forwarding method for VoiceOver to
		// find the content view's focused accessibility element.
		class_name, err := strings.clone_to_cstring("SDL3Window", context.temp_allocator)
		if err != nil { return false }
		accesskit_macos_add_focus_forwarder_to_window_class(class_name)
	}
	return true
}

native_accessibility_adapter_init :: proc(host: ^Native_Accessibility_Host, window: ^sdl3.Window) -> bool {
	if host == nil || window == nil { return false }
	props := sdl3.GetWindowProperties(window)
	when ODIN_OS == .Windows {
		hwnd := sdl3.GetPointerProperty(props, "SDL.window.win32.hwnd", nil)
		if hwnd == nil { return false }
		host.adapter = accesskit_windows_subclassing_adapter_new(
		hwnd,
		native_accessibility_activation_callback, rawptr(host),
		native_accessibility_action_callback, rawptr(host),
		)
	} else when ODIN_OS == .Darwin {
		native_window := sdl3.GetPointerProperty(props, "SDL.window.cocoa.window", nil)
		if native_window == nil { return false }
		host.adapter = accesskit_macos_subclassing_adapter_for_window(
			native_window,
			native_accessibility_activation_callback, rawptr(host),
			native_accessibility_action_callback, rawptr(host),
		)
	} else {
		return false
	}
	return host.adapter != nil
}

when ODIN_OS == .Windows || ODIN_OS == .Darwin {
native_accessibility_activation_callback :: proc "c" (userdata: rawptr) -> rawptr {
	context = runtime.default_context()
	host := cast(^Native_Accessibility_Host)userdata
	if !native_accessibility_callback_enter(host) { return nil }
	defer native_accessibility_callback_leave(host)
	update := native_accessibility_build_snapshot_update(host)
	if update != nil { native_host_event_wake(host.host_waker) }
	return update
}
}

Native_Accessibility_Update_Context :: struct {
	host: ^Native_Accessibility_Host,
	delta: ^Accessibility_Projection_Delta,
	force_snapshot: bool,
}

native_accessibility_sync :: proc(
	host: ^Native_Accessibility_Host,
	rt: ^alicorn.Runtime,
	content_inset_top: f32 = 0,
) -> bool {
	if host == nil || rt == nil || host.mutex == nil { return false }
	sdl3.LockMutex(host.mutex)
	active := host.active
	sdl3.UnlockMutex(host.mutex)
	if !active { return false }
	revision := alicorn.semantic_revision(rt)
	sdl3.LockMutex(host.mutex)
	unchanged := host.projection_ready && host.projection.revision == revision
	sdl3.UnlockMutex(host.mutex)
	if unchanged { return false }

	snapshot := alicorn.semantic_snapshot(rt, context.temp_allocator)
	defer alicorn.semantic_snapshot_destroy(&snapshot)
	if snapshot.revision != revision { return false }

	sdl3.LockMutex(host.mutex)
	if !host.active {
		sdl3.UnlockMutex(host.mutex)
		return false
	}
	full_snapshot := !host.projection_ready
	delta: Accessibility_Projection_Delta
	if !host.projection_ready {
		projection, status := accessibility_projection_from_snapshot(snapshot, context.allocator)
		if status != .Success {
			sdl3.UnlockMutex(host.mutex)
			return false
		}
		host.projection = projection
		host.projection_ready = true
		delta = Accessibility_Projection_Delta{
			from_revision=0,
			to_revision=projection.revision,
			keyboard_focus=projection.keyboard_focus,
			requires_snapshot=true,
			allocator=context.allocator,
		}
	} else {
		update := alicorn.semantic_update_since(rt, host.projection.revision)
		if update.requires_snapshot {
			full_snapshot = true
			accessibility_projection_destroy(&host.projection)
			projection, status := accessibility_projection_from_snapshot(snapshot, context.allocator)
			if status != .Success {
				host.projection_ready = false
				sdl3.UnlockMutex(host.mutex)
				return false
			}
			host.projection = projection
			delta = Accessibility_Projection_Delta{
				from_revision=update.from_revision,
				to_revision=projection.revision,
				keyboard_focus=projection.keyboard_focus,
				requires_snapshot=true,
				allocator=context.allocator,
			}
		} else {
			result: Accessibility_Projection_Apply_Result
			delta, result = accessibility_projection_apply_update(
				&host.projection, update, snapshot, context.allocator,
			)
			if result == .Requires_Snapshot {
				full_snapshot = true
				accessibility_projection_delta_destroy(&delta)
				accessibility_projection_destroy(&host.projection)
				projection, status := accessibility_projection_from_snapshot(snapshot, context.allocator)
				if status != .Success {
					host.projection_ready = false
					sdl3.UnlockMutex(host.mutex)
					return false
				}
				host.projection = projection
				delta = Accessibility_Projection_Delta{
					from_revision=update.from_revision,
					to_revision=projection.revision,
					keyboard_focus=projection.keyboard_focus,
					requires_snapshot=true,
					allocator=context.allocator,
				}
			}
		}
	}
	host.content_inset_top = content_inset_top
	host_revision := host.projection.revision
	sdl3.UnlockMutex(host.mutex)

	if host.adapter != nil {
		update_context := Native_Accessibility_Update_Context{
			host=host,
			delta=&delta,
			force_snapshot=full_snapshot,
		}
		when ODIN_OS == .Windows {
			events := accesskit_windows_subclassing_adapter_update_if_active(
				host.adapter, native_accessibility_update_factory, rawptr(&update_context),
			)
			if events != nil { accesskit_windows_queued_events_raise(events) }
		} else when ODIN_OS == .Darwin {
			events := accesskit_macos_subclassing_adapter_update_if_active(
				host.adapter, native_accessibility_update_factory, rawptr(&update_context),
			)
			if events != nil { accesskit_macos_queued_events_raise(events) }
		}
	}
	accessibility_projection_delta_destroy(&delta)
	return host_revision == revision
}

when ODIN_OS == .Windows || ODIN_OS == .Darwin {
native_accessibility_update_factory :: proc "c" (userdata: rawptr) -> rawptr {
	context = runtime.default_context()
	update_context := cast(^Native_Accessibility_Update_Context)userdata
	if update_context == nil || update_context.host == nil { return nil }
	host := update_context.host
	if host.mutex == nil { return nil }
	sdl3.LockMutex(host.mutex)
	if !host.active || !host.projection_ready {
		sdl3.UnlockMutex(host.mutex)
		return nil
	}
	full_snapshot := update_context.force_snapshot || update_context.delta == nil ||
		host.adapter_revision != update_context.delta.from_revision
	result: rawptr
	if full_snapshot {
		result = native_accessibility_build_tree_update(
			host.projection.nodes[:], host.projection.keyboard_focus,
			host.projection.root_id, host.content_inset_top, include_tree_info=true,
		)
	} else {
		result = native_accessibility_build_tree_update(
			update_context.delta.changed_nodes[:], update_context.delta.keyboard_focus,
			host.projection.root_id, host.content_inset_top, include_tree_info=false,
		)
	}
	if result != nil {
		host.adapter_revision = host.projection.revision
		host.counters.updates_submitted += 1
	}
	sdl3.UnlockMutex(host.mutex)
	return result
}
}

when ODIN_OS == .Windows || ODIN_OS == .Darwin {
native_accessibility_build_snapshot_update :: proc(host: ^Native_Accessibility_Host) -> rawptr {
	if host == nil || host.mutex == nil { return nil }
	sdl3.LockMutex(host.mutex)
	if !host.active || !host.projection_ready {
		sdl3.UnlockMutex(host.mutex)
		return nil
	}
	update := native_accessibility_build_tree_update(
		host.projection.nodes[:], host.projection.keyboard_focus,
		host.projection.root_id, host.content_inset_top, include_tree_info=true,
	)
	if update != nil {
		host.adapter_revision = host.projection.revision
		host.counters.activation_wakes += 1
		host.counters.updates_submitted += 1
	}
	sdl3.UnlockMutex(host.mutex)
	return update
}
}

when ODIN_OS == .Windows || ODIN_OS == .Darwin {
native_accessibility_build_tree_update :: proc(
	nodes: []Accessibility_Projection_Node,
	focus, root_id: u64,
	content_inset_top: f32,
	include_tree_info: bool,
) -> rawptr {
	update := accesskit_tree_update_with_capacity_and_focus(uint(len(nodes)), focus)
	if update == nil { return nil }
	if include_tree_info {
		tree := accesskit_tree_info_new(root_id)
		if tree == nil { accesskit_tree_update_free(update); return nil }
		toolkit_name := "Alicorn"
		toolkit_version := "0.1"
		accesskit_tree_info_set_toolkit_name_with_length(tree, raw_data(toolkit_name), uint(len(toolkit_name)))
		accesskit_tree_info_set_toolkit_version_with_length(tree, raw_data(toolkit_version), uint(len(toolkit_version)))
		accesskit_tree_update_set_tree_info(update, tree)
	}
	for source in nodes {
		node := native_accessibility_build_node(source, content_inset_top)
		if node == nil {
			accesskit_tree_update_free(update)
			return nil
		}
		accesskit_tree_update_push_node(update, source.id, node)
	}
	return update
}
}

when ODIN_OS == .Windows || ODIN_OS == .Darwin {
native_accessibility_build_node :: proc(source: Accessibility_Projection_Node, content_inset_top: f32) -> rawptr {
	node := accesskit_node_new(native_accessibility_accesskit_role(source.role))
	if node == nil { return nil }
	if len(source.label) > 0 {
		accesskit_node_set_label_with_length(node, raw_data(source.label), uint(len(source.label)))
	}
	description := source.description
	if len(description) == 0 && accessibility_projection_state_has(source.states, .Modified) {
		description = "Modified"
	}
	if len(description) > 0 {
		accesskit_node_set_description_with_length(node, raw_data(description), uint(len(description)))
	}
	if len(source.value) > 0 {
		accesskit_node_set_value_with_length(node, raw_data(source.value), uint(len(source.value)))
	}
	if source.has_bounds {
		bounds := AccessKit_Rect{
			x0=f64(source.bounds.x),
			y0=f64(source.bounds.y+content_inset_top),
			x1=f64(source.bounds.x+source.bounds.w),
			y1=f64(source.bounds.y+source.bounds.h+content_inset_top),
		}
		accesskit_node_set_bounds(node, bounds)
	}
	if accessibility_projection_state_has(source.states, .Disabled) { accesskit_node_set_disabled(node) }
	if accessibility_projection_state_has(source.states, .Selected) { accesskit_node_set_selected(node, true) }
	if source.role == .Check_Box {
		toggled := ACCESSKIT_TOGGLED_FALSE
		if accessibility_projection_state_has(source.states, .Checked) { toggled = ACCESSKIT_TOGGLED_TRUE }
		accesskit_node_set_toggled(node, toggled)
	}
	if accessibility_projection_state_has(source.states, .Required) { accesskit_node_set_required(node) }
	if accessibility_projection_state_has(source.states, .Read_Only) { accesskit_node_set_read_only(node) }
	if accessibility_projection_state_has(source.states, .Invalid) { accesskit_node_set_invalid(node, 0) }
	if accessibility_projection_state_has(source.states, .Busy) { accesskit_node_set_busy(node) }
	if accessibility_projection_state_has(source.states, .Current) { accesskit_node_set_aria_current(node, 1) }
	if accessibility_projection_state_has(source.states, .Expanded) ||
		accessibility_projection_action_has(source.actions, .Expand) ||
		accessibility_projection_action_has(source.actions, .Collapse) {
		accesskit_node_set_expanded(node, accessibility_projection_state_has(source.states, .Expanded))
	}
	if source.position_in_set > 0 { accesskit_node_set_position_in_set(node, uint(source.position_in_set)) }
	if source.size_of_set > 0 { accesskit_node_set_size_of_set(node, uint(source.size_of_set)) }
	if source.has_numeric_value {
		accesskit_node_set_numeric_value(node, source.numeric_value)
		accesskit_node_set_min_numeric_value(node, source.numeric_minimum)
		accesskit_node_set_max_numeric_value(node, source.numeric_maximum)
		accesskit_node_set_numeric_value_step(node, source.numeric_step)
	}
	for child in source.children { accesskit_node_push_child(node, child) }
	native_accessibility_add_node_actions(node, source.actions)
	return node
}
}

when ODIN_OS == .Windows || ODIN_OS == .Darwin {
native_accessibility_add_node_actions :: proc(node: rawptr, actions: Accessibility_Projection_Actions) {
	if accessibility_projection_action_has(actions, .Press) || accessibility_projection_action_has(actions, .Select) {
		accesskit_node_add_action(node, ACCESSKIT_ACTION_CLICK)
	}
	if accessibility_projection_action_has(actions, .Focus) { accesskit_node_add_action(node, ACCESSKIT_ACTION_FOCUS) }
	if accessibility_projection_action_has(actions, .Set_Value) {
		accesskit_node_add_action(node, ACCESSKIT_ACTION_SET_VALUE)
	}
	if accessibility_projection_action_has(actions, .Increment) { accesskit_node_add_action(node, ACCESSKIT_ACTION_INCREMENT) }
	if accessibility_projection_action_has(actions, .Decrement) { accesskit_node_add_action(node, ACCESSKIT_ACTION_DECREMENT) }
	if accessibility_projection_action_has(actions, .Expand) { accesskit_node_add_action(node, ACCESSKIT_ACTION_EXPAND) }
	if accessibility_projection_action_has(actions, .Collapse) { accesskit_node_add_action(node, ACCESSKIT_ACTION_COLLAPSE) }
	if accessibility_projection_action_has(actions, .Scroll_Into_View) { accesskit_node_add_action(node, ACCESSKIT_ACTION_SCROLL_INTO_VIEW) }
	if accessibility_projection_action_has(actions, .Scroll_Forward) { accesskit_node_add_action(node, ACCESSKIT_ACTION_SCROLL_DOWN) }
	if accessibility_projection_action_has(actions, .Scroll_Backward) { accesskit_node_add_action(node, ACCESSKIT_ACTION_SCROLL_UP) }
	if accessibility_projection_action_has(actions, .Dismiss) { accesskit_node_add_action(node, ACCESSKIT_ACTION_HIDE_TOOLTIP) }
}
}

native_accessibility_accesskit_role :: proc(role: Accessibility_Projection_Role) -> u8 {
	switch role {
	case .Window: return ACCESSKIT_ROLE_WINDOW
	case .Group: return ACCESSKIT_ROLE_GROUP
	case .Static_Text: return ACCESSKIT_ROLE_LABEL
	case .Button: return ACCESSKIT_ROLE_BUTTON
	case .Check_Box: return ACCESSKIT_ROLE_CHECK_BOX
	case .Slider: return ACCESSKIT_ROLE_SLIDER
	case .Text_Input: return ACCESSKIT_ROLE_TEXT_INPUT
	case .Text_Area: return ACCESSKIT_ROLE_MULTILINE_TEXT_INPUT
	case .Tab_List: return ACCESSKIT_ROLE_TAB_LIST
	case .Tab: return ACCESSKIT_ROLE_TAB
	case .List: return ACCESSKIT_ROLE_LIST
	case .List_Item: return ACCESSKIT_ROLE_LIST_ITEM
	case .Tree: return ACCESSKIT_ROLE_TREE
	case .Tree_Item: return ACCESSKIT_ROLE_TREE_ITEM
	case .Menu: return ACCESSKIT_ROLE_MENU
	case .Menu_Item: return ACCESSKIT_ROLE_MENU_ITEM
	case .Dialog: return ACCESSKIT_ROLE_DIALOG
	case .Tooltip: return ACCESSKIT_ROLE_TOOLTIP
	case .Scroll_View: return ACCESSKIT_ROLE_SCROLL_VIEW
	case .Generic_Container: return ACCESSKIT_ROLE_GENERIC_CONTAINER
	}
	return ACCESSKIT_ROLE_UNKNOWN
}

native_accessibility_semantic_for_node :: proc(host: ^Native_Accessibility_Host, node_id: u64) -> (Accessibility_Projection_Node, bool) {
	if host == nil || !host.projection_ready { return {}, false }
	return accessibility_projection_node_by_id(host.projection, node_id)
}
