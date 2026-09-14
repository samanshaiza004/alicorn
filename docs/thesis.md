# Alicorn thesis

Alicorn aims to be direct to write and retained to run: application code emits
an ephemeral procedural description, while the runtime retains identity,
interaction state, layout products, paint products and GPU-facing resources.

The application owns ordinary Odin state. It explicitly invalidates the root
or a region after a logical mutation. The runtime does not observe arbitrary
Odin memory and does not retain arbitrary application pointers.

This foundation milestone asks one question: can that model support stable
identity, granular reuse, bounded virtualization, deterministic input/focus and
a native compositor boundary without requiring a mandatory reactive state
model? `proof.md` is the authority for the current evidence and verdict.
