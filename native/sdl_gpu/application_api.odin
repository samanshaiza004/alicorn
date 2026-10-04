package alicorn_sdl_gpu

import alicorn "../../runtime"

// Application_Key is the small cross-platform command vocabulary exposed by
// the SDL host. Applications do not need to depend on SDL keycode constants
// just to implement navigation or a few commands.
Application_Key :: enum {
	Left,
	Right,
	Up,
	Down,
	Page_Up,
	Page_Down,
	Home,
	End,
	Fit_Selection,
	Command_1,
	Command_2,
	Command_3,
	Toggle,
	Open_Repository,
	Open_Command_Palette,
	Find,
	Workspace_Search,
	Context_Menu,
	Workspace_Rename,
	Find_Next,
	Find_Previous,
	Zoom_In,
	Zoom_Out,
	Zoom_Reset,
	Escape,
	Return,
}

// These keys may be offered to an application before native text editing so a
// focused text field can participate in transient UI such as a command picker.
application_key_can_preempt_text_field :: proc(key: Application_Key, composition_active := false) -> bool {
	if key == .Escape && composition_active { return false }
	if key == .Workspace_Rename && composition_active { return false }
	if composition_active && (key == .Zoom_In || key == .Zoom_Out || key == .Zoom_Reset) { return false }
	#partial switch key {
	case .Up, .Down, .Page_Up, .Page_Down, .Open_Repository, .Open_Command_Palette,
	     .Find, .Workspace_Search, .Workspace_Rename, .Context_Menu, .Find_Next, .Find_Previous,
	     .Zoom_In, .Zoom_Out, .Zoom_Reset, .Escape, .Return:
		return true
	case:
		return false
	}
}

native_text_field_return_key :: proc(shifted: bool) -> Application_Key {
	return .Find_Previous if shifted else .Return
}

// Application_Command_ID is a compatibility/transport alias for Alicorn's
// runtime-visible Action_ID. Platform-native menu item IDs stay host-private.
Application_Command_ID :: alicorn.Action_ID

Application_Menu_Item_Kind :: enum {
	Command,
	Separator,
	Submenu,
}

Application_Menu_Modifier :: enum {
	Primary,
	Shift,
	Alt,
	Super,
}

Application_Menu_Modifiers :: distinct bit_set[Application_Menu_Modifier; u8]

// A shortcut uses one printable key plus platform-neutral modifiers.
// Primary means Ctrl on Windows and Command on macOS; Super maps to the
// Windows key on Windows and Control on macOS.
Application_Menu_Shortcut :: struct {
	key:       rune,
	modifiers: Application_Menu_Modifiers,
}

// Menu descriptions are borrowed for the duration of Run. Labels and menu
// structure are snapshotted at startup; Action_State is read from
// the borrowed item storage whenever a native menu opens. Keep that storage
// stable and update its state on the application thread.
Application_Menu_Item :: struct {
	kind:     Application_Menu_Item_Kind,
	command:  Application_Command_ID,
	label:    string,
	state:    alicorn.Action_State,
	shortcut: Application_Menu_Shortcut,
	items:    []Application_Menu_Item,
}

Application_Menu :: struct {
	label: string,
	items: []Application_Menu_Item,
}

Window_Decoration_Mode :: enum {
	System,
	Integrated_Title_Bar,
}

Application_Build_Proc :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	logical_width, logical_height: int,
	dpi_scale: f32,
) -> alicorn.Node_ID

Application_Text_Change_Proc :: proc(state: rawptr, rt: ^alicorn.Runtime, change: alicorn.Text_Change)

Application_Text_Input_Event_Kind :: enum { Commit, Preedit, Cancel }

// SDL event text is borrowed for the callback. Preedit selection offsets are
// UTF-8 byte offsets, not SDL's character indexes.
Application_Text_Input_Event :: struct {
	kind: Application_Text_Input_Event_Kind,
	text: string,
	selection_start_byte: int,
	selection_end_byte: int,
}

Application_Text_Input_Proc :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	owner: alicorn.Node_ID,
	event: Application_Text_Input_Event,
)

// Application_Text_Navigation_Key is the host-normalized editing intent. The
// SDL host applies platform modifier conventions before delivering it, so an
// application need not interpret Ctrl/Option/Command itself.
Application_Text_Navigation_Key :: enum {
	Left, Right, Home, End, Up, Down, Page_Up, Page_Down, Backspace, Delete, Tab,
	Word_Left, Word_Right, Line_Start, Line_End, Document_Start, Document_End,
	Delete_Word_Backward, Delete_Word_Forward, Delete_Line_Backward, Delete_Line_Forward,
}

Application_Text_Key_Event :: struct {
	key:     Application_Text_Navigation_Key,
	shift:   bool,
	control: bool,
	alt:     bool,
	super:   bool,
}

Application_Text_Key_Proc :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	owner: alicorn.Node_ID,
	event: Application_Text_Key_Event,
) -> bool

Application_Key_Proc :: proc(state: rawptr, rt: ^alicorn.Runtime, key: Application_Key) -> bool

Application_Pointer_Proc :: proc(state: rawptr, rt: ^alicorn.Runtime, event: alicorn.Pointer_Event, target: alicorn.Node_ID)

Application_Drag_Proc :: proc(state: rawptr, rt: ^alicorn.Runtime, event: alicorn.Drag_Event)

Application_Scroll_Proc :: proc(state: rawptr, rt: ^alicorn.Runtime, event: alicorn.Scroll_Event)

Application_Tick_Proc :: proc(state: rawptr, rt: ^alicorn.Runtime)

Application_Start_Proc :: proc(state: rawptr, waker: Application_Waker)

Application_Services_Proc :: proc(state: rawptr, services: Application_Services)

Application_Wake_Proc :: proc(state: rawptr, rt: ^alicorn.Runtime)

Application_Scheduled_Wake_Proc :: proc(state: rawptr, rt: ^alicorn.Runtime, class: Scheduled_Wake_Class)

Application_Stop_Proc :: proc(state: rawptr)

Application_Menu_Command_Proc :: proc(state: rawptr, rt: ^alicorn.Runtime, command: Application_Command_ID)

Application_Close_Result :: enum {Allow, Defer}

Application_Close_Requested_Proc :: proc(state: rawptr, rt: ^alicorn.Runtime) -> Application_Close_Result

// Scheduled_Wake_Class distinguishes work that should run at a useful cadence
// from lower-fidelity work that can wait until the user has been quiet.
Scheduled_Wake_Class :: enum {Frequent, Opportunistic}

NATIVE_DRAG_AUTOSCROLL_INTERVAL_NS :: u64(16_000_000)

Application_Schedule_After_Proc :: proc(data: rawptr, class: Scheduled_Wake_Class, delay_ns: u64) -> bool

Application_Cancel_Scheduled_Proc :: proc(data: rawptr, class: Scheduled_Wake_Class) -> bool

Application_Scheduler_Stats_Proc :: proc(data: rawptr) -> Application_Scheduler_Stats

Application_Scheduler_Stats :: struct {
	scheduled:               u64,
	coalesced:               u64,
	frequent_wakes:          u64,
	opportunistic_wakes:     u64,
	opportunistic_deferrals: u64,
	maximum_lateness_ns:     u64,
	frequent_pending:        bool,
	opportunistic_pending:   bool,
}

// Application_Scheduler is a UI-thread-only service. It owns at most one
// replaceable deadline for each class; it is deliberately not a task queue.
Application_Scheduler :: struct {
	data:         rawptr,
	schedule:     Application_Schedule_After_Proc,
	cancel:       Application_Cancel_Scheduled_Proc,
	read_stats:   Application_Scheduler_Stats_Proc,
}

application_schedule_after :: proc(scheduler: Application_Scheduler, class: Scheduled_Wake_Class, delay_ns: u64) -> bool {
	return scheduler.schedule != nil && scheduler.schedule(scheduler.data, class, delay_ns)
}

application_cancel_scheduled_wake :: proc(scheduler: Application_Scheduler, class: Scheduled_Wake_Class) -> bool {
	return scheduler.cancel != nil && scheduler.cancel(scheduler.data, class)
}

application_scheduler_stats :: proc(scheduler: Application_Scheduler) -> Application_Scheduler_Stats {
	if scheduler.read_stats != nil { return scheduler.read_stats(scheduler.data) }
	return {}
}

// Application_Waker is an opaque, thread-safe request to wake the native
// application loop. The application can retain and call it from a worker
// thread; the SDL host owns the actual event transport.
Application_Wake_Callback :: proc(data: rawptr)

Application_Waker :: struct {
	data: rawptr,
	wake: Application_Wake_Callback,
}

application_wake :: proc(waker: Application_Waker) {
	if waker.wake != nil { waker.wake(waker.data) }
}

// Application is the intended public boundary for a small native Alicorn
// program. State is borrowed by callbacks for the duration of Run; retained
// runtime nodes never store this pointer.
Application :: struct {
	state:              rawptr,
	title:              string,
	width:              int,
	height:             int,
	menus:              []Application_Menu,
	window_decorations: Window_Decoration_Mode,
	build:              Application_Build_Proc,
	on_text_change:     Application_Text_Change_Proc,
	on_text_input:      Application_Text_Input_Proc,
	on_text_key:        Application_Text_Key_Proc,
	on_key:             Application_Key_Proc,
	on_pointer:         Application_Pointer_Proc,
	on_drag:            Application_Drag_Proc,
	on_scroll:          Application_Scroll_Proc,
	on_tick:            Application_Tick_Proc,
	on_services:        Application_Services_Proc,
	on_start:           Application_Start_Proc,
	on_dialog:          Application_Dialog_Proc,
	on_wake:            Application_Wake_Proc,
	on_scheduled_wake:  Application_Scheduled_Wake_Proc,
	on_close_requested: Application_Close_Requested_Proc,
	on_stop:            Application_Stop_Proc,
	on_menu_command:    Application_Menu_Command_Proc,
}
