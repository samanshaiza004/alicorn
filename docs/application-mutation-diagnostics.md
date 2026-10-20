# Application mutation diagnostics

Alicorn does not inspect or poll application memory. Applications remain
responsible for requesting a new description or presentation when their state
changes. Debug builds can check that contract for selected mutation domains by
bracketing synchronous state changes with `application_mutation_begin` and
`application_mutation_end`.

Enable the checker by building with both Odin debug mode and the explicit
define:

```powershell
odin test runtime -debug -define:ALICORN_APP_MUTATION_DIAGNOSTICS=true
```

Use the same flags when building an application that uses the checker. Without
both flags, the scope type and Runtime tracking state are empty, the procedures
compile to no-op paths, and Alicorn performs no mutation tracking allocations.

```odin
scope := alicorn.application_mutation_begin(
    runtime,
    "document projection adoption",
    .Description,
    app.document_revision,
    "worker result became authoritative",
)
app.adopt_projection(result)
app.document_revision += 1
alicorn.invalidate_root(runtime, "document projection changed")
alicorn.application_mutation_end(runtime, &scope, app.document_revision)
```

The scope must cover both the application mutation and the scheduling request.
Scopes belong to the Runtime passed to `application_mutation_begin` and must
end in reverse order. If an outer scope is ended too early, Alicorn records a
misuse diagnostic and leaves the scope stack intact; close the inner scope,
then end the outer scope. Destroying the Runtime releases any still-open
tracking entries, and their handles must not be used afterward. If `end` is
called with a different Runtime, the diagnostic is recorded on the owning
Runtime; a topmost scope is still closed against its owner.

End each scope on every control-flow path. Use stable, concise domain names
such as `document content`, `active selection`, or `search results`; the
optional reason can describe the event that caused the change.

`Application_Mutation_Impact` describes the required work:

| Impact | Satisfying request |
| --- | --- |
| `.Description` | `invalidate_root` or a successful `invalidate_region` |
| `.Presentation` | `request_presentation` or a description invalidation |
| `.Background` | No UI request required |

When the ending revision differs from the starting revision and the required
request did not occur inside the scope, Alicorn adds an advisory
`Mutation_Diagnostic` event to the Runtime inspector trace. It includes the
domain, revision transition, expected request, and reason. This does not set
the Runtime hard-error state or schedule work by itself.

This is a scheduling check, not proof that the affected UI dependency was
invalidated. Any successful `invalidate_region` call while a scope is open
satisfies every open description scope, because the checker does not know
which region a mutation affects. Likewise, a root invalidation satisfies all
open UI scopes. Use the result to find missing scheduling calls; applications
remain responsible for choosing the correct invalidation target.

The checker can only verify scopes the application reports. It does not detect
unbracketed changes, validate that an application's revision covers every
output dependency, or make Runtime thread-safe. For background workers, bracket
the UI-thread adoption of a result, not mutation of worker-owned data. The
instrumentation compiles away when disabled, but normal Odin argument
evaluation still occurs at the call site. Keep domain and reason arguments
cheap; guard expensive diagnostic-string construction with the same compile
time condition used to enable the checker.
