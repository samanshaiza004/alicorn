# Advanced identity and allocation

Most applications should stay on the canonical API. The advanced APIs are
available for tests, diagnostics, custom identity, and runtime integrations.

## Explicit identity

`Source_Site`, `*_ex` procedures, and explicit paint generations are exported
for cases where a test or integration must control the structural source. They
are not required for ordinary widgets and should not replace `#caller_location`
in application code.

The typed key forms are:

```odin
key_string("stable-name")
key_u64(process_id)
key_pair(process_id, creation_time)
```

The key variant is part of identity. An unkeyed emission, an empty string, a
zero integer, and a zero pair are all different keys. Duplicate keys in one
scope are hard diagnostics.

## Runtime ownership

The runtime accepts optional allocator configuration at construction:

```odin
config := alicorn.Runtime_Config{
	persistent_allocator = context.allocator,
	scratch_backing_allocator = context.allocator,
	trace_capacity = 256,
}
rt := alicorn.new_runtime(viewport, config)
```

The runtime wraps the persistent allocator for retained data and owns its own
scratch arena backed by `scratch_backing_allocator`. It resets and destroys
that arena itself. It never resets or frees the application's temporary
allocator.

`Runtime_Allocation_Stats` reports requested allocation calls and bytes for
runtime-owned persistent and scratch work. It does not measure RSS, committed
pages, allocator overhead, GPU memory, driver residency, or allocations made by
the application.

Applications that need end-to-end memory accounting should track their own
samplers and data separately.
