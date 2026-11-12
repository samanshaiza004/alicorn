package alicorn

Paint_Stroke_Placement :: enum u8 {
	Centered,
	Inside,
	Outside,
	Count,
}

// Backdrop_Effect is a bounded compositor request attached to a semantic
// surface. Direct is the required fallback for hosts that cannot retain or
// filter the backdrop within their supported resource policy.
Backdrop_Effect_Kind :: enum u8 { None, Blur }
Backdrop_Effect_Fallback :: enum u8 { Direct }
Backdrop_Effect :: struct {
	kind: Backdrop_Effect_Kind,
	sigma: f32,
	fallback: Backdrop_Effect_Fallback,
}

BACKDROP_NONE :: Backdrop_Effect{}

backdrop_blur :: proc(sigma: f32, fallback := Backdrop_Effect_Fallback.Direct) -> Backdrop_Effect {
	return Backdrop_Effect{kind=.Blur, sigma=sigma, fallback=fallback}
}

Backdrop_Effect_Paint :: struct {
	sigma: f32,
	fallback: Backdrop_Effect_Fallback,
}

// Paint_Command is the renderer-facing output of every paint producer:
// retained widgets, runtime overlays, and host chrome. The owner identifies
// the producer for diagnostics and sidecar resolution; renderers dispatch on
// the payload and use explicit resolvers for retained geometry.
Paint_Command :: struct {
	owner:       Node_ID,
	bounds:      Rect,
	clip:        Rect,
	opacity:     f32,
	translation: [2]f32,
	// Kept outside the payload union so this geometry hint occupies existing
	// alignment padding instead of increasing the retained command size.
	stroke_placement: Paint_Stroke_Placement,
	// Semantic surface gradient data stays in the Runtime's computed-style
	// sidecar; this marker occupies existing alignment padding.
	semantic_surface_gradient: bool,
	payload:     Paint_Payload,
}

Paint_Payload :: union #no_nil {
	Surface_Paint,
	Backdrop_Effect_Paint,
	Icon_Paint,
	Image_Paint,
	Text_Paint,
	Geometry_Paint,
}

paint_backdrop_effect_command :: proc(owner: Node_ID, bounds, clip: Rect, effect: Backdrop_Effect) -> Paint_Command {
	return Paint_Command{
		owner=owner,
		bounds=bounds,
		clip=clip,
		payload=Backdrop_Effect_Paint{effect.sigma, effect.fallback},
	}
}

// Icon_ID names font-independent, theme-tinted icons backed by compiled
// monochrome coverage masks. None is reserved for controls without an icon.
Icon_ID :: enum {
	None,
	Check,
	Chevron_Down,
	Chevron_Right,
	Close,
	Minus,
	Radio_Selected,
	Warning,
	Info,
	Folder_Closed,
	Folder_Open,
	File,
	Search,
	Settings,
	Terminal,
	Count,
}

Icon_Paint :: struct {
	id:    Icon_ID,
	color: Color,
}

Surface_Shape_Kind :: enum u8 {
	Rectangle,
	Rounded_Rectangle,
	Line,
	// Component-private bounded contour. Public surface_begin callers cannot
	// author this shape; TabBar owns its decoration and interaction separately.
	Connected_Tab,
	Rounded_Rectangle_Per_Corner,
}

// Surface_Corner_Radii stores logical radii in clockwise order, starting at
// the top-left corner. Paint normalizes overlapping sums against its bounds.
Surface_Corner_Radii :: struct {
	top_left, top_right, bottom_right, bottom_left: f32,
}

Surface_Shape :: struct {
	kind:          Surface_Shape_Kind,
	corner_radius: f32,
	corner_radii:  Surface_Corner_Radii,
}

surface_shape_rounded_corners :: proc(radii: Surface_Corner_Radii) -> Surface_Shape {
	return Surface_Shape{kind=.Rounded_Rectangle_Per_Corner, corner_radii=radii}
}

// surface_shape_uniform_corner_radius is the migration form for positional
// Surface_Shape literals; named corner_radius literals and UI radius options
// remain source-compatible.
surface_shape_uniform_corner_radius :: proc(radius: f32) -> Surface_Shape {
	return Surface_Shape{kind=.Rounded_Rectangle, corner_radius=radius}
}

surface_corner_radii_is_zero :: proc(radii: Surface_Corner_Radii) -> bool {
	return radii.top_left == 0 && radii.top_right == 0 && radii.bottom_right == 0 && radii.bottom_left == 0
}

surface_corner_radii_is_valid :: proc(radii: Surface_Corner_Radii) -> bool {
	for radius in ([4]f32{radii.top_left, radii.top_right, radii.bottom_right, radii.bottom_left}) {
		if !number_is_finite(radius) || radius < 0 { return false }
	}
	return true
}

surface_shape_corner_radii :: proc(shape: Surface_Shape) -> Surface_Corner_Radii {
	switch shape.kind {
	case .Rounded_Rectangle:
		return Surface_Corner_Radii{shape.corner_radius, shape.corner_radius, shape.corner_radius, shape.corner_radius}
	case .Rounded_Rectangle_Per_Corner:
		return shape.corner_radii
	case .Rectangle, .Line, .Connected_Tab:
		return {}
	}
	return {}
}

surface_corner_radii_normalize :: proc(radii: Surface_Corner_Radii, width, height: f32) -> Surface_Corner_Radii {
	if !surface_corner_radii_is_valid(radii) || !number_is_finite(width) || !number_is_finite(height) || width <= 0 || height <= 0 {
		return {}
	}

	// Reduce every radius by one shared factor so opposing arcs never overlap.
	// Use f64 for sums so every finite f32 radius remains normalizable.
	// Applying one factor preserves the authored corner proportions.
	scale := f64(1)
	w, h := f64(width), f64(height)
	top := f64(radii.top_left)+f64(radii.top_right)
	right := f64(radii.top_right)+f64(radii.bottom_right)
	bottom := f64(radii.bottom_right)+f64(radii.bottom_left)
	left := f64(radii.bottom_left)+f64(radii.top_left)
	if top > w { scale = min(scale, w/top) }
	if right > h { scale = min(scale, h/right) }
	if bottom > w { scale = min(scale, w/bottom) }
	if left > h { scale = min(scale, h/left) }
	return Surface_Corner_Radii{
		f32(f64(radii.top_left)*scale),
		f32(f64(radii.top_right)*scale),
		f32(f64(radii.bottom_right)*scale),
		f32(f64(radii.bottom_left)*scale),
	}
}

surface_shape_normalized_corner_radii :: proc(shape: Surface_Shape, width, height: f32) -> Surface_Corner_Radii {
	return surface_corner_radii_normalize(surface_shape_corner_radii(shape), width, height)
}

surface_shape_has_rounded_corners :: proc(shape: Surface_Shape) -> bool {
	radii := surface_shape_corner_radii(shape)
	return radii.top_left > 0 || radii.top_right > 0 || radii.bottom_right > 0 || radii.bottom_left > 0
}

surface_shape_is_valid :: proc(shape: Surface_Shape) -> bool {
	switch shape.kind {
	case .Rectangle:
		return shape.corner_radius == 0 && surface_corner_radii_is_zero(shape.corner_radii)
	case .Rounded_Rectangle:
		return number_is_finite(shape.corner_radius) && shape.corner_radius >= 0 &&
		       surface_corner_radii_is_zero(shape.corner_radii)
	case .Rounded_Rectangle_Per_Corner:
		return shape.corner_radius == 0 && surface_corner_radii_is_valid(shape.corner_radii)
	case .Line:
		return false
	case .Connected_Tab:
		return false
	}
	return false
}

Paint_Stroke :: struct {
	color: Color,
	width: f32,
}

Material_ID :: distinct u32
MATERIAL_FLAT :: Material_ID(0)

Material_Group_ID :: distinct u32
MATERIAL_GROUP_NONE :: Material_Group_ID(0)

// Surface gradients are deliberately limited to one axis and two stops. The
// existing surface fill is stop one; end is stop two. None preserves the
// ordinary solid-fill path without extra geometry or renderer state.
Surface_Gradient_Axis :: enum u8 {
	None,
	Horizontal,
	Vertical,
}

Surface_Gradient :: struct {
	axis: Surface_Gradient_Axis,
	end:  Color,
}

SURFACE_GRADIENT_NONE :: Surface_Gradient{}

Surface_Gradient_Is_Valid :: proc(start: Color, gradient: Surface_Gradient) -> bool {
	switch gradient.axis {
	case .None:
		return true
	case .Horizontal, .Vertical:
		return semantic_surface_color_is_valid(start) && semantic_surface_color_is_valid(gradient.end) && start.a == gradient.end.a
	}
	return false
}

Surface_Paint :: struct {
	shape:           Surface_Paint_Shape,
	fill:            Color,
	stroke:          Paint_Stroke,
	material:        Material_ID,
	physical_height: f32,
	material_group:  Material_Group_ID,
	// Absolute logical X coordinates of an opening in the top optical edge.
	// A zero interval keeps the ordinary uninterrupted surface treatment.
	top_edge_gap:    [2]f32,
}

// Surface_Paint_Shape keeps Paint_Command compact. Uniform radii fit inline;
// per-corner radii resolve from the retained semantic or computed style keyed
// by the command owner.
Surface_Paint_Shape :: struct {
	kind: Surface_Shape_Kind,
	corner_radius: f32,
}

surface_paint_shape :: proc(shape: Surface_Shape) -> Surface_Paint_Shape {
	return Surface_Paint_Shape{kind=shape.kind, corner_radius=shape.corner_radius}
}

Text_Run_Source :: enum {
	Retained,
	Composition,
	Tooltip,
	Drag_Preview,
	Host,
}

// A handle identifies one shaped text resource generation. Runtime resolvers
// return only the shaped run, never widget state or layout/presentation data.
Text_Run_Handle :: struct {
	source:     Text_Run_Source,
	resource:   u64,
	generation: u64,
}

Text_Paint :: struct {
	run:   Text_Run_Handle,
	color: Color,
	// Spans are borrowed from the owning retained node for the same lifetime
	// as its paint cache. Paint commands do not own dynamically allocated data.
	spans: []Text_Paint_Span,
}

// Geometry handles address payload data only. Bounds, clip, opacity, and
// translation are already resolved on Paint_Command.
Geometry_Handle :: struct {
	resource:   Node_ID,
	generation: u64,
}

// Image_Handle is a monotonically allocated Runtime-local resource ID. IDs
// are never reused during a Runtime lifetime, so a released handle stays stale.
Image_Handle :: distinct u64

Image_Pixels_View :: struct {
	width, height: int,
	rgba8:         []u8,
}

Image_Paint :: struct {
	image: Image_Handle,
}

Geometry_Paint :: struct {
	geometry: Geometry_Handle,
}

paint_surface_command :: proc(
	owner: Node_ID,
	bounds, clip: Rect,
	color: Color,
	opacity: f32 = 1,
	translation: [2]f32 = {},
	shape: Surface_Shape = Surface_Shape{kind=.Rectangle},
	material: Material_ID = MATERIAL_FLAT,
	physical_height: f32 = 0,
	material_group: Material_Group_ID = MATERIAL_GROUP_NONE,
	stroke: Paint_Stroke = {},
	stroke_placement: Paint_Stroke_Placement = .Centered,
	top_edge_gap: [2]f32 = {},
) -> Paint_Command {
	return Paint_Command{
		owner=owner,
		bounds=bounds,
		clip=clip,
		opacity=opacity,
		translation=translation,
		stroke_placement=stroke_placement,
		payload=Surface_Paint{
			shape=surface_paint_shape(shape),
			fill=color,
			material=material,
			physical_height=physical_height,
			material_group=material_group,
			stroke=stroke,
			top_edge_gap=top_edge_gap,
		},
	}
}

paint_text_command :: proc(
	owner: Node_ID,
	bounds, clip: Rect,
	run: Text_Run_Handle,
	color: Color,
	spans: []Text_Paint_Span = nil,
	opacity: f32 = 1,
	translation: [2]f32 = {},
) -> Paint_Command {
	return Paint_Command{
		owner=owner,
		bounds=bounds,
		clip=clip,
		opacity=opacity,
		translation=translation,
		payload=Text_Paint{run, color, spans},
	}
}

paint_icon_command :: proc(
	owner: Node_ID,
	bounds, clip: Rect,
	id: Icon_ID,
	color: Color,
	opacity: f32 = 1,
	translation: [2]f32 = {},
) -> Paint_Command {
	return Paint_Command{
		owner=owner,
		bounds=bounds,
		clip=clip,
		opacity=opacity,
		translation=translation,
		payload=Icon_Paint{id, color},
	}
}

paint_geometry_command :: proc(
	owner: Node_ID,
	bounds, clip: Rect,
	geometry: Geometry_Handle,
	opacity: f32 = 1,
	translation: [2]f32 = {},
) -> Paint_Command {
	return Paint_Command{
		owner=owner,
		bounds=bounds,
		clip=clip,
		opacity=opacity,
		translation=translation,
		payload=Geometry_Paint{geometry},
	}
}

paint_image_command :: proc(
	owner: Node_ID,
	bounds, clip: Rect,
	image: Image_Handle,
	opacity: f32 = 1,
	translation: [2]f32 = {},
) -> Paint_Command {
	return Paint_Command{
		owner=owner,
		bounds=bounds,
		clip=clip,
		opacity=opacity,
		translation=translation,
		payload=Image_Paint{image},
	}
}

paint_command_is_surface :: proc(command: Paint_Command) -> bool {
	_, ok := command.payload.(Surface_Paint)
	return ok
}

paint_command_is_backdrop_effect :: proc(command: Paint_Command) -> bool {
	_, ok := command.payload.(Backdrop_Effect_Paint)
	return ok
}

paint_command_is_text :: proc(command: Paint_Command) -> bool {
	_, ok := command.payload.(Text_Paint)
	return ok
}

paint_command_is_icon :: proc(command: Paint_Command) -> bool {
	_, ok := command.payload.(Icon_Paint)
	return ok
}

paint_command_is_geometry :: proc(command: Paint_Command) -> bool {
	_, ok := command.payload.(Geometry_Paint)
	return ok
}

paint_command_is_image :: proc(command: Paint_Command) -> bool {
	_, ok := command.payload.(Image_Paint)
	return ok
}

paint_surface_color :: proc(command: Paint_Command) -> (color: Color, ok: bool) {
	if surface, ok := command.payload.(Surface_Paint); ok {
		return surface.fill, true
	}
	return {}, false
}
