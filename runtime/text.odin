package alicorn

import "core:mem"
import "core:strings"
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
	shape_calls:   u64,
	glyph_cache_hits: u64,
	glyph_cache_misses: u64,
	glyph_rasterizations: u64,
	font_data:     []u8,
	font:          runa.Font,
	cache:         runa.Cache,
	font_loaded:   bool,
	cache_initialized: bool,
	font_generation: u64,
	atlas:         runa.Atlas,
	atlas_initialized: bool,
	glyphs:        map[Glyph_Resource_Key]runa.Atlas_Slot,
}

// Glyph_Resource_Key is the CPU-side identity of one rasterized glyph. It is
// deliberately independent of an SDL_GPU texture pointer: GPU residency can
// be recreated after device loss or page retirement without changing the
// logical glyph resource identity.
Glyph_Resource_Key :: struct {
	font_generation: u64,
	glyph_id:        runa.Glyph_ID,
	size_bits:       u32,
	subpixel_bucket: u8,
	hint:            bool,
	is_color:        bool,
}

Text_Glyph :: struct {
	glyph_id:  runa.Glyph_ID,
	cluster:   u32,
	x, y:      f32,
	x_advance: f32,
	y_advance: f32,
	x_offset:  f32,
	y_offset:  f32,
	level:     u8,
	slot:      runa.Atlas_Slot,
	drawable:  bool,
}

// Text_Run is an Alicorn-owned retained product. It copies all placement
// data out of Runa's paragraph lines; in particular it never retains Runa's
// non-owning Paragraph_Glyph.font pointer.
Text_Run :: struct {
	value:       string,
	glyphs:      [dynamic]Text_Glyph,
	width:       f32,
	height:      f32,
	size:        f32,
	max_width:   f32,
	font_generation: u64,
	allocator:   mem.Allocator,
}

new_text_engine :: proc(name := "unconfigured", available := false) -> Text_Engine {
	return Text_Engine{
		name=owned(name), available=available,
		cache=runa.cache_make(), cache_initialized=true,
		atlas=runa.atlas_make(1024, 1024), atlas_initialized=true,
		glyphs=make(map[Glyph_Resource_Key]runa.Atlas_Slot),
	}
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
	if engine.atlas_initialized {
		runa.atlas_destroy(&engine.atlas)
	}
	if engine.glyphs != nil {
		delete(engine.glyphs)
	}
	if engine.font_loaded {
		runa.font_destroy(&engine.font)
		delete(engine.font_data)
	}
	engine.font_data = copy_data
	engine.font = font
	engine.cache = runa.cache_make()
	engine.cache_initialized = true
	engine.atlas = runa.atlas_make(1024, 1024)
	engine.atlas_initialized = true
	engine.glyphs = make(map[Glyph_Resource_Key]runa.Atlas_Slot)
	engine.font_generation += 1
	engine.font_loaded = true
	engine.available = true
	return true
}

text_engine_destroy :: proc(engine: ^Text_Engine) {
	if engine.cache_initialized {
		runa.cache_destroy(&engine.cache)
	}
	if engine.atlas_initialized {
		runa.atlas_destroy(&engine.atlas)
	}
	if engine.glyphs != nil {
		delete(engine.glyphs)
	}
	if engine.font_loaded {
		runa.font_destroy(&engine.font)
	}
	delete(engine.font_data)
	if len(engine.name) > 0 { delete(engine.name) }
	engine^ = {}
}

text_engine_glyph :: proc(engine: ^Text_Engine, glyph_id: runa.Glyph_ID, size: f32, subpixel_bucket: u8 = 0, hint: bool = true) -> (slot: runa.Atlas_Slot, drawable, ok: bool) {
	if !engine.font_loaded || size <= 0 { return }
	is_color := runa.font_has_color_layers(&engine.font, glyph_id)
	key := Glyph_Resource_Key{
		font_generation = engine.font_generation,
		glyph_id = glyph_id,
		size_bits = transmute(u32)size,
		subpixel_bucket = subpixel_bucket & 3,
		hint = hint,
		is_color = is_color,
	}
	if cached, found := engine.glyphs[key]; found {
		engine.glyph_cache_hits += 1
		return cached, cached.px_size[0] > 0 && cached.px_size[1] > 0, true
	}
	engine.glyph_cache_misses += 1
	err: runa.Error
	slot, err = runa.raster_glyph(&engine.font, glyph_id, size, key.subpixel_bucket, &engine.atlas, hint=hint)
	if err != .None { return runa.Atlas_Slot{}, false, false }
	engine.glyphs[key] = slot
	engine.glyph_rasterizations += 1
	drawable = slot.px_size[0] > 0 && slot.px_size[1] > 0
	ok = true
	return
}

text_run_destroy :: proc(run: ^Text_Run) {
	if run.allocator.procedure != nil {
		if len(run.value) > 0 { delete(run.value, run.allocator) }
		delete(run.glyphs)
	} else {
		if len(run.value) > 0 { delete(run.value) }
		delete(run.glyphs)
	}
	run^ = {}
}

// text_run_build shapes and raster-cache-resolves a complete paragraph. The
// returned product is safe to retain after Runa destroys its temporary Line
// values. Coordinates are in the same logical units as the requested size;
// a later GPU adapter may choose a physical-pixel raster policy and include
// that scale in its own key.
text_run_build :: proc(engine: ^Text_Engine, value: string, size: f32, max_width: f32 = 0, allocator := context.allocator) -> (run: Text_Run, ok: bool) {
	if !engine.font_loaded || size <= 0 { return }
	stack := runa.Font_Stack{&engine.font}
	opts := runa.Paragraph_Opts{fonts=stack, size=size, direction=.Auto, align=.Start, max_width=max_width}
	lines, err := runa.layout_paragraph(value, opts, &engine.cache, allocator=allocator)
	if err != .None { return }
	defer {
		for i := 0; i < len(lines); i += 1 { runa.line_destroy(&lines[i], allocator) }
		delete(lines, allocator)
	}
	value_copy, clone_err := strings.clone(value, allocator)
	if clone_err != nil { return Text_Run{}, false }
	run.value = value_copy
	run.glyphs = make([dynamic]Text_Glyph, 0, 32, allocator)
	run.size = size
	run.max_width = max_width
	run.font_generation = engine.font_generation
	run.allocator = allocator
	for line, line_index in lines {
		if line.width > run.width { run.width = line.width }
		run.height += line.height
		pen_x: f32 = 0
		for glyph in line.glyphs {
			slot, drawable, glyph_ok := text_engine_glyph(engine, glyph.glyph_id, size)
			if !glyph_ok { text_run_destroy(&run); return Text_Run{}, false }
			append(&run.glyphs, Text_Glyph{
				glyph_id=glyph.glyph_id,
				cluster=glyph.cluster,
				x=pen_x + glyph.x_offset,
				y=f32(line_index) * line.height + line.baseline + glyph.y_offset,
				x_advance=glyph.x_advance,
				y_advance=glyph.y_advance,
				x_offset=glyph.x_offset,
				y_offset=glyph.y_offset,
				level=glyph.level,
				slot=slot,
				drawable=drawable,
			})
			pen_x += glyph.x_advance
		}
	}
	engine.shape_calls += 1
	ok = true
	return
}

runa_cache_size :: proc(engine: ^Text_Engine) -> int {
	if !engine.font_loaded { return 0 }
	return runa.cache_size(&engine.cache)
}

// These are the text abstraction's editing boundaries. The runtime stores
// byte offsets because strings are byte-addressed, but callers cannot create
// a caret inside an extended grapheme cluster.
grapheme_floor_boundary :: proc(value: string, byte_index: int) -> int {
	if byte_index <= 0 { return 0 }
	if byte_index >= len(value) { return len(value) }
	last := 0
	it := runa.grapheme_iter_make(value)
	for {
		lo, hi, ok := runa.grapheme_iter_next(&it)
		if !ok { break }
		if byte_index < hi { return lo }
		last = hi
	}
	return last
}

grapheme_ceil_boundary :: proc(value: string, byte_index: int) -> int {
	if byte_index <= 0 { return 0 }
	if byte_index >= len(value) { return len(value) }
	it := runa.grapheme_iter_make(value)
	for {
		lo, hi, ok := runa.grapheme_iter_next(&it)
		if !ok { break }
		if byte_index <= lo { return lo }
		if byte_index < hi { return hi }
	}
	return len(value)
}

text_layout :: proc(engine: ^Text_Engine, value: string, size: f32, max_width: f32 = 0) -> (width, height: f32, glyphs: int, ok: bool) {
	if !engine.font_loaded || size <= 0 { return }
	stack := runa.Font_Stack{&engine.font}
	opts := runa.Paragraph_Opts{fonts=stack, size=size, direction=.Auto, align=.Start, max_width=max_width}
	lines, err := runa.layout_paragraph(value, opts, &engine.cache)
	if err != .None { return }
	defer {
		for i := 0; i < len(lines); i += 1 { runa.line_destroy(&lines[i]) }
		delete(lines)
	}
	for line in lines {
		if line.width > width { width = line.width }
		height += line.height
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
