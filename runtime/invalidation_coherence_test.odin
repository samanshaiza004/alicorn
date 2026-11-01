package alicorn

import "core:fmt"
import "core:strings"
import "core:testing"

// Exercise app-owned state through the public frame/invalidation API. Read
// node snapshots and renderer-facing paint, never retained Node/cache storage.
Coherence_Row :: struct {
	key: string,
	revision: u64,
	value: string,
	scale: f32,
	raised: bool,
}

Coherence_App :: struct {
	parent_revision: u64,
	rows: [3]Coherence_Row,
	order: [3]int,
	count: int,
	status: string,
	status_revision: u64,
	peer_value: string,
	actions: int,
}

coherence_app :: proc() -> Coherence_App {
	return Coherence_App{
		parent_revision=1,
		rows={{"coherence-a", 1, "Alpha", 1, false},
		      {"coherence-b", 1, "Bravo", 1, false},
		      {"coherence-c", 1, "Charlie", 1, false}},
		order={0, 1, 2}, count=3, status="Ready", status_revision=1, peer_value="Unrelated",
	}
}

COHERENCE_FONT :: #load("../assets/fonts/AtkinsonHyperlegibleNext-Variable.ttf")

coherence_setup :: proc(t: ^testing.T, rt: ^Runtime) -> Material_ID {
	testing.expect(t, font_load_bytes(rt, .UI, COHERENCE_FONT), "the fixture font must load through the app API")
	return style_material_register(rt, Style_Material{kind=.Analytic_Relief, bevel_width=1, bevel_strength=0.12})
}

coherence_describe :: proc(ui: ^UI, app: ^Coherence_App, material: Material_ID, regions: ^[3]Node_ID = nil) {
	container_begin(ui, .Root, key=key_string("coherence-root"), style=layout_style(.Column, gap=4))
	text_field(ui, app.status, key=key_string("before-action"), style=layout_style(height=28))
	if button(ui, "Change status", key=key_string("coherence-action"), style=layout_style(width=160, height=32)) {
		scope := application_mutation_begin(ui.runtime, "coherence status", .Description, app.status_revision)
		app.actions += 1
		app.status = "Action consumed"
		app.status_revision += 1
		invalidate_root(ui.runtime, "consumed action changed status")
		application_mutation_end(ui.runtime, &scope, app.status_revision)
	}
	text_field(ui, app.status, key=key_string("after-action"), style=layout_style(height=28))
	parent, reused := region_begin(ui, "coherence-parent", app.parent_revision, style=layout_style(.Column, width=260, height=260, gap=4))
	if parent != 0 && !reused {
		for index in app.order[:app.count] {
			row := app.rows[index]
			id, cached := region_begin(ui, row.key, row.revision, style=layout_style(.Column, width=240, height=80))
			if regions != nil { regions[index] = id }
			if id == 0 || cached { continue }
			scope := style_environment_push(ui, Style_Environment{text_scale=row.scale})
			surface_begin(ui, surface_core_color_role(.Surface), key=key_pair(u64(index), 1),
				style=layout_style(.Column, width=240, height=80, padding=4),
				material=material if row.raised else MATERIAL_FLAT,
				physical_height=1 if row.raised else 0)
			text_field(ui, row.value, key=key_pair(u64(index), 2), style=layout_style(width=220, height=64))
			surface_end(ui)
			style_environment_pop(ui, scope)
			region_end(ui, id, false, 0)
		}
		region_end(ui, parent, false, 0)
	}
	peer, cached := region_begin(ui, "coherence-peer", 1, style=layout_style(width=240, height=32))
	if peer != 0 && !cached {
		text_field(ui, app.peer_value, key=key_string("coherence-peer-text"), style=layout_style(height=28))
		region_end(ui, peer, false, 0)
	}
	container_end(ui)
}

// A bounded host-style description drain, with no synthetic input or mutation
// between passes. A consumed action may request a corrective description.
coherence_settle :: proc(t: ^testing.T, rt: ^Runtime, app: ^Coherence_App, material: Material_ID, regions: ^[3]Node_ID = nil) -> int {
	for pass in 0..<4 {
		ui, build := begin_frame(rt)
		if !build {
			testing.expect(t, !layout_is_pending(rt) && !presentation_needs_frame(rt), "the fixture must settle retained work too")
			return pass
		}
		coherence_describe(&ui, app, material, regions)
		end_frame(&ui)
		inspection := inspect(rt)
		testing.expect(t, !strings.contains(inspection, "HARD ERROR:"), "the fixture must not trigger a runtime contract error")
		delete(inspection)
	}
	testing.expect(t, false, "description side effects must not create an unbounded rebuild loop")
	return 4
}

// The oracle observes only supported queries: Node_Info, controlled text-field
// values/interaction, semantic snapshots, text-line geometry, and the public
// inspector's resolved style/paint summaries. It deliberately avoids Runtime's
// retained node map, display list, and text-run resource table.
coherence_inspector_paint_projection :: proc(rt: ^Runtime) -> string {
	inspection := inspect(rt)
	defer delete(inspection)
	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	line_start := 0
	for index := 0; index <= len(inspection); index += 1 {
		if index != len(inspection) && inspection[index] != '\n' { continue }
		line := inspection[line_start:index]
		if strings.starts_with(line, "  style environment:") {
			fmt.sbprintf(&builder, "%s\n", line)
		} else if strings.starts_with(line, "  semantic surface:") {
			fmt.sbprintf(&builder, "%s\n", coherence_before_marker(line, " resolution="))
		} else if strings.starts_with(line, "  button recipe:") ||
		   strings.starts_with(line, "  optical surface:") ||
		   strings.starts_with(line, "  token provenance:") {
			fmt.sbprintf(&builder, "%s\n", line)
		}
		line_start = index+1
	}
	return strings.to_string(builder)
}

coherence_before_marker :: proc(value, marker: string) -> string {
	if len(marker) == 0 || len(value) < len(marker) { return value }
	for index in 0..=len(value)-len(marker) {
		if value[index:index+len(marker)] == marker { return value[:index] }
	}
	return value
}

coherence_semantic_node_matches :: proc(a, b: Semantic_Node) -> bool {
	if a.id != b.id || a.role != b.role || a.label != b.label || a.description != b.description || a.value != b.value ||
	   a.states != b.states || a.actions != b.actions || a.parent != b.parent || a.visual_node != b.visual_node ||
	   a.bounds != b.bounds || a.has_bounds != b.has_bounds || a.tree_order != b.tree_order ||
	   a.is_collection != b.is_collection || a.logical_count != b.logical_count ||
	   a.realized_first != b.realized_first || a.realized_last != b.realized_last ||
	   a.selected_id != b.selected_id || a.current_id != b.current_id || a.collection_id != b.collection_id ||
	   a.position_in_set != b.position_in_set || a.size_of_set != b.size_of_set ||
	   a.is_virtual_item != b.is_virtual_item || a.numeric_value != b.numeric_value ||
	   a.numeric_minimum != b.numeric_minimum || a.numeric_maximum != b.numeric_maximum ||
	   a.numeric_step != b.numeric_step || a.has_numeric_value != b.has_numeric_value ||
	   a.text_selection != b.text_selection || a.live != b.live || a.live_atomic != b.live_atomic ||
	   len(a.text_run_character_lengths) != len(b.text_run_character_lengths) { return false }
	for value, index in a.text_run_character_lengths {
		if value != b.text_run_character_lengths[index] { return false }
	}
	return true
}

coherence_semantics_match :: proc(a, b: ^Runtime) -> bool {
	left := semantic_snapshot(a, context.temp_allocator)
	defer semantic_snapshot_destroy(&left)
	right := semantic_snapshot(b, context.temp_allocator)
	defer semantic_snapshot_destroy(&right)
	if left.keyboard_focus != right.keyboard_focus || len(left.nodes) != len(right.nodes) { return false }
	for node, index in left.nodes {
		if !coherence_semantic_node_matches(node, right.nodes[index]) { return false }
	}
	return true
}

coherence_public_text_matches :: proc(a, b: ^Runtime, key: UI_Key, kind: Node_Kind) -> bool {
	left_id, left_found := node_by_key(a, key, kind)
	right_id, right_found := node_by_key(b, key, kind)
	if left_found != right_found { return false }
	if !left_found { return true }
	left_info, left_info_found := node_info(a, left_id)
	right_info, right_info_found := node_info(b, right_id)
	if !left_info_found || !right_info_found || left_info != right_info || focused_node(a) != focused_node(b) { return false }
	left_value, left_value_found := text_field_value(a, left_id)
	right_value, right_value_found := text_field_value(b, right_id)
	if left_value_found != right_value_found || (left_value_found && left_value != right_value) { return false }
	left_interaction, left_interaction_found := text_field_interaction(a, left_id)
	right_interaction, right_interaction_found := text_field_interaction(b, right_id)
	if left_interaction_found != right_interaction_found ||
	   (left_interaction_found && left_interaction != right_interaction) { return false }
	left_lines, right_lines := text_node_line_count(a, left_id), text_node_line_count(b, right_id)
	if left_lines != right_lines { return false }
	for index in 0..<left_lines {
		left_line, left_line_found := text_node_line_geometry(a, left_id, index)
		right_line, right_line_found := text_node_line_geometry(b, right_id, index)
		if left_line_found != right_line_found || (left_line_found && left_line != right_line) { return false }
	}
	return true
}

coherence_matches_fresh :: proc(t: ^testing.T, rt: ^Runtime, app: Coherence_App) -> bool {
	fresh := new_runtime(viewport_bounds(rt))
	defer destroy_runtime(&fresh)
	material := coherence_setup(t, &fresh)
	app_copy := app
	_ = coherence_settle(t, &fresh, &app_copy, material)
	if focused_node(rt) != 0 {
		testing.expect(t, focus(&fresh, focused_node(rt)), "the fresh Runtime must receive the same keyboard focus")
		_ = coherence_settle(t, &fresh, &app_copy, material)
	}
	if focused_node(rt) != focused_node(&fresh) || !coherence_semantics_match(rt, &fresh) ||
	   coherence_inspector_paint_projection(rt) != coherence_inspector_paint_projection(&fresh) { return false }
	for index in 0..<len(app.rows) {
		for part in u64(1)..=2 {
			kind := Node_Kind.Container if part == 1 else Node_Kind.Text_Field
			a, aok := node_by_key(rt, key_pair(u64(index), part), kind)
			b, bok := node_by_key(&fresh, key_pair(u64(index), part), kind)
			if aok != bok { return false }
			if !aok { continue }
			ai, _ := node_info(rt, a)
			bi, _ := node_info(&fresh, b)
			if a != b || ai != bi { return false }
			if part == 2 && !coherence_public_text_matches(rt, &fresh, key_pair(u64(index), part), kind) { return false }
		}
	}
	return coherence_public_text_matches(rt, &fresh, key_string("before-action"), .Text_Field) &&
		coherence_public_text_matches(rt, &fresh, key_string("after-action"), .Text_Field) &&
		coherence_public_text_matches(rt, &fresh, key_string("coherence-peer-text"), .Text_Field)
}

coherence_diagnostics :: proc(rt: ^Runtime, domain: string) -> int {
	events := trace_snapshot(rt)
	defer delete(events)
	count := 0
	for event in events {
		if event.kind == .Mutation_Diagnostic && strings.contains(event.reason, domain) { count += 1 }
	}
	return count
}

Coherence_Oracle_Mutation :: enum { Content, Typography, Material, Combined }
Coherence_Oracle_Invalidation :: enum { Root, Parent, Child, Wrong_Region, Omitted }
Coherence_Oracle_Action :: struct {
	row: int,
	mutation: Coherence_Oracle_Mutation,
	invalidation: Coherence_Oracle_Invalidation,
}
Coherence_Oracle_Result :: struct {
	diverged: bool,
	step: int,
	row: int,
	domain: string,
	advisory_failure_count: int,
}

COHERENCE_ORACLE_SEED :: u64(0x106A11CE)
COHERENCE_ORACLE_ACTION_COUNT :: 8

coherence_oracle_next_random :: proc(state: ^u64) -> u64 {
	value := state^
	value = value ~ (value << 13)
	value = value ~ (value >> 7)
	value = value ~ (value << 17)
	state^ = value
	return value
}

coherence_oracle_actions :: proc(seed: u64) -> ([COHERENCE_ORACLE_ACTION_COUNT]Coherence_Oracle_Action, int) {
	result: [COHERENCE_ORACLE_ACTION_COUNT]Coherence_Oracle_Action
	random_state := seed if seed != 0 else u64(1)
	for index in 0..<COHERENCE_ORACLE_ACTION_COUNT {
		random_row := coherence_oracle_next_random(&random_state)
		random_kind := coherence_oracle_next_random(&random_state)
		random_scope := coherence_oracle_next_random(&random_state)
		result[index] = Coherence_Oracle_Action{
			row=int(random_row % 3),
			mutation=Coherence_Oracle_Mutation(random_kind % 4),
			invalidation=.Child if random_scope%2 == 0 else .Parent,
		}
	}
	// Keep at least two correct updates before injecting one incorrect but
	// otherwise valid request. The chosen step is derived from the seed.
	fault_step := 2 + int(seed % 4)
	result[fault_step].invalidation = .Wrong_Region
	return result, fault_step
}

coherence_oracle_domain :: proc(kind: Coherence_Oracle_Mutation) -> string {
	switch kind {
	case .Content: return "content"
	case .Typography: return "typography"
	case .Material: return "material"
	case .Combined: return "content+typography+material"
	}
	return "unknown"
}

coherence_oracle_replay :: proc(
	t: ^testing.T,
	seed: u64,
	actions: [COHERENCE_ORACLE_ACTION_COUNT]Coherence_Oracle_Action,
	count: int,
) -> Coherence_Oracle_Result {
	rt := new_runtime(Rect{0, 0, 400, 420}, Runtime_Config{trace_capacity=256})
	defer destroy_runtime(&rt)
	material := coherence_setup(t, &rt)
	app := coherence_app()
	_ = coherence_settle(t, &rt, &app, material)
	for index in 0..<min(count, len(actions)) {
		action := actions[index]
		row := &app.rows[action.row]
		old_revision := row.revision
		scope := application_mutation_begin(&rt, "seeded oracle action", .Description, old_revision)
		switch action.mutation {
		case .Content, .Combined:
			row.value = "Alpha generated A" if row.value != "Alpha generated A" else "Alpha generated B"
		case .Typography:
			row.scale = 1.5 if row.scale == 1 else 1
		case .Material:
			row.raised = !row.raised
		case:
			// All enum cases are handled above.
		}
		if action.mutation == .Combined {
			row.scale = 1.5 if row.scale == 1 else 1
			row.raised = !row.raised
		}
		row.revision += 1
		switch action.invalidation {
		case .Root:
			app.parent_revision += 1
			invalidate_root(&rt, "seeded oracle root invalidation")
		case .Parent:
			app.parent_revision += 1
			invalidate_region(&rt, "coherence-parent", app.parent_revision, "seeded oracle parent invalidation")
		case .Child:
			app.parent_revision += 1
			invalidate_region(&rt, row.key, row.revision, "seeded oracle child invalidation")
		case .Wrong_Region:
			// This satisfies the description-scheduling contract but does not
			// invalidate the mutated row's dependency.
			invalidate_region(&rt, "coherence-peer", 1, "seeded oracle wrong-region invalidation")
		case .Omitted:
			// Available for minimized corpus cases that intentionally omit work.
		}
		application_mutation_end(&rt, &scope, row.revision)
		_ = coherence_settle(t, &rt, &app, material)
		if !coherence_matches_fresh(t, &rt, app) {
			return Coherence_Oracle_Result{
				diverged=true,
				step=index,
				row=action.row,
				domain=coherence_oracle_domain(action.mutation),
				advisory_failure_count=coherence_diagnostics(&rt, "seeded oracle action"),
			}
		}
	}
	testing.expect(t, coherence_settle(t, &rt, &app, material) == 0,
		"a correct replay must converge to zero description, layout, and presentation work")
	return {}
}

coherence_oracle_first_failing_prefix :: proc(
	t: ^testing.T,
	seed: u64,
	actions: [COHERENCE_ORACLE_ACTION_COUNT]Coherence_Oracle_Action,
) -> (minimal_count: int, failure: Coherence_Oracle_Result) {
	for count in 1..=len(actions) {
		failure = coherence_oracle_replay(t, seed, actions, count)
		if failure.diverged { return count, failure }
	}
	return 0, {}
}

coherence_oracle_without_action :: proc(
	actions: [COHERENCE_ORACLE_ACTION_COUNT]Coherence_Oracle_Action,
	count, remove_index: int,
) -> [COHERENCE_ORACLE_ACTION_COUNT]Coherence_Oracle_Action {
	result := actions
	for index := remove_index; index < count-1; index += 1 {
		result[index] = result[index+1]
	}
	return result
}

coherence_oracle_minimize_actions :: proc(
	t: ^testing.T,
	seed: u64,
	actions: [COHERENCE_ORACLE_ACTION_COUNT]Coherence_Oracle_Action,
	count: int,
) -> (minimal: [COHERENCE_ORACLE_ACTION_COUNT]Coherence_Oracle_Action, minimal_count: int, failure: Coherence_Oracle_Result) {
	minimal, minimal_count = actions, count
	index := 0
	for index < minimal_count {
		// Keep the designated faulty request; shrink unrelated setup and
		// correctly invalidated mutations around it.
		if minimal[index].invalidation == .Wrong_Region {
			index += 1
			continue
		}
		candidate := coherence_oracle_without_action(minimal, minimal_count, index)
		candidate_count := minimal_count-1
		candidate_failure := coherence_oracle_replay(t, seed, candidate, candidate_count)
		if candidate_failure.diverged {
			minimal, minimal_count = candidate, candidate_count
		} else {
			index += 1
		}
	}
	failure = coherence_oracle_replay(t, seed, minimal, minimal_count)
	return minimal, minimal_count, failure
}

coherence_oracle_failure_report :: proc(
	seed: u64,
	minimal_count: int,
	failure: Coherence_Oracle_Result,
	actions: [COHERENCE_ORACLE_ACTION_COUNT]Coherence_Oracle_Action,
) -> string {
	builder := strings.builder_make()
	key := "coherence-a" if actions[failure.step].row == 0 else
		"coherence-b" if actions[failure.step].row == 1 else "coherence-c"
	path := fmt.tprintf("coherence-root/coherence-parent/%s", key)
	fmt.sbprintf(&builder,
		"seed=%d minimized_actions=%d first_divergence_step=%d key=%s path=%s domain=%s advisory_failures=%d actions=[",
		seed, minimal_count, failure.step, key, path, failure.domain, failure.advisory_failure_count)
	for index in 0..<minimal_count {
		if index > 0 { fmt.sbprintf(&builder, "; ") }
		action := actions[index]
		fmt.sbprintf(&builder, "%d:%v(row=%d,scope=%v)", index, action.mutation, action.row, action.invalidation)
	}
	fmt.sbprintf(&builder, "]")
	return strings.to_string(builder)
}

@(test)
test_seeded_invalidation_oracle_replays_and_shrinks_wrong_region_failure :: proc(t: ^testing.T) {
	seed := COHERENCE_ORACLE_SEED
	actions, fault_step := coherence_oracle_actions(seed)
	repeated_actions, repeated_fault_step := coherence_oracle_actions(seed)
	full := coherence_oracle_replay(t, seed, actions, len(actions))
	prefix_count, prefix_failure := coherence_oracle_first_failing_prefix(t, seed, actions)
	minimal_actions, minimal_count, minimal := coherence_oracle_minimize_actions(t, seed, actions, prefix_count)
	report := coherence_oracle_failure_report(seed, minimal_count, minimal, minimal_actions)
	defer delete(report)
	testing.expect(t, actions == repeated_actions && fault_step == repeated_fault_step,
		"the recorded seed must reproduce the same app-model actions and fault location")
	testing.expect(t, full.diverged && full.step == fault_step && full.row == actions[fault_step].row &&
		full.advisory_failure_count == 0,
		"a valid but mis-scoped invalidation must produce stale output that advisory scheduling diagnostics cannot prove")
	testing.expect(t, prefix_count == fault_step+1 && prefix_failure.diverged && prefix_failure.step == fault_step,
		"the seeded run must stop at the first divergent action instead of hiding it behind later updates")
	testing.expect(t, minimal_count == 1 && minimal_actions[0].invalidation == .Wrong_Region &&
		minimal.diverged && minimal.step == 0 &&
		minimal.row == full.row && minimal.domain == full.domain && minimal.advisory_failure_count == 0,
		"action deletion must shrink the report to the smallest reproducing wrong-region mutation")
	testing.expect(t,
		strings.contains(report, fmt.tprintf("seed=%d", seed)) && strings.contains(report, "minimized_actions=1") &&
		strings.contains(report, "key=coherence-") && strings.contains(report, "path=coherence-root/coherence-parent/") &&
		strings.contains(report, "domain=") && strings.contains(report, "scope=Wrong_Region"),
		fmt.tprintf("a divergence report must include seed, minimized sequence, keyed path, domain, and action log: %s", report))

	corrected := actions
	corrected[fault_step].invalidation = .Parent
	clean := coherence_oracle_replay(t, seed, corrected, len(corrected))
	testing.expect(t, !clean.diverged,
		"replaying the same seeded mutations with the correct region revision must match a fresh Runtime at every step")
}

@(test)
test_invalidation_coherence_consumed_action_settles_once :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 400, 420}, Runtime_Config{trace_capacity=256})
	defer destroy_runtime(&rt)
	material := coherence_setup(t, &rt)
	app := coherence_app()
	_ = coherence_settle(t, &rt, &app, material)
	action, found := node_by_key(&rt, key_string("coherence-action"), .Button)
	testing.expect(t, found && focus(&rt, action) && activate_focused(&rt, .Enter), "a real keyboard activation should request the app description")
	passes := coherence_settle(t, &rt, &app, material)
	testing.expect(t, passes == 2 && app.actions == 1 && app.status == "Action consumed",
		"one consumed action must request one corrective pass without replaying its side effect")
	testing.expect(t, coherence_matches_fresh(t, &rt, app), "labels before and after the action must both match a fresh description")
	testing.expect(t, coherence_diagnostics(&rt, "coherence status") == 0, "the action must schedule its changed app revision")
	invalidate_root(&rt, "repeat the description without another action")
	_ = coherence_settle(t, &rt, &app, material)
	testing.expect(t, app.actions == 1, "ordinary repeated descriptions must not repeat the consumed action")
}

@(test)
test_invalidation_coherence_keyed_mutations_match_fresh :: proc(t: ^testing.T) {
	rt := new_runtime(Rect{0, 0, 400, 420}, Runtime_Config{trace_capacity=512})
	defer destroy_runtime(&rt)
	material := coherence_setup(t, &rt)
	app := coherence_app()
	ids: [3]Node_ID
	_ = coherence_settle(t, &rt, &app, material, &ids)
	testing.expect(t, coherence_matches_fresh(t, &rt, app), "the initial app must match a fresh Runtime")
	peer, _ := node_by_key(&rt, key_string("coherence-peer-text"), .Text_Field)
	peer_before, _ := node_info(&rt, peer)

	// Every nonempty combination of content, typography and material changes.
	// Ancestor revisions cover the child inputs even when a child is the target.
	for mask in 1..=7 {
		row := &app.rows[0]
		scope := application_mutation_begin(&rt, "coherence row", .Description, row.revision)
		if mask & 1 != 0 { row.value = "Alpha revised" if row.value == "Alpha" else "Alpha" }
		if mask & 2 != 0 { row.scale = 1.5 if row.scale == 1 else 1 }
		if mask & 4 != 0 { row.raised = !row.raised }
		row.revision += 1
		app.parent_revision += 1
		switch mask % 3 {
		case 0: invalidate_root(&rt, "coherence root mutation")
		case 1: invalidate_region(&rt, "coherence-parent", app.parent_revision, "coherence parent mutation")
		case 2: invalidate_region(&rt, row.key, row.revision, "coherence child mutation")
		}
		application_mutation_end(&rt, &scope, row.revision)
		testing.expect(t, coherence_settle(t, &rt, &app, material) == 1, "an outside-description mutation should settle in one description")
		testing.expect(t, coherence_matches_fresh(t, &rt, app), fmt.tprintf("content/typography/material mask %d must match fresh paint and public geometry", mask))
	}

	app.order = {2, 0, 1}
	app.parent_revision += 1
	invalidate_region(&rt, "coherence-parent", app.parent_revision, "reorder keyed regions")
	reordered_ids: [3]Node_ID
	_ = coherence_settle(t, &rt, &app, material, &reordered_ids)
	testing.expect(t, coherence_matches_fresh(t, &rt, app), "reordered cached children must match fresh render order")
	previous_y := f32(-1)
	for index in app.order {
		id := reordered_ids[index]
		info, found := node_info(&rt, id)
		testing.expect(t, found && id == ids[index] && info.bounds.y > previous_y,
			fmt.tprintf("key %s must keep identity and follow reordered placement: found=%t id=%d old=%d y=%.1f previous=%.1f", app.rows[index].key, found, id, ids[index], info.bounds.y, previous_y))
		previous_y = info.bounds.y
	}
	app.count = 2 // Omit Bravo, keeping the reordered Charlie/Alpha pair.
	app.parent_revision += 1
	invalidate_root(&rt, "remove a keyed region")
	_ = coherence_settle(t, &rt, &app, material)
	_, removed_present := node_by_key(&rt, key_pair(1, 2), .Text_Field)
	testing.expect(t, !removed_present && coherence_matches_fresh(t, &rt, app), "omitted regions must disappear from public queries and paint")
	peer_after, peer_found := node_info(&rt, peer)
	testing.expect(t, peer_found && peer_after.bounds == peer_before.bounds && peer_after.text_content_width == peer_before.text_content_width,
		"the unrelated retained region must keep its identity and output")
	testing.expect(t, coherence_diagnostics(&rt, "coherence row") == 0, "all reported row mutations scheduled description work")
	testing.expect(t, coherence_settle(t, &rt, &app, material) == 0, "settled state must not describe again")
}

@(test)
test_invalidation_coherence_forgotten_requests_are_advisory :: proc(t: ^testing.T) {
	Case :: struct { inside_description, reported: bool }
	cases := []Case{{false, true}, {true, true}, {false, false}}
	for entry in cases {
		rt := new_runtime(Rect{0, 0, 400, 420}, Runtime_Config{trace_capacity=256})
		material := coherence_setup(t, &rt)
		app := coherence_app()
		_ = coherence_settle(t, &rt, &app, material)
		ui: UI
		if entry.inside_description {
			// The earlier request must not satisfy a mutation scope opened later.
			invalidate_root(&rt, "enter a description before the forgotten transition")
			build: bool
			ui, build = begin_frame(&rt)
			testing.expect(t, build, "the inside-description case must open a real frame")
			coherence_describe(&ui, &app, material)
		}
		scope: Application_Mutation_Scope
		if entry.reported { scope = application_mutation_begin(&rt, "forgotten status", .Description, app.status_revision) }
		app.status = "Forgotten transition"
		app.status_revision += 1
		if entry.reported { application_mutation_end(&rt, &scope, app.status_revision) }
		if entry.inside_description { end_frame(&ui) }
		testing.expect(t, coherence_settle(t, &rt, &app, material) == 0 && !coherence_matches_fresh(t, &rt, app),
			"unrequested app changes must remain observably stale; the checker must not schedule repairs")
		expected := 1 if entry.reported && APP_MUTATION_DIAGNOSTICS_ENABLED else 0
		testing.expect(t, coherence_diagnostics(&rt, "forgotten status") == expected,
			"only explicitly reported changed revisions can produce an advisory finding when enabled")
		invalidate_root(&rt, "repair the forgotten scheduling request")
		_ = coherence_settle(t, &rt, &app, material)
		testing.expect(t, coherence_matches_fresh(t, &rt, app), "explicit invalidation must recover the stale result")
		destroy_runtime(&rt)
	}
}

@(test)
test_invalidation_coherence_scheduling_does_not_prove_region_dependencies :: proc(t: ^testing.T) {
	Fault :: enum { Stale_Parent, Stale_Child, Wrong_Region }
	for fault in Fault {
		rt := new_runtime(Rect{0, 0, 400, 420}, Runtime_Config{trace_capacity=256})
		material := coherence_setup(t, &rt)
		app := coherence_app()
		_ = coherence_settle(t, &rt, &app, material)
		scope := application_mutation_begin(&rt, "region dependency fault", .Description, 1)
		switch fault {
		case .Stale_Parent:
			app.rows[0].value = "Child changed behind cached parent"
			app.rows[0].revision += 1
			invalidate_region(&rt, app.rows[0].key, app.rows[0].revision, "child target with stale ancestor revision")
		case .Stale_Child:
			app.rows[0].value = "Child changed behind its stale revision"
			app.parent_revision += 1
			invalidate_region(&rt, "coherence-parent", app.parent_revision, "parent target with stale descendant revision")
		case .Wrong_Region:
			app.peer_value = "Peer changed"
			// Equal revisions legally force a target to rebuild. Choosing another
			// live region satisfies diagnostics but cannot refresh this peer.
			invalidate_region(&rt, "coherence-parent", app.parent_revision, "wrong live region")
		}
		application_mutation_end(&rt, &scope, 2)
		_ = coherence_settle(t, &rt, &app, material)
		testing.expect(t, !coherence_matches_fresh(t, &rt, app), fmt.tprintf("%v must expose stale output against fresh app state", fault))
		testing.expect(t, coherence_diagnostics(&rt, "region dependency fault") == 0,
			"a successful scheduling request cannot prove region choice or revision completeness")
		if fault == .Wrong_Region {
			invalidate_region(&rt, "coherence-peer", 1, "invalidate the actual dependency")
		} else {
			app.rows[0].revision += 1
			app.parent_revision += 1
			invalidate_root(&rt, "repair ancestor and descendant dependency revisions")
		}
		_ = coherence_settle(t, &rt, &app, material)
		testing.expect(t, coherence_matches_fresh(t, &rt, app), "the corrected dependency contract must recover fresh output")
		destroy_runtime(&rt)
	}
}
