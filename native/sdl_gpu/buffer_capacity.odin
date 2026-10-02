package alicorn_sdl_gpu

// Native GPU buffers grow geometrically so a larger frame mesh does not
// truncate at the previous capacity. `maximum` is the largest element count
// representable by the backend's buffer-size field.
native_next_vertex_capacity :: proc(current, required, maximum: int) -> int {
	if required <= current { return current }
	if required <= 0 || maximum <= 0 || required > maximum { return 0 }
	capacity := max(current, 4096)
	for capacity < required {
		if capacity > maximum / 2 {
			capacity = maximum
		} else {
			capacity *= 2
		}
	}
	return capacity
}
