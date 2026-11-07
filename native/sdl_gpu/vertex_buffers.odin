package alicorn_sdl_gpu

import "vendor:sdl3"

native_white_texture_initialize :: proc(
	device: ^sdl3.GPUDevice,
	texture: ^sdl3.GPUTexture,
	initialized: ^bool,
	command: ^sdl3.GPUCommandBuffer,
) -> bool {
	if initialized^ { return true }
	target := sdl3.GPUColorTargetInfo{
		texture=texture, clear_color=sdl3.FColor{1, 1, 1, 1},
		load_op=.CLEAR, store_op=.STORE,
	}
	pass := sdl3.BeginGPURenderPass(command, &target, 1, nil)
	if pass == nil { return false }
	sdl3.EndGPURenderPass(pass)
	initialized^ = true
	return true
}

native_vertex_buffer_upload :: proc(
	device: ^sdl3.GPUDevice,
	vertex_buffer: ^sdl3.GPUBuffer,
	vertex_transfer: ^sdl3.GPUTransferBuffer,
	vertices: []Native_Text_Vertex,
	vertex_capacity: int,
	upload_pending: bool,
	vertices_uploaded: ^u64,
	command: ^sdl3.GPUCommandBuffer,
) -> bool {
	if !upload_pending { return true }
	if len(vertices) > vertex_capacity { return false }
	mapped := sdl3.MapGPUTransferBuffer(device, vertex_transfer, true)
	if mapped == nil { return false }
	destination := cast([^]Native_Text_Vertex)mapped
	for vertex, i in vertices { destination[i] = vertex }
	sdl3.UnmapGPUTransferBuffer(device, vertex_transfer)
	copy_pass := sdl3.BeginGPUCopyPass(command)
	if copy_pass == nil { return false }
	source := sdl3.GPUTransferBufferLocation{transfer_buffer=vertex_transfer, offset=0}
	destination_region := sdl3.GPUBufferRegion{
		buffer=vertex_buffer,
		offset=0,
		size=sdl3.Uint32(len(vertices) * size_of(Native_Text_Vertex)),
	}
	sdl3.UploadToGPUBuffer(copy_pass, source, destination_region, true)
	sdl3.EndGPUCopyPass(copy_pass)
	vertices_uploaded^ += 1
	return true
}

// Solid and icon meshes share the same vertex buffer growth and retirement
// contract. Keep the buffer handles and capacity explicit so both renderers
// use the same allocation path.
native_vertex_buffer_ensure_capacity :: proc(
	device: ^sdl3.GPUDevice,
	vertex_buffer: ^^sdl3.GPUBuffer,
	vertex_transfer: ^^sdl3.GPUTransferBuffer,
	vertex_capacity: ^int,
	required: int,
) -> bool {
	maximum := int(sdl3.Uint32(0xFFFFFFFF) / sdl3.Uint32(size_of(Native_Text_Vertex)))
	new_capacity := native_next_vertex_capacity(vertex_capacity^, required, maximum)
	if new_capacity == 0 { return false }
	if new_capacity == vertex_capacity^ { return true }
	new_size := sdl3.Uint32(new_capacity * size_of(Native_Text_Vertex))
	new_buffer := sdl3.CreateGPUBuffer(device, sdl3.GPUBufferCreateInfo{
		usage=sdl3.GPUBufferUsageFlags{.VERTEX}, size=new_size,
	})
	if new_buffer == nil { return false }
	new_transfer := sdl3.CreateGPUTransferBuffer(device, sdl3.GPUTransferBufferCreateInfo{
		usage=.UPLOAD, size=new_size,
	})
	if new_transfer == nil {
		sdl3.ReleaseGPUBuffer(device, new_buffer)
		return false
	}
	// These buffers are shared by submissions. Wait before replacing them so
	// earlier frames cannot still be reading the old vertex buffer.
	if !sdl3.WaitForGPUIdle(device) {
		sdl3.ReleaseGPUTransferBuffer(device, new_transfer)
		sdl3.ReleaseGPUBuffer(device, new_buffer)
		return false
	}
	sdl3.ReleaseGPUBuffer(device, vertex_buffer^)
	sdl3.ReleaseGPUTransferBuffer(device, vertex_transfer^)
	vertex_buffer^ = new_buffer
	vertex_transfer^ = new_transfer
	vertex_capacity^ = new_capacity
	return true
}
