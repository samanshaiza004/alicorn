package alicorn_sdl_gpu

// Focused retained-effects GPU validation. Readbacks reuse draw_display_list
// and its existing shaders.
import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"
import alicorn "../../runtime"
import "vendor:sdl3"

EFFECT_PROBE_WIDTH :: 384
EFFECT_PROBE_HEIGHT :: 256
EFFECT_PROBE_BUDGET :: 16*1024*1024
EFFECT_PROBE_BACKGROUND :: sdl3.FColor{0.08,0.12,0.18,0.4}

Effect_Probe_Timing :: struct { encode_ns, submit_wait_ns: i64, render_passes: int }

// This fixture contains only Surface/Text commands. Count actual populated
// renderer runs, including clip culling, without adding production telemetry.
effect_probe_draw_passes :: proc(renderers:^Blend_Validation_Renderers, display:[]alicorn.Paint_Command) -> int {
    count,index:=0,0
    for index<len(display) {
        kind,end:=native_paint_run(display,index)
        if kind==.Text {
            for draw in renderers.text.draws {
                if draw.command_index==index { count+=1; break }
            }
        } else if kind==.Surface {
            for draw in renderers.solid.draws[index:end] {
                if draw.vertex_count>0 { count+=1; break }
            }
        }
        index=end
    }
    return count
}

effect_probe_scene :: proc(rt: ^alicorn.Runtime, text: ^Native_Text_Renderer, shadow: bool) -> []alicorn.Paint_Command {
    commands := make([dynamic]alicorn.Paint_Command, allocator=context.temp_allocator)
    clip := alicorn.Rect{0,0,EFFECT_PROBE_WIDTH,EFFECT_PROBE_HEIGHT}
    for i in 0..<12 {
        color := alicorn.Color{0.12+f32(i%3)*0.15,0.3,0.52,0.7}
        append(&commands, alicorn.paint_surface_command(1, {f32(i*32),0,16,EFFECT_PROBE_HEIGHT},clip,color))
    }
    handle := native_text_host_handle(text, 1)
    for i in 0..<9 {
        append(&commands, alicorn.paint_text_command(2,{14,f32(18+i*25),350,22},clip,handle,{0.95,0.85,0.48,0.8}))
    }
    if shadow {
        material := alicorn.style_material_register(rt, {.Analytic_Relief,0,0,0,0.7,8})
        append(&commands, alicorn.paint_surface_command(3,{96,56,192,144},clip,{0,0,0,0},
            shape={.Rounded_Rectangle,10},material=material,physical_height=1))
    }
    return commands[:]
}

effect_probe_local_stream :: proc(display: []alicorn.Paint_Command, origin: alicorn.Rect) -> []alicorn.Paint_Command {
    result := make([]alicorn.Paint_Command,len(display),allocator=context.temp_allocator)
    for draw,i in display {
        result[i] = draw
        result[i].bounds.x -= origin.x; result[i].bounds.y -= origin.y
        result[i].clip.x -= origin.x; result[i].clip.y -= origin.y
    }
    return result
}

effect_probe_clear :: proc(command: ^sdl3.GPUCommandBuffer, target: ^sdl3.GPUTexture, color: sdl3.FColor) -> bool {
    info := make_color_target(target,color,false)
    pass := sdl3.BeginGPURenderPass(command,&info,1,nil)
    if pass == nil { return false }
    sdl3.EndGPURenderPass(pass)
    return true
}

// A fence round trip is reported as such: SDL_GPU exposes no portable GPU
// timestamp query here, so this is not mislabeled as hardware GPU execution time.
effect_probe_frame :: proc(
    renderers: ^Blend_Validation_Renderers, cache: ^Native_Effect_Cache,
    plan: Native_Effect_Plan, display: []alicorn.Paint_Command,
    target: ^sdl3.GPUTexture, download: ^sdl3.GPUTransferBuffer,
    pixels, source_pixels: []u8, use_effect, overlay: bool, backdrop := false,
) -> (timing: Effect_Probe_Timing, ok: bool) {
    started := time.now()
    status := Native_Effect_Status.Inactive
    if use_effect { status = native_effect_prepare(cache,plan) }
    apply_effect:=use_effect && status!=.Fallback && status!=.Inactive
    device := renderers.solid.device
    command := sdl3.AcquireGPUCommandBuffer(device)
    if command == nil { return }
    submitted := false
    defer if !submitted { _ = sdl3.CancelGPUCommandBuffer(command); native_effect_abort(cache) }
    background:=EFFECT_PROBE_BACKGROUND
    if backdrop { background.a=1 }
    if !effect_probe_clear(command,target,background) { return }
    timing.render_passes+=1
    if backdrop {
        if !draw_display_list(command,target,EFFECT_PROBE_WIDTH,EFFECT_PROBE_HEIGHT,
            &renderers.text,&renderers.geometry,&renderers.solid,display,plan.scale,plan.scale,clear_background=false) { return }
        timing.render_passes+=effect_probe_draw_passes(renderers,display)
    }
    if apply_effect {
        if status == .Render {
            source_clear:=sdl3.FColor{}
            // This candidate captures a known opaque paint prefix. Its alpha
            // stays one, replacing the original backdrop without double-over.
            // Transparent isolated-layer behavior is tested separately below.
            if backdrop { source_clear=background }
            if !effect_probe_clear(command,cache.source,source_clear) { return }
            timing.render_passes+=1
            local := effect_probe_local_stream(display,plan.source_bounds)
            if !draw_display_list(command,cache.source,plan.width,plan.height,
                &renderers.text,&renderers.geometry,&renderers.solid,local,plan.scale,plan.scale,clear_background=false) { return }
            timing.render_passes+=effect_probe_draw_passes(renderers,local)
            if !native_effect_encode(cache,command) { return }
            timing.render_passes+=2
        }
        if !native_effect_composite(cache,command,target,EFFECT_PROBE_WIDTH,EFFECT_PROBE_HEIGHT) { return }
        timing.render_passes+=1
    } else if !backdrop {
        if !draw_display_list(command,target,EFFECT_PROBE_WIDTH,EFFECT_PROBE_HEIGHT,
            &renderers.text,&renderers.geometry,&renderers.solid,display,plan.scale,plan.scale,clear_background=false) { return }
        timing.render_passes+=effect_probe_draw_passes(renderers,display)
    }
    if overlay {
        foreground := [1]alicorn.Paint_Command{alicorn.paint_surface_command(4,{40,36,20,16},{0,0,384,256},{1,0,0,0.5})}
        if !draw_display_list(command,target,EFFECT_PROBE_WIDTH,EFFECT_PROBE_HEIGHT,
            &renderers.text,&renderers.geometry,&renderers.solid,foreground[:],plan.scale,plan.scale,clear_background=false) { return }
        timing.render_passes+=effect_probe_draw_passes(renderers,foreground[:])
    }
    if backdrop {
        foreground:=[4]alicorn.Paint_Command{
            alicorn.paint_surface_command(5,{96,56,192,144},{0,0,384,256},{0.14,0.18,0.26,0.78}),
            alicorn.paint_text_command(6,{112,76,160,24},{96,56,192,144},native_text_host_handle(&renderers.text,2),{1,1,1,1}),
            alicorn.paint_surface_command(7,{108,118,168,30},{96,56,192,144},{0.2,0.36,0.58,0.95}),
            alicorn.paint_text_command(8,{116,122,150,24},{96,56,192,144},native_text_host_handle(&renderers.text,3),{1,1,1,1}),
        }
        if !draw_display_list(command,target,EFFECT_PROBE_WIDTH,EFFECT_PROBE_HEIGHT,
            &renderers.text,&renderers.geometry,&renderers.solid,foreground[:],1,1,clear_background=false) { return }
        timing.render_passes+=effect_probe_draw_passes(renderers,foreground[:])
    }
    if len(pixels)>0 || len(source_pixels)>0 {
        copy_pass := sdl3.BeginGPUCopyPass(command)
        if copy_pass == nil { return }
        if len(pixels)>0 {
            sdl3.DownloadFromGPUTexture(copy_pass,
                {texture=target,w=EFFECT_PROBE_WIDTH,h=EFFECT_PROBE_HEIGHT,d=1},
                {transfer_buffer=download,pixels_per_row=EFFECT_PROBE_WIDTH,rows_per_layer=EFFECT_PROBE_HEIGHT})
        }
        if len(source_pixels)>0 {
            sdl3.DownloadFromGPUTexture(copy_pass,{texture=cache.source,w=plan.width,h=plan.height,d=1},
                {transfer_buffer=download,offset=EFFECT_PROBE_WIDTH*EFFECT_PROBE_HEIGHT*4,pixels_per_row=((plan.width+63)/64)*64,rows_per_layer=plan.height})
        }
        sdl3.EndGPUCopyPass(copy_pass)
    }
    timing.encode_ns = time.duration_nanoseconds(time.since(started))
    submit_start := time.now()
    fence := sdl3.SubmitGPUCommandBufferAndAcquireFence(command)
    submitted = true
    if fence == nil { native_effect_abort(cache); return }
    defer sdl3.ReleaseGPUFence(device,fence)
    native_text_commit_submission(&renderers.text)
    native_surface_commit_submission(&renderers.geometry)
    native_solid_commit_submission(&renderers.solid)
    native_effect_commit(cache)
    fences := [1]^sdl3.GPUFence{fence}
    if !sdl3.WaitForGPUFences(device,true,&fences[0],1) { return }
    timing.submit_wait_ns = time.duration_nanoseconds(time.since(submit_start))
    if len(pixels)>0 || len(source_pixels)>0 {
        mapped := sdl3.MapGPUTransferBuffer(device,download,false)
        if mapped == nil { return }
        bytes := cast([^]u8)mapped
        copy(pixels,bytes[:len(pixels)])
        if len(source_pixels)>0 {
            stride:=int(((plan.width+63)/64)*64)*4
            row_bytes:=int(plan.width)*4
            for y in 0..<int(plan.height) {
                copy(source_pixels[y*row_bytes:][:row_bytes],bytes[EFFECT_PROBE_WIDTH*EFFECT_PROBE_HEIGHT*4+y*stride:][:row_bytes])
            }
        }
        sdl3.UnmapGPUTransferBuffer(device,download)
    }
    return timing,true
}

// Dense CPU Gaussian oracle. The GPU uses bilinear-paired taps and half-float
// accumulation; this reference uses every integer kernel coefficient directly.
effect_probe_reference :: proc(plan: Native_Effect_Plan, source, actual: []u8, overlay: bool) -> bool {
    w,h := int(plan.width),int(plan.height)
    weights, radius, weights_ok := native_effect_gaussian_weights(plan.sigma_pixels)
    if !weights_ok { return false }
    center := NATIVE_EFFECT_MAX_GAUSSIAN_RADIUS_PIXELS
    normalized := make([]f32,len(source),allocator=context.temp_allocator)
    ping := make([]f32,len(source),allocator=context.temp_allocator)
    filtered := make([]f32,len(source),allocator=context.temp_allocator)
    for value,index in source { normalized[index]=f32(value)/255 }
    for axis in 0..<2 {
        input,output := normalized,ping
        if axis==1 { input,output=ping,filtered }
        for y in 0..<h { for x in 0..<w { for c in 0..<4 {
            sum := f32(0)
            for offset in -radius..<(radius+1) {
                sx,sy := x,y
                if axis==0 { sx=clamp(x+offset,0,w-1) } else { sy=clamp(y+offset,0,h-1) }
                sum += input[(sy*w+sx)*4+c]*weights[center+offset]
            }
            output[(y*w+x)*4+c]=sum
        } } }
    }
    clip := plan.output_clip
    x0,y0,x1,y1 := logical_to_pixel_bounds(clip,plan.scale,plan.scale)
    ox,oy := int(math.round(plan.source_bounds.x*plan.scale)),int(math.round(plan.source_bounds.y*plan.scale))
    background := [4]f32{0.08,0.12,0.18,0.4}
    worst := 0
    for y in 0..<EFFECT_PROBE_HEIGHT { for x in 0..<EFFECT_PROBE_WIDTH {
        expected:=background
        effect_index := -1
        if x>=x0 && x<x1 && y>=y0 && y<y1 {
            index:=((y-oy)*w+x-ox)*4
            effect_index = index
            a:=filtered[index+3]
            for c in 0..<4 { expected[c]=filtered[index+c]+background[c]*(1-a) }
        }
        if overlay && x>=int(40*plan.scale) && x<int(60*plan.scale) && y>=int(36*plan.scale) && y<int(52*plan.scale) {
            expected=blend_validation_over(expected,{1,0,0,0.5})
        }
        for c in 0..<4 {
            delta:=abs(int(actual[(y*EFFECT_PROBE_WIDTH+x)*4+c])-int(math.round(expected[c]*255)))
            worst=max(worst,delta)
            if delta>3 {
                if effect_index >= 0 {
                    fmt.println("effects_pixel_mismatch","scale",plan.scale,"pixel",x,y,"channel",c,"error",delta,
                        "actual",actual[(y*EFFECT_PROBE_WIDTH+x)*4+c],"expected",expected[c],
                        "expected_byte",math.round(expected[c]*255),"filtered_rgba",filtered[effect_index:effect_index+4])
                } else {
                    fmt.println("effects_pixel_mismatch","scale",plan.scale,"pixel",x,y,"channel",c,"error",delta,
                        "actual",actual[(y*EFFECT_PROBE_WIDTH+x)*4+c],"expected",expected[c])
                }
                return false
            }
        }
    } }
    fmt.println("effects_gaussian_readback","scale",plan.scale,"sigma_pixels",plan.sigma_pixels,
        "kernel_radius",radius,"paired_taps",plan.filter_tap_count,"worst_rgba8_error",worst,"painter_order",overlay)
    return true
}

effect_probe_ppm :: proc(path: string, pixels: []u8) -> bool {
    builder:=strings.builder_make(allocator=context.temp_allocator)
    fmt.sbprintf(&builder,"P6\n%d %d\n255\n",EFFECT_PROBE_WIDTH,EFFECT_PROBE_HEIGHT)
    for i in 0..<EFFECT_PROBE_WIDTH*EFFECT_PROBE_HEIGHT {
        for c in 0..<3 { strings.write_byte(&builder,pixels[i*4+c]) }
    }
    return os.write_entire_file(path,strings.to_string(builder))==nil
}

effect_probe_device :: proc(driver: cstring) -> bool {
    device:=sdl3.CreateGPUDevice({.DXIL,.MSL,.SPIRV},true,driver)
    if device==nil { return false }
    defer sdl3.DestroyGPUDevice(device)
    fmt.println("effects_gpu_validation","driver",sdl3.GetGPUDeviceDriver(device),"sdl_version",sdl3.GetVersion(),
        "source_format","RGBA8_UNORM","filter_format","RGBA16_FLOAT","color_space","encoded SDR (not linear-light blur)")
    rt:=alicorn.new_runtime({0,0,384,256})
    defer alicorn.destroy_runtime(&rt)
    renderers:Blend_Validation_Renderers
    ok:=false
    renderers.text,ok=native_text_make(device,.R8G8B8A8_UNORM,&rt)
    if !ok { return false }; defer native_text_destroy(&renderers.text)
    renderers.geometry,ok=native_surface_make(device,.R8G8B8A8_UNORM,&rt)
    if !ok { return false }; defer native_surface_destroy(&renderers.geometry)
    renderers.solid,ok=native_solid_make(device,.R8G8B8A8_UNORM,&rt)
    if !ok { return false }; defer native_solid_destroy(&renderers.solid)
    if !alicorn.text_engine_load_font(&rt.text_engine,NATIVE_UI_FONT_DATA) { return false }
    run,shaped:=alicorn.text_run_build(&rt.text_engine,"Retained UI: source / palette / selection",14)
    if !shaped || !native_text_register_host_run(&renderers.text,1,run) { return false }
    title,title_ok:=alicorn.text_run_build(&rt.text_engine,"Quick Open",18)
    if !title_ok || !native_text_register_host_run(&renderers.text,2,title) { return false }
    entry,entry_ok:=alicorn.text_run_build(&rt.text_engine,"notes.md",14)
    if !entry_ok || !native_text_register_host_run(&renderers.text,3,entry) { return false }
    display:=effect_probe_scene(&rt,&renderers.text,false)
    analytic:=effect_probe_scene(&rt,&renderers.text,true)
    target:=sdl3.CreateGPUTexture(device,{type=.D2,format=.R8G8B8A8_UNORM,usage={.COLOR_TARGET},width=384,height=256,layer_count_or_depth=1,num_levels=1,sample_count=._1})
    if target==nil { return false }; defer sdl3.ReleaseGPUTexture(device,target)
    download:=sdl3.CreateGPUTransferBuffer(device,{usage=.DOWNLOAD,size=EFFECT_PROBE_WIDTH*EFFECT_PROBE_HEIGHT*4+EFFECT_PROBE_BUDGET})
    if download==nil { return false }; defer sdl3.ReleaseGPUTransferBuffer(device,download)
    pixels:=make([]u8,EFFECT_PROBE_WIDTH*EFFECT_PROBE_HEIGHT*4,allocator=context.temp_allocator)
    cache:=native_effect_make(device,EFFECT_PROBE_BUDGET)
    defer native_effect_reset(&cache)
    // Initial disabled scene never initializes an effect pipeline or texture.
    for _ in 0..<100 { if native_effect_prepare(&cache,{})!=.Inactive { return false } }
    if cache.allocations!=0 || cache.filter_passes!=0 || cache.live_bytes!=0 { return false }
    request:=Native_Effect_Request{enabled=true,key=1,source_generation=1,region={16,16,128,96},clip={24,20,116,92},scale=1,sigma=4,depth=1}
    plan:Native_Effect_Plan
    for sigma in ([3]f32{1,4,8}) {
        request.sigma=sigma
        for scale in ([3]f32{1,1.5,2}) {
            request.scale=scale
            plan,ok=native_effect_plan(request)
            if !ok { return false }
            source:=make([]u8,int(plan.width*plan.height*4),allocator=context.temp_allocator)
            _,ok=effect_probe_frame(&renderers,&cache,plan,display,target,download,pixels,source,true,true)
            if !ok || !effect_probe_reference(plan,source,pixels,true) { return false }
        }
    }
    generation,allocations,passes:=cache.output_generation,cache.allocations,cache.filter_passes
    uploads:=cache.vertex_upload_bytes
    for _ in 0..<100 { if native_effect_prepare(&cache,plan)!=.Cached { return false } }
    if cache.output_generation!=generation || cache.allocations!=allocations || cache.filter_passes!=passes { return false }
    fmt.println("effects_unchanged","attempts",100,"new_passes",0,"new_allocations",0,"new_submissions",0)
    previous:=make([]u8,len(pixels),allocator=context.temp_allocator)
    copy(previous,pixels)
    changed:=make([]alicorn.Paint_Command,len(display),allocator=context.temp_allocator)
    copy(changed,display)
    changed[2].payload=alicorn.Surface_Paint{fill={0,1,0,0.6}}
    plan.source_generation+=1
    source:=make([]u8,int(plan.width*plan.height*4),allocator=context.temp_allocator)
    _,ok=effect_probe_frame(&renderers,&cache,plan,changed,target,download,pixels,source,true,true)
    if !ok || !effect_probe_reference(plan,source,pixels,true) { return false }
    if cache.vertex_upload_bytes!=uploads { fmt.println("effects_source_change_reuploaded_filter_mesh"); return false }
    difference:=false
    for value,i in pixels { if value!=previous[i] { difference=true; break } }
    if !difference { fmt.println("effects_source_change_was_invisible"); return false }
    copy(previous,pixels)
    // Retained and freshly repainted output must agree byte-for-byte.
    _,ok=effect_probe_frame(&renderers,&cache,plan,changed,target,download,pixels,nil,true,true)
    if !ok { return false }
    for value,i in pixels { if value!=previous[i] { return false } }
    native_effect_reset(&cache)
    _,ok=effect_probe_frame(&renderers,&cache,plan,changed,target,download,pixels,nil,true,true)
    if !ok { return false }
    for value,i in pixels { if value!=previous[i] { return false } }
    // An abandoned generation must not become a valid retained output.
    plan.source_generation+=1
    if native_effect_prepare(&cache,plan)!=.Render { return false }
    native_effect_abort(&cache)
    if native_effect_prepare(&cache,plan)!=.Render { return false }
    native_effect_abort(&cache)
    native_effect_reset(&cache)
    fmt.println("effects_retirement","live_bytes",cache.live_bytes)
    request.scale=1; request.sigma=4; request.region={96,56,192,144}; request.clip=request.region
    plan,ok=native_effect_plan(request)
    if !ok { return false }
    for mode in 0..<4 {
        encodes,waits: [40]i64
        native_effect_reset(&cache)
        cache=native_effect_make(device,EFFECT_PROBE_BUDGET)
        before_allocations,before_passes:=cache.allocations,cache.filter_passes
        warm_render_passes:=0
        for i in 0..<41 {
            if mode==2 { plan.source_generation+=1 }
            scene:=display
            if mode==1 { scene=analytic }
            var_output:[]u8
            if i==0 { var_output=pixels }
            timing,rendered:=effect_probe_frame(&renderers,&cache,plan,scene,target,download,var_output,nil,mode>=2,false,backdrop=true)
            if !rendered { return false }
            if i==0 {
                fmt.println("effects_first_frame","mode",mode,"encode_ns",timing.encode_ns,"submit_wait_ns",timing.submit_wait_ns,"render_passes",timing.render_passes)
                names:=[4]string{"flat","analytic-shadow","blur-cold","blur-retained"}
                if !effect_probe_ppm(fmt.tprintf("out/retained-effects/%s.ppm",names[mode]),pixels) { return false }
            } else { encodes[i-1]=timing.encode_ns; waits[i-1]=timing.submit_wait_ns; warm_render_passes=timing.render_passes }
        }
        slice.sort(encodes[:]); slice.sort(waits[:])
        fmt.println("effects_warm","mode",mode,"samples",40,"encode_p95_ns",encodes[37],"submit_wait_p95_ns",waits[37],
            "render_passes",warm_render_passes,"allocations",cache.allocations-before_allocations,"filter_passes",cache.filter_passes-before_passes,
            "live_bytes",cache.live_bytes,"peak_bytes",cache.peak_bytes,"effect_upload_bytes_total",cache.vertex_upload_bytes)
    }
    tiny:=native_effect_make(device,1)
    defer native_effect_reset(&tiny)
    if native_effect_prepare(&tiny,plan)!=.Fallback || tiny.live_bytes!=0 { return false }
    _,ok=effect_probe_frame(&renderers,&cache,plan,display,target,download,previous,nil,false,false)
    if !ok { return false }
    _,ok=effect_probe_frame(&renderers,&tiny,plan,display,target,download,pixels,nil,true,false)
    if !ok { return false }
    for value,i in pixels { if value!=previous[i] { return false } }
    fmt.println("effects_gpu_validation PASS","dense_gaussian_reference_cases",9,"cache_equals_fresh",true,"budget_fallback",true,"nesting_limit",1)
    return true
}

RunRetainedEffectsValidation :: proc() {
    driver:cstring=nil
    when ODIN_OS==.Darwin { driver="metal" }
    when ODIN_OS==.Windows { driver="direct3d12" }
    when ODIN_OS==.Linux { driver="vulkan" }
    for arg in os.args[1:] {
        switch arg {
        case "--driver=metal": driver="metal"
        case "--driver=vulkan": driver="vulkan"
        case "--driver=direct3d12": driver="direct3d12"
        case: fail("unknown effects-validation argument")
        }
    }
    // SDL GPU requires the video subsystem. No window/swapchain is created,
    // but initialization failure is reported rather than treated as a skip.
    if !sdl3.Init(sdl3.INIT_VIDEO) { fail("effects SDL initialization failed") }
    defer sdl3.Quit()
    if !effect_probe_device(driver) { fail("retained effects experiment failed") }
}
