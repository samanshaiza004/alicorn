package alicorn

import "core:fmt"

// application_mutation_begin opens a debug-only scope around one synchronous
// application-owned state change. The caller supplies a stable domain name,
// the kind of UI work that change requires, and its current revision. Pair the
// returned scope with application_mutation_end after requesting that work.
//
// Background mutations do not require UI work. Description mutations require
// invalidate_root or a successful invalidate_region call. Presentation
// mutations accept request_presentation or a description invalidation.
application_mutation_begin :: proc(
	rt: ^Runtime,
	domain: string,
	impact: Application_Mutation_Impact,
	before_revision: u64,
	reason := "",
) -> Application_Mutation_Scope {
	when APP_MUTATION_DIAGNOSTICS_ENABLED {
		tracking := &rt.application_mutation_tracking
		tracking.sequence += 1
		if tracking.sequence == 0 { tracking.sequence = 1 }
		id := tracking.sequence
		domain_name := domain if len(domain) > 0 else "<unspecified>"
		cause_scope := cause_begin(rt, .Application, fmt.tprintf("application mutation: %s", domain_name))
		cause := cause_scope.cause
		entry := Application_Mutation_Entry{
			id=id,
			domain=owned_with_allocator(domain_name, rt.persistent_allocator),
			impact=impact,
			before_revision=before_revision,
			reason=owned_with_allocator(reason, rt.persistent_allocator),
			cause=cause,
		}
		append(&tracking.entries, entry)
		record_trace_with_cause(rt, .Mutation, 0,
			fmt.tprintf("domain=%q impact=%v revision=%d reason=%s", domain_name, impact, before_revision, reason),
			cause)
		return Application_Mutation_Scope{runtime=rt, id=id, cause_scope=cause_scope, active=true}
	}
	return {}
}

// application_mutation_end reports a changed revision that did not schedule
// its required UI work. The finding is advisory trace data and does not make
// the runtime enter its hard-error state. Scopes must be ended in LIFO order.
// An out-of-order call records a misuse diagnostic and leaves the stack open
// so the caller can close inner scopes and retry. Passing another Runtime
// records a diagnostic on the owning Runtime; a topmost scope is still closed
// against that owner. Runtime destruction releases any unclosed entries.
application_mutation_end :: proc(rt: ^Runtime, scope: ^Application_Mutation_Scope, after_revision: u64) {
	when APP_MUTATION_DIAGNOSTICS_ENABLED {
		if scope == nil || !scope.active { return }
		owner := scope.runtime
		if owner == nil { return }
		if owner != rt {
			record_trace_with_cause(owner, .Mutation_Diagnostic, 0,
				"application mutation scope ended with a different Runtime", scope.cause_scope.cause)
		}
		tracking := &owner.application_mutation_tracking
		if len(tracking.entries) == 0 || tracking.entries[len(tracking.entries)-1].id != scope.id {
			record_trace_with_cause(owner, .Mutation_Diagnostic, 0,
				"application mutation scopes must end in reverse order", scope.cause_scope.cause)
			return
		}

		index := len(tracking.entries)-1
		entry := tracking.entries[index]
		pop(&tracking.entries)
		missing_request := false
		switch entry.impact {
		case .Background:
		case .Description:
			missing_request = after_revision != entry.before_revision && !entry.description_requested
		case .Presentation:
			missing_request = after_revision != entry.before_revision && !entry.presentation_requested
		}
		if missing_request {
			regressed := after_revision < entry.before_revision
			revision_note := "changed"
			if regressed { revision_note = "changed with a revision regression" }
			expected := "invalidate_root or a successful invalidate_region"
			if entry.impact == .Presentation { expected = "request_presentation or a description invalidation" }
			record_trace_with_cause(owner, .Mutation_Diagnostic, 0,
				fmt.tprintf("Unobserved application mutation: domain=%q revision=%d->%d (%s); expected %s, but none was requested in this scope. reason=%q",
					entry.domain, entry.before_revision, after_revision, revision_note, expected, entry.reason),
				entry.cause)
		}
		if len(entry.domain) > 0 { delete(entry.domain, owner.persistent_allocator) }
		if len(entry.reason) > 0 { delete(entry.reason, owner.persistent_allocator) }
		scope.runtime = nil
		scope.id = 0
		scope.active = false
		cause_end(owner, scope.cause_scope)
	}
}

// application_mutation_note_request tracks scheduling, not dependency
// correctness: the checker does not know which region a mutation affects.
// Requests made while nested scopes are open count for every open scope. A
// root description rebuild satisfies either UI impact; presentation-only
// work cannot satisfy a description mutation.
application_mutation_note_request :: proc(rt: ^Runtime, requested: Application_Mutation_Impact) {
	when APP_MUTATION_DIAGNOSTICS_ENABLED {
		for &entry in rt.application_mutation_tracking.entries {
			if requested == .Description {
				entry.description_requested = true
				entry.presentation_requested = true
			} else if requested == .Presentation {
				entry.presentation_requested = true
			}
		}
	}
}
