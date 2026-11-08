package testui

import "core:encoding/json"
import "core:mem"
import "core:strings"
import alicorn "alicorn:runtime"

REPLAY_LOG_SCHEMA_VERSION :: u32(1)
REPLAY_LOG_MAX_TURNS :: 256
REPLAY_LOG_MAX_TEXT_BYTES :: 65536
REPLAY_LOG_MAX_FILE_BYTES :: 1048576

Replay_Log_Error :: enum {
	None,
	Limit_Exceeded,
	Text_Limit_Exceeded,
	Allocation_Failed,
	Invalid_Data,
	Unsupported_Version,
	Redacted_Input,
	Diverged,
	Encoding_Failed,
}

Replay_Turn :: struct {
	input: Input,
	status: Status,
	turn: Turn_Report,
	turn_valid: bool,
	text_was_redacted: bool,
	text_bytes_redacted: int,
	semantic_text_was_redacted: bool,
	semantic_text_bytes_redacted: int,
}

// Replay_Log is a bounded, deterministic interaction recording. Text input is
// omitted unless include_text=true. A redacted log remains useful for review
// but intentionally cannot replay text events whose payload was omitted.
Replay_Log :: struct {
	include_text: bool,
	turns: [dynamic]Replay_Turn,
	allocator: mem.Allocator,
	text_bytes: int,
}

Replay_File :: struct {
	schema_version: u32,
	include_text: bool,
	turns: [dynamic]Replay_Turn,
}

replay_log_create :: proc(allocator := context.allocator, include_text := false) -> Replay_Log {
	return Replay_Log{
		include_text=include_text,
		turns=make([dynamic]Replay_Turn, 0, REPLAY_LOG_MAX_TURNS, allocator=allocator),
		allocator=allocator,
	}
}

replay_log_destroy :: proc(log: ^Replay_Log) {
	if log == nil { return }
	for &turn in log.turns {
		if len(turn.input.text) > 0 { delete(turn.input.text, log.allocator) }
		if len(turn.input.semantic_text) > 0 { delete(turn.input.semantic_text, log.allocator) }
		if len(turn.turn.message) > 0 { delete(turn.turn.message, log.allocator) }
	}
	delete(log.turns)
	log^ = {}
}

// replay_log_step applies one input through the ordinary headless host path,
// then records the sanitized input and its observable result. Recordings are
// capped at 256 turns and 64 KiB of opted-in text payload.
replay_log_step :: proc(
	log: ^Replay_Log,
	handle: ^Test_Handle($T),
	input: Input,
) -> (step_status: Status, log_error: Replay_Log_Error) {
	if log == nil || handle == nil || handle.runtime == nil { return .Invalid_Application, .Invalid_Data }
	if len(log.turns) >= REPLAY_LOG_MAX_TURNS { return .Invalid_Application, .Limit_Exceeded }
	text_bytes := len(input.text)
	semantic_text_bytes := len(input.semantic_text)
	new_payload_bytes := 0
	if log.include_text { new_payload_bytes = text_bytes + semantic_text_bytes }
	if new_payload_bytes > REPLAY_LOG_MAX_TEXT_BYTES-log.text_bytes {
		return .Invalid_Application, .Text_Limit_Exceeded
	}

	copy := input
	copy.text = ""
	copy.semantic_text = ""
	copy.pointer.target_key = alicorn.key_string("")
	if log.include_text {
		ok: bool
		copy.text, ok = replay_clone_string(input.text, log.allocator)
		if !ok { return .Invalid_Application, .Allocation_Failed }
		copy.semantic_text, ok = replay_clone_string(input.semantic_text, log.allocator)
		if !ok {
			if len(copy.text) > 0 { delete(copy.text, log.allocator) }
			return .Invalid_Application, .Allocation_Failed
		}
	}

	step_status = step(handle, input)
	entry := Replay_Turn{
		input=copy,
		status=step_status,
		turn_valid=step_status == .Ok,
		text_was_redacted=!log.include_text && text_bytes > 0,
		text_bytes_redacted=text_bytes if !log.include_text else 0,
		semantic_text_was_redacted=!log.include_text && semantic_text_bytes > 0,
		semantic_text_bytes_redacted=semantic_text_bytes if !log.include_text else 0,
	}
	if entry.turn_valid {
		entry.turn = handle.last_turn
		ok: bool
		entry.turn.message, ok = replay_clone_string(handle.last_turn.message, log.allocator)
		if !ok {
			if len(copy.text) > 0 { delete(copy.text, log.allocator) }
			if len(copy.semantic_text) > 0 { delete(copy.semantic_text, log.allocator) }
			return step_status, .Allocation_Failed
		}
	}
	append(&log.turns, entry)
	log.text_bytes += new_payload_bytes
	return step_status, .None
}

replay_clone_string :: proc(value: string, allocator: mem.Allocator) -> (copy: string, ok: bool) {
	if len(value) == 0 { return "", true }
	result, err := strings.clone(value, allocator)
	return result, err == nil
}

// replay_log_encode returns one bounded JSON document. The returned byte slice
// belongs to allocator and must be deleted by the caller. include_text logs
// contain the exact committed/preedit strings and should be handled as source
// documents; redacted logs omit those payloads by default.
replay_log_encode :: proc(
	log: ^Replay_Log,
	allocator := context.allocator,
) -> (data: []byte, log_error: Replay_Log_Error) {
	if log == nil || len(log.turns) > REPLAY_LOG_MAX_TURNS || log.text_bytes > REPLAY_LOG_MAX_TEXT_BYTES {
		return nil, .Invalid_Data
	}
	payload_bytes := 0
	file := Replay_File{
		schema_version=REPLAY_LOG_SCHEMA_VERSION,
		include_text=log.include_text,
		turns=log.turns,
	}
	for turn in file.turns {
		if (!file.include_text && (len(turn.input.text) > 0 || len(turn.input.semantic_text) > 0)) ||
		   (turn.text_was_redacted && len(turn.input.text) > 0) ||
		   (turn.semantic_text_was_redacted && len(turn.input.semantic_text) > 0) ||
		   (file.include_text && (turn.text_was_redacted || turn.semantic_text_was_redacted)) {
			return nil, .Invalid_Data
		}
		payload_bytes += len(turn.input.text) + len(turn.input.semantic_text)
	}
	if payload_bytes > REPLAY_LOG_MAX_TEXT_BYTES { return nil, .Text_Limit_Exceeded }
	encoded, err := json.marshal(file, allocator=allocator)
	if err != nil { return nil, .Encoding_Failed }
	if len(encoded) > REPLAY_LOG_MAX_FILE_BYTES {
		delete(encoded, allocator)
		return nil, .Limit_Exceeded
	}
	data = encoded
	return data, .None
}

// replay_log_decode rejects oversized or unsupported logs before playback and
// returns a log that owns every decoded input and report string through the
// supplied allocator.
replay_log_decode :: proc(
	data: []byte,
	allocator := context.allocator,
) -> (log: Replay_Log, log_error: Replay_Log_Error) {
	if len(data) == 0 || len(data) > REPLAY_LOG_MAX_FILE_BYTES { return {}, .Invalid_Data }
	file := Replay_File{}
	if err := json.unmarshal(data, &file, allocator=allocator); err != nil {
		replay_file_destroy(&file, allocator)
		return {}, .Invalid_Data
	}
	if file.schema_version != REPLAY_LOG_SCHEMA_VERSION {
		replay_file_destroy(&file, allocator)
		return {}, .Unsupported_Version
	}
	if len(file.turns) > REPLAY_LOG_MAX_TURNS {
		replay_file_destroy(&file, allocator)
		return {}, .Invalid_Data
	}
	log = Replay_Log{
		include_text=file.include_text,
		turns=file.turns,
		allocator=allocator,
	}
	file.turns = nil
	for turn in log.turns {
		if turn.input.kind == .Initial_Description || !replay_input_valid(turn.input) {
			replay_log_destroy(&log)
			return {}, .Invalid_Data
		}
		if turn.text_was_redacted && len(turn.input.text) != 0 ||
		   turn.semantic_text_was_redacted && len(turn.input.semantic_text) != 0 ||
		   (!log.include_text && (len(turn.input.text) > 0 || len(turn.input.semantic_text) > 0)) {
			replay_log_destroy(&log)
			return {}, .Invalid_Data
		}
		log.text_bytes += len(turn.input.text) + len(turn.input.semantic_text)
	}
	if log.text_bytes > REPLAY_LOG_MAX_TEXT_BYTES {
		replay_log_destroy(&log)
		return {}, .Invalid_Data
	}
	return log, .None
}

replay_file_destroy :: proc(file: ^Replay_File, allocator: mem.Allocator) {
	if file == nil { return }
	for &turn in file.turns {
		if len(turn.input.text) > 0 { delete(turn.input.text, allocator) }
		if len(turn.input.semantic_text) > 0 { delete(turn.input.semantic_text, allocator) }
		if len(turn.turn.message) > 0 { delete(turn.turn.message, allocator) }
	}
	delete(file.turns)
	file^ = {}
}

replay_input_valid :: proc(input: Input) -> bool {
	switch input.kind {
	case .Key, .Text_Commit, .Text_Preedit, .Text_Cancel, .Pointer, .Scroll,
	     .Semantic_Action, .Time_Advance:
	case .Initial_Description:
		return false
	}
	if input.kind == .Time_Advance && input.delta_ns > 0x7fffffffffffffff { return false }
	if !alicorn.number_is_finite(input.pointer.x) || !alicorn.number_is_finite(input.pointer.y) ||
	   !alicorn.number_is_finite(input.scroll.x) || !alicorn.number_is_finite(input.scroll.y) ||
	   !alicorn.number_is_finite(input.scroll.delta_x) || !alicorn.number_is_finite(input.scroll.delta_y) {
		return false
	}
	return true
}

// replay_log_play re-applies the complete log to an already initialized fresh
// handle. It validates semantic identity, focus, revision, target, and turn
// stabilization. Work deltas are diagnostic by default; compare_work enables
// exact counter comparison for same-build regression runs.
replay_log_play :: proc(
	log: ^Replay_Log,
	handle: ^Test_Handle($T),
	compare_work := false,
) -> (log_error: Replay_Log_Error, mismatch_turn: int) {
	if log == nil || handle == nil || handle.runtime == nil || len(log.turns) > REPLAY_LOG_MAX_TURNS {
		return .Invalid_Data, -1
	}
	payload_bytes := 0
	for turn in log.turns {
		if turn.text_was_redacted || turn.semantic_text_was_redacted { return .Redacted_Input, -1 }
		payload_bytes += len(turn.input.text) + len(turn.input.semantic_text)
	}
	if payload_bytes > REPLAY_LOG_MAX_TEXT_BYTES { return .Invalid_Data, -1 }
	for index in 0..<len(log.turns) {
		expected := log.turns[index]
		if !replay_input_valid(expected.input) { return .Invalid_Data, index }
		status := step(handle, expected.input)
		if status != expected.status { return .Diverged, index }
		if !expected.turn_valid { continue }
		actual := handle.last_turn
		if !replay_turn_equal(expected.turn, actual, compare_work) { return .Diverged, index }
	}
	return .None, -1
}

replay_turn_equal :: proc(expected, actual: Turn_Report, compare_work: bool) -> bool {
	if expected.input != actual.input || expected.key != actual.key || expected.key_valid != actual.key_valid ||
	   expected.descriptions != actual.descriptions || expected.stabilized != actual.stabilized ||
	   expected.layout_pending != actual.layout_pending ||
	   expected.focus_semantic_id != actual.focus_semantic_id ||
	   expected.pointer_target_semantic_id != actual.pointer_target_semantic_id ||
	   expected.semantic_revision_before != actual.semantic_revision_before ||
	   expected.semantic_revision != actual.semantic_revision ||
	   expected.cause_id != actual.cause_id || expected.cause_kind != actual.cause_kind ||
	   expected.action_id != actual.action_id {
		return false
	}
	if compare_work && expected.work != actual.work { return false }
	return true
}
