#+vet explicit-allocators
package alicorn

import "core:mem"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"
import runa "../third_party/Runa"

FONT_WEIGHT_AXIS_TAG :: runa.Axis_Tag(0x77676874)

Font_Weight_Axis :: struct {
	available: bool,
	tag:       runa.Axis_Tag,
	min_value: f32,
	max_value: f32,
}

// Text_Engine is intentionally a narrow seam. The runtime owns GUI concerns
// while a provider owns shaping, bidi, segmentation, line breaking and glyph
// rasterization. Runa is the foundation provider; its atlas remains behind
// this GUI-facing abstraction.
Text_Engine :: struct {
	allocator:             mem.Allocator,
	name:                  string,
	available:             bool,
	shaped_runs:           u64,
	cache_hits:            u64,
	shape_calls:           u64,
	glyph_cache_hits: u64,
	glyph_cache_misses: u64,
	glyph_rasterizations: u64,
	font_data:            []u8,
	font:                 runa.Font,
	font_weight_axis:     Font_Weight_Axis,
	fallback_font_data:   []u8,
	fallback_font:        runa.Font,
	fallback_font_weight_axis: Font_Weight_Axis,
	monospace_font_data: []u8,
	monospace_font:       runa.Font,
	monospace_font_weight_axis: Font_Weight_Axis,
	monospace_fallback_font_data: []u8,
	monospace_fallback_font:      runa.Font,
	monospace_fallback_font_weight_axis: Font_Weight_Axis,
	cache:                runa.Cache,
	font_loaded:          bool,
	fallback_font_loaded: bool,
	monospace_font_loaded: bool,
	monospace_fallback_font_loaded: bool,
	cache_initialized:    bool,
	font_generation:      u64,
	atlas:                 runa.Atlas,
	atlas_initialized:    bool,
	glyphs:                map[Glyph_Resource_Key]runa.Atlas_Slot,
}

Text_Font_Source :: enum u8 {
	Primary,
	Fallback,
}

// Glyph_Resource_Key is the CPU-side identity of one rasterized glyph. It is
// deliberately independent of an SDL_GPU texture pointer: GPU residency can
// be recreated after device loss or page retirement without changing the
// logical glyph resource identity.
Glyph_Resource_Key :: struct {
	font_generation: u64,
	font:           Font_Role,
	font_source:    Text_Font_Source,
	font_weight_bits: u32,
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
	// Control whitespace keeps layout/editor geometry but is skipped by raster.
	control_advance: bool,
}

Text_Source_Kind :: enum {
	Text,
	Tab,
	Control,
	Line_Break,
}

Text_Source_Span :: struct {
	output_start, output_end: int,
	source_start, source_end: int,
	kind: Text_Source_Kind,
}

TEXT_TAB_WIDTH_SPACES :: 4

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

// Text_Command is the platform-neutral editing vocabulary. Hosts translate
// their key and modifier events into these semantic operations; the runtime
// owns the word and grapheme rules behind them.
Text_Command :: enum {
	Move_Left,
	Move_Right,
	Move_Word_Left,
	Move_Word_Right,
	Delete_Backward,
	Delete_Forward,
	Delete_Word_Backward,
	Delete_Word_Forward,
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
	source_value:   string,
	source_value_override: bool,
	glyphs:         [dynamic]Text_Glyph,
	lines:          [dynamic]Text_Line,
	width:          f32,
	height:         f32,
	size:           f32,
	max_width:      f32,
	font_generation: u64,
	font:           Font_Role,
	font_source:    Text_Font_Source,
	font_weight:    f32,
	overflow:       Text_Overflow,
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
	return text_engine_load_font_role(engine, .UI, data)
}

text_engine_font :: proc(engine: ^Text_Engine, role: Font_Role) -> (font: ^runa.Font, loaded: bool) {
	if role == .Monospace && engine.monospace_font_loaded {
		return &engine.monospace_font, true
	}
	return &engine.font, engine.font_loaded
}

effective_font_weight :: proc(weight: f32) -> f32 {
	// Zero-initialized Text_Style values occur in older aggregate callers; keep
	// those equivalent to the documented regular default.
	if weight <= 0 { return FONT_WEIGHT_REGULAR }
	return weight
}

text_engine_weight_axis_for_font :: proc(font: ^runa.Font) -> Font_Weight_Axis {
	for axis in runa.font_axes(font) {
		if axis.tag == FONT_WEIGHT_AXIS_TAG {
			return Font_Weight_Axis{true, axis.tag, axis.min_value, axis.max_value}
		}
	}
	return {}
}

text_engine_weight_axis :: proc(engine: ^Text_Engine, role: Font_Role, source: Text_Font_Source) -> Font_Weight_Axis {
	if role == .Monospace {
		if source == .Fallback { return engine.monospace_fallback_font_weight_axis }
		return engine.monospace_font_weight_axis
	}
	if source == .Fallback { return engine.fallback_font_weight_axis }
	return engine.font_weight_axis
}

text_engine_apply_font_weight :: proc(font: ^runa.Font, axis: Font_Weight_Axis, weight: f32) -> bool {
	runa.font_reset_variations(font)
	if !axis.available { return false }
	resolved := effective_font_weight(weight)
	if resolved < axis.min_value { resolved = axis.min_value }
	if resolved > axis.max_value { resolved = axis.max_value }
	if runa.font_set_variation(font, axis.tag, resolved) != .None {
		runa.font_reset_variations(font)
		return false
	}
	return true
}

text_engine_fallback_font :: proc(engine: ^Text_Engine, role: Font_Role) -> (font: ^runa.Font, loaded: bool) {
	if role == .Monospace {
		return &engine.monospace_fallback_font, engine.monospace_fallback_font_loaded
	}
	return &engine.fallback_font, engine.fallback_font_loaded
}

text_engine_font_for_source :: proc(engine: ^Text_Engine, role: Font_Role, source: Text_Font_Source) -> (font: ^runa.Font, loaded: bool) {
	if source == .Fallback {
		if font, ok := text_engine_fallback_font(engine, role); ok { return font, true }
	}
	return text_engine_font(engine, role)
}

// Use a platform/application fallback face for a run if the primary face is
// missing any codepoint that the fallback can render. Keeping each run on one
// face avoids losing face identity in retained glyph geometry; mixed-face
// shaping remains a future text-engine improvement.
text_engine_choose_font_source :: proc(engine: ^Text_Engine, role: Font_Role, value: string) -> Text_Font_Source {
	primary, primary_loaded := text_engine_font(engine, role)
	fallback, fallback_loaded := text_engine_fallback_font(engine, role)
	if !primary_loaded || !fallback_loaded { return .Primary }
	for r in value {
		if runa.font_lookup_glyph(primary, r) == 0 && runa.font_lookup_glyph(fallback, r) != 0 {
			return .Fallback
		}
	}
	return .Primary
}

text_engine_reset_font_resources :: proc(engine: ^Text_Engine) {
	if engine.cache_initialized { runa.cache_destroy(&engine.cache) }
	if engine.atlas_initialized { runa.atlas_destroy(&engine.atlas) }
	if engine.glyphs != nil { delete(engine.glyphs) }
	engine.cache = runa.cache_make(engine.allocator)
	engine.cache_initialized = true
	engine.atlas = runa.atlas_make(1024, 1024, engine.allocator)
	engine.atlas_initialized = true
	engine.glyphs = make(map[Glyph_Resource_Key]runa.Atlas_Slot, allocator=engine.allocator)
}

// text_engine_load_font_role installs a role-specific font. Replacing either
// font clears shared Runa caches and atlas slots before destroying the old
// font, so no cached shaping product can retain a dead font pointer.
text_engine_load_font_role :: proc(engine: ^Text_Engine, role: Font_Role, data: []u8) -> bool {
	if len(data) == 0 { return false }
	copy_data := make([]u8, len(data), engine.allocator)
	copy(copy_data, data)
	font, err := runa.font_load(copy_data, engine.allocator)
	if err != .None {
		delete(copy_data, engine.allocator)
		return false
	}
	weight_axis := text_engine_weight_axis_for_font(&font)
	text_engine_reset_font_resources(engine)
	switch role {
	case .UI:
		if engine.font_loaded { runa.font_destroy(&engine.font) }
		delete(engine.font_data, engine.allocator)
		engine.font_data = copy_data
		engine.font = font
		engine.font_weight_axis = weight_axis
		engine.font_loaded = true
	case .Monospace:
		if engine.monospace_font_loaded { runa.font_destroy(&engine.monospace_font) }
		delete(engine.monospace_font_data, engine.allocator)
		engine.monospace_font_data = copy_data
		engine.monospace_font = font
		engine.monospace_font_weight_axis = weight_axis
		engine.monospace_font_loaded = true
	}
	engine.font_generation += 1
	engine.available = true
	return true
}

// text_engine_load_fallback_font_role installs a per-role fallback face.
// Fallbacks are deliberately separate from the bundled primary faces so apps
// can provide only the script coverage they need.
text_engine_load_fallback_font_role :: proc(engine: ^Text_Engine, role: Font_Role, data: []u8) -> bool {
	if len(data) == 0 { return false }
	copy_data := make([]u8, len(data), engine.allocator)
	copy(copy_data, data)
	font, err := runa.font_load(copy_data, engine.allocator)
	if err != .None {
		delete(copy_data, engine.allocator)
		return false
	}
	weight_axis := text_engine_weight_axis_for_font(&font)
	text_engine_reset_font_resources(engine)
	switch role {
	case .UI:
		if engine.fallback_font_loaded { runa.font_destroy(&engine.fallback_font) }
		delete(engine.fallback_font_data, engine.allocator)
		engine.fallback_font_data = copy_data
		engine.fallback_font = font
		engine.fallback_font_weight_axis = weight_axis
		engine.fallback_font_loaded = true
	case .Monospace:
		if engine.monospace_fallback_font_loaded { runa.font_destroy(&engine.monospace_fallback_font) }
		delete(engine.monospace_fallback_font_data, engine.allocator)
		engine.monospace_fallback_font_data = copy_data
		engine.monospace_fallback_font = font
		engine.monospace_fallback_font_weight_axis = weight_axis
		engine.monospace_fallback_font_loaded = true
	}
	engine.font_generation += 1
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
	if engine.monospace_font_loaded {
		runa.font_destroy(&engine.monospace_font)
	}
	if engine.fallback_font_loaded {
		runa.font_destroy(&engine.fallback_font)
	}
	if engine.monospace_fallback_font_loaded {
		runa.font_destroy(&engine.monospace_fallback_font)
	}
	delete(engine.font_data, engine.allocator)
	delete(engine.fallback_font_data, engine.allocator)
	delete(engine.monospace_font_data, engine.allocator)
	delete(engine.monospace_fallback_font_data, engine.allocator)
	if len(engine.name) > 0 { delete(engine.name, engine.allocator) }
	engine^ = {}
}

text_engine_glyph :: proc(engine: ^Text_Engine, glyph_id: runa.Glyph_ID, size: f32, subpixel_bucket: u8 = 0, hint: bool = true, scratch_allocator := context.temp_allocator, font_role := Font_Role.UI, font_source := Text_Font_Source.Primary, font_weight: f32 = FONT_WEIGHT_REGULAR) -> (slot: runa.Atlas_Slot, drawable, ok: bool) {
	font, loaded := text_engine_font_for_source(engine, font_role, font_source)
	if !loaded || size <= 0 { return }
	weight := effective_font_weight(font_weight)
	is_color := runa.font_has_color_layers(font, glyph_id)
	key := Glyph_Resource_Key{
		font_generation = engine.font_generation,
		font = font_role,
		font_source = font_source,
		font_weight_bits = transmute(u32)weight,
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
	previous_temp_allocator := context.temp_allocator
	context.temp_allocator = scratch_allocator
	_ = text_engine_apply_font_weight(font, text_engine_weight_axis(engine, font_role, font_source), weight)
	defer { runa.font_reset_variations(font) }
	slot, err = runa.raster_glyph(font, glyph_id, size, key.subpixel_bucket, &engine.atlas, allocator=engine.allocator, hint=hint)
	context.temp_allocator = previous_temp_allocator
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
		if len(run.source_value) > 0 { delete(run.source_value, run.allocator) }
		delete(run.glyphs)
		delete(run.lines)
	} else {
		if len(run.value) > 0 { delete(run.value, context.allocator) }
		if len(run.source_value) > 0 { delete(run.source_value, context.allocator) }
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

// text_normalize_controls keeps the application string untouched and gives
// Runa only printable text plus its supported line break. Tabs and remaining
// C0/C1 controls become non-rendering space advances; CR and CRLF normalize
// to one line break. Each output span remembers the source byte range so
// caret, selection, and hit testing continue to use the original string.
text_contains_control :: proc(value: string) -> bool {
	for i := 0; i < len(value); i += 1 {
		b := value[i]
		if b < 0x20 || b == 0x7f { return true }
		if b == 0xc2 && i+1 < len(value) && value[i+1] >= 0x80 && value[i+1] <= 0x9f { return true }
	}
	return false
}

text_normalize_controls :: proc(value: string, allocator := context.temp_allocator) -> (normalized: string, spans: [dynamic]Text_Source_Span) {
	if !text_contains_control(value) { return value, nil }
	builder := strings.builder_make(0, len(value), allocator)
	spans = make([dynamic]Text_Source_Span, 0, len(value), allocator)
	output_byte := 0
	for source_byte := 0; source_byte < len(value); {
		r, size := utf8.decode_rune_in_string(value[source_byte:])
		if size <= 0 { size = 1 }
		source_end := source_byte + size
		kind := Text_Source_Kind.Text
		output_size := size
		switch r {
		case '\r':
			if source_end < len(value) && value[source_end] == '\n' { source_end += 1 }
			strings.write_byte(&builder, '\n')
			kind = .Line_Break
			output_size = 1
		case '\n':
			strings.write_byte(&builder, '\n')
			kind = .Line_Break
			output_size = 1
		case '\t':
			strings.write_byte(&builder, ' ')
			kind = .Tab
			output_size = 1
		case:
			if unicode.is_control(r) {
				strings.write_byte(&builder, ' ')
				kind = .Control
				output_size = 1
			} else {
				strings.write_string(&builder, value[source_byte:source_end])
			}
		}
		append(&spans, Text_Source_Span{output_byte, output_byte+output_size, source_byte, source_end, kind})
		output_byte += output_size
		source_byte = source_end
	}
	normalized = strings.to_string(builder)
	return
}

text_source_span_at :: proc(spans: []Text_Source_Span, output_byte, source_length: int) -> Text_Source_Span {
	for span in spans {
		if output_byte >= span.output_start && output_byte < span.output_end { return span }
	}
	return Text_Source_Span{output_byte, output_byte, source_length, source_length, .Text}
}

text_source_range_for_output :: proc(spans: []Text_Source_Span, output_start, output_end, source_length: int) -> (source_start, source_end: int, control_advance: bool, tab: bool) {
	if len(spans) == 0 {
		source_start = text_min_int(text_max_int(output_start, 0), source_length)
		source_end = text_min_int(text_max_int(output_end, source_start), source_length)
		return
	}
	source_start = source_length
	source_end = 0
	found := false
	for span in spans {
		if span.output_end <= output_start || span.output_start >= output_end { continue }
		if !found || span.source_start < source_start { source_start = span.source_start }
		if !found || span.source_end > source_end { source_end = span.source_end }
		found = true
		if span.kind == .Tab { tab = true }
		if span.kind == .Tab || span.kind == .Control { control_advance = true }
	}
	if !found {
		span := text_source_span_at(spans, output_start, source_length)
		source_start, source_end = span.source_start, span.source_end
		control_advance = span.kind == .Tab || span.kind == .Control
		tab = span.kind == .Tab
	}
	return
}

text_tab_advance :: proc(line_x, space_advance: f32) -> f32 {
	stop := space_advance * f32(TEXT_TAB_WIDTH_SPACES)
	if stop <= 0 { return space_advance }
	// Text advances are nonnegative in the visual line order returned by Runa.
	// Advance to the next stop even when the current pen is already on one.
	next_stop := f32(int(line_x / stop) + 1) * stop
	advance := next_stop - line_x
	if advance <= 0 { return stop }
	return advance
}

// text_run_build shapes a complete paragraph and copies its logical geometry.
// The returned product is safe to retain after Runa destroys its temporary
// Line values. Coordinates are in the same logical units as the requested
// size. Physical glyph rasterization is deliberately deferred to the native
// renderer so a window can move between DPI scales without changing logical
// layout.
text_run_build :: proc(engine: ^Text_Engine, value: string, size: f32, max_width: f32 = 0, editable: bool = false, allocator := context.allocator, scratch_allocator := context.temp_allocator, font_role := Font_Role.UI, font_weight: f32 = FONT_WEIGHT_REGULAR, overflow := Text_Overflow.Wrap) -> (run: Text_Run, ok: bool) {
	font_source := text_engine_choose_font_source(engine, font_role, value)
	font, font_loaded := text_engine_font_for_source(engine, font_role, font_source)
	if !font_loaded || size <= 0 { return }
	resolved_font_weight := effective_font_weight(font_weight)
	_ = text_engine_apply_font_weight(font, text_engine_weight_axis(engine, font_role, font_source), resolved_font_weight)
	defer { runa.font_reset_variations(font) }
	stack := runa.Font_Stack{font}
	disable_features: bit_set[runa.Feature] = {}
	if editable {
		// Runa documents a known cluster bookkeeping defect after GSUB
		// ligation. Editable text keeps mandatory shaping but disables the
		// discretionary features that commonly collapse Latin source spans.
		disable_features = {.Ligatures, .Contextual_Ligatures, .Contextual_Alternates}
	}
	wrap_width := max_width if overflow == .Wrap else 0
	opts := runa.Paragraph_Opts{fonts=stack, size=size, direction=.Auto, align=.Start, max_width=wrap_width, disable_features=disable_features}
	normalized_value, source_spans := text_normalize_controls(value, scratch_allocator)
	defer { delete(source_spans) }
	previous_temp_allocator := context.temp_allocator
	context.temp_allocator = scratch_allocator
	lines, err := runa.layout_paragraph(normalized_value, opts, &engine.cache, allocator=allocator)
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
	run.font = font_role
	run.font_source = font_source
	run.font_weight = resolved_font_weight
	run.overflow = overflow
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
			output_start := int(glyph.cluster)
			output_end := text_cluster_end(output_start, cluster_starts[:], len(normalized_value))
			cluster_start, cluster_end, control_advance, tab := text_source_range_for_output(source_spans[:], output_start, output_end, len(value))
			if cluster_start < line_byte_start { line_byte_start = cluster_start }
			if cluster_end > line_byte_end { line_byte_end = cluster_end }
			advance := glyph.x_advance
			if tab { advance = text_tab_advance(pen_x, glyph.x_advance) }
			append(&run.glyphs, Text_Glyph{
				glyph_id=glyph.glyph_id,
				cluster_start=cluster_start,
				cluster_end=cluster_end,
				x=pen_x + glyph.x_offset,
				y=line_y + line.baseline + glyph.y_offset,
				x_advance=advance,
				y_advance=glyph.y_advance,
				x_offset=glyph.x_offset,
				y_offset=glyph.y_offset,
				line_index=line_index,
				level=glyph.level,
				control_advance=control_advance,
			})
			pen_x += advance
		}
		if len(line.glyphs) == 0 {
			if line_index == 0 { line_byte_start = 0 }
			else if line_index > 0 { line_byte_start = run.lines[line_index-1].byte_end }
			line_byte_end = line_byte_start
		}
		line_width := line.width
		if pen_x > line.width { line_width = pen_x }
		if line_width > run.width { run.width = line_width }
		append(&run.lines, Text_Line{
			glyph_start=line_glyph_start,
			glyph_end=len(run.glyphs),
			byte_start=line_byte_start,
			byte_end=line_byte_end,
			x=0,
			y=line_y,
			width=line_width,
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

text_ellipsis_candidate :: proc(value: string, prefix_end: int, allocator: mem.Allocator) -> string {
	ELLIPSIS := "…"
	bytes := make([]u8, prefix_end+len(ELLIPSIS), allocator=allocator)
	copy(bytes[:prefix_end], value[:prefix_end])
	copy(bytes[prefix_end:], ELLIPSIS)
	return string(bytes)
}

text_ellipsis_candidate_fits :: proc(
	engine: ^Text_Engine,
	value: string,
	prefix_end: int,
	max_width, size: f32,
	font_role: Font_Role,
	font_weight: f32,
	scratch_allocator: mem.Allocator,
	editable: bool = false,
) -> bool {
	candidate := text_ellipsis_candidate(value, prefix_end, scratch_allocator)
	defer { delete(candidate, scratch_allocator) }
	run, ok := text_run_build(
		engine, candidate, size,
		editable=editable,
		allocator=scratch_allocator,
		scratch_allocator=scratch_allocator,
		font_role=font_role,
		font_weight=font_weight,
		overflow=.Clip,
	)
	if !ok { return false }
	fits := run.width <= max_width
	text_run_destroy(&run)
	return fits
}

text_run_build_with_overflow :: proc(
	engine: ^Text_Engine,
	value: string,
	size: f32,
	max_width: f32,
	allocator, scratch_allocator: mem.Allocator,
	font_role: Font_Role,
	font_weight: f32,
	overflow: Text_Overflow,
	editable: bool = false,
) -> (run: Text_Run, ok: bool) {
	if overflow != .Ellipsis {
		return text_run_build(
			engine, value, size, max_width,
			editable=editable,
			allocator=allocator,
			scratch_allocator=scratch_allocator,
			font_role=font_role,
			font_weight=font_weight,
			overflow=overflow,
		)
	}

	// A single-line label treats a hard line break as omitted trailing content.
	line_end := len(value)
	for i in 0..<len(value) {
		if value[i] == '\n' || value[i] == '\r' {
			line_end = i
			break
		}
	}
	line_value := value[:line_end]
	full, full_ok := text_run_build(
		engine, line_value, size, max_width,
		editable=editable,
		allocator=allocator,
		scratch_allocator=scratch_allocator,
		font_role=font_role,
		font_weight=font_weight,
		overflow=.Clip,
	)
	if !full_ok { return }
	if line_end == len(value) && (max_width <= 0 || full.width <= max_width) {
		full.overflow = .Ellipsis
		return full, true
	}
	text_run_destroy(&full)

	ends := make([dynamic]int, 0, len(line_value)+1, scratch_allocator)
	defer { delete(ends) }
	append(&ends, 0)
	iter := runa.grapheme_iter_make(line_value)
	for {
		_, hi, found := runa.grapheme_iter_next(&iter)
		if !found { break }
		append(&ends, hi)
	}

	// Fit the longest grapheme-safe prefix plus an ellipsis. Shaping candidate
	// prefixes, rather than clipping glyphs by x-coordinate, keeps ligatures,
	// combining marks and emoji clusters intact.
	best := 0
	low := 0
	high := len(ends)
	for high-low > 1 {
		mid := (low+high)/2
		if text_ellipsis_candidate_fits(
			engine, line_value, ends[mid], max_width, size,
			font_role, font_weight, scratch_allocator, editable,
		) {
			best = mid
			low = mid
		} else {
			high = mid
		}
	}

	display_value := text_ellipsis_candidate(line_value, ends[best], scratch_allocator)
	defer { delete(display_value, scratch_allocator) }
	run, ok = text_run_build(
		engine, display_value, size, max_width,
		editable=editable,
		allocator=allocator,
		scratch_allocator=scratch_allocator,
		font_role=font_role,
		font_weight=font_weight,
		overflow=.Clip,
	)
	if !ok { return }
	run.overflow = .Ellipsis
	source_copy, err := strings.clone(value, allocator)
	if err != nil {
		text_run_destroy(&run)
		return Text_Run{}, false
	}
	run.source_value = source_copy
	run.source_value_override = true
	return run, true
}

// prepare_text_runs materializes the platform-neutral text product before
// layout. A node owns the product for as long as its retained identity lives;
// the application never needs to retain a Runa object or a renderer handle.
// Font replacement is represented by font_generation, so old runs are
// discarded before stale logical geometry can reach layout or paint.
prepare_text_run_node :: proc(rt: ^Runtime, node: ^Node, max_width: f32 = -1) -> bool {
	if !node_has_text_product(node.kind) || !node.active { return false }
	text_value := node.text
	if node.kind == .Button || node.kind == .Checkbox || node.kind == .Slider { text_value = node.label }
	text_overflow := node.text_style.overflow
	if node.kind == .Text_Field { text_overflow = .Wrap }
	// Runtime editing can update Node.text before the next application
	// description is emitted. Never allow a logically valid-looking retained
	// run for a different source value to reach layout or a native renderer.
	if node.text_run_valid && node.text_run.overflow == text_overflow &&
		((node.text_run.source_value_override && node.text_run.source_value != text_value) ||
		 (!node.text_run.source_value_override && node.text_run.value != text_value)) {
		text_run_destroy(&node.text_run)
		node.text_run_valid = false
		node.text_run_generation += 1
	}
	_, role_loaded := text_engine_font(&rt.text_engine, node.font)
	if !role_loaded {
		if node.text_run_valid {
			text_run_destroy(&node.text_run)
			node.text_run_valid = false
		}
		return false
	}
	requested_width := max_width
	font_weight := effective_font_weight(node.text_style.font_weight)
	if requested_width < 0 {
		// For auto-width text, the parent layout pass owns the real wrapping
		// constraint. Once that pass has produced a valid run, do not rebuild it
		// here with the temporary unconstrained value on every root wake.
		if node.style.width <= 0 && node.text_run_valid &&
			node.text_run.font_generation == rt.text_engine.font_generation &&
			node.text_run.font_weight == font_weight &&
			node.text_run.overflow == text_overflow {
			return false
		}
		requested_width = 0
		if node.style.width > 0 { requested_width = node.style.width }
	}
	if node.text_run_valid &&
		node.text_run.font_generation == rt.text_engine.font_generation &&
		node.text_run.max_width == requested_width &&
		node.text_run.font_weight == font_weight &&
		node.text_run.overflow == text_overflow {
		return false
	}
	if node.text_run_valid { text_run_destroy(&node.text_run) }
	run, built := text_run_build_with_overflow(
		&rt.text_engine, text_value, 16, requested_width,
		rt.persistent_allocator, rt.scratch_allocator,
		node.font, font_weight, text_overflow, editable=node.kind == .Text_Field,
	)
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
		if ok && (!node.text_run_valid || dirty_has(node.dirty, .Layout)) {
			prepare_text_run_node(rt, node)
		}
	}
}

runa_cache_size :: proc(engine: ^Text_Engine) -> int {
	if !engine.font_loaded && !engine.monospace_font_loaded { return 0 }
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

text_run_position_x :: proc(run: ^Text_Run, line_index: int, position: Text_Position, scratch_allocator := context.temp_allocator) -> (x: f32, found: bool) {
	if run == nil || line_index < 0 || line_index >= len(run.lines) { return }
	points := make([dynamic]Text_Caret_Point, 0, 32, scratch_allocator)
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

text_run_caret_geometry :: proc(run: ^Text_Run, position: Text_Position, scratch_allocator := context.temp_allocator) -> Text_Caret_Geometry {
	if run == nil || len(run.lines) == 0 { return Text_Caret_Geometry{} }
	normalized := text_position_normalize(run, position)
	line_index := text_run_line_for_byte(run, normalized)
	x, found := text_run_position_x(run, line_index, normalized, scratch_allocator)
	if !found { return Text_Caret_Geometry{} }
	line := run.lines[line_index]
	return Text_Caret_Geometry{
		position=normalized,
		line_index=line_index,
		rect=Rect{x, line.y, 1, line.height},
		valid=true,
	}
}

text_run_hit_test :: proc(run: ^Text_Run, x, y: f32, scratch_allocator := context.temp_allocator) -> Text_Position {
	if run == nil || len(run.lines) == 0 { return Text_Position{} }
	line_index := text_run_line_for_y(run, y)
	points := make([dynamic]Text_Caret_Point, 0, 32, scratch_allocator)
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

text_run_selection_rects :: proc(run: ^Text_Run, start, end: Text_Position, allocator := context.allocator, scratch_allocator := context.temp_allocator) -> [dynamic]Text_Selection_Rect {
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
			left, _ = text_run_position_x(run, line_index, Text_Position{line_start, .Leading}, scratch_allocator)
		}
		if line_end < line.byte_end {
			right, _ = text_run_position_x(run, line_index, Text_Position{line_end, .Trailing}, scratch_allocator)
		}
		if right < left { left, right = right, left }
		if right > left {
			append(&result, Text_Selection_Rect{line_index, Rect{left, line.y, right-left, line.height}})
		}
	}
	return result
}

text_move_logical :: proc(value: string, position: Text_Position, delta: int) -> Text_Position {
	normalized := Text_Position{grapheme_floor_boundary(value, position.byte), position.affinity}
	if delta == 0 { return normalized }
	byte := normalized.byte
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

text_word_range :: struct {
	start, end: int,
}

// text_word_ranges uses Runa's UAX #29 word iterator rather than code-point
// heuristics. Runa emits separator runs as ranges too, which lets command
// movement skip punctuation and whitespace while retaining Unicode behavior.
text_word_ranges :: proc(value: string, scratch_allocator := context.temp_allocator) -> [dynamic]text_word_range {
	ranges := make([dynamic]text_word_range, 0, 16, scratch_allocator)
	it := runa.word_iter_make(value)
	for {
		start, end, ok := runa.word_iter_next(&it)
		if !ok { break }
		append(&ranges, text_word_range{start, end})
	}
	return ranges
}

// Runa intentionally returns every UAX word segment, including whitespace
// and punctuation. Those non-word segments are separators for editor-style
// Ctrl+arrow semantics. The ASCII test covers the host keyboard vocabulary;
// non-ASCII segments remain word-like so scripts, combining text, and emoji
// are never split by a byte-level shortcut.
text_word_range_is_separator :: proc(value: string, range: text_word_range) -> bool {
	if range.end <= range.start { return true }
	for i := range.start; i < range.end; {
		r, size := utf8.decode_rune_in_string(value[i:])
		if size <= 0 { return true }
		if unicode.is_letter(r) || unicode.is_digit(r) || unicode.is_combining(r) || r == '_' {
			return false
		}
		if !unicode.is_space(r) && !unicode.is_punct(r) && r >= 0x80 && !unicode.is_control(r) {
			// Keep non-ASCII symbols (notably emoji) as navigable word
			// units; Runa's grapheme iterator still protects their extent.
			return false
		}
		i += size
	}
	return true
}

text_move_word :: proc(value: string, position: Text_Position, delta: int, scratch_allocator := context.temp_allocator) -> Text_Position {
	normalized := Text_Position{grapheme_floor_boundary(value, position.byte), position.affinity}
	if delta == 0 || len(value) == 0 { return normalized }
	ranges := text_word_ranges(value, scratch_allocator)
	byte := normalized.byte
	steps := delta
	for steps < 0 {
		if byte <= 0 { break }
		candidate := -1
		for range, i in ranges {
			if byte <= range.start { break }
			candidate = i
			if byte <= range.end { break }
		}
		if candidate < 0 { byte = 0; break }
		// Ctrl/Option-Left lands at the beginning of the current word when
		// the caret is inside it or at its trailing edge. At a word's
		// leading edge, it skips separators and lands at the prior word.
		if byte == ranges[candidate].start { candidate -= 1 }
		for candidate >= 0 && text_word_range_is_separator(value, ranges[candidate]) {
			candidate -= 1
		}
		byte = 0 if candidate < 0 else ranges[candidate].start
		steps += 1
	}
	for steps > 0 {
		if byte >= len(value) { break }
		candidate := -1
		for range, i in ranges {
			if byte < range.end {
				candidate = i
				break
			}
		}
		if candidate < 0 { byte = len(value); break }
		// Ctrl/Option-Right lands at the beginning of the next word. Skip
		// the current word (or the separator containing the caret), then
		// skip all separator ranges before the next word.
		if !text_word_range_is_separator(value, ranges[candidate]) {
			candidate += 1
		}
		for candidate < len(ranges) && text_word_range_is_separator(value, ranges[candidate]) {
			candidate += 1
		}
		byte = len(value) if candidate >= len(ranges) else ranges[candidate].start
		steps -= 1
	}
	return Text_Position{grapheme_floor_boundary(value, byte), .Leading}
}

text_run_move_visual :: proc(run: ^Text_Run, position: Text_Position, direction: int, scratch_allocator := context.temp_allocator) -> Text_Position {
	if run == nil || direction == 0 || len(run.lines) == 0 { return text_position_normalize(run, position) }
	normalized := text_position_normalize(run, position)
	line_index := text_run_line_for_byte(run, normalized)
	points := make([dynamic]Text_Caret_Point, 0, 32, scratch_allocator)
	text_run_line_caret_points(run, line_index, &points)
	origin_x, found := text_run_position_x(run, line_index, normalized, scratch_allocator)
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
		previous := make([dynamic]Text_Caret_Point, 0, 32, scratch_allocator)
		text_run_line_caret_points(run, line_index-1, &previous)
		if point, ok := text_run_extreme_caret_point(previous[:], false); ok { return point.position }
	} else if direction > 0 && line_index+1 < len(run.lines) {
		next := make([dynamic]Text_Caret_Point, 0, 32, scratch_allocator)
		text_run_line_caret_points(run, line_index+1, &next)
		if point, ok := text_run_extreme_caret_point(next[:], true); ok { return point.position }
	}
	return normalized
}

text_layout :: proc(engine: ^Text_Engine, value: string, size: f32, max_width: f32 = 0, scratch_allocator := context.temp_allocator, font_role := Font_Role.UI, font_weight: f32 = FONT_WEIGHT_REGULAR) -> (width, height: f32, glyphs: int, ok: bool) {
	font_source := text_engine_choose_font_source(engine, font_role, value)
	font, font_loaded := text_engine_font_for_source(engine, font_role, font_source)
	if !font_loaded || size <= 0 { return }
	_ = text_engine_apply_font_weight(font, text_engine_weight_axis(engine, font_role, font_source), font_weight)
	defer { runa.font_reset_variations(font) }
	stack := runa.Font_Stack{font}
	opts := runa.Paragraph_Opts{fonts=stack, size=size, direction=.Auto, align=.Start, max_width=max_width}
	normalized_value, source_spans := text_normalize_controls(value, scratch_allocator)
	defer { delete(source_spans) }
	previous_temp_allocator := context.temp_allocator
	context.temp_allocator = scratch_allocator
	lines, err := runa.layout_paragraph(normalized_value, opts, &engine.cache, allocator=engine.allocator)
	context.temp_allocator = previous_temp_allocator
	if err != .None { return }
	defer {
		for i := 0; i < len(lines); i += 1 { runa.line_destroy(&lines[i], engine.allocator) }
		delete(lines, engine.allocator)
	}
	for line in lines {
		line_width := line.width
		pen_x: f32 = 0
		for glyph in line.glyphs {
			advance := glyph.x_advance
			span := text_source_span_at(source_spans[:], int(glyph.cluster), len(value))
			if span.kind == .Tab { advance = text_tab_advance(pen_x, glyph.x_advance) }
			pen_x += advance
		}
		if pen_x > line_width { line_width = pen_x }
		if line_width > width { width = line_width }
		height += line.height
		glyphs += len(line.glyphs)
	}
	ok = true
	return
}

text_shape :: proc(engine: ^Text_Engine, value: string, changed: bool, scratch_allocator := context.temp_allocator) {
	if !engine.font_loaded {
		if engine.available {
			if changed { engine.shaped_runs += 1 } else { engine.cache_hits += 1 }
		}
		return
	}
	_, _, _, ok := text_layout(engine, value, 16, scratch_allocator=scratch_allocator)
	if !ok { return }
	if changed { engine.shaped_runs += 1 } else { engine.cache_hits += 1 }
}
