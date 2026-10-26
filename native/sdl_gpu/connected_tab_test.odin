package alicorn_sdl_gpu

import "core:testing"
import alicorn "../../runtime"

@(test)
test_connected_tab_contour_has_bounded_dpi_stable_geometry_and_open_baseline :: proc(t:^testing.T) {
	for scale in ([4]f32{1,1.25,1.5,2}) {
		vertices:=make([dynamic]Native_Text_Vertex,0,NATIVE_CONNECTED_TAB_VERTICES,context.temp_allocator)
		defer delete(vertices)
		bounds:=alicorn.Rect{10*scale,20*scale,180*scale,42*scale}
		native_solid_append_connected_tab(&vertices,bounds,{0.9,0.87,0.8,1},1,scale)
		testing.expect(t,len(vertices)==NATIVE_CONNECTED_TAB_VERTICES,"every scale must use the same fixed contour budget")
		for vertex in vertices {
			testing.expect(t,vertex.position[0]>=bounds.x-1 && vertex.position[0]<=bounds.x+bounds.w+1 && vertex.position[1]>=bounds.y && vertex.position[1]<=bounds.y+bounds.h,
				"the contour and antialias fringe must remain within its clipped allocation")
			if vertex.position[1]==bounds.y+bounds.h && vertex.position[0]>=bounds.x && vertex.position[0]<=bounds.x+bounds.w {
				testing.expect(t,vertex.color[3]==1,"the baseline joining paper must be fully opaque without an antialias seam")
			}
		}
	}
}

@(test)
test_connected_paper_gap_omits_only_top_relief_and_stroke :: proc(t:^testing.T) {
	vertices:=make([dynamic]Native_Text_Vertex,0,200,context.temp_allocator)
	defer delete(vertices)
	material:=alicorn.Style_Material{kind=.Analytic_Relief,bevel_width=1,bevel_strength=0.36,inner_shadow_strength=0.18}
	fill:=alicorn.Color{0.94,0.91,0.82,1}
	stroke:=alicorn.Paint_Stroke{color={0,0,0,1},width=1}
	gap:=[2]f32{50,120}
	native_solid_append_material_surface(&vertices,{0,42,200,100},{0,42,200,100},fill,material,-0.75,1,stroke,.Inside,gap)
	testing.expect(t,len(vertices)<=native_solid_material_vertex_count(material,-0.75,stroke=stroke,top_edge_gap=gap),"the split optical edge must stay inside its reserved vertex count")
	// The first quad is the fill. Subsequent top-edge quads may occupy either
	// side of the opening but must not cover its interior with relief or ink.
	for i:=6;i<len(vertices);i+=6 {
		left,right:=vertices[i].position[0],vertices[i+2].position[0]
		top,bottom:=vertices[i].position[1],vertices[i+2].position[1]
		if top>=42 && bottom<=44 {
			testing.expect(t,right<=gap[0] || left>=gap[1],"no top material edge or border may cross the tab-to-paper join")
		}
	}
}
