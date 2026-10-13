package alicorn

// image emits a retained, noninteractive image node. Intrinsic pixel size is
// used for unspecified dimensions; authored size/height in style are logical
// units and the compositor scales them with the window's DPI transform.
// Provide alt_text to expose a concise accessible label; omit it for purely
// decorative artwork.
image :: proc(
	ui: ^UI,
	handle: Image_Handle,
	alt_text := "",
	key: UI_Key = UI_Unkeyed{},
	style := DEFAULT_STYLE,
	loc := #caller_location,
) -> Node_ID {
	if ui == nil || ui.runtime == nil || !ui.runtime.frame_open { return 0 }
	if _, ok := image_resolve(ui.runtime, handle); !ok {
		append_diagnostic(ui.runtime, "image requires a live image handle owned by this Runtime")
		return 0
	}
	id := emit_key(
		ui,
		.Image,
		resolve_source(Source_Site{}, "image", loc),
		label=alt_text,
		key=key,
		style=style,
		state_bits=u64(handle),
		paint_background=false,
	)
	if id == 0 { return 0 }
	if alt_text != "" { semantic_description(ui, .Static_Text, alt_text) }
	return id
}
