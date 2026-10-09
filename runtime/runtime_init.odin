package alicorn
import "core:mem"

new_runtime :: proc(viewport: Rect, config := Runtime_Config{}) -> Runtime {
	persistent_backing_allocator := config.persistent_allocator
	if persistent_backing_allocator.procedure == nil {
		persistent_backing_allocator = context.allocator
	}
	scratch_backing_allocator := config.scratch_backing_allocator
	if scratch_backing_allocator.procedure == nil {
		scratch_backing_allocator = persistent_backing_allocator
	}
	capacity := config.trace_capacity
	if capacity < 1 { capacity = 1 }
	stats := config.allocation_stats
	stats_owned := false
	if stats == nil {
		stats = new(Runtime_Allocation_Stats, allocator=persistent_backing_allocator)
		stats_owned = true
	}
	persistent_state := new(Runtime_Allocator_State, allocator=persistent_backing_allocator)
	persistent_state^ = Runtime_Allocator_State{backing=persistent_backing_allocator, stats=stats, scratch=false}
	rt := Runtime{
		persistent_backing_allocator = persistent_backing_allocator,
		persistent_allocator = runtime_allocator(persistent_state),
		scratch_backing_allocator = scratch_backing_allocator,
		allocation_stats = stats,
		allocation_stats_owned = stats_owned,
		persistent_allocator_state = persistent_state,
		viewport = viewport,
		presentation_scale_x = 1,
		presentation_scale_y = 1,
		style_environment = DEFAULT_STYLE_ENVIRONMENT,
		invalidated = true,
	}
	rt.scratch_arena = new(mem.Dynamic_Arena, allocator=rt.persistent_allocator)
	mem.dynamic_arena_init(rt.scratch_arena, block_allocator=scratch_backing_allocator, array_allocator=rt.persistent_allocator)
	rt.scratch_allocator_state = new(Runtime_Allocator_State, allocator=rt.persistent_allocator)
	rt.scratch_allocator_state^ = Runtime_Allocator_State{
		backing=mem.dynamic_arena_allocator(rt.scratch_arena),
		stats=stats,
		scratch=true,
	}
	rt.scratch_allocator = runtime_allocator(rt.scratch_allocator_state)
	rt.nodes = make(map[Node_ID]^Node, allocator=rt.persistent_allocator)
	rt.measure_states = make(map[Node_ID]Measure_State, allocator=rt.persistent_allocator)
	rt.finalized_geometry = make(map[Node_ID]Finalized_Geometry, allocator=rt.persistent_allocator)
	rt.computed_styles = make(map[Node_ID]Computed_Style, allocator=rt.persistent_allocator)
	rt.semantic_surfaces = make(map[Node_ID]Semantic_Surface_Style, allocator=rt.persistent_allocator)
	rt.visual_parts = make(map[Node_ID]Visual_Part_Style, allocator=rt.persistent_allocator)
	rt.semantic_entities = make(map[Semantic_ID]Semantic_Entity, allocator=rt.persistent_allocator)
	rt.semantic_pending_changed = make(map[Semantic_ID]bool, allocator=rt.persistent_allocator)
	rt.semantic_pending_added = make(map[Semantic_ID]bool, allocator=rt.persistent_allocator)
	rt.semantic_pending_structure = make(map[Semantic_ID]bool, allocator=rt.persistent_allocator)
	rt.semantic_pending_removed = make(map[Semantic_ID]bool, allocator=rt.persistent_allocator)
	rt.semantic_last_changed = make([dynamic]Semantic_ID, 0, allocator=rt.persistent_allocator)
	rt.semantic_last_removed = make([dynamic]Semantic_ID, 0, allocator=rt.persistent_allocator)
	rt.semantic_collection_touched = make(map[Semantic_ID]u64, allocator=rt.persistent_allocator)
	rt.semantic_requests = make([dynamic]Semantic_Request_Event, 0, allocator=rt.persistent_allocator)
	rt.order = make([dynamic]Node_ID, 0, allocator=rt.persistent_allocator)
	rt.top_level = make([dynamic]Node_ID, 0, allocator=rt.persistent_allocator)
	rt.pending = make([dynamic]Pending_Item, 0, allocator=rt.persistent_allocator)
	rt.seen = make(map[Node_ID]Identity_Declaration, allocator=rt.persistent_allocator)
	rt.identity_scopes = make(map[Node_ID]Identity_Declaration, allocator=rt.persistent_allocator)
	rt.grid_pending_scopes = make(map[Node_ID]bool, allocator=rt.persistent_allocator)
	rt.stack = make([dynamic]Node_ID, 0, allocator=rt.persistent_allocator)
	rt.identity_stack = make([dynamic]Node_ID, 0, allocator=rt.persistent_allocator)
	rt.identity_labels = make([dynamic]string, 0, allocator=rt.persistent_allocator)
	rt.identity_key_u64 = make([dynamic]u64, 0, allocator=rt.persistent_allocator)
	rt.identity_key_numeric = make([dynamic]bool, 0, allocator=rt.persistent_allocator)
	rt.identity_key_kind = make([dynamic]u8, 0, allocator=rt.persistent_allocator)
	rt.identity_key_pair = make([dynamic]UI_Key_Pair, 0, allocator=rt.persistent_allocator)
	rt.style_themes = make([dynamic]Style_Theme, 0, allocator=rt.persistent_allocator)
	append(&rt.style_themes, DEFAULT_STYLE_THEME)
	rt.style_materials = make([dynamic]Style_Material, 0, allocator=rt.persistent_allocator)
	rt.style_scope_stack = make([dynamic]Style_Environment_Scope, 0, allocator=rt.persistent_allocator)
	rt.adaptive_description_scopes = make([dynamic]Adaptive_Description_Scope, 0, allocator=rt.persistent_allocator)
	rt.layout_roots = make([dynamic]Node_ID, 0, allocator=rt.persistent_allocator)
	rt.paint_queue = make([dynamic]Node_ID, 0, allocator=rt.persistent_allocator)
	rt.display = make([dynamic]Paint_Command, 0, allocator=rt.persistent_allocator)
	rt.display_target = make([dynamic]Paint_Command, 0, allocator=rt.persistent_allocator)
	rt.trace = Trace_Ring{events = make([dynamic]Trace_Event, capacity, allocator=rt.persistent_allocator)}
	rt.actions = make([dynamic]Action_Entry, 0, allocator=rt.persistent_allocator)
	rt.text_engine = new_text_engine("runtime text", false, rt.persistent_allocator)
	return rt
}

