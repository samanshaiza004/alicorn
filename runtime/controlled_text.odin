package alicorn

import "core:mem"
import "core:strings"

// Text_Field_Buffer is app-owned committed text with an explicit allocator.
// Keep one owner for each buffer; copying the struct copies its ownership.
Text_Field_Buffer :: struct {
	text: string,
	allocator: mem.Allocator,
	initialized: bool,
}

// text_field_buffer_init copies initial into allocator-owned storage. The
// allocator must outlive the buffer and must be suitable for repeated edits.
text_field_buffer_init :: proc(initial: string, allocator: mem.Allocator) -> (buffer: Text_Field_Buffer, ok: bool) {
	copy, err := strings.clone(initial, allocator)
	if err != nil { return }
	buffer = Text_Field_Buffer{text=copy, allocator=allocator, initialized=true}
	ok = true
	return
}

// text_field_buffer_set replaces the app-owned value after allocating the new
// contents successfully, then releases the previous value through its owner.
text_field_buffer_set :: proc(buffer: ^Text_Field_Buffer, value: string) -> bool {
	if buffer == nil || !buffer.initialized { return false }
	if buffer.text == value { return true }
	copy, err := strings.clone(value, buffer.allocator)
	if err != nil { return false }
	if len(buffer.text) > 0 { delete(buffer.text, buffer.allocator) }
	buffer.text = copy
	return true
}

text_field_buffer_destroy :: proc(buffer: ^Text_Field_Buffer) {
	if buffer == nil || !buffer.initialized { return }
	if len(buffer.text) > 0 { delete(buffer.text, buffer.allocator) }
	buffer^ = {}
}

controlled_text_field_state_clear :: proc(rt: ^Runtime, id: Node_ID) {
	if rt == nil || id == 0 { return }
	if state, found := rt.controlled_text_fields[id]; found {
		if len(state.model_text) > 0 { delete(state.model_text, rt.persistent_allocator) }
		delete_key(&rt.controlled_text_fields, id)
	}
}

controlled_text_field_note_edit :: proc(rt: ^Runtime, id: Node_ID) {
	if rt == nil || id == 0 { return }
	if state, found := rt.controlled_text_fields[id]; found {
		state.edit_revision += 1
		rt.controlled_text_fields[id] = state
	}
}

controlled_text_field_model_update :: proc(value: ^string, text: string, allocator: mem.Allocator) -> bool {
	if value == nil { return false }
	if value^ == text { return true }
	copy, err := strings.clone(text, allocator)
	if err != nil { return false }
	if len(value^) > 0 { delete(value^, allocator) }
	value^ = copy
	return true
}

Text_Field_Response :: struct {
	node: Node_ID,
	changed: bool,
	submitted: bool,
}

// text_field_controlled binds a retained Text_Field to an app-owned buffer.
// The pointer is used only during this call. Committed native edits are copied
// into the buffer on its next description; IME preedit remains runtime-owned
// transient state. The caller may use changed to update dependent app state.
text_field_controlled :: proc(
	ui: ^UI,
	buffer: ^Text_Field_Buffer,
	key: UI_Key = UI_Unkeyed{},
	style := DEFAULT_STYLE,
	loc := #caller_location,
	font := Font_Role.UI,
	text_style := DEFAULT_TEXT_STYLE,
) -> Text_Field_Response {
	result := Text_Field_Response{}
	if ui == nil || ui.runtime == nil || buffer == nil || !buffer.initialized || !ui.runtime.frame_open {
		return result
	}
	rt := ui.runtime
	source := resolve_source(Source_Site{}, "text_field", loc)
	result.node = emit_key(
		ui,
		.Text_Field,
		source,
		text=buffer.text,
		key=key,
		style=style,
		focusable=true,
		font=font,
		text_style=text_style,
	)
	if result.node == 0 { return result }
	state, state_found := rt.controlled_text_fields[result.node]
	synchronization_incomplete := false
	if retained, found := rt.nodes[result.node]; found && state_found {
		if state.edit_revision > state.seen_edit_revision &&
		   buffer.text == state.model_text && buffer.text != retained.text {
			if text_field_buffer_set(buffer, retained.text) {
				result.changed = true
			} else {
				append_diagnostic(rt, "controlled text field could not copy committed input into its app-owned buffer")
				synchronization_incomplete = true
			}
		}
		if state.submit_pending {
			result.submitted = true
			state.submit_pending = false
		}
	}
	if len(rt.pending) > 0 {
		item := &rt.pending[len(rt.pending)-1]
		if item.kind == .Description && item.description.id == result.node {
			item.description.text = buffer.text
		}
	}
	if !state_found { state = Controlled_Text_Field_State{} }
	if !controlled_text_field_model_update(&state.model_text, buffer.text, rt.persistent_allocator) {
		append_diagnostic(rt, "controlled text field could not retain its app-owned value snapshot")
		synchronization_incomplete = true
	}
	if !synchronization_incomplete { state.seen_edit_revision = state.edit_revision }
	rt.controlled_text_fields[result.node] = state
	if result.changed || result.submitted { interaction_consumption_note(rt) }
	return result
}

// text_field_request_submit queues a one-shot submit for a focused controlled
// field. The native host calls this after application key handling declines
// Return. Active IME composition retains ownership of Return.
text_field_request_submit :: proc(rt: ^Runtime, id: Node_ID) -> bool {
	if rt == nil || id == 0 || rt.focused != id { return false }
	node, found := rt.nodes[id]
	state, state_found := rt.controlled_text_fields[id]
	if !found || !state_found || !node_is_presentation_active(rt, id) ||
	   node.composition.active || state.submit_pending {
		return false
	}
	state.submit_pending = true
	rt.controlled_text_fields[id] = state
	invalidate_root(rt, "controlled text field submitted")
	return true
}
