package main

import "core:fmt"
import alicorn "alicorn:runtime"
import host "alicorn:native/sdl_gpu"
import ui "alicorn:ui"

VOICEOVER_SEMANTIC_NAMESPACE :: u64(0x564F4943454F5601)
VOICEOVER_FIELD_ID :: alicorn.Semantic_ID{namespace=VOICEOVER_SEMANTIC_NAMESPACE, value=1}
VOICEOVER_SLIDER_ID :: alicorn.Semantic_ID{namespace=VOICEOVER_SEMANTIC_NAMESPACE, value=2}
VOICEOVER_LIST_ID :: alicorn.Semantic_ID{namespace=VOICEOVER_SEMANTIC_NAMESPACE, value=3}
VOICEOVER_LIST_ITEM_NAMESPACE :: u64(0x564F4943454F5602)
VOICEOVER_LIST_COUNT :: 18

Announcement_Request :: enum { None, Polite_Status, Assertive_Alert, Dismiss }

App :: struct {
	name: alicorn.Text_Field_Buffer,
	page: int,
	checked: bool,
	level: f32,
	selected_option: u64,
	selected_item: int,
	list_scroll_id: alicorn.Node_ID,
	activation_count: int,
	validation_invalid: bool,
	show_dialog: bool,
	field_id: alicorn.Semantic_ID,
	slider_id: alicorn.Semantic_ID,
	waker: host.Application_Waker,
	announcement_request: Announcement_Request,
	announcement_wake_queued: bool,
}

voiceover_item_id :: proc(index: int) -> alicorn.Semantic_ID {
	return alicorn.Semantic_ID{namespace=VOICEOVER_LIST_ITEM_NAMESPACE, value=u64(index+1)}
}

voiceover_queue_announcement :: proc(app: ^App, request: Announcement_Request) {
	if app == nil { return }
	app.announcement_request = request
	if app.announcement_wake_queued { return }
	app.announcement_wake_queued = true
	host.application_wake(app.waker)
}

voiceover_start :: proc(state: rawptr, waker: host.Application_Waker) {
	app := cast(^App)state
	app.waker = waker
}

voiceover_wake :: proc(state: rawptr, rt: ^alicorn.Runtime) {
	app := cast(^App)state
	request := app.announcement_request
	app.announcement_request = .None
	app.announcement_wake_queued = false
	switch request {
	case .None:
	case .Polite_Status:
		_ = alicorn.notice_post(rt, alicorn.Notice{
			id="voiceover-polite-status", title="Saved", message="The sample document was saved.",
			severity=.Success, lifetime=.Persistent, placement=.Toast,
		}, 0)
	case .Assertive_Alert:
		_ = alicorn.notice_post(rt, alicorn.Notice{
			id="voiceover-assertive-alert", title="Connection lost", message="The sample service is unavailable.",
			severity=.Error, lifetime=.Persistent, placement=.Toast,
		}, 0)
	case .Dismiss:
		_ = alicorn.notice_dismiss(rt, "voiceover-polite-status")
		_ = alicorn.notice_dismiss(rt, "voiceover-assertive-alert")
	case:
	}
}

voiceover_adopt_requests :: proc(app: ^App, rt: ^alicorn.Runtime) {
	if app == nil || rt == nil { return }
	for {
		event, found := alicorn.semantic_request_pop(rt)
		if !found { break }
		if event.kind == .Perform {
			switch {
			case event.id == app.field_id && event.action == .Set_Value:
				_ = alicorn.text_field_buffer_set(&app.name, event.text_value)
			case event.id == app.slider_id:
				#partial switch event.action {
				case .Set_Value:
					if event.has_numeric_value {
						app.level = f32(event.numeric_value)
						if app.level < 0 { app.level = 0 }
						if app.level > 1 { app.level = 1 }
					}
				case .Increment: app.level = min(app.level+0.05, 1)
				case .Decrement: app.level = max(app.level-0.05, 0)
				case:
				}
			case event.id == VOICEOVER_LIST_ID && event.action == .Scroll_Forward:
				if app.list_scroll_id != 0 {
					state := alicorn.scroll_region_state(rt, app.list_scroll_id)
					_ = alicorn.scroll_region_set_offset(rt, app.list_scroll_id, state.offset_y+state.viewport_height, "VoiceOver paged sample list forward")
				}
			case event.id == VOICEOVER_LIST_ID && event.action == .Scroll_Backward:
				if app.list_scroll_id != 0 {
					state := alicorn.scroll_region_state(rt, app.list_scroll_id)
					_ = alicorn.scroll_region_set_offset(rt, app.list_scroll_id, state.offset_y-state.viewport_height, "VoiceOver paged sample list backward")
				}
			case event.id.namespace == VOICEOVER_LIST_ITEM_NAMESPACE && event.action == .Select:
				index := int(event.id.value)-1
				if index >= 0 && index < VOICEOVER_LIST_COUNT { app.selected_item = index }
			case:
			}
		} else if event.kind == .Reveal && event.id.namespace == VOICEOVER_LIST_ITEM_NAMESPACE {
			index := int(event.id.value)-1
			if index >= 0 && index < VOICEOVER_LIST_COUNT && app.list_scroll_id != 0 {
				_ = alicorn.scroll_region_set_offset(rt, app.list_scroll_id, f32(index)*36, "VoiceOver revealed sample document")
			}
		}
		alicorn.semantic_request_event_destroy(rt, &event)
	}
}

voiceover_slider_adopt :: proc(app: ^App, change: alicorn.Control_Change_F32) {
	if app == nil || !change.changed { return }
	app.level = change.value
}

voiceover_text :: proc(ctx: ^ui.UI, value, key: string, size: f32 = 0) {
	_ = ui.text(ctx, value, key=alicorn.key_string(key), size=size, color=ui.rgb(0xE5E7EB))
	_ = alicorn.semantic_static_text(ctx)
}

voiceover_controls_page :: proc(app: ^App, ctx: ^ui.UI) {
	voiceover_text(ctx, "Controls and announcements", "controls-heading", 22)
	voiceover_text(ctx, "Use VoiceOver navigation to inspect names, roles, values, states, and actions.", "controls-intro")

	if ui.column(ctx, gap=8, label="voiceover-actions") {
		_ = alicorn.semantic_description(ctx, .Group, "Actions and announcements")
		if ui.row(ctx, gap=8, label="voiceover-action-buttons") {
			if ui.button(ctx, "Activate action", key=alicorn.key_string("activate-action"), width=180, height=38) {
				app.activation_count += 1
			}
			if ui.button(ctx, "Disabled action", key=alicorn.key_string("disabled-action"), width=180, height=38,
				state=alicorn.Button_State{disabled=true}) {}
			_, clicked := alicorn.icon_button(ctx, "Search icon button", .Search,
				key=alicorn.key_string("search-icon"), style=alicorn.layout_style(.Row, width=38, height=38))
			if clicked { app.activation_count += 1 }
		}
		count_value := fmt.tprintf("%d", app.activation_count)
		_ = ui.text(ctx, fmt.tprintf("Actions activated: %d", app.activation_count),
			key=alicorn.key_string("action-count"), color=ui.rgb(0xE5E7EB))
		_ = alicorn.semantic_description(ctx, .Status, "Action count", value=count_value)
	}

	if ui.column(ctx, gap=8, label="voiceover-form-controls") {
		_ = alicorn.semantic_description(ctx, .Group, "Form controls")
		checkbox := alicorn.checkbox(
			ctx,
			"Enable notifications",
			app.checked,
			key=alicorn.key_string("notifications"),
			style=alicorn.layout_style(.Row, height=36),
		)
		if checkbox.changed { app.checked = checkbox.value }

		voiceover_text(ctx, "Display name", "name-label")
		field := alicorn.text_field_controlled(
			ctx,
			&app.name,
			key=alicorn.key_string("display-name"),
			style=alicorn.layout_style(height=40),
		)
		app.field_id = VOICEOVER_FIELD_ID
		_ = alicorn.semantic_bind(ctx, app.field_id)
		field_states := alicorn.semantic_states_add({}, .Required)
		if app.validation_invalid { field_states = alicorn.semantic_states_add(field_states, .Invalid) }
		field_actions := alicorn.semantic_actions_add({}, .Focus)
		field_actions = alicorn.semantic_actions_add(field_actions, .Set_Value)
		_ = alicorn.semantic_description(ctx, .Text_Field, "Display name", "Required sample text field", app.name.text,
			states=field_states, actions=field_actions)
		_ = field

		if ui.row(ctx, gap=8, label="voiceover-field-actions") {
			if ui.button(ctx, "Validate name", key=alicorn.key_string("validate-name"), width=150, height=34) {
				app.validation_invalid = len(app.name.text) == 0
			}
			if ui.button(ctx, "Reset name", key=alicorn.key_string("reset-name"), width=130, height=34) {
				_ = alicorn.text_field_buffer_set(&app.name, "Alicorn")
				app.validation_invalid = false
			}
		}
		if app.validation_invalid { voiceover_text(ctx, "Name is required", "name-error") }

		slider := alicorn.slider_f32(
			ctx,
			"Volume",
			app.level,
			0,
			1,
			0.05,
			key=alicorn.key_string("volume"),
			style=alicorn.layout_style(.Row, height=44),
		)
		voiceover_slider_adopt(app, slider)
		app.slider_id = VOICEOVER_SLIDER_ID
		_ = alicorn.semantic_bind(ctx, app.slider_id)
		_ = alicorn.semantic_range_value_text(ctx, fmt.tprintf("%.0f percent", app.level*100))
		voiceover_text(ctx, fmt.tprintf("Volume value: %.0f percent", app.level*100), "volume-value")
	}

	if ui.column(ctx, gap=8, label="voiceover-live-regions") {
		_ = alicorn.semantic_description(ctx, .Group, "Live announcements")
		voiceover_text(ctx, "Post a polite status or an assertive alert. Dismiss each announcement with its named control.", "announcement-instructions")
		if ui.row(ctx, gap=8, label="announcement-actions") {
			if ui.button(ctx, "Announce saved status", key=alicorn.key_string("announce-status"), width=210, height=36) {
				voiceover_queue_announcement(app, .Polite_Status)
			}
			if ui.button(ctx, "Announce error alert", key=alicorn.key_string("announce-alert"), width=210, height=36) {
				voiceover_queue_announcement(app, .Assertive_Alert)
			}
		}
		if ui.button(ctx, "Dismiss sample announcements", key=alicorn.key_string("dismiss-announcements"), width=230, height=34) {
			voiceover_queue_announcement(app, .Dismiss)
		}
	}
}

voiceover_collections_page :: proc(app: ^App, ctx: ^ui.UI) {
	voiceover_text(ctx, "Tabs, choices, and collections", "collections-heading", 22)
	voiceover_text(ctx, "Test tab selection, a combo box, and a scrollable list with selected items.", "collections-intro")

	if ui.column(ctx, gap=8, label="voiceover-choice-controls") {
		_ = alicorn.semantic_description(ctx, .Group, "Choice controls")
		options := [3]alicorn.Select_Option{
			{key=1, label="Light appearance"},
			{key=2, label="Dark appearance"},
			{key=3, label="System appearance", disabled=true},
		}
		voiceover_text(ctx, "Appearance", "appearance-label")
		choice := alicorn.select_control(
			ctx,
			alicorn.key_string("appearance-choice"),
			"Appearance",
			options[:],
			app.selected_option,
			style=alicorn.layout_style(.Row, width=300, height=38),
		)
		if choice.changed { app.selected_option = choice.selected_key }
	}

	if ui.column(ctx, gap=8, label="voiceover-virtualized-list") {
		_ = alicorn.semantic_description(ctx, .Group, "Sample documents")
		list := alicorn.virtual_list_begin(
			ctx,
			VOICEOVER_LIST_COUNT,
			36,
			key=alicorn.key_string("voiceover-document-list"),
			style=alicorn.layout_style(.Column, height=250, clip=true),
			label="Sample documents",
			focusable=true,
		)
		app.list_scroll_id = list.scroll.id
		selected_id := voiceover_item_id(app.selected_item)
		collection := alicorn.semantic_collection_begin(
			ctx,
			list.scroll.id,
			VOICEOVER_LIST_ID,
			.List,
			"Sample documents",
			u64(VOICEOVER_LIST_COUNT),
			selected_id=selected_id,
			current_id=selected_id,
			realized_first=u64(list.first),
			realized_last=u64(list.last),
			actions=alicorn.semantic_actions_add(alicorn.semantic_actions_add({}, .Scroll_Forward), .Scroll_Backward),
		)
		for index := list.first; index < list.last; index += 1 {
			row_label := fmt.tprintf("Document %02d", index+1)
			selected := index == app.selected_item
			if ui.button(
				ctx,
				row_label,
				key=alicorn.key_u64(u64(index+1)),
				style=alicorn.layout_style(.Row, height=34),
			) {
				app.selected_item = index
			}
			states := alicorn.Semantic_States{}
			if selected { states = alicorn.semantic_states_add(states, .Selected) }
			row_actions := alicorn.semantic_actions_add({}, .Focus)
			row_actions = alicorn.semantic_actions_add(row_actions, .Select)
			_ = alicorn.semantic_collection_item(ctx, collection, u64(index), alicorn.Semantic_Node_Description{
				id=voiceover_item_id(index), role=.List_Item, label=row_label,
					value="Sample document", states=states, actions=row_actions,
			})
		}
		for index := 0; index < list.first; index += 1 {
			states := alicorn.Semantic_States{}
			if index == app.selected_item { states = alicorn.semantic_states_add(states, .Selected) }
			item_actions := alicorn.semantic_actions_add(alicorn.semantic_actions_add({}, .Focus), .Select)
			item_actions = alicorn.semantic_actions_add(item_actions, .Scroll_Into_View)
			_ = alicorn.semantic_collection_virtual_item(ctx, collection, u64(index), alicorn.Semantic_Node_Description{
				id=voiceover_item_id(index), role=.List_Item,
				label=fmt.tprintf("Document %02d", index+1), value="Sample document",
				states=states, actions=item_actions,
			})
		}
		for index := list.last; index < VOICEOVER_LIST_COUNT; index += 1 {
			states := alicorn.Semantic_States{}
			if index == app.selected_item { states = alicorn.semantic_states_add(states, .Selected) }
			item_actions := alicorn.semantic_actions_add(alicorn.semantic_actions_add({}, .Focus), .Select)
			item_actions = alicorn.semantic_actions_add(item_actions, .Scroll_Into_View)
			_ = alicorn.semantic_collection_virtual_item(ctx, collection, u64(index), alicorn.Semantic_Node_Description{
				id=voiceover_item_id(index), role=.List_Item,
				label=fmt.tprintf("Document %02d", index+1), value="Sample document",
				states=states, actions=item_actions,
			})
		}
		alicorn.virtual_list_end(ctx, list)
		voiceover_text(ctx, fmt.tprintf("Selected document: %02d", app.selected_item+1), "selected-document")
	}
}

voiceover_dialog_page :: proc(app: ^App, ctx: ^ui.UI) {
	voiceover_text(ctx, "Dialog and focus containment", "dialog-heading", 22)
	voiceover_text(ctx, "Open the dialog, navigate its controls, and verify that VoiceOver stays within it until dismissal.", "dialog-instructions")
	if ui.button(ctx, "Open confirmation dialog", key=alicorn.key_string("open-dialog"), width=240, height=40) {
		app.show_dialog = true
	}
	voiceover_text(ctx, "The dialog has separate confirm and cancel actions. Use Cancel dialog to close it.", "dialog-help")
}

render :: proc(app: ^App, ctx: ^ui.UI) {
	voiceover_adopt_requests(app, ctx.runtime)
	if ui.panel(ctx, grow=1, padding=18, gap=12, fill=ui.rgb(0x111827), label="voiceover-gallery") {
		_ = alicorn.semantic_description(ctx, .Group, "Alicorn VoiceOver test gallery")
		voiceover_text(ctx, "Alicorn VoiceOver test gallery", "gallery-title", 26)
		voiceover_text(ctx, "A practical screen-reader tour of controls and accessibility state.", "gallery-description")

		tabs := [3]alicorn.Tab_Bar_Item{
			{key=alicorn.key_string("controls-tab"), label="Controls", selected=app.page == 0},
			{key=alicorn.key_string("collections-tab"), label="Collections", selected=app.page == 1},
			{key=alicorn.key_string("dialog-tab"), label="Dialog", selected=app.page == 2},
		}
		tab_result := alicorn.tab_bar(
			ctx,
			alicorn.key_string("voiceover-pages"),
			tabs[:],
			options=alicorn.Tab_Bar_Options{min_tab_width=110, max_tab_width=190, height=36},
			style=alicorn.layout_style(.Row, height=40),
		)
		if tab_result.action == .Select { app.page = tab_result.item_index }

		content := alicorn.scroll_region_begin(
			ctx,
			key=alicorn.key_string("voiceover-page-content"),
			content_height=1200,
			line_height=28,
			style=alicorn.layout_style(.Column, grow=1, clip=true),
			label="Page content",
			axes=.Vertical,
		)
		if ui.column(ctx, gap=16, padding=8, label="voiceover-page-content-inner") {
			switch app.page {
			case 0: voiceover_controls_page(app, ctx)
			case 1: voiceover_collections_page(app, ctx)
			case 2: voiceover_dialog_page(app, ctx)
			case: app.page = 0
			}
		}
		alicorn.scroll_region_end(ctx)
		_ = content
	}
}

render_overlays :: proc(app: ^App, ctx: ^ui.UI) {
	if !app.show_dialog { return }
	if alicorn.modal_overlay_begin(
		ctx,
		alicorn.key_string("voiceover-confirmation-overlay"),
		style=alicorn.layout_style(.Column, align=.Center, justify=.Center),
		backdrop_color=alicorn.Color{0, 0, 0, 0.72},
	) == 0 { return }
	if ui.panel(ctx, width=480, padding=24, gap=12, fill=ui.rgb(0x1F2937),
		stroke=ui.border(1, ui.rgb(0x94A3B8)), label="confirmation-dialog") {
		_ = alicorn.semantic_description(ctx, .Dialog, "Confirmation dialog", "A modal dialog with confirm and cancel actions.")
		voiceover_text(ctx, "Confirm action?", "dialog-title", 22)
		voiceover_text(ctx, "This is sample dialog content for VoiceOver navigation.", "dialog-message")
		if ui.row(ctx, gap=10, label="dialog-actions") {
			if ui.button(ctx, "Confirm", key=alicorn.key_string("dialog-confirm"), width=140, height=40) {
				app.activation_count += 1
				app.show_dialog = false
			}
			if ui.button(ctx, "Cancel dialog", key=alicorn.key_string("dialog-cancel"), width=160, height=40) {
				app.show_dialog = false
			}
		}
	}
	alicorn.modal_overlay_end(ctx)
}

build :: proc(
	state: rawptr,
	rt: ^alicorn.Runtime,
	_logical_width, _logical_height: int,
	_dpi_scale: f32,
) -> alicorn.Node_ID {
	app := cast(^App)state
	ctx, should_build := alicorn.begin_frame(rt)
	if !should_build { return 0 }
	root := alicorn.container_begin(
		&ctx,
		.Root,
		label="voiceover-root",
		key=alicorn.key_string("voiceover-root"),
		style=alicorn.layout_style(.Column, grow=1),
	)
	if root != 0 {
		render(app, &ctx)
		alicorn.container_end(&ctx)
		render_overlays(app, &ctx)
	}
	alicorn.end_frame(&ctx)
	return root
}

main :: proc() {
	name, ok := alicorn.text_field_buffer_init("Alicorn", context.allocator)
	if !ok { return }
	app := App{name=name, checked=true, level=0.65, selected_option=2}
	defer alicorn.text_field_buffer_destroy(&app.name)

	host.Run(host.Application{
		state=rawptr(&app),
		title="Alicorn VoiceOver Test Gallery",
		width=940,
		height=780,
		build=build,
		on_start=voiceover_start,
		on_wake=voiceover_wake,
		interaction_update_policy=.Correct_After_Interaction,
	})
}
