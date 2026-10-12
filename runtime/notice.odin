package alicorn

import "core:fmt"

NOTICE_DEFAULT_DURATION_MS :: u32(5_000)
NOTICE_MAX_DURATION_MS :: u32(60_000)
NOTICE_CARD_WIDTH :: f32(360)
NOTICE_CARD_MAX_HEIGHT :: f32(220)
NOTICE_CONTEXTUAL_HEIGHT :: f32(180)
NOTICE_TOAST_LAYER_KEY :: "alicorn-notice-toast-layer"

// notice_post copies one application notice into Alicorn's fixed-size queue.
// An existing ID is replaced in place and refreshes a transient deadline.
// When full, the oldest transient notice is evicted; a queue containing only
// persistent notices rejects the new record instead of silently losing one.
// Notices with actions are promoted to persistent: an actionable control must
// not disappear on a timer before the user has a reasonable chance to activate it.
notice_post :: proc(rt: ^Runtime, notice: Notice, now_ns: u64) -> bool {
	if rt == nil || rt.frame_open || len(notice.id) == 0 ||
		(len(notice.title) == 0 && len(notice.message) == 0) ||
		len(notice.actions) > NOTICE_ACTION_CAPACITY ||
		notice.severity < .Info || notice.severity > .Error ||
		notice.lifetime < .Transient || notice.lifetime > .Persistent ||
		notice.placement < .Toast || notice.placement > .Contextual ||
		(notice.placement == .Contextual && notice.anchor == 0) {
		return false
	}
	duration_ms := notice.duration_ms
	if duration_ms == 0 { duration_ms = NOTICE_DEFAULT_DURATION_MS }
	effective_lifetime := notice.lifetime
	if len(notice.actions) > 0 { effective_lifetime = .Persistent }
	if effective_lifetime == .Transient && duration_ms > NOTICE_MAX_DURATION_MS { return false }

	record := Notice_Record{
		severity=notice.severity,
		lifetime=effective_lifetime,
		placement=notice.placement,
		anchor=notice.anchor,
	}
	if !notice_copy_record_string(record.id[:], &record.id_length, notice.id) ||
		!notice_copy_record_string(record.title[:], &record.title_length, notice.title) ||
		!notice_copy_record_string(record.message[:], &record.message_length, notice.message) ||
		!notice_copy_record_string(record.details[:], &record.details_length, notice.details) {
		return false
	}
	record.id_hash = notice_string_hash(notice.id)
	for index in 0..<len(notice.actions) {
		action := notice.actions[index]
		if action.id == Action_ID(0) || len(action.label) == 0 { return false }
		record_action := &record.actions[index]
		record_action.id = action.id
		if !notice_copy_record_string(record_action.label[:], &record_action.label_length, action.label) { return false }
		record.action_count += 1
	}
	if record.lifetime == .Transient {
		delta := u64(duration_ms)*1_000_000
		record.deadline_ns = now_ns + delta
		if record.deadline_ns < now_ns { record.deadline_ns = u64(0xFFFFFFFFFFFFFFFF) }
		if record.deadline_ns == 0 { record.deadline_ns = 1 }
	}

	if existing := notice_find(rt, notice.id); existing >= 0 {
		record.handle = rt.notices[existing].handle
		record.sequence = notice_next_sequence(rt)
		rt.notices[existing] = record
		invalidate_root(rt, "notice updated")
		return true
	}
	if rt.notice_count >= NOTICE_QUEUE_CAPACITY {
		oldest_transient := -1
		oldest_sequence := u64(0xFFFFFFFFFFFFFFFF)
		for index in 0..<rt.notice_count {
			candidate := rt.notices[index]
			if candidate.lifetime == .Transient && candidate.sequence < oldest_sequence {
				oldest_transient = index
				oldest_sequence = candidate.sequence
			}
		}
		if oldest_transient < 0 { return false }
		notice_remove_at(rt, oldest_transient)
	}
	record.sequence = notice_next_sequence(rt)
	record.handle = notice_next_handle(rt)
	rt.notices[rt.notice_count] = record
	rt.notice_count += 1
	invalidate_root(rt, "notice posted")
	return true
}

// notice_emit adds one distinct event even when another event has identical
// text. Use notice_post with a stable ID when repeated reports describe one
// ongoing condition that should update in place.
notice_emit :: proc(rt: ^Runtime, notice: Notice, now_ns: u64) -> (handle: Notice_Handle, accepted: bool) {
	if rt == nil || rt.frame_open { return }
	event_id := ""
	for {
		rt.notice_event_sequence += 1
		if rt.notice_event_sequence == 0 { rt.notice_event_sequence = 1 }
		event_id = fmt.aprintf("alicorn-event-%d", rt.notice_event_sequence, allocator=rt.scratch_allocator)
		if notice_find(rt, event_id) < 0 { break }
	}
	event := notice
	event.id = event_id
	if !notice_post(rt, event, now_ns) { return }
	index := notice_find(rt, event_id)
	if index < 0 { return }
	return rt.notices[index].handle, true
}

// notice_dismiss removes a record by its application-owned stable ID.
notice_dismiss :: proc(rt: ^Runtime, id: string) -> bool {
	if rt == nil || rt.frame_open || len(id) == 0 { return false }
	index := notice_find(rt, id)
	if index < 0 { return false }
	notice_remove_at(rt, index)
	invalidate_root(rt, "notice dismissed")
	return true
}

// notice_dismiss_handle removes one occurrence returned by notice_emit.
notice_dismiss_handle :: proc(rt: ^Runtime, handle: Notice_Handle) -> bool {
	if rt == nil || rt.frame_open || handle == Notice_Handle(0) { return false }
	for index in 0..<rt.notice_count {
		if rt.notices[index].handle != handle { continue }
		notice_remove_at(rt, index)
		invalidate_root(rt, "notice occurrence dismissed")
		return true
	}
	return false
}

// notice_take_action drains one button activation from the bounded action
// queue. Alicorn returns the app-owned Action_ID; the app performs the work.
notice_take_action :: proc(rt: ^Runtime) -> (event: Notice_Action_Event, found: bool) {
	if rt == nil || rt.notice_action_count <= 0 { return }
	event = rt.notice_actions[rt.notice_action_read]
	rt.notice_actions[rt.notice_action_read] = {}
	rt.notice_action_read = (rt.notice_action_read+1)%len(rt.notice_actions)
	rt.notice_action_count -= 1
	return event, true
}

// notice_next_deadline returns the earliest transient expiration, or zero if
// every notice is persistent or the queue is empty.
notice_next_deadline :: proc(rt: ^Runtime) -> u64 {
	if rt == nil { return 0 }
	deadline := u64(0)
	for index in 0..<rt.notice_count {
		record := rt.notices[index]
		if record.lifetime != .Transient || record.deadline_ns == 0 { continue }
		if deadline == 0 || record.deadline_ns < deadline { deadline = record.deadline_ns }
	}
	return deadline
}

// notice_advance removes due transient records. It performs no periodic work;
// hosts should schedule a single wait for notice_next_deadline.
notice_advance :: proc(rt: ^Runtime, now_ns: u64) -> bool {
	if rt == nil || rt.frame_open { return false }
	changed := false
	index := 0
	for index < rt.notice_count {
		record := rt.notices[index]
		if record.lifetime == .Transient && record.deadline_ns != 0 && now_ns >= record.deadline_ns {
			notice_remove_at(rt, index)
			changed = true
			continue
		}
		index += 1
	}
	if changed { invalidate_root(rt, "transient notice expired") }
	return changed
}

// notice_overlay_describe adds independent nonmodal notice roots after the
// application has closed its ordinary roots. It never inserts a child into
// the workspace tree. Modal dialogs and unrelated transient menus/popups take precedence.
notice_overlay_describe :: proc(ui: ^UI) {
	if ui == nil || ui.runtime == nil || !ui.runtime.frame_open { return }
	rt := ui.runtime
	if len(rt.stack) != 0 {
		append_diagnostic(rt, "notice_overlay_describe must follow the ordinary roots")
		return
	}
	if notice_overlay_is_suppressed(rt) || rt.notice_count == 0 { return }

	has_toasts := false
	for index in 0..<rt.notice_count {
		if rt.notices[index].placement == .Toast { has_toasts = true; break }
	}
	if has_toasts {
		root := container_begin_simple(
			ui,
			.Container,
			label="notice-toast-overlay",
			key=key_string(NOTICE_TOAST_LAYER_KEY),
			style=layout_style(.Column, padding=14, gap=8, align=.End, clip=true),
			layout_boundary=true,
		)
		if root != 0 {
			for index in 0..<rt.notice_count {
				// Keep string slices backed by the runtime-owned record alive until
				// end_frame reconciles the descriptions emitted below.
				record := &rt.notices[index]
				if record.placement != .Toast { continue }
				if notice_describe_card(ui, record, contextual=false) { break }
			}
			container_end(ui)
		}
	}
	// Contextual notices get their own one-child overlay roots. The existing
	// Context_Menu_Overlay layout hook supplies absolute placement, but these
	// roots are not tied to Context_Menu_State and are therefore nonmodal.
	for index in 0..<rt.notice_count {
		record := &rt.notices[index]
		if record.placement != .Contextual { continue }
		anchor, ok := rt.nodes[record.anchor]
		if !ok || !node_is_presentation_active(rt, record.anchor) { continue }
		anchor_bounds := layout_node_finalized_geometry(rt, anchor.id).bounds
		bounds := context_menu_placement(rt.viewport, anchor_bounds, NOTICE_CARD_WIDTH, NOTICE_CONTEXTUAL_HEIGHT)
		root := container_begin_simple(
			ui,
			.Context_Menu_Overlay,
			label="notice-contextual-overlay",
			key=key_pair(record.id_hash, u64(0x4E4F54494345)),
			style=layout_style(.Column, clip=true),
		)
		if root == 0 { continue }
		if notice_describe_card(ui, record, contextual=true, placement=bounds) {
			container_end(ui)
			return
		}
		container_end(ui)
	}
}

@(private)
notice_overlay_is_suppressed :: proc(rt: ^Runtime) -> bool {
	if rt == nil { return false }
	if modal_overlay_root(rt) != 0 { return true }
	// Select shares the context-menu input machinery but has an explicit
	// nonmodal layering policy. Other application/context menus keep precedence.
	if (rt.context_menu.open || rt.context_menu.dismissed) && !rt.select.open { return true }
	for item in rt.pending {
		if item.kind != .Description { continue }
		if item.description.kind == .Modal_Overlay {
			return true
		}
		if item.description.kind == .Context_Menu_Overlay && !rt.select.open { return true }
	}
	return false
}

@(private)
notice_describe_card :: proc(
	ui: ^UI,
	record: ^Notice_Record,
	contextual: bool,
	placement := Rect{},
) -> bool {
	rt := ui.runtime
	card_height := NOTICE_CARD_MAX_HEIGHT if !contextual else NOTICE_CONTEXTUAL_HEIGHT
	card_style := layout_style(
		.Column,
		width=placement.w if contextual else NOTICE_CARD_WIDTH,
		height=card_height if contextual else LAYOUT_SIZE_FIT_CONTENT,
		max_height=NOTICE_CARD_MAX_HEIGHT,
		padding=10,
		gap=5,
		clip=true,
	)
	card_id := container_begin_simple(
		ui,
		.Container,
		label="notice-card",
		key=key_pair(record.id_hash, u64(0x43415244)),
		style=card_style,
		color=style_color(ui, .Subtle_Surface),
	)
	if card_id == 0 { return false }
	if contextual {
		for index := len(rt.pending)-1; index >= 0; index -= 1 {
			item := &rt.pending[index]
			if item.kind == .Description && item.description.id == card_id {
				item.description.context_menu_bounds = placement
				break
			}
		}
	}
	semantic_role := Semantic_Role.Status
	announcement := Semantic_Live_Announcement.Polite
	if record.severity == .Error {
		semantic_role = .Alert
		announcement = .Assertive
	}
	_ = semantic_description(ui, semantic_role, notice_record_title(record), description=notice_record_details(record), value=notice_record_message(record))
	semantic_pending := &rt.pending[len(rt.pending)-1].semantic
	semantic_pending.live = announcement
	semantic_pending.live_atomic = true

	container_begin_simple(ui, .Container, label="notice-heading-row", key=key_pair(record.id_hash, u64(0x48454144)), style=layout_style(.Row, height=28, gap=6, align=.Center))
	severity_icon, severity_color := notice_severity_icon(record.severity)
	icon(ui, severity_icon, key=key_pair(record.id_hash, u64(0x53455645)), size=16, color_role=severity_color)
	if record.title_length > 0 {
		text(ui, notice_record_title(record), key=key_pair(record.id_hash, u64(0x5449544C)), style=layout_style(.Row, grow=1, height=24))
	}
	_, close_clicked := icon_button(
		ui,
		"Dismiss notice",
		.Close,
		key=key_pair(record.id_hash, u64(0x434C4F53)),
		style=layout_style(.Row, width=28, height=28),
	)
	container_end(ui)
	if record.message_length > 0 {
		text(ui, notice_record_message(record), key=key_pair(record.id_hash, u64(0x4D534747)), style=layout_style(.Column, height=LAYOUT_SIZE_FIT_CONTENT))
	}
	if record.action_count > 0 {
		container_begin_simple(ui, .Container, label="notice-actions", key=key_pair(record.id_hash, u64(0x41435453)), style=layout_style(.Row, height=32, gap=5, align=.End))
		for index in 0..<record.action_count {
			// button() retains this label through reconciliation at end_frame.
			// Do not slice a stack copy of the inline action record.
			action := &record.actions[index]
			if button(
				ui,
				string(action.label[:action.label_length]),
				key=key_pair(record.id_hash, u64(0x100+index)),
				style=layout_style(.Row, width=96, height=30),
				variant=.Quiet,
			) {
				_ = notice_enqueue_action(rt, Notice_Action_Event{notice=record.handle, notice_id_hash=record.id_hash, action=action.id})
			}
		}
		container_end(ui)
	}
	container_end(ui)
	if close_clicked {
		if index := notice_find_hash(rt, record.id_hash); index >= 0 {
			notice_remove_at(rt, index)
			invalidate_root(rt, "notice close activated")
		}
		return true
	}
	return false
}

@(private)
notice_next_handle :: proc(rt: ^Runtime) -> Notice_Handle {
	if rt == nil { return 0 }
	rt.notice_handle_sequence += 1
	if rt.notice_handle_sequence == 0 { rt.notice_handle_sequence = 1 }
	return Notice_Handle(rt.notice_handle_sequence)
}

@(private)
notice_enqueue_action :: proc(rt: ^Runtime, event: Notice_Action_Event) -> bool {
	if rt == nil || event.action == Action_ID(0) || rt.notice_action_count >= len(rt.notice_actions) { return false }
	rt.notice_actions[rt.notice_action_write] = event
	rt.notice_action_write = (rt.notice_action_write+1)%len(rt.notice_actions)
	rt.notice_action_count += 1
	return true
}

@(private)
notice_find :: proc(rt: ^Runtime, id: string) -> int {
	for index in 0..<rt.notice_count {
		record := rt.notices[index]
		if len(id) != record.id_length { continue }
		matched := true
		for byte_index in 0..<record.id_length {
			if record.id[byte_index] != id[byte_index] { matched = false; break }
		}
		if matched { return index }
	}
	return -1
}

@(private)
notice_find_hash :: proc(rt: ^Runtime, id_hash: u64) -> int {
	for index in 0..<rt.notice_count { if rt.notices[index].id_hash == id_hash { return index } }
	return -1
}

@(private)
notice_remove_at :: proc(rt: ^Runtime, index: int) {
	if rt == nil || index < 0 || index >= rt.notice_count { return }
	for move_index in index..<rt.notice_count-1 { rt.notices[move_index] = rt.notices[move_index+1] }
	rt.notice_count -= 1
	rt.notices[rt.notice_count] = {}
}

@(private)
notice_next_sequence :: proc(rt: ^Runtime) -> u64 {
	rt.notice_sequence += 1
	if rt.notice_sequence == 0 { rt.notice_sequence = 1 }
	return rt.notice_sequence
}

@(private)
notice_copy_record_string :: proc(destination: []u8, destination_length: ^int, value: string) -> bool {
	if destination_length == nil || len(value) > len(destination) { return false }
	for index in 0..<len(value) { destination[index] = value[index] }
	destination_length^ = len(value)
	return true
}

@(private)
notice_string_hash :: proc(value: string) -> u64 {
	hash := u64(1469598103934665603)
	for byte in value {
		hash = (hash ~ u64(byte))*1099511628211
	}
	if hash == 0 { hash = 1 }
	return hash
}

@(private)
notice_record_title :: proc(record: ^Notice_Record) -> string { return string(record.title[:record.title_length]) }

@(private)
notice_record_message :: proc(record: ^Notice_Record) -> string { return string(record.message[:record.message_length]) }

@(private)
notice_record_details :: proc(record: ^Notice_Record) -> string { return string(record.details[:record.details_length]) }

@(private)
notice_severity_icon :: proc(severity: Notice_Severity) -> (Icon_ID, Style_Color_Role) {
	switch severity {
	case .Info: return .Info, .Accent
	case .Success: return .Check, .Success
	case .Warning: return .Warning, .Accent_Hover
	case .Error: return .Warning, .Danger
	}
	return .Info, .Muted_Text
}
