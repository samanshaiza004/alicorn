package alicorn

import "core:math"

// number_is_finite is shared by numeric validation paths for both f32 and f64.
number_is_finite :: proc(value: $T) -> bool {
	return !math.is_nan(value) && !math.is_inf(value)
}
