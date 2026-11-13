package alicorn

import "core:testing"
import "core:strings"
import "core:math"

@(test)
test_surface_corner_radii_validate_copy_hash_and_normalize :: proc(t: ^testing.T) {
	authored := Surface_Corner_Radii{top_left=80, top_right=40, bottom_right=40, bottom_left=80}
	shape := surface_shape_rounded_corners(authored)
	paint := Surface_Paint{shape=surface_paint_shape(shape)}
	shape_copy := shape
	testing.expect(t, surface_shape_is_valid(shape) && paint.shape == surface_paint_shape(shape) &&
		shape_copy == shape && surface_shape_corner_radii(shape) == authored,
		"a valid per-corner shape should preserve its exact f32 values in retained style data and compact paint references")

	style := Semantic_Surface_Style{defined=true, shape=shape}
	changed := style
	changed.shape.corner_radii.top_left += 1
	testing.expect(t, semantic_surface_style_hash(changed) != semantic_surface_style_hash(style),
		"a corner-only edit should change the retained surface style hash")
	changed = style
	changed.shape.corner_radii.top_right += 1
	testing.expect(t, semantic_surface_style_hash(changed) != semantic_surface_style_hash(style),
		"each authored corner should participate in retained invalidation")
	changed = style
	changed.shape.corner_radii.bottom_right += 1
	testing.expect(t, semantic_surface_style_hash(changed) != semantic_surface_style_hash(style),
		"the bottom-right radius should participate in retained invalidation")
	changed = style
	changed.shape.corner_radii.bottom_left += 1
	testing.expect(t, semantic_surface_style_hash(changed) != semantic_surface_style_hash(style),
		"the bottom-left radius should participate in retained invalidation")

	normalized := surface_corner_radii_normalize(authored, 100, 50)
	testing.expect(t, abs(normalized.top_left-25) < 0.001 &&
		abs(normalized.top_right-12.5) < 0.001 &&
		abs(normalized.bottom_right-12.5) < 0.001 &&
		abs(normalized.bottom_left-25) < 0.001,
		"all opposing radius constraints should share one proportional normalization factor")
	testing.expect(t, normalized.top_left+normalized.top_right <= 100.001 &&
		normalized.top_right+normalized.bottom_right <= 50.001 &&
		normalized.bottom_right+normalized.bottom_left <= 100.001 &&
		normalized.bottom_left+normalized.top_left <= 50.001,
		"normalized corner arcs should not overlap along any side")

	large := surface_corner_radii_normalize(Surface_Corner_Radii{1e30, 1e30, 1e30, 1e30}, 100, 50)
	testing.expect(t, surface_corner_radii_is_valid(large) && large.top_left == 25 && large.top_right == 25 &&
		large.bottom_right == 25 && large.bottom_left == 25,
		"every finite f32 radius should normalize without overflow")
	testing.expect(t, surface_corner_radii_is_zero(surface_corner_radii_normalize(authored, 0, 50)) &&
		surface_corner_radii_is_zero(surface_corner_radii_normalize(authored, 100, 0)) &&
		surface_corner_radii_is_zero(surface_corner_radii_normalize(authored, math.QNAN_F32, 50)),
		"zero or invalid bounds should resolve to square corners")
	testing.expect(t, !surface_corner_radii_is_valid(Surface_Corner_Radii{top_left=-1}) &&
		!surface_corner_radii_is_valid(Surface_Corner_Radii{top_right=math.INF_F32}) &&
		!surface_shape_is_valid(surface_shape_rounded_corners(Surface_Corner_Radii{bottom_left=math.QNAN_F32})),
		"negative and non-finite radii should be rejected at the semantic surface boundary")
	legacy := Surface_Shape{kind=.Rounded_Rectangle, corner_radius=7}
	legacy_radii := surface_shape_corner_radii(legacy)
	testing.expect(t, surface_shape_is_valid(legacy) && legacy_radii == Surface_Corner_Radii{7, 7, 7, 7},
		"the legacy uniform radius should remain valid and resolve to four equal corners")
}

@(test)
test_backdrop_is_an_ordered_surface_boundary :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 180, 100})
	defer destroy_runtime(&rt)
	effect := backdrop_blur(4, .Direct)
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "backdrop boundary fixture should build"); return }
	container_begin(&ui, .Root, key=key_string("backdrop-boundary-root"), style=layout_style(width=180, height=100))
	id := surface_begin(&ui, surface_core_color_role(.Surface), key=key_string("backdrop-boundary"),
		style=layout_style(width=120, height=60), fill=Color{0.2, 0.3, 0.4, 0.88}, backdrop_effect=effect)
	text(&ui, "foreground remains ordinary text", key=key_string("backdrop-boundary-text"))
	surface_end(&ui)
	container_end(&ui)
	end_frame(&ui)

	node := rt.nodes[id]
	testing.expect(t, len(node.paint) == 2 && paint_command_is_backdrop_effect(node.paint[0]) && paint_command_is_surface(node.paint[1]),
		"the backdrop marker should be ordered before its translucent surface, leaving child foreground paint afterward")
	if len(node.paint) >= 2 {
		marker, marker_ok := node.paint[0].payload.(Backdrop_Effect_Paint)
		fill, fill_ok := paint_surface_color(node.paint[1])
		testing.expect(t, marker_ok && marker.sigma == 4 && marker.fallback == .Direct && fill_ok && fill.a == 0.88,
			"the generic paint boundary should carry a bounded blur request and preserve the app-selected translucent fill")
	}
	style := rt.semantic_surfaces[id]
	changed := style
	changed.backdrop_effect.sigma = 5
	testing.expect(t, semantic_surface_style_hash(changed) != semantic_surface_style_hash(style),
		"changing effect parameters should invalidate the retained surface description")
	testing.expect(t, !backdrop_effect_is_valid(backdrop_blur(9)),
		"blur sigma beyond the supported logical bound must be rejected")
}

@(test)
test_semantic_surface_composes_children_and_resolves_extension_role :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 240, 140})
	defer destroy_runtime(&rt)

	role := style_extension_color_role_id("app.scratchpad.editor", "paper_surface")
	paper := Color{0.91, 0.88, 0.78, 1}
	theme := DEFAULT_STYLE_THEME
	theme.colors[int(Style_Color_Role.Accent)] = Color{0.35, 0.55, 0.75, 1}
	theme.color_tokens = {paper}
	theme.extension_color_roles = {Style_Extension_Color_Role_Binding{role=role, token=Style_Color_Token_ID(1)}}
	theme_id := style_theme_register(&rt, theme)
	testing.expect(t, theme_id != 0, "theme with an app-namespaced surface role should register")

	material := Style_Material{
		kind=.Analytic_Relief,
		bevel_width=1.25,
		bevel_strength=0.14,
		inner_shadow_strength=0.08,
		outer_shadow_strength=0.04,
		outer_shadow_radius=2,
	}
	material_id := style_material_register(&rt, material)
	testing.expect(t, material_id != MATERIAL_FLAT, "surface material should be registered once during app setup")

	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "semantic surface fixture should describe its first frame"); return }
	container_begin(&ui, .Root, key=key_string("semantic-surface-root"), style=layout_style(width=220, height=120))
	scope := style_environment_push(&ui, Style_Environment{theme=theme_id})
	surface := surface_begin(
		&ui,
		surface_extension_color_role(role),
		key=key_string("semantic-paper"),
		style=layout_style(width=160, height=80, padding=8),
		shape=Surface_Shape{kind=.Rectangle},
		material=material_id,
		physical_height=1.25,
		material_group=Material_Group_ID(7),
		label="paper",
	)
	child := text(&ui, "editable content", key=key_string("semantic-paper-child"), style=layout_style(width=100, height=24))
	surface_end(&ui)
	core_surface := surface_begin(
		&ui,
		surface_core_color_role(.Accent),
		key=key_string("semantic-core-surface"),
		style=layout_style(width=64, height=24),
		label="core accent surface",
	)
	surface_end(&ui)
	style_environment_pop(&ui, scope)
	container_end(&ui)
	end_frame(&ui)

	node, surface_exists := rt.nodes[surface]
	child_node, child_exists := rt.nodes[child]
	testing.expect(t, surface_exists && child_exists && child_node.parent == surface,
		"semantic surface should behave as an ordinary layout container for its children")
	if !surface_exists || !child_exists { return }
	testing.expect(t, node.style_environment.theme == theme_id,
		"the surface should retain the theme environment active where it was declared")
	testing.expect(t, child_node.bounds.x >= node.bounds.x && child_node.bounds.y >= node.bounds.y &&
		child_node.bounds.x+child_node.bounds.w <= node.bounds.x+node.bounds.w &&
		child_node.bounds.y+child_node.bounds.h <= node.bounds.y+node.bounds.h,
		"children should be laid out inside the semantic surface bounds")
	testing.expect(t, len(node.paint) == 1 && paint_command_is_surface(node.paint[0]),
		"the app-facing surface should emit one generic Surface paint command")
	if len(node.paint) == 1 {
		fill, fill_ok := paint_surface_color(node.paint[0])
		payload, payload_ok := node.paint[0].payload.(Surface_Paint)
		testing.expect(t, fill_ok && fill == paper,
			"a namespaced role should resolve through the active theme into the paint fill")
		testing.expect(t, payload_ok && payload.shape == surface_paint_shape(Surface_Shape{kind=.Rectangle}) &&
			payload.material == material_id && payload.physical_height == 1.25 &&
			payload.material_group == Material_Group_ID(7),
			"surface paint should carry shape and optical material metadata without affecting layout")
		if payload_ok {
			testing.expect(t, node.paint[0].bounds == node.bounds && node.paint[0].clip == node.clip,
				"the runtime should provide resolved bounds and clipping to the generic renderer")
		}
	}
	core_node, core_exists := rt.nodes[core_surface]
	core_fill_ok := false
	if core_exists && len(core_node.paint) == 1 {
		core_fill, core_fill_valid := paint_surface_color(core_node.paint[0])
		core_fill_ok = core_fill_valid && core_fill == theme.colors[int(Style_Color_Role.Accent)]
	}
	testing.expect(t, core_fill_ok, "core-role surfaces should resolve through the same active theme scope")
	inspection := inspect(&rt)
	defer delete(inspection)
	testing.expect(t, strings.contains(inspection, "semantic surface: role=extension.") &&
		strings.contains(inspection, "token=1 shape=rectangle radius=0.00 corner-radii=(0.00 0.00 0.00 0.00)") &&
		strings.contains(inspection, "arc=(center=0.000,0.000 radius=0.000 start=0.000 sweep=0.000)") &&
		strings.contains(inspection, "bezier=[[0, 0], [0, 0], [0, 0], [0, 0]]") &&
		strings.contains(inspection, "material=1(analytic-relief) height=1.25 group=7") &&
		strings.contains(inspection, "resolution=retained-cache dependencies=paint,material generations=(paint=") &&
		node.style_generations.paint > 0 && node.style_generations.material > 0,
		"inspector should explain extension-role token, optical surface inputs, and paint/material generation context")
}

@(test)
test_style_environment_scope_failure_reports_the_call_site :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 120, 80})
	defer destroy_runtime(&rt)
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "style diagnostic fixture should build"); return }
	_ = style_environment_push(&ui, Style_Environment{theme=DEFAULT_STYLE_THEME_ID})
	testing.expect(t, strings.contains(rt.diagnostic, "Style environment error at") &&
		strings.contains(rt.diagnostic, "style_surface_test.odin:") &&
		strings.contains(rt.diagnostic, "described container boundary"),
		"an invalid style scope should point back to the consumer's source location and explain the required boundary")
	end_frame(&ui)
}

@(test)
test_semantic_surface_accepts_direct_fill_and_stroke :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 160, 100})
	defer destroy_runtime(&rt)
	fill := Color{0.20, 0.30, 0.40, 1}
	border := Color{0.10, 0.70, 0.90, 1}
	ui, should_build := begin_frame(&rt)
	if !should_build { testing.expect(t, false, "direct surface fixture should describe its first frame"); return }
	container_begin(&ui, .Root, key=key_string("direct-surface-root"), style=layout_style(width=160, height=100))
	id := surface_begin(
		&ui,
		surface_core_color_role(.Surface),
		key=key_string("direct-surface-card"),
		style=layout_style(width=120, height=72, padding=8),
		shape=Surface_Shape{kind=.Rounded_Rectangle, corner_radius=6},
		fill=fill,
		stroke=Paint_Stroke{color=border, width=1},
	)
	text(&ui, "content", key=key_string("direct-surface-content"))
	surface_end(&ui)
	container_end(&ui)
	end_frame(&ui)

	node, found := rt.nodes[id]
	testing.expect(t, found && len(node.paint) == 1,
		"a direct fill and border should remain one ordinary retained surface node")
	if found && len(node.paint) == 1 {
		paint, ok := node.paint[0].payload.(Surface_Paint)
		resolved_shape, resolved_ok := surface_paint_shape_resolve(&rt, id, paint.shape)
		testing.expect(t, ok && paint.fill == fill && paint.stroke == Paint_Stroke{color=border, width=1} &&
			resolved_ok && resolved_shape == Surface_Shape{kind=.Rounded_Rectangle, corner_radius=6},
			"resolved direct appearance should preserve fill, stroke, and rounded geometry")
	}
	style := rt.semantic_surfaces[id]
	testing.expect(t, style.fill_override_set && style.fill_override == fill && style.stroke.color == border,
		"direct appearance inputs should be retained in the existing semantic-surface sidecar")

	changed := style
	changed.fill_override = Color{0.3, 0.3, 0.4, 1}
	testing.expect(t, semantic_surface_style_hash(changed) != semantic_surface_style_hash(style),
		"changing direct fill must invalidate the retained surface paint description")
	changed = style
	changed.stroke_placement = .Outside
	testing.expect(t, semantic_surface_style_hash(changed) != semantic_surface_style_hash(style),
		"changing border placement must invalidate retained surface paint")
}

@(test)
test_semantic_surface_rejects_invalid_recipes_before_opening_container :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 120, 80})
	defer destroy_runtime(&rt)
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "invalid surface fixture should build"); return }
	container_begin(&ui, .Root, key=key_string("invalid-surface-root"), style=layout_style())
	stack_depth := len(rt.stack)
	invalid_material := Semantic_Surface_Style{
		defined=true,
		role=surface_core_color_role(.Surface),
		shape=Surface_Shape{kind=.Rectangle},
		material=Material_ID(99),
	}
	valid_environment := rt.style_environment
	testing.expect(t, !semantic_surface_style_is_valid(&rt, valid_environment, invalid_material),
		"an unregistered material handle must not enter retained paint")
	invalid_shape := invalid_material
	invalid_shape.material = MATERIAL_FLAT
	invalid_shape.shape = Surface_Shape{kind=.Rounded_Rectangle, corner_radius=8}
	testing.expect(t, semantic_surface_style_is_valid(&rt, valid_environment, invalid_shape),
		"uniform rounded surfaces with a finite nonnegative radius should be accepted")
	invalid_shape.shape.corner_radius = -1
	testing.expect(t, !semantic_surface_style_is_valid(&rt, valid_environment, invalid_shape),
		"negative corner radii must be rejected before paint")
	invalid_shape.shape = Surface_Shape{kind=.Line}
	testing.expect(t, !semantic_surface_style_is_valid(&rt, valid_environment, invalid_shape),
		"line geometry is not a filled semantic surface")
	missing_role := invalid_material
	missing_role.material = MATERIAL_FLAT
	missing_role.role = surface_extension_color_role(style_extension_color_role_id("app.missing", "surface"))
	testing.expect(t, !semantic_surface_style_is_valid(&rt, valid_environment, missing_role),
		"an extension role missing from the active theme should be rejected explicitly")
	id := surface_begin(&ui, surface_core_color_role(.Surface), key=key_string("invalid-material-surface"), material=Material_ID(99))
	testing.expect(t, id == 0 && len(rt.stack) == stack_depth,
		"an unregistered material should return without opening a partially composed container")
	id = surface_begin(
		&ui,
		surface_core_color_role(.Surface),
		key=key_string("supported-rounded-surface"),
		shape=Surface_Shape{kind=.Rounded_Rectangle, corner_radius=8},
	)
	testing.expect(t, id != 0 && len(rt.stack) == stack_depth+1,
		"a rounded shape should open its ordinary semantic surface container")
	surface_end(&ui)
	id = surface_begin(&ui, surface_core_color_role(.Surface), key=key_string("negative-rounded-surface"), shape=Surface_Shape{kind=.Rounded_Rectangle, corner_radius=-1})
	testing.expect(t, id == 0 && len(rt.stack) == stack_depth,
		"an invalid rounded shape must fail without opening a layout scope")
	container_end(&ui)
	end_frame(&ui)
}

@(test)
test_semantic_surface_sidecar_is_retired_with_its_node :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 120, 80})
	defer destroy_runtime(&rt)
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "surface lifetime fixture should build"); return }
	container_begin(&ui, .Root, key=key_string("surface-lifetime-root"), style=layout_style())
	id := surface_begin(&ui, surface_core_color_role(.Subtle_Surface), key=key_string("surface-lifetime-node"), style=layout_style(width=48, height=32))
	surface_end(&ui)
	container_end(&ui)
	end_frame(&ui)
	_, retained := rt.semantic_surfaces[id]
	testing.expect(t, retained, "reconciliation should retain the semantic recipe beside its node")

	invalidate_root(&rt, "retire semantic surface fixture")
	ui, build = begin_frame(&rt)
	if !build { testing.expect(t, false, "retirement frame should rebuild the root"); return }
	container_begin(&ui, .Root, key=key_string("surface-lifetime-root"), style=layout_style())
	container_end(&ui)
	end_frame(&ui)
	_, retained = rt.semantic_surfaces[id]
	testing.expect(t, !retained && id not_in rt.nodes,
		"retiring a surface node should also release its sidecar recipe")
}

@(test)
test_semantic_surface_material_input_advances_material_generation :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 120, 80})
	defer destroy_runtime(&rt)
	analytic_material := style_material_register(&rt, Style_Material{kind=.Analytic_Relief, bevel_width=1, bevel_strength=0.12})
	describe := proc(rt: ^Runtime, height: f32, material: Material_ID) -> Node_ID {
		invalidate_root(rt, "semantic surface material generation fixture")
		ui, build := begin_frame(rt)
		if !build { return 0 }
		container_begin(&ui, .Root, key=key_string("material-generation-root"), style=layout_style())
		id := surface_begin(&ui, surface_core_color_role(.Surface), key=key_string("material-generation-surface"),
			style=layout_style(width=64, height=40), material=material, physical_height=height)
		surface_end(&ui)
		container_end(&ui)
		end_frame(&ui)
		return id
	}

	id := describe(&rt, 0.25, MATERIAL_FLAT)
	first, found := rt.nodes[id]
	testing.expect(t, found && first.style_generations.material > 0,
		"first semantic surface description should establish its material dependency generation")
	if !found { return }
	first_generation := first.style_generations.material
	first_paint_generation := first.style_generations.paint
	first_bounds := first.bounds
	first_hit_bounds := first.hit_bounds
	first_layout_visits := rt.stats.layout_nodes_visited
	_ = describe(&rt, 0.75, analytic_material)
	second := rt.nodes[id]
	testing.expect(t, second.style_generations.material > first_generation,
		"changing optical height/material on the same retained surface should advance its material dependency generation")
	testing.expect(t, second.style_generations.paint == first_paint_generation,
		"a material-only surface change should not advance Paint generation")
	testing.expect(t, second.bounds == first_bounds && second.hit_bounds == first_hit_bounds,
		"a material-only surface change should preserve layout and hit geometry")
	testing.expect(t, rt.stats.layout_nodes_visited == first_layout_visits,
		"changing only surface material inputs should not visit nodes during layout")
}

@(test)
test_corner_radius_only_change_skips_text_measurement_and_layout :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 120, 80})
	defer destroy_runtime(&rt)
	describe := proc(rt: ^Runtime, radii: Surface_Corner_Radii) -> Node_ID {
		invalidate_root(rt, "corner radius only invalidation fixture")
		ui, build := begin_frame(rt)
		if !build { return 0 }
		container_begin(&ui, .Root, key=key_string("corner-radius-root"), style=layout_style(width=120, height=80))
		id := surface_begin(&ui, surface_core_color_role(.Surface), key=key_string("corner-radius-surface"),
			style=layout_style(width=96, height=56), shape=surface_shape_rounded_corners(radii))
		text(&ui, "Retained label", key=key_string("corner-radius-label"))
		surface_end(&ui)
		container_end(&ui)
		end_frame(&ui)
		return id
	}

	id := describe(&rt, Surface_Corner_Radii{4, 4, 4, 4})
	first := rt.nodes[id]
	shape_requests := rt.stats.text_shape_requests
	measure_requests := rt.stats.measure_requests
	layout_visits := rt.stats.layout_nodes_visited
	paint_visits := rt.stats.paint_nodes_visited
	first_material_generation := first.style_generations.material
	_ = describe(&rt, Surface_Corner_Radii{4, 12, 4, 4})
	second := rt.nodes[id]
	if len(second.paint) != 1 {
		testing.expect(t, false, "the updated surface should keep one paint command")
		return
	}
	testing.expect(t, second.style_generations.material > first_material_generation && second.bounds == first.bounds,
		"an isolated radius change should update retained surface material state without changing its bounds")
	testing.expect(t, rt.stats.text_shape_requests == shape_requests && rt.stats.measure_requests == measure_requests &&
		rt.stats.layout_nodes_visited == layout_visits,
		"a radius-only surface update must not shape text, measure, or run layout")
	testing.expect(t, rt.stats.paint_nodes_visited > paint_visits && len(second.paint) == 1,
		"the localized change should rebuild the retained surface paint command")
	paint, paint_ok := second.paint[0].payload.(Surface_Paint)
	resolved_shape, resolved_ok := surface_paint_shape_resolve(&rt, id, paint.shape)
	testing.expect(t, paint_ok && resolved_ok && resolved_shape == surface_shape_rounded_corners(Surface_Corner_Radii{4, 12, 4, 4}),
		"the renderer-facing compact command should resolve the latest retained corner values, not stale paint data")

	fresh := new_runtime(Rect{0, 0, 120, 80})
	defer destroy_runtime(&fresh)
	fresh_id := describe(&fresh, Surface_Corner_Radii{4, 12, 4, 4})
	fresh_node := fresh.nodes[fresh_id]
	if len(fresh_node.paint) != 1 {
		testing.expect(t, false, "a fresh runtime should emit one surface paint command")
		return
	}
	fresh_paint, fresh_paint_ok := fresh_node.paint[0].payload.(Surface_Paint)
	fresh_shape, fresh_shape_ok := surface_paint_shape_resolve(&fresh, fresh_id, fresh_paint.shape)
	testing.expect(t, fresh_paint_ok && fresh_shape_ok && resolved_shape == fresh_shape &&
		semantic_surface_style_hash(rt.semantic_surfaces[id]) == semantic_surface_style_hash(fresh.semantic_surfaces[fresh_id]) &&
		second.bounds == fresh_node.bounds && second.paint[0].bounds == fresh_node.paint[0].bounds,
		"incremental retained replay should match a fresh runtime built with the same per-corner shape")
}

@(test)
test_surface_gradient_resolves_theme_stops_and_invalidates_paint_only :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 160, 100})
	defer destroy_runtime(&rt)
	start_role := style_extension_color_role_id("app.gradient", "start")
	end_role := style_extension_color_role_id("app.gradient", "end")
	start := Color{0.08, 0.16, 0.28, 0.6}
	end := Color{0.72, 0.44, 0.20, 0.6}
	theme := DEFAULT_STYLE_THEME
	theme.color_tokens = {start, end}
	theme.extension_color_roles = {
		Style_Extension_Color_Role_Binding{role=start_role, token=Style_Color_Token_ID(1)},
		Style_Extension_Color_Role_Binding{role=end_role, token=Style_Color_Token_ID(2)},
	}
	theme_id := style_theme_register(&rt, theme)
	testing.expect(t, theme_id != 0, "both gradient stops should use ordinary namespaced theme color roles")
	ui, build := begin_frame(&rt)
	if !build { testing.expect(t, false, "gradient surface fixture should describe its first frame"); return }
	container_begin(&ui, .Root, key=key_string("gradient-root"), style=layout_style(.Column, width=160, height=100))
	scope := style_environment_push(&ui, Style_Environment{theme=theme_id})
	id := surface_begin(&ui, surface_extension_color_role(start_role), key=key_string("gradient-surface"),
		style=layout_style(width=96, height=48), shape=Surface_Shape{kind=.Rounded_Rectangle, corner_radius=8},
		gradient=surface_gradient_to(surface_extension_color_role(end_role), .Horizontal))
	surface_end(&ui)
	style_environment_pop(&ui, scope)
	container_end(&ui)
	end_frame(&ui)

	node := rt.nodes[id]
	testing.expect(t, len(node.paint) == 1 && node.paint[0].semantic_surface_gradient,
		"an opted-in semantic surface should mark its retained paint command without expanding its payload")
	if len(node.paint) == 1 {
		paint, paint_ok := node.paint[0].payload.(Surface_Paint)
		resolved := semantic_surface_gradient_for_paint_owner(&rt, id)
		testing.expect(t, paint_ok && paint.fill == start && resolved.axis == .Horizontal && resolved.end == end,
			"the start stop should remain the ordinary surface fill and the cached theme role should supply stop two")
	}
	first_paint_generation := node.style_generations.paint
	first_metrics_generation := node.style_generations.metrics
	first_typography_generation := node.style_generations.typography
	first_layout_visits := rt.stats.layout_nodes_visited

	contrast_node := node^
	contrast_node.style_environment.accessibility.increased_contrast = true
	contrast := style_semantic_surface_resolve_retained(&rt, &contrast_node, rt.semantic_surfaces[id])
	testing.expect(t, contrast.gradient.axis == .None,
		"increased contrast should flatten decorative gradients while retaining the first semantic stop and independent focus paint")
	transparency_node := node^
	transparency_node.style_environment.accessibility.reduce_transparency = true
	opaque := style_semantic_surface_resolve_retained(&rt, &transparency_node, rt.semantic_surfaces[id])
	testing.expect(t, opaque.gradient.axis == .Horizontal && opaque.fill.a == 1 && opaque.gradient.end.a == 1,
		"Reduce Transparency should preserve the gradient while making both stops opaque")

	changed_theme := theme
	changed_theme.color_tokens = {start, Color{0.2, 0.6, 0.9, 0.6}}
	testing.expect(t, style_theme_replace(&rt, theme_id, changed_theme) == .Replaced,
		"replacing a gradient endpoint token should update the registered theme")
	updated_node := rt.nodes[id]
	updated := style_semantic_surface_resolve_retained(&rt, updated_node, rt.semantic_surfaces[id])
	testing.expect(t, updated.gradient.end == Color{0.2, 0.6, 0.9, 0.6} &&
		updated_node.style_generations.paint > first_paint_generation,
		"theme replacement should refresh the cached gradient endpoint and advance Paint")
	testing.expect(t, updated_node.style_generations.metrics == first_metrics_generation &&
		updated_node.style_generations.typography == first_typography_generation &&
		rt.stats.layout_nodes_visited == first_layout_visits,
		"gradient endpoint changes must not recompute layout, metrics, or typography")
	testing.expect(t, semantic_surface_gradient_for_paint_owner(&rt, id).end == updated.gradient.end,
		"the renderer lookup should observe the newly resolved paint-only cache product")

	retained_hash := semantic_surface_style_hash(rt.semantic_surfaces[id])
	invalidate_root(&rt, "replay gradient surface description")
	ui, build = begin_frame(&rt)
	if !build { testing.expect(t, false, "gradient replay frame should describe"); return }
	container_begin(&ui, .Root, key=key_string("gradient-root"), style=layout_style(.Column, width=160, height=100))
	replay_scope := style_environment_push(&ui, Style_Environment{theme=theme_id})
	replay_id := surface_begin(&ui, surface_extension_color_role(start_role), key=key_string("gradient-surface"),
		style=layout_style(width=96, height=48), shape=Surface_Shape{kind=.Rounded_Rectangle, corner_radius=8},
		gradient=surface_gradient_to(surface_extension_color_role(end_role), .Horizontal))
	surface_end(&ui)
	style_environment_pop(&ui, replay_scope)
	container_end(&ui)
	end_frame(&ui)
	replay_node := rt.nodes[replay_id]
	testing.expect(t, len(replay_node.paint) == 1 && replay_node.paint[0].semantic_surface_gradient,
		"retained replay should preserve the gradient marker in its paint command")
	testing.expect(t, semantic_surface_style_hash(rt.semantic_surfaces[replay_id]) == retained_hash,
		"retained replay should reproduce the same semantic gradient style")
	testing.expect(t, semantic_surface_gradient_for_paint_owner(&rt, replay_id).end == updated.gradient.end,
		"retained replay should resolve the latest endpoint after theme replacement")

	invalidate_root(&rt, "retire gradient surface")
	ui, build = begin_frame(&rt)
	if !build { testing.expect(t, false, "gradient retirement frame should describe"); return }
	container_begin(&ui, .Root, key=key_string("gradient-root"), style=layout_style(.Column, width=160, height=100))
	container_end(&ui)
	end_frame(&ui)
	_, semantic_retained := rt.semantic_surfaces[id]
	_, cache_retained := rt.computed_styles[id]
	testing.expect(t, !semantic_retained && !cache_retained && id not_in rt.nodes,
		"retiring a gradient surface should release its style and endpoint cache with the retained node")

	bad_alpha := Surface_Gradient{axis=.Vertical, end=Color{0.1, 0.2, 0.3, 0.4}}
	testing.expect(t, !Surface_Gradient_Is_Valid(start, bad_alpha),
		"different stop alpha must be rejected until a premultiplied shader path exists")
	testing.expect(t, !Surface_Gradient_Is_Valid(start, Surface_Gradient{axis=Surface_Gradient_Axis(99), end=end}),
		"unsupported axes must be rejected rather than entering retained paint")
}
