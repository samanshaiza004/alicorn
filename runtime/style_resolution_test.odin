package alicorn

import "core:testing"
import "core:strings"

@(test)
test_retained_computed_style_is_scoped_to_theme_identity :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 120, 80})
	defer destroy_runtime(&rt)

	red_theme := DEFAULT_STYLE_THEME
	red_theme.colors[int(Style_Color_Role.Accent)] = Color{0.9, 0.1, 0.1, 1}
	red_theme.color_tokens = {red_theme.colors[int(Style_Color_Role.Accent)]}
	red_theme.core_color_tokens[int(Style_Color_Role.Accent)] = Style_Color_Token_ID(1)
	red_id := style_theme_register(&rt, red_theme)
	blue_theme := DEFAULT_STYLE_THEME
	blue_theme.colors[int(Style_Color_Role.Accent)] = Color{0.1, 0.1, 0.9, 1}
	blue_theme.color_tokens = {blue_theme.colors[int(Style_Color_Role.Accent)]}
	blue_theme.core_color_tokens[int(Style_Color_Role.Accent)] = Style_Color_Token_ID(1)
	blue_id := style_theme_register(&rt, blue_theme)

	node := Node{
		id=1,
		style_environment=Style_Environment{theme=red_id, density=1, text_scale=1},
		button_variant=.Primary,
	}
	first := style_button_resolve_retained(&rt, &node, Button_Visual_State{})
	computed := rt.computed_styles[node.id]
	testing.expect(t, first.surface == red_theme.colors[int(Style_Color_Role.Accent)], "computed style should resolve through the node's initial theme")
	testing.expect(t, computed.valid && computed.provenance.theme == red_id,
		"retained computed style should carry its theme identity and provenance")
	testing.expect(t, computed.family == .Button && computed.dependencies == BUTTON_STYLE_DEPENDENCIES &&
		computed.provenance.variant == u8(Button_Variant.Primary) &&
		computed.provenance.state_bits == 0,
		"button style provenance should identify the recipe inputs and paint dependency")
	testing.expect(t, style_theme_color_token(&rt, red_id, .Accent) == Style_Color_Token_ID(1),
		"inspector provenance can resolve semantic roles to theme-local token IDs")
	hovered := style_button_resolve_retained(&rt, &node, Button_Visual_State{hovered=true})
	computed = rt.computed_styles[node.id]
	testing.expect(t, computed.provenance.state_bits == style_button_state_bits(Button_Visual_State{hovered=true}) &&
		hovered.applied_transforms == {.Hovered},
		"a state change must recompute and retain provenance for the transform that produced the style")
	hovered_cached := style_button_resolve_retained(&rt, &node, Button_Visual_State{hovered=true})
	computed = rt.computed_styles[node.id]
	testing.expect(t, hovered_cached == hovered && computed.provenance.state_bits == style_button_state_bits(Button_Visual_State{hovered=true}) &&
		style_computed_cache_matches(&rt, &node, .Button, style_button_provenance(node.style_environment, node.button_variant, Button_Visual_State{hovered=true}, false), BUTTON_STYLE_DEPENDENCIES),
		"an unchanged state should reuse both the resolved result and its matching provenance")

	// The token indices and recipe slots are allowed to repeat between themes;
	// the node must recompute when theme identity changes.
	node.style_environment.theme = blue_id
	second := style_button_resolve_retained(&rt, &node, Button_Visual_State{})
	testing.expect(t, second.surface == blue_theme.colors[int(Style_Color_Role.Accent)] && second.surface != first.surface,
		"a stale computed style from another theme must never be reused")
	again := style_button_resolve_retained(&rt, &node, Button_Visual_State{})
	testing.expect(t, again == second, "an unchanged node/theme/state should reuse its retained computed result")
	computed = rt.computed_styles[node.id]
	resolved_generations := computed.generations
	style_generations_advance(&node.style_generations, {.Metrics, .Typography})
	metric_only := style_button_resolve_retained(&rt, &node, Button_Visual_State{})
	computed = rt.computed_styles[node.id]
	testing.expect(t, metric_only == second && computed.generations == resolved_generations,
		"paint-only button style should reuse its computed result after metric/typography generations change")
	style_generations_advance(&node.style_generations, {.Material})
	material_only := style_button_resolve_retained(&rt, &node, Button_Visual_State{})
	computed = rt.computed_styles[node.id]
	testing.expect(t, material_only == second && computed.generations == resolved_generations,
		"flat button style should not depend on material generations")
	style_generations_advance(&node.style_generations, {.Paint})
	paint_changed := style_button_resolve_retained(&rt, &node, Button_Visual_State{})
	computed = rt.computed_styles[node.id]
	testing.expect(t, paint_changed == second && computed.generations.paint == node.style_generations.paint,
		"a changed paint generation should recompute and record only the dependent generation")
	wrapped_generations := Style_Generations{paint=0xFFFFFFFF}
	wrapped := style_generations_advance(&wrapped_generations, {.Paint})
	testing.expect(t, wrapped && wrapped_generations.paint == 1,
		"generation wrap should report that retained snapshots must be invalidated")

	node.style_environment.accent = style_accent(Color{0.2, 0.8, 0.3, 1})
	accented := style_button_resolve_retained(&rt, &node, Button_Visual_State{})
	testing.expect(t, accented.surface == style_accent_color(node.style_environment.accent),
		"the paint-relevant accent override must participate in retained style provenance")
}

@(test)
test_computed_style_inspector_reports_dependency_and_token_provenance :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 200, 80})
	defer destroy_runtime(&rt)
	theme := DEFAULT_STYLE_THEME
	theme.color_tokens = {theme.colors[int(Style_Color_Role.Accent)]}
	theme.core_color_tokens[int(Style_Color_Role.Accent)] = Style_Color_Token_ID(1)
	theme_id := style_theme_register(&rt, theme)
	testing.expect(t, theme_id != 0, "provenance theme should register")

	ui, should_build := begin_frame(&rt)
	if !should_build { testing.expect(t, false, "first style inspector frame should build"); return }
	container_begin(&ui, .Root, key=key_string("computed-style-root"), style=layout_style())
	scope := style_environment_push(&ui, Style_Environment{theme=theme_id})
	button(&ui, "Save", key=key_string("computed-style-save"), variant=.Primary)
	style_environment_pop(&ui, scope)
	container_end(&ui)
	end_frame(&ui)
	for id in rt.order {
		if node, ok := rt.nodes[id]; ok && node.kind == .Button {
			_ = style_button_resolve_retained(&rt, node, Button_Visual_State{hovered=true})
			break
		}
	}
	inspection := inspect(&rt)
	defer delete(inspection)
	testing.expect(t, strings.contains(inspection, "computed style: dependencies=paint") && strings.contains(inspection, "generations=(metrics="),
		"inspector should expose style dependency domains and the generations used by the retained result")
	testing.expect(t, strings.contains(inspection, "token provenance: button.primary") && strings.contains(inspection, "hovered") &&
		strings.contains(inspection, "token=1"),
		"inspector should explain the semantic recipe, applied state, and theme-local token ID")
}

@(test)
test_retained_recipe_families_use_exact_paint_and_material_dependencies :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt)
	theme_a := DEFAULT_STYLE_THEME
	theme_a.colors[int(Style_Color_Role.Surface)] = Color{0.3, 0.4, 0.5, 1}
	theme_a.colors[int(Style_Color_Role.Accent)] = Color{0.9, 0.1, 0.1, 1}
	theme_a.colors[int(Style_Color_Role.Danger)] = Color{0.7, 0.05, 0.1, 1}
	theme_a.text_field_recipe.surface_role = .Surface
	theme_a.text_field_recipe.hovered.surface_role = .Accent
	theme_a.text_field_recipe.focused_border_role = .Danger
	theme_a.scrollbar_recipe.thumb_role = .Accent
	theme_b := theme_a
	theme_b.colors[int(Style_Color_Role.Surface)] = Color{0.2, 0.5, 0.3, 1}
	theme_b.colors[int(Style_Color_Role.Accent)] = Color{0.1, 0.2, 0.9, 1}
	theme_a_id := style_theme_register(&rt, theme_a)
	theme_b_id := style_theme_register(&rt, theme_b)
	testing.expect(t, theme_a_id != 0 && theme_b_id != 0, "retained recipe themes should register")

	field_node := Node{id=71, kind=.Text_Field, style_environment=Style_Environment{theme=theme_a_id, density=1, text_scale=1}}
	field_base := style_text_field_resolve_retained(&rt, &field_node, Text_Field_Visual_State{})
	field_cache := rt.computed_styles[field_node.id]
	testing.expect(t, field_cache.valid && field_cache.family == .Text_Field &&
		field_cache.dependencies == TEXT_FIELD_STYLE_DEPENDENCIES &&
		field_cache.dependencies == Style_Domains{.Paint},
		"Text Field should retain only its color-role Paint dependency")
	testing.expect(t, style_computed_cache_matches(&rt, &field_node, .Text_Field,
		style_text_field_provenance(field_node.style_environment, {}), TEXT_FIELD_STYLE_DEPENDENCIES),
		"an unchanged Text Field recipe/state should hit its retained cache")

	scroll_node := Node{id=72, kind=.Scroll_Region, style_environment=field_node.style_environment}
	scroll_base := style_scrollbar_resolve_retained(&rt, &scroll_node, Scrollbar_Visual_State{})
	scroll_cache_before_field_state := rt.computed_styles[scroll_node.id]
	field_hovered := style_text_field_resolve_retained(&rt, &field_node, Text_Field_Visual_State{hovered=true})
	testing.expect(t, field_hovered.surface != field_base.surface &&
		!style_computed_cache_matches(&rt, &field_node, .Text_Field,
			style_text_field_provenance(field_node.style_environment, {}), TEXT_FIELD_STYLE_DEPENDENCIES),
		"hover changes must miss the Text Field cache and apply only its hover recipe")
	field_focused := style_text_field_resolve_retained(&rt, &field_node, Text_Field_Visual_State{hovered=true, focused=true})
	testing.expect(t, field_focused.surface == field_hovered.surface && field_focused.border == theme_a.colors[int(Style_Color_Role.Danger)],
		"focus changes must recompute the field border while preserving its hovered surface")
	scroll_cache_after_field_state := rt.computed_styles[scroll_node.id]
	testing.expect(t, scroll_cache_after_field_state.payload.(Scrollbar_Resolved_Style) == scroll_base &&
		scroll_cache_after_field_state.provenance == scroll_cache_before_field_state.provenance,
		"field focus/hover transitions must leave another node family’s retained payload untouched")

	field_node.style_environment.theme = theme_b_id
	style_generations_advance(&field_node.style_generations, {.Paint})
	testing.expect(t, !style_computed_cache_matches(&rt, &field_node, .Text_Field,
		style_text_field_provenance(field_node.style_environment, Text_Field_Visual_State{hovered=true, focused=true}), TEXT_FIELD_STYLE_DEPENDENCIES),
		"theme identity and Paint generation changes must invalidate the Text Field cache")
	field_theme_b := style_text_field_resolve_retained(&rt, &field_node, Text_Field_Visual_State{hovered=true, focused=true})
	testing.expect(t, field_theme_b.border == theme_b.colors[int(Style_Color_Role.Danger)],
		"a theme cache miss must resolve roles from the new immutable theme")
	field_node.style_environment.accent = style_accent(Color{0.1, 0.85, 0.3, 1})
	style_generations_advance(&field_node.style_generations, {.Paint})
	field_accented := style_text_field_resolve_retained(&rt, &field_node, Text_Field_Visual_State{hovered=true, focused=true})
	testing.expect(t, field_accented.caret == style_accent_color(field_node.style_environment.accent),
		"accent changes must invalidate and recompute Paint-dependent text-field roles")
	field_cache_before_metrics := rt.computed_styles[field_node.id]
	style_generations_advance(&field_node.style_generations, {.Metrics, .Typography})
	testing.expect(t, style_computed_cache_matches(&rt, &field_node, .Text_Field,
		style_text_field_provenance(field_node.style_environment, Text_Field_Visual_State{hovered=true, focused=true}), TEXT_FIELD_STYLE_DEPENDENCIES),
		"text-scale metric/typography generation changes must not invalidate a color-only Text Field style")
	_ = style_text_field_resolve_retained(&rt, &field_node, Text_Field_Visual_State{hovered=true, focused=true})
	field_cache_after_metrics := rt.computed_styles[field_node.id]
	testing.expect(t, field_cache_after_metrics.generations == field_cache_before_metrics.generations,
		"a cache hit after text-scale domains change should retain only its original Paint snapshot")

	scroll_base = style_scrollbar_resolve_retained(&rt, &scroll_node, Scrollbar_Visual_State{})
	scroll_hovered := style_scrollbar_resolve_retained(&rt, &scroll_node, Scrollbar_Visual_State{hovered=true})
	testing.expect(t, scroll_hovered.thumb != scroll_base.thumb &&
		!style_computed_cache_matches(&rt, &scroll_node, .Scrollbar,
			style_scrollbar_provenance(scroll_node.style_environment, Scrollbar_Visual_State{}), SCROLLBAR_STYLE_DEPENDENCIES),
		"scrollbar hover should recompute the scrollbar payload, not reuse a different state")
	style_generations_advance(&scroll_node.style_generations, {.Material})
	scroll_after_material := style_scrollbar_resolve_retained(&rt, &scroll_node, Scrollbar_Visual_State{hovered=true})
	scroll_cache_after_material := rt.computed_styles[scroll_node.id]
	testing.expect(t, scroll_after_material == scroll_hovered &&
		scroll_cache_after_material.generations == scroll_cache_after_field_state.generations,
		"Paint-only scrollbar styles should hit across material-only generation changes")

	material_id := style_material_register(&rt, Style_Material{kind=.Analytic_Relief, bevel_width=1, bevel_strength=0.12})
	surface_node := Node{id=73, kind=.Container, style_environment=field_node.style_environment}
	surface := Semantic_Surface_Style{
		defined=true,
		role=surface_core_color_role(.Surface),
		shape=Surface_Shape{kind=.Rectangle},
		material=MATERIAL_FLAT,
		physical_height=0.25,
	}
	surface_first := style_semantic_surface_resolve_retained(&rt, &surface_node, surface)
	surface_cache := rt.computed_styles[surface_node.id]
	testing.expect(t, surface_cache.dependencies == SEMANTIC_SURFACE_STYLE_DEPENDENCIES &&
		surface_cache.dependencies == Style_Domains{.Paint, .Material},
		"semantic surfaces should depend on both role paint and optical material inputs")
	old_surface_generations := surface_node.style_generations
	surface.material = material_id
	surface.physical_height = 0.75
	style_generations_advance(&surface_node.style_generations, {.Material})
	new_surface_provenance := style_semantic_surface_provenance(surface_node.style_environment, surface)
	testing.expect(t, !style_computed_cache_matches(&rt, &surface_node, .Semantic_Surface,
		new_surface_provenance, SEMANTIC_SURFACE_STYLE_DEPENDENCIES),
		"surface material/height changes must miss the Material-dependent cache without changing Paint generation")
	surface_second := style_semantic_surface_resolve_retained(&rt, &surface_node, surface)
	surface_cache = rt.computed_styles[surface_node.id]
	testing.expect(t, surface_second.fill == surface_first.fill &&
		surface_cache.generations.paint == old_surface_generations.paint &&
		surface_cache.generations.material == surface_node.style_generations.material,
		"material-only surface changes should preserve role color while refreshing Material provenance")
	surface_node.style_environment.theme = theme_b_id
	style_generations_advance(&surface_node.style_generations, {.Paint})
	surface_theme_b := style_semantic_surface_resolve_retained(&rt, &surface_node, surface)
	testing.expect(t, surface_theme_b.fill == theme_b.colors[int(Style_Color_Role.Surface)],
		"surface theme changes should invalidate Paint while retaining its independent Material dependency")
}

Style_Cache_Scope_Nodes :: struct { scaled, sibling: Node_ID }

style_text_field_cache_scope_describe :: proc(rt: ^Runtime, scale: f32) -> Style_Cache_Scope_Nodes {
	invalidate_root(rt, "text-field cache scope fixture")
	ui, build := begin_frame(rt)
	if !build { return {} }
	container_begin(&ui, .Root, key=key_string("cache-scope-root"), style=layout_style())
	scope := style_environment_push(&ui, Style_Environment{text_scale=scale})
	result := Style_Cache_Scope_Nodes{}
	result.scaled = text_field(&ui, "scaled", key=key_string("scaled-field"), style=layout_style(width=120, height=32))
	style_environment_pop(&ui, scope)
	result.sibling = text_field(&ui, "sibling", key=key_string("sibling-field"), style=layout_style(width=120, height=32))
	container_end(&ui)
	end_frame(&ui)
	return result
}

@(test)
test_text_scale_scope_reflows_while_color_style_cache_remains_paint_only :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120})
	defer destroy_runtime(&rt)
	nodes := style_text_field_cache_scope_describe(&rt, 1.25)
	if nodes.scaled == 0 || nodes.sibling == 0 { testing.expect(t, false, "scoped text fields should be retained"); return }
	first_scaled_generations := rt.nodes[nodes.scaled].style_generations
	first_sibling_generations := rt.nodes[nodes.sibling].style_generations
	first_scaled_cache := rt.computed_styles[nodes.scaled]
	first_sibling_cache := rt.computed_styles[nodes.sibling]
	layout_visits := rt.stats.layout_nodes_visited

	next_nodes := style_text_field_cache_scope_describe(&rt, 1.5)
	scaled := rt.nodes[next_nodes.scaled]
	sibling := rt.nodes[next_nodes.sibling]
	scaled_cache := rt.computed_styles[next_nodes.scaled]
	sibling_cache := rt.computed_styles[next_nodes.sibling]
	testing.expect(t, next_nodes.scaled == nodes.scaled && next_nodes.sibling == nodes.sibling,
		"a text-scale update should retain keyed control identities")
	testing.expect(t, scaled.style_generations.metrics > first_scaled_generations.metrics &&
		scaled.style_generations.typography > first_scaled_generations.typography &&
		scaled.style_generations.paint == first_scaled_generations.paint,
		"a text-scale scope should advance only its subtree's metrics/typography domains")
	testing.expect(t, sibling.style_generations == first_sibling_generations,
		"a sibling outside the text-scale scope should keep all style generations")
	testing.expect(t, rt.stats.layout_nodes_visited > layout_visits,
		"the scoped text-scale change should still run layout for its dependent subtree")
	testing.expect(t, scaled_cache.family == .Text_Field &&
		scaled_cache.generations == first_scaled_cache.generations &&
		style_computed_cache_matches(&rt, scaled, .Text_Field,
			style_text_field_provenance(scaled.style_environment, {}), TEXT_FIELD_STYLE_DEPENDENCIES),
		"Text Field's resolved color cache should hit across text-scale Metrics/Typography changes")
	testing.expect(t, sibling_cache.family == first_sibling_cache.family &&
		sibling_cache.generations == first_sibling_cache.generations &&
		sibling_cache.provenance == first_sibling_cache.provenance &&
		sibling_cache.payload.(Text_Field_Resolved_Style) == first_sibling_cache.payload.(Text_Field_Resolved_Style),
		"an unaffected sibling should retain its original computed style payload and generations")
}

@(test)
test_computed_style_sidecar_is_released_on_node_retirement_and_runtime_destroy :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 120})
	nodes := style_text_field_cache_scope_describe(&rt, 1)
	if nodes.scaled == 0 { testing.expect(t, false, "sidecar fixture should create a Text Field"); destroy_runtime(&rt); return }
	field := rt.nodes[nodes.scaled]
	_ = style_text_field_resolve_retained(&rt, field, Text_Field_Visual_State{})
	_, cached := rt.computed_styles[nodes.scaled]
	testing.expect(t, cached, "resolving a retained Text Field should create a Runtime-owned computed-style sidecar")

	invalidate_root(&rt, "retire computed style sidecar fixture")
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "retirement frame should rebuild the root"); destroy_runtime(&rt); return }
	container_begin(&ui, .Root, key=key_string("cache-scope-root"), style=layout_style())
	container_end(&ui)
	end_frame(&ui)
	_, cached = rt.computed_styles[nodes.scaled]
	testing.expect(t, !cached && nodes.scaled not_in rt.nodes,
		"retiring a node should release its computed-style sidecar so a reused identity cannot inherit stale style")
	destroy_runtime(&rt)

	destroy_rt := new_runtime(Rect{0, 0, 240, 120})
	destroy_nodes := style_text_field_cache_scope_describe(&destroy_rt, 1)
	if destroy_nodes.scaled != 0 {
		destroy_field := destroy_rt.nodes[destroy_nodes.scaled]
		_ = style_text_field_resolve_retained(&destroy_rt, destroy_field, Text_Field_Visual_State{})
	}
	_, destroy_cached := destroy_rt.computed_styles[destroy_nodes.scaled]
	testing.expect(t, destroy_nodes.scaled != 0 && destroy_cached,
		"runtime destruction fixture should populate a computed-style sidecar first")
	destroy_runtime(&destroy_rt)
}
