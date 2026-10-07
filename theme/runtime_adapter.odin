package theme

import alicorn "../runtime"

// Theme_Builtin_Base_Source owns only the two model slices it creates; names
// and spans point at static identifiers. Runtime startup continues to use
// Alicorn's typed DEFAULT_STYLE_THEME and never invokes a parser.
Theme_Builtin_Base_Source :: struct {
	model: Theme_Source_Model,
	tokens: []Token_Definition,
	core_roles: []Core_Role_Binding,
}

THEME_BUILTIN_BASE_TOKEN_NAMES: [CORE_COLOR_ROLE_COUNT]string = {
	"alicorn.color.window_background",
	"alicorn.color.surface",
	"alicorn.color.subtle_surface",
	"alicorn.color.editor_background",
	"alicorn.color.text",
	"alicorn.color.muted_text",
	"alicorn.color.accent",
	"alicorn.color.accent_hover",
	"alicorn.color.accent_pressed",
	"alicorn.color.accent_text",
	"alicorn.color.selection",
	"alicorn.color.focus",
	"alicorn.color.semantic_focus",
	"alicorn.color.border",
	"alicorn.color.danger",
	"alicorn.color.success",
	"alicorn.color.scrollbar_track",
	"alicorn.color.scrollbar_thumb",
}

// theme_builtin_base_source_create projects the typed built-in palette into
// compiler input so tools can resolve aliases against alicorn.base without
// reading a file or duplicating default color values.
theme_builtin_base_source_create :: proc(allocator := context.allocator) -> Theme_Builtin_Base_Source {
	owner := Theme_Builtin_Base_Source{
		tokens=make([]Token_Definition, CORE_COLOR_ROLE_COUNT, allocator),
		core_roles=make([]Core_Role_Binding, CORE_COLOR_ROLE_COUNT, allocator),
	}
	default_theme := alicorn.DEFAULT_STYLE_THEME
	span := Source_Span{path="alicorn.base", start_offset=0, end_offset=0, line=1, column=1}
	for role in Core_Color_Role {
		if role == .Count { continue }
		runtime_role, mapped := theme_runtime_adapter_core_role(role)
		if !mapped {
			theme_builtin_base_source_destroy(&owner, allocator)
			return {}
		}
		index := int(role)
		name := THEME_BUILTIN_BASE_TOKEN_NAMES[index]
		color := default_theme.colors[int(runtime_role)]
		owner.tokens[index] = Token_Definition{
			name=name,
			kind=.Color,
			value=Theme_Color{color.r, color.g, color.b, color.a},
			span=span,
		}
		owner.core_roles[index] = Core_Role_Binding{role=role, token=name, span=span}
	}
	owner.model = Theme_Source_Model{
		metadata=Theme_Source_Metadata{
			schema_version=THEME_SOURCE_SCHEMA_VERSION,
			contract=THEME_CONTRACT_VERSION,
			span=span,
		},
		tokens=owner.tokens,
		core_roles=owner.core_roles,
	}
	return owner
}

theme_builtin_base_source_destroy :: proc(owner: ^Theme_Builtin_Base_Source, allocator := context.allocator) {
	if owner == nil { return }
	delete(owner.tokens, allocator)
	delete(owner.core_roles, allocator)
	owner^ = Theme_Builtin_Base_Source{}
}

// theme_runtime_style_theme creates an unregistered runtime snapshot from a
// successful compiler output. The returned token and binding slices are owned
// by the caller and are independent of output; style_theme_register makes its
// own retained copy, after which this value may be destroyed with
// theme_runtime_style_theme_destroy.
//
// Extension role IDs use the same stable namespaced hash contract in the
// compiler and runtime, so the typed IDs are copied numerically. Authored
// names and alias edges are copied as small optional inspector metadata;
// source spans and parser structures remain compiler-only.
theme_runtime_style_theme :: proc(
	output: Theme_Compile_Output,
	allocator := context.allocator,
) -> (result: alicorn.Style_Theme, ok: bool) {
	if !output.ok { return }
	compiled := output.theme
	if !theme_runtime_adapter_compiled_is_valid(compiled) { return }

	result = alicorn.DEFAULT_STYLE_THEME

	color_roles := make([dynamic]alicorn.Style_Extension_Color_Role_Binding, 0, allocator=allocator)
	defer delete(color_roles)
	length_roles := make([dynamic]alicorn.Style_Extension_Length_Role_Binding, 0, allocator=allocator)
	defer delete(length_roles)

	for binding in compiled.extension_color_roles {
		if u64(binding.id) == 0 || u32(binding.token) == 0 || int(u32(binding.token)) > len(compiled.colors) { return }
		role_id := alicorn.Style_Extension_Color_Role_ID(u64(binding.id))
		if role_id == 0 || theme_runtime_adapter_color_role_exists(color_roles[:], role_id) { return }
		append(&color_roles, alicorn.Style_Extension_Color_Role_Binding{
			role=role_id,
			token=alicorn.Style_Color_Token_ID(u32(binding.token)),
		})
	}
	for binding in compiled.extension_length_roles {
		if u64(binding.id) == 0 || u32(binding.token) == 0 || int(u32(binding.token)) > len(compiled.lengths) { return }
		role_id := alicorn.Style_Extension_Length_Role_ID(u64(binding.id))
		if role_id == 0 || theme_runtime_adapter_length_role_exists(length_roles[:], role_id) { return }
		append(&length_roles, alicorn.Style_Extension_Length_Role_Binding{
			role=role_id,
			token=alicorn.Style_Length_Token_ID(u32(binding.token)),
		})
	}

	result.color_tokens = make([]alicorn.Color, len(compiled.colors), allocator)
	for color, index in compiled.colors {
		result.color_tokens[index] = alicorn.Color{color.r, color.g, color.b, color.a}
	}
	result.length_tokens = make([]alicorn.Style_Length, len(compiled.lengths), allocator)
	for length, index in compiled.lengths {
		result.length_tokens[index] = alicorn.Style_Length{logical_units=f32(length)}
	}

	for compiler_role in Core_Color_Role {
		if compiler_role == .Count { continue }
		runtime_role, mapped := theme_runtime_adapter_core_role(compiler_role)
		if !mapped { return }
		token := compiled.core_color_roles[int(compiler_role)]
		if token == 0 { continue }
		color_index := int(u32(token)) - 1
		if color_index < 0 || color_index >= len(result.color_tokens) { return }
		result.core_color_tokens[int(runtime_role)] = alicorn.Style_Color_Token_ID(u32(token))
		// Keep the legacy direct value in sync for consumers that inspect the
		// role table directly; Alicorn resolves the typed token first.
		result.colors[int(runtime_role)] = result.color_tokens[color_index]
	}
	for override in compiled.button_recipes {
		variant, variant_ok := theme_runtime_adapter_button_variant(override.variant)
		if !variant_ok { return }
		recipe := &result.button_recipes.recipes[int(variant)]
		if override.has_surface_role {
			role, ok := theme_runtime_adapter_core_role(override.surface_role)
			if !ok { return }
			recipe.surface_role = role
		}
		if override.has_text_role {
			role, ok := theme_runtime_adapter_core_role(override.text_role)
			if !ok { return }
			recipe.text_role = role
		}
		if override.has_surface_visible { recipe.surface_visible = override.surface_visible }
		if override.has_selected_indicator {
			if override.selected_indicator { recipe.selected_indicator = .Underline } else { recipe.selected_indicator = .None }
		}
		if override.has_selected_indicator_role {
			role, ok := theme_runtime_adapter_core_role(override.selected_indicator_role)
			if !ok { return }
			recipe.selected_indicator_role = role
		}
		if override.has_focus_indicator_keyboard {
			if override.focus_indicator_keyboard_only { recipe.focus_indicator_mode = .Keyboard_Only } else { recipe.focus_indicator_mode = .Always }
		}
		if override.has_focus_role {
			role, ok := theme_runtime_adapter_core_role(override.focus_role)
			if !ok { return }
			recipe.focus_role = role
		}
		if override.has_semantic_active_role {
			role, ok := theme_runtime_adapter_core_role(override.semantic_active_role)
			if !ok { return }
			recipe.semantic_active_role = role
		}
		for state in Theme_Button_State {
			if state == .Count { continue }
			from := override.states[int(state)]
			transform := theme_runtime_adapter_button_transform(recipe, state)
			if from.has_surface_role {
				role, ok := theme_runtime_adapter_core_role(from.surface_role)
				if !ok { return }
				transform.surface_role = role
			}
			if from.has_surface_mix { transform.surface_mix = from.surface_mix }
			if from.has_text_role {
				role, ok := theme_runtime_adapter_core_role(from.text_role)
				if !ok { return }
				transform.text_role = role
			}
			if from.has_text_mix { transform.text_mix = from.text_mix }
			theme_runtime_adapter_button_transform_set(recipe, state, transform)
		}
	}

	if len(color_roles) > 0 {
		result.extension_color_roles = make([]alicorn.Style_Extension_Color_Role_Binding, len(color_roles), allocator)
		copy(result.extension_color_roles, color_roles[:])
	}
	if len(length_roles) > 0 {
		result.extension_length_roles = make([]alicorn.Style_Extension_Length_Role_Binding, len(length_roles), allocator)
		copy(result.extension_length_roles, length_roles[:])
	}

	if len(output.debug.tokens) == len(compiled.colors)+len(compiled.lengths) {
		color_metadata := make([]alicorn.Style_Token_Provenance, len(compiled.colors), allocator)
		length_metadata := make([]alicorn.Style_Token_Provenance, len(compiled.lengths), allocator)
		color_seen := make([]bool, len(compiled.colors), allocator)
		length_seen := make([]bool, len(compiled.lengths), allocator)
		valid_metadata := true
		for source in output.debug.tokens {
			if source.id == 0 || source.name == "" { valid_metadata = false; break }
			index := int(source.id)-1
			if source.kind == .Color {
				if index < 0 || index >= len(color_metadata) || color_seen[index] { valid_metadata = false; break }
				color_seen[index] = true
				color_metadata[index] = alicorn.Style_Token_Provenance{
					id=source.id,
					name=theme_clone_string(source.name, allocator),
					alias_target=theme_clone_string(source.alias_target, allocator),
				}
			} else {
				if index < 0 || index >= len(length_metadata) || length_seen[index] { valid_metadata = false; break }
				length_seen[index] = true
				length_metadata[index] = alicorn.Style_Token_Provenance{
					id=source.id,
					name=theme_clone_string(source.name, allocator),
					alias_target=theme_clone_string(source.alias_target, allocator),
				}
			}
		}
		for seen in color_seen { valid_metadata = valid_metadata && seen }
		for seen in length_seen { valid_metadata = valid_metadata && seen }
		delete(color_seen, allocator)
		delete(length_seen, allocator)
		if valid_metadata {
			result.color_token_provenance = color_metadata
			result.length_token_provenance = length_metadata
		} else {
			for value in color_metadata { delete(value.name, allocator); delete(value.alias_target, allocator) }
			for value in length_metadata { delete(value.name, allocator); delete(value.alias_target, allocator) }
			delete(color_metadata, allocator)
			delete(length_metadata, allocator)
		}
	}

	color_role_provenance_count := 0
	length_role_provenance_count := 0
	for source in output.debug.extension_roles {
		if source.color_id != 0 { color_role_provenance_count += 1 }
		if source.length_id != 0 { length_role_provenance_count += 1 }
	}
	if color_role_provenance_count > 0 {
		result.extension_color_role_provenance = make([]alicorn.Style_Extension_Color_Role_Provenance, color_role_provenance_count, allocator)
		index := 0
		for source in output.debug.extension_roles {
			if source.color_id == 0 { continue }
			result.extension_color_role_provenance[index] = alicorn.Style_Extension_Color_Role_Provenance{
				role=alicorn.Style_Extension_Color_Role_ID(u64(source.color_id)),
				name=theme_clone_string(source.name, allocator),
			}
			index += 1
		}
	}
	if length_role_provenance_count > 0 {
		result.extension_length_role_provenance = make([]alicorn.Style_Extension_Length_Role_Provenance, length_role_provenance_count, allocator)
		index := 0
		for source in output.debug.extension_roles {
			if source.length_id == 0 { continue }
			result.extension_length_role_provenance[index] = alicorn.Style_Extension_Length_Role_Provenance{
				role=alicorn.Style_Extension_Length_Role_ID(u64(source.length_id)),
				name=theme_clone_string(source.name, allocator),
			}
			index += 1
		}
	}
	return result, true
}

theme_runtime_style_materials :: proc(
	output: Theme_Compile_Output,
	allocator := context.allocator,
) -> (result: []alicorn.Style_Material_Definition, ok: bool) {
	if !output.ok || len(output.theme.materials) != len(output.debug.materials) { return }
	if len(output.theme.materials) == 0 { return nil, true }
	result = make([]alicorn.Style_Material_Definition, len(output.theme.materials), allocator)
	for material, index in output.theme.materials {
		if index >= len(output.debug.materials) { theme_runtime_style_materials_destroy(&result, allocator); return nil, false }
		kind: alicorn.Style_Material_Kind
		switch material.kind {
		case .Flat: kind = .Flat
		case .Analytic_Relief: kind = .Analytic_Relief
		case: theme_runtime_style_materials_destroy(&result, allocator); return nil, false
		}
		result[index] = alicorn.Style_Material_Definition{
			name=theme_clone_string(output.debug.materials[index].name, allocator),
			material=alicorn.Style_Material{
				kind=kind,
				bevel_width=material.bevel_width,
				bevel_strength=material.bevel_strength,
				inner_shadow_strength=material.inner_shadow_strength,
				outer_shadow_strength=material.outer_shadow_strength,
				outer_shadow_radius=material.outer_shadow_radius,
			},
		}
	}
	return result, true
}

theme_runtime_style_materials_destroy :: proc(
	materials: ^[]alicorn.Style_Material_Definition,
	allocator := context.allocator,
) {
	if materials == nil { return }
	for material in materials^ { delete(material.name, allocator) }
	delete(materials^, allocator)
	materials^ = nil
}

theme_runtime_adapter_button_variant :: proc(value: Theme_Button_Variant) -> (alicorn.Button_Variant, bool) {
	switch value {
	case .Default: return .Default, true
	case .Primary: return .Primary, true
	case .Toolbar: return .Toolbar, true
	case .Quiet: return .Quiet, true
	case .Tab: return .Tab, true
	case .Danger: return .Danger, true
	case .Count:
	}
	return .Default, false
}

theme_runtime_adapter_button_transform :: proc(
	recipe: ^alicorn.Button_Recipe,
	state: Theme_Button_State,
) -> alicorn.Style_Transform {
	switch state {
	case .Selected: return recipe.selected
	case .Hovered: return recipe.hovered
	case .Pressed: return recipe.pressed
	case .Disabled: return recipe.disabled
	case .Count:
	}
	return {}
}

theme_runtime_adapter_button_transform_set :: proc(
	recipe: ^alicorn.Button_Recipe,
	state: Theme_Button_State,
	transform: alicorn.Style_Transform,
) {
	switch state {
	case .Selected: recipe.selected = transform
	case .Hovered: recipe.hovered = transform
	case .Pressed: recipe.pressed = transform
	case .Disabled: recipe.disabled = transform
	case .Count:
	}
}

// Releases the caller-owned slices returned by theme_runtime_style_theme.
// Registered themes are separate immutable copies and are not affected.
theme_runtime_style_theme_destroy :: proc(
	theme: ^alicorn.Style_Theme,
	allocator := context.allocator,
) {
	if theme == nil { return }
	delete(theme.color_tokens, allocator)
	delete(theme.length_tokens, allocator)
	delete(theme.extension_color_roles, allocator)
	delete(theme.extension_length_roles, allocator)
	for provenance in theme.color_token_provenance {
		delete(provenance.name, allocator)
		delete(provenance.alias_target, allocator)
	}
	delete(theme.color_token_provenance, allocator)
	for provenance in theme.length_token_provenance {
		delete(provenance.name, allocator)
		delete(provenance.alias_target, allocator)
	}
	delete(theme.length_token_provenance, allocator)
	for provenance in theme.extension_color_role_provenance { delete(provenance.name, allocator) }
	delete(theme.extension_color_role_provenance, allocator)
	for provenance in theme.extension_length_role_provenance { delete(provenance.name, allocator) }
	delete(theme.extension_length_role_provenance, allocator)
	theme.color_tokens = nil
	theme.length_tokens = nil
	theme.extension_color_roles = nil
	theme.extension_length_roles = nil
	theme.color_token_provenance = nil
	theme.length_token_provenance = nil
	theme.extension_color_role_provenance = nil
	theme.extension_length_role_provenance = nil
}

theme_runtime_adapter_compiled_is_valid :: proc(compiled: Compiled_Theme) -> bool {
	for color in compiled.colors {
		if !theme_runtime_adapter_color_is_valid(color) { return false }
	}
	for length in compiled.lengths {
		value := f32(length)
		if !(value == value && value >= 0 && value <= 1_000_000) { return false }
	}
	for token in compiled.core_color_roles {
		if token != 0 && int(u32(token)) > len(compiled.colors) { return false }
	}
	return true
}

theme_runtime_adapter_color_is_valid :: proc(color: Theme_Color) -> bool {
	return color.r == color.r && color.g == color.g && color.b == color.b && color.a == color.a &&
	       color.r >= 0 && color.r <= 1 && color.g >= 0 && color.g <= 1 &&
	       color.b >= 0 && color.b <= 1 && color.a > 0 && color.a <= 1
}

theme_runtime_adapter_core_role :: proc(role: Core_Color_Role) -> (alicorn.Style_Color_Role, bool) {
	switch role {
	case .Window_Background: return .Window_Background, true
	case .Surface: return .Surface, true
	case .Subtle_Surface: return .Subtle_Surface, true
	case .Editor_Background: return .Editor_Background, true
	case .Text: return .Text, true
	case .Muted_Text: return .Muted_Text, true
	case .Accent: return .Accent, true
	case .Accent_Hover: return .Accent_Hover, true
	case .Accent_Pressed: return .Accent_Pressed, true
	case .Accent_Text: return .Accent_Text, true
	case .Selection: return .Selection, true
	case .Focus: return .Focus, true
	case .Semantic_Focus: return .Semantic_Focus, true
	case .Border: return .Border, true
	case .Danger: return .Danger, true
	case .Success: return .Success, true
	case .Scrollbar_Track: return .Scrollbar_Track, true
	case .Scrollbar_Thumb: return .Scrollbar_Thumb, true
	case .Count: return .Count, false
	}
	return .Count, false
}

theme_runtime_adapter_color_role_exists :: proc(
	bindings: []alicorn.Style_Extension_Color_Role_Binding,
	role: alicorn.Style_Extension_Color_Role_ID,
) -> bool {
	for binding in bindings { if binding.role == role { return true } }
	return false
}

theme_runtime_adapter_length_role_exists :: proc(
	bindings: []alicorn.Style_Extension_Length_Role_Binding,
	role: alicorn.Style_Extension_Length_Role_ID,
) -> bool {
	for binding in bindings { if binding.role == role { return true } }
	return false
}
