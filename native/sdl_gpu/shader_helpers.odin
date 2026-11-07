package alicorn_sdl_gpu

import "vendor:sdl3"

// Image and icon fragment shaders share device-format selection while keeping
// their shader programs and compiled artifacts independent.
native_fragment_shader :: proc(
	device: ^sdl3.GPUDevice,
	dxil, msl, spirv: []u8,
) -> ^sdl3.GPUShader {
	if device == nil { return nil }
	supported := sdl3.GetGPUShaderFormats(device)
	info := sdl3.GPUShaderCreateInfo{stage=.FRAGMENT, num_samplers=1}
	if native_shader_supported(supported, {.DXIL}) && len(dxil) > 0 {
		info.format = {.DXIL}
		info.code = &dxil[0]
		info.code_size = uint(len(dxil))
		info.entrypoint = "PSMain"
	} else if native_shader_supported(supported, {.MSL}) && len(msl) > 0 {
		info.format = {.MSL}
		info.code = &msl[0]
		info.code_size = uint(len(msl))
		info.entrypoint = "PSMain"
	} else if native_shader_supported(supported, {.SPIRV}) && len(spirv) > 0 {
		info.format = {.SPIRV}
		info.code = &spirv[0]
		info.code_size = uint(len(spirv))
		info.entrypoint = "main"
	}
	if info.code == nil { return nil }
	return sdl3.CreateGPUShader(device, info)
}
