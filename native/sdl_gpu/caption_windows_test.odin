#+build windows

package alicorn_sdl_gpu

import "core:mem"
import "core:testing"
import win "core:sys/windows"
import alicorn "../../runtime"

@(test)
test_caption_repeated_activation_preserves_hover_and_requests_no_frame :: proc(t: ^testing.T) {
	menu := Native_Menu_Runtime{}
	state := Win32_Menu_State{menu=&menu,active=true,caption_hovered=1,caption_pressed=1}
	for _ in 0..<10_000 { testing.expect(t,!win32_menu_set_active(&state,true)) }
	testing.expect(t,!menu.chrome_redraw_pending && state.caption_hovered == 1 && state.caption_pressed == 1,
		"duplicate activation notifications must not clear hover or wake the renderer")
	testing.expect(t,win32_menu_set_active(&state,false))
	testing.expect(t,menu.chrome_redraw_pending && state.caption_hovered == -1 && state.caption_pressed == -1)
	menu.chrome_redraw_pending = false
	testing.expect(t,!win32_menu_set_active(&state,false) && !menu.chrome_redraw_pending)
	testing.expect(t,win32_menu_set_active(&state,true) && menu.chrome_redraw_pending)
}

@(test)
test_caption_fallback_is_bounded_when_dwm_is_unavailable :: proc(t: ^testing.T) {
	dpis := [4]u32{96,120,144,192}
	for dpi in dpis {
		for width in 1..<320 {
			controls := win32_caption_layout_controls({}, false, i32(width), 32, dpi, true)
			for control in controls {
				testing.expect(t, control.bounds.left >= 0 && control.bounds.right <= win.LONG(width) && control.bounds.right >= control.bounds.left)
			}
			testing.expect_value(t, controls[2].bounds.right, win.LONG(width))
		}
		invalid := win32_caption_layout_controls(win.RECT{10,20,200,20}, true, 500, 32, dpi, true)
		fallback := win32_caption_layout_controls({}, false, 500, 32, dpi, true)
		testing.expect(t, invalid == fallback, "undefined or zero-height DWM rectangles must use the bounded fallback")
	}
}

@(test)
test_caption_masks_have_shared_metrics_and_occluded_restore_edges :: proc(t: ^testing.T) {
	dpis := [4]u32{96,120,144,192}
	versions := [2]bool{false,true}
	for dpi in dpis {
		for windows_11 in versions {
			for icon in Win32_Caption_Icon {
				mask := win32_caption_build_mask(icon,dpi,windows_11,context.allocator)
				testing.expect_value(t, mask.size, native_pixel_edge(10,f32(dpi)/96))
				testing.expect_value(t, len(mask.pixels), mask.size*mask.size)
				ink := 0
				for coverage in mask.pixels { if coverage != 0 { ink += 1 } }
				testing.expect(t, ink > 0 && ink < len(mask.pixels), "all symbols must have ink and open background")
				if icon == .Restore {
					// The old unoccluded rear square drew a horizontal edge here.
					x := mask.size/2
					y := mask.size-int(native_pixel_edge(2,f32(dpi)/96))-1
					testing.expect(t, mask.pixels[y*mask.size+x] == 0, "rear edges cannot appear inside the front window")
				}
				delete(mask.pixels)
			}
		}
	}
}

@(test)
test_caption_masks_reuse_storage_until_dpi_changes_and_release_it :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking,context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	state := Win32_Menu_State{allocator=mem.tracking_allocator(&tracking),windows_11=true}
	testing.expect(t,win32_caption_sync_masks(&state),"unspecified DPI defaults to 96 and must still build masks")
	testing.expect_value(t,state.caption_mask_builds,u64(1))
	first := raw_data(state.caption_masks[3].pixels)
	for _ in 0..<10_000 { testing.expect(t,win32_caption_sync_masks(&state)) }
	testing.expect(t,state.caption_mask_builds == 1 && first == raw_data(state.caption_masks[3].pixels))
	state.dpi = 144
	testing.expect(t,win32_caption_sync_masks(&state))
	testing.expect_value(t,state.caption_masks[3].size,15)
	testing.expect(t,len(tracking.allocation_map) == 4,"replacing the DPI cache must release all old masks")
	state.windows_11 = false
	testing.expect(t,win32_caption_sync_masks(&state))
	testing.expect_value(t,state.caption_mask_builds,u64(3))
	win32_caption_destroy_masks(&state)
	testing.expect_value(t,len(tracking.allocation_map),0)
}

@(test)
test_caption_text_clips_to_label_allocations_and_refreshes_only_for_scale :: proc(t: ^testing.T) {
	rt := alicorn.new_runtime(alicorn.Rect{0,0,900,600})
	defer alicorn.destroy_runtime(&rt)
	testing.expect(t,alicorn.text_engine_load_font(&rt.text_engine,NATIVE_UI_FONT_DATA))
	renderer := Native_Text_Renderer{runtime=&rt}
	defer native_text_destroy(&renderer)
	labels := [1]Win32_Menu_Label{{host_node=NATIVE_MENU_HOST_NODE_BASE+1}}
	menus := [1]Application_Menu{{label="Extraordinarily long menu label"}}
	app := Application{menus=menus[:],window_decorations=.Integrated_Title_Bar}
	menu := Native_Menu_Runtime{application=&app}
	state := Win32_Menu_State{menu=&menu,dpi=96,pixels_per_unit=1,text_renderer=&renderer,
		title_text="A disproportionately long window title",title=Win32_Menu_Label{host_node=NATIVE_MENU_HOST_NODE_BASE},
		ellipsis_host_node=NATIVE_MENU_HOST_NODE_BASE+3,labels=labels[:]}
	testing.expect(t,win32_menu_refresh_text(&state,&rt))
	old_handle := native_text_host_handle(&renderer,state.title.host_node)
	shape_calls := rt.text_engine.shape_calls
	generation := renderer.host_run_generation
	for _ in 0..<100 { testing.expect(t,win32_menu_refresh_text(&state,&rt)) }
	testing.expect(t,shape_calls == rt.text_engine.shape_calls && generation == renderer.host_run_generation)
	state.dpi = 144
	testing.expect(t,win32_menu_refresh_text(&state,&rt))
	testing.expect(t,native_text_host_resolve(&renderer,old_handle) == nil,"old text handles must not resolve after DPI replacement")
	testing.expect(t,len(renderer.host_runs) == 3,"DPI updates must replace host runs rather than accumulating them")
	testing.expect_value(t,native_text_host_run(&renderer,state.title.host_node).size,f32(21))
	densities := [2]f32{1,2}
	widths := [3]i32{200,500,1200}
	for density in densities {
		state.pixels_per_unit = density
		testing.expect(t,win32_menu_refresh_text(&state,&rt))
		for width in widths {
			state.chrome_height_pixels = 48
			state.caption_controls = win32_caption_layout_controls({},false,width,48,144,true)
			win32_menu_layout_label_bounds(&state)
			commands := make([dynamic]alicorn.Paint_Command)
			win32_menu_append_text(&commands,&state,state.title,8,alicorn.Color{1,1,1,1},ellipsis=true)
			win32_menu_append_text(&commands,&state,state.labels[0],12,alicorn.Color{1,1,1,1})
			for command in commands {
				_,_,right,_ := logical_to_pixel_bounds(command.clip,density,density)
				testing.expect(t,right <= int(state.caption_controls[0].bounds.left),"title/menu clips cannot enter caption controls")
				if command.owner == state.labels[0].host_node { testing.expect(t,command.clip.x*density >= f32(state.labels[0].bounds.left)) }
			}
			delete(commands)
		}
	}
	testing.expect(t,rt.stats.frames_built == 0,"native chrome refresh must not describe application nodes")
}
