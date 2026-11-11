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
		primary_glyphs, fallback_glyphs := 0, 0
		if ok {
			for glyph in run.glyphs {
				if glyph.font_source == .Fallback { fallback_glyphs += 1 }
				else { primary_glyphs += 1 }
			}
		}
		testing.expect(t, ok && run.font_source == .Fallback && len(run.glyphs) == 15 && primary_glyphs > 0 && fallback_glyphs > 0,
			"mixed text should retain primary glyphs while selecting the verified fallback only for missing symbols")
	}
}

@(test)
test_windows_directwrite_cjk_fallback_and_color_emoji :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		rt := alicorn.new_runtime(alicorn.Rect{0, 0, 320, 120})
		defer alicorn.destroy_runtime(&rt)
		testing.expect(t, native_load_default_fonts(&rt), "Windows primary font initialization should succeed")
		testing.expect(t, alicorn.text_engine_registered_font_face_count(&rt.text_engine) > 0,
			"DirectWrite should register supported system fallback faces")

		value := "日本語 🎉"
		run, ok := alicorn.text_run_build(&rt.text_engine, value, 20, font_role=.Monospace)
		defer if ok { alicorn.text_run_destroy(&run) }
		japanese_fallback_glyphs := 0
		color_emoji_slot := false
		emoji_start := len("日本語 ")
		if ok {
			for glyph in run.glyphs {
				if glyph.cluster_start < emoji_start && glyph.font_face != 0 { japanese_fallback_glyphs += 1 }
				if glyph.cluster_start == emoji_start && glyph.font_face != 0 {
					slot, drawable, glyph_ok := alicorn.text_engine_glyph(
						&rt.text_engine, glyph.glyph_id, run.size,
						font_role=.Monospace,
						font_source=glyph.font_source,
						font_weight=glyph.font_weight,
						italic=glyph.italic,
						face_id=glyph.font_face,
					)
					color_emoji_slot = glyph_ok && drawable && slot.is_color
				}
			}
		}
		testing.expect(t, ok && japanese_fallback_glyphs > 0,
			"Japanese text should select a registered DirectWrite fallback face")
		testing.expect(t, color_emoji_slot,
			"the mapped Windows emoji face should rasterize emoji into the RGBA atlas")
	}
}
