package alicorn

import "core:testing"
import "core:strings"

@(test)
application_mutation_diagnostics_test_is_inert_when_disabled :: proc(t: ^testing.T) {
	when !APP_MUTATION_DIAGNOSTICS_ENABLED {
		rt := new_runtime(Rect{0, 0, 100, 80})
		defer destroy_runtime(&rt)
		trace_before := rt.trace.sequence
		causes_before := rt.cause_sequence
		allocations_before := rt.allocation_stats.persistent_alloc_calls
		scope := application_mutation_begin(&rt, "editor-content", .Description, 3, "test")
		application_mutation_end(&rt, &scope, 4)
		testing.expect(t, rt.trace.sequence == trace_before && rt.cause_sequence == causes_before,
			"disabled diagnostics must not emit trace events or create causes")
		testing.expect(t, rt.allocation_stats.persistent_alloc_calls == allocations_before,
			"disabled diagnostics must not allocate tracking state")
	}
}

when APP_MUTATION_DIAGNOSTICS_ENABLED {
	application_mutation_test_has_trace :: proc(rt: ^Runtime, kind: Trace_Kind, phrase: string) -> bool {
		events := trace_snapshot(rt)
		defer delete(events)
		for event in events {
			if event.kind == kind && strings.contains(event.reason, phrase) { return true }
		}
		return false
	}

	application_mutation_test_count_trace :: proc(rt: ^Runtime, kind: Trace_Kind) -> int {
		count := 0
		events := trace_snapshot(rt)
		defer delete(events)
		for event in events { if event.kind == kind { count += 1 } }
		return count
	}

	application_mutation_test_build_region :: proc(ui: ^UI) {
		container_begin_simple(ui, .Root, label="mutation-region-root", key=key_string("mutation-region-root"), style=layout_style())
		id, reused := region_begin(ui, "mutation-region", 1, style=layout_style(.Column, width=160, height=80))
		if !reused && id != 0 {
			text(ui, "cached", style=layout_style(.Row, height=24))
			region_end(ui, id, false, 0)
		}
		container_end(ui)
	}

	@(test)
	test_application_mutation_reports_changed_description_without_request :: proc(t: ^testing.T) {
		rt := new_runtime(Rect{0, 0, 240, 120}, Runtime_Config{trace_capacity=32})
		defer destroy_runtime(&rt)

		scope := application_mutation_begin(&rt, "document projection adoption", .Description, 42, "worker result became authoritative")
		application_mutation_end(&rt, &scope, 43)

		testing.expect(t, application_mutation_test_has_trace(&rt, .Mutation_Diagnostic, "Unobserved application mutation"),
			"a changed description revision without an invalidation should produce an advisory diagnostic")
		trace := trace_snapshot(&rt)
		defer delete(trace)
		mutation_cause, diagnostic_cause: u64
		for event in trace {
			if event.kind == .Mutation { mutation_cause = event.cause_id }
			if event.kind == .Mutation_Diagnostic { diagnostic_cause = event.cause_id }
		}
		testing.expect(t, mutation_cause != 0 && mutation_cause == diagnostic_cause,
			"mutation and diagnostic events should retain the same causal identity")
		inspection := inspect(&rt)
		defer delete(inspection)
		testing.expect(t, strings.contains(inspection, "document projection adoption") && strings.contains(inspection, "42->43"),
			"the inspector should show the mutation domain and revision transition")
		causes := inspector_overlay_recent_causes(&rt)
		defer delete(causes)
		graphical_inspector_found := false
		for cause in causes {
			if strings.contains(cause.mutation_diagnostic, "document projection adoption") { graphical_inspector_found = true }
		}
		testing.expect(t, graphical_inspector_found,
			"the graphical inspector's cause view should expose application mutation findings")
		testing.expect(t, !rt.hard_error && len(rt.diagnostic) == 0,
			"a missing-invalidation finding must not become a runtime hard error")

		regressed := application_mutation_begin(&rt, "stale projection revision", .Description, 44)
		application_mutation_end(&rt, &regressed, 43)
		testing.expect(t, application_mutation_test_has_trace(&rt, .Mutation_Diagnostic, "revision regression"),
			"a regressing application revision should be called out in the diagnostic")
	}

	@(test)
	test_application_mutation_root_and_presentation_requests_satisfy_their_contracts :: proc(t: ^testing.T) {
		rt := new_runtime(Rect{0, 0, 240, 120}, Runtime_Config{trace_capacity=32})
		defer destroy_runtime(&rt)

		description := application_mutation_begin(&rt, "active document", .Description, 5, "text edit")
		invalidate_root(&rt, "document changed")
		application_mutation_end(&rt, &description, 6)

		presentation := application_mutation_begin(&rt, "caret blink", .Presentation, 11, "blink phase advanced")
		request_presentation(&rt, "caret changed")
		application_mutation_end(&rt, &presentation, 12)
		testing.expect(t, application_mutation_test_count_trace(&rt, .Mutation_Diagnostic) == 0,
			"root descriptions and presentation requests should satisfy the matching mutation impact")
	}

	@(test)
	test_application_mutation_presentation_request_does_not_satisfy_description :: proc(t: ^testing.T) {
		rt := new_runtime(Rect{0, 0, 240, 120}, Runtime_Config{trace_capacity=32})
		defer destroy_runtime(&rt)

		scope := application_mutation_begin(&rt, "editor content", .Description, 8)
		request_presentation(&rt, "paint-only work")
		application_mutation_end(&rt, &scope, 9)
		testing.expect(t, application_mutation_test_has_trace(&rt, .Mutation_Diagnostic, "expected invalidate_root"),
			"presentation-only scheduling must not conceal a missing description rebuild")
	}

	@(test)
	test_application_mutation_region_invalidation_satisfies_description :: proc(t: ^testing.T) {
		rt := new_runtime(Rect{0, 0, 240, 120}, Runtime_Config{trace_capacity=32})
		defer destroy_runtime(&rt)
		ui, should_build := begin_frame(&rt)
		if !should_build {
			testing.expect(t, false, "initial region fixture should request a description")
			return
		}
		application_mutation_test_build_region(&ui)
		end_frame(&ui)

		scope := application_mutation_begin(&rt, "expensive subtree", .Description, 1)
		invalidate_region(&rt, "mutation-region", 2, "subtree changed")
		application_mutation_end(&rt, &scope, 2)
		testing.expect(t, application_mutation_test_count_trace(&rt, .Mutation_Diagnostic) == 0,
			"a successful region invalidation should satisfy the description impact")
	}

	@(test)
	test_application_mutation_ignores_background_and_unchanged_revisions :: proc(t: ^testing.T) {
		rt := new_runtime(Rect{0, 0, 240, 120}, Runtime_Config{trace_capacity=32})
		defer destroy_runtime(&rt)

		background := application_mutation_begin(&rt, "parser cache", .Background, 7, "cache entry refreshed")
		application_mutation_end(&rt, &background, 8)
		unchanged := application_mutation_begin(&rt, "document metadata", .Description, 9, "no logical change")
		application_mutation_end(&rt, &unchanged, 9)
		testing.expect(t, application_mutation_test_count_trace(&rt, .Mutation_Diagnostic) == 0,
			"background work and unchanged revisions should not require UI scheduling")
	}

	@(test)
	test_application_mutation_scopes_are_nested_and_requests_propagate_outward :: proc(t: ^testing.T) {
		rt := new_runtime(Rect{0, 0, 240, 120}, Runtime_Config{trace_capacity=32})
		defer destroy_runtime(&rt)

		outer := application_mutation_begin(&rt, "document model", .Description, 20)
		inner := application_mutation_begin(&rt, "selection presentation", .Presentation, 30)
		invalidate_root(&rt, "document and selection changed")
		application_mutation_end(&rt, &inner, 31)
		application_mutation_end(&rt, &outer, 21)
		testing.expect(t, application_mutation_test_count_trace(&rt, .Mutation_Diagnostic) == 0,
			"a root description requested inside nested scopes should satisfy both scopes")
		testing.expect(t, rt.active_cause.id == 0,
			"ending nested mutation scopes should restore the prior causal context")
	}
}
