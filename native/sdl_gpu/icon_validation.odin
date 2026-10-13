package alicorn_sdl_gpu

import "core:fmt"
import "core:math"
import alicorn "../../runtime"
import "vendor:sdl3"

native_icon_readback_case :: proc(renderer: ^Native_Icon_Renderer, scale: f32, layers: int, tint := alicorn.Color{1,0.25,0.5,0.8}) -> bool {
    device := renderer.device
    width, height := sdl3.Uint32(256), sdl3.Uint32(128)
    target := sdl3.CreateGPUTexture(device, sdl3.GPUTextureCreateInfo{type=.D2, format=.R8G8B8A8_UNORM, usage={.COLOR_TARGET}, width=width, height=height, layer_count_or_depth=1, num_levels=1, sample_count=._1})
    if target == nil { return false }
    defer sdl3.ReleaseGPUTexture(device, target)
    download := sdl3.CreateGPUTransferBuffer(device, sdl3.GPUTransferBufferCreateInfo{usage=.DOWNLOAD, size=width*height*4})
    if download == nil { return false }
    defer sdl3.ReleaseGPUTransferBuffer(device, download)
    command := sdl3.AcquireGPUCommandBuffer(device)
    if command == nil { return false }
    submitted := false
    defer if !submitted { _ = sdl3.CancelGPUCommandBuffer(command) }
    clear_target := sdl3.GPUColorTargetInfo{texture=target, clear_color={}, load_op=.CLEAR, store_op=.STORE}
    pass := sdl3.BeginGPURenderPass(command, &clear_target, 1, nil)
    if pass == nil { return false }
    sdl3.EndGPURenderPass(pass)
    draw := alicorn.paint_icon_command(1, alicorn.Rect{8,8,16,16}, alicorn.Rect{0,0,256,128}, .Search, tint, opacity=0.5)
    display := [2]alicorn.Paint_Command{draw,draw}
    if !native_icon_build(renderer, display[:layers], scale, scale, width, height) { return false }
    if !native_icon_upload(renderer, command) { return false }
    if !native_icon_render_batch(renderer, command, target, width, height, renderer.draws[:]) { return false }
    copy_pass := sdl3.BeginGPUCopyPass(command)
    if copy_pass == nil { return false }
    source := sdl3.GPUTextureRegion{texture=target, w=width, h=height, d=1}
    destination := sdl3.GPUTextureTransferInfo{transfer_buffer=download, pixels_per_row=width, rows_per_layer=height}
    sdl3.DownloadFromGPUTexture(copy_pass, source, destination)
    sdl3.EndGPUCopyPass(copy_pass)
    fence := sdl3.SubmitGPUCommandBufferAndAcquireFence(command)
    submitted = true
    if fence == nil { return false }
    defer sdl3.ReleaseGPUFence(device, fence)
    fences := [1]^sdl3.GPUFence{fence}
    if !sdl3.WaitForGPUFences(device, true, &fences[0], 1) { return false }
    renderer.upload_pending = false
    mapped := sdl3.MapGPUTransferBuffer(device, download, false)
    if mapped == nil { return false }
    defer sdl3.UnmapGPUTransferBuffer(device, download)
    pixels := cast([^]u8)mapped
    x0,y0,x1,y1 := logical_to_pixel_bounds(draw.bounds, scale, scale)
    entry, valid := alicorn.icon_atlas_lookup(.Search, x1-x0)
    if !valid { return false }
    page := alicorn.ICON_ATLAS_PAGES[entry.page]
    for y in 0..<int(height) {
        for x in 0..<int(width) {
            expected_alpha: f32 = 0
            if x >= x0 && x < x1 && y >= y0 && y < y1 {
                coverage := f32(page.pixels[(entry.y+y-y0)*page.width+entry.x+x-x0])/255
                alpha := coverage*tint.a*0.5
                for layer in 0..<layers { expected_alpha = alpha+(1-alpha)*expected_alpha }
            }
            offset := (y*int(width)+x)*4
            expected := [4]f32{expected_alpha*tint.r, expected_alpha*tint.g, expected_alpha*tint.b, expected_alpha}
            for channel in 0..<4 {
                if abs(f32(pixels[offset+channel])-math.round(expected[channel]*255)) > 2 {
                    fmt.println("icon_readback_mismatch", "scale",scale,"layers",layers,"pixel",x,y,"channel",channel,"actual",pixels[offset+channel],"expected",expected[channel]*255)
                    return false
                }
            }
        }
    }
    return true
}

native_icon_validate_device :: proc() -> bool {
    driver: cstring = nil
    when ODIN_OS == .Windows { driver = "direct3d12" }
    when ODIN_OS == .Darwin { driver = "metal" }
    device := sdl3.CreateGPUDevice({.DXIL,.MSL,.SPIRV}, false, driver)
    if device == nil { return false }
    defer sdl3.DestroyGPUDevice(device)
    renderer, ok := native_icon_make(device, .R8G8B8A8_UNORM, nil)
    if !ok { return false }
    defer native_icon_destroy(&renderer)
    uploads := renderer.atlas_uploads
    scales := [4]f32{1,1.25,1.5,2}
    for scale in scales {
        for layers in 1..=2 {
            if !native_icon_readback_case(&renderer, scale, layers) { return false }
            rebuilds := renderer.mesh_rebuilds
            if !native_icon_readback_case(&renderer, scale, layers) || renderer.mesh_rebuilds != rebuilds {
                return false
            }
            if !native_icon_readback_case(&renderer, scale, layers, alicorn.Color{0.2,0.8,0.35,0.5}) { return false }
        }
    }
    if renderer.atlas_uploads != uploads { return false }
    fmt.println("icon_gpu_validation", "driver", sdl3.GetGPUDeviceDriver(device), "atlas_uploads",uploads, "atlas_bytes",renderer.atlas_upload_bytes, "mesh_cache_hits",renderer.mesh_cache_hits, "transparent_source_over",true)
    return true
}

// Independent offscreen proof: real sampled masks and transparent source-over
// readback at four DPIs, immutable atlas reuse, then a complete device recreation.
RunIconValidation :: proc() {
    if !sdl3.Init(sdl3.INIT_VIDEO) { fail("icon validation SDL initialization failed") }
    defer sdl3.Quit()
    for cycle in 0..<2 {
        if !native_icon_validate_device() { fail("icon atlas GPU validation failed") }
    }
}
