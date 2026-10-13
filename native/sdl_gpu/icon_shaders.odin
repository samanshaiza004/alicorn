package alicorn_sdl_gpu

// Offline artifacts: DXC v1.9.2609 and glslang 16.6.0. Metal is source compiled
// by SDL on the device. Each fragment shader reads linear R8 coverage exactly once.
GPU_ICON_FRAG_DXIL := #load("icon_shaders/icon.frag.dxil")
GPU_ICON_FRAG_SPV := #load("icon_shaders/icon.frag.spv")
GPU_ICON_FRAG_MSL := #load("icon_shaders/icon.frag.metal")
