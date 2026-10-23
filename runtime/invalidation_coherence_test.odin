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
	text(ui, app.status, key=key_string("before-action"), style=layout_style(height=28))
	if button(ui, "Change status", key=key_string("coherence-action"), style=layout_style(width=160, height=32)) {
		scope := application_mutation_begin(ui.runtime, "coherence status", .Description, app.status_revision)
		app.actions += 1
		app.status = "Action consumed"
		app.status_revision += 1
		invalidate_root(ui.runtime, "consumed action changed status")
		application_mutation_end(ui.runtime, &scope, app.status_revision)
	}
	text(ui, app.status, key=key_string("after-action"), style=layout_style(height=28))
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
			text(ui, row.value, key=key_pair(u64(index), 2), style=layout_style(width=220, height=64))
			surface_end(ui)
			style_environment_pop(ui, scope)
			region_end(ui, id, false, 0)
		}
		region_end(ui, parent, false, 0)
	}
	peer, cached := region_begin(ui, "coherence-peer", 1, style=layout_style(width=240, height=32))
	if peer != 0 && !cached {
		text(ui, app.peer_value, key=key_string("coherence-peer-text"), style=layout_style(height=28))
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

// Handles/generations are Runtime-local. Compare resolved render products,
// including text content/typography and material descriptors, instead of IDs.
coherence_paint_matches :: proc(a, b: ^Runtime) -> bool {
	if len(a.display) != len(b.display) { return false }
	for left, i in a.display {
		right := b.display[i]
		if left.owner != right.owner || left.bounds != right.bounds || left.clip != right.clip ||
		   left.opacity != right.opacity || left.translation != right.translation { return false }
		switch l in left.payload {
		case Surface_Paint:
			r, ok := right.payload.(Surface_Paint)
			if !ok { return false }
			lm, lok := style_material_resolve(a, l.material)
			rm, rok := style_material_resolve(b, r.material)
			if !lok || !rok || lm != rm { return false }
			resolved_left := l
			resolved_left.material, r.material = MATERIAL_FLAT, MATERIAL_FLAT
			if resolved_left != r { return false }
		case Text_Paint:
			r, ok := right.payload.(Text_Paint)
			if !ok || l.color != r.color || len(l.spans) != 0 || len(r.spans) != 0 { return false }
			lr, lok := paint_text_run_resolve(a, l.run)
			rr, rok := paint_text_run_resolve(b, r.run)
			if !lok || !rok { return false }
			if lr.value != rr.value || lr.size != rr.size || lr.font != rr.font || lr.font_weight != rr.font_weight ||
			   lr.width != rr.width || lr.height != rr.height || len(lr.lines) != len(rr.lines) { return false }
		case Icon_Paint, Image_Paint, Geometry_Paint:
			// This tiny app emits only surfaces and text; unexpected paint is a failure.
			return false
		}
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
	if !coherence_paint_matches(rt, &fresh) { return false }
	for index in 0..<len(app.rows) {
		for part in u64(1)..=2 {
			kind := Node_Kind.Container if part == 1 else Node_Kind.Text
			a, aok := node_by_key(rt, key_pair(u64(index), part), kind)
			b, bok := node_by_key(&fresh, key_pair(u64(index), part), kind)
			if aok != bok { return false }
			if !aok { continue }
			ai, _ := node_info(rt, a)
			bi, _ := node_info(&fresh, b)
			if a != b || ai.bounds != bi.bounds || ai.hit_bounds != bi.hit_bounds ||
			   ai.text_content_width != bi.text_content_width || ai.text_content_height != bi.text_content_height { return false }
		}
	}
	return true
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
	peer, _ := node_by_key(&rt, key_string("coherence-peer-text"), .Text)
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
	_, removed_present := node_by_key(&rt, key_pair(1, 2), .Text)
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
