package alicorn_sdl_gpu

// Native dialogs are host services rather than retained-runtime nodes. SDL's
// file-dialog callback may run away from the application thread, so this file
// owns the copy-and-wake bridge that returns results to the main loop.
import "core:c"
import "core:mem"
import "base:runtime"
import "core:strings"
import "core:sync"
import alicorn "../../runtime"
import "vendor:sdl3"

Dialog_ID :: distinct u64

File_Dialog_Kind :: enum {
	Open_File,
	Open_Folder,
	Save_File,
}

Dialog_Filter :: struct {
	name:    string,
	// SDL extension tokens, separated by semicolons (for example "json",
	// "jpg;jpeg", or "*"). This is not a glob; do not include "*.".
	pattern: string,
}

File_Dialog_Request :: struct {
	id:               Dialog_ID,
	kind:             File_Dialog_Kind,
	title:            string,
	initial_location: string,
	filters:          []Dialog_Filter,
	allow_many:       bool,
	accept_label:     string,
	cancel_label:     string,
}

Dialog_Status :: enum {
	Accepted,
	Cancelled,
	Error,
}

File_Dialog_Result :: struct {
	id:              Dialog_ID,
	status:          Dialog_Status,
	paths:           [dynamic]string,
	selected_filter: int,
	error:           string,
}

Dialog_Message_Kind :: enum {
	Information,
	Warning,
	Error,
}

Dialog_Message_Button :: struct {
	id:             int,
	text:           string,
	default_return: bool,
	default_escape: bool,
}

Dialog_Message_Request :: struct {
	kind:    Dialog_Message_Kind,
	title:   string,
	message: string,
	buttons: []Dialog_Message_Button,
}

// Dialog_Service is an opaque host-owned service. File-dialog result strings
// and paths are borrowed only for the duration of Application.on_dialog; an
// application must clone any value it keeps.
Dialog_Service :: struct {
	handle:  rawptr,
	backend: Dialog_Service_Backend,
}

Dialog_Service_Backend :: enum {
	Native,
	Fake,
}

Application_Services :: struct {
	dialogs: Dialog_Service,
}

Application_Dialog_Proc :: proc(state: rawptr, rt: ^alicorn.Runtime, result: ^File_Dialog_Result)

// Dialog_Fake_Backend is a headless test service. It exercises the same
// accepted/cancelled/error callback shape and one-dialog busy policy without
// opening an OS panel. Complete it from the test/application thread with
// Dialog_Fake_Complete.
Dialog_Fake_Backend :: struct {
	allocator:       mem.Allocator,
	active:          bool,
	request_count:   int,
	busy_rejections: int,
	pending_id:      Dialog_ID,
	pending_kind:    File_Dialog_Kind,
	callback:        Application_Dialog_Proc,
	callback_state:  rawptr,
	callback_runtime: ^alicorn.Runtime,
}

Native_Dialog_String :: struct {
	bytes: []byte,
	cstr:  cstring,
}

Native_Dialog_Request :: struct {
	bridge:        ^Native_Dialog_Bridge,
	id:            Dialog_ID,
	props:         sdl3.PropertiesID,
	filters:       [dynamic]sdl3.DialogFileFilter,
	filter_names:  [dynamic]Native_Dialog_String,
	filter_patterns: [dynamic]Native_Dialog_String,
	title:         Native_Dialog_String,
	location:      Native_Dialog_String,
	accept:        Native_Dialog_String,
	cancel:        Native_Dialog_String,
}

Native_Dialog_Bridge :: struct {
	allocator:       mem.Allocator,
	mutex:           sync.Mutex,
	completions:     [dynamic]File_Dialog_Result,
	window:          ^sdl3.Window,
	waker:           Application_Waker,
	active:          bool,
	accepting:       bool,
	next_id:         u64,
	refs:            int,
}

native_dialog_string_make :: proc(value: string, allocator: mem.Allocator) -> (Native_Dialog_String, bool) {
	bytes, err := make([]byte, len(value)+1, allocator)
	if err != nil { return {}, false }
	copy(bytes, value)
	bytes[len(value)] = 0
	return Native_Dialog_String{bytes=bytes, cstr=cstring(&bytes[0])}, true
}

native_dialog_string_destroy :: proc(value: ^Native_Dialog_String, allocator: mem.Allocator) {
	if value == nil { return }
	if len(value.bytes) > 0 { delete(value.bytes, allocator) }
	value^ = {}
}

native_dialog_bridge_make :: proc(window: ^sdl3.Window, waker: Application_Waker) -> ^Native_Dialog_Bridge {
	bridge := new(Native_Dialog_Bridge, allocator=context.allocator)
	bridge.allocator = context.allocator
	bridge.completions = make([dynamic]File_Dialog_Result, 0, allocator=bridge.allocator)
	bridge.window = window
	bridge.waker = waker
	bridge.accepting = true
	bridge.refs = 1 // host ownership; each in-flight SDL callback owns another.
	return bridge
}

native_dialog_result_destroy :: proc(result: ^File_Dialog_Result, allocator: mem.Allocator) {
	if result == nil { return }
	for path in result.paths {
		if len(path) > 0 { delete(path, allocator) }
	}
	if len(result.paths) > 0 { delete(result.paths) }
	if len(result.error) > 0 { delete(result.error, allocator) }
	result^ = {}
}

native_dialog_bridge_destroy :: proc(bridge: ^Native_Dialog_Bridge) {
	if bridge == nil { return }
	for &result in bridge.completions {
		native_dialog_result_destroy(&result, bridge.allocator)
	}
	delete(bridge.completions)
	free(bridge, allocator=bridge.allocator)
}

native_dialog_bridge_release :: proc(bridge: ^Native_Dialog_Bridge) {
	if bridge == nil { return }
	should_destroy := false
	sync.mutex_lock(&bridge.mutex)
	bridge.refs -= 1
	if bridge.refs == 0 { should_destroy = true }
	sync.mutex_unlock(&bridge.mutex)
	if should_destroy { native_dialog_bridge_destroy(bridge) }
}

native_dialog_bridge_shutdown :: proc(bridge: ^Native_Dialog_Bridge) {
	if bridge == nil { return }
	sync.mutex_lock(&bridge.mutex)
	bridge.accepting = false
	bridge.active = false
	bridge.waker = {}
	sync.mutex_unlock(&bridge.mutex)
}

native_dialog_request_destroy :: proc(request: ^Native_Dialog_Request) {
	if request == nil { return }
	bridge := request.bridge
	allocator := bridge.allocator
	if request.props != sdl3.PropertiesID(0) { sdl3.DestroyProperties(request.props) }
	for &value in request.filter_names { native_dialog_string_destroy(&value, allocator) }
	for &value in request.filter_patterns { native_dialog_string_destroy(&value, allocator) }
	delete(request.filter_names)
	delete(request.filter_patterns)
	delete(request.filters)
	native_dialog_string_destroy(&request.title, allocator)
	native_dialog_string_destroy(&request.location, allocator)
	native_dialog_string_destroy(&request.accept, allocator)
	native_dialog_string_destroy(&request.cancel, allocator)
	free(request, allocator=allocator)
}

native_dialog_callback_path :: proc(value: cstring, allocator: mem.Allocator) -> (string, bool) {
	if value == nil { return "", false }
	copy, err := strings.clone(string(value), allocator)
	if err != nil { return "", false }
	return copy, true
}

@(private)
native_dialog_file_callback :: proc "c" (userdata: rawptr, filelist: [^]cstring, filter: c.int) {
	context = runtime.default_context()
	request := cast(^Native_Dialog_Request)userdata
	if request == nil || request.bridge == nil { return }
	bridge := request.bridge
	result := File_Dialog_Result{id=request.id, selected_filter=int(filter)}
	result.paths = make([dynamic]string, 0, allocator=bridge.allocator)
	if filelist == nil {
		result.status = .Error
		message := sdl3.GetError()
		if message != nil {
			result.error, _ = strings.clone(string(message), bridge.allocator)
		}
		if len(result.error) == 0 { result.error, _ = strings.clone("native file dialog failed", bridge.allocator) }
	} else if filelist[0] == nil {
		result.status = .Cancelled
	} else {
		result.status = .Accepted
		for i := 0; filelist[i] != nil; i += 1 {
			path, ok := native_dialog_callback_path(filelist[i], bridge.allocator)
			if ok { append(&result.paths, path) }
		}
		if len(result.paths) == 0 {
			result.status = .Error
			result.error, _ = strings.clone("native file dialog returned no paths", bridge.allocator)
		}
	}

	should_wake := false
	waker: Application_Waker
	sync.mutex_lock(&bridge.mutex)
	bridge.active = false
	if bridge.accepting {
		append(&bridge.completions, result)
		waker = bridge.waker
		should_wake = true
	} else {
		native_dialog_result_destroy(&result, bridge.allocator)
	}
	sync.mutex_unlock(&bridge.mutex)
	native_dialog_request_destroy(request)
	if should_wake { application_wake(waker) }
	native_dialog_bridge_release(bridge)
}

native_dialog_build_request :: proc(bridge: ^Native_Dialog_Bridge, request: File_Dialog_Request) -> (^Native_Dialog_Request, bool) {
	native := new(Native_Dialog_Request, allocator=bridge.allocator)
	native.bridge = bridge
	native.id = request.id
	native.filter_names = make([dynamic]Native_Dialog_String, 0, allocator=bridge.allocator)
	native.filter_patterns = make([dynamic]Native_Dialog_String, 0, allocator=bridge.allocator)
	native.filters = make([dynamic]sdl3.DialogFileFilter, 0, allocator=bridge.allocator)
	if native.id == Dialog_ID(0) {
		bridge.next_id += 1
		native.id = Dialog_ID(bridge.next_id)
	}
	for filter in request.filters {
		name, name_ok := native_dialog_string_make(filter.name, bridge.allocator)
		pattern, pattern_ok := native_dialog_string_make(filter.pattern, bridge.allocator)
		if !name_ok || !pattern_ok {
			native_dialog_string_destroy(&name, bridge.allocator)
			native_dialog_string_destroy(&pattern, bridge.allocator)
			native_dialog_request_destroy(native)
			return nil, false
		}
		append(&native.filter_names, name)
		append(&native.filter_patterns, pattern)
		append(&native.filters, sdl3.DialogFileFilter{name=name.cstr, pattern=pattern.cstr})
	}
	ok: bool
	native.title, ok = native_dialog_string_make(request.title, bridge.allocator)
	if !ok { native_dialog_request_destroy(native); return nil, false }
	native.location, ok = native_dialog_string_make(request.initial_location, bridge.allocator)
	if !ok { native_dialog_request_destroy(native); return nil, false }
	native.accept, ok = native_dialog_string_make(request.accept_label, bridge.allocator)
	if !ok { native_dialog_request_destroy(native); return nil, false }
	native.cancel, ok = native_dialog_string_make(request.cancel_label, bridge.allocator)
	if !ok { native_dialog_request_destroy(native); return nil, false }
	native.props = sdl3.CreateProperties()
	if native.props == sdl3.PropertiesID(0) { native_dialog_request_destroy(native); return nil, false }
	if len(native.filters) > 0 {
		if !sdl3.SetPointerProperty(native.props, sdl3.PROP_FILE_DIALOG_FILTERS_POINTER, rawptr(&native.filters[0])) {
			native_dialog_request_destroy(native); return nil, false
		}
	}
	if !sdl3.SetNumberProperty(native.props, sdl3.PROP_FILE_DIALOG_NFILTERS_NUMBER, sdl3.Sint64(len(native.filters))) ||
		!sdl3.SetPointerProperty(native.props, sdl3.PROP_FILE_DIALOG_WINDOW_POINTER, rawptr(bridge.window)) ||
		!sdl3.SetBooleanProperty(native.props, sdl3.PROP_FILE_DIALOG_MANY_BOOLEAN, request.allow_many) {
		native_dialog_request_destroy(native); return nil, false
	}
	if len(native.location.bytes) > 1 && !sdl3.SetStringProperty(native.props, sdl3.PROP_FILE_DIALOG_LOCATION_STRING, native.location.cstr) {
		native_dialog_request_destroy(native); return nil, false
	}
	if len(native.title.bytes) > 1 && !sdl3.SetStringProperty(native.props, sdl3.PROP_FILE_DIALOG_TITLE_STRING, native.title.cstr) {
		native_dialog_request_destroy(native); return nil, false
	}
	if len(native.accept.bytes) > 1 && !sdl3.SetStringProperty(native.props, sdl3.PROP_FILE_DIALOG_ACCEPT_STRING, native.accept.cstr) {
		native_dialog_request_destroy(native); return nil, false
	}
	if len(native.cancel.bytes) > 1 && !sdl3.SetStringProperty(native.props, sdl3.PROP_FILE_DIALOG_CANCEL_STRING, native.cancel.cstr) {
		native_dialog_request_destroy(native); return nil, false
	}
	return native, true
}

// ShowFileDialog returns false when the host is shutting down or another
// native file dialog is already active. The request is copied before SDL sees
// it, so every string/filter remains valid until the asynchronous callback.
ShowFileDialog :: proc(service: Dialog_Service, request: File_Dialog_Request) -> bool {
	if service.backend == .Fake {
		fake := cast(^Dialog_Fake_Backend)service.handle
		if fake == nil || fake.callback == nil || fake.active {
			if fake != nil && fake.active { fake.busy_rejections += 1 }
			return false
		}
		fake.active = true
		fake.request_count += 1
		fake.pending_id = request.id
		fake.pending_kind = request.kind
		return true
	}
	bridge := cast(^Native_Dialog_Bridge)service.handle
	if bridge == nil { return false }
	sync.mutex_lock(&bridge.mutex)
	if !bridge.accepting || bridge.active {
		sync.mutex_unlock(&bridge.mutex)
		return false
	}
	bridge.active = true
	bridge.refs += 1
	sync.mutex_unlock(&bridge.mutex)
	native, ok := native_dialog_build_request(bridge, request)
	if !ok {
		sync.mutex_lock(&bridge.mutex)
		bridge.active = false
		bridge.refs -= 1
		sync.mutex_unlock(&bridge.mutex)
		return false
	}
	type: sdl3.FileDialogType
	switch request.kind {
	case .Open_File: type = .OPENFILE
	case .Save_File: type = .SAVEFILE
	case .Open_Folder: type = .OPENFOLDER
	}
	sdl3.ShowFileDialogWithProperties(type, native_dialog_file_callback, rawptr(native), native.props)
	return true
}

Dialog_Fake_Service :: proc(
	fake: ^Dialog_Fake_Backend,
	callback: Application_Dialog_Proc,
	state: rawptr,
	rt: ^alicorn.Runtime,
	allocator := context.allocator,
) -> Dialog_Service {
	if fake == nil { return {} }
	fake^ = Dialog_Fake_Backend{
		allocator=allocator,
		callback=callback,
		callback_state=state,
		callback_runtime=rt,
	}
	return Dialog_Service{handle=rawptr(fake), backend=.Fake}
}

Dialog_Fake_Complete :: proc(fake: ^Dialog_Fake_Backend, status: Dialog_Status, path := "", error := "") -> bool {
	if fake == nil || !fake.active || fake.callback == nil { return false }
	fake.active = false
	result := File_Dialog_Result{id=fake.pending_id, status=status, selected_filter=-1}
	result.paths = make([dynamic]string, 0, allocator=fake.allocator)
	if len(path) > 0 {
		copy, clone_err := strings.clone(path, fake.allocator)
		if clone_err == nil { append(&result.paths, copy) }
	}
	if len(error) > 0 { result.error, _ = strings.clone(error, fake.allocator) }
	fake.callback(fake.callback_state, fake.callback_runtime, &result)
	native_dialog_result_destroy(&result, fake.allocator)
	return true
}

// Dispatch is called only by the SDL application thread. A result's paths and
// error remain borrowed through on_dialog and are released immediately after
// the callback returns.
native_dialog_dispatch :: proc(bridge: ^Native_Dialog_Bridge, application: ^Application, rt: ^alicorn.Runtime) {
	if bridge == nil || application == nil || application.on_dialog == nil { return }
	for {
		result: File_Dialog_Result
		have_result := false
		sync.mutex_lock(&bridge.mutex)
		if len(bridge.completions) > 0 {
			result = bridge.completions[0]
			ordered_remove(&bridge.completions, 0)
			have_result = true
		}
		sync.mutex_unlock(&bridge.mutex)
		if !have_result { break }
		application.on_dialog(application.state, rt, &result)
		native_dialog_result_destroy(&result, bridge.allocator)
	}
}

dialog_message_flags :: proc(kind: Dialog_Message_Kind) -> sdl3.MessageBoxFlags {
	switch kind {
	case .Warning: return sdl3.MessageBoxFlags{.WARNING}
	case .Error: return sdl3.MessageBoxFlags{.ERROR}
	case .Information: return sdl3.MessageBoxFlags{.INFORMATION}
	}
	return sdl3.MessageBoxFlags{.INFORMATION}
}

// ShowSimpleMessageBox is intentionally synchronous. Use it for genuinely
// modal alerts/confirmations, not for routine application errors.
ShowSimpleMessageBox :: proc(service: Dialog_Service, kind: Dialog_Message_Kind, title, message: string) -> bool {
	bridge := cast(^Native_Dialog_Bridge)service.handle
	if bridge == nil { return false }
	title_c, title_err := strings.clone_to_cstring(title, context.temp_allocator)
	message_c, message_err := strings.clone_to_cstring(message, context.temp_allocator)
	if title_err != nil || message_err != nil { return false }
	return sdl3.ShowSimpleMessageBox(dialog_message_flags(kind), title_c, message_c, bridge.window)
}

// ShowMessageBox supports application-defined button IDs. It blocks the main
// thread until the user responds, as required for a native modal confirmation.
ShowMessageBox :: proc(service: Dialog_Service, request: Dialog_Message_Request) -> (button_id: int, ok: bool) {
	bridge := cast(^Native_Dialog_Bridge)service.handle
	if bridge == nil { return 0, false }
	title_c, title_err := strings.clone_to_cstring(request.title, context.temp_allocator)
	message_c, message_err := strings.clone_to_cstring(request.message, context.temp_allocator)
	if title_err != nil || message_err != nil { return 0, false }
	buttons := make([]sdl3.MessageBoxButtonData, len(request.buttons), context.temp_allocator)
	for button, i in request.buttons {
		text, err := strings.clone_to_cstring(button.text, context.temp_allocator)
		if err != nil { return 0, false }
		flags := sdl3.MessageBoxButtonFlags{}
		if button.default_return { flags |= sdl3.MessageBoxButtonFlags{.RETURNKEY_DEFAULT} }
		if button.default_escape { flags |= sdl3.MessageBoxButtonFlags{.ESCAPEKEY_DEFAULT} }
		buttons[i] = sdl3.MessageBoxButtonData{flags=flags, buttonID=c.int(button.id), text=text}
	}
	button_ptr: [^]sdl3.MessageBoxButtonData
	if len(buttons) > 0 { button_ptr = &buttons[0] }
	data := sdl3.MessageBoxData{
		flags=dialog_message_flags(request.kind),
		window=bridge.window,
		title=title_c,
		message=message_c,
		numbuttons=c.int(len(buttons)),
		buttons=button_ptr,
	}
	selected: c.int
	return int(selected), sdl3.ShowMessageBox(data, &selected)
}
