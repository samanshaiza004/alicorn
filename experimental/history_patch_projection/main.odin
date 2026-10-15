package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:sort"
import "core:strings"
import "core:time"

Fixture :: struct { name, data: string }
FIXTURES :: [?]Fixture{
	{"toolbar", #load("fixtures/history-toolbar.patch", string)},
	{"scroll", #load("fixtures/history-scroll.patch", string)},
	{"parser-addition", #load("fixtures/history-parser.patch", string)},
	{"edge-cases", #load("fixtures/edge-cases.patch", string)},
	{"empty", ""},
	{"binary", "Binary files a/image.png and b/image.png differ\n"},
	{"zero-delete", "@@ -1,2 +0,0 @@\n-a\n-b\n"},
}

check :: proc(ok: bool, message: string) {
	if !ok { fmt.eprintln("FAIL", message); os.exit(1) }
}
validate_index :: proc(index: ^Projection_Index, active: []bool) {
	store := index.store
	oracle := oracle_rows(store, active)
	defer delete(oracle)
	check(index_measure(index).display_rows == i64(len(oracle)), "total displayed rows")
	viewport := make([]Visible_Row, 100)
	defer delete(viewport)
	for first := 0; first < len(oracle); first += 37 {
		count := index_viewport(index, i64(first), viewport)
		check(count == min(len(viewport), len(oracle)-first), "viewport count")
		for row, i in viewport[:count] {
			check(row == oracle[first+i], "actual text/kind/gutters/semantic row mismatch")
			check(raw_data(row.line.text) == raw_data(oracle[first+i].line.text), "text must borrow upstream storage")
		}
	}
	check(!index_seek(index, .Display, -1).ok && !index_seek(index, .Display, i64(len(oracle))).ok, "display boundaries")
	// Recompute every leaf independently and compare all directory nodes.
	whole := Measure{}
	for &b, bi in index.blocks {
		measure := Measure{}
		for span in b.spans[:b.count] { measure = combine(measure, span_measure(store, span)) }
		check(measure == b.measure, "leaf cached summary")
		whole = combine(whole, measure)
		if index.backend == .Block_Prefix { check(whole == index.prefix[bi+1], "block prefix summary") }
		if index.backend == .Block_Hierarchy { check(measure == index.binary[index.base+bi], "binary leaf summary") }
	}
	check(whole == index_measure(index), "full directory summary")
	if index.backend == .Block_Hierarchy {
		for i in 1..<index.base { check(index.binary[i] == combine(index.binary[2*i], index.binary[2*i+1]), "binary parent summary") }
	}
	if index.backend == .Measured_Tree {
		for &branch in index.branches {
			measure := Measure{}
			for child in branch.children[:branch.count] { measure = combine(measure, node_measure(index, child)) }
			check(measure == branch.measure, "fanout-16 parent summary")
		}
	}
	old_sides := [2]bool{false, true}
	for old_side in old_sides {
		total := index_measure(index).new_rows
		if old_side { total = index_measure(index).old_rows }
		for coordinate := i64(0); coordinate <= total+2; coordinate += 1 {
			a := oracle_source(store, oracle[:], old_side, coordinate)
			b := index_source(index, old_side, coordinate)
			if a != b { fmt.eprintln("source mismatch", old_side, coordinate, a, b, index.backend) }
			check(a == b, "accelerated old/new source lookup")
		}
	}
	for _, hi in store.patch.hunks {
		seek := index_seek(index, .Hunk, i64(hi))
		check(seek.ok, "hunk ordinal")
		expected := -1
		for row, ri in oracle { if row.line.hunk && row.line.hunk_index == hi { expected = ri; break } }
		check(seek.before.display_rows == i64(expected), "hunk navigation after folds")
		for line, li in store.patch.hunks[hi].lines {
			anchor := Anchor{store.epoch, hi, li, min(len(line.text), 2), 0.35}
			result := index_anchor(index, anchor)
			check(result.ok, "logical line anchor")
			if !result.folded { check(oracle[result.row].patch_line == li && oracle[result.row].line.hunk_index == hi, "selection/scroll anchor realized at wrong line") }
			if result.folded {
				check(oracle[result.row].fold_id != 0, "hidden anchor resolves to fold placeholder")
			}
		}
	}
	check(!index_anchor(index, Anchor{epoch=store.epoch+1}).ok, "different patch epoch must not bind")
}
run_fixture :: proc(fixture: Fixture, benchmark: bool) {
	patch, error_text := git_parse_patch(transmute([]byte)fixture.data)
	check(len(error_text) == 0, "upstream parser")
	defer file_patch_destroy(&patch)
	store := Patch_Store{patch=&patch, epoch=42}
	seed, seed_ok := make_spans(&store)
	check(seed_ok, "parsed patch geometry must be valid")
	defer delete(seed)
	store.folds = make_fold_plans(&store, seed[:], 128)
	defer destroy_fold_plans(store.folds)
	active := make([]bool, len(store.folds))
	defer delete(active)
	fmt.println("fixture", fixture.name, "display_rows", len(patch.display_lines), "compact_spans", len(seed), "folds", len(store.folds), "span_bytes", size_of(Span_Ref))
	for backend in Backend {
		index: Projection_Index
		check(index_init(&index, &store, seed[:], backend), "index build")
		validate_index(&index, active)
		original_measure := index_measure(&index)
		// Overlapping/repeated folds are rejected. Two or more independent
		// folds coexist, then expand in a different order from creation.
		for fi in 0..<min(len(store.folds), 4) {
			check(index_fold(&index, fi, true), "collapse independent span")
			active[fi] = true
			validate_index(&index, active)
			before := index_measure(&index)
			revision := index.revision
			check(!index_fold(&index, fi, true) && index_measure(&index) == before && index.revision == revision, "double collapse is unchanged")
		}
		for fi := min(len(store.folds), 4)-1; fi >= 0; fi -= 1 {
			check(index_fold(&index, fi, false), "unfold independent span")
			active[fi] = false
			validate_index(&index, active)
		}
		check(index_measure(&index) == original_measure, "all source extents round trip")
		// All available plans coexist, across leaves. Expand odd plans first
		// and even plans second, checking that retained placeholders survive.
		for fi in 0..<len(store.folds) { check(index_fold(&index, fi, true), "all simultaneous folds"); active[fi] = true }
		validate_index(&index, active)
		for parity in 0..<2 {
			for fi in 0..<len(store.folds) {
				if fi%2 == parity { check(index_fold(&index, fi, false), "non-LIFO unfold"); active[fi] = false; validate_index(&index, active) }
			}
		}
		before := index.blocks[0]
		revision := index.revision
		bad := [1]Span_Ref{Span_Ref{kind=.Fold, source=0xffff_ffff, count=1}}
		check(!index_splice_block(&index, 0, 0, 0, bad[:]) && index.blocks[0] == before && revision == index.revision, "invalid reference splice atomicity")
		check(!index_splice_block(&index, 0, -1, 0, nil) && index.blocks[0] == before && revision == index.revision, "invalid range splice atomicity")
		if len(seed) > 0 {
			too_many: [LEAF_CAPACITY+1]Span_Ref
			for &span in too_many { span = seed[0] }
			check(!index_splice_block(&index, 0, 0, 0, too_many[:]) && index.blocks[0] == before && revision == index.revision, "growing splice refused before mutation")
		}
		if before.count >= 3 {
			check(index_splice_block(&index, 0, 1, 3, index.blocks[0].spans[0:2]), "aliasing replacement")
			check(index.blocks[0].spans[1] == before.spans[0] && index.blocks[0].spans[2] == before.spans[1], "aliased input must be snapshotted")
			check(index_splice_block(&index, 0, 0, index.blocks[0].count, before.spans[:before.count]), "restore aliased test")
			validate_index(&index, active)
		}
		index_destroy(&index)
	}
	fmt.println("source_payload", fixture.name, "parsed_bytes", parsed_payload(&patch), "existing_display_index_bytes", cap(patch.display_lines)*size_of(Patch_Display_Line), "fold_catalog_bytes", fold_payload(store.folds), "seed_capacity_bytes", cap(seed)*size_of(Span_Ref))
	// The alternatives need parsed hunks, not History's expanded index. Drop
	// it after the oracle proof instead of counting it as shared tree storage.
	delete(patch.display_lines)
	patch.display_lines = nil
	if benchmark && len(store.folds) > 0 { benchmark_fixture(&store, seed[:], fixture.name) }
}
parsed_payload :: proc(patch: ^File_Patch) -> int {
	bytes := cap(patch.hunks)*size_of(Diff_Hunk)+cap(patch.metadata)*size_of(string)+len(patch.path)
	for text in patch.metadata { bytes += len(text) }
	for h in patch.hunks {
		bytes += len(h.header)+cap(h.lines)*size_of(Diff_Line)
		for line in h.lines { bytes += len(line.text) }
	}
	return bytes
}
fold_payload :: proc(plans: []Fold_Plan) -> int {
	bytes := len(plans)*size_of(Fold_Plan)
	for plan in plans { bytes += len(plan.original)*size_of(Span_Ref) }
	return bytes
}
row_checksum :: proc(rows: []Visible_Row) -> u64 {
	checksum: u64 = 0
	for row in rows {
		checksum = checksum*33+u64(row.line.old_line+row.line.new_line+int(row.line.kind))+row.fold_id
		for byte in transmute([]byte)row.line.text { checksum = checksum*33+u64(byte) }
	}
	return checksum
}
print_samples :: proc(label: string, samples: []i64) {
	sort.quick_sort(samples)
	fmt.println(label, "p50_ns", samples[len(samples)/2], "p95_ns", samples[(len(samples)*95)/100], "max_ns", samples[len(samples)-1])
}
benchmark_fixture :: proc(store: ^Patch_Store, seed: []Span_Ref, label: string) {
	backing := context.allocator
	for backend in Backend {
		tracker: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracker, backing, internals_allocator=backing)
		defer mem.tracking_allocator_destroy(&tracker)
		context.allocator = mem.tracking_allocator(&tracker)
		index: Projection_Index
		build_start := time.now()
		check(index_init(&index, store, seed, backend), "tracked build")
		build_ns := time.duration_nanoseconds(time.since(build_start))
		live := tracker.current_memory_allocated
		peak := tracker.peak_memory_allocated
		allocations := tracker.total_allocation_count
		// Measure mutation/query peak independently of temporary build arrays.
		tracker.peak_memory_allocated = tracker.current_memory_allocated
		viewport: [100]Visible_Row
		readonly: [180]i64
		transactions: [180]i64
		checksum: u64 = 0
		// Keep the first independent region collapsed while folding another.
		if len(store.folds) > 1 { check(index_fold(&index, 0, true), "persistent first fold") }
		for i in 0..<len(transactions) {
			fi := i%len(store.folds)
			if len(store.folds) > 1 { fi = 1+i%(len(store.folds)-1) }
			rows := index_measure(&index).display_rows
			first := i64(i)*104729%max(rows, 1)
			start := time.now()
			count := index_viewport(&index, first, viewport[:])
			readonly[i] = time.duration_nanoseconds(time.since(start))
			checksum += row_checksum(viewport[:count])
			start = time.now()
			check(index_fold(&index, fi, true), "timed fold")
			rows = index_measure(&index).display_rows
			count = index_viewport(&index, i64(i)*104729%max(rows, 1), viewport[:])
			source := index_source(&index, i%2 == 0, 1+i64(i)*7919%max(index_measure(&index).old_rows if i%2 == 0 else index_measure(&index).new_rows, 1))
			fold_ns := time.duration_nanoseconds(time.since(start))
			checksum += row_checksum(viewport[:count])
			checksum += u64(source.kind)+u64(source.display_row)
			start = time.now()
			check(index_fold(&index, fi, false), "timed unfold")
			rows = index_measure(&index).display_rows
			count = index_viewport(&index, i64(i)*104729%max(rows, 1), viewport[:])
			source = index_source(&index, i%2 != 0, 1+i64(i)*7919%max(index_measure(&index).old_rows if i%2 != 0 else index_measure(&index).new_rows, 1))
			transactions[i] = fold_ns+time.duration_nanoseconds(time.since(start))
			checksum += row_checksum(viewport[:count])
			checksum += u64(source.kind)+u64(source.display_row)
		}
		if len(store.folds) > 1 { check(index_fold(&index, 0, false), "restore persistent fold") }
		check(tracker.total_allocation_count == allocations, "queries and local folds must allocate nothing")
		fmt.println("real_patch", label, "backend", backend, "build_ns", build_ns, "index_live_bytes", live, "index_peak_build_bytes", peak, "index_peak_fold_bytes", tracker.peak_memory_allocated, "checksum", checksum)
		print_samples("readonly_viewport", readonly[:])
		print_samples("fold_unfold_two_viewports", transactions[:])
		index_destroy(&index)
		check(tracker.current_memory_allocated == 0, "index leaked memory")
	}
}

// A scale test derived from a real patch, explicitly not a captured large
// History workload. Serialize the real hunk bodies with shifted origins, then
// use the same unchanged parser. No native applications or GPU work is run.
amplified_fixture :: proc(repetitions: int) -> string {
	patch, err := git_parse_patch(transmute([]byte)FIXTURES[1].data)
	check(len(err) == 0, "amplified source parse")
	defer file_patch_destroy(&patch)
	builder: strings.Builder
	defer strings.builder_destroy(&builder)
	old_base, new_base := 0, 0
	old_stride, new_stride := 0, 0
	for h in patch.hunks { old_stride = max(old_stride, h.old_start+h.old_count+20); new_stride = max(new_stride, h.new_start+h.new_count+20) }
	for _ in 0..<repetitions {
		for h in patch.hunks {
			fmt.sbprintf(&builder, "@@ -%d,%d +%d,%d @@\n", old_base+h.old_start, h.old_count, new_base+h.new_start, h.new_count)
			for line in h.lines {
				switch line.kind {
				case .Context: strings.write_string(&builder, " ")
				case .Addition: strings.write_string(&builder, "+")
				case .Deletion: strings.write_string(&builder, "-")
				case .Meta:
				}
				strings.write_string(&builder, line.text); strings.write_string(&builder, "\n")
			}
		}
		old_base += old_stride; new_base += new_stride
	}
	copy, _ := strings.clone(strings.to_string(builder))
	return copy
}
run_amplified :: proc(repetitions: int) {
	data := amplified_fixture(repetitions)
	defer delete(data)
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&tracker)
	context.allocator = mem.tracking_allocator(&tracker)
	patch, err := git_parse_patch(transmute([]byte)data)
	check(len(err) == 0, "amplified parse")
	defer file_patch_destroy(&patch)
	store := Patch_Store{patch=&patch, epoch=99}
	seed, ok := make_spans(&store)
	check(ok, "amplified geometry")
	store.folds = make_fold_plans(&store, seed[:], 128)
	defer destroy_fold_plans(store.folds)
	fmt.println("amplified_history_scroll", "repetitions", repetitions, "display_rows", len(patch.display_lines), "spans", len(seed), "folds", len(store.folds), "existing_display_bytes", cap(patch.display_lines)*size_of(Patch_Display_Line), "common_peak_prepare_bytes", tracker.peak_memory_allocated)
	delete(patch.display_lines); patch.display_lines = nil
	fmt.println("amplified_common_live_bytes", tracker.current_memory_allocated, "seed_capacity_bytes", cap(seed)*size_of(Span_Ref))
	// Validate selected real rows at the first, middle and last hunk. Full
	// exhaustive mapping/selection proofs run on the unamplified fixtures.
	index: Projection_Index
	check(index_init(&index, &store, seed[:], .Measured_Tree), "amplified index")
	selected_hunks := [3]int{0, len(patch.hunks)/2, len(patch.hunks)-1}
	for hi in selected_hunks {
		for line, li in patch.hunks[hi].lines {
			anchor := Anchor{epoch=99, hunk=hi, line=li}
			result := index_anchor(&index, anchor)
			check(result.ok && !result.folded, "amplified anchor")
			output: [1]Visible_Row
			check(index_viewport(&index, result.row, output[:]) == 1 && output[0].line.text == line.text, "amplified actual text")
		}
	}
	index_destroy(&index)
	benchmark_fixture(&store, seed[:], "amplified-scroll")
	delete(seed)
}
main :: proc() {
	benchmark := len(os.args) > 1 && os.args[1] == "--bench"
	for fixture in FIXTURES { run_fixture(fixture, benchmark) }
	if benchmark { run_amplified(256) }
	fmt.println("PASS real History patch projection: all backends, actual rows, old/new axes, multi-folds and logical anchors")
}
