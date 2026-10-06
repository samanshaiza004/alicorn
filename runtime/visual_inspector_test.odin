package alicorn

import "core:fmt"
import "core:strings"
import "core:testing"

Inspector_Test_Nodes :: struct { root, group, disabled, text, sibling: Node_ID }
INSPECTOR_TEST_MONO_FONT_DATA :: #load("../assets/fonts/AtkinsonHyperlegibleMono-Variable.ttf")

inspector_test_describe :: proc(rt: ^Runtime, include_group := true, extra_rows := 0) -> Inspector_Test_Nodes {
	invalidate_root(rt,"inspector fixture changed")
	ui,build := begin_frame(rt)
	if !build { return {} }
	nodes: Inspector_Test_Nodes
	nodes.root = container_begin(&ui,.Root,label="fixture-root",key=key_string("root"),style=layout_style())
	if include_group {
		nodes.group = container_begin(&ui,.Container,label="fixture-group",key=key_string("group"),style=layout_style(height=100))
		button(&ui,"Disabled app control",key=key_string("disabled"),style=layout_style(.Row,height=30),state=Button_State{disabled=true})
		nodes.disabled = rt.pending[len(rt.pending)-1].description.id
		nodes.text = text(&ui,"App text",key=key_string("text"),style=layout_style(.Row,height=30))
		container_end(&ui)
	}
	nodes.sibling,_ = button_ex(&ui,"App sibling",key="sibling",explicit_key=true,style=layout_style(.Row,height=30))
	for index in 0..<extra_rows {
		button(&ui,fmt.tprintf("App row %d",index),key=key_u64(u64(index)),style=layout_style(.Row,height=28))
	}
	container_end(&ui)
	end_frame(&ui)
	return nodes
}

inspector_test_build :: proc(panel: ^Runtime,state: ^Inspector_Overlay,app: ^Runtime) {
	invalidate_root(panel,"inspector test rebuild")
	ui,build := begin_frame(panel)
	if build { inspector_overlay_build(&ui,state,app); end_frame(&ui) }
}

@(test)
test_inspector_hierarchy_collapse_and_retirement :: proc(t: ^testing.T) {
	app := new_runtime(Rect{0,0,800,600})
	defer destroy_runtime(&app)
	state := inspector_overlay_make()
	defer inspector_overlay_destroy(&state)
	nodes := inspector_test_describe(&app)
	rows := inspector_overlay_tree_rows(&state,&app)
	defer delete(rows)
	testing.expect(t,len(rows)==5,"the tree must contain the parent, grouped descendants and sibling")
	if len(rows)!=5 { return }
	testing.expect(t,rows[0].id==nodes.root && rows[0].depth==0 && rows[1].id==nodes.group && rows[1].depth==1 && rows[2].id==nodes.disabled && rows[2].depth==2,
		"retained adjacency must preserve hierarchy and depth")
	testing.expect(t,inspector_overlay_toggle_collapsed(&state,&app,nodes.group),"a retained parent must collapse")
	collapsed := inspector_overlay_tree_rows(&state,&app)
	defer delete(collapsed)
	testing.expect(t,len(collapsed)==3 && collapsed[1].id==nodes.group && collapsed[2].id==nodes.sibling,
		"collapse must hide only descendants while retaining the parent and its sibling")
	state.selected = nodes.disabled
	_ = inspector_test_describe(&app,false)
	pruned := inspector_overlay_tree_rows(&state,&app)
	defer delete(pruned)
	testing.expect(t,len(state.collapsed)==0 && state.selected==0,"retired node IDs must leave selection and the bounded collapse map")
	testing.expect(t,len(pruned)==2,"the tree must reflect the current retained adjacency after retirement")
}

@(test)
test_inspector_picking_includes_disabled_text_and_containers_without_app_mutation :: proc(t: ^testing.T) {
	app := new_runtime(Rect{0,0,800,600},Runtime_Config{trace_capacity=64})
	defer destroy_runtime(&app)
	nodes := inspector_test_describe(&app)
	state := inspector_overlay_make()
	defer inspector_overlay_destroy(&state)
	inspector_overlay_open(&state)
	before := inspect(&app)
	defer delete(before)
	allocation_before := app.allocation_stats^
	targets := [3]Node_ID{nodes.disabled,nodes.text,nodes.group}
	for id in targets {
		state.picking = true
		bounds := app.nodes[id].bounds
		y := bounds.y+bounds.h/2
		if id==nodes.group { y = bounds.y+bounds.h-2 }
		testing.expect(t,inspector_overlay_pick(&state,&app,bounds.x+4,y)==id && state.selected==id && !state.picking,
			"picking must identify visible disabled, text and container nodes without using application input")
	}
	state.picking = true
	testing.expect(t,inspector_overlay_pick(&state,&app,-1,-1)==0 && state.picking,"a pick miss must keep picking armed")
	after := inspect(&app)
	defer delete(after)
	testing.expect(t,before==after,"picking must leave application focus, selection, trace, geometry and work unchanged")
	testing.expect(t,app.allocation_stats^==allocation_before,"picking must allocate no application runtime storage")
}

@(test)
test_inspector_recent_causes_are_bounded_and_preserve_action_and_stage_truth :: proc(t: ^testing.T) {
	app := new_runtime(Rect{0,0,800,600},Runtime_Config{trace_capacity=512})
	defer destroy_runtime(&app)
	for index in 0..<30 {
		scope := cause_begin(&app,.Keyboard,fmt.tprintf("command %d",index))
		trace_action(&app,Action_ID(index+1),"Fixture action")
		record_trace(&app,.Invalidation,0,"Fixture invalidation")
		record_trace(&app,.Reconcile,0,"Fixture reconcile")
		for visit in 0..<6 { record_trace(&app,.Layout,Node_ID(visit+1),"Fixture layout") }
		record_trace(&app,.Paint,0,"Fixture paint")
		record_trace(&app,.Composite,0,"Fixture composite")
		record_trace(&app,.Submit,0,"Fixture submit")
		cause_end(&app,scope)
	}
	sequence_before := app.trace.sequence
	causes := inspector_overlay_recent_causes(&app)
	defer delete(causes)
	testing.expect(t,len(causes)==INSPECTOR_CAUSE_LIMIT,"the inspector must retain at most 20 useful cause summaries")
	if len(causes)!=INSPECTOR_CAUSE_LIMIT { return }
	for cause,index in causes {
		testing.expect(t,cause.id==u64(30-index) && cause.action==Action_ID(30-index),"the newest distinct causes must preserve their semantic action IDs")
		testing.expect(t,cause.action_reason=="Fixture action" && cause.invalidation=="Fixture invalidation" && cause.visits[.Layout]==6 && cause.visits[.Submit]==1,
			"per-node stage records must remain grouped with action, invalidation and successful submission")
	}
	testing.expect(t,app.trace.sequence==sequence_before,"summarizing causes must not create telemetry")
	record_trace_with_cause(&app,.Paint,0,"mixed paint",Cause_Context{})
	record_trace_with_cause(&app,.Submit,0,"mixed submit",Cause_Context{})
	mixed := inspector_overlay_recent_causes(&app)
	defer delete(mixed)
	testing.expect(t,mixed[0].id==0 && mixed[0].visits[.Paint]==1 && mixed[0].visits[.Submit]==1,
		"coalesced work must remain explicitly unassigned instead of inheriting a nearby cause")
}

@(test)
test_inspector_ui_is_virtualized_and_independent_of_app_hard_error :: proc(t: ^testing.T) {
	app := new_runtime(Rect{0,0,1024,600},Runtime_Config{trace_capacity=512})
	panel := new_runtime(app.viewport)
	defer destroy_runtime(&app)
	defer destroy_runtime(&panel)
	state := inspector_overlay_make()
	defer inspector_overlay_destroy(&state)
	inspector_overlay_open(&state)
	nodes := inspector_test_describe(&app,true,1000)
	_ = focus(&app,nodes.sibling)
	append_diagnostic(&app,"intentional app fixture hard error")
	before := inspect(&app)
	defer delete(before)
	stats_before := app.stats
	allocation_before := app.allocation_stats^
	for tab in Inspector_Tab {
		state.tab = tab
		inspector_test_build(&panel,&state,&app)
		testing.expect(t,!panel.hard_error && len(panel.nodes)>0,"an app hard error must not prevent inspector descriptions or interaction")
		testing.expect(t,len(panel.nodes)<150,"large application trees and trace views must realize only the visible inspector rows")
	}
	testing.expect(t,state.initial_focus!=0 && focus(&panel,state.initial_focus),"initial inspector focus must target a retained inspector control")
	_ = focus_traverse(&panel,.Next)
	_ = activate_focused(&panel,.Enter)
	inspector_test_build(&panel,&state,&app)
	after := inspect(&app)
	defer delete(after)
	testing.expect(t,before==after && app.stats==stats_before && app.allocation_stats^==allocation_before,
		"building and navigating all inspector tabs must leave the hard-error application unchanged")
	found_diagnostic := false
	for id in panel.order {
		node := panel.nodes[id]
		if strings.contains(node.text,"intentional app fixture hard error") { found_diagnostic = true }
	}
	state.tab = .Work
	inspector_test_build(&panel,&state,&app)
	for id in panel.order { if strings.contains(panel.nodes[id].text,"App hard error") { found_diagnostic = true } }
	testing.expect(t,found_diagnostic,"the inspector must expose the application's retained hard-error status")
}

@(test)
test_inspector_source_fingerprint_tracks_app_acknowledgements_only :: proc(t: ^testing.T) {
	app := new_runtime(Rect{0,0,800,600},Runtime_Config{trace_capacity=64})
	panel := new_runtime(app.viewport,Runtime_Config{trace_capacity=64})
	defer destroy_runtime(&app)
	defer destroy_runtime(&panel)
	_ = inspector_test_describe(&app)
	before := inspector_overlay_source_fingerprint(&app)
	frame_submission_succeeded(&app)
	after_app_submit := inspector_overlay_source_fingerprint(&app)
	testing.expect(t,before!=after_app_submit,"actual app acknowledgements must refresh submitted revision and cause truth")
	frame_submission_succeeded(&panel)
	testing.expect(t,inspector_overlay_source_fingerprint(&app)==after_app_submit,"a separate inspector acknowledgement must not schedule another inspector rebuild")
}

@(test)
test_inspector_selected_bounds_and_panel_layout :: proc(t: ^testing.T) {
	app := new_runtime(Rect{40,30,1000,600})
	panel := new_runtime(app.viewport)
	defer destroy_runtime(&app)
	defer destroy_runtime(&panel)
	state := inspector_overlay_make()
	defer inspector_overlay_destroy(&state)
	inspector_overlay_open(&state)
	ui,build := begin_frame(&app)
	if !build { testing.expect(t,false,"fixture should build"); return }
	container_begin(&ui,.Root,label="highlight-root",style=layout_style(align=.Start))
	selected,_ := button_ex(&ui,"Highlight target",style=layout_style(.Row,width=200,height=40))
	container_end(&ui)
	end_frame(&ui)
	state.selected = selected
	before := inspect(&app)
	defer delete(before)
	inspector_test_build(&panel,&state,&app)
	target := app.nodes[selected].bounds
	outline_count := 0
	detail_found := false
	for id in panel.order {
		node := panel.nodes[id]
		if node.label=="highlight-top" || node.label=="highlight-bottom" || node.label=="highlight-left" || node.label=="highlight-right" {
			outline_count += 1
			testing.expect(t,node.bounds.x>=target.x && node.bounds.y>=target.y && node.bounds.x+node.bounds.w<=target.x+target.w && node.bounds.y+node.bounds.h<=target.y+target.h,
				"the selected outline must use application logical bounds, including a nonzero viewport origin")
		}
		if node.label=="inspector-node-details" && node.kind==.Scroll_Region {
			detail_found = true
			testing.expect(t,node.bounds.y+node.bounds.h<=state.panel_bounds.y+state.panel_bounds.h-8,
				"the complete detail scroll region and scrollbar must fit inside the panel padding")
		}
		if node.label=="inspector-overlay" || node.label=="inspector-highlight-layer" {
			testing.expect(t,!node.paint_background,"viewport roots must remain transparent so the inspected app stays visible")
		}
	}
	testing.expect(t,outline_count==4 && detail_found,"selection must paint all four bounds edges and retain scrollable details")
	after := inspect(&app)
	defer delete(after)
	testing.expect(t,before==after,"highlight geometry must belong entirely to the separate inspector runtime")
}

@(test)
test_inspector_loaded_monospace_lines_reach_their_final_glyph :: proc(t: ^testing.T) {
	panel := new_runtime(Rect{0,0,480,180})
	defer destroy_runtime(&panel)
	testing.expect(t,text_engine_load_font_role(&panel.text_engine,.Monospace,INSPECTOR_TEST_MONO_FONT_DATA),
		"the bundled monospace face must load for the scroll-width regression")
	longest := strings.repeat("W",1000)
	defer delete(longest)
	lines := [2]string{"Select a retained node in the tree, or use Pick.",longest}
	inspector_test_lines_build(&panel,lines[:])
	region: ^Node
	for id in panel.order {
		node := panel.nodes[id]
		if node.kind==.Scroll_Region && node.label=="width-lines" { region = node; break }
	}
	testing.expect(t,region!=nil,"details must retain a scroll region")
	if region==nil { return }
	max_width := f32(0)
	for id in panel.order {
		node := panel.nodes[id]
		if node.kind!=.Text { continue }
		testing.expect(t,node.text_run_valid,"loaded-font lines must retain shaped text products")
		max_width = maxf(max_width,node.text_run.width)
	}
	testing.expect(t,max_width>8192 && region.scroll_content_width>=max_width,
		"the content extent must include the complete longest shaped line without an arbitrary width cap")
	testing.expect(t,region.scrollbar_horizontal_visible,"actual monospace overflow must create a horizontal scrollbar")
	_ = scroll_region_set_offset_x(&panel,region.id,1_000_000,"inspector width regression")
	inspector_test_lines_build(&panel,lines[:])
	for id in panel.order {
		node := panel.nodes[id]
		if node.kind==.Text && node.text==longest {
			testing.expect(t,node.bounds.x+node.text_run.width<=region.scroll_viewport_bounds.x+region.scroll_viewport_bounds.w,
				"maximum horizontal scrolling must expose the final glyph of the longest detail line")
		}
	}
}

@(test)
test_inspector_reports_retained_control_recipe_provenance :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 480, 240})
	defer destroy_runtime(&rt)
	theme := DEFAULT_STYLE_THEME
	theme.text_field_recipe.surface_role = .Editor_Background
	theme.text_field_recipe.hovered.surface_role = .Accent
	theme.scrollbar_recipe.hovered_thumb.role = .Accent_Hover
	theme.scrollbar_recipe.pressed_thumb.role = .Accent_Pressed
	theme_id := style_theme_register(&rt, theme)
	testing.expect(t, theme_id != 0, "control provenance fixture theme should register")

	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "control provenance fixture should build"); return }
	container_begin(&ui, .Root, key=key_string("control-provenance-root"), style=layout_style())
	scope := style_environment_push(&ui, Style_Environment{theme=theme_id})
	field := text_field(&ui, "query", key=key_string("provenance-field"), style=layout_style(width=180, height=32))
	scroll := scroll_region_begin(
		&ui,
		key=key_string("provenance-scroll"),
		viewport_height=64,
		content_height=160,
		style=layout_style(.Column, width=180, height=64),
		axes=.Vertical,
		label="provenance-scroll",
	)
	scroll_region_end(&ui)
	style_environment_pop(&ui, scope)
	container_end(&ui)
	end_frame(&ui)

	_ = focus(&rt, field)
	field_node := rt.nodes[field]
	field_node.hovered = true
	rt.nodes[field] = field_node
	scroll_node := rt.nodes[scroll.id]
	scroll_node.hovered = true
	rt.nodes[scroll.id] = scroll_node
	rt.scrollbar_drag_node = scroll.id

	inspection := inspect(&rt)
	defer delete(inspection)
	testing.expect(t, strings.contains(inspection, "semantics: revision=") && strings.contains(inspection, "focus-search=") &&
		strings.contains(inspection, "active-update="),
		"the inspector should expose the current semantic working set, delta, request queue, and focus-scan costs")
	testing.expect(t, strings.contains(inspection,
		"text field style: recipe=text_field.default resolution=retained-cache state=(hovered=true focused=true) dependencies=paint generations=(paint=") &&
		strings.contains(inspection, "token provenance: text_field.default") &&
		strings.contains(inspection, "surface.base=Editor_Background") &&
		strings.contains(inspection, "surface.hovered=Accent"),
		"inspector should explain the retained text-field result, state, and semantic roles")
	testing.expect(t, strings.contains(inspection,
		"scrollbar style: recipe=scrollbar.default resolution=retained-cache state=(hovered=true pressed=true) dependencies=paint generations=(paint=") &&
		strings.contains(inspection, "token provenance: scrollbar.default") &&
		strings.contains(inspection, "thumb.hovered=Accent_Hover") &&
		strings.contains(inspection, "thumb.pressed=Accent_Pressed"),
		"inspector should explain scrollbar interaction state and applied thumb roles")
	field_style, field_cached := rt.computed_styles[field]
	scroll_style, scroll_cached := rt.computed_styles[scroll.id]
	testing.expect(t, field_cached && field_style.valid && field_style.family == .Text_Field &&
		scroll_cached && scroll_style.valid && scroll_style.family == .Scrollbar,
		"the inspector should populate the corresponding retained Computed_Style sidecar entries")
}

inspector_test_lines_build :: proc(panel: ^Runtime,lines: []string) {
	invalidate_root(panel,"inspector line fixture rebuild")
	ui,build := begin_frame(panel)
	if !build { return }
	container_begin(&ui,.Container,label="width-fixture",style=layout_style())
	inspector_overlay_lines(&ui,lines,"width-lines",140)
	container_end(&ui)
	end_frame(&ui)
}
