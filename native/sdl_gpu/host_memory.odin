package alicorn_sdl_gpu

import "core:mem"

// Native host work uses its own resettable arena. This keeps atlas snapshots
// and other renderer-side temporary products out of the caller's ambient
// temporary allocator; application callbacks retain their original context.
Native_Host_Scratch :: struct {
	backing:  mem.Allocator,
	arena:    ^mem.Dynamic_Arena,
	allocator: mem.Allocator,
}

native_host_scratch_make :: proc(backing := context.allocator) -> Native_Host_Scratch {
	scratch := Native_Host_Scratch{backing=backing}
	scratch.arena = new(mem.Dynamic_Arena, allocator=backing)
	mem.dynamic_arena_init(scratch.arena, block_allocator=backing, array_allocator=backing)
	scratch.allocator = mem.dynamic_arena_allocator(scratch.arena)
	return scratch
}

native_host_scratch_reset :: proc(scratch: ^Native_Host_Scratch) {
	if scratch != nil && scratch.arena != nil { mem.dynamic_arena_reset(scratch.arena) }
}

native_host_scratch_destroy :: proc(scratch: ^Native_Host_Scratch) {
	if scratch == nil || scratch.arena == nil { return }
	mem.dynamic_arena_destroy(scratch.arena)
	free(scratch.arena, allocator=scratch.backing)
	scratch^ = {}
}

#assert(offset_of(Native_Text_Vertex, position) == 0)
#assert(offset_of(Native_Text_Vertex, color) == size_of([3]f32))
#assert(offset_of(Native_Text_Vertex, uv) == size_of([3]f32) + size_of([4]f32))
#assert(size_of(Native_Text_Vertex) == size_of([9]f32))
#assert(size_of(Native_Text_Uniforms) == size_of([32]f32))
