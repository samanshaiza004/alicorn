package alicorn_sdl_gpu

import "core:testing"

@(test)
test_native_vertex_capacity_growth_and_bounds :: proc(t: ^testing.T) {
	maximum := int(u32(0xFFFFFFFF) / u32(size_of(Native_Text_Vertex)))
	testing.expect(t, native_next_vertex_capacity(65536, 65536, maximum) == 65536,
		"mesh within current capacity should not reallocate")
	testing.expect(t, native_next_vertex_capacity(65536, 65542, maximum) == 131072,
		"mesh above current capacity should grow geometrically")
	testing.expect(t, native_next_vertex_capacity(65536, maximum, maximum) == maximum,
		"capacity should clamp to the largest representable GPU buffer")
	testing.expect(t, native_next_vertex_capacity(65536, maximum+1, maximum) == 0,
		"unrepresentable GPU buffer size should be rejected")
	testing.expect(t, native_next_vertex_capacity(0, 1, maximum) == 4096,
		"the first allocation should use the shared minimum capacity")
}
