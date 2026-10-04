package alicorn

style_environment_changed_domains :: proc(previous, next: Style_Environment) -> Style_Domains {
	changed: Style_Domains = {}
	if previous.text_scale != next.text_scale { changed += {.Metrics, .Typography} }
	return changed
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
	if !rt.frame_open || environment.text_scale <= 0 || environment.text_scale >= 100 || environment.text_scale != environment.text_scale {
		append_diagnostic(rt, "style environment requires an open description frame and a finite positive text scale")
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
	rt.style_environment = environment
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

