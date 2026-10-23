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
	Tab_Next,
	Tab_Previous,
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
	     .Tab_Next, .Tab_Previous, .Zoom_In, .Zoom_Out, .Zoom_Reset, .Escape, .Return:
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
	// A nonzero command turns this top-level label into a direct action instead
	// of a popup menu. Its state and shortcut are borrowed like item state.
	command: Application_Command_ID,
	state: alicorn.Action_State,
	shortcut: Application_Menu_Shortcut,
}

Window_Decoration_Mode :: enum {
	System,
	Integrated_Title_Bar,
	Content_Title_Bar,
}

// Window_Chrome_Metrics reports measured native geometry for an application-
// authored titlebar header. Rectangles use top-left window-logical points. On
// macOS, content_start_x follows the native traffic lights. On Windows,
// content_start_x follows the native menu labels and content_end_x precedes
// the native caption buttons. The host keeps native-control hit testing.
Window_Chrome_Metrics :: struct {
	header: alicorn.Rect,
	native_controls: [3]alicorn.Rect,
	native_control_count: int,
	content_start_x: f32,
	content_end_x: f32,
	display_scale: f32,
	fullscreen: bool,
}

Window_Chrome_Metrics_Proc :: proc(state: rawptr, rt: ^alicorn.Runtime, metrics: Window_Chrome_Metrics)

Window_Chrome_Region_Kind :: enum { Interactive, Window_Drag }

WINDOW_CHROME_REGION_CAPACITY :: 16

// A chrome region references an ordinary retained node. The host resolves its
// finalized bounds after layout and retains only those geometry products. At
// most WINDOW_CHROME_REGION_CAPACITY regions are consumed per layout callback.
Window_Chrome_Region :: struct {
	node: alicorn.Node_ID,
	kind: Window_Chrome_Region_Kind,
}

Window_Chrome_Layout :: struct {
	header: alicorn.Node_ID,
	regions: []Window_Chrome_Region,
}

Window_Chrome_Layout_Proc :: proc(state: rawptr, rt: ^alicorn.Runtime) -> Window_Chrome_Layout

Application_Build_Proc :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	logical_width, logical_height: int,
	dpi_scale: f32,
) -> alicorn.Node_ID

// Application_Interaction_Update_Policy controls whether a consumed widget
// interaction during a description requests a corrective description.
// Stabilization remains bounded by the native host pass limit. Explicit is
// the default for applications that manage invalidation themselves.
Application_Interaction_Update_Policy :: enum {
	Explicit,
	Correct_After_Interaction,
}

// Application_Initialize_Proc runs on the application thread after Runtime
// creation and before host-default fonts and renderer resources initialize.
// It is the intended place to install embedded or disk-loaded font roles.
Application_Initialize_Proc :: proc(state: rawptr, rt: ^alicorn.Runtime)

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

// Application_Waker is a borrowed, thread-safe request to wake the native
// application loop. Applications may copy and call it from worker threads
// while Run is active. on_stop must stop and join every worker that can call
// the waker before returning; no copy may be used after on_stop returns. The
// host keeps its backing state alive through on_stop and retires it afterward.
Application_Wake_Callback :: proc(data: rawptr)

Application_Waker :: struct {
	data: rawptr,
	wake: Application_Wake_Callback,
}

application_wake :: proc(waker: Application_Waker) {
	if waker.wake != nil { waker.wake(waker.data) }
}

// Window_Chrome_Appearance is optional host presentation policy for integrated
// window chrome. The native host keeps ownership of rendering and interaction;
// applications may supply colors resolved from their active theme.
Window_Chrome_Appearance :: struct {
	defined:    bool,
	background: alicorn.Color,
	foreground: alicorn.Color,
}

Application_Chrome_Appearance_Proc :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
) -> Window_Chrome_Appearance

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
	// Content_Title_Bar is the macOS full-size-content mode. Integrated_Title_Bar
	// may also opt in to application-authored controls in the Windows native
	// titlebar band while the host retains its menu and caption buttons. In both
	// modes, the application describes ordinary retained nodes and declares
	// their node IDs through window_chrome_layout. Metrics are delivered before
	// the first build and when native geometry changes; the layout callback is
	// sampled after description and retained layout passes. Its returned slice
	// is borrowed only for that call.
	window_chrome_height: f32,
	window_chrome_metrics: Window_Chrome_Metrics_Proc,
	window_chrome_layout: Window_Chrome_Layout_Proc,
	// Optional theme-resolved appearance for host-owned integrated chrome.
	window_chrome_appearance: Application_Chrome_Appearance_Proc,
	interaction_update_policy: Application_Interaction_Update_Policy,
	on_initialize:      Application_Initialize_Proc,
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

// Application_Window_Description describes one secondary native window. Its
// Application callbacks own that window's procedural description and event
// handling. State should point at a window context that explicitly references
// shared domain state owned by the parent application; the parent state is not
// implicitly reused. The native host creates an independent Runtime and
// renderer set for this window, while the host retains ownership of the shared
// GPU device. `on_open_failed` runs only if setup fails before callbacks start.
Application_Window_Open_Failed_Proc :: proc(state: rawptr)

Application_Window_Description :: struct {
	application:  Application,
	width:        int,
	height:       int,
	always_on_top: bool,
	on_open_failed: Application_Window_Open_Failed_Proc,
}

Application_Window_Open_Proc :: proc(data: rawptr, description: Application_Window_Description) -> bool
Application_Window_Close_Proc :: proc(data: rawptr)
Application_Window_Topmost_Proc :: proc(data: rawptr, always_on_top: bool) -> bool
Application_Window_Set_Title_Proc :: proc(data: rawptr, title: string) -> bool

// Application_Window_Service currently supports one live secondary window.
// Applications can request it from a callback, but window creation and GPU
// resource initialization are deferred to the host's next event-loop safe point.
Application_Window_Service :: struct {
	data:  rawptr,
	open:  Application_Window_Open_Proc,
	close: Application_Window_Close_Proc,
	set_always_on_top: Application_Window_Topmost_Proc,
	set_title: Application_Window_Set_Title_Proc,
}

application_open_window :: proc(service: Application_Window_Service, description: Application_Window_Description) -> bool {
	return service.open != nil && service.open(service.data, description)
}

application_close_window :: proc(service: Application_Window_Service) {
	if service.close != nil { service.close(service.data) }
}

application_window_set_always_on_top :: proc(service: Application_Window_Service, always_on_top: bool) -> bool {
	return service.set_always_on_top != nil && service.set_always_on_top(service.data, always_on_top)
}

application_window_set_title :: proc(service: Application_Window_Service, title: string) -> bool {
	return service.set_title != nil && service.set_title(service.data, title)
}
