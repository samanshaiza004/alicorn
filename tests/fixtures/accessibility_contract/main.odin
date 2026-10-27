package main

// Minimal native fixture for querying Alicorn's exported platform
// accessibility tree. The query probes use UIA/AX APIs only; they do not
// depend on Alicorn semantic IDs or runtime internals.

import "core:fmt"
import "core:mem"
import alicorn "alicorn:runtime"
import ui "alicorn:ui"

App :: struct {
	text: alicorn.Text_Field_Buffer,
	text_semantic_id: alicorn.Semantic_ID,
	count: int,
	action_disabled: bool,
}

accessibility_contract_adopt_requests :: proc(app: ^App, rt: ^alicorn.Runtime) -> (adopted_value: bool) {
	if app == nil || rt == nil || !alicorn.semantic_id_is_valid(app.text_semantic_id) { return }
	for {
		event, found := alicorn.semantic_request_pop(rt)
		if !found { break }
		if event.kind == .Perform && event.id == app.text_semantic_id && event.action == .Set_Value {
			adopted_value = alicorn.text_field_buffer_set(&app.text, event.text_value) || adopted_value
		}
		alicorn.semantic_request_event_destroy(rt, &event)
	}
	return
}

render :: proc(app: ^App, ctx: ^ui.UI) {
	// Accessibility value changes are requests to the application. Adopt the
	// request into the app-owned buffer before describing the next frame.
	_ = accessibility_contract_adopt_requests(app, ctx.runtime)
	if ui.column(ctx, grow=1, padding=24, gap=12, label="accessibility-contract-content") {
		ui.text(ctx, "Accessibility contract fixture", size=24)
		ui.text(ctx, "Use the native query probe to inspect this window, edit the field, and invoke the button.")

		if ui.button(
			ctx,
			"Increment value",
			key=alicorn.key_string("accessibility-contract-increment"),
			width=220,
			height=40,
		) {
			app.count += 1
		}
		if ui.button(
			ctx,
			"Toggle action disabled",
			key=alicorn.key_string("accessibility-contract-toggle-disabled"),
			width=220,
			height=40,
		) {
			app.action_disabled = !app.action_disabled
		}
		guarded_activated := ui.button(
			ctx,
			"Guarded action",
			key=alicorn.key_string("accessibility-contract-guarded-action"),
			width=220,
			height=40,
		)
		guarded_states: alicorn.Semantic_States
		guarded_actions: alicorn.Semantic_Actions
		if app.action_disabled {
			guarded_states = alicorn.semantic_states_add(guarded_states, .Disabled)
		} else {
			guarded_actions = alicorn.semantic_actions_add(guarded_actions, .Press)
		}
		_ = alicorn.semantic_description(
			ctx,
			.Button,
			"Guarded action",
			states=guarded_states,
			actions=guarded_actions,
		)
		if guarded_activated && !app.action_disabled {
			app.count += 1
		}

		status_value := fmt.tprintf("%d", app.count)
		ui.text(ctx, fmt.tprintf("Action count: %d", app.count), key=alicorn.key_string("accessibility-contract-status"))
		_ = alicorn.semantic_description(ctx, .Status, "Action count", value=status_value)

		field := alicorn.text_field_controlled(
			ctx,
			&app.text,
			key=alicorn.key_string("accessibility-contract-text"),
			style=alicorn.layout_style(height=40),
		)
		app.text_semantic_id = alicorn.semantic_visual_id(field.node)
		_ = alicorn.semantic_description(
			ctx,
			.Text_Field,
			"Contract text field",
			value=app.text.text,
			actions=alicorn.semantic_actions_add(
				alicorn.semantic_actions_add({}, .Focus),
				.Set_Value,
			),
		)
	}
}

main :: proc() {
	text, ok := alicorn.text_field_buffer_init("Editable value", context.allocator)
	if !ok { return }
	app := App{text=text}
	defer alicorn.text_field_buffer_destroy(&app.text)

	ui.run(
		&app,
		render,
		title="Alicorn Accessibility Contract",
		width=760,
		height=420,
	)
}
