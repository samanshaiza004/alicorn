package alicorn

import "core:testing"

button_relief_fixture :: proc(rt: ^Runtime, theme: Style_Theme_ID, activated: ^bool = nil) -> Node_ID {
	invalidate_root(rt, "button relief theme fixture")
	ui, build := begin_frame(rt)
	if !build { return 0 }
	container_begin(&ui, .Root, key=key_string("relief-root"), style=layout_style(.Column))
	scope := style_environment_push(&ui, Style_Environment{theme=theme})
	clicked := button(&ui, "Apply", key=key_string("relief-button"), style=layout_style(width=140, height=40))
	if activated != nil { activated^ = clicked }
	style_environment_pop(&ui, scope)
	container_end(&ui)
	end_frame(&ui)
	return style_recipe_test_button(rt, "Apply")
}

@(test)
test_button_relief_preserves_geometry_focus_and_retained_work :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 300, 180})
	defer destroy_runtime(&rt)
	flat := style_theme_register(&rt, DEFAULT_STYLE_THEME)
	material := style_material_register(&rt, Style_Material{kind=.Analytic_Relief, bevel_width=1, bevel_strength=0.35, inner_shadow_strength=0.1, outer_shadow_strength=0.15, outer_shadow_radius=2})
	theme := DEFAULT_STYLE_THEME
	theme.button_recipes.recipes[int(Button_Variant.Default)].rest_surface = {defined=true, material=material, physical_height=0.5}
	theme.button_recipes.recipes[int(Button_Variant.Default)].pressed_surface = {defined=true, material=material, physical_height=-0.25}
	relief := style_theme_register(&rt, theme)
	testing.expect(t, relief != 0, "a registered material should support typed Button treatments")
	id := button_relief_fixture(&rt, flat)
	if id == 0 { testing.expect(t, false, "fixture should retain its Button"); return }
	_ = focus(&rt, id)
	_ = button_relief_fixture(&rt, flat)
	original := rt.nodes[id]^
	layout := rt.stats.layout_nodes_visited
	measurements, shapes := rt.stats.measure_requests, rt.stats.text_shape_requests
	semantic_revision := rt.semantic_revision
	testing.expect(t, button_relief_fixture(&rt, relief) == id && rt.focused == id, "theme changes preserve identity and focus")
	node := rt.nodes[id]
	testing.expect(t, node.bounds == original.bounds && node.hit_bounds == original.hit_bounds && node.clip == original.clip, "relief never changes layout, clips, or hit geometry")
	testing.expect(t, rt.stats.layout_nodes_visited == layout, "material-only themes must not re-enter layout")
	testing.expect(t, rt.stats.measure_requests == measurements && rt.stats.text_shape_requests == shapes && rt.semantic_revision == semantic_revision,
		"optical changes preserve measurement, shaping and semantic truth")
	paint, found := node.paint[0].payload.(Surface_Paint)
	testing.expect(t, found && paint.material == material && paint.physical_height == 0.5, "rest paint uses the generic material surface")
	x, y := node.bounds.x+20, node.bounds.y+20
	_ = process_pointer(&rt, Pointer_Event{kind=.Down, x=x, y=y})
	_ = button_relief_fixture(&rt, relief)
	node = rt.nodes[id]
	paint, found = node.paint[0].payload.(Surface_Paint)
	testing.expect(t, found && paint.physical_height == -0.25 && node.bounds == original.bounds, "pointer press changes optical treatment without moving its target")
	_ = process_pointer(&rt, Pointer_Event{kind=.Up, x=x, y=y})
	activated := false
	_ = button_relief_fixture(&rt, relief, &activated)
	testing.expect(t, activated, "release dispatches the action through the ordinary Button path")
	testing.expect(t, rt.stats.layout_nodes_visited == layout && rt.focused == id, "press/release preserves layout and focus")
	_ = button_relief_fixture(&rt, relief, &activated)
	testing.expect(t, !activated, "later descriptions do not repeat the action")
	_, idle_build := begin_frame(&rt)
	testing.expect(t, !idle_build, "settled relief has no description work")
	_, idle_present := begin_presentation_frame(&rt)
	testing.expect(t, !idle_present, "settled relief schedules no presentation work")
}

@(test)
test_button_relief_presence_validation_and_accessibility :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 200, 100})
	defer destroy_runtime(&rt)
	material := style_material_register(&rt, Style_Material{kind=.Analytic_Relief, bevel_width=1, bevel_strength=0.3, outer_shadow_strength=0.2, outer_shadow_radius=3})
	theme := DEFAULT_STYLE_THEME
	recipe := &theme.button_recipes.recipes[int(Button_Variant.Default)]
	recipe.rest_surface = {defined=true, material=material, physical_height=0.5}
	id := style_theme_register(&rt, theme)
	environment := Style_Environment{theme=id}
	pressed := style_button_resolve(&rt, environment, .Default, {pressed=true})
	testing.expect(t, pressed.material == material && pressed.physical_height == 0.5, "omitted pressed treatment inherits rest")
	recipe.pressed_surface = {defined=true}
	id = style_theme_register(&rt, theme)
	environment.theme = id
	pressed = style_button_resolve(&rt, environment, .Default, {pressed=true})
	testing.expect(t, pressed.material == MATERIAL_FLAT && pressed.physical_height == 0, "explicit flat pressed treatment overrides rest")
	disabled := style_button_resolve(&rt, environment, .Default, {pressed=true, disabled=true})
	testing.expect(t, disabled.material == material && disabled.physical_height == 0.5, "disabled controls cannot gain a pressed optical treatment")
	environment.accessibility = {increased_contrast=true, reduce_transparency=true}
	accessible := style_button_resolve(&rt, environment, .Default, {})
	variant, ok := style_material_resolve(&rt, accessible.material)
	testing.expect(t, ok && variant.bevel_strength >= 0.75 && variant.outer_shadow_strength == 0, "Button materials consume contrast and transparency preferences")
	recipe.rest_surface.physical_height = 3
	testing.expect(t, style_theme_register(&rt, theme) == 0, "out of range height is rejected")
	recipe.rest_surface.physical_height = 0.5
	recipe.rest_surface.material = Material_ID(9999)
	testing.expect(t, style_theme_register(&rt, theme) == 0, "unregistered material is rejected before paint")
}
