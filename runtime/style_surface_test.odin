package alicorn

import "core:testing"
import "core:strings"

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
		testing.expect(t, payload_ok && payload.shape == Surface_Shape{kind=.Rectangle} &&
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
		strings.contains(inspection, "token=1 shape=rectangle radius=0.00 material=1(analytic-relief) height=1.25 group=7") &&
		strings.contains(inspection, "resolution=description-hashed retained-cache=no dependencies=paint,material generations=(paint=") &&
		node.style_generations.paint > 0 && node.style_generations.material > 0,
		"inspector should explain extension-role token, optical surface inputs, and paint/material generation context")
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
	testing.expect(t, !semantic_surface_style_is_valid(&rt, valid_environment, invalid_shape),
		"the semantic helper must reject rounded surfaces until the renderer supports their shape")
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
		key=key_string("unsupported-rounded-surface"),
		shape=Surface_Shape{kind=.Rounded_Rectangle, corner_radius=8},
	)
	testing.expect(t, id == 0 && len(rt.stack) == stack_depth,
		"an unsupported shape must fail without opening a layout container")
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
	describe := proc(rt: ^Runtime, height: f32) -> Node_ID {
		invalidate_root(rt, "semantic surface material generation fixture")
		ui, build := begin_frame(rt)
		if !build { return 0 }
		container_begin(&ui, .Root, key=key_string("material-generation-root"), style=layout_style())
		id := surface_begin(&ui, surface_core_color_role(.Surface), key=key_string("material-generation-surface"),
			style=layout_style(width=64, height=40), physical_height=height)
		surface_end(&ui)
		container_end(&ui)
		end_frame(&ui)
		return id
	}

	id := describe(&rt, 0.25)
	first, found := rt.nodes[id]
	testing.expect(t, found && first.style_generations.material > 0,
		"first semantic surface description should establish its material dependency generation")
	if !found { return }
	first_generation := first.style_generations.material
	_ = describe(&rt, 0.75)
	second := rt.nodes[id]
	testing.expect(t, second.style_generations.material > first_generation,
		"changing optical height on the same retained surface should advance only its material dependency generation")
}
