package main

import alicorn "../runtime"

STYLE_EDITOR_TEXT :: "A long editor sentence wraps into multiple visual lines at this fixed width."
STYLE_EDITOR_SOURCE :: alicorn.Source_Site{"tests/style_environment.odin", 1, 1, "editor_text"}

render_style_environment_fixture :: proc(rt: ^alicorn.Runtime, environment: alicorn.Style_Environment) -> (editor, editor_text, sidebar, sidebar_text: alicorn.Node_ID) {
	alicorn.invalidate_root(rt, "style environment regression")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin(&ui, .Root, key="style-root", style=alicorn.layout_style(.Row, grow=1, gap=12, clip=true))
	editor = alicorn.container_begin(&ui, .Container, key="editor-pane", style=alicorn.layout_style(width=180, height=180, clip=true))
	scope := alicorn.style_environment_push(&ui, environment)
	editor_text = alicorn.text_ex(
		&ui,
		STYLE_EDITOR_TEXT,
		STYLE_EDITOR_SOURCE,
		key="editor-body",
		explicit_key=true,
		style=alicorn.layout_style(width=alicorn.style_metric(&ui, 112)),
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

	editor, editor_text, sidebar, sidebar_text := render_style_environment_fixture(&rt, alicorn.Style_Environment{text_scale=1})
	base_editor_run := rt.nodes[editor_text].text_run_generation
	base_sidebar_run := rt.nodes[sidebar_text].text_run_generation
	base_editor_layout := rt.layout_visit_probe[editor]
	base_editor_text_layout := rt.layout_visit_probe[editor_text]
	base_sidebar_layout := rt.layout_visit_probe[sidebar]
	base_sidebar_text_layout := rt.layout_visit_probe[sidebar_text]
	base_editor_generations := rt.nodes[editor_text].style_generations
	base_sidebar_generations := rt.nodes[sidebar_text].style_generations
	base_layout_visits := rt.stats.layout_nodes_visited
	base_size := rt.nodes[editor_text].text_run.size
	base_height := rt.nodes[editor_text].text_run.height
	expect(state, rt.nodes[editor_text].text_run_valid, "initial editor text must be shaped")
	expect(state, base_height > 0, "initial editor text must have measurable height")

	editor, editor_text, sidebar, sidebar_text = render_style_environment_fixture(&rt, alicorn.Style_Environment{text_scale=1.5})
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
	expect(state, editor_text_node.style_generations.metrics > base_editor_generations.metrics &&
		editor_text_node.style_generations.typography > base_editor_generations.typography,
		"local text scale changes must advance only the affected node's metric and typography dependencies")
	expect(state, sidebar_text_node.style_generations == base_sidebar_generations,
		"an unaffected sibling must retain all style generations")
	expect(state, sidebar_text_node.text_run_generation == base_sidebar_run, "editor-only typography change must not reshape sidebar text")
	idle_stats := rt.stats
	_, should_build := alicorn.begin_frame(&rt)
	expect(state, !should_build && rt.stats.layout_nodes_visited == idle_stats.layout_nodes_visited,
		"editor-local typography invalidation must settle without layout work on idle frames")
}

test_style_environment_domains_and_density :: proc(state: ^Test_State) {
	previous := alicorn.DEFAULT_STYLE_ENVIRONMENT
	density := previous
	density.density = 1.25
	domains := alicorn.style_environment_changed_domains(previous, density)
	expect(state, alicorn.Style_Domain.Metrics in domains, "density changes must invalidate metrics")
	expect(state, alicorn.Style_Domain.Typography not_in domains && alicorn.Style_Domain.Paint not_in domains,
		"density changes must not invalidate typography or paint")
	text_scale := previous
	text_scale.text_scale = 1.2
	domains = alicorn.style_environment_changed_domains(previous, text_scale)
	expect(state, alicorn.Style_Domain.Metrics in domains && alicorn.Style_Domain.Typography in domains,
		"text scale changes must invalidate metrics and typography")
	theme := previous
	theme.theme = alicorn.Style_Theme_ID(2)
	domains = alicorn.style_environment_changed_domains(previous, theme)
	expect(state, alicorn.Style_Domain.Paint in domains && alicorn.Style_Domain.Metrics not_in domains,
		"theme changes must invalidate paint only")
	accent := previous
	accent.accent = alicorn.style_accent(alicorn.Color{0.7, 0.3, 0.2, 1})
	domains = alicorn.style_environment_changed_domains(previous, accent)
	expect(state, alicorn.Style_Domain.Paint in domains && alicorn.Style_Domain.Metrics not_in domains,
		"accent changes must invalidate paint only")
	material_stages := alicorn.style_domain_dirty_stages(.Material)
	expect(state, alicorn.Dirty_Stage.Paint in material_stages && alicorn.Dirty_Stage.Composite in material_stages &&
		alicorn.Dirty_Stage.Layout not_in material_stages,
		"material changes must repaint/recompose without visiting layout")

	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 400, 220})
	defer alicorn.destroy_runtime(&rt)
	rt.layout_visit_probe = make(map[alicorn.Node_ID]u64, allocator=rt.persistent_allocator)
	rt.layout_visit_probe[0] = 0
	expect(state, alicorn.text_engine_load_font(&rt.text_engine, TEST_UI_FONT_DATA), "density fixture font must load")
	editor, editor_text, sidebar, sidebar_text := render_style_environment_fixture(&rt, alicorn.Style_Environment{density=1})
	initial_width := rt.nodes[editor_text].bounds.w
	editor_visits := rt.layout_visit_probe[editor_text]
	sidebar_visits := rt.layout_visit_probe[sidebar]
	initial_metrics_generation := rt.nodes[editor_text].style_generations.metrics
	initial_paint_generation := rt.nodes[editor_text].style_generations.paint
	_, _, _, _ = render_style_environment_fixture(&rt, alicorn.Style_Environment{density=1.25})
	expect(state, rt.nodes[editor_text].bounds.w > initial_width+1, "density must scale metrics explicitly requested through style_metric")
	expect(state, rt.layout_visit_probe[editor_text] > editor_visits, "density change must relayout the styled subtree")
	expect(state, rt.nodes[editor_text].style_generations.metrics > initial_metrics_generation &&
		rt.nodes[editor_text].style_generations.paint == initial_paint_generation,
		"density change must advance only the metric generation before downstream paint")
	expect(state, rt.layout_visit_probe[sidebar] == sidebar_visits, "density change must not visit sibling layout")
	expect(state, rt.nodes[sidebar_text].style_environment.density == 1, "density scope must not leak to siblings")
	_ = editor
	_ = sidebar_text
}

test_style_environment_theme_paint_locality :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 400, 220})
	defer alicorn.destroy_runtime(&rt)
	rt.layout_visit_probe = make(map[alicorn.Node_ID]u64, allocator=rt.persistent_allocator)
	rt.layout_visit_probe[0] = 0
	expect(state, alicorn.text_engine_load_font(&rt.text_engine, TEST_UI_FONT_DATA), "theme fixture font must load")
	theme := alicorn.DEFAULT_STYLE_THEME
	theme.colors[int(alicorn.Style_Color_Role.Text)] = alicorn.Color{0.18, 0.16, 0.14, 1}
	theme.colors[int(alicorn.Style_Color_Role.Accent)] = alicorn.Color{0.7, 0.35, 0.18, 1}
	theme_id := alicorn.style_theme_register(&rt, theme)
	expect(state, theme_id != 0, "valid immutable theme must register")
	editor, editor_text, sidebar, sidebar_text := render_style_environment_fixture(&rt, alicorn.Style_Environment{theme=alicorn.DEFAULT_STYLE_THEME_ID})
	initial_layout_visits := rt.stats.layout_nodes_visited
	initial_paint_visits := rt.stats.paint_nodes_visited
	initial_editor_generations := rt.nodes[editor_text].style_generations
	initial_sidebar_generations := rt.nodes[sidebar_text].style_generations
	initial_editor_color := rt.nodes[editor_text].color
	initial_sidebar_color := rt.nodes[sidebar_text].color
	_, _, _, _ = render_style_environment_fixture(&rt, alicorn.Style_Environment{theme=theme_id})
	updated_editor_color := rt.nodes[editor_text].color
	updated_sidebar_color := rt.nodes[sidebar_text].color
	expect(state, updated_editor_color.r == 0.18 && updated_editor_color.g == 0.16, "registered theme text role must reach text nodes")
	expect(state, updated_editor_color != initial_editor_color, "theme change must update styled text paint")
	expect(state, updated_sidebar_color == initial_sidebar_color, "scoped theme must not change sibling text")
	expect(state, rt.stats.layout_nodes_visited == initial_layout_visits, "paint-only theme change must not visit layout")
	expect(state, rt.stats.paint_nodes_visited > initial_paint_visits, "theme change must repaint the styled subtree")
	expect(state, rt.nodes[editor_text].style_generations.paint > initial_editor_generations.paint &&
		rt.nodes[editor_text].style_generations.metrics == initial_editor_generations.metrics &&
		rt.nodes[editor_text].style_generations.typography == initial_editor_generations.typography,
		"a theme-only change must advance paint without advancing layout dependencies")
	expect(state, rt.nodes[sidebar_text].style_generations == initial_sidebar_generations,
		"a scoped theme change must not advance style generations in a sibling subtree")
	_ = editor
	_ = sidebar
}
