package alicorn_sdl_gpu

import "core:fmt"
import "core:os"
import "core:strings"
import alicorn "../../runtime"

Native_Dialog_Fixture_State :: struct {
	diagnostics:     Application_Diagnostics,
	dialogs:         Dialog_Service,
	initial_location: string,
	last_result:     string,
	request_id:      u64,
	completed:       u64,
}

native_dialog_fixture_services :: proc(data: rawptr, services: Application_Services) {
	state := cast(^Native_Dialog_Fixture_State)data
	state.diagnostics = services.diagnostics
	state.dialogs = services.dialogs
}

native_dialog_fixture_open :: proc(state: ^Native_Dialog_Fixture_State) {
	state.request_id += 1
	application_diagnostic_event(state.diagnostics, "fixture.dialog.requested", state.request_id)
	if !ShowFileDialog(state.dialogs, File_Dialog_Request{
		id=Dialog_ID(state.request_id),
		kind=.Open_Folder,
		title="Alicorn native dialog fixture",
		initial_location=state.initial_location,
	}) {
		state.last_result = "Dialog request was rejected"
		application_diagnostic_event(state.diagnostics, "fixture.dialog.request_rejected", state.request_id)
	}
}

native_dialog_fixture_dialog :: proc(data: rawptr, rt: ^alicorn.Runtime, result: ^File_Dialog_Result) {
	state := cast(^Native_Dialog_Fixture_State)data
	state.completed += 1
	switch result.status {
	case .Accepted:
		state.last_result = fmt.tprintf("Accepted (%d item(s)); path omitted from fixture output", len(result.paths))
		application_diagnostic_event(state.diagnostics, "fixture.dialog.accepted", u64(result.id))
	case .Cancelled:
		state.last_result = "Cancelled"
		application_diagnostic_event(state.diagnostics, "fixture.dialog.cancelled", u64(result.id))
	case .Error:
		state.last_result = "Native dialog error"
		application_diagnostic_event(state.diagnostics, "fixture.dialog.error", u64(result.id))
	}
	alicorn.invalidate_root(rt, "native dialog fixture completed")
}

native_dialog_fixture_build :: proc(
	data: rawptr,
	rt: ^alicorn.Runtime,
	logical_width, _logical_height: int,
	_dpi_scale: f32,
) -> alicorn.Node_ID {
	state := cast(^Native_Dialog_Fixture_State)data
	ctx, should_build := alicorn.begin_frame(rt)
	if !should_build { return 0 }
	root := alicorn.container_begin(
		&ctx,
		.Root,
		label="native-dialog-fixture",
		style=alicorn.layout_style(width=f32(logical_width), grow=1, padding=24, gap=12),
	)
	alicorn.text(&ctx, "Alicorn native folder-dialog fixture")
	alicorn.text(&ctx, "This process has no Caliber or Punks backend. Open Folder, then cancel or choose a directory.")
	initial_label := "current working directory"
	if state.initial_location == "" { initial_label = "empty" }
	alicorn.text(&ctx, fmt.tprintf("Initial location: %s", initial_label))
	if alicorn.button(&ctx, "Open Folder", style=alicorn.layout_style(width=150, height=36)) {
		native_dialog_fixture_open(state)
	}
	alicorn.text(&ctx, fmt.tprintf("Completed dialogs: %d", state.completed))
	alicorn.text(&ctx, fmt.tprintf("Last result: %s", state.last_result))
	alicorn.text(&ctx, "The breadcrumb log excludes selected paths.")
	alicorn.container_end(&ctx)
	alicorn.end_frame(&ctx)
	return root
}

// RunDialogFixture starts the native host without Caliber or any application
// filesystem code. Use --dialog-initial=none, ordinary, or extended to choose
// the native dialog's starting location for a Windows-only reproduction pass.
RunDialogFixture :: proc() {
	initial_mode := "ordinary"
	for argument in os.args {
		prefix := "--dialog-initial="
		if strings.has_prefix(argument, prefix) { initial_mode = argument[len(prefix):] }
	}
	initial_location := ""
	switch initial_mode {
	case "none":
	case "ordinary", "extended":
		cwd, cwd_error := os.getwd(context.allocator)
		if cwd_error == nil {
			defer delete(cwd)
			initial_location = cwd
			if initial_mode == "extended" && len(cwd) >= 2 && cwd[1] == ':' && !strings.has_prefix(cwd, `\\?\`) {
				initial_location = fmt.tprintf(`\\?\%s`, cwd)
			}
		}
	case:
		fmt.eprintln("dialog fixture: expected --dialog-initial=none, ordinary, or extended")
		os.exit(2)
	}
	state := Native_Dialog_Fixture_State{initial_location=initial_location, last_result="not opened"}
	Run(Application{
		state=rawptr(&state),
		title="Alicorn Dialog Fixture",
		width=720,
		height=420,
		build=native_dialog_fixture_build,
		on_services=native_dialog_fixture_services,
		on_dialog=native_dialog_fixture_dialog,
	})
}
