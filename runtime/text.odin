#+vet explicit-allocators
package alicorn

import "core:mem"
import "core:strings"
import runa "../third_party/Runa"

// Text_Engine is intentionally a narrow seam. The runtime owns GUI concerns
// while a provider owns shaping, bidi, segmentation, line breaking and glyph
// rasterization. Runa is the foundation provider; its atlas remains behind
// this GUI-facing abstraction.
Text_Engine :: struct {
	allocator:      mem.Allocator,
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
	glyph_id:       runa.Glyph_ID,
	cluster_start:  int,
	cluster_end:    int,
	x, y:           f32,
	x_advance:      f32,
	y_advance:      f32,
	x_offset:       f32,
	y_offset:       f32,
	line_index:     int,
	level:          u8,
}

Text_Line :: struct {
	glyph_start: int,
	glyph_end:   int,
	byte_start:  int,
	byte_end:    int,
	x, y:        f32,
	width:       f32,
	height:      f32,
	baseline:    f32,
}

Text_Affinity :: enum {
	Leading,
	Trailing,
}

// Text_Position uses the application's byte-addressed string model while
// affinity disambiguates a boundary shared by adjacent visual runs or lines.
// Callers should only construct positions at grapheme boundaries; the public
// helpers normalize arbitrary byte offsets before using them.
Text_Position :: struct {
	byte:     int,
	affinity: Text_Affinity,
}

Text_Caret_Geometry :: struct {
	position:   Text_Position,
	line_index: int,
	rect:       Rect,
	valid:      bool,
}

Text_Selection_Rect :: struct {
	line_index: int,
	rect:       Rect,
}

Text_Caret_Point :: struct {
	position:   Text_Position,
	line_index: int,
	x:          f32,
}

// Text_Run is an Alicorn-owned logical typography product. It copies all
// placement data out of Runa's paragraph lines; in particular it never retains
// Runa's non-owning Paragraph_Glyph.font pointer or a physical atlas slot.
// Physical glyph residency is resolved later by the platform renderer for its
// actual DPI and raster policy.
Text_Run :: struct {
	value:          string,
	glyphs:         [dynamic]Text_Glyph,
	lines:          [dynamic]Text_Line,
	width:          f32,
	height:         f32,
	size:           f32,
	max_width:      f32,
	font_generation: u64,
	ligatures_disabled: bool,
	allocator:      mem.Allocator,
}

new_text_engine :: proc(name := "unconfigured", available := false, allocator := context.allocator) -> Text_Engine {
	return Text_Engine{
		allocator=allocator,
		name=owned_with_allocator(name, allocator), available=available,
		cache=runa.cache_make(allocator), cache_initialized=true,
		atlas=runa.atlas_make(1024, 1024, allocator), atlas_initialized=true,
		glyphs=make(map[Glyph_Resource_Key]runa.Atlas_Slot, allocator=allocator),
	}
}

text_engine_load_font :: proc(engine: ^Text_Engine, data: []u8) -> bool {
	if len(data) == 0 { return false }
	copy_data := make([]u8, len(data), engine.allocator)
	copy(copy_data, data)
	font, err := runa.font_load(copy_data, engine.allocator)
	if err != .None {
		delete(copy_data, engine.allocator)
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
		delete(engine.font_data, engine.allocator)
	}
	engine.font_data = copy_data
	engine.font = font
	engine.cache = runa.cache_make(engine.allocator)
	engine.cache_initialized = true
	engine.atlas = runa.atlas_make(1024, 1024, engine.allocator)
	engine.atlas_initialized = true
	engine.glyphs = make(map[Glyph_Resource_Key]runa.Atlas_Slot, allocator=engine.allocator)
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
	delete(engine.font_data, engine.allocator)
	if len(engine.name) > 0 { delete(engine.name, engine.allocator) }
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
	slot, err = runa.raster_glyph(&engine.font, glyph_id, size, key.subpixel_bucket, &engine.atlas, allocator=engine.allocator, hint=hint)
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
		delete(run.lines)
	} else {
		if len(run.value) > 0 { delete(run.value, context.allocator) }
		delete(run.glyphs)
		delete(run.lines)
	}
	run^ = {}
}

text_cluster_end :: proc(start: int, starts: []int, value_length: int) -> int {
	result := value_length
	for candidate in starts {
		if candidate > start && candidate < result { result = candidate }
	}
	return result
}

text_max_int :: proc(a, b: int) -> int {
	if a > b { return a }
	return b
}

text_min_int :: proc(a, b: int) -> int {
	if a < b { return a }
	return b
}

// text_run_build shapes a complete paragraph and copies its logical geometry.
// The returned product is safe to retain after Runa destroys its temporary
// Line values. Coordinates are in the same logical units as the requested
// size. Physical glyph rasterization is deliberately deferred to the native
// renderer so a window can move between DPI scales without changing logical
// layout.
text_run_build :: proc(engine: ^Text_Engine, value: string, size: f32, max_width: f32 = 0, editable: bool = false, allocator := context.allocator, scratch_allocator := context.temp_allocator) -> (run: Text_Run, ok: bool) {
	if !engine.font_loaded || size <= 0 { return }
	stack := runa.Font_Stack{&engine.font}
	disable_features: bit_set[runa.Feature] = {}
	if editable {
		// Runa documents a known cluster bookkeeping defect after GSUB
		// ligation. Editable text keeps mandatory shaping but disables the
		// discretionary features that commonly collapse Latin source spans.
		disable_features = {.Ligatures, .Contextual_Ligatures, .Contextual_Alternates}
	}
	opts := runa.Paragraph_Opts{fonts=stack, size=size, direction=.Auto, align=.Start, max_width=max_width, disable_features=disable_features}
	previous_temp_allocator := context.temp_allocator
	context.temp_allocator = scratch_allocator
	lines, err := runa.layout_paragraph(value, opts, &engine.cache, allocator=allocator)
	context.temp_allocator = previous_temp_allocator
	if err != .None { return }
	defer {
		for i := 0; i < len(lines); i += 1 { runa.line_destroy(&lines[i], allocator) }
		delete(lines, allocator)
	}
	value_copy, clone_err := strings.clone(value, allocator)
	if clone_err != nil { return Text_Run{}, false }
	run.value = value_copy
	run.glyphs = make([dynamic]Text_Glyph, 0, 32, allocator)
	run.lines = make([dynamic]Text_Line, 0, 4, allocator)
	run.size = size
	run.max_width = max_width
	run.font_generation = engine.font_generation
	run.ligatures_disabled = editable
	run.allocator = allocator
	// A ligature may collapse several source graphemes into one shaping
	// cluster. The next distinct shaped cluster therefore defines its source
	// range; this is more useful for caret/selection geometry than assuming
	// that every glyph maps one-to-one to a grapheme.
	cluster_starts := make([dynamic]int, 0, 32, scratch_allocator)
	for line in lines {
		for glyph in line.glyphs {
			start := int(glyph.cluster)
			known := false
			for prior in cluster_starts {
				if prior == start { known = true; break }
			}
			if !known { append(&cluster_starts, start) }
		}
	}

	line_y: f32 = 0
	for line, line_index in lines {
		line_glyph_start := len(run.glyphs)
		line_byte_start := len(value)
		line_byte_end := 0
		pen_x: f32 = 0
		for glyph in line.glyphs {
			cluster_start := int(glyph.cluster)
			cluster_end := text_cluster_end(cluster_start, cluster_starts[:], len(value))
			if cluster_start < line_byte_start { line_byte_start = cluster_start }
			if cluster_end > line_byte_end { line_byte_end = cluster_end }
			append(&run.glyphs, Text_Glyph{
				glyph_id=glyph.glyph_id,
				cluster_start=cluster_start,
				cluster_end=cluster_end,
				x=pen_x + glyph.x_offset,
				y=line_y + line.baseline + glyph.y_offset,
				x_advance=glyph.x_advance,
				y_advance=glyph.y_advance,
				x_offset=glyph.x_offset,
				y_offset=glyph.y_offset,
				line_index=line_index,
				level=glyph.level,
			})
			pen_x += glyph.x_advance
		}
		if len(line.glyphs) == 0 {
			if line_index == 0 { line_byte_start = 0 }
			else if line_index > 0 { line_byte_start = run.lines[line_index-1].byte_end }
			line_byte_end = line_byte_start
		}
		if line.width > run.width { run.width = line.width }
		append(&run.lines, Text_Line{
			glyph_start=line_glyph_start,
			glyph_end=len(run.glyphs),
			byte_start=line_byte_start,
			byte_end=line_byte_end,
			x=0,
			y=line_y,
			width=line.width,
			height=line.height,
			baseline=line.baseline,
		})
		line_y += line.height
	}
	run.height = line_y
	if len(run.lines) > 0 {
		// Include hard-break bytes and trailing source bytes in the line ranges
		// so a caret can still be placed on an empty or terminal line.
		run.lines[0].byte_start = 0
		for i := 0; i+1 < len(run.lines); i += 1 {
			if run.lines[i].byte_end < run.lines[i+1].byte_start {
				run.lines[i].byte_end = run.lines[i+1].byte_start
			}
		}
		run.lines[len(run.lines)-1].byte_end = len(value)
	}
	delete(cluster_starts)
	engine.shape_calls += 1
	ok = true
	return
}

// prepare_text_runs materializes the platform-neutral text product before
// layout. A node owns the product for as long as its retained identity lives;
// the application never needs to retain a Runa object or a renderer handle.
// Font replacement is represented by font_generation, so old runs are
// discarded before stale logical geometry can reach layout or paint.
prepare_text_run_node :: proc(rt: ^Runtime, node: ^Node, max_width: f32 = -1) -> bool {
	if !node_has_text_product(node.kind) || !node.active { return false }
	text_value := node.text
	if node.kind == .Button { text_value = node.label }
	// Runtime editing can update Node.text before the next application
	// description is emitted. Never allow a logically valid-looking retained
	// run for a different source value to reach layout or a native renderer.
	if node.text_run_valid && node.text_run.value != text_value {
		text_run_destroy(&node.text_run)
		node.text_run_valid = false
		node.text_run_generation += 1
	}
	if !rt.text_engine.font_loaded {
		if node.text_run_valid {
			text_run_destroy(&node.text_run)
			node.text_run_valid = false
		}
		return false
	}
	requested_width := max_width
	if requested_width < 0 {
		// For auto-width text, the parent layout pass owns the real wrapping
		// constraint. Once that pass has produced a valid run, do not rebuild it
		// here with the temporary unconstrained value on every root wake.
		if node.style.width <= 0 && node.text_run_valid &&
			node.text_run.font_generation == rt.text_engine.font_generation {
			return false
		}
		requested_width = 0
		if node.style.width > 0 { requested_width = node.style.width }
	}
	if node.text_run_valid &&
		node.text_run.font_generation == rt.text_engine.font_generation &&
		node.text_run.max_width == requested_width {
		return false
	}
	if node.text_run_valid { text_run_destroy(&node.text_run) }
	run, built := text_run_build(&rt.text_engine, text_value, 16, requested_width, editable=node.kind == .Text_Field, allocator=rt.persistent_allocator, scratch_allocator=rt.scratch_allocator)
	if built {
		node.text_run = run
		node.text_run_valid = true
		node.text_run_generation += 1
		return true
	}
	return false
}

prepare_text_runs :: proc(rt: ^Runtime) {
	// Normal frames only prepare nodes already made dirty by reconciliation.
	// A font replacement is the exceptional explicit event that changes every
	// text product's generation and therefore permits one full text-node pass.
	font_changed := rt.text_font_generation_seen != rt.text_engine.font_generation
	if font_changed {
		for id in rt.order {
			node, ok := rt.nodes[id]
			if ok { prepare_text_run_node(rt, node) }
		}
		rt.text_font_generation_seen = rt.text_engine.font_generation
		return
	}
	for id in rt.paint_queue {
		node, ok := rt.nodes[id]
		if ok { prepare_text_run_node(rt, node) }
	}
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

text_position_normalize :: proc(run: ^Text_Run, position: Text_Position) -> Text_Position {
	if run == nil { return Text_Position{} }
	byte := position.byte
	if byte < 0 { byte = 0 }
	if byte > len(run.value) { byte = len(run.value) }
	return Text_Position{grapheme_floor_boundary(run.value, byte), position.affinity}
}

text_run_line_for_byte :: proc(run: ^Text_Run, position: Text_Position) -> int {
	if run == nil || len(run.lines) == 0 { return -1 }
	normalized := text_position_normalize(run, position)
	for line, i in run.lines {
		if normalized.byte < line.byte_end { return i }
		if normalized.byte == line.byte_end {
			if normalized.affinity == .Trailing || i == len(run.lines)-1 { return i }
			if normalized.byte < run.lines[i+1].byte_end { return i+1 }
			return i
		}
	}
	return len(run.lines)-1
}

text_run_line_for_y :: proc(run: ^Text_Run, y: f32) -> int {
	if run == nil || len(run.lines) == 0 { return -1 }
	for line, i in run.lines {
		if y < line.y + line.height { return i }
	}
	return len(run.lines)-1
}

text_glyph_boundary_x :: proc(glyph: Text_Glyph, byte: int) -> f32 {
	start, end := glyph.cluster_start, glyph.cluster_end
	if end <= start || byte <= start {
		if glyph.level % 2 == 1 { return glyph.x + glyph.x_advance }
		return glyph.x
	}
	if byte >= end {
		if glyph.level % 2 == 1 { return glyph.x }
		return glyph.x + glyph.x_advance
	}
	ratio := f32(byte-start) / f32(end-start)
	if glyph.level % 2 == 1 { ratio = 1-ratio }
	return glyph.x + glyph.x_advance*ratio
}

append_text_caret_point :: proc(points: ^[dynamic]Text_Caret_Point, point: Text_Caret_Point) {
	for existing in points^ {
		if existing.position == point.position && existing.line_index == point.line_index {
			return
		}
	}
	append(points, point)
}

append_glyph_caret_points :: proc(run: ^Text_Run, line_index: int, glyph: Text_Glyph, points: ^[dynamic]Text_Caret_Point) {
	start, end := glyph.cluster_start, glyph.cluster_end
	if start < 0 { start = 0 }
	if end > len(run.value) { end = len(run.value) }
	if end < start { end = start }
	if start == end {
		append_text_caret_point(points, Text_Caret_Point{Text_Position{start, .Leading}, line_index, glyph.x})
		append_text_caret_point(points, Text_Caret_Point{Text_Position{start, .Trailing}, line_index, glyph.x})
		return
	}
	append_text_caret_point(points, Text_Caret_Point{
		Text_Position{start, .Leading},
		line_index,
		text_glyph_boundary_x(glyph, start),
	})

	// Use grapheme boundaries inside a shaping cluster as caret candidates.
	// When a ligature has one visual glyph for several graphemes, the internal
	// positions use deterministic interpolation across that glyph's advance.
	it := runa.grapheme_iter_make(run.value[start:end])
	for {
		_, local_end, ok := runa.grapheme_iter_next(&it)
		if !ok { break }
		byte := start + local_end
		x := text_glyph_boundary_x(glyph, byte)
		if byte == start {
			append_text_caret_point(points, Text_Caret_Point{Text_Position{byte, .Leading}, line_index, x})
		} else if byte == end {
			append_text_caret_point(points, Text_Caret_Point{Text_Position{byte, .Trailing}, line_index, x})
		} else {
			append_text_caret_point(points, Text_Caret_Point{Text_Position{byte, .Leading}, line_index, x})
			append_text_caret_point(points, Text_Caret_Point{Text_Position{byte, .Trailing}, line_index, x})
		}
	}
}

text_run_line_caret_points :: proc(run: ^Text_Run, line_index: int, points: ^[dynamic]Text_Caret_Point) {
	if run == nil || line_index < 0 || line_index >= len(run.lines) { return }
	line := run.lines[line_index]
	for i := line.glyph_start; i < line.glyph_end; i += 1 {
		append_glyph_caret_points(run, line_index, run.glyphs[i], points)
	}
	// Glyph-derived points carry bidi-aware edges. Add line endpoints only as
	// fallbacks for empty lines or source boundaries not represented by a glyph.
	append_text_caret_point(points, Text_Caret_Point{Text_Position{line.byte_start, .Leading}, line_index, line.x})
	append_text_caret_point(points, Text_Caret_Point{Text_Position{line.byte_end, .Trailing}, line_index, line.width})
}

text_run_position_x :: proc(run: ^Text_Run, line_index: int, position: Text_Position) -> (x: f32, found: bool) {
	if run == nil || line_index < 0 || line_index >= len(run.lines) { return }
	points := make([dynamic]Text_Caret_Point, 0, 32, context.temp_allocator)
	text_run_line_caret_points(run, line_index, &points)
	normalized := text_position_normalize(run, position)
	for point in points {
		if point.position == normalized {
			return point.x, true
		}
	}
	// A line can contain a hard break with no drawable glyph. Its source byte
	// range still has a deterministic caret at the line origin.
	line := run.lines[line_index]
	if normalized.byte <= line.byte_start { return line.x, true }
	if normalized.byte >= line.byte_end { return line.width, true }
	return line.x, false
}

text_run_caret_geometry :: proc(run: ^Text_Run, position: Text_Position) -> Text_Caret_Geometry {
	if run == nil || len(run.lines) == 0 { return Text_Caret_Geometry{} }
	normalized := text_position_normalize(run, position)
	line_index := text_run_line_for_byte(run, normalized)
	x, found := text_run_position_x(run, line_index, normalized)
	if !found { return Text_Caret_Geometry{} }
	line := run.lines[line_index]
	return Text_Caret_Geometry{
		position=normalized,
		line_index=line_index,
		rect=Rect{x, line.y, 1, line.height},
		valid=true,
	}
}

text_run_hit_test :: proc(run: ^Text_Run, x, y: f32) -> Text_Position {
	if run == nil || len(run.lines) == 0 { return Text_Position{} }
	line_index := text_run_line_for_y(run, y)
	points := make([dynamic]Text_Caret_Point, 0, 32, context.temp_allocator)
	text_run_line_caret_points(run, line_index, &points)
	if len(points) == 0 { return Text_Position{run.lines[line_index].byte_start, .Leading} }
	best := points[0]
	distance := best.x-x
	if distance < 0 { distance = -distance }
	for point in points[1:] {
		candidate := point.x-x
		if candidate < 0 { candidate = -candidate }
		if candidate < distance {
			best = point
			distance = candidate
		}
	}
	return text_position_normalize(run, best.position)
}

text_run_extreme_caret_point :: proc(points: []Text_Caret_Point, want_min: bool) -> (point: Text_Caret_Point, found: bool) {
	if len(points) == 0 { return }
	point = points[0]
	found = true
	for candidate in points[1:] {
		if (want_min && candidate.x < point.x) || (!want_min && candidate.x > point.x) {
			point = candidate
		}
	}
	return
}

text_run_selection_rects :: proc(run: ^Text_Run, start, end: Text_Position, allocator := context.allocator) -> [dynamic]Text_Selection_Rect {
	result := make([dynamic]Text_Selection_Rect, 0, 4, allocator)
	if run == nil || len(run.lines) == 0 { return result }
	normalized_start := text_position_normalize(run, start)
	normalized_end := text_position_normalize(run, end)
	low, high := normalized_start.byte, normalized_end.byte
	if low > high { low, high = high, low }
	if low == high { return result }
	for line, line_index in run.lines {
		if high <= line.byte_start || low >= line.byte_end { continue }
		line_start := text_max_int(low, line.byte_start)
		line_end := text_min_int(high, line.byte_end)
		left: f32 = line.x
		right := line.width
		if line_start > line.byte_start {
			left, _ = text_run_position_x(run, line_index, Text_Position{line_start, .Leading})
		}
		if line_end < line.byte_end {
			right, _ = text_run_position_x(run, line_index, Text_Position{line_end, .Trailing})
		}
		if right < left { left, right = right, left }
		if right > left {
			append(&result, Text_Selection_Rect{line_index, Rect{left, line.y, right-left, line.height}})
		}
	}
	return result
}

text_move_logical :: proc(value: string, position: Text_Position, delta: int) -> Text_Position {
	byte := position.byte
	steps := delta
	if steps < 0 {
		for steps < 0 {
			byte = grapheme_floor_boundary(value, byte-1)
			steps += 1
		}
	} else {
		for steps > 0 {
			byte = grapheme_ceil_boundary(value, byte+1)
			steps -= 1
		}
	}
	return Text_Position{grapheme_floor_boundary(value, byte), .Leading}
}

text_run_move_visual :: proc(run: ^Text_Run, position: Text_Position, direction: int) -> Text_Position {
	if run == nil || direction == 0 || len(run.lines) == 0 { return text_position_normalize(run, position) }
	normalized := text_position_normalize(run, position)
	line_index := text_run_line_for_byte(run, normalized)
	points := make([dynamic]Text_Caret_Point, 0, 32, context.temp_allocator)
	text_run_line_caret_points(run, line_index, &points)
	origin_x, found := text_run_position_x(run, line_index, normalized)
	if !found || len(points) == 0 { return normalized }
	chosen := normalized
	chosen_x := origin_x
	has_choice := false
	for point in points {
		if point.position == normalized { continue }
		if direction < 0 && point.x < origin_x-0.001 {
			if !has_choice || point.x > chosen_x {
				chosen, chosen_x, has_choice = point.position, point.x, true
			}
		} else if direction > 0 && point.x > origin_x+0.001 {
			if !has_choice || point.x < chosen_x {
				chosen, chosen_x, has_choice = point.position, point.x, true
			}
		}
	}
	if has_choice { return text_position_normalize(run, chosen) }
	if direction < 0 && line_index > 0 {
		previous := make([dynamic]Text_Caret_Point, 0, 32, context.temp_allocator)
		text_run_line_caret_points(run, line_index-1, &previous)
		if point, ok := text_run_extreme_caret_point(previous[:], false); ok { return point.position }
	} else if direction > 0 && line_index+1 < len(run.lines) {
		next := make([dynamic]Text_Caret_Point, 0, 32, context.temp_allocator)
		text_run_line_caret_points(run, line_index+1, &next)
		if point, ok := text_run_extreme_caret_point(next[:], true); ok { return point.position }
	}
	return normalized
}

text_layout :: proc(engine: ^Text_Engine, value: string, size: f32, max_width: f32 = 0) -> (width, height: f32, glyphs: int, ok: bool) {
	if !engine.font_loaded || size <= 0 { return }
	stack := runa.Font_Stack{&engine.font}
	opts := runa.Paragraph_Opts{fonts=stack, size=size, direction=.Auto, align=.Start, max_width=max_width}
	lines, err := runa.layout_paragraph(value, opts, &engine.cache, allocator=engine.allocator)
	if err != .None { return }
	defer {
		for i := 0; i < len(lines); i += 1 { runa.line_destroy(&lines[i], engine.allocator) }
		delete(lines, engine.allocator)
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
