package main

import "core:fmt"
import "core:time"

// A bottom-up, History-specific B+ tree prototype. This is an isolated
// performance experiment: leaves hold borrowed projection records and branch
// nodes cache ordered summaries. The measured splice is intentionally limited
// to one leaf with spare capacity; split/merge and allocator-failure behavior
// remain correctness gates before any reusable core is considered.

TREE_LEAF_CAPACITY :: 32
TREE_BRANCH_CAPACITY :: 16

Tree_Ref_Kind :: enum { Leaf, Branch }
Tree_Ref :: struct { kind: Tree_Ref_Kind, index: int }
Tree_Path :: struct { branch_indices: [32]int, depth: int }
Tree_Item_Ref :: struct { source_record_index: u32 }
// Fold descriptors are application-owned and indexed independently. Each
// active fold has a stable reference; updating one never aliases another.
TREE_FOLD_REFERENCE_BIT :: u32(0x8000_0000)

Tree_Leaf :: struct {
	records: [TREE_LEAF_CAPACITY]Tree_Item_Ref,
	count:   int,
	items:   int,
	summary: Projection_Summary,
	prev:    int,
	next:    int,
}

Tree_Branch :: struct {
	children:          [TREE_BRANCH_CAPACITY]Tree_Ref,
	child_leaf_first:  [TREE_BRANCH_CAPACITY]int,
	child_leaf_end:    [TREE_BRANCH_CAPACITY]int,
	count:             int,
	items:             int,
	first_leaf:        int,
	leaf_end:          int,
	summary:           Projection_Summary,
}

History_Tree :: struct {
	leaves:   [dynamic]Tree_Leaf,
	branches: [dynamic]Tree_Branch,
	source_records: []Projection_Record,
	fold_records: []Projection_Record,
	root:     Tree_Ref,
	revision: u64,
}

tree_branch_count_for :: proc(leaf_count: int) -> int {
	if leaf_count <= 1 { return 0 }
	total, level := 0, leaf_count
	for level > 1 {
		level = (level+TREE_BRANCH_CAPACITY-1)/TREE_BRANCH_CAPACITY
		total += level
	}
	return total
}

tree_init :: proc(tree: ^History_Tree, records: []Projection_Record, fold_records: []Projection_Record = nil, allocator := context.allocator) -> bool {
	if tree == nil || u64(len(records)) >= u64(TREE_FOLD_REFERENCE_BIT) { return false }
	leaf_count := max((len(records)+TREE_LEAF_CAPACITY-1)/TREE_LEAF_CAPACITY, 1)
	branch_capacity := tree_branch_count_for(leaf_count)
	tree^ = History_Tree{
		leaves=make([dynamic]Tree_Leaf, 0, leaf_count, allocator=allocator),
		branches=make([dynamic]Tree_Branch, 0, branch_capacity, allocator=allocator),
		source_records=records,
		fold_records=fold_records,
	}
	for start := 0; start < len(records); start += TREE_LEAF_CAPACITY {
		end := min(start+TREE_LEAF_CAPACITY, len(records))
		leaf := Tree_Leaf{count=end-start, items=end-start, prev=len(tree.leaves)-1, next=-1}
		for i in start..<end {
			leaf.records[i-start] = Tree_Item_Ref{u32(i)}
			leaf.summary = summary_combine(leaf.summary, records[i].summary)
		}
		if len(tree.leaves) > 0 { tree.leaves[len(tree.leaves)-1].next = len(tree.leaves) }
		append(&tree.leaves, leaf)
	}
	if len(tree.leaves) == 0 { append(&tree.leaves, Tree_Leaf{prev=-1, next=-1}) }

	current := make([]Tree_Ref, len(tree.leaves), allocator=allocator)
	defer delete(current)
	for i in 0..<len(tree.leaves) { current[i] = Tree_Ref{.Leaf, i} }
	for len(current) > 1 {
		next_count := (len(current)+TREE_BRANCH_CAPACITY-1)/TREE_BRANCH_CAPACITY
		next := make([]Tree_Ref, next_count, allocator=allocator)
		for group in 0..<next_count {
			first := group*TREE_BRANCH_CAPACITY
			end := min(first+TREE_BRANCH_CAPACITY, len(current))
			branch := Tree_Branch{count=end-first}
			for i in first..<end {
				child := current[i]
				branch.children[i-first] = child
				child_first, child_end := tree_leaf_range(tree, child)
				branch.child_leaf_first[i-first] = child_first
				branch.child_leaf_end[i-first] = child_end
				if i == first { branch.first_leaf = child_first }
				branch.leaf_end = child_end
				branch.items += tree_item_count(tree, child)
				branch.summary = summary_combine(branch.summary, tree_node_summary(tree, child))
			}
			branch_index := len(tree.branches)
			append(&tree.branches, branch)
			next[group] = Tree_Ref{.Branch, branch_index}
		}
		delete(current)
		current = next
	}
	tree.root = current[0]
	return true
}

tree_destroy :: proc(tree: ^History_Tree) {
	if tree == nil { return }
	delete(tree.leaves)
	delete(tree.branches)
	tree^ = {}
}

tree_node_summary :: proc(tree: ^History_Tree, ref: Tree_Ref) -> Projection_Summary {
	if ref.kind == .Leaf { return tree.leaves[ref.index].summary }
	return tree.branches[ref.index].summary
}

tree_item_record_ptr :: proc(tree: ^History_Tree, item: Tree_Item_Ref) -> ^Projection_Record {
	if item.source_record_index & TREE_FOLD_REFERENCE_BIT != 0 {
		index := int(item.source_record_index & ~TREE_FOLD_REFERENCE_BIT)
		if index >= len(tree.fold_records) { return nil }
		return &tree.fold_records[index]
	}
	index := int(item.source_record_index)
	if index >= len(tree.source_records) { return nil }
	return &tree.source_records[index]
}

tree_item_count :: proc(tree: ^History_Tree, ref: Tree_Ref) -> int {
	if ref.kind == .Leaf { return tree.leaves[ref.index].items }
	return tree.branches[ref.index].items
}

tree_total_summary :: proc(tree: ^History_Tree) -> Projection_Summary {
	if tree == nil || len(tree.leaves) == 0 { return {} }
	return tree_node_summary(tree, tree.root)
}

tree_validate_summary :: proc(tree: ^History_Tree, ref: Tree_Ref) -> (summary: Projection_Summary, items: int, ok: bool) {
	if ref.kind == .Leaf {
		leaf := &tree.leaves[ref.index]
		for item in leaf.records[:leaf.count] { summary = summary_combine(summary, tree_item_record_ptr(tree, item).summary) }
	return summary, leaf.count, summary == leaf.summary && leaf.items == leaf.count
	}
	branch := &tree.branches[ref.index]
	for i in 0..<branch.count {
		child_summary, child_items, child_ok := tree_validate_summary(tree, branch.children[i])
		if !child_ok { return {}, 0, false }
		summary = summary_combine(summary, child_summary)
		items += child_items
	}
	return summary, items, summary == branch.summary && items == branch.items
}

tree_locate_record :: proc(tree: ^History_Tree, index: int) -> (leaf_index, local_index: int, ok: bool) {
	if tree == nil || index < 0 || index >= tree_item_count(tree, tree.root) { return 0, 0, false }
	remaining := index
	ref := tree.root
	for ref.kind == .Branch {
		branch := &tree.branches[ref.index]
		selected := -1
		for i in 0..<branch.count {
			child := branch.children[i]
			child_items := tree_item_count(tree, child)
			if remaining < child_items { selected = i; break }
			remaining -= child_items
		}
		if selected < 0 { return 0, 0, false }
		ref = branch.children[selected]
	}
	if remaining >= tree.leaves[ref.index].count { return 0, 0, false }
	return ref.index, remaining, true
}

tree_recompute_branch :: proc(tree: ^History_Tree, branch_index: int) {
	branch := &tree.branches[branch_index]
	branch.summary = {}
	branch.items = 0
	for i in 0..<branch.count {
		child := branch.children[i]
		branch.summary = summary_combine(branch.summary, tree_node_summary(tree, child))
		branch.items += tree_item_count(tree, child)
	}
}

tree_collect_path :: proc(tree: ^History_Tree, leaf_index: int, path: ^Tree_Path) -> bool {
	if tree == nil || path == nil || leaf_index < 0 || leaf_index >= len(tree.leaves) { return false }
	path^ = {}
	ref := tree.root
	for ref.kind == .Branch {
		branch := &tree.branches[ref.index]
		selected := -1
		for i in 0..<branch.count {
			if leaf_index >= branch.child_leaf_first[i] && leaf_index < branch.child_leaf_end[i] { selected = i; break }
		}
		if selected < 0 || path.depth >= len(path.branch_indices) { return false }
		path.branch_indices[path.depth] = ref.index
		path.depth += 1
		ref = branch.children[selected]
	}
	if ref.index != leaf_index { return false }
	return true
}

tree_recompute_path :: proc(tree: ^History_Tree, path: Tree_Path) {
	for i := path.depth-1; i >= 0; i -= 1 { tree_recompute_branch(tree, path.branch_indices[i]) }
}

tree_leaf_range :: proc(tree: ^History_Tree, ref: Tree_Ref) -> (first, end: int) {
	if ref.kind == .Leaf { return ref.index, ref.index+1 }
	branch := &tree.branches[ref.index]
	return branch.first_leaf, branch.leaf_end
}

tree_seek_display :: proc(tree: ^History_Tree, row: i64) -> (leaf_index, record_index: int, row_offset: int, ok: bool) {
	if tree == nil || row < 0 || row >= tree_total_summary(tree).display_rows { return 0, 0, 0, false }
	remaining := row
	ref := tree.root
	for ref.kind == .Branch {
		branch := &tree.branches[ref.index]
		selected := -1
		for i in 0..<branch.count {
			child := branch.children[i]
			child_rows := tree_node_summary(tree, child).display_rows
			if remaining < child_rows { selected = i; break }
			remaining -= child_rows
		}
		if selected < 0 { return 0, 0, 0, false }
		ref = branch.children[selected]
	}
	leaf := &tree.leaves[ref.index]
	for i in 0..<leaf.count {
		rows := tree_item_record_ptr(tree, leaf.records[i]).summary.display_rows
		if remaining < rows { return ref.index, i, int(remaining), true }
		remaining -= rows
	}
	return 0, 0, 0, false
}

tree_hunk_display :: proc(tree: ^History_Tree, ordinal: i64) -> (row: i64, ok: bool) {
	if tree == nil || ordinal < 0 || ordinal >= tree_total_summary(tree).hunk_headers { return 0, false }
	remaining := ordinal
	row = 0
	ref := tree.root
	for ref.kind == .Branch {
		branch := &tree.branches[ref.index]
		selected := -1
		for i in 0..<branch.count {
			child := branch.children[i]
			child_summary := tree_node_summary(tree, child)
			if remaining < child_summary.hunk_headers { selected = i; break }
			remaining -= child_summary.hunk_headers
			row += child_summary.display_rows
		}
		if selected < 0 { return 0, false }
		ref = branch.children[selected]
	}
	leaf := &tree.leaves[ref.index]
	for i in 0..<leaf.count {
		summary := tree_item_record_ptr(tree, leaf.records[i]).summary
		if summary.hunk_headers > remaining { return row, true }
		remaining -= summary.hunk_headers
		row += summary.display_rows
	}
	return 0, false
}

tree_source_lookup :: proc(tree: ^History_Tree, old_side: bool, line: i64) -> Source_Lookup {
	if tree == nil || line < 0 { return {} }
	display_prefix: i64 = 0
	for leaf_index in 0..<len(tree.leaves) {
		leaf := &tree.leaves[leaf_index]
		for item in leaf.records[:leaf.count] {
			record := tree_item_record_ptr(tree, item)
			first, count := record.new_first, record.summary.new_rows
			if old_side { first, count = record.old_first, record.summary.old_rows }
			if count > 0 && line >= first && line < first+count {
				switch record.kind {
				case .Source_Gap: return Source_Lookup{kind=.Gap, first=first, count=count}
				case .Collapsed: return Source_Lookup{kind=.Collapsed, display_row=display_prefix, first=first, count=count}
				case .Header: return Source_Lookup{kind=.Missing}
				case .Context, .Addition, .Deletion:
					within := line-first
					if within >= record.summary.display_rows { return Source_Lookup{kind=.Missing} }
					return Source_Lookup{kind=.Visible, display_row=display_prefix+within, patch_line=record.first_patch_line+int(within), first=first, count=count}
				}
			}
			display_prefix += record.summary.display_rows
		}
	}
	return {}
}

tree_window_checksum :: proc(tree: ^History_Tree, first_display: i64, visible_rows: int) -> u64 {
	leaf_index, record_index, row_offset, ok := tree_seek_display(tree, first_display)
	if !ok || visible_rows <= 0 { return 0 }
	checksum: u64 = 0
	remaining := visible_rows
	for leaf_index >= 0 && leaf_index < len(tree.leaves) && remaining > 0 {
		leaf := &tree.leaves[leaf_index]
		for record_index < leaf.count && remaining > 0 {
			record := tree_item_record_ptr(tree, leaf.records[record_index])
			available := int(record.summary.display_rows)-row_offset
			if available > 0 {
				take := min(available, remaining)
				for row in 0..<take { checksum = checksum*33+u64(record.first_patch_line+row_offset+row+record.hunk_index) }
				remaining -= take
			}
			record_index += 1
			row_offset = 0
		}
		leaf_index = leaf.next
		record_index = 0
	}
	return checksum
}

tree_splice_leaf :: proc(tree: ^History_Tree, leaf_index, first, end: int, inserted: []Tree_Item_Ref) -> bool {
	if tree == nil || leaf_index < 0 || leaf_index >= len(tree.leaves) { return false }
	leaf := &tree.leaves[leaf_index]
	if first < 0 || end < first || end > leaf.count { return false }
	new_count := leaf.count-(end-first)+len(inserted)
	if new_count > TREE_LEAF_CAPACITY { return false }
	for item in inserted { if tree_item_record_ptr(tree, item) == nil { return false } }
	path: Tree_Path
	if !tree_collect_path(tree, leaf_index, &path) { return false }
	staged: [TREE_LEAF_CAPACITY]Tree_Item_Ref
	copy(staged[:], inserted)
	old_count := leaf.count
	delta := len(inserted)-(end-first)
	if delta > 0 {
		for i := old_count-1; i >= end; i -= 1 { leaf.records[i+delta] = leaf.records[i] }
	} else if delta < 0 {
		for i in end..<old_count { leaf.records[i+delta] = leaf.records[i] }
		for i in new_count..<old_count { leaf.records[i] = Tree_Item_Ref{} }
	}
	for i in 0..<len(inserted) { leaf.records[first+i] = staged[i] }
	leaf.count = new_count
	leaf.items = new_count
	leaf.summary = {}
	for item in leaf.records[:leaf.count] { leaf.summary = summary_combine(leaf.summary, tree_item_record_ptr(tree, item).summary) }
	tree_recompute_path(tree, path)
	tree.revision += 1
	return true
}

verify_tree_matches_flat :: proc(flat: ^Flat_Projection, tree: ^History_Tree) -> bool {
	if flat == nil || tree == nil || tree_total_summary(tree) != flat.prefix[len(flat.prefix)-1] { return false }
	for row := i64(0); row < tree_total_summary(tree).display_rows; row += 997 {
		flat_index, flat_offset, flat_ok := flat_seek_display(flat, row)
		leaf_index, record_index, tree_offset, tree_ok := tree_seek_display(tree, row)
		if !flat_ok || !tree_ok || flat_offset != tree_offset { fmt.println("flat/tree display seek mismatch", row); return false }
		global_index := 0
		for i in 0..<leaf_index { global_index += tree.leaves[i].count }
		if global_index+record_index != flat_index || tree_item_record_ptr(tree, tree.leaves[leaf_index].records[record_index])^ != flat.records[flat_index] { fmt.println("flat/tree record mismatch", row); return false }
	}
	whole := tree_total_summary(tree)
	for ordinal := i64(0); ordinal < whole.hunk_headers; ordinal += 7 {
		a, a_ok := flat_hunk_display(flat, ordinal)
		b, b_ok := tree_hunk_display(tree, ordinal)
		if !a_ok || !b_ok || a != b { fmt.println("flat/tree hunk mismatch", ordinal); return false }
	}
	old_sides := [2]bool{false, true}
	for old_side in old_sides {
		total := whole.new_rows
		if old_side { total = whole.old_rows }
		step := max(total/257, 1)
		for line := i64(0); line < total; line += step {
			if flat_source_lookup(flat, old_side, line) != tree_source_lookup(tree, old_side, line) { fmt.println("flat/tree source mismatch", line); return false }
		}
	}
	return true
}

benchmark_tree_projection :: proc(record_count: int, alternating: bool) -> bool {
	assert(verify_tree_multiple_folds())
	source := make_fixture(record_count, alternating)
	defer delete(source)
	flat: Flat_Projection
	if !flat_init(&flat, source, extra_capacity=8) { return false }
	defer flat_destroy(&flat)
	tree: History_Tree
	fold_records := make([]Projection_Record, TRANSACTIONS)
	defer delete(fold_records)
	if !tree_init(&tree, source, fold_records) { return false }
	defer tree_destroy(&tree)
	if !verify_tree_matches_flat(&flat, &tree) { return false }
	initial_first, initial_end, found := find_collapse_span(flat.records[:], record_count/2)
	if !found { return false }
	read_samples := make([]i64, TRANSACTIONS)
	defer delete(read_samples)
	read_checksum: u64 = 0
	display_total_before := tree_total_summary(&tree).display_rows
	for transaction in 0..<TRANSACTIONS {
		first_row := i64((transaction*97)%max(int(display_total_before-VIEWPORT_ROWS), 1))
		start := time.now()
		read_checksum += tree_window_checksum(&tree, first_row, VIEWPORT_ROWS)
		read_samples[transaction] = time.duration_nanoseconds(time.since(start))
	}
	fmt.println("history_measured_tree_readonly", "visible_rows", VIEWPORT_ROWS, "checksum", read_checksum)
	report_samples("readonly_tree_run", read_samples)
	initial_summary := tree_total_summary(&tree)
	initial_revision := tree.revision
	invalid_insert: [TREE_LEAF_CAPACITY+1]Tree_Item_Ref
	if tree_splice_leaf(&tree, 0, -1, 0, invalid_insert[:]) || tree_total_summary(&tree) != initial_summary || tree.revision != initial_revision {
		fmt.println("tree rejected-splice atomicity fixture failed")
		return false
	}
	if tree_splice_leaf(&tree, 0, 0, 0, invalid_insert[:]) || tree_total_summary(&tree) != initial_summary || tree.revision != initial_revision {
		fmt.println("tree over-capacity splice atomicity fixture failed")
		return false
	}

	samples := make([]i64, TRANSACTIONS)
	defer delete(samples)
	checksum: u64 = 0
	for transaction in 0..<TRANSACTIONS {
		preferred := initial_first
		if transaction%3 == 1 { preferred = len(source)/2 }
		if transaction%3 == 2 { preferred = max(len(source)-initial_end, 0) }
		first, end, span_found := find_collapse_span(flat.records[:], preferred)
		if !span_found { return false }
		leaf_index, local_first, locate_ok := tree_locate_record(&tree, first)
		if !locate_ok || end-first > tree.leaves[leaf_index].count-local_first { fmt.println("tree local splice trace mismatch", first); return false }
		span := make([]Tree_Item_Ref, end-first)
		for i in 0..<len(span) { span[i] = Tree_Item_Ref{u32(first+i)} }
		collapsed := make_collapsed_record(flat.records[:], first, end)
		fold_records[transaction] = collapsed
		removed_summary := Projection_Summary{}
		for record in flat.records[first:end] { removed_summary = summary_combine(removed_summary, record.summary) }
		placeholder := [1]Tree_Item_Ref{Tree_Item_Ref{TREE_FOLD_REFERENCE_BIT | u32(transaction)}}
		start := time.now()
		if !tree_splice_leaf(&tree, leaf_index, local_first, local_first+(end-first), placeholder[:]) { return false }
		display_total := tree_total_summary(&tree).display_rows
		viewport_start := i64((transaction*97)%max(int(display_total-VIEWPORT_ROWS), 1))
		checksum += tree_window_checksum(&tree, viewport_start, VIEWPORT_ROWS)
		collapse_ns := time.duration_nanoseconds(time.since(start))
		collapsed_total := initial_summary
		collapsed_total.old_rows += collapsed.summary.old_rows-removed_summary.old_rows
		collapsed_total.new_rows += collapsed.summary.new_rows-removed_summary.new_rows
		collapsed_total.display_rows += 1-removed_summary.display_rows
		if tree_total_summary(&tree) != collapsed_total { fmt.println("tree collapsed summary mismatch", transaction); return false }
		if _, _, valid := tree_validate_summary(&tree, tree.root); !valid { fmt.println("tree internal summary invariant failed", transaction); return false }
		if collapsed.summary.old_rows > 0 && tree_source_lookup(&tree, true, collapsed.old_first).kind != .Collapsed { fmt.println("tree old-side collapsed source mapping failed", transaction); return false }
		if collapsed.summary.new_rows > 0 && tree_source_lookup(&tree, false, collapsed.new_first).kind != .Collapsed { fmt.println("tree new-side collapsed source mapping failed", transaction); return false }
		hunk_row, hunk_ok := tree_hunk_display(&tree, i64(collapsed.hunk_index))
		flat_hunk_row, flat_hunk_ok := flat_hunk_display(&flat, i64(collapsed.hunk_index))
		if !hunk_ok || !flat_hunk_ok || hunk_row != flat_hunk_row { fmt.println("tree hunk navigation changed after collapse", transaction, hunk_row, flat_hunk_row); return false }
		restore_start := time.now()
		if !tree_splice_leaf(&tree, leaf_index, local_first, local_first+1, span) { return false }
		display_total = tree_total_summary(&tree).display_rows
		viewport_start = i64((transaction*97)%max(int(display_total-VIEWPORT_ROWS), 1))
		checksum += tree_window_checksum(&tree, viewport_start, VIEWPORT_ROWS)
		samples[transaction] = collapse_ns+time.duration_nanoseconds(time.since(restore_start))
		if tree_total_summary(&tree) != initial_summary { fmt.println("tree splice round-trip summary mismatch", transaction); return false }
		delete(span)
	}
	fmt.println("history_measured_tree_projection", "records", record_count, "alternating", alternating, "transactions", TRANSACTIONS, "viewport_rows", VIEWPORT_ROWS, "checksum", checksum)
	report_samples("collapse_expand_plus_viewport", samples)
	fmt.println("tree_storage_payload_bytes", "leaf_nodes", cap(tree.leaves)*size_of(Tree_Leaf), "branch_nodes", cap(tree.branches)*size_of(Tree_Branch), "total", cap(tree.leaves)*size_of(Tree_Leaf)+cap(tree.branches)*size_of(Tree_Branch), "leaf_capacity", TREE_LEAF_CAPACITY, "branch_capacity", TREE_BRANCH_CAPACITY)
	return true
}

verify_tree_multiple_folds :: proc() -> bool {
	source := make_fixture(200, false)
	defer delete(source)
	folds := [2]Projection_Record{make_collapsed_record(source, 2, 6), make_collapsed_record(source, 42, 46)}
	tree: History_Tree
	if !tree_init(&tree, source, folds[:]) { return false }
	defer tree_destroy(&tree)
	flat: Flat_Projection
	if !flat_init(&flat, source) { return false }
	defer flat_destroy(&flat)
	for fi in 0..<2 {
		original_first := 2 if fi == 0 else 42
		leaf, local, ok := tree_locate_record(&tree, original_first-3*fi)
		if !ok { return false }
		placeholder := [1]Tree_Item_Ref{Tree_Item_Ref{TREE_FOLD_REFERENCE_BIT | u32(fi)}}
		if !tree_splice_leaf(&tree, leaf, local, local+4, placeholder[:]) { return false }
		if !flat_splice(&flat, original_first-3*fi, original_first-3*fi+4, folds[fi:fi+1]) { return false }
		if !verify_tree_matches_flat(&flat, &tree) { return false }
	}
	if tree_source_lookup(&tree, true, folds[0].old_first).kind != .Collapsed ||
	   tree_source_lookup(&tree, true, folds[1].old_first).kind != .Collapsed { return false }
	_, _, valid := tree_validate_summary(&tree, tree.root)
	return valid
}
