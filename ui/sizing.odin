package ui

import "core:math"
import alicorn "alicorn:runtime"

// Size_Input is a bounded authoring declaration. Fixed and fit-content
// dimensions lower to the existing Layout_Style representation. Percentage
// width is a separate description-time prototype; it adds no retained-node or
// solver state.
Size_Input_Kind :: enum { Unspecified, Fixed, Fit_Content, Percentage }

Size_Input :: struct {
	kind: Size_Input_Kind,
	value: f32,
}

// Expand is intentionally a separate type because expansion belongs to the
// parent's main-axis allocator, not to a width/height expression.
Expand_Input :: struct {
	defined: bool,
	weight: f32,
}

Sizing :: struct {
	width, height: Size_Input,
	min_width, max_width: Size_Input,
	min_height, max_height: Size_Input,
	grow: Expand_Input,
}

logical :: proc(value: f32) -> Size_Input {
	return Size_Input{kind=.Fixed, value=value}
}

fit_content :: proc() -> Size_Input {
	return Size_Input{kind=.Fit_Content}
}

// percent expresses a parent-relative fraction, where 1 means 100%. The first
// prototype supports width only and resolves it at description time against a
// provably definite parent inner width.
percent :: proc(fraction: f32) -> Size_Input {
	return Size_Input{kind=.Percentage, value=fraction}
}

expand :: proc(weight: f32 = 1) -> Expand_Input {
	return Expand_Input{defined=true, weight=weight}
}

sizing :: proc(
	width: Size_Input = {},
	height: Size_Input = {},
	min_width: Size_Input = {},
	max_width: Size_Input = {},
	min_height: Size_Input = {},
	max_height: Size_Input = {},
	grow: Expand_Input = {},
) -> Sizing {
	return Sizing{width, height, min_width, max_width, min_height, max_height, grow}
}

size_input_valid :: proc(input: Size_Input, allow_fit_content: bool, allow_percentage: bool = false) -> bool {
	switch input.kind {
	case .Unspecified:
		return true
	case .Fixed:
		return !math.is_nan(input.value) && !math.is_inf(input.value) && input.value >= 0
	case .Fit_Content:
		return allow_fit_content
	case .Percentage:
		return allow_percentage && !math.is_nan(input.value) && !math.is_inf(input.value) && input.value >= 0 && input.value <= 100
	}
	return false
}

@(private)
resolve_size_input :: proc(input: Size_Input, current, default_value, fit_value: f32, allow_fit_content: bool) -> (f32, bool) {
	if !size_input_valid(input, allow_fit_content) { return current, false }
	switch input.kind {
	case .Unspecified:
		return current, true
	case .Fixed:
		if current != default_value && current != input.value { return current, false }
		return input.value, true
	case .Fit_Content:
		if current != default_value && current != fit_value { return current, false }
		return fit_value, true
	case .Percentage:
		return current, false
	}
	return current, false
}

// resolve_sizing lowers fixed declarations to the existing style fields.
// Supplying a second, conflicting value in the base style is rejected; callers
// can use base for padding, gap, direction and alignment without maintaining
// two competing size declarations. Bounds accept fixed logical values only.
// Percentage declarations need a description-time parent and are handled by
// the scoped layout_sized UI helper instead.
resolve_sizing :: proc(base: Layout_Style, declaration: Sizing) -> (Layout_Style, bool) {
	result := base
	valid: bool
	result.width, valid = resolve_size_input(declaration.width, base.width, -1, alicorn.LAYOUT_SIZE_FIT_CONTENT, false)
	if !valid { return base, false }
	result.height, valid = resolve_size_input(declaration.height, base.height, -1, alicorn.LAYOUT_SIZE_FIT_CONTENT, true)
	if !valid { return base, false }
	result.min_width, valid = resolve_size_input(declaration.min_width, base.min_width, 0, alicorn.LAYOUT_SIZE_FIT_CONTENT, false)
	if !valid { return base, false }
	result.max_width, valid = resolve_size_input(declaration.max_width, base.max_width, -1, alicorn.LAYOUT_SIZE_FIT_CONTENT, false)
	if !valid { return base, false }
	result.min_height, valid = resolve_size_input(declaration.min_height, base.min_height, 0, alicorn.LAYOUT_SIZE_FIT_CONTENT, false)
	if !valid { return base, false }
	result.max_height, valid = resolve_size_input(declaration.max_height, base.max_height, -1, alicorn.LAYOUT_SIZE_FIT_CONTENT, false)
	if !valid { return base, false }
	if declaration.grow.defined {
		weight := declaration.grow.weight
		if math.is_nan(weight) || math.is_inf(weight) || weight <= 0 { return base, false }
		if base.grow > 0 && base.grow != weight { return base, false }
		result.grow = weight
	}
	if result.max_width >= 0 && result.min_width > result.max_width { return base, false }
	if result.max_height >= 0 && result.min_height > result.max_height { return base, false }
	return result, true
}

// sizing_layout builds an ordinary Layout_Style from a typed declaration and
// the non-sizing layout properties. Invalid or conflicting declarations
// return valid=false and a default style; callers should handle that result.
sizing_layout :: proc(
	direction: Layout_Direction = .Column,
	declaration: Sizing = {},
	padding: f32 = 0,
	gap: f32 = 0,
	align: Align = .Stretch,
	justify: Main_Axis_Distribution = .Start,
	clip: bool = false,
) -> (Layout_Style, bool) {
	base := alicorn.layout_style(direction, padding=padding, gap=gap, align=align, justify=justify, clip=clip)
	return resolve_sizing(base, declaration)
}
