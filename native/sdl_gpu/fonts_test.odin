package alicorn_sdl_gpu

import "core:os"
import "core:testing"
import alicorn "../../runtime"

@(test)
test_optional_fallback_rejects_missing_font :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 120})
	defer alicorn.destroy_runtime(&rt)
	testing.expect(t, !native_load_optional_fallback_font(
		&rt,
		.UI,
		"/font-that-does-not-exist-for-alicorn-test.ttf",
		NATIVE_FALLBACK_CODEPOINTS[:],
	), "an unavailable fallback path must remain optional")
}

@(test)
test_linux_fontconfig_fallback_covers_ui_symbols :: proc(t: ^testing.T) {
	when ODIN_OS == .Linux {
		path := native_ui_fallback_font_path()
		if path == "" {
			testing.expect(t, !native_fontconfig_initialize(), "Fontconfig absence should be the only reason Linux fallback discovery is empty")
			return
		}
		data, err := os.read_entire_file_from_path(path, context.allocator)
		defer delete(data)
		testing.expect(t, err == nil && native_font_data_covers(data, NATIVE_FALLBACK_CODEPOINTS[:]),
			"Fontconfig must resolve a readable font containing every UI fallback symbol")

		rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 120})
		defer alicorn.destroy_runtime(&rt)
		testing.expect(t, alicorn.text_engine_load_font(&rt.text_engine, NATIVE_UI_FONT_DATA),
			"the bundled UI face should load for the fallback fixture")
		testing.expect(t, native_load_optional_fallback_font(&rt, .UI, path, NATIVE_FALLBACK_CODEPOINTS[:]),
			"the resolved Fontconfig face should load through the native fallback path")
		run, ok := alicorn.text_run_build(&rt.text_engine, "ABC ↑ ↓ → ← × —", 16, allocator=context.allocator)
		defer if ok { alicorn.text_run_destroy(&run) }
		testing.expect(t, ok && run.font_source == .Fallback && len(run.glyphs) == 15,
			"a run containing missing arrows should select the verified fallback face")
	}
}
