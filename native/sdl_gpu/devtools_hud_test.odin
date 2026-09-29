package alicorn_sdl_gpu

import "core:testing"

@(test)
test_devtools_hud_toggle_is_host_local_state :: proc(t: ^testing.T) {
	hud := Native_DevTools_HUD{}
	testing.expect(t, !hud.visible, "HUD starts hidden so applications remain visually unchanged")
	native_devtools_hud_toggle(&hud)
	testing.expect(t, hud.visible, "first toggle shows the host overlay")
	native_devtools_hud_toggle(&hud)
	testing.expect(t, !hud.visible, "second toggle hides the host overlay")
}

@(test)
test_devtools_hud_aggregates_recent_second_without_counting_old_samples :: proc(t: ^testing.T) {
	recorder: Native_Flight_Recorder
	native_flight_record(&recorder, Native_DevTools_Sample{
		timestamp_ns=900_000_000, app_builds=20, gpu_submissions=20,
	})
	native_flight_record(&recorder, Native_DevTools_Sample{
		timestamp_ns=1_500_000_000, cause_id=6, cause_kind=.Keyboard,
		app_builds=1, presentation_updates=2, gpu_submissions=1,
		host_wakes=1, surface_updates=3, persistent_allocations=4,
	})
	native_flight_record(&recorder, Native_DevTools_Sample{
		timestamp_ns=1_900_000_000, cause_id=7, cause_kind=.Text_Input,
		app_builds=2, presentation_updates=1, gpu_submissions=1,
		host_wakes=2, surface_updates=4, persistent_allocations=5,
	})

	recent, last, has_last := native_devtools_hud_recent(&recorder, 2_000_000_000)
	testing.expect(t, has_last && last.cause_id == 7 && last.cause_kind == .Text_Input,
		"HUD should report the newest recorded cause")
	testing.expect(t, recent.app_builds == 3 && recent.presentation_updates == 3 && recent.gpu_submissions == 2,
		"one-second summary should sum only samples inside its time window")
	testing.expect(t, recent.host_wakes == 3 && recent.surface_updates == 7,
		"one-second summary should include host wakes and surface-only updates")
	testing.expect(t, recent.persistent_allocations == 9,
		"one-second summary should include runtime persistent allocation calls")
}

@(test)
test_devtools_hud_deadline_ages_recent_counters_then_sleeps :: proc(t: ^testing.T) {
	recorder: Native_Flight_Recorder
	native_flight_record(&recorder, Native_DevTools_Sample{timestamp_ns=1_200_000_000, app_builds=1})
	native_flight_record(&recorder, Native_DevTools_Sample{timestamp_ns=1_750_000_000, cause_id=2, cause_kind=.Pointer, gpu_submissions=1})
	testing.expect(t, native_devtools_hud_next_wake_ns(&recorder, 2_000_000_000) == 2_200_000_000,
		"the oldest recent sample expiration should be the first HUD refresh deadline")
	testing.expect(t, native_devtools_hud_next_wake_ns(&recorder, 2_800_000_000) == 0,
		"once recent samples have expired and the HUD is idle, no polling deadline remains")
}

@(test)
test_devtools_hud_idle_transition_deadline :: proc(t: ^testing.T) {
	recorder: Native_Flight_Recorder
	native_flight_record(&recorder, Native_DevTools_Sample{timestamp_ns=1_800_000_000, app_builds=1})
	testing.expect(t, native_devtools_hud_next_wake_ns(&recorder, 2_000_000_000) == 2_300_000_000,
		"a recently active HUD should wake once to show its idle state")
}

@(test)
test_devtools_hud_includes_current_unrecorded_wake_preview :: proc(t: ^testing.T) {
	recorder: Native_Flight_Recorder
	native_flight_record(&recorder, Native_DevTools_Sample{
		timestamp_ns=900_000_000, cause_id=4, cause_kind=.Keyboard,
		app_builds=1, gpu_submissions=1, host_wakes=1,
	})
	preview := Native_DevTools_Sample{
		timestamp_ns=1_000_000_000, cause_id=5, cause_kind=.Text_Input,
		app_builds=1, presentation_updates=1, gpu_submissions=1, host_wakes=1,
	}
	recent, last, has_last := native_devtools_hud_recent(&recorder, 1_000_000_000, preview, true)
	testing.expect(t, has_last && last.cause_id == 5 && last.cause_kind == .Text_Input,
		"HUD should show the in-progress host wake without waiting for ring finalization")
	testing.expect(t, recent.app_builds == 2 && recent.gpu_submissions == 2 && recent.presentation_updates == 1,
		"preview metrics should be added once to the rolling totals")
}

@(test)
test_devtools_hud_preview_works_before_first_recorded_sample :: proc(t: ^testing.T) {
	preview := Native_DevTools_Sample{
		timestamp_ns=1_000,
		cause_id=9,
		cause_kind=.Keyboard,
		app_builds=1,
		host_wakes=1,
	}
	recent, last, has_last := native_devtools_hud_recent(nil, 1_000, preview, true)
	testing.expect(t, has_last && last.cause_id == 9 && last.cause_kind == .Keyboard,
		"the HUD should display an in-progress first interaction before ring finalization")
	testing.expect(t, recent.app_builds == 1 && recent.host_wakes == 1,
		"the preview should contribute to recent totals even when the recorder is empty")
}

@(test)
test_devtools_activity_classes_separate_host_presentation_app_and_surface :: proc(t: ^testing.T) {
	host := Native_DevTools_Sample{host_wakes=1, pointer_events=6}
	present := Native_DevTools_Sample{presentation_updates=1, gpu_submissions=1, paint_visits=2, hover_target_transitions=1}
	app := Native_DevTools_Sample{app_builds=1, presentation_updates=1, layout_visits=3}
	surface := Native_DevTools_Sample{surface_updates=1, presentation_updates=1, gpu_submissions=1}
	testing.expect(t, native_devtools_activity_class(host) == .Host,
		"input wakes with no runtime work are classified as HOST")
	testing.expect(t, native_devtools_activity_class(present) == .Present,
		"retained paint work is classified as PRESENT")
	testing.expect(t, native_devtools_activity_class(app) == .App,
		"application description work is classified as APP")
	testing.expect(t, native_devtools_activity_class(surface) == .Surface,
		"custom-surface-only updates are not mislabeled as retained presentation")
	testing.expect(t, native_devtools_activity_class_name(.Host) == "host" &&
		native_devtools_activity_class_label(.Present) == "PRESENT",
		"activity class has stable timeline and HUD spellings")
}

@(test)
test_devtools_hud_latest_activity_class_and_idle_timeout :: proc(t: ^testing.T) {
	recorder: Native_Flight_Recorder
	native_flight_record(&recorder, Native_DevTools_Sample{timestamp_ns=1_000_000_000, host_wakes=1, pointer_events=3})
	testing.expect(t, native_devtools_hud_activity_class(&recorder, 1_100_000_000) == .Host,
		"the HUD reflects the latest host-only pointer activity")
	testing.expect(t, native_devtools_hud_activity_class(&recorder, 1_500_000_000) == .Idle,
		"the HUD returns to IDLE at the existing one-shot inactivity deadline")
	preview := Native_DevTools_Sample{timestamp_ns=1_600_000_000, app_builds=1}
	testing.expect(t, native_devtools_hud_activity_class(&recorder, 1_600_000_000, preview, true) == .App,
		"the in-progress app wake is reflected before recorder finalization")
	zero_time_recorder: Native_Flight_Recorder
	native_flight_record(&zero_time_recorder, Native_DevTools_Sample{host_wakes=1, pointer_events=1})
	testing.expect(t, native_devtools_hud_activity_class(&zero_time_recorder, 1) == .Host &&
		native_devtools_hud_next_wake_ns(&zero_time_recorder, 1) == NATIVE_DEVTOOLS_HUD_IDLE_AFTER_NS,
		"timestamp zero remains a valid event time for classification and the one-shot idle deadline")
}
