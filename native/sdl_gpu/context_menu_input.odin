package alicorn_sdl_gpu

import alicorn "../../runtime"
import "vendor:sdl3"

native_context_menu_key_from_sdl :: proc(key: sdl3.Keycode) -> alicorn.Context_Menu_Key {
	switch key {
	case sdl3.K_UP: return .Up
	case sdl3.K_DOWN: return .Down
	case sdl3.K_HOME: return .Home
	case sdl3.K_END: return .End
	case sdl3.K_RETURN, sdl3.K_KP_ENTER, sdl3.K_SPACE: return .Activate
	case sdl3.K_ESCAPE: return .Cancel
	case: return .Other
	}
}
