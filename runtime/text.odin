package alicorn

// Text_Engine is intentionally a narrow seam. The runtime owns GUI concerns
// while a provider owns shaping, bidi, segmentation, line breaking and glyph
// rasterization. Runa is the intended provider, but is not bundled in the
// available Odin SDK.
Text_Engine :: struct {
	name: string,
	available: bool,
	shaped_runs: u64,
	cache_hits: u64,
}

new_text_engine :: proc(name := "unconfigured", available := false) -> Text_Engine {
	return Text_Engine{owned(name), available, 0, 0}
}

text_shape :: proc(engine: ^Text_Engine, value: string, changed: bool) {
	if !engine.available {
		return
	}
	if changed { engine.shaped_runs += 1 } else { engine.cache_hits += 1 }
}

