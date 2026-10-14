package main

import "core:fmt"
import "core:time"
import alicorn "../../runtime"

// This is the pre-tree baseline gate for #50. It compares Alicorn's current
// f32 sparse index with two f64 alternatives using the same row positions and
// measured heights. It has no native window or text-shaping dependency.

BLOCK_CAPACITY :: 32
TRANSACTIONS :: 180
UPDATES_PER_TRANSACTION :: 32
ESTIMATED_HEIGHT :: f64(84)

Entry :: struct {
	index:        int,
	height:       f64,
	prefix_delta: f64,
}

Sparse_Index :: struct {
	item_count:       int,
	estimated_height: f64,
	total_height:     f64,
	entries:          [dynamic]Entry,
	prefix_dirty:     bool,
}

Height_Block :: struct {
	entries:          [BLOCK_CAPACITY]Entry,
	count:            int,
	delta_sum:        f64,
	prefix_delta:     f64,
	index_bias:       int,
}

Chunked_Index :: struct {
	item_count:       int,
	estimated_height: f64,
	total_height:     f64,
	blocks:           [dynamic]Height_Block,
	block_prefix_dirty: bool,
}

Measurement :: struct {
	index:  int,
	height: f64,
}

height_for :: proc(ordinal: int) -> f64 {
	switch ordinal%4 {
	case 0: return 62.4
	case 1: return 66
	case 2: return 104
	case: return 187.2
	}
}

make_measurements :: proc(item_count, measured_count: int, clustered: bool, allocator := context.allocator) -> []Measurement {
	measurements := make([]Measurement, measured_count, allocator=allocator)
	for i in 0..<measured_count {
		item_index := 0
		if !clustered {
			item_index = ((i+1)*item_count)/(measured_count+1)
		} else {
			// Two local groups make the same override count exercise short and
			// long estimated gaps without relying on random-number state.
			half := max(measured_count/2, 1)
			if i < half {
				item_index = (i+1)*max(item_count/10, 1)/(half+1)
			} else {
				local := i-half
				count := measured_count-half
				item_index = item_count-item_count/10 + (local+1)*max(item_count/10, 1)/(count+1)
			}
		}
		measurements[i] = Measurement{item_index, height_for(i)}
	}
	return measurements
}

make_integer_measurements :: proc(item_count, measured_count: int, allocator := context.allocator) -> []Measurement {
	measurements := make_measurements(item_count, measured_count, false, allocator)
	for i in 0..<len(measurements) {
		measurements[i].height = f64(60+(i%3)*16)
	}
	return measurements
}

make_oracle_tops :: proc(item_count: int, measurements: []Measurement, allocator := context.allocator) -> []f64 {
	tops := make([]f64, item_count+1, allocator=allocator)
	measurement_index := 0
	for item_index in 0..<item_count {
		height := ESTIMATED_HEIGHT
		if measurement_index < len(measurements) && measurements[measurement_index].index == item_index {
			height = measurements[measurement_index].height
			measurement_index += 1
		}
		tops[item_index+1] = tops[item_index]+height
	}
	return tops
}

oracle_item_at :: proc(tops: []f64, content_y: f64) -> int {
	item_count := len(tops)-1
	if item_count <= 0 { return -1 }
	target := max(content_y, 0)
	target = min(target, max(tops[item_count]-0.000001, 0))
	low, high := 0, item_count
	for low < high {
		mid := (low+high)/2
		if tops[mid+1] <= target { low = mid+1 } else { high = mid }
	}
	return min(low, item_count-1)
}

build_current :: proc(item_count: int, measurements: []Measurement, allocator := context.allocator) -> (index: alicorn.Virtual_List_Height_Index, ok: bool) {
	ok = alicorn.virtual_list_height_index_init(&index, item_count, f32(ESTIMATED_HEIGHT), allocator)
	if !ok { return }
	for measurement in measurements {
		if !alicorn.virtual_list_height_index_set_height(&index, measurement.index, f32(measurement.height)) {
			alicorn.virtual_list_height_index_destroy(&index)
			return {}, false
		}
	}
	return
}

build_sparse :: proc(item_count: int, measurements: []Measurement, allocator := context.allocator) -> Sparse_Index {
	index := Sparse_Index{
		item_count=item_count,
		estimated_height=ESTIMATED_HEIGHT,
		total_height=f64(item_count)*ESTIMATED_HEIGHT,
		entries=make([dynamic]Entry, 0, len(measurements), allocator=allocator),
	}
	for measurement in measurements {
		append(&index.entries, Entry{measurement.index, measurement.height, 0})
		index.total_height += measurement.height-ESTIMATED_HEIGHT
	}
	index.prefix_dirty = true
	sparse_rebuild_prefix(&index)
	return index
}

build_chunked :: proc(item_count: int, measurements: []Measurement, allocator := context.allocator) -> Chunked_Index {
	block_count := (len(measurements)+BLOCK_CAPACITY-1)/BLOCK_CAPACITY
	index := Chunked_Index{
		item_count=item_count,
		estimated_height=ESTIMATED_HEIGHT,
		total_height=f64(item_count)*ESTIMATED_HEIGHT,
		blocks=make([dynamic]Height_Block, 0, block_count, allocator=allocator),
	}
	for measurement in measurements {
		if len(index.blocks) == 0 || index.blocks[len(index.blocks)-1].count == BLOCK_CAPACITY {
			append(&index.blocks, Height_Block{})
		}
		block := &index.blocks[len(index.blocks)-1]
		delta := measurement.height-ESTIMATED_HEIGHT
		block.entries[block.count] = Entry{measurement.index, measurement.height, block.delta_sum+delta}
		block.count += 1
		block.delta_sum += delta
		index.total_height += delta
	}
	index.block_prefix_dirty = true
	chunked_rebuild_prefix(&index)
	return index
}

sparse_rebuild_prefix :: proc(index: ^Sparse_Index) {
	if index == nil || !index.prefix_dirty { return }
	delta: f64 = 0
	for i in 0..<len(index.entries) {
		delta += index.entries[i].height-index.estimated_height
		index.entries[i].prefix_delta = delta
	}
	index.total_height = max(f64(index.item_count)*index.estimated_height+delta, 0)
	index.prefix_dirty = false
}

chunked_rebuild_prefix :: proc(index: ^Chunked_Index) {
	if index == nil || !index.block_prefix_dirty { return }
	delta: f64 = 0
	for i in 0..<len(index.blocks) {
		index.blocks[i].prefix_delta = delta
		delta += index.blocks[i].delta_sum
	}
	index.total_height = max(f64(index.item_count)*index.estimated_height+delta, 0)
	index.block_prefix_dirty = false
}

// Direct sparse seek: binary-search measured row bottoms once, then calculate
// the item arithmetically inside the estimated gap containing y.
sparse_item_at :: proc(index: ^Sparse_Index, content_y: f64) -> int {
	if index == nil || index.item_count <= 0 { return -1 }
	sparse_rebuild_prefix(index)
	target := max(content_y, 0)
	target = min(target, max(index.total_height-0.000001, 0))
	low, high := 0, len(index.entries)
	for low < high {
		mid := (low+high)/2
		bottom := f64(index.entries[mid].index+1)*index.estimated_height + index.entries[mid].prefix_delta
		if bottom <= target { low = mid+1 } else { high = mid }
	}
	previous_delta: f64 = 0
	if low > 0 { previous_delta = index.entries[low-1].prefix_delta }
	if low >= len(index.entries) {
		return min(max(int((target-previous_delta)/index.estimated_height), 0), index.item_count-1)
	}
	item := max(int((target-previous_delta)/index.estimated_height), 0)
	if item >= index.entries[low].index { return index.entries[low].index }
	return min(item, index.item_count-1)
}

chunked_block_for_y :: proc(index: ^Chunked_Index, target: f64) -> int {
	low, high := 0, len(index.blocks)
	for low < high {
		mid := (low+high)/2
		block := &index.blocks[mid]
		last := block.entries[block.count-1]
		bottom := f64(last.index+block.index_bias+1)*index.estimated_height + block.prefix_delta + last.prefix_delta
		if bottom <= target { low = mid+1 } else { high = mid }
	}
	return low
}

chunked_item_at :: proc(index: ^Chunked_Index, content_y: f64) -> int {
	if index == nil || index.item_count <= 0 { return -1 }
	chunked_rebuild_prefix(index)
	target := max(content_y, 0)
	target = min(target, max(index.total_height-0.000001, 0))
	block_index := chunked_block_for_y(index, target)
	if block_index >= len(index.blocks) {
		previous_delta: f64 = 0
		if len(index.blocks) > 0 {
			last_block := &index.blocks[len(index.blocks)-1]
			previous_delta = last_block.prefix_delta+last_block.delta_sum
		}
		return min(max(int((target-previous_delta)/index.estimated_height), 0), index.item_count-1)
	}
	block := &index.blocks[block_index]
	low, high := 0, block.count
	for low < high {
		mid := (low+high)/2
		entry := block.entries[mid]
		bottom := f64(entry.index+block.index_bias+1)*index.estimated_height + block.prefix_delta + entry.prefix_delta
		if bottom <= target { low = mid+1 } else { high = mid }
	}
	previous_delta := block.prefix_delta
	if low > 0 { previous_delta += block.entries[low-1].prefix_delta }
	if low >= block.count {
		return min(max(int((target-previous_delta)/index.estimated_height), 0), index.item_count-1)
	}
	item := max(int((target-previous_delta)/index.estimated_height), 0)
	if item >= block.entries[low].index+block.index_bias { return block.entries[low].index+block.index_bias }
	return min(item, index.item_count-1)
}

// Same f32 entries and prefix cache as Alicorn's current index, but searches
// the measured-row bottoms directly instead of binary-searching logical rows
// and repeatedly calling item_top.
current_direct_item_at :: proc(index: ^alicorn.Virtual_List_Height_Index, content_y: f32) -> int {
	if index == nil || index.item_count <= 0 { return -1 }
	alicorn.virtual_list_height_index_rebuild_prefix(index)
	target := max(content_y, f32(0))
	target = min(target, max(index.total_height-0.001, f32(0)))
	low, high := 0, len(index.entries)
	for low < high {
		mid := (low+high)/2
		entry := index.entries[mid]
		bottom := f32(entry.index+1)*index.estimated_height + entry.prefix_delta
		if bottom <= target { low = mid+1 } else { high = mid }
	}
	previous_delta: f32 = 0
	if low > 0 { previous_delta = index.entries[low-1].prefix_delta }
	gap_last := index.item_count-1
	if low < len(index.entries) {
		measured := index.entries[low]
		measured_top := f32(measured.index)*index.estimated_height+previous_delta
		if measured_top <= target { return measured.index }
		gap_last = measured.index-1
	}
	item := clamp(int((target-previous_delta)/index.estimated_height), 0, gap_last)
	// Correct a one-row division-rounding difference using the same f32 top
	// equation as the original logical-row binary search.
	if item < gap_last && f32(item+1)*index.estimated_height+previous_delta <= target { item += 1 }
	if item > 0 && f32(item)*index.estimated_height+previous_delta > target { item -= 1 }
	return item
}

sparse_set_height :: proc(index: ^Sparse_Index, item_index: int, height: f64) -> bool {
	low, high := 0, len(index.entries)
	for low < high {
		mid := (low+high)/2
		if index.entries[mid].index < item_index { low = mid+1 } else { high = mid }
	}
	if low >= len(index.entries) || index.entries[low].index != item_index { return false }
	previous := index.entries[low].height
	if previous == height { return false }
	index.entries[low].height = height
	index.total_height += height-previous
	index.prefix_dirty = true
	return true
}

chunked_set_height :: proc(index: ^Chunked_Index, item_index: int, height: f64) -> bool {
	if len(index.blocks) == 0 { return false }
	low, high := 0, len(index.blocks)
	for low < high {
		mid := (low+high)/2
		block := &index.blocks[mid]
		if block.entries[block.count-1].index+block.index_bias < item_index { low = mid+1 } else { high = mid }
	}
	if low >= len(index.blocks) { return false }
	block := &index.blocks[low]
	entry_low, entry_high := 0, block.count
	for entry_low < entry_high {
		mid := (entry_low+entry_high)/2
		if block.entries[mid].index+block.index_bias < item_index { entry_low = mid+1 } else { entry_high = mid }
	}
	if entry_low >= block.count || block.entries[entry_low].index+block.index_bias != item_index { return false }
	if block.entries[entry_low].height == height { return false }
	previous := block.entries[entry_low].height
	block.entries[entry_low].height = height
	block.delta_sum = 0
	for entry_index in 0..<block.count {
		block.delta_sum += block.entries[entry_index].height-index.estimated_height
		block.entries[entry_index].prefix_delta = block.delta_sum
	}
	index.total_height += height-previous
	index.block_prefix_dirty = true
	return true
}

sparse_apply_insert :: proc(index: ^Sparse_Index, first_item, inserted_count: int) -> bool {
	if index == nil || first_item < 0 || first_item > index.item_count || inserted_count < 0 { return false }
	if inserted_count == 0 { return true }
	for i in 0..<len(index.entries) {
		if index.entries[i].index >= first_item { index.entries[i].index += inserted_count }
	}
	index.item_count += inserted_count
	index.total_height += f64(inserted_count)*index.estimated_height
	index.prefix_dirty = true
	return true
}

// A front edit changes the logical origin of each occupied block. Keeping a
// small per-block bias avoids rewriting every measurement in later blocks.
chunked_apply_insert :: proc(index: ^Chunked_Index, first_item, inserted_count: int) -> bool {
	if index == nil || first_item < 0 || first_item > index.item_count || inserted_count < 0 { return false }
	if inserted_count == 0 { return true }
	if len(index.blocks) > 0 {
		block_index := 0
		for block_index < len(index.blocks) && index.blocks[block_index].entries[index.blocks[block_index].count-1].index+index.blocks[block_index].index_bias < first_item {
			block_index += 1
		}
		if block_index < len(index.blocks) {
			block := &index.blocks[block_index]
			first_stored := block.entries[0].index+block.index_bias
			if first_item <= first_stored {
				for i in block_index..<len(index.blocks) { index.blocks[i].index_bias += inserted_count }
			} else {
				for i in 0..<block.count {
					if block.entries[i].index+block.index_bias >= first_item { block.entries[i].index += inserted_count }
				}
				for i in block_index+1..<len(index.blocks) { index.blocks[i].index_bias += inserted_count }
			}
		}
	}
	index.item_count += inserted_count
	index.total_height += f64(inserted_count)*index.estimated_height
	return true
}

// The benchmark intentionally samples elapsed time at the interaction level:
// a batch of measured-height updates followed by leading and trailing seeks.
// Sorting occurs after the timed loop, so percentile work is excluded.
sort_i64 :: proc(values: []i64) {
	for i in 1..<len(values) {
		value := values[i]
		j := i
		for j > 0 && values[j-1] > value {
			values[j] = values[j-1]
			j -= 1
		}
		values[j] = value
	}
}

report_samples :: proc(label: string, samples: []i64) {
	ordered := make([]i64, len(samples))
	copy(ordered, samples)
	sort_i64(ordered)
	fmt.println(label,
		"transactions", len(samples),
		"p50_ns", ordered[len(ordered)/2],
		"p95_ns", ordered[(len(ordered)*95)/100],
		"max_ns", ordered[len(ordered)-1],
	)
	delete(ordered)
}

benchmark_front_insert :: proc(item_count: int, measurements: []Measurement, clustered: bool) -> bool {
	current, ok := build_current(item_count, measurements)
	if !ok { return false }
	defer alicorn.virtual_list_height_index_destroy(&current)
	direct, direct_ok := build_current(item_count, measurements)
	if !direct_ok { return false }
	defer alicorn.virtual_list_height_index_destroy(&direct)
	sparse := build_sparse(item_count, measurements)
	defer delete(sparse.entries)
	chunked := build_chunked(item_count, measurements)
	defer delete(chunked.blocks)
	current_samples := make([]i64, TRANSACTIONS)
	direct_samples := make([]i64, TRANSACTIONS)
	sparse_samples := make([]i64, TRANSACTIONS)
	chunked_samples := make([]i64, TRANSACTIONS)
	defer delete(current_samples)
	defer delete(direct_samples)
	defer delete(sparse_samples)
	defer delete(chunked_samples)
	current_checksum, direct_checksum, sparse_checksum, chunked_checksum: i64 = 0, 0, 0, 0
	for transaction in 0..<TRANSACTIONS {
		start := time.now()
		if !alicorn.virtual_list_height_index_apply_edit(&current, 0, 0, 1, current.item_count+1) { return false }
		y := f32((transaction*113)%max(int(current.total_height), 1))
		current_checksum += i64(alicorn.virtual_list_height_index_item_at(&current, y))
		current_checksum += i64(alicorn.virtual_list_height_index_item_at(&current, min(y+860, current.total_height)))
		current_samples[transaction] = time.duration_nanoseconds(time.since(start))

		start = time.now()
		if !alicorn.virtual_list_height_index_apply_edit(&direct, 0, 0, 1, direct.item_count+1) { return false }
		y = f32((transaction*113)%max(int(direct.total_height), 1))
		direct_checksum += i64(current_direct_item_at(&direct, y))
		direct_checksum += i64(current_direct_item_at(&direct, min(y+860, direct.total_height)))
		direct_samples[transaction] = time.duration_nanoseconds(time.since(start))

		start = time.now()
		if !sparse_apply_insert(&sparse, 0, 1) { return false }
		y64 := f64((transaction*113)%max(int(sparse.total_height), 1))
		sparse_checksum += i64(sparse_item_at(&sparse, y64))
		sparse_checksum += i64(sparse_item_at(&sparse, min(y64+f64(860), sparse.total_height)))
		sparse_samples[transaction] = time.duration_nanoseconds(time.since(start))

		start = time.now()
		if !chunked_apply_insert(&chunked, 0, 1) { return false }
		y64 = f64((transaction*113)%max(int(chunked.total_height), 1))
		chunked_checksum += i64(chunked_item_at(&chunked, y64))
		chunked_checksum += i64(chunked_item_at(&chunked, min(y64+f64(860), chunked.total_height)))
		chunked_samples[transaction] = time.duration_nanoseconds(time.since(start))
	}
	shifted := make([]Measurement, len(measurements))
	defer delete(shifted)
	for i in 0..<len(measurements) { shifted[i] = Measurement{measurements[i].index+TRANSACTIONS, measurements[i].height} }
	tops := make_oracle_tops(item_count+TRANSACTIONS, shifted)
	defer delete(tops)
	for sample in 0..<2048 {
		y := (f64(sample)+0.371)*tops[len(tops)-1]/2048
		want := oracle_item_at(tops, y)
		if sparse_item_at(&sparse, y) != want || chunked_item_at(&chunked, y) != want {
			fmt.println("front-insert oracle mismatch", "pattern", "clustered" if clustered else "scattered", "y", y, "expected", want)
			return false
		}
	}
	fmt.println("front_insert_one_row_per_transaction", "logical_rows", item_count, "measured", len(measurements), "pattern", "clustered" if clustered else "scattered")
	report_samples("front_insert_plus_two_viewport_seeks current_f32", current_samples)
	report_samples("front_insert_plus_two_viewport_seeks direct_sparse_f32", direct_samples)
	report_samples("front_insert_plus_two_viewport_seeks direct_sparse_f64", sparse_samples)
	report_samples("front_insert_plus_two_viewport_seeks chunked_f64", chunked_samples)
	fmt.println("front_insert_checksums", current_checksum, direct_checksum, sparse_checksum, chunked_checksum)
	return true
}

verify_queries :: proc(current: ^alicorn.Virtual_List_Height_Index, sparse: ^Sparse_Index, chunked: ^Chunked_Index) -> bool {
	// The two f64 candidates are checked against a fully expanded height oracle.
	// The current f32 structure remains a compatibility comparison; its expected
	// near-boundary differences are counted rather than hidden.
	measurements := make([]Measurement, len(sparse.entries))
	for i in 0..<len(sparse.entries) {
		measurements[i] = Measurement{sparse.entries[i].index, sparse.entries[i].height}
	}
	tops := make_oracle_tops(sparse.item_count, measurements)
	defer delete(measurements)
	defer delete(tops)
	current_mismatches := 0
	current_direct_mismatches := 0
	current_direct_boundary_mismatches := 0
	for sample in 0..<4096 {
		y := (f64(sample)+0.371)*tops[len(tops)-1]/4096
		want := alicorn.virtual_list_height_index_item_at(current, f32(y))
		got_current_direct := current_direct_item_at(current, f32(y))
		oracle := oracle_item_at(tops, y)
		got_sparse := sparse_item_at(sparse, y)
		got_chunked := chunked_item_at(chunked, y)
		if got_sparse != oracle || got_chunked != oracle {
			fmt.println("oracle mismatch", "y", y, "oracle", oracle, "sparse", got_sparse, "chunked", got_chunked)
			return false
		}
		if want != got_sparse { current_mismatches += 1 }
		if want != got_current_direct { current_direct_mismatches += 1 }
	}
	for measurement in measurements {
		boundary := tops[measurement.index+1]
		near_boundaries := [2]f64{boundary-0.001, boundary+0.001}
		for y in near_boundaries {
			if y < 0 || y >= tops[len(tops)-1] { continue }
			want := oracle_item_at(tops, y)
			if sparse_item_at(sparse, y) != want || chunked_item_at(chunked, y) != want {
				fmt.println("near-boundary oracle mismatch", "row", measurement.index, "y", y, "expected", want)
				return false
			}
			if alicorn.virtual_list_height_index_item_at(current, f32(y)) != current_direct_item_at(current, f32(y)) {
				current_direct_boundary_mismatches += 1
			}
		}
	}
	fmt.println("current_f32_vs_candidate_boundary_differences", current_mismatches, "of", 4096, "samples")
	fmt.println("current_f32_direct_vs_nested_differences", current_direct_mismatches, "of", 4096, "samples")
	fmt.println("current_f32_direct_vs_nested_near_boundary_differences", current_direct_boundary_mismatches)
	return true
}

verify_integer_boundaries :: proc() -> bool {
	item_count := 4096
	measurements := make_integer_measurements(item_count, 257)
	defer delete(measurements)
	current, ok := build_current(item_count, measurements)
	if !ok { return false }
	defer alicorn.virtual_list_height_index_destroy(&current)
	sparse := build_sparse(item_count, measurements)
	defer delete(sparse.entries)
	chunked := build_chunked(item_count, measurements)
	defer delete(chunked.blocks)
	tops := make_oracle_tops(item_count, measurements)
	defer delete(tops)
	for row in 0..<item_count {
		y := tops[row]
		want := oracle_item_at(tops, y)
		if alicorn.virtual_list_height_index_item_at(&current, f32(y)) != want || current_direct_item_at(&current, f32(y)) != want || sparse_item_at(&sparse, y) != want || chunked_item_at(&chunked, y) != want {
			fmt.println("integer boundary fixture failed", "row", row, "y", y, "expected", want)
			return false
		}
		if row+1 < item_count {
			boundary := tops[row+1]
			if oracle_item_at(tops, boundary) != row+1 ||
			   alicorn.virtual_list_height_index_item_at(&current, f32(boundary)) != row+1 ||
			   current_direct_item_at(&current, f32(boundary)) != row+1 ||
			   sparse_item_at(&sparse, boundary) != row+1 ||
			   chunked_item_at(&chunked, boundary) != row+1 {
				fmt.println("integer exact-boundary fixture failed", "row", row, "boundary", boundary)
				return false
			}
		}
	}
	fmt.println("integer_exact_boundary_fixture", "rows", item_count, "measured", len(measurements), "result", "passed")
	return true
}

benchmark_case :: proc(item_count, measured_count: int, clustered: bool) -> bool {
	measurements := make_measurements(item_count, measured_count, clustered)
	defer delete(measurements)
	current, ok := build_current(item_count, measurements)
	if !ok { fmt.println("current index setup failed"); return false }
	defer alicorn.virtual_list_height_index_destroy(&current)
	current_direct, direct_ok := build_current(item_count, measurements)
	if !direct_ok { fmt.println("direct current index setup failed"); return false }
	defer alicorn.virtual_list_height_index_destroy(&current_direct)
	sparse := build_sparse(item_count, measurements)
	defer delete(sparse.entries)
	chunked := build_chunked(item_count, measurements)
	defer delete(chunked.blocks)
	if !verify_queries(&current, &sparse, &chunked) { return false }

	query_count := 50_000
	current_sum, sparse_sum, chunked_sum: i64 = 0, 0, 0
	start := time.now()
	for i in 0..<query_count {
		y := f32((i*7919)%max(int(current.total_height), 1))
		current_sum += i64(alicorn.virtual_list_height_index_item_at(&current, y))
	}
	current_ns := time.duration_nanoseconds(time.since(start))
	direct_f32_sum: i64 = 0
	start = time.now()
	for i in 0..<query_count {
		y := f32((i*7919)%max(int(current.total_height), 1))
		direct_f32_sum += i64(current_direct_item_at(&current, y))
	}
	direct_f32_ns := time.duration_nanoseconds(time.since(start))
	start = time.now()
	for i in 0..<query_count {
		y := f64((i*7919)%max(int(sparse.total_height), 1))
		sparse_sum += i64(sparse_item_at(&sparse, y))
	}
	sparse_ns := time.duration_nanoseconds(time.since(start))
	start = time.now()
	for i in 0..<query_count {
		y := f64((i*7919)%max(int(chunked.total_height), 1))
		chunked_sum += i64(chunked_item_at(&chunked, y))
	}
	chunked_ns := time.duration_nanoseconds(time.since(start))

	fmt.println("case", "logical_rows", item_count, "measured", measured_count, "pattern", "clustered" if clustered else "scattered")
	fmt.println("seek_batch", "queries", query_count,
		"current_f32_ns_per_query", current_ns/i64(query_count),
		"direct_sparse_f32_ns_per_query", direct_f32_ns/i64(query_count),
		"direct_sparse_f64_ns_per_query", sparse_ns/i64(query_count),
		"chunked_f64_ns_per_query", chunked_ns/i64(query_count),
		"checksums", current_sum, direct_f32_sum, sparse_sum, chunked_sum,
	)
	fmt.println("index_storage_estimate_bytes",
		"current_sparse_entries", len(current.entries)*size_of(alicorn.Virtual_List_Height_Entry),
		"direct_sparse_entries", len(sparse.entries)*size_of(Entry),
		"chunked_blocks", len(chunked.blocks),
		"chunked_storage", cap(chunked.blocks)*size_of(Height_Block),
		"chunked_used_slots", measured_count,
	)

	current_samples := make([]i64, TRANSACTIONS)
	direct_f32_samples := make([]i64, TRANSACTIONS)
	sparse_samples := make([]i64, TRANSACTIONS)
	chunked_samples := make([]i64, TRANSACTIONS)
	defer delete(current_samples)
	defer delete(direct_f32_samples)
	defer delete(sparse_samples)
	defer delete(chunked_samples)
	current_interaction_checksum, direct_interaction_checksum, sparse_interaction_checksum, chunked_interaction_checksum: i64 = 0, 0, 0, 0
	for transaction in 0..<TRANSACTIONS {
		start = time.now()
		for update in 0..<UPDATES_PER_TRANSACTION {
			measurement_index := (transaction*UPDATES_PER_TRANSACTION+update)%measured_count
			next := height_for(measurement_index)+f64(transaction%2)
			_ = alicorn.virtual_list_height_index_set_height(&current, measurements[measurement_index].index, f32(next))
		}
		leading := f32(transaction*97%max(int(current.total_height), 1))
		current_interaction_checksum += i64(alicorn.virtual_list_height_index_item_at(&current, leading))
		current_interaction_checksum += i64(alicorn.virtual_list_height_index_item_at(&current, min(leading+f32(860), current.total_height)))
		current_samples[transaction] = time.duration_nanoseconds(time.since(start))

		start = time.now()
		for update in 0..<UPDATES_PER_TRANSACTION {
			measurement_index := (transaction*UPDATES_PER_TRANSACTION+update)%measured_count
			next := height_for(measurement_index)+f64(transaction%2)
			_ = alicorn.virtual_list_height_index_set_height(&current_direct, measurements[measurement_index].index, f32(next))
		}
		leading = f32(transaction*97%max(int(current_direct.total_height), 1))
		direct_interaction_checksum += i64(current_direct_item_at(&current_direct, leading))
		direct_interaction_checksum += i64(current_direct_item_at(&current_direct, min(leading+f32(860), current_direct.total_height)))
		direct_f32_samples[transaction] = time.duration_nanoseconds(time.since(start))

		start = time.now()
		for update in 0..<UPDATES_PER_TRANSACTION {
			measurement_index := (transaction*UPDATES_PER_TRANSACTION+update)%measured_count
			next := height_for(measurement_index)+f64(transaction%2)
			_ = sparse_set_height(&sparse, measurements[measurement_index].index, next)
		}
		leading64 := f64((transaction*97)%max(int(sparse.total_height), 1))
		sparse_interaction_checksum += i64(sparse_item_at(&sparse, leading64))
		sparse_interaction_checksum += i64(sparse_item_at(&sparse, min(leading64+f64(860), sparse.total_height)))
		sparse_samples[transaction] = time.duration_nanoseconds(time.since(start))

		start = time.now()
		for update in 0..<UPDATES_PER_TRANSACTION {
			measurement_index := (transaction*UPDATES_PER_TRANSACTION+update)%measured_count
			next := height_for(measurement_index)+f64(transaction%2)
			_ = chunked_set_height(&chunked, measurements[measurement_index].index, next)
		}
		leading64 = f64((transaction*97)%max(int(chunked.total_height), 1))
		chunked_interaction_checksum += i64(chunked_item_at(&chunked, leading64))
		chunked_interaction_checksum += i64(chunked_item_at(&chunked, min(leading64+f64(860), chunked.total_height)))
		chunked_samples[transaction] = time.duration_nanoseconds(time.since(start))
	}
	report_samples("update_batch_plus_two_viewport_seeks current_f32", current_samples)
	report_samples("update_batch_plus_two_viewport_seeks direct_sparse_f32", direct_f32_samples)
	report_samples("update_batch_plus_two_viewport_seeks direct_sparse_f64", sparse_samples)
	report_samples("update_batch_plus_two_viewport_seeks chunked_f64", chunked_samples)
	fmt.println("update_batch_checksums", current_interaction_checksum, direct_interaction_checksum, sparse_interaction_checksum, chunked_interaction_checksum)
	return benchmark_front_insert(item_count, measurements, clustered)
}

main :: proc() {
	fmt.println("Alicorn #50 baseline only; no B+ tree; Odin dev-2026-09-nightly:a2fb372; one process")
	if !verify_integer_boundaries() { return }
	if !benchmark_case(20_000, 317, false) { return }
	if !benchmark_case(20_000, 317, true) { return }
	if !benchmark_case(100_000, 1_000, false) { return }
	if !benchmark_case(100_000, 1_000, true) { return }
}
