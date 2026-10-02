package alicorn

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

