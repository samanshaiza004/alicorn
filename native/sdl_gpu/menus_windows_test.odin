#+build windows

package alicorn_sdl_gpu

import "core:testing"
import win "core:sys/windows"
import alicorn "../../runtime"

@(test)
test_win32_chrome_uses_theme_colors_and_respects_high_contrast :: proc(t: ^testing.T) {
	appearance := Window_Chrome_Appearance{
		defined=true,
		background=alicorn.Color{0.18, 0.22, 0.28, 1},
		foreground=alicorn.Color{0.9, 0.92, 0.96, 1},
	}
	menu := Native_Menu_Runtime{chrome_appearance=appearance}
	state := Win32_Menu_State{menu=&menu, active=true}
	background, foreground := win32_menu_chrome_colors(&state)
	testing.expect(t, background == appearance.background && foreground == appearance.foreground,
		"normal integrated chrome should use the app's resolved theme appearance")

	state.active = false
	background, foreground = win32_menu_chrome_colors(&state)
	testing.expect(t, background == appearance.background &&
		foreground == win32_color_mix(appearance.background, appearance.foreground, 0.72),
		"inactive themed chrome should retain its surface with softer foreground contrast")

	state.high_contrast = true
	background, foreground = win32_menu_chrome_colors(&state)
	testing.expect(t,
		background == win32_color_ref(win.GetSysColor(win.COLOR_MENU)) &&
		foreground == win32_color_ref(win.GetSysColor(win.COLOR_MENUTEXT)),
		"high contrast should use the Windows system menu palette instead of app colors")
}
