package testui

import "core:strings"
import "core:testing"
import alicorn "alicorn:runtime"

Replay_Button_App :: struct {
	activations: int,
}

replay_button_render :: proc(app: ^Replay_Button_App, ui: ^alicorn.UI) {
	if alicorn.button(ui, "Advance", key=alicorn.key_string("replay.advance"),
		style=alicorn.layout_style(.Row, width=160, height=36)) {
		app.activations += 1
	}
}

replay_pointer_turn :: proc(log: ^Replay_Log, handle: ^Test_Handle(Replay_Button_App), kind: alicorn.Pointer_Kind, x, y: f32) -> bool {
	status, log_error := replay_log_step(log, handle, Input{
		kind=.Pointer,
		pointer=alicorn.Pointer_Event{kind=kind, x=x, y=y, button=alicorn.POINTER_BUTTON_PRIMARY},
	})
	return status == .Ok && log_error == .None
}

@(test)
test_replay_log_round_trips_public_input_identity_revision_and_work :: proc(t: ^testing.T) {
	app := Replay_Button_App{}
	h, status := open(&app, replay_button_render, width=240, height=100)
	if !testing.expect(t, status == .Ok, "the replay fixture should open headlessly") { return }
	defer close(&h)
	button := find(&h, Query{role=.Button, name="Advance", match_role=true, match_name=true})
	if !testing.expect(t, button.match == .Unique && button.element.has_bounds,
		"the fixture button should be exposed through the public semantic query") {
		destroy_find_result(&button)
		return
	}
	x := button.element.bounds.x + button.element.bounds.w*0.5
	y := button.element.bounds.y + button.element.bounds.h*0.5
	destroy_find_result(&button)

	log := replay_log_create()
	defer replay_log_destroy(&log)
	if !testing.expect(t, replay_pointer_turn(&log, &h, .Down, x, y), "pointer down should be recorded through the ordinary input path") ||
	   !testing.expect(t, replay_pointer_turn(&log, &h, .Up, x, y), "pointer up should activate and be recorded") {
		return
	}
	if !testing.expect(t, app.activations == 1 && len(log.turns) == 2,
		"the recorded interaction should include the app-visible activation") { return }
	entry := log.turns[1]
	if !testing.expect(t, entry.turn.pointer_target_semantic_id.value != 0,
		"the turn should retain a stable semantic target") { return }
	if !testing.expect(t, entry.turn.cause_kind == .Pointer && entry.turn.cause_id != 0,
		"the turn should retain its pointer cause") { return }
	if !testing.expect(t, entry.turn.semantic_revision > 0 &&
		(entry.turn.work.reconcile_nodes_visited + entry.turn.work.layout_nodes_visited +
		 entry.turn.work.paint_nodes_visited) > 0,
		"the turn should record revision and stage-work deltas") { return }

	encoded, encode_error := replay_log_encode(&log)
	if !testing.expect(t, encode_error == .None && len(encoded) > 0, "the bounded recording should serialize to JSON") { return }
	defer delete(encoded)
	decoded, decode_error := replay_log_decode(encoded)
	if !testing.expect(t, decode_error == .None && len(decoded.turns) == 2, "the JSON log should decode into an owned replay") { return }
	defer replay_log_destroy(&decoded)

	replayed_app := Replay_Button_App{}
	replayed, open_status := open(&replayed_app, replay_button_render, width=240, height=100)
	if !testing.expect(t, open_status == .Ok, "a fresh handle should initialize for replay") { return }
	defer close(&replayed)
	play_error, mismatch := replay_log_play(&decoded, &replayed, compare_work=true)
	testing.expect(t, play_error == .None && mismatch == -1 && replayed_app.activations == 1,
		"the serialized pointer sequence should replay identities, work counters, and app state")

	negative_app := Replay_Button_App{}
	negative, negative_status := open(&negative_app, replay_button_render, width=240, height=100)
	if !testing.expect(t, negative_status == .Ok, "the negative-control handle should initialize") { return }
	defer close(&negative)
	decoded.turns[0].turn.pointer_target_semantic_id.value += 1
	negative_error, negative_turn := replay_log_play(&decoded, &negative)
	testing.expect(t, negative_error == .Diverged && negative_turn == 0 && negative_app.activations == 0,
		"the replay should expose a deliberately changed semantic target before the activation event")
}

@(test)
test_replay_log_redacts_text_by_default_and_requires_opt_in_for_text_replay :: proc(t: ^testing.T) {
	secret := "private-source-fragment-7f2a"
	app := Harness_Test_App{}
	h, status := open(&app, harness_test_render, width=240, height=120,
		on_text_change=harness_test_text_changed)
	if !testing.expect(t, status == .Ok, "the text fixture should open") { return }
	defer close(&h)
	defer if len(app.name) > 0 { delete(app.name) }
	field := find(&h, Query{role=.Text_Field, name="Name", match_role=true, match_name=true})
	if !testing.expect(t, field.match == .Unique, "the text field should be semantically discoverable") {
		destroy_find_result(&field)
		return
	}
	x := field.element.bounds.x + field.element.bounds.w*0.5
	y := field.element.bounds.y + field.element.bounds.h*0.5
	destroy_find_result(&field)
	if !testing.expect(t, click_at(&h, x, y) == .Ok, "the text field should accept focus") { return }

	redacted := replay_log_create()
	defer replay_log_destroy(&redacted)
	step_status, log_error := replay_log_step(&redacted, &h, Input{kind=.Text_Commit, text=secret})
	if !testing.expect(t, step_status == .Ok && log_error == .None &&
		redacted.turns[0].text_was_redacted && redacted.turns[0].text_bytes_redacted == len(secret),
		"default logs should record text length but omit document contents") { return }
	encoded, redacted_encode_error := replay_log_encode(&redacted)
	if !testing.expect(t, redacted_encode_error == .None && !strings.contains(string(encoded), secret),
		"serialized default logs must not contain committed user text") { return }
	defer delete(encoded)

	blocked_app := Harness_Test_App{}
	blocked, blocked_status := open(&blocked_app, harness_test_render, width=240, height=120,
		on_text_change=harness_test_text_changed)
	if !testing.expect(t, blocked_status == .Ok, "a fresh handle should open for the redaction guard") { return }
	defer close(&blocked)
	play_error, mismatch := replay_log_play(&redacted, &blocked)
	testing.expect(t, play_error == .Redacted_Input && mismatch == -1 && blocked_app.name == "",
		"a redacted log must refuse replay before mutating application state")

	private_log := replay_log_create(include_text=true)
	defer replay_log_destroy(&private_log)
	// Re-run the same focus and input sequence against a clean handle so the
	// opted-in fixture is an independently replayable recording.
	private_app := Harness_Test_App{}
	private_handle, private_status := open(&private_app, harness_test_render, width=240, height=120,
		on_text_change=harness_test_text_changed)
	if !testing.expect(t, private_status == .Ok, "the explicit text-capture fixture should open") { return }
	defer close(&private_handle)
	defer if len(private_app.name) > 0 { delete(private_app.name) }
	private_field := find(&private_handle, Query{role=.Text_Field, name="Name", match_role=true, match_name=true})
	if !testing.expect(t, private_field.match == .Unique, "the private fixture field should be found") {
		destroy_find_result(&private_field)
		return
	}
	private_x := private_field.element.bounds.x + private_field.element.bounds.w*0.5
	private_y := private_field.element.bounds.y + private_field.element.bounds.h*0.5
	destroy_find_result(&private_field)
	if !testing.expect(t, click_at(&private_handle, private_x, private_y) == .Ok,
		"the private fixture field should accept focus") { return }
	step_status, log_error = replay_log_step(&private_log, &private_handle, Input{kind=.Text_Commit, text=secret})
	if !testing.expect(t, step_status == .Ok && log_error == .None && private_app.name == secret,
		"opt-in text recording should preserve the exact application input") { return }
	private_bytes, private_encode_error := replay_log_encode(&private_log)
	if !testing.expect(t, private_encode_error == .None && strings.contains(string(private_bytes), secret),
		"explicit text capture should serialize the input for faithful replay") { return }
	defer delete(private_bytes)
	private_decoded, private_decode_error := replay_log_decode(private_bytes)
	if !testing.expect(t, private_decode_error == .None, "the explicit text log should decode") { return }
	defer replay_log_destroy(&private_decoded)

	final_app := Harness_Test_App{}
	final_handle, final_status := open(&final_app, harness_test_render, width=240, height=120,
		on_text_change=harness_test_text_changed)
	if !testing.expect(t, final_status == .Ok, "a fresh text handle should open for faithful replay") { return }
	defer close(&final_handle)
	defer if len(final_app.name) > 0 { delete(final_app.name) }
	final_field := find(&final_handle, Query{role=.Text_Field, name="Name", match_role=true, match_name=true})
	if !testing.expect(t, final_field.match == .Unique, "the final fixture field should be found") {
		destroy_find_result(&final_field)
		return
	}
	final_x := final_field.element.bounds.x + final_field.element.bounds.w*0.5
	final_y := final_field.element.bounds.y + final_field.element.bounds.h*0.5
	destroy_find_result(&final_field)
	if !testing.expect(t, click_at(&final_handle, final_x, final_y) == .Ok,
		"the final text field should accept focus") { return }
	play_error, mismatch = replay_log_play(&private_decoded, &final_handle)
	testing.expect(t, play_error == .None && mismatch == -1 && final_app.name == secret,
		"opt-in text payload should reproduce the same document edit")
}
