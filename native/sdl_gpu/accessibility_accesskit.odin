package alicorn_sdl_gpu

import libc "core:c/libc"
import "base:runtime"
import "core:strings"
import alicorn "../../runtime"
import ak "../../accesskit"
import "vendor:sdl3"

// Alicorn keeps semantic projection and action routing; C ABI declarations,
// AccessKit identifiers, and native adapters live in the standalone package.
ACCESSKIT_ACTION_CLICK :: ak.ACTION_CLICK
ACCESSKIT_ACTION_FOCUS :: ak.ACTION_FOCUS
ACCESSKIT_ACTION_COLLAPSE :: ak.ACTION_COLLAPSE
ACCESSKIT_ACTION_EXPAND :: ak.ACTION_EXPAND
ACCESSKIT_ACTION_HIDE_TOOLTIP :: ak.ACTION_HIDE_TOOLTIP
ACCESSKIT_ACTION_REPLACE_SELECTED_TEXT :: ak.ACTION_REPLACE_SELECTED_TEXT
ACCESSKIT_ACTION_DECREMENT :: ak.ACTION_DECREMENT
ACCESSKIT_ACTION_INCREMENT :: ak.ACTION_INCREMENT
ACCESSKIT_ACTION_SCROLL_DOWN :: ak.ACTION_SCROLL_DOWN
ACCESSKIT_ACTION_SCROLL_UP :: ak.ACTION_SCROLL_UP
ACCESSKIT_ACTION_SCROLL_INTO_VIEW :: ak.ACTION_SCROLL_INTO_VIEW
ACCESSKIT_ACTION_SET_TEXT_SELECTION :: ak.ACTION_SET_TEXT_SELECTION
ACCESSKIT_ACTION_SET_VALUE :: ak.ACTION_SET_VALUE

ACCESSKIT_ACTION_DATA_VALUE :: ak.ACTION_DATA_VALUE
ACCESSKIT_ACTION_DATA_NUMERIC_VALUE :: ak.ACTION_DATA_NUMERIC_VALUE
ACCESSKIT_ACTION_DATA_SET_TEXT_SELECTION :: ak.ACTION_DATA_SET_TEXT_SELECTION

ACCESSKIT_ROLE_UNKNOWN :: ak.ROLE_UNKNOWN
ACCESSKIT_ROLE_TEXT_RUN :: ak.ROLE_TEXT_RUN
ACCESSKIT_ROLE_LABEL :: ak.ROLE_LABEL
ACCESSKIT_ROLE_LIST_ITEM :: ak.ROLE_LIST_ITEM
ACCESSKIT_ROLE_MENU_ITEM :: ak.ROLE_MENU_ITEM
ACCESSKIT_ROLE_TREE_ITEM :: ak.ROLE_TREE_ITEM
ACCESSKIT_ROLE_GENERIC_CONTAINER :: ak.ROLE_GENERIC_CONTAINER
ACCESSKIT_ROLE_CHECK_BOX :: ak.ROLE_CHECK_BOX
ACCESSKIT_ROLE_TEXT_INPUT :: ak.ROLE_TEXT_INPUT
ACCESSKIT_ROLE_BUTTON :: ak.ROLE_BUTTON
ACCESSKIT_ROLE_LIST :: ak.ROLE_LIST
ACCESSKIT_ROLE_LIST_BOX_OPTION :: ak.ROLE_LIST_BOX_OPTION
ACCESSKIT_ROLE_COMBO_BOX :: ak.ROLE_COMBO_BOX
ACCESSKIT_ROLE_LIST_BOX :: ak.ROLE_LIST_BOX
ACCESSKIT_ROLE_STATUS :: ak.ROLE_STATUS
ACCESSKIT_ROLE_ALERT :: ak.ROLE_ALERT
ACCESSKIT_ROLE_DIALOG :: ak.ROLE_DIALOG
ACCESSKIT_ROLE_GROUP :: ak.ROLE_GROUP
ACCESSKIT_ROLE_SCROLL_VIEW :: ak.ROLE_SCROLL_VIEW
ACCESSKIT_ROLE_SLIDER :: ak.ROLE_SLIDER
ACCESSKIT_ROLE_TAB :: ak.ROLE_TAB
ACCESSKIT_ROLE_TAB_LIST :: ak.ROLE_TAB_LIST
ACCESSKIT_ROLE_TAB_PANEL :: ak.ROLE_TAB_PANEL
ACCESSKIT_ROLE_MENU :: ak.ROLE_MENU
ACCESSKIT_ROLE_MULTILINE_TEXT_INPUT :: ak.ROLE_MULTILINE_TEXT_INPUT
ACCESSKIT_ROLE_TREE :: ak.ROLE_TREE
ACCESSKIT_ROLE_TOOLTIP :: ak.ROLE_TOOLTIP
ACCESSKIT_ROLE_WINDOW :: ak.ROLE_WINDOW

ACCESSKIT_TOGGLED_FALSE :: ak.TOGGLED_FALSE
ACCESSKIT_TOGGLED_TRUE :: ak.TOGGLED_TRUE
ACCESSKIT_LIVE_OFF :: ak.LIVE_OFF
ACCESSKIT_LIVE_POLITE :: ak.LIVE_POLITE
ACCESSKIT_LIVE_ASSERTIVE :: ak.LIVE_ASSERTIVE

NATIVE_ACCESSIBILITY_ACTION_QUEUE_CAPACITY :: 64
NATIVE_ACCESSIBILITY_ACTION_TEXT_LIMIT :: 1 << 20

Native_Accessibility_Sync_Plan :: struct {
	required: bool,
	force_snapshot: bool,
}

// AccessKit bounds depend on native host geometry as well as semantic content.
// In particular, a content inset change moves every exported node without
// changing the semantic revision, so it requires a full tree refresh.
native_accessibility_sync_plan :: proc(
	projection_ready: bool,
	projection_revision, semantic_revision: u64,
	current_inset, requested_inset: f32,
) -> Native_Accessibility_Sync_Plan {
	if !projection_ready {
		return {required=true, force_snapshot=true}
	}

	semantic_changed := projection_revision != semantic_revision
	geometry_changed := current_inset != requested_inset
	return {
		required=semantic_changed || geometry_changed,
		force_snapshot=geometry_changed,
	}
}

Native_Accessibility_Queued_Action :: struct {
	semantic_id: alicorn.Semantic_ID,
	action: alicorn.Semantic_Action,
	text_pointer: rawptr,
	text_length: int,
	numeric_value: f64,
	has_numeric_value: bool,
	text_selection: alicorn.Semantic_Text_Selection,
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
			adapter := ak.Windows_Subclassing_Adapter{raw=host.adapter}
			ak.windows_subclassing_adapter_destroy(&adapter)
		} else when ODIN_OS == .Darwin {
			adapter := ak.MacOS_Subclassing_Adapter{raw=host.adapter}
			ak.macos_subclassing_adapter_destroy(&adapter)
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

native_accessibility_action_to_semantic :: proc(action: ak.Action, node: Accessibility_Projection_Node) -> (alicorn.Semantic_Action, bool, bool) {
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
	case ACCESSKIT_ACTION_SET_TEXT_SELECTION:
		if accessibility_projection_action_has(node.actions, .Set_Text_Selection) { return .Set_Text_Selection, false, true }
	case ACCESSKIT_ACTION_REPLACE_SELECTED_TEXT:
		if accessibility_projection_action_has(node.actions, .Replace_Selected_Text) { return .Replace_Selected_Text, false, true }
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
	case ACCESSKIT_ACTION_SCROLL_DOWN:
		if accessibility_projection_action_has(node.actions, .Scroll_Forward) { return .Scroll_Forward, false, true }
	case ACCESSKIT_ACTION_SCROLL_UP:
		if accessibility_projection_action_has(node.actions, .Scroll_Backward) { return .Scroll_Backward, false, true }
	}
	return .None, false, false
}

native_accessibility_selection_from_action_data :: proc(
	projection: Accessibility_Projection,
	area_id: alicorn.Semantic_ID,
	data: ak.Action_Data_ABI,
) -> (selection: alicorn.Semantic_Text_Selection, ok: bool) {
	if ak.Action_Data_Tag(data.tag) != ACCESSKIT_ACTION_DATA_SET_TEXT_SELECTION { return {}, false }
	return accessibility_projection_text_selection_decode(
		projection,
		area_id,
		data.value[0], data.value[1], data.value[2], data.value[3],
	)
}

when ODIN_OS == .Windows || ODIN_OS == .Darwin {
native_accessibility_action_callback :: proc "c" (request_pointer, userdata: rawptr) {
	context = runtime.default_context()
	if request_pointer == nil { return }
	request_owner := ak.action_request_take(request_pointer)
	defer ak.action_request_destroy(&request_owner)
	request, request_ok := ak.action_request_borrow(&request_owner)
	if !request_ok { return }
	host := cast(^Native_Accessibility_Host)userdata
	if !native_accessibility_callback_enter(host) { return }
	defer native_accessibility_callback_leave(host)

	// The current semantic projection owns this mapping. It is bounded by the
	// exported working set and is read only under the same mutex as publication.
	sdl3.LockMutex(host.mutex)
	node, found := native_accessibility_semantic_for_node(host, u64(request.target_node))
	if !found {
		host.counters.actions_dropped += 1
		sdl3.UnlockMutex(host.mutex)
		return
	}
	action, reveal, supported := native_accessibility_action_to_semantic(request.action, node)
	if !supported || host.action_count >= len(host.actions) {
		host.counters.actions_dropped += 1
		sdl3.UnlockMutex(host.mutex)
		return
	}
	queued := Native_Accessibility_Queued_Action{semantic_id=node.semantic_id, action=action}
	if (action == .Set_Value || action == .Replace_Selected_Text) && request.has_data {
		if request.data_tag == ACCESSKIT_ACTION_DATA_VALUE {
			if node.role != .Text_Input && node.role != .Text_Area {
				host.counters.actions_dropped += 1
				sdl3.UnlockMutex(host.mutex)
				return
			}
			// AccessKit's Value union arm contains a borrowed char pointer. Copy
			// it before freeing the action request at the end of this callback.
			text := request.text_value
			if text == nil {
				host.counters.actions_dropped += 1
				sdl3.UnlockMutex(host.mutex)
				return
			}
			length := native_accessibility_cstring_length(text, NATIVE_ACCESSIBILITY_ACTION_TEXT_LIMIT)
			if length == NATIVE_ACCESSIBILITY_ACTION_TEXT_LIMIT {
				host.counters.actions_dropped += 1
				sdl3.UnlockMutex(host.mutex)
				return
			}
			copy := libc.malloc(uint(length))
			if length > 0 && copy == nil {
				host.counters.actions_dropped += 1
				sdl3.UnlockMutex(host.mutex)
				return
			}
			if length > 0 {
				destination := cast([^]u8)copy
				source := cast([^]u8)text
				for i in 0..<length { destination[i] = source[i] }
				queued.text_pointer = copy
				queued.text_length = length
			}
		} else if request.data_tag == ACCESSKIT_ACTION_DATA_NUMERIC_VALUE {
			if !node.has_numeric_value {
				host.counters.actions_dropped += 1
				sdl3.UnlockMutex(host.mutex)
				return
			}
			queued.numeric_value = request.numeric_value
			queued.has_numeric_value = true
		} else {
			host.counters.actions_dropped += 1
			sdl3.UnlockMutex(host.mutex)
			return
		}
	} else if action == .Set_Text_Selection && request.has_data &&
	   request.data_tag == ACCESSKIT_ACTION_DATA_SET_TEXT_SELECTION {
		// ActionData::SetTextSelection is two 16-byte positions in the
		// union's 32-byte payload: {node, character_index} for each endpoint.
		selection, selection_ok := native_accessibility_selection_from_action_data(
			host.projection, node.semantic_id, request.payload,
		)
		if !selection_ok {
			host.counters.actions_dropped += 1
			sdl3.UnlockMutex(host.mutex)
			return
		}
		queued.text_selection = selection
	} else if action == .Set_Value || action == .Replace_Selected_Text || action == .Set_Text_Selection {
		host.counters.actions_dropped += 1
		sdl3.UnlockMutex(host.mutex)
		return
	}
	if reveal { queued.action = .Scroll_Into_View }
	host.actions[host.action_write] = queued
	host.action_write = (host.action_write+1)%len(host.actions)
	host.action_count += 1
	host.counters.actions_received += 1
	sdl3.UnlockMutex(host.mutex)
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
		} else if event.action == .Set_Text_Selection {
			_ = alicorn.semantic_text_selection_request(rt, event.semantic_id, event.text_selection)
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
		adapter := ak.MacOS_Subclassing_Adapter{raw=host.adapter}
		events := ak.macos_subclassing_adapter_update_focus_state(&adapter, focused)
		ak.macos_queued_events_raise(&events)
	}
}

native_accessibility_prepare_platform :: proc() -> bool {
	when ODIN_OS == .Darwin {
		// SDL's NSWindow subclass needs this forwarding method for VoiceOver to
		// find the content view's focused accessibility element.
		class_name, err := strings.clone_to_cstring("SDL3Window", context.temp_allocator)
		if err != nil { return false }
		ak.macos_add_focus_forwarder_to_window_class(class_name)
	}
	return true
}

native_accessibility_adapter_init :: proc(host: ^Native_Accessibility_Host, window: ^sdl3.Window) -> bool {
	if host == nil || window == nil { return false }
	props := sdl3.GetWindowProperties(window)
	when ODIN_OS == .Windows {
		hwnd := sdl3.GetPointerProperty(props, "SDL.window.win32.hwnd", nil)
		if hwnd == nil { return false }
		adapter, ok := ak.windows_subclassing_adapter_create(
		hwnd,
		native_accessibility_activation_callback, rawptr(host),
		native_accessibility_action_callback, rawptr(host),
		)
		if !ok { return false }
		host.adapter = adapter.raw
	} else when ODIN_OS == .Darwin {
		native_window := sdl3.GetPointerProperty(props, "SDL.window.cocoa.window", nil)
		if native_window == nil { return false }
		adapter, ok := ak.macos_subclassing_adapter_create_for_window(
			native_window,
			native_accessibility_activation_callback, rawptr(host),
			native_accessibility_action_callback, rawptr(host),
		)
		if !ok { return false }
		host.adapter = adapter.raw
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
	plan := native_accessibility_sync_plan(
		host.projection_ready, host.projection.revision, revision,
		host.content_inset_top, content_inset_top,
	)
	sdl3.UnlockMutex(host.mutex)
	if !plan.required { return false }

	snapshot := alicorn.semantic_snapshot(rt, context.temp_allocator)
	defer alicorn.semantic_snapshot_destroy(&snapshot)
	if snapshot.revision != revision { return false }

	sdl3.LockMutex(host.mutex)
	if !host.active {
		sdl3.UnlockMutex(host.mutex)
		return false
	}
	current_plan := native_accessibility_sync_plan(
		host.projection_ready, host.projection.revision, snapshot.revision,
		host.content_inset_top, content_inset_top,
	)
	full_snapshot := current_plan.force_snapshot
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
			adapter := ak.Windows_Subclassing_Adapter{raw=host.adapter}
			events := ak.windows_subclassing_adapter_update_if_active(
				&adapter, native_accessibility_update_factory, rawptr(&update_context),
			)
			ak.windows_queued_events_raise(&events)
		} else when ODIN_OS == .Darwin {
			adapter := ak.MacOS_Subclassing_Adapter{raw=host.adapter}
			events := ak.macos_subclassing_adapter_update_if_active(
				&adapter, native_accessibility_update_factory, rawptr(&update_context),
			)
			ak.macos_queued_events_raise(&events)
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
	update, update_ok := ak.tree_update_create(uint(len(nodes)), ak.Node_ID(focus))
	if !update_ok { return nil }
	defer ak.tree_update_destroy(&update)
	if include_tree_info {
		tree, tree_ok := ak.tree_info_create(ak.Node_ID(root_id))
		if !tree_ok { return nil }
		defer ak.tree_info_destroy(&tree)
		toolkit_name := "Alicorn"
		toolkit_version := "0.1"
		ak.tree_info_set_toolkit_name(&tree, toolkit_name)
		ak.tree_info_set_toolkit_version(&tree, toolkit_version)
		if !ak.tree_update_set_tree_info(&update, &tree) { return nil }
	}
	for source in nodes {
		node, node_ok := native_accessibility_build_node(source, content_inset_top)
		if !node_ok { return nil }
		defer ak.node_destroy(&node)
		if !ak.tree_update_push_node(&update, ak.Node_ID(source.id), &node) { return nil }
	}
	return ak.tree_update_take(&update)
}
}

when ODIN_OS == .Windows || ODIN_OS == .Darwin {
native_accessibility_build_node :: proc(
	source: Accessibility_Projection_Node,
	content_inset_top: f32,
) -> (node: ak.Node, ok: bool) {
	node, ok = ak.node_create(native_accessibility_accesskit_role(source.role))
	if !ok { return }
	if len(source.label) > 0 {
		ak.node_set_label(&node, source.label)
	}
	description := source.description
	if len(description) == 0 && accessibility_projection_state_has(source.states, .Modified) {
		description = "Modified"
	}
	if len(description) > 0 {
		ak.node_set_description(&node, description)
	}
	if len(source.value) > 0 || source.role == .Text_Run {
		ak.node_set_value(&node, source.value)
	}
	if source.live != .Off {
		live := ACCESSKIT_LIVE_OFF
		if source.live == .Polite { live = ACCESSKIT_LIVE_POLITE }
		if source.live == .Assertive { live = ACCESSKIT_LIVE_ASSERTIVE }
		ak.node_set_live(&node, live)
		if source.live_atomic { ak.node_set_live_atomic(&node) }
	}
	if source.has_bounds {
		ak.node_set_bounds(&node, native_accessibility_bounds(source.bounds, content_inset_top))
	}
	if accessibility_projection_state_has(source.states, .Disabled) { ak.node_set_disabled(&node, true) }
	if accessibility_projection_state_has(source.states, .Selected) { ak.node_set_selected(&node, true) }
	if source.role == .Check_Box {
		toggled := ACCESSKIT_TOGGLED_FALSE
		if accessibility_projection_state_has(source.states, .Checked) { toggled = ACCESSKIT_TOGGLED_TRUE }
		ak.node_set_toggled(&node, toggled)
	}
	if accessibility_projection_state_has(source.states, .Required) { ak.node_set_required(&node) }
	if accessibility_projection_state_has(source.states, .Read_Only) { ak.node_set_read_only(&node) }
	if accessibility_projection_state_has(source.states, .Invalid) { ak.node_set_invalid(&node, ak.INVALID_TRUE) }
	if accessibility_projection_state_has(source.states, .Busy) { ak.node_set_busy(&node) }
	if accessibility_projection_state_has(source.states, .Current) { ak.node_set_aria_current(&node, ak.ARIA_CURRENT_TRUE) }
	if accessibility_projection_state_has(source.states, .Expanded) ||
		accessibility_projection_action_has(source.actions, .Expand) ||
		accessibility_projection_action_has(source.actions, .Collapse) {
		ak.node_set_expanded(&node, accessibility_projection_state_has(source.states, .Expanded))
	}
	if source.has_position_in_set { ak.node_set_position_in_set(&node, uint(source.position_in_set)) }
	if source.is_collection && source.size_of_set > 0 {
		ak.node_set_size_of_set(&node, uint(source.size_of_set))
	}
	if source.has_numeric_value {
		ak.node_set_numeric_value(&node, source.numeric_value)
		ak.node_set_min_numeric_value(&node, source.numeric_minimum)
		ak.node_set_max_numeric_value(&node, source.numeric_maximum)
		ak.node_set_numeric_value_step(&node, source.numeric_step)
	}
	for child in source.children { ak.node_push_child(&node, ak.Node_ID(child)) }
	if len(source.text_run_character_lengths) > 0 {
		ak.node_set_character_lengths(&node, source.text_run_character_lengths)
	}
	if source.text_selection.valid {
		ak.node_set_text_selection(&node, ak.Text_Selection{
			anchor={node=source.text_selection.anchor.node_id, character_index=uint(source.text_selection.anchor.character_index)},
			focus={node=source.text_selection.focus.node_id, character_index=uint(source.text_selection.focus.character_index)},
		})
	}
	native_accessibility_add_node_actions(&node, source.actions)
	ok = true
	return
}

native_accessibility_bounds :: proc(bounds: alicorn.Rect, content_inset_top: f32) -> ak.Rect {
	return {
		x0=f64(bounds.x),
		y0=f64(bounds.y+content_inset_top),
		x1=f64(bounds.x+bounds.w),
		y1=f64(bounds.y+bounds.h+content_inset_top),
	}
}
}

when ODIN_OS == .Windows || ODIN_OS == .Darwin {
native_accessibility_add_node_actions :: proc(node: ^ak.Node, actions: Accessibility_Projection_Actions) {
	if accessibility_projection_action_has(actions, .Press) || accessibility_projection_action_has(actions, .Select) {
		ak.node_add_action(node, ACCESSKIT_ACTION_CLICK)
	}
	if accessibility_projection_action_has(actions, .Focus) { ak.node_add_action(node, ACCESSKIT_ACTION_FOCUS) }
	if accessibility_projection_action_has(actions, .Set_Value) {
		ak.node_add_action(node, ACCESSKIT_ACTION_SET_VALUE)
	}
	if accessibility_projection_action_has(actions, .Set_Text_Selection) {
		ak.node_add_action(node, ACCESSKIT_ACTION_SET_TEXT_SELECTION)
	}
	if accessibility_projection_action_has(actions, .Replace_Selected_Text) {
		ak.node_add_action(node, ACCESSKIT_ACTION_REPLACE_SELECTED_TEXT)
	}
	if accessibility_projection_action_has(actions, .Increment) { ak.node_add_action(node, ACCESSKIT_ACTION_INCREMENT) }
	if accessibility_projection_action_has(actions, .Decrement) { ak.node_add_action(node, ACCESSKIT_ACTION_DECREMENT) }
	if accessibility_projection_action_has(actions, .Expand) { ak.node_add_action(node, ACCESSKIT_ACTION_EXPAND) }
	if accessibility_projection_action_has(actions, .Collapse) { ak.node_add_action(node, ACCESSKIT_ACTION_COLLAPSE) }
	if accessibility_projection_action_has(actions, .Scroll_Into_View) { ak.node_add_action(node, ACCESSKIT_ACTION_SCROLL_INTO_VIEW) }
	if accessibility_projection_action_has(actions, .Scroll_Forward) { ak.node_add_action(node, ACCESSKIT_ACTION_SCROLL_DOWN) }
	if accessibility_projection_action_has(actions, .Scroll_Backward) { ak.node_add_action(node, ACCESSKIT_ACTION_SCROLL_UP) }
	if accessibility_projection_action_has(actions, .Dismiss) { ak.node_add_action(node, ACCESSKIT_ACTION_HIDE_TOOLTIP) }
}
}

native_accessibility_accesskit_role :: proc(role: Accessibility_Projection_Role) -> ak.Role {
	switch role {
	case .Window: return ACCESSKIT_ROLE_WINDOW
	case .Group: return ACCESSKIT_ROLE_GROUP
	case .Static_Text: return ACCESSKIT_ROLE_LABEL
	case .Button: return ACCESSKIT_ROLE_BUTTON
	case .Check_Box: return ACCESSKIT_ROLE_CHECK_BOX
	case .Slider: return ACCESSKIT_ROLE_SLIDER
	case .Text_Input: return ACCESSKIT_ROLE_TEXT_INPUT
	case .Text_Area: return ACCESSKIT_ROLE_MULTILINE_TEXT_INPUT
	case .Text_Run: return ACCESSKIT_ROLE_TEXT_RUN
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
	case .Combo_Box: return ACCESSKIT_ROLE_COMBO_BOX
	case .List_Box: return ACCESSKIT_ROLE_LIST_BOX
	case .List_Box_Option: return ACCESSKIT_ROLE_LIST_BOX_OPTION
	case .Status: return ACCESSKIT_ROLE_STATUS
	case .Alert: return ACCESSKIT_ROLE_ALERT
	case .Generic_Container: return ACCESSKIT_ROLE_GENERIC_CONTAINER
	}
	return ACCESSKIT_ROLE_UNKNOWN
}

native_accessibility_semantic_for_node :: proc(host: ^Native_Accessibility_Host, node_id: u64) -> (Accessibility_Projection_Node, bool) {
	if host == nil || !host.projection_ready { return {}, false }
	return accessibility_projection_node_by_id(host.projection, node_id)
}
