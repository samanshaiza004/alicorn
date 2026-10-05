package alicorn

// Paint_Command is the renderer-facing output of every paint producer:
// retained widgets, runtime overlays, and host chrome. The owner is diagnostic
// and transient-maintenance metadata; renderers dispatch only on the payload.
Paint_Command :: struct {
	owner:       Node_ID,
	bounds:      Rect,
	clip:        Rect,
	opacity:     f32,
	translation: [2]f32,
	payload:     Paint_Payload,
}

Paint_Payload :: union #no_nil {
	Surface_Paint,
	Text_Paint,
	Geometry_Paint,
}

Surface_Shape_Kind :: enum {
	Rectangle,
	Rounded_Rectangle,
	Line,
}

Surface_Shape :: struct {
	kind:          Surface_Shape_Kind,
	corner_radius: f32,
}

Paint_Stroke :: struct {
	color: Color,
	width: f32,
}

Material_ID :: distinct u32
MATERIAL_FLAT :: Material_ID(0)

Material_Group_ID :: distinct u32
MATERIAL_GROUP_NONE :: Material_Group_ID(0)

Surface_Paint :: struct {
	shape:           Surface_Shape,
	fill:            Color,
	stroke:          Paint_Stroke,
	material:        Material_ID,
	physical_height: f32,
	material_group:  Material_Group_ID,
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
) -> Paint_Command {
	return Paint_Command{
		owner=owner,
		bounds=bounds,
		clip=clip,
		opacity=opacity,
		translation=translation,
		payload=Surface_Paint{
			shape=shape,
			fill=color,
			material=material,
			physical_height=physical_height,
			material_group=material_group,
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

paint_command_is_surface :: proc(command: Paint_Command) -> bool {
	_, ok := command.payload.(Surface_Paint)
	return ok
}

paint_command_is_text :: proc(command: Paint_Command) -> bool {
	_, ok := command.payload.(Text_Paint)
	return ok
}

paint_command_is_geometry :: proc(command: Paint_Command) -> bool {
	_, ok := command.payload.(Geometry_Paint)
	return ok
}

paint_surface_color :: proc(command: Paint_Command) -> (color: Color, ok: bool) {
	if surface, ok := command.payload.(Surface_Paint); ok {
		return surface.fill, true
	}
	return {}, false
}
