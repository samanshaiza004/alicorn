package main

import "core:fmt"
import "core:time"

// A simpler block-prefix alternative to a tree. Records stay in fixed-size
// blocks, so a local collapse shifts only one block; the compact block prefix
// array is rebuilt after a projection edit.

BLOCK_CAPACITY :: 32

Projection_Block :: struct {
	records: [BLOCK_CAPACITY]Projection_Record,
	count:   int,
	summary: Projection_Summary,
}

Blocked_Projection :: struct {
	blocks:   [dynamic]Projection_Block,
	prefix:   [dynamic]Projection_Summary,
	revision: u64,
}

blocked_init :: proc(projection: ^Blocked_Projection, source: []Projection_Record, allocator := context.allocator) -> bool {
	if projection == nil { return false }
	block_count := (len(source)+BLOCK_CAPACITY-1)/BLOCK_CAPACITY
	projection^ = Blocked_Projection{
		blocks=make([dynamic]Projection_Block, 0, block_count, allocator=allocator),
		prefix=make([dynamic]Projection_Summary, 0, block_count+1, allocator=allocator),
	}
	for record in source {
		if len(projection.blocks) == 0 || projection.blocks[len(projection.blocks)-1].count == BLOCK_CAPACITY {
			append(&projection.blocks, Projection_Block{})
		}
		block := &projection.blocks[len(projection.blocks)-1]
		block.records[block.count] = record
		block.count += 1
		block.summary = summary_combine(block.summary, record.summary)
	}
	append(&projection.prefix, Projection_Summary{})
	blocked_rebuild_prefix(projection)
	return true
}

blocked_destroy :: proc(projection: ^Blocked_Projection) {
	if projection == nil { return }
	delete(projection.blocks)
	delete(projection.prefix)
	projection^ = {}
}

blocked_rebuild_prefix :: proc(projection: ^Blocked_Projection) {
	for len(projection.prefix) < len(projection.blocks)+1 { append(&projection.prefix, Projection_Summary{}) }
	for len(projection.prefix) > len(projection.blocks)+1 { _ = pop(&projection.prefix) }
	projection.prefix[0] = {}
	for i in 0..<len(projection.blocks) {
		projection.prefix[i+1] = summary_combine(projection.prefix[i], projection.blocks[i].summary)
	}
}

blocked_splice :: proc(projection: ^Blocked_Projection, block_index, first, end: int, inserted: []Projection_Record) -> bool {
	if projection == nil || block_index < 0 || block_index >= len(projection.blocks) { return false }
	block := &projection.blocks[block_index]
	if first < 0 || end < first || end > block.count { return false }
	new_count := block.count-(end-first)+len(inserted)
	if new_count > BLOCK_CAPACITY { return false }
	old_count := block.count
	delta := len(inserted)-(end-first)
	if delta > 0 {
		for i in 0..<delta { block.records[block.count+i] = Projection_Record{} }
		for i := old_count-1; i >= end; i -= 1 { block.records[i+delta] = block.records[i] }
	} else if delta < 0 {
		for i in end..<old_count { block.records[i+delta] = block.records[i] }
		for i in new_count..<old_count { block.records[i] = Projection_Record{} }
	}
	for i in 0..<len(inserted) { block.records[first+i] = inserted[i] }
	block.count = new_count
	block.summary = {}
	for record in block.records[:block.count] { block.summary = summary_combine(block.summary, record.summary) }
	blocked_rebuild_prefix(projection)
	projection.revision += 1
	return true
}

blocked_seek_display :: proc(projection: ^Blocked_Projection, display_row: i64) -> (block_index, record_index, row_offset: int, ok: bool) {
	if projection == nil || display_row < 0 || display_row >= projection.prefix[len(projection.prefix)-1].display_rows { return 0, 0, 0, false }
	low, high := 0, len(projection.blocks)
	for low < high {
		mid := (low+high)/2
		if projection.prefix[mid+1].display_rows <= display_row { low = mid+1 } else { high = mid }
	}
	if low >= len(projection.blocks) { return 0, 0, 0, false }
	remaining := display_row-projection.prefix[low].display_rows
	block := &projection.blocks[low]
	for i in 0..<block.count {
		if remaining < block.records[i].summary.display_rows { return low, i, int(remaining), true }
		remaining -= block.records[i].summary.display_rows
	}
	return 0, 0, 0, false
}

blocked_hunk_display :: proc(projection: ^Blocked_Projection, hunk_ordinal: i64) -> (display_row: i64, ok: bool) {
	if projection == nil || hunk_ordinal < 0 || hunk_ordinal >= projection.prefix[len(projection.prefix)-1].hunk_headers { return 0, false }
	low, high := 0, len(projection.blocks)
	for low < high {
		mid := (low+high)/2
		if projection.prefix[mid+1].hunk_headers <= hunk_ordinal { low = mid+1 } else { high = mid }
	}
	if low >= len(projection.blocks) { return 0, false }
	remaining := hunk_ordinal-projection.prefix[low].hunk_headers
	block := &projection.blocks[low]
	display_prefix := projection.prefix[low].display_rows
	for i in 0..<block.count {
		if block.records[i].summary.hunk_headers > remaining { return display_prefix, true }
		remaining -= block.records[i].summary.hunk_headers
		display_prefix += block.records[i].summary.display_rows
	}
	return 0, false
}

blocked_source_lookup :: proc(projection: ^Blocked_Projection, old_side: bool, line: i64) -> Source_Lookup {
	if projection == nil || line < 0 { return {} }
	display_prefix := projection.prefix[0].display_rows
	for block_index in 0..<len(projection.blocks) {
		block := &projection.blocks[block_index]
		for record_index in 0..<block.count {
			record := block.records[record_index]
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

blocked_window_checksum :: proc(projection: ^Blocked_Projection, first_display: i64, visible_rows: int) -> u64 {
	if projection == nil || visible_rows <= 0 { return 0 }
	block_index, record_index, row_offset, ok := blocked_seek_display(projection, first_display)
	if !ok { return 0 }
	checksum: u64 = 0
	remaining := visible_rows
	for remaining > 0 && block_index < len(projection.blocks) {
		block := &projection.blocks[block_index]
		for record_index < block.count && remaining > 0 {
			record := block.records[record_index]
			available := int(record.summary.display_rows)-row_offset
			if available > 0 {
				take := min(available, remaining)
				for row in 0..<take { checksum = checksum*33+u64(record.first_patch_line+row_offset+row+record.hunk_index) }
				remaining -= take
			}
			record_index += 1
			row_offset = 0
		}
		block_index += 1
		record_index = 0
	}
	return checksum
}

verify_blocked_matches_flat :: proc(flat: ^Flat_Projection, blocked: ^Blocked_Projection) -> bool {
	if flat == nil || blocked == nil || len(flat.records) == 0 { return false }
	flat_summary := flat.prefix[len(flat.prefix)-1]
	blocked_summary := blocked.prefix[len(blocked.prefix)-1]
	if flat_summary != blocked_summary { fmt.println("flat/block summary mismatch"); return false }
	for display_row := i64(0); display_row < flat_summary.display_rows; display_row += 997 {
		flat_record_index, flat_offset, flat_ok := flat_seek_display(flat, display_row)
		block_index, record_index, block_offset, block_ok := blocked_seek_display(blocked, display_row)
		if !flat_ok || !block_ok || flat_offset != block_offset { fmt.println("flat/block display seek mismatch", display_row); return false }
		global_record_index := record_index
		for i in 0..<block_index { global_record_index += blocked.blocks[i].count }
		if global_record_index != flat_record_index || blocked.blocks[block_index].records[record_index] != flat.records[flat_record_index] {
			fmt.println("flat/block record mapping mismatch", display_row)
			return false
		}
	}
	for ordinal := i64(0); ordinal < flat_summary.hunk_headers; ordinal += 7 {
		flat_row, flat_ok := flat_hunk_display(flat, ordinal)
		block_row, block_ok := blocked_hunk_display(blocked, ordinal)
		if !flat_ok || !block_ok || flat_row != block_row { fmt.println("flat/block hunk seek mismatch", ordinal); return false }
	}
	old_sides := [2]bool{false, true}
	for old_side in old_sides {
		total := flat_summary.new_rows
		if old_side { total = flat_summary.old_rows }
		step := max(total/257, 1)
		for line := i64(0); line < total; line += step {
			a := flat_source_lookup(flat, old_side, line)
			b := blocked_source_lookup(blocked, old_side, line)
			if a != b { fmt.println("flat/block source lookup mismatch", old_side, line); return false }
		}
	}
	return true
}

blocked_record_at :: proc(projection: ^Blocked_Projection, index: int) -> (record: Projection_Record, block_index, local_index: int, ok: bool) {
	if projection == nil || index < 0 { return {}, 0, 0, false }
	base := 0
	for block_index in 0..<len(projection.blocks) {
		block := &projection.blocks[block_index]
		if index < base+block.count { return block.records[index-base], block_index, index-base, true }
		base += block.count
	}
	return {}, 0, 0, false
}

blocked_span_valid_at :: proc(projection: ^Blocked_Projection, first, span_len: int) -> bool {
	first_record, first_block, _, ok := blocked_record_at(projection, first)
	if !ok { return false }
	for offset in 0..<span_len {
		record, block_index, _, found := blocked_record_at(projection, first+offset)
		if !found || block_index != first_block || record.kind == .Header || record.kind == .Source_Gap || record.kind == .Collapsed || record.summary.display_rows <= 0 || record.hunk_index != first_record.hunk_index {
			return false
		}
	}
	return true
}

blocked_find_span :: proc(projection: ^Blocked_Projection, preferred_record: int) -> (block_index, first, end: int, global_first: int, ok: bool) {
	if projection == nil || len(projection.blocks) == 0 { return 0, 0, 0, 0, false }
	total_records := 0
	for block in projection.blocks { total_records += block.count }
	span_len := 4
	start := clamp(preferred_record, 0, max(total_records-span_len, 0))
	for candidate in start..<max(total_records-span_len, 0) {
		if !blocked_span_valid_at(projection, candidate, span_len) { continue }
		_, block_index, local_first, _ := blocked_record_at(projection, candidate)
		return block_index, local_first, local_first+span_len, candidate, true
	}
	for candidate in 0..<start {
		if !blocked_span_valid_at(projection, candidate, span_len) { continue }
		_, block_index, local_first, _ := blocked_record_at(projection, candidate)
		return block_index, local_first, local_first+span_len, candidate, true
	}
	return 0, 0, 0, 0, false
}

benchmark_blocked_projection :: proc(record_count: int, alternating: bool) -> bool {
	source := make_fixture(record_count, alternating)
	defer delete(source)
	projection: Blocked_Projection
	if !blocked_init(&projection, source) { return false }
	defer blocked_destroy(&projection)
	flat: Flat_Projection
	if !flat_init(&flat, source, extra_capacity=8) { return false }
	defer flat_destroy(&flat)
	if !verify_blocked_matches_flat(&flat, &projection) { return false }
	first_block, first, end, initial_global_first, ok := blocked_find_span(&projection, record_count/2)
	if !ok { return false }
	initial_global_end := initial_global_first+(end-first)
	flat_first, flat_end, flat_ok := find_collapse_span(flat.records[:], record_count/2)
	if !flat_ok || flat_first != initial_global_first || flat_end != initial_global_end { fmt.println("flat/block collapse trace mismatch"); return false }
	block := &projection.blocks[first_block]
	saved := make([]Projection_Record, end-first)
	copy(saved, block.records[first:end])
	defer delete(saved)
	original := projection.prefix[len(projection.prefix)-1]
	collapsed := make_collapsed_record(block.records[:block.count], first, end)
	placeholder := [1]Projection_Record{collapsed}
	if !blocked_splice(&projection, first_block, first, end, placeholder[:]) { return false }
	if collapsed.summary.old_rows > 0 && blocked_source_lookup(&projection, true, collapsed.old_first).kind != .Collapsed { return false }
	if collapsed.summary.new_rows > 0 && blocked_source_lookup(&projection, false, collapsed.new_first).kind != .Collapsed { return false }
	if !blocked_splice(&projection, first_block, first, first+1, saved) { return false }
	if projection.prefix[len(projection.prefix)-1] != original { fmt.println("blocked projection failed round trip"); return false }
	if hunk_row, hunk_ok := blocked_hunk_display(&projection, 0); !hunk_ok || hunk_row != source_header_display(source, 0) { return false }
	read_samples := make([]i64, TRANSACTIONS)
	defer delete(read_samples)
	read_checksum: u64 = 0
	display_total_before := projection.prefix[len(projection.prefix)-1].display_rows
	for transaction in 0..<TRANSACTIONS {
		first_row := i64((transaction*97)%max(int(display_total_before-VIEWPORT_ROWS), 1))
		start := time.now()
		read_checksum += blocked_window_checksum(&projection, first_row, VIEWPORT_ROWS)
		read_samples[transaction] = time.duration_nanoseconds(time.since(start))
	}
	fmt.println("history_blocked_readonly", "visible_rows", VIEWPORT_ROWS, "checksum", read_checksum)
	report_samples("readonly_blocked_run", read_samples)

	samples := make([]i64, TRANSACTIONS)
	defer delete(samples)
	checksum: u64 = 0
	for transaction in 0..<TRANSACTIONS {
		preferred := initial_global_first
		if transaction%3 == 1 { preferred = len(source)/2 }
		if transaction%3 == 2 { preferred = max(len(source)-initial_global_end, 0) }
		block_index, local_first, local_end, global_first, found := blocked_find_span(&projection, preferred)
		if !found { return false }
		flat_first, flat_end, flat_found := find_collapse_span(flat.records[:], preferred)
		if !flat_found || global_first != flat_first || local_end-local_first != flat_end-flat_first { fmt.println("flat/block collapse trace diverged", transaction); return false }
		block = &projection.blocks[block_index]
		transaction_span := make([]Projection_Record, local_end-local_first)
		copy(transaction_span, block.records[local_first:local_end])
		transaction_collapsed := make_collapsed_record(block.records[:block.count], local_first, local_end)
		transaction_placeholder := [1]Projection_Record{transaction_collapsed}
		start := time.now()
		if !blocked_splice(&projection, block_index, local_first, local_end, transaction_placeholder[:]) { return false }
		display_total := projection.prefix[len(projection.prefix)-1].display_rows
		viewport_start := i64((transaction*97)%max(int(display_total-VIEWPORT_ROWS), 1))
		checksum += blocked_window_checksum(&projection, viewport_start, VIEWPORT_ROWS)
		if !blocked_splice(&projection, block_index, local_first, local_first+1, transaction_span) { return false }
		display_total = projection.prefix[len(projection.prefix)-1].display_rows
		viewport_start = i64((transaction*97)%max(int(display_total-VIEWPORT_ROWS), 1))
		checksum += blocked_window_checksum(&projection, viewport_start, VIEWPORT_ROWS)
		samples[transaction] = time.duration_nanoseconds(time.since(start))
		delete(transaction_span)
	}
	fmt.println("history_blocked_run_projection", "records", len(source), "alternating", alternating, "transactions", TRANSACTIONS, "viewport_rows", VIEWPORT_ROWS, "checksum", checksum)
	report_samples("collapse_expand_plus_viewport", samples)
	fmt.println("projection_storage_payload_bytes", "blocks", cap(projection.blocks)*size_of(Projection_Block), "block_prefix", len(projection.prefix)*size_of(Projection_Summary), "total", cap(projection.blocks)*size_of(Projection_Block)+len(projection.prefix)*size_of(Projection_Summary))
	return true
}
