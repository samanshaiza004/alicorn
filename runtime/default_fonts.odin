package alicorn

// Runtime and headless application hosts use the same bundled primary faces.
// Platform-specific fallback fonts remain the responsibility of native hosts.
DEFAULT_UI_FONT_DATA :: #load("../assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf")
DEFAULT_UI_ITALIC_FONT_DATA :: #load("../assets/fonts/AtkinsonHyperlegibleNext-Italic-Variable.ttf")
DEFAULT_MONO_FONT_DATA :: #load("../assets/fonts/AtkinsonHyperlegibleMono-Variable.ttf")
DEFAULT_MONO_ITALIC_FONT_DATA :: #load("../assets/fonts/AtkinsonHyperlegibleMono-Italic-Variable.ttf")

text_engine_load_default_fonts :: proc(rt: ^Runtime) -> bool {
	if rt == nil { return false }
	if !rt.text_engine.font_loaded && !text_engine_load_font(&rt.text_engine, DEFAULT_UI_FONT_DATA) { return false }
	if !rt.text_engine.monospace_font_loaded && !text_engine_load_font_role(&rt.text_engine, .Monospace, DEFAULT_MONO_FONT_DATA) { return false }
	if !rt.text_engine.italic_font_loaded && !rt.text_engine.application_primary_font[.UI] &&
	   !text_engine_load_italic_font_role(&rt.text_engine, .UI, DEFAULT_UI_ITALIC_FONT_DATA) { return false }
	if !rt.text_engine.monospace_italic_font_loaded && !rt.text_engine.application_primary_font[.Monospace] &&
	   !text_engine_load_italic_font_role(&rt.text_engine, .Monospace, DEFAULT_MONO_ITALIC_FONT_DATA) { return false }
	return true
}
