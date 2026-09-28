package alicorn_sdl_gpu

import "core:testing"
import alicorn "../../runtime"

@(test)
test_flight_recorder_reads_samples_oldest_to_newest :: proc(t: ^testing.T) {
	rec: Native_Flight_Recorder
	_, found := native_flight_sample_at(&rec, 0)
	testing.expect(t, !found && native_flight_sample_count(&rec) == 0,
		"an empty recorder has no readable samples")

	native_flight_record(&rec, Native_DevTools_Sample{timestamp_ns=10, cause_id=3, cause_kind=.Keyboard, app_builds=1})
	native_flight_record(&rec, Native_DevTools_Sample{timestamp_ns=20, cause_id=4, cause_kind=.Text_Input, gpu_submissions=1})
	first, first_found := native_flight_sample_at(&rec, 0)
	last, last_found := native_flight_sample_at(&rec, 1)
	_, out_of_range := native_flight_sample_at(&rec, 2)
	testing.expect(t, first_found && first.timestamp_ns == 10 && first.cause_id == 3 && first.cause_kind == alicorn.Cause_Kind.Keyboard,
		"logical index zero should refer to the oldest sample")
	testing.expect(t, last_found && last.timestamp_ns == 20 && last.gpu_submissions == 1,
		"the newest sample should remain readable at the final logical index")
	testing.expect(t, !out_of_range && native_flight_sequence(&rec) == 2,
		"out-of-range reads fail and sequence counts all recorded samples")
}

@(test)
test_flight_recorder_overwrites_oldest_without_growing :: proc(t: ^testing.T) {
	rec: Native_Flight_Recorder
	for i in 0..<(NATIVE_FLIGHT_RECORDER_CAPACITY+3) {
		native_flight_record(&rec, Native_DevTools_Sample{timestamp_ns=u64(i), app_builds=u64(i)})
	}
	oldest, oldest_found := native_flight_sample_at(&rec, 0)
	newest, newest_found := native_flight_sample_at(&rec, NATIVE_FLIGHT_RECORDER_CAPACITY-1)
	testing.expect(t, native_flight_sample_count(&rec) == NATIVE_FLIGHT_RECORDER_CAPACITY,
		"retained history should remain bounded at its fixed capacity")
	testing.expect(t, oldest_found && oldest.timestamp_ns == 3 && oldest.app_builds == 3,
		"once full, writing must overwrite only the oldest sample")
	testing.expect(t, newest_found && newest.timestamp_ns == u64(NATIVE_FLIGHT_RECORDER_CAPACITY+2),
		"the final logical sample should be the latest recorded sample")
	testing.expect(t, native_flight_sequence(&rec) == u64(NATIVE_FLIGHT_RECORDER_CAPACITY+3),
		"total sequence should continue increasing after ring wraparound")
}

@(test)
test_flight_recorder_nil_access_is_safe :: proc(t: ^testing.T) {
	rec: ^Native_Flight_Recorder = nil
	native_flight_record(rec, {})
	_, found := native_flight_sample_at(rec, 0)
	testing.expect(t, !found && native_flight_sample_count(rec) == 0 && native_flight_sequence(rec) == 0,
		"nil recorder access should be a safe no-op")
}
