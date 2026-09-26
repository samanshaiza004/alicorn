package alicorn_sdl_gpu

import "core:testing"
import alicorn "../../runtime"
import "vendor:sdl3"

render_keyboard_control_test :: proc(
	rt: ^alicorn.Runtime,
	checked: bool,
	value: f32,
) -> (checkbox_id, slider_id: alicorn.Node_ID, checkbox_change: alicorn.Control_Change_Bool, slider_change: alicorn.Control_Change_F32) {
	alicorn.invalidate_root(rt, "native widget keyboard routing test")
	ui, should_build := alicorn.begin_frame(rt)
	if !should_build { return }
	alicorn.container_begin(&ui, .Root, label="widget-keyboard-test")
	checkbox_change = alicorn.checkbox(&ui, "Enabled", checked, key=alicorn.key_string("enabled"))
	slider_change = alicorn.slider_f32(&ui, "Level", value, 0, 1, 0.25, key=alicorn.key_string("level"))
	alicorn.container_end(&ui)
	alicorn.end_frame(&ui)
	for id in rt.order {
		if node, ok := rt.nodes[id]; ok {
			if node.kind == .Checkbox { checkbox_id = id }
			if node.kind == .Slider { slider_id = id }
		}
	}
	return
}

@(test)
test_focused_widget_keyboard_conventions :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 160})
	defer alicorn.destroy_runtime(&rt)
	checkbox_id, slider_id, _, _ := render_keyboard_control_test(&rt, false, 0.5)
	testing.expect(t, checkbox_id != 0 && slider_id != 0, "keyboard fixture should emit checkbox and slider")

	testing.expect(t, alicorn.focus(&rt, slider_id), "slider should accept focus")
	testing.expect(t, native_route_focused_control_key(&rt, sdl3.K_DOWN), "Down should be consumed as slider decrement")
	_, _, _, slider_change := render_keyboard_control_test(&rt, false, 0.5)
	testing.expect(t, slider_change.value == 0.25, "Down should decrease by one step")
	testing.expect(t, native_route_focused_control_key(&rt, sdl3.K_UP), "Up should be consumed as slider increment")
	_, _, _, slider_change = render_keyboard_control_test(&rt, false, slider_change.value)
	testing.expect(t, slider_change.value == 0.5, "Up should increase by one step")
	testing.expect(t, native_route_focused_control_key(&rt, sdl3.K_HOME), "Home should be consumed by a focused slider")
	_, _, _, slider_change = render_keyboard_control_test(&rt, false, slider_change.value)
	testing.expect(t, slider_change.value == 0, "Home should move to the minimum")
	testing.expect(t, native_route_focused_control_key(&rt, sdl3.K_END), "End should be consumed by a focused slider")
	_, _, _, slider_change = render_keyboard_control_test(&rt, false, slider_change.value)
	testing.expect(t, slider_change.value == 1, "End should move to the maximum")

	testing.expect(t, alicorn.focus(&rt, checkbox_id), "checkbox should accept focus")
	testing.expect(t, !native_route_focused_control_key(&rt, sdl3.K_RETURN), "Enter should not toggle a checkbox")
	_, _, checkbox_change, _ := render_keyboard_control_test(&rt, false, 1)
	testing.expect(t, !checkbox_change.changed && !checkbox_change.value, "Enter should leave checkbox state unchanged")
	testing.expect(t, native_route_focused_control_key(&rt, sdl3.K_SPACE), "Space should toggle a checkbox")
	_, _, checkbox_change, _ = render_keyboard_control_test(&rt, false, 1)
	testing.expect(t, checkbox_change.changed && checkbox_change.value, "Space should report the checked value")
}
