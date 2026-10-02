package alicorn_sdl_gpu

import alicorn "../../runtime"

import "core:os"

// Alicorn's native host embeds its default faces so apps do not depend on
// system-installed fonts or the process working directory.
NATIVE_UI_FONT_DATA :: #load("../../assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf")
NATIVE_UI_ITALIC_FONT_DATA :: #load("../../assets/fonts/AtkinsonHyperlegibleNext-Italic-Variable.ttf")
NATIVE_MONO_FONT_DATA :: #load("../../assets/fonts/AtkinsonHyperlegibleMono-Variable.ttf")
NATIVE_MONO_ITALIC_FONT_DATA :: #load("../../assets/fonts/AtkinsonHyperlegibleMono-Italic-Variable.ttf")

native_ui_fallback_font_path :: proc() -> string {
	when ODIN_OS == .Windows {
		// Keep the previous broad Windows fallback for Japanese and other glyphs
		// outside the bundled Latin-focused default face.
		japanese_font := "C:/Windows/Fonts/NotoSansJP-VF.ttf"
		if os.exists(japanese_font) { return japanese_font }
		return "C:/Windows/Fonts/segoeui.ttf"
	} else when ODIN_OS == .Darwin {
		return "/System/Library/Fonts/SFNS.ttf"
	} else {
		return "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
	}
}

native_monospace_fallback_font_path :: proc() -> string {
	when ODIN_OS == .Windows {
		return "C:/Windows/Fonts/consola.ttf"
	} else when ODIN_OS == .Darwin {
		return "/System/Library/Fonts/SFNSMono.ttf"
	} else {
		return "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
	}
}

native_load_optional_fallback_font :: proc(rt: ^alicorn.Runtime, role: alicorn.Font_Role, path: string) -> bool {
	if !os.exists(path) { return false }
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil { return false }
	defer delete(data)
	return alicorn.text_engine_load_fallback_font_role(&rt.text_engine, role, data)
}

native_load_default_fonts :: proc(rt: ^alicorn.Runtime) -> bool {
	if !alicorn.text_engine_load_font(&rt.text_engine, NATIVE_UI_FONT_DATA) { return false }
	if !alicorn.text_engine_load_font_role(&rt.text_engine, .Monospace, NATIVE_MONO_FONT_DATA) { return false }
	if !alicorn.text_engine_load_italic_font_role(&rt.text_engine, .UI, NATIVE_UI_ITALIC_FONT_DATA) { return false }
	if !alicorn.text_engine_load_italic_font_role(&rt.text_engine, .Monospace, NATIVE_MONO_ITALIC_FONT_DATA) { return false }
	// System faces are optional, script-oriented fallbacks; they do not alter
	// the bundled primary typography for text the default face can render.
	_ = native_load_optional_fallback_font(rt, .UI, native_ui_fallback_font_path())
	_ = native_load_optional_fallback_font(rt, .Monospace, native_monospace_fallback_font_path())
	return true
}
