package main

import "core:fmt"
import "core:strings"
import alicorn "../runtime"
import theme "../theme"

STYLE_EDITOR_TEXT :: "A long editor sentence wraps into multiple visual lines at this fixed width."
STYLE_EDITOR_SOURCE :: alicorn.Source_Site{"tests/style_environment.odin", 1, 1, "editor_text"}

render_style_environment_fixture :: proc(rt: ^alicorn.Runtime, environment: alicorn.Style_Environment) -> (editor, editor_text, sidebar, sidebar_text: alicorn.Node_ID) {
	alicorn.invalidate_root(rt, "style environment regression")
	ui, build := alicorn.begin_frame(rt)
	if !build { return }
	alicorn.container_begin(&ui, .Root, key="style-root", style=alicorn.layout_style(.Row, grow=1, gap=12, clip=true))
	editor = alicorn.container_begin(&ui, .Container, key="editor-pane", style=alicorn.layout_style(width=180, height=180, clip=true), layout_boundary=true)
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
	styled_container_visits := rt.layout_visit_probe[editor]
	sidebar_visits := rt.layout_visit_probe[sidebar]
	sidebar_text_visits := rt.layout_visit_probe[sidebar_text]
	initial_metrics_generation := rt.nodes[editor_text].style_generations.metrics
	initial_paint_generation := rt.nodes[editor_text].style_generations.paint
	_, _, _, _ = render_style_environment_fixture(&rt, alicorn.Style_Environment{density=1.25})
	expect(state, rt.nodes[editor_text].bounds.w > initial_width+1, "density must scale metrics explicitly requested through style_metric")
	expect(state, rt.layout_visit_probe[editor_text] > editor_visits, "density change must relayout the styled subtree")
	expect(state, rt.nodes[editor_text].style_generations.metrics > initial_metrics_generation &&
		rt.nodes[editor_text].style_generations.paint == initial_paint_generation,
		"density change must advance only the metric generation before downstream paint")
	expect(state, rt.layout_visit_probe[editor] > styled_container_visits,
		"density changes may revisit the containing editor layout needed to place the affected subtree")
	expect(state, rt.layout_visit_probe[sidebar] == sidebar_visits && rt.layout_visit_probe[sidebar_text] == sidebar_text_visits,
		"density change must not visit layout in the unaffected sidebar subtree")
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
	theme.color_tokens = {
		theme.colors[int(alicorn.Style_Color_Role.Text)],
		theme.colors[int(alicorn.Style_Color_Role.Accent)],
	}
	theme.core_color_tokens[int(alicorn.Style_Color_Role.Text)] = alicorn.Style_Color_Token_ID(1)
	theme.core_color_tokens[int(alicorn.Style_Color_Role.Accent)] = alicorn.Style_Color_Token_ID(2)
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

render_primary_button_with_accent :: proc(rt: ^alicorn.Runtime, accent: alicorn.Color) -> alicorn.Node_ID {
	alicorn.invalidate_root(rt, "accent paint-domain fixture")
	ui, build := alicorn.begin_frame(rt)
	if !build { return 0 }
	alicorn.container_begin(&ui, .Root, key="accent-root", style=alicorn.layout_style(.Row, width=360, height=80))
	scope := alicorn.style_environment_push(&ui, alicorn.Style_Environment{accent=alicorn.style_accent(accent)})
	_ = alicorn.button(&ui, "Primary", key="accent-primary", style=alicorn.layout_style(width=110, height=32), variant=.Primary)
	alicorn.style_environment_pop(&ui, scope)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	for id in rt.order {
		node, found := rt.nodes[id]
		if found && node.kind == .Button && node.label == "Primary" { return id }
	}
	return 0
}

test_accent_override_repaints_primary_control_without_layout :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 360, 80})
	defer alicorn.destroy_runtime(&rt)
	red := alicorn.Color{0.82, 0.16, 0.12, 1}
	green := alicorn.Color{0.12, 0.68, 0.28, 1}
	button := render_primary_button_with_accent(&rt, red)
	if button == 0 { expect(state, false, "accent fixture should retain its Primary button"); return }
	first_layout_visits := rt.stats.layout_nodes_visited
	first_style := rt.computed_styles[button].payload.(alicorn.Button_Resolved_Style)
	button = render_primary_button_with_accent(&rt, green)
	updated_style := rt.computed_styles[button].payload.(alicorn.Button_Resolved_Style)
	expect(state, updated_style.surface == green && updated_style.surface != first_style.surface,
		"an accent-token change must resolve the Primary button through its new Paint input")
	expect(state, rt.stats.layout_nodes_visited == first_layout_visits,
		"changing only the accent Paint input must visit zero layout nodes")
}

Style_Contract_Fixture_Nodes :: struct {
	editor:          alicorn.Node_ID,
	paper:           alicorn.Node_ID,
	gutter_metric:   alicorn.Node_ID,
	editor_text:     alicorn.Node_ID,
	primary_button:  alicorn.Node_ID,
	sidebar:         alicorn.Node_ID,
	sidebar_text:    alicorn.Node_ID,
}

STYLE_CONTRACT_SEMANTIC_ID :: alicorn.Semantic_ID{namespace=0x5354594C45434F4E, value=1}

style_contract_theme_create :: proc(ink_red: string) -> (runtime_theme: alicorn.Style_Theme, ok: bool) {
	source_builder := strings.builder_make()
	defer strings.builder_destroy(&source_builder)
	strings.write_string(&source_builder, `{
	  "schema": 1,
	  "contract": "0.2",
	  "extends": "alicorn.base",
	  "tokens": {
	    "palette.ink": {"$type":"color", "$value":{"colorSpace":"srgb", "components":[`)
	strings.write_string(&source_builder, ink_red)
	strings.write_string(&source_builder, `,0.13,0.10], "alpha":1}},
	    "text.primary": {"$type":"color", "$value":"{palette.ink}"},
	    "palette.paper": {"$type":"color", "$value":{"colorSpace":"srgb", "components":[0.94,0.90,0.82], "alpha":1}},
	    "space.editor.gutter": {"$type":"dimension", "$value":{"value":14, "unit":"px"}},
	    "space.editor.gutter_alias": {"$type":"dimension", "$value":"{space.editor.gutter}"}
	  },
	  "roles": {
	    "core": {"text":"{text.primary}"},
	    "extensions": {
	      "app.editor.paper": {"$type":"color", "$value":"{palette.paper}"},
	      "app.editor.gutter": {"$type":"dimension", "$value":"{space.editor.gutter_alias}"}
	    }
	  }
	}`)
	source_text := strings.to_string(source_builder)
	parsed := theme.theme_json_parse(source_text, "tests/style_contract.json")
	defer theme.theme_json_output_destroy(&parsed)
	if !parsed.ok {
		for diagnostic in parsed.diagnostics { fmt.println("style contract parse:", diagnostic.message) }
		return
	}

	base := theme.theme_builtin_base_source_create()
	defer theme.theme_builtin_base_source_destroy(&base)
	compiled := theme.theme_compile({base.model, parsed.source}, support=theme.THEME_COMPILER_SUPPORT)
	defer theme.theme_output_destroy(&compiled)
	if !compiled.ok {
		for diagnostic in compiled.diagnostics {
			fmt.println("style contract compile:", diagnostic.code, diagnostic.path, diagnostic.span.line, diagnostic.span.column)
		}
		return
	}

	return theme.theme_runtime_style_theme(compiled)
}

render_style_contract_fixture :: proc(
	rt: ^alicorn.Runtime,
	theme_id: alicorn.Style_Theme_ID,
	density, text_scale: f32,
	accent: alicorn.Style_Accent,
	material: alicorn.Material_ID,
	physical_height: f32,
) -> Style_Contract_Fixture_Nodes {
	nodes: Style_Contract_Fixture_Nodes
	alicorn.invalidate_root(rt, "styling contract end-to-end fixture")
	ui, build := alicorn.begin_frame(rt)
	if !build { return nodes }
	alicorn.container_begin(&ui, .Root, key="style-contract-root", style=alicorn.layout_style(.Row, width=460, height=260, gap=12, clip=true))
	nodes.editor = alicorn.container_begin(&ui, .Container, key="style-contract-editor", style=alicorn.layout_style(width=220, height=220, clip=true), layout_boundary=true)
	scope := alicorn.style_environment_push(&ui, alicorn.Style_Environment{
		theme=theme_id,
		density=density,
		text_scale=text_scale,
		accent=accent,
	})
	paper_role := alicorn.style_extension_color_role_id("app.editor", "paper")
	gutter_role := alicorn.style_extension_length_role_id("app.editor", "gutter")
	gutter, gutter_found := alicorn.style_extension_length(rt, theme_id, gutter_role)
	if !gutter_found { gutter.logical_units = 14 }
	nodes.paper = alicorn.surface_begin(
		&ui,
		alicorn.surface_extension_color_role(paper_role),
		key="style-contract-paper",
		style=alicorn.layout_style(.Column, width=220, height=220, gap=6, padding=8, clip=true),
		material=material,
		physical_height=physical_height,
		label="editor paper",
	)
	nodes.gutter_metric = alicorn.container_begin(&ui, .Container, key="style-contract-gutter", style=alicorn.layout_style(width=alicorn.style_metric(&ui, gutter.logical_units), height=12))
	alicorn.container_end(&ui)
	nodes.editor_text = alicorn.text_ex(
		&ui,
		STYLE_EDITOR_TEXT,
		STYLE_EDITOR_SOURCE,
		key="style-contract-copy",
		explicit_key=true,
		style=alicorn.layout_style(width=132),
		text_style=alicorn.Text_Style{overflow=.Wrap},
	)
	_ = alicorn.semantic_describe_as(
		&ui,
		STYLE_CONTRACT_SEMANTIC_ID,
		.Text_Area,
		"Editor body",
		value="Stable semantic value",
		actions=alicorn.semantic_actions_add({}, .Set_Value),
	)
	nodes.primary_button, _ = alicorn.button_begin(
		&ui,
		"Apply",
		key="style-contract-primary",
		style=alicorn.layout_style(width=92, height=28),
		variant=.Primary,
	)
	alicorn.button_end(&ui)
	alicorn.surface_end(&ui)
	alicorn.style_environment_pop(&ui, scope)
	alicorn.container_end(&ui)
	nodes.sidebar = alicorn.container_begin(&ui, .Container, key="style-contract-sidebar", style=alicorn.layout_style(width=220, height=220, clip=true))
	nodes.sidebar_text = alicorn.text_ex(
		&ui,
		"Stable sidebar label",
		alicorn.site("tests/style_environment.odin", 260, 1, "sidebar_text"),
		key="style-contract-sidebar-label",
		explicit_key=true,
	)
	alicorn.container_end(&ui)
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	return nodes
}

test_style_contract_end_to_end_domains_and_semantic_separation :: proc(state: ^Test_State) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 460, 260})
	defer alicorn.destroy_runtime(&rt)
	rt.layout_visit_probe = make(map[alicorn.Node_ID]u64, allocator=rt.persistent_allocator)
	rt.layout_visit_probe[0] = 0
	expect(state, alicorn.text_engine_load_font(&rt.text_engine, TEST_UI_FONT_DATA), "style contract fixture font must load")

	first_theme, first_adapted := style_contract_theme_create("0.14")
	expect(state, first_adapted, "JSON source should compile through aliases, built-in base, typed roles, and the runtime adapter")
	if !first_adapted { return }
	first_theme_id := alicorn.style_theme_register(&rt, first_theme)
	theme.theme_runtime_style_theme_destroy(&first_theme)
	expect(state, first_theme_id != 0, "compiled theme should register as an immutable runtime theme")
	if first_theme_id == 0 { return }

	second_theme, second_adapted := style_contract_theme_create("0.32")
	expect(state, second_adapted, "a second compiled palette should adapt through the same typed runtime path")
	if !second_adapted { return }
	second_theme_id := alicorn.style_theme_register(&rt, second_theme)
	theme.theme_runtime_style_theme_destroy(&second_theme)
	expect(state, second_theme_id != 0, "second compiled theme should register")
	if second_theme_id == 0 { return }

	material := alicorn.style_material_register(&rt, alicorn.Style_Material{
		kind=.Analytic_Relief,
		bevel_width=1,
		bevel_strength=0.12,
	})
	nodes := render_style_contract_fixture(&rt, first_theme_id, 1, 1, 0, material, 0.25)
	expect(state, nodes.editor != 0 && nodes.paper != 0 && nodes.gutter_metric != 0 && nodes.editor_text != 0 && nodes.primary_button != 0 && nodes.sidebar_text != 0,
		"fixture should realize a themed editor, typed metric, styled control, semantic surface, and sibling")
	if nodes.editor_text == 0 || nodes.primary_button == 0 || nodes.paper == 0 { return }
	semantic_revision_before := alicorn.semantic_revision(&rt)
	semantic_before, semantic_before_found := alicorn.semantic_node_lookup(&rt, STYLE_CONTRACT_SEMANTIC_ID)
	expect(state, semantic_before_found && semantic_before.role == .Text_Area && semantic_before.label == "Editor body",
		"the application semantic descriptor should be retained beside themed presentation")

	text_token := alicorn.style_theme_color_token(&rt, first_theme_id, .Text)
	text_provenance, provenance_found := alicorn.style_token_provenance(&rt, first_theme_id, text_token)
	expect(state, provenance_found && text_provenance.name == "text.primary" && text_provenance.alias_target == "palette.ink",
		"compiled aliases should retain inspectable authored provenance after registration")
	text_color := alicorn.style_theme_color(&rt, first_theme_id, .Text)
	expect(state, rt.nodes[nodes.editor_text].color == text_color,
		"a compiled semantic text token should reach the retained editor text paint")
	paper_role := alicorn.style_extension_color_role_id("app.editor", "paper")
	paper_color, paper_color_found := alicorn.style_extension_color(&rt, first_theme_id, paper_role)
	paper_style, paper_style_found := rt.computed_styles[nodes.paper]
	expect(state, paper_color_found && paper_style_found && paper_style.payload.(alicorn.Semantic_Surface_Resolved_Style).fill == paper_color,
		"an app-namespaced color role should resolve through a retained semantic surface")
	button_style, button_style_found := rt.computed_styles[nodes.primary_button]
	expect(state, button_style_found && button_style.family == .Button && button_style.valid && button_style.provenance.theme == first_theme_id,
		"the normal Button recipe path should retain computed style and its theme provenance")
	expect(state, button_style_found && button_style.dependencies == {.Paint},
		"the Button computed style should declare its Paint-only dependency")
	expect(state, paper_style_found && paper_style.dependencies == {.Paint, .Material},
		"the semantic surface computed style should declare Paint and Material, separate from layout")

	first_layout_visits := rt.stats.layout_nodes_visited
	first_paint_visits := rt.stats.paint_nodes_visited
	first_sidebar_layout := rt.layout_visit_probe[nodes.sidebar]
	first_sidebar_text_layout := rt.layout_visit_probe[nodes.sidebar_text]
	first_editor_generations := rt.nodes[nodes.editor_text].style_generations
	first_sidebar_generations := rt.nodes[nodes.sidebar_text].style_generations

	// Theme colors are Paint inputs: the compiled theme change must repaint its
	// scope without visiting layout or leaking into the sibling.
	nodes = render_style_contract_fixture(&rt, second_theme_id, 1, 1, 0, material, 0.25)
	second_text_color := alicorn.style_theme_color(&rt, second_theme_id, .Text)
	expect(state, rt.nodes[nodes.editor_text].color == second_text_color && second_text_color != text_color,
		"a changed compiled paint token should update the editor text color")
	expect(state, rt.stats.layout_nodes_visited == first_layout_visits && rt.stats.paint_nodes_visited > first_paint_visits,
		"a theme Paint change should repaint without any layout visits")
	expect(state, rt.layout_visit_probe[nodes.sidebar] == first_sidebar_layout && rt.layout_visit_probe[nodes.sidebar_text] == first_sidebar_text_layout &&
		rt.nodes[nodes.sidebar_text].style_generations == first_sidebar_generations,
		"the theme Paint change should leave sibling layout and style generations untouched")
	expect(state, rt.nodes[nodes.editor_text].style_generations.metrics == first_editor_generations.metrics &&
		rt.nodes[nodes.editor_text].style_generations.typography == first_editor_generations.typography,
		"the theme Paint change must not advance layout-related style domains")

	// Accent is a separate Paint input consumed by the Primary Button recipe.
	accent := alicorn.style_accent(alicorn.Color{0.25, 0.68, 0.42, 1})
	accent_layout_visits := rt.stats.layout_nodes_visited
	accent_before := rt.computed_styles[nodes.primary_button].payload.(alicorn.Button_Resolved_Style).surface
	nodes = render_style_contract_fixture(&rt, second_theme_id, 1, 1, accent, material, 0.25)
	accent_after := rt.computed_styles[nodes.primary_button].payload.(alicorn.Button_Resolved_Style).surface
	expect(state, accent_after != accent_before && rt.stats.layout_nodes_visited == accent_layout_visits,
		"an accent override should transform the Primary recipe through Paint without layout")
	expect(state, alicorn.semantic_revision(&rt) == semantic_revision_before,
		"theme and accent Paint changes should not publish semantic changes")

	// A namespaced logical-length token enters layout only through the explicit
	// density-aware metric call at the app's point of use.
	base_metric_width := rt.nodes[nodes.gutter_metric].bounds.w
	base_metric_generations := rt.nodes[nodes.gutter_metric].style_generations
	density_layout_visits := rt.stats.layout_nodes_visited
	nodes = render_style_contract_fixture(&rt, second_theme_id, 1.5, 1, accent, material, 0.25)
	expect(state, rt.nodes[nodes.gutter_metric].bounds.w > base_metric_width+1,
		"a compiled length role should scale through style_metric when density changes")
	expect(state, rt.nodes[nodes.gutter_metric].style_generations.metrics > base_metric_generations.metrics &&
		rt.nodes[nodes.gutter_metric].style_generations.paint == base_metric_generations.paint,
		"density should invalidate Metrics without declaring a Paint dependency")
	expect(state, rt.stats.layout_nodes_visited > density_layout_visits &&
		rt.layout_visit_probe[nodes.sidebar] == first_sidebar_layout && rt.layout_visit_probe[nodes.sidebar_text] == first_sidebar_text_layout,
		"density should lay out the explicitly metric-dependent editor subtree and skip its sibling")

	// Typography changes reshape and relayout the scoped copy; the sidebar stays
	// stable and the color-only Button cache remains independent.
	text_run_before_scale := rt.nodes[nodes.editor_text].text_run_generation
	scale_layout_visits := rt.stats.layout_nodes_visited
	scale_sidebar_run := rt.nodes[nodes.sidebar_text].text_run_generation
	nodes = render_style_contract_fixture(&rt, second_theme_id, 1.5, 1.35, accent, material, 0.25)
	expect(state, rt.nodes[nodes.editor_text].text_run_generation > text_run_before_scale &&
		rt.nodes[nodes.editor_text].style_generations.typography > first_editor_generations.typography,
		"text scale should reshape the scoped editor copy and advance Typography")
	expect(state, rt.stats.layout_nodes_visited > scale_layout_visits && rt.nodes[nodes.sidebar_text].text_run_generation == scale_sidebar_run,
		"text scale should relayout the editor subtree without reshaping the sidebar")

	// Optical height is material state only. It preserves bounds and hit results.
	material_before := rt.nodes[nodes.paper].style_generations
	paper_bounds_before := rt.nodes[nodes.paper].bounds
	semantic_revision_before_material := alicorn.semantic_revision(&rt)
	hit_x := paper_bounds_before.x+paper_bounds_before.w-2
	hit_y := paper_bounds_before.y+paper_bounds_before.h-2
	hit_before := alicorn.hit_test(&rt, hit_x, hit_y)
	material_layout_visits := rt.stats.layout_nodes_visited
	nodes = render_style_contract_fixture(&rt, second_theme_id, 1.5, 1.35, accent, material, 0.75)
	material_after := rt.nodes[nodes.paper].style_generations
	expect(state, material_after.material > material_before.material && material_after.metrics == material_before.metrics &&
		material_after.typography == material_before.typography,
		"optical-height changes should invalidate Material while preserving layout domains")
	expect(state, rt.stats.layout_nodes_visited == material_layout_visits && rt.nodes[nodes.paper].bounds == paper_bounds_before &&
		alicorn.hit_test(&rt, hit_x, hit_y) == hit_before && alicorn.semantic_revision(&rt) == semantic_revision_before_material,
		"material-only changes should preserve layout bounds and hit-test geometry")

	final_semantic, final_semantic_found := alicorn.semantic_node_lookup(&rt, STYLE_CONTRACT_SEMANTIC_ID)
	expect(state, semantic_before_found && final_semantic_found &&
		final_semantic.role == semantic_before.role && final_semantic.label == semantic_before.label &&
		final_semantic.value == semantic_before.value && final_semantic.actions == semantic_before.actions,
		"theme, density, typography, accent, and material changes must not mutate accessibility semantics")

	idle_stats := rt.stats
	_, should_build := alicorn.begin_frame(&rt)
	expect(state, !should_build && rt.stats.layout_nodes_visited == idle_stats.layout_nodes_visited &&
		rt.stats.style_resolutions == idle_stats.style_resolutions,
		"an unchanged idle frame should perform no retained style resolution or layout work")
}
