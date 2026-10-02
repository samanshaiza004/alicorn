package alicorn

custom_surface :: proc(ui: ^UI, surface_key: string, frame: u64, logical_bounds: Rect, pixel_width, pixel_height: int, dpi_scale: f32, source := Source_Site{}, loc := #caller_location) -> Node_ID {
	resolved_source := resolve_source(source, "custom_surface", loc)
	style := DEFAULT_STYLE
	style.width = logical_bounds.w
	style.height = logical_bounds.h
	return emit(ui, .Custom_Surface, resolved_source, label=surface_key, key=surface_key, explicit_key=true, style=style, paint_value=frame, color=Color{0.15, 0.25, 0.42, 1}, surface_pixel_width=pixel_width, surface_pixel_height=pixel_height, surface_dpi_scale=dpi_scale)
}

// gpu_surface is the explicit public name for the retained surface contract;
// custom_surface remains as the compatibility spelling used by the first
// native fixture.
gpu_surface_ex :: proc(ui: ^UI, surface_key: string, revision: u64, logical_bounds: Rect, pixel_width, pixel_height: int, dpi_scale: f32, source := Source_Site{}, loc := #caller_location) -> Node_ID {
	return custom_surface(ui, surface_key, revision, logical_bounds, pixel_width, pixel_height, dpi_scale, source, loc)
}

gpu_surface_simple :: proc(ui: ^UI, surface_key: string, revision: u64, logical_bounds: Rect, pixel_width, pixel_height: int, dpi_scale: f32, loc := #caller_location) -> Node_ID {
	return custom_surface(ui, surface_key, revision, logical_bounds, pixel_width, pixel_height, dpi_scale, Source_Site{}, loc)
}

gpu_surface :: proc(ui: ^UI, surface_key: string, revision: u64, logical_bounds: Rect, pixel_width, pixel_height: int, dpi_scale: f32, loc := #caller_location) -> Node_ID {
	return gpu_surface_simple(ui, surface_key, revision, logical_bounds, pixel_width, pixel_height, dpi_scale, loc)
}

// gpu_geometry_surface_ex creates a retained colored-geometry surface whose
// bounds are resolved by Alicorn layout. Geometry update coordinates are
// logical units local to the resulting bounds. Pixel extent is derived from
// the resolved bounds and dpi_scale when queried through gpu_surface_context.
gpu_geometry_surface_ex :: proc(
	ui: ^UI,
	surface_key: string,
	revision: u64,
	style: Layout_Style,
	dpi_scale: f32 = 1,
	source := Source_Site{},
	loc := #caller_location,
) -> Node_ID {
	resolved_source := resolve_source(source, "gpu_geometry_surface", loc)
	return emit(
		ui, .Custom_Surface, resolved_source,
		label=surface_key,
	key=surface_key,
	explicit_key=true,
	style=style,
	paint_value=revision,
	color=Color{0.08, 0.14, 0.24, 1},
	surface_kind=.Geometry,
	surface_dpi_scale=dpi_scale,
	)
}

gpu_geometry_surface_simple :: proc(
	ui: ^UI,
	surface_key: string,
	revision: u64,
	style: Layout_Style,
	dpi_scale: f32 = 1,
	loc := #caller_location,
) -> Node_ID {
	return gpu_geometry_surface_ex(ui, surface_key, revision, style, dpi_scale, Source_Site{}, loc)
}

gpu_geometry_surface :: proc(
	ui: ^UI,
	surface_key: string,
	revision: u64,
	style: Layout_Style,
	dpi_scale: f32 = 1,
	loc := #caller_location,
) -> Node_ID {
	return gpu_geometry_surface_simple(ui, surface_key, revision, style, dpi_scale, loc)
}
