package alicorn

import "core:testing"

test_theme_for_live_replace :: proc(color: Color) -> Style_Theme {
	theme := DEFAULT_STYLE_THEME
	theme.colors[int(Style_Color_Role.Accent)] = color
	return theme
}

@(test)
test_live_theme_replace_keeps_stable_id_and_bounded_registry :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 120, 80}, Runtime_Config{trace_capacity=4})
	defer destroy_runtime(&rt)
	initial := test_theme_for_live_replace(Color{0.2, 0.1, 0.1, 1})
	id := style_theme_register(&rt, initial)
	testing.expect(t, id != 0, "valid development theme should register")
	registered_count := len(rt.style_themes)

	node := new(Node, allocator=rt.persistent_allocator)
	node^ = Node{
		id=41,
		active=true,
		present=true,
		style_environment=Style_Environment{theme=id},
		button_variant=.Primary,
		caret=Text_Position{byte=17, affinity=.Trailing},
		selection_anchor=Text_Position{byte=4, affinity=.Leading},
		selection_focus=Text_Position{byte=17, affinity=.Trailing},
		scroll_offset_y=240,
	}
	rt.nodes[node.id] = node
	rt.focused = node.id
	rt.semantic_revision = 17
	first_style := style_button_resolve_retained(&rt, node, Button_Visual_State{})
	_ = first_style
	previous_generation := node.style_generations.paint
	registered_snapshot := rt.style_themes[int(u32(id))-1]
	testing.expect(t, style_theme_replace(&rt, id, registered_snapshot) == .Unchanged, "identical candidate should be recognized as a no-op")
	rt.invalidated = false

	for index in 0..<4 {
		red := f32(index%2)*0.5 + 0.2
		candidate := test_theme_for_live_replace(Color{red, 0.15, 0.2, 1})
		testing.expect(t, style_theme_replace(&rt, id, candidate) == .Replaced, "valid theme candidate should replace in place")
		testing.expect(t, rt.style_themes[int(u32(id))-1].colors[int(Style_Color_Role.Accent)] == candidate.colors[int(Style_Color_Role.Accent)],
			"the stable theme ID should resolve to the newest accepted values")
		testing.expect(t, style_theme_color(&rt, id, .Accent) == candidate.colors[int(Style_Color_Role.Accent)],
			"the style query API should expose the newest color value")
		cached, cached_ok := rt.computed_styles[node.id]
		testing.expect(t, cached_ok && !cached.valid, "replacement should invalidate the retained computed style")
		updated_style := style_button_resolve_retained(&rt, node, Button_Visual_State{})
		fresh_style := style_button_resolve(&rt, node.style_environment, .Primary, Button_Visual_State{})
		testing.expect(t, updated_style == fresh_style,
			"same-ID replacement must recompute the cached style from the newest theme")
	}
	bytes_after_warmup := rt.allocation_stats.persistent_requested_bytes_live
	for index in 4..<64 {
		red := f32(index%2)*0.5 + 0.2
		candidate := test_theme_for_live_replace(Color{red, 0.15, 0.2, 1})
		testing.expect(t, style_theme_replace(&rt, id, candidate) == .Replaced, "repeated theme candidate should replace")
		updated_style := style_button_resolve_retained(&rt, node, Button_Visual_State{})
		fresh_style := style_button_resolve(&rt, node.style_environment, .Primary, Button_Visual_State{})
		testing.expect(t, updated_style == fresh_style,
			"repeated replacement should keep computed paint current")
	}

	testing.expect(t, len(rt.style_themes) == registered_count, "repeated live edits must not grow the theme registry")
	testing.expect(t, rt.allocation_stats.persistent_requested_bytes_live == bytes_after_warmup,
		"after bounded trace/cache warmup, repeated replacements must not grow live runtime allocations")
	testing.expect(t, node.style_generations.paint > previous_generation, "same-ID replacement must advance paint generations")
	testing.expect(t, Dirty_Stage.Paint in node.dirty && Dirty_Stage.Composite in node.dirty,
		"paint replacement must queue repaint and composition")
	testing.expect(t, Dirty_Stage.Measure not_in node.dirty && !rt.layout_pending && rt.stats.layout_nodes_visited == 0,
		"paint-only replacement must not schedule or visit layout")
	testing.expect(t, rt.presentation_pending, "paint-only replacement should request presentation")
	testing.expect(t, !rt.invalidated, "paint-only replacement must not request an application description rebuild")
	testing.expect(t, rt.semantic_revision == 17, "visual theme replacement must not change semantic revision")
	testing.expect(t, rt.focused == node.id && node.caret.byte == 17 && node.selection_anchor.byte == 4 &&
		node.selection_focus.byte == 17 && node.scroll_offset_y == 240,
		"paint-only replacement must preserve focus, text selection, caret, and scroll anchoring")
}

@(test)
test_live_theme_replace_rejects_invalid_or_open_frame_candidates :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 120, 80})
	defer destroy_runtime(&rt)
	id := style_theme_register(&rt, test_theme_for_live_replace(Color{0.2, 0.1, 0.1, 1}))
	old_color := style_theme_color(&rt, id, .Text)

	invalid := test_theme_for_live_replace(Color{0.4, 0.1, 0.1, 1})
	invalid.colors[int(Style_Color_Role.Text)].r = 2
	testing.expect(t, style_theme_replace(&rt, id, invalid) == .Rejected, "invalid candidate should be rejected")
	testing.expect(t, style_theme_color(&rt, id, .Text) == old_color, "invalid candidate must preserve last good theme")

	rt.frame_open = true
	valid := test_theme_for_live_replace(Color{0.7, 0.1, 0.1, 1})
	testing.expect(t, style_theme_replace(&rt, id, valid) == .Rejected, "replacement during an open frame should be rejected")
	rt.frame_open = false
	testing.expect(t, style_theme_color(&rt, id, .Text) == old_color, "rejected publication must not mutate the active theme")
	testing.expect(t, style_theme_replace(&rt, DEFAULT_STYLE_THEME_ID, valid) == .Rejected, "the default theme must remain immutable")
}

@(test)
test_live_theme_metric_replace_invalidates_root_and_measurement :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 120, 80})
	defer destroy_runtime(&rt)
	theme := DEFAULT_STYLE_THEME
	theme.control_metrics.defined = true
	id := style_theme_register(&rt, theme)
	node := new(Node, allocator=rt.persistent_allocator)
	node^ = Node{
		id=42,
		active=true,
		present=true,
		style_environment=Style_Environment{theme=id},
	}
	rt.nodes[node.id] = node

	next := theme
	next.control_metrics.button.preferred_height += 4
	testing.expect(t, style_theme_replace(&rt, id, next) == .Replaced, "valid metric candidate should replace")
	testing.expect(t, rt.invalidated, "metric replacement should rebuild application-authored metric consumers")
	testing.expect(t, Dirty_Stage.Measure in node.dirty, "metric replacement must invalidate measurement")
	testing.expect(t, rt.layout_pending && node.style_generations.metrics > 0,
		"metric replacement must schedule retained layout and advance metric generation")
	testing.expect(t, rt.semantic_revision == 0, "metric-only theme change must not mutate accessibility semantics")
}

@(test)
test_live_theme_replacement_is_runtime_local :: proc(t: ^testing.T) {
	left := new_runtime(Rect{0, 0, 120, 80})
	defer destroy_runtime(&left)
	right := new_runtime(Rect{0, 0, 120, 80})
	defer destroy_runtime(&right)
	left_id := style_theme_register(&left, test_theme_for_live_replace(Color{0.2, 0.1, 0.1, 1}))
	right_id := style_theme_register(&right, test_theme_for_live_replace(Color{0.3, 0.1, 0.1, 1}))
	testing.expect(t, left_id == right_id, "independent windows may use the same local theme ID")

	replacement := test_theme_for_live_replace(Color{0.8, 0.1, 0.1, 1})
	testing.expect(t, style_theme_replace(&left, left_id, replacement) == .Replaced, "one runtime should accept its own replacement")
	testing.expect(t, style_theme_color(&left, left_id, .Accent) == replacement.colors[int(Style_Color_Role.Accent)],
		"the updated runtime should expose its own replacement")
	testing.expect(t, style_theme_color(&right, right_id, .Accent) == Color{0.3, 0.1, 0.1, 1},
		"a separate runtime's window theme must remain unchanged")
}
