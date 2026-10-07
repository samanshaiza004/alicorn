package alicorn

import "core:fmt"
import "core:strings"

stage_word :: proc(value: bool) -> string {
	if value { return "changed" }
	return "reused"
}

style_control_state_name :: proc(state: Style_Control_State) -> string {
	switch state {
	case .Selected: return "selected"
	case .Hovered: return "hovered"
	case .Pressed: return "pressed"
	case .Disabled: return "disabled"
	}
	return "unknown"
}

style_inspector_token_role :: proc(
	sb: ^strings.Builder,
	rt: ^Runtime,
	theme: Style_Theme_ID,
	property, source: string,
	role: Style_Color_Role,
	accent: Style_Accent = 0,
) {
	if role == .Accent && accent != 0 {
		fmt.sbprintf(sb, " %s.%s=%v(environment accent=%d)", property, source, role, u32(accent))
		return
	}
	token := style_theme_color_token(rt, theme, role)
	fmt.sbprintf(sb, " %s.%s=%v", property, source, role)
	if token != 0 {
		fmt.sbprintf(sb, "(token=%d)", u32(token))
		style_inspector_color_token_chain(sb, rt, theme, token)
	}
}

style_inspector_color_token_chain :: proc(sb: ^strings.Builder, rt: ^Runtime, theme: Style_Theme_ID, token: Style_Color_Token_ID) {
	current := token
	first := true
	theme_index := u64(u32(theme))
	if rt == nil || theme_index == 0 || theme_index > u64(len(rt.style_themes)) { return }
	metadata := rt.style_themes[theme_index-1].color_token_provenance
	for _ in 0..<len(metadata) {
		provenance, found := style_token_provenance(rt, theme, current)
		if !found { break }
		if first {
			fmt.sbprintf(sb, " provenance=[%s", provenance.name)
			first = false
		}
		if provenance.alias_target == "" { break }
		fmt.sbprintf(sb, " -> %s", provenance.alias_target)
		next := Style_Color_Token_ID(0)
		for candidate, index in metadata {
			if candidate.name == provenance.alias_target {
				next = Style_Color_Token_ID(index+1)
				break
			}
		}
		if next == 0 { break }
		current = next
	}
	if !first { fmt.sbprintf(sb, "]") }
}

style_inspector_transform_provenance :: proc(
	sb: ^strings.Builder,
	rt: ^Runtime,
	theme: Style_Theme_ID,
	source: string,
	transform: Style_Transform,
	accent: Style_Accent = 0,
) {
	if transform.surface_mix > 0 { style_inspector_token_role(sb, rt, theme, "surface", source, transform.surface_role, accent) }
	if transform.text_mix > 0 { style_inspector_token_role(sb, rt, theme, "text", source, transform.text_role, accent) }
}

style_inspector_control_transform_provenance :: proc(
	sb: ^strings.Builder,
	rt: ^Runtime,
	theme: Style_Theme_ID,
	source: string,
	transform: Control_Part_Transform,
	accent: Style_Accent = 0,
) {
	if transform.surface_mix > 0 { style_inspector_token_role(sb, rt, theme, "surface", source, transform.surface_role, accent) }
	if transform.text_mix > 0 { style_inspector_token_role(sb, rt, theme, "text", source, transform.text_role, accent) }
	if transform.border_mix > 0 { style_inspector_token_role(sb, rt, theme, "border", source, transform.border_role, accent) }
}

style_inspector_surface_shape_name :: proc(kind: Surface_Shape_Kind) -> string {
	switch kind {
	case .Rectangle: return "rectangle"
	case .Rounded_Rectangle: return "rounded-rectangle"
	case .Line: return "line"
	}
	return "unknown"
}

style_inspector_material_kind_name :: proc(kind: Style_Material_Kind) -> string {
	switch kind {
	case .Flat: return "flat"
	case .Analytic_Relief: return "analytic-relief"
	}
	return "unknown"
}

style_inspector_surface_role :: proc(sb: ^strings.Builder, rt: ^Runtime, theme: Style_Theme_ID, role: Semantic_Surface_Color_Role) {
	switch value in role {
	case Style_Color_Role:
		fmt.sbprintf(sb, "role=core.%v", value)
		if token := style_theme_color_token(rt, theme, value); token != 0 {
			fmt.sbprintf(sb, " token=%d", u32(token))
		}
	case Style_Extension_Color_Role_ID:
		name, named := style_extension_color_role_name(rt, theme, value)
		if named { fmt.sbprintf(sb, "role=%s", name) } else { fmt.sbprintf(sb, "role=extension.%d", u64(value)) }
		if token, found := style_extension_color_token(rt, theme, value); found {
			fmt.sbprintf(sb, " token=%d", u32(token))
			style_inspector_color_token_chain(sb, rt, theme, token)
		}
	}
}

style_inspector_text_field_provenance :: proc(sb: ^strings.Builder, rt: ^Runtime, node: ^Node) {
	if rt == nil || node == nil { return }
	environment := node.style_environment
	recipe := style_text_field_recipe(rt, environment)
	state := Text_Field_Visual_State{hovered=node.hovered, focused=rt.focused == node.id}
	_ = style_text_field_resolve_retained(rt, node, state)
	computed, cached := rt.computed_styles[node.id]
	if !cached { return }
	fmt.sbprintf(sb, "  text field style: recipe=text_field.default resolution=retained-cache state=(hovered=%t focused=%t) dependencies=paint generations=(paint=%d)\n",
		state.hovered, state.focused, computed.generations.paint)
	fmt.sbprintf(sb, "  token provenance: text_field.default")
	style_inspector_token_role(sb, rt, environment.theme, "surface", "base", recipe.surface_role, environment.accent)
	style_inspector_token_role(sb, rt, environment.theme, "text", "base", recipe.text_role, environment.accent)
	style_inspector_token_role(sb, rt, environment.theme, "border", "base", recipe.border_role, environment.accent)
	style_inspector_token_role(sb, rt, environment.theme, "focus-border", "focused", recipe.focused_border_role, environment.accent)
	style_inspector_token_role(sb, rt, environment.theme, "focus", "overlay", recipe.focus_role, environment.accent)
	style_inspector_token_role(sb, rt, environment.theme, "selection", "base", recipe.selection_role, environment.accent)
	style_inspector_token_role(sb, rt, environment.theme, "caret", "base", recipe.caret_role, environment.accent)
	if state.hovered { style_inspector_control_transform_provenance(sb, rt, environment.theme, "hovered", recipe.hovered, environment.accent) }
	fmt.sbprintln(sb)
}

style_inspector_scrollbar_provenance :: proc(sb: ^strings.Builder, rt: ^Runtime, node: ^Node) {
	if rt == nil || node == nil { return }
	environment := node.style_environment
	recipe := style_scrollbar_recipe(rt, environment)
	state := Scrollbar_Visual_State{hovered=node.hovered, pressed=rt.scrollbar_drag_node == node.id}
	_ = style_scrollbar_resolve_retained(rt, node, state)
	computed, cached := rt.computed_styles[node.id]
	if !cached { return }
	fmt.sbprintf(sb, "  scrollbar style: recipe=scrollbar.default resolution=retained-cache state=(hovered=%t pressed=%t) dependencies=paint generations=(paint=%d)\n",
		state.hovered, state.pressed, computed.generations.paint)
	fmt.sbprintf(sb, "  token provenance: scrollbar.default")
	style_inspector_token_role(sb, rt, environment.theme, "track", "base", recipe.track_role, environment.accent)
	style_inspector_token_role(sb, rt, environment.theme, "thumb", "base", recipe.thumb_role, environment.accent)
	style_inspector_token_role(sb, rt, environment.theme, "corner", "base", recipe.corner_role, environment.accent)
	if state.hovered { style_inspector_token_role(sb, rt, environment.theme, "thumb", "hovered", recipe.hovered_thumb.role, environment.accent) }
	if state.pressed { style_inspector_token_role(sb, rt, environment.theme, "thumb", "pressed", recipe.pressed_thumb.role, environment.accent) }
	fmt.sbprintln(sb)
}

style_inspector_control_part_recipe :: proc(
	sb: ^strings.Builder,
	rt: ^Runtime,
	theme: Style_Theme_ID,
	name: string,
	recipe: Control_Part_Recipe,
	state: Control_Visual_State,
	accent: Style_Accent,
) {
	fmt.sbprintf(sb, "\n  %s", name)
	style_inspector_token_role(sb, rt, theme, "surface", "base", recipe.surface_role, accent)
	style_inspector_token_role(sb, rt, theme, "text", "base", recipe.text_role, accent)
	style_inspector_token_role(sb, rt, theme, "border", "base", recipe.border_role, accent)
	if state.selected { style_inspector_control_transform_provenance(sb, rt, theme, "selected", recipe.selected, accent) }
	if state.hovered { style_inspector_control_transform_provenance(sb, rt, theme, "hovered", recipe.hovered, accent) }
	if state.pressed { style_inspector_control_transform_provenance(sb, rt, theme, "pressed", recipe.pressed, accent) }
	if state.disabled { style_inspector_control_transform_provenance(sb, rt, theme, "disabled", recipe.disabled, accent) }
}

style_inspector_checkbox_provenance :: proc(sb: ^strings.Builder, rt: ^Runtime, node: ^Node) {
	if rt == nil || node == nil { return }
	environment := node.style_environment
	state := Checkbox_Visual_State{
		checked=node.paint_value&1 != 0,
		hovered=node.hovered,
		pressed=node.pressed,
		disabled=node.disabled,
		focused=rt.focused == node.id,
	}
	recipe := style_checkbox_recipe(rt, environment)
	resolved := style_checkbox_resolve_retained(rt, node, state)
	computed, cached := rt.computed_styles[node.id]
	if !cached { return }
	fmt.sbprintf(sb, "  checkbox style: recipe=checkbox.default resolution=retained-cache state=(checked=%t hovered=%t pressed=%t disabled=%t focused=%t) applied=",
		state.checked, state.hovered, state.pressed, state.disabled, state.focused)
	first := true
	for transform in Style_Control_State {
		if transform not_in resolved.applied_transforms { continue }
		if !first { fmt.sbprintf(sb, ",") }
		fmt.sbprintf(sb, "%s", style_control_state_name(transform))
		first = false
	}
	fmt.sbprintf(sb, " focus-mode=%s dependencies=paint generations=(paint=%d)\n  token provenance: checkbox.default",
		focus_indicator_mode_name(resolved.focus_indicator_mode), computed.generations.paint)
	style_inspector_control_part_recipe(sb, rt, environment.theme, "box", recipe.box,
		Control_Visual_State{selected=state.checked, hovered=state.hovered, pressed=state.pressed, disabled=state.disabled}, environment.accent)
	style_inspector_control_part_recipe(sb, rt, environment.theme, "checkmark", recipe.checkmark,
		Control_Visual_State{selected=state.checked, hovered=state.hovered, pressed=state.pressed, disabled=state.disabled}, environment.accent)
	style_inspector_control_part_recipe(sb, rt, environment.theme, "label", recipe.label,
		Control_Visual_State{selected=state.checked, hovered=state.hovered, pressed=state.pressed, disabled=state.disabled}, environment.accent)
	style_inspector_token_role(sb, rt, environment.theme, "focus", "overlay", recipe.focus_role, environment.accent)
	fmt.sbprintln(sb)
}

style_inspector_slider_provenance :: proc(sb: ^strings.Builder, rt: ^Runtime, node: ^Node) {
	if rt == nil || node == nil { return }
	environment := node.style_environment
	state := Slider_Visual_State{
		hovered=node.hovered,
		pressed=node.pressed,
		disabled=node.disabled,
		focused=rt.focused == node.id,
	}
	resolved := style_slider_resolve_retained(rt, node, state)
	computed, cached := rt.computed_styles[node.id]
	if !cached { return }
	fmt.sbprintf(sb, "  slider style: recipe=slider.default resolution=retained-cache state=(hovered=%t pressed=%t disabled=%t focused=%t) applied=",
		state.hovered, state.pressed, state.disabled, state.focused)
	first := true
	for transform in Style_Control_State {
		if transform not_in resolved.applied_transforms { continue }
		if !first { fmt.sbprintf(sb, ",") }
		fmt.sbprintf(sb, "%s", style_control_state_name(transform))
		first = false
	}
	fmt.sbprintf(sb, " focus-mode=%s dependencies=paint generations=(paint=%d)\n  token provenance: slider.default",
		focus_indicator_mode_name(resolved.focus_indicator_mode), computed.generations.paint)
	recipe := style_slider_recipe(rt, environment)
	part_state := Control_Visual_State{hovered=state.hovered, pressed=state.pressed, disabled=state.disabled}
	style_inspector_control_part_recipe(sb, rt, environment.theme, "track", recipe.track, part_state, environment.accent)
	style_inspector_control_part_recipe(sb, rt, environment.theme, "fill", recipe.fill, part_state, environment.accent)
	style_inspector_control_part_recipe(sb, rt, environment.theme, "thumb", recipe.thumb, part_state, environment.accent)
	style_inspector_control_part_recipe(sb, rt, environment.theme, "label", recipe.label, part_state, environment.accent)
	style_inspector_token_role(sb, rt, environment.theme, "focus", "overlay", recipe.focus_role, environment.accent)
	fmt.sbprintln(sb)
}

style_inspector_semantic_surface :: proc(sb: ^strings.Builder, rt: ^Runtime, node: ^Node, style: Semantic_Surface_Style) {
	if rt == nil || node == nil || !style.defined { return }
	resolved := style_semantic_surface_resolve_retained(rt, node, style)
	computed, cached := rt.computed_styles[node.id]
	if !cached { return }
	fmt.sbprintf(sb, "  semantic surface: ")
	style_inspector_surface_role(sb, rt, node.style_environment.theme, style.role)
	material, material_found := style_material_resolve(rt, style.material)
	material_kind := "unavailable"
	if material_found { material_kind = style_inspector_material_kind_name(material.kind) }
	fmt.sbprintf(sb, " shape=%s radius=%.2f material=%d(%s) height=%.2f group=%d fill=(%.3f,%.3f,%.3f,%.3f) resolution=retained-cache dependencies=paint,material generations=(paint=%d material=%d)\n",
		style_inspector_surface_shape_name(style.shape.kind), style.shape.corner_radius,
		u32(style.material), material_kind, style.physical_height, u32(style.material_group),
		resolved.fill.r, resolved.fill.g, resolved.fill.b, resolved.fill.a,
		computed.generations.paint, computed.generations.material)
}

inspect :: proc(rt: ^Runtime) -> string {
	previous_suppression := false
	if rt != nil {
		previous_suppression = rt.style_stats_suppressed
		rt.style_stats_suppressed = true
	}
	defer {
		if rt != nil { rt.style_stats_suppressed = previous_suppression }
	}
	sb := strings.builder_make()
	fmt.sbprintln(&sb, "Alicorn inspector")
	fmt.sbprintf(&sb, "keyboard focus: %d selected node: %d captured: %d\n", rt.focused, rt.selected, rt.captured_node)
	if semantic_id_is_valid(rt.semantic_focus.id) {
		fmt.sbprintf(&sb, "semantic focus: namespace=%d value=%d owner=%d realized=%d\n",
			rt.semantic_focus.id.namespace, rt.semantic_focus.id.value,
			rt.semantic_focus.owner, rt.semantic_focus.realized_node)
	} else {
		fmt.sbprintln(&sb, "semantic focus: none")
	}
	fmt.sbprintf(&sb, "retained nodes: %d\n", len(rt.nodes))
	queued_semantic_requests := max(len(rt.semantic_requests)-rt.semantic_request_read_index, 0)
	fmt.sbprintf(&sb,
		"semantics: revision=%d entities=%d latest=(%d>%d +%d -%d) requests=%d work=(described=%d resolved=%d structure=%d properties=%d focus-search=%d active-update=%d)\n",
		rt.semantic_revision, len(rt.semantic_entities), rt.semantic_last_from_revision, rt.semantic_last_to_revision,
		len(rt.semantic_last_changed), len(rt.semantic_last_removed), queued_semantic_requests,
		rt.stats.semantic_descriptions_emitted, rt.stats.semantic_entities_resolved,
		rt.stats.semantic_structure_changes, rt.stats.semantic_property_changes,
		rt.stats.semantic_focus_search_visits, rt.stats.semantic_active_update_visits)
	fmt.sbprintf(&sb, "last invalidation: %s\n", rt.last_invalidation_reason)
	fmt.sbprintf(&sb, "frame: %d built=%d idle=%d regions-skipped=%d subtrees-reused=%d adjacency-rebuilds=%d surface-updates=%d geometry-updates=%d surface-clears=%d stale-surface-updates=%d geometry-overflow-rejections=%d surface-pending=%t presentation=%d submitted=%d\n", rt.stats.frame, rt.stats.frames_built, rt.stats.idle_frames, rt.stats.regions_skipped, rt.stats.retained_subtrees_reused, rt.stats.adjacency_rebuilds, rt.stats.surface_updates, rt.stats.surface_geometry_updates, rt.stats.surface_clear_count, rt.stats.surface_stale_update_rejections, rt.stats.surface_geometry_overflow_rejections, rt.surface_frame_pending, rt.presentation_revision, rt.submitted_revision)
	fmt.sbprintf(&sb, "work: reconcile=%d measure=%d measure_hits=%d measure_misses=%d text_shapes=%d layout=%d paint=%d compose=%d style_resolutions=%d style_cache_hits=%d created=%d retired=%d\n", rt.stats.reconcile_nodes_visited, rt.stats.measure_requests, rt.stats.measure_cache_hits, rt.stats.measure_cache_misses, rt.stats.text_shape_requests, rt.stats.layout_nodes_visited, rt.stats.paint_nodes_visited, rt.stats.composition_nodes_visited, rt.stats.style_resolutions, rt.stats.style_cache_hits, rt.stats.nodes_created, rt.stats.nodes_retired)
	fmt.sbprintln(&sb, "actions:")
	for entry in rt.actions {
		fmt.sbprintf(&sb, "  %s · %s (id=%d enabled=%t checked=%t)\n", entry.descriptor.name, entry.descriptor.label, u32(entry.descriptor.id), entry.state.enabled, entry.state.checked)
	}
	fmt.sbprintln(&sb, "recent trace:")
	trace := trace_snapshot(rt)
	defer delete(trace)
	trace_start := max(0, len(trace)-12)
	for event in trace[trace_start:] {
		if event.cause_id == 0 {
			fmt.sbprintf(&sb, "  #%d %v cause=none node=%d %s\n", event.sequence, event.kind, event.node, event.reason)
		} else {
			if event.action_id != Action_ID(0) {
				descriptor, state, found := action_lookup(rt, event.action_id)
				if found {
					fmt.sbprintf(&sb, "  #%d %v cause=#%d origin=%v action=%s · %s (id=%d enabled=%t checked=%t) node=%d %s\n", event.sequence, event.kind, event.cause_id, event.cause_kind, descriptor.name, descriptor.label, u32(event.action_id), state.enabled, state.checked, event.node, event.reason)
				} else {
					fmt.sbprintf(&sb, "  #%d %v cause=#%d origin=%v action=%d node=%d %s\n", event.sequence, event.kind, event.cause_id, event.cause_kind, u32(event.action_id), event.node, event.reason)
				}
			} else {
				fmt.sbprintf(&sb, "  #%d %v cause=#%d origin=%v node=%d %s\n", event.sequence, event.kind, event.cause_id, event.cause_kind, event.node, event.reason)
			}
		}
	}
	for id in rt.order {
		node, ok := rt.nodes[id]
		if !ok { continue }
		if node.identity_key_kind == 3 {
			fmt.sbprintf(&sb, "Node: %d parent=%d kind=%v source=%s:%d:%d component=%s key=%q scope_pair=(%d,%d) bounds=(%.1f,%.1f %.1fx%.1f)\n", node.id, node.parent, node.kind, node.site.file, node.site.line, node.site.column, node.site.component, node.key, node.identity_key_pair.first, node.identity_key_pair.second, node.bounds.x, node.bounds.y, node.bounds.w, node.bounds.h)
		} else if node.identity_key_numeric {
			fmt.sbprintf(&sb, "Node: %d parent=%d kind=%v source=%s:%d:%d component=%s key=%q scope_u64=%d bounds=(%.1f,%.1f %.1fx%.1f)\n", node.id, node.parent, node.kind, node.site.file, node.site.line, node.site.column, node.site.component, node.key, node.identity_key_u64, node.bounds.x, node.bounds.y, node.bounds.w, node.bounds.h)
		} else {
			fmt.sbprintf(&sb, "Node: %d parent=%d kind=%v source=%s:%d:%d component=%s key=%q scope=%q bounds=(%.1f,%.1f %.1fx%.1f)\n", node.id, node.parent, node.kind, node.site.file, node.site.line, node.site.column, node.site.component, node.key, node.identity_key, node.bounds.x, node.bounds.y, node.bounds.w, node.bounds.h)
		}
		fmt.sbprintf(&sb, "  description: %s layout: %s paint: %s composite: %s\n", stage_word(dirty_has(node.dirty, .Description)), stage_word(dirty_has(node.dirty, .Layout)), stage_word(dirty_has(node.dirty, .Paint)), stage_word(dirty_has(node.dirty, .Composite)))
		appearance := node.style_environment.accessibility
		fmt.sbprintf(&sb,
			"  style environment: text-scale=%.2f accessibility-appearance=(increased-contrast=%t reduce-motion=%t reduce-transparency=%t differentiate-without-color=%t)\n",
			node.style_environment.text_scale, appearance.increased_contrast, appearance.reduce_motion,
			appearance.reduce_transparency, appearance.differentiate_without_color)
		if node.region {
			fmt.sbprintf(&sb, "  region: revision=%d cached=%t\n", node.region_revision, node.region_cached)
		}
		if node.kind == .Custom_Surface {
			fmt.sbprintf(&sb, "  surface: payload-revision=%d interaction=%v kind=%v samples=%d segments=%d circles=%d pixels=%dx%d dpi=%.2f clip=(%.1f,%.1f %.1fx%.1f)\n", u64(node.surface_payload_revision), node.surface_interaction, node.surface_geometry_active ? GPU_Surface_Kind.Geometry : GPU_Surface_Kind.Waveform, len(node.surface_samples), len(node.surface_segments), len(node.surface_circles), node.surface_pixel_width, node.surface_pixel_height, node.surface_dpi_scale, node.clip.x, node.clip.y, node.clip.w, node.clip.h)
		}
		if semantic_style, has_semantic_style := rt.semantic_surfaces[id]; has_semantic_style {
			style_inspector_semantic_surface(&sb, rt, node, semantic_style)
		}
		fmt.sbprintf(&sb, "  selected=%t semantic_active=%t hovered=%t pressed=%t caret=(%d,%v) selection=(%d,%v)->(%d,%v) reason: %s\n", node.selected, node.semantic_active, node.hovered, node.pressed, node.caret.byte, node.caret.affinity, node.selection_anchor.byte, node.selection_anchor.affinity, node.selection_focus.byte, node.selection_focus.affinity, node.last_reason)
		if node.kind == .Button {
			recipe := style_button_recipe(rt, node.style_environment, node.button_variant)
			hovered := visual_part_owner_hovered(rt, node.id)
			fmt.sbprintf(&sb, "  button/tab state: selected=%t hovered=%t pressed=%t disabled=%t focused=%t\n",
				node.selected, hovered, node.pressed, node.disabled, rt.focused == node.id)
			resolved := style_button_resolve_retained(rt, node, Button_Visual_State{
				selected=node.selected,
				hovered=hovered,
				pressed=node.pressed,
				disabled=node.disabled,
			}, node.drop_position == .On)
			computed_style := rt.computed_styles[node.id]
			if node.button_variant == .Tab {
				fmt.sbprintf(&sb, "  tab identity: label=%q recipe=tab.document variant=button.tab\n", visual_part_owner_label(rt, node.id))
			} else {
				fmt.sbprintf(&sb, "  button identity: label=%q\n", node.label)
			}
			fmt.sbprintf(&sb, "  button recipe: variant=%s recipe=button.%s base=(%v,%v) surface=(%.3f,%.3f,%.3f,%.3f) text=(%.3f,%.3f,%.3f,%.3f) indicator=%v/%v\n",
				button_variant_name(node.button_variant), button_variant_name(node.button_variant), recipe.surface_role, recipe.text_role,
				resolved.surface.r, resolved.surface.g, resolved.surface.b, resolved.surface.a,
				resolved.text.r, resolved.text.g, resolved.text.b, resolved.text.a,
				resolved.selected_indicator, recipe.selected_indicator_role)
			fmt.sbprintf(&sb, "  applied transforms:")
			for style_state in Style_Control_State {
				if style_state in resolved.applied_transforms { fmt.sbprintf(&sb, " %s", style_control_state_name(style_state)) }
			}
			fmt.sbprintf(&sb, " | focus-mode=%s\n", focus_indicator_mode_name(recipe.focus_indicator_mode))
			fmt.sbprintf(&sb, " | focus overlay=%v semantic-active overlay=%v\n", recipe.focus_role, recipe.semantic_active_role)
			fmt.sbprintf(&sb, "  computed style: dependencies=")
			first_domain := true
			for domain in Style_Domain {
				if domain not_in computed_style.dependencies { continue }
				if !first_domain { fmt.sbprintf(&sb, ",") }
				first_domain = false
				switch domain {
				case .Metrics: fmt.sbprintf(&sb, "metrics")
				case .Typography: fmt.sbprintf(&sb, "typography")
				case .Paint: fmt.sbprintf(&sb, "paint")
				case .Material: fmt.sbprintf(&sb, "material")
				}
			}
			fmt.sbprintf(&sb, " resolution=retained-cache generations=(metrics=%d typography=%d paint=%d material=%d)\n",
				computed_style.generations.metrics, computed_style.generations.typography,
				computed_style.generations.paint, computed_style.generations.material)
			provenance := computed_style.provenance
			provenance_variant := Button_Variant(provenance.variant)
			provenance_state := style_button_state_from_bits(provenance.state_bits)
			fmt.sbprintf(&sb, "  token provenance: button.%s", button_variant_name(provenance_variant))
			style_inspector_token_role(&sb, rt, provenance.theme, "surface", "base", recipe.surface_role, provenance.accent)
			style_inspector_token_role(&sb, rt, provenance.theme, "text", "base", recipe.text_role, provenance.accent)
			style_inspector_token_role(&sb, rt, provenance.theme, "focus", "base", recipe.focus_role, provenance.accent)
			style_inspector_token_role(&sb, rt, provenance.theme, "semantic-active", "base", recipe.semantic_active_role, provenance.accent)
			style_inspector_token_role(&sb, rt, provenance.theme, "indicator", "base", recipe.selected_indicator_role, provenance.accent)
			if provenance_state.selected { style_inspector_transform_provenance(&sb, rt, provenance.theme, "selected", recipe.selected, provenance.accent) }
			if provenance_state.hovered { style_inspector_transform_provenance(&sb, rt, provenance.theme, "hovered", recipe.hovered, provenance.accent) }
			if provenance_state.pressed { style_inspector_transform_provenance(&sb, rt, provenance.theme, "pressed", recipe.pressed, provenance.accent) }
			if provenance_state.disabled { style_inspector_transform_provenance(&sb, rt, provenance.theme, "disabled", recipe.disabled, provenance.accent) }
			if provenance.drop_target_on && !provenance_state.disabled {
				style_inspector_token_role(&sb, rt, provenance.theme, "surface", "drop-target", .Success, provenance.accent)
			}
			fmt.sbprintf(&sb, "\n")
		}
		if node.kind == .Checkbox { style_inspector_checkbox_provenance(&sb, rt, node) }
		if node.kind == .Slider { style_inspector_slider_provenance(&sb, rt, node) }
		if node.kind == .Text_Field {
			style_inspector_text_field_provenance(&sb, rt, node)
		}
		if node.kind == .Scroll_Region {
			style_inspector_scrollbar_provenance(&sb, rt, node)
		}
		if node.composition.active {
			fmt.sbprintf(&sb, "  composition: active text-bytes=%d selection=(%d,%d) replaces=(%d,%v)->(%d,%v)\n", len(node.composition.text), node.composition.selection_start, node.composition.selection_end, node.composition.replace_anchor.byte, node.composition.replace_anchor.affinity, node.composition.replace_focus.byte, node.composition.replace_focus.affinity)
		}
	}
	if rt.hard_error {
		fmt.sbprintf(&sb, "HARD ERROR: %s\n", rt.diagnostic)
	}
	return strings.to_string(sb)
}

trace_snapshot :: proc(rt: ^Runtime) -> []Trace_Event {
	result := make([]Trace_Event, rt.trace.count)
	start := (rt.trace.next - rt.trace.count + len(rt.trace.events)) % len(rt.trace.events)
	for i := 0; i < rt.trace.count; i += 1 {
		result[i] = rt.trace.events[(start+i)%len(rt.trace.events)]
	}
	return result
}
