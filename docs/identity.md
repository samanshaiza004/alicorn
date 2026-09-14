# Identity contract

`Node_ID` is a runtime identity, not a persistence or migration identity.

For an emitted node:

```text
Node_ID = hash(parent_identity_scope, source_site, explicit_key_or_zero)
```

`Source_Site` consists of a file label, line, column and component label. Public
emission calls may omit the site; they derive it from Odin `#caller_location`.
Low-level tests may still supply an explicit site. The `component_begin/end`
API captures an invocation site and adds a keyed component scope, allowing a
helper's internal widget call site to be reused safely at multiple call sites.
The source portion identifies the structural program site. It does not identify
a repeated runtime item.

`ui.key_scope(key, site, body)` adds a keyed identity scope without emitting a
retained node. `ui.key_scope_u64` is the allocation-free numeric equivalent;
both feed the same hierarchical identity rules and preserve the key type for
inspector output. A keyed list should put the logical item key in this scope.
Nested reusable components then derive their descendants from that item scope.
`virtual_list` enforces the same rule through its `item_key(index)` callback.

Rules:

1. A repeated sibling from one structural site without a key is ambiguous.
2. Duplicate keys in one identity scope are ambiguous.
3. Both cases set `Runtime.hard_error` and append an actionable diagnostic;
   they are never silently disambiguated by position.
4. Different sites are different structural identities even when labels match.
5. Reordering, insertion, removal and filtering do not change keyed IDs.
6. A representation change may intentionally reuse an ID when the caller uses
   the same site and key. This is the explicit LOD mapping seam.
7. A conditional structural wrapper that must not change an item's logical
   identity uses `transparent_container_begin/end`. The wrapper remains in the
   retained hierarchy for layout, while keyed descendants retain their scope.
8. A missing node is retired at reconciliation end. Focus fallback is
   deterministic and defined in [`architecture.md`](architecture.md).

When a region revision is unchanged, the region root is emitted followed by a
retained-subtree reuse marker. The marker does not enumerate descendants;
their existing adjacency and identity remain authoritative. If the region is
omitted later, retirement walks that retained adjacency and removes the entire
subtree.

Runtime identity is not promised to survive application source changes. A
future `Semantic_ID` must be explicit if persistence across versions becomes a
requirement.
