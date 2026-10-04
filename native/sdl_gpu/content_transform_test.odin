package alicorn_sdl_gpu

import "core:testing"
import alicorn "../../runtime"

@(test)
test_integrated_chrome_maps_window_input_to_application_space :: proc(t: ^testing.T) {
	transform := native_content_transform_make(800, 32)
	testing.expect(t, transform.window_height == 800, "window space should retain the full client height")
	testing.expect(t, transform.app_height == 768, "application viewport should exclude the chrome inset")
	testing.expect(t, transform.inset_top == 32, "transform should retain the host chrome height")

	x, y, inside := native_application_point_from_window(transform, 17, 32)
	testing.expect(t, inside, "the first application pixel should be inside the app viewport")
	testing.expect(t, x == 17 && y == 0, "the first application pixel should map to app origin")

	_, _, inside = native_application_point_from_window(transform, 17, 31)
	testing.expect(t, !inside, "pointer input over host chrome must not reach the application")

	x, y, inside = native_application_point_from_window(transform, 17, 40)
	testing.expect(t, inside && x == 17 && y == 8, "window-space pointer coordinates should subtract the chrome inset once")
}

@(test)
test_integrated_chrome_maps_application_geometry_to_window_space_once :: proc(t: ^testing.T) {
	transform := native_content_transform_make(800, 32)
	app_rect := alicorn.Rect{12, 24, 80, 18}
	window_rect := native_application_rect_to_window(transform, app_rect)
	testing.expect(t, window_rect.x == app_rect.x && window_rect.y == 56,
		"native geometry should add the chrome inset exactly once")
	testing.expect(t, window_rect.w == app_rect.w && window_rect.h == app_rect.h,
		"coordinate conversion should preserve the geometry extent")

	zero_inset := native_content_transform_make(800, 0)
	identity_rect := native_application_rect_to_window(zero_inset, app_rect)
	testing.expect(t, identity_rect == app_rect, "system-decorated windows should keep identity app/window geometry")
}

@(test)
test_integrated_chrome_transform_clamps_invalid_insets :: proc(t: ^testing.T) {
	negative := native_content_transform_make(800, -12)
	testing.expect(t, negative.inset_top == 0 && negative.app_height == 800,
		"negative chrome metrics should clamp to an identity transform")

	oversized := native_content_transform_make(800, 900)
	testing.expect(t, oversized.inset_top == 800 && oversized.app_height == 1,
		"oversized chrome should preserve a minimal positive app viewport for window metric validation")
	_, _, inside := native_application_point_from_window(oversized, 0, 800)
	testing.expect(t, !inside, "a fully-inset window should not dispatch any point to the application")

	zero_height := native_content_transform_make(0, 32)
	testing.expect(t, zero_height.app_height == 0,
		"a minimized or unavailable zero-height window should remain invalid")
}
