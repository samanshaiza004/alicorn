package main

import alicorn "../runtime"

STYLE_EDITOR_TEXT :: "A long editor sentence wraps into multiple visual lines at this fixed width."
STYLE_EDITOR_SOURCE :: alicorn.Source_Site{"tests/style_environment.odin", 1, 1, "editor_text"}

render_style_environment_fixture :: proc(rt: ^alicorn.Runtime, text_scale: f32) -> (editor, editor_text, sidebar, sidebar_text: alicorn.Node_ID) {
	alicorn.invalidate_root(rt, "style environment regression")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin(&ui, .Root, key="style-root", style=alicorn.layout_style(.Row, grow=1, gap=12, clip=true))
	editor = alicorn.container_begin(&ui, .Container, key="editor-pane", style=alicorn.layout_style(width=180, height=180, clip=true))
	scope := alicorn.style_environment_push(&ui, alicorn.Style_Environment{text_scale=text_scale})
	editor_text = alicorn.text_ex(
		&ui,
		STYLE_EDITOR_TEXT,
		STYLE_EDITOR_SOURCE,
		key="editor-body",
		explicit_key=true,
		style=alicorn.layout_style(width=112),
		text_style=alicorn.Text_Style{overflow=.Wrap},
	)
	alicorn.style_environment_pop(&ui, scope)
	alicorn.container_end(&ui)
	sidebar = alicorn.container_begin(&ui, .Container, key="sidebar-pane", style=alicorn.layout_style(width=180, height=180, clip=true))
	sidebar_text = alicorn.text_ex(&ui, "Stable sidebar label", alicorn.site("tests/style_environment.odin", 2, 1, "sidebar_text"), key="sidebar-label", explicit_key=true)
	alicorn.container_end(&ui)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return
}

test_style_environment_local_typography_invalidation :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 400, 220})
	defer alicorn.destroy_runtime(&rt)
	rt.layout_visit_probe = make(map[alicorn.Node_ID]u64, allocator=rt.persistent_allocator)
	rt.layout_visit_probe[0] = 0
	expect(state, alicorn.text_engine_load_font(&rt.text_engine, TEST_UI_FONT_DATA), "style environment fixture font must load")

	editor, editor_text, sidebar, sidebar_text := render_style_environment_fixture(&rt, 1)
	base_editor_run := rt.nodes[editor_text].text_run_generation
	base_sidebar_run := rt.nodes[sidebar_text].text_run_generation
	base_editor_layout := rt.layout_visit_probe[editor]
	base_editor_text_layout := rt.layout_visit_probe[editor_text]
	base_sidebar_layout := rt.layout_visit_probe[sidebar]
	base_sidebar_text_layout := rt.layout_visit_probe[sidebar_text]
	base_layout_visits := rt.stats.layout_nodes_visited
	base_size := rt.nodes[editor_text].text_run.size
	base_height := rt.nodes[editor_text].text_run.height
	expect(state, rt.nodes[editor_text].text_run_valid, "initial editor text must be shaped")
	expect(state, base_height > 0, "initial editor text must have measurable height")

	editor, editor_text, sidebar, sidebar_text = render_style_environment_fixture(&rt, 1.5)
	editor_node := rt.nodes[editor]
	editor_text_node := rt.nodes[editor_text]
	sidebar_node := rt.nodes[sidebar]
	sidebar_text_node := rt.nodes[sidebar_text]
	expect(state, editor_text_node.text_run_generation > base_editor_run, "changing text scale must reshape editor text")
	expect(state, abs(editor_text_node.text_run.size-base_size*1.5) < 0.01, "shaped editor text must use the scoped text scale")
	expect(state, editor_text_node.text_run.height > base_height, "larger editor typography must update wrapped text height")
	expect(state, rt.layout_visit_probe[editor] > base_editor_layout && rt.layout_visit_probe[editor_text] > base_editor_text_layout, "editor text scale change must visit editor layout")
	expect(state, rt.stats.layout_nodes_visited > base_layout_visits, "style change must perform measurable retained layout work")
	expect(state, rt.layout_visit_probe[sidebar] == base_sidebar_layout && rt.layout_visit_probe[sidebar_text] == base_sidebar_text_layout, "editor-only typography change must not visit sidebar layout")
	expect(state, sidebar_text_node.text_run_generation == base_sidebar_run, "editor-only typography change must not reshape sidebar text")
}
