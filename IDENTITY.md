# Identity contract

`Node_ID` is a runtime identity, not a persistence or migration identity.

For an emitted node:

```text
Node_ID = hash(parent_identity_scope, source_site, explicit_key_or_zero)
```

`Source_Site` consists of a file label, line, column and component label. In
the foundation API the site is supplied explicitly; `caller_site` can derive
the source portion with Odin `#caller_location`. The source portion identifies
the structural program site. It does not identify a repeated runtime item.

`ui.key_scope(key, site, body)` adds a keyed identity scope without emitting a
retained node. A keyed list should put the logical item key in this scope.
Nested reusable components then derive their descendants from that item scope.

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
   deterministic and defined in `ARCHITECTURE.md`.

Runtime identity is not promised to survive application source changes. A
future `Semantic_ID` must be explicit if persistence across versions becomes a
requirement.
