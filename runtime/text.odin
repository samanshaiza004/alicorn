package alicorn

import runa "../third_party/Runa"

// Text_Engine is intentionally a narrow seam. The runtime owns GUI concerns
// while a provider owns shaping, bidi, segmentation, line breaking and glyph
// rasterization. Runa is the foundation provider; its atlas remains behind
// this GUI-facing abstraction.
Text_Engine :: struct {
	name:          string,
	available:     bool,
	shaped_runs:   u64,
	cache_hits:    u64,
	font_data:     []u8,
	font:          runa.Font,
	cache:         runa.Cache,
	font_loaded:   bool,
	cache_initialized: bool,
}

new_text_engine :: proc(name := "unconfigured", available := false) -> Text_Engine {
	return Text_Engine{name=owned(name), available=available, cache=runa.cache_make(), cache_initialized=true}
}

text_engine_load_font :: proc(engine: ^Text_Engine, data: []u8) -> bool {
	if len(data) == 0 { return false }
	copy_data := make([]u8, len(data))
	copy(copy_data, data)
	font, err := runa.font_load(copy_data)
	if err != .None {
		delete(copy_data)
		return false
	}
	if engine.cache_initialized {
		runa.cache_destroy(&engine.cache)
	}
	if engine.font_loaded {
		runa.font_destroy(&engine.font)
		delete(engine.font_data)
	}
	engine.font_data = copy_data
	engine.font = font
	engine.cache = runa.cache_make()
	engine.cache_initialized = true
	engine.font_loaded = true
	engine.available = true
	return true
}

text_engine_destroy :: proc(engine: ^Text_Engine) {
	if engine.cache_initialized {
		runa.cache_destroy(&engine.cache)
	}
	if engine.font_loaded {
		runa.font_destroy(&engine.font)
	}
	delete(engine.font_data)
	if len(engine.name) > 0 { delete(engine.name) }
	engine^ = {}
}

runa_cache_size :: proc(engine: ^Text_Engine) -> int {
	if !engine.font_loaded { return 0 }
	return runa.cache_size(&engine.cache)
}

text_layout :: proc(engine: ^Text_Engine, value: string, size: f32) -> (width, height: f32, glyphs: int, ok: bool) {
	if !engine.font_loaded || size <= 0 { return }
	stack := runa.Font_Stack{&engine.font}
	opts := runa.Paragraph_Opts{fonts=stack, size=size, direction=.Auto, align=.Start}
	lines, err := runa.layout_paragraph(value, opts, &engine.cache)
	if err != .None { return }
	defer {
		for i := 0; i < len(lines); i += 1 { runa.line_destroy(&lines[i]) }
		delete(lines)
	}
	for line in lines {
		if line.width > width { width = line.width }
		if line.height > height { height = line.height }
		glyphs += len(line.glyphs)
	}
	ok = true
	return
}

text_shape :: proc(engine: ^Text_Engine, value: string, changed: bool) {
	if !engine.font_loaded {
		if engine.available {
			if changed { engine.shaped_runs += 1 } else { engine.cache_hits += 1 }
		}
		return
	}
	_, _, _, ok := text_layout(engine, value, 16)
	if !ok { return }
	if changed { engine.shaped_runs += 1 } else { engine.cache_hits += 1 }
}
