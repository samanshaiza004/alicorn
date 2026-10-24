package alicorn_sdl_gpu

import alicorn "../../runtime"

import "core:os"
import runa "../../third_party/Runa"

// Alicorn's native host embeds its default faces so apps do not depend on
// system-installed fonts or the process working directory.
NATIVE_UI_FONT_DATA :: #load("../../assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf")
NATIVE_UI_ITALIC_FONT_DATA :: #load("../../assets/fonts/AtkinsonHyperlegibleNext-Italic-Variable.ttf")
NATIVE_MONO_FONT_DATA :: #load("../../assets/fonts/AtkinsonHyperlegibleMono-Variable.ttf")
NATIVE_MONO_ITALIC_FONT_DATA :: #load("../../assets/fonts/AtkinsonHyperlegibleMono-Italic-Variable.ttf")

NATIVE_FALLBACK_CODEPOINTS := [?]rune{'↑', '↓', '→', '←', '×', '—'}

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
		return native_fontconfig_find_font("sans-serif", NATIVE_FALLBACK_CODEPOINTS[:])
	}
}

native_monospace_fallback_font_path :: proc() -> string {
	when ODIN_OS == .Windows {
		return "C:/Windows/Fonts/consola.ttf"
	} else when ODIN_OS == .Darwin {
		return "/System/Library/Fonts/SFNSMono.ttf"
	} else {
		return native_fontconfig_find_font("monospace", NATIVE_FALLBACK_CODEPOINTS[:])
	}
}

native_font_data_covers :: proc(data: []u8, codepoints: []rune) -> bool {
	if len(data) == 0 || len(codepoints) == 0 { return false }
	font, err := runa.font_load(data, context.temp_allocator)
	if err != .None { return false }
	defer runa.font_destroy(&font)
	for codepoint in codepoints {
		if runa.font_lookup_glyph(&font, codepoint) == 0 { return false }
	}
	return true
}

native_load_optional_fallback_font :: proc(
	rt: ^alicorn.Runtime,
	role: alicorn.Font_Role,
	path: string,
	required_codepoints: []rune = nil,
) -> bool {
	if !os.exists(path) { return false }
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil { return false }
	defer delete(data)
	if len(required_codepoints) > 0 && !native_font_data_covers(data, required_codepoints) { return false }
	return alicorn.text_engine_load_fallback_font_role(&rt.text_engine, role, data)
}

native_load_default_fonts :: proc(rt: ^alicorn.Runtime) -> bool {
	if !rt.text_engine.font_loaded && !alicorn.text_engine_load_font(&rt.text_engine, NATIVE_UI_FONT_DATA) { return false }
	if !rt.text_engine.monospace_font_loaded && !alicorn.text_engine_load_font_role(&rt.text_engine, .Monospace, NATIVE_MONO_FONT_DATA) { return false }
	if !rt.text_engine.italic_font_loaded && !rt.text_engine.application_primary_font[.UI] && !alicorn.text_engine_load_italic_font_role(&rt.text_engine, .UI, NATIVE_UI_ITALIC_FONT_DATA) { return false }
	if !rt.text_engine.monospace_italic_font_loaded && !rt.text_engine.application_primary_font[.Monospace] && !alicorn.text_engine_load_italic_font_role(&rt.text_engine, .Monospace, NATIVE_MONO_ITALIC_FONT_DATA) { return false }
	// System faces are optional, script-oriented fallbacks; they do not alter
	// the bundled primary typography for text the default face can render.
	if !rt.text_engine.fallback_font_loaded && !rt.text_engine.application_fallback_font[.UI] {
		_ = native_load_optional_fallback_font(rt, .UI, native_ui_fallback_font_path(), NATIVE_FALLBACK_CODEPOINTS[:])
	}
	if !rt.text_engine.monospace_fallback_font_loaded && !rt.text_engine.application_fallback_font[.Monospace] {
		_ = native_load_optional_fallback_font(rt, .Monospace, native_monospace_fallback_font_path(), NATIVE_FALLBACK_CODEPOINTS[:])
	}
	return true
}
