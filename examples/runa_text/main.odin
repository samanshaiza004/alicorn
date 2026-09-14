package main

import "core:fmt"
import "core:os"
import alicorn "../../runtime"

main :: proc() {
	if len(os.args) < 2 {
		fmt.eprintln("usage: runa_text <font.ttf>")
		os.exit(2)
	}
	data, err := os.read_entire_file_from_path(os.args[1], context.allocator)
	if err != nil {
		fmt.eprintln("font read failed:", err)
		os.exit(1)
	}
	defer delete(data)

	engine := alicorn.new_text_engine("Runa")
	if !alicorn.text_engine_load_font(&engine, data) {
		fmt.eprintln("Runa font_load failed")
		os.exit(1)
	}
	width, height, glyphs, ok := alicorn.text_layout(&engine, "office — Alicorn", 24)
	if !ok {
		fmt.eprintln("Runa paragraph layout failed")
		os.exit(1)
	}
	_, one_line_height, _, one_line_ok := alicorn.text_layout(&engine, "one", 24)
	_, multiline_height, multiline_glyphs, multiline_ok := alicorn.text_layout(&engine, "one\ntwo\nthree", 24)
	_, wrapped_height, wrapped_glyphs, wrapped_ok := alicorn.text_layout(&engine, "one two three four five", 24, 70)
	if !one_line_ok || !multiline_ok || !wrapped_ok || multiline_height <= one_line_height || wrapped_height <= one_line_height {
		fmt.eprintln("Runa multiline/wrap metrics failed", "one", one_line_height, "multi", multiline_height, "wrapped", wrapped_height)
		os.exit(1)
	}
	first_cache_size := alicorn.runa_cache_size(&engine)
	_, _, _, _ = alicorn.text_layout(&engine, "office — Alicorn", 24)
	second_cache_size := alicorn.runa_cache_size(&engine)
	fmt.println("Runa text proof: PASS", "width", width, "height", height, "glyphs", glyphs, "multiline_height", multiline_height, "multiline_glyphs", multiline_glyphs, "wrapped_height", wrapped_height, "wrapped_glyphs", wrapped_glyphs, "cache", first_cache_size, "->", second_cache_size)
	alicorn.text_engine_destroy(&engine)
}
