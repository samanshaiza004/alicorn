package alicorn

style_environment_changed_domains :: proc(previous, next: Style_Environment) -> Style_Domains {
	changed: Style_Domains = {}
	if previous.text_scale != next.text_scale { changed += {.Metrics, .Typography} }
	if previous.density != next.density { changed += {.Metrics} }
	if previous.theme != next.theme || previous.accent != next.accent { changed += {.Paint} }
	return changed
}

style_color_is_valid :: proc(color: Color) -> bool {
	return color.r == color.r && color.g == color.g && color.b == color.b && color.a == color.a &&
	       color.r >= 0 && color.r <= 1 && color.g >= 0 && color.g <= 1 &&
	       color.b >= 0 && color.b <= 1 && color.a > 0 && color.a <= 1
}

style_color_role_is_valid :: proc(role: Style_Color_Role) -> bool {
	return int(role) >= 0 && role < .Count
}

style_transform_is_valid :: proc(transform: Style_Transform) -> bool {
	return style_color_role_is_valid(transform.surface_role) &&
	       style_color_role_is_valid(transform.text_role) &&
	       transform.surface_mix == transform.surface_mix && transform.surface_mix >= 0 && transform.surface_mix <= 1 &&
	       transform.text_mix == transform.text_mix && transform.text_mix >= 0 && transform.text_mix <= 1
}

style_button_recipe_is_valid :: proc(recipe: Button_Recipe) -> bool {
	if !recipe.defined { return true }
	return style_color_role_is_valid(recipe.surface_role) &&
	       style_color_role_is_valid(recipe.text_role) &&
	       style_color_role_is_valid(recipe.selected_indicator_role) &&
	       style_color_role_is_valid(recipe.focus_role) &&
	       style_color_role_is_valid(recipe.semantic_active_role) &&
	       (recipe.selected_indicator == .None || recipe.selected_indicator == .Underline) &&
	       style_transform_is_valid(recipe.selected) &&
	       style_transform_is_valid(recipe.hovered) &&
	       style_transform_is_valid(recipe.pressed) &&
	       style_transform_is_valid(recipe.disabled)
}

style_theme_is_valid :: proc(theme: Style_Theme) -> bool {
	for color in theme.colors {
		if !style_color_is_valid(color) { return false }
	}
	for recipe in theme.button_recipes.recipes {
		if !style_button_recipe_is_valid(recipe) { return false }
	}
	return true
}

// style_accent packs an opaque accent into the compact value stored per node.
// Invalid or fully transparent values return zero, which means inherit.
style_accent :: proc(color: Color) -> Style_Accent {
	if !style_color_is_valid(color) { return 0 }
	r := u32(clamp(int(color.r*255+0.5), 0, 255))
	g := u32(clamp(int(color.g*255+0.5), 0, 255))
	b := u32(clamp(int(color.b*255+0.5), 0, 255))
	return Style_Accent(0xFF000000 | (r << 16) | (g << 8) | b)
}

style_accent_color :: proc(accent: Style_Accent) -> Color {
	packed := u32(accent)
	return Color{
		f32((packed >> 16) & 0xFF)/255,
		f32((packed >> 8) & 0xFF)/255,
		f32(packed & 0xFF)/255,
		1,
	}
}

// style_theme_register appends an immutable palette and returns a compact ID.
// IDs remain stable for the lifetime of this Runtime.
style_theme_register :: proc(rt: ^Runtime, theme: Style_Theme) -> Style_Theme_ID {
	if rt == nil || !style_theme_is_valid(theme) {
		if rt != nil { append_diagnostic(rt, "style theme contains invalid colors or button recipes") }
		return 0
	}
	append(&rt.style_themes, theme)
	return Style_Theme_ID(u32(len(rt.style_themes)))
}

style_theme_color :: proc(rt: ^Runtime, theme: Style_Theme_ID, role: Style_Color_Role) -> Color {
	default_theme := DEFAULT_STYLE_THEME
	if int(role) < 0 || role >= .Count { return default_theme.colors[int(Style_Color_Role.Text)] }
	index := u64(u32(theme))
	if rt != nil && index > 0 && index <= u64(len(rt.style_themes)) {
		return rt.style_themes[index-1].colors[int(role)]
	}
	return default_theme.colors[int(role)]
}

style_color :: proc(ui: ^UI, role: Style_Color_Role) -> Color {
	if ui == nil || ui.runtime == nil { return style_theme_color(nil, DEFAULT_STYLE_THEME_ID, role) }
	return style_environment_color(ui.runtime, ui.runtime.style_environment, role)
}

style_environment_color :: proc(rt: ^Runtime, environment: Style_Environment, role: Style_Color_Role) -> Color {
	if role == .Accent && environment.accent != 0 { return style_accent_color(environment.accent) }
	return style_theme_color(rt, environment.theme, role)
}

style_color_mix :: proc(from, to: Color, amount: f32) -> Color {
	mix := clamp(amount, 0, 1)
	if mix == 0 { return from }
	if mix == 1 { return to }
	return Color{
		from.r+(to.r-from.r)*mix,
		from.g+(to.g-from.g)*mix,
		from.b+(to.b-from.b)*mix,
		from.a+(to.a-from.a)*mix,
	}
}

style_button_recipe :: proc(rt: ^Runtime, environment: Style_Environment, variant: Button_Variant) -> Button_Recipe {
	index := int(variant)
	if index < 0 || index >= BUTTON_VARIANT_COUNT { index = int(Button_Variant.Default) }
	theme := DEFAULT_STYLE_THEME
	if rt != nil {
		id := u64(u32(environment.theme))
		if id > 0 && id <= u64(len(rt.style_themes)) { theme = rt.style_themes[id-1] }
	}
	recipe := theme.button_recipes.recipes[index]
	if !recipe.defined {
		fallbacks := DEFAULT_BUTTON_RECIPES
		recipe = fallbacks.recipes[index]
	}
	return recipe
}

style_button_variant_is_valid :: proc(variant: Button_Variant) -> bool {
	return int(variant) >= 0 && int(variant) < BUTTON_VARIANT_COUNT
}

style_button_variant_resolve :: proc(rt: ^Runtime, variant: Button_Variant) -> Button_Variant {
	if style_button_variant_is_valid(variant) { return variant }
	if rt != nil { append_diagnostic(rt, "button variant must be one of the declared Button_Variant values; using .Default") }
	return .Default
}

style_button_apply_transform :: proc(style: ^Button_Resolved_Style, transform: Style_Transform, rt: ^Runtime, environment: Style_Environment) {
	if transform.surface_mix > 0 {
		target := style_environment_color(rt, environment, transform.surface_role)
		style.surface = style_color_mix(style.surface, target, transform.surface_mix)
	}
	if transform.text_mix > 0 {
		target := style_environment_color(rt, environment, transform.text_role)
		style.text = style_color_mix(style.text, target, transform.text_mix)
	}
}

// style_button_resolve applies the recipe's independent transforms in this
// fixed order: selected, hovered, pressed, disabled. Focus and semantic-active
// are returned as separate overlays and never replace a state fill.
style_button_resolve :: proc(
	rt: ^Runtime,
	environment: Style_Environment,
	variant: Button_Variant,
	state: Button_Visual_State,
	drop_target_on := false,
) -> Button_Resolved_Style {
	recipe := style_button_recipe(rt, environment, variant)
	style := Button_Resolved_Style{
		surface=style_environment_color(rt, environment, recipe.surface_role),
		text=style_environment_color(rt, environment, recipe.text_role),
		focus=style_environment_color(rt, environment, recipe.focus_role),
		semantic_active=style_environment_color(rt, environment, recipe.semantic_active_role),
		selected_indicator=.None,
		selected_indicator_color=style_environment_color(rt, environment, recipe.selected_indicator_role),
	}
	if !recipe.surface_visible { style.surface.a = 0 }
	if state.selected {
		style.applied_transforms += {.Selected}
		style_button_apply_transform(&style, recipe.selected, rt, environment)
	}
	if state.hovered {
		style.applied_transforms += {.Hovered}
		style_button_apply_transform(&style, recipe.hovered, rt, environment)
	}
	if state.pressed {
		style.applied_transforms += {.Pressed}
		style_button_apply_transform(&style, recipe.pressed, rt, environment)
	}
	if state.disabled {
		style.applied_transforms += {.Disabled}
		style_button_apply_transform(&style, recipe.disabled, rt, environment)
	}
	if state.selected && !state.disabled { style.selected_indicator = recipe.selected_indicator }
	if drop_target_on && !state.disabled {
		style.surface = style_environment_color(rt, environment, .Success)
	}
	return style
}

button_variant_name :: proc(variant: Button_Variant) -> string {
	switch variant {
	case .Default: return "default"
	case .Primary: return "primary"
	case .Toolbar: return "toolbar"
	case .Quiet: return "quiet"
	case .Tab: return "tab"
	case .Count: return "invalid"
	}
	return "invalid"
}

// style_metric scales an application-authored logical metric by the active
// density. It leaves ownership and the meaning of each metric with the app.
style_metric :: proc(ui: ^UI, value: f32) -> f32 {
	if ui == nil || ui.runtime == nil { return value }
	return value * ui.runtime.style_environment.density
}

style_environment_resolve :: proc(previous, override: Style_Environment, rt: ^Runtime) -> (resolved: Style_Environment, valid: bool) {
	resolved = previous
	valid = false
	if override.theme != 0 {
		index := u64(u32(override.theme))
		if index == 0 || index > u64(len(rt.style_themes)) { return }
		resolved.theme = override.theme
	}
	if override.density != 0 {
		if override.density != override.density || override.density < 0.5 || override.density > 3 { return }
		resolved.density = override.density
	}
	if override.text_scale != 0 {
		if override.text_scale != override.text_scale || override.text_scale <= 0 || override.text_scale >= 100 { return }
		resolved.text_scale = override.text_scale
	}
	if override.accent != 0 { resolved.accent = override.accent }
	valid = true
	return
}

// style_domain_dirty_stages maps style dependencies to retained work. Typography
// also invalidates the node's shaped text product during reconciliation.
style_domain_dirty_stages :: proc(domain: Style_Domain) -> Dirty_Stages {
	dirty: Dirty_Stages = {}
	switch domain {
	case .Metrics, .Typography:
		dirty += {.Layout, .Paint, .Composite}
	case .Paint, .Material:
		dirty += {.Paint, .Composite}
	}
	return dirty
}

style_domains_dirty_stages :: proc(domains: Style_Domains) -> Dirty_Stages {
	dirty: Dirty_Stages = {}
	for domain in Style_Domain {
		if domain in domains { dirty += style_domain_dirty_stages(domain) }
	}
	return dirty
}

// style_environment_push scopes subtree-wide inputs to nodes described below
// the current container. The containing node is also a layout-isolation
// boundary: its parent-assigned bounds stay stable while its contents reflow.
style_environment_push :: proc(ui: ^UI, environment: Style_Environment) -> Style_Environment_Scope {
	if ui == nil || ui.runtime == nil { return Style_Environment_Scope{} }
	rt := ui.runtime
	resolved, valid := style_environment_resolve(rt.style_environment, environment, rt)
	if !rt.frame_open || !valid {
		append_diagnostic(rt, "style environment requires an open description frame and valid theme, density, text scale, and accent inputs")
		return Style_Environment_Scope{}
	}
	if len(rt.stack) == 0 {
		append_diagnostic(rt, "style environment scope requires a described container boundary")
		return Style_Environment_Scope{}
	}
	boundary := rt.stack[len(rt.stack)-1]
	boundary_described := false
	for index := len(rt.pending)-1; index >= 0; index -= 1 {
		item := &rt.pending[index]
		if item.kind == .Description && item.description.id == boundary {
			item.description.style_scope_boundary = true
			boundary_described = true
			break
		}
	}
	if !boundary_described {
		append_diagnostic(rt, "style environment boundary must be described in the current frame")
		return Style_Environment_Scope{}
	}
	if node, exists := rt.nodes[boundary]; exists { node.style_scope_boundary = true }
	scope := Style_Environment_Scope{
		runtime=rt,
		previous=rt.style_environment,
		active=true,
	}
	append(&rt.style_scope_stack, scope)
	scope.depth = len(rt.style_scope_stack)-1
	rt.style_scope_stack[len(rt.style_scope_stack)-1].depth = scope.depth
	rt.style_environment = resolved
	return scope
}

style_environment_pop :: proc(ui: ^UI, scope: Style_Environment_Scope) {
	if ui == nil || ui.runtime == nil || !scope.active { return }
	rt := ui.runtime
	if scope.runtime != rt || len(rt.style_scope_stack) == 0 ||
		scope.depth != len(rt.style_scope_stack)-1 {
		append_diagnostic(rt, "style environment scopes must be popped once in last-in, first-out order")
		return
	}
	rt.style_environment = scope.previous
	pop(&rt.style_scope_stack)
}

DEFAULT_STYLE :: Layout_Style{
	direction = .Column,
	width = -1,
	height = -1,
	min_width = 0,
	max_width = -1,
	min_height = 0,
	max_height = -1,
	grow = 0,
	padding = 0,
	gap = 0,
	align = .Stretch,
	clip = false,
}

// layout_style starts from Alicorn's ordinary layout defaults and lets an
// application name only the values that express its intent. It is a
// constructor, not a second styling language: advanced callers can still use
// Layout_Style directly when they need every field.
layout_style :: proc(
	direction: Layout_Direction = .Column,
	width: f32 = -1,
	height: f32 = -1,
	min_width: f32 = 0,
	max_width: f32 = -1,
	min_height: f32 = 0,
	max_height: f32 = -1,
	grow: f32 = 0,
	padding: f32 = 0,
	gap: f32 = 0,
	align: Align = .Stretch,
	clip: bool = false,
) -> Layout_Style {
	return Layout_Style{
		direction = direction,
		width = width,
		height = height,
		min_width = min_width,
		max_width = max_width,
		min_height = min_height,
		max_height = max_height,
		grow = grow,
		padding = padding,
		gap = gap,
		align = align,
		clip = clip,
	}
}

DEFAULT_COLOR :: Color{0.78, 0.82, 0.90, 1.0}

// Container APIs use this sentinel to distinguish an omitted background from
// an explicitly requested color. Root resolves the omitted value to
// DEFAULT_COLOR; ordinary layout containers remain non-painting by default.
NO_BACKGROUND_COLOR :: Color{0, 0, 0, 0}

color_equal :: proc(a, b: Color) -> bool {
	return a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a
}

resolve_container_color :: proc(kind: Node_Kind, color: Color) -> (resolved: Color, paints: bool) {
	if color_equal(color, NO_BACKGROUND_COLOR) {
		if kind == .Root {
			return DEFAULT_COLOR, true
		}
		return color, false
	}
	return color, true
}

site :: proc(file: string, line, column: int, component: string) -> Source_Site {
	return Source_Site{file, line, column, component}
}

caller_site :: proc(component: string, loc := #caller_location) -> Source_Site {
	return Source_Site{loc.file_path, int(loc.line), int(loc.column), component}
}

resolve_source :: proc(source: Source_Site, component: string, loc := #caller_location) -> Source_Site {
	if source.file != "" { return source }
	return Source_Site{loc.file_path, int(loc.line), int(loc.column), component}
}

