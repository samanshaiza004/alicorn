package alicorn

Icon_Point :: struct { x, y: f32 }

Icon_Segment :: struct {
	x0, y0: f32,
	x1, y1: f32,
}

ICON_MAX_SEGMENTS :: 32
ICON_DEFAULT_STROKE_WIDTH :: f32(1.8)
ICON_TRAILING_SLOT_WIDTH :: f32(26)

Icon_Geometry :: struct {
	segments: [ICON_MAX_SEGMENTS]Icon_Segment,
	count: int,
}

icon_id_is_valid :: proc(id: Icon_ID) -> bool {
	return id > .None && id < .Count
}

// icon_geometry returns a small normalized line path. Coordinates range from
// zero to one so the native renderer can scale it independently of fonts/DPI.
icon_geometry :: proc(id: Icon_ID) -> (geometry: Icon_Geometry) {
	#partial switch id {
	case .Check:
		icon_add_polyline(&geometry, [3]Icon_Point{{0.18, 0.52}, {0.42, 0.75}, {0.83, 0.24}})
	case .Chevron_Down:
		icon_add_polyline(&geometry, [3]Icon_Point{{0.22, 0.38}, {0.50, 0.64}, {0.78, 0.38}})
	case .Chevron_Right:
		icon_add_polyline(&geometry, [3]Icon_Point{{0.38, 0.22}, {0.64, 0.50}, {0.38, 0.78}})
	case .Close:
		icon_add_segment(&geometry, 0.25, 0.25, 0.75, 0.75)
		icon_add_segment(&geometry, 0.75, 0.25, 0.25, 0.75)
	case .Minus:
		icon_add_segment(&geometry, 0.22, 0.50, 0.78, 0.50)
	case .Radio_Selected:
		icon_add_polyline(&geometry, [9]Icon_Point{
			{0.50, 0.10}, {0.78, 0.22}, {0.90, 0.50}, {0.78, 0.78},
			{0.50, 0.90}, {0.22, 0.78}, {0.10, 0.50}, {0.22, 0.22}, {0.50, 0.10},
		})
		icon_add_polyline(&geometry, [5]Icon_Point{{0.50, 0.36}, {0.64, 0.50}, {0.50, 0.64}, {0.36, 0.50}, {0.50, 0.36}})
	case .Warning:
		icon_add_polyline(&geometry, [4]Icon_Point{{0.50, 0.10}, {0.91, 0.84}, {0.09, 0.84}, {0.50, 0.10}})
		icon_add_segment(&geometry, 0.50, 0.36, 0.50, 0.59)
		icon_add_segment(&geometry, 0.50, 0.70, 0.50, 0.72)
	case .Info:
		icon_add_polyline(&geometry, [9]Icon_Point{
			{0.50, 0.10}, {0.78, 0.22}, {0.90, 0.50}, {0.78, 0.78},
			{0.50, 0.90}, {0.22, 0.78}, {0.10, 0.50}, {0.22, 0.22}, {0.50, 0.10},
		})
		icon_add_segment(&geometry, 0.50, 0.42, 0.50, 0.69)
		icon_add_segment(&geometry, 0.50, 0.30, 0.50, 0.32)
	case .Folder_Closed:
		icon_add_polyline(&geometry, [7]Icon_Point{
			{0.10, 0.26}, {0.39, 0.26}, {0.49, 0.38}, {0.90, 0.38},
			{0.90, 0.78}, {0.10, 0.78}, {0.10, 0.26},
		})
	case .Folder_Open:
		icon_add_polyline(&geometry, [8]Icon_Point{
			{0.10, 0.25}, {0.38, 0.25}, {0.49, 0.36}, {0.83, 0.36},
			{0.72, 0.63}, {0.92, 0.45}, {0.80, 0.78}, {0.10, 0.78},
		}, closed=true)
		icon_add_segment(&geometry, 0.10, 0.61, 0.73, 0.61)
	case .File:
		icon_add_polyline(&geometry, [6]Icon_Point{
			{0.23, 0.10}, {0.63, 0.10}, {0.80, 0.27}, {0.80, 0.90}, {0.23, 0.90}, {0.23, 0.10},
		})
		icon_add_polyline(&geometry, [3]Icon_Point{{0.63, 0.10}, {0.63, 0.27}, {0.80, 0.27}})
	case .Search:
		icon_add_polyline(&geometry, [9]Icon_Point{
			{0.45, 0.12}, {0.68, 0.21}, {0.78, 0.44}, {0.68, 0.67},
			{0.45, 0.76}, {0.22, 0.67}, {0.12, 0.44}, {0.22, 0.21}, {0.45, 0.12},
		})
		icon_add_segment(&geometry, 0.65, 0.64, 0.88, 0.88)
	case .Settings:
		icon_add_polyline(&geometry, [17]Icon_Point{
			{0.50, 0.08}, {0.60, 0.20}, {0.75, 0.17}, {0.77, 0.32},
			{0.90, 0.42}, {0.80, 0.53}, {0.84, 0.68}, {0.69, 0.70},
			{0.59, 0.88}, {0.49, 0.75}, {0.34, 0.82}, {0.32, 0.66},
			{0.15, 0.58}, {0.26, 0.47}, {0.20, 0.31}, {0.37, 0.29}, {0.50, 0.08},
		})
		icon_add_polyline(&geometry, [8]Icon_Point{
			{0.50, 0.36}, {0.62, 0.41}, {0.66, 0.53}, {0.59, 0.64},
			{0.46, 0.65}, {0.37, 0.56}, {0.38, 0.43}, {0.50, 0.36},
		})
	case .Terminal:
		icon_add_polyline(&geometry, [5]Icon_Point{{0.12, 0.20}, {0.88, 0.20}, {0.88, 0.80}, {0.12, 0.80}, {0.12, 0.20}})
		icon_add_polyline(&geometry, [3]Icon_Point{{0.28, 0.39}, {0.43, 0.50}, {0.28, 0.61}})
		icon_add_segment(&geometry, 0.50, 0.62, 0.70, 0.62)
	}
	return
}

@(private)
icon_add_polyline :: proc(geometry: ^Icon_Geometry, points: $Points, closed := false) {
	if geometry == nil || len(points) < 2 { return }
	for index in 0..<len(points)-1 {
		icon_add_segment(geometry, points[index].x, points[index].y, points[index+1].x, points[index+1].y)
	}
	if closed { icon_add_segment(geometry, points[len(points)-1].x, points[len(points)-1].y, points[0].x, points[0].y) }
}

@(private)
icon_add_segment :: proc(geometry: ^Icon_Geometry, x0, y0, x1, y1: f32) {
	if geometry == nil || geometry.count >= len(geometry.segments) { return }
	geometry.segments[geometry.count] = Icon_Segment{x0, y0, x1, y1}
	geometry.count += 1
}

// icon inserts a decorative, font-independent icon into ordinary layout.
// The surrounding component remains responsible for its accessible name.
icon :: proc(
	ui: ^UI,
	id: Icon_ID,
	key: UI_Key = UI_Unkeyed{},
	size: f32 = 16,
	color_role := Style_Color_Role.Muted_Text,
	loc := #caller_location,
) -> Node_ID {
	if ui == nil || ui.runtime == nil || !ui.runtime.frame_open { return 0 }
	if !icon_id_is_valid(id) || size <= 0 || !style_color_role_is_valid(color_role) {
		append_diagnostic(ui.runtime, "icon requires a built-in icon ID, positive size, and valid theme color role")
		return 0
	}
	rt := ui.runtime
	node := container_begin_simple(
		ui,
		.Container,
		label="",
		key=key,
		style=layout_style(width=size, height=size),
		loc=loc,
	)
	if node == 0 { return 0 }
	pending := &rt.pending[len(rt.pending)-1]
	if pending.kind == .Description && pending.description.id == node {
		pending.description.icon_id = id
		pending.description.color = style_color(ui, color_role)
	}
	container_end(ui)
	return node
}
