package alicorn

// custom_surface declares a waveform surface. The declaration is stable UI
// structure; changing its retained payload is done with gpu_surface_update.
// Surfaces are presentation-only and do not receive pointer events unless
// surface_interaction is explicitly set to .Pointer. Application-wide host
// pointer callbacks remain global; this controls Alicorn retained hit testing.
custom_surface :: proc(
	ui: ^UI,
	surface_key: string,
	logical_bounds: Rect,
	pixel_width, pixel_height: int,
	dpi_scale: f32,
	surface_interaction := GPU_Surface_Interaction.Inert,
	source := Source_Site{},
	loc := #caller_location,
) -> Node_ID {
	resolved_source := resolve_source(source, "custom_surface", loc)
	style := DEFAULT_STYLE
	style.width = logical_bounds.w
	style.height = logical_bounds.h
	return emit(
		ui, .Custom_Surface, resolved_source,
		label=surface_key,
		key=surface_key,
		explicit_key=true,
		style=style,
		color=Color{0.15, 0.25, 0.42, 1},
		surface_kind=.Waveform,
		surface_interaction=surface_interaction,
		surface_pixel_width=pixel_width,
		surface_pixel_height=pixel_height,
		surface_dpi_scale=dpi_scale,
	)
}

// gpu_surface is the public spelling for the retained waveform-surface
// contract. custom_surface remains as a compatibility name.
gpu_surface_ex :: proc(
	ui: ^UI,
	surface_key: string,
	logical_bounds: Rect,
	pixel_width, pixel_height: int,
	dpi_scale: f32,
	surface_interaction := GPU_Surface_Interaction.Inert,
	source := Source_Site{},
	loc := #caller_location,
) -> Node_ID {
	return custom_surface(ui, surface_key, logical_bounds, pixel_width, pixel_height, dpi_scale, surface_interaction, source, loc)
}

gpu_surface_simple :: proc(
	ui: ^UI,
	surface_key: string,
	logical_bounds: Rect,
	pixel_width, pixel_height: int,
	dpi_scale: f32,
	surface_interaction := GPU_Surface_Interaction.Inert,
	loc := #caller_location,
) -> Node_ID {
	return custom_surface(ui, surface_key, logical_bounds, pixel_width, pixel_height, dpi_scale, surface_interaction, Source_Site{}, loc)
}

gpu_surface :: proc(
	ui: ^UI,
	surface_key: string,
	logical_bounds: Rect,
	pixel_width, pixel_height: int,
	dpi_scale: f32,
	surface_interaction := GPU_Surface_Interaction.Inert,
	loc := #caller_location,
) -> Node_ID {
	return gpu_surface_simple(ui, surface_key, logical_bounds, pixel_width, pixel_height, dpi_scale, surface_interaction, loc)
}

// gpu_geometry_surface_ex creates a retained colored-geometry surface whose
// bounds are resolved by Alicorn layout. Geometry update coordinates are
// surface-local logical units. Its payload is retained across ordinary
// description and layout changes, and the surface is inert unless interaction
// is explicitly requested.
gpu_geometry_surface_ex :: proc(
	ui: ^UI,
	surface_key: string,
	style: Layout_Style,
	dpi_scale: f32 = 1,
	surface_interaction := GPU_Surface_Interaction.Inert,
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
		color=Color{0.08, 0.14, 0.24, 1},
		surface_kind=.Geometry,
		surface_interaction=surface_interaction,
		surface_dpi_scale=dpi_scale,
	)
}

gpu_geometry_surface_simple :: proc(
	ui: ^UI,
	surface_key: string,
	style: Layout_Style,
	dpi_scale: f32 = 1,
	surface_interaction := GPU_Surface_Interaction.Inert,
	loc := #caller_location,
) -> Node_ID {
	return gpu_geometry_surface_ex(ui, surface_key, style, dpi_scale, surface_interaction, Source_Site{}, loc)
}

gpu_geometry_surface :: proc(
	ui: ^UI,
	surface_key: string,
	style: Layout_Style,
	dpi_scale: f32 = 1,
	surface_interaction := GPU_Surface_Interaction.Inert,
	loc := #caller_location,
) -> Node_ID {
	return gpu_geometry_surface_simple(ui, surface_key, style, dpi_scale, surface_interaction, loc)
}
