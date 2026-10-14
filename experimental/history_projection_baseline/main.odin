package main

import "core:fmt"
import "core:time"

// Headless History projection baseline for Alicorn #50. Records refer to
// immutable patch storage by hunk and line range; they never own patch text.
// This models collapse/expand semantics with the same flat-run operations that
// a future measured-sequence adapter must support.

TRANSACTIONS :: 180
VIEWPORT_ROWS :: 100

Record_Kind :: enum { Header, Context, Addition, Deletion, Source_Gap, Collapsed }
Lookup_Kind :: enum { Missing, Visible, Gap, Collapsed }

Projection_Summary :: struct {
	old_rows:     i64,
	new_rows:     i64,
	display_rows: i64,
	hunk_headers: i64,
}

Projection_Record :: struct {
	kind:             Record_Kind,
	hunk_index:       int,
	first_patch_line: int,
	patch_line_count: int,
	old_first:        i64,
	new_first:        i64,
	summary:          Projection_Summary,
}

Flat_Projection :: struct {
	records:  [dynamic]Projection_Record,
	prefix:   [dynamic]Projection_Summary,
	revision: u64,
}

Source_Lookup :: struct {
	kind:        Lookup_Kind,
	display_row: i64,
	patch_line:  int,
	first:       i64,
	count:       i64,
}

Display_Reference :: struct { record_index, row_offset: int }

make_display_references :: proc(records: []Projection_Record) -> [dynamic]Display_Reference {
	display_rows: i64 = 0
	for record in records { display_rows += record.summary.display_rows }
	references := make([dynamic]Display_Reference, 0, int(display_rows))
	for record, record_index in records {
		for row_offset in 0..<int(record.summary.display_rows) {
			append(&references, Display_Reference{record_index, row_offset})
		}
	}
	return references
}

direct_display_window_checksum :: proc(records: []Projection_Record, references: []Display_Reference, first_row: int, visible_rows: int) -> u64 {
	return direct_window_checksum(records, references, {}, first_row, visible_rows)
}

direct_window_checksum :: proc(records: []Projection_Record, references: []Display_Reference, collapsed: Projection_Record, first_row: int, visible_rows: int) -> u64 {
	if first_row < 0 || visible_rows <= 0 || first_row >= len(references) { return 0 }
	end := min(first_row+visible_rows, len(references))
	checksum: u64 = 0
	for row in first_row..<end {
		reference := references[row]
		record := collapsed
		if reference.record_index >= 0 { record = records[reference.record_index] }
		checksum = checksum*33+u64(record.first_patch_line+reference.row_offset+record.hunk_index)
	}
	return checksum
}

direct_display_splice :: proc(rows: ^[dynamic]Display_Reference, first, end: int, inserted: []Display_Reference) -> bool {
	if rows == nil || first < 0 || end < first || end > len(rows^) { return false }
	old_count := len(rows^)
	new_count := old_count-(end-first)+len(inserted)
	if new_count > cap(rows^) { return false }
	delta := len(inserted)-(end-first)
	if delta > 0 {
		for _ in 0..<delta { append(rows, Display_Reference{}) }
		for i := old_count-1; i >= end; i -= 1 { rows^[i+delta] = rows^[i] }
	} else if delta < 0 {
		for i in end..<old_count { rows^[i+delta] = rows^[i] }
		for _ in 0..<(-delta) { _ = pop(rows) }
	}
	for i in 0..<len(inserted) { rows^[first+i] = inserted[i] }
	return len(rows^) == new_count
}

summary_combine :: proc(left, right: Projection_Summary) -> Projection_Summary {
	return Projection_Summary{
		old_rows=left.old_rows+right.old_rows,
		new_rows=left.new_rows+right.new_rows,
		display_rows=left.display_rows+right.display_rows,
		hunk_headers=left.hunk_headers+right.hunk_headers,
	}
}

make_record :: proc(
	kind: Record_Kind,
	hunk_index, patch_first, patch_count: int,
	old_first, new_first, old_count, new_count, display_count: i64,
	header_count: i64 = 0,
) -> Projection_Record {
	return Projection_Record{
		kind=kind,
		hunk_index=hunk_index,
		first_patch_line=patch_first,
		patch_line_count=patch_count,
		old_first=old_first,
		new_first=new_first,
		summary=Projection_Summary{old_count, new_count, display_count, header_count},
	}
}

flat_init :: proc(projection: ^Flat_Projection, source: []Projection_Record, extra_capacity: int = 8, allocator := context.allocator) -> bool {
	if projection == nil || extra_capacity < 0 { return false }
	capacity := len(source)+extra_capacity
	projection^ = Flat_Projection{
		records=make([dynamic]Projection_Record, 0, capacity, allocator=allocator),
		prefix=make([dynamic]Projection_Summary, 0, capacity+1, allocator=allocator),
	}
	for record in source { append(&projection.records, record) }
	append(&projection.prefix, Projection_Summary{})
	flat_rebuild_prefix(projection)
	return true
}

flat_destroy :: proc(projection: ^Flat_Projection) {
	if projection == nil { return }
	delete(projection.records)
	delete(projection.prefix)
	projection^ = {}
}

flat_rebuild_prefix :: proc(projection: ^Flat_Projection) {
	if projection == nil { return }
	for len(projection.prefix) < len(projection.records)+1 {
		append(&projection.prefix, Projection_Summary{})
	}
	for len(projection.prefix) > len(projection.records)+1 { _ = pop(&projection.prefix) }
	projection.prefix[0] = {}
	for i in 0..<len(projection.records) {
		projection.prefix[i+1] = summary_combine(projection.prefix[i], projection.records[i].summary)
	}
}

flat_splice :: proc(projection: ^Flat_Projection, first, end: int, inserted: []Projection_Record) -> bool {
	if projection == nil || first < 0 || end < first || end > len(projection.records) { return false }
	old_len := len(projection.records)
	removed := end-first
	new_len := old_len-removed+len(inserted)
	if new_len > cap(projection.records) || new_len+1 > cap(projection.prefix) { return false }
	delta := len(inserted)-removed
	if delta > 0 {
		for _ in 0..<delta { append(&projection.records, Projection_Record{}) }
		for i := old_len-1; i >= end; i -= 1 { projection.records[i+delta] = projection.records[i] }
	} else if delta < 0 {
		for i in end..<old_len { projection.records[i+delta] = projection.records[i] }
		for _ in 0..<(-delta) { _ = pop(&projection.records) }
	}
	for i in 0..<len(inserted) { projection.records[first+i] = inserted[i] }
	flat_rebuild_prefix(projection)
	projection.revision += 1
	return true
}

flat_seek_display :: proc(projection: ^Flat_Projection, display_row: i64) -> (record_index, row_offset: int, ok: bool) {
	if projection == nil || display_row < 0 || display_row >= projection.prefix[len(projection.prefix)-1].display_rows { return 0, 0, false }
	low, high := 0, len(projection.records)
	for low < high {
		mid := (low+high)/2
		if projection.prefix[mid+1].display_rows <= display_row { low = mid+1 } else { high = mid }
	}
	if low >= len(projection.records) { return 0, 0, false }
	return low, int(display_row-projection.prefix[low].display_rows), true
}

flat_hunk_display :: proc(projection: ^Flat_Projection, hunk_ordinal: i64) -> (display_row: i64, ok: bool) {
	if projection == nil || hunk_ordinal < 0 || hunk_ordinal >= projection.prefix[len(projection.prefix)-1].hunk_headers { return 0, false }
	low, high := 0, len(projection.records)
	for low < high {
		mid := (low+high)/2
		if projection.prefix[mid+1].hunk_headers <= hunk_ordinal { low = mid+1 } else { high = mid }
	}
	if low >= len(projection.records) { return 0, false }
	return projection.prefix[low].display_rows, true
}

flat_source_lookup :: proc(projection: ^Flat_Projection, old_side: bool, line: i64) -> Source_Lookup {
	if projection == nil || line < 0 { return {} }
	for record, i in projection.records {
		first := record.new_first
		count := record.summary.new_rows
		if old_side { first, count = record.old_first, record.summary.old_rows }
		if count <= 0 || line < first || line >= first+count { continue }
		switch record.kind {
		case .Source_Gap:
			return Source_Lookup{kind=.Gap, first=first, count=count}
		case .Collapsed:
			return Source_Lookup{kind=.Collapsed, display_row=projection.prefix[i].display_rows, first=first, count=count}
		case .Header:
			return Source_Lookup{kind=.Missing}
		case .Context, .Addition, .Deletion:
			within := line-first
			if within >= record.summary.display_rows { return Source_Lookup{kind=.Missing} }
			return Source_Lookup{
				kind=.Visible,
				display_row=projection.prefix[i].display_rows+within,
				patch_line=record.first_patch_line+int(within),
				first=first,
				count=count,
			}
		}
	}
	return {}
}

flat_window_checksum :: proc(projection: ^Flat_Projection, first_display: i64, visible_rows: int) -> u64 {
	if projection == nil || visible_rows <= 0 { return 0 }
	record_index, row_offset, ok := flat_seek_display(projection, first_display)
	if !ok { return 0 }
	checksum: u64 = 0
	remaining := visible_rows
	for remaining > 0 && record_index < len(projection.records) {
		record := projection.records[record_index]
		available := int(record.summary.display_rows)-row_offset
		if available > 0 {
			take := min(available, remaining)
			for row in 0..<take {
				checksum = checksum*33+u64(record.first_patch_line+row_offset+row+record.hunk_index)
			}
			remaining -= take
		}
		record_index += 1
		row_offset = 0
	}
	return checksum
}

make_fixture :: proc(record_count: int, alternating: bool, allocator := context.allocator) -> []Projection_Record {
	records := make([dynamic]Projection_Record, 0, record_count, allocator=allocator)
	old_line, new_line: i64 = 1, 1
	patch_line := 0
	hunk_index := 0
	for i in 0..<record_count {
		if i%40 == 0 {
			append(&records, make_record(.Header, hunk_index, patch_line, 0, old_line, new_line, 0, 0, 1, 1))
			hunk_index += 1
			continue
		}
		active_hunk := max(hunk_index-1, 0)
		if i%40 == 1 {
			append(&records, make_record(.Source_Gap, active_hunk, patch_line, 0, old_line, new_line, 100, 100, 0))
			old_line += 100
			new_line += 100
			continue
		}
		kind := Record_Kind.Context
		count := 8
		if alternating {
			if i%2 == 0 { kind, count = .Addition, 1 } else { kind, count = .Deletion, 1 }
		} else {
			switch i%3 {
			case 0: kind, count = .Context, 8
			case 1: kind, count = .Addition, 3
			case: kind, count = .Deletion, 3
			}
		}
		old_count, new_count: i64 = 0, 0
		if kind == .Context { old_count, new_count = i64(count), i64(count) }
		if kind == .Addition { new_count = i64(count) }
		if kind == .Deletion { old_count = i64(count) }
		display_count := i64(count)
		append(&records, make_record(kind, active_hunk, patch_line, count, old_line, new_line, old_count, new_count, display_count))
		patch_line += count
		old_line += old_count
		new_line += new_count
	}
	return records[:]
}

make_collapsed_record :: proc(records: []Projection_Record, first, end: int) -> Projection_Record {
	combined := Projection_Summary{}
	patch_count := 0
	for i in first..<end {
		combined = summary_combine(combined, records[i].summary)
		patch_count += records[i].patch_line_count
	}
	anchor := records[first]
	return make_record(.Collapsed, anchor.hunk_index, anchor.first_patch_line, patch_count,
		anchor.old_first, anchor.new_first, combined.old_rows, combined.new_rows, 1)
}

find_collapse_span :: proc(records: []Projection_Record, preferred: int) -> (first, end: int, ok: bool) {
	span_len := 4
	start := clamp(preferred, 0, max(len(records)-span_len, 0))
	for candidate in start..<len(records)-span_len {
		valid := true
		for i in candidate..<candidate+span_len {
			if records[i].kind == .Header || records[i].kind == .Source_Gap || records[i].kind == .Collapsed || records[i].summary.display_rows <= 0 || records[i].hunk_index != records[candidate].hunk_index {
				valid = false
				break
			}
		}
		if valid { return candidate, candidate+span_len, true }
	}
	for candidate in 0..<start {
		if candidate+span_len > len(records) { break }
		valid := true
		for i in candidate..<candidate+span_len {
			if records[i].kind == .Header || records[i].kind == .Source_Gap || records[i].kind == .Collapsed || records[i].summary.display_rows <= 0 || records[i].hunk_index != records[candidate].hunk_index {
				valid = false
				break
			}
		}
		if valid { return candidate, candidate+span_len, true }
	}
	return 0, 0, false
}

verify_projection :: proc(projection: ^Flat_Projection, source: []Projection_Record, first, end: int) -> bool {
	original_summary := projection.prefix[len(projection.prefix)-1]
	collapsed := make_collapsed_record(projection.records[:], first, end)
	removed_display_rows: i64 = 0
	for i in first..<end { removed_display_rows += projection.records[i].summary.display_rows }
	placeholder := [1]Projection_Record{collapsed}
	if !flat_splice(projection, first, end, placeholder[:]) { return false }
	collapsed_summary := projection.prefix[len(projection.prefix)-1]
	if collapsed_summary.old_rows != original_summary.old_rows || collapsed_summary.new_rows != original_summary.new_rows ||
	   collapsed_summary.display_rows != original_summary.display_rows-removed_display_rows+1 || collapsed_summary.hunk_headers != original_summary.hunk_headers {
		fmt.println("collapse summary fixture failed")
		return false
	}
	if collapsed.summary.old_rows > 0 {
		result := flat_source_lookup(projection, true, collapsed.old_first)
		if result.kind != .Collapsed { fmt.println("old source lookup did not report collapsed range"); return false }
	}
	if collapsed.summary.new_rows > 0 {
		result := flat_source_lookup(projection, false, collapsed.new_first)
		if result.kind != .Collapsed { fmt.println("new source lookup did not report collapsed range"); return false }
	}
	if collapsed.summary.display_rows > 0 {
		index, offset, found := flat_seek_display(projection, projection.prefix[first].display_rows)
		if !found || projection.records[index].kind != .Collapsed || offset != 0 { fmt.println("display boundary did not select collapse placeholder"); return false }
	}
	restored := make([]Projection_Record, end-first)
	copy(restored, source[first:end])
	defer delete(restored)
	if !flat_splice(projection, first, first+1, restored) { return false }
	if projection.prefix[len(projection.prefix)-1] != original_summary {
		fmt.println("expand did not restore original summary")
		return false
	}
	if projection.records[first].first_patch_line != source[first].first_patch_line { return false }
	if hunk_row, ok := flat_hunk_display(projection, 0); !ok || hunk_row != source_header_display(source, 0) {
		fmt.println("hunk navigation summary failed")
		return false
	}
	return true
}

source_header_display :: proc(records: []Projection_Record, hunk_ordinal: i64) -> i64 {
	row: i64 = 0
	remaining_hunks := hunk_ordinal
	for record in records {
		if record.kind == .Header {
			if remaining_hunks == 0 { return row }
			remaining_hunks -= 1
		}
		row += record.summary.display_rows
	}
	return -1
}

sort_i64 :: proc(values: []i64) {
	for i in 1..<len(values) {
		value := values[i]
		j := i
		for j > 0 && values[j-1] > value { values[j] = values[j-1]; j -= 1 }
		values[j] = value
	}
}

report_samples :: proc(label: string, samples: []i64) {
	ordered := make([]i64, len(samples))
	copy(ordered, samples)
	sort_i64(ordered)
	fmt.println(label, "transactions", len(samples), "p50_ns", ordered[len(ordered)/2], "p95_ns", ordered[len(ordered)*95/100], "max_ns", ordered[len(ordered)-1])
	delete(ordered)
}

benchmark_direct_projection :: proc(record_count: int, alternating: bool) -> bool {
	source := make_fixture(record_count, alternating)
	defer delete(source)
	flat: Flat_Projection
	if !flat_init(&flat, source, extra_capacity=8) { return false }
	defer flat_destroy(&flat)
	rows := make_display_references(source)
	defer delete(rows)
	initial_row_count := len(rows)
	initial_first, initial_end, found := find_collapse_span(flat.records[:], record_count/2)
	if !found { return false }
	profile_direct_windows(source, "history_expanded_display_baseline")
	samples := make([]i64, TRANSACTIONS)
	defer delete(samples)
	checksum: u64 = 0
	for transaction in 0..<TRANSACTIONS {
		preferred := initial_first
		if transaction%3 == 1 { preferred = len(source)/2 }
		if transaction%3 == 2 { preferred = max(len(source)-initial_end, 0) }
		first, end, span_found := find_collapse_span(flat.records[:], preferred)
		if !span_found { return false }
		display_first := int(flat.prefix[first].display_rows)
		display_end := int(flat.prefix[end].display_rows)
		if display_first < 0 || display_end < display_first || display_end > len(rows) { return false }
		saved := make([]Display_Reference, display_end-display_first)
		copy(saved, rows[display_first:display_end])
		collapsed := make_collapsed_record(flat.records[:], first, end)
		placeholder := [1]Display_Reference{{-1, 0}}
		start := time.now()
		if !direct_display_splice(&rows, display_first, display_end, placeholder[:]) { return false }
		viewport_start := (transaction*97)%max(len(rows)-VIEWPORT_ROWS, 1)
		checksum += direct_window_checksum(source, rows[:], collapsed, viewport_start, VIEWPORT_ROWS)
		collapse_ns := time.duration_nanoseconds(time.since(start))
		restore_start := time.now()
		if !direct_display_splice(&rows, display_first, display_first+1, saved) { return false }
		viewport_start = (transaction*97)%max(len(rows)-VIEWPORT_ROWS, 1)
		checksum += direct_display_window_checksum(source, rows[:], viewport_start, VIEWPORT_ROWS)
		samples[transaction] = collapse_ns+time.duration_nanoseconds(time.since(restore_start))
		if len(rows) != initial_row_count { fmt.println("direct display round-trip row count mismatch"); return false }
		delete(saved)
	}
	fmt.println("history_expanded_display_projection", "records", record_count, "alternating", alternating, "transactions", TRANSACTIONS, "viewport_rows", VIEWPORT_ROWS, "checksum", checksum)
	report_samples("collapse_expand_plus_viewport", samples)
	fmt.println("expanded_display_storage_payload_bytes", cap(rows)*size_of(Display_Reference), "visible_rows", initial_row_count)
	return true
}

profile_direct_windows :: proc(source: []Projection_Record, label: string) {
	references := make_display_references(source)
	defer delete(references)
	samples := make([]i64, TRANSACTIONS)
	defer delete(samples)
	checksum: u64 = 0
	for transaction in 0..<TRANSACTIONS {
		first := (transaction*97)%max(len(references)-VIEWPORT_ROWS, 1)
		start := time.now()
		checksum += direct_display_window_checksum(source, references[:], first, VIEWPORT_ROWS)
		samples[transaction] = time.duration_nanoseconds(time.since(start))
	}
	fmt.println(label, "visible_rows", VIEWPORT_ROWS, "checksum", checksum, "display_reference_payload_bytes", len(references)*size_of(Display_Reference))
	report_samples("readonly_direct_display", samples)
}

benchmark_projection :: proc(record_count: int, alternating: bool) -> bool {
	source := make_fixture(record_count, alternating)
	defer delete(source)
	projection: Flat_Projection
	if !flat_init(&projection, source, extra_capacity=8) { return false }
	defer flat_destroy(&projection)
	span_first, span_end, ok := find_collapse_span(source, record_count/2)
	if !ok { fmt.println("no collapsible span in fixture", record_count); return false }
	if !verify_projection(&projection, source, span_first, span_end) { return false }
	// Verify source gaps remain explicit and never masquerade as visible rows.
	for record in projection.records {
		if record.kind == .Source_Gap && record.summary.old_rows > 0 {
			lookup := flat_source_lookup(&projection, true, record.old_first)
			if lookup.kind != .Gap { fmt.println("source gap lookup fixture failed"); return false }
			break
		}
	}
	display_boundaries := [2]i64{0, projection.prefix[len(projection.prefix)-1].display_rows-1}
	for row in display_boundaries {
		if index, _, found := flat_seek_display(&projection, row); !found || index < 0 || index >= len(projection.records) { return false }
	}
	read_samples := make([]i64, TRANSACTIONS)
	defer delete(read_samples)
	read_checksum: u64 = 0
	display_total := projection.prefix[len(projection.prefix)-1].display_rows
	for transaction in 0..<TRANSACTIONS {
		first_row := i64((transaction*97)%max(int(display_total-VIEWPORT_ROWS), 1))
		start := time.now()
		read_checksum += flat_window_checksum(&projection, first_row, VIEWPORT_ROWS)
		read_samples[transaction] = time.duration_nanoseconds(time.since(start))
	}
	fmt.println("history_flat_run_readonly", "visible_rows", VIEWPORT_ROWS, "checksum", read_checksum)
	report_samples("readonly_flat_run", read_samples)

	samples := make([]i64, TRANSACTIONS)
	defer delete(samples)
	checksum: u64 = 0
	for transaction in 0..<TRANSACTIONS {
		preferred := span_first
		if transaction%3 == 1 {
			preferred = len(projection.records)/2
		} else if transaction%3 == 2 {
			preferred = max(len(projection.records)-span_end, 0)
		}
		first, end, found := find_collapse_span(projection.records[:], preferred)
		if !found { return false }
		span := make([]Projection_Record, end-first)
		copy(span, projection.records[first:end])
		collapsed := make_collapsed_record(projection.records[:], first, end)
		placeholder := [1]Projection_Record{collapsed}
		start := time.now()
		if !flat_splice(&projection, first, end, placeholder[:]) { return false }
		display_total := projection.prefix[len(projection.prefix)-1].display_rows
		viewport_start := i64((transaction*97)%max(int(display_total-VIEWPORT_ROWS), 1))
		checksum += flat_window_checksum(&projection, viewport_start, VIEWPORT_ROWS)
		if !flat_splice(&projection, first, first+1, span) { return false }
		display_total = projection.prefix[len(projection.prefix)-1].display_rows
		viewport_start = i64((transaction*97)%max(int(display_total-VIEWPORT_ROWS), 1))
		checksum += flat_window_checksum(&projection, viewport_start, VIEWPORT_ROWS)
		samples[transaction] = time.duration_nanoseconds(time.since(start))
		delete(span)
	}
	fmt.println("history_flat_run_projection", "records", len(source), "alternating", alternating, "transactions", TRANSACTIONS, "viewport_rows", VIEWPORT_ROWS, "checksum", checksum)
	report_samples("collapse_expand_plus_viewport", samples)
	fmt.println("projection_storage_payload_bytes", "records", len(projection.records)*size_of(Projection_Record), "prefix", len(projection.prefix)*size_of(Projection_Summary), "total", len(projection.records)*size_of(Projection_Record)+len(projection.prefix)*size_of(Projection_Summary))
	return true
}

main :: proc() {
	fmt.println("History projection comparison; local-splice prototypes; Odin dev-2026-09-nightly:a2fb372; one process")
	if !benchmark_direct_projection(10_000, false) { return }
	if !benchmark_projection(10_000, false) { return }
	if !benchmark_projection(10_000, true) { return }
	if !benchmark_direct_projection(10_000, true) { return }
	if !benchmark_blocked_projection(10_000, false) { return }
	if !benchmark_blocked_projection(10_000, true) { return }
	if !benchmark_tree_projection(10_000, false) { return }
	if !benchmark_tree_projection(10_000, true) { return }
	if !benchmark_direct_projection(50_000, false) { return }
	if !benchmark_projection(50_000, false) { return }
	if !benchmark_projection(50_000, true) { return }
	if !benchmark_direct_projection(50_000, true) { return }
	if !benchmark_blocked_projection(50_000, false) { return }
	if !benchmark_blocked_projection(50_000, true) { return }
	if !benchmark_tree_projection(50_000, false) { return }
	if !benchmark_tree_projection(50_000, true) { return }
}
