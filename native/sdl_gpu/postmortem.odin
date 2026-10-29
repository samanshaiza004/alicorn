package alicorn_sdl_gpu

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:time"
import "vendor:sdl3"

// Native_Breadcrumb_Recorder writes rare lifecycle events as they occur. It is
// opt-in through --diagnostics or --diagnostic-events and never records paths
// or arbitrary event payloads.
Native_Breadcrumb_Recorder :: struct {
	mutex: sync.Mutex,
	file:  ^os.File,
	refs:  int,
	failed: bool,
}

native_breadcrumb_event_name_valid :: proc(name: string) -> bool {
	if len(name) == 0 || len(name) > 96 { return false }
	for ch in name {
		if !('a' <= ch && ch <= 'z') &&
		   !('0' <= ch && ch <= '9') &&
		   ch != '.' && ch != '_' && ch != '-' {
			return false
		}
	}
	return true
}

native_breadcrumb_json_line :: proc(
	timestamp_utc: string,
	monotonic_ns: u64,
	thread_id: int,
	source, name: string,
	request_id: u64,
) -> string {
	if !native_breadcrumb_event_name_valid(name) { return "" }
	return fmt.tprintf(
		`{"schema":1,"timestamp_utc":"%s","monotonic_ns":%d,"thread_id":%d,"source":"%s","event":"%s","request_id":%d}` + "\n",
		timestamp_utc, monotonic_ns, thread_id, source, name, request_id,
	)
}

native_breadcrumb_event :: proc(
	recorder: ^Native_Breadcrumb_Recorder,
	source, name: string,
	request_id: u64 = 0,
) {
	if recorder == nil || !native_breadcrumb_event_name_valid(name) { return }
	stamp, _, timestamp_ok := native_diagnostics_timestamp(time.now())
	if !timestamp_ok { return }
	monotonic_ns := u64(sdl3.GetTicksNS())
	thread_id := sync.current_thread_id()
	line := native_breadcrumb_json_line(stamp, monotonic_ns, thread_id, source, name, request_id)

	write_failed := false
	sync.mutex_lock(&recorder.mutex)
	if recorder.file != nil && !recorder.failed {
		_, write_error := os.write_string(recorder.file, line)
		flush_error := os.flush(recorder.file)
		sync_error := os.sync(recorder.file)
		if write_error != nil || flush_error != nil || sync_error != nil {
			recorder.failed = true
			write_failed = true
		}
	}
	sync.mutex_unlock(&recorder.mutex)
	if write_failed { fmt.eprintln("alicorn_diagnostics", "breadcrumb_write_failed") }
}

native_breadcrumb_application_event :: proc(data: rawptr, name: string, request_id: u64) {
	native_breadcrumb_event(cast(^Native_Breadcrumb_Recorder)data, "application", name, request_id)
}

native_breadcrumbs_retain :: proc(recorder: ^Native_Breadcrumb_Recorder) {
	if recorder == nil { return }
	sync.mutex_lock(&recorder.mutex)
	recorder.refs += 1
	sync.mutex_unlock(&recorder.mutex)
}

native_breadcrumbs_release :: proc(recorder: ^Native_Breadcrumb_Recorder) {
	if recorder == nil { return }
	should_destroy := false
	sync.mutex_lock(&recorder.mutex)
	recorder.refs -= 1
	should_destroy = recorder.refs == 0
	file := recorder.file if should_destroy else nil
	if should_destroy { recorder.file = nil }
	sync.mutex_unlock(&recorder.mutex)
	if should_destroy {
		if file != nil { _ = os.close(file) }
		free(recorder, allocator=context.allocator)
	}
}

native_breadcrumbs_start :: proc(options: Native_Diagnostics_Options) -> ^Native_Breadcrumb_Recorder {
	if !options.breadcrumbs_enabled { return nil }
	root := options.capture_dir
	if root == "" {
		root, _ = native_diagnostics_default_capture_dir()
		if root == "" { return nil }
		defer delete(root)
	}
	stamp, _, stamp_ok := native_diagnostics_timestamp(time.now())
	if !stamp_ok { return nil }
	directory, _, directory_ok, directory_failure := native_diagnostics_create_bundle(root, fmt.tprintf("events-%s", stamp), 1)
	if !directory_ok {
		fmt.eprintln("alicorn_diagnostics", "events_unavailable", directory_failure)
		return nil
	}
	path := fmt.tprintf("%s/events.jsonl", directory)
	file, open_error := os.open(path, {.Write, .Create, .Append, .Sync}, os.Permissions{.Read_User, .Write_User})
	if open_error != nil {
		fmt.eprintln("alicorn_diagnostics", "events_file_unavailable", open_error)
		return nil
	}
	recorder := new(Native_Breadcrumb_Recorder, allocator=context.allocator)
	recorder.file = file
	recorder.refs = 1
	native_breadcrumb_event(recorder, "alicorn", "session.started")
	fmt.println("alicorn_diagnostics", "events", path)
	return recorder
}
