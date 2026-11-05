package paint_reference

import "core:math"
import alicorn "../../runtime"

PAINT_REFERENCE_MAX_DIMENSION :: 128
PAINT_REFERENCE_SCENE_RECTANGLES :: 8

// This one-command scene was minimized from the clip/translation GPU failure
// found by seed 2. Keep it independent of the generated corpus so generator
// changes cannot remove this regression coverage.
paint_reference_stationary_clip_regression :: proc() -> alicorn.Paint_Command {
	return alicorn.paint_surface_command(
		alicorn.Node_ID(7),
		{112, 76, 36, 42},
		{113, 101, 2, 9},
		{0.85882354, 0.92941177, 0.49019608, 0.5019608},
		opacity=0.2509804,
		translation={2, -3},
	)
}

Paint_Reference_Error_Code :: enum {
	None,
	Invalid_Target,
	Invalid_Clear_Color,
	Invalid_Opacity,
	Unsupported_Payload,
	Unsupported_Shape,
	Unsupported_Material,
	Unsupported_Stroke,
	Unsupported_Optical_Decoration,
	Non_Finite_Input,
	Out_Of_Range_Color,
	Non_Pixel_Aligned,
	Invalid_Rectangle,
}

Paint_Reference_Error :: struct {
	code:          Paint_Reference_Error_Code,
	command_index: int,
	owner:         alicorn.Node_ID,
}

paint_reference_error :: proc(code: Paint_Reference_Error_Code, index: int, owner: alicorn.Node_ID) -> Paint_Reference_Error {
	return Paint_Reference_Error{code, index, owner}
}

paint_reference_finite :: proc(value: f32) -> bool {
	return !math.is_nan(value) && !math.is_inf(value)
}

paint_reference_integral :: proc(value: f32) -> bool {
	return paint_reference_finite(value) && math.floor(value) == value
}

paint_reference_color_valid :: proc(color: alicorn.Color) -> bool {
	return paint_reference_finite(color.r) && paint_reference_finite(color.g) &&
		paint_reference_finite(color.b) && paint_reference_finite(color.a) &&
		color.r >= 0 && color.r <= 1 && color.g >= 0 && color.g <= 1 &&
		color.b >= 0 && color.b <= 1 && color.a >= 0 && color.a <= 1
}

paint_reference_color_finite :: proc(color: alicorn.Color) -> bool {
	return paint_reference_finite(color.r) && paint_reference_finite(color.g) &&
		paint_reference_finite(color.b) && paint_reference_finite(color.a)
}

paint_reference_validate_command :: proc(command: alicorn.Paint_Command, index: int) -> Paint_Reference_Error {
	if !paint_reference_finite(command.opacity) ||
		!paint_reference_finite(command.bounds.x) || !paint_reference_finite(command.bounds.y) ||
		!paint_reference_finite(command.bounds.w) || !paint_reference_finite(command.bounds.h) ||
		!paint_reference_finite(command.clip.x) || !paint_reference_finite(command.clip.y) ||
		!paint_reference_finite(command.clip.w) || !paint_reference_finite(command.clip.h) ||
		!paint_reference_finite(command.translation[0]) || !paint_reference_finite(command.translation[1]) {
		return paint_reference_error(.Non_Finite_Input, index, command.owner)
	}
	if command.opacity < 0 || command.opacity > 1 {
		return paint_reference_error(.Invalid_Opacity, index, command.owner)
	}
	if command.bounds.w < 0 || command.bounds.h < 0 || command.clip.w < 0 || command.clip.h < 0 {
		return paint_reference_error(.Invalid_Rectangle, index, command.owner)
	}
	left := command.bounds.x + command.translation[0]
	top := command.bounds.y + command.translation[1]
	right := command.bounds.x + command.bounds.w + command.translation[0]
	bottom := command.bounds.y + command.bounds.h + command.translation[1]
	clip_right := command.clip.x + command.clip.w
	clip_bottom := command.clip.y + command.clip.h
	if !paint_reference_finite(left) || !paint_reference_finite(top) ||
		!paint_reference_finite(right) || !paint_reference_finite(bottom) ||
		!paint_reference_finite(clip_right) || !paint_reference_finite(clip_bottom) {
		return paint_reference_error(.Non_Finite_Input, index, command.owner)
	}
	// The initial reference uses scale 1 and half-open integer pixel bounds.
	// Translation applies to bounds; clip is already resolved in its own space.
	if !paint_reference_integral(left) || !paint_reference_integral(top) ||
		!paint_reference_integral(right) || !paint_reference_integral(bottom) ||
		!paint_reference_integral(command.clip.x) || !paint_reference_integral(command.clip.y) ||
		!paint_reference_integral(clip_right) || !paint_reference_integral(clip_bottom) {
		return paint_reference_error(.Non_Pixel_Aligned, index, command.owner)
	}

	switch surface in command.payload {
	case alicorn.Surface_Paint:
		if !paint_reference_finite(surface.shape.corner_radius) ||
			!paint_reference_finite(surface.stroke.width) || !paint_reference_finite(surface.physical_height) ||
			!paint_reference_finite(surface.top_edge_gap[0]) || !paint_reference_finite(surface.top_edge_gap[1]) ||
			!paint_reference_color_finite(surface.fill) || !paint_reference_color_finite(surface.stroke.color) {
			return paint_reference_error(.Non_Finite_Input, index, command.owner)
		}
		if surface.shape.kind != .Rectangle || surface.shape.corner_radius != 0 {
			return paint_reference_error(.Unsupported_Shape, index, command.owner)
		}
		if surface.material != alicorn.MATERIAL_FLAT {
			return paint_reference_error(.Unsupported_Material, index, command.owner)
		}
		if surface.stroke.width != 0 {
			return paint_reference_error(.Unsupported_Stroke, index, command.owner)
		}
		if surface.physical_height != 0 || surface.material_group != alicorn.MATERIAL_GROUP_NONE ||
			surface.top_edge_gap[0] != 0 || surface.top_edge_gap[1] != 0 {
			return paint_reference_error(.Unsupported_Optical_Decoration, index, command.owner)
		}
		if !paint_reference_color_valid(surface.fill) {
			return paint_reference_error(.Out_Of_Range_Color, index, command.owner)
		}
	case alicorn.Icon_Paint, alicorn.Image_Paint, alicorn.Text_Paint, alicorn.Geometry_Paint:
		return paint_reference_error(.Unsupported_Payload, index, command.owner)
	}
	return Paint_Reference_Error{}
}

paint_reference_clear_valid :: proc(clear: [4]u8) -> bool {
	if clear[3] == 0 { return clear[0] == 0 && clear[1] == 0 && clear[2] == 0 }
	return clear[3] == 255
}

paint_reference_quantize :: proc(value: f32) -> u8 {
	bounded := value
	if bounded < 0 { bounded = 0 }
	if bounded > 1 { bounded = 1 }
	return u8(math.floor(bounded*255+0.5))
}

// Renders the supported subset of the resolved paint stream into a caller-owned
// RGBA8 buffer. Validation completes before the output is changed, so an
// unsupported scene is rejected transactionally.
paint_reference_render :: proc(
	commands: []alicorn.Paint_Command,
	width, height: int,
	clear: [4]u8,
	output: []u8,
) -> Paint_Reference_Error {
	if width <= 0 || height <= 0 || width > PAINT_REFERENCE_MAX_DIMENSION ||
		height > PAINT_REFERENCE_MAX_DIMENSION || len(output) != width*height*4 {
		return paint_reference_error(.Invalid_Target, -1, 0)
	}
	if !paint_reference_clear_valid(clear) {
		return paint_reference_error(.Invalid_Clear_Color, -1, 0)
	}
	for command, command_index in commands {
		if error := paint_reference_validate_command(command, command_index); error.code != .None {
			return error
		}
	}

	for pixel in 0..<width*height {
		base := pixel*4
		output[base+0] = clear[0]
		output[base+1] = clear[1]
		output[base+2] = clear[2]
		output[base+3] = clear[3]
	}

	for command in commands {
		surface := command.payload.(alicorn.Surface_Paint)
		left := max(command.bounds.x+command.translation[0], command.clip.x)
		top := max(command.bounds.y+command.translation[1], command.clip.y)
		right := min(command.bounds.x+command.bounds.w+command.translation[0], command.clip.x+command.clip.w)
		bottom := min(command.bounds.y+command.bounds.h+command.translation[1], command.clip.y+command.clip.h)
		if right < left { right = left }
		if bottom < top { bottom = top }
		left = max(left, 0)
		top = max(top, 0)
		right = min(right, f32(width))
		bottom = min(bottom, f32(height))
		if right < left { right = left }
		if bottom < top { bottom = top }
		x0, y0, x1, y1 := int(left), int(top), int(right), int(bottom)
		if x1 <= x0 || y1 <= y0 { continue }

		source_alpha := surface.fill.a*command.opacity
		inverse_alpha := 1-source_alpha
		for y in y0..<y1 {
			for x in x0..<x1 {
				base := (y*width+x)*4
				destination_r := f32(output[base+0])/255
				destination_g := f32(output[base+1])/255
				destination_b := f32(output[base+2])/255
				destination_a := f32(output[base+3])/255
				output[base+0] = paint_reference_quantize(surface.fill.r*source_alpha + destination_r*inverse_alpha)
				output[base+1] = paint_reference_quantize(surface.fill.g*source_alpha + destination_g*inverse_alpha)
				output[base+2] = paint_reference_quantize(surface.fill.b*source_alpha + destination_b*inverse_alpha)
				output[base+3] = paint_reference_quantize(source_alpha + destination_a*inverse_alpha)
			}
		}
	}
	return Paint_Reference_Error{}
}

paint_reference_rng_next :: proc(state: ^u64) -> u32 {
	value := state^ * 6364136223846793005 + 1442695040888963407
	state^ = value
	return u32(value >> 32)
}

paint_reference_channel :: proc(value: u32) -> f32 {
	return f32(value%256)/255
}

// Produces one replayable, bounded scene. The first translucent rectangle
// ensures each generated case has a broad compositing destination.
paint_reference_generate_scene :: proc(seed: u64, width, height: int, commands: []alicorn.Paint_Command) -> int {
	if width < 16 || height < 16 || width > PAINT_REFERENCE_MAX_DIMENSION ||
		height > PAINT_REFERENCE_MAX_DIMENSION || len(commands) < PAINT_REFERENCE_SCENE_RECTANGLES {
		return 0
	}
	state := seed if seed != 0 else 0x9E3779B97F4A7C15
	full_clip := alicorn.Rect{0, 0, f32(width), f32(height)}
	commands[0] = alicorn.paint_surface_command(1, alicorn.Rect{8, 8, f32(width-16), f32(height-16)}, full_clip,
		alicorn.Color{0.25, 0.5, 0.75, 128.0/255.0})
	for index in 1..<PAINT_REFERENCE_SCENE_RECTANGLES {
		rx := paint_reference_rng_next(&state)
		ry := paint_reference_rng_next(&state)
		rw := paint_reference_rng_next(&state)
		rh := paint_reference_rng_next(&state)
		clip_x := paint_reference_rng_next(&state)%u32(width)
		clip_y := paint_reference_rng_next(&state)%u32(height)
		clip_w := paint_reference_rng_next(&state)%u32(width-int(clip_x)+1)
		clip_h := paint_reference_rng_next(&state)%u32(height-int(clip_y)+1)
		translation_x := int(paint_reference_rng_next(&state)%17)-8
		translation_y := int(paint_reference_rng_next(&state)%17)-8
		alpha_index := paint_reference_rng_next(&state)%4
		opacity_index := paint_reference_rng_next(&state)%4
		alpha_values := [4]u32{64, 128, 192, 255}
		alpha := f32(alpha_values[alpha_index])/255
		opacity := f32(alpha_values[opacity_index])/255
		commands[index] = alicorn.paint_surface_command(
			alicorn.Node_ID(index+1),
			alicorn.Rect{f32(int(rx%u32(width+32))-16), f32(int(ry%u32(height+32))-16), f32(8+rw%40), f32(8+rh%40)},
			alicorn.Rect{f32(clip_x), f32(clip_y), f32(clip_w), f32(clip_h)},
			alicorn.Color{paint_reference_channel(paint_reference_rng_next(&state)),
				paint_reference_channel(paint_reference_rng_next(&state)),
				paint_reference_channel(paint_reference_rng_next(&state)), alpha},
			opacity=opacity,
			translation={f32(translation_x), f32(translation_y)},
		)
	}
	return PAINT_REFERENCE_SCENE_RECTANGLES
}
