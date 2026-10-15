package main

// Fixed leaves deliberately hold exactly the same 16-byte references in all
// three backends. The binary summary directory is the simpler alternative to
// the existing fanout-16 measured-tree prototype. None can grow/rebalance.
LEAF_CAPACITY :: 32
FANOUT :: 16
Backend :: enum { Block_Prefix, Block_Hierarchy, Measured_Tree }
Span_Block :: struct { spans: [LEAF_CAPACITY]Span_Ref, count: int, measure: Measure }
Branch :: struct { children: [FANOUT]int, count, parent: int, measure: Measure }
Projection_Index :: struct {
	store: ^Patch_Store,
	backend: Backend,
	blocks: []Span_Block,
	prefix: []Measure,
	binary: []Measure,
	base: int,
	branches: []Branch,
	leaf_parent: []int,
	root: int,
	revision: u64,
}
Seek :: struct { block, local: int, within: i64, before: Measure, ok: bool }

branch_count_for :: proc(leaves: int) -> int {
	count := 0
	level := leaves
	for level > 1 { level = (level+FANOUT-1)/FANOUT; count += level }
	return count
}
node_measure :: proc(index: ^Projection_Index, node: int) -> Measure {
	return index.blocks[-node-1].measure if node < 0 else index.branches[node].measure
}
block_recompute :: proc(index: ^Projection_Index, bi: int) {
	block := &index.blocks[bi]
	block.measure = {}
	for span in block.spans[:block.count] { block.measure = combine(block.measure, span_measure(index.store, span)) }
}
index_init :: proc(index: ^Projection_Index, store: ^Patch_Store, seed: []Span_Ref, backend: Backend) -> bool {
	for span in seed { if !span_valid(store, span) { return false } }
	index^ = Projection_Index{store=store, backend=backend, blocks=make([]Span_Block, max((len(seed)+LEAF_CAPACITY-1)/LEAF_CAPACITY, 1))}
	for span, i in seed { bi := i/LEAF_CAPACITY; index.blocks[bi].spans[i%LEAF_CAPACITY] = span; index.blocks[bi].count += 1 }
	for _, bi in index.blocks { block_recompute(index, bi) }
	switch backend {
	case .Block_Prefix:
		index.prefix = make([]Measure, len(index.blocks)+1)
		for b, bi in index.blocks { index.prefix[bi+1] = combine(index.prefix[bi], b.measure) }
	case .Block_Hierarchy:
		index.base = 1
		for index.base < len(index.blocks) { index.base *= 2 }
		index.binary = make([]Measure, 2*index.base)
		for b, bi in index.blocks { index.binary[index.base+bi] = b.measure }
		for i := index.base-1; i > 0; i -= 1 { index.binary[i] = combine(index.binary[2*i], index.binary[2*i+1]) }
	case .Measured_Tree:
		index.branches = make([]Branch, branch_count_for(len(index.blocks)))
		index.leaf_parent = make([]int, len(index.blocks))
		for &p in index.leaf_parent { p = -1 }
		level := make([]int, len(index.blocks))
		for _, i in level { level[i] = -i-1 }
		created := 0
		for len(level) > 1 {
			next := make([]int, (len(level)+FANOUT-1)/FANOUT)
			for _, group in next {
				branch := &index.branches[created]
				branch.parent = -1
				for i in group*FANOUT..<min((group+1)*FANOUT, len(level)) {
					child := level[i]
					branch.children[branch.count] = child
					branch.count += 1
					branch.measure = combine(branch.measure, node_measure(index, child))
					if child < 0 { index.leaf_parent[-child-1] = created } else { index.branches[child].parent = created }
				}
				next[group] = created
				created += 1
			}
			delete(level)
			level = next
		}
		index.root = level[0]
		delete(level)
	}
	return true
}
index_destroy :: proc(index: ^Projection_Index) {
	delete(index.blocks); delete(index.prefix); delete(index.binary)
	delete(index.branches); delete(index.leaf_parent)
	index^ = {}
}
index_measure :: proc(index: ^Projection_Index) -> Measure {
	switch index.backend {
	case .Block_Prefix: return index.prefix[len(index.prefix)-1]
	case .Block_Hierarchy: return index.binary[1]
	case .Measured_Tree: return node_measure(index, index.root)
	}
	return {}
}
index_changed :: proc(index: ^Projection_Index, bi: int) {
	block_recompute(index, bi)
	switch index.backend {
	case .Block_Prefix:
		for i in bi..<len(index.blocks) { index.prefix[i+1] = combine(index.prefix[i], index.blocks[i].measure) }
	case .Block_Hierarchy:
		node := index.base+bi
		index.binary[node] = index.blocks[bi].measure
		for node > 1 { node /= 2; index.binary[node] = combine(index.binary[node*2], index.binary[node*2+1]) }
	case .Measured_Tree:
		parent := index.leaf_parent[bi]
		for parent >= 0 {
			branch := &index.branches[parent]
			branch.measure = {}
			for child in branch.children[:branch.count] { branch.measure = combine(branch.measure, node_measure(index, child)) }
			parent = branch.parent
		}
	}
	index.revision += 1
}
index_seek :: proc(index: ^Projection_Index, dimension: Dimension, coordinate: i64) -> Seek {
	if index == nil || coordinate < 0 || coordinate >= extent(index_measure(index), dimension) { return {} }
	remaining := coordinate
	before := Measure{}
	bi := 0
	switch index.backend {
	case .Block_Prefix:
		low, high := 0, len(index.blocks)
		for low < high { mid := (low+high)/2; if extent(index.prefix[mid+1], dimension) <= coordinate { low = mid+1 } else { high = mid } }
		bi = low
		before = index.prefix[bi]
		remaining -= extent(before, dimension)
	case .Block_Hierarchy:
		node := 1
		for node < index.base {
			left := index.binary[node*2]
			if remaining < extent(left, dimension) { node *= 2 } else { remaining -= extent(left, dimension); before = combine(before, left); node = node*2+1 }
		}
		bi = node-index.base
	case .Measured_Tree:
		node := index.root
		for node >= 0 {
			branch := &index.branches[node]
			selected := false
			for child in branch.children[:branch.count] {
				measure := node_measure(index, child)
				if remaining < extent(measure, dimension) { node = child; selected = true; break }
				remaining -= extent(measure, dimension)
				before = combine(before, measure)
			}
			if !selected { return {} }
		}
		bi = -node-1
	}
	block := &index.blocks[bi]
	for span, local in block.spans[:block.count] {
		measure := span_measure(index.store, span)
		if remaining < extent(measure, dimension) { return {bi, local, remaining, before, true} }
		remaining -= extent(measure, dimension)
		before = combine(before, measure)
	}
	return {}
}
index_source :: proc(index: ^Projection_Index, old_side: bool, coordinate: i64) -> Source_Result {
	seek := index_seek(index, .Old if old_side else .New, coordinate-1)
	if !seek.ok { return {} }
	span := index.blocks[seek.block].spans[seek.local]
	switch span.kind {
	case .Gap: return {kind=.Gap}
	case .Fold:
		plan := index.store.folds[span.source]
		return {kind=.Folded, display_row=seek.before.display_rows, hunk=int(plan.original[0].source), fold_id=plan.id}
	case .Line: return {kind=.Visible, display_row=seek.before.display_rows+seek.within, hunk=int(span.source), patch_line=int(span.first)+int(seek.within)}
	case .Metadata, .Header, .Binary: return {}
	}
	return {}
}
// Complete headless viewport reconstruction: actual strings, kinds, gutters,
// hunk IDs and folded descriptors, rather than the earlier checksum-only work.
index_viewport :: proc(index: ^Projection_Index, first: i64, output: []Visible_Row) -> int {
	seek := index_seek(index, .Display, first)
	if !seek.ok { return 0 }
	bi, local, within := seek.block, seek.local, int(seek.within)
	written := 0
	for bi < len(index.blocks) && written < len(output) {
		block := &index.blocks[bi]
		for local < block.count && written < len(output) {
			span := block.spans[local]
			rows := int(span_measure(index.store, span).display_rows)
			for within < rows && written < len(output) {
				output[written] = materialize_row(index.store, span, within)
				written += 1; within += 1
			}
			local += 1; within = 0
		}
		bi += 1; local = 0
	}
	return written
}
index_splice_block :: proc(index: ^Projection_Index, bi, first, end: int, inserted: []Span_Ref) -> bool {
	if index == nil || bi < 0 || bi >= len(index.blocks) { return false }
	block := &index.blocks[bi]
	if first < 0 || end < first || end > block.count { return false }
	new_count := block.count-(end-first)+len(inserted)
	if new_count > LEAF_CAPACITY { return false }
	for span in inserted { if !span_valid(index.store, span) { return false } }
	if first == end && len(inserted) == 0 { return true }
	// Snapshot before shifting in case the input slice aliases this leaf.
	staged: [LEAF_CAPACITY]Span_Ref
	copy(staged[:], inserted)
	// After validation there is no allocation or other fallible work.
	delta := len(inserted)-(end-first)
	if delta > 0 { for i := block.count-1; i >= end; i -= 1 { block.spans[i+delta] = block.spans[i] } }
	if delta < 0 { for i in end..<block.count { block.spans[i+delta] = block.spans[i] } }
	for i in 0..<len(inserted) { block.spans[first+i] = staged[i] }
	block.count = new_count
	index_changed(index, bi)
	return true
}
index_fold :: proc(index: ^Projection_Index, fi: int, collapse: bool) -> bool {
	if fi < 0 || fi >= len(index.store.folds) { return false }
	plan := index.store.folds[fi]
	block := &index.blocks[plan.block]
	placeholder := [1]Span_Ref{Span_Ref{kind=.Fold, source=u32(fi), count=1}}
	find := placeholder[0]
	if collapse { find = plan.original[0] }
	for span, local in block.spans[:block.count] {
		if span != find { continue }
		if collapse {
			if local+len(plan.original) > block.count { return false }
			for original, i in plan.original { if block.spans[local+i] != original { return false } }
			return index_splice_block(index, plan.block, local, local+len(plan.original), placeholder[:])
		}
		return index_splice_block(index, plan.block, local, local+1, plan.original)
	}
	return false
}
index_anchor :: proc(index: ^Projection_Index, anchor: Anchor) -> Anchor_Result {
	store := index.store
	if anchor.epoch != store.epoch || anchor.hunk < 0 || anchor.hunk >= len(store.patch.hunks) { return {} }
	h := store.patch.hunks[anchor.hunk]
	if anchor.line < 0 || anchor.line >= len(h.lines) { return {} }
	line := h.lines[anchor.line]
	if line.old_line > 0 || line.new_line > 0 {
		result := index_source(index, line.old_line > 0, i64(line.old_line if line.old_line > 0 else line.new_line))
		if result.kind == .Visible || result.kind == .Folded { return {result.display_row, result.kind == .Folded, true} }
		return {}
	}
	// Meta lines have zero extent on both source axes. Start at the owning
	// hunk and scan its spans, not unrelated panels or other hunk identities.
	seek := index_seek(index, .Hunk, i64(anchor.hunk))
	if !seek.ok { return {} }
	row := seek.before.display_rows
	for bi in seek.block..<len(index.blocks) {
		block := &index.blocks[bi]
		first := seek.local if bi == seek.block else 0
		for span in block.spans[first:block.count] {
			if span.kind == .Header && int(span.source) != anchor.hunk { return {} }
			if span.kind == .Line && int(span.source) == anchor.hunk && anchor.line >= int(span.first) && anchor.line < int(span.first+span.count) { return {row+i64(anchor.line-int(span.first)), false, true} }
			if span.kind == .Fold {
				for original in store.folds[span.source].original {
					if int(original.source) == anchor.hunk && anchor.line >= int(original.first) && anchor.line < int(original.first+original.count) { return {row, true, true} }
				}
			}
			row += span_measure(store, span).display_rows
		}
	}
	return {}
}
