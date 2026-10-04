package alicorn

style_environment_changed_domains :: proc(previous, next: Style_Environment) -> Style_Domains {
	changed: Style_Domains = {}
	if previous.text_scale != next.text_scale { changed += {.Metrics, .Typography} }
	if previous.density != next.density { changed += {.Metrics} }
	if previous.theme != next.theme || !color_equal(previous.accent, next.accent) { changed += {.Paint} }
	return changed
}

style_color_is_valid :: proc(color: Color) -> bool {
	return color.r == color.r && color.g == color.g && color.b == color.b && color.a == color.a &&
	       color.r >= 0 && color.r <= 1 && color.g >= 0 && color.g <= 1 &&
	       color.b >= 0 && color.b <= 1 && color.a > 0 && color.a <= 1
}

style_theme_is_valid :: proc(theme: Style_Theme) -> bool {
	for color in theme.colors {
		if !style_color_is_valid(color) { return false }
	}
	return true
}

// style_theme_register appends an immutable palette and returns a compact ID.
// IDs remain stable for the lifetime of this Runtime.
style_theme_register :: proc(rt: ^Runtime, theme: Style_Theme) -> Style_Theme_ID {
	if rt == nil || !style_theme_is_valid(theme) {
		if rt != nil { append_diagnostic(rt, "style theme colors must be finite, opaque-or-visible normalized RGBA values") }
		return 0
	}
	append(&rt.style_themes, theme)
	return Style_Theme_ID(u64(len(rt.style_themes)))
}

style_theme_color :: proc(rt: ^Runtime, theme: Style_Theme_ID, role: Style_Color_Role) -> Color {
	default_theme := DEFAULT_STYLE_THEME
	if int(role) < 0 || role >= .Count { return default_theme.colors[int(Style_Color_Role.Text)] }
	index := u64(theme)
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
	if role == .Accent && environment.accent.a > 0 { return environment.accent }
	return style_theme_color(rt, environment.theme, role)
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
		index := u64(override.theme)
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
	if override.accent.a != 0 {
		if !style_color_is_valid(override.accent) { return }
		resolved.accent = override.accent
	}
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

